-- Saved motorcycle trips for clients and suppliers visiting the shop.
local Bike = require("src.commute.motorcycle")
local Bays = require("src.commute.parking_bays")
local Routes = require("src.commute.commuter_routes")
local NpcJourney = require("src.commute.npc_journey")

local Visitors = { TRAVEL_HOURS = 1 }

local visitorSlots = { customer = 1, vendor = 2 }
local visitorLabels = { customer = "Client", vendor = "Supplier" }

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function routeWorld(town, activeWorld)
    if activeWorld and activeWorld.sites and activeWorld.sites.byId then return activeWorld end
    return Routes.world(town, activeWorld)
end

local function appendTrip(result, id, label, character, journey, slot, town, hours, activeWorld)
    local world = routeWorld(town, activeWorld)
    local route = Routes.route(town, journey.fromId, journey.toId, activeWorld)
    local fromSlot = journey.fromId == "warehouse" and slot or nil
    local toSlot = journey.toId == "warehouse" and slot or nil
    local trip = NpcJourney.sample(journey, hours, world, route, fromSlot, toSlot)
    if not trip or not trip.bike then return end

    local pose = trip.bike
    local bike = Bike.new(pose.x, pose.z, pose.heading)
    bike.h=pose.h or world:supportHeight(pose.x,pose.z)
    bike.speed = pose.speed or 0
    bike.distance = (route.length or 0) * (pose.progress or 0)
    bike.trafficKind, bike.aiKind, bike.trafficId = "motorcycle", "motorcycle", id
    result[#result + 1] = {
        id = id, actor = bike, bike = true, bikeOnly = pose.parked == true,
        journey=journey,route=route,fromSlot=fromSlot,toSlot=toSlot,
        deliveryBike = true, visitorCommuter = true, phase = "commuting",
        npcStage = trip.stage, parked = pose.parked == true,
        label = label, characterId = character,
        destinationId = journey.toId,
    }
    if trip.walker then
        result[#result + 1] = {
            id = id .. "-walker", actor = trip.walker, npcCharacter = true,
            visitorCommuter = true, characterId = character, phase = trip.stage,
            label = label,
        }
    end
end

function Visitors.travelSeconds(state)
    return require("src.business_calendar").secondsPerDay(state) / 24 * Visitors.TRAVEL_HOURS
end

function Visitors.depart(state, kind, character, hours)
    if not state or not state.home or not visitorSlots[kind] or not finite(hours) then return false end
    local saved=state.home.visitorJourneys or {incoming={},returning={}}
    state.home.visitorJourneys=saved
    if NpcJourney.pending(saved.returning[kind]) then return false end
    saved.incoming[kind]=nil
    saved.returning[kind] = {
        character = character,
        departAtHours = hours, arriveAtHours = hours + Visitors.TRAVEL_HOURS,
        fromId = "warehouse", toId = "mainland_exit",
    }
    state.home.revision=(state.home.revision or 0)+1
    return true
end

function Visitors.valid(saved)
    if saved==nil then return true end
    if type(saved)~='table' then return false end
    for _,direction in ipairs({'incoming','returning'}) do
        if type(saved[direction])~='table' then return false end
        for kind,j in pairs(saved[direction]) do
            if not visitorSlots[kind] or type(j)~='table' or not finite(j.departAtHours)
                or not finite(j.arriveAtHours) or math.abs(j.arriveAtHours-j.departAtHours-Visitors.TRAVEL_HOURS)>1e-8
                or type(j.character)~='string' or #j.character>80
                or j.fromId~=(direction=='incoming' and 'mainland_exit' or 'warehouse')
                or j.toId~=(direction=='incoming' and 'warehouse' or 'mainland_exit')
                or not require('src.commute.scheduled_motion').valid(j.motion,Visitors.TRAVEL_HOURS) then return false end
        end
    end
    return true
end

