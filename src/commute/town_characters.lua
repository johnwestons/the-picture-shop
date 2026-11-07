-- Persistent town attendants and their daily home/work journeys.
local Bike=require('src.commute.motorcycle')
local Paint=require('src.commute.bike_paint')
local Bays=require('src.commute.parking_bays')
local Routes=require('src.commute.commuter_routes')
local Characters={VERSION=1,OPEN_HOUR=8,CLOSE_HOUR=18,DEPARTURE_HOUR=7,HOME_HOUR=19}

local profiles={
    {id='mechanic',name='Raccoon Mechanic',character='mechanic-raccoon',jobId='mechanic',
        homeSiteId='brick-walkup',workSiteId='mechanic',paintId='red'},
    {id='grocery-owner',name='Grocery Owner',character='business-cat',jobId='grocery',
        homeSiteId='garden',workSiteId='grocery',paintId='teal'},
    {id='gas-attendant',name='Gas Station Attendant',character='business-fox',jobId='gas-station',
        homeSiteId='corner',workSiteId='gas-station',paintId='green'},
}
local phases={home=true,commuting_to_work=true,working=true,commuting_home=true}
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for key,item in pairs(value) do result[key]=copy(item) end;return result
end
local function finite(value)return type(value)=='number' and value==value and math.abs(value)<math.huge end
local function journeyValid(journey,profile,phase)
    if phase~='commuting_to_work' and phase~='commuting_home' then return journey==nil end
    local toWork=phase=='commuting_to_work'
    local from=toWork and profile.homeSiteId or profile.workSiteId
    local to=toWork and profile.workSiteId or profile.homeSiteId
    local departOffset=toWork and Characters.DEPARTURE_HOUR or Characters.CLOSE_HOUR
    local arriveOffset=toWork and Characters.OPEN_HOUR or Characters.HOME_HOUR
    return type(journey)=='table' and type(journey.day)=='number' and journey.day%1==0 and journey.day>=0
        and journey.fromId==from and journey.toId==to
        and finite(journey.departAtHours) and journey.departAtHours==journey.day*24+departOffset
        and finite(journey.arriveAtHours) and journey.arriveAtHours==journey.day*24+arriveOffset
end
local function expectedPerson(profile)
    return {id=profile.id,name=profile.name,character=profile.character,jobId=profile.jobId,
        homeSiteId=profile.homeSiteId,workSiteId=profile.workSiteId,
        vehicleKind='motorcycle',paintId=profile.paintId,
        schedule={openHour=Characters.OPEN_HOUR,closeHour=Characters.CLOSE_HOUR,
            leaveHomeHour=Characters.DEPARTURE_HOUR,arriveHomeHour=Characters.HOME_HOUR},
        phase='home'}
end
function Characters.defaultState(town)
    local people={}
    for index,profile in ipairs(profiles) do people[index]=expectedPerson(profile) end
    return {version=Characters.VERSION,townId=town and town.id or 'original-valley-v3',people=people}
end
function Characters.valid(value,town)
    if type(value)~='table' or value.version~=Characters.VERSION
        or type(value.townId)~='string' or #value.townId>80
        or town and value.townId~=town.id or type(value.people)~='table' or #value.people~=#profiles then return false end
    local count=0
    for key,person in pairs(value.people) do
        count=count+1
        local profile=profiles[key]
        if type(key)~='number' or key%1~=0 or not profile or type(person)~='table'
            or person.id~=profile.id or person.name~=profile.name or person.character~=profile.character
            or person.jobId~=profile.jobId or person.homeSiteId~=profile.homeSiteId
            or person.workSiteId~=profile.workSiteId or person.vehicleKind~='motorcycle'
            or person.paintId~=profile.paintId or not Paint.valid(person.paintId)
            or type(person.schedule)~='table' or person.schedule.openHour~=Characters.OPEN_HOUR
            or person.schedule.closeHour~=Characters.CLOSE_HOUR
            or person.schedule.leaveHomeHour~=Characters.DEPARTURE_HOUR
            or person.schedule.arriveHomeHour~=Characters.HOME_HOUR
            or not phases[person.phase] or not journeyValid(person.journey,profile,person.phase) then return false end
    end
    return count==#profiles
end
function Characters.normalize(value,town)
    if value==nil then return Characters.defaultState(town) end
    if not Characters.valid(value,town) then return nil end
    return copy(value)
