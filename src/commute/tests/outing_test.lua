local State=require('src.state')
local Schema=require('src.save_schema')
local Flow=require('src.weekend_flow')
local Calendar=require('src.business_calendar')
local Travel=require('src.home_travel')
local Trip=require('src.commute.trip')
local Town=require('src.commute.town')
local Residents=require('src.home_residents')
local Rider=require('src.commute.rider')
local Test={}
local function at(state,hours)
    state.calendar=Calendar.dateFromHours(hours)
    state.calendar.elapsed=hours%24/24*Calendar.secondsPerDay(state)
end
function Test.run(check)
    local state=State.new();local world=Town.world(state.home.town)
    local host={id=1,homeResidentId='owner',sceneId='warehouse',character='rabbit-worker'}
    local guest={id=2,sceneId='warehouse',character='rabbit-worker'}
    local guestId=assert(Residents.bind(state,guest,string.rep('a',64),{host}))
    local players={host,guest}
    local context={world={truck={state='absent'}},commuteWorld=world,players=function()return players end}
    local function entrance(player)
        local target=assert(Travel.target(player,state));player.x,player.y=target.x,target.y
    end
    local function command(player,command) return Travel.command(state,player,command,context) end
    local function request()
        entrance(host);assert(command(host,'outing'))
        local token=state.home.weekend.travelToken
        assert(command(guest,'ready:'..token));assert(command(host,'depart:'..token));return token
    end
    local function park(part,id)
        local anchor=assert(Trip.parking(world,id,part.slot));local door=world.sites.byId[id].door
        part.rider=Rider.new(anchor.x,anchor.z,anchor.heading,{version=1,outfit='normal',mounted=false,engine=false,revision=0})
        part.rider.ped.x,part.rider.ped.z=door.x,door.z;Rider.update(part.rider,{},0,world)
    end
    local function enterDestination(token)
        local trip=state.home.commute
        for _,p in ipairs(players) do park(trip.participants[Residents.key(p)],trip.destination);assert(Trip.command(state,p,token,'arrive',world)) end
        local okay,event=Trip.finish(state,host,token,false);assert(okay,event)
        Travel.placeArrival(state,players,event.destination~='warehouse');return event
    end
    at(state,10);entrance(host);entrance(guest)
    local initialBalance=state.home.balanceCents;local initialHistory=#state.home.finance.history
    check('outing_guest_cannot_choose_household_departure',not command(guest,'outing'))
    host.x=0;host.y=0;check('outing_requires_actual_entrance',not command(host,'outing'));entrance(host)
    check('outing_weekday_weekend_request_still_rejected',not command(host,'request'))
    assert(command(host,'outing'));local token=state.home.weekend.travelToken
    check('outing_pending_request_is_durable_on_workday',Flow.valid(state.home.weekend)
        and Schema.validState(assert(Schema.snapshot(state))) and state.home.weekend.travelPurpose=='outing')
    check('outing_host_waits_for_guest_readiness',not command(host,'depart:'..token))
    check('outing_stale_ready_cannot_set_mask',not command(guest,'ready:'..(token+1)) and state.home.weekend.readyMask==1)
    assert(command(guest,'ready:'..token));assert(command(guest,'ready:'..token))
    check('outing_duplicate_ready_idempotent',state.home.weekend.readyMask==3)
    assert(command(host,'depart:'..token))
    check('outing_leaves_on_foot_without_shutdown_or_settlement',host.sceneId=='commute' and guest.sceneId=='commute'
        and state.home.commute.purpose=='outing' and state.home.weekend.phase=='working'
        and state.home.balanceCents==initialBalance and #state.home.finance.history==initialHistory)
    check('outing_depart_replay_cannot_replace_trip',not command(host,'depart:'..token) and state.home.commute.token==token)
    check('outing_calendar_advances_while_riding',Flow.limitCalendarStep(state,2)==2)
    local snapshot=assert(Schema.snapshot(state));state=snapshot
    state.home.commute=assert(Trip.restore(state.home.commute,world))
    check('outing_snapshot_restores_exact_purpose_and_town',Schema.validState(snapshot) and Trip.valid(state.home.commute,state.home)
        and state.home.commute.purpose=='outing' and state.home.commute.mapId==world.townId)
    local malformed=Schema.copy(state);malformed.home.commute.purpose='teleport'
    check('outing_unknown_purpose_rejected',not Schema.validState(malformed))
    malformed=Schema.copy(state);malformed.home.commute.destination='corner'
    if malformed.home.apartmentId=='corner' then malformed.home.commute.destination='garden' end
    check('outing_cannot_enter_unowned_apartment',not Trip.valid(malformed.home.commute,malformed.home))
    check('outing_cannot_enter_from_origin_or_guest_force',not Trip.command(state,host,token,'arrive',world)
        and not Trip.finish(state,guest,token,true))
    enterDestination(token)
    check('outing_weekday_apartment_arrival_keeps_working_calendar',Flow.atHome(state) and host.sceneId=='home'
        and state.home.weekend.phase=='working' and not Flow.shopClosed(state) and state.home.visit.scene=='home')
    check('outing_arrival_replay_rejected',not Trip.finish(state,host,token,false))
    snapshot=assert(Schema.snapshot(state));check('outing_home_visit_survives_schema_snapshot',Schema.validState(snapshot)
        and Flow.atHome(snapshot) and snapshot.home.visit.kind=='outing')
    malformed=Schema.copy(state);malformed.home.visit.scene='commute'
    check('outing_invalid_visit_scene_rejected',not Schema.validState(malformed))
    state.home.residents.owner.hunger=35;state.home.inventory.basic_meal=1
    assert(Residents.command(state,host,'eat:floor'))
    check('outing_home_activity_uses_actual_home_scene',not Residents.command(state,{id=2,homeResidentId=guestId,sceneId='warehouse',x=host.x,y=host.y},'eat:floor'))
    local first=Calendar.absoluteHours(state);Residents.advance(state,players,first,first+.3)
    check('outing_weekday_home_activity_completes',state.home.residents.owner.hunger>35 and not state.home.residents.owner.activity)
    assert(Residents.command(state,host,'sleepfloor:floor'));assert(Residents.command(state,guest,'sleepfloor:floor'))
    local dt,accelerated=require('src.home_sleep').calendarStep(state,players,1)
    check('outing_weekday_sleep_does_not_accelerate_shop',dt==1 and not accelerated)
    Residents.command(state,host,'cancel');Residents.command(state,guest,'cancel')
    token=request();check('outing_weekday_home_exit_available',state.home.commute.origin==state.home.apartmentId and state.home.commute.destination=='warehouse')
    enterDestination(token)
    check('outing_returns_to_warehouse_without_weekly_transition',not Flow.atHome(state) and host.sceneId=='warehouse'
        and state.home.weekend.transition==0 and state.home.visit==nil
        and state.home.balanceCents==initialBalance and #state.home.finance.history==initialHistory)
    token=request();local trip=state.home.commute
    check('outing_origin_return_checks_real_door',not Trip.cancel(state,host,token,world))
    for _,part in pairs(trip.participants) do park(part,trip.origin) end
    local okay,event=Trip.cancel(state,host,token,world);assert(okay,event);Travel.placeArrival(state,players,false)
    check('outing_can_return_through_actual_origin_door',state.home.commute==nil and not Flow.atHome(state) and host.sceneId=='warehouse')
    token=request();at(state,44-1/60)
    Calendar.update(state,Flow.limitCalendarStep(state,1000));Flow.update(state,false)
    check('outing_still_honors_real_friday_closing_boundary',Calendar.absoluteHours(state)==44 and state.home.weekend.phase=='closing')
    Flow.update(state,true);local settled=#state.home.finance.history
    check('outing_friday_settlement_once_and_clock_continues',settled==initialHistory+1 and Flow.limitCalendarStep(state,2)==2
        and not Flow.update(state,true) and #state.home.finance.history==settled)
    at(state,Flow.returnAtHours(state.home.weekend));Flow.update(state,false)
    check('outing_monday_reopens_without_owner_return',state.home.weekend.phase=='working' and state.home.weekend.closesAtHours==212
        and state.home.commute.token==token and Trip.valid(state.home.commute,state.home) and not Flow.shopClosed(state))
    -- A weekend home outing can return to the actual warehouse while the shop
    -- remains closed. Location must not be inferred from the weekly phase.
    state.home.commute=nil;state.home.weekend=Flow.new(44);state.home.weekend.phase='home';state.home.weekend.closedAtHours=44
    state.home.visit=nil;at(state,60);host.sceneId='home';guest.sceneId='home'
    token=request();enterDestination(token)
    snapshot=assert(Schema.snapshot(state))
    check('outing_weekend_warehouse_visit_overrides_weekly_home_phase',state.home.weekend.phase=='home' and Flow.shopClosed(state)
        and not Flow.atHome(state) and not Flow.atHome(snapshot) and Flow.limitCalendarStep(state,2)==2 and Schema.validState(snapshot))
    state.home.visit={kind='outing',scene='home'};host.sceneId='home';guest.sceneId='home'
    at(state,Flow.returnAtHours(state.home.weekend));entrance(host)
    assert(command(host,'request'));token=state.home.weekend.travelToken
    assert(command(guest,'ready:'..token));assert(command(host,'depart:'..token));Flow.update(state,false)
    check('outing_legacy_weekend_trip_takes_priority_over_previous_visit',state.home.commute.purpose=='weekend'
        and state.home.weekend.phase=='home' and Flow.limitCalendarStep(state,1)==0 and Trip.valid(state.home.commute,state.home))
    require('src.commute.tests.outing_session_test').run(check)
end
return Test
