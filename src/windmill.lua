local BusinessCalendar = require("src.business_calendar")
local Config = require("src.config")
local MachineFleet = require("src.machine_fleet")
local PalletState = require("src.pallet_state")
local Plates = require("src.plate_service")

local Windmill = {}
local setupTasks = { "chase", "packing", "rollers", "ink", "feeder", "register" }

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

local function process(state)
    local placement = state.windmill
    placement.process = type(placement.process) == "table" and placement.process or {}
    local p = placement.process
    p.status = type(p.status) == "string" and p.status or "idle"
    p.speed = clamp(tonumber(p.speed) or 3000, 1000, 5500)
    p.motor, p.feeder, p.impression, p.emergency = p.motor == true, p.feeder == true,
        p.impression == true, p.emergency == true
    p.setup = type(p.setup) == "table" and p.setup or {}
    p.counter, p.goodSheets, p.spoilage = math.max(0, tonumber(p.counter) or 0),
        math.max(0, tonumber(p.goodSheets) or 0), math.max(0, tonumber(p.spoilage) or 0)
    p.sheetAccumulator = math.max(0, tonumber(p.sheetAccumulator) or 0)
    p.animationClock = math.max(0, tonumber(p.animationClock) or 0)
    return p
end

function Windmill.ensure(state)
    state.windmill = type(state.windmill) == "table" and state.windmill or {
        x = Config.windmillPlacement.spawnX, y = Config.windmillPlacement.spawnY,
        direction = Config.windmillPlacement.defaultDirection, moving = false, inMotion = false,
    }
    return process(state)
end

local function activeJob(state, jobId)
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do if job.id == jobId then return job end end
end

function Windmill.current(state)
    local p = Windmill.ensure(state)
    local job = activeJob(state, p.jobId)
    if not job then return p end
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.id == p.palletId then return p, job, pallet end
    end
    return p, job
end

local function actual(job)
    Plates.ensureJob(job)
    return job.press.actual
end

local function componentPenalty(machine)
    if not machine then return 0.30, "PRESS NOT AVAILABLE" end
    local values = machine.variables or {}
    local penalty = math.max(0, 45 - (values.formRollers or 0)) / 500
        + math.max(0, 45 - (values.gripperTiming or 0)) / 420
        + math.max(0, 45 - (values.suctionAir or 0)) / 380
        + math.max(0, 45 - (values.inkTrain or 0)) / 500
    local labels = {
        formRollers = "ROLLER STRIPE UNSTABLE", gripperTiming = "REGISTER DRIFT",
        suctionAir = "FEED / DOUBLE-SHEET RISK", inkTrain = "INK DISTRIBUTION UNEVEN",
        driveLubrication = "LUBRICATION SERVICE DUE", safetyCircuit = "SAFETY CIRCUIT SERVICE DUE",
    }
    local weakest, warning = 101, nil
    for id, value in pairs(values) do
        if value < weakest then weakest, warning = value, labels[id] end
    end
    return penalty, weakest < 45 and warning or nil
end

function Windmill.failureSummary(state)
    local _, warning = componentPenalty(MachineFleet.installed(state, "heidelberg_10x15"))
    return warning or "NO ACTIVE FAULTS"
end

