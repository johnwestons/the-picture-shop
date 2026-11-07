-- Rigid box truck with front-wheel steering and surface-dependent tire grip.
local M=require('src.commute.vendor.mathx')
local liveries=require('src.commute.truck_liveries')
local footprint=require('src.commute.truck_footprint')
local Truck={MAX_SPEED=13.6,REVERSE_SPEED=3.2,ACCELERATION=1.75,BRAKE=4.4,COAST=1.15,
    WHEELBASE=3.5,STEER_LOCK=math.rad(38),RADIUS=1.18,COLLISION_HEIGHT=footprint.height,FRAME_DISTANCE=.12,
    TANK_LITERS=60,FUEL_PER_METER=.0003}
local profiles={box={maxSpeed=13.6,reverseSpeed=3.2,acceleration=1.75,brake=4.4,coast=1.15,
    wheelbase=3.5,steerLock=math.rad(38)},kei={maxSpeed=14.8,reverseSpeed=3.2,
    acceleration=2.05,brake=4.7,coast=1.15,wheelbase=2.15,steerLock=math.rad(42)}}
local soundProfiles={box='box',kei='box'}
function Truck.profile(vehicle)
    local model=type(vehicle)=='table' and vehicle.model or vehicle
    return profiles[model or 'box'] or profiles.box
end
function Truck.radius(vehicle)return footprint.dimensions(vehicle).radius end
function Truck.collisionHeight(vehicle)return footprint.dimensions(vehicle).height end
function Truck.audioProfile(vehicle)
    local model=type(vehicle)=='table' and vehicle.model or vehicle
    return soundProfiles[model or 'box'] or soundProfiles.box
end

function Truck.new(x,z,heading,livery,model)
    return {x=x,z=z,heading=heading or 0,livery=livery or 'plain',model=model or 'box',speed=0,reverse=false,distance=0,
        h=0,pitch=0,steering=0,throttle=0,brake=0,acceleration=0,
        fuel=Truck.TANK_LITERS,fuelRevision=0,engine=true,headlight=false,headlightHighBeam=false,turnSignal=nil}
end

function Truck.valid(p)
    return type(p)=='table' and M.finite(p.x) and M.finite(p.z) and M.finite(p.heading)
        and (p.model==nil or profiles[p.model]~=nil)
        and (p.fuelRevision==nil or M.finite(p.fuelRevision) and p.fuelRevision%1==0 and p.fuelRevision>=0)
        and (p.livery==nil or liveries[p.livery]~=nil)
        and p.x>=0 and p.x<=512 and p.z>=0 and p.z<=512
        and M.finite(p.speed) and p.speed>=0 and p.speed<=Truck.profile(p).maxSpeed
        and (p.reverse==nil or type(p.reverse)=='boolean')
        and (p.engine==nil or type(p.engine)=='boolean')
        and (p.fuel==nil or M.finite(p.fuel) and p.fuel>=0 and p.fuel<=Truck.TANK_LITERS)
        and (p.headlight==nil or type(p.headlight)=='boolean')
        and (p.headlightHighBeam==nil or type(p.headlightHighBeam)=='boolean')
        and (p.turnSignal==nil or p.turnSignal=='left' or p.turnSignal=='right')
        and (p.distance==nil or M.finite(p.distance) and p.distance>=0 and p.distance<=1e12)
        and (p.h==nil or M.finite(p.h) and p.h>=-2 and p.h<=100)
        and (p.pitch==nil or M.finite(p.pitch) and math.abs(p.pitch)<=1.6)
        and (p.steering==nil or M.finite(p.steering) and math.abs(p.steering)<=1)
        and (p.slipAngle==nil or M.finite(p.slipAngle) and math.abs(p.slipAngle)<=.5)
        and (p.homeX==nil or M.finite(p.homeX)) and (p.homeZ==nil or M.finite(p.homeZ))
end

