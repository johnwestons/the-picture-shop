local B=require('src.commute.bindings')
local Settings=require('src.settings')
local Touch=require('src.commute.touch_controls')
local Screen=require('src.commute.controls_screen')
local C=require('src.commute.runtime')
local Test={}
function Test.run(check)
    require('src.commute.tests.camera_preferences_test').run(check)
    local p=B.defaults()
    check('mapping_has_four_device_profiles',p.keyboard.accelerate=='w' and p.controller.accelerate=='axis:triggerright+' and p.mouse.orbit=='mouse3' and p.touch.accelerate=='touch1')
    local okay,message=B.assign(p,'keyboard','ignition','h')
    check('mapping_conflicts_swap_without_duplicates',okay and p.keyboard.ignition=='h' and p.keyboard.headlight=='i' and message:find('Swapped'))
    check('mapping_devices_are_independent',p.controller.ignition=='back' and p.touch.headlight=='touch5')
    check('mapping_reserved_menu_inputs_cannot_be_lost',not B.assign(p,'keyboard','ignition','escape') and not B.assign(p,'keyboard','ignition','f10') and not B.assign(p,'controller','ignition','start') and not B.assign(p,'mouse','ignition','mouse1'))
    check('mapping_axis_directions_are_validated',B.valid('controller','accelerate','axis:lefty-') and not B.valid('controller','accelerate','axis:bogus+') and not B.valid('keyboard','accelerate','notakey'))
    check('mapping_wheel_cannot_hold_throttle',not B.valid('mouse','accelerate','wheelup'))
    local malformed=B.normalize({keyboard={accelerate='notakey'},layout={stick={x=-100,y=100}},controller={brake='axis:bogus+'}})
    check('mapping_corrupt_preferences_recover',malformed.keyboard.accelerate=='w' and malformed.controller.brake=='axis:triggerleft+' and malformed.layout.stick.x==.10 and malformed.layout.stick.y==.90)
    local normalized=B.normalize(p)
    check('mapping_normalize_preserves_swaps',normalized.keyboard.ignition=='h' and normalized.keyboard.headlight=='i')
    local freeCamera={firstPerson=false,screenVectorToWorld=function(_,x,z)return x,z end}
    local directionalBike={heading=0,reverse=false}
    local steer,drive=B.drive(B.defaults(),{x=0,y=1},freeCamera,directionalBike)
    check('free_camera_directional_input_turns_before_applying_full_throttle',steer>.7 and drive<0 and drive>-.05)
    steer,drive=B.drive(B.defaults(),{x=-1,y=0},freeCamera,directionalBike)
    check('free_camera_opposite_direction_brakes_instead_of_powering_through_turn',steer<-.7 and drive==1)
    local rescueButton=false
    for _,button in ipairs(Touch.actionButtons(1280,880,B.defaults(),{mounted=true},{mobile=true})) do
        if button.action=='rescue' then rescueButton=button.label=='RESCUE' and button.enabled end
    end
    check('motorcycle_controls_expose_a_recovery_button_and_keyboard_binding',rescueButton and B.defaults().keyboard.rescue=='u')
    local oldInfo,oldRead,oldWrite=love.filesystem.getInfo,love.filesystem.read,love.filesystem.write
    local oldIdentity,oldSetIdentity=love.filesystem.getIdentity,love.filesystem.setIdentity
    local identity='the-picture-shop-motorcycle-preview'
    local stored
    local okaySave,saveError=pcall(function()
        love.filesystem.getInfo=function(path) return path=='settings.lua' and stored and {} or nil end
        love.filesystem.read=function()return stored end
        love.filesystem.write=function(_,value)stored=value;return true end
        love.filesystem.getIdentity=function()return identity end
        love.filesystem.setIdentity=function(value)identity=value;return true end
        local settings=Settings.normalize({masterVolume=37,motorcycleControls=p})
        assert(Settings.save(settings));local loaded=Settings.load()
        check('mapping_round_trips_with_unrelated_settings',loaded.masterVolume==37 and loaded.motorcycleControls.keyboard.ignition=='h' and loaded.motorcycleControls.controller.accelerate=='axis:triggerright+')
        check('mapping_preferences_do_not_enter_game_saves',not stored:find('activeSlot',1,true))
        check('mapping_preview_reads_shared_controls_and_restores_identity',Settings.sharedMotorcycle().keyboard.ignition=='h' and identity=='the-picture-shop-motorcycle-preview')
        local shared=B.defaults();shared.keyboard.ignition='j'
        check('mapping_preview_saves_shared_controls_without_other_changes',Settings.sharedMotorcycle(shared) and Settings.load().masterVolume==37
            and Settings.load().motorcycleControls.keyboard.ignition=='j' and identity=='the-picture-shop-motorcycle-preview')
        local Options=require('src.screens.options_screen')
        Options.enter({settings=settings,state={},save={SLOT_COUNT=3}})
        Options.mousepressed(475,114,1);Options.mousepressed(700,565,1)
        check('mapping_main_options_controls_entry_opens_panel',Options.motorcycleEditor~=nil)
        Options.mousepressed(600,470,1);Options.keypressed('k')
        check('mapping_main_options_panel_saves_binding',Settings.load().motorcycleControls.keyboard.ignition=='k')
        Options.keypressed('escape');check('mapping_main_panel_returns_to_options',Options.motorcycleEditor==nil)
    end)
    love.filesystem.getInfo,love.filesystem.read,love.filesystem.write=oldInfo,oldRead,oldWrite
    love.filesystem.getIdentity,love.filesystem.setIdentity=oldIdentity,oldSetIdentity
    assert(okaySave,saveError)

    local oldKeys,oldMouse,oldJoysticks=love.keyboard.isDown,love.mouse.isDown,love.joystick.getJoysticks
    local keys,mouse,buttons,axes={},{},{},{}
    local joy={isGamepad=function()return true end,getGamepadAxis=function(_,axis)return axes[axis] or 0 end,isGamepadDown=function(_,button)return buttons[button]==true end}
    local calls={}
    local inputOkay,inputError=pcall(function()
        love.keyboard.isDown=function(...)for i=1,select('#',...) do if keys[select(i,...)] then return true end end;return false end
        love.mouse.isDown=function(button)return mouse[button]==true end
        love.joystick.getJoysticks=function()return {joy} end
        p=B.defaults();assert(B.assign(p,'keyboard','accelerate','k'))
        keys.w=true;local x,y=B.drive(p);check('mapping_old_keyboard_key_no_longer_drives',y==0)
        keys.k=true;x,y=B.drive(p);check('mapping_custom_keyboard_throttle_drives',y==-1)
        keys={};axes.triggerright=.6;axes.leftx=-.6;x,y=B.drive(p)
        check('mapping_controller_preserves_analog_strength',math.abs(x+.5)<.001 and math.abs(y+.5)<.001)
        axes.leftx=.1;axes.triggerright=.1;x,y=B.drive(p);check('mapping_controller_deadzone_blocks_drift',x==0 and y==0)
        axes={};assert(B.assign(p,'mouse','accelerate','mouse5'));mouse[5]=true;x,y=B.drive(p)
        check('mapping_held_mouse_button_drives',y==-1);mouse={}
        local touch=Touch.new();local performed={};local boost
        local function perform(id)performed[#performed+1]=id end
        touch:press('go',p.layout.touch1.x*960,p.layout.touch1.y*678,960,678,p,perform)
        touch:press('boost',p.layout.touch3.x*960,p.layout.touch3.y*678,960,678,p,perform)
        x,y,boost=B.drive(p,touch);check('mapping_multitouch_holds_throttle_and_boost',y==-1 and boost)
        touch:release('go');x,y,boost=B.drive(p,touch);check('mapping_touch_release_is_per_finger',y==0 and boost)
        touch:press('steer',p.layout.stick.x*960,p.layout.stick.y*678,960,678,p,perform)
        touch:move('steer',p.layout.stick.x*960+80,p.layout.stick.y*678,960,678,p);x=B.drive(p,touch)
        check('mapping_touch_pad_steers',x==1)
        touch:press('use',p.layout.touch4.x*960,p.layout.touch4.y*678,960,678,p,perform)
        check('mapping_touch_action_is_semantic',performed[1]=='interact')
        touch:cancel();x,y,boost=B.drive(p,touch);check('mapping_touch_cancel_clears_all_held_controls',x==0 and y==0 and not boost)
        local r=require('src.commute.rider').new(100,100,0,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
        local R={App={settings={motorcycleControls=p}},Config={baseWidth=960,baseHeight=678},state={screen='world',home={commute={token=12,participants={owner={rider=r}}}}},World={player={id=1}},Input={movement=function()return 0,0 end},_commute={camera={}},openOptions=function()return true end}
        local request=C.request;C.request=function(_,command)calls[#calls+1]=command;return true end
        local routeOkay,routeError=pcall(function()
            assert(B.assign(p,'keyboard','ignition','j'))
            C.keypressed(R,'i');check('mapping_unbound_old_ignition_is_inert',#calls==0)
            C.keypressed(R,'j');check('mapping_keyboard_routes_semantic_command',calls[1]=='ignition:12')
            C.deviceInput(R,'controller','back');check('mapping_controller_routes_semantic_command',calls[2]=='ignition:12')
            assert(B.assign(p,'mouse','ignition','mouse4'));C.deviceInput(R,'mouse','mouse4')
            check('mapping_mouse_routes_semantic_command',calls[3]=='ignition:12')
            local ignition
            for _,button in ipairs(Touch.actionButtons(960,678,p,C.controlContext(R),{mobile=false})) do
                if button.action=='ignition' then ignition=button end
            end
            C.pointer(R,ignition.x,ignition.y,'mouse')
            check('mapping_shared_action_button_still_works_after_rebind',calls[4]=='ignition:12')
            assert(B.assign(p,'controller','ignition','axis:lefty+'))
            C.gamepadaxis(R,joy,'lefty',.8);C.gamepadaxis(R,joy,'lefty',.9)
            check('mapping_axis_oneshot_fires_once_per_crossing',#calls==5)
            C.gamepadaxis(R,joy,'lefty',0);C.gamepadaxis(R,joy,'lefty',.8)
            check('mapping_axis_rearms_after_release',#calls==6)
            keys.k=true;local _,throttle=C.localInput(R);check('mapping_main_riding_uses_custom_profile',throttle==-1)
        end)
        C.request=request;assert(routeOkay,routeError)
    end)
    love.keyboard.isDown,love.mouse.isDown,love.joystick.getJoysticks=oldKeys,oldMouse,oldJoysticks
    assert(inputOkay,inputError)

    local writes,closed=0,false
    local settings={motorcycleControls=B.defaults()}
    local screen=Screen.new(settings,function()writes=writes+1;return true end,function()closed=true end)
    screen.capture='ignition';screen:keypressed('j');check('mapping_ui_captures_keyboard_and_persists',settings.motorcycleControls.keyboard.ignition=='j' and writes==1)
    screen.device='mouse';screen.capture='ignition';screen:mousepressed(0,0,5)
    check('mapping_ui_captures_mouse',settings.motorcycleControls.mouse.ignition=='mouse5')
    screen.device='controller';screen.capture='accelerate';screen:gamepadaxis(joy,'lefty',.2)
    check('mapping_ui_ignores_controller_axis_drift',screen.capture=='accelerate')
    screen:gamepadaxis(joy,'lefty',-.8);check('mapping_ui_captures_signed_axis',settings.motorcycleControls.controller.accelerate=='axis:lefty-')
    screen.capture='ignition';screen:gamepadpressed(joy,'leftshoulder')
    check('mapping_ui_captures_controller_button',settings.motorcycleControls.controller.ignition=='leftshoulder')
    screen.device='touch';screen.capture='ignition';screen:mousepressed(150,555,1)
    check('mapping_ui_assigns_touch_button',settings.motorcycleControls.touch.ignition=='touch1')
    screen.layout=true;local point=settings.motorcycleControls.layout.stick
    screen:mousepressed(100+point.x*760,165+point.y*380,1);screen:mousemoved(300,300);screen:mousereleased()
    check('mapping_ui_persists_touch_positions',math.abs(settings.motorcycleControls.layout.stick.x-200/760)<.001)
    screen:mousepressed(100,610,1)
    check('mapping_ui_reset_restores_all_devices',settings.motorcycleControls.keyboard.ignition=='i' and settings.motorcycleControls.touch.accelerate=='touch1' and settings.motorcycleControls.layout.stick.x==.1)
    screen.capture='ignition';screen:keypressed('escape');check('mapping_ui_cancel_does_not_close_or_change_binding',not closed and not screen.capture and settings.motorcycleControls.keyboard.ignition=='i')
    screen:keypressed('escape');check('mapping_ui_has_unremappable_exit',closed)
end
return Test