end
local function scheduledPhase(profile,hours)
    local day=math.floor(math.max(0,hours)/24)
    local hour=hours-day*24
    if hour>=Characters.DEPARTURE_HOUR and hour<Characters.OPEN_HOUR then
        return 'commuting_to_work',day,{day=day,fromId=profile.homeSiteId,toId=profile.workSiteId,
            departAtHours=day*24+Characters.DEPARTURE_HOUR,arriveAtHours=day*24+Characters.OPEN_HOUR}
    elseif hour>=Characters.OPEN_HOUR and hour<Characters.CLOSE_HOUR then
        return 'working',day,nil
    elseif hour>=Characters.CLOSE_HOUR and hour<Characters.HOME_HOUR then
        return 'commuting_home',day,{day=day,fromId=profile.workSiteId,toId=profile.homeSiteId,
            departAtHours=day*24+Characters.CLOSE_HOUR,arriveAtHours=day*24+Characters.HOME_HOUR}
    end
    return 'home',day,nil
end
function Characters.advance(state,hours)
    local home=state and state.home
    local saved=home and home.townCharacters
    if type(saved)~='table' or not finite(hours) then return false end
    local changed=false
    for index,profile in ipairs(profiles) do
        local person=saved.people[index]
        local phase,_,journey=scheduledPhase(profile,hours)
        local journeyChanged=not journeyValid(person.journey,profile,phase)
        if journey and person.journey and person.journey.day~=journey.day then journeyChanged=true end
        if person.phase~=phase or journeyChanged then
            -- The journey record holds the home/work route and scheduled time
            -- window. Position is derived from that record as game time moves.
            person.phase=phase;person.journey=journey;changed=true
        end
    end
    if changed then home.revision=(home.revision or 0)+1 end
    return changed
end
function Characters.isOpen(home,workSiteId,hours)
    if not finite(hours) then return false end
    local hour=hours%24
    if hour<Characters.OPEN_HOUR or hour>=Characters.CLOSE_HOUR then return false end
    for _,profile in ipairs(profiles) do
        if profile.workSiteId==workSiteId then return true end
    end
    return false
end
function Characters.profiles() return copy(profiles) end
local function parkedActor(person,site,slot)
    if not site then return nil end
    local x,z=Bays.center(site,slot)
    local bike=Bike.new(x,z,site.yaw or 0)
    bike.paintId=person.paintId;bike.speed=0;bike.trafficKind='motorcycle'
    bike.aiKind='motorcycle';bike.trafficId='town-npc-'..person.id
    return {id='town-npc-'..person.id,actor=bike,bike=true,bikeOnly=true,deliveryBike=true,
        townNpc=true,phase='parked',parked=true,label=person.name..' · parked',
        characterId=person.character,rosterId=person.id}
end
function Characters.actors(home,town,hours,activeWorld)
    local result={}
    if type(home)~='table' or type(home.townCharacters)~='table'
        or type(home.townCharacters.people)~='table' or not finite(hours) then return result end
    local saved=home.townCharacters
    for index,profile in ipairs(profiles) do
        local person=saved.people[index]
        if person and (person.phase=='commuting_to_work' or person.phase=='commuting_home') and person.journey then
            local journey=person.journey
            local duration=journey.arriveAtHours-journey.departAtHours
            local progress=math.max(0,math.min(1,(hours-journey.departAtHours)/duration))
            local path=Routes.route(town,journey.fromId,journey.toId,activeWorld)
            local pose=Routes.sample(path,progress)
            if pose then
                local bike=Bike.new(pose.x,pose.z,pose.heading)
                bike.paintId=person.paintId;bike.speed=progress<1 and 7.2 or 0
                bike.distance=(path.length or 0)*progress;bike.trafficKind='motorcycle'
                bike.aiKind='motorcycle';bike.trafficId='town-npc-'..person.id
                result[#result+1]={id='town-npc-'..person.id,actor=bike,bike=true,deliveryBike=true,
                    townNpc=true,phase='commuting',label=person.name..' · '..journey.fromId..' → '..journey.toId,
                    characterId=person.character,rosterId=person.id,destinationId=journey.toId}
            end
        elseif person then
            local siteId=person.phase=='working' and person.workSiteId or person.homeSiteId
            local sites=activeWorld and activeWorld.sites and activeWorld.sites.byId
            local world=sites and activeWorld or Routes.world(town,activeWorld)
            local routeSites=world and world.sites and world.sites.byId
            local site=routeSites and routeSites[siteId]
            local actor=parkedActor(person,site,index)
            if actor then result[#result+1]=actor end
        end
    end
    return result
end
return Characters
