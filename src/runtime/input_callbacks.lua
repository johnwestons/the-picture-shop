-- LÖVE keyboard, pointer, touch, and controller callbacks.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.App.keypressed(key)
        if Runtime.spriteLabActive then Runtime.SpriteMotionLab.keypressed(key, Runtime.CharacterAssets); return end
        if Runtime.state.screen == "asset_error" then
            if key == "escape" or key == "q" then love.event.quit() end
            return
        end
        Runtime.dispatchKeyPressed(key)
    end

    function Runtime.App.keyreleased(key)
        if Runtime.state.screen == "lan" or Runtime.state.screen == "direct" then return false end
        Runtime.Input.keyreleased(key, Runtime.inputContext)
    end

    function Runtime.App.textinput(text)
        if Runtime.state.screen == "options" then
            local result = Runtime.OptionsScreen.textinput(text)
            Runtime.syncMobileKeyboard()
            return result
        elseif Runtime.state.screen == "lan" then
            local result = Runtime.LanScreen.textinput(text)
            Runtime.syncMobileKeyboard()
            return result
        elseif Runtime.state.screen == "direct" then
            local result = Runtime.DirectScreen.textinput(text)
            Runtime.syncMobileKeyboard()
            return result
        end
        Runtime.Input.textinput(text, Runtime.inputContext)
    end

    function Runtime.App.mousepressed(x, y, button, isTouch)
        if Runtime.mobileControls and Runtime.mobileControls:ignoreSyntheticMouse(isTouch) then return end
        return Runtime.dispatchMousePressed(x, y, button)
    end

    function Runtime.App.mousereleased(x, y, button, isTouch)
        if Runtime.mobileControls and Runtime.mobileControls:ignoreSyntheticMouse(isTouch) then return end
        return Runtime.dispatchMouseReleased(x, y, button)
    end

    function Runtime.App.mousemoved(x, y, _, _, isTouch)
        if Runtime.mobileControls and Runtime.mobileControls:ignoreSyntheticMouse(isTouch) then return end
        return Runtime.dispatchMouseMoved(x, y)
    end

    function Runtime.App.wheelmoved(x, y)
        Runtime.syncCamera()
        if Runtime.App.cameraTransformsWorld() and y ~= 0 then return Runtime.App.mobileCamera:zoomBy(1.12 ^ y) end
        if Runtime.state.screen == "options" or Runtime.state.screen == "lan" or Runtime.state.screen == "direct" then
            return false
        end
        Runtime.Input.wheelmoved(x, y, Runtime.inputContext)
    end

    function Runtime.App.touchpressed(id, x, y)
        if Runtime.state.screen=="air_hockey" then
            return require("src.screens.air_hockey_screen").touchpressed(Runtime,id,x,y)
        end
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").touchpressed(Runtime,id,x,y)
        end
        if Runtime.mobileControls then return Runtime.mobileControls:touchpressed(id, x, y) end
    end

    function Runtime.App.touchmoved(id, x, y, dx, dy)
        if Runtime.state.screen=="air_hockey" then
            return require("src.screens.air_hockey_screen").touchmoved(Runtime,id,x,y)
        end
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").touchmoved(Runtime,id,x,y)
        end
        if Runtime.mobileControls then return Runtime.mobileControls:touchmoved(id, x, y, dx, dy) end
    end

    function Runtime.App.touchreleased(id, x, y)
        if Runtime.state.screen=="air_hockey" then
            return require("src.screens.air_hockey_screen").touchreleased(id)
        end
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").touchreleased(id)
        end
        if Runtime.mobileControls then return Runtime.mobileControls:touchreleased(id, x, y) end
    end

    function Runtime.App.gamepadpressed(joystick, button)
        if Runtime.controller then return Runtime.controller:gamepadpressed(joystick, button) end
    end

    function Runtime.App.gamepadreleased(joystick, button)
        if Runtime.controller then return Runtime.controller:gamepadreleased(joystick, button) end
    end
end

return Component
