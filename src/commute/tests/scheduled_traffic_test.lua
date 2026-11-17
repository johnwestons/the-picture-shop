local State=require('src.state')
local Town=require('src.commute.town')
local Traffic=require('src.commute.delivery_traffic')
local Characters=require('src.commute.town_characters')
local Employees=require('src.commute.employee_commute')
local Visitors=require('src.commute.visitor_commute')
local Journey=require('src.commute.npc_journey')
local Calendar=require('src.business_calendar')
local Codec=require('src.net.codec')
local Motion=require('src.commute.scheduled_motion')
local Test={}
local limits={maxBytes=2000000,maxEntries=100000,maxDepth=64}
local function clone(value)return assert(Codec.decode(assert(Codec.encode(value,limits)),limits))end
local function entry(state,town,world,visitors,id)
    local hours=Calendar.absoluteHours(state)
    local groups={Characters.actors(state.home,town,hours,world),Employees.actors(state,town,hours,world),
        Visitors.actors(visitors,state,town,hours,world)}
    for _,group in ipairs(groups) do for _,e in ipairs(group) do if e.id==id then return e end end end
end
local function fixture(seed,daySeconds,kind,returning)
    local state=State.new();local town=assert(Town.generate(seed));local world=Town.world(town)
    state.home.town=town;state.home.townCharacters=nil
    state.calendar.secondsPerDay=daySeconds;state.calendar.elapsed=(returning and 18.4 or 7.4)*daySeconds/24
    local hours=Calendar.absoluteHours(state);local depart=hours-.4
    local id,journey,visitors
    if kind=='attendant' then
        state.home.townCharacters=Characters.defaultState(town);Characters.advance(state,hours)
        id='town-npc-mechanic';journey=state.home.townCharacters.people[1].journey
    elseif kind=='visitor' then
        visitors={customer={state='scheduled',visible=false,character='business-cat',timer=.6*daySeconds/24}}
        if returning then
            assert(Visitors.depart(state,'customer','business-cat',depart))
            id='visitor-customer-return';journey=state.home.visitorJourneys.returning.customer
        else
            Visitors.prepare(state,visitors,hours)
            id='visitor-customer';journey=state.home.visitorJourneys.incoming.customer
        end
    else
        local profile={residenceKind='town',residenceId='brick-walkup',workSiteId='warehouse',paintId='red',rosterId='cat'}
        journey=Employees.journey(profile,returning and 'commuting_home' or 'commuting_to_work',depart)
        local person={id='audit-rider',name='Audit rider',status=kind=='employee' and 'employed' or 'visiting',
            character='cat-worker',commuteProfile=profile,commuteState=journey}
        state.employment[kind=='employee' and 'staff' or 'applications']={person}
        id=kind..'-audit-rider'
    end
    return state,town,world,id,journey,visitors
