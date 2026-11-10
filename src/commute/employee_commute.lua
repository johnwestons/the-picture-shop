-- Saved employee commute context and deterministic motorcycle journeys.
local Bike=require('src.commute.motorcycle')
local Bays=require('src.commute.parking_bays')
local Contracts=require('src.employment_contracts')
local Routes=require('src.commute.commuter_routes')
local NpcJourney=require('src.commute.npc_journey')
local Commuters={TRAVEL_HOURS=1}

local function finite(value)return type(value)=='number' and value==value and math.abs(value)<math.huge end
local function equal(a,b)
    if a==b then return true end
    if type(a)~='table' or type(b)~='table' then return false end
    for key,value in pairs(a) do if b[key]~=value then return false end end
    for key,value in pairs(b) do if a[key]~=value then return false end end
    return true
end
local function residenceId(profile)
    return profile.residenceKind=='city' and 'mainland_exit' or profile.residenceId
end
local function stateFor(worker,hours)
    local profile=worker.commuteProfile
    local contract=worker.contract
    if worker.status~='employed' or not contract then return {phase='home'} end
    local today=math.floor(math.max(0,hours)/24)
    for day=math.max(0,today-1),today+1 do
        local first,last=Contracts.shiftBounds(contract,day)
        if first and day>=contract.startDay then
            if worker.sentHomeShiftDay~=day and hours>=first-Commuters.TRAVEL_HOURS and hours<first then
                return {phase='commuting_to_work',day=day,
                    fromId=residenceId(profile),toId=profile.workSiteId,
                    departAtHours=first-Commuters.TRAVEL_HOURS,arriveAtHours=first}
            elseif worker.sentHomeShiftDay~=day and hours>=first and hours<last then
                return {phase='at_work',day=day}
            elseif hours>=last and hours<last+Commuters.TRAVEL_HOURS then
                return {phase='commuting_home',day=day,
                    fromId=profile.workSiteId,toId=residenceId(profile),
                    departAtHours=last,arriveAtHours=last+Commuters.TRAVEL_HOURS}
            end
        end
    end
    return {phase='home'}
end
function Commuters.validState(value,profile)
    if type(value)~='table' then return false end
    local phase=value.phase
    if phase=='home' then
        for key in pairs(value) do if key~='phase' then return false end end
        return true
    end
    if phase=='at_work' then
        if type(value.day)~='number' or value.day%1~=0 or value.day<0 then return false end
        for key in pairs(value) do if key~='phase' and key~='day' then return false end end
        return true
    end
    if phase~='commuting_to_work' and phase~='commuting_home' then return false end
    local toWork=phase=='commuting_to_work'
    local expectedFrom=toWork and residenceId(profile) or profile.workSiteId
    local expectedTo=toWork and profile.workSiteId or residenceId(profile)
    local day=value.day
    return type(day)=='number' and day%1==0 and day>=0
        and value.fromId==expectedFrom and value.toId==expectedTo
        and finite(value.departAtHours) and finite(value.arriveAtHours)
        and value.arriveAtHours-value.departAtHours==Commuters.TRAVEL_HOURS
        and value.departAtHours>=day*24 and value.departAtHours<=(day+2)*24
end
function Commuters.journey(profile,phase,departAtHours)
    if type(profile)~='table' or not finite(departAtHours) then return nil end
    local toWork=phase=='commuting_to_work'
    if not toWork and phase~='commuting_home' then return nil end
    local residence=residenceId(profile)
    return {phase=phase,day=math.floor(math.max(0,departAtHours)/24),
        fromId=toWork and residence or profile.workSiteId,
        toId=toWork and profile.workSiteId or residence,
        departAtHours=departAtHours,arriveAtHours=departAtHours+Commuters.TRAVEL_HOURS}
end
function Commuters.advance(state,hours)
    if not state or not state.employment or not finite(hours) then return false end
    local changed=false
    for _,worker in ipairs(state.employment.staff or {}) do
        if worker.commuteProfile then
            local nextState=stateFor(worker,hours)
            if not equal(worker.commuteState,nextState) then
                worker.commuteState=nextState
                changed=true
            end
        end
    end
    return changed
