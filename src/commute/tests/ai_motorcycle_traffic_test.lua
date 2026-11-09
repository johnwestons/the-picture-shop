local Network=require('src.commute.delivery_traffic')
local BikeTraffic=require('src.commute.ai_motorcycle_traffic')
local Town=require('src.commute.town')
local State=require('src.state')
local Home=require('src.home')
local Calendar=require('src.business_calendar')
local Trip=require('src.commute.trip')
local Bike=require('src.commute.motorcycle')
local DrivingPath=require('src.commute.driving_path')
local TrafficRules=require('src.commute.traffic_rules')
local TrafficActorIndex=require('src.commute.traffic_actor_index')
local Footprint=require('src.commute.truck_footprint')
local Test={}

local function seedTestTraffic(commute,world)
    local routes=assert(BikeTraffic.routes(world))
    local agents=commute.aiMotorcycles or {}
    for index=#agents,1,-1 do agents[index]=nil end
    for index=1,math.min(BikeTraffic.MAX_BIKES,routes.pairCount) do
        local routeId=routes.pairCount>=index and (index-1)*2+1 or index
        local route=routes[routeId] or routes[1]
        local sample=assert(DrivingPath.sample(route.points,route.length,.24))
        local bike=Bike.new(sample.x,sample.z,sample.heading)
        bike.aiKind='motorcycle';bike.trafficKind='motorcycle';bike.driverSkill=48
        bike.trafficId='test-ai-motorcycle-'..index
        Bike.resetContact(bike,world);Bike.resetHorizontal(bike);bike._aiHydrated=true
        agents[#agents+1]={id='test-motorcycle-'..index,routeId=routeId,
            pathIndex=sample.pathIndex,dwell=0,bike=bike}
    end
    commute.aiMotorcycles=agents
    return agents
end

local function newTripState(town,world,token,seedMotorcycles)
    local state=State.new()
    state.home=assert(Home.new({apartmentId='garden',town=town},0))
    state.calendar=Calendar.dateFromHours(44)
    state.calendar.elapsed=44%24/24*Calendar.secondsPerDay(state)
    state.home.weekend.phase='ready';state.home.weekend.closedAtHours=44
    state.home.weekend.travelToken=token;state.home.weekend.readyMask=3
    local host={id=1,homeResidentId='owner'}
    assert(Trip.start(state,{host},token,world))
    if seedMotorcycles~=false then seedTestTraffic(state.home.commute,world) end
    return state
end

local function angleDifference(a,b)
    return math.atan2(math.sin(a-b),math.cos(a-b))
end

local function clearOfJunctions(world,point)
    for _,junction in ipairs(world.roads.junctions or {}) do
        local radius=(junction.outerRadius or junction.radius or 0)+9
        if (point.x-junction.x)^2+(point.z-junction.z)^2<radius*radius then return false end
    end
    return true
end

