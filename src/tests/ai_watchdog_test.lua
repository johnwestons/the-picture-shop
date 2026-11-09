local Watchdog=require('src.ai_watchdog')
local Test={}

local function latest(snapshot)
    return snapshot.events[#snapshot.events]
end

function Test.run(_,check)
    local state={}
    local key={}
    local recoveries=0
    local didRecover=Watchdog.observe(state,key,{issueId='watchdog:progress',system='Test AI',
        subject='Test actor',stage='walking',dt=1,timeout=1,retryDelay=1,
        visible=false,x=40,y=50,recover=function()
            recoveries=recoveries+1
            return {ok=true,action='Moved actor to a safe test point'}
        end})
    local snapshot=Watchdog.snapshot(state)
    local recoveryEvent=latest(snapshot)
    check('watchdog_timeout_attempts_local_recovery_and_records_it',didRecover and recoveries==1
        and recoveryEvent and recoveryEvent.status=='RECOVERING'
        and recoveryEvent.action=='Moved actor to a safe test point'
        and #snapshot.active==1)

    Watchdog.observe(state,key,{issueId='watchdog:progress',system='Test AI',
        subject='Test actor',stage='walking',dt=.4,timeout=1,retryDelay=1,visible=false,
        recover=function() recoveries=recoveries+1;return {ok=true} end})
    local held=Watchdog.snapshot(state)
    check('watchdog_retry_delay_prevents_recovery_spam',recoveries==1 and #held.events==1)
    Watchdog.observe(state,key,{issueId='watchdog:progress',system='Test AI',
        subject='Test actor',stage='walking',dt=.6,timeout=1,retryDelay=1,visible=false,
        recover=function() recoveries=recoveries+1;return {ok=true} end})
    check('watchdog_retries_after_the_configured_cooldown',recoveries==2
        and latest(Watchdog.snapshot(state)).attempt==2)
    Watchdog.observe(state,key,{stage='walking',dt=.1,timeout=1,progressed=true,visible=false})
    snapshot=Watchdog.snapshot(state)
    local resolved=latest(snapshot)
    check('watchdog_clears_stalled_issue_when_progress_resumes',#snapshot.active==0
        and resolved and resolved.status=='RESOLVED' and resolved.visible==false)

    local errorState={}
    local operationOkay,operationError,recovered=Watchdog.protect(errorState,'watchdog:error-recovered',{
        system='Test AI',subject='Error fixture',stage='movement',scope='off-screen',x=10,z=20,
        visible=false},function()
        error('deliberate navigation failure')
    end,function(message)
        return {ok=message:find('deliberate navigation failure',1,true)~=nil,
            action='Applied a fixture recovery',detail='Reset route and retained task'}
    end)
    snapshot=Watchdog.snapshot(errorState)
    local caught=latest(snapshot)
    check('watchdog_catches_ai_error_and_records_successful_fallback',not operationOkay and recovered
        and operationError:find('deliberate navigation failure',1,true)~=nil
        and caught and caught.status=='RECOVERED' and caught.action=='Applied a fixture recovery'
        and caught.detail:find('Reset route and retained task',1,true)~=nil
        and caught.scope=='off-screen' and caught.visible==false and caught.x==10 and caught.z==20
        and #snapshot.active==0)

    local fallbackFailed,_,recoveredFromFailure=Watchdog.protect(errorState,'watchdog:error-unrecovered',{
        system='Test AI',subject='Failure fixture',stage='queue',visible=false},function()
        error('deliberate queue failure')
    end,function()
        error('deliberate recovery failure')
    end)
    snapshot=Watchdog.snapshot(errorState)
    local stalled=latest(snapshot)
    check('watchdog_records_unrecoverable_error_and_recovery_failure',not fallbackFailed
        and not recoveredFromFailure and stalled and stalled.status=='STALLED'
        and stalled.action=='Recovery callback failed'
        and stalled.detail:find('deliberate queue failure',1,true)~=nil
        and stalled.detail:find('deliberate recovery failure',1,true)~=nil
        and #snapshot.active==1)

    local success,first,second=Watchdog.protect(errorState,'watchdog:error-unrecovered',{
        system='Test AI',subject='Failure fixture',stage='queue'},function()
        return 'resumed',false
    end)
    snapshot=Watchdog.snapshot(errorState)
    check('watchdog_successful_retry_resolves_the_recorded_error',success and first=='resumed'
        and second==false and #snapshot.active==0 and latest(snapshot).status=='RESOLVED')

    local missingRecovery=Watchdog.protect(errorState,'watchdog:no-fallback',{
        system='Test AI',stage='waiting'},function()
        error('no local recovery')
    end)
    snapshot=Watchdog.snapshot(errorState)
    check('watchdog_keeps_unhandled_errors_visible_without_throwing_them_upward',
        missingRecovery==false and latest(snapshot).status=='STALLED'
        and latest(snapshot).action=='No automatic recovery configured' and #snapshot.active==1)

    local transitionState={}
    local transitionKey={}
    Watchdog.observe(transitionState,transitionKey,{issueId='watchdog:stage-a',stage='stage-a',
        dt=1,timeout=1,recover=function() return {ok=false,action='Still blocked'} end})
    Watchdog.observe(transitionState,transitionKey,{issueId='watchdog:stage-b',stage='stage-b',dt=.1,timeout=1})
    snapshot=Watchdog.snapshot(transitionState)
    check('watchdog_closes_old_issue_when_workflow_stage_changes',#snapshot.active==0
        and snapshot.events[2] and snapshot.events[2].status=='RESOLVED'
        and snapshot.events[2].issueId=='watchdog:stage-a')

    local boundedState={}
    for index=1,Watchdog.EVENT_LIMIT+9 do
        Watchdog.note(boundedState,'event:'..index,{reason='event '..index})
    end
    snapshot=Watchdog.snapshot(boundedState)
    snapshot.events[1].reason='mutated snapshot'
    local fresh=Watchdog.snapshot(boundedState)
    check('watchdog_event_history_is_bounded_and_snapshots_are_copies',
        #fresh.events==Watchdog.EVENT_LIMIT and fresh.events[1].sequence==10
        and fresh.events[#fresh.events].sequence==Watchdog.EVENT_LIMIT+9
        and fresh.events[1].reason=='event 10')
    check('watchdog_reset_clears_transient_diagnostics',Watchdog.reset(boundedState)
        and #Watchdog.snapshot(boundedState).events==0 and not Watchdog.reset(nil))

    -- Exercise the production employee movement boundary with one injected
    -- transient collision-query error. The safe-point recovery should let the
    -- game loop continue, while preserving the fault in the playtest report.
    local AI=require('src.employee_ai')
    local navigationState={}
    local actor={x=200,y=200,id='watchdog-worker',distance=0}
    local failOnce=true
    local context={state=navigationState,assets={getData=function() return nil end},
        obstacles=function()
            if failOnce then failOnce=false;error('fixture obstacle index failure') end
            return {}
        end}
    local reached,blocked=AI.move(actor,{x=400,y=200},.1,context)
    snapshot=Watchdog.snapshot(navigationState)
    local movementFault=latest(snapshot)
    local recoveredPosition=(actor.x-200)^2+(actor.y-200)^2
    check('watchdog_recovers_employee_navigation_error_at_actor_boundary',reached==false
        and blocked==true and recoveredPosition>0 and recoveredPosition<=40^2
        and movementFault and movementFault.status=='RECOVERED'
        and movementFault.reason=='AI operation raised an error'
        and movementFault.detail:find('fixture obstacle index failure',1,true)~=nil)
    local resumed=AI.move(actor,{x=400,y=200},.1,context)
    snapshot=Watchdog.snapshot(navigationState)
    check('employee_navigation_continues_after_watchdog_recovery',resumed==false
        and actor.x>200 and #snapshot.active==0)

    local Town=require('src.commute.town')
    local Routes=require('src.commute.routes')
    local Truck=require('src.commute.delivery_truck')
    local Traffic=require('src.commute.delivery_traffic')
    local town=assert(Town.generate(712345))
    local roadWorld=Town.world(town)
    local destinations={}
    for id in pairs(roadWorld.roads.destinations) do
        if id~='mainland_exit' then destinations[#destinations+1]=id end
    end
    table.sort(destinations)
    local route=destinations[2] and Routes.new(roadWorld.roads,{pavedOnly=true}):find(
        destinations[1],destinations[2])
    local roadState={}
    local roadFault=false
    if route and #route.points>=2 then
        local first,second=route.points[1],route.points[2]
        local vehicle=Truck.new(first.x,first.z,math.atan2(second.z-first.z,second.x-first.x),'plain')
        vehicle.h=roadWorld:supportHeight(vehicle.x,vehicle.z)
        vehicle.pathIndex=2;vehicle.trafficId='watchdog-road-error-fixture'
        local originalUpdate=Truck.update
        local injected=true
        Truck.update=function(...)
            if injected then injected=false;error('fixture truck controller failure') end
            return originalUpdate(...)
        end
        local callOkay=pcall(Traffic.driveRoute,vehicle,route.points,.1,roadWorld,
            'watchdog-fixture-route',roadState)
        Truck.update=originalUpdate
        local roadSnapshot=Watchdog.snapshot(roadState)
        local roadFaultEvent=latest(roadSnapshot)
        local rescuedPosition=(vehicle.x-first.x)^2+(vehicle.z-first.z)^2
        roadFault=callOkay and roadFaultEvent and roadFaultEvent.status=='RECOVERED'
            and roadFaultEvent.system=='Road traffic'
            and roadFaultEvent.detail:find('fixture truck controller failure',1,true)~=nil
            and rescuedPosition>0 and rescuedPosition<=80^2 and roadWorld.activeTruck==nil
        if roadFault then
            for _=1,10 do Traffic.driveRoute(vehicle,route.points,.1,roadWorld,
                'watchdog-fixture-route',roadState) end
            roadSnapshot=Watchdog.snapshot(roadState)
            roadFault=vehicle.distance>0 and #roadSnapshot.active==0
        end
    end
    check('watchdog_catches_and_recovers_delivery_vehicle_controller_error',roadFault,
        route and destinations[1]..' -> '..destinations[2] or 'no paved route fixture')
end

return Test