function Windmill.candidates(state)
    local result = {}
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do
        if job.press then
            Plates.ensureJob(job)
            for _, pallet in ipairs(job.pallets or {}) do
                local paperReady = pallet.paper and pallet.paper.status == "complete"
                local press = pallet.press
                local color = press and (press.completedColors or 0) + 1 or 1
                local dry = not press or not press.dryUntilHours
                    or BusinessCalendar.absoluteHours(state) >= press.dryUntilHours
                if paperReady and dry and color <= (job.press.colors or 1)
                    and (pallet.location == "warehouse" or pallet.location == "cutter_output"
                        or pallet.location == "press_output")
                then result[#result + 1] = { job = job, pallet = pallet, color = color } end
            end
        end
    end
    return result
end

function Windmill.load(state, palletId)
    local p = Windmill.ensure(state)
    if p.status ~= "idle" then return false, "Return the press to idle before loading another pallet." end
    for _, item in ipairs(Windmill.candidates(state)) do
        if item.pallet.id == palletId then
            local ready = Plates.ready(item.job, item.color)
            if not ready then return false, "Prepare and mount the plate for this color first." end
            local transitioned, errorMessage = PalletState.transition(state, item.pallet, "at_press", {
                status = "press_setup",
            })
            if not transitioned then return false, errorMessage end
            item.pallet.press = type(item.pallet.press) == "table" and item.pallet.press or {
                status = "setup", completedColors = 0, goodSheets = 0, spoilage = 0,
            }
            p.jobId, p.palletId, p.colorIndex = item.job.id, item.pallet.id, item.color
            p.status, p.setup = "setup", {}
            p.counter, p.goodSheets, p.spoilage, p.sheetAccumulator = 0, 0, 0, 0
            p.motor, p.feeder, p.impression, p.emergency = false, false, false, false
            return true, item
        end
    end
    return false, "No print-ready pallet with a mounted plate is available."
end

function Windmill.completeSetup(state, task, score)
    local p = Windmill.ensure(state)
    if p.status ~= "setup" then return false, "Load a pallet before setup." end
    local valid = false
    for _, id in ipairs(setupTasks) do if id == task then valid = true end end
    if not valid then return false, "Unknown press setup task." end
    if not p.setup[task] then
        local stock = state.inventory and state.inventory.stock or {}
        if task == "ink" then
            local _, job = Windmill.current(state)
            local plate = job and Plates.ensureJob(job)[p.colorIndex]
            local inkId = plate and plate.inkColor == "Black" and "black_ink" or "color_ink"
            if (stock[inkId] or 0) < 1 then return false, "The correct ink is not in inventory." end
            stock[inkId] = stock[inkId] - 1
            if job then
                local totals = actual(job)
                totals.inkUnits = (totals.inkUnits or 0) + 1
                totals.supplyCost = (totals.supplyCost or 0) + (inkId == "black_ink" and 46 / 35 or 82 / 35)
            end
        elseif task == "packing" then
            if (stock.tympan_sheets or 0) < 1 then return false, "A clean tympan sheet is required." end
            stock.tympan_sheets = stock.tympan_sheets - 1
            local _, job = Windmill.current(state)
            if job then
                local totals = actual(job)
                totals.tympanSheets = (totals.tympanSheets or 0) + 1
                totals.supplyCost = (totals.supplyCost or 0) + 1
            end
        end
    end
    p.setup[task] = clamp(tonumber(score) or 0, 0, 1)
    return true, p
end

function Windmill.setupComplete(state)
    local p = Windmill.ensure(state)
    for _, task in ipairs(setupTasks) do if not p.setup[task] then return false end end
    return true
end

function Windmill.setupTasks() return setupTasks end

function Windmill.control(state, action)
    local p = Windmill.ensure(state)
    if action == "emergency" then
        p.emergency, p.motor, p.feeder, p.impression, p.status = true, false, false, false, "stopped"
        return true
    elseif action == "reset" then
        if p.status == "production" then return false, "Stop production before resetting." end
        p.emergency = false
        if p.palletId then p.status = Windmill.setupComplete(state) and "proof" or "setup" else p.status = "idle" end
        return true
    elseif p.emergency then return false, "Emergency stop is active. Reset the press first." end
    if action == "motor" then
        if not p.motor then
            local operable, reason = MachineFleet.canOperate(state, "heidelberg_10x15")
            if not operable then return false, reason end
        end
        p.motor = not p.motor
        if not p.motor then p.feeder, p.impression = false, false end
    elseif action == "feeder" then if not p.motor then return false, "Start the motor first." end; p.feeder = not p.feeder
    elseif action == "impression" then if not p.motor then return false, "Start the motor first." end; p.impression = not p.impression
    elseif action == "speed_up" then p.speed = clamp(p.speed + 500, 1000, 5500)
    elseif action == "speed_down" then p.speed = clamp(p.speed - 500, 1000, 5500)
    else return false, "Unknown press control." end
    return true, p
end

local function setupAverage(p)
    local total = 0
    for _, task in ipairs(setupTasks) do total = total + (p.setup[task] or 0) end
    return total / #setupTasks
end

function Windmill.takeProof(state)
    local p, job, pallet = Windmill.current(state)
    if not job or not pallet or not Windmill.setupComplete(state) then return false, "Complete all setup tasks first." end
    if p.emergency or not p.motor or not p.feeder or not p.impression then
        return false, "Proofing requires motor, feeder, and impression on."
    end
    local plate = Plates.ensureJob(job)[p.colorIndex]
    local machine = MachineFleet.installed(state, "heidelberg_10x15")
    local condition = machine and MachineFleet.condition(machine) / 100 or 0
    local quality = clamp(setupAverage(p) * 0.72 + (plate and plate.quality or 0) * 0.18
        + condition * 0.10 - math.max(0, p.speed - 3000) / 25000, 0, 1)
    p.proofQuality, p.proofApproved, p.status = quality, false, "proof"
    p.counter, p.spoilage = p.counter + 1, p.spoilage + 1
    pallet.press.spoilage = (pallet.press.spoilage or 0) + 1
    local totals = actual(job)
    totals.proofs = (totals.proofs or 0) + 1
    totals.impressions = (totals.impressions or 0) + 1
    totals.spoilage = (totals.spoilage or 0) + 1
    return true, quality
end

function Windmill.approveProof(state)
    local p = Windmill.ensure(state)
    if p.status ~= "proof" or (p.proofQuality or 0) < 0.82 then
        return false, "The proof must score at least 82% before approval."
    end
    p.proofApproved, p.status = true, "approved"
    return true, p
end

function Windmill.startProduction(state)
    local p = Windmill.ensure(state)
    if not p.proofApproved then return false, "Approve a proof first." end
    if p.emergency or not p.motor or not p.feeder or not p.impression then
        return false, "Production requires motor, feeder, and impression on."
    end
    local operable, reason = MachineFleet.canOperate(state, "heidelberg_10x15")
    if not operable then return false, reason end
    p.status = "production"
    return true, p
end

function Windmill.stopProduction(state)
    local p = Windmill.ensure(state)
    if p.status ~= "production" then return false end
    p.status, p.feeder, p.impression = "approved", false, false
    return true, p
end

function Windmill.update(dt, state)
    local p, job, pallet = Windmill.current(state)
    p.animationClock = p.animationClock + math.max(0, dt)
    Plates.update(state)
    if p.status ~= "production" or not job or not pallet then return false end
    local gameHours = math.max(0, dt) * 24 / Config.businessCalendar.secondsPerDay
    p.sheetAccumulator = p.sheetAccumulator + p.speed * gameHours
    local attempted = math.floor(p.sheetAccumulator)
    if attempted <= 0 then return false end
    p.sheetAccumulator = p.sheetAccumulator - attempted
    local machine = MachineFleet.installed(state, "heidelberg_10x15")
    local condition = machine and MachineFleet.condition(machine) / 100 or 0
    local setup = setupAverage(p)
    local mechanicalPenalty, warning = componentPenalty(machine)
    local wasteRate = clamp(0.01 + (1 - setup) * 0.18 + (1 - condition) * 0.12 + mechanicalPenalty
        + math.max(0, p.speed - 3000) / 25000, 0.01, 0.35)
    local waste = math.floor(attempted * wasteRate + 0.5)
    local good = math.max(0, attempted - waste)
    local target = pallet.initialSheets or 0
    good = math.min(good, math.max(0, target - p.goodSheets))
    p.counter, p.goodSheets, p.spoilage = p.counter + attempted, p.goodSheets + good, p.spoilage + waste
    pallet.press.goodSheets = p.goodSheets
    pallet.press.spoilage = (pallet.press.spoilage or 0) + waste
    p.warning = warning
    local totals = actual(job)
    totals.impressions = (totals.impressions or 0) + attempted
    totals.spoilage = (totals.spoilage or 0) + waste
    totals.pressHours = (totals.pressHours or 0) + attempted / math.max(1, p.speed)
    MachineFleet.recordUse(state, "heidelberg_10x15", attempted / 1000)
    local plate = Plates.ensureJob(job)[p.colorIndex]
    if plate then plate.life = clamp(plate.life - attempted / 250000, 0, 1) end
    if p.goodSheets >= target then
        p.status, p.feeder, p.impression = "pass_complete", false, false
        pallet.press.status = "pass_complete"
        return true
    end
    return false
end

function Windmill.cleanAndUnload(state)
    local p, job, pallet = Windmill.current(state)
    if p.status ~= "pass_complete" then return false, "Finish the color pass before cleanup." end
    local stock = state.inventory and state.inventory.stock or {}
    if (stock.press_wash or 0) < 1 then return false, "Press wash is required for cleanup." end
    stock.press_wash = stock.press_wash - 1
    local totals = actual(job)
    totals.washUnits = (totals.washUnits or 0) + 1
    totals.supplyCost = (totals.supplyCost or 0) + 34 / 6
    pallet.press.completedColors = p.colorIndex
    pallet.press.goodSheets = p.goodSheets
    pallet.press.status = p.colorIndex >= (job.press.colors or 1) and "complete" or "drying"
    if pallet.press.status == "drying" then
        local coated = job.details and tostring(job.details.stockDescription or ""):lower():find("gloss", 1, true)
        pallet.press.dryUntilHours = BusinessCalendar.absoluteHours(state) + (coated and 8 or 2)
    else
        pallet.press.dryUntilHours = nil
        pallet.status = "printed"
    end
    local world = pallet.world or { x = state.windmill.x + 80, y = state.windmill.y + 45,
        direction = state.windmill.direction }
    local transitioned, errorMessage = PalletState.transition(state, pallet, "press_output", {
        status = pallet.status, world = world,
    })
    if not transitioned then return false, errorMessage end
    p.status, p.jobId, p.palletId, p.colorIndex = "idle", nil, nil, nil
    p.setup, p.motor, p.feeder, p.impression, p.proofApproved = {}, false, false, false, false
    return true, pallet
end

function Windmill.canExit(state) return Windmill.ensure(state).status ~= "production" end

return Windmill
