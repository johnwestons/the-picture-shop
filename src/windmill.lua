local BusinessCalendar = require("src.business_calendar")
local Config = require("src.config")
local MachineFleet = require("src.machine_fleet")
local PalletState = require("src.pallet_state")
local Plates = require("src.plate_service")

local Windmill = {}
local setupTasks = { "chase", "packing", "rollers", "ink", "feeder", "register" }
local UINT32_MODULUS = 4294967296
local runtimeRevision = 0

function Windmill.bumpNetworkRevision()
    runtimeRevision = (runtimeRevision + 1) % UINT32_MODULUS
    return runtimeRevision
end

function Windmill.networkRuntimeRevision()
    return runtimeRevision
end

function Windmill.resetNetworkRuntime()
    runtimeRevision = 0
    return runtimeRevision
end

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

local function placementFor(state)
    local machine = MachineFleet.installed(state, "heidelberg_10x15")
    return machine and machine.world or state.windmill
end

local function process(placement)
    placement.process = type(placement.process) == "table" and placement.process or {}
    local p = placement.process
    p.status = type(p.status) == "string" and p.status or "idle"
    p.speed = clamp(tonumber(p.speed) or 3000, 1000, 5500)
    p.motor, p.feeder, p.impression, p.emergency = p.motor == true, p.feeder == true,
        p.impression == true, p.emergency == true
    p.setup = type(p.setup) == "table" and p.setup or {}
    p.counter, p.goodSheets, p.spoilage = math.max(0, tonumber(p.counter) or 0),
        math.max(0, tonumber(p.goodSheets) or 0), math.max(0, tonumber(p.spoilage) or 0)
    p.targetSheets = math.max(0, math.floor(tonumber(p.targetSheets) or 0))
    p.feedStart = math.max(0, math.floor(tonumber(p.feedStart) or 0))
    p.feedRemaining = math.max(0, math.floor(tonumber(p.feedRemaining) or 0))
    p.artworkVerified = p.artworkVerified == true
    p.sheetAccumulator = math.max(0, tonumber(p.sheetAccumulator) or 0)
    p.animationClock = math.max(0, tonumber(p.animationClock) or 0)
    return p
end

local function ensurePalletPress(job, pallet)
    pallet.press = type(pallet.press) == "table" and pallet.press or {}
    local press = pallet.press
    press.status = type(press.status) == "string" and press.status or "awaiting_cut"
    press.completedColors = math.max(0, math.floor(tonumber(press.completedColors) or 0))
    press.goodSheets = math.max(0, math.floor(tonumber(press.goodSheets) or 0))
    press.spoilage = math.max(0, math.floor(tonumber(press.spoilage) or 0))
    press.requiredGoodSheets = math.max(1, math.floor(tonumber(press.requiredGoodSheets)
        or tonumber(pallet.requestedCopies) or tonumber(pallet.initialSheets) or 1))
    press.availableSheets = math.max(0, math.floor(tonumber(press.availableSheets)
        or tonumber(pallet.finishedSheets) or tonumber(pallet.initialSheets) or 0))
    press.passHistory = type(press.passHistory) == "table" and press.passHistory or {}
    return press
end

function Windmill.passTarget(job, pallet, colorIndex)
    local press = ensurePalletPress(job, pallet)
    local required = press.requiredGoodSheets
    local colors = math.max(1, math.floor(tonumber(job and job.press and job.press.colors) or 1))
    local color = clamp(math.floor(tonumber(colorIndex) or 1), 1, colors)
    local supplied = math.max(required, math.floor(tonumber(pallet.initialSheets) or required))
    local allowance = math.max(0, math.floor(tonumber(pallet.spoilageAllowance)
        or (supplied - required)))
    local reservePerPass = math.floor(allowance / colors)
    return required + reservePerPass * (colors - color)
end

function Windmill.ensure(state)
    state.windmill = type(state.windmill) == "table" and state.windmill or {
        x = Config.windmillPlacement.spawnX, y = Config.windmillPlacement.spawnY,
        direction = Config.windmillPlacement.defaultDirection, moving = false, inMotion = false,
    }
    return process(placementFor(state))
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

