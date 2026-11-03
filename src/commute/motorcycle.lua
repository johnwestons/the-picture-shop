local M=require('src.commute.vendor.mathx')
local RidingAnimation=require('src.commute.riding_animation')
local Damping=require('src.commute.damping')
local Upgrades=require('src.commute.bike_upgrades')
local Paint=require('src.commute.bike_paint')
local Damage=require('src.commute.bike_damage')
local Bike={MAX_SPEED=12,REVERSE_MAX_SPEED=1.2,BOOST_MAX_SPEED=14.4,BOOST_ACCELERATION=1.6,BOOST_PULSE=.78,
    TUCK_START_SPEED=13.35,IMPACT_DURATION=.62,IMPACT_MIN_SPEED=.35,
    ACCELERATION=3.4,BRAKE=9,COAST=1.0,WHEELBASE=1.25,RADIUS=.42,
    IDLE_RPM=1400,REDLINE=8000,SHIFT_TIME=.16,STEER_SMOOTH_TIME=.20,LEAN_SMOOTH_TIME=.30,
    OFFROAD_SCALE=.82,GRAVITY=9.81,SUSPENSION_SPRING=110,SUSPENSION_DAMPING=21,
    SUSPENSION_REACH=.22,MAX_COMPRESSION=.16,PITCH_INERTIA=.8,MAX_PITCH=.82,MAX_PRESENTATION_SPEED=32,
    ROAD_GRIP=13,DIRT_GRIP=5.6,ROAD_RESPONSE=14,DIRT_RESPONSE=8,COLLISION_HEIGHT=1.2,
    GEARS={{speed=4.4,force=4.4,up=3.6,down=0},{speed=7.1,force=3.4,up=6,down=2.3},
        {speed=10,force=2.6,up=8.6,down=4.2},{speed=15,force=2,up=math.huge,down=6.4}}}
function Bike.new(x,z,heading)
    return {x=x,z=z,heading=heading or 0,speed=0,distance=0,lean=0,gear=1,transmission='automatic',upgradeLevel=0,paintId=Paint.DEFAULT,damage=0,
        vx=0,vz=0,_velocitySpeed=0,vy=0,pitch=0,pitchVelocity=0,suspension=0,landingPulse=0,
        lateralSpeed=0,slipAngle=0,slip=0,tireSlip=0,surface='road',
        rpm=Bike.IDLE_RPM,shiftTime=0,shiftDirection=0,shiftCooldown=0,throttle=0,grade=0,
        reverse=false,headlight=false,boosting=false,boostPulse=0,steering=0,acceleration=0,impactPulse=0,impactStrength=0,collisionContact=false,
        safeX=x,safeZ=z,safeHeading=heading or 0,
        ridingAnimation={kind='idle',remaining=0,queue={}}}
