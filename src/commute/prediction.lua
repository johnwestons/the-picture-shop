-- A private physics replica. Replaying inputs never charges fuel, pays a job,
-- starts a delivery cinematic, or changes the authoritative household.
local Rider=require('src.commute.rider')
local Truck=require('src.commute.delivery_truck')
local Gear=require('src.commute.gear')
local Copy=require('src.net.shop_replication').copy
local P={PART_VALUES=64}
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
local access={}
for mode,names in pairs(P.fields)do
    access[mode]={}
    for i,key in ipairs(names)do
        local parent,field=key:match('^([^.]+)%.(.+)$')
        access[mode][i]={parent=parent,field=field or key,boolean=booleans[key]}
    end
end
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
    for i,field in ipairs(access[mode]) do
        local source=body
        if field.parent then source=body[field.parent]end
        local value=source and source[field.field]
        if field.boolean then value=value==true and 1 or 0 else value=tonumber(value) or 0 end
        -- Binary checkpoint doubles preserve the host's actual integration
        -- seed. Decimal rounding amplified into RPM/velocity derivative drift
        -- on the next step and forced otherwise unnecessary history replay.
        values[i]=value
    end
    local contact
    if mode=='bike' and body.collisionContact==true and body.collisionKind~=nil then
        -- Contact identity is part of the integrator state: dropping it makes
        -- an existing impact look new on the first replayed physics step.
        contact={kind=body.collisionKind,id=body.collisionId}
    end
    return {key=P.key(part,token),mode=mode,values=values,contact=contact}
end
function P.captureLocal(player)
    local prediction=player and player._predictedCommute
    return prediction and P.capture(prediction.part,prediction.token) or nil
end
local function matches(left,right,except)
    if type(left)~='table' or type(right)~='table' or left.key~=right.key or left.mode~=right.mode then return false end
    local names=P.fields[left.mode]
    if not names or type(left.values)~='table' or type(right.values)~='table'
        or #left.values~=#names or #right.values~=#names then return false end
    for i,key in ipairs(names)do
        local a,b=left.values[i],right.values[i]
        if type(a)~='number' or type(b)~='number' or a~=a or b~=b
            or a==math.huge or a==-math.huge or b==math.huge or b==-math.huge then return false end
        if key==except then
            -- Only the guarded shared-fuel rebase below may omit this field.
        elseif booleans[key] or key=='gear' or key=='facing' or key=='shiftDirection' then
            if a~=b then return false end
        -- Permit only tiny cross-platform numerical drift. Full-precision
        -- seeds prevent derivative noise without widening any field tolerance.
        elseif math.abs(a-b)>1.0001e-6 then return false end
        if left.mode=='bike' and key=='collisionContact' and a==1 then
            local aContact,bContact=left.contact,right.contact
            if aContact~=nil and type(aContact)~='table' or bContact~=nil and type(bContact)~='table'
                or (aContact and aContact.kind)~=(bContact and bContact.kind)
                or (aContact and aContact.id)~=(bContact and bContact.id) then return false end
        end
    end
    return true
end
function P.matches(left,right)return matches(left,right)end
function P.reconcileSharedTruckFuel(player,history,expected,authoritative)
    if type(authoritative)~='table'then return false end
    local mode=authoritative.mode
    if mode~='box' and mode~='kei' or not matches(expected,authoritative,'fuel') then return false end
    if type(authoritative.sequence)~='number' or authoritative.sequence<0 or authoritative.sequence>4294967295
        or authoritative.sequence~=math.floor(authoritative.sequence) then return false end
    local prediction=player and player._predictedCommute
    if not prediction or prediction.key~=authoritative.key or prediction.mode~=mode then return false end
    local body=prediction.rider and prediction.rider.truck
    if not body or body.model~=mode or body.engine~=true or type(history)~='table' or #history>240 then return false end
    local fuelIndex,engineIndex
    for i,key in ipairs(P.fields[mode])do
        if key=='fuel'then fuelIndex=i elseif key=='engine'then engineIndex=i end
    end
    local before,after=expected.values[fuelIndex],authoritative.values[fuelIndex]
    local delta=after-before
    -- Company trucks share fuel: another driver's consumption changes our
    -- fuel independently of our input sequence. Positive changes/refills and
    -- engine transitions retain ordinary authoritative restore/replay.
    if delta>=0 or delta< -Truck.TANK_LITERS or expected.values[engineIndex]~=1
        or authoritative.values[engineIndex]~=1 then return false end
    -- Keep two units of the existing comparison tolerance above empty. This
    -- conservative 0.013m fuel margin always uses full replay at depletion.
    local margin=2e-6
    local function safe(value)
        return type(value)=='number' and value==value and value>margin and value<=Truck.TANK_LITERS
    end
    if not safe(before) or not safe(after) or not safe(body.fuel) or not safe(body.fuel+delta) then return false end
    local updates={}
    for _,command in ipairs(history)do
        if type(command.sequence)~='number' or command.sequence<0 or command.sequence>4294967295
            or command.sequence~=math.floor(command.sequence) then return false end
        if command.sequence>authoritative.sequence then
            local checkpoint=command.checkpoint
            if not checkpoint or checkpoint.key~=authoritative.key or checkpoint.mode~=mode
                or not P.matches(checkpoint,checkpoint) or checkpoint.values[engineIndex]~=1 then return false end
            local old=checkpoint.values[fuelIndex]
            local value=old+delta
            if not safe(old) or not safe(value) then return false end
            updates[#updates+1]={checkpoint=checkpoint,fuel=value}
        end
    end
    -- Preflight every retained checkpoint before changing any private state.
    expected.values[fuelIndex]=after
    for _,update in ipairs(updates)do update.checkpoint.values[fuelIndex]=update.fuel end
    body.fuel=body.fuel+delta
    return true
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
    if prediction.mode=='bike' then
        local contact=snapshot.contact
        body.collisionKind=contact and contact.kind or nil
        body.collisionId=contact and contact.id or nil
    end
    -- Preserve _velocitySpeed as captured: Bike.update uses a real difference
    -- from speed to detect an intentional host reset, including after impact.
    return true
end
function P.controls(rider,x,y,boost)
    return (rider.vehicle=='truck' or rider.gear.mounted)
        and {steer=x,drive=y,boost=rider.vehicle~='truck' and boost==true}
        or {walkX=x,walkZ=y,sprint=boost==true}
end
function P.step(player,part,token,dt,x,y,boost,world,state,visitors)
    local prediction=P.ensure(player,part,token);if not prediction then return false end
    local mode=prediction.mode
    if mode=='grocery' or mode=='barn' then
        prediction.part.interiorPose.id=player.id
        prediction.part.interiorPose.homeResidentId=player.homeResidentId
        require('src.commute.'..mode..'_interior').movePose(prediction.part.interiorPose,x,y,dt,state)
    else
        local rider=prediction.rider
        local controls=P.controls(rider,x,y,boost)
        controls.walkScale=require('src.player_medical').speed(state,player,true)
        local function step()
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
        local trip=state.home and state.home.commute
        local source=trip and trip.participants and trip.participants[require('src.home_residents').key(player)]
        require('src.commute.delivery_traffic').withPredictionObstacles(state,world,
            source and source.rider or part.rider,visitors,step)
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
