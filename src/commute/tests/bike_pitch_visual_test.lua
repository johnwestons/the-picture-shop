local Art = require('src.commute.bike_art')
local Bike = require('src.commute.motorcycle')
local Camera = require('src.commute.camera')
local FP = require('src.commute.first_person_camera')
local Body = require('src.commute.first_person_bike')
local Test = {}
local world = {height=function() return 5 end,supportHeight=function() return 5 end}
local function near(a,b) return math.abs(a-b)<1e-6 end

local function capture(directory)
    local g=love.graphics
    local art=Art.new()
    local panelHeight=314
    local canvas=g.newCanvas(960,panelHeight*2)
    local cases={
        {'Level road',0,0,true},{'Uphill',.44,0,true},{'Downhill',-.44,0,true},
        {'Airborne, rear wheel low',.74,0,false},{'Airborne, front wheel low',-.64,0,false},
        {'Airborne, directly from behind',.74,270,false},
    }
    g.push('all');g.origin();g.setCanvas(canvas);g.setScissor();g.setShader()
    g.clear(.13,.19,.23,1)
    for i,sample in ipairs(cases) do
        local col=(i-1)%3
        local row=math.floor((i-1)/3)
        local left,top=col*320,row*panelHeight
        local pitch,yaw,onRoad=sample[2],sample[3],sample[4]
        local bike=Bike.new(100,100,0)
        bike.h,bike.pitch=5,pitch
        local camera=Camera.new(bike,world)
        camera.tilt,camera.yaw,camera.zoom=35,yaw,1.75
        g.push();g.setScissor(left+2,top+36,316,panelHeight-38)
        g.translate(left+160-640,top+231-440)
        local grade=onRoad and math.tan(pitch) or 0
        local ground=onRoad and bike.h or bike.h-.95
        local leftX,leftY=camera:screen(97,100,ground-grade*3)
        local rightX,rightY=camera:screen(103,100,ground+grade*3)
        if yaw==270 then leftX,rightX=rightX-230,leftX+230;leftY,rightY=440+32,440+32 end
        g.setColor(.23,.29,.23);g.polygon('fill',leftX,leftY,rightX,rightY,rightX,860,leftX,860)
        g.setColor(.75,.81,.61);g.line(leftX,leftY,rightX,rightY)
        art:draw(bike,camera,world)
        g.pop();g.setScissor()
        g.setColor(.10,.15,.18);g.rectangle('fill',left+2,top+2,316,32)
        g.setColor(.95,.93,.80);g.printf(sample[1],left+4,top+10,312,'center')
    end
    g.pop()
    local pixels=canvas:newImageData();local png=pixels:encode('png')
    local file=assert(io.open(directory..'/bike-pitch-poses.png','wb'))
    file:write(png:getString());file:close()
    png:release();pixels:release();canvas:release();art:release()
end

function Test.run(check)
    local bike=Bike.new(100,100,0)
    bike.h,bike.pitch=5,.36
    local camera=Camera.new(bike,world)
    camera.tilt,camera.zoom=35,1.4
    local contact=true
    for _,yaw in ipairs({0,32,135,180}) do
        camera.yaw=yaw
        local x,y=camera:screen(bike.x,bike.z,bike.h)
        local fx,fy=camera:screen(bike.x+Bike.WHEELBASE*.5,bike.z,bike.h)
        local px,py=camera:screen(bike.x+Bike.WHEELBASE*.5,bike.z,bike.h+Bike.WHEELBASE*.5*math.tan(bike.pitch))
        local rotated=math.atan2(fy-y,fx-x)+Art.pitchRotation(bike,camera,bike.h,bike.pitch)
        contact=contact and near(math.sin(rotated),(py-y)/math.sqrt((px-x)^2+(py-y)^2))
    end
    check('bike_pitch_rotates_side_and_diagonal_art_to_projected_wheel_contact',contact)
    local upright=true
    for _,yaw in ipairs({80,90,100,260,270,280}) do
        camera.yaw=yaw
        upright=upright and Art.pitchRotation(bike,camera,5,1.15)==0 and Art.pitchRotation(bike,camera,5,-1.15)==0
    end
    check('bike_pitch_front_and_back_sheets_stay_upright_even_at_steep_air_angles',upright)

    -- A point on the handlebars should project to the same pixel as its
    -- rotated world position, even while the head and chassis pitches differ.
    local attached,uncapped=true,true
    for _,pitch in ipairs({-.78,.24,.94}) do
        bike.pitch=pitch
        camera=Camera.new(bike,world);camera:setFirstPerson(true,bike)
        uncapped=uncapped and near(camera.viewPitch,pitch+FP.NEUTRAL_PITCH)
        camera.lookYaw,camera.lookPitch=.32,.1
        for _=1,50 do camera:update(bike,1/60) end
        local chassis=Body.camera(camera)
        local forward,up,right=Body.point(760,300)
        local wx,wy=FP.screen(camera,bike.x+forward*math.cos(pitch)-up*math.sin(pitch),
            bike.z+right,bike.h+forward*math.sin(pitch)+up*math.cos(pitch))
        local sx,sy=FP.screen(chassis,forward,right,up)
        attached=attached and near(sx,wx) and near(sy,wy) and sx~=-10000
    end
    check('bike_pitch_first_person_uses_full_pitch_in_both_directions',uncapped)
    check('bike_pitch_cockpit_stays_attached_for_air_grade_and_head_look',attached)
    local dir=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE')
    if dir and dir~='' and love and love.graphics then capture(dir) end
end

return Test
