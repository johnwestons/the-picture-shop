local BusinessCalendar = require("src.business_calendar")

local Plates = {}
local actions = { "expose", "wash", "dry", "mount" }

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

function Plates.ensureJob(job)
    if type(job) ~= "table" or type(job.press) ~= "table" then return {} end
    job.press.plates = type(job.press.plates) == "table" and job.press.plates or {}
    job.press.actual = type(job.press.actual) == "table" and job.press.actual or {
        plateCost = 0, inHousePlates = 0, inkUnits = 0, tympanSheets = 0,
        washUnits = 0, proofs = 0, impressions = 0, spoilage = 0, pressHours = 0, supplyCost = 0,
    }
    job.press.actual.supplyCost = tonumber(job.press.actual.supplyCost) or 0
    local count = math.max(1, math.floor(tonumber(job.press.colors) or 1))
    for color = 1, count do
        local plate = job.press.plates[color]
        if type(plate) ~= "table" then
            plate = {
                id = string.format("%s-PLATE-%02d", job.id or "JOB", color),
                jobId = job.id,
                colorIndex = color,
                inkColor = (job.press.colorSequence or {})[color] or (color == 1 and "Black" or "Spot " .. color),
                artworkKey = job.artworkKey,
                artworkSize = copy(job.press.artworkSize or job.finishedSize),
                status = "unprepared",
                source = nil,
                quality = 0,
                life = 1,
                processStep = 1,
                processScores = {},
                mounted = false,
            }
            job.press.plates[color] = plate
        end
        plate.processScores = type(plate.processScores) == "table" and plate.processScores or {}
        plate.processStep = math.max(1, math.floor(tonumber(plate.processStep) or 1))
        plate.quality = math.max(0, math.min(1, tonumber(plate.quality) or 0))
        plate.life = math.max(0, math.min(1, tonumber(plate.life) or 1))
        plate.mounted = plate.mounted == true
    end
    return job.press.plates
end

function Plates.update(state)
    local changed, now = false, BusinessCalendar.absoluteHours(state)
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do
        for _, plate in ipairs(Plates.ensureJob(job)) do
            if plate.status == "ordered" and now + 0.000001 >= (plate.readyAtHours or math.huge) then
                plate.status, plate.source, plate.quality, plate.mounted = "ready", "outsourced", 0.98, true
                changed = true
            end
        end
    end
    return changed
end

function Plates.order(state, job, colorIndex)
    local plate = Plates.ensureJob(job)[colorIndex]
    if not plate or plate.status ~= "unprepared" then return false, "That plate is already being prepared." end
    local budget = job.quote and job.quote.pressBudget
    local colors = math.max(1, tonumber(job.press.colors) or 1)
    local cost = math.max(1, math.ceil(((budget and budget.plateCost) or 38.5) / colors * 100) / 100)
    if (state.money or 0) < cost then return false, "Not enough cash to outsource this plate." end
    state.money = state.money - cost
    plate.status, plate.source = "ordered", "outsourced"
    plate.orderedAtHours = BusinessCalendar.absoluteHours(state)
    plate.readyAtHours = plate.orderedAtHours + 24
    plate.actualCost = cost
    job.press.actual.plateCost = (job.press.actual.plateCost or 0) + cost
    job.press.actual.supplyCost = job.press.actual.supplyCost + cost
    return true, plate
end

function Plates.beginInHouse(state, job, colorIndex)
    local plate = Plates.ensureJob(job)[colorIndex]
    if not plate or plate.status ~= "unprepared" then return false, "That plate cannot enter the platemaker." end
    local stock = state.inventory and state.inventory.stock or {}
    local required = { raw_press_plates = 1, negative_film = 1, plate_adhesive = 1, plate_chemistry = 1 }
    for id, amount in pairs(required) do
        if (stock[id] or 0) < amount then return false, "In-house platemaking needs raw plate, film, adhesive, and chemistry." end
    end
    for id, amount in pairs(required) do stock[id] = stock[id] - amount end
    plate.status, plate.source, plate.processStep, plate.processScores = "processing", "in_house", 1, {}
    job.press.actual.inHousePlates = (job.press.actual.inHousePlates or 0) + 1
    job.press.actual.supplyCost = job.press.actual.supplyCost + 34
    return true, plate
end

function Plates.process(plate, action, accuracy)
    if type(plate) ~= "table" or plate.status ~= "processing" then return false, "No plate is in process." end
    local expected = actions[plate.processStep]
    if action ~= expected then return false, "Complete plate steps in exposure, washout, drying, and mounting order." end
    accuracy = math.max(0, math.min(1, tonumber(accuracy) or 0))
    plate.processScores[#plate.processScores + 1] = accuracy
    plate.processStep = plate.processStep + 1
    if plate.processStep > #actions then
        local total = 0
        for _, score in ipairs(plate.processScores) do total = total + score end
        plate.quality = total / #plate.processScores
        plate.status, plate.mounted = "ready", true
    end
    return true, plate
end

function Plates.actionFor(plate) return actions[plate and plate.processStep or 1] end
function Plates.ready(job, colorIndex)
    local plate = Plates.ensureJob(job)[colorIndex]
    return plate and plate.status == "ready" and plate.mounted and plate.life > 0, plate
end

return Plates
