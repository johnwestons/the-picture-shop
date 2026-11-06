-- LÖVE keyboard, pointer, touch, and controller callbacks.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.App.keypressed(key)
        if Runtime.Assets.isLoading and Runtime.Assets.isLoading()
            and key~="escape" and key~="back" then return end
        if Runtime.spriteLabActive then Runtime.SpriteMotionLab.keypressed(key, Runtime.CharacterAssets); return end
        if require('src.screens.hud_visibility').keypressed(Runtime,key) then return true end
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
        if Runtime.state.screen == "title" then
            local result = Runtime.TitleScreen.textinput(text)
            Runtime.syncMobileKeyboard()
            return result
        elseif Runtime.state.screen == "options" then
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
        if Runtime.Assets.isLoading and Runtime.Assets.isLoading() then return end
        if Runtime.mobileControls and Runtime.mobileControls:ignoreSyntheticMouse(isTouch) then return end
        if Runtime.state.screen=='options' and Runtime.OptionsScreen.motorcycleEditor then
            local px,py=Runtime.toPointerCoordinates(x,y)
            return Runtime.OptionsScreen.mousepressed(px,py,button)
        end
        local px,py=Runtime.toPointerCoordinates(x,y)
        if Runtime.menuAccessPointer and Runtime.menuAccessPointer(px,py,button) then return true end
        if Runtime.WarehouseFirstPerson and Runtime.WarehouseFirstPerson:mousepressed(Runtime,button) then return true end
        if not isTouch and require('src.commute.runtime').cameraPointerPressed(Runtime,button) then return true end
        if not isTouch and button~=1 and require('src.commute.runtime').deviceInput(Runtime,'mouse','mouse'..button) then return true end
        if button==1 and require('src.commute.runtime').pointer(Runtime,px,py,'mouse') then return true end
        return Runtime.dispatchMousePressed(x, y, button)
    end

    function Runtime.App.mousereleased(x, y, button, isTouch)
        if Runtime.mobileControls and Runtime.mobileControls:ignoreSyntheticMouse(isTouch) then return end
        if Runtime.WarehouseFirstPerson and Runtime.WarehouseFirstPerson:mousereleased(Runtime,button) then return true end
        if not isTouch and require('src.commute.runtime').cameraPointerReleased(Runtime,button) then return true end
        if button==1 then require('src.commute.runtime').pointerReleased(Runtime,'mouse') end
        return Runtime.dispatchMouseReleased(x, y, button)
    end

    function Runtime.App.mousemoved(x, y, dx, dy, isTouch)
        if Runtime.mobileControls and Runtime.mobileControls:ignoreSyntheticMouse(isTouch) then return end
        if not isTouch then
            local px,py=Runtime.toPointerCoordinates(x,y)
            local oldX,oldY=Runtime.toPointerCoordinates(x-(dx or 0),y-(dy or 0))
            if Runtime.WarehouseFirstPerson and Runtime.WarehouseFirstPerson:mousemoved(Runtime,px-oldX,py-oldY) then return true end
            if require('src.commute.runtime').cameraPointerMoved(Runtime,px-oldX,py-oldY) then return true end
        end
        return Runtime.dispatchMouseMoved(x, y)
    end

    function Runtime.App.wheelmoved(x, y)
        if Runtime.state.screen=='options' and Runtime.OptionsScreen.wheelmoved(x,y) then return true end
        if Runtime.state.screen=='world' and Runtime.World.player.sceneId=='commute' then
            if y~=0 then require('src.commute.runtime').deviceInput(Runtime,'mouse',y>0 and 'wheelup' or 'wheeldown') end
            return true
        end
        Runtime.syncCamera()
        if Runtime.App.cameraTransformsWorld() and y ~= 0 then return Runtime.App.mobileCamera:zoomBy(1.12 ^ y) end
        if Runtime.state.screen == "options" or Runtime.state.screen == "lan" or Runtime.state.screen == "direct" then
            return false
        end
        Runtime.Input.wheelmoved(x, y, Runtime.inputContext)
    end

    function Runtime.App.touchpressed(id, x, y)
        if Runtime.Assets.isLoading and Runtime.Assets.isLoading() then return end
        local px,py=Runtime.toPointerCoordinates(x,y)
        if Runtime.menuAccessPointer and Runtime.menuAccessPointer(px,py,1) then return true end
        if Runtime.state.screen=='options' and Runtime.OptionsScreen.motorcycleEditor then return Runtime.OptionsScreen.mousepressed(px,py,1) end
        if require('src.commute.runtime').touchPressed(Runtime,id,px,py) then return true end
        if require("src.basketball_controls").touchpressed(id,px,py,Runtime) then return true end
        if Runtime.state.screen=="air_hockey" then
            return require("src.screens.air_hockey_screen").touchpressed(Runtime,id,x,y)
        end
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").touchpressed(Runtime,id,x,y)
        end
        if Runtime.mobileControls then return Runtime.mobileControls:touchpressed(id, x, y) end
    end

    function Runtime.App.touchmoved(id, x, y, dx, dy)
        local px,py=Runtime.toPointerCoordinates(x,y)
        if Runtime.state.screen=='options' and Runtime.OptionsScreen.motorcycleEditor then return Runtime.OptionsScreen.mousemoved(px,py) end
        if require('src.commute.runtime').touchMoved(Runtime,id,px,py) then return true end
        if require("src.basketball_controls").touchmoved(id,px,py,Runtime) then return true end
        if Runtime.state.screen=="air_hockey" then
            return require("src.screens.air_hockey_screen").touchmoved(Runtime,id,x,y)
        end
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").touchmoved(Runtime,id,x,y)
        end
        if Runtime.mobileControls then return Runtime.mobileControls:touchmoved(id, x, y, dx, dy) end
    end

    function Runtime.App.touchreleased(id, x, y)
        local px,py=Runtime.toPointerCoordinates(x,y)
        if Runtime.state.screen=='options' and Runtime.OptionsScreen.motorcycleEditor then return Runtime.OptionsScreen.mousereleased(px,py,1) end
        if require('src.commute.runtime').touchReleased(Runtime,id) then return true end
        require('src.commute.runtime').pointerReleased(Runtime,id)
        if require("src.basketball_controls").touchreleased(id,px,py,Runtime) then return true end
        if Runtime.state.screen=="air_hockey" then
            return require("src.screens.air_hockey_screen").touchreleased(id)
        end
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").touchreleased(id)
        end
        if Runtime.mobileControls then return Runtime.mobileControls:touchreleased(id, x, y) end
    end

    function Runtime.App.gamepadpressed(joystick, button)
        if Runtime.state.screen=='options' and Runtime.OptionsScreen.gamepadpressed(joystick,button) then return true end
        if Runtime.state.screen=='world' and require('src.commute.runtime').active(Runtime) then
            if button=='start' then return require('src.commute.runtime').keypressed(Runtime,'f10') end
            return require('src.commute.runtime').deviceInput(Runtime,'controller',button)
        end
        if Runtime.state.screen=='world' and (Runtime.World.player.sceneId=='commute'
            or require('src.commute.outfit').get(Runtime.state,Runtime.World.player)) then
            local commute=require('src.commute.runtime')
            local action=require('src.commute.bindings').action(commute.bindings(Runtime),'controller',button)
            if action=='gear' and commute.perform(Runtime,action) then return true end
        end
        if Runtime.Assets.isLoading and Runtime.Assets.isLoading() and button~="b" then return end
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").gamepadpressed(Runtime,joystick,button)
        end
        if Runtime.controller then return Runtime.controller:gamepadpressed(joystick, button) end
    end

    function Runtime.App.gamepadreleased(joystick, button)
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").gamepadreleased(Runtime,joystick,button)
        end
        if Runtime.controller then return Runtime.controller:gamepadreleased(joystick, button) end
    end

    function Runtime.App.gamepadaxis(joystick,axis,value)
        if Runtime.state.screen=='options' and Runtime.OptionsScreen.gamepadaxis(joystick,axis,value) then return true end
        if require('src.commute.runtime').gamepadaxis(Runtime,joystick,axis,value) then return true end
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").gamepadaxis(Runtime,joystick,axis,value)
        end
    end
end

return Component
