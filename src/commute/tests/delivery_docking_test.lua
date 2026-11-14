local Town=require('src.commute.town')
local Network=require('src.commute.delivery_traffic')
local Truck=require('src.commute.delivery_truck')
local Trip=require('src.commute.trip')
local Watchdog=require('src.ai_watchdog')
local Test={}
local epoch=1700000000

local function fixture(seed)
    local town=assert(Town.generate(seed))
    local world=Town.world(town)
    local site=world.sites.byId.warehouse
    local a,b=world.truckAccess.entryPath[1],world.truckAccess.entryPath[2]
    local truck=Truck.new(b.x,b.z,math.atan2(b.z-a.z,b.x-a.x),'plain')
    truck.phase='approaching';truck.pathIndex=2;truck.h=world:supportHeight(truck.x,truck.z)
    local delivery={status='pending_arrival',route={roadTownId=town.id,
        departedAtEpoch=epoch,arrivedAtEpoch=epoch+300,vehicle=truck}}
    local box=assert(Trip.truckParking(world,{fuelLiters=60},'box'))
    local kei=assert(Trip.truckParking(world,{fuelLiters=60},'kei',box))
    local state={home={town=town,commute={participants={},truck=box,keiTruck=kei}},
        jobs={active={{id='DOCK-TEST',delivery=delivery}},completed={}}}
    return state,town,world,truck,delivery,site
end