local function dryingDuration(job)
    local finish = job and job.stockSpec and job.stockSpec.finish
        or (job and job.details and tostring(job.details.stockDescription or ""))
    return tostring(finish or ""):lower():find("gloss", 1, true) and 8 or 2
end

function Windmill.dryingStatus(state, job, pallet)
    local press = pallet and ensurePalletPress(job, pallet)
    if not press or press.status ~= "drying" then return nil end
    local duration = dryingDuration(job)
    local finish = tonumber(press.dryUntilHours)
    if not finish then
        return { progress = 1, remainingHours = 0, durationHours = duration, ready = true }
    end
    local now = BusinessCalendar.absoluteHours(state)
    local remaining = math.max(0, finish - now)
    local progress = clamp(1 - remaining / math.max(0.001, duration), 0, 1)
    return {
        progress = progress,
        remainingHours = remaining,
        durationHours = duration,
        ready = remaining <= 0,
    }
end

function Windmill.dryingPallets(state)
    local result = {}
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do
        if job.press then
            for _, pallet in ipairs(job.pallets or {}) do
                local drying = Windmill.dryingStatus(state, job, pallet)
                if drying and not drying.ready then
                    result[#result + 1] = { job = job, pallet = pallet, drying = drying }
                end
            end
        end
    end
    return result
end

function Windmill.candidates(state)
    local result = {}
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do
        if job.press then
            Plates.ensureJob(job)
            for _, pallet in ipairs(job.pallets or {}) do
                local paperReady = pallet.paper and pallet.paper.status == "complete"
                local press = ensurePalletPress(job, pallet)
                local color = press and (press.completedColors or 0) + 1 or 1
                local dry = not press or not press.dryUntilHours
                    or BusinessCalendar.absoluteHours(state) >= press.dryUntilHours
                local world = pallet.world
                local placement = placementFor(state)
                local staged = world and ((world.x - placement.x) ^ 2
                    + (world.y - placement.y) ^ 2
                    <= (Config.windmillPlacement.palletRadius or 120) ^ 2)
                if paperReady and dry and color <= (job.press.colors or 1)
                    and not pallet.wrapped and staged
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
            local palletPress = ensurePalletPress(item.job, item.pallet)
            local target = Windmill.passTarget(item.job, item.pallet, item.color)
            local available = item.color == 1
                and math.max(0, math.floor(tonumber(item.pallet.finishedSheets)
                    or tonumber(item.pallet.initialSheets) or 0))
                or palletPress.availableSheets
            if available < target then
                return false, string.format("Only %d prepared sheets remain; this pass needs %d good sheets.",
                    available, target)
            end
            local transitioned, errorMessage = PalletState.transition(state, item.pallet, "at_press", {
                status = "press_setup",
            })
            if not transitioned then return false, errorMessage end
            palletPress.availableSheets = available
            palletPress.status = "setup"
            p.jobId, p.palletId, p.colorIndex = item.job.id, item.pallet.id, item.color
            p.status, p.setup = "setup", {}
            p.counter, p.goodSheets, p.spoilage, p.sheetAccumulator = 0, 0, 0, 0
            p.targetSheets, p.feedStart, p.feedRemaining = target, available, available
            p.artworkVerified, p.proofQuality, p.proofApproved = false, nil, false
            p.warning = nil
            p.motor, p.feeder, p.impression, p.emergency = false, false, false, false
            state.message = string.format(
                "Loaded %s: pass target %d, client order %d, %d sheets available.",
                item.pallet.id, target, palletPress.requiredGoodSheets, available)
            Windmill.bumpNetworkRevision()
            return true, item
        end
    end
    return false, "No print-ready pallet with a mounted plate is available."
end

function Windmill.completeSetup(state, task, score)
    local p = Windmill.ensure(state)
    if not p.palletId or p.status == "production" or p.status == "pass_complete" then
        return false, "Load a stopped pallet before setup."
    end
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
                totals.supplyCost = (totals.supplyCost or 0) + (inkId == "black_ink" and 46 / 35 or 42 / 35)
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
    p.status, p.proofQuality, p.proofApproved, p.artworkVerified = "setup", nil, false, false
    Windmill.bumpNetworkRevision()
    return true, p
end

function Windmill.setupComplete(state)
    local p = Windmill.ensure(state)
    for _, task in ipairs(setupTasks) do if not p.setup[task] then return false end end
    return true
end

function Windmill.setupTasks() return setupTasks end

function Windmill.proofReadiness(state)
    local p, job, pallet = Windmill.current(state)
    if not job or not pallet then return false, "Load a print-ready pallet first." end
    if p.status ~= "setup" and p.status ~= "proof" and p.status ~= "approved" then
        return false, p.status == "production"
            and "Stop production before pulling another proof."
            or "Return the loaded press to setup or proof approval before pulling a proof."
    end
    local plate = p.colorIndex and Plates.ensureJob(job)[p.colorIndex] or nil
    if not plate or plate.status ~= "ready" or not plate.mounted then
        return false, "Prepare and mount the plate for this color before proofing."
    end
    if not Windmill.setupComplete(state) then return false, "Complete all six setup checks first." end
    if p.emergency then return false, "Reset the emergency stop before proofing." end
    if not p.motor then return false, "Start the motor before proofing." end
    if not p.feeder then return false, "Turn the feeder on before proofing." end
    if not p.impression then return false, "Turn impression on before proofing." end
    if p.feedRemaining <= math.max(0, p.targetSheets - p.goodSheets) then
        return false, "No proof allowance remains; preserve the remaining client sheets."
    end
    return true, "Ready to pull one proof sheet."
end

function Windmill.control(state, action)
    local p = Windmill.ensure(state)
    if action == "emergency" then
        p.emergency, p.motor, p.feeder, p.impression, p.status = true, false, false, false, "stopped"
        Windmill.bumpNetworkRevision()
        return true
    elseif action == "reset" then
        if not p.emergency then return false, "E-STOP is not active." end
        p.emergency = false
        if not p.palletId then
            p.status = "idle"
        elseif p.targetSheets > 0 and p.goodSheets >= p.targetSheets then
            p.status = "pass_complete"
        elseif p.feedRemaining <= 0 and p.goodSheets < p.targetSheets then
            p.status = "stock_shortage"
        elseif p.proofApproved then
            p.status = "approved"
        else
            p.status = Windmill.setupComplete(state) and "proof" or "setup"
        end
        Windmill.bumpNetworkRevision()
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
    Windmill.bumpNetworkRevision()
    return true, p
end

local function setupAverage(p)
    local total = 0
    for _, task in ipairs(setupTasks) do total = total + (p.setup[task] or 0) end
    return total / #setupTasks
end

function Windmill.takeProof(state)
    local p, job, pallet = Windmill.current(state)
    local ready, reason = Windmill.proofReadiness(state)
    if not ready then return false, reason end
    local plate = Plates.ensureJob(job)[p.colorIndex]
    local machine = MachineFleet.installed(state, "heidelberg_10x15")
    local condition = machine and MachineFleet.condition(machine) / 100 or 0
    local quality = clamp(setupAverage(p) * 0.72 + (plate and plate.quality or 0) * 0.18
        + condition * 0.10 - math.max(0, p.speed - 3000) / 25000, 0, 1)
    p.proofQuality, p.proofApproved, p.artworkVerified, p.status = quality, false, false, "proof"
    p.counter, p.spoilage = p.counter + 1, p.spoilage + 1
    p.feedRemaining = math.max(0, p.feedRemaining - 1)
    pallet.press.spoilage = (pallet.press.spoilage or 0) + 1
    local totals = actual(job)
    totals.proofs = (totals.proofs or 0) + 1
    totals.impressions = (totals.impressions or 0) + 1
    totals.spoilage = (totals.spoilage or 0) + 1
    Windmill.bumpNetworkRevision()
    return true, quality
end

function Windmill.verifyArtwork(state)
    local p, job = Windmill.current(state)
    if not job or p.status ~= "proof" or not p.proofQuality then
        return false, "Pull a proof before matching it to the client artwork."
    end
    p.artworkVerified = true
    Windmill.bumpNetworkRevision()
    return true, job.artwork or { key = job.artworkKey }
end

function Windmill.approveProof(state)
    local p = Windmill.ensure(state)
    if p.status ~= "proof" or (p.proofQuality or 0) < 0.82 then
        return false, "The proof must score at least 82% before approval."
    end
    if not p.artworkVerified then
        return false, "Compare the proof to the client file and verify the artwork first."
    end
    p.proofApproved, p.status = true, "approved"
    Windmill.bumpNetworkRevision()
    return true, p
end

function Windmill.startProduction(state)
    local p = Windmill.ensure(state)
    if p.status ~= "approved" or not p.proofApproved then
        return false, "Approve a proof before starting or resuming production."
    end
    if p.emergency or not p.motor or not p.feeder or not p.impression then
        return false, "Production requires motor, feeder, and impression on."
    end
    local operable, reason = MachineFleet.canOperate(state, "heidelberg_10x15")
    if not operable then return false, reason end
    p.status = "production"
    Windmill.bumpNetworkRevision()
    return true, p
end

function Windmill.stopProduction(state)
    local p = Windmill.ensure(state)
    if p.status ~= "production" then return false end
    p.status, p.feeder, p.impression = "approved", false, false
    Windmill.bumpNetworkRevision()
    return true, p
end

function Windmill.update(dt, state)
    local platesChanged = Plates.update(state)
    if platesChanged then Windmill.bumpNetworkRevision() end
    local p, job, pallet = Windmill.current(state)
    p.animationClock = p.animationClock + math.max(0, dt)
    if p.status ~= "production" or not job or not pallet then
        return platesChanged, platesChanged
    end
    if p.emergency or not p.motor or not p.feeder or not p.impression then
        return platesChanged, platesChanged
    end
    local gameHours = math.max(0, dt) * 24 / Config.businessCalendar.secondsPerDay
    p.sheetAccumulator = p.sheetAccumulator + p.speed * gameHours
    local attempted = math.min(math.floor(p.sheetAccumulator), p.feedRemaining)
    if attempted <= 0 then return platesChanged, platesChanged end
    p.sheetAccumulator = p.sheetAccumulator - attempted
    local machine = MachineFleet.installed(state, "heidelberg_10x15")
    local condition = machine and MachineFleet.condition(machine) / 100 or 0
    local setup = setupAverage(p)
    local mechanicalPenalty, warning = componentPenalty(machine)
    local wasteRate = clamp(0.01 + (1 - setup) * 0.18 + (1 - condition) * 0.12 + mechanicalPenalty
        + math.max(0, p.speed - 3000) / 25000, 0.01, 0.35)
    local needed = math.max(0, p.targetSheets - p.goodSheets)
    local waste = math.floor(attempted * wasteRate + 0.5)
    -- Spoilage may use the customer's explicit overage, but never the sheets
    -- reserved to satisfy the promised good-copy count.
    waste = math.min(waste, math.max(0, p.feedRemaining - needed))
    local good = math.max(0, attempted - waste)
    if good > needed then
        good = needed
        attempted = good + waste
    end
    p.counter, p.goodSheets, p.spoilage = p.counter + attempted, p.goodSheets + good, p.spoilage + waste
    p.feedRemaining = math.max(0, p.feedRemaining - attempted)
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
    Windmill.bumpNetworkRevision()
    if p.goodSheets >= p.targetSheets then
        p.status, p.feeder, p.impression = "pass_complete", false, false
        pallet.press.status = "pass_complete"
        return true, true
    end
    if p.feedRemaining <= 0 then
        p.status, p.feeder, p.impression = "stock_shortage", false, false
        pallet.press.status = "stock_shortage"
        p.warning = "CLIENT STOCK EXHAUSTED"
        return true, true
    end
    return true, platesChanged
end

function Windmill.cleanAndUnload(state)
    local p, job, pallet = Windmill.current(state)
    if p.status ~= "pass_complete" then return false, "Finish the color pass before cleanup." end
    local stock = state.inventory and state.inventory.stock or {}
    if (stock.press_wash or 0) < 1 then return false, "Press wash is required for cleanup." end
    local nextPressStatus = p.colorIndex >= (job.press.colors or 1) and "complete" or "drying"
    local nextPalletStatus = nextPressStatus == "complete" and "printed" or pallet.status
    local placement = placementFor(state)
    local world = { x = placement.x + 78, y = placement.y + 42,
        direction = placement.direction, spawnProgress = 1 }
    local transitioned, errorMessage = PalletState.transition(state, pallet, "press_output", {
        status = nextPalletStatus, world = world,
    })
    if not transitioned then return false, errorMessage end
    stock.press_wash = stock.press_wash - 1
    local totals = actual(job)
    totals.washUnits = (totals.washUnits or 0) + 1
    totals.supplyCost = (totals.supplyCost or 0) + 34 / 6
    pallet.press.completedColors = p.colorIndex
    pallet.press.goodSheets = p.goodSheets
    pallet.press.availableSheets = p.goodSheets
    pallet.press.passHistory[#pallet.press.passHistory + 1] = {
        colorIndex = p.colorIndex,
        inkColor = (job.press.colorSequence or {})[p.colorIndex] or "Black",
        targetSheets = p.targetSheets,
        feedSheets = p.feedStart,
        remainingSheets = p.feedRemaining,
        goodSheets = p.goodSheets,
        spoilage = p.spoilage,
        impressions = p.counter,
        proofQuality = p.proofQuality,
        artworkVerified = p.artworkVerified,
    }
    pallet.finishedSheets = p.goodSheets
    pallet.press.status = nextPressStatus
    if pallet.press.status == "drying" then
        pallet.press.dryUntilHours = BusinessCalendar.absoluteHours(state) + dryingDuration(job)
    else
        pallet.press.dryUntilHours = nil
    end
    if pallet.press.status == "complete" and state.inventory then
        state.inventory.inProcessPallets = math.max(0,
            (state.inventory.inProcessPallets or 0) - 1)
        state.inventory.finishedPallets = (state.inventory.finishedPallets or 0) + 1
    end
    state.message = pallet.press.status == "complete"
        and string.format("%s is fully printed. Move it to the skid wrapper for packaging.", pallet.id)
        or string.format("Color %d is complete on %s. Let it dry before loading the next color.",
            p.colorIndex, pallet.id)
    p.status, p.jobId, p.palletId, p.colorIndex = "idle", nil, nil, nil
    p.setup, p.motor, p.feeder, p.impression, p.proofApproved = {}, false, false, false, false
    p.artworkVerified, p.targetSheets, p.feedStart, p.feedRemaining = false, 0, 0, 0
    Windmill.bumpNetworkRevision()
    return true, pallet
end

function Windmill.releaseOperator(state)
    local p = Windmill.ensure(state)
    local changed = p.motor or p.feeder or p.impression or p.status == "production"
    p.motor, p.feeder, p.impression = false, false, false
    if p.status == "production" then p.status = "approved" end
    if changed then Windmill.bumpNetworkRevision() end
    return changed, p
end

function Windmill.releaseAllOperators(state)
    local units = MachineFleet.installedUnits(state, "heidelberg_10x15")
    if #units == 0 then return Windmill.releaseOperator(state) end
    local changed = false
    for _, unit in ipairs(units) do
        MachineFleet.withUnit(state, unit.id, function()
            if Windmill.releaseOperator(state) then changed = true end
        end)
    end
    return changed
end

function Windmill.canExit(state) return true end

function Windmill.updateAll(dt, state)
    local changed, durable = false, false
    local units = MachineFleet.installedUnits(state, "heidelberg_10x15")
    if #units == 0 then return Windmill.update(dt, state) end
    for _, unit in ipairs(units) do
        MachineFleet.withUnit(state, unit.id, function()
            local unitChanged, unitDurable = Windmill.update(dt, state)
            changed = changed or unitChanged
            durable = durable or unitDurable
        end)
    end
    return changed, durable
end

return Windmill
