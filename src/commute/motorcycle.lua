local M=require('src.commute.vendor.mathx')
local RidingAnimation=require('src.commute.riding_animation')
local Damping=require('src.commute.damping')
local Bike={MAX_SPEED=12,REVERSE_MAX_SPEED=1.2,BOOST_MAX_SPEED=14.4,BOOST_ACCELERATION=1.6,BOOST_PULSE=.78,
    TUCK_START_SPEED=13.35,IMPACT_DURATION=.62,IMPACT_MIN_SPEED=.35,
    ACCELERATION=3.4,BRAKE=9,COAST=1.0,WHEELBASE=1.25,RADIUS=.42,
    IDLE_RPM=1400,REDLINE=8000,SHIFT_TIME=.16,STEER_SMOOTH_TIME=.20,LEAN_SMOOTH_TIME=.30,
    GEARS={{speed=4.4,force=4.4,up=3.6,down=0},{speed=7.1,force=3.4,up=6,down=2.3},
        {speed=10,force=2.6,up=8.6,down=4.2},{speed=15,force=2,up=math.huge,down=6.4}}}
function Bike.new(x,z,heading)
    return {x=x,z=z,heading=heading or 0,speed=0,distance=0,lean=0,gear=1,transmission='automatic',
        rpm=Bike.IDLE_RPM,shiftTime=0,shiftDirection=0,shiftCooldown=0,throttle=0,grade=0,
        reverse=false,headlight=false,boosting=false,boostPulse=0,steering=0,acceleration=0,impactPulse=0,impactStrength=0,collisionContact=false,
        ridingAnimation={kind='idle',remaining=0,queue={}}}
