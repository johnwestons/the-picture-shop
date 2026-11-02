local C=require('src.commute.runtime')
local Trip=require('src.commute.trip')
local Rider=require('src.commute.rider')
local Gear=require('src.commute.gear')
local Weekend=require('src.weekend_runtime')
local Calendar=require('src.business_calendar')
local Routes=require('src.commute.routes')
local Bindings=require('src.commute.bindings')
local Test={}
local function at(state,hours)
    state.calendar=Calendar.dateFromHours(hours);state.calendar.elapsed=hours%24/24*Calendar.secondsPerDay(state)
end
local function capture(R,name)
    local directory=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE');if not directory then return end
    local canvas=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
    love.graphics.push('all');love.graphics.setCanvas(canvas);R.App.draw();love.graphics.pop()
    local data=canvas:newImageData();local bytes=data:encode('png')
    local file=assert(io.open(directory..'/'..name..'.png','wb'));file:write(bytes:getString());file:close()
    bytes:release();data:release();canvas:release()
end
function Test.run(context,check)
    local R=assert(context.appRuntime);assert(C.enabled(),'Commute runtime test requires PICTURE_SHOP_COMMUTE=1')
    R.Save.delete(3)
    assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden'})),'smoke'))
    R.state.screen='world'
    local originalMovement,originalDrive=R.Input.movement,Bindings.drive;local ix,iy=0,0
    R.Input.movement=function()return ix,iy end
    -- Walking and riding now read separate input adapters. Feed the same route
    -- driver into both, leaving semantic button dispatch under test below.
    Bindings.drive=function()return ix,iy,false end
    local function ticks(n) for _=1,n do R.App.update(.05) end end
    local function beginTrip()
        local target=require('src.home_travel').target(R.World.player,R.state)
        R.World.player.x,R.World.player.y=target.x,target.y
        assert(Weekend.command(R,R.World.player,'request'))
        local token=R.state.home.weekend.travelToken
        assert(Weekend.command(R,R.World.player,'depart:'..token))
        ticks(2);return token
    end
    at(R.state,44);R.state.home.weekend.phase='ready';R.state.home.weekend.closedAtHours=44
    R.World.truck.state='absent'
    R.World.player.furColorway=2;R.World.player.overallsColorway=3
    local token=beginTrip()
    check('commute_runtime_front_door_enters_lot_before_home_phase',R.World.player.sceneId=='commute'
        and R.state.home.weekend.phase=='ready' and not C.localPart(R).rider.gear.mounted)
    local appearance=C.localPart(R).appearance
    check('commute_runtime_normal_avatar_preserves_character_and_colors',appearance.character==R.World.player.character
        and appearance.furColorway==2 and appearance.overallsColorway==3)
    ticks(80);capture(R,'runtime-normal-lot')
    ix=1;ticks(8);capture(R,'runtime-normal-walk');ix=0;ticks(10)
    check('commute_runtime_unprotected_mount_rejected',not C.command(R,R.World.player,'mount:'..token))
    R.App.keypressed('g');ticks(80)
    check('commute_runtime_gear_sequence_reaches_geared_foot',C.localPart(R).rider.gear.outfit=='geared')
    capture(R,'runtime-geared-lot')
    R.App.keypressed('e');ticks(40)
    check('commute_runtime_mount_ignition_allows_riding',Gear.allowed(C.localPart(R).rider.gear,'ride'))
    R.App.keypressed('p');ticks(2)
    check('commute_runtime_keyboard_enters_first_person',R._commute.camera.firstPerson)
    ticks(100);capture(R,'runtime-first-person')
    R.App.gamepadpressed(nil,Bindings.byId.view.pad);ticks(2)
    check('commute_runtime_controller_returns_outside',not R._commute.camera.firstPerson)
    local vx,vy,vs=require('src.commute.cockpit').layout(R.Config.baseWidth,R.Config.baseHeight)
    assert(C.pointer(R,vx+625*vs,vy+278*vs));ticks(2)
    check('commute_runtime_touch_enters_first_person',R._commute.camera.firstPerson)
    assert(C.cameraPointerPressed(R,3,false));assert(C.cameraPointerMoved(R,-70,30));C.cameraPointerReleased(R,3);ticks(12)
    local lookX=require('src.commute.first_person_camera').cockpitPose(R._commute.camera)
    check('commute_runtime_middle_look_keeps_cockpit_on_bike',lookX< -100)
    assert(C.pointer(R,vx+650*vs,vy+224*vs));ticks(1)
    check('commute_runtime_center_button_faces_bike_forward',R._commute.camera.headYaw==0 and R._commute.camera.lookYaw==0)
    R.App.keypressed('p');ticks(2)
    R.App.keypressed('v');R.App.keypressed('x');ticks(5)
    check('commute_runtime_keyboard_changes_transmission',C.localPart(R).rider.bike.transmission=='manual' and C.localPart(R).rider.bike.gear==2)
    R.App.gamepadpressed(nil,Bindings.byId.shiftUp.pad);ticks(5)
    local shiftedUp=C.localPart(R).rider.bike.gear==3
    R.App.gamepadpressed(nil,Bindings.byId.shiftDown.pad);ticks(5)
    check('commute_runtime_controller_bindings_shift',shiftedUp and C.localPart(R).rider.bike.gear==2)
    capture(R,'runtime-cockpit-manual')
    assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
    check('commute_runtime_saved_scene_is_commute',saved.player.sceneId=='commute' and saved.state.home.commute~=nil)
    assert(R.startGame(saved,'smoke'));R.state.screen='world';ticks(2)
    check('commute_runtime_midride_reload_retains_trip_and_gear',R.World.player.sceneId=='commute'
        and Gear.allowed(C.localPart(R).rider.gear,'ride'))
    check('commute_runtime_save_retains_manual_transmission',C.localPart(R).rider.bike.transmission=='manual' and C.localPart(R).rider.bike.gear==2)
    check('commute_runtime_transmission_preference_saved_on_resident',R.state.home.residents.owner.ridingTransmission=='manual')
    local hx,hy,hs=require('src.commute.cockpit').layout(R.Config.baseWidth,R.Config.baseHeight)
    assert(C.pointer(R,hx+250*hs,hy+280*hs));ticks(20)
    check('commute_runtime_cockpit_button_selects_auto',C.localPart(R).rider.bike.transmission=='automatic' and C.localPart(R).rider.bike.gear==1)
    local function rideRoute(label)
        local t=R.state.home.commute;local world=C.world(R)
        local route=assert(Routes.new(world.roads):find(t.origin,t.destination))
        local destination=world.roads.destinations[t.destination];local index=1;local arrived=false;local bridgeCapture=false
        R.App.keypressed('p');ticks(2)
        check('commute_runtime_route_rider_view_'..label,R._commute.camera.firstPerson)
        for frame=1,9000 do
            local bike=C.localPart(R).rider.bike
            local distance=math.sqrt((bike.x-destination.x)^2+(bike.z-destination.z)^2)
            if distance<3 then ix,iy=0,1 else
                while index<#route.points and (bike.x-route.points[index].x)^2+(bike.z-route.points[index].z)^2<25 do index=index+1 end
                local target=route.points[index]
                local angle=math.atan2(target.z-bike.z,target.x-bike.x)
                local error=(angle-bike.heading+math.pi)%(2*math.pi)-math.pi
                ix=math.max(-1,math.min(1,error*2))
                iy=bike.speed<4 and -.8 or bike.speed>5 and .5 or 0
            end
            R.App.update(.05)
            if frame%500==0 then
                print(('COMMUTE ROUTE %s frame=%d position=%.1f,%.1f speed=%.2f remaining=%.1f'):format(
                    label,frame,bike.x,bike.z,bike.speed,distance));io.stdout:flush()
            end
            if not bridgeCapture and math.abs(bike.x-330)<1.5 and math.abs(bike.z-270)<2 then
                capture(R,'runtime-bridge-'..label);bridgeCapture=true
            end
            if distance<3 and bike.speed==0 then arrived=true;break end
        end
        ix,iy=0,0
        check('commute_runtime_physically_rides_entire_route_'..label,arrived)
        check('commute_runtime_rides_bridge_'..label,bridgeCapture)
        assert(arrived,'Route steering did not reach the lot')
        R.App.keypressed('e');ticks(25)
        check('commute_runtime_dismount_restores_outside_'..label,not R._commute.camera.firstPerson)
        check('commute_runtime_dismount_stays_suited_'..label,C.localPart(R).rider.gear.outfit=='geared' and not C.localPart(R).rider.gear.mounted)
        for _=1,200 do
            local ped=C.localPart(R).rider.ped
            local dx,dz=destination.x-ped.x,destination.z-3-ped.z;local d=math.sqrt(dx*dx+dz*dz)
            if d<.5 then break end
            ix,iy=dx/d,dz/d;R.App.update(.05)
        end
        ix,iy=0,0;ticks(12);R.App.keypressed('e');ticks(2)
        check('commute_runtime_destination_entry_finishes_trip_'..label,R.state.home.commute==nil)
    end
    rideRoute('home')
    check('commute_runtime_arrives_home_geared',R.World.player.sceneId=='home' and R.state.home.weekend.phase=='home'
        and R.state.home.residents.owner.ridingGear.outfit=='geared')
    local okay,code=require('src.home_residents').command(R.state,R.World.player,'eat:floor')
    check('commute_runtime_helmet_blocks_eating',not okay and code=='riding_gear')
    capture(R,'runtime-geared-home')
    R.App.keypressed('g');ticks(60)
    check('commute_runtime_explicit_indoor_removal_restores_normal_avatar',R.state.home.residents.owner.ridingGear.outfit=='normal'
        and R.World.player.character=='rabbit-worker')
    at(R.state,105);token=beginTrip();R.App.keypressed('g');ticks(80);R.App.keypressed('e');ticks(40)
    rideRoute('work')
    check('commute_runtime_returns_to_work_without_rewinding_calendar',R.World.player.sceneId=='warehouse'
        and R.state.home.weekend.phase=='working' and Calendar.absoluteHours(R.state)>=105)
    R.Input.movement=originalMovement
    Bindings.drive=originalDrive
    R.App.keypressed('g');ticks(60)
    R.state.activeSlot=nil
end
return Test
