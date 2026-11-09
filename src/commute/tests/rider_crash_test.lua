local Rider = require('src.commute.rider')
local Gear = require('src.commute.gear')
local Obstacles = require('src.commute.obstacles')
local M = require('src.commute.vendor.mathx')
local Test = {}

local function crashSite()
    -- A rock ahead, a trunk to its left and a steep drop to its right.
    local props = {
        {kind='rock',x=101.3,z=100,h=3,collisionRadius=.4,collisionHeight=1.5},
        {kind='oak',x=100.1,z=98.8,h=3,collisionRadius=.4,collisionHeight=4},
    }
    local world = {roads={}}
    function world:supportHeight(x,z) return z>100.8 and -1 or 3 end
    function world.roads:blocked(_,x,z) return world:supportHeight(x,z)<.25 end
    function world.roads:nearest() return 0,{surface='paved',width=7} end
    function world:sweepObstacles(x,z,nx,nz,radius,bottom,top)
        local first,nxHit,nzHit,kind,id
        for i,prop in ipairs(props) do
            local t,a,b=Obstacles.sweep(x,z,nx,nz,radius,prop,bottom,top)
            if t and (not first or t<first) then first,nxHit,nzHit,kind,id=t,a,b,prop.kind,i end
        end
        return first,nxHit,nzHit,kind,id
    end
    return world
end

function Test.run(check)
    local world = crashSite()
    local rider = Rider.new(100,100,0,{version=1,outfit='geared',mounted=true,engine=true,revision=1})
    local bike,ped = rider.bike,rider.ped
    bike.upgradeLevel,bike.speed = 3,21
    for i=1,10 do
        if Rider.update(rider,{throttle=1},1/60,world) then break end
    end
    check('crash_hard_rock_hit_dismounts_rider_once_and_stops_bike',
        Rider.pose(rider)=='crash' and not rider.gear.mounted and not rider.gear.engine
        and rider.gear.outfit=='geared' and rider.gear.revision==2 and bike.damage>0
        and bike.speed==0 and bike.vx==0 and bike.vz==0 and not bike.crashPending)
    local bikeX,bikeZ=bike.x,bike.z
    local blockedMount=not Rider.command(rider,'mount',world)
    local clear=true
    local pose,progress
    for i=1,90 do
        Rider.update(rider,{walkX=1},1/60,world)
        local h=world:supportHeight(ped.x,ped.z)
        clear=clear and h==3 and Rider.clear(world,ped.x,ped.z,Rider.RADIUS)
            and world:sweepObstacles(ped.x,ped.z,ped.x,ped.z,Rider.RADIUS,h,h+1.5)==nil
        if i==36 then pose,progress=Rider.pose(rider) end
        if not ped.crash then break end
    end
    check('crash_recovery_keeps_throw_clear_of_second_trunk_and_cliff',
        blockedMount and clear and pose=='crash' and progress>.4 and progress<.6
        and not ped.crash and bike.x==bikeX and bike.z==bikeZ and ped.distance==0
        and M.length(ped.x-bikeX,ped.z-bikeZ)>2)
    local saved=Rider.snapshot(rider)
    local function restore() return assert(Rider.restore(saved,world,{x=100,z=100})) end
    local loaded=restore()
    check('crash_restores_stopped_damaged_bike_and_standing_suited_rider',
        loaded.bike.damage==bike.damage and loaded.bike.speed==0 and not loaded.ped.crash
        and not loaded.gear.mounted and not loaded.gear.engine)
    saved.bike.x=0/0
    local recovered=restore()
    saved.bike.damage=nil
    local legacy=restore()
    check('crash_parking_recovery_preserves_damage_and_old_saves_default_to_healthy',
        recovered.bike.damage==bike.damage and legacy.bike.damage==0)

    -- Walk back towards the bike until within the normal mount range.
    local dx,dz=bikeX-ped.x,bikeZ-ped.z
    local distance=M.length(dx,dz)
    for i=1,180 do
        if M.length(bikeX-ped.x,bikeZ-ped.z)<1.7 then break end
        Rider.update(rider,{walkX=dx/distance,walkZ=dz/distance},1/60,world)
    end
    for i=1,20 do Rider.update(rider,{},1/60,world) end
    local mount=Rider.command(rider,'mount',world)
    for i=1,110 do Rider.update(rider,{},1/60,world) end
    check('crash_walk_back_and_normal_remount_restore_riding_without_repair',
        mount and Gear.allowed(rider.gear,'ride') and bike.damage>0 and not ped.crash)
end

return Test
