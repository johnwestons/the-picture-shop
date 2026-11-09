-- Actual app callbacks and disk save/reload across the outdoor and home scenes.
local C=require('src.commute.runtime')
local Trip=require('src.commute.trip')
local Bike=require('src.commute.motorcycle')
local Calendar=require('src.business_calendar')
local Test={}
local function capture(R,name)
    local directory=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE');if not directory then return end
    local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
    love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true});R.App.draw();love.graphics.pop()
    local data=canvas:newImageData();local bytes=data:encode('png')
    local file=assert(io.open(directory..'/'..name..'.png','wb'));file:write(bytes:getString());file:close()
    bytes:release();data:release();canvas:release()
end
local function at(R,hours)
    R.state.calendar=Calendar.dateFromHours(hours)
    R.state.calendar.elapsed=hours%24/24*Calendar.secondsPerDay(R.state)
end
function Test.run(context,check)
    local R=assert(context.appRuntime)
    local mobileEnabled=R.mobileControls.enabled
    local oldFlush,oldSaveCurrent=R.Save.flush,R.saveCurrent
    local oldIsClient,oldIsHost=R.multiplayer.isClient,R.multiplayer.isHost
    local oldSound=R.App.sound
    R.mobileControls.enabled=true
    local finger=0
    local function tap(rect)
        assert(rect,'Expected a visible menu control')
        finger=finger+1
        R.syncCamera()
        local gx,gy=rect.x+rect.width*.5,rect.y+rect.height*.5
        if R.App.cameraTransformsUi() then gx,gy=R.App.mobileCamera:worldToScreen(gx,gy)end
        local ox,oy,s=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,R.App.officeUsesSafeArea())
        local x,y=ox+gx*s,oy+gy*s
        R.App.touchpressed('scene-exit-'..finger,x,y)
        R.App.touchreleased('scene-exit-'..finger,x,y)
    end
    local function options()
        local screen,bounds=R.optionsAccessLayout()
        tap(R.OptionsScreen.accessRect(screen,bounds))
        check('scene_exit_touch_opens_options_'..finger,R.state.screen=='options',
            ('from=%s to=%s scene=%s loadingAssets=%s'):format(tostring(screen),tostring(R.state.screen),
                tostring(R.World.player.sceneId),tostring(R.Assets.isLoading())))
    end
    local function menu()
        tap(R.OptionsScreen.menuRect())
    end
    local function fresh()
        R.Save.delete(3)
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden'})),'smoke'))
        R.state.screen='world'
    end
    local okay,reason=xpcall(function()
        fresh();at(R,44)
        -- Smoke starts before the normal audio bootstrap; exercise its real
        -- lifecycle here and restore it before bootstrap installs the app sound.
        if not R.App.sound then
            R.App.sound=require('src.sound').new({state=R.state,world=R.World,machine=R.Machine,
                wrapper=R.Wrapper,windmill=R.Windmill})
            R.App.sound:initialize();R.App.sound:setMuted(true)
        end
        local week=R.state.home.weekend
        week.phase='ready';week.closedAtHours=44;week.travelToken=91;week.readyMask=1
        assert(Trip.start(R.state,{R.World.player},91,C.world(R)))
        local part=C.localPart(R);C.syncPlayer(R.World.player,part)
        R._weekendPromptToken=91;R._weekendScene='commute'
        -- The menu must remain reachable before any exterior art is ready.
        R._commute.loading=true
        options()
        check('scene_exit_options_available_during_terrain_loading',R.state.screen=='options')
        R.App.keypressed('escape')
        check('scene_exit_escape_resumes_terrain_loading',R.state.screen=='world')
        require('src.commute.tests.loading_test_support').wait(R,check,'scene_exit_loading')
        part=C.localPart(R)
        part.rider.gear={version=1,outfit='geared',mounted=true,engine=true,revision=1}
        local bike=part.rider.bike;bike.speed=7;bike.gear=3;Bike.resetHorizontal(bike)
        local x,z=bike.x,bike.z;C.syncPlayer(R.World.player,part)
        R.App.sound:syncCommuteAudio(0)
        check('scene_exit_mounted_trip_starts_motorcycle_audio',R.App.sound.commuteAudio~=nil)
        capture(R,'riding-exit-header')
        options();R.OptionsScreen.openMotorcycleControls()
        capture(R,'riding-options-exit')
        menu()
        check('scene_exit_mobile_can_leave_from_motorcycle_controls',R.state.screen=='title' and R._commute==nil)
        local mountedSave=assert(R.Save.load(3))
        local savedBike=mountedSave.state.home.commute.participants.owner.rider.bike
        check('scene_exit_moving_trip_is_durably_saved_before_title',savedBike.x==x and savedBike.z==z
            and mountedSave.state.home.commute.participants.owner.rider.gear.mounted)
        local titleHours=Calendar.absoluteHours(R.state)
        local titleSaveBytes=love.filesystem.read('saves/slot3.lua')
        for _=1,60 do R.App.update(.05)end
        local titleBike=R.state.home.commute.participants.owner.rider.bike
        check('scene_exit_title_does_not_advance_trip_or_calendar',R.state.screen=='title'
            and titleBike.x==x and titleBike.z==z and Calendar.absoluteHours(R.state)==titleHours
            and love.filesystem.read('saves/slot3.lua')==titleSaveBytes)
        check('scene_exit_title_keeps_renderer_and_motorcycle_audio_released',R._commute==nil
            and R.App.sound and R.App.sound.commuteAudio==nil)
        assert(R.startGame(mountedSave,'smoke'));R.state.screen='world'
        part=C.localPart(R)
        check('scene_exit_moving_trip_resumes_parked_at_saved_position',R.World.player.sceneId=='commute'
            and part.rider.bike.x==x and part.rider.bike.z==z and part.rider.bike.speed==0
            and part.rider.bike.vx==0 and part.rider.bike.vz==0)
        require('src.commute.tests.loading_test_support').wait(R,check,'scene_exit_reload')
        assert(C.command(R,R.World.player,'dismount:'..R.state.home.commute.token))
        for _=1,30 do R.App.update(.05)end
        check('scene_exit_resume_allows_normal_dismount',not C.localPart(R).rider.gear.mounted)
        local footX,footZ=C.localPart(R).rider.ped.x,C.localPart(R).rider.ped.z
        capture(R,'dismounted-exit-header')
        R.App.keypressed('escape')
        check('scene_exit_escape_opens_riding_options',R.state.screen=='options')
        capture(R,'dismounted-options-exit');R.App.keypressed('escape')
        check('scene_exit_escape_resumes_dismounted_game',R.state.screen=='world')
        tap(require('src.screens.hud').exitRect(select(2,R.optionsAccessLayout())))
        local footSave=assert(R.Save.load(3))
        check('scene_exit_dismounted_trip_keeps_bike_and_walker_separate',R.state.screen=='title'
            and not footSave.state.home.commute.participants.owner.rider.gear.mounted
            and footSave.state.home.commute.participants.owner.rider.ped.x==footX
            and footSave.state.home.commute.participants.owner.rider.ped.z==footZ)

        fresh();at(R,50);R.state.home.weekend.phase='home';R.state.home.weekend.closedAtHours=44
        R.World.player.sceneId='home'
        R.World.player.x,R.World.player.y=require('src.home_layouts').spawn(R.state,1)
        local resident=R.state.home.residents.owner;resident.energy=47
        assert(require('src.home_residents').command(R.state,R.World.player,'rest:floor'))
        R.state.screen='home_activity'
        options();capture(R,'apartment-options-exit')
        R.Save.flush=function()return false end
        menu()
        check('scene_exit_save_failure_keeps_apartment_and_options_open',R.state.screen=='options'
            and R.state.optionsReturnScreen=='home_activity' and R.World.player.sceneId=='home'
            and R.state.home.residents.owner.activity~=nil)
        R.Save.flush=oldFlush
        menu()
        check('scene_exit_retry_can_return_to_menu_after_saving',R.state.screen=='title')
        local homeSave=assert(R.Save.load(3));local savedHours=Calendar.absoluteHours(homeSave.state)
        check('scene_exit_apartment_progress_is_flushed_to_disk',homeSave.player.sceneId=='home'
            and homeSave.state.home.residents.owner.energy==47 and homeSave.state.home.weekend.phase=='home')
        assert(R.startGame(homeSave,'smoke'));R.state.screen='world'
        check('scene_exit_apartment_reload_retains_progress_without_offline_simulation',R.World.player.sceneId=='home'
            and R.state.home.residents.owner.energy==47 and Calendar.absoluteHours(R.state)==savedHours
            and R.state.home.residents.owner.activity==nil)
        local homeX,homeY=R.World.player.x,R.World.player.y
        local Hud=require('src.screens.hud')
        local _,homeBounds=R.optionsAccessLayout()
        local header=Hud.exitRect(homeBounds)
        local headerReady=false
        for _=1,120 do
            R.App.update(0)
            R.App.draw()
            if Hud.hitTest(header.x+header.width*.5,header.y+header.height*.5)=='exit' then
                headerReady=true;break
            end
        end
        check('scene_exit_apartment_header_renders_after_reload',headerReady,
            ('screen=%s assetsLoading=%s hudVisible=%s'):format(tostring(R.state.screen),
                tostring(R.Assets.isLoading()),tostring(require('src.screens.hud_visibility').isVisible(R))))
        capture(R,'apartment-exit-header')
        tap(Hud.exitRect(select(2,R.optionsAccessLayout())))
        local headerHomeSave=assert(R.Save.load(3))
        check('scene_exit_apartment_header_returns_to_menu_and_saves_home',R.state.screen=='title'
            and headerHomeSave.player.sceneId=='home' and headerHomeSave.player.x==homeX
            and headerHomeSave.player.y==homeY and headerHomeSave.state.home.residents.owner.energy==47
            and Calendar.absoluteHours(headerHomeSave.state)==savedHours)
        assert(R.startGame(headerHomeSave,'smoke'));R.state.screen='world'
        -- Role is supplied by the real session layer; exercise the UI/exit branch
        -- here without opening any socket or creating another user's save.
        assert(R.saveCurrent(true))
        local before=love.filesystem.read('saves/slot3.lua');local writes=0
        R.multiplayer.isClient=function()return true end;R.multiplayer.isHost=function()return false end
        R.saveCurrent=function()writes=writes+1;return false end
        options();menu()
        check('scene_exit_client_leaves_without_writing_host_state',R.state.screen=='title' and writes==0
            and love.filesystem.read('saves/slot3.lua')==before)
    end,debug.traceback)
    R.Save.flush,R.saveCurrent=oldFlush,oldSaveCurrent
    R.multiplayer.isClient,R.multiplayer.isHost=oldIsClient,oldIsHost
    if R.App.sound~=oldSound then R.App.sound:shutdown();R.App.sound=oldSound end
    R.mobileControls:cancelAll();R.mobileControls.enabled=mobileEnabled
    if not okay then error(reason,0)end
end
return Test
