local Options=require('src.screens.options_screen')
local Settings=require('src.settings')
local Test={}
local function fixture(client)
    local events={};local mode=client and 'client' or 'host'
    local R={state={screen='options',activeSlot=1,optionsReturnScreen='world'},
        App={settings=Settings.normalize()},Save={SLOT_COUNT=3},Settings=Settings,
        OptionsScreen=Options,DirectIpv4Runtime={},CryptoNative={productionReady=false},
        TitleScreen={selected=1,enter=function()events[#events+1]='title'end},
        lanDiscovery={stop=function()events[#events+1]='discovery'end},
        lanReconnect={cancel=function()events[#events+1]='reconnect'end},
        multiplayer={isClient=function()return mode=='client'end,isHost=function()return mode=='host'end,
            stop=function()events[#events+1]='stop';mode='offline';return true end},
        clearWorkshopAuthority=function()events[#events+1]='authority'end,
        closeDirectConnection=function()events[#events+1]='connection';return true end,
        closeDirectHostComposite=function()events[#events+1]='host';return true end,
        DirectScreen={leave=function()events[#events+1]='leave'end},
        mobileControls={cancelAll=function()events[#events+1]='touch_cancel'end},
        controller={cancelAll=function()events[#events+1]='controller_cancel'end},
        isAndroidPlatform=function()return false end,
        syncMobileKeyboard=function()events[#events+1]='keyboard'end,
        saveCurrent=function(immediate)events[#events+1]=immediate and 'save_flush' or 'save_queue';return true end}
    R.enterDirectCleanupScreen=function(reason,retry)R.state.screen='direct';R.cleanupRetry=retry end
    require('src.runtime.direct_join').install(R)
    require('src.runtime.options').install(R)
    return R,events
end
local function has(events,value)for _,e in ipairs(events)do if e==value then return true end end;return false end
local function wideHeader(check)
    local config=require('src.config')
    local wide={left=-254,right=config.baseWidth+254}
    local r={state={screen='world',home={commute={participants={owner={}}}}},Config=config,
        App={mobileCamera={isEnabled=function()return true end}},World={player={sceneId='commute'}},
        Viewport={gameBounds=function()return wide end},mobileControls={isEnabled=function()return true end},
        _commute={renderer={}}}
    require('src.runtime.camera').install(r)
    local screen,bounds=r.optionsAccessLayout()
    local options=Options.accessRect(screen,bounds)
    local exit=require('src.screens.hud').exitRect(bounds)
    local map=require('src.commute.runtime').mapButton(r)
    local function fits(rect)return rect.x>=0 and rect.x+rect.width<=config.baseWidth end
    check('widescreen_commute_options_map_and_exit_fit_clipped_game_canvas',
        fits(options) and fits(map) and fits(exit) and Options.accessHit(options.x+2,options.y+2,screen,bounds)
        and require('src.screens.hud').exitHit(exit.x+2,exit.y+2,bounds))
    r.World.player.sceneId='home'
    local _,homeBounds=r.optionsAccessLayout()
    check('widescreen_apartment_toolbar_uses_expanded_camera_bounds',homeBounds==wide)
    r.App.mobileCamera.isEnabled=function()return false end
    check('widescreen_apartment_without_camera_keeps_toolbar_inside_canvas',select(2,r.optionsAccessLayout())==nil)
    r.Viewport.fullScreenDevice=function()return true end
    r.World.player.sceneId='grocery'
    local groceryScreen,groceryBounds=r.optionsAccessLayout()
    check('android_grocery_toolbar_stays_inside_letterboxed_canvas',groceryBounds==nil
        and fits(Options.accessRect(groceryScreen,groceryBounds))
        and fits(require('src.screens.hud').exitRect(groceryBounds)))
end
local function indoorOptionsTouch(context,check)
    local R=assert(context.appRuntime)
    local previousScreen,previousScene,previousCommute=R.state.screen,R.World.player.sceneId,R._commute
    local previousEnabled=R.mobileControls.enabled
    local cameraEnabled=R.App.mobileCamera:isEnabled()
    R.mobileControls.enabled=true;R.App.mobileCamera.enabled=false
    local function tap(id,x,y)
        local ox,oy,_,sx,sy=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight)
        R.App.touchpressed(id,ox+x*sx,oy+y*sy)
        R.App.touchreleased(id,ox+x*sx,oy+y*sy)
    end
    for _,kind in ipairs({'grocery','station'}) do
        R.World.player.sceneId=kind
        R._commute={mechanicOffer={interiorKind=kind,page=kind..'Floor'}}
        R.state.screen='options'
        Options.enter({settings=Settings.normalize(),save={SLOT_COUNT=3},state=R.state,
            onClose=function()R.state.screen='world'end})
        local audioTab=Options.tabRect('audio')
        tap('indoor-options-tab',audioTab.x+audioTab.width/2,112)
        check('mobile_'..kind..'_options_touch_changes_tab',Options.tab=='audio')
        tap('indoor-options-resume',868,41)
        check('mobile_'..kind..'_options_touch_resumes_world',R.state.screen=='world')
        R.mobileControls:cancelAll()
    end
    R.state.screen,R.World.player.sceneId,R._commute=previousScreen,previousScene,previousCommute
    R.mobileControls.enabled=previousEnabled;R.App.mobileCamera.enabled=cameraEnabled
end
function Test.run(context,check)
    indoorOptionsTouch(context,check)
    wideHeader(check)
    local R,events=fixture()
    local saved=0;R.saveCurrent=function(immediate)saved=saved+1;return false end
    local okay,reason=R.returnToTitle()
    check('menu_exit_save_failure_keeps_game_and_session',not okay and saved==1
        and R.state.screen=='options' and R.state.optionsReturnScreen=='world'
        and #events==0 and reason:find('could not be saved',1,true)~=nil)
    R,events=fixture();okay=R.returnToTitle()
    check('menu_exit_flushes_authoritative_save_before_network_cleanup',okay and events[1]=='save_flush'
        and events[2]=='discovery' and R.state.screen=='title' and has(events,'stop'))
    check('menu_exit_clears_return_screen_and_held_input',R.state.optionsReturnScreen==nil
        and has(events,'touch_cancel') and has(events,'controller_cancel') and has(events,'keyboard'))
    R,events=fixture(true);okay=R.returnToTitle()
    check('menu_exit_guest_does_not_write_host_state',okay and R.state.screen=='title'
        and not has(events,'save_flush') and not has(events,'save_queue'))
    R,events=fixture(true)
    local first=true;R.closeDirectConnection=function()if first then first=false;return false,'Retry cleanup' end;return true end
    local firstOkay=R.returnToTitle();local retry=R.cleanupRetry
    local retryOkay=retry and retry()
    check('menu_exit_guest_cleanup_retry_never_becomes_authoritative_save',not firstOkay and retryOkay
        and R.state.screen=='title' and not has(events,'save_flush') and not has(events,'save_queue'))
    R,events=fixture();first=true
    R.closeDirectHostComposite=function()if first then first=false;return false,'Retry host cleanup'end;return true end
    firstOkay=R.returnToTitle();retryOkay=R.cleanupRetry()
    local saves=0;for _,event in ipairs(events)do if event=='save_flush' then saves=saves+1 end end
    check('menu_exit_successful_flush_is_not_repeated_after_cleanup_failure',not firstOkay and retryOkay and saves==1)

    R,events=fixture();R.state.screen='world'
    local heldKey=false
    R.mobileControls=require('src.mobile_controls').new({enabled=true,
        toGame=function(x,y)return x,y end,
        pressKey=function()heldKey=true end,releaseKey=function()heldKey=false end,
        pressPointer=function()end,releasePointer=function()end,movePointer=function()end,
        gameplayActive=function()return R.state.screen=='world'end})
    local mobile=R.mobileControls
    mobile:touchpressed('stick',mobile.joystick.x+30,mobile.joystick.y)
    mobile:touchpressed('action',mobile.primary.x,mobile.primary.y)
    assert(mobile.axisX>0 and heldKey,'regression setup requires held gameplay touches')
    assert(R.openOptions());Options.openMotorcycleControls()
    -- The controls editor consumes the original fingers' release events.
    Options.keypressed('escape');Options.keypressed('escape')
    check('menu_exit_options_cancel_gameplay_touches_before_editor_consumes_releases',
        R.state.screen=='world' and mobile.axisX==0 and mobile.axisY==0
        and next(mobile.touches)==nil and not heldKey)

    R,events=fixture();R.state.screen='world';assert(R.openOptions())
    local rect=Options.menuRect()
    check('menu_exit_live_options_expose_save_menu_button',rect and rect.width>=180 and rect.height>=40
        and Options.menuLabel()=='SAVE & MAIN MENU' and R.state.optionsReturnScreen=='world')
    Options.mousepressed(rect.x+5,rect.y+5,1)
    check('menu_exit_pointer_action_returns_to_title',R.state.screen=='title' and has(events,'save_flush'))
    assert(R.openOptions())
    check('menu_exit_title_options_do_not_offer_save_exit_for_stale_slot',Options.menuRect()==nil)
    Options.keypressed('escape')
    check('menu_exit_title_options_back_returns_to_title',R.state.screen=='title')
    R,events=fixture(true);R.state.activeSlot=nil;R.state.screen='world';assert(R.openOptions())
    check('menu_exit_guest_options_expose_leave_session',Options.menuRect()~=nil and Options.menuLabel()=='LEAVE SESSION')
    assert(Options.gamepadpressed(nil,'y'))
    check('menu_exit_controller_leave_respects_guest_authority',R.state.screen=='title' and not has(events,'save_flush'))
    R,events=fixture();R.state.screen='world';assert(R.openOptions());Options.openMotorcycleControls()
    rect=Options.menuRect()
    check('menu_exit_motorcycle_controls_have_touch_exit_button',rect and rect.y==590 and rect.width>=180)
    Options.motorcycleEditor.capture='ignition'
    check('menu_exit_binding_capture_hides_global_exit_target',Options.menuRect()==nil)
    Options.keypressed('escape');Options.keypressed('f9')
    check('menu_exit_keyboard_action_works_after_binding_capture',R.state.screen=='title' and not Options.motorcycleEditor)
    R,events=fixture();R.state.screen='world';assert(R.openOptions())
    R.saveCurrent=function()return false end;rect=Options.menuRect();Options.mousepressed(rect.x+5,rect.y+5,1)
    check('menu_exit_options_show_failed_save_and_allow_retry',R.state.screen=='options'
        and Options.menuRect()~=nil and Options.message:find('could not be saved',1,true)~=nil)
    Options.mousepressed(850,40,1)
    check('menu_exit_resume_returns_to_previous_game_screen',R.state.screen=='world' and not has(events,'stop'))
end
return Test
