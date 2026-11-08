local Network=require('src.commute.delivery_traffic')
local DrivingPath=require('src.commute.driving_path')
local TrafficRules=require('src.commute.traffic_rules')
local TrafficActorIndex=require('src.commute.traffic_actor_index')
local Truck=require('src.commute.delivery_truck')
local Footprint=require('src.commute.truck_footprint')
local Town=require('src.commute.town')
local Test={}

local function angleDifference(a,b)
    return math.atan2(math.sin(a-b),math.cos(a-b))
end

local function sample(path,station)
    return DrivingPath.sample(path.points,path.length,station/path.length)
end

local function straightApproach(world)
    local best
    for _,path in ipairs(world.roads.paths or {}) do
        if path.lanes==2 and not path.oneWay and path.role~='drive' and path.surface~='dirt'
            and path.width>=6 and path.length>=36 then
            for station=20,path.length-10,2 do
                local start,center,finish=sample(path,station-18),sample(path,station),sample(path,station+8)
                if math.abs(angleDifference(start.heading,finish.heading))<.16
                    and (not best or path.length>best.path.length) then
                    best={path=path,station=station,start=start,center=center}
                end
            end
        end
    end
    return best
end

function Test.run(check,town)
    town=town or assert(Town.generate(712345))
    local world=Town.world(town)
    local approach=straightApproach(world)
    if not approach then
        check('delivery_truck_stops_and_dwells_at_a_stop_fixture',false,'no straight two-lane approach was found')
        return
    end

    local points={}
    for offset=-18,-3,3 do
        local point=sample(approach.path,approach.station+offset)
        points[#points+1]={x=point.x,z=point.z,h=point.h}
    end
    local stopPoint=approach.center
    points[#points+1]={x=stopPoint.x,z=stopPoint.z,h=stopPoint.h}
    for offset=3,9,3 do
        local point=sample(approach.path,approach.station+offset)
        points[#points+1]={x=point.x,z=point.z,h=point.h}
    end

    local heading=stopPoint.heading
    local approachX,approachZ=math.cos(heading),math.sin(heading)
    local normalX,normalZ=-approachZ,approachX
    local reach=approach.path.width*.5+1.3
    local stopFixture={kind='stop',roadId=approach.path.id,roadWidth=approach.path.width,
        stopX=stopPoint.x,stopZ=stopPoint.z,fx=-approachX,fz=-approachZ,
        x=stopPoint.x+normalX*reach,z=stopPoint.z+normalZ*reach,
        junctionX=stopPoint.x+approachX*12,junctionZ=stopPoint.z+approachZ*12}
    world.infrastructure.fixtures={stopFixture}

    local offset=TrafficRules.laneOffset(approach.path,TrafficRules.drivingSide(world.town),false)
    local startHeading=math.atan2(points[2].z-points[1].z,points[2].x-points[1].x)
    local startX,startZ=TrafficRules.lanePoint(points[1],startHeading,offset)
    local truck=Truck.new(startX,startZ,startHeading,'plain')
    truck.speed=8.6
    truck.h=world:supportHeight(truck.x,truck.z)
    local dimensions=Footprint.dimensions(truck)
    local occupant=Truck.new(stopFixture.junctionX,stopFixture.junctionZ,heading,'plain')
    occupant.speed=0
    occupant.h=world:supportHeight(occupant.x,occupant.z)
    local occupantDimensions=Footprint.dimensions(occupant)
    local truckEntry={actor=truck,id='stop-control-test',kind='vehicle',
        halfLength=dimensions.halfLength,halfWidth=dimensions.halfWidth}
    local occupantEntry={actor=occupant,id='stopped-junction-occupant',kind='vehicle',
        halfLength=occupantDimensions.halfLength,halfWidth=occupantDimensions.halfWidth}
    world.trafficActors={truckEntry,occupantEntry}
    world.trafficActorIndex=TrafficActorIndex.new(world.trafficActors)
    Network.installVehicleObstacles(nil,world)

    local stoppedAt,crossedAt=nil,nil
    local elapsed=0
    local crossedWhileOccupied=false
    for _=1,1200 do
        Network.driveRoute(truck,points,.05,world,'stop-control-test')
        elapsed=elapsed+.05
        local distance=(stopFixture.stopX-truck.x)*approachX+(stopFixture.stopZ-truck.z)*approachZ
        local frontGap=distance-dimensions.halfLength-.35
        if not stoppedAt and truck.speed<.22 and frontGap<=.18 and frontGap>=-.35 then
            stoppedAt=elapsed
        end
        if frontGap<-.5 then
            crossedWhileOccupied=true
            break
        end
        if stoppedAt and elapsed-stoppedAt>=1.25 then break end
    end
    local waitedForOccupiedJunction=stoppedAt~=nil and not crossedWhileOccupied
        and elapsed-stoppedAt>=1.25 and truck.speed<.22
    world.trafficActors={truckEntry}
    world.trafficActorIndex=TrafficActorIndex.new(world.trafficActors)
    for _=1,300 do
        Network.driveRoute(truck,points,.05,world,'stop-control-test')
        elapsed=elapsed+.05
        local distance=(stopFixture.stopX-truck.x)*approachX+(stopFixture.stopZ-truck.z)*approachZ
        local frontGap=distance-dimensions.halfLength-.35
        if frontGap<-.5 then crossedAt=elapsed;break end
    end
    local dwellSeconds=stoppedAt and crossedAt and crossedAt-stoppedAt or 0
    check('delivery_truck_stops_and_dwells_at_a_stop_fixture',
        waitedForOccupiedJunction and crossedAt~=nil and dwellSeconds>=1.25,
        ('foundApproach=%s waitedForOccupant=%s crossedAt=%s dwell=%.2fs'):
            format(tostring(approach~=nil),tostring(waitedForOccupiedJunction),
                tostring(crossedAt),dwellSeconds))

    local weakWorld=setmetatable({world},{__mode='v'})
    local weakDriver=setmetatable({truck},{__mode='v'})
    world,truck,town,points,approach,stopPoint,stopFixture,truckEntry,
        occupant,occupantEntry,dimensions,occupantDimensions=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
    for _=1,6 do collectgarbage('collect') end
    check('junction_claims_release_discarded_worlds',
        weakWorld[1]==nil,
        ('worldRetained=%s driverRetained=%s'):format(
            tostring(weakWorld[1]~=nil),tostring(weakDriver[1]~=nil)))
end

return Test