-- Called only by host simulation. Rendering and guest snapshots do not create,
-- remove, or advance journeys. At most two incoming and two returning trips.
function Visitors.prepare(state,visitors,hours)
    if not state or not state.home or not visitors then return false end
    local changed=state.home.visitorJourneys==nil
    local saved=state.home.visitorJourneys or {incoming={},returning={}}
    state.home.visitorJourneys=saved
    local secondsPerHour=require('src.business_calendar').secondsPerDay(state)/24
    for _,kind in ipairs({'customer','vendor'}) do
        local returning=saved.returning[kind]
        if returning and hours>=returning.arriveAtHours and not NpcJourney.pending(returning) then
            saved.returning[kind]=nil;changed=true
        end
        local visitor=visitors[kind]
        if visitor and visitor.state=='scheduled' then
            if not saved.incoming[kind] and not saved.returning[kind]
                and (visitor.timer or 0)<=secondsPerHour*Visitors.TRAVEL_HOURS then
                local arrival=hours+math.max(0,visitor.timer or 0)/secondsPerHour
                saved.incoming[kind]={fromId='mainland_exit',toId='warehouse',character=visitor.character,
                    departAtHours=arrival-Visitors.TRAVEL_HOURS,arriveAtHours=arrival}
                changed=true
            end
        elseif visitor and saved.incoming[kind] then saved.incoming[kind]=nil;changed=true end
    end
    if changed then state.home.revision=(state.home.revision or 0)+1 end
    return changed
end
function Visitors.holdArrival(state,kind,visitor,dt)
    if not visitor or visitor.state~='scheduled' then return false end
    local saved=state and state.home and state.home.visitorJourneys
    if not saved then return false end
    if saved.returning[kind] and (visitor.timer or 0)<=Visitors.travelSeconds(state) then return true end
    local journey=saved.incoming[kind]
    -- A legacy visitor already at the door can enter before an outdoor actor
    -- has ever been initialized. Once physical progress exists, it owns arrival.
    return NpcJourney.pending(journey) and (visitor.timer or 0)<=dt or false
end

function Visitors.actors(visitorState, state, town, hours, activeWorld)
    local result = {}
    if type(visitorState) ~= "table" or not finite(hours) then return result end
    local secondsPerHour = require("src.business_calendar").secondsPerDay(state) / 24
    for _, kind in ipairs({ "customer", "vendor" }) do
        local visitor = visitorState[kind]
        if visitor and visitor.visible then
            local slot = visitorSlots[kind]
            local world = routeWorld(town, activeWorld)
            local site = world and world.sites and world.sites.byId.warehouse
            if site then
                local x, z = Bays.center(site, slot)
                local bike = Bike.new(x, z, Bays.heading(site))
                bike.trafficKind, bike.aiKind = "motorcycle", "motorcycle"
                bike.trafficId = "visitor-" .. kind
                result[#result + 1] = {
                    id = "visitor-" .. kind, actor = bike, bike = true, bikeOnly = true,
                    deliveryBike = true, visitorCommuter = true, phase = "parked",
                    parked = true,
                    label = visitorLabels[kind] .. " · parked at the Picture Shop",
                    characterId = visitor.character, destinationId = "warehouse",
                }
            end
        elseif visitor and visitor.state == "scheduled" and secondsPerHour > 0 then
            -- The visitor's timer includes the one-hour motorcycle trip. The
            -- earlier part remains a quiet gap before they leave Milhaven City.
            local saved=state and state.home and state.home.visitorJourneys
            local journey=saved and saved.incoming[kind]
            local arrivalAt = journey and journey.arriveAtHours or hours + math.max(0, visitor.timer or 0) / secondsPerHour
            local departAt = arrivalAt - Visitors.TRAVEL_HOURS
            if journey and (NpcJourney.pending(journey) or hours >= departAt and hours <= arrivalAt) then
                appendTrip(result, "visitor-" .. kind,
                    visitorLabels[kind] .. " · Milhaven City → Picture Shop",
                    visitor.character, journey, visitorSlots[kind], town, hours, activeWorld)
            end
        end
    end

    local returning = state and state.home and state.home.visitorJourneys and state.home.visitorJourneys.returning
    if returning then
        for _,kind in ipairs({'customer','vendor'}) do
            local journey = returning[kind]
            if journey and hours >= journey.departAtHours then
                appendTrip(result, 'visitor-'..kind..'-return', visitorLabels[kind]..' · Picture Shop → Milhaven City',
                    journey.character, journey, visitorSlots[kind], town, hours, activeWorld)
            end
        end
    end
    return result
end

return Visitors
