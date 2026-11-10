local Gps=require('src.commute.gps')
local Test={}
function Test.run(check)
    local route={points={{x=0,z=0},{x=60,z=0},{x=60,z=80}}}
    local path=Gps.prepare(route)
    local nextTurn=Gps.guidance(path,{x=10,z=0,heading=0})
    check('gps_right_turn_uses_road_distance',nextTurn.kind=='right' and nextTurn.distance==50 and nextTurn.remaining==130)
    local advanced=Gps.guidance(path,{x=45,z=0,heading=0})
    check('gps_counts_down_without_waiting_for_route_refresh',advanced.distance==15 and advanced.remaining==95)
    local passed=Gps.guidance(path,{x=60,z=30,heading=math.pi/2})
    check('gps_passed_turn_drops_old_instruction',passed.kind=='straight' and passed.remaining==50)
    local left=Gps.guidance(Gps.prepare({points={{x=0,z=0},{x=60,z=0},{x=60,z=-80}}}),{x=10,z=0,heading=0})
    check('gps_left_turn_matches_world_axes',left.kind=='left' and left.distance==50)
    check('gps_wrong_way_has_safe_turnaround_instruction',Gps.guidance(path,{x=10,z=0,heading=math.pi}).kind=='uturn')
    check('gps_off_route_requests_rejoin',Gps.guidance(path,{x=10,z=-40,heading=0}).kind=='rejoin')
    local joining=Gps.prepare({points={{x=0,z=-40},{x=0,z=0},{x=60,z=0}},joinDistance=40})
    local rejoin=Gps.guidance(joining,{x=0,z=-30,heading=math.pi/2})
    check('gps_recalculated_offroad_connector_keeps_rejoin_guidance',rejoin.kind=='rejoin' and rejoin.distance==30)
    check('gps_arrival_requires_nearby_endpoint',Gps.guidance(path,{x=60,z=77,heading=math.pi/2}).kind=='arrive')
    check('gps_near_start_is_not_arrival',Gps.guidance(path,{x=0,z=0,heading=0}).kind~='arrive')
    check('gps_missing_route_is_explicit',Gps.guidance(Gps.prepare(nil),{x=0,z=0}).kind=='unavailable')
    local noisy={points={}}
    for x=0,100 do noisy.points[#noisy.points+1]={x=x,z=math.sin(x)*.08} end
    check('gps_tessellation_noise_does_not_create_turns',#Gps.prepare(noisy).turns==0)
    local curve={points={{x=0,z=0},{x=40,z=0}}}
    for i=1,20 do
        local a=i/20*math.pi/2
        curve.points[#curve.points+1]={x=40+8*math.sin(a),z=8-8*math.cos(a)}
    end
    curve.points[#curve.points+1]={x=48,z=80}
    local rounded=Gps.prepare(curve)
    check('gps_curved_junction_produces_one_turn',#rounded.turns==1 and rounded.turns[1].angle>0)
    check('gps_distance_units_are_readable',Gps.distance(1240)=='1.2 km' and Gps.distance(37)=='37 m')
end
return Test
