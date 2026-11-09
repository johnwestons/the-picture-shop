-- Each observer owns a camera; network snapshots own the rider's physical pose.
local Art=require('src.commute.bike_art')
local View=require('src.commute.first_person_renderer')
local Camera=require('src.commute.camera')
local Trip=require('src.commute.trip')
local Rider=require('src.commute.rider')
local Codec=require('src.net.codec')
local C=require('src.commute.runtime')
local Test={}
local tau=math.pi*2
local world={size=512,height=function()return 0 end,supportHeight=function()return 0 end}
local function expected(heading,bearing,count)
    return math.floor(((heading-bearing)%tau)/(tau/count)+.5)%count+1
end
function Test.fixture()
    local gear={version=1,outfit='geared',mounted=true,engine=true,revision=0}
    return {version=Trip.VERSION,mapVersion=3,token=71,origin='warehouse',destination='garden',purpose='weekend',
        participants={owner={slot=1,arrived=false,rider=Rider.new(100,100,0,gear)},
            ['guest-1']={slot=2,arrived=false,rider=Rider.new(108,100,0,gear)}}}
end
function Test.run(check)
    local remote={x=108,z=100,heading=.37}
    local observer=Camera.new({x=100,z=100},world);observer.firstPerson=true;observer.viewHeading=0
    local coverage,legacy,bank=true,true,true
    for frame=1,64 do
        local bearing=remote.heading-(frame-1)*tau/64
        observer.centerX=remote.x-math.cos(bearing)*8;observer.centerZ=remote.z-math.sin(bearing)*8
        for _,look in ipairs({-.6,0,.6}) do
            observer.viewHeading=bearing+look
            local proxy=View.actorCamera(observer,remote,1)
            coverage=coverage and Art.frame(proxy,remote.heading,64)==frame
            if frame%8==1 then
                legacy=legacy and Art.frame(proxy,remote.heading,16)==expected(remote.heading,bearing,16)
                    and Art.frame(proxy,remote.heading,8)==expected(remote.heading,bearing,8)
            end
            bank=bank and math.abs(Art.bank(remote,proxy,.3)-.16*math.sin(remote.heading-bearing-math.pi*.5))<1e-9
        end
    end
    check('bike_multiplayer_all_64_facings_use_each_observers_position_independent_of_head_look',coverage)
    check('bike_multiplayer_parked_and_onfoot_views_use_the_same_observer_bearing',legacy)
    check('bike_multiplayer_lean_bank_uses_the_observer_bearing',bank)
    remote.heading=0;observer.centerX,observer.centerZ=100,100;observer.viewHeading=0
    local side={}
    for _,z in ipairs({97,100,103}) do
        remote.z=z;side[#side+1]=Art.frame(View.actorCamera(observer,remote,1),remote.heading,64)
    end
    check('bike_multiplayer_equal_heading_bikes_on_opposite_screen_sides_expose_different_views',
        side[1]~=side[2] and side[2]~=side[3] and side[2]==1)
    remote.z=100
    local back=Art.frame(View.actorCamera(observer,remote,1),0,64)
    local front=Art.frame(View.actorCamera(observer,remote,1),math.pi,64)
    observer.centerX,observer.centerZ=108,92
    local left=Art.frame(View.actorCamera(observer,remote,1),0,64)
    observer.centerZ=108
    local right=Art.frame(View.actorCamera(observer,remote,1),0,64)
    check('bike_multiplayer_back_front_and_physical_sides_match_observer_location',back==1 and front==33 and left==49 and right==17)
    observer.centerX,observer.centerZ=remote.x,remote.z;observer.viewHeading=.73
    local coincident=View.actorCamera(observer,remote,1)
    check('bike_multiplayer_coincident_positions_have_a_finite_deterministic_fallback',coincident.viewHeading==.73)
    check('bike_multiplayer_first_person_hides_only_the_local_participant_even_with_copied_actors',
        not View.shouldDrawActor({actor={},localPlayer=true},{})
        and View.shouldDrawActor({actor={},localPlayer=false},{})
        and not View.shouldDrawActor({actor=remote},remote))

    local trip=Test.fixture();local packet=assert(Codec.encode(Trip.snapshot(trip)))
    local clients={assert(Codec.decode(packet)),assert(Codec.decode(packet))}
    local cameras={Camera.new(trip.participants.owner.rider.bike,world),Camera.new(trip.participants['guest-1'].rider.bike,world)}
    local independent,untouched=true,true
    for _,a in ipairs({'fixed','follow','first'}) do for _,b in ipairs({'fixed','follow','first'}) do
        for index,mode in ipairs({a,b}) do
            local camera=cameras[index];local actor=trip.participants[index==1 and 'owner' or 'guest-1'].rider.bike
            camera:setFirstPerson(mode=='first',actor)
            if mode~='first' then camera:setOutsideMode(mode,actor,true) end
        end
        for index,client in ipairs(clients) do
            local part=client.participants[index==1 and 'guest-1' or 'owner'];local actor=part.rider.bike
            local camera=cameras[index]
            local proxy=camera.firstPerson and View.actorCamera(camera,actor,1) or camera
            local bearing=math.atan2(actor.z-camera.centerZ,actor.x-camera.centerX)
            local wanted=camera.firstPerson and expected(actor.heading,bearing,64)
                or math.floor((actor.heading+math.rad(camera.yaw)+math.pi*.5)/(tau/64)+.5)%64+1
            independent=independent and Art.frame(proxy,actor.heading,64)==wanted
        end
        untouched=untouched and assert(Codec.encode(Trip.snapshot(trip)))==packet
    end end
    check('bike_multiplayer_both_observers_keep_correct_views_for_all_nine_camera_mode_pairs',independent)
    check('bike_multiplayer_camera_switches_do_not_change_or_replicate_physical_heading_and_pose',untouched)
    local part=clients[1].participants['guest-1'];local physical=part.rider.bike
    local rendered=C.visualRider(part,{sceneId='commute',x=111,y=104,facing=-1,intentX=-1,intentY=0})
    observer.centerX,observer.centerZ=100,100;observer.viewHeading=0
    check('bike_multiplayer_smoothed_position_changes_view_bearing_without_replacing_bike_heading',
        rendered.bike.heading==physical.heading and rendered.bike.x==111 and rendered.bike.z==104
        and physical.x==108 and physical.z==100
        and Art.frame(View.actorCamera(observer,rendered.bike,1),rendered.bike.heading,64)==expected(physical.heading,math.atan2(4,11),64))
    local poses=require('src.commute.bike_action_pose');local A=require('src.commute.riding_animation')
    local retained=true
    for _,action in ipairs({'boost','shift'}) do
        local bike=trip.participants['guest-1'].rider.bike
        A.reset(bike);A.request(bike,action);A.update(bike,A.durations[action]/2)
        local received=assert(Codec.decode(assert(Codec.encode(Trip.snapshot(trip))))).participants['guest-1']
        retained=retained and poses.select(received.rider.bike,received.presentation)==action
    end
    local bike=trip.participants['guest-1'].rider.bike;A.reset(bike);bike.speed=8
    bike.ridingAnimation.brakingWeight=1;bike.lean=-.3;bike.paintId='red';bike.distance=25
    local received=assert(Codec.decode(assert(Codec.encode(Trip.snapshot(trip))))).participants['guest-1']
    check('bike_multiplayer_network_roundtrip_retains_actions_braking_lean_paint_and_tire_distance',
        retained and poses.select(received.rider.bike,received.presentation)=='brake'
        and received.presentation.lean==-.3 and received.rider.bike.paintId=='red' and received.presentation.distance==25)
    bike.reverse=true;bike.heading=0
    received=assert(Codec.decode(assert(Codec.encode(Trip.snapshot(trip))))).participants['guest-1']
    observer.centerX,observer.centerZ=100,100
    check('bike_multiplayer_reversing_never_flips_the_remote_bikes_physical_facing',
        received.rider.bike.reverse==true
        and Art.frame(View.actorCamera(observer,received.rider.bike,1),received.rider.bike.heading,64)==1)
end
return Test
