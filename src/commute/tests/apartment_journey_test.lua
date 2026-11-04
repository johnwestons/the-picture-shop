-- Actual app journeys for every apartment. This supplements the detailed input
-- and multiplayer suites with physical road/parking/door coverage after scenery
-- changes. No rider or motorcycle is teleported during an exterior journey.
local Commute=require('src.commute.runtime')
local Gear=require('src.commute.gear')
local Rider=require('src.commute.rider')
local Routes=require('src.commute.routes')
local Bindings=require('src.commute.bindings')
local Calendar=require('src.business_calendar')
local Flow=require('src.weekend_flow')
local Weekend=require('src.weekend_runtime')
local Catalog=require('src.home_catalog')
local Layout=require('src.home_layouts')
local Town=require('src.commute.town')
local Test={}

local function at(state,hours)
    local seconds=Calendar.secondsPerDay(state)
    state.calendar=Calendar.dateFromHours(hours);state.calendar.secondsPerDay=seconds
    state.calendar.elapsed=hours%24/24*Calendar.secondsPerDay(state)
end

local function installInput(R)
    local originalMovement,originalDrive=R.Input.movement,Bindings.drive
    local input={walkX=0,walkZ=0,steer=0,drive=0}
    R.Input.movement=function()
        local camera=R._commute and R._commute.camera
        local yaw=math.rad(camera and camera.yaw or 0)
        -- The runtime converts screen movement back into world space.
        return input.walkX*math.cos(yaw)-input.walkZ*math.sin(yaw),
            input.walkX*math.sin(yaw)+input.walkZ*math.cos(yaw)
    end
    Bindings.drive=function() return input.steer,input.drive,false end
    function input.clear() input.walkX,input.walkZ,input.steer,input.drive=0,0,0,0 end
    function input.restore() R.Input.movement,Bindings.drive=originalMovement,originalDrive end
    return input
end

local function capture(R,name)
    local directory=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE')
    if not directory then return end
    local canvas=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
    love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true})
    R.App.draw();love.graphics.pop()
    local pixels=canvas:newImageData();local encoded=pixels:encode('png')
    local file=assert(io.open(directory..'/journey-'..name..'.png','wb'))
    file:write(encoded:getString());file:close()
    encoded:release();pixels:release();canvas:release()
end

