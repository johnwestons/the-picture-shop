-- One authoritative rider: the parked vehicle and pedestrian have independent
-- positions. Movement never equips gear and no scene transition removes it.
local Gear=require('src.commute.gear')
local Bike=require('src.commute.motorcycle')
local Truck=require('src.commute.delivery_truck')
local Fall=require('src.commute.rider_fall')
local M=require('src.commute.vendor.mathx')
local Service=require('src.commute.bike_service')
local Rider={WALK_SPEED=1.7,RADIUS=.32,FRAME_DISTANCE=.13}
local speedCurve={.96,.94,1.04,1.06,.96,.94,1.04,1.06}
local accelerationCurve={.92,.90,1.08,1.10,.92,.90,1.08,1.10}
local function gait(values,distance)
    local phase=distance/Rider.FRAME_DISTANCE;local index=math.floor(phase)
    return M.lerp(values[index%8+1],values[(index+1)%8+1],M.smooth(phase-index))
end
function Rider.new(x,z,heading,savedGear)
    return {ped={x=x,z=z+1.2,heading=heading or 0,distance=0,speed=0,vx=0,vz=0},
        bike=Bike.new(x,z,heading),gear=assert(Gear.restore(savedGear))}
end
function Rider.actor(r) return r.vehicle=='truck' and r.truck or r.gear.mounted and r.bike or r.ped end
function Rider.pose(r)
    if r.ped.crash then return 'crash',r.ped.crash.elapsed/Fall.DURATION end
    return Gear.pose(r.gear)
end
function Rider.clear(world,x,z,radius)
    for i=0,7 do local a=i*math.pi/4
        if world.roads:blocked(world,x+math.cos(a)*radius,z+math.sin(a)*radius) then return false end
    end
    return true
end
function Rider.footing(r,world)
    if r.bike.grounded==false or math.abs(r.bike.vy or 0)>.1 then return nil end
    for _,side in ipairs({1,-1}) do
        local x=r.bike.x-math.sin(r.bike.heading)*1.2*side
        local z=r.bike.z+math.cos(r.bike.heading)*1.2*side
        if Rider.clear(world,x,z,Rider.RADIUS) and math.abs(world:supportHeight(x,z)-world:supportHeight(r.bike.x,r.bike.z))<.45 then
            return x,z
        end
    end
end
function Rider.command(r,action,world)
    if r.ped.crash then return false,'Get back on your feet before using the motorcycle.' end
    if action=='rescue' then
        if r.gear.transition then return false,'Finish the current riding action first.' end
        local okay,message=Bike.rescue(r.bike,world)
        if not okay then return false,message end
        r.gear.engine=false
        r.ped.speed,r.ped.vx,r.ped.vz=0,0,0
        r.ped.heading=r.bike.heading
        if r.gear.mounted then
            r.ped.x,r.ped.z=r.bike.x,r.bike.z
        elseif M.length(r.ped.x-r.bike.x,r.ped.z-r.bike.z)>2 then
            local x,z=Rider.footing(r,world)
            if x then r.ped.x,r.ped.z=x,z end
        end
        return true,'Motorcycle moved to open ground. The engine is off.'
    end
    if not M.finite(r.bike.h) then Bike.resetContact(r.bike,world) end
    if (action=='dismount' or action=='ignition') and (not r.bike.grounded or math.abs(r.bike.vy or 0)>.1) then
        return false,'Wait until the motorcycle has landed and settled before getting off or switching the engine.'
    end
    if action=='ignition' or action=='headlight' or action=='beam' or action=='reverse' then
        if r.gear.transition or not r.gear.mounted then return false,'Mount the motorcycle and finish the current action first.' end
        if action=='ignition' then
            if not r.gear.engine and r.bike.service.fuel<=0 then return false,'Out of fuel. Visit the gas station for fuel.' end
            if r.bike.speed>.05 then return false,'Stop completely before switching the engine on or off.' end
            r.bike.speed=0;Bike.resetHorizontal(r.bike)
            r.gear.engine=not r.gear.engine;r.gear.revision=r.gear.revision+1
            r.bike.throttle=0;r.bike.boosting=false
            return true,r.gear.engine and 'Engine started.' or 'Engine off. E: dismount.'
        end
        return Bike.command(r.bike,action)
    end
    if action=='automatic' or action=='manual' or action=='shiftup' or action=='shiftdown' then
        if not Gear.allowed(r.gear,'ride') then return false,'Mount and start the motorcycle first.' end
        return Bike.command(r.bike,action)
    end
    local x,z=Rider.footing(r,world)
    local okay,reason=Gear.begin(r.gear,action,{nearBike=M.length(r.ped.x-r.bike.x,r.ped.z-r.bike.z)<=2,
        moving=r.ped.speed>.05,speed=r.gear.mounted and r.bike.speed or 0,safeFooting=x~=nil})
    if okay then
        r.ped.speed=0;r.ped.vx=0;r.ped.vz=0
        if action=='dismount' then r.dismountPoint={x=x,z=z} end
    end
    return okay,reason