end
function Commuters.actors(state,town,hours,activeWorld)
    local result={}
    if not state or not state.employment or not finite(hours) then return result end
    local parkingSlots={};local employeeParkingIndex=0
    for _,worker in ipairs(state.employment.staff or {}) do
        if worker.status=='employed' and worker.commuteProfile then
            employeeParkingIndex=employeeParkingIndex+1
            parkingSlots[worker]=9-employeeParkingIndex
        end
    end
    for _,worker in ipairs(state.employment.staff or {}) do
        local profile=worker.commuteProfile
        local journey=worker.commuteState
        if worker.status=='employed' and profile and journey then
            if journey.phase=='commuting_to_work' or journey.phase=='commuting_home' then
                local world=activeWorld and activeWorld.sites and activeWorld.sites.byId
                    and activeWorld or Routes.world(town,activeWorld)
                local route=Routes.route(town,journey.fromId,journey.toId,activeWorld)
                local homeSlot=profile.residenceKind=='town' and 1 or nil
                local workSlot=parkingSlots[worker]
                local fromSlot=journey.fromId==profile.workSiteId and workSlot or homeSlot
                local toSlot=journey.toId==profile.workSiteId and workSlot or homeSlot
                local trip=NpcJourney.sample(journey,hours,world,route,fromSlot,toSlot)
                if trip and trip.bike then
                    local pose=trip.bike
                    local bike=Bike.new(pose.x,pose.z,pose.heading)
                    bike.paintId=profile.paintId;bike.speed=pose.speed or 0
                    bike.distance=(route.length or 0)*(pose.progress or 0)
                    bike.trafficKind='motorcycle';bike.aiKind='motorcycle'
                    bike.trafficId='employee-'..worker.id
                    result[#result+1]={id='employee-'..worker.id,actor=bike,bike=true,
                        bikeOnly=pose.parked==true,deliveryBike=true,
                        employeeCommuter=true,phase='commuting',npcStage=trip.stage,
                        parked=pose.parked==true,
                        label=worker.name..' · '..journey.fromId..' → '..journey.toId,
                        characterId=worker.character,rosterId=profile.rosterId,destinationId=journey.toId}
                    if trip.walker then
                        result[#result+1]={id='employee-'..worker.id..'-walker',actor=trip.walker,
                            npcCharacter=true,characterId=worker.character,employeeCommuter=true,
                            phase=trip.stage,rosterId=profile.rosterId,label=worker.name}
                    end
                end
            else
                local siteId,slot
                if journey.phase=='at_work' then
                    siteId=profile.workSiteId;slot=parkingSlots[worker]
                elseif journey.phase=='home' and profile.residenceKind=='town' then
                    siteId=profile.residenceId;slot=1
                end
                if siteId then
                    local sites=activeWorld and activeWorld.sites and activeWorld.sites.byId
                    local world=sites and activeWorld or Routes.world(town,activeWorld)
                    local routeSites=world and world.sites and world.sites.byId
                    local site=routeSites and routeSites[siteId]
                    if site then
                        local x,z=Bays.center(site,slot)
                        local bike=Bike.new(x,z,Bays.heading(site))
                        bike.paintId=profile.paintId;bike.speed=0
                        bike.trafficKind='motorcycle';bike.aiKind='motorcycle'
                        bike.trafficId='employee-'..worker.id
                        result[#result+1]={id='employee-'..worker.id,actor=bike,bike=true,bikeOnly=true,
                            deliveryBike=true,employeeCommuter=true,phase='parked',parked=true,
                            label=worker.name..' · parked',characterId=worker.character,
                            rosterId=profile.rosterId}
                    end
                end
            end
        end
    end
    local applicantParkingSlots={};local applicantIndex=0
    for _,application in ipairs(state.employment.applications or {}) do
        local commute=application.commuteState
        if application.status~='hired' and application.commuteProfile and commute
            and commute.phase~='home' then
            applicantIndex=applicantIndex+1
            applicantParkingSlots[application]=8-employeeParkingIndex-applicantIndex
        end
    end
    for _,application in ipairs(state.employment.applications or {}) do
        local profile=application.commuteProfile
        local journey=application.commuteState
        if application.status~='hired' and profile and journey then
            local homeSlot=profile.residenceKind=='town' and 1 or nil
            if journey.phase=='commuting_to_work' or journey.phase=='commuting_home' then
                if hours>=journey.arriveAtHours then
                    local siteId,slot
                    if journey.phase=='commuting_to_work' then
                        siteId=profile.workSiteId;slot=applicantParkingSlots[application]
                    elseif profile.residenceKind=='town' then
                        siteId=profile.residenceId;slot=homeSlot
                    end
                    local routeWorld=activeWorld and activeWorld.sites and activeWorld.sites.byId
                        and activeWorld or Routes.world(town,activeWorld)
                    local site=routeWorld and routeWorld.sites.byId[siteId]
                    if site then
                        local x,z=Bays.center(site,slot)
                        local bike=Bike.new(x,z,Bays.heading(site))
                        bike.paintId=profile.paintId;bike.speed=0
                        bike.trafficKind='motorcycle';bike.aiKind='motorcycle'
                        bike.trafficId='applicant-'..application.id
                        result[#result+1]={id='applicant-'..application.id,actor=bike,bike=true,
                            bikeOnly=true,deliveryBike=true,applicantCommuter=true,phase='parked',
                            parked=true,characterId=application.character,rosterId=profile.rosterId,
                            label=application.name..' · parked'}
                    end
                else
                    local routeWorld=activeWorld and activeWorld.sites and activeWorld.sites.byId
                        and activeWorld or Routes.world(town,activeWorld)
                    local route=Routes.route(town,journey.fromId,journey.toId,activeWorld)
                    local fromSlot=journey.fromId==profile.workSiteId
                        and applicantParkingSlots[application] or homeSlot
                    local toSlot=journey.toId==profile.workSiteId
                        and applicantParkingSlots[application] or homeSlot
                    local trip=NpcJourney.sample(journey,hours,routeWorld,route,fromSlot,toSlot)
                    if trip and trip.bike then
                        local pose=trip.bike
                        local bike=Bike.new(pose.x,pose.z,pose.heading)
                        bike.paintId=profile.paintId;bike.speed=pose.speed or 0
                        bike.distance=(route.length or 0)*(pose.progress or 0)
                        bike.trafficKind='motorcycle';bike.aiKind='motorcycle'
                        bike.trafficId='applicant-'..application.id
                        result[#result+1]={id='applicant-'..application.id,actor=bike,bike=true,
                            bikeOnly=pose.parked==true,deliveryBike=true,applicantCommuter=true,
                            phase='commuting',npcStage=trip.stage,parked=pose.parked==true,
                            characterId=application.character,rosterId=profile.rosterId,
                            label=application.name..' · '..journey.fromId..' → '..journey.toId}
                        if trip.walker then
                            result[#result+1]={id='applicant-'..application.id..'-walker',actor=trip.walker,
                                npcCharacter=true,applicantCommuter=true,characterId=application.character,
                                phase=trip.stage,rosterId=profile.rosterId,label=application.name}
                        end
                    end
                end
            elseif journey.phase=='at_work' then
                local routeWorld=activeWorld and activeWorld.sites and activeWorld.sites.byId
                    and activeWorld or Routes.world(town,activeWorld)
                local site=routeWorld and routeWorld.sites.byId[profile.workSiteId]
                if site then
                    local x,z=Bays.center(site,applicantParkingSlots[application])
                    local bike=Bike.new(x,z,Bays.heading(site))
                    bike.paintId=profile.paintId;bike.speed=0
                    bike.trafficKind='motorcycle';bike.aiKind='motorcycle'
                    bike.trafficId='applicant-'..application.id
                    result[#result+1]={id='applicant-'..application.id,actor=bike,bike=true,
                        bikeOnly=true,deliveryBike=true,applicantCommuter=true,phase='parked',
                        parked=true,characterId=application.character,rosterId=profile.rosterId,
                        label=application.name..' · parked'}
                end
            elseif journey.phase=='home' and homeSlot then
                local routeWorld=activeWorld and activeWorld.sites and activeWorld.sites.byId
                    and activeWorld or Routes.world(town,activeWorld)
                local site=routeWorld and routeWorld.sites.byId[profile.residenceId]
                if site then
                    local x,z=Bays.center(site,homeSlot)
                    local bike=Bike.new(x,z,Bays.heading(site))
                    bike.paintId=profile.paintId;bike.speed=0
                    bike.trafficKind='motorcycle';bike.aiKind='motorcycle'
                    bike.trafficId='applicant-'..application.id
                    result[#result+1]={id='applicant-'..application.id,actor=bike,bike=true,
                        bikeOnly=true,deliveryBike=true,applicantCommuter=true,phase='parked',
                        parked=true,characterId=application.character,rosterId=profile.rosterId,
                        label=application.name..' · parked'}
                end
            end
        end
    end
    return result
end
return Commuters
