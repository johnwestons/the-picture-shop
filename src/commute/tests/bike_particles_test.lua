local Particles=require('src.commute.bike_particles')
local Test={}
local function world(surface)
    local w={surface=surface or 'asphalt',supportHeight=function()return 0 end}
    w.roads={nearest=function()return 0,{surface=w.surface,width=6}end}
    return w
end
local function bike()
    return {x=50,z=70,h=0,heading=0,speed=0,throttle=0,grounded=true,pitch=0,slip=0,tireSlip=0}
end
local function tick(p,id,b,w,dt,engine,visual)
    p:advance(dt);p:emit(id,b,w,dt,visual,engine,true)
end
local function emitterCount(p)
    local count=0;for _ in pairs(p.emitters) do count=count+1 end;return count
end
local function travel(rate,surface,reportedSpeed)
    local p,b,w=Particles.new(),bike(),world(surface);local dt=1/rate
    b.speed=reportedSpeed or 6;p:emit('bike',b,w,dt,nil,false,true)
    for _=1,rate*2 do b.x=b.x+6*dt;tick(p,'bike',b,w,dt,false) end
    return p:stats().totalDust
end
function Test.run(check)
    local p,b,w=Particles.new(),bike(),world('dirt')
    for _=1,120 do tick(p,'bike',b,w,1/60,false) end
    check('bike_particles_stationary_engine_off_has_no_dust_or_exhaust',p:stats().active==0
        and p:stats().totalDust==0 and p:stats().totalExhaust==0)
    b.speed=8
    for _=1,30 do tick(p,'bike',b,w,1/60,false) end
    check('bike_particles_reported_speed_without_actual_movement_does_not_emit_dust',p:stats().totalDust==0)

    local tailpipe=true
    for n=0,7 do
        local smoke,rider=Particles.new(),bike();rider.heading=n*math.pi/4
        for _=1,3 do if #smoke.particles==0 then tick(smoke,'bike',rider,w,.1,true) end end
        local puff=smoke.particles[1];local c,s=math.cos(rider.heading),math.sin(rider.heading)
        local dx,dz=puff and puff.x-rider.x or 0,puff and puff.z-rider.z or 0
        tailpipe=tailpipe and smoke:stats().totalDust==0 and smoke:stats().totalExhaust==1
            and puff.kind=='exhaust' and math.abs(dx*c+dz*s+.80)<1e-9
            and math.abs(-dx*s+dz*c-.27)<1e-9 and math.abs(puff.h-rider.h-.83)<1e-9
    end
    check('bike_particles_idle_engine_exhaust_stays_at_physical_right_rear_tailpipe_across_headings',tailpipe)

    local rateIndependent,looseDensity=true,true
    local dirt30,road30=travel(30,'dirt'),travel(30,'asphalt')
    for _,rate in ipairs({30,60,120}) do
        local dirt,road=travel(rate,'dirt'),travel(rate,'asphalt')
        rateIndependent=rateIndependent and dirt==dirt30 and road==road30
        looseDensity=looseDensity and dirt>=road*4 and road>0
    end
    check('bike_particles_distance_spaced_dust_matches_at_30_60_120_fps',rateIndependent)
    check('bike_particles_dirt_trails_emit_more_dust_than_pavement_over_same_distance',looseDensity)
    check('bike_particles_dust_density_uses_traveled_distance_instead_of_speed_telemetry',
        travel(60,'dirt',18)==dirt30)

    local airborne,airBike=Particles.new(),bike();airBike.speed=6;airBike.grounded=false
    airborne:emit('bike',airBike,w,.1,nil,false,true)
    for _=1,20 do airBike.x=airBike.x+.6;tick(airborne,'bike',airBike,w,.1,false) end
    check('bike_particles_airborne_wheels_emit_no_road_dust',airborne:stats().totalDust==0)
    airBike.grounded=true
    for _=1,20 do airBike.x=airBike.x+.6;tick(airborne,'bike',airBike,w,.1,false,{grounded=false}) end
    check('bike_particles_remote_airborne_presentation_overrides_local_ground_contact',airborne:stats().totalDust==0)

    local jump,relocated=Particles.new(),bike();relocated.speed=6
    jump:emit('bike',relocated,w,.1,nil,false,true);relocated.x=3050
    tick(jump,'bike',relocated,w,.1,false)
    local noTeleportDust=jump:stats().totalDust==0
    relocated.x=3050.2;tick(jump,'bike',relocated,w,.1,false)
    noTeleportDust=noTeleportDust and jump:stats().totalDust==0
    relocated.x=3050.55;tick(jump,'bike',relocated,w,.1,false)
    check('bike_particles_teleports_do_not_paint_long_dust_bursts_or_carry_old_distance',
        noTeleportDust and jump:stats().totalDust==1 and jump.particles[1].x>3048)

    local change,surfaceBike,changing=Particles.new(),bike(),world('asphalt');surfaceBike.speed=10
    change:emit('bike',surfaceBike,changing,.1,nil,false,true)
    surfaceBike.x=surfaceBike.x+2.4;tick(change,'bike',surfaceBike,changing,.1,false)
    changing.surface='dirt';surfaceBike.x=surfaceBike.x+.05;tick(change,'bike',surfaceBike,changing,.1,false)
    local noBankedBurst=change:stats().totalDust==0
    surfaceBike.x=surfaceBike.x+.5;tick(change,'bike',surfaceBike,changing,.1,false)
    check('bike_particles_surface_changes_reset_spacing_without_banking_a_dirt_burst',
        noBankedBurst and change:stats().totalDust==1)

    local lingering,rider=Particles.new(),bike();rider.speed=6
    lingering:emit('bike',rider,w,.1,nil,true,true)
    for _=1,5 do rider.x=rider.x+.6;tick(lingering,'bike',rider,w,.1,true) end
    local before=lingering:stats();local existing=lingering.particles[1];local initialAge=existing.age
    rider.speed=0
    for _=1,6 do tick(lingering,'bike',rider,w,1/60,false) end
    local after=lingering:stats()
    check('bike_particles_stopping_and_engine_off_stop_new_emission_while_existing_puffs_age',
        before.totalDust>0 and before.totalExhaust>0 and after.totalDust==before.totalDust
        and after.totalExhaust==before.totalExhaust and after.active>0 and existing.age>initialAge)
    lingering:advance(2)
    check('bike_particles_old_puffs_expire_after_engine_and_movement_stop',lingering:stats().active==0)

    local drift,moving=Particles.new(),bike();moving.speed=6
    drift:emit('bike',moving,w,.1,nil,false,true);moving.x=moving.x+.6;tick(drift,'bike',moving,w,.1,false)
    local puff=drift.particles[1];local x,z=puff.x,puff.z;moving.x=moving.x+20
    drift:emit('bike',moving,w,.1,nil,false,true)
    local leftBehind=puff.x==x and puff.z==z
    drift:advance(.1)
    check('bike_particles_emitted_dust_remains_in_world_and_drifts_after_bike_passes',leftBehind
        and math.abs(puff.x-(x+puff.vx*.1))<1e-9 and math.abs(puff.z-(z+puff.vz*.1))<1e-9
        and math.abs(puff.x-moving.x)>19 and puff.h>.055)

    local shared=Particles.new();shared:add('dust',0,0,0,0,0,.2);local aged=shared.particles[1]
    shared:advance(.1)
    for i=1,4 do shared:emit(i,bike(),w,.1,nil,false,true) end
    check('bike_particles_multiple_actor_emission_does_not_advance_shared_clock_or_age_twice',
        math.abs(shared.time-.1)<1e-12 and math.abs(aged.age-.1)<1e-12)

    local bounded=Particles.new();local crowd={};local alwaysBounded=true
    for i=1,12 do crowd[i]=bike();crowd[i].z=70+i;crowd[i].speed=20;crowd[i].throttle=1 end
    for _=1,40 do
        bounded:advance(.1)
        for i,r in ipairs(crowd) do r.x=r.x+2;bounded:emit(i,r,w,.1,nil,true,true) end
        alwaysBounded=alwaysBounded and #bounded.particles<=Particles.MAX_PARTICLES and emitterCount(bounded)<=Particles.MAX_EMITTERS
    end
    check('bike_particles_particle_and_emitter_limits_hold_under_twelve_actor_pressure',alwaysBounded
        and #bounded.particles==192 and emitterCount(bounded)==8 and not bounded.emitters[9])
    bounded:advance(2);bounded:emit('replacement',bike(),w,.1,nil,false,true)
    check('bike_particles_inactive_emitters_expire_and_release_capacity',emitterCount(bounded)==1
        and bounded.emitters.replacement~=nil and #bounded.particles==0)
    local paused=Particles.new();paused:emit('bike',bike(),w,0,nil,true,true);paused:advance(0)
    check('bike_particles_zero_time_does_not_emit_or_advance',paused.time==0 and #paused.particles==0 and emitterCount(paused)==0)
end
return Test