end
function Rider.update(r,input,dt,world)
    dt=M.clamp(dt,0,.1)
    local previousMounted=r.gear.mounted
    local finished=Gear.update(r.gear,dt)
    if not Gear.allowed(r.gear,'ride') then
        require('src.commute.riding_animation').reset(r.bike)
    end
    if previousMounted and not r.gear.mounted then
        local point=r.dismountPoint
        local x,z=point and point.x,point and point.z
        if not x or not Rider.clear(world,x,z,Rider.RADIUS) then x,z=Rider.footing(r,world) end
        -- The controller reserves clear footing before beginning dismount.
        if x then r.ped.x,r.ped.z=x,z end
        r.ped.heading=r.bike.heading;r.dismountPoint=nil
    end
    if r.gear.engine and r.bike.service.fuel<=0 then
        r.gear.engine=false;r.gear.revision=r.gear.revision+1;finished=true
    end
    local powered=Gear.allowed(r.gear,'ride')
    local coasting=not powered and r.gear.mounted and not r.gear.transition
        and (r.bike.speed>.025 or r.bike.grounded==false)
    if powered or coasting then
        local controls=powered and input or {steer=input.steer,brake=math.max(input.brake or 0,input.drive or 0)}
        local meters=Bike.update(r.bike,controls,dt,world)
        if Service.run(r.bike,meters,dt,powered) then
            r.gear.engine=false;r.gear.revision=r.gear.revision+1
            r.bike.stallClock=0;r.bike.throttle=0;r.bike.boosting=false
            finished=true
        end
        r.ped.x,r.ped.z=r.bike.x,r.bike.z;r.ped.heading=r.bike.heading
        if r.bike.crashPending then
            Fall.begin(r,r.bike.crashPending,world,Rider.RADIUS,Rider.clear)
            r.bike.crashPending=nil
            r.dismountPoint=nil
            finished=true
        end
    elseif r.ped.crash then
        finished=Fall.update(r.ped,dt)
    elseif Gear.allowed(r.gear,'walk') then
        local p=r.ped;local dx,dz=input.walkX or 0,input.walkZ or 0
        local magnitude=M.length(dx,dz)
        if magnitude>1 then dx,dz=dx/magnitude,dz/magnitude end
        local speed=Rider.WALK_SPEED*gait(speedCurve,p.distance)
        local tx,tz=dx*speed,dz*speed
        local reversal=p.vx*tx+p.vz*tz<0
        local acceleration=(magnitude<.001 or reversal) and 12 or 8*gait(accelerationCurve,p.distance)
        local deltaX,deltaZ=tx-p.vx,tz-p.vz;local delta=M.length(deltaX,deltaZ)
        local blend=delta>0 and math.min(1,acceleration*dt/delta) or 1
        p.vx,p.vz=p.vx+deltaX*blend,p.vz+deltaZ*blend
        local x0,z0=p.x,p.z
        local steps=math.max(1,math.ceil(M.length(p.vx,p.vz)*dt/.12))
        for _=1,steps do
            local nx,nz=p.x+p.vx*dt/steps,p.z+p.vz*dt/steps
            if Rider.clear(world,nx,p.z,Rider.RADIUS) then p.x=nx else p.vx=0 end
            if Rider.clear(world,p.x,nz,Rider.RADIUS) then p.z=nz else p.vz=0 end
        end
        local moved=M.length(p.x-x0,p.z-z0)
        p.distance=p.distance+moved;p.speed=dt>0 and moved/dt or 0
        if moved>1e-7 then p.heading=math.atan2(p.z-z0,p.x-x0) end
    end
    if not powered and not coasting then Bike.settle(r.bike,dt,world) end
    r.ped.h=world:supportHeight(r.ped.x,r.ped.z)
    return finished