local function passSection(world)
    local best
    for _,path in ipairs(world.roads.paths or {}) do
        if path.lanes==2 and not path.oneWay and path.surface~='dirt'
            and path.role~='drive' and path.width>=6 then
            local length=DrivingPath.length(path.points)
            local sectionLength=42
            if length>=sectionLength+36 then
                local startDistance=(length-sectionLength)*.5
                local blockerDistance=startDistance+11
                local finishDistance=startDistance+sectionLength
                local start=DrivingPath.sample(path.points,length,startDistance/length)
                local blocker=DrivingPath.sample(path.points,length,blockerDistance/length)
                local finish=DrivingPath.sample(path.points,length,finishDistance/length)
                local _,startSegment=world.roads:nearest(start.x,start.z,true)
                local _,blockerSegment=world.roads:nearest(blocker.x,blocker.z,true)
                local _,finishSegment=world.roads:nearest(finish.x,finish.z,true)
                local validSegments=startSegment and blockerSegment and finishSegment
                    and not startSegment.junction and not blockerSegment.junction and not finishSegment.junction
                    and startSegment.path==path and blockerSegment.path==path and finishSegment.path==path
                local straight=math.abs(angleDifference(blocker.heading,start.heading))<.45
                    and math.abs(angleDifference(finish.heading,blocker.heading))<.45
                if validSegments and straight and clearOfJunctions(world,start)
                    and clearOfJunctions(world,blocker) and clearOfJunctions(world,finish)
                    and (not best or length>best.length) then
                    local points={{x=start.x,z=start.z,h=start.h}}
                    for index=start.pathIndex,finish.pathIndex-1 do
                        local point=path.points[index]
                        local last=points[#points]
                        if point and (point.x-last.x)^2+(point.z-last.z)^2>.2^2 then
                            points[#points+1]={x=point.x,z=point.z,h=point.h}
                        end
                    end
                    local last=points[#points]
                    if (finish.x-last.x)^2+(finish.z-last.z)^2>.2^2 then
                        points[#points+1]={x=finish.x,z=finish.z,h=finish.h}
                    end
                    if #points>=3 then
                        best={length=length,start=start,blocker=blocker,finish=finish,
                            startSegment=startSegment,blockerSegment=blockerSegment,points=points}
                    end
                end
            end
        end
    end
    return best
end

function Test.run(check,town,routeSmoke)
    local testSeed=tonumber(os.getenv('PICTURE_SHOP_AI_TOWN_SEED')) or 712345
    town=town or Town.generate(testSeed)
    local world=Town.world(town)
    local state=newTripState(town,world,101,false)
    local epoch=1700000000
    local created,emptyMoving=Network.simulate(state,town,.05,epoch,world)
    local agents=state.home.commute.aiMotorcycles
    local visibleMotorcycles=0
    for _,entry in ipairs(Network.actors(state,town,0,epoch)) do
        if entry.deliveryBike and not entry.townNpc then visibleMotorcycles=visibleMotorcycles+1 end
    end
    check('ai_motorcycle_traffic_waits_for_an_explicit_commute_journey',
        not created and not emptyMoving and #agents==0 and visibleMotorcycles==0)
    seedTestTraffic(state.home.commute,world)
    local _,moving=Network.simulate(state,town,.05,epoch,world)
    local initial={}
    for index,agent in ipairs(agents) do
        initial[index]={x=agent.bike.x,z=agent.bike.z}
    end
    local originalBikeUpdate=Bike.update
    local updateCalls,totalUpdateTime,maxUpdateTime=0,0,0
    Bike.update=function(bike,input,dt,activeWorld)
        updateCalls=updateCalls+1
        totalUpdateTime=totalUpdateTime+dt
        maxUpdateTime=math.max(maxUpdateTime,dt)
        return originalBikeUpdate(bike,input,dt,activeWorld)
    end
    local substepOk,substepError=pcall(Network.simulate,state,town,.25,epoch,world)
    Bike.update=originalBikeUpdate
    if not substepOk then error(substepError,0) end
    check('ai_motorcycle_traffic_consumes_long_frames_in_shared_substeps',
        updateCalls==BikeTraffic.MAX_BIKES*3 and math.abs(totalUpdateTime-.5)<1e-8
            and maxUpdateTime<=.1)
    local serial=BikeTraffic.snapshot(agents)
    check('ai_motorcycle_traffic_drives_context_seeded_route_agents',#agents==BikeTraffic.MAX_BIKES
        and BikeTraffic.valid(serial) and agents[1].bike._aiHydrated==true)
    local routes=BikeTraffic.routes(world)
    local distinctPairs=routes and routes.pairCount<2
        or routes and math.floor((agents[1].routeId+1)/2)~=math.floor((agents[2].routeId+1)/2)
    local pairDetail=routes and ('availablePairs=%d assignedRoutes=%d/%d'):format(routes.pairCount,
        agents[1].routeId,agents[2].routeId) or 'no route pair available'
    check('ai_motorcycle_traffic_assigns_distinct_route_pairs_when_available',distinctPairs==true,pairDetail)

    local disposableTown=assert(Town.generate(testSeed+900003))
    local disposableWorld=Town.world(disposableTown)
    local disposableRoutes=assert(BikeTraffic.routes(disposableWorld))
    local weakRoutePoint=setmetatable({disposableRoutes[1].points[1]},{__mode='v'})
    disposableRoutes=nil;disposableWorld=nil;disposableTown=nil
    collectgarbage('collect');collectgarbage('collect')
    check('ai_motorcycle_route_cache_releases_discarded_town_geometry',weakRoutePoint[1]==nil)

    local recoveryState=newTripState(town,world,104)
    Network.simulate(recoveryState,town,.05,epoch,world)
    local recoveryAgent=recoveryState.home.commute.aiMotorcycles[1]
    recoveryAgent.bike.crashPending={kind='test'}
    recoveryAgent.recoveryTime=0
    for _=1,40 do Network.simulate(recoveryState,town,.05,epoch,world) end
    check('ai_motorcycle_traffic_recovers_crashed_riders_after_a_brief_delay',
        recoveryAgent.bike.crashPending==nil and recoveryAgent.bike.rescueCount==1
            and recoveryAgent.recoveryTime==0 and BikeTraffic.valid(BikeTraffic.snapshot(
                recoveryState.home.commute.aiMotorcycles)))

    -- Exercise the collision and recovery as one live simulation lifecycle.
    -- A fast test bike makes the pedestrian impact severe enough to enter the
    -- same crash state used by production damage/ejection handling.
    local pedestrianCrashState=newTripState(town,world,105)
    Network.simulate(pedestrianCrashState,town,.05,epoch,world)
    local crashAgent=pedestrianCrashState.home.commute.aiMotorcycles[1]
    pedestrianCrashState.home.commute.aiMotorcycles={crashAgent}
    local crashBike=crashAgent.bike
    local crashRider=pedestrianCrashState.home.commute.participants.owner.rider
    crashRider.gear.mounted=false
    crashBike.speed=14;Bike.resetHorizontal(crashBike)
    local forwardX,forwardZ=math.cos(crashBike.heading),math.sin(crashBike.heading)
    crashRider.ped.x=crashBike.x+forwardX*1.25
    crashRider.ped.z=crashBike.z+forwardZ*1.25
    crashRider.ped.h=world:supportHeight(crashRider.ped.x,crashRider.ped.z)
    Network.simulate(pedestrianCrashState,town,.05,epoch,world)
    local realPedestrianCrash=crashBike.crashPending~=nil
        and crashBike.crashPending.kind=='pedestrian'
    for _=1,40 do Network.simulate(pedestrianCrashState,town,.05,epoch,world) end
    check('ai_motorcycle_pedestrian_crash_recovers_through_live_traffic_simulation',
        realPedestrianCrash and crashBike.crashPending==nil and crashBike.rescueCount==1
            and BikeTraffic.valid(BikeTraffic.snapshot(
                pedestrianCrashState.home.commute.aiMotorcycles)),
        ('impact=%s rescueCount=%s pending=%s'):format(
            tostring(realPedestrianCrash),tostring(crashBike.rescueCount),
            tostring(crashBike.crashPending~=nil)))

    local pedestrianYieldState=newTripState(town,world,106)
    Network.simulate(pedestrianYieldState,town,.05,epoch,world)
    local yieldAgent=pedestrianYieldState.home.commute.aiMotorcycles[1]
    pedestrianYieldState.home.commute.aiMotorcycles={yieldAgent}
    local yieldBike=yieldAgent.bike
    local yieldRider=pedestrianYieldState.home.commute.participants.owner.rider
    yieldRider.gear.mounted=false
    yieldBike.speed=7.2;Bike.resetHorizontal(yieldBike)
    local yieldRoute=BikeTraffic.routes(world)[yieldAgent.routeId]
    local pedestrianTarget,pedestrianHeading=DrivingPath.lookAhead(yieldRoute.points,
        yieldBike.x,yieldBike.z,yieldAgent.pathIndex,5)
    local _,pedestrianSegment=world.roads:nearest(pedestrianTarget.x,pedestrianTarget.z,true)
    local pedestrianLane=TrafficRules.laneOffset(pedestrianSegment,
        TrafficRules.drivingSide(world.town),false)
    yieldRider.ped.x,yieldRider.ped.z=TrafficRules.lanePoint(pedestrianTarget,
        pedestrianHeading,pedestrianLane)
    yieldRider.ped.h=world:supportHeight(yieldRider.ped.x,yieldRider.ped.z)
    local minimumPedestrianGap=math.huge
    for _=1,100 do
        Network.simulate(pedestrianYieldState,town,.05,epoch,world)
        minimumPedestrianGap=math.min(minimumPedestrianGap,
            math.sqrt((yieldBike.x-yieldRider.ped.x)^2+(yieldBike.z-yieldRider.ped.z)^2))
    end
    check('ai_motorcycle_avoids_pedestrian_without_collision',
        yieldBike.crashPending==nil and minimumPedestrianGap>Bike.RADIUS+.55,
        ('minGap=%.3f finalSpeed=%.3f crash=%s'):format(minimumPedestrianGap,
            yieldBike.speed,tostring(yieldBike.crashPending~=nil)))

    local sharedState=newTripState(town,world,102)
    Network.simulate(sharedState,town,.05,epoch,world)
    local sharedCommute=sharedState.home.commute
    local sharedAgent=sharedCommute.aiMotorcycles[1]
    local player=sharedCommute.participants.owner.rider
    local playerBike=player.bike
    local route=BikeTraffic.routes(world)[sharedAgent.routeId]
    local ahead,heading=DrivingPath.lookAhead(route.points,sharedAgent.bike.x,sharedAgent.bike.z,
        sharedAgent.pathIndex,8)
    local _,segment=world.roads:nearest(ahead.x,ahead.z,true)
    local offset=TrafficRules.laneOffset(segment,TrafficRules.drivingSide(world.town),false)
    playerBike.x,playerBike.z=TrafficRules.lanePoint(ahead,heading,offset)
    playerBike.heading=heading;playerBike.speed=0
    Bike.resetContact(playerBike,world);Bike.resetHorizontal(playerBike)
    player.gear.mounted=true
    local minimumGap,maxFollowingSpeed=math.huge,0
    local noCollision=true
    for _=1,120 do
        Network.simulate(sharedState,town,.05,epoch,world)
        local bike=sharedAgent.bike
        local dx,dz=bike.x-playerBike.x,bike.z-playerBike.z
        minimumGap=math.min(minimumGap,math.sqrt(dx*dx+dz*dz))
        maxFollowingSpeed=math.max(maxFollowingSpeed,bike.speed)
        noCollision=noCollision and bike.crashPending==nil
    end
    check('ai_motorcycle_traffic_keeps_safe_spacing_from_mounted_player_bike',noCollision
        and maxFollowingSpeed>1 and minimumGap>1 and minimumGap<12,
        ('minimumGap=%.2fm maxSpeed=%.2fm/s safe=%s'):format(minimumGap,maxFollowingSpeed,tostring(noCollision)))

    player.gear.mounted=false
    local truck=sharedCommute.truck
    local truckAhead,truckHeading=DrivingPath.lookAhead(route.points,sharedAgent.bike.x,sharedAgent.bike.z,
        sharedAgent.pathIndex,8)
    local _,truckSegment=world.roads:nearest(truckAhead.x,truckAhead.z,true)
    local truckOffset=TrafficRules.laneOffset(truckSegment,TrafficRules.drivingSide(world.town),false)
    truck.x,truck.z=TrafficRules.lanePoint(truckAhead,truckHeading,truckOffset)
    truck.heading=truckHeading;truck.speed=0;truck.h=world:supportHeight(truck.x,truck.z);truck.engine=false
    local truckGap,truckFollowingSpeed=math.huge,0
    local truckNoCollision=true
    for _=1,120 do
        Network.simulate(sharedState,town,.05,epoch,world)
        local bike=sharedAgent.bike
        local dx,dz=bike.x-truck.x,bike.z-truck.z
        truckGap=math.min(truckGap,math.sqrt(dx*dx+dz*dz))
        truckFollowingSpeed=math.max(truckFollowingSpeed,bike.speed)
        truckNoCollision=truckNoCollision and bike.crashPending==nil
    end
    check('ai_motorcycle_traffic_keeps_clearance_from_player_truck',truckNoCollision
        and truckGap>3 and truckGap<12,
        ('minimumGap=%.2fm maxSpeed=%.2fm/s safe=%s roadLanes=%s roadWidth=%s oneWay=%s junction=%s surface=%s laneOffset=%.2f'):
            format(truckGap,truckFollowingSpeed,tostring(truckNoCollision),
                tostring(truckSegment and truckSegment.lanes),tostring(truckSegment and truckSegment.width),
                tostring(truckSegment and truckSegment.oneWay),tostring(truckSegment and truckSegment.junction),
                tostring(truckSegment and truckSegment.surface),truckOffset or 0))

    local passRoute=passSection(world)
    local passOkay,passDetail=false,'no clear two-lane road section was available'
    if passRoute then
        local passState=newTripState(town,world,103)
        Network.simulate(passState,town,.05,epoch,world)
        local passCommute=passState.home.commute
        local passAgent=passCommute.aiMotorcycles[1]
        passCommute.aiMotorcycles={passAgent}
        local passBike=passAgent.bike
        local side=TrafficRules.drivingSide(world.town)
        local laneOffset=TrafficRules.laneOffset(passRoute.startSegment,side,false)
        local blockerOffset=TrafficRules.laneOffset(passRoute.blockerSegment,side,false)
        local startX,startZ=TrafficRules.lanePoint(passRoute.start,passRoute.start.heading,laneOffset)
        local blockerX,blockerZ=TrafficRules.lanePoint(passRoute.blocker,passRoute.blocker.heading,blockerOffset)
        passBike.x,passBike.z,passBike.heading=startX,startZ,passRoute.start.heading
        passBike.speed=0;passBike.pathIndex=2;passBike.pathTarget=nil
        Bike.resetContact(passBike,world);Bike.resetHorizontal(passBike)
        passAgent.pathIndex=2;passAgent.routeId=1;passAgent.dwell=0
        local blockingTruck=passCommute.truck
        blockingTruck.x,blockingTruck.z=blockerX,blockerZ
        blockingTruck.heading=passRoute.blocker.heading
        blockingTruck.speed=0;blockingTruck.engine=false;blockingTruck.reverse=false
        blockingTruck.h=world:supportHeight(blockingTruck.x,blockingTruck.z)
        local spareTruck=passCommute.keiTruck
        spareTruck.x,spareTruck.z=500,500
        local blockerDimensions=Footprint.dimensions(blockingTruck)
        Network.installVehicleObstacles(passState,world)
        local trafficActors={
            {actor=passBike,id='ai-pass-test',kind='bike',halfLength=BikeTraffic.HALF_LENGTH,
                halfWidth=BikeTraffic.HALF_WIDTH,radius=.5},
            {actor=blockingTruck,id='player-truck-box',kind='vehicle',isPlayer=true,
                halfLength=blockerDimensions.halfLength,halfWidth=blockerDimensions.halfWidth},
        }
        world.trafficActors=trafficActors
        world.trafficActorIndex=TrafficActorIndex.new(trafficActors)
        local fx,fz=math.cos(blockingTruck.heading),math.sin(blockingTruck.heading)
        local laneWidth=passRoute.blockerSegment.width/passRoute.blockerSegment.lanes
        local minimumTruckGap=math.huge
        local passedBlocker,enteredPassingLane,returnedToLane,noCrash=false,false,false,true
        local hazardInjected,returnedBehindBlocker=false,false
        local minimumOncomingGap=math.huge
        local oncomingClearAtInjection,returnClearAtInjection,edgeClearAtInjection
        local blockerGapAtInjection,edgeOffsetAtInjection,roadWidthAtInjection
        local minOncomingForward,minOncomingRoadOffset,minOncomingSpeed
        local oncomingEntry,oncomingBike
        for _=1,600 do
            Network.driveRoute(passBike,passRoute.points,.05,world,'ai-pass-test')
            local dx,dz=passBike.x-blockingTruck.x,passBike.z-blockingTruck.z
            local forward=-dx*fx-dz*fz
            minimumTruckGap=math.min(minimumTruckGap,math.sqrt(dx*dx+dz*dz))
            local _,roadSegment,u=world.roads:nearest(passBike.x,passBike.z,true)
            local roadOffset
            if roadSegment and not roadSegment.junction then
                local centerX=roadSegment.a.x+u*roadSegment.dx
                local centerZ=roadSegment.a.z+u*roadSegment.dz
                roadOffset=(passBike.x-centerX)*roadSegment.nx+(passBike.z-centerZ)*roadSegment.nz
            end
            if math.abs(forward)<7 and roadOffset and roadOffset*laneOffset<0
                and math.abs(roadOffset)>laneWidth*.2 then
                enteredPassingLane=true
            end
            local passStarted=roadOffset and math.abs(roadOffset-laneOffset)>.45
            local stillBehindBlocker=forward>-(TrafficRules.dimensions(passBike).halfLength
                +blockerDimensions.halfLength+1)
            if passStarted and stillBehindBlocker and not hazardInjected and roadSegment then
                local heading=passBike.heading
                local fx,fz=math.cos(heading),math.sin(heading)
                local nx,nz=-fz,fx
                local roadCenterX=passBike.x-nx*roadOffset
                local roadCenterZ=passBike.z-nz*roadOffset
                local oncomingOffset=-laneOffset
                oncomingBike={x=roadCenterX+fx*36+nx*oncomingOffset,
                    z=roadCenterZ+fz*36+nz*oncomingOffset,
                    heading=heading+math.pi,speed=10,trafficKind='motorcycle'}
                oncomingEntry={actor=oncomingBike,id='ai-pass-oncoming-test',kind='bike',
                    halfLength=BikeTraffic.HALF_LENGTH,halfWidth=BikeTraffic.HALF_WIDTH,radius=.5}
                trafficActors[#trafficActors+1]=oncomingEntry
                world.trafficActorIndex=TrafficActorIndex.new(trafficActors)
                local oncomingForward=(oncomingBike.x-passBike.x)*math.cos(passBike.heading)
                    +(oncomingBike.z-passBike.z)*math.sin(passBike.heading)
                local oncomingLookahead=TrafficRules.passLookaheadSeconds(passBike,oncomingForward,oncomingBike)
                oncomingClearAtInjection=TrafficRules.laneClear(passBike,roadSegment,-laneOffset,roadOffset,
                    trafficActors,world.trafficActorIndex,blockingTruck,oncomingLookahead)
                returnClearAtInjection=TrafficRules.laneClear(passBike,roadSegment,laneOffset,roadOffset,
                    trafficActors,world.trafficActorIndex,blockingTruck)
                roadWidthAtInjection=roadSegment.width
                edgeOffsetAtInjection=(laneOffset>0 and -1 or 1)
                    *(roadSegment.width*.5-BikeTraffic.HALF_WIDTH-.5)
                edgeClearAtInjection=TrafficRules.laneClear(passBike,roadSegment,edgeOffsetAtInjection,
                    roadOffset,trafficActors,world.trafficActorIndex,blockingTruck,oncomingLookahead)
                local blockerForward=(blockingTruck.x-passBike.x)*math.cos(passBike.heading)
                    +(blockingTruck.z-passBike.z)*math.sin(passBike.heading)
                blockerGapAtInjection=blockerForward-TrafficRules.dimensions(passBike).halfLength
                    -blockerDimensions.halfLength
                hazardInjected=true
            end
            if oncomingBike then
                local gapX,gapZ=passBike.x-oncomingBike.x,passBike.z-oncomingBike.z
                local gap=math.sqrt(gapX*gapX+gapZ*gapZ)
                if gap<minimumOncomingGap then
                    minimumOncomingGap=gap
                    minOncomingForward=(oncomingBike.x-passBike.x)*math.cos(passBike.heading)
                        +(oncomingBike.z-passBike.z)*math.sin(passBike.heading)
                    minOncomingRoadOffset=roadOffset
                    minOncomingSpeed=passBike.speed
                end
                oncomingBike.x=oncomingBike.x+math.cos(oncomingBike.heading)*oncomingBike.speed*.05
                oncomingBike.z=oncomingBike.z+math.sin(oncomingBike.heading)*oncomingBike.speed*.05
                world.trafficActorIndex:update(oncomingBike,oncomingEntry)
            end
            local dimensions=TrafficRules.dimensions(passBike)
            if forward<-(dimensions.halfLength+blockerDimensions.halfLength+1) then passedBlocker=true end
            if hazardInjected and not passedBlocker and roadOffset and roadOffset*laneOffset>0
                and math.abs(roadOffset-laneOffset)<laneWidth*.35 then
                returnedBehindBlocker=true
            end
            if passedBlocker and forward< -8 and roadOffset and roadOffset*laneOffset>0
                and math.abs(roadOffset-laneOffset)<laneWidth*.35 then
                returnedToLane=true
            end
            noCrash=noCrash and passBike.crashPending==nil
            if returnedToLane and forward< -15 then break end
        end
        local yieldedToBlocker=not enteredPassingLane and not passedBlocker
            and passBike.speed<.5 and minimumTruckGap>3 and minimumTruckGap<12 and noCrash
        passOkay=(enteredPassingLane and passedBlocker and returnedToLane and noCrash
            and minimumTruckGap>1) or yieldedToBlocker
        local hazardPassOkay=(hazardInjected and minimumOncomingGap>2.5 and noCrash)
            or (not hazardInjected and yieldedToBlocker)
        local hazardPassDetail=('injected=%s passClearAtInjection=%s returnClearAtInjection=%s edgeClear=%s edgeOffset=%.2f roadWidth=%.2f blockerGap=%.2f returnedBehindBlocker=%s minOncomingGap=%.2f forward=%.2f laneOffset=%.2f bikeSpeed=%.2f crashFree=%s finalBike=(%.2f,%.2f) start=(%.2f,%.2f) blocker=(%.2f,%.2f) points=%d truckGap=%.2f finalSpeed=%.2f entered=%s passed=%s yielded=%s'):
            format(tostring(hazardInjected),tostring(oncomingClearAtInjection),tostring(returnClearAtInjection),
                tostring(edgeClearAtInjection),edgeOffsetAtInjection or math.huge,roadWidthAtInjection or math.huge,
                blockerGapAtInjection or math.huge,tostring(returnedBehindBlocker),
                minimumOncomingGap,minOncomingForward or math.huge,minOncomingRoadOffset or math.huge,
                minOncomingSpeed or math.huge,tostring(noCrash),passBike.x,passBike.z,startX,startZ,
                blockerX,blockerZ,#passRoute.points,minimumTruckGap,passBike.speed,
                tostring(enteredPassingLane),tostring(passedBlocker),tostring(yieldedToBlocker))
        passDetail=('road=%s width=%.1f lanes=%d enteredPassLane=%s crossed=%s returned=%s yielded=%s crashFree=%s minGap=%.2f finalSpeed=%.2f'):
            format(tostring(passRoute.startSegment.id),passRoute.blockerSegment.width,
                passRoute.blockerSegment.lanes,tostring(enteredPassingLane),tostring(passedBlocker),
                tostring(returnedToLane),tostring(yieldedToBlocker),tostring(noCrash),minimumTruckGap,passBike.speed)
        world.vehicleObstacles=nil;world.sweepTrafficObstacles=nil
        world.trafficActors=nil;world.trafficActorIndex=nil
        -- The driver may safely finish the pass or yield behind the blocker;
        -- require a clear encounter rather than one specific evasive choice.
        check('ai_motorcycle_traffic_keeps_clearance_when_oncoming_traffic_appears_during_a_pass',
            hazardPassOkay,hazardPassDetail)
    end
    check('ai_motorcycle_traffic_passes_or_yields_safely_around_a_stopped_truck',passOkay,passDetail)

    for _=1,80 do Network.simulate(state,town,.05,epoch,world) end
    local distance=0
    for index,agent in ipairs(agents) do
        distance=distance+math.sqrt((agent.bike.x-initial[index].x)^2+(agent.bike.z-initial[index].z)^2)
    end
    local safe=true
    for _,agent in ipairs(agents) do safe=safe and agent.bike.crashPending==nil end
    if routeSmoke then
        local routes=BikeTraffic.routes(world)
        local initialRouteIds={agents[1].routeId,agents[2].routeId}
        local completed={false,false}
        local routeLength=0
        for index,routeId in ipairs(initialRouteIds) do
            routeLength=math.max(routeLength,routes[routeId].length)
        end
        local maxSeconds=routeLength*.76/3.8*1.8+30
        local stepDt=.05
        local steps=math.ceil(maxSeconds/stepDt)
        local safeThroughout=true
        local stepTimes={}
        for _=1,steps do
            local started=love.timer.getTime()
            Network.simulate(state,town,stepDt,epoch,world)
            stepTimes[#stepTimes+1]=(love.timer.getTime()-started)*1000
            for index,agent in ipairs(agents) do
                if agent.routeId~=initialRouteIds[index] then completed[index]=true end
                safeThroughout=safeThroughout and agent.bike.crashPending==nil
            end
            if (completed[1] and completed[2]) or not safeThroughout then break end
        end
        local routeSmokeOkay=completed[1] and completed[2] and safeThroughout
        local routeSmokeDetail=('length=%.1fm completed=%s/%s safe=%s'):format(routeLength,
            tostring(completed[1]),tostring(completed[2]),tostring(safeThroughout))
        table.sort(stepTimes)
        local count=#stepTimes
        local sum=0
        for _,elapsed in ipairs(stepTimes) do sum=sum+elapsed end
        print(('AI_DRIVING_SIMULATION_PERF town=%s samples=%d mean_ms=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f'):
            format(tostring(town.id),count,count>0 and sum/count or 0,stepTimes[math.ceil(count*.50)] or 0,
                stepTimes[math.ceil(count*.95)] or 0,stepTimes[count] or 0))
        check('ai_motorcycle_traffic_completes_assigned_route_legs_safely',routeSmokeOkay,routeSmokeDetail)
    end
    local actors=Network.actors(state,town,100,epoch)
    local rendered=0
    for _,entry in ipairs(actors) do
        if entry.deliveryBike and entry.bike and entry.actor and entry.phase=='riding' then rendered=rendered+1 end
    end
    local tripSnapshot=Trip.snapshot(state.home.commute)
    local snapshotOkay=Trip.valid(tripSnapshot,state.home)
        and #tripSnapshot.aiMotorcycles==BikeTraffic.MAX_BIKES
    local restored=Trip.restore(tripSnapshot,world)
    local restoreCountOkay=restored and #restored.aiMotorcycles==BikeTraffic.MAX_BIKES
    if restoreCountOkay then BikeTraffic.ensure(restored,world) end
    local restoreOkay=restoreCountOkay and restored.aiMotorcycles[1].bike._aiHydrated==true
    local crashState=newTripState(town,world,102)
    Network.simulate(crashState,town,.05,epoch,world)
    local crashAgent=crashState.home.commute.aiMotorcycles[1]
    local crashBike=crashAgent.bike
    crashBike.damage=27
    crashBike.collisionContact=true
    crashBike.collisionKind='pedestrian'
    crashBike.collisionId='owner'
    crashBike.impactPulse=.2
    crashBike.impactStrength=.7
    crashBike.rescueCount=2
    crashBike.safeX=crashBike.x;crashBike.safeZ=crashBike.z
    crashBike.safeHeading=crashBike.heading
    crashBike.crashPending={dx=1,dz=0,speed=14,nx=-1,nz=0,severity=.7,kind='pedestrian'}
    crashBike.rescueHistory={{x=crashBike.x-8,z=crashBike.z}}
    crashAgent.recoveryTime=.4
    local crashSnapshot=Trip.snapshot(crashState.home.commute)
    crashBike.crashPending.speed=0
    crashBike.rescueHistory[1].x=crashBike.x+8
    local crashSnapshotIndependent=crashSnapshot.aiMotorcycles[1].bike.crashPending.speed==14
        and crashSnapshot.aiMotorcycles[1].bike.rescueHistory[1].x~=crashBike.rescueHistory[1].x
    local crashRestored=Trip.restore(crashSnapshot,world)
    if crashRestored then BikeTraffic.ensure(crashRestored,world) end
    local restoredCrashAgent=crashRestored and crashRestored.aiMotorcycles[1]
    local restoredCrashBike=restoredCrashAgent and restoredCrashAgent.bike
    local crashRecoveryOkay=crashSnapshotIndependent and restoredCrashAgent
        and restoredCrashAgent.recoveryTime==.4 and restoredCrashBike._aiHydrated==true
        and restoredCrashBike.damage==27 and restoredCrashBike.collisionContact==true
        and restoredCrashBike.collisionKind=='pedestrian' and restoredCrashBike.collisionId=='owner'
        and restoredCrashBike.impactPulse==.2 and restoredCrashBike.impactStrength==.7
        and restoredCrashBike.rescueCount==2 and restoredCrashBike.safeX==crashBike.safeX
        and restoredCrashBike.safeZ==crashBike.safeZ and restoredCrashBike.safeHeading==crashBike.safeHeading
        and restoredCrashBike.crashPending and restoredCrashBike.crashPending.speed==14
        and restoredCrashBike.crashPending.kind=='pedestrian'
        and restoredCrashBike.rescueHistory and restoredCrashBike.rescueHistory[1].x==crashBike.x-8
        and restoredCrashBike.rescueHistory[1].z==crashBike.z
    local savedAgents=state.home.commute.aiMotorcycles
    state.home.commute.aiMotorcycles={agents[1]}
    Network.installVehicleObstacles(state,world)
    local obstacleQueriesInstalled=type(world.vehicleObstacles)=='function'
        and type(world.sweepTrafficObstacles)=='function'
    local playerRider=state.home.commute.participants.owner.rider
    local savedPed={x=playerRider.ped.x,z=playerRider.ped.z,h=playerRider.ped.h}
    local collisionBike=agents[1].bike
    local fx,fz=math.cos(collisionBike.heading),math.sin(collisionBike.heading)
    playerRider.gear.mounted=false
    playerRider.ped.x=collisionBike.x+fx*1.5;playerRider.ped.z=collisionBike.z+fz*1.5
    playerRider.ped.h=world:supportHeight(playerRider.ped.x,playerRider.ped.z)
    world.activeTrafficBike=nil
    local pedestrianHit,_,_,pedestrianKind=world.sweepTrafficObstacles(
        collisionBike.x-fx*.5,collisionBike.z-fz*.5,
        collisionBike.x+fx*2.3,collisionBike.z+fz*2.3,
        Bike.RADIUS,collisionBike.h,collisionBike.h+Bike.COLLISION_HEIGHT,collisionBike)
    local pedestrianCollisionDetected=pedestrianHit~=nil and pedestrianKind=='pedestrian'
    playerRider.ped.x,playerRider.ped.z,playerRider.ped.h=savedPed.x,savedPed.z,savedPed.h
    state.home.commute.aiMotorcycles=savedAgents
    local realTrafficSweep=world.sweepTrafficObstacles
    local sweepSubject
    local subjectBike=Bike.new(agents[1].bike.x,agents[1].bike.z,agents[1].bike.heading)
    Bike.resetContact(subjectBike,world)
    world.sweepTrafficObstacles=function(_,_,_,_,_,_,_,subject)
        sweepSubject=subject
        if subject~=subjectBike then return 0,1,0,'test','missing-bike-subject' end
    end
    Bike.update(subjectBike,{throttle=.2},.05,world)
    world.sweepTrafficObstacles=realTrafficSweep
    local collisionSubjectPassed=sweepSubject==subjectBike and subjectBike.crashPending==nil
    world.vehicleObstacles=nil;world.sweepTrafficObstacles=nil
    check('ai_motorcycle_traffic_moves_with_live_motorcycle_physics',moving and distance>1)
    check('ai_motorcycle_traffic_stays_out_of_crash_state',safe)
    check('ai_motorcycle_traffic_is_exposed_as_mounted_world_actors',rendered==BikeTraffic.MAX_BIKES)
    check('ai_motorcycle_traffic_survives_commute_snapshot_and_restore',snapshotOkay and restoreOkay)
    check('ai_motorcycle_traffic_preserves_crash_state_and_damage_across_restore',crashRecoveryOkay)
    check('delivery_traffic_installs_player_collision_queries',obstacleQueriesInstalled)
    check('motorcycle_traffic_collision_sweep_detects_pedestrians',pedestrianCollisionDetected)
    check('motorcycle_update_passes_its_subject_to_the_collision_sweep',collisionSubjectPassed)
end

return Test
