-- Slow, heavy road vehicle for the warehouse commute. Its static body is
-- represented by a 64-view billboard; the physics remain deliberately simple.
local M=require('src.commute.vendor.mathx')
local Truck={MAX_SPEED=12.5,REVERSE_SPEED=3.2,ACCELERATION=1.55,BRAKE=4.4,COAST=1.15,
    TURN_RATE=.62,RADIUS=1.18,COLLISION_HEIGHT=2.55,FRAME_DISTANCE=.12}

function Truck.new(x,z,heading)
    return {x=x,z=z,heading=heading or 0,speed=0,reverse=false,distance=0,
        h=0,pitch=0,steering=0,throttle=0,brake=0,acceleration=0,
        engine=true,headlight=false,headlightHighBeam=false,turnSignal=nil}
end

function Truck.valid(p)
    return type(p)=='table' and M.finite(p.x) and M.finite(p.z) and M.finite(p.heading)
        and p.x>=0 and p.x<=512 and p.z>=0 and p.z<=512
        and M.finite(p.speed) and p.speed>=0 and p.speed<=Truck.MAX_SPEED
        and (p.reverse==nil or type(p.reverse)=='boolean')
        and (p.engine==nil or type(p.engine)=='boolean')
        and (p.headlight==nil or type(p.headlight)=='boolean')
        and (p.headlightHighBeam==nil or type(p.headlightHighBeam)=='boolean')
        and (p.turnSignal==nil or p.turnSignal=='left' or p.turnSignal=='right')
        and (p.distance==nil or M.finite(p.distance) and p.distance>=0 and p.distance<=1e12)
        and (p.h==nil or M.finite(p.h) and p.h>=-2 and p.h<=100)
        and (p.pitch==nil or M.finite(p.pitch) and math.abs(p.pitch)<=1.6)
        and (p.homeX==nil or M.finite(p.homeX)) and (p.homeZ==nil or M.finite(p.homeZ))
end

function Truck.snapshot(p)
    return {x=p.x,z=p.z,heading=p.heading,speed=p.speed or 0,reverse=p.reverse==true,
        distance=p.distance or 0,h=p.h,pitch=p.pitch or 0,homeX=p.homeX,homeZ=p.homeZ,
        engine=p.engine~=false,headlight=p.headlight==true,
        headlightHighBeam=p.headlightHighBeam==true,turnSignal=p.turnSignal}
end

function Truck.command(p,action)
    if action=='ignition' then
        if (p.speed or 0)>.05 then return false,'Stop completely before switching the truck engine.' end
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

local function blocked(p,world,x,z)
    for i=0,7 do
        local angle=i*math.pi/4
        if world.roads:blocked(world,x+math.cos(angle)*Truck.RADIUS,z+math.sin(angle)*Truck.RADIUS) then return true end
    end
    local h=world:supportHeight(x,z)
    return world.sweepObstacles and world:sweepObstacles(p.x,p.z,x,z,Truck.RADIUS,
        math.min(h,p.h or h),math.max(h,p.h or h)+Truck.COLLISION_HEIGHT)~=nil
end

function Truck.update(p,input,dt,world)
    dt=M.clamp(dt or 0,0,.1)
    input=input or {}
    local axis=M.clamp(input.drive or 0,-1,1)
    local steer=M.clamp(input.steer or 0,-1,1)
    local wantedReverse=axis>0
    local magnitude=math.abs(axis)
    local before=p.speed or 0
    local opposite=magnitude>.001 and wantedReverse~=(p.reverse==true)
    local throttle,brake=0,0
    if p.engine==false then
        if magnitude>.001 then
            brake=magnitude
            p.speed=math.max(0,before-Truck.BRAKE*magnitude*dt)
        else p.speed=math.max(0,before-Truck.COAST*dt) end
    elseif opposite and before>.025 then
        brake=magnitude
        p.speed=math.max(0,before-Truck.BRAKE*magnitude*dt)
        if p.speed<=.025 then p.speed=0;p.reverse=wantedReverse end
    elseif magnitude>.001 then
        p.reverse=wantedReverse
        throttle=magnitude
        local limit=p.reverse and Truck.REVERSE_SPEED or Truck.MAX_SPEED
        p.speed=math.min(limit,before+Truck.ACCELERATION*magnitude*dt)
    else
        p.speed=math.max(0,before-Truck.COAST*dt)
    end
    p.throttle,p.brake,p.steering=throttle,brake,steer
    p.acceleration=dt>0 and (p.speed-before)/dt or 0
    local direction=p.reverse and -1 or 1
    if p.speed>.08 then
        local speedFactor=M.clamp(p.speed/4,.18,1)
        p.heading=(p.heading+steer*Truck.TURN_RATE*speedFactor*direction*dt)%(math.pi*2)
    end
    local travel=p.speed*direction*dt
    local steps=math.max(1,math.ceil(math.abs(travel)/.10))
    local moved=0
    for _=1,steps do
        local nx=p.x+math.cos(p.heading)*travel/steps
        local nz=p.z+math.sin(p.heading)*travel/steps
        if blocked(p,world,nx,nz) then
            p.speed=0;p.throttle=0;p.brake=1
            break
        end
        local distance=M.length(nx-p.x,nz-p.z)
        p.x,p.z=nx,nz;moved=moved+distance
    end
    p.h=world:supportHeight(p.x,p.z)
    local forwardX,forwardZ=math.cos(p.heading),math.sin(p.heading)
    local ahead=world:supportHeight(p.x+forwardX*.7,p.z+forwardZ*.7)
    local behind=world:supportHeight(p.x-forwardX*.7,p.z-forwardZ*.7)
    p.pitch=math.atan2(ahead-behind,1.4)
    p.distance=(p.distance or 0)+moved
    if p.speed<.025 then p.speed=0 end
    return moved
end

return Truck
