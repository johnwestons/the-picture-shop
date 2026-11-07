local Rules=require('src.commute.traffic_rules')
local Index=require('src.commute.traffic_actor_index')
local Test={}

local function bikeEntry(x,speed,id)
    return {id=id,kind='bike',halfLength=.65,halfWidth=.38,
        actor={x=x,z=0,heading=0,speed=speed,trafficKind='motorcycle'}}
end

function Test.run(check)
    local vehicle={x=0,z=0,heading=0,speed=7,trafficKind='motorcycle',trafficId='traffic-test'}
    local nearFast=bikeEntry(4,6,'near-fast')
    local farStopped=bikeEntry(10.5,0,'far-stopped')
    local farAway=bikeEntry(40,0,'far-away')
    local segment={lanes=2,width=7.2}
    local bridgeSegment={lanes=3,width=12,bridge=true}
    local bridgeLaneOffset=Rules.laneOffset(bridgeSegment,'right',false)
    local first=Rules.limitForTraffic(vehicle,8,{nearFast,farStopped,farAway},segment)
    local reversed=Rules.limitForTraffic(vehicle,8,{farStopped,nearFast,farAway},segment)
    local indexed=Rules.limitForTraffic(vehicle,8,nil,segment,Index.new({farStopped,nearFast,farAway}))
    local pedestrianAhead={id='pedestrian-ahead',kind='pedestrian',halfLength=.3,halfWidth=.55,
        actor={x=8,z=0,heading=0,speed=0}}
    local pedestrianYieldSpeed=Rules.limitForTraffic(vehicle,8,{pedestrianAhead},segment)
    local stoppingFollower={x=0,z=0,heading=0,speed=8.6,model='box',trafficId='braking-test'}
    local stoppedBox={id='stopped-box',kind='vehicle',halfLength=2.74,halfWidth=1.08,
        actor={x=20,z=0,heading=0,speed=0,model='box'}}
    local safeFollowingSpeed=Rules.limitForTraffic(stoppingFollower,8.6,{stoppedBox},segment)
    local indexedSafeFollowingSpeed=Rules.limitForTraffic(stoppingFollower,8.6,nil,segment,
        Index.new({stoppedBox}))
    local stoppingClearance=20-2.74-2.74-Rules.MIN_FOLLOW_GAP
    local brakingEnvelope=math.sqrt(2*Rules.brakeDeceleration(stoppingFollower)*stoppingClearance)
    local oncoming={id='player-bike',kind='bike',isPlayer=true,halfLength=.65,halfWidth=.38,
        actor={x=4,z=0,heading=math.pi,speed=3,trafficKind='motorcycle'}}
    local oneLane={lanes=1,width=4.2,oneWay=false}
    local yieldSpeed,yield=Rules.limitForTraffic(vehicle,8,{oncoming},oneLane)
    local indexedYieldSpeed,indexedYield=Rules.limitForTraffic(vehicle,8,nil,oneLane,Index.new({oncoming}))
    local junctionVehicle={trafficKind='motorcycle'}
    local stoppedInside={x=4,z=0,heading=0,speed=0}
    local stoppedOutside={x=7,z=0,heading=0,speed=0}
    local approachingJunction={x=9,z=0,heading=math.pi,speed=5}
    local leavingJunction={x=9,z=0,heading=0,speed=5}
    local occupiedByStopped=Rules.actorBlocksJunction(junctionVehicle,stoppedInside,'vehicle',0,0,5)
    local blockedByApproaching=Rules.actorBlocksJunction(junctionVehicle,approachingJunction,'vehicle',0,0,5)
    local clearOfDeparting=not Rules.actorBlocksJunction(junctionVehicle,leavingJunction,'vehicle',0,0,5)
    local clearOfDistantStopped=not Rules.actorBlocksJunction(junctionVehicle,stoppedOutside,'vehicle',0,0,5)

    local roadVehicle={x=0,z=1.8,heading=0,speed=6,trafficKind='motorcycle',trafficId='pass-test'}
    local twoLane={lanes=2,width=7.2,oneWay=false}
    local stoppedTruck={id='stopped-truck',kind='vehicle',halfLength=2.3,halfWidth=1.2,
        actor={x=8,z=1.8,heading=0,speed=0,model='box'}}
    local passOffset,passActor=Rules.passLaneOffset(roadVehicle,twoLane,1.8,{stoppedTruck})
    local indexedOffset,indexedActor=Rules.passLaneOffset(roadVehicle,twoLane,1.8,nil,
        Index.new({stoppedTruck}))
    local passingSpeed,passingYield=Rules.limitForTraffic(roadVehicle,8,{stoppedTruck},twoLane,
        nil,stoppedTruck.actor)
    local oncomingInPassLane={id='oncoming-pass-lane',kind='bike',halfLength=.65,halfWidth=.38,
        actor={x=6,z=-1.8,heading=math.pi,speed=5,trafficKind='motorcycle'}}
    local blockedPass=Rules.passLaneOffset(roadVehicle,twoLane,1.8,
        {stoppedTruck,oncomingInPassLane})
    local farOncomingInPassLane={id='far-oncoming-pass-lane',kind='bike',halfLength=.65,halfWidth=.38,
        actor={x=36,z=-1.8,heading=math.pi,speed=10,trafficKind='motorcycle'}}
    local closingTrafficPass=Rules.passLaneOffset(roadVehicle,twoLane,1.8,
        {stoppedTruck,farOncomingInPassLane})
    local indexedClosingTrafficPass=Rules.passLaneOffset(roadVehicle,twoLane,1.8,nil,
        Index.new({stoppedTruck,farOncomingInPassLane}))
    local distantOncomingInPassLane={id='distant-oncoming-pass-lane',kind='bike',halfLength=.65,halfWidth=.38,
        actor={x=100,z=-1.8,heading=math.pi,speed=10,trafficKind='motorcycle'}}
    local safeDistantPass=Rules.passLaneOffset(roadVehicle,twoLane,1.8,
        {stoppedTruck,distantOncomingInPassLane})
    local activePassVehicle={x=4,z=-1.8,heading=0,speed=6,trafficKind='motorcycle'}
    local activePassLookahead=Rules.passLookaheadSeconds(activePassVehicle,4,stoppedTruck.actor)
    local almostPastVehicle={x=12,z=-1.8,heading=0,speed=6,trafficKind='motorcycle'}
    local almostPastLookahead=Rules.passLookaheadSeconds(almostPastVehicle,-4,stoppedTruck.actor)
    local escapeBike={x=0,z=0,heading=0,speed=6,trafficKind='motorcycle'}
    local shoulderOncoming=bikeEntry(36,10,'shoulder-oncoming')
    shoulderOncoming.actor.z=-3;shoulderOncoming.actor.heading=math.pi
    local escapeOffset=Rules.passEscapeOffset(escapeBike,{lanes=2,width=12},-3,-3,
        {shoulderOncoming},nil,nil,1)
    local noEscapeOffset=Rules.passEscapeOffset(escapeBike,{lanes=2,width=6},-1.5,-1.5,
        {shoulderOncoming},nil,nil,1)
    local shoulderPedestrian={id='shoulder-pedestrian',kind='pedestrian',halfLength=.3,halfWidth=.55,
        actor={x=8,z=-2.52,heading=0,speed=0}}
    local pedestrianBlockedEscape=Rules.passEscapeOffset(escapeBike,{lanes=2,width=12},-3,-3,
        {shoulderPedestrian},nil,nil,1)
    local activePassBlocked=not Rules.laneClear(activePassVehicle,twoLane,-1.8,-1.8,
        {stoppedTruck,farOncomingInPassLane},nil,stoppedTruck.actor,activePassLookahead)
    local activePassSafe=Rules.laneClear(activePassVehicle,twoLane,-1.8,-1.8,
        {stoppedTruck,distantOncomingInPassLane},nil,stoppedTruck.actor,activePassLookahead)
    check('traffic_following_is_order_independent_and_uses_nearby_index',
        math.abs(first-reversed)<1e-8 and math.abs(first-indexed)<1e-8
            and first>6 and first<6.1 and yield and indexedYield
            and yieldSpeed==0 and indexedYieldSpeed==0)
    check('traffic_following_brakes_for_pedestrians_in_its_lane',
        pedestrianYieldSpeed<vehicle.speed and pedestrianYieldSpeed>0)
    check('traffic_centering_keeps_vehicles_clear_of_bridge_rails',bridgeLaneOffset==0)
    check('traffic_following_reserves_relative_braking_distance',
        safeFollowingSpeed<8.6 and math.abs(safeFollowingSpeed-brakingEnvelope)<1e-8
            and math.abs(indexedSafeFollowingSpeed-safeFollowingSpeed)<1e-8)
    check('junction_conflicts_include_stopped_occupants_and_approaching_traffic',
        occupiedByStopped and blockedByApproaching and clearOfDeparting and clearOfDistantStopped)
    check('traffic_passes_stopped_road_users_only_when_opposite_lane_is_clear',
        passOffset==-1.8 and passActor==stoppedTruck.actor
            and indexedOffset==passOffset and indexedActor==passActor
            and passingSpeed==3 and not passingYield and blockedPass==nil)
    check('traffic_pass_rejects_oncoming_users_that_can_reach_the_maneuver',
        closingTrafficPass==nil and indexedClosingTrafficPass==nil and safeDistantPass==-1.8)
    check('active_traffic_pass_rechecks_oncoming_conflicts_for_remaining_distance',
        activePassLookahead>almostPastLookahead and almostPastLookahead>0
            and activePassBlocked and activePassSafe)
    check('active_pass_evasion_uses_only_a_clear_paved_edge',
        escapeOffset and escapeOffset< -3 and noEscapeOffset==nil and pedestrianBlockedEscape==nil)
end

return Test
