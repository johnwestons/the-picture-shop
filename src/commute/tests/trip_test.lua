local Trip=require('src.commute.trip')
local Gear=require('src.commute.gear')
local Rider=require('src.commute.rider')
local Roads=require('src.commute.roads')
local Terrain=require('src.commute.terrain')
local State=require('src.state')
local Schema=require('src.save_schema')
local Flow=require('src.weekend_flow')
local Calendar=require('src.business_calendar')
local Residents=require('src.home_residents')
local Test={}
local function at(state,hours) state.calendar=Calendar.dateFromHours(hours);state.calendar.elapsed=hours%24/24*Calendar.secondsPerDay(state) end
local function request(state,token) state.home.weekend.travelToken=token;state.home.weekend.readyMask=3 end
local function readyAtDoor(part,anchor,world)
    part.rider=Rider.new(anchor.x,anchor.z,0,{version=1,outfit='geared',mounted=false,engine=false,revision=1})
    part.rider.ped.x,part.rider.ped.z=anchor.x,anchor.z-3;Rider.update(part.rider,{},0,world)
end
function Test.run(check)
    local world=Roads.new():attach(Terrain.new())
    local state=State.new();local host={id=1,homeResidentId='owner'};local guest={id=2,name='Rider'}
    state.home.residents.owner.ridingTransmission='manual'
    local credential=string.rep('a',64);local guestId=assert(Residents.bind(state,guest,credential,{host}))
    at(state,44);state.home.weekend.phase='ready';state.home.weekend.closedAtHours=44;request(state,12)
    check('commute_trip_rejects_stale_departure_token',not Trip.start(state,{host,guest},11,world))
    assert(Trip.start(state,{host,guest},12,world))
    check('commute_trip_uses_resident_transmission_preference',state.home.commute.participants.owner.rider.bike.transmission=='manual')
    require('src.home_travel').clearRequest(state.home.weekend)
    check('commute_trip_starts_outside_without_home_phase',state.home.weekend.phase=='ready' and state.home.commute.origin=='warehouse')
    local guestRider=state.home.commute.participants[guestId].rider
    guestRider.gear={version=1,outfit='geared',mounted=true,engine=true,revision=0}
    assert(Trip.command(state,guest,12,'reverse',world))
    assert(Trip.command(state,guest,12,'headlight',world))
    assert(Trip.command(state,guest,12,'ignition',world))
    check('guest_controls_only_own_bike',guestRider.bike.reverse and guestRider.bike.headlight and not guestRider.gear.engine
        and not state.home.commute.participants.owner.rider.bike.reverse)
    check('stale_controls_cannot_toggle_bike',not Trip.command(state,guest,11,'ignition',world) and not guestRider.gear.engine)
    local Animation=require('src.commute.riding_animation')
    local ownerBike=state.home.commute.participants.owner.rider.bike
    Animation.request(ownerBike,'boost');Animation.update(ownerBike,.2);Animation.request(ownerBike,'shift')
    local snapshot=assert(Schema.snapshot(state))
    local visual=snapshot.home.commute.participants.owner.presentation
    check('commute_trip_snapshot_replicates_sequenced_riding_pose',visual.ridingAction=='boost'
        and math.abs(visual.ridingActionTime-.58)<1e-7)
    local invalid=Schema.copy(snapshot.home.commute)
    invalid.participants.owner.presentation.ridingActionTime=999
    check('commute_trip_rejects_unbounded_riding_animation_time',not Trip.valid(invalid))
    local publicGuest=snapshot.home.commute.participants[guestId].rider
    check('public_snapshot_carries_direction_light_and_ignition',publicGuest.bike.reverse and publicGuest.bike.headlight and not publicGuest.gear.engine)
    check('commute_trip_real_schema_preserves_participants',Schema.validState(snapshot) and snapshot.home.commute.participants[guestId]~=nil)
    check('commute_trip_snapshot_preserves_detached_appearance',snapshot.home.commute.participants.owner.appearance.character=='rabbit-worker'
        and snapshot.home.commute.participants.owner.appearance~=state.home.commute.participants.owner.appearance)
    state.home.commute=assert(Trip.restore(snapshot.home.commute,world))
    check('commute_trip_restore_discards_stale_riding_animation',Animation.sample(state.home.commute.participants.owner.rider.bike)=='idle')
    check('commute_trip_clock_frozen_while_outbound',Flow.limitCalendarStep(state,100)==0)
    check('commute_trip_cannot_arrive_at_origin',not Trip.command(state,host,12,'arrive',world))
    local t=state.home.commute;local dest=world.roads.destinations[t.destination]
    readyAtDoor(t.participants.owner,dest,world)
    assert(Trip.command(state,host,12,'arrive',world))
    check('commute_trip_host_waits_for_other_riders',not Trip.finish(state,host,12,false) and state.home.weekend.phase=='ready')
    check('commute_trip_guest_cannot_commit_household',not Trip.finish(state,guest,12,true))
    readyAtDoor(t.participants[guestId],dest,world);assert(Trip.command(state,guest,12,'arrive',world))
    local okay,event=Trip.finish(state,host,12,false)
    check('commute_trip_home_arrival_exactly_once_with_suit',okay and event.destination==state.home.apartmentId
        and state.home.weekend.phase=='home' and state.home.commute==nil
        and state.home.residents.owner.ridingGear.outfit=='geared' and not Trip.finish(state,host,12,false))
    at(state,72);request(state,13)
    check('commute_trip_preserves_closed_sunday',not Trip.start(state,{host,guest},13,world))
    at(state,105);assert(Trip.start(state,{host,guest},13,world));require('src.home_travel').clearRequest(state.home.weekend)
    check('commute_trip_return_keeps_shop_closed_and_clock_frozen',Flow.shopClosed(state) and Flow.limitCalendarStep(state,100)==0
        and state.home.commute.destination=='warehouse' and state.home.weekend.phase=='home')
    t=state.home.commute;local p=t.participants.owner
    assert(Gear.begin(p.rider.gear,'mount',{nearBike=true}));Gear.update(p.rider.gear,2)
    check('commute_trip_mounted_player_cannot_enter_door',not Trip.command(state,host,13,'arrive',world))
    readyAtDoor(p,world.roads.destinations.warehouse,world);assert(Trip.command(state,host,13,'arrive',world))
    check('commute_trip_explicit_host_bring_everyone_retains_gear',Trip.finish(state,host,13,true)
        and state.home.residents[guestId].ridingGear.outfit=='geared' and state.home.weekend.phase=='working')
    -- Saved map versions recover at their safe origin with equipment retained.
    state.home.weekend.phase='ready';state.home.weekend.closedAtHours=212;request(state,14)
    assert(Trip.start(state,{host},14,world));local old=Trip.snapshot(state.home.commute);old.mapVersion=99
    local restored=assert(Trip.restore(old,world))
    check('commute_trip_map_change_recovers_parked_with_gear',restored.mapVersion==Roads.VERSION
        and not restored.participants.owner.rider.gear.mounted and restored.participants.owner.rider.gear.outfit=='geared')
    old.participants.owner.slot=2
    check('commute_trip_rejects_invalid_host_assignment',not Trip.valid(old))
end
return Test
