-- Rigid box truck with front-wheel steering and surface-dependent tire grip.
local M=require('src.commute.vendor.mathx')
local liveries=require('src.commute.truck_liveries')
local footprint=require('src.commute.truck_footprint')
local Service=require('src.commute.truck_service')
local Truck={MAX_SPEED=13.6,REVERSE_SPEED=3.2,ACCELERATION=1.75,BRAKE=6.5,COAST=1.15,
    WHEELBASE=3.5,STEER_LOCK=math.rad(42),RADIUS=1.18,COLLISION_HEIGHT=footprint.height,FRAME_DISTANCE=.12,
    -- 60 L gives roughly 250 miles at the shared delivery-truck economy.
    TANK_LITERS=60,FUEL_PER_METER=.00015,COLLISION_STUN_SECONDS=2,
    COLLISION_STUN_CRAWL_SPEED=1.4,COLLISION_STUN_MIN_ACCELERATION=.2,COLLISION_STUN_TRIGGER_SPEED=3}
local profiles={box={maxSpeed=13.6,reverseSpeed=3.2,acceleration=1.75,brake=6.5,coast=1.15,
    wheelbase=3.5,steerLock=math.rad(42),dirtGrip=4.25,roadGrip=5.15,
    brakeGripBonus=.20,brakeSlipReduction=.60,brakeSlipDamping=6,
    dirtSlipDamping=5.1,roadSlipDamping=8.2,collisionHeadOnThreshold=.92,collisionNormalSpeedLoss=.28},
    kei={maxSpeed=14.8,reverseSpeed=3.2,
    acceleration=2.05,brake=8.8,coast=1.15,wheelbase=2.15,steerLock=math.rad(32),
    brakeGripBonus=.30,brakeSlipReduction=.80,brakeSlipDamping=10,
    steerDeadzone=.04,steerExponent=1.15,steerReturn=7.5,
    gripMultiplier=1.2,lowSpeedGripBonus=.18,lowSpeedSlipReduction=.45,lowSpeedSlipDamping=3.5,
    collisionHeadOnThreshold=.92,collisionNormalSpeedLoss=.28}}
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
        fuel=Truck.TANK_LITERS,fuelRevision=0,engine=true,headlight=false,headlightHighBeam=false,
        turnSignal=nil,collisionContact=false,collisionStun=0}
end

function Truck.valid(p)
    return type(p)=='table' and M.finite(p.x) and M.finite(p.z) and M.finite(p.heading)
        and (p.model==nil or profiles[p.model]~=nil)
        and (p.fuelRevision==nil or M.finite(p.fuelRevision) and p.fuelRevision%1==0 and p.fuelRevision>=0)
        and (p.livery==nil or liveries[p.livery]~=nil)
        and p.x>=0 and p.x<=512 and p.z>=0 and p.z<=512
        and M.finite(p.speed) and p.speed>=0 and p.speed<=Truck.profile(p).maxSpeed*1.12
        and (p.reverse==nil or type(p.reverse)=='boolean')
        and (p.engine==nil or type(p.engine)=='boolean')
        and (p.fuel==nil or M.finite(p.fuel) and p.fuel>=0 and p.fuel<=Truck.TANK_LITERS)
        and (p.headlight==nil or type(p.headlight)=='boolean')
        and (p.headlightHighBeam==nil or type(p.headlightHighBeam)=='boolean')
        and (p.turnSignal==nil or p.turnSignal=='left' or p.turnSignal=='right')
        and (p.collisionContact==nil or type(p.collisionContact)=='boolean')
        and (p.collisionStun==nil or M.finite(p.collisionStun)
            and p.collisionStun>=0 and p.collisionStun<=Truck.COLLISION_STUN_SECONDS)
        and (p.distance==nil or M.finite(p.distance) and p.distance>=0 and p.distance<=1e12)
        and (p.damage==nil or type(p.damage)=='number' and p.damage%1==0 and p.damage>=0 and p.damage<=100)
        and (p.repairRevision==nil or type(p.repairRevision)=='number' and p.repairRevision%1==0
            and p.repairRevision>=0 and p.repairRevision<=Service.MAX_REVISION)
        and (p.service==nil or Service.valid(p.service))
        and (p.h==nil or M.finite(p.h) and p.h>=-2 and p.h<=100)
        and (p.pitch==nil or M.finite(p.pitch) and math.abs(p.pitch)<=1.6)
        and (p.steering==nil or M.finite(p.steering) and math.abs(p.steering)<=1)
        and (p.slipAngle==nil or M.finite(p.slipAngle) and math.abs(p.slipAngle)<=.5)
        and (p.homeX==nil or M.finite(p.homeX)) and (p.homeZ==nil or M.finite(p.homeZ))
