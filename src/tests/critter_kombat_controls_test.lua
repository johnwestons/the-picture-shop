local Controls=require("src.critter_kombat_controls")
local Screen=require("src.screens.critter_kombat_screen")
local Options=require("src.screens.critter_kombat_options")
local Kombat=require("src.critter_kombat")
local Test={}
local function capture(runtime,name)
    local dir=os.getenv("PICTURE_SHOP_KOMBAT_CAPTURE_DIR")
    if not dir then return end
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.origin();love.graphics.clear()
    Screen.draw(runtime);love.graphics.setCanvas();love.graphics.pop()
    local data=canvas:newImageData();local encoded=data:encode("png")
    local file=assert(io.open(dir.."/"..name..".png","wb"));file:write(encoded:getString());file:close()
    data:release();encoded:release();canvas:release()
end
local function pad()
    return {down={},axes={},connected=true,isGamepad=function()return true end,
        isConnected=function(self)return self.connected end,
        isGamepadDown=function(self,b)return self.down[b]==true end,
        getGamepadAxis=function(self,a)return self.axes[a] or 0 end}
end
local function valueChecks(check)
    local pressed={};local environment={keyboard={isDown=function(key)return pressed[key]end}}
    local bit={left=0,right=0,jump=1,punch=2,kick=4,block=8}
    local axis={left=-1,right=1,jump=0,punch=0,kick=0,block=0}
    for i,action in ipairs(Controls.ACTIONS) do
        local config=Controls.default();local key=({"z","c","v","b","n","m"})[i]
        assert(Controls.assign(config,"keyboard",action,key));pressed[key]=true
        local x,bits=Controls.input(config,{}, {},nil,environment)
        check("kombat_remapped_keyboard_"..action,x==axis[action] and bits==bit[action])
        pressed[key]=nil
        config=Controls.default();local mouseButton=(i-1)%5+1
        assert(Controls.assign(config,"mouse",action,mouseButton))
        x,bits=Controls.input(config,{}, {[mouseButton]=true},nil,environment)
        check("kombat_remapped_mouse_"..action,x==axis[action] and bits==bit[action])
        config=Controls.default();local controller=pad()
        local button=({"leftshoulder","rightstick","b","rightshoulder","leftstick","start"})[i]
        assert(Controls.assign(config,"gamepad",action,button));controller.down[button]=true
        x,bits=Controls.input(config,{}, {},controller,environment)
        check("kombat_remapped_controller_"..action,x==axis[action] and bits==bit[action])
    end
    local config=Controls.default();local controller=pad()
    controller.axes.leftx=.20
    local x,bits=Controls.input(config,{}, {},controller,environment)
    check("kombat_controller_deadzone_rejects_drift",x==0 and bits==0)
    controller.axes.leftx=-.8;x,bits=Controls.input(config,{}, {},controller,environment)
    check("kombat_controller_default_left_stick_moves",x==-1 and bits==0)
    assert(Controls.assign(config,"gamepad","jump","triggerright+"));controller.axes.leftx=0;controller.axes.triggerright=.8
    x,bits=Controls.input(config,{}, {},controller,environment)
    check("kombat_controller_trigger_can_jump",x==0 and bits==1)
    assert(Controls.assign(config,"gamepad","kick","righty-"));controller.axes.righty=-.9
    x,bits=Controls.input(config,{}, {},controller,environment)
    check("kombat_controller_signed_axis_can_attack",bits==5)
    controller.connected=false;x,bits=Controls.input(config,{}, {},controller,environment)
    check("kombat_disconnected_controller_is_neutral",x==0 and bits==0)
    config=Controls.default();assert(Controls.assign(config,"keyboard","jump","j"));pressed.j=true
    x,bits=Controls.input(config,{}, {},nil,environment);pressed.j=nil
    check("kombat_duplicate_binding_moves_to_new_action",bits==1 and #config.keyboard.punch==0)
    check("kombat_escape_and_controller_back_remain_exit_controls",not Controls.valid("keyboard","escape")
        and not Controls.valid("gamepad","back") and not Controls.assign(config,"mouse","jump",6))
    local bad=Controls.normalize({touchScale=0/0,touchOpacity=math.huge,deadzone=-50,
        touch={left={x=-20,y=2}},keyboard={jump={"escape","invalid-key",{}}},gamepad={jump={"triggerright+","dragon"}}})
    check("kombat_controls_normalize_invalid_and_nonfinite_data",bad.touchScale==1 and bad.touchOpacity==.9
        and bad.deadzone==.1 and bad.touch.left.x==.04 and bad.touch.left.y==.95
        and #bad.keyboard.jump==0 and #bad.gamepad.jump==1)
    config.touchScale=1.5;config.touch.jump={x=0,y=0}
    local r=Controls.rect(config,"jump")
    check("kombat_touch_layout_clamps_offscreen_positions",r[1]>=8 and r[2]>=200 and r[1]+r[3]<=952 and r[2]+r[4]<=670)
    config.touch.jump={x=1,y=1};r=Controls.rect(config,"jump")
    check("kombat_enlarged_touch_buttons_stay_inside_screen",r[1]+r[3]<=952 and r[2]+r[4]<=670)
    local other=Controls.default();config.touch.left.x=.8
    check("kombat_default_controls_are_independent_copies",other.touch.left.x==125/960 and other.keyboard.jump[1]=="space")
end
local function uiChecks(check)
    -- Real callback components, isolated device state and a transient arcade match.
    local keys={};local controller=pad();local genericPresses=0
    local oldDown,oldPads=love.keyboard.isDown,love.joystick.getJoysticks
    local oldInfo,oldRead,oldWrite=love.filesystem.getInfo,love.filesystem.read,love.filesystem.write
    local bytes,writeOkay=nil,true
    love.keyboard.isDown=function(key)return keys[key]==true end
    love.joystick.getJoysticks=function()return {controller}end
    love.filesystem.getInfo=function(path,...)
        if path==Controls.PATH then return bytes and {type="file"} end
        return oldInfo(path,...)
    end
    love.filesystem.read=function(path,...)
        if path==Controls.PATH then return bytes end;return oldRead(path,...)
    end
    love.filesystem.write=function(path,value,...)
        if path==Controls.PATH then if writeOkay then bytes=value;return true end;return false,"test failure" end
        return oldWrite(path,value,...)
    end
    local Runtime={state={screen="critter_kombat"},World={player={id=1,sceneId="front_left"}},
        Config={baseWidth=960,baseHeight=678},Viewport={toGame=function(x,y)return x/2,y/2 end},
        App={officeFitsScreen=function()return true end},toPointerCoordinates=function(x,y)return x/2,y/2 end,
        multiplayer={isClient=function()return false end,isActive=function()return false end,
            isHost=function()return false end,sendNeutralInput=function()end},
        Assets={clearCache=function()end},CharacterAssets={clearCache=function()end},WorldRenderer={clearCache=function()end},
        saveCurrent=function()end}
    Runtime.App.multiplayerFocusGrace=require("src.net.focus_grace").new({clock=function()return 0 end})
    Runtime.controller=require("src.controller").new({screenInfo=function()return Runtime.state.screen end,
        pressKey=function()genericPresses=genericPresses+1 end,releaseKey=function()end,
        pressPointer=function()genericPresses=genericPresses+1 end,releasePointer=function()end,menuAction=function()genericPresses=genericPresses+1 end})
    require("src.runtime.keyboard_mobile").install(Runtime)
    require("src.runtime.pointer_dispatch").install(Runtime)
    require("src.runtime.input_callbacks").install(Runtime)
    require("src.runtime.lifecycle").install(Runtime)
    Kombat.clear();Screen.enter(Runtime,"front_left")
    Runtime.App.gamepadpressed(controller,"start")
    check("kombat_controller_opens_title_controls_without_global_menu",Screen.page(Runtime)=="options" and genericPresses==0)
    capture(Runtime,"controls-keyboard")
    Runtime.App.keypressed("down");Runtime.App.keypressed("down");Runtime.App.keypressed("return");Runtime.App.keypressed("v")
    check("kombat_options_captures_keyboard_key",Options.draft.keyboard.jump[1]=="v" and Screen.bindings.keyboard.jump[1]=="space")
    Runtime.App.keypressed("tab");Runtime.dispatchGameMousePressed(400,395,1)
    Runtime.App.mousepressed(960,560,2)
    check("kombat_options_captures_mouse_button_through_dispatch",Options.draft.mouse.punch[1]==2)
    capture(Runtime,"controls-mouse")
    Runtime.App.keypressed("tab");Runtime.dispatchGameMousePressed(400,448,1)
    Runtime.App.gamepadpressed(controller,"b")
    check("kombat_options_captures_controller_button_without_exiting",Options.draft.gamepad.kick[1]=="b" and Screen.view=="options")
    Runtime.dispatchGameMousePressed(400,448,1);Runtime.App.gamepadaxis(controller,"righty",-.9)
    check("kombat_options_captures_signed_controller_axis",Options.draft.gamepad.kick[1]=="righty-")
    Runtime.dispatchGameMousePressed(400,448,1);Runtime.App.gamepadpressed(controller,"back")
    check("kombat_controller_back_cancels_capture_without_closing",not Options.listening and Screen.view=="options"
        and Options.draft.gamepad.kick[1]=="righty-")
    capture(Runtime,"controls-controller")
    Runtime.App.keypressed("tab")
    Runtime.App.touchpressed("drag",250,1276)
    Runtime.App.touchpressed("other",1056,1276);Runtime.App.touchmoved("other",800,800)
    check("kombat_touch_layout_keeps_original_drag_finger",Options.drag and Options.drag.pointer=="drag" and Options.drag.action=="left")
    Runtime.App.touchreleased("other",800,800)
    check("kombat_unrelated_touch_release_keeps_layout_drag",Options.drag~=nil)
    Runtime.App.touchmoved("drag",340,1060);Runtime.App.touchreleased("drag",340,1060)
    check("kombat_touch_layout_drag_uses_scaled_game_coordinates",math.abs(Options.draft.touch.left.x-170/960)<.001
        and math.abs(Options.draft.touch.left.y-530/678)<.001 and not Options.drag)
    Runtime.App.mousepressed(402,1276,1);Runtime.App.mousemoved(490,1130);Runtime.App.mousereleased(490,1130,1)
    check("kombat_mouse_can_rearrange_touch_layout",math.abs(Options.draft.touch.right.x-245/960)<.001
        and math.abs(Options.draft.touch.right.y-565/678)<.001 and not Options.drag)
    Runtime.dispatchGameMousePressed(326,180,1);Runtime.dispatchGameMousePressed(446,180,1)
    check("kombat_touch_size_and_opacity_are_adjustable",Options.draft.touchScale>1 and Options.draft.touchOpacity<.9)
    capture(Runtime,"controls-touch-layout")
    Runtime.App.keypressed("s")
    check("kombat_save_applies_all_devices_and_touch_layout",Screen.view=="title" and bytes and Screen.bindings.keyboard.jump[1]=="v"
        and Screen.bindings.mouse.punch[1]==2 and Screen.bindings.gamepad.kick[1]=="righty-" and Screen.bindings.touchScale>1)
    local reloaded=Controls.load()
    check("kombat_controls_persist_outside_shop_save",reloaded.keyboard.jump[1]=="v" and reloaded.mouse.punch[1]==2
        and reloaded.touch.left.x==Screen.bindings.touch.left.x and Controls.PATH~="save.lua")
    Screen.enter(Runtime,"front_left")
    check("kombat_reopening_cabinet_loads_saved_bindings",Screen.bindings.keyboard.jump[1]=="v" and Screen.bindings.touchScale>1)
    Screen.openControls();Runtime.App.keypressed("down");Runtime.App.keypressed("down");Runtime.App.keypressed("return")
    Runtime.App.keypressed("escape")
    check("kombat_escape_cancels_capture_before_closing_menu",not Options.listening and Screen.view=="options")
    Runtime.App.keypressed("return");Runtime.App.keypressed("q");Runtime.App.keypressed("escape")
    check("kombat_back_discards_unsaved_bindings",Screen.view=="title" and Screen.bindings.keyboard.jump[1]=="v")
    Screen.openControls();Runtime.App.keypressed("r");writeOkay=false;Runtime.App.keypressed("s")
    check("kombat_failed_control_save_retains_draft",Screen.view=="options" and Options.message:find("Could not save",1,true)
        and Screen.bindings.keyboard.jump[1]=="v")
    writeOkay=true;Runtime.App.keypressed("s")
    check("kombat_reset_tab_only_resets_selected_device",Screen.bindings.keyboard.jump[1]=="space" and Screen.bindings.mouse.punch[1]==2)
    Screen.openControls();Runtime.App.keypressed("tab");Runtime.App.keypressed("down");Runtime.App.keypressed("down")
    Runtime.App.keypressed("down");Runtime.App.keypressed("delete");Runtime.App.keypressed("s")
    check("kombat_bindings_can_be_cleared",#Screen.bindings.mouse.punch==0)
    Screen.bindings=Controls.default();assert(Controls.assign(Screen.bindings,"keyboard","jump","v"))
    assert(Controls.assign(Screen.bindings,"mouse","punch",1));assert(Controls.assign(Screen.bindings,"mouse","block",3))
    assert(Controls.assign(Screen.bindings,"gamepad","kick","righty-"))
    Kombat.matches.front_left={leftId=1,rightId=2,mode="versus",phase="playing",
        left={character="mouse"},right={character="fox"}}
    Screen.view="fight"
    keys.v=true;Runtime.App.mousepressed(900,720,1);Runtime.App.mousepressed(900,720,3);controller.axes.righty=-.8
    local x,bits=Screen.controls(Runtime)
    check("kombat_actual_screen_combines_remapped_device_inputs",x==0 and bits==15)
    Runtime.App.mousereleased(900,720,1);x,bits=Screen.controls(Runtime)
    check("kombat_mouse_release_only_clears_its_button",bits==13)
    Runtime.App.mousereleased(900,720,3);keys.v=nil;controller.axes.righty=0
    local jumpRect=Controls.rect(Screen.bindings,"jump")
    Runtime.App.touchpressed("jump",(jumpRect[1]+10)*2,(jumpRect[2]+10)*2)
    Runtime.App.touchpressed("move",400,1276)
    x,bits=Screen.controls(Runtime)
    check("kombat_customized_touch_layout_still_supports_multitouch",x==1 and bits==1)
    keys.v=true;Runtime.App.focus(false);x,bits=Screen.controls(Runtime)
    check("kombat_focus_loss_clears_and_suspends_all_inputs",x==0 and bits==0 and not next(Screen.touches) and not next(Screen.mouse))
    Runtime.App.focus(true);x,bits=Screen.controls(Runtime)
    check("kombat_focus_resume_waits_for_held_key_release",x==0 and bits==0 and Screen.awaitNeutral)
    keys.v=nil;Screen.controls(Runtime);keys.v=true;x,bits=Screen.controls(Runtime)
    check("kombat_focus_resume_accepts_fresh_input",bits==1 and not Screen.awaitNeutral);keys.v=nil
    controller.axes.leftx=1;Runtime.controller:update(.1)
    check("kombat_controller_does_not_move_global_virtual_pointer",Runtime.controller.pointerX==480 and genericPresses==0)
    controller.axes.leftx=0;Screen.bindings.showTouch=false
    Runtime.App.touchpressed("hidden",1056,1276);x,bits=Screen.controls(Runtime)
    check("kombat_hidden_touch_buttons_do_not_capture_input",x==0 and bits==0)
    Screen.openControls();x,bits=Screen.controls(Runtime)
    check("kombat_controls_menu_never_generates_fight_input",x==0 and bits==0)
    Runtime.App.gamepadpressed(controller,"rightshoulder");Runtime.App.gamepadpressed(controller,"rightshoulder")
    Runtime.App.gamepadpressed(controller,"a");Runtime.App.focus(false);Runtime.App.gamepadaxis(controller,"rightx",1)
    check("kombat_background_controller_cannot_rebind",not Options.listening and Options.draft.gamepad.left[1]=="dpleft")
    Runtime.App.focus(true)
    Runtime.App.gamepadpressed(controller,"dpdown");Runtime.App.gamepadpressed(controller,"a");Runtime.App.gamepadpressed(controller,"leftstick")
    Runtime.App.gamepadpressed(controller,"start")
    check("kombat_controller_only_can_remap_and_save",Screen.view=="title" and Screen.bindings.gamepad.right[1]=="leftstick")
    bytes="return os.execute('untrusted')"
    check("kombat_invalid_controls_file_falls_back_safely",Controls.load().keyboard.jump[1]=="space")
    controller.connected=false
    check("kombat_disconnected_preferred_pad_is_dropped",Controls.findGamepad(controller)==nil)
    -- Restore native APIs before other suites run; the tests never touch actual saves.
    love.keyboard.isDown=oldDown;love.joystick.getJoysticks=oldPads
    love.filesystem.getInfo=oldInfo;love.filesystem.read=oldRead;love.filesystem.write=oldWrite
    Kombat.clear();Screen.bindings=Controls.default();Screen.view="title";Screen.pad=nil;Screen.cancelInputs(false)
    Screen.awaitNeutral=false
end
function Test.run(_,check) valueChecks(check);uiChecks(check) end
return Test
