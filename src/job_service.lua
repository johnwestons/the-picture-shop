-- Connects pure job-domain rules to the game's saved shop state.
local Jobs = require("src.jobs")

local JobService = {}

local templates = {
    {
        difficulty = "easy",
        company = "Blue Ridge Packaging",
        sourceSize = { width = 25, height = 19 },
        finishedSize = { width = 12.5, height = 9.5 },
        sheetCounts = { 1000, 750 },
        packaging = "boxed",
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

function JobService.templates()
    return copy(templates)
end

return JobService
