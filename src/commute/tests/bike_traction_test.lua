local Bike=require('src.commute.motorcycle')
local Test={}
local function world(dirt)
    return {supportHeight=function()return 0 end,
        roads={nearest=function()return dirt and 20 or 0,{width=6} end,
            blocked=function()return false end}}
end
local function moving(speed)
    local p=Bike.new(0,0,0);p.speed=speed or 10;p.gear=4;return p
end
local function run(p,w,input,seconds,hz)
    hz=hz or 120
    for _=1,math.floor(seconds*hz+.5) do Bike.update(p,input,1/hz,w) end
    return p
end
function Test.run(check)
    local road,dirt=world(),world(true)
    local paved=run(moving(),road,{throttle=1,steer=1},1)
    local loose=run(moving(),dirt,{throttle=1,steer=1},1)
    check('bike_dirt_corner_retains_momentum_outside_facing_direction',math.abs(loose.lateralSpeed)>3
        and loose.slip>.5 and loose.z<paved.z and loose.surface=='dirt')
    check('bike_pavement_has_more_cornering_grip_than_dirt',math.abs(paved.lateralSpeed)<1
        and paved.slip<.15 and paved.surface=='road' and loose.tireSlip>paved.tireSlip)
    local glide=run(moving(),dirt,{steer=1},.8)
    local braking=run(moving(),dirt,{steer=1,brake=.7},.8)
    check('bike_braking_uses_corner_grip_and_can_start_dirt_slide',braking.slip>glide.slip+.25
        and math.abs(braking.lateralSpeed)>math.abs(glide.lateralSpeed) and braking.speed<glide.speed)
    run(loose,dirt,{throttle=.5},3)
    check('bike_easing_steering_recovers_grip_without_stopping',loose.speed>5
        and math.abs(loose.lateralSpeed)<.01 and loose.slip<.01)

    local hard=run(moving(),road,{brake=1},3)
    local soft=run(moving(),dirt,{brake=1},3)
    check('bike_dirt_braking_distance_exceeds_pavement',hard.speed==0 and soft.speed==0
        and soft.distance>hard.distance*1.4 and soft.distance<hard.distance*2)
    local partial=run(moving(),road,{brake=.35},1)
    local full=run(moving(),road,{brake=1},1)
    check('bike_analog_brake_pressure_changes_stopping_force',full.speed<partial.speed-4)
    local held=Bike.new(0,0,0)
    run(held,dirt,{throttle=1,brake=1,steer=1},2)
    check('bike_brake_wins_over_throttle_at_rest',held.speed==0 and held.x==0 and held.z==0)
    local gentle=Bike.new(0,0,0);local eager=Bike.new(0,0,0)
    run(gentle,dirt,{throttle=.3},2);run(eager,dirt,{throttle=1},2)
    check('bike_dirt_acceleration_retains_analog_throttle',eager.speed>gentle.speed+2)
    local tuned=Bike.new(0,0,0);tuned.upgradeLevel=3
    Bike.update(tuned,{throttle=1,boost=true},1/120,dirt)
    check('bike_upgraded_launch_respects_dirt_traction_limit',tuned.acceleration<=Bike.DIRT_GRIP
        and tuned.tireSlip>0 and tuned.speed>0)

    local airborne=moving(12);airborne.h=100;airborne.grounded=false
    run(airborne,road,{throttle=1,brake=1,steer=1},.5)
    check('bike_airborne_steering_does_not_redirect_velocity',airborne.heading>.02
        and airborne.x>5.9 and math.abs(airborne.z)<1e-10 and math.abs(airborne.vz)<1e-10)
    check('bike_airborne_braking_has_no_tire_grip',airborne.speed>11.8
        and airborne.slip==0 and airborne.tireSlip==0 and not airborne.grounded)

    local results={}
    for _,hz in ipairs({30,60,120}) do
        local p=moving();run(p,dirt,{throttle=1,steer=.9},1,hz)
        run(p,dirt,{brake=.65,steer=-.5},1,hz)
        run(p,dirt,{throttle=.4},2,hz);results[#results+1]=p
    end
    check('bike_slide_brake_and_recovery_match_30_60_120hz',
        math.abs(results[1].x-results[2].x)<1e-8 and math.abs(results[1].z-results[3].z)<1e-8
        and math.abs(results[1].vx-results[3].vx)<1e-8 and math.abs(results[1].vz-results[3].vz)<1e-8)
    local reverse=Bike.new(0,0,0);assert(Bike.command(reverse,'reverse'))
    run(reverse,dirt,{throttle=1,steer=.5},2);run(reverse,dirt,{brake=1},1)
    check('bike_reverse_keeps_slow_speed_and_stops_lateral_motion',reverse.x<0
        and reverse.heading>math.pi and reverse.speed==0 and reverse.vx==0 and reverse.vz==0)
    local scalar=Bike.new(0,0,0);scalar.speed=8
    Bike.update(scalar,{},1/120,road)
    check('bike_legacy_scalar_speed_initializes_world_velocity',scalar.vx>7.9
        and scalar.vz==0 and scalar.x>0)
    scalar.speed=0;Bike.resetHorizontal(scalar)
    check('bike_parking_reset_clears_momentum_and_slide_feedback',scalar.vx==0 and scalar.vz==0
        and scalar.slip==0 and scalar.tireSlip==0 and scalar.lateralSpeed==0)
    local slide=run(moving(),dirt,{throttle=1,steer=1},1)
    local oldX,oldZ,oldVx,oldVz=slide.x,slide.z,slide.vx,slide.vz
    Bike.update(slide,{},0,dirt)
    check('bike_zero_dt_preserves_position_and_lateral_momentum',slide.x==oldX and slide.z==oldZ
        and slide.vx==oldVx and slide.vz==oldVz)

    -- The collision module supplies exact swept time and an outward normal.
    -- Exercise the controller response independently of generated scenery.
    local barrier=world()
    function barrier:sweepObstacles(x,z,nx,nz,radius)
        local edge=5-radius
        if x<edge and nx>=edge then return (edge-x)/(nx-x),-1,0,'tree','test-trunk' end
    end
    local hit=moving(26.8);hit.upgradeLevel=3
    run(hit,barrier,{},.3,30)
    check('bike_swept_prop_hit_stops_center_impact_without_tunneling',hit.x<5-Bike.RADIUS
        and hit.x>5-Bike.RADIUS-.01 and hit.speed==0 and hit.vx==0 and hit.vz==0
        and hit.impactPulse>0 and hit.collisionKind=='tree' and hit.collisionId=='test-trunk')
    local glance=moving(12);glance.heading=math.pi/6
    run(glance,barrier,{},.6)
    check('bike_glancing_prop_hit_removes_only_inward_momentum',glance.x<5-Bike.RADIUS
        and math.abs(glance.vx)<.01 and glance.vz>1 and glance.speed>1 and glance.z>2)
    local airborneHit=moving(26.8);airborneHit.upgradeLevel=3;airborneHit.h=3;airborneHit.vy=3;airborneHit.grounded=false
    local seenBottom,seenTop
    function barrier:sweepObstacles(x,z,nx,nz,radius,bottom,top)
        seenBottom,seenTop=bottom,top
    end
    Bike.update(airborneHit,{},1/120,barrier)
    check('bike_collision_sweep_supplies_body_vertical_interval',seenBottom>=3
        and seenTop>seenBottom+Bike.COLLISION_HEIGHT-.001)
end
return Test
