local Terrain=require('src.commute.terrain')
local Roads=require('src.commute.roads')
local Rider=require('src.commute.rider')
local Gear=require('src.commute.gear')
local Test={}
function Test.run(check)
    local world=Roads.new():attach(Terrain.new())
    local r=Rider.new(100,380,0);Rider.update(r,{},0,world)
    assert(Rider.command(r,'equip',world))
    for _=1,40 do Rider.update(r,{},.1,world) end
    assert(Rider.command(r,'mount',world))
    for _=1,20 do Rider.update(r,{},.1,world) end
    check('commute_rider_starts_engine_after_complete_sequence',Gear.allowed(r.gear,'ride'))
    assert(Rider.command(r,'dismount',world))
    local saved=Rider.snapshot(r);local recovered=assert(Rider.restore(saved,world,world.roads.destinations.warehouse))
    check('commute_rider_interrupted_dismount_recovers_beside_bike',not recovered.gear.mounted
        and recovered.gear.outfit=='geared' and math.abs(recovered.ped.z-recovered.bike.z)>1)
    for _=1,15 do Rider.update(r,{},.1,world) end
    local distance=r.ped.distance;local bikeX,bikeZ=r.bike.x,r.bike.z
    for _=1,30 do Rider.update(r,{walkX=1},1/30,world) end
    check('commute_rider_walk_keeps_parked_bike_in_place',r.ped.distance>distance and r.bike.x==bikeX and r.bike.z==bikeZ)
    for _=1,10 do Rider.update(r,{},.1,world) end
    local stopped=r.ped.distance;local facing=r.ped.heading;Rider.update(r,{},.1,world)
    check('commute_rider_idle_preserves_facing_and_gait',r.ped.distance==stopped and r.ped.heading==facing)
    local a,b=Rider.new(100,380,0),Rider.new(100,380,0)
    for _=1,60 do Rider.update(a,{walkX=1},1/60,world);Rider.update(b,{walkX=1,walkZ=1},1/60,world) end
    check('commute_rider_diagonal_speed_normalized',math.abs(a.ped.distance-b.ped.distance)<.001)
    local blocked={supportHeight=function()return 1 end,roads={blocked=function()return true end}}
    local before=r.ped.distance
    for _=1,20 do Rider.update(r,{walkX=1,walkZ=1},.1,blocked) end
    check('commute_rider_collision_stops_gait',r.ped.distance==before and r.ped.speed==0)
    saved=Rider.snapshot(recovered);saved.bike.x=0/0
    local fallback=assert(Rider.restore(saved,world,world.roads.destinations.warehouse))
    check('commute_rider_invalid_position_recovers_suited_at_safe_lot',fallback.bike.x==100
        and fallback.gear.outfit=='geared' and not fallback.gear.mounted)
end
return Test
