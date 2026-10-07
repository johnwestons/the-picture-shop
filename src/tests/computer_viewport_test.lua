local Viewport = require("src.viewport")
local Camera = require("src.mobile_camera")
local Remote = require("src.screens.workshop_remote_screen")
local Test = {}
local function near(a, b) return math.abs(a - b) < .001 end

function Test.run(context, check)
    local app, state, computer = context.app, context.state, context.computerScreen
    local oldDimensions, oldSafeArea = love.graphics.getDimensions, love.window.getSafeArea
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
                app.mousepressed(x + 822 * scale, y + 68 * scale, 1, false)
                app.mousereleased(x + 822 * scale, y + 68 * scale, 1, false)
                check("computer_fit_real_app_back_hit_" .. suffix, state.screen == "world")
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
    app.mobileCamera, state.screen, state.activeSlot = oldCamera, oldScreen, oldSlot
    computer.tab, computer.tabDropdownOpen, Remote.resourceId = oldTab, oldDropdown, oldResource
    assert(ok, message)
end

return Test
