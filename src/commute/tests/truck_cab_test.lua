local PixelCanvas=require('src.tests.support.pixel_canvas')
local Cockpit = require('src.commute.truck_cockpit')
local Test = {}

local function imageHasTransparentAndVisiblePixels(path)
    local image = love.image.newImageData(path)
    local width, height = image:getDimensions()
    local clear, visible = 0, 0
    for y = 0, height - 1, 16 do
        for x = 0, width - 1, 16 do
            local _, _, _, alpha = image:getPixel(x, y)
            if alpha < .05 then clear = clear + 1 end
            if alpha > .9 then visible = visible + 1 end
        end
    end
    image:release()
    return width == Cockpit.WIDTH and height == Cockpit.HEIGHT and clear > 20 and visible > 20,
        ('%dx%d transparent=%d visible=%d'):format(width, height, clear, visible)
end

local function byAction(controls)
    local result = {}
    for _, control in ipairs(controls) do result[control.action] = control end
    return result
end

local function regionDiff(first, second, x0, y0, x1, y1)
    local different = 0
    for y = y0, y1, 2 do
        for x = x0, x1, 2 do
            local r1, g1, b1, a1 = first:getPixel(x, y)
            local r2, g2, b2, a2 = second:getPixel(x, y)
            if math.abs(r1-r2) + math.abs(g1-g2) + math.abs(b1-b2) + math.abs(a1-a2) > .18 then
                different = different + 1
            end
        end
    end
    return different
end

function Test.run(check)
    local overlay = love.image.newImageData(Cockpit.PATH)
    local _, _, _, windshieldAlpha = overlay:getPixel(760, 100)
    local _, _, _, dashboardAlpha = overlay:getPixel(760, 600)
    overlay:release()
    check('truck_cab_windshield_is_open_to_the_world', windshieldAlpha < .02 and dashboardAlpha > .9,
        ('windshield alpha=%.3f dashboard alpha=%.3f'):format(windshieldAlpha, dashboardAlpha))

    for _, layer in ipairs({
        {'steering-wheel', 'steering-wheel.png', 480, 560},
        {'accelerator', 'accelerator-pedal.png', 640, 860},
        {'brake', 'brake-pedal.png', 640, 860},
    }) do
        local path = 'assets/commute/truck/interior-v2/' .. layer[2]
        local hasContent, detail = imageHasTransparentAndVisiblePixels(path)
        local image = love.image.newImageData(path)
        local _, _, _, cornerAlpha = image:getPixel(0, 0)
        local _, _, _, detailAlpha = image:getPixel(layer[3], layer[4])
        image:release()
        check('truck_cab_' .. layer[1] .. '_is_a_separate_transparent_layer',
            hasContent and cornerAlpha < .02 and detailAlpha > .9, detail)
    end

    local cab = Cockpit.new()
    local camera = {
        firstPerson = true,
        viewHeading = 0,
        bikeHeading = 0,
        focal = 640 / math.tan(math.rad(41)),
    }
    local radio = require('src.jukebox')
    local oldRadio = {active=radio.active, paused=radio.paused, muted=radio.muted}
    radio.active, radio.paused, radio.muted = true, false, true
    local controls = byAction(Cockpit.controls(1280, 880, camera, {
        engine=true, headlight=true, headlightHighBeam=true, turnSignal='left',
    }))
    check('truck_cab_projects_all_dashboard_hit_targets',
        controls.ignition and controls.headlight and controls.beam and controls.signalLeft
            and controls.signalRight and controls.radioPrevious and controls.radioPlay
            and controls.radioNext and controls.radioMute)
    check('truck_cab_controls_reflect_live_lights_signals_and_radio',
        controls.ignition and controls.ignition.active and controls.headlight and controls.headlight.active
            and controls.beam and controls.beam.active and controls.signalLeft and controls.signalLeft.active
            and controls.signalRight and not controls.signalRight.active
            and controls.radioPlay and controls.radioPlay.active and controls.radioMute and controls.radioMute.active)
    for _, control in pairs(controls) do
        check('truck_cab_hit_target_inside_view_' .. control.action,
            control.x >= 0 and control.x <= 1280 and control.y >= 0 and control.y <= 880
                and control.hitRadius >= 26)
    end
    radio.active, radio.paused, radio.muted = oldRadio.active, oldRadio.paused, oldRadio.muted

    local graphics = love.graphics
    local canvas = PixelCanvas(1280, 880)
    local originalDraw, originalDelta = graphics.draw, love.timer.getDelta
    local recorded = {}
    local truck = {speed=0, steering=0, throttle=0, brake=0, engine=false}
    local drawOkay, drawError = xpcall(function()
        graphics.draw = function(image, ...)
            if image == cab.wheel then recorded.wheel = {...}
            elseif image == cab.accelerator then recorded.accelerator = {...}
            elseif image == cab.brake then recorded.brake = {...} end
            return originalDraw(image, ...)
        end
        love.timer.getDelta = function() return .1 end
        local function drawFrame()
            recorded = {}
            graphics.push('all')
            graphics.setCanvas(canvas)
            graphics.origin()
            graphics.clear(0, 0, 0, 0)
            cab:draw(truck, 1280, 880, camera)
            graphics.pop()
            return cab.panel:newImageData()
        end
        local idle = drawFrame()
        local idleWheel, idleAccelerator, idleBrake = recorded.wheel, recorded.accelerator, recorded.brake
        truck.speed, truck.steering, truck.throttle, truck.brake, truck.engine = 24, .8, .75, .65, true
        local active = drawFrame()
        local steering, accelerator, brake = recorded.wheel, recorded.accelerator, recorded.brake
        check('truck_cab_steering_layer_rotates_with_steering_input',
            idleWheel and steering and math.abs(steering[3]) > .1 and cab.displaySteering > .4)
        check('truck_cab_accelerator_layer_moves_with_throttle',
            idleAccelerator and accelerator and accelerator[2] < idleAccelerator[2] and cab.displayThrottle > .4)
        check('truck_cab_brake_layer_moves_with_braking',
            idleBrake and brake and brake[2] < idleBrake[2] and cab.displayBrake > .4)
        local speedNeedleDiff = regionDiff(idle, active, 285, 330, 390, 420)
        local engineNeedleDiff = regionDiff(idle, active, 430, 330, 505, 420)
        check('truck_cab_speedometer_needle_responds_to_speed', speedNeedleDiff > 2,
            'changed pixels=' .. speedNeedleDiff)
        check('truck_cab_engine_gauge_responds_to_throttle', engineNeedleDiff > 2,
            'changed pixels=' .. engineNeedleDiff)
        idle:release()
        active:release()
    end, debug.traceback)
    graphics.draw, love.timer.getDelta = originalDraw, originalDelta
    canvas:release()
    cab:release()
    assert(drawOkay, drawError)
end

return Test
