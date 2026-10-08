-- Pointer dispatch and multiplayer HUD input.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.pointerPosition()
        if Runtime.controller and Runtime.controller:isActive() and Runtime.state.screen ~= "world" then
            return Runtime.controller:pointer()
        end
        if Runtime.mobileControls and Runtime.mobileControls:isEnabled() then
            local x, y = Runtime.mobileControls:pointer()
            if x and y then
                if Runtime.App.cameraTransformsUi() then return Runtime.App.mobileCamera:screenToWorld(x, y) end
                return x, y
            end
        end
        local x, y = love.mouse.getPosition()
        return Runtime.toPointerCoordinates(x, y)
    end

    function Runtime.multiplayerHudInfo()
        local info = Runtime.multiplayer:hudInfo()
        info.canInvite = Runtime.directHostCanInvite()
        if Runtime.multiplayer:isHost() then
            info.workshopResources = Runtime.workshopAuthority and Runtime.workshopAuthority:snapshot() or {}
        end
        return info
    end

    function Runtime.handleMultiplayerHudAction(action)
        if action == true then return true end
        if type(action) ~= "table" then return false end
        local ok, message
        if action.kind == "approve" then
            ok, message = Runtime.multiplayer:approveJoin(action.requestId)
        elseif action.kind == "deny" then
            ok, message = Runtime.multiplayer:rejectJoin(action.requestId)
        elseif action.kind == "remove" then
            ok, message = Runtime.multiplayer:kickPlayer(action.playerId)
        elseif action.kind == "invite" then
            Runtime.openDirectInvite()
            return true
        else
            return true
        end
        Runtime.state.message = tostring(message or (ok
            and "Direct player control completed."
            or "That Direct player action is no longer available."))
        return true
    end

    function Runtime.multiplayerHudMousepressed(gameX, gameY, button)
        if Runtime.state.screen ~= "world" then return false end
        local action = Runtime.MultiplayerHud.mousepressed(
            gameX, gameY, button, Runtime.multiplayerHudInfo())
        if not action then return false end
        return Runtime.handleMultiplayerHudAction(action)
    end

    function Runtime.multiplayerHudMousereleased(gameX, gameY, button)
        if Runtime.state.screen ~= "world" then return false end
        return Runtime.MultiplayerHud.mousereleased(
            gameX, gameY, button, Runtime.multiplayerHudInfo()) == true
    end

    function Runtime.dispatchGameMousePressed(gameX, gameY, button)
        if Runtime.state.screen == "asset_error" then return end
        if require("src.shop_room_controls").mousepressed(gameX,gameY,button,Runtime) then return true end
        if button == 1 then Runtime.Ui.notePress(gameX, gameY) end
        if Runtime.App.sound then Runtime.App.sound:pointerPressed(button, Runtime.state.screen) end
        if Runtime.state.screen == "options" then
            local result = Runtime.OptionsScreen.mousepressed(gameX, gameY, button)
            Runtime.syncMobileKeyboard()
            return result
        elseif button == 1 and Runtime.OptionsScreen.accessHit(gameX, gameY, Runtime.optionsAccessLayout()) then
            return Runtime.openOptions()
        elseif Runtime.state.screen == "lan" then
            local result = Runtime.LanScreen.mousepressed(gameX, gameY, button)
            Runtime.syncMobileKeyboard()
            return result
        elseif Runtime.state.screen == "direct" then
            local result = Runtime.DirectScreen.mousepressed(gameX, gameY, button)
            Runtime.syncMobileKeyboard()
            return result
        end
        if Runtime.multiplayerHudMousepressed(gameX, gameY, button) then return true end
        if Runtime.warehouseControls:mousepressed(gameX,gameY,button) then return true end
        return Runtime.Input.mousepressed(gameX, gameY, button, Runtime.inputContext)
    end

    function Runtime.dispatchGameMouseReleased(gameX, gameY, button)
        if Runtime.state.screen == "options" then return Runtime.OptionsScreen.mousereleased(gameX, gameY, button) end
        if Runtime.state.screen == "lan" then return Runtime.LanScreen.mousereleased(gameX, gameY, button) end
        if Runtime.state.screen == "direct" then return Runtime.DirectScreen.mousereleased(gameX, gameY, button) end
        if Runtime.multiplayerHudMousereleased(gameX, gameY, button) then return true end
        return Runtime.Input.mousereleased(gameX, gameY, button, Runtime.inputContext)
    end

    function Runtime.dispatchMousePressed(x, y, button)
        if Runtime.state.screen == "asset_error" then return end
        local gameX, gameY = Runtime.toPointerCoordinates(x, y)
        if require("src.shop_room_controls").mousepressed(gameX,gameY,button,Runtime) then return true end
        if button == 1 then Runtime.Ui.notePress(gameX, gameY) end
        if Runtime.App.sound then Runtime.App.sound:pointerPressed(button, Runtime.state.screen) end
        if Runtime.state.screen == "options" then
            local result = Runtime.OptionsScreen.mousepressed(gameX, gameY, button)
            Runtime.syncMobileKeyboard()
            return result
        elseif button == 1 and Runtime.OptionsScreen.accessHit(gameX, gameY, Runtime.optionsAccessLayout()) then
            return Runtime.openOptions()
        elseif Runtime.state.screen == "lan" then
            local result = Runtime.LanScreen.mousepressed(gameX, gameY, button)
            Runtime.syncMobileKeyboard()
            return result
        elseif Runtime.state.screen == "direct" then
            local result = Runtime.DirectScreen.mousepressed(gameX, gameY, button)
            Runtime.syncMobileKeyboard()
            return result
        end
        if Runtime.state.screen == "world" and Runtime.multiplayer:isActive() then
            local worldX, worldY = gameX, gameY
            if Runtime.App.cameraTransformsWorld() and Runtime.App.mobileCamera then
                worldX, worldY = Runtime.App.mobileCamera:screenToWorld(gameX, gameY)
            end
            local consumed, message = Runtime.HighFiveUi.mousepressed(gameX, gameY,
                worldX, worldY, button, Runtime.multiplayer:highFiveInfo(),
                Runtime.multiplayer:remotePlayers(), Runtime.World.player, Runtime.multiplayer)
            if consumed then
                if message then Runtime.state.message = tostring(message) end
                return true
            end
        end
        if Runtime.multiplayerHudMousepressed(gameX, gameY, button) then return true end
        if Runtime.warehouseControls:mousepressed(gameX,gameY,button) then return true end
        return Runtime.Input.mousepressed(gameX, gameY, button, Runtime.inputContext)
    end

    function Runtime.dispatchMouseReleased(x, y, button)
        local gameX, gameY = Runtime.toPointerCoordinates(x, y)
        if Runtime.state.screen == "options" then return Runtime.OptionsScreen.mousereleased(gameX, gameY, button) end
        if Runtime.state.screen == "lan" then return Runtime.LanScreen.mousereleased(gameX, gameY, button) end
        if Runtime.state.screen == "direct" then return Runtime.DirectScreen.mousereleased(gameX, gameY, button) end
        if Runtime.multiplayerHudMousereleased(gameX, gameY, button) then return true end
        return Runtime.Input.mousereleased(gameX, gameY, button, Runtime.inputContext)
    end

    function Runtime.dispatchMouseMoved(x, y)
        local gameX, gameY = Runtime.toPointerCoordinates(x, y)
        if Runtime.state.screen == "options" then return Runtime.OptionsScreen.mousemoved(gameX, gameY) end
        return Runtime.Input.mousemoved(gameX, gameY, Runtime.inputContext)
    end
end

return Component