local function run(state,town,world,truck,seconds,wanted)
    local collision,reverseDistance=false,0
    local trace={}
    for step=1,seconds*10 do
        local x,z=truck.x,truck.z
        Network.simulate(state,town,.1,epoch+step*.1,world)
        if truck.collisionContact and not collision then
            local lx,lz=world.sites.byId.warehouse:toLocal(truck.x,truck.z)
            trace[#trace+1]=('COLLISION t%.1f %.2f,%.2f'):format(step/10,lx,lz)
            collision=true
        end
        if truck.reverse then reverseDistance=reverseDistance+math.sqrt((truck.x-x)^2+(truck.z-z)^2) end
        if step%50==0 then
            local lx,lz=world.sites.byId.warehouse:toLocal(truck.x,truck.z)
            trace[#trace+1]=('t%d %.1f,%.1f h%.2f v%.2f %s i%d'):format(step/10,lx,lz,
                truck.heading-world.sites.byId.warehouse.yaw,truck.speed,truck.phase,truck.pathIndex or 0)
        end
        if truck.phase==wanted then
            return true,collision,reverseDistance,table.concat(trace,'; ')
        end
    end
    return false,collision,reverseDistance,table.concat(trace,'; ')
end

function Test.run(check)
    for _,seed in ipairs({712345,712346,43127}) do
        local state,town,world,truck,delivery,site=fixture(seed)
        local arrived,collision,reversed,trace=run(state,town,world,truck,100,'at_bay')
        check('delivery_backs_into_clear_dock_with_both_shop_trucks_parked_'..seed,
            arrived and not collision and reversed>5 and reversed<14,trace..' reverse='..reversed)
        check('delivery_rear_doors_align_with_dock_'..seed,
            math.abs(math.sin(truck.heading-site.yaw))<.02
                and (truck.x-site.truckParking.x)^2+(truck.z-site.truckParking.z)^2<.1)
        check('delivery_normal_docking_needs_no_watchdog_recovery_'..seed,#Watchdog.snapshot(state).events==0)
        delivery.status='received'
        delivery.returnRoute={departedAtEpoch=epoch,arrivedAtEpoch=epoch+1000,vehicle=truck}
        truck.phase='departing';truck.pathIndex=2;truck.pathTarget=nil
        local departed,hit,_,detail=run(state,town,world,truck,250,'offmap')
        check('delivery_leaves_dock_without_hitting_parked_fleet_'..seed,departed and not hit,detail)
    end

    local state,town,world,truck,delivery,site=fixture(712345)
    -- A kei at the dock must reserve it just like the box truck does.
    local kei=state.home.commute.keiTruck
    kei.x,kei.z,kei.heading=site.truckParking.x,site.truckParking.z,site.yaw
    local queued,hit,_,trace=run(state,town,world,truck,40,'waiting_bay')
    check('delivery_waits_upstream_when_kei_occupies_dock',queued and not hit,trace)
    local validation={}
    require('src.save_schema.primitives').install(validation)
    require('src.save_schema.paper').install(validation)
    check('delivery_queued_route_survives_save_validation',validation.delivery(delivery))
    local parked=assert(Trip.truckParking(world,{fuelLiters=60},'kei',state.home.commute.truck))
    local q=site.truckQueueWorldAnchors[2]
    local follower=Truck.new(q.x,q.z,site.yaw-math.pi*.5,'plain')
    follower.phase='waiting_bay';follower.pathTarget='waiting-2';follower.pathIndex=2
    state.jobs.active[2]={id='DOCK-FOLLOWER',delivery={status='pending_arrival',
        route={roadTownId=town.id,departedAtEpoch=epoch+.1,arrivedAtEpoch=epoch+300,vehicle=follower}}}
    kei.x,kei.z,kei.heading=parked.x,parked.z,parked.heading
    local resumed,collision,_,detail=run(state,town,world,truck,100,'at_bay')
    check('delivery_resumes_when_parked_truck_is_moved_away',resumed and not collision,detail)
    local advanced,queueCollision,_,queueTrace=run(state,town,world,follower,20,'waiting_bay')
    local front=site.truckQueueWorldAnchors[1]
    check('delivery_queue_advances_when_front_truck_takes_the_dock',advanced and not queueCollision
        and (follower.x-front.x)^2+(follower.z-front.z)^2<1,queueTrace)

    state,town,world,truck,delivery,site=fixture(712345)
    truck.x,truck.z=site:toWorld(0,0,0)
    truck.phase='waiting_bay';truck.pathTarget='waiting-2';truck.pathIndex=2
    Network.simulate(state,town,.1,epoch+.1,world)
    local misplaced=false
    for _,event in ipairs(Watchdog.snapshot(state).events) do
        if event.issueId=='delivery-park-position:DOCK-TEST'
            and event.reason=='Truck was marked parked away from its assigned dock or queue position' then
            misplaced=true
        end
    end
    check('delivery_watchdog_replans_truck_parked_off_its_assigned_stop',misplaced
        and truck.phase~='waiting_bay',truck.phase..'/'..tostring(truck.pathTarget))

    state,town,world,truck,delivery,site=fixture(712345)
    truck.x,truck.z=site:toWorld(0,0,0)
    truck.phase='waiting_bay';truck.pathTarget='waiting-2'
    local issueId='delivery-park-position:DOCK-TEST'
    Watchdog.note(state,issueId,{status='RECOVERING',system='Shop driveway',subject='DOCK-TEST',
        stage='rejoin_dock',reason='Test driveway report',action='Replan to assigned stop'})
    local panel=require('src.screens.ai_watchdog_panel')
    local selected=panel.unstickEvent(Watchdog.snapshot(state),state)
    local callOkay,operationOkay,result=pcall(Network.debugUnstick,state,issueId)
    check('watchdog_exposes_one_click_driveway_unstick_for_active_trucks',selected~=nil
        and panel.hitTest(120,580)=='unstick')
    check('watchdog_unstick_resets_parked_delivery_for_safe_replanning',callOkay and operationOkay
        and truck.phase=='approaching' and truck.replanRoute==true,tostring(result))

    state,town,world,truck,delivery,site=fixture(712345)
    -- Reproduce an obstruction halfway down the reversing aisle, away from
    -- the dock occupancy sensor. Monitor offscreen simulation as well.
    truck.x,truck.z=site:toWorld(20,0,0);truck.heading=site.yaw;truck.visible=false
    local box=state.home.commute.truck
    box.x,box.z=site:toWorld(13.5,0,0);box.heading=site.yaw
    run(state,town,world,truck,18,'at_bay')
    local snapshot=Watchdog.snapshot(state)
    check('delivery_watchdog_reports_blocked_reverse_while_offscreen',#snapshot.active>0
        and snapshot.active[1].system=='Delivery docking' and snapshot.active[1].detail~=nil)
    run(state,town,world,truck,12,'at_bay')
    local reset=false
    for _,event in ipairs(Watchdog.snapshot(state).events) do
        if event.action=='Reset to the clear dock approach and retried backing in' then reset=true end
    end
    check('delivery_watchdog_escalates_to_clear_dock_setup_without_skipping_delivery',reset
        and truck.phase~='at_bay' and delivery.status=='pending_arrival')
    local home=assert(Trip.truckParking(world,{fuelLiters=60},'box'))
    box.x,box.z,box.heading=home.x,home.z,home.heading
    local completed,_,_,resumeTrace=run(state,town,world,truck,30,'at_bay')
    check('delivery_reverse_resumes_without_restart_after_obstruction_removed',completed,resumeTrace)
    check('delivery_watchdog_closes_issue_after_docking',#Watchdog.snapshot(state).active==0)

    state,town,world,truck,delivery,site=fixture(712345)
    truck.x,truck.z=site:toWorld(20,0,0);truck.heading=site.yaw
    local originalUpdate=Truck.update
    Truck.update=function()error('injected docking controller failure')end
    local okay,failure=pcall(Network.simulate,state,town,.1,epoch+.1,world)
    Truck.update=originalUpdate
    check('delivery_watchdog_contains_docking_controller_exception',okay
        and #Watchdog.snapshot(state).events>0 and world.activeTruck==nil,tostring(failure))
    local recovered,_,_,recoveryTrace=run(state,town,world,truck,30,'at_bay')
    check('delivery_retries_docking_after_controller_exception',recovered,recoveryTrace)

    -- A controller reporting a low desired speed used to disable the watchdog
    -- entirely. Freeze the physics to reproduce that silent forward softlock.
    local Rules=require('src.commute.traffic_rules')
    local limitTraffic,command=Rules.limitForTraffic,Truck.command
    local rescues=0
    local x,z=site:toWorld(-10.1,14,0)
    local ex,ez=site:toWorld(-10.1,-5.4,0)
    local stalled=Truck.new(x,z,site.yaw-math.pi*.5,'plain')
    stalled.trafficId='stalled-creep-test'
    local points={{x=x,z=z,h=site.h},{x=ex,z=ez,h=site.h}}
    local creepState={}
    Rules.limitForTraffic=function()return .5,false end
    Truck.update=function()return 0 end
    Truck.command=function()rescues=rescues+1;return false,'Injected unsafe recovery point'end
    local ran,reason=pcall(function()
        for _=1,450 do Network.driveRoute(stalled,points,.1,world,'creep-test',creepState) end
    end)
    Truck.update=originalUpdate;Truck.command=command;Rules.limitForTraffic=limitTraffic
    check('delivery_watchdog_detects_low_speed_stall_and_escalates_recovery',ran
        and rescues>0 and #Watchdog.snapshot(creepState).active>0,tostring(reason))
    for _=1,300 do if Network.driveRoute(stalled,points,.1,world,'creep-test',creepState) then break end end
    check('delivery_forward_driver_resumes_after_physics_unsticks',stalled.distance>5
        and #Watchdog.snapshot(creepState).active==0)
    local crawling=Truck.new(x,z,site.yaw-math.pi*.5,'plain')
    local crawlingState={}
    Rules.limitForTraffic=function()return .5,false end
    local crawled,crawlError=pcall(function()
        for _=1,150 do Network.driveRoute(crawling,points,.1,world,'moving-creep-test',crawlingState) end
    end)
    Rules.limitForTraffic=limitTraffic
    check('delivery_watchdog_accepts_genuine_slow_forward_progress',crawled
        and crawling.distance>.5 and #Watchdog.snapshot(crawlingState).events==0,tostring(crawlError))

    local Company=require('src.company_delivery_driver')
    for _,model in ipairs({'box','kei'}) do
        local company=Company.defaultState()
        company.status='returning';company.vehicleModel=model;company.deliveryRun={}
        company.nextActionAtHours=0;company.currentLegFuelLiters=0
        company.departureHomeX,company.departureHomeZ=site.truckParking.x,site.truckParking.z
        state.employment={companyTruck=company,staff={}}
        local returned=model=='box' and state.home.commute.truck or state.home.commute.keiTruck
        returned.x,returned.z=site.truckParking.x,site.truckParking.z
        Company.update(state,100)
        local home=site.truckHomeParking[model]
        check('employee_returns_empty_'..model..'_to_home_stall_instead_of_loading_dock',
            returned.x==home.x and returned.z==home.z and returned.heading==home.heading)
    end
end
return Test
