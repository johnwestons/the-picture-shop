-- A private physics replica. Replaying inputs never charges fuel, pays a job,
-- starts a delivery cinematic, or changes the authoritative household.
local Rider=require('src.commute.rider')
local Truck=require('src.commute.delivery_truck')
local Gear=require('src.commute.gear')
local Copy=require('src.net.shop_replication').copy
local P={PART_VALUES=24}
local common={'x','z','heading','speed','distance','h','pitch','vx','vz','vy','reverse'}
local function fields(extra)
    local result={};for _,v in ipairs(common) do result[#result+1]=v end
    for _,v in ipairs(extra) do result[#result+1]=v end
    return result
end
P.fields={
    ped=fields({}),
    bike=fields({'_velocitySpeed','lean','leanVelocity','gear','pitchVelocity','suspension','landingPulse',
        'lateralSpeed','slipAngle','slip','tireSlip','rpm','shiftTime','shiftDirection','shiftCooldown',
        'throttle','brake','grade','boosting','boostPulse','steering','steeringVelocity','acceleration',
        'impactPulse','impactStrength','collisionContact','frontGrounded','rearGrounded','grounded',
        'damage','stallClock','safeX','safeZ','safeHeading','service.fuel','service.miles','service.oil','service.chain','service.tread'}),
    box=fields({'steering','slipAngle','throttle','brake','acceleration','collisionContact','collisionStun','fuel','engine','damage'}),
    kei=fields({'steering','slipAngle','throttle','brake','acceleration','collisionContact','collisionStun','fuel','engine','damage'}),
    grocery={'x','y','velocityX','velocityY','intentX','intentY','animationDistance','facing','moving','cartPushing'},
    barn={'x','y','velocityX','velocityY','intentX','intentY','animationDistance','facing','moving'},
}
for _,mode in ipairs({'box','kei'})do
    for _,field in ipairs({'totalMiles','oilMiles','oilFilterMiles','airFilterMiles','sparkPlugMiles',
        'coolantMiles','tireMiles','brakeMiles','failureClock','mechanicalFailure'})do
        P.fields[mode][#P.fields[mode]+1]='service.'..field
    end
end
local booleans={reverse=true,boosting=true,collisionContact=true,frontGrounded=true,rearGrounded=true,
    grounded=true,engine=true,moving=true,cartPushing=true,['service.mechanicalFailure']=true}
P.booleans=booleans
local function fieldTarget(body,key)
    local parent,field=key:match('^([^.]+)%.(.+)$')
    if parent then body[parent]=body[parent] or {};return body[parent],field end
    return body,key
end
function P.mode(part)
    if not part or part.arrived then return nil end
    if part.interior then return P.fields[part.interior] and part.interior or nil end
    local rider=part.rider
    if not rider or rider.gear.transition or rider.ped.crash then return nil end
    local pose=part.presentation and part.presentation.pose or Rider.pose(rider)
    if pose~='normal_idle' and pose~='geared_idle' and pose~='riding' and pose~='seated' then return nil end
    return rider.vehicle=='truck' and (rider.truck.model or 'box') or rider.gear.mounted and 'bike' or 'ped'
end
function P.key(part,token)
    local mode=P.mode(part)
    return mode and ('ride_'..token..'_'..mode..'_'..(part.rider.gear.revision or 0)) or nil
end
local function actor(part,mode)
    if mode=='grocery' or mode=='barn' then return part.interiorPose end
    return mode=='bike' and part.rider.bike or mode=='ped' and part.rider.ped or part.rider.truck
end
function P.capture(part,token)
    local mode=P.mode(part);if not mode then return nil end
    local values={};local body=actor(part,mode)
    for i,key in ipairs(P.fields[mode]) do
        local parent,field=key:match('^([^.]+)%.(.+)$')
        local value=parent and body[parent] and body[parent][field] or body[key]
        if booleans[key] then value=value==true and 1 or 0 else value=tonumber(value) or 0 end
        values[i]=math.floor(value*1000000+.5)/1000000
    end
    return {key=P.key(part,token),mode=mode,values=values}
end
function P.ensure(player,part,token)
    local key=P.key(part,token)
    if not key then player._predictedCommute=nil;return nil end
    local prediction=player._predictedCommute
    if prediction and prediction.key==key then
        if prediction.source~=part.rider then
            for _,field in ipairs({'transmission','upgradeLevel','upgradeParts','paintId','headlight','headlightHighBeam'})do
                prediction.rider.bike[field]=Copy(part.rider.bike[field])
            end
            prediction.rider.bike.service.tire=part.rider.bike.service.tire
            if prediction.rider.truck and part.rider.truck then
                for _,field in ipairs({'livery','headlight','headlightHighBeam','turnSignal'})do
                    prediction.rider.truck[field]=Copy(part.rider.truck[field])
                end
                local service=part.rider.truck.service
                if service then
                    prediction.rider.truck.service=prediction.rider.truck.service or require('src.commute.truck_service').new()
                    for _,field in ipairs({'upgrades','failureType','revision','upgradeRevision'})do
                        prediction.rider.truck.service[field]=Copy(service[field])
                    end
                end
            end
            prediction.source=part.rider
        end
        return prediction
    end
    local source=part.rider
    local rider=Rider.new(source.bike.x,source.bike.z,source.bike.heading,source.gear)
    for field,value in pairs(source.bike) do rider.bike[field]=Copy(value) end
    for field,value in pairs(source.ped) do rider.ped[field]=Copy(value) end
    rider.vehicle,rider.transport=source.vehicle,source.transport
    if source.truck then
        rider.truck=Truck.new(source.truck.x,source.truck.z,source.truck.heading,source.truck.livery,source.truck.model)
        for field,value in pairs(source.truck) do rider.truck[field]=Copy(value) end
    end
    local replica={rider=rider,interior=part.interior,interiorPose=Copy(part.interiorPose)}
    prediction={key=key,token=token,mode=P.mode(part),part=replica,rider=rider,source=source}
    player._predictedCommute=prediction
    return prediction
end
function P.restore(player,part,token,snapshot)
    if snapshot.key~=P.key(part,token) or snapshot.mode~=P.mode(part)
        or #snapshot.values~=#(P.fields[snapshot.mode] or {}) then return false end
    local prediction=P.ensure(player,part,token)
    prediction.rider.gear=assert(Gear.restore(part.rider.gear))
    prediction.rider.vehicle=part.rider.vehicle
    prediction.rider.ped.crash=nil;prediction.rider.bike.crashPending=nil
    local body=actor(prediction.part,prediction.mode)
    if prediction.mode=='box' or prediction.mode=='kei' then
        body.service=Copy(part.rider.truck.service) or require('src.commute.truck_service').new()
    end
    for i,key in ipairs(P.fields[prediction.mode]) do
        local target,field=fieldTarget(body,key)
        if booleans[key] then target[field]=snapshot.values[i]==1 else target[field]=snapshot.values[i] end
    end
    -- Quantization must not make Bike.update mistake replicated lateral
    -- velocity for an intentional scalar-speed reset.
    if prediction.mode=='bike' then body._velocitySpeed=body.speed end
    return true
end
function P.controls(rider,x,y,boost)
    return (rider.vehicle=='truck' or rider.gear.mounted)
        and {steer=x,drive=y,boost=rider.vehicle~='truck' and boost==true}
        or {walkX=x,walkZ=y,sprint=boost==true}
end
function P.step(player,part,token,dt,x,y,boost,world,state)
    local prediction=P.ensure(player,part,token);if not prediction then return false end
    local mode=prediction.mode
    if mode=='grocery' or mode=='barn' then
        prediction.part.interiorPose.id=player.id
        prediction.part.interiorPose.homeResidentId=player.homeResidentId
        require('src.commute.'..mode..'_interior').movePose(prediction.part.interiorPose,x,y,dt,state)
    else
        local rider=prediction.rider
        local controls=P.controls(rider,x,y,boost)
        controls.walkScale=require('src.player_medical').speed(state,player)
        if rider.vehicle=='truck' then
            local trip=state.home and state.home.commute
            local run=trip and (not trip.independent or trip.deliveryDriver==require('src.home_residents').key(player)) and trip.deliveryRun
            if run and run.status=='loading' then
                local loaded=require('src.commute.delivery_run').loadingProgress(state,run)
                if (loaded or 0)>0 and require('src.commute.trip').truckAtLoadingBay(world,rider.truck) then
                    controls={drive=0,steer=0,brake=1}
                end
            end
            Truck.update(rider.truck,controls,dt,world)
            rider.ped.x,rider.ped.z,rider.ped.heading=rider.truck.x,rider.truck.z,rider.truck.heading
        else Rider.update(rider,controls,dt,world) end
    end
    return true
end
function P.presentation(prediction)
    local rider=prediction.rider;local body=Rider.actor(rider)
    local pose,progress=Gear.pose(rider.gear)
    local result={pose=pose,progress=progress,speed=body.speed or 0,distance=body.distance or 0,
        heading=body.heading,steer=body.steering or 0,boost=body.boosting==true}
    for _,key in ipairs({'h','vy','pitch','grounded','suspension','landingPulse','throttle','brake','slip',
        'tireSlip','lateralSpeed','grade','shiftTime','lean','boostPulse','impactPulse','impactStrength','rpm'}) do result[key]=body[key] end
    return result
end
return P
