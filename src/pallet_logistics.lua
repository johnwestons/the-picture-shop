local Logistics = {}
local Procurement = require("src.procurement")
local PalletState = require("src.pallet_state")
local Receiving = require("src.receiving")
local Config = require("src.config")
local directionFrames = { northwest = 1, northeast = 2, southwest = 3, southeast = 4 }

local function activeJob(state, jobId)
    local active = state and state.jobs and state.jobs.active or {}
    for _, job in ipairs(active) do
        if job.id == jobId then return job end
    end
end

local function copyPosition(point)
    local direction = directionFrames[point.direction] and point.direction or "northwest"
    local rotation = directionFrames[direction]
    if type(point.rotation) == "number" and point.rotation >= 1 and point.rotation <= 4 then
        rotation = math.floor(point.rotation)
    end
    return { x = point.x, y = point.y, direction = direction, rotation = rotation }
end

local function commaNumber(value)
    local text = tostring(math.floor(value or 0))
    while true do
        local replaced, count = text:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
        text = replaced
        if count == 0 then return text end
    end
end

function Logistics.truckInventory(state, jobId)
    local purchase = Procurement.orderById(state, jobId)
    if purchase then return Procurement.truckInventory(state, jobId) end
    local job = activeJob(state, jobId)
    local inventory = {}
    for _, pallet in ipairs(job and job.pallets or {}) do
        inventory[#inventory + 1] = {
            id = pallet.id,
            number = pallet.number,
            sheets = pallet.initialSheets,
            location = pallet.location,
            status = pallet.status,
            paper = pallet.paper,
            pallet = pallet,
        }
    end
    return job, inventory
end

function Logistics.remainingOnTruck(state, jobId)
    if Procurement.orderById(state, jobId) then return Procurement.remainingOnTruck(state, jobId) end
    local _, inventory = Logistics.truckInventory(state, jobId)
    local count = 0
    for _, item in ipairs(inventory) do
        if item.location == "awaiting_delivery" then count = count + 1 end
    end
    return count
end

function Logistics.unload(state, jobId, palletId, spawnPoints, origin)
    if Procurement.orderById(state, jobId) then
        return Procurement.unload(state, jobId, palletId, spawnPoints, origin)
    end
    local job = activeJob(state, jobId)
    if not job then return false, "The delivery job is no longer active." end
    for index, pallet in ipairs(job.pallets or {}) do
        if pallet.id == palletId then
            if pallet.location ~= "awaiting_delivery" then
                return false, "That pallet has already been unloaded."
            end
            local point, laneError = Receiving.claim(
                state, spawnPoints, Config.palletLogistics.receivingLaneRadius, pallet.id)
            if not point then return false, laneError end
            local world = copyPosition(point)
            world.fromX = origin and origin.x or point.x
            world.fromY = origin and origin.y or point.y
            world.spawnProgress = 0
            local transitioned, transitionError = PalletState.transition(state, pallet, "warehouse", {
                status = "raw",
                world = world,
            })
            if not transitioned then return false, transitionError end
            state.inventory.rawPallets = (state.inventory.rawPallets or 0) + 1
            local remaining = Logistics.remainingOnTruck(state, jobId)
            if remaining == 0 then
                job.status = "in_production"
                job.delivery = job.delivery or {}
                job.delivery.status = "received"
                job.delivery.receivedAt = os.time()
            else
                job.delivery = job.delivery or {}
                job.delivery.status = "unloading"
            end
            return true, pallet, remaining
        end
    end
    return false, "The pallet was not found in this truck."
end

function Logistics.receivingStatus(state, spawnPoints)
    return Receiving.snapshot(state, spawnPoints, Config.palletLogistics.receivingLaneRadius)
end

function Logistics.update(state, dt, duration)
    duration = math.max(0.01, duration or 0.65)
    for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.world and (pallet.world.spawnProgress or 1) < 1 then
                pallet.world.spawnProgress = math.min(1,
                    (pallet.world.spawnProgress or 0) + math.max(0, dt) / duration)
            end
        end
    end
    for _, item in ipairs(Procurement.physicalPallets(state)) do
        local world = item.pallet.world
        if world and (world.spawnProgress or 1) < 1 then
            world.spawnProgress = math.min(1, (world.spawnProgress or 0) + math.max(0, dt) / duration)
        end
    end
end

function Logistics.physicalPallets(state)
    local result = {}
    local active = state and state.jobs and state.jobs.active or {}
    for _, job in ipairs(active) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.world and (pallet.location == "warehouse" or pallet.location == "cutter_output") then
                local progress = pallet.world.spawnProgress or 1
                local fromX = pallet.world.fromX or pallet.world.x
                local fromY = pallet.world.fromY or pallet.world.y
                result[#result + 1] = {
                    job = job,
                    pallet = pallet,
                    x = fromX + (pallet.world.x - fromX) * progress,
                    y = fromY + (pallet.world.y - fromY) * progress,
                }
            end
        end
    end
    for _, item in ipairs(Procurement.physicalPallets(state)) do result[#result + 1] = item end
    return result
end

function Logistics.obstacles(state, halfWidth, halfHeight, excludedPalletId)
    local result = {}
    for _, item in ipairs(Logistics.physicalPallets(state)) do
        if item.pallet.id ~= excludedPalletId then
            result[#result + 1] = {
                x = item.x,
                y = item.y - 8,
                halfWidth = halfWidth or 33,
                halfHeight = halfHeight or 11,
            }
        end
    end
    return result
end

function Logistics.hovered(state, mouseX, mouseY)
    if type(mouseX) ~= "number" or type(mouseY) ~= "number" then return nil end
    local best
    for _, item in ipairs(Logistics.physicalPallets(state)) do
        local inside = mouseX >= item.x - 54 and mouseX <= item.x + 54
            and mouseY >= item.y - 82 and mouseY <= item.y + 10
        if inside and (not best or item.y > best.y) then best = item end
    end
    return best
end

function Logistics.tooltip(item)
    if not item then return nil end
    if item.vendor then
        local pallet, order = item.pallet, item.job
        return {
            title = pallet.id .. "  •  " .. order.company,
            line1 = string.format("Purchase %s  |  %s", order.id, pallet.productName),
            line2 = string.format("Quantity: %s %s  |  Category: %s", tostring(pallet.quantity), pallet.unit, pallet.categoryName),
            line3 = string.format("Status: %s  |  Location: %s", pallet.status, pallet.location),
        }
    end
    local paper, pallet, job = item.pallet.paper, item.pallet, item.job
    local size = paper and paper.currentSize or job.sourceSize
    return {
        title = pallet.id .. "  •  " .. job.company,
        line1 = string.format("Job %s  |  %s sheets", job.id, commaNumber(pallet.initialSheets)),
        line2 = string.format("Paper %s  |  %.2f x %.2f in", paper and paper.id or "unassigned", size.width, size.height),
        line3 = string.format("Status: %s  |  Location: %s", pallet.status, pallet.location),
    }
end

function Logistics.directionFrame(pallet)
    local world = pallet and pallet.world or nil
    if world and directionFrames[world.direction] then
        return directionFrames[world.direction]
    end
    if world and type(world.rotation) == "number" and world.rotation >= 1 and world.rotation <= 4 then
        return math.floor(world.rotation)
    end
    return 1
end

return Logistics
