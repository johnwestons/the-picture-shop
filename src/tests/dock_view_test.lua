local Test={}
function Test.run(context,check)
    local Dock=require('src.dock_renderer')
    local Shutter=require('src.dock_shutter')
    local Exterior=require('src.dock_exterior')
    local State=require('src.state')
    local Calendar=require('src.business_calendar')
    local Config=require('src.config')
    local Characters=require('src.character_assets')
    local Loader=require('src.image_loader')
    local state=State.new();state.screen='world';local door=require('src.bay_door').new(Config.loadingBay)
    local seed=tonumber(os.getenv('PICTURE_SHOP_GAMEPLAY_SEED'))
    if seed then state.home.town=assert(require('src.commute.town').generate(seed))end
    local world={bayDoor=door,doorForScene=function()return door end,
        truck={isVisible=function()return false end,state='absent'}}
    local assets=context.assets or context.appRuntime.Assets
    local g=love.graphics;local enabled=Loader.enabled;Loader.setEnabled(false)
    local originalRender=Exterior.render;local observed
    Exterior.render=function(self,...)observed=self;return originalRender(self,...)end
    local canvas=require('src.tests.support.pixel_canvas')(960,678)
    local folder=os.getenv('PICTURE_SHOP_DOCK_PREVIEW_DIR')
    local players={}
    local function capture(name,target)
        if not folder then return end
        local previous={g.getCanvas()}
        g.setCanvas();local data=(target or canvas):newImageData();local bytes=data:encode('png')
        local file=assert(io.open(folder..'/'..name..'.png','wb'));file:write(bytes:getString());file:close()
        bytes:release();data:release();g.setCanvas({previous[1] or canvas,stencil=true})
    end
    local function draw()
        g.setShader();g.setColor(1,1,1,1);g.clear(.025,.035,.045,1,0)
        local background=assets.get('warehouse')
        g.draw(background,0,0,0,960/background:getWidth(),678/background:getHeight())
        Dock.draw(world,assets,Characters,state,players,nil,'warehouse',Config.truck.aperture)
    end
    Dock.clear();g.push('all');g.setCanvas({canvas,stencil=true})
    local okay,err=xpcall(function()
        for _=1,8 do draw()end
        check('dock_closed_does_not_allocate_or_prepare_exterior',Dock.stats()==nil)
        capture('door-closed')
        local points=Shutter.opening(Config.truck.aperture,.5)
        local x,y=Shutter.point(Config.truck.aperture,0,.5)
        check('dock_partial_opening_uses_registered_wall_plane',points[1]==x and points[2]==y)
        door.state,door.progress='opening',.42;draw();capture('door-partial')
        state.calendar.elapsed=12/24*Calendar.secondsPerDay(state)
        door.state,door.progress='open',1
        for _=1,600 do
            draw();love.timer.sleep(.002)
            if observed and observed.stage=='ready' and observed.stats.renders>2 then break end
        end
        local stats=assert(Dock.stats())
        check('dock_exterior_prepares_incrementally',stats.steps>=Exterior.ROWS and stats.rows==Exterior.ROWS,stats.rows)
        check('dock_exterior_uses_bounded_geometry',stats.vertices==Exterior.ROWS*Exterior.COLUMNS*6,stats.vertices)
        check('dock_exterior_renders_local_terrain',stats.renders>2,stats.renders)
        local sx,sz=observed:worldPoint(7,1.8)
        local vehicle={x=sx,z=sz,h=observed.world:supportHeight(sx,sz),heading=observed.site.yaw+.6,
            speed=0,model='box',phase='approaching',trafficId='dock-view-supplier'}
        state.jobs.active={{id='dock-view-supplier',company='Dock review',delivery={status='scheduled',route={vehicle=vehicle}}}}
        local px,pz=observed:worldPoint(3,-1.4)
        local rider=require('src.commute.rider').new(px,pz,observed.site.yaw,require('src.commute.gear').new())
        rider.bike.x,rider.bike.z=-100,-100
        state.home.commute={token=1,participants={guest={slot=2,rider=rider,appearance={character='rabbit-worker'}}}}
        players={{id=2,homeResidentId='guest',sceneId='commute',x=px,y=pz,intentX=1,intentY=0,
            velocityX=0,velocityY=0,animationDistance=0}}
        local entries=observed:collect(state,players,world.truck)
        check('dock_outdoor_player_and_truck_are_visible',#entries==2,#entries)
        vehicle.x,vehicle.z=observed:worldPoint(100,0)
        check('dock_distant_truck_is_culled_before_art_loading',#observed:collect(state,players,world.truck)==1)
        vehicle.x,vehicle.z=sx,sz
        world.truck.jobId='dock-view-supplier';world.truck.isVisible=function()return true end
        check('dock_detailed_cargo_proxy_does_not_duplicate_terrain_truck',#observed:collect(state,players,world.truck)==1)
        world.truck.isVisible=function()return false end
        players[1].sceneId='grocery'
        check('dock_indoor_guest_does_not_leave_a_pedestrian_ghost',#observed:collect(state,players,world.truck)==1)
        players[1].sceneId='commute'
        players[1]._visualVelocityX=2;players[1]._visualVelocityY=0
        players[1]._visualWalkDistance=1.2;players[1]._visualIntentX=0;players[1]._visualIntentY=1
        local pedestrian
        for _,entry in ipairs(observed:collect(state,players,world.truck))do
            if entry.id=='player:guest'then pedestrian=entry.actor end
        end
        check('dock_remote_walker_uses_realtime_motion_and_heading',pedestrian and pedestrian.speed==2
            and pedestrian.distance==1.2 and math.abs(pedestrian.heading-math.pi/2)<.00001
            and rider.ped.speed==0)
        Loader.setEnabled(true)
        for _=1,300 do Loader.update();draw();love.timer.sleep(.003)end
        check('dock_async_actor_art_reaches_small_resident_cache',observed.actorArt.bytes>0
            and observed.actorArt.bytes<=require('src.dock_actor_art').MAX_BYTES,observed.actorArt.bytes)
        check('dock_view_never_advances_vehicle_simulation',vehicle.x==sx and vehicle.z==sz and vehicle.speed==0)
        check('dock_view_retains_remote_character_art',observed.visibleCharacters['rabbit-worker']==true)
        rider.gear.outfit='geared'
        for _=1,100 do Loader.update();draw();love.timer.sleep(.003)end
        check('dock_geared_walker_keeps_the_correct_character_art',observed.visibleCharacters['suited-rider']==true)
        rider.gear.outfit='normal';observed.lastRender=-math.huge;draw()
        capture('door-open')
        if folder then
            local detail=require('src.tests.support.pixel_canvas')(640,640)
            g.push('all');g.setCanvas({detail,stencil=true});g.scale(4,4);g.translate(-24,-65)
            draw();capture('door-open-detail',detail)
            door.progress=0;draw();capture('door-closed-detail',detail)
            door.progress=.5;draw();capture('door-half-detail',detail)
            door.progress=1;g.pop();detail:release()
        end
        if folder and observed and observed.canvas then
            g.setCanvas();local data=observed.canvas:newImageData();local bytes=data:encode('png')
            local file=assert(io.open(folder..'/outside-buffer.png','wb'));file:write(bytes:getString());file:close()
            bytes:release();data:release();g.setCanvas({canvas,stencil=true})
        end
        -- Change the scene behind a stationary half-open shutter. Only the
        -- exposed gap may change; the raised steel and surrounding wall cannot.
        observed.lastRender=math.huge;door.progress=.5
        local function coloredExterior(r,b)
            g.setCanvas(observed.canvas);g.clear(r,0,b,1)
            g.setCanvas({canvas,stencil=true});draw();g.setCanvas()
            local data=canvas:newImageData();g.setCanvas({canvas,stencil=true});return data
        end
        local red,blue=coloredExterior(1,0),coloredExterior(0,1)
        local function delta(u,v)
            local x,y=Shutter.point(Config.truck.aperture,u,v);x,y=math.floor(x),math.floor(y)
            local ar,ag,ab=red:getPixel(x,y);local br,bg,bb=blue:getPixel(x,y)
            return math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)
        end
        check('dock_partial_shutter_occludes_the_real_exterior',delta(.5,.25)<.001 and delta(.5,.75)>1.8)
        red:release();blue:release();observed.lastRender=-math.huge;door.progress=1;draw()
        local daylight=require('src.outdoor_weather').sample(state)
        local noon=state.calendar.elapsed
        local dayPixels=observed.canvas:newImageData()
        state.calendar.elapsed=0;observed.lastRender=-math.huge;draw()
        local nightPixels=observed.canvas:newImageData()
        local dr,dg,db=dayPixels:getPixel(24,160);local nr,ng,nb=nightPixels:getPixel(24,160)
        check('dock_local_scene_follows_actual_daylight',daylight==1 and dr+dg+db>nr+ng+nb+.1)
        capture('door-night')
        dayPixels:release();nightPixels:release();state.calendar.elapsed=noon
        local savedDay=state.calendar.totalDays
        for day=0,30 do
            local weather=require('src.outdoor_weather').conditionsForDay(day)
            if weather.rain then
                state.calendar.totalDays=day
                state.calendar.elapsed=(weather.rainStart+.1)/24*Calendar.secondsPerDay(state)
                observed.lastRender=-math.huge
                local rainOkay,rainError=pcall(draw)
                check('dock_rain_uses_live_weather_without_an_extra_world_pass',rainOkay and stats.raining,rainError)
                capture('door-rain');break
            end
        end
        state.calendar.totalDays=savedDay;state.calendar.elapsed=noon
        observed.lastRender=-math.huge;draw()
        local beforeOffscreen=stats.renders
        g.push('all');g.translate(-3000,-3000);love.timer.sleep(.05);draw();g.pop()
        check('dock_offscreen_door_does_not_render_exterior',stats.renders==beforeOffscreen)
        local renders,steps=stats.renders,stats.steps
        door.state,door.progress='closed',0
        for _=1,12 do draw()end
        check('dock_closed_stops_all_exterior_render_and_preparation',stats.renders==renders and stats.steps==steps)
        door.state,door.progress='open',1;love.timer.sleep(.05);draw()
        check('dock_reopening_reuses_prepared_terrain',stats.rows==Exterior.ROWS and stats.renders>renders)
        local resumed=stats.renders
        Dock.selectScene('home',state)
        check('dock_leaving_warehouse_pauses_pending_asset_requests',next(observed.actorArt.pending)==nil)
        state.screen='computer';love.timer.sleep(.05);draw()
        check('dock_covered_view_does_not_render_behind_full_screen_ui',stats.renders==resumed)
        state.screen='world'
        state.home.town=require('src.save_schema').copy(state.home.town)
        love.timer.sleep(.05);draw()
        check('dock_same_town_snapshot_reuses_view_and_buffers',Dock.stats()==stats)
        state.warehouse.garageDoors={front_left={},front_right={}}
        world.truck.sceneId='warehouse'
        for _,room in ipairs({'front_left','front_right'})do
            local roomOkay,roomError=pcall(require('src.room_loading_bay_renderer').draw,
                world,assets,state,room,Characters,players)
            check('dock_purchased_room_uses_detailed_shutter_'..room,roomOkay,roomError)
        end
        for _,angle in ipairs({0,math.pi/3,math.pi})do
            local site=require('src.commute.sites').create({placements={{id='warehouse',design='warehouse',
                origin={x=100,z=200,h=4},yaw=angle,size={width=18,depth=7.8,height=6.75}}}}).byId.warehouse
            local probe=Exterior.new({id='geometry'},nil);probe.site=site;probe.dockX=site.localFoundation.maxX
            local x,z=probe:worldPoint(14,2)
            local ax,az=probe:worldPoint(0,2)
            check('dock_rotated_scaled_town_uses_real_metre_bounds_'..tostring(angle),
                math.abs(math.sqrt((x-ax)^2+(z-az)^2)-14)<.000001 and probe:inside({x=x,z=z}))
            x,z=probe:worldPoint(20,0)
            check('dock_rotated_town_keeps_far_clip_'..tostring(angle),not probe:inside({x=x,z=z}))
            local ax0,az0=probe:worldPoint(-30,0);local bx0,bz0=probe:worldPoint(40,0)
            check('dock_long_road_crossing_keeps_its_paint_'..tostring(angle),
                probe:crosses({x=ax0,z=az0},{x=bx0,z=bz0}))
            probe:release()
        end
        local R=context.appRuntime
        if R then
            local snapshot=R.World.bayDoor:snapshot()
            R.World.bayDoor.state,R.World.bayDoor.progress='open',1
            local nativeOkay,nativeError=pcall(R.App.draw)
            R.World.bayDoor:applySnapshot(snapshot)
            check('dock_full_runtime_draw_includes_exterior_without_losing_camera_state',nativeOkay,nativeError)
        end
        print(('DOCK_PROFILE renders=%d vertices=%d maxStepMs=%.3f maxRenderMs=%.3f'):format(
            stats.renders,stats.vertices,stats.maxStepMs,stats.maxRenderMs))
        local phases={};for phase,ms in pairs(stats.phaseMs)do phases[#phases+1]={phase,ms}end
        table.sort(phases,function(a,b)return a[2]>b[2]end)
        for index=1,math.min(5,#phases)do print(('DOCK_PREPARE %s %.3f'):format(phases[index][1],phases[index][2]))end
    end,debug.traceback)
    g.pop();canvas:release();Dock.clear();if not enabled then Loader.shutdown()end
    Loader.setEnabled(enabled);Exterior.render=originalRender
    assert(okay,err)
end
return Test