end
function Bike.valid(p)
    return type(p)=='table' and (p.gear==nil or M.finite(p.gear) and p.gear%1==0 and p.gear>=1 and p.gear<=#Bike.GEARS)
        and (p.transmission==nil or p.transmission=='automatic' or p.transmission=='manual')
        and (p.reverse==nil or type(p.reverse)=='boolean') and (p.headlight==nil or type(p.headlight)=='boolean')
end
function Bike.shift(p,delta)
    local target=p.gear+delta
    if p.shiftTime>0 then return false,'Finish the current shift first.' end
    if target<1 or target>#Bike.GEARS then return false,delta>0 and 'Already in top gear.' or 'Already in first gear.' end
    if p.speed>Bike.GEARS[target].speed then return false,'Slow down before selecting that gear.' end
    p.gear=target;p.shiftTime=Bike.SHIFT_TIME;p.shiftDirection=delta;p.shiftCooldown=.65
    RidingAnimation.request(p,'shift')
    return true
end
function Bike.command(p,action)
    if action=='headlight' then p.headlight=not p.headlight;return true,p.headlight and 'Headlight on.' or 'Headlight off.' end
    if action=='reverse' then
        if math.abs(p.speed or 0)>.05 or p.shiftTime>0 then return false,'Stop completely before selecting forward or reverse.' end
        p.speed=0;p.reverse=not p.reverse;p.gear=1;p.boosting=false
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
local function step(p,input,dt,world)
    local throttle=M.clamp(input.throttle or 0,0,1);local brake=M.clamp(input.brake or 0,0,1)
    local requestedSteering=M.clamp(input.steer or 0,-1,1)
    p.steering,p.steeringVelocity=Damping.spring(p.steering or 0,requestedSteering,
        p.steeringVelocity,Bike.STEER_SMOOTH_TIME,dt)
    local steering=M.clamp(p.steering,-1,1)
    local boosting=input.boost==true and throttle>.05 and not p.reverse
    local direction=p.reverse and -1 or 1
    local d,s=world.roads:nearest(p.x,p.z)
    local roadLimit=s and d<s.width*.5+1 and Bike.MAX_SPEED or 4
    local limit=p.reverse and Bike.REVERSE_MAX_SPEED or roadLimit*(boosting and Bike.BOOST_MAX_SPEED/Bike.MAX_SPEED or 1)
    p.throttle=throttle;p.brake=brake;p.steering=steering
    p.boostPulse=math.max(0,(p.boostPulse or 0)-dt)
    p.impactPulse=math.max(0,(p.impactPulse or 0)-dt)
    if boosting and not p.boosting then
        p.boostPulse=Bike.BOOST_PULSE
        RidingAnimation.request(p,'boost')
    end
    p.boosting=boosting
    local dx,dz=math.cos(p.heading)*Bike.WHEELBASE*.5,math.sin(p.heading)*Bike.WHEELBASE*.5
    p.grade=(world:supportHeight(p.x+dx,p.z+dz)-world:supportHeight(p.x-dx,p.z-dz))/Bike.WHEELBASE
    p.pitch=math.atan(p.grade)
    p.shiftTime=math.max(0,p.shiftTime-dt);p.shiftCooldown=math.max(0,p.shiftCooldown-dt)
    local gear=Bike.GEARS[p.gear]
    if not p.reverse and p.transmission=='automatic' and p.shiftCooldown==0 then
        if p.speed<gear.down then Bike.shift(p,-1)
        elseif throttle>0 and p.speed>gear.up then Bike.shift(p,1) end
        gear=Bike.GEARS[p.gear]
    end
    local revs=p.speed/gear.speed
    -- A forgiving centrifugal clutch permits starts; tall gears still lug.
    local torque=M.clamp(.22+revs*1.6,p.gear==1 and .85 or .22,1)
    local gearDrive=throttle*gear.force*torque*M.clamp((1-revs)/.12,0,1)
    local boostDrive=boosting and throttle*Bike.BOOST_ACCELERATION
        *M.clamp((gear.speed*1.08-p.speed)/(gear.speed*.08),0,1) or 0
    local drive=p.shiftTime==0 and gearDrive+boostDrive or 0
    if p.reverse then drive=throttle*1.8*M.clamp((limit-p.speed)/.25,0,1) end
    local drag=.22+.005*p.speed*p.speed+(throttle==0 and .6*4.4/gear.speed or 0)
    local acceleration=drive-brake*Bike.BRAKE-drag-9.81*math.sin(p.pitch)*direction
    local before=p.speed
    -- Parking hold prevents a stationary bike creeping away during ignition.
    local speedCeiling=math.max(limit,before)
    p.speed=(before==0 and throttle==0) and 0 or M.clamp(before+acceleration*dt,0,speedCeiling)
    p.acceleration=dt>0 and (p.speed-before)/dt or 0
    p.rpm=M.clamp(Bike.REDLINE*p.speed/gear.speed,Bike.IDLE_RPM,Bike.REDLINE)
    if p.reverse then p.rpm=Bike.IDLE_RPM+p.speed*500 end
    local turn=steering*(1.5-M.clamp(p.speed/20,0,.8))*math.min(p.speed/1.5,1)
    p.heading=(p.heading+turn*dt*direction)%(math.pi*2)
    local steps=math.max(1,math.ceil(p.speed*dt/.18));local travel=(before+p.speed)*.5*dt/steps
    local moved=0
    for _=1,steps do
        local nx,nz=p.x+math.cos(p.heading)*travel*direction,p.z+math.sin(p.heading)*travel*direction
        local blocked=false
        for i=0,7 do local a=i*math.pi/4
            if world.roads:blocked(world,nx+math.cos(a)*Bike.RADIUS,nz+math.sin(a)*Bike.RADIUS) then blocked=true;break end
        end
        if blocked then
            if not p.collisionContact and before>Bike.IMPACT_MIN_SPEED then
                p.impactPulse=Bike.IMPACT_DURATION
                p.impactStrength=.3+.7*M.clamp(before/Bike.BOOST_MAX_SPEED,0,1)
            end
            p.collisionContact=true
            p.speed=0;break
        end
        p.collisionContact=false
        moved=moved+M.length(nx-p.x,nz-p.z);p.x,p.z=nx,nz
    end
    p.distance=p.distance+moved
    p.lean,p.leanVelocity=Damping.spring(p.lean or 0,-steering*p.speed*.025,
        p.leanVelocity,Bike.LEAN_SMOOTH_TIME,dt)
    p.h=world:supportHeight(p.x,p.z)
    RidingAnimation.update(p,dt)
    return moved
end
function Bike.update(p,input,dt,world)
    dt=M.clamp(dt,0,.1)
    local count=math.max(1,math.ceil(dt*120-1e-9));local moved=0
    for _=1,count do moved=moved+step(p,input,dt/count,world) end
    return moved
end
return Bike
