local Network=require('src.commute.delivery_traffic')
local Town=require('src.commute.town')
local Routes=require('src.commute.routes')
local Truck=require('src.commute.delivery_truck')
local Bike=require('src.commute.motorcycle')
local Footprint=require('src.commute.truck_footprint')
local DrivingPath=require('src.commute.driving_path')
local TrafficActorIndex=require('src.commute.traffic_actor_index')
local BikeTraffic=require('src.commute.ai_motorcycle_traffic')
local Test={}

local RETURN_TRUCKS=Network.MAX_ACTIVE_TRUCKS
local SIMULATION_STEPS=80

local function seedTestMotorcycles(commute,world,routes)
    local agents={}
    for index=1,math.min(BikeTraffic.MAX_BIKES,routes.pairCount) do
        local routeId=routes.pairCount>=index and (index-1)*2+1 or index
        local route=routes[routeId] or routes[1]
        local sample=assert(DrivingPath.sample(route.points,route.length,.24))
        local bike=Bike.new(sample.x,sample.z,sample.heading)
        bike.aiKind='motorcycle';bike.trafficKind='motorcycle';bike.driverSkill=48
        bike.trafficId='test-dense-ai-motorcycle-'..index
        Bike.resetContact(bike,world);Bike.resetHorizontal(bike);bike._aiHydrated=true
        agents[#agents+1]={id='test-dense-motorcycle-'..index,routeId=routeId,
            pathIndex=sample.pathIndex,dwell=0,bike=bike}
    end
    commute.aiMotorcycles=agents
end

local function returnPoints(world)
    local integrated=world.truckDestinations~=nil
    local planner=Routes.new(world.roads,{includeTruckOnly=integrated,pavedOnly=true,
        destinations=integrated and world.truckDestinations or nil})
    local site=world.sites.byId.warehouse
    if integrated and site and site.truckParking then
        local route=planner:findFromPoint(site.truckParking.x,site.truckParking.z,'mainland_exit')
        return route and route.points
    end
    local inbound=planner:findFromPoint(world.mainlandExit.x,world.mainlandExit.z,'warehouse')
    if not inbound then return nil end
    local result={}
    for index=#inbound.points,1,-1 do
        local point=inbound.points[index]
        result[#result+1]={x=point.x,z=point.z,h=point.h,
            speedLimit=point.speedLimit,turnAngle=point.turnAngle and -point.turnAngle or nil}
    end
    return result
end

local function stateWithReturnConvoy(town,world,points,epoch)
    local length=DrivingPath.length(points)
    local state={home={commute={participants={}}},jobs={active={},completed={}}}
    local trucks,initialPositions={},{}
    for index=1,RETURN_TRUCKS do
        local progress=.08+.68*(index-1)/(RETURN_TRUCKS-1)
        local sample=assert(DrivingPath.sample(points,length,progress))
        local truck=Truck.new(sample.x,sample.z,sample.heading,'plain')
        truck.h=world:supportHeight(truck.x,truck.z)
        truck.phase='departing';truck.pathIndex=sample.pathIndex
        local id=('DENSE-RETURN-%02d'):format(index)
        trucks[index]=truck
        initialPositions[index]={x=truck.x,z=truck.z}
        state.jobs.completed[index]={id=id,company='Millhaven Freight',pallets={},delivery={
            status='received',route={roadTownId=town.id,vehicle={phase='offmap'}},
            returnRoute={origin='warehouse',destinationCity='Millhaven',originCompany='Millhaven Freight',
                roadTownId=town.id,departedAtEpoch=epoch-20,arrivedAtEpoch=epoch+3600,vehicle=truck},
        }}
    end
    return state,trucks,initialPositions,length
end