end
local function case(check,seed,seconds,kind,returning,obstacleKind)
    local state,town,world,id,journey,visitors=fixture(seed,seconds,kind,returning)
    local now=1700000000;local dt=.05
    local function tick()
        state.calendar.elapsed=state.calendar.elapsed+dt
        if visitors then visitors.customer.timer=math.max(0,visitors.customer.timer-dt) end
        Traffic.simulate(state,town,dt,now,world,visitors);now=now+dt
    end
    tick()
    local initial=assert(entry(state,town,world,visitors,id),id)
    local j=initial.journey;local bike=j.motion.bike
    local blocker=require('src.commute.delivery_truck').new(bike.x+math.cos(bike.heading)*4.2,
        bike.z+math.sin(bike.heading)*4.2,bike.heading)
    state.home.commute={participants={},truck=blocker,aiMotorcycles={}}
    if obstacleKind then
        state.home.commute.truck=nil
        state.home.commute.participants.blocker={slot=2,rider=obstacleKind=='bike'
            and {gear={mounted=true},bike={x=blocker.x,z=blocker.z,h=blocker.h,heading=blocker.heading,speed=0}}
            or {gear={mounted=false},ped={x=blocker.x,z=blocker.z,h=blocker.h}}}
    end
    local suffix=seed..'_'..seconds..'_'..kind..(returning and '_return' or '_inbound')..(obstacleKind or '')
    local biggestStep,largestSpeedError,overlap=0,0,false
    for i=1,500 do
        local x,z=bike.x,bike.z
        tick();bike=j.motion.bike
        local moved=math.sqrt((bike.x-x)^2+(bike.z-z)^2)
        biggestStep=math.max(biggestStep,moved)
        largestSpeedError=math.max(largestSpeedError,math.abs(moved/dt-bike.speed))
        overlap=overlap or (obstacleKind and (bike.x-blocker.x)^2+(bike.z-blocker.z)^2<.9^2)
            or (not obstacleKind and require('src.commute.truck_footprint').overlaps(blocker.x,blocker.z,
                math.cos(blocker.heading),math.sin(blocker.heading),bike.x,bike.z,bike.x,bike.z,.42))
    end
    check('scheduled_rider_yields_without_ghosting_'..suffix,not overlap and Journey.pending(j),
        'pending='..tostring(Journey.pending(j))..' overlap='..tostring(overlap))
    check('scheduled_reported_speed_matches_displacement_'..suffix,largestSpeedError<.00001
        and biggestStep<=require('src.commute.motorcycle').MAX_SPEED*dt+.00001,largestSpeedError)
    local original=assert(Codec.encode(j,limits))
    for _=1,20 do entry(state,town,world,visitors,id) end
    check('scheduled_render_never_advances_host_progress_'..suffix,Codec.encode(j,limits)==original)
    local restored=clone(j)
    check('scheduled_saved_progress_is_valid_'..suffix,Motion.valid(restored.motion,restored.arriveAtHours-restored.departAtHours)
        and restored.motion.bike.x==bike.x and restored.motion.elapsed==j.motion.elapsed)
    if kind=='attendant' then
        Characters.advance(state,Calendar.absoluteHours(state))
        local normalized=Characters.normalize(clone(state.home.townCharacters),town,Calendar.absoluteHours(state))
        check('overdue_attendant_save_keeps_physical_journey_'..suffix,normalized.people[1].journey
            and normalized.people[1].journey.motion.bike.x==bike.x)
    elseif kind=='employee' then
        Employees.advance(state,Calendar.absoluteHours(state))
        check('overdue_employee_waits_for_physical_arrival_'..suffix,state.employment.staff[1].commuteState==j)
    elseif kind=='visitor' and not returning then
        visitors.customer.timer=0
        check('blocked_visitor_cannot_arrive_indoors_'..suffix,Visitors.holdArrival(state,'customer',visitors.customer,dt))
    end
    state.home.commute=nil
    -- Continue from the serialized progress, as a host would after reload.
    j.motion=restored.motion;bike=j.motion.bike
    for _=1,math.ceil(math.max(300,seconds/24*4)/dt) do
        local x,z=bike.x,bike.z
        tick();bike=j.motion.bike
        local moved=math.sqrt((bike.x-x)^2+(bike.z-z)^2)
        biggestStep=math.max(biggestStep,moved)
        largestSpeedError=math.max(largestSpeedError,math.abs(moved/dt-bike.speed))
        if not Journey.pending(j) then break end
    end
    check('scheduled_resume_never_catches_up_in_a_jump_'..suffix,largestSpeedError<.00001
        and biggestStep<=require('src.commute.motorcycle').MAX_SPEED*dt+.00001)
    check('scheduled_rider_resumes_and_completes_'..suffix,not Journey.pending(j),
        ('elapsed=%.4f target=%s pos=%.2f,%.2f'):format(j.motion.elapsed,tostring(j.motion.target),j.motion.bike.x,j.motion.bike.z))
    if Journey.pending(j) then
        local e=entry(state,town,world,visitors,id);local m=j.motion;j.motion=nil
        local target=Journey.sample(j,j.departAtHours+(m.target or m.elapsed),world,e.route,e.fromSlot,e.toSlot).bike
        j.motion=m
        local h=world:supportHeight(m.bike.x,m.bike.z)
        print('STALLED_TARGET',suffix,e.fromSlot,e.toSlot,target.x,target.z,
            world:sweepObstacles(m.bike.x,m.bike.z,target.x,target.z,.42,h,h+1.2))
    end
    world.vehicleObstacles=nil;world.sweepTrafficObstacles=nil;world.trafficActors=nil;world.trafficActorIndex=nil
end
function Test.lifecycle(check)
    local state=State.new();local visitors={customer={state='scheduled',character='business-cat',timer=0}}
    check('visitor_journey_creation_requests_save',Visitors.prepare(state,visitors,10))
    check('unchanged_visitor_journeys_do_not_request_save',not Visitors.prepare(state,visitors,10))
    check('legacy_visitor_at_door_can_enter_without_outdoor_initialization',not Visitors.holdArrival(state,'customer',visitors.customer,.1))
    check('bounded_visitor_journeys_pass_save_validation',Visitors.valid(clone(state.home.visitorJourneys)))
    visitors.customer.state='entering';visitors.customer.visible=true
    check('visitor_arrival_retires_saved_incoming_journey',Visitors.prepare(state,visitors,10)
        and state.home.visitorJourneys.incoming.customer==nil)
    local revision=state.home.revision
    check('visitor_departure_marks_saved_home_revision',Visitors.depart(state,'customer','business-cat',10)
        and state.home.revision==revision+1)
    local before=assert(Codec.encode(state.home.visitorJourneys,limits))
    local town=state.home.town;local world=Town.world(town)
    Visitors.actors(visitors,state,town,12,world)
    check('visitor_render_does_not_retire_return_journey',Codec.encode(state.home.visitorJourneys,limits)==before)
    check('host_retires_finished_legacy_visitor_return',Visitors.prepare(state,visitors,12)
        and state.home.visitorJourneys.returning.customer==nil)
