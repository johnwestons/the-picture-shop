-- Real travel UI: position, heading, building identification and input access.
local C=require('src.commute.runtime')
local Trip=require('src.commute.trip')
local Bike=require('src.commute.motorcycle')
local Bindings=require('src.commute.bindings')
local Calendar=require('src.business_calendar')
local Test={}
local function near(a,b)return math.abs(a-b)<.000001 end
local function draw(R,name)
    local canvas=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
    love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true})
    R.App.draw();love.graphics.pop()
    local directory=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE')
    if directory and name then
        local data=canvas:newImageData();local bytes=data:encode('png')
        local file=assert(io.open(directory..'/'..name..'.png','wb'))
        file:write(bytes:getString());file:close();bytes:release();data:release()
    end
    canvas:release()
end
function Test.run(context,check)
    local R=assert(context.appRuntime)
    local oldProfile=R.App.settings.motorcycleControls
    local oldMobile,oldMovement=R.mobileControls.enabled,R.Input.movement
    local map,originalDraw,observed
    local finger=0
    local function point(rect)
        assert(rect,'Expected an available map/menu button')
        R.syncCamera()
        local gx,gy=rect.x+rect.width*.5,rect.y+rect.height*.5
        if R.App.cameraTransformsUi() then gx,gy=R.App.mobileCamera:worldToScreen(gx,gy)end
        local ox,oy,s=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,R.App.officeUsesSafeArea())
        return ox+gx*s,oy+gy*s
    end
    local function tap(rect)
        local x,y=point(rect);finger=finger+1
        R.App.touchpressed('route-map-'..finger,x,y)
        R.App.touchreleased('route-map-'..finger,x,y)
    end
    local function click(rect)
        local x,y=point(rect)
        R.App.mousepressed(x,y,1,false);R.App.mousereleased(x,y,1,false)
    end
    local function ticks(n,dt)for _=1,n do R.App.update(dt or 1/60)end end
    R.App.settings.motorcycleControls=Bindings.defaults()
    R.mobileControls.enabled=true;R.Input.movement=function()return 0,0 end
    local okay,reason=xpcall(function()
        R.Save.delete(3)
        local town=assert(require('src.commute.town').generate(712345))
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden',town=town})),'smoke'))
        R.state.screen='world';R.state.calendar=Calendar.dateFromHours(44)
        R.state.calendar.elapsed=44%24/24*Calendar.secondsPerDay(R.state)
        local week=R.state.home.weekend
        week.phase='ready';week.closedAtHours=44;week.travelToken=97;week.readyMask=1
        assert(Trip.start(R.state,{R.World.player},97,C.world(R)))
        C.syncPlayer(R.World.player,C.localPart(R))
        R._weekendPromptToken=97;R._weekendScene='commute'
        require('src.commute.tests.loading_test_support').wait(R,check,'route_map_loading')
        local part=C.localPart(R);local rider=part.rider;local bike=rider.bike
        rider.gear={version=1,outfit='geared',mounted=true,engine=true,revision=1}
        bike.speed=0;Bike.resetHorizontal(bike);Bike.resetContact(bike,C.world(R))
        C.syncPlayer(R.World.player,part)
        R.App.keypressed('m')
        check('route_map_keyboard_opens_live_travel_map',R._commute.mapOpen==true)
        local firstDraw=love.timer.getTime()
        draw(R)
        print(('ROUTE_MAP_FIRST_DRAW_MS %.3f'):format((love.timer.getTime()-firstDraw)*1000))
        map=assert(R._commute.routeMap);originalDraw=map.draw
        map.draw=function(self,rect,actor,options)
            local result=originalDraw(self,rect,actor,options)
            observed={actor={x=actor.x,z=actor.z,heading=actor.heading},
                snapshot=self:snapshot(rect,actor,options),options=options}
            return result
        end
        draw(R,'travel-map-mounted')
        check('route_map_draw_uses_current_mounted_actor',observed and near(observed.actor.x,bike.x)
            and near(observed.actor.z,bike.z) and near(observed.actor.heading,bike.heading))
        local first=observed.snapshot.marker
        local names={}
        for _,building in ipairs(observed.snapshot.buildings)do names[building.id]=building.label end
        local allNamed=#observed.snapshot.buildings==#C.world(R).sites.all
        for _,site in ipairs(C.world(R).sites.all)do
            local destination=C.world(R).roads.destinations[site.id]
            allNamed=allNamed and type(names[site.id])=='string' and #names[site.id]>0
                and (not destination or names[site.id]==destination.label)
        end
        check('route_map_identifies_every_seeded_building',allNamed and #observed.snapshot.buildings>=16)
        check('route_map_includes_mechanic_grocery_civic_shops_and_apartments',
            names.mechanic and names.grocery and names['post-office'] and names.police
            and names['fire-station'] and names.diner and names['coffee-shop']
            and names['general-store'] and names.garden and names['residential-1'])
        local background,builds,samples=map.background,map.backgroundBuilds,map.terrainSamples
        local camera=R._commute.camera;camera.yaw=(camera.yaw+127)%360
        draw(R)
        check('route_map_north_up_marker_ignores_outside_camera_rotation',
            near(first.x,observed.snapshot.marker.x) and near(first.y,observed.snapshot.marker.y)
            and near(first.tipX,observed.snapshot.marker.tipX) and near(first.tipY,observed.snapshot.marker.tipY))
        local oldX,oldZ=bike.x,bike.z
        bike.speed=4;bike.gear=2;Bike.resetHorizontal(bike)
        ticks(15)
        draw(R)
        check('route_map_tracks_a_moving_bike_without_reopening',R._commute.mapOpen
            and math.abs(bike.x-oldX)+math.abs(bike.z-oldZ)>.05
            and near(observed.actor.x,bike.x) and near(observed.actor.z,bike.z)
            and math.abs(observed.snapshot.marker.x-first.x)+math.abs(observed.snapshot.marker.y-first.y)>.01)
        bike.speed=0;Bike.resetHorizontal(bike)
        local headings={0,-math.pi/2,math.pi/2,math.pi}
        local directions=true
        for _,heading in ipairs(headings)do
            bike.heading=heading;C.syncPlayer(R.World.player,part);draw(R)
            local marker=observed.snapshot.marker
            local dx,dy=marker.tipX-marker.x,marker.tipY-marker.y
            local length=math.sqrt(dx*dx+dy*dy)
            directions=directions and length>1 and near(dx/length,math.cos(heading))
                and near(dy/length,math.sin(heading))
        end
        check('route_map_heading_arrow_matches_cardinal_bike_headings',directions)
        check('route_map_movement_and_rotation_reuse_cached_terrain',background~=nil
            and map.background==background and map.backgroundBuilds==builds and map.terrainSamples==samples)
        R.App.keypressed('m')
        check('route_map_keyboard_closes_without_leaving_travel',not R._commute.mapOpen and R.state.screen=='world')
        local mini=C.miniMapRect(R);local level=map.miniLevel
        local target=C.activeWaypoint(R);local camera=R._commute.camera
        local zoom=camera.targetZoom
        tap(map.miniZoomButton(mini,1))
        check('mini_plus_touch_only_zooms_navigation',map.miniLevel==level+1 and not R._commute.mapOpen
            and camera.targetZoom==zoom and C.activeWaypoint(R)==target and C.touch(R).x==0)
        draw(R,'mini-map-zoomed')
        click(map.miniZoomButton(mini,-1))
        check('mini_minus_pointer_restores_scale_and_route',map.miniLevel==level and C.activeWaypoint(R)==target)
        local beforeWheel=map.miniLevel
        check('gps_wheel_changes_map_without_camera_zoom',C.mapWheel(R,mini.x+20,mini.y+20,1)
            and map.miniLevel==beforeWheel+1 and camera.targetZoom==zoom)
        check('gps_wheel_outside_map_is_not_consumed',not C.mapWheel(R,mini.x-10,mini.y,1))
        tap(map.miniFollowButton(mini))
        check('gps_auto_button_restores_navigation_follow',map.miniAuto and map.miniFollow and C.activeWaypoint(R)==target)
        draw(R,'gps-auto-mobile')
        R.mobileControls.enabled=false;draw(R,'gps-auto-desktop');R.mobileControls.enabled=true
        tap({x=mini.x+30,y=mini.y+60,width=30,height=30})
        check('gps_map_tap_opens_destinations_without_rerouting',R._commute.mapOpen and C.activeWaypoint(R)==target)
        tap(C.mapButton(R))
        click(C.mapButton(R))
        check('route_map_pc_button_opens_map',R._commute.mapOpen==true)
        tap(C.mapButton(R))
        check('route_map_touch_button_closes_map',not R._commute.mapOpen)
        tap(C.mapButton(R));R.App.keypressed('escape')
        check('route_map_escape_closes_map_before_opening_options',R.state.screen=='world' and not R._commute.mapOpen)
        -- Return to the known safe parking position for a real dismount, then
        -- walk away so a map that incorrectly tracks the parked bike will fail.
        local parking=assert(Trip.parking(C.world(R),'warehouse',1))
        bike.x,bike.z,bike.heading=parking.x,parking.z,parking.heading
        bike.speed=0;Bike.resetHorizontal(bike);Bike.resetContact(bike,C.world(R))
        C.syncPlayer(R.World.player,part)
        assert(C.command(R,R.World.player,'dismount:'..R.state.home.commute.token))
        ticks(35,.05)
        check('route_map_test_rider_dismounts',not rider.gear.mounted)
        R.Input.movement=function()return 1,0 end;ticks(60)
        R.Input.movement=function()return 0,0 end;ticks(8)
        tap(C.mapButton(R));draw(R,'travel-map-on-foot')
        check('route_map_on_foot_tracks_walker_instead_of_parked_bike',R._commute.mapOpen
            and math.abs(rider.ped.x-bike.x)+math.abs(rider.ped.z-bike.z)>.5
            and near(observed.actor.x,rider.ped.x) and near(observed.actor.z,rider.ped.z)
            and near(observed.actor.heading,rider.ped.heading))
        local screen,bounds=R.optionsAccessLayout()
        tap(R.OptionsScreen.accessRect(screen,bounds))
        check('route_map_global_options_remain_touch_accessible',R.state.screen=='options')
        R.App.keypressed('escape')
        check('route_map_options_resume_returns_to_travel',R.state.screen=='world' and C.localPart(R)~=nil)
        if not R._commute.mapOpen then tap(C.mapButton(R))end
        draw(R,'travel-map-seeded-town')
        tap(require('src.screens.hud').exitRect(select(2,R.optionsAccessLayout())))
        check('route_map_exit_releases_cached_map_with_travel_scene',R.state.screen=='title'
            and R._commute==nil and map.released==true and map.background==nil)
    end,debug.traceback)
    if map and originalDraw then map.draw=originalDraw end
    R.mobileControls:cancelAll();R.mobileControls.enabled=oldMobile
    R.Input.movement=oldMovement;R.App.settings.motorcycleControls=oldProfile
    if not okay then error(reason,0)end
end
return Test