end

function Truck.snapshot(p)
    local result={x=p.x,z=p.z,heading=p.heading,speed=p.speed or 0,reverse=p.reverse==true,
        livery=p.livery or 'picture_shop', -- Older towns only had the shop's delivery truck.
        distance=p.distance or 0,h=p.h,pitch=p.pitch or 0,homeX=p.homeX,homeZ=p.homeZ,
        steering=p.steering or 0,slipAngle=p.slipAngle or 0,
        fuel=p.fuel==nil and Truck.TANK_LITERS or p.fuel,
        engine=p.engine~=false,headlight=p.headlight==true,
        headlightHighBeam=p.headlightHighBeam==true,turnSignal=p.turnSignal,
        model=p.model or 'box',fuelRevision=p.fuelRevision or 0,
        collisionContact=p.collisionContact==true,
        collisionStun=M.clamp(p.collisionStun or 0,0,Truck.COLLISION_STUN_SECONDS)}
    if p.service then
        local record=Service.record(p)
        result.damage=record.damage;result.repairRevision=record.repairRevision;result.service=record.service
    end
    return result
end

function Truck.command(p,action,world)
    if action=='rescue' then
        local x,z,heading=require('src.commute.motorcycle').findRecoveryPoint(p,world,
            Truck.radius(p)+.5,Truck.collisionHeight(p),Truck.blocked)
        if not x then return false,z end
        p.x,p.z,p.heading,p.h=x,z,heading,world:supportHeight(x,z)
        p.speed,p.throttle,p.brake,p.steering,p.slipAngle,p.pitch,p.acceleration=0,0,0,0,0,0,0
        p.reverse=false;p.collisionContact=false;p.collisionStun=0
        return true,'Delivery truck moved to clear ground.'
    end
    if action=='ignition' then
        if (p.speed or 0)>.05 then return false,'Stop completely before switching the truck engine.' end
        if p.service and p.service.mechanicalFailure and p.engine==false then
            local failure=({oil_pressure='an oil pressure failure',overheating='a cooling system failure',
                ignition_misfire='an ignition misfire'})[p.service.failureType] or 'an engine failure'
            return false,'The truck has '..failure..'. Take it to the mechanic for repairs.'
        end
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

-- Resolve the nearest clear translation from a newly overlapped truck pose.
-- This gives the movement solver a contact normal without shrinking the
-- truck's collision footprint or changing its parking/overlap checks.
local function contactNormal(world,x,z,heading,subject,dx,dz)
    local moveLength=M.length(dx,dz)
    if moveLength<1e-8 then return -math.cos(heading),-math.sin(heading) end
    local moveX,moveZ=dx/moveLength,dz/moveLength
    local dims=footprint.dimensions(subject)
    if world.sweepObstacles and world.supportHeight then
        local h=world:supportHeight(subject.x,subject.z)
        local hit,nx,nz=world:sweepObstacles(subject.x,subject.z,x,z,dims.radius,
            h,h+dims.height,math.cos(heading),math.sin(heading))
        if hit and M.finite(nx) and M.finite(nz) then
            local length=M.length(nx,nz)
            if length>1e-8 then return nx/length,nz/length end
        end
    end
    local bestX,bestZ,bestDistance,bestAlignment
    for i=0,15 do
        local angle=i*math.pi/8
        local nx,nz=math.cos(angle),math.sin(angle)
        local limit=1.2
        if not Truck.blocked(world,x+nx*limit,z+nz*limit,heading,subject) then
            local low,high=0,limit
            for _=1,7 do
                local middle=(low+high)*.5
                if Truck.blocked(world,x+nx*middle,z+nz*middle,heading,subject) then low=middle else high=middle end
            end
            local alignment=-(moveX*nx+moveZ*nz)
            if not bestDistance or high<bestDistance-.012
                or math.abs(high-bestDistance)<=.012 and alignment>bestAlignment then
                bestX,bestZ,bestDistance,bestAlignment=nx,nz,high,alignment
            end
        end
    end
    if bestX then return bestX,bestZ end
    return -moveX,-moveZ
end

local function wrapAngle(angle)
    while angle>math.pi do angle=angle-math.pi*2 end
    while angle< -math.pi do angle=angle+math.pi*2 end
    return angle
end