end
local function frameRateArrival(check)
    local Bike=require('src.commute.motorcycle')
    for _,fps in ipairs({30,60,120}) do
        local dt=1/fps
        local world={trafficActors={},roads={sample=function()return 0,nil end,blocked=function()return false end},
            supportHeight=function()return 0 end}
        local journey={departAtHours=0,arriveAtHours=1}
        local actor={trafficId='rate-test',trafficKind='motorcycle',x=0,z=0,heading=0,speed=0}
        local function sample(_,at)
            return {stage='straight',bike={x=at*100,z=0,h=0,heading=0,speed=10,progress=at,parked=false}}
        end
        Motion.update(journey,0,dt,.1,world,{},nil,nil,actor,sample)
        local elapsed,maxStep,speedError=0,0,0
        while Motion.pending(journey) and elapsed<15 do
            local before=journey.motion.bike.x
            Motion.update(journey,elapsed*.1,dt,.1,world,{},nil,nil,actor,sample)
            local bike=journey.motion.bike;local moved=bike.x-before
            actor.x,actor.speed=bike.x,bike.speed
            maxStep=math.max(maxStep,moved);speedError=math.max(speedError,math.abs(moved/dt-bike.speed))
            elapsed=elapsed+dt
        end
        check('scheduled_rider_arrives_without_frame_rate_crawl_'..fps,not Motion.pending(journey)
            and math.abs(journey.motion.bike.x-100)<.00001 and elapsed<15,
            ('elapsed=%.3f position=%.3f'):format(elapsed,journey.motion.bike.x))
        check('scheduled_rider_reports_physical_speed_at_'..fps,maxStep<=Bike.MAX_SPEED*dt+.00001 and speedError<.00001)
    end
end
function Test.run(check)
    frameRateArrival(check)
    Test.lifecycle(check)
    for i,seed in ipairs({712345,712346,43127}) do
        for _,kind in ipairs({'attendant','employee','applicant','visitor'}) do
            case(check,seed,({300,1200,4800})[i],kind,false)
        end
    end
    for _,kind in ipairs({'attendant','employee','applicant','visitor'}) do case(check,712345,300,kind,true) end
    for _,obstacle in ipairs({'bike','pedestrian'}) do case(check,712345,300,'attendant',false,obstacle) end
    local state,town,world,id,j=fixture(712345,300,'attendant')
    local R=require('src.net.shop_replication')
    local before=R.copy(R.project(state))
    Traffic.simulate(state,town,.1,1700000000,world)
    local live=R.copy(R.project(state));local delta=R.diff(before,live)
    local guest=assert(R.apply(before,delta))
    local a=entry(state,town,world,nil,id);local b=entry(guest,town,world,nil,id)
    check('scheduled_host_progress_replicates_to_guest',a and b and a.actor.x==b.actor.x
        and a.actor.z==b.actor.z and a.actor.speed==b.actor.speed)
    local snapshot=require('src.save_schema').snapshot(state)
    check('scheduled_motion_survives_full_save_snapshot',snapshot and snapshot.home.townCharacters.people[1].journey
        and snapshot.home.townCharacters.people[1].journey.motion.bike.x==a.actor.x
        and require('src.save_schema').validState(snapshot))
    local bad=clone(j.motion);bad.bike.speed=1/0
    check('scheduled_save_validation_rejects_nonfinite_speed',not Motion.valid(bad,1))
    check('legacy_journeys_without_progress_remain_valid',Motion.valid(nil,1))
end
function Test.performance()
    local state,town,world=fixture(712345,300,'attendant')
    local homes={'brick-walkup','garden','courtyard','corner'}
    for i=1,8 do
        local profile={residenceKind='town',residenceId=homes[(i-1)%#homes+1],workSiteId='warehouse',paintId='red',rosterId='cat'}
        for _,kind in ipairs({'staff','applications'}) do
            local journey=Employees.journey(profile,'commuting_to_work',7+(i-1)*.035)
            state.employment[kind][i]={id=kind..i,name='Traffic stress rider',status=kind=='staff' and 'employed' or 'visiting',
                character='cat-worker',commuteProfile=profile,commuteState=journey}
        end
    end
    local visitors={customer={state='scheduled',character='business-cat',timer=7.5},
        vendor={state='scheduled',character='business-fox',timer=7.5}}
    local samples={};local R=require('src.net.shop_replication');local before
    for i=1,330 do
        state.calendar.elapsed=state.calendar.elapsed+1/60
        for _,v in pairs(visitors) do v.timer=math.max(0,v.timer-1/60) end
        local start=love.timer.getTime()
        Traffic.simulate(state,town,1/60,1700000000+i/60,world,visitors)
        if i>30 then samples[#samples+1]=(love.timer.getTime()-start)*1000 end
        if i==315 then before=R.copy(R.project(state)) end
    end
    table.sort(samples);local sum=0;for _,ms in ipairs(samples) do sum=sum+ms end
    local delta=assert(Codec.encode(R.diff(before,R.project(state)),limits))
    print(('SCHEDULED_PERFORMANCE actors=%d mean_ms=%.3f p95_ms=%.3f max_ms=%.3f quarter_second_delta_bytes=%d'):
        format(#Traffic.actors(state,town,Calendar.absoluteHours(state),1700000006,world,visitors),
            sum/#samples,samples[math.ceil(#samples*.95)],samples[#samples],#delta))
end
return Test