end
function Bike.valid(p)
    return type(p)=='table' and (p.gear==nil or M.finite(p.gear) and p.gear%1==0 and p.gear>=1 and p.gear<=#Bike.GEARS)
        and Upgrades.validLevel(p.upgradeLevel)
        and Damage.valid(p.damage)
        and (p.paintId==nil or Paint.valid(p.paintId))
        and (p.transmission==nil or p.transmission=='automatic' or p.transmission=='manual')
        and (p.reverse==nil or type(p.reverse)=='boolean') and (p.headlight==nil or type(p.headlight)=='boolean')
end
function Bike.rpmForSpeed(p,speed)
    speed=speed or p.speed or 0
    if p.reverse then return Bike.IDLE_RPM+speed*500 end
    local gear=Bike.GEARS[p.gear or 1]
    local gearSpeed=gear.speed*Upgrades.profile(p.upgradeLevel).maxSpeed/Bike.MAX_SPEED
    return M.clamp(Bike.REDLINE*speed/gearSpeed,Bike.IDLE_RPM,Bike.REDLINE)
end
local halfBase = Bike.WHEELBASE*.5
local function wheelSupports(p,world)
    local dx, dz = math.cos(p.heading)*halfBase, math.sin(p.heading)*halfBase
    local front = world:supportHeight(p.x+dx, p.z+dz)
    local rear = world:supportHeight(p.x-dx, p.z-dz)
    return front, rear
end
function Bike.resetContact(p,world)
    local front,rear=wheelSupports(p,world)
    p.grade=(front-rear)/Bike.WHEELBASE
    p.h=(front+rear)*.5;p.pitch=math.atan(p.grade);p.pitchVelocity=0;p.vy=0
    p.frontGrounded,p.rearGrounded,p.grounded=true,true,true
    p.suspension=0;p.landingPulse=0
end
-- Call after intentionally changing speed or heading (parking, spawn, recovery).
-- Normal simulation never rotates velocity with the sprite's facing direction.
function Bike.resetHorizontal(p)
    local direction=p.reverse and -1 or 1
    p.vx=math.cos(p.heading)*(p.speed or 0)*direction
    p.vz=math.sin(p.heading)*(p.speed or 0)*direction
    p._velocitySpeed=p.speed or 0
    p.lateralSpeed=0;p.slipAngle=0;p.slip=0;p.tireSlip=0
end
Bike.RESCUE_CHECKPOINT_DISTANCE=6
local function safeRecoveryPoint(world,x,z)
    if not M.finite(x) or not M.finite(z) then return false end
    if world.roads and world.roads.blocked and world.roads:blocked(world,x,z) then return false end
    if world.sweepObstacles then
        local height=world:supportHeight(x,z)
        if world:sweepObstacles(x,z,x,z,Bike.RADIUS,height,height+Bike.COLLISION_HEIGHT) then return false end
    end
    return true
end
function Bike.rescue(p,world)
    local x,z=p.safeX,p.safeZ
    if not safeRecoveryPoint(world,x,z) then return false,'No nearby safe recovery spot is available.' end
    p.x,p.z=x,z;p.heading=p.safeHeading or p.heading
    p.speed,p.vx,p.vz,p._velocitySpeed=0,0,0,0
    p.reverse=false;p.boosting=false;p.boostPulse=0
    p.throttle,p.brake,p.steering,p.steeringVelocity=0,0,0,0
    p.lean,p.leanVelocity,p.pitchVelocity=0,0,0
    p.shiftTime,p.shiftCooldown=0,0
    p.crashPending=nil;p.collisionContact=false;p.collisionKind=nil;p.collisionId=nil
    p.impactPulse,p.impactStrength,p.landingPulse=0,0,0
    Bike.resetContact(p,world)
    RidingAnimation.reset(p)
    return true
end
local function rememberRecoveryPoint(p,world)
    if not p.grounded or math.abs(p.vy or 0)>.3 then return end
    local dx,dz=p.x-(p.safeX or p.x),p.z-(p.safeZ or p.z)
    if dx*dx+dz*dz<Bike.RESCUE_CHECKPOINT_DISTANCE^2 then return end
    if safeRecoveryPoint(world,p.x,p.z) then
        p.safeX,p.safeZ,p.safeHeading=p.x,p.z,p.heading
    end
end
local function wheelForce(compression,closingSpeed)
    if compression < -Bike.SUSPENSION_REACH then return 0 end
    return .5*M.clamp(Bike.GRAVITY + Bike.SUSPENSION_SPRING*compression
        + Bike.SUSPENSION_DAMPING*closingSpeed, 0, 90)
end

local function contact(p,dt,front,rear,frontBefore,rearBefore,throttle,brake)
    if dt==0 then return end
    local wasGrounded = p.grounded
    local pitch = p.pitch or 0
    local angularSpeed = p.pitchVelocity or 0
    local offset = halfBase*math.tan(pitch)
    local wheelVelocity = halfBase*angularSpeed / math.cos(pitch)^2
    local frontForce = wheelForce(front-p.h-offset, (front-frontBefore)/dt-p.vy-wheelVelocity)
    local rearForce = wheelForce(rear-p.h+offset, (rear-rearBefore)/dt-p.vy+wheelVelocity)
    p.frontGrounded, p.rearGrounded = frontForce>0, rearForce>0
    p.grounded = p.frontGrounded or p.rearGrounded
    if p.grounded then
        -- Independent reactions: rear-wheel contact raises the tail and
        -- brings the front down. Landing never enters the damage path.
        angularSpeed = angularSpeed + (frontForce-rearForce)*halfBase/Bike.PITCH_INERTIA*dt
        if not wasGrounded then p.landingPulse=M.clamp(-p.vy/10,0,1) end
    else
        -- Once unloaded, gravity changes the trajectory, not the attitude.
        -- Keep the launch rotation, with a small nose lift on a forward crest.
        if wasGrounded and not p.reverse and p.vy>0 then
            angularSpeed = angularSpeed + .60*M.clamp(p.vy/3,0,1)
        end
        local rotation = throttle*(1-brake)*1.65
        if brake>0 then rotation = rotation - brake*(7*pitch+3.2*angularSpeed) end
        angularSpeed = (angularSpeed+rotation*dt)*math.exp(-.9*dt)
    end
    angularSpeed = M.clamp(angularSpeed,-2.5,2.5)
    local nextPitch = pitch+angularSpeed*dt
    p.pitch = M.clamp(nextPitch,-Bike.MAX_PITCH,Bike.MAX_PITCH)
    p.pitchVelocity = p.pitch==nextPitch and angularSpeed or 0
    p.vy = p.vy+(frontForce+rearForce-Bike.GRAVITY)*dt
    p.h = p.h+p.vy*dt
    offset = halfBase*math.tan(p.pitch)
    local compression = math.max(front-p.h-offset, rear-p.h+offset)
    if compression>Bike.MAX_COMPRESSION then
        p.h = p.h+compression-Bike.MAX_COMPRESSION
        p.vy = math.max(0,p.vy)
        p.frontGrounded=p.frontGrounded or front-p.h-offset>=Bike.MAX_COMPRESSION-1e-7
        p.rearGrounded=p.rearGrounded or rear-p.h+offset>=Bike.MAX_COMPRESSION-1e-7
        p.grounded=true
    end
    p.grade = (front-rear)/Bike.WHEELBASE
    p.suspension = M.clamp(compression/Bike.SUSPENSION_REACH,-1,1)
    p.landingPulse = math.max(0,(p.landingPulse or 0)-dt*1.5)
end
function Bike.settle(p,dt,world)
    p.speed=0;Bike.resetHorizontal(p)
    if not M.finite(p.h) then Bike.resetContact(p,world) end
    dt=M.clamp(dt,0,.1)
    local count=math.max(1,math.ceil(dt*120-1e-9));local front,rear=wheelSupports(p,world)
    for _=1,count do contact(p,dt/count,front,rear,front,rear,0,0) end
end
function Bike.shift(p,delta)
    local target=p.gear+delta
    if p.shiftTime>0 then return false,'Finish the current shift first.' end
    if target<1 or target>#Bike.GEARS then return false,delta>0 and 'Already in top gear.' or 'Already in first gear.' end
    if p.speed>Bike.GEARS[target].speed*Upgrades.profile(p.upgradeLevel).maxSpeed/Bike.MAX_SPEED then return false,'Slow down before selecting that gear.' end
    p.gear=target;p.shiftTime=Bike.SHIFT_TIME;p.shiftDirection=delta;p.shiftCooldown=.65
    RidingAnimation.request(p,'shift')
    return true
end
function Bike.command(p,action)
    if action=='headlight' then p.headlight=not p.headlight;return true,p.headlight and 'Headlight on.' or 'Headlight off.' end
    if action=='reverse' then
        if math.abs(p.speed or 0)>.05 or p.shiftTime>0 then return false,'Stop completely before selecting forward or reverse.' end
        p.speed=0;p.reverse=not p.reverse;p.gear=1;p.boosting=false;Bike.resetHorizontal(p)
        return true,p.reverse and 'Reverse selected. Accelerate gently to back up; brake to stop.' or 'Forward selected.'
    end
    if p.reverse then return false,'Select forward before changing transmission or gears.' end
    if action=='automatic' or action=='manual' then
        p.transmission=action
        return true,p.transmission=='manual' and 'Manual: Z shifts down, X shifts up.' or 'Automatic transmission enabled.'
    end
    if p.transmission~='manual' then return false,'Press V to select manual transmission first.' end
    if action~='shiftup' and action~='shiftdown' then return false,'Invalid transmission action.' end
    return Bike.shift(p,action=='shiftup' and 1 or -1)
end

local rim = {}
for i=0,7 do
    local angle = i * math.pi / 4
    rim[i+1] = {x=math.cos(angle), z=math.sin(angle)}
end

local function barrierNormal(world, x, z)
    -- The two rays tangent to a wall mark where solid samples turn into open
    -- samples around the contact point. Refine those angles so a rotated wall
    -- does not round to the nearest rim direction and inflate a scrape.
    local function solidAt(angle)
        return world.roads:blocked(world, x+math.cos(angle)*.04, z+math.sin(angle)*.04, true)
    end
    local normalX, normalZ = 0, 0
    local wasSolid = solidAt(0)
    for i=1,#rim do
        local hi = i * math.pi / 4
        local isSolid = solidAt(hi)
        if isSolid ~= wasSolid then
            local lo = hi-math.pi/4
            for _=1,6 do
                local angle = (lo+hi)*.5
                if solidAt(angle)==wasSolid then lo=angle else hi=angle end
            end
            local tangent = (lo+hi)*.5
            local side = wasSolid and 1 or -1
            normalX, normalZ = normalX-side*math.sin(tangent), normalZ+side*math.cos(tangent)
        end
        wasSolid = isSolid
    end
    return normalX, normalZ
end

-- Buildings, bridges and the map perimeter expose solid point tests. Locate
-- the first rim contact, then sample its exposed face for an outward normal.
-- Trees, rocks and street furniture supply exact sweep normals separately.
local function barrierHit(world, x, z, nextX, nextZ)
    local dx, dz = nextX-x, nextZ-z
    local fraction, touchX, touchZ
    for _, offset in ipairs(rim) do
        local px, pz = x + offset.x*Bike.RADIUS, z + offset.z*Bike.RADIUS
        local hi = fraction or 1
        if world.roads:blocked(world, px+dx*hi, pz+dz*hi, true) then
            local lo = 0
            for _=1,8 do
                local mid = (lo+hi)*.5
                if world.roads:blocked(world, px+dx*mid, pz+dz*mid, true) then hi=mid else lo=mid end
            end
            fraction, touchX, touchZ = lo, px+dx*hi, pz+dz*hi
        end
    end
    if not fraction then return end
    local _, kind = world.roads:blocked(world,touchX,touchZ,true)
    local normalX, normalZ = barrierNormal(world, touchX, touchZ)
    local length = M.length(normalX, normalZ)
    if length < .001 then
        normalX, normalZ, length = -dx, -dz, M.length(dx,dz)
    end
    if length < 1e-10 then return fraction, 0, 0, kind or 'barrier' end
    return fraction, normalX/length, normalZ/length, kind or 'barrier'
end

local function step(p,input,dt,world)
    local profile=Upgrades.profile(p.upgradeLevel)
    local speedScale=profile.maxSpeed/Bike.MAX_SPEED
    local frontBefore,rearBefore=wheelSupports(p,world)
    local throttle=M.clamp(input.throttle or 0,0,1);local brake=M.clamp(input.brake or 0,0,1)
    local requestedSteering=M.clamp(input.steer or 0,-1,1)
    p.steering,p.steeringVelocity=Damping.spring(p.steering or 0,requestedSteering,
        p.steeringVelocity,Bike.STEER_SMOOTH_TIME,dt)
    local steering=M.clamp(p.steering,-1,1)
    local boosting=input.boost==true and throttle>.05 and not p.reverse
    local direction=p.reverse and -1 or 1
    -- At a trailhead the paved street keeps its grip across the trail mouth.
    local d,s=world.roads:nearest(p.x,p.z,true)
    local roadAmount=s and s.surface~='dirt' and 1-M.smooth(d-s.width*.5) or 0
    local roadScale=M.lerp(Bike.OFFROAD_SCALE,1,roadAmount)
    local grip=M.lerp(Bike.DIRT_GRIP,Bike.ROAD_GRIP,roadAmount)
    local response=M.lerp(Bike.DIRT_RESPONSE,Bike.ROAD_RESPONSE,roadAmount)
    p.surface=roadAmount>=.5 and 'road' or 'dirt'
    local limit=p.reverse and Bike.REVERSE_MAX_SPEED or
        Damage.speedLimit(roadScale*(boosting and profile.boostMaxSpeed or profile.maxSpeed), p.damage)
    p.throttle=throttle;p.brake=brake;p.steering=steering
    p.boostPulse=math.max(0,(p.boostPulse or 0)-dt)
    p.impactPulse=math.max(0,(p.impactPulse or 0)-dt)
    if boosting and not p.boosting then
        p.boostPulse=Bike.BOOST_PULSE
        RidingAnimation.request(p,'boost')
    end
    p.boosting=boosting
    p.grade=(frontBefore-rearBefore)/Bike.WHEELBASE
    local groundPitch=math.atan(p.grade)
    p.shiftTime=math.max(0,p.shiftTime-dt);p.shiftCooldown=math.max(0,p.shiftCooldown-dt)
    local gear=Bike.GEARS[p.gear]
    if not p.reverse and p.transmission=='automatic' and p.shiftCooldown==0 then
        if p.speed<gear.down*speedScale then Bike.shift(p,-1)
        elseif throttle>0 and p.speed>gear.up*speedScale then Bike.shift(p,1) end
        gear=Bike.GEARS[p.gear]
    end
    local gearSpeed=gear.speed*speedScale
    local revs=p.speed/gearSpeed
    -- A forgiving centrifugal clutch permits starts; tall gears still lug.
    local torque=M.clamp(.22+revs*1.6,p.gear==1 and .85 or .22,1)
    local gearDrive=throttle*gear.force*profile.acceleration*torque*M.clamp((1-revs)/.12,0,1)
    local boostDrive=boosting and throttle*Bike.BOOST_ACCELERATION*profile.acceleration
        *M.clamp((gearSpeed*1.08-p.speed)/(gearSpeed*.08),0,1) or 0
    local drive=p.shiftTime==0 and gearDrive+boostDrive or 0
    if p.reverse then drive=throttle*1.8*M.clamp((limit-p.speed)/.25,0,1) end
    if p.speed>limit then drive=0 end
    local drag=.22+.005*p.speed*p.speed+(throttle==0 and .6*4.4/gearSpeed or 0)
    local before=p.speed
    local vxBefore,vzBefore=p.vx,p.vz
    local turn=steering*(1.5-M.clamp(p.speed/20,0,.8))*math.min(p.speed/1.5,1)*(p.grounded and 1 or .12)
    p.heading=(p.heading+turn*dt*direction)%(math.pi*2)
    local fx,fz=math.cos(p.heading)*direction,math.sin(p.heading)*direction
    if dt>0 and p.grounded and (before>0 or throttle>0) then
        local forward=p.vx*fx+p.vz*fz
        local lateral=-p.vx*fz+p.vz*fx
        -- Both tires share a finite grip budget. Braking/drive consume part of
        -- it, leaving less force to redirect momentum through a tight corner.
        -- Brakes win over throttle and cannot propel the bike backward.
        local longitudinal=drive*(1-brake)-brake*Bike.BRAKE*(forward<0 and -1 or 1)
        if longitudinal<0 and forward>=0 then longitudinal=math.max(longitudinal,-forward/dt)
        elseif longitudinal>0 and forward<0 then longitudinal=math.min(longitudinal,-forward/dt) end
        local lateralRequest=-lateral*math.min(response,1/dt)
        local demand=M.length(longitudinal,lateralRequest)
        local appliedLong=M.clamp(longitudinal,-grip,grip)
        local lateralGrip=math.sqrt(math.max(0,grip*grip-appliedLong*appliedLong))
        local appliedLateral=M.clamp(lateralRequest,-lateralGrip,lateralGrip)
        p.tireSlip=M.clamp((demand-grip)/grip,0,1)
        p.vx=p.vx+(fx*appliedLong-fz*appliedLateral)*dt
        p.vz=p.vz+(fz*appliedLong+fx*appliedLateral)*dt
        local rollingSpeed=M.length(p.vx,p.vz)
        local resistance=rollingSpeed>0 and math.max(0,1-drag*dt/rollingSpeed) or 0
        p.vx,p.vz=p.vx*resistance,p.vz*resistance
        local slope=-Bike.GRAVITY*math.sin(groundPitch)*direction
        -- Keep the original parking/clutch hold near zero forward speed.
        local along=p.vx*fx+p.vz*fz
        if along>=0 and slope<0 then slope=math.max(slope,-along/dt) end
        p.vx,p.vz=p.vx+fx*slope*dt,p.vz+fz*slope*dt
    elseif not p.grounded then
        -- Air steering can rotate the rider slightly; it cannot redirect the
        -- bike's trajectory until the tires make contact again.
        local airDrag=math.max(0,1-.02*dt)
        p.vx,p.vz=p.vx*airDrag,p.vz*airDrag;p.tireSlip=0
    elseif dt>0 then p.vx,p.vz,p.tireSlip=0,0,0 end
    p.speed=M.length(p.vx,p.vz)
    local speedCeiling=math.max(limit,before)
    if (p.damage or 0)>0 and not p.reverse then
        speedCeiling=math.min(speedCeiling,Damage.speedLimit(profile.boostMaxSpeed,p.damage))
    end
    if p.speed>speedCeiling then
        local scale=speedCeiling/p.speed;p.vx,p.vz=p.vx*scale,p.vz*scale;p.speed=speedCeiling
    end
    if p.grounded and throttle==0 and p.speed<.025 then p.vx,p.vz,p.speed=0,0,0 end
    local travelX,travelZ=(vxBefore+p.vx)*.5*dt,(vzBefore+p.vz)*.5*dt
    local steps=math.max(1,math.ceil(M.length(travelX,travelZ)/.18))
    local wheelOffset=math.abs(halfBase*math.tan(p.pitch or 0))
    local nextHeight=p.h+p.vy*dt
    local bottom=math.min(p.h,nextHeight)-wheelOffset
    local top=math.max(p.h,nextHeight)+wheelOffset+Bike.COLLISION_HEIGHT
    local moved=0
    for _=1,steps do
        local nx,nz=p.x+travelX/steps,p.z+travelZ/steps
        local hit,nxHit,nzHit,kind,id
        if world.sweepObstacles then
            hit,nxHit,nzHit,kind,id=world:sweepObstacles(p.x,p.z,nx,nz,Bike.RADIUS,bottom,top)
        end
        if world.infrastructure then
            local t,fx,fz,fixtureKind,fixtureId=world.infrastructure:sweep(p.x,p.z,nx,nz,Bike.RADIUS,bottom,top)
            if t and (not hit or t<hit) then hit,nxHit,nzHit,kind,id=t,fx,fz,fixtureKind,fixtureId end
        end
        local barrier, bx, bz, barrierKind=barrierHit(world,p.x,p.z,nx,nz)
        if barrier and (not hit or barrier<hit) then hit,nxHit,nzHit,kind,id=barrier,bx,bz,barrierKind,nil end
        if hit then
            local fraction=math.max(0,hit-1e-4)
            local hx,hz=p.x+(nx-p.x)*fraction,p.z+(nz-p.z)*fraction
            moved=moved+M.length(hx-p.x,hz-p.z);p.x,p.z=hx,hz
            local inward=p.vx*nxHit+p.vz*nzHit
            local impactSpeed=math.max(0,-inward)
            local newContact=not p.collisionContact or p.collisionKind~=kind or p.collisionId~=id
            if kind~='travelLimit' and newContact and impactSpeed>Bike.IMPACT_MIN_SPEED then
                p.impactPulse=Bike.IMPACT_DURATION
                p.impactStrength=.3+.7*M.clamp(impactSpeed/Damage.EJECTION_SPEED,0,1)
                Damage.impact(p,impactSpeed,nxHit,nzHit,p.vx,p.vz,kind)
            end
            p.collisionContact,p.collisionKind,p.collisionId=true,kind,id
            if inward<0 then p.vx,p.vz=p.vx-inward*nxHit,p.vz-inward*nzHit end
            p.speed=M.length(p.vx,p.vz)
            if p.speed<.025 or p.crashPending then p.vx,p.vz,p.speed=0,0,0 end
            break
        end
        p.collisionContact=false
        moved=moved+M.length(nx-p.x,nz-p.z);p.x,p.z=nx,nz
    end
    p.acceleration=dt>0 and (p.speed-before)/dt or 0
    p.rpm=Bike.rpmForSpeed(p)
    p._velocitySpeed=p.speed
    p.distance=p.distance+moved
    p.lean,p.leanVelocity=Damping.spring(p.lean or 0,M.clamp(-steering*p.speed*.025,-.8,.8),
        p.leanVelocity,Bike.LEAN_SMOOTH_TIME,dt)
    local front,rear=wheelSupports(p,world)
    contact(p,dt,front,rear,frontBefore,rearBefore,throttle,brake)
    p.lateralSpeed=-p.vx*fz+p.vz*fx
    p.slipAngle=p.speed>.1 and math.atan2(p.lateralSpeed,p.vx*fx+p.vz*fz) or 0
    p.slip=p.grounded and p.speed>.5 and M.clamp(math.abs(p.slipAngle)/.6,0,1) or 0
    if not p.grounded then p.tireSlip=0 end
    RidingAnimation.update(p,dt)
    return moved
end
function Bike.update(p,input,dt,world)
    if not M.finite(p.h) then Bike.resetContact(p,world) end
    -- Older saves, callers and lab probes initialize a scalar speed. Keep that
    -- supported without discarding lateral momentum on ordinary updates.
    if not M.finite(p.vx) or not M.finite(p.vz) or p._velocitySpeed==nil
        or math.abs(p.speed-p._velocitySpeed)>1e-7 then Bike.resetHorizontal(p) end
    dt=M.clamp(dt,0,.1)
    local count=math.max(1,math.ceil(dt*120-1e-9));local moved=0
    for _=1,count do
        if p.crashPending then break end
        moved=moved+step(p,input,dt/count,world)
    end
    rememberRecoveryPoint(p,world)
    return moved
end
return Bike