function Test.run(check)
    local baseSeed=tonumber(os.getenv('PICTURE_SHOP_AI_TOWN_SEED')) or 712345
    local town=assert(Town.generate(baseSeed+500003))
    local world=Town.world(town)
    local points=assert(returnPoints(world),'a paved warehouse return route is required')
    local epoch=1700100000
    local state,trucks,initialPositions,routeLength=stateWithReturnConvoy(town,world,points,epoch)
    local routeStarted=love.timer.getTime()
    local motorcycleRoutes=BikeTraffic.routes(world)
    local motorcycleRouteInitMs=(love.timer.getTime()-routeStarted)*1000
    assert(motorcycleRoutes and motorcycleRoutes.pairCount>=1
        and #motorcycleRoutes==motorcycleRoutes.pairCount*2,
        'a complete motorcycle route pair is required')
    seedTestMotorcycles(state.home.commute,world,motorcycleRoutes)
    local function safeAfterStep()
        local safe=true
        for index,truck in ipairs(trucks) do
            safe=safe and Truck.valid(truck)
            for otherIndex=1,index-1 do
                local other=trucks[otherIndex]
                safe=safe and not Footprint.overlapsTruck(truck.x,truck.z,truck.heading,
                    other.x,other.z,other.heading,truck.model,other.model)
            end
        end
        for _,agent in ipairs(state.home.commute.aiMotorcycles or {}) do
            safe=safe and agent.bike.crashPending==nil
        end
        return safe
    end
    local coldStarted=love.timer.getTime()
    local originalTownWorld=Town.world
    local originalRoutesNew=Routes.new
    local originalFindFromPoint=Routes.findFromPoint
    local originalFind=Routes.find
    local townWorldBuilds=0
    local plannerBuildMs,pointSearchMs,namedSearchMs=0,0,0
    Town.world=function(value)
        townWorldBuilds=townWorldBuilds+1
        return originalTownWorld(value)
    end
    Routes.new=function(...)
        local started=love.timer.getTime()
        local planner=originalRoutesNew(...)
        plannerBuildMs=plannerBuildMs+(love.timer.getTime()-started)*1000
        return planner
    end
    Routes.findFromPoint=function(self,...)
        local started=love.timer.getTime()
        local result,reason=originalFindFromPoint(self,...)
        pointSearchMs=pointSearchMs+(love.timer.getTime()-started)*1000
        return result,reason
    end
    Routes.find=function(self,...)
        local started=love.timer.getTime()
        local result,reason=originalFind(self,...)
        namedSearchMs=namedSearchMs+(love.timer.getTime()-started)*1000
        return result,reason
    end
    local simulated,simulationError=pcall(Network.simulate,state,town,.05,epoch,world)
    Town.world=originalTownWorld
    Routes.new=originalRoutesNew
    Routes.findFromPoint=originalFindFromPoint
    Routes.find=originalFind
    if not simulated then error(simulationError,0) end
    local coldStartMs=(love.timer.getTime()-coldStarted)*1000
    local actorCount=#Network.actors(state,town,0,epoch)
    local originalTruckUpdate=Truck.update
    local truckUpdateCalls,truckUpdateTime,maxTruckStep=0,0,0
    Truck.update=function(truck,input,dt,activeWorld)
        truckUpdateCalls=truckUpdateCalls+1
        truckUpdateTime=truckUpdateTime+dt
        maxTruckStep=math.max(maxTruckStep,dt)
        return originalTruckUpdate(truck,input,dt,activeWorld)
    end
    local stepped,stepError=pcall(Network.simulate,state,town,.25,epoch,world)
    Truck.update=originalTruckUpdate
    if not stepped then error(stepError,0) end
    check('delivery_traffic_consumes_long_frames_in_shared_substeps',
        truckUpdateCalls==RETURN_TRUCKS*3
            and math.abs(truckUpdateTime-RETURN_TRUCKS*.25)<1e-8 and maxTruckStep<=.1)
    local safe=safeAfterStep()
    local stepTimes={}
    for _=1,SIMULATION_STEPS do
        local started=love.timer.getTime()
        Network.simulate(state,town,.05,epoch,world)
        stepTimes[#stepTimes+1]=(love.timer.getTime()-started)*1000
        safe=safe and safeAfterStep()
    end
    local movedCount=0
    for index,truck in ipairs(trucks) do
        local dx,dz=truck.x-initialPositions[index].x,truck.z-initialPositions[index].z
        if dx*dx+dz*dz>.5^2 then movedCount=movedCount+1 end
    end
    local motorcycleCount=#BikeTraffic.actors(state.home.commute)
    table.sort(stepTimes)
    local total=0
    for _,elapsed in ipairs(stepTimes) do total=total+elapsed end
    print(('AI_DELIVERY_DENSE_PERF actors=%d trucks=%d motorcycles=%d motorcycle_route_init_ms=%.3f planner_build_ms=%.3f from_point_ms=%.3f named_route_ms=%.3f cold_ms=%.3f combined_cold_ms=%.3f samples=%d mean_ms=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f'):
        format(actorCount,RETURN_TRUCKS,motorcycleCount,motorcycleRouteInitMs,plannerBuildMs,
            pointSearchMs,namedSearchMs,coldStartMs,motorcycleRouteInitMs+coldStartMs,#stepTimes,
            #stepTimes>0 and total/#stepTimes or 0,stepTimes[math.ceil(#stepTimes*.50)] or 0,
            stepTimes[math.ceil(#stepTimes*.95)] or 0,stepTimes[#stepTimes] or 0))
    check('delivery_traffic_dense_return_convoy_shares_indexed_roads_safely',
        routeLength>100 and actorCount>=TrafficActorIndex.MIN_ACTORS
            and TrafficActorIndex.shouldUse(actorCount) and motorcycleCount==BikeTraffic.MAX_BIKES
            and movedCount>=RETURN_TRUCKS-2 and safe and townWorldBuilds==0,
        ('route=%.1fm actors=%d movingTrucks=%d/%d safe=%s redundantWorldBuilds=%d'):format(
            routeLength,actorCount,movedCount,RETURN_TRUCKS,tostring(safe),townWorldBuilds))
end

return Test
