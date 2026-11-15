-- Authoritative low-speed path motion inside controlled yards. No lane choice,
-- overtaking, route replanning or road-AI recovery can change this line.
local Truck=require('src.commute.delivery_truck')
local Path=require('src.commute.driving_path')
local Service=require('src.commute.truck_service')
local Rail={}
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<1e12 end
local function wrap(n)return math.atan2(math.sin(n),math.cos(n))end
function Rail.valid(r)
    return r==nil or type(r)=='table' and finite(r.station) and r.station>=0 and r.station<=10000
end
function Rail.project(points,x,z)
    local station,best,walked=0,math.huge,0
    for i=2,#points do
        local a,b=points[i-1],points[i]
        local dx,dz=b.x-a.x,b.z-a.z;local length=math.sqrt(dx*dx+dz*dz)
        local f=length>0 and math.max(0,math.min(1,((x-a.x)*dx+(z-a.z)*dz)/(length*length))) or 0
        local distance=(x-a.x-dx*f)^2+(z-a.z-dz*f)^2
        if distance<best then station,best=walked+length*f,distance end
        walked=walked+length
    end
    return station,math.sqrt(best)
end
local function pose(points,station,reverse,heading)
    local length=Path.length(points)
    local p=Path.sample(points,length,length>0 and station/length or 1)
    p.heading=wrap(p.heading+(reverse and math.pi or 0))
    if station>=length-.001 and heading then p.heading=heading end
    return p
end
function Rail.stop(v)
    v.speed=0;v.throttle=0;v.brake=1;v.acceleration=0;v.steering=0;v.slipAngle=0
end
local function sweepClear(v,p,world)
    local distance=math.sqrt((p.x-v.x)^2+(p.z-v.z)^2)
    local angle=wrap(p.heading-v.heading)
    local count=math.max(1,math.ceil(distance/.12),math.ceil(math.abs(angle)/.06))
    for i=1,count do
        local f=i/count
        if Truck.blocked(world,v.x+(p.x-v.x)*f,v.z+(p.z-v.z)*f,v.heading+angle*f,v) then return false end
    end
    return true
end
function Rail.place(v,p,world)
    if Truck.blocked(world,p.x,p.z,p.heading,v) then return false end
    v.x,v.z,v.h,v.heading=p.x,p.z,world:supportHeight(p.x,p.z),p.heading
    v.collisionContact=false;v.collisionStun=0;Rail.stop(v)
    if world.trafficActorIndex then world.trafficActorIndex:update(v) end
    return true
end
function Rail.endpoint(points,reverse,heading)
    return pose(points,Path.length(points),reverse,heading)
end
function Rail.step(v,r,points,dt,world,options)
    options=options or {};dt=math.max(0,math.min(.1,dt or 0))
    if dt<=0 then return false,0 end
    local length=Path.length(points)
    r.station=math.max(0,math.min(length,r.station))
    local current=pose(points,r.station,options.reverse,options.heading)
    local offset=math.sqrt((v.x-current.x)^2+(v.z-current.z)^2)
    if offset>1.5 then Rail.stop(v);return false,0,'off_line' end
    if v.engine==false or (v.fuel or Truck.TANK_LITERS)<=0
        or v.service and v.service.mechanicalFailure then Rail.stop(v);return false,0,'engine' end
    local speed=math.min(options.speed or 2.4,(v.speed or 0)+1.5*dt,
        math.sqrt(6*math.max(offset,length-r.station)))
    local advance=math.min(length-r.station,speed*dt)
    local station=r.station+advance
    local nextPose=pose(points,station,options.reverse,options.heading)
    -- Take over from the road controller without a visible jump into the line.
    if offset>1e-6 then
        local f=math.min(1,speed*dt/offset)
        nextPose.x=v.x+(current.x-v.x)*f;nextPose.z=v.z+(current.z-v.z)*f
        nextPose.heading=current.heading;station=r.station
    end
    if not sweepClear(v,nextPose,world) then Rail.stop(v);return false,0,'obstacle' end
    local moved=math.sqrt((v.x-nextPose.x)^2+(v.z-nextPose.z)^2)
    local oldHeading=v.heading
    v.x,v.z,v.h,v.heading=nextPose.x,nextPose.z,world:supportHeight(nextPose.x,nextPose.z),nextPose.heading
    -- Keep the controller's commanded speed through the last short alignment
    -- step. Deriving it from that leftover distance makes acceleration depend
    -- on which frame happens to finish joining the line.
    v.speed=speed;v.reverse=options.reverse==true;v.collisionContact=false;v.collisionStun=0
    v.throttle=v.reverse and -.3 or .3;v.brake=0;v.slipAngle=0
    v.steering=math.max(-1,math.min(1,wrap(v.heading-oldHeading)*(v.reverse and -1 or 1)*3))
    v.distance=(v.distance or 0)+moved
    v.fuel=math.max(0,(v.fuel or Truck.TANK_LITERS)-moved*Truck.FUEL_PER_METER)
    if v.fuel<=0 then v.engine=false end
    Service.run(v,moved,dt)
    r.station=station;v.pathIndex=nextPose.pathIndex
    if world.trafficActorIndex then world.trafficActorIndex:update(v) end
    if station>=length-.001 and offset<=1e-6 then Rail.stop(v);return true,moved end
    return false,moved
end
-- Round authored corners once, keeping a single immutable line for all trucks.
function Rail.round(points)
    local result={points[1]}
    for i=2,#points-1 do
        local a,b,c=points[i-1],points[i],points[i+1]
        local incoming=math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
        local outgoing=math.sqrt((c.x-b.x)^2+(c.z-b.z)^2)
        local trim=math.min(2,incoming*.35,outgoing*.35)
        if trim>.01 then
            local before={x=b.x+(a.x-b.x)*trim/incoming,z=b.z+(a.z-b.z)*trim/incoming,h=b.h}
            local after={x=b.x+(c.x-b.x)*trim/outgoing,z=b.z+(c.z-b.z)*trim/outgoing,h=b.h}
            result[#result+1]=before
            for j=1,12 do
                local t=j/12;local u=1-t
                result[#result+1]={x=u*u*before.x+2*u*t*b.x+t*t*after.x,
                    z=u*u*before.z+2*u*t*b.z+t*t*after.z,h=b.h}
            end
        else result[#result+1]=b end
    end
    result[#result+1]=points[#points];return result
end
return Rail