function Truck.update(p,input,dt,world)
    dt=M.clamp(dt or 0,0,.1)
    p.collisionStun=M.clamp((p.collisionStun or 0)-dt,0,Truck.COLLISION_STUN_SECONDS)
    local stunRatio=p.collisionStun/Truck.COLLISION_STUN_SECONDS
    p.fuel=M.clamp(p.fuel==nil and Truck.TANK_LITERS or p.fuel,0,Truck.TANK_LITERS)
    if p.service and p.service.mechanicalFailure then p.engine=false end
    if p.fuel<=0 then p.engine=false end
    input=input or {}
    local profile=Truck.profile(p)
    local axis=M.clamp(input.drive or 0,-1,1)
    local steer=M.clamp(input.steer or 0,-1,1)
    if profile.steerDeadzone then
        -- The short kei wheelbase magnifies small stick corrections. Leave a
        -- quiet center and retain its tighter turn at larger inputs.
        local amount=math.max(0,(math.abs(steer)-profile.steerDeadzone)/(1-profile.steerDeadzone))
        steer=(steer<0 and -1 or 1)*amount^profile.steerExponent
    end
    local wantedReverse=axis>0
    local magnitude=math.abs(axis)
    local before=p.speed or 0
    local condition=p.service and Service.modifiers(p) or {speed=1,acceleration=1,brake=1,grip=1}
    local _,surface=world:supportHeight(p.x,p.z)
    local loose=surface=='trail' or surface=='terrain'
    if loose and world.roads.padAt then
        local _,edge=world.roads:padAt(p.x,p.z)
        if edge and edge<=.5 then loose=false end
    end
    local grounded=p.grounded~=false
    local braking=profile.brake*condition.brake*(loose and .69 or 1)
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
        local limit=(p.reverse and profile.reverseSpeed or profile.maxSpeed)*condition.speed
        if loose then limit=limit*.74 end
        if stunRatio>0 then
            limit=math.min(limit,Truck.COLLISION_STUN_CRAWL_SPEED
                +(limit-Truck.COLLISION_STUN_CRAWL_SPEED)*(1-stunRatio))
        end
        local pull=profile.acceleration*condition.acceleration*(loose and .68 or 1)
            *(1-.55*math.min(1,before/limit))
            *(Truck.COLLISION_STUN_MIN_ACCELERATION+(1-Truck.COLLISION_STUN_MIN_ACCELERATION)*(1-stunRatio))
        if before>limit then p.speed=math.max(limit,before-rolling*dt)
        else p.speed=math.min(limit,before+pull*magnitude*dt) end
    else
        p.speed=math.max(0,before-rolling*dt)
    end
    if stunRatio>0 then
        local recoveryLimit=(p.reverse and profile.reverseSpeed or profile.maxSpeed)*condition.speed*(loose and .74 or 1)
        p.speed=math.min(p.speed,Truck.COLLISION_STUN_CRAWL_SPEED
            +(recoveryLimit-Truck.COLLISION_STUN_CRAWL_SPEED)*(1-stunRatio))
    end
    p.throttle,p.brake=throttle,brake
    -- Under braking the tires settle onto the chosen line and shed sideways
    -- motion quickly. Scale this with pedal pressure, surface and tire health;
    -- airborne trucks cannot gain contact grip from their brakes.
    local brakeTraction=grounded and brake*(loose and .5 or 1)*math.min(1,condition.grip) or 0
    local lowSpeedBlend=grounded and (1-M.smooth((p.speed-2)/5)) or 0
    local grip=loose and (profile.dirtGrip or 2.45) or (profile.roadGrip or 4.8)
    grip=grip*(1+((profile.gripMultiplier or 1)-1)*(grounded and 1 or 0))
        *condition.grip
        *(1+(profile.lowSpeedGripBonus or 0)*lowSpeedBlend)
        *(1+(profile.brakeGripBonus or 0)*brakeTraction)
    local steerRate=steer==0 and (profile.steerReturn or 4.5) or 4.5
    p.steering=M.lerp(p.steering or 0,steer,1-math.exp(-steerRate*dt))
    local direction=p.reverse and -1 or 1
    local wheelAngle=p.steering*profile.steerLock
    local desiredYaw=direction*p.speed*math.tan(wheelAngle)/profile.wheelbase
    local maxYaw=grip/math.max(.1,p.speed)
    local turn=M.clamp(desiredYaw,-maxYaw,maxYaw)*dt
    -- The velocity direction takes time to follow the chassis on loose dirt.
    -- At low speed, the kei's tires hold the line more closely and recover
    -- sideways motion faster without changing steering input or wheel angle.
    local slipTurn=turn*(1-(profile.lowSpeedSlipReduction or 0)*lowSpeedBlend)
        *(1-(profile.brakeSlipReduction or 0)*brakeTraction)
    local slipDamping=(loose and (profile.dirtSlipDamping or 2.3)
        or (profile.roadSlipDamping or 7.5))+(profile.lowSpeedSlipDamping or 0)*lowSpeedBlend
        +(profile.brakeSlipDamping or 0)*brakeTraction
    p.slipAngle=M.clamp(((p.slipAngle or 0)-slipTurn)*math.exp(-slipDamping*dt),-.5,.5)
    local travel=p.speed*direction*dt
    local steps=math.max(1,math.ceil(math.abs(travel)/.10))
    local moved,conditionChanged=0,false
    for _=1,steps do
        if travel==0 then break end
        local heading=(p.heading+turn/steps)%(math.pi*2)
        local pathHeading=heading+p.slipAngle
        local nx=p.x+math.cos(pathHeading)*travel/steps
        local nz=p.z+math.sin(pathHeading)*travel/steps
        if Truck.blocked(world,nx,nz,heading,p) then
            local stepX,stepZ=nx-p.x,nz-p.z
            local stepLength=M.length(stepX,stepZ)
            local normalX,normalZ=contactNormal(world,nx,nz,heading,p,stepX,stepZ)
            local inward=stepX*normalX+stepZ*normalZ
            local approach=stepLength>1e-8 and M.clamp(-inward/stepLength,0,1) or 1
            local impactSpeed=p.speed*approach
            local freshContact=not p.collisionContact
            if freshContact and Service.impact(p,impactSpeed) then conditionChanged=true end
            local headOn=approach>=(profile.collisionHeadOnThreshold or .92)
            if freshContact and headOn and impactSpeed>Truck.COLLISION_STUN_TRIGGER_SPEED then
                p.collisionStun=Truck.COLLISION_STUN_SECONDS
            end

            -- Remove only the component going into the obstacle. A side brush
            -- keeps the truck moving along the surface; a head-on hit loses
            -- its forward motion. Tiny outward offsets avoid sticking on the
            -- same edge on the next physics step.
            local slideX,slideZ=stepX,stepZ
            if inward<0 then slideX,slideZ=stepX-inward*normalX,stepZ-inward*normalZ end
            local slideLength=M.length(slideX,slideZ)
            local placedX,placedZ,placedDistance
            if slideLength>.001 and approach<(profile.collisionHeadOnThreshold or .92) then
                for _,push in ipairs({0,.015,.04,.08}) do
                    local candidateX=p.x+slideX+normalX*push
                    local candidateZ=p.z+slideZ+normalZ*push
                    if not Truck.blocked(world,candidateX,candidateZ,heading,p) then
                        placedX,placedZ=candidateX,candidateZ
                        placedDistance=M.length(candidateX-p.x,candidateZ-p.z)
                        break
                    end
                end
            end
            if placedX then
                p.x,p.z,p.heading=placedX,placedZ,heading
                moved=moved+placedDistance
                local motionAngle=math.atan2(placedZ-(nz-stepZ),placedX-(nx-stepX))
                local vehicleAngle=heading+(p.reverse and math.pi or 0)
                p.slipAngle=M.clamp(wrapAngle(motionAngle-vehicleAngle),-.5,.5)
                if freshContact then
                    p.speed=p.speed*(1-(profile.collisionNormalSpeedLoss or .28)*approach)
                end
            else
                p.speed=0;p.throttle=0;p.brake=1;p.slipAngle=0
            end
            p.collisionContact=true
            break
        end
        p.collisionContact=false
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
    local wore,failed=Service.run(p,moved,dt)
    if wore then conditionChanged=true end
    if failed then conditionChanged=true end
    if p.throttle==0 and p.speed<.025 then p.speed=0;p.slipAngle=0 end
    p.acceleration=dt>0 and (p.speed-before)/dt or 0
    return moved,conditionChanged
end

-- Off-map city deliveries still count against the same fuel, odometer and
-- maintenance records as distance driven in town.
function Truck.accountRouteDistance(p,meters)
    meters=math.max(0,tonumber(meters) or 0)
    if not p or meters<=0 then return 0 end
    p.distance=(p.distance or 0)+meters
    p.fuel=math.max(0,(p.fuel or Truck.TANK_LITERS)-meters*Truck.FUEL_PER_METER)
    if p.fuel<=0 then p.engine=false;p.throttle=0 end
    Service.run(p,meters,0)
    return meters
end

return Truck
