local Viewport = require("src.viewport")
local Camera = require("src.mobile_camera")
local Remote = require("src.screens.workshop_remote_screen")
local Test = {}
local function near(a, b) return math.abs(a - b) < .001 end

function Test.run(context, check)
    local app, state, computer = context.app, context.state, context.computerScreen
    local stagingComputer = computer.new({warehouseEnabled = true})
    stagingComputer.tab, stagingComputer.warehouseStagingPage = "warehouse", true
    local oldSetScissor = love.graphics.setScissor
    local stagingClip
    local drawOkay, drawError = xpcall(function()
        love.graphics.setScissor = function(...)
            if select("#", ...) == 4 then stagingClip = {...} end
            return oldSetScissor(...)
        end
        love.graphics.push("all")
        love.graphics.translate(41, 29)
        love.graphics.scale(1.37)
        stagingComputer.draw(state, nil, nil, context.assets)
        love.graphics.pop()
    end, debug.traceback)
    love.graphics.setScissor = oldSetScissor
    if not drawOkay then love.graphics.pop() end
    assert(drawOkay, drawError)
    local mapScale = math.min(520 / 960, 344 / 678)
    local mapX = 76 + (520 - 960 * mapScale) / 2
    local left, top = 41 + (55.25 + mapX * .883) * 1.37, 29 + (18.2 + 260 * .901) * 1.37
    local right, bottom = 41 + (55.25 + (mapX + 960 * mapScale) * .883) * 1.37,
        29 + (18.2 + 604 * .901) * 1.37
    check("computer_staging_map_clip_tracks_mobile_viewport",
        stagingClip and stagingClip[1] == math.floor(left)
            and stagingClip[2] == math.floor(top)
            and stagingClip[3] == math.ceil(right) - math.floor(left)
            and stagingClip[4] == math.ceil(bottom) - math.floor(top))
    local exit=stagingComputer.mousepressed(state,55.25+770*.883,18.2+206*.901,1)
    check("computer_staging_contained_exit_click_works",exit and exit.action=="warehouse_staging_page_changed"
        and not stagingComputer.warehouseStagingPage)
    local reopen=stagingComputer.mousepressed(state,31.6+600*.956,9.5+216*.95,1)
    check("computer_staging_contained_reentry_click_works",reopen and reopen.action=="warehouse_staging_page_changed"
        and stagingComputer.warehouseStagingPage)
    local oldDimensions, oldSafeArea, oldOS = love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS
    local oldCamera, oldScreen, oldSlot = app.mobileCamera, state.screen, state.activeSlot
    local oldTab, oldDropdown = computer.tab, computer.tabDropdownOpen
    local oldResource = Remote.resourceId
    local cases = {
        { name = "desktop", width = 1920, height = 1080, area = {0, 0, 1920, 1080} },
        { name = "small_pc", width = 720, height = 509, area = {0, 0, 720, 509} },
        { name = "phone_landscape", width = 2400, height = 1080, area = {96, 0, 2208, 1032} },
        { name = "phone_portrait", width = 1080, height = 2400, area = {0, 96, 1080, 2212} },
        { name = "tablet", width = 1536, height = 2048, area = {0, 24, 1536, 1988} },
    }
    local ok, message = xpcall(function()
        -- This suite supplies synthetic desktop, phone and tablet safe areas.
        -- Keep the test platform synthetic too; native Android intentionally
        -- ignores orientation-dependent safe-area insets for the fitted office.
        love.system.getOS = function() return "Windows" end
        for _, case in ipairs(cases) do
            love.graphics.getDimensions = function() return case.width, case.height end
            love.window.getSafeArea = function() return unpack(case.area) end
            local x, y, scale = Viewport.transform(960, 678, true)
            local sx, sy, sw, sh = unpack(case.area)
            check("computer_fit_contains_complete_gui_" .. case.name,
                x >= sx and y >= sy and x + 960 * scale <= sx + sw + .001
                    and y + 678 * scale <= sy + sh + .001)
            local gx, gy = Viewport.toGame(x + 668 * scale, y + 156 * scale, 960, 678, true)
            check("computer_fit_pointer_round_trip_" .. case.name, near(gx, 668) and near(gy, 156))
            -- Exercise App's rendering and click routes with a deliberately
            -- zoomed mobile menu camera; the office must ignore that zoom.
            for _, mobile in ipairs({ false, true }) do
                local suffix = case.name .. (mobile and "_touch" or "_mouse")
                app.mobileCamera = Camera.new({ enabled = mobile })
                app.mobileCamera:setViewport(960, 678)
                app.mobileCamera:selectView("computer", false)
                app.mobileCamera.zoom, app.mobileCamera.centerX = 2, 320
                state.screen, state.activeSlot = "computer", nil
                computer.tabDropdownOpen = false
                app.draw()
                app.mousepressed(x + 668 * scale, y + 156 * scale, 1, false)
                app.mousereleased(x + 668 * scale, y + 156 * scale, 1, false)
                check("computer_fit_real_app_dropdown_hit_" .. suffix, computer.tabDropdownOpen)
                computer.tabDropdownOpen = false
                app.mousepressed(x + 400 * scale, y + 156 * scale, 1, false)
                app.mousereleased(x + 400 * scale, y + 156 * scale, 1, false)
                check("computer_fit_real_app_address_hit_" .. suffix, computer.tabDropdownOpen)
                local tabX,tabY=computer.tabCenter("calendar")
                app.mousepressed(x+tabX*scale,y+tabY*scale,1,false)
                app.mousereleased(x+tabX*scale,y+tabY*scale,1,false)
                app.mousepressed(x+354*scale,y+103*scale,1,false)
                app.mousereleased(x+354*scale,y+103*scale,1,false)
                check("computer_fit_real_app_find_hit_" .. suffix,computer.browserOverlay=="search" and computer.wantsTextInput())
                computer.dismissBrowserOverlay()
                -- Actual painted X location, independent of the screen's hitbox helper.
                app.mousepressed(x + 836 * scale, y + 56 * scale, 1, false)
                app.mousereleased(x + 836 * scale, y + 56 * scale, 1, false)
                check("computer_fit_real_app_sprite_x_hit_" .. suffix, state.screen == "world")
            end
            -- The multiplayer office uses the same fit and inverse transform.
            state.screen, state.activeSlot, Remote.resourceId = "workshop_remote", nil, "office_computer"
            local key = app.mobileCamera.viewKey
            app.mousemoved(x + 500 * scale, y + 300 * scale, 0, 0, false)
            check("computer_fit_remote_office_does_not_select_zoom_camera_" .. case.name,
                app.mobileCamera.viewKey == key)
        end
    end, debug.traceback)
    love.graphics.getDimensions, love.window.getSafeArea = oldDimensions, oldSafeArea
    love.system.getOS = oldOS
    app.mobileCamera, state.screen, state.activeSlot = oldCamera, oldScreen, oldSlot
    computer.tab, computer.tabDropdownOpen, Remote.resourceId = oldTab, oldDropdown, oldResource
    assert(ok, message)
end

return Test