end
function Rider.snapshot(r)
    local gear=Gear.snapshot(r.gear)
    local ped={x=r.ped.x,z=r.ped.z,heading=r.ped.heading}
    if r.gear.transition and r.gear.transition.kind=='dismount' and r.dismountPoint then
        ped.x,ped.z=r.dismountPoint.x,r.dismountPoint.z
    end
    local result={gear=gear,ped=ped,bike={x=r.bike.x,z=r.bike.z,heading=r.bike.heading,
        gear=r.bike.gear or 1,transmission=r.bike.transmission or 'automatic',
        upgradeLevel=r.bike.upgradeLevel or 0,paintId=r.bike.paintId or require('src.commute.bike_paint').DEFAULT,
        damage=r.bike.damage or 0,service=Service.copy(r.bike.service),
        reverse=r.bike.reverse==true,headlight=r.bike.headlight==true,
        headlightHighBeam=r.bike.headlightHighBeam==true},
        vehicle=r.vehicle,transport=r.transport}
    if r.vehicle=='truck' and Truck.valid(r.truck) then result.truck=Truck.snapshot(r.truck) end
    return result
end
function Rider.restore(saved,world,anchor)
    if type(saved)~='table' then return nil,'Invalid saved rider.' end
    local gear,reason=Gear.restore(saved.gear);if not gear then return nil,reason end
    if saved.vehicle~=nil and saved.vehicle~='truck' or saved.transport~=nil and saved.transport~='truck'
        or saved.vehicle=='truck' and (gear.mounted or not Truck.valid(saved.truck)) then return nil,'Invalid saved vehicle.' end
    if not Bike.valid(saved.bike) then return nil,'Invalid saved transmission.' end
    local function validPosition(p,radius,solidBike)
        if not (type(p)=='table' and M.finite(p.x) and M.finite(p.z) and M.finite(p.heading)
            and Rider.clear(world,p.x,p.z,radius)) then return false end
        if solidBike and world.sweepObstacles then
            local h=world:supportHeight(p.x,p.z)
            return world:sweepObstacles(p.x,p.z,p.x,p.z,radius,h,h+Bike.COLLISION_HEIGHT)==nil
        end
        return true
    end
    if not validPosition(saved.ped,Rider.RADIUS) or not validPosition(saved.bike,Bike.RADIUS,true) then
        -- Save compatibility recovery is always parked, still wearing the
        -- stable outfit. The caller supplies the last safe origin/destination.
        gear.mounted=false;gear.engine=false
        local r=Rider.new(anchor.x,anchor.z,anchor.heading or 0,gear)
        if anchor.pedX then r.ped.x,r.ped.z=anchor.pedX,anchor.pedZ end
        r.bike.transmission=saved.bike.transmission or 'automatic'
        r.bike.upgradeLevel=saved.bike.upgradeLevel or 0
        r.bike.service=Service.copy(saved.bike.service)
        r.bike.damage=saved.bike.damage or 0
        r.bike.paintId=saved.bike.paintId or require('src.commute.bike_paint').DEFAULT
        Rider.update(r,{},0,world);return r,'Recovered at parking area.'
    end
    local r=Rider.new(saved.bike.x,saved.bike.z,saved.bike.heading,gear)
    r.bike.transmission=saved.bike.transmission or 'automatic'
    r.bike.upgradeLevel=saved.bike.upgradeLevel or 0
    r.bike.service=Service.copy(saved.bike.service)
    r.bike.damage=saved.bike.damage or 0
    r.bike.paintId=saved.bike.paintId or require('src.commute.bike_paint').DEFAULT
    r.bike.reverse=saved.bike.reverse==true;r.bike.headlight=saved.bike.headlight==true
    r.bike.headlightHighBeam=saved.bike.headlightHighBeam==true
    r.bike.gear=r.bike.transmission=='manual' and (saved.bike.gear or 1) or 1
    r.ped.x,r.ped.z,r.ped.heading=saved.ped.x,saved.ped.z,saved.ped.heading
    r.transport=saved.transport
    if saved.vehicle=='truck' then r.vehicle='truck';r.truck=Truck.snapshot(saved.truck) end
    if gear.mounted then r.ped.x,r.ped.z=r.bike.x,r.bike.z end
    Rider.update(r,{},0,world);return r
end
return Rider
