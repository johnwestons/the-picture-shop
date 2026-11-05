-- Persistent, low-cost location tracking for scheduled supply trucks.
-- Positions are derived from game-clock timestamps and the saved road graph;
-- saves only retain a few timestamps, never a per-frame position history.
local Calendar=require('src.business_calendar')
local Network={CITY='Millhaven',AVERAGE_SPEED=8}

local citySites={
    'Millhaven Paper Depot','Millhaven Freight Yard','Millhaven Press Row',
    'Millhaven Commercial Wharf',
}
local routeCache={}

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end
local function hash(text)
    local result=17
    for i=1,#tostring(text or '') do result=(result*131+tostring(text):byte(i))%2147483647 end
    return result
end
local function townWorld(town)
    if type(town)~='table' or type(town.id)~='string' then return nil end
    local cached=routeCache[town.id]
    if cached then return cached end
    local ok,world=pcall(require('src.commute.town').world,town)
    if not ok or not world or not world.mainlandExit then return nil end
    local Routes=require('src.commute.routes')
    local planner=Routes.new(world.roads)
    local gate=world.mainlandExit
    local inward=planner:findFromPoint(gate.x,gate.z,'warehouse')
    if not inward or type(inward.points)~='table' or #inward.points<2 then return nil end
    local length=0
    for i=2,#inward.points do
        local a,b=inward.points[i-1],inward.points[i]
        length=length+math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
    end
    if length<1 then return nil end
    local outward={}
    for i=#inward.points,1,-1 do
        local p=inward.points[i]
        outward[#outward+1]={x=p.x,z=p.z,h=p.h}
    end
    cached={world=world,gate=gate,inward=inward.points,outward=outward,length=length}
    routeCache[town.id]=cached
    return cached
end

local function routeSample(points,length,progress)
    if type(points)~='table' or #points<2 then return nil end
    local wanted=math.max(0,math.min(1,progress))*length
    local walked=0
    for i=2,#points do
        local a,b=points[i-1],points[i]
        local dx,dz=b.x-a.x,b.z-a.z
        local segment=math.sqrt(dx*dx+dz*dz)
        if wanted<=walked+segment or i==#points then
            local t=segment>1e-6 and math.max(0,math.min(1,(wanted-walked)/segment)) or 1
            return {x=a.x+dx*t,z=a.z+dz*t,h=(a.h or b.h or 0)+((b.h or a.h or 0)-(a.h or b.h or 0))*t,
                heading=math.atan2(dz,dx)}
        end
        walked=walked+segment
    end
end

local function firstOrder(state,shipment)
    local wanted={}
    for _,id in ipairs(shipment.orderIds or {}) do wanted[id]=true end
    for _,order in ipairs(state.procurement and state.procurement.orders or {}) do
        if wanted[order.id] then return order end
    end
end

local function sourceLocation(state,shipment)
    local order=firstOrder(state,shipment)
    if order and order.category=='paper' then return citySites[1] end
    local index=(hash(shipment.id)+1)%#citySites+1
    return citySites[index]
end

local function shipmentCompany(state,shipment)
    local wanted,companies={},{}
    for _,id in ipairs(shipment.orderIds or {}) do wanted[id]=true end
    for _,order in ipairs(state.procurement and state.procurement.orders or {}) do
        if wanted[order.id] then
            local company=order.company or order.vendor
            if type(company)=='string' and company~='' and not companies[company] then
                companies[company]=true
            end
        end
    end
    local only,count=nil,0
    for company in pairs(companies) do only=company;count=count+1 end
    if count==1 then return only end
    return 'Millhaven Freight'
end

local function updateTrackedDelivery(delivery,company,location,id,now,epoch,durationHours,route)
    if type(delivery)~='table' then return false end
    local expected=tonumber(delivery.readyAtHours)
    local changed=false
    if delivery.status=='pending_arrival' and expected and not delivery.route then
        delivery.route={originCity=Network.CITY,originLocation=location,
            originCompany=company,destination='warehouse',startAtHours=expected-durationHours,
            arrivalAtHours=expected,roadTownId=id}
        changed=true
    end
    local inbound=delivery.route
    if inbound and not inbound.departedAtEpoch and finite(inbound.startAtHours)
        and now>=inbound.startAtHours then
        inbound.departedAtEpoch=epoch
        inbound.arrivedAtEpoch=epoch+route.length/Network.AVERAGE_SPEED
        changed=true
    end
    if delivery.status=='received' and inbound and not delivery.returnRoute then
        local start=tonumber(delivery.receivedAtHours)
        if start then
            delivery.returnRoute={origin='warehouse',destinationCity=Network.CITY,
                destinationLocation=location,originCompany=company,startAtHours=start,
                arrivalAtHours=start+durationHours,departedAtEpoch=epoch,
                arrivedAtEpoch=epoch+route.length/Network.AVERAGE_SPEED,roadTownId=id}
            changed=true
        end
    end
    if inbound and inbound.roadTownId~=id then
        inbound.roadTownId=id
        if expected then inbound.startAtHours=expected-durationHours end
        changed=true
    end
    local outbound=delivery.returnRoute
    if outbound and outbound.roadTownId~=id then
        local start=tonumber(outbound.startAtHours) or now
        outbound.roadTownId=id;outbound.arrivalAtHours=start+durationHours
        outbound.departedAtEpoch=outbound.departedAtEpoch or epoch
        outbound.arrivedAtEpoch=outbound.arrivedAtEpoch or outbound.departedAtEpoch+route.length/Network.AVERAGE_SPEED
        changed=true
    end
    return changed
end

function Network.update(state,town,now,epoch)
    if type(state)~='table' then return false end
    local shipments=state.procurement and state.procurement.shipments or {}
    local jobs=state.jobs
    local activeJobs=jobs and jobs.active or {}
    local completedJobs=jobs and jobs.completed or {}
    if #shipments==0 and #activeJobs==0 and #completedJobs==0 then return false end
    local route=townWorld(town)
    if not route then return false end
    now=finite(now) and now or Calendar.absoluteHours(state)
    epoch=finite(epoch) and epoch or os.time()
    local durationHours=route.length/Network.AVERAGE_SPEED*24/math.max(1,Calendar.secondsPerDay(state))
    local changed=false
    for _,shipment in ipairs(shipments) do
        local delivery=shipment.delivery
        local expected=delivery and tonumber(delivery.expectedAtHours)
        if delivery and expected and delivery.status~='received' and not delivery.route then
            delivery.route={originCity=Network.CITY,originLocation=sourceLocation(state,shipment),
                originCompany=shipmentCompany(state,shipment),destination='warehouse',startAtHours=expected-durationHours,
                arrivalAtHours=expected,roadTownId=town.id}
            changed=true
        end
        local inbound=delivery and delivery.route
        if inbound and not inbound.departedAtEpoch and finite(inbound.startAtHours)
            and now>=inbound.startAtHours then
            inbound.departedAtEpoch=epoch
            inbound.arrivedAtEpoch=epoch+route.length/Network.AVERAGE_SPEED
            changed=true
        end
        if delivery and delivery.status=='received' and delivery.route and not delivery.returnRoute then
            local start=tonumber(delivery.receivedAtHours)
            if start then
                delivery.returnRoute={origin='warehouse',destinationCity=Network.CITY,
                    destinationLocation=sourceLocation(state,shipment),originCompany=shipmentCompany(state,shipment),startAtHours=start,
                    arrivalAtHours=start+durationHours,departedAtEpoch=epoch,
                    arrivedAtEpoch=epoch+route.length/Network.AVERAGE_SPEED,roadTownId=town.id}
                changed=true
            end
        end
        if delivery and delivery.route and delivery.route.roadTownId~=town.id then
            delivery.route.roadTownId=town.id
            if expected then delivery.route.startAtHours=expected-durationHours end
            changed=true
        end
        if delivery and delivery.returnRoute and delivery.returnRoute.roadTownId~=town.id then
            local start=tonumber(delivery.returnRoute.startAtHours) or now
            delivery.returnRoute.roadTownId=town.id
            delivery.returnRoute.arrivalAtHours=start+durationHours
            delivery.returnRoute.departedAtEpoch=delivery.returnRoute.departedAtEpoch or epoch
            delivery.returnRoute.arrivedAtEpoch=delivery.returnRoute.arrivedAtEpoch
                or delivery.returnRoute.departedAtEpoch+route.length/Network.AVERAGE_SPEED
            changed=true
        end
    end
    for _,collection in ipairs({activeJobs,completedJobs}) do
        for _,job in ipairs(collection) do
            local delivery=job.delivery
            local company=job.company or 'Millhaven Freight'
            changed=updateTrackedDelivery(delivery,company,Network.cityLocationFor(job.id),town.id,
                now,epoch,durationHours,route) or changed
        end
    end
    return changed
end

function Network.arrived(shipment,epoch)
    local route=shipment and shipment.delivery and shipment.delivery.route
    if not route then return true end
    epoch=finite(epoch) and epoch or os.time()
    return finite(route.arrivedAtEpoch) and epoch>=route.arrivedAtEpoch
end

function Network.tracking(shipment,now,epoch)
    local delivery=shipment and shipment.delivery or {}
    epoch=finite(epoch) and epoch or os.time()
    local outbound=delivery.returnRoute
    if outbound and finite(outbound.departedAtEpoch) and finite(outbound.arrivedAtEpoch)
        and epoch>=outbound.departedAtEpoch and epoch<outbound.arrivedAtEpoch then
        return 'Leaving town · heading to '..Network.CITY
    end
    if outbound and finite(outbound.arrivedAtEpoch) and epoch>=outbound.arrivedAtEpoch
        and delivery.status=='received' then return 'Delivered · truck returned to '..Network.CITY end
    local inbound=delivery.route
    if inbound and finite(inbound.startAtHours) and finite(inbound.arrivalAtHours) then
        if not inbound.departedAtEpoch then
            return 'At '..Network.CITY..' · '..tostring(inbound.originLocation or 'Freight Yard')
        end
        if epoch<inbound.arrivedAtEpoch then return 'In town · on the way to The Picture Shop' end
        if delivery.status~='received' then return 'At The Picture Shop · warehouse loading bay' end
    end
    if delivery.status=='received' then return 'Delivered · supplier shipment received' end
    if delivery.status=='at_bay' or delivery.status=='backing' or delivery.status=='unloading'
        or delivery.status=='scheduled' then return 'At The Picture Shop · warehouse loading bay' end
    return Network.CITY..' · preparing shipment'
end

function Network.actors(state,town,now,epoch)
    local route=townWorld(town)
    if not route then return {} end
    now=finite(now) and now or Calendar.absoluteHours(state)
    epoch=finite(epoch) and epoch or os.time()
    local result={}
    local function append(id,delivery,company)
        delivery=delivery or {}
        local inbound,outbound=delivery.route,delivery.returnRoute
        local sample,phase,speed
        if outbound and finite(outbound.departedAtEpoch) and finite(outbound.arrivedAtEpoch)
            and epoch>=outbound.departedAtEpoch and epoch<outbound.arrivedAtEpoch then
            local progress=(epoch-outbound.departedAtEpoch)/math.max(1e-8,outbound.arrivedAtEpoch-outbound.departedAtEpoch)
            sample=routeSample(route.outward,route.length,progress);phase='departing';speed=Network.AVERAGE_SPEED
        elseif delivery.status~='received' and inbound and finite(inbound.departedAtEpoch)
            and finite(inbound.arrivedAtEpoch) and epoch>=inbound.departedAtEpoch and epoch<inbound.arrivedAtEpoch then
            local progress=(epoch-inbound.departedAtEpoch)/math.max(1e-8,inbound.arrivedAtEpoch-inbound.departedAtEpoch)
            sample=routeSample(route.inward,route.length,progress);phase='approaching';speed=Network.AVERAGE_SPEED
        elseif not outbound and inbound and finite(inbound.arrivedAtEpoch) and epoch>=inbound.arrivedAtEpoch
            and delivery.status~='received' then
            local site=route.world.sites.byId.warehouse
            local localPoint=site and site.design.truckParking
            if localPoint then
                local x,z=site:toWorld(localPoint.x,localPoint.z,0)
                sample={x=x,z=z,h=route.world:supportHeight(x,z),heading=site.yaw}
                phase='at_bay';speed=0
            end
        end
        if sample then
            local actor={x=sample.x,z=sample.z,h=sample.h,heading=sample.heading,
                speed=speed,engine=speed>0,reverse=false,livery='plain',company=company,turnSignal=nil}
            local source={delivery=delivery}
            result[#result+1]={id=id,shipmentId=id,actor=actor,
                truck=true,deliveryTruck=true,phase=phase,label=Network.tracking(source,now,epoch)}
        end
    end
    for _,shipment in ipairs(state and state.procurement and state.procurement.shipments or {}) do
        append(shipment.id,shipment.delivery,shipmentCompany(state,shipment))
    end
    local jobs=state and state.jobs
    for _,collection in ipairs({jobs and jobs.active or {},jobs and jobs.completed or {}}) do
        for _,job in ipairs(collection) do
            if job.delivery and job.delivery.route then
                append(job.id,job.delivery,job.company or 'Millhaven Freight')
            end
        end
    end
    return result
end

function Network.cityLocationFor(id)
    return citySites[(hash(id)+1)%#citySites+1]
end

return Network
