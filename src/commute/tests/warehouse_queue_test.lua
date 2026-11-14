local Test={}
function Test.run(check)
    local Budget=require('src.commute.traffic_budget')
    local load={}
    for _=1,12 do Budget.record(load,20,1) end
    check('receiving_slows_new_departures_under_simulation_load',not Budget.allows(load,8) and Budget.allows(load,0))
    for _=1,20 do Budget.record(load,2,1) end
    check('receiving_dispatch_recovers_when_simulation_load_falls',Budget.allows(load,8))
    local Network=require('src.commute.delivery_traffic')
    local Town=require('src.commute.town')
    local Truck=require('src.commute.delivery_truck')
    local Path=require('src.commute.driving_path')
    local Queue=require('src.commute.warehouse_queue')
    local Footprint=require('src.commute.truck_footprint')
    local town=assert(Town.generate(712345));local world=Town.world(town)
    local epoch=1700000000
    local state={calendar={secondsPerDay=300},jobs={active={},completed={}}}
    for i=1,20 do state.jobs.active[i]={id=('QUEUE-%02d'):format(i),status='ready_for_pickup',
        pickup={status='awaiting_schedule',dispatchAtHours=105}} end
    Network.update(state,town,105,epoch,world)
    Network.update(state,town,105,epoch+1,world)
    check('receiving_dispatch_spaces_burst_requests',state.jobs.active[1].pickup.roadDelivery.route.departedAtEpoch==epoch
        and state.jobs.active[2].pickup.roadDelivery.route.departedAtEpoch==nil)
    for i=1,19 do Network.update(state,town,105,epoch+i*Network.DISPATCH_HEADWAY_SECONDS,world) end
    local count=0
    for _,job in ipairs(state.jobs.active) do if job.pickup.roadDelivery.route.departedAtEpoch then count=count+1 end end
    check('receiving_dispatch_budget_exceeds_old_three_truck_limit',count==Network.MAX_ACTIVE_TRUCKS and count>3)
    local actors=Network.actors(state,town,105,epoch+152,world)
    check('receiving_all_dispatched_trucks_remain_visible',#actors==count)
    local route=state.jobs.active[1].pickup.roadDelivery.route
    route.vehicle=Truck.new(world.mainlandExit.x,world.mainlandExit.z,0)
    route.vehicle.phase='approaching'
    for i=2,16 do state.jobs.active[i].pickup.roadDelivery.route.vehicle={phase='offmap'} end
    Network.update(state,town,105,epoch+200,world)
    check('receiving_gate_blocks_overlapping_spawns',not state.jobs.active[17].pickup.roadDelivery.route.departedAtEpoch)
    route.vehicle.phase='offmap'
    Network.update(state,town,105,epoch+201,world)
    check('receiving_dispatch_resumes_after_gate_clears',state.jobs.active[17].pickup.roadDelivery.route.departedAtEpoch==epoch+201)

    local site=world.sites.byId.warehouse
    local planner=require('src.commute.routes').new(world.roads,{includeTruckOnly=true,pavedOnly=true,destinations=world.truckDestinations})
    local inward=assert(planner:findFromPoint(world.mainlandExit.x,world.mainlandExit.z,'warehouse_truck_dock')).points
    local routing={world=world,inward=inward,length=Path.length(inward)}
    local entries={}
    for i=5,1,-1 do entries[#entries+1]={id='QUEUE-'..i,delivery={status='pending_arrival',
        route={roadTownId=town.id,departedAtEpoch=epoch+i,arrivedAtEpoch=epoch+999}}} end
    local plan=Queue.plan(entries,routing,true,epoch+10,Network.lanePosition)
    local positions={};local safe=true
    for _,entry in ipairs(entries) do
        local assignment=plan[entry.delivery.route];local a=assignment.anchor
        local x,z=site:toWorld(a.x,a.z,0)
        local truck=Truck.new(x,z,a.heading or site.yaw-math.pi*.5,'plain')
        truck.h=world:supportHeight(x,z);truck.phase='waiting_bay';truck.pathTarget=assignment.target;truck.pathIndex=2
        entry.delivery.route.vehicle=truck;positions[#positions+1]=truck
        for i=1,#positions-1 do
            local other=positions[i]
            safe=safe and not Footprint.overlapsTruck(x,z,truck.heading,other.x,other.z,other.heading)
        end
    end
    check('receiving_overflow_has_separate_nonoverlapping_positions',safe
        and plan[entries[1].delivery.route].target=='waiting-5' and plan[entries[5].delivery.route].target=='waiting-1')
    local capacity=Queue.capacity(routing)
    local capacityEntries={}
    for i=1,capacity+1 do
        capacityEntries[i]={id=('CAPACITY-%02d'):format(i),delivery={status='pending_arrival',
            route={roadTownId=town.id,departedAtEpoch=epoch+i,arrivedAtEpoch=epoch+999}}}
    end
    local capacityPlan=Queue.plan(capacityEntries,routing,true,epoch+capacity+2,Network.lanePosition)
    local capacityOkay=capacity>=#(site.truckQueueAnchors or {})
    for i=1,capacity do
        local assignment=capacityPlan[capacityEntries[i].delivery.route]
        capacityOkay=capacityOkay and assignment~=nil and assignment.anchor~=nil
    end
    local overflowAssignment=capacityPlan[capacityEntries[capacity+1].delivery.route]
    check('receiving_queue_capacity_tracks_usable_procedural_road_length',capacityOkay
        and overflowAssignment~=nil and overflowAssignment.anchor==nil
        and overflowAssignment.capacity==capacity)
    local clear=Queue.plan(entries,routing,false,epoch+10,Network.lanePosition)
    check('receiving_first_truck_gets_dock_regardless_of_job_array_order',clear[entries[5].delivery.route].target=='dock'
        and clear[entries[4].delivery.route].target=='waiting-1')
    local box=Truck.new(site.truckParking.x,site.truckParking.z,site.yaw)
    state={home={town=town,commute={participants={},truck=box}},jobs={active=entries,completed={}}}
    for i=1,200 do Network.simulate(state,town,.1,epoch+10+i*.1,world) end
    local held=true
    for _,entry in ipairs(entries) do held=held and entry.delivery.route.vehicle.phase=='waiting_bay' end
    local snapshotEvents=require('src.ai_watchdog').snapshot(state).events
    local detail={}
    for _,entry in ipairs(entries) do detail[#detail+1]=entry.id..':'..entry.delivery.route.vehicle.phase end
    for _,event in ipairs(snapshotEvents) do detail[#detail+1]=tostring(event.subject)..':'..tostring(event.action) end
    check('receiving_full_queue_waits_without_deadlock_recovery',held and #snapshotEvents==0,table.concat(detail,'; '))
    local markerEntries=Network.physicalActors(state)
    local Map=require('src.commute.route_map')
    local originX,originZ=site:toWorld(0,0,0)
    local snapshot={viewport={x=0,y=0,width=800,height=800,scale=1,bounds={x0=originX-400,z0=originZ-400}}}
    check('receiving_map_includes_every_queued_truck',#Map.trafficMarkers(snapshot,markerEntries,false)==5)
    local parking=assert(require('src.commute.trip').truckParking(world,{fuelLiters=60},'box'))
    box.x,box.z,box.heading=parking.x,parking.z,parking.heading
    local collided=false
    for i=1,1800 do
        Network.simulate(state,town,.1,epoch+30+i*.1,world)
        for _,entry in ipairs(entries) do collided=collided or entry.delivery.route.vehicle.collisionContact==true end
        if entries[5].delivery.route.vehicle.phase=='at_bay'
            and entries[4].delivery.route.vehicle.phase=='waiting_bay' then break end
    end
    local leader,follower=entries[5].delivery.route.vehicle,entries[4].delivery.route.vehicle
    check('receiving_queue_drives_forward_in_order_after_bay_clears',not collided and leader.phase=='at_bay'
        and follower.phase=='waiting_bay' and follower.pathTarget=='waiting-1',
        ('leader=%s follower=%s/%s collisions=%s'):format(leader.phase,follower.phase,follower.pathTarget,tostring(collided)))
    local directory=os.getenv('PICTURE_SHOP_RECEIVING_CAPTURE')
    if directory then
        local g=love.graphics;local canvas=require('src.tests.support.pixel_canvas')(480,700)
        g.push('all');g.setCanvas(canvas);g.origin();g.clear(.12,.17,.18,1)
        local vertices=require('src.commute.dock_apron_geometry').build(site)
        for i=1,#vertices,3 do
            local points={}
            for j=i,i+2 do local x,z=site:toLocal(vertices[j][1],vertices[j][2]);points[#points+1]=240+(x+10.1)*23;points[#points+1]=100+(z+5)*23 end
            g.setColor(.95,.70,.24,1);g.polygon('fill',points)
        end
        g.pop();local data=canvas:newImageData();local png=data:encode('png')
        local file=assert(io.open(directory..'/queue-markings.png','wb'));file:write(png:getString());file:close()
        png:release();data:release();canvas:release()
    end
end
return Test