local function scenario(R,input,id,check,town,outing)
    local function verify(name,okay,detail)
        check((outing and 'commute_outing_' or 'commute_apartment_')..id..'_'..name,okay,detail)
    end
    local function ticks(count)
        for _=1,count do R.App.update(.05) end
    end
    local function waitFor(predicate,limit,label)
        for _=1,limit do
            if predicate() then return true end
            R.App.update(.05)
        end
        assert(predicate(),id..': '..label)
        return true
    end
    local function part() return assert(Commute.localPart(R)) end
    local function reload(label,scene)
        input.clear()
        assert(R.saveCurrent(true))
        local saved=assert(R.Save.load(3))
        assert(R.startGame(saved,'smoke'))
        R.state.screen='world'
        if scene=='commute' then
            require('src.commute.tests.loading_test_support').wait(R,verify,label)
        else ticks(2)end
        verify(label..'_reload_keeps_scene_and_apartment',R.World.player.sceneId==scene
            and R.state.home.apartmentId==id and Town.fingerprint(R.state.home.town)==Town.fingerprint(town))
        return saved
    end
    local function beginTrip(destination,label)
        local target=assert(require('src.home_travel').target(R.World.player,R.state))
        -- Interior approach placement is separate from the exterior being tested.
        R.World.player.x,R.World.player.y=target.x,target.y
        if outing then
            R.state.screen='world'
            R.World.updateNetworkPlayer(0,0,0,R.Assets,R.state,target.hoverX,target.hoverY)
            local controls=require('src.home_travel_controls')
            assert(controls.keypressed('e',R) and R.state.screen=='home_travel','Town entrance did not open')
            assert(controls.keypressed('return',R))
        else assert(Weekend.command(R,R.World.player,'request')) end
        local token=assert(R.state.home.weekend.travelToken)
        if outing then assert(require('src.home_travel_controls').keypressed('return',R))
        else assert(Weekend.command(R,R.World.player,'depart:'..token)) end
        require('src.commute.tests.loading_test_support').wait(R,verify,label or destination)
        verify((label or destination)..'_starts_on_foot_in_origin_lot',R.World.player.sceneId=='commute'
            and R.state.home.commute.destination==destination and not part().rider.gear.mounted)
        return token
    end
    local function equipAndMount(token,label)
        verify(label..'_incomplete_gear_cannot_mount',not Commute.command(R,R.World.player,'mount:'..token))
        assert(Commute.command(R,R.World.player,'equip:'..token))
        waitFor(function() return part().rider.gear.outfit=='geared' and not part().rider.gear.transition end,
            160,'dressing did not complete')
        assert(Commute.command(R,R.World.player,'mount:'..token))
        waitFor(function() return Gear.allowed(part().rider.gear,'ride') end,100,'mount/ignition did not complete')
        verify(label..'_mount_starts_engine_only_after_dressing',part().rider.gear.engine and part().rider.gear.mounted)
    end
    local function journey(token,label)
        local trip=R.state.home.commute
        local destinationId=trip.destination
        local world=Commute.world(R)
        local destination=assert(world.roads.destinations[destinationId])
        local sites=assert(world.sites or world.roads.sites,'The exterior world must own its site registry')
        local site=assert(sites.byId[destinationId],'Missing exterior structure for '..destinationId)
        local Bays=require('src.commute.parking_bays')
        local parkX,parkZ=Bays.center(site,1)
        local door=assert(site.door,'Missing registered pedestrian door for '..destinationId)
        verify(label..'_registered_door_has_clear_footing',Rider.clear(world,door.x,door.z,Rider.RADIUS))
        local route=assert(Routes.new(world.roads):find(trip.origin,destinationId))
        local clock=Calendar.absoluteHours(R.state)
        local phase=R.state.home.weekend.phase
        local index,reloaded,stopped,parkingApproach,parkingBrake=1,false,false,false,false
        verify(label..'_mounted_door_entry_rejected',not Commute.command(R,R.World.player,'arrive:'..token))
        for frame=1,9000 do
            local bike=part().rider.bike
            local padDistance=math.sqrt((bike.x-destination.x)^2+(bike.z-destination.z)^2)
            local distance=math.sqrt((bike.x-parkX)^2+(bike.z-parkZ)^2)
            if padDistance<12 then parkingApproach=true end
            if parkingApproach then
                local heading=math.atan2(parkZ-bike.z,parkX-bike.x)
                local error=(heading-bike.heading+math.pi)%(2*math.pi)-math.pi
                input.steer=math.max(-1,math.min(1,error*2))
                if distance<1.8 then parkingBrake=true end
                if parkingBrake then
                    input.steer=0
                    input.drive=bike.speed>.45 and 1 or 0
                else input.drive=bike.speed>2.5 and .5 or -.45 end
            else
                while index<#route.points and (bike.x-route.points[index].x)^2+(bike.z-route.points[index].z)^2<25 do
                    index=index+1
                end
                local waypoint=route.points[index]
                local heading=math.atan2(waypoint.z-bike.z,waypoint.x-bike.x)
                local error=(heading-bike.heading+math.pi)%(2*math.pi)-math.pi
                input.steer=math.max(-1,math.min(1,error*2))
                input.drive=bike.speed<4 and -.8 or bike.speed>5 and .5 or 0
            end
            R.App.update(.05)
            if not reloaded and frame>=60 and bike.speed>1 then
                local x,z=bike.x,bike.z
                reload(label..'_midride','commute')
                local restored=part().rider
                verify(label..'_midride_reload_preserves_vehicle_and_gear',
                    math.abs(restored.bike.x-x)<.001 and math.abs(restored.bike.z-z)<.001
                    and restored.gear.outfit=='geared' and Gear.allowed(restored.gear,'ride'))
                world=Commute.world(R)
                reloaded=true
            end
            if distance<2.2 and part().rider.bike.speed==0
                and Bays.slotAt(site,bike.x,bike.z) then stopped=true;break end
        end
        input.clear()
        local finalBike=part().rider.bike
        local finalX,finalZ=site:toLocal(finalBike.x,finalBike.z)
        verify(label..'_physically_rides_route_and_parks',stopped and reloaded,
            string.format('remaining=%.2f speed=%.2f slot=%s local=(%.2f,%.2f)',
                math.sqrt((finalBike.x-parkX)^2+(finalBike.z-parkZ)^2),finalBike.speed,
                tostring(Bays.slotAt(site,finalBike.x,finalBike.z)),finalX,finalZ))
        assert(stopped,id..': '..label..' did not reach its parking area')
        waitFor(function()local b=part().rider.bike;return b.grounded and math.abs(b.vy or 0)<.08 end,
            120,'parked motorcycle did not settle')
        assert(Commute.command(R,R.World.player,'dismount:'..token))
        waitFor(function() return not part().rider.gear.mounted and not part().rider.gear.transition end,
            100,'dismount did not complete')
        local parkedX,parkedZ=part().rider.bike.x,part().rider.bike.z
        verify(label..'_dismount_keeps_suit_and_stops_engine',part().rider.gear.outfit=='geared'
            and not part().rider.gear.engine)
        local reached=false
        for _=1,400 do
            local ped=part().rider.ped
            local dx,dz=door.x-ped.x,door.z-ped.z
            local distance=math.sqrt(dx*dx+dz*dz)
            if distance<.4 then reached=true;break end
            input.walkX,input.walkZ=dx/distance,dz/distance
            R.App.update(.05)
        end
        input.clear();ticks(12)
        verify(label..'_walks_to_actual_structure_door',reached
            and part().rider.ped.speed<=.05
            and part().rider.bike.x==parkedX and part().rider.bike.z==parkedZ)
        verify(label..(outing and '_travel_advances_calendar_without_closing_shop' or '_travel_does_not_advance_calendar_or_week_phase'),
            (outing and Calendar.absoluteHours(R.state)>clock or not outing and math.abs(Calendar.absoluteHours(R.state)-clock)<.000001)
                and R.state.home.weekend.phase==phase)
        capture(R,id..'-'..label..'-door')
        local localX,localZ=site:toLocal(parkedX,parkedZ)
        verify(label..'_bike_inside_marked_stall',Bays.slotAt(site,parkedX,parkedZ)~=nil,
            string.format('local=(%.2f,%.2f) pad=(%.2f,%.2f)',localX,localZ,site.design.parking.x,site.design.parking.z))
        assert(Commute.command(R,R.World.player,'arrive:'..token))
        verify(label..'_door_commits_correct_interior_once',R.state.home.commute==nil
            and R.World.player.sceneId==(destinationId=='warehouse' and 'warehouse' or 'home')
            and R.state.home.weekend.phase==(outing and 'working' or destinationId=='warehouse' and 'working' or 'home'))
        verify(label..'_replayed_arrival_rejected',not Commute.command(R,R.World.player,'arrive:'..token))
    end

    input.clear();assert(R.Save.delete(3))
    assert(R.startGame(assert(R.Save.newGame(3,{apartmentId=id,town=town})),'smoke'))
    R.state.screen='world';R.state.employment.recruiting=false
    if outing then
        -- Keep the route away from a Friday boundary while retaining the real
        -- simulation clock, employee updates, save writer and scene adapter.
        R.state.calendar.secondsPerDay=3600;at(R.state,10)
    else
        local close=R.state.home.weekend.closesAtHours
        at(R.state,close)
        waitFor(function() return R.state.home.weekend.phase=='ready' end,100,'Friday shutdown did not finish')
        local frozen=Calendar.absoluteHours(R.state);ticks(20)
        verify('friday_shutdown_is_safe_and_clock_held',#require('src.shop_shutdown').checklist(R.state,R.World)==0
            and Calendar.absoluteHours(R.state)==frozen and #R.state.home.finance.history==1)
    end
    local history=#R.state.home.finance.history
    if outing then
        local originToken=beginTrip(id,'origin_return')
        local door=Commute.world(R).sites.byId.warehouse.door
        verify('origin_return_rejects_lot_shortcut',not Commute.command(R,R.World.player,'cancel:'..originToken))
        for _=1,300 do
            local ped=part().rider.ped;local dx,dz=door.x-ped.x,door.z-ped.z
            local distance=math.sqrt(dx*dx+dz*dz);if distance<.4 then break end
            input.walkX,input.walkZ=dx/distance,dz/distance;R.App.update(.05)
        end
        input.clear();ticks(12)
        assert(Commute.command(R,R.World.player,'cancel:'..originToken))
        verify('walk_back_through_warehouse_door_cancels_outing',R.World.player.sceneId=='warehouse'
            and not R.state.home.commute and R.state.home.weekend.phase=='working')
        reload('origin_return','warehouse')
    end
    local token=beginTrip(id)
    equipAndMount(token,'homeward');journey(token,'homeward')
    reload('indoors','home')
    verify('arrival_and_reload_retain_riding_gear',R.state.home.residents.owner.ridingGear.outfit=='geared')
    local okay,code=require('src.home_residents').command(R.state,R.World.player,'drink:sink')
    verify('helmet_blocks_household_activity',not okay and code=='riding_gear')
    assert(Commute.command(R,R.World.player,'remove'))
    waitFor(function() local gear=R.state.home.residents.owner.ridingGear
        return gear.outfit=='normal' and not gear.transition end,160,'indoor gear removal did not finish')
    local sink=Layout.get(R.state).fixtures.sink
    R.World.player.x,R.World.player.y=Layout.toWorld(unpack(sink.approach))
    R.state.home.residents.owner.thirst=20
    assert(require('src.home_activity_controls').command(R,R.World.player,'drink:sink'))
    waitFor(function() return not R.state.home.residents.owner.activity end,200,'home drinking did not complete')
    verify('explicit_removal_allows_real_apartment_routine',R.state.home.residents.owner.thirst>85)
    capture(R,id..'-interior')
    local homeDoor=require('src.home_travel').target(R.World.player,R.state)
    R.World.player.x,R.World.player.y=homeDoor.x,homeDoor.y
    if not outing then
        verify('return_before_monday_rejected',not Weekend.command(R,R.World.player,'request'))
        at(R.state,Flow.returnAtHours(R.state.home.weekend))
    end
    token=beginTrip('warehouse')
    equipAndMount(token,'workward');journey(token,'workward')
    verify(outing and 'weekday_roundtrip_does_not_create_friday_payment' or 'return_does_not_repeat_friday_payment',#R.state.home.finance.history==history)
    reload('returned_shop','warehouse')
    verify('returned_shop_retains_outfit_until_explicit_removal',R.state.home.residents.owner.ridingGear.outfit=='geared')
    assert(Commute.command(R,R.World.player,'remove'))
    waitFor(function() local gear=R.state.home.residents.owner.ridingGear
        return gear.outfit=='normal' and not gear.transition end,160,'shop gear removal did not finish')
end

function Test.run(context,check)
    if os.getenv('PICTURE_SHOP_TOUCH_LOADING')=='1' then
        return require('src.commute.tests.touch_loading_test').run(context,check)
    end
    if os.getenv('PICTURE_SHOP_LOADING_COAST')=='1' then
        return require('src.commute.tests.loading_coast_test').run(context,check)
    end
    local R=assert(context.appRuntime)
    assert(Commute.enabled(),'Apartment journeys require PICTURE_SHOP_COMMUTE=1')
    local town=assert(Town.generate(712345))
    local input=installInput(R)
    local okay,reason=xpcall(function()
        for _,id in ipairs(Catalog.ORDER) do scenario(R,input,id,check,town) end
    end,debug.traceback)
    input.clear();input.restore();R.state.activeSlot=nil
    if not okay then error(reason,0) end
end
function Test.runOuting(context,check)
    local R=assert(context.appRuntime);assert(Commute.enabled(),'Town outings require commute runtime')
    local town=assert(Town.generate(712345));local input=installInput(R)
    local okay,reason=xpcall(function() scenario(R,input,'garden',check,town,true) end,debug.traceback)
    input.clear();input.restore();R.state.activeSlot=nil
    if not okay then error(reason,0) end
end
return Test