function Truck.snapshot(p)
    return {x=p.x,z=p.z,heading=p.heading,speed=p.speed or 0,reverse=p.reverse==true,
        livery=p.livery or 'picture_shop', -- Older towns only had the shop's delivery truck.
        distance=p.distance or 0,h=p.h,pitch=p.pitch or 0,homeX=p.homeX,homeZ=p.homeZ,
        steering=p.steering or 0,slipAngle=p.slipAngle or 0,
        fuel=p.fuel==nil and Truck.TANK_LITERS or p.fuel,
        engine=p.engine~=false,headlight=p.headlight==true,
        headlightHighBeam=p.headlightHighBeam==true,turnSignal=p.turnSignal,
        model=p.model or 'box',fuelRevision=p.fuelRevision or 0}
end

function Truck.command(p,action,world)
    if action=='rescue' then
        local x,z,heading=require('src.commute.motorcycle').findRecoveryPoint(p,world,
            Truck.radius(p)+.5,Truck.collisionHeight(p),Truck.blocked)
        if not x then return false,z end
        p.x,p.z,p.heading,p.h=x,z,heading,world:supportHeight(x,z)
        p.speed,p.throttle,p.brake,p.steering,p.slipAngle,p.pitch,p.acceleration=0,0,0,0,0,0,0
        p.reverse=false
        return true,'Delivery truck moved to clear ground.'
    end
    if action=='ignition' then
        if (p.speed or 0)>.05 then return false,'Stop completely before switching the truck engine.' end
        if p.engine==false and (p.fuel or Truck.TANK_LITERS)<=0 then
            return false,'The delivery truck is out of fuel. Walk to the gas station to refill it.'
        end
        p.engine=not (p.engine~=false)
        if not p.engine then p.throttle=0;p.headlightHighBeam=false end
        return true,p.engine and 'Truck engine started.' or 'Truck engine off.'
    elseif action=='headlight' then
        p.headlight=not (p.headlight==true)
        return true,p.headlight and 'Truck headlights on.' or 'Truck headlights off.'
    elseif action=='beam' then
        p.headlightHighBeam=not (p.headlightHighBeam==true)
        return true,p.headlightHighBeam and 'Truck high beams on.' or 'Truck low beams on.'
    elseif action=='signalLeft' or action=='signalRight' then
        local signal=action=='signalLeft' and 'left' or 'right'
        if p.turnSignal==signal then p.turnSignal=nil else p.turnSignal=signal end
        return true,p.turnSignal and ('Truck %s signal on.'):format(p.turnSignal) or 'Truck turn signal off.'
    end
    return false,'That truck control is unavailable.'
end

function Truck.blocked(world,x,z,heading,subject)
    local dims=footprint.dimensions(subject)
    local c,s=math.cos(heading),math.sin(heading)
    local roadDistance,road=world.roads:sample(x,z)
    local drivableRoadId=road and not road.junction and roadDistance<=road.width*.5+.5 and road.id or nil
    if world.infrastructure and world.infrastructure:blocksTruck(x,z,c,s,dims,drivableRoadId) then return true end
    if world.sites and world.sites.nearby then
        for _,site in ipairs(world.sites:nearby(x,z)) do
            if footprint.hitsEdges(site.footprints,x,z,c,s,dims)
                or footprint.hitsEdges(site.obstacles,x,z,c,s,dims) then return true end
        end
    end
    for row=-2,2 do
        local along=row*dims.halfLength*.5
        for col=-1,1 do
            local side=col*dims.halfWidth
            if world.roads:blocked(world,x+c*along-s*side,z+s*along+c*side,true) then return true end
        end
    end
    if world.vehicleObstacles and world.vehicleObstacles(x,z,heading,subject) then return true end
    local h=world:supportHeight(x,z)
    return world.sweepObstacles and world:sweepObstacles(x,z,x,z,dims.radius,h,h+dims.height,c,s)~=nil
end

