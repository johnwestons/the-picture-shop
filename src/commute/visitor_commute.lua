-- Clock-derived motorcycle trips for clients and suppliers visiting the shop.
local Bike = require("src.commute.motorcycle")
local Bays = require("src.commute.parking_bays")
local Routes = require("src.commute.commuter_routes")
local NpcJourney = require("src.commute.npc_journey")

local Visitors = { TRAVEL_HOURS = 1 }
local departures = setmetatable({}, { __mode = "k" })
local departureSerial = 0

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
    bike.speed = pose.speed or 0
    bike.distance = (route.length or 0) * (pose.progress or 0)
    bike.trafficKind, bike.aiKind, bike.trafficId = "motorcycle", "motorcycle", id
    result[#result + 1] = {
        id = id, actor = bike, bike = true, bikeOnly = pose.parked == true,
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
    if type(state) ~= "table" or not visitorSlots[kind] or not finite(hours) then return false end
    departureSerial = departureSerial + 1
    local list = departures[state]
    if not list then list = {}; departures[state] = list end
    local id = "visitor-" .. kind .. "-return-" .. departureSerial
    list[#list + 1] = {
        id = id, label = visitorLabels[kind] .. " · Picture Shop → Milhaven City",
        character = character, slot = visitorSlots[kind],
        departAtHours = hours, arriveAtHours = hours + Visitors.TRAVEL_HOURS,
        fromId = "warehouse", toId = "mainland_exit",
    }
    return true
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
            local arrivalAt = hours + math.max(0, visitor.timer or 0) / secondsPerHour
            local departAt = arrivalAt - Visitors.TRAVEL_HOURS
            if hours >= departAt and hours <= arrivalAt then
                appendTrip(result, "visitor-" .. kind,
                    visitorLabels[kind] .. " · Milhaven City → Picture Shop",
                    visitor.character, {
                        fromId = "mainland_exit", toId = "warehouse",
                        departAtHours = departAt, arriveAtHours = arrivalAt,
                    }, visitorSlots[kind], town, hours, activeWorld)
            end
        end
    end

    local returning = departures[state]
    if returning then
        for index = #returning, 1, -1 do
            local journey = returning[index]
            if hours >= journey.arriveAtHours then
                table.remove(returning, index)
            elseif hours >= journey.departAtHours then
                appendTrip(result, journey.id, journey.label, journey.character, journey,
                    journey.slot, town, hours, activeWorld)
            end
        end
    end
    return result
end

return Visitors
