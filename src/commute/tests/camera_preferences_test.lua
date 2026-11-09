local B=require('src.commute.bindings')
local Screen=require('src.commute.controls_screen')
local Settings=require('src.settings')
local Test={}
function Test.run(check)
    local defaults=B.defaults()
    check('camera_preferences_default_to_existing_fixed_angle',defaults.outsideCamera=='fixed'
        and B.normalize({}).outsideCamera=='fixed')
    check('camera_preferences_reject_unknown_mode',B.normalize({outsideCamera='sideways'}).outsideCamera=='fixed'
        and B.normalize({outsideCamera={}}).outsideCamera=='fixed')
    check('camera_preferences_expose_remappable_follow_toggle',B.action(defaults,'keyboard','o')=='followCamera'
        and B.action(defaults,'controller','leftshoulder')=='followCamera')
    local custom=B.defaults();custom.outsideCamera='follow';custom.keyboard.ignition='j'
    local encoded=B.encode(custom);local chunk=assert(loadstring('return '..encoded));setfenv(chunk,{})
    local decoded=B.normalize(chunk())
    check('camera_preferences_roundtrip_mode_with_custom_bindings',decoded.outsideCamera=='follow'
        and decoded.keyboard.ignition=='j' and decoded.keyboard.view=='p')
    local legacy=B.defaults();legacy.keyboard.ignition='o';legacy.keyboard.followCamera=nil
    local restored=B.normalize(legacy)
    check('camera_preferences_new_default_does_not_steal_existing_binding',restored.keyboard.ignition=='o'
        and restored.keyboard.followCamera=='')

    local oldFilesystem=love.filesystem;local saved
    local okay,reason=xpcall(function()
        love.filesystem={getInfo=function(path)return path=='settings.lua' and saved and {} or nil end,
            write=function(_,text)saved=text;return true end,read=function()return saved end}
        assert(Settings.save({masterVolume=37,motorcycleControls=custom}))
        local settings=Settings.load()
        check('camera_preferences_settings_save_load_retains_choice',settings.motorcycleControls.outsideCamera=='follow'
            and settings.motorcycleControls.keyboard.ignition=='j' and settings.masterVolume==37)
    end,debug.traceback)
    love.filesystem=oldFilesystem;if not okay then error(reason,0) end

    local settings={motorcycleControls=B.defaults()};local writes=0
    local screen=Screen.new(settings,function()writes=writes+1;return true end,function()end)
    screen:mousepressed(500,42,1)
    check('camera_preferences_header_selector_saves_follow',settings.motorcycleControls.outsideCamera=='follow'
        and writes==1 and screen.capture==nil and screen.message:find('Follow rider',1,true)~=nil)
    screen:keypressed('o')
    check('camera_preferences_keyboard_selector_returns_to_fixed',settings.motorcycleControls.outsideCamera=='fixed'
        and writes==2 and screen.message:find('Fixed angle',1,true)~=nil)
    screen:gamepadpressed(nil,'leftshoulder')
    check('camera_preferences_controller_selector_saves_follow',settings.motorcycleControls.outsideCamera=='follow'
        and writes==3 and screen.device=='keyboard' and screen.page==1)
    screen:gamepadpressed(nil,'rightshoulder')
    check('camera_preferences_controller_tab_navigation_unchanged',screen.device=='mouse'
        and settings.motorcycleControls.outsideCamera=='follow' and writes==3)
    screen.device='keyboard';screen.capture='ignition';screen:keypressed('o')
    check('camera_preferences_keyboard_capture_does_not_toggle_mode',settings.motorcycleControls.outsideCamera=='follow'
        and settings.motorcycleControls.keyboard.ignition=='o' and screen.capture==nil and writes==4)
    screen.device='controller';screen.capture='ignition';screen:gamepadpressed(nil,'leftshoulder')
    check('camera_preferences_controller_capture_does_not_toggle_mode',settings.motorcycleControls.outsideCamera=='follow'
        and settings.motorcycleControls.controller.ignition=='leftshoulder' and screen.capture==nil and writes==5)
    screen.device='touch';screen.layout=true;screen:mousepressed(500,42,1)
    check('camera_preferences_header_remains_available_during_touch_layout',settings.motorcycleControls.outsideCamera=='fixed'
        and writes==6 and screen.layout and not screen.drag)
    screen:toggleOutsideCamera();screen:mousepressed(100,610,1)
    check('camera_preferences_reset_all_restores_fixed_mode',settings.motorcycleControls.outsideCamera=='fixed'
        and settings.motorcycleControls.keyboard.followCamera=='o')
end
return Test
