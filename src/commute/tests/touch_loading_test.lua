-- Exact App touch route from the Android cold-commute crash, plus pointer ownership.
local C=require('src.commute.runtime')
local Trip=require('src.commute.trip')
local Town=require('src.commute.town')
local Test={}
function Test.run(context,check)
    for _,name in ipairs({'terrain_mesh','terrain_renderer','touch_journey'})do
        require('src.commute.tests.'..name..'_test').run(check)
    end
    local R=assert(context.appRuntime)
    local oldEnabled=R.mobileControls.enabled
    local oldState,oldInteraction=R.World._state,R.World.interactionAt
    local selectors=0
    local function screen(x,y)
        local ox,oy,s=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,R.App.officeFitsScreen())
        return ox+x*s,oy+y*s
    end
    local function press(id,x,y)local sx,sy=screen(x,y);return R.App.touchpressed(id,sx,sy)end
    local function release(id,x,y)local sx,sy=screen(x,y);return R.App.touchreleased(id,sx,sy)end
    local function tap(id,x,y)local result=press(id,x,y);release(id,x,y);return result end
    local okay,reason=xpcall(function()
        assert(R.Save.delete(3))
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden',town=Town.legacy()})),'smoke'))
        local week=R.state.home.weekend
        week.phase='ready';week.closedAtHours=week.closesAtHours;week.travelToken=91;week.readyMask=1
        assert(Trip.start(R.state,{R.World.player},91,C.world(R)))
        C.syncPlayer(R.World.player,C.localPart(R))
        assert(R.saveCurrent(true));assert(R.startGame(assert(R.Save.load(3)),'smoke'))
        R.state.screen='world';R.mobileControls.enabled=true
        -- An exterior-only cold load has not needed the warehouse update cache.
        R.World._state=nil
        R.World.interactionAt=function(...)selectors=selectors+1;return oldInteraction(...)end
        R.App.update(0);R.App.update(0)
        check('touch_loading_fixture_is_partial_exterior_without_warehouse_state',R._commute.loading
            and R._commute.renderer and not R._commute.renderer:terrainReady() and R.World._state==nil)
        local x,y=R.Config.baseWidth*.5,R.Config.baseHeight*.32
        local safe,detail=pcall(tap,'blank',x,y)
        check('touch_loading_blank_app_touch_never_queries_warehouse',safe and selectors==0,detail)
        local touch=C.touch(R);local profile=C.bindings(R)
        for i=1,6 do local point=profile.layout['touch'..i]
            press('held'..i,point.x*R.Config.baseWidth,point.y*R.Config.baseHeight)
        end
        local point=profile.layout.stick
        press('stick',point.x*R.Config.baseWidth,point.y*R.Config.baseHeight)
        check('touch_loading_does_not_latch_driving_contacts',next(touch.contacts)==nil and next(touch.held)==nil
            and touch.x==0 and touch.y==0 and not R._commute.touchBoost and not C.localPart(R).rider.gear.transition)
        local oldRelease=R.OptionsScreen.mousereleased;local menuReleases=0
        R.OptionsScreen.mousereleased=function(...)menuReleases=menuReleases+1;return oldRelease(...)end
        R.state.screen='options';release('held1',x,y);R.state.screen='world';R.OptionsScreen.mousereleased=oldRelease
        check('touch_loading_release_cannot_activate_menu',menuReleases==0)
        local gear=C.localPart(R).rider.gear
        local outfit,mounted,engine=gear.outfit,gear.mounted,gear.engine
        gear.outfit,gear.mounted,gear.engine='geared',true,true
        local ox,oy,scale=require('src.commute.cockpit').layout(R.Config.baseWidth,R.Config.baseHeight)
        local bx,by=ox+90*scale,oy+278*scale
        local mx,my=screen(bx,by)
        R.App.mousepressed(mx,my,1,false);R.App.mousereleased(mx,my,1,false)
        check('touch_loading_mounted_mouse_cannot_latch_boost',not R._commute.touchBoost)
        gear.outfit,gear.mounted,gear.engine=outfit,mounted,engine
        local sx,sy=screen(x,y)
        R.App.mousepressed(sx,sy,1,true);R.App.mousereleased(sx,sy,1,true)
        check('touch_loading_synthetic_mouse_is_ignored',selectors==0 and R.state.screen=='world')
        local deadline=love.timer.getTime()+60
        while R._commute.loading do R.App.update(0);assert(love.timer.getTime()<deadline,'Terrain loading timed out')end
        for i=1,6 do local p=profile.layout['touch'..i];release('held'..i,p.x*R.Config.baseWidth,p.y*R.Config.baseHeight)end
        release('stick',point.x*R.Config.baseWidth,point.y*R.Config.baseHeight)
        check('touch_loading_release_after_reveal_has_no_stale_input',next(touch.contacts)==nil and next(touch.held)==nil
            and touch.x==0 and touch.y==0 and not R._commute.touchBoost)
        check('touch_ready_on_foot_blank_touch_is_scene_local',tap('ready',x,y) and selectors==0 and R.state.screen=='world')
        R.App.mousepressed(sx,sy,1,false);R.App.mousereleased(sx,sy,1,false)
        check('touch_ready_mouse_cannot_invoke_hidden_warehouse_controls',selectors==0 and R.state.screen=='world')
        local player=R.World.player;local oldX,oldY,oldScene=player.x,player.y,player.sceneId
        player.sceneId='warehouse';R.World._state=nil;R.World.selectedInteraction={kind='cutter',hovered=true}
        local empty=oldInteraction(100,100,false)
        check('world_pointer_without_bound_state_clears_selection',empty==nil and R.World.selectedInteraction==nil)
        R.World._state=R.state
        local door=R.World.bayDoor:getInteraction();player.x,player.y=door.x,door.y
        local ready=oldInteraction(door.hoverX or door.x,door.hoverY or door.y,false)
        check('world_pointer_with_bound_state_keeps_warehouse_targets',ready~=nil)
        player.x,player.y,player.sceneId=oldX,oldY,oldScene
        local button=assert(C.gearTouchButton(R))
        tap('gear',button.x+button.width/2,button.y+button.height/2)
        check('touch_ready_real_gear_button_still_dispatches',C.localPart(R).rider.gear.transition
            and C.localPart(R).rider.gear.transition.kind=='equip')
        for _=1,100 do R.App.update(.05)end
        local use=profile.layout.touch4
        tap('mount',use.x*R.Config.baseWidth,use.y*R.Config.baseHeight)
        for _=1,60 do R.App.update(.05)end
        check('touch_ready_actual_app_mount_is_available',C.localPart(R).rider.gear.mounted
            and C.localPart(R).rider.gear.engine and not C.localPart(R).rider.gear.transition)
        press('boost',bx,by)
        check('touch_ready_cockpit_boost_press_is_owned',R._commute.touchBoost==true)
        release('boost',bx,by)
        check('touch_ready_cockpit_boost_release_clears_hold',not R._commute.touchBoost and not R._commute.touchBoostSource)
        local access=R.OptionsScreen.accessRect(R.optionsAccessLayout())
        tap('options',access.x+access.width/2,access.y+access.height/2)
        check('touch_ready_global_options_access_remains_available',R.state.screen=='options')
        R.App.keypressed('escape')
        tap('dismount',use.x*R.Config.baseWidth,use.y*R.Config.baseHeight)
        for _=1,60 do R.App.update(.05)end
        check('touch_ready_actual_app_dismount_remains_available',not C.localPart(R).rider.gear.mounted
            and not C.localPart(R).rider.gear.engine)
        R.state.activeSlot=nil
    end,debug.traceback)
    R.mobileControls:cancelAll();R.mobileControls.enabled=oldEnabled
    R.World._state,R.World.interactionAt=oldState,oldInteraction
    if not okay then error(reason,0)end
end
return Test