function Truck.update(p,input,dt,world)
    dt=M.clamp(dt or 0,0,.1)
    p.fuel=M.clamp(p.fuel==nil and Truck.TANK_LITERS or p.fuel,0,Truck.TANK_LITERS)
    if p.fuel<=0 then p.engine=false end
    input=input or {}
    local profile=Truck.profile(p)
    local axis=M.clamp(input.drive or 0,-1,1)
    local steer=M.clamp(input.steer or 0,-1,1)
    local wantedReverse=axis>0
    local magnitude=math.abs(axis)
    local before=p.speed or 0
    local _,surface=world:supportHeight(p.x,p.z)
    local loose=surface=='trail' or surface=='terrain'
    if loose and world.roads.padAt then
        local _,edge=world.roads:padAt(p.x,p.z)
        if edge and edge<=.5 then loose=false end
    end
    local grip=loose and 2.45 or 4.8 -- available lateral acceleration, m/s²
    local braking=profile.brake*(loose and .69 or 1)
    local rolling=profile.coast*(loose and 1.45 or 1)
    local opposite=magnitude>.001 and wantedReverse~=(p.reverse==true)
    local throttle,brake=0,0
    local serviceBrake=M.clamp(input.brake or 0,0,1)
    if serviceBrake>.001 then
        brake=serviceBrake
        p.speed=math.max(0,before-braking*serviceBrake*dt)
    elseif p.engine==false or p.fuel<=0 then
        if magnitude>.001 then
            brake=magnitude
            p.speed=math.max(0,before-braking*magnitude*dt)
        else p.speed=math.max(0,before-rolling*dt) end
    elseif opposite and before>.025 then
        brake=magnitude
        p.speed=math.max(0,before-braking*magnitude*dt)
        if p.speed<=.025 then p.speed=0;p.reverse=wantedReverse end
    elseif magnitude>.001 then
        p.reverse=wantedReverse
        throttle=magnitude
        local limit=p.reverse and profile.reverseSpeed or profile.maxSpeed
        if loose then limit=limit*.74 end
        local pull=profile.acceleration*(loose and .68 or 1)*(1-.55*math.min(1,before/limit))
        if before>limit then p.speed=math.max(limit,before-rolling*dt)
        else p.speed=math.min(limit,before+pull*magnitude*dt) end
    else
        p.speed=math.max(0,before-rolling*dt)
    end
    p.throttle,p.brake=throttle,brake
    p.steering=M.lerp(p.steering or 0,steer,1-math.exp(-4.5*dt))
    local direction=p.reverse and -1 or 1
    local wheelAngle=p.steering*profile.steerLock
    local desiredYaw=direction*p.speed*math.tan(wheelAngle)/profile.wheelbase
    local maxYaw=grip/math.max(.1,p.speed)
    local turn=M.clamp(desiredYaw,-maxYaw,maxYaw)*dt
    -- The velocity direction takes time to follow the chassis on loose dirt.
    p.slipAngle=M.clamp(((p.slipAngle or 0)-turn)*math.exp(-(loose and 2.3 or 7.5)*dt),-.5,.5)
    local travel=p.speed*direction*dt
    local steps=math.max(1,math.ceil(math.abs(travel)/.10))
    local moved=0
    for _=1,steps do
        if travel==0 then break end
        local heading=(p.heading+turn/steps)%(math.pi*2)
        local pathHeading=heading+p.slipAngle
        local nx=p.x+math.cos(pathHeading)*travel/steps
        local nz=p.z+math.sin(pathHeading)*travel/steps
        if Truck.blocked(world,nx,nz,heading,p) then
            p.speed=0;p.throttle=0;p.brake=1
            break
        end
        local distance=M.length(nx-p.x,nz-p.z)
        p.x,p.z,p.heading=nx,nz,heading;moved=moved+distance
    end
    p.h=world:supportHeight(p.x,p.z)
    local forwardX,forwardZ=math.cos(p.heading),math.sin(p.heading)
    local ahead=world:supportHeight(p.x+forwardX*.7,p.z+forwardZ*.7)
    local behind=world:supportHeight(p.x-forwardX*.7,p.z-forwardZ*.7)
    p.pitch=math.atan2(ahead-behind,1.4)
    p.distance=(p.distance or 0)+moved
    if p.engine~=false and moved>0 then
        p.fuel=math.max(0,p.fuel-moved*Truck.FUEL_PER_METER)
        if p.fuel<=0 then p.engine=false;p.throttle=0 end
    end
    if p.throttle==0 and p.speed<.025 then p.speed=0;p.slipAngle=0 end
    p.acceleration=dt>0 and (p.speed-before)/dt or 0
    return moved
end

return Truck
