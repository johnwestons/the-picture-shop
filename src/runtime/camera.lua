-- Camera transforms and pointer coordinates.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.App.officeFitsScreen()
        return Runtime.state.screen == "computer"
            or Runtime.state.screen == "shop_rooms"
            or Runtime.state.screen == "workshop_remote" and Runtime.WorkshopRemoteScreen.resourceId == "office_computer"
    end

    function Runtime.App.cameraTransformsUi()
        return Runtime.App.mobileCamera and Runtime.App.mobileCamera:isEnabled() and Runtime.state.screen ~= "world"
            and not Runtime.App.officeFitsScreen()
    end

    function Runtime.App.cameraTransformsWorld()
        return Runtime.state.screen == "world" and Runtime.App.mobileCamera
            and (Runtime.App.mobileCamera:isEnabled() or Runtime.App.settings and Runtime.App.settings.followPlayerCamera)
    end

    function Runtime.cameraViewKey()
        if Runtime.state.screen == "machine" then return "machine:" .. tostring(Runtime.state.machineType or "unknown") end
        return tostring(Runtime.state.screen)
    end

    function Runtime.syncCamera()
        local bounds = Runtime.Viewport.gameBounds(Runtime.Config.baseWidth, Runtime.Config.baseHeight, Runtime.App.officeFitsScreen())
        if Runtime.App.mobileCamera then
            Runtime.App.mobileCamera:setViewport(bounds.width, bounds.height)
            if Runtime.App.cameraTransformsWorld() or Runtime.App.cameraTransformsUi() then
                Runtime.App.mobileCamera:selectView(Runtime.cameraViewKey(), Runtime.state.screen == "world")
            end
            Runtime.App.mobileCamera:setFollowTarget(Runtime.App.cameraTransformsWorld() and Runtime.App.settings
                and Runtime.App.settings.followPlayerCamera and Runtime.World.player or nil)
        end
        return bounds
    end

    function Runtime.toPointerCoordinates(x, y)
        Runtime.syncCamera()
        local gameX, gameY = Runtime.Viewport.toGame(x, y, Runtime.Config.baseWidth, Runtime.Config.baseHeight, Runtime.App.officeFitsScreen())
        if Runtime.App.cameraTransformsUi() then return Runtime.App.mobileCamera:screenToWorld(gameX, gameY) end
        return gameX, gameY
    end

    function Runtime.optionsAccessLayout()
        local screen, machineScreen = Runtime.state.screen, Runtime.MachineScreen
        if screen == "workshop_remote" then
            local resource = Runtime.WorkshopRemoteScreen.resourceId
            if resource == "office_computer" then screen = "computer"
            elseif Runtime.WorkshopRemoteScreen.sharedMachine then
                screen, machineScreen = "machine", Runtime.WorkshopRemoteScreen.sharedMachine
            elseif Runtime.WorkshopRemoteScreen.sharedPress then screen = "press"
            elseif resource == "work_phone" then screen = "work_phone"
            elseif resource == "vendor" then screen = "vendor"
            elseif resource == "truck" then screen = "truck_inventory"
            elseif resource == "reception_customer" then screen = "job_offer" end
        end
        if screen == "machine" and (machineScreen.helpOpen or machineScreen.maintenanceView) then
            screen = "machine_service"
        end
        local bounds
        if screen == "world" and Runtime.mobileControls and Runtime.mobileControls:isEnabled() then
            bounds = Runtime.Viewport.gameBounds(Runtime.Config.baseWidth, Runtime.Config.baseHeight)
        end
        return screen, bounds
    end
end

return Component
