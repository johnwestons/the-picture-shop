-- Connects pure job-domain rules to the game's saved shop state.
local Jobs = require("src.jobs")
local PalletState = require("src.pallet_state")
local Config = require("src.config")

local JobService = {}

local templates = {
    {
        difficulty = "easy",
        company = "Blue Ridge Packaging",
        sourceSize = { width = 25, height = 19 },
        finishedSize = { width = 12.5, height = 9.5 },
        sheetCounts = { 1000, 750 },
        packaging = "boxed",
        artworkKey = "flower",
        details = {
            stockDescription = "80 lb customer-supplied cover stock",
            dueDate = "Standard 5-business-day turnaround",
            grainDirection = "Grain long; keep orientation consistent",
            notes = "Keep the two pallets separated and retain all customer skid labels.",
        },
    },
    {
        difficulty = "medium",
        company = "Northstar Bindery",
        sourceSize = { width = 23, height = 17.5 },
        finishedSize = { width = 11.5, height = 8.75 },
        sheetCounts = { 1500 },
        packaging = "flat",
        artworkKey = "cat",
        details = {
            stockDescription = "100 lb gloss text",
            dueDate = "Standard 5-business-day turnaround",
            grainDirection = "Grain long",
            notes = "Protect the gloss surface and wrap the finished skid before pickup.",
        },
    },
    {
        difficulty = "hard",
        company = "Keystone Paper Supply",
        sourceSize = { width = 25, height = 25 },
        finishedSize = { width = 20, height = 12.5 },
        sheetCounts = { 3000, 3000, 2000 },
        packaging = "flat",
        artworkKey = "landscape",
        details = {
            stockDescription = "Uncoated offset sheets",
            dueDate = "Standard 7-business-day turnaround",
            grainDirection = "Grain short",
            notes = "Count and label every finished pallet separately.",
        },
    },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function nextSequence(state)
    local sequence = type(state.nextJobId) == "number" and math.floor(state.nextJobId) or 1
    return math.max(1, sequence)
end

function JobService.createNextOffer(state, timestamp)
    if type(state) ~= "table" then return nil, { "shop state is required" } end
    local sequence = nextSequence(state)
    local template = copy(templates[(sequence - 1) % #templates + 1])
    template.id = Jobs.formatId(sequence)
    template.sequence = sequence
    template.createdAt = timestamp
    local artwork = Config.artworkOrder or {}
    if #artwork > 0 then template.artworkKey = artwork[(sequence - 1) % #artwork + 1] end
    return Jobs.createOffer(template)
end

local function prepareCollections(state)
    state.jobs = type(state.jobs) == "table" and state.jobs or {}
    state.jobs.active = type(state.jobs.active) == "table" and state.jobs.active or {}
    state.jobs.completed = type(state.jobs.completed) == "table" and state.jobs.completed or {}
    state.jobs.declined = type(state.jobs.declined) == "table" and state.jobs.declined or {}
end

function JobService.acceptOffer(state, job, timestamp)
    if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
    local accepted, errorMessage = Jobs.accept(job, timestamp)
    if not accepted then return false, errorMessage end
    prepareCollections(state)
    state.jobs.active[#state.jobs.active + 1] = job
    state.accountsReceivable = math.max(0, state.accountsReceivable or 0) + job.quote.totalPrice
    state.nextJobId = nextSequence(state) + 1
    return true, job
end

function JobService.declineOffer(state, job, timestamp)
    if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
    local declined, errorMessage = Jobs.decline(job, timestamp)
    if not declined then return false, errorMessage end
    prepareCollections(state)
    state.jobs.declined[#state.jobs.declined + 1] = job
    state.nextJobId = nextSequence(state) + 1
    return true, job
end

local function activeJob(state, jobId)
    prepareCollections(state)
    for index, job in ipairs(state.jobs.active) do
        if job.id == jobId then return job, index end
    end
end

function JobService.completionReady(job)
    if type(job) ~= "table" or job.status ~= "in_production"
        or type(job.pallets) ~= "table" or #job.pallets == 0
    then
        return false
    end
    for _, pallet in ipairs(job.pallets) do
        if (pallet.remainingSheets or 0) > 0 or pallet.status ~= "wrapped" or not pallet.wrapped then
            return false
        end
    end
    return true
end

function JobService.requestPickup(state, job, timestamp)
    if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
    local active = activeJob(state, job.id)
    if active ~= job then return false, "job is not active" end
    if not JobService.completionReady(job) then
        return false, "every pallet must be finished and wrapped before pickup"
    end
    job.status = "ready_for_pickup"
    job.pickup = {
        status = "awaiting_schedule",
        requestedAt = timestamp,
    }
    return true, job
end

function JobService.nextPickup(state)
    prepareCollections(state)
    for _, job in ipairs(state.jobs.active) do
        local pickupStatus = job.pickup and job.pickup.status
        if job.status == "ready_for_pickup"
            or (job.status == "pickup_in_progress" and pickupStatus ~= "completed")
        then
            return job
        end
    end
end

function JobService.schedulePickup(job, timestamp)
    if type(job) ~= "table" or (job.status ~= "ready_for_pickup" and job.status ~= "pickup_in_progress") then
        return false, "job is not awaiting pickup"
    end
    job.pickup = type(job.pickup) == "table" and job.pickup or {}
    job.status = "pickup_in_progress"
    job.pickup.status = "scheduled"
    job.pickup.scheduledAt = timestamp
    return true, job
end

function JobService.setPickupStatus(job, status, timestampField, timestamp)
    if type(job) ~= "table" or job.status ~= "pickup_in_progress" then return false end
    job.pickup = type(job.pickup) == "table" and job.pickup or {}
    job.pickup.status = status
    if timestampField then job.pickup[timestampField] = timestamp end
    return true
end

function JobService.pickupInventory(state, jobId)
    local job = activeJob(state, jobId)
    local inventory = {}
    for _, pallet in ipairs(job and job.pallets or {}) do
        inventory[#inventory + 1] = {
            id = pallet.id,
            number = pallet.number,
            sheets = pallet.finishedSheets,
            location = pallet.location,
            status = pallet.status,
            paper = pallet.paper,
            pallet = pallet,
        }
    end
    return job, inventory
end

function JobService.remainingPickup(state, jobId)
    local _, inventory = JobService.pickupInventory(state, jobId)
    local remaining = 0
    for _, item in ipairs(inventory) do
        if item.location ~= "outbound_truck" and item.location ~= "none" then remaining = remaining + 1 end
    end
    return remaining
end

function JobService.loadForPickup(state, jobId, palletId, timestamp)
    local job = activeJob(state, jobId)
    if not job or job.status ~= "pickup_in_progress" then return false, "pickup is not in progress" end
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.id == palletId then
            if pallet.location == "outbound_truck" then return false, "that pallet is already on the truck" end
            if pallet.status ~= "wrapped" or not pallet.wrapped then return false, "that pallet is not wrapped" end
            if pallet.location ~= "warehouse" and pallet.location ~= "cutter_output" then
                return false, "lower the wrapped pallet onto the warehouse floor before loading"
            end
            local transitioned, transitionError = PalletState.transition(
                state, pallet, "outbound_truck", { status = "loaded_for_pickup" })
            if not transitioned then return false, transitionError end
            state.inventory.finishedPallets = math.max(0, (state.inventory.finishedPallets or 0) - 1)
            local remaining = JobService.remainingPickup(state, jobId)
            JobService.setPickupStatus(job, remaining == 0 and "loaded" or "loading",
                remaining == 0 and "loadedAt" or nil, timestamp)
            return true, pallet, remaining
        end
    end
    return false, "the pickup pallet was not found"
end

function JobService.completePickup(state, jobId, timestamp)
    local job, activeIndex = activeJob(state, jobId)
    if not job or job.status ~= "pickup_in_progress" then return false, "pickup is not in progress" end
    if JobService.remainingPickup(state, jobId) ~= 0 then return false, "pickup pallets remain on the floor" end
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.location ~= "outbound_truck" then return false, "pickup manifest is incomplete" end
    end
    for _, pallet in ipairs(job.pallets or {}) do
        local transitioned, transitionError = PalletState.transition(
            state, pallet, "none", { status = "picked_up" })
        if not transitioned then return false, transitionError end
        pallet.pickedUpAt = timestamp
    end
    local payment = job.quote.totalPrice
    job.status = "completed"
    job.completedAt = timestamp
    job.paidAt = timestamp
    job.paymentAmount = payment
    job.pickup.status = "completed"
    job.pickup.completedAt = timestamp
    table.remove(state.jobs.active, activeIndex)
    state.jobs.completed[#state.jobs.completed + 1] = job
    state.accountsReceivable = math.max(0, (state.accountsReceivable or 0) - payment)
    state.money = math.max(0, state.money or 0) + payment
    return true, job, payment
end

function JobService.templates()
    return copy(templates)
end

return JobService
