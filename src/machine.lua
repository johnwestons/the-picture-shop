local PaperWork = require("src.paper_work")
local Config = require("src.config")
local Jobs = require("src.jobs")
local PalletState = require("src.pallet_state")
local Procurement = require("src.procurement")
local MachineFleet = require("src.machine_fleet")

local Machine = {
    step = "idle", progress = 0, loaded = false, clamp = false,
    clampProgress = 0, bladeProgress = 0, barrierClear = true,
    emergencyStopped = false, leftDown = false, rightDown = false,
    _leftAt = -math.huge, _rightAt = -math.huge, _clock = 0,
    simultaneity = 0.30, cycleTime = 1.25, transferTime = 0.45,
    repeatCycleTime = 1.0,
    gauge = 0, programIndex = 1, savedGauge = nil, autoCycle = {},
    paper = nil, pallet = nil, job = nil, legacyPaper = false, paperTravel = 0,
    pendingOutput = nil, outputResolver = nil,
    runtimeRevision = 0, _resetResume = nil, _blockedResume = nil,
    multiplayerSingleControl = false,
}

local UINT32_MODULUS = 4294967296

local function bumpRevision()
    Machine.runtimeRevision = (math.floor(tonumber(Machine.runtimeRevision) or 0) + 1)
        % UINT32_MODULUS
end

local function message(state, text)
    if state then state.message = text end
end

local function safeResumeStep(step)
    if step == "blocked" and Machine._blockedResume then return Machine._blockedResume end
    if step == "resetting" and Machine._resetResume then return Machine._resetResume end
    if step == "repeat_ready" then return "repeat_ready" end
    if step == "finished" or step == "idle" then return "idle" end
    if step == "cut_complete" or step == "lift_returning" or step == "unloading" then
        return "cut_complete"
    end
    return Machine.paper and "loaded" or "idle"
end

local function enterBlocked(state, text, resumeStep)
    Machine._blockedResume = resumeStep or safeResumeStep(Machine.step)
    Machine.step, Machine.progress = "blocked", 0
    message(state, text)
end

local function availablePapers(state)
    return PalletState.cutterCandidates(state, Config.cutterPlacement.palletInputZoneRadius)
end

local function makeLegacyPaper()
    local job = { id = "STOCK", sourceSize = { width = 13, height = 10 }, finishedSize = { width = 12, height = 9 } }
    local pallet = { id = "STOCK-P01" }
    return PaperWork.create(job, pallet, "easy", 1), pallet, job
end

local function syncProgram()
    if Machine.paper then Machine.programIndex = math.min(Machine.paper.activeCut, #Machine.paper.cuts) end
end

local function ensureLiftProgress(pallet)
    if type(pallet) ~= "table" then return end
    pallet.completedLifts = math.max(0, math.floor(pallet.completedLifts or 0))
    pallet.remainingSheets = math.max(0, math.floor(pallet.remainingSheets or pallet.initialSheets or 0))
    pallet.finishedSheets = math.max(0, math.floor(pallet.finishedSheets or 0))
    pallet.activeLift = math.min(pallet.requiredLifts or 1, pallet.completedLifts + 1)
    pallet.lastLiftSheets = math.max(0, math.floor(pallet.lastLiftSheets or 0))
    pallet.programVerified = pallet.programVerified == true or pallet.completedLifts > 0
    pallet.awaitingPalletReturn = pallet.awaitingPalletReturn == true
end

local function completeLift(state)
    local pallet = Machine.pallet
    if Machine.legacyPaper or not pallet then
        Machine.step = "cut_complete"
        return
    end
    ensureLiftProgress(pallet)
    if pallet.remainingSheets <= 0 or pallet.completedLifts >= pallet.requiredLifts then
        Machine.step = "cut_complete"
        pallet.awaitingPalletReturn = true
        message(state, "All quoted lifts are complete. Press TO PALLET to return this lift.")
        return
    end
    local sheets = math.min(Jobs.LIFT_CAPACITY, pallet.remainingSheets)
    pallet.remainingSheets = pallet.remainingSheets - sheets
    pallet.finishedSheets = pallet.finishedSheets + sheets
    pallet.completedLifts = pallet.completedLifts + 1
    pallet.lastLiftSheets = sheets
    pallet.programVerified = true
    pallet.awaitingPalletReturn = true
    pallet.activeLift = math.min(pallet.requiredLifts, pallet.completedLifts + 1)
    Machine.step = "cut_complete"
    if pallet.remainingSheets == 0 or pallet.completedLifts >= pallet.requiredLifts then
        message(state, string.format("Lift %d/%d complete (%d sheets). All paper is ready to unload.",
            pallet.completedLifts, pallet.requiredLifts, sheets))
    else
        message(state, string.format(
            "Lift %d/%d cut (%d sheets). Press TO PALLET before loading lift %d.",
            pallet.completedLifts, pallet.requiredLifts, sheets, pallet.activeLift))
    end
end

function Machine.reset(state)
    Machine.step, Machine.progress, Machine.loaded = "idle", 0, false
    Machine.clamp, Machine.clampProgress, Machine.bladeProgress = false, 0, 0
    Machine.leftDown, Machine.rightDown = false, false
    Machine.barrierClear, Machine.emergencyStopped = true, false
    Machine.gauge, Machine.programIndex, Machine.savedGauge, Machine.autoCycle = 0, 1, nil, {}
    Machine.paper, Machine.pallet, Machine.job = nil, nil, nil
    Machine.legacyPaper, Machine.paperTravel, Machine.pendingOutput = false, 0, nil
    Machine._leftAt, Machine._rightAt = -math.huge, -math.huge
    Machine._resetResume, Machine._blockedResume = nil, nil
    bumpRevision()
    message(state, "Cutter ready. Select a pallet paper batch and load it.")
end

local function statePallet(state, palletId)
    if type(palletId) ~= "string" then return nil end
    for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.id == palletId then return pallet end
        end
    end
    return nil
end

-- Opening the cutter is deliberately non-destructive. A live singleton that
-- still points into this save is preserved; a fresh process rebuilds a safe
-- resumable runtime from the pallet durably parked at the cutter.
function Machine.open(state)
    if Machine.legacyPaper and Machine.paper then return true end
    if Machine.pallet and statePallet(state, Machine.pallet.id) == Machine.pallet then
        return true
    end
    Machine.reset(state)
    for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.location == "at_cutter" then
                return Machine.load(state, pallet.id)
            end
        end
    end
    return true
end

function Machine.availablePapers(state) return availablePapers(state) end

function Machine.setOutputResolver(resolver)
    Machine.outputResolver = type(resolver) == "function" and resolver or nil
end

function Machine.load(state, palletId)
    if Machine.step ~= "idle" and Machine.step ~= "finished" then return false end
    local operable, machineOrError = MachineFleet.canOperate(state, "polar_115")
    if not operable then message(state, machineOrError); return false end
    local candidates = availablePapers(state)
    local selected
    if palletId ~= "__generic_stock__" then
        if palletId then
            for _, candidate in ipairs(candidates) do
                if candidate.pallet.id == palletId then selected = candidate; break end
            end
            if not selected then
                message(state, "That pallet is no longer available in the cutter load zone.")
                return false
            end
        else
            selected = candidates[1]
        end
    end
    if selected then
        local wasWarehouse = selected.pallet.location == "warehouse"
        if wasWarehouse then
            local transitioned, transitionError = PalletState.transition(state, selected.pallet, "at_cutter", {
                status = "in_process",
                cutterRadius = Config.cutterPlacement.palletInputZoneRadius,
            })
            if not transitioned then message(state, transitionError); return false end
        end
        Machine.paper, Machine.pallet, Machine.job = selected.paper, selected.pallet, selected.job
        Machine.legacyPaper = false
        ensureLiftProgress(selected.pallet)
        if wasWarehouse and state and state.inventory then
            state.inventory.rawPallets = math.max(0, (state.inventory.rawPallets or 0) - 1)
            state.inventory.inProcessPallets = (state.inventory.inProcessPallets or 0) + 1
        end
        if selected.paper.status == "complete" then
            if selected.pallet.completedLifts == 0 and selected.pallet.remainingSheets > 0 then
                completeLift(state)
            end
            local resumeStep = selected.pallet.awaitingPalletReturn and "cut_complete"
                or (selected.pallet.remainingSheets > 0 and "repeat_ready" or "cut_complete")
            Machine.loaded, Machine.step, Machine.progress, Machine.paperTravel =
                resumeStep ~= "repeat_ready", resumeStep, 0,
                resumeStep == "repeat_ready" and 0 or 1
            syncProgram()
            bumpRevision()
            message(state, resumeStep == "repeat_ready"
                and string.format("Verified program restored. Press T to run lift %d/%d.",
                    selected.pallet.activeLift, selected.pallet.requiredLifts)
                or "Finished paper is still at the cutter. Press U to place its pallet in a clear output zone.")
            return true
        end
    elseif PalletState.hasUnfinishedCustomerPaper(state) then
        message(state, "Stage an unfinished pallet on clear floor beside the cutter before loading.")
        return false
    elseif state and state.inventory and Procurement.paperAvailable(state) > 0 then
        Machine.paper, Machine.pallet, Machine.job = makeLegacyPaper()
        Machine.legacyPaper = true
    else
        message(state, "No eligible paper is in the warehouse or generic stock inventory.")
        return false
    end
    Machine.loaded, Machine.step, Machine.progress, Machine.paperTravel = true, "loading", 0, 0
    Machine.gauge = 0
    syncProgram()
    bumpRevision()
    message(state, "Paper batch " .. Machine.paper.id .. " is moving onto the cutting bed.")
    return true
end

function Machine.selectProgram(index, state)
    if not Machine.paper or type(index) ~= "number" then return false end
    index = math.max(1, math.min(#Machine.paper.cuts, math.floor(index)))
    Machine.programIndex = index
    Machine.autoCycle[index] = 1
    local cut = Machine.paper.cuts[index]
    message(state, string.format("Program %d: trim %s margin %.2f in.", index, cut.edge, cut.margin))
    bumpRevision()
    return true
end

function Machine.adjustGauge(amount, state)
    if not Machine.paper or Machine.clamp or Machine.step == "cutting" then return false end
    Machine.gauge = math.max(0, math.min(25,
        math.floor((Machine.gauge + amount) * 100 + 0.5) / 100))
    message(state, string.format("Backgauge set to %.2f in.", Machine.gauge))
    bumpRevision()
    return true
end

function Machine.setGauge(value, state)
    value = tonumber(value)
    if not Machine.paper or Machine.clamp or Machine.step == "cutting" then return false end
    if not value or value < 0 or value > 25 then
        message(state, "Enter a backgauge position from 0.00 to 25.00 inches.")
        return false
    end
    Machine.gauge = math.floor(value * 100 + 0.5) / 100
    message(state, string.format("Backgauge typed in at %.2f in.", Machine.gauge))
    bumpRevision()
    return true
end

local function measurements(state, cutNumber, create)
    if type(state) ~= "table" then return nil end
    if type(state.cutterMemory) ~= "table" then
        if not create then return nil end
        state.cutterMemory = {}
    end
    local key = tostring(math.max(1, math.min(4, math.floor(cutNumber or 1))))
    if type(state.cutterMemory[key]) ~= "table" then
        if not create then return nil end
        state.cutterMemory[key] = {}
    end
    return state.cutterMemory[key]
end

function Machine.savedMeasurements(state, cutNumber)
    local source, result = measurements(state, cutNumber or Machine.programIndex, false), {}
    for index, value in ipairs(source or {}) do result[index] = value end
    return result
end

function Machine.autoGauge(state)
    if not Machine.paper or Machine.clamp or Machine.step == "cutting" then return false end
    local cutNumber = Machine.programIndex
    local saved = measurements(state, cutNumber, false)
    if not saved or #saved == 0 then
        message(state, string.format(
            "AUTO SET P%d has no player-saved measurement. Type a gauge and press SAVE first.", cutNumber))
        return false
    end
    local cursor = math.max(1, math.min(#saved, Machine.autoCycle[cutNumber] or 1))
    Machine.gauge = saved[cursor]
    Machine.savedGauge = Machine.gauge
    Machine.autoCycle[cutNumber] = cursor % #saved + 1
    message(state, string.format("AUTO SET P%d recalled %.2f in. (%d of %d saved).",
        cutNumber, Machine.gauge, cursor, #saved))
    bumpRevision()
    return true
end

function Machine.saveGauge(state)
    if not Machine.paper or Machine.clamp or Machine.step == "cutting" then return false end
    Machine.savedGauge = Machine.gauge
    local cutNumber = Machine.programIndex
    local saved = measurements(state, cutNumber, true)
    for index = #saved, 1, -1 do
        if math.abs(saved[index] - Machine.gauge) < 0.001 then table.remove(saved, index) end
    end
    table.insert(saved, 1, Machine.gauge)
    while #saved > 3 do table.remove(saved) end
    Machine.autoCycle[cutNumber] = 1
    message(state, string.format("Saved P%d gauge %.2f in. (%d of 3 memory slots used).",
        cutNumber, Machine.savedGauge, #saved))
    bumpRevision()
    return true
end

function Machine.recallGauge(state)
    if Machine.clamp then return false end
    local saved = measurements(state, Machine.programIndex, false)
    if not saved or #saved == 0 then
        message(state, string.format("No saved measurement exists for P%d.", Machine.programIndex))
        return false
    end
    Machine.gauge, Machine.savedGauge = saved[1], saved[1]
    message(state, string.format("Recalled newest P%d gauge %.2f in.", Machine.programIndex, Machine.gauge))
    bumpRevision()
    return true
end

function Machine.rotate(state)
    if not Machine.paper or Machine.clamp then return false end
    if Machine.step ~= "loaded" and Machine.step ~= "positioned" then return false end
    if not PaperWork.rotate(Machine.paper) then return false end
    Machine.step, Machine.paperTravel = "loaded", 0.35
    message(state, string.format("Paper rotated counter-clockwise into the %s cutting position. Reposition it.",
        PaperWork.currentCut(Machine.paper).edge))
    bumpRevision()
    return true
end

function Machine.position(state)
    if Machine.step ~= "loaded" then return false end
    local cut = PaperWork.currentCut(Machine.paper)
    if not cut or Machine.programIndex ~= Machine.paper.activeCut then
        message(state, "Select the highlighted next cut program before positioning.")
        return false
    elseif Machine.paper.orientation ~= cut.orientation then
        message(state, string.format("Rotate the paper to %d degrees first.", cut.orientation))
        return false
    elseif not PaperWork.gaugeMatches(Machine.paper, Machine.gauge) then
        message(state, string.format("Backgauge mismatch: this cut requires %.2f in.", cut.gauge))
        return false
    end
    Machine.step, Machine.progress = "positioning", 0
    message(state, "Pushing the paper stack against the programmed backgauge...")
    bumpRevision()
    return true
end

function Machine.toggleClamp(state)
    if Machine.step ~= "positioned" and Machine.step ~= "clamped" then return false end
    Machine.clamp = not Machine.clamp
    Machine.step = Machine.clamp and "clamped" or "positioned"
    message(state, Machine.clamp
        and (Machine.multiplayerSingleControl
            and "Clamp engaged. Press either cut control."
            or "Clamp engaged. Hold both cut controls.")
        or "Clamp released.")
    bumpRevision()
    return true
end

function Machine.setClamp(down, state)
    if type(down) ~= "boolean" then return false end
    if Machine.clamp == down then return true end
    return Machine.toggleClamp(state)
end

function Machine.setBarrier(clear, state)
    Machine.barrierClear = clear ~= false
    if not Machine.barrierClear and (Machine.step == "cutting" or Machine.step == "armed") then
        enterBlocked(state, "Safety barrier interrupted. Clear the cutter and reset.", "loaded")
    end
    bumpRevision()
    return true
end

function Machine.emergencyStop(state)
    local resumeStep = safeResumeStep(Machine.step)
    Machine.emergencyStopped = true
    enterBlocked(state, "Emergency stop active. Reset the cutter before continuing.", resumeStep)
    bumpRevision()
    return true
end

local function tryCut(state)
    if Machine.step ~= "clamped" or not Machine.loaded then return false end
    local operable, machineOrError = MachineFleet.canOperate(state, "polar_115")
    if not operable then message(state, machineOrError); return false end
    if not Machine.barrierClear or Machine.emergencyStopped then
        enterBlocked(state, "Cut blocked: check the safety barrier and emergency stop.", "loaded")
        return false
    end
    local cut = PaperWork.currentCut(Machine.paper)
    if Machine.programIndex ~= Machine.paper.activeCut or not cut
        or Machine.paper.orientation ~= cut.orientation
        or not PaperWork.gaugeMatches(Machine.paper, Machine.gauge)
    then
        message(state, "Cut blocked: program, rotation, and backgauge must match the work order.")
        return false
    end
    Machine.step, Machine.progress = "armed", 0
    message(state, "Cut controls validated. Blade cycle starting.")
    bumpRevision()
    return true
end

function Machine.guardedCut(state)
    return tryCut(state)
end

function Machine.setMultiplayerSingleControl(enabled)
    Machine.multiplayerSingleControl = enabled == true
end

function Machine.resetSafety(state)
    if Machine.step ~= "blocked" and Machine.step ~= "finished" then return false end
    Machine._resetResume = Machine.step == "blocked"
        and (Machine._blockedResume or safeResumeStep(Machine.step)) or "idle"
    Machine.emergencyStopped, Machine.barrierClear = false, true
    Machine.clamp, Machine.leftDown, Machine.rightDown = false, false, false
    Machine.step, Machine.progress, Machine.bladeProgress = "resetting", 0, 0
    message(state, "Resetting safety controls...")
    bumpRevision()
    return true
end

function Machine.releaseOperator(state)
    local changed = Machine.leftDown or Machine.rightDown
    Machine.leftDown, Machine.rightDown = false, false
    Machine._leftAt, Machine._rightAt = -math.huge, -math.huge
    if Machine.step == "clamped" then
        Machine.clamp, Machine.step = false, "positioned"
        changed = true
        message(state, "Cutter controls released safely; the clamp was raised.")
    end
    if changed then bumpRevision() end
    return changed
end

function Machine.unload(state)
    if not Machine.paper or Machine.paper.status ~= "complete" or Machine.step ~= "cut_complete" then return false end
    if Machine.pallet and (Machine.pallet.remainingSheets or 0) > 0 then
        Machine.step, Machine.progress = "lift_returning", 0
        message(state, "Returning the completed lift to its pallet...")
        bumpRevision()
        return true
    end
    if Machine.pallet then
        if not Machine.outputResolver then
            message(state, "Cutter output safety is unavailable. Return to the warehouse and reopen the console.")
            return false
        end
        local output, outputError = Machine.outputResolver(state, Machine.pallet)
        if not output then message(state, outputError); return false end
        Machine.pendingOutput = output
    end
    Machine.step, Machine.progress = "unloading", 0
    message(state, "Pulling finished paper from the bed and returning it to its pallet.")
    bumpRevision()
    return true
end

function Machine.repeatLift(state)
    if Machine.step ~= "repeat_ready" or not Machine.pallet or not Machine.pallet.programVerified then return false end
    if (Machine.pallet.remainingSheets or 0) <= 0 then
        Machine.step = "cut_complete"
        return false
    end
    if not PaperWork.resetForNextLift(Machine.paper) then return false end
    Machine.programIndex, Machine.gauge = 1, 0
    Machine.autoCycle = {}
    Machine.loaded, Machine.step, Machine.progress, Machine.paperTravel = true, "loading", 0, 0
    message(state, string.format("Loading lift %d/%d. Make every programmed cut again.",
        Machine.pallet.activeLift, Machine.pallet.requiredLifts))
    bumpRevision()
    return true
end

function Machine.keypressed(key, state)
    key = string.lower(key)
    if key == "l" then return Machine.load(state)
    elseif key == "p" then return Machine.position(state)
    elseif key == "q" then return Machine.rotate(state)
    elseif key == "space" then return Machine.toggleClamp(state)
    elseif key == "g" then return Machine.autoGauge(state)
    elseif key == "m" then return Machine.saveGauge(state)
    elseif key == "v" then return Machine.recallGauge(state)
    elseif key == "u" then return Machine.unload(state)
    elseif key == "t" then return Machine.repeatLift(state)
    elseif key == "[" then return Machine.selectProgram(Machine.programIndex - 1, state)
    elseif key == "]" then return Machine.selectProgram(Machine.programIndex + 1, state)
    elseif key == "b" then Machine.setBarrier(not Machine.barrierClear, state); return true
    elseif key == "x" then Machine.emergencyStop(state); return true
    elseif key == "r" then
        return Machine.resetSafety(state)
    end
    if Machine.step ~= "clamped" then return false end
    if Machine.multiplayerSingleControl and (key == "j" or key == "k") then
        tryCut(state)
        return true
    end
    if key == "j" then Machine.leftDown, Machine._leftAt = true, Machine._clock
    elseif key == "k" then Machine.rightDown, Machine._rightAt = true, Machine._clock
    else return false end
    if Machine.leftDown and Machine.rightDown
        and math.abs(Machine._leftAt - Machine._rightAt) <= Machine.simultaneity
    then tryCut(state) end
    return true
end

function Machine.keyreleased(key)
    key = string.lower(key)
    if key == "j" then Machine.leftDown = false; return true
    elseif key == "k" then Machine.rightDown = false; return true end
    return false
end

local function finishCut(state)
    local succeeded, result = PaperWork.applyCut(Machine.paper, Machine.gauge)
    if not succeeded then enterBlocked(state, result, "loaded"); return false end
    MachineFleet.recordUse(state, "polar_115", 1)
    if state and state.shopProgress then
        state.shopProgress.completedCuts = (state.shopProgress.completedCuts or 0) + 1
    end
    Machine.clamp, Machine.leftDown, Machine.rightDown = false, false, false
    if Machine.paper.status == "complete" then
        completeLift(state)
    else
        Machine.step, Machine.paperTravel = "loaded", 0.35
        syncProgram()
        message(state, "Cut complete. Rotate 90 degrees, set the next gauge, and reposition.")
    end
    return true
end

function Machine.update(dt, state)
    bumpRevision()
    Machine._clock = Machine._clock + dt
    if Machine.step == "clamped" then
        if Machine.leftDown and not Machine.rightDown and Machine._clock - Machine._leftAt > Machine.simultaneity then
            Machine.leftDown = false
        elseif Machine.rightDown and not Machine.leftDown and Machine._clock - Machine._rightAt > Machine.simultaneity then
            Machine.rightDown = false
        end
    end
    local target, speed = Machine.clamp and 1 or 0, dt / 0.25
    if Machine.clampProgress < target then Machine.clampProgress = math.min(target, Machine.clampProgress + speed)
    elseif Machine.clampProgress > target then Machine.clampProgress = math.max(target, Machine.clampProgress - speed) end

    if Machine.step == "loading" or Machine.step == "positioning" or Machine.step == "unloading"
        or Machine.step == "lift_returning"
    then
        Machine.progress = Machine.progress + dt
        Machine.paperTravel = math.min(1, Machine.progress / Machine.transferTime)
        if Machine.progress >= Machine.transferTime then
            if Machine.step == "loading" then
                Machine.step, Machine.paperTravel = "loaded", 0.35
                message(state, "Paper is on the bed. Program the first backgauge position.")
            elseif Machine.step == "positioning" then
                Machine.step, Machine.paperTravel = "positioned", 1
                message(state, "Paper is against the backgauge. Engage the clamp.")
            elseif Machine.step == "lift_returning" then
                if Machine.pallet then Machine.pallet.awaitingPalletReturn = false end
                Machine.loaded, Machine.step, Machine.paperTravel = false, "repeat_ready", 0
                message(state, string.format("Lift returned to pallet. Press RUN NEXT LIFT for lift %d/%d.",
                    Machine.pallet.activeLift, Machine.pallet.requiredLifts))
                return true
            else
                if Machine.legacyPaper and state and state.inventory then
                    local consumed, consumeError = Procurement.consumePaper(state, 1)
                    if not consumed then
                        enterBlocked(state,
                            consumeError or "Production paper is no longer available.", "cut_complete")
                        return false
                    end
                    state.inventory.prints = (state.inventory.prints or 0) + 1
                elseif Machine.pallet then
                    local output = Machine.pendingOutput
                    if not output then
                        enterBlocked(state,
                            "Could not return the pallet: the reserved output zone was lost.",
                            "cut_complete")
                        return false
                    end
                    local world = {}
                    for key, value in pairs(Machine.pallet.world or {}) do world[key] = value end
                    world.x, world.y = output.x, output.y
                    world.direction = output.direction or world.direction or "northwest"
                    world.rotation = output.rotation or world.rotation
                    world.fromX, world.fromY = output.x, output.y
                    world.spawnProgress = 1
                    local transitioned, transitionError = PalletState.transition(state, Machine.pallet, "cutter_output", {
                        status = "cut",
                        world = world,
                    })
                    if not transitioned then
                        enterBlocked(state,
                            "Could not return the pallet: " .. tostring(transitionError),
                            "cut_complete")
                        return false
                    end
                    Machine.pendingOutput = nil
                    if state and state.inventory then
                        -- Printed work remains in process after cutting; it is
                        -- only finished after the final Windmill color pass.
                        if not (Machine.job and Machine.job.press) then
                            state.inventory.inProcessPallets = math.max(0,
                                (state.inventory.inProcessPallets or 0) - 1)
                            state.inventory.finishedPallets = (state.inventory.finishedPallets or 0) + 1
                        end
                    end
                end
                Machine.loaded, Machine.step, Machine.paperTravel = false, "finished", 0
                message(state, Machine.job and Machine.job.press
                    and "Cut client stock returned to its pallet. Stage it beside the Windmill for printing."
                    or "Finished paper returned to its pallet. Reset for the next batch.")
                return true
            end
        end
        return false
    end
    if Machine.step == "armed" then Machine.step, Machine.progress = "cutting", 0 end
    if Machine.step == "cutting" then
        Machine.progress = Machine.progress + dt
        local phase = math.min(1, Machine.progress / Machine.cycleTime)
        Machine.bladeProgress = phase < 0.5 and phase * 2 or (1 - phase) * 2
        if Machine.progress >= Machine.cycleTime then
            Machine.bladeProgress = 0
            return finishCut(state)
        end
    elseif Machine.step == "resetting" then
        Machine.progress = Machine.progress + dt
        if Machine.progress >= 0.35 then
            local resume = Machine._resetResume
            if resume == nil or resume == "idle" then
                Machine.reset(state)
            else
                Machine.step, Machine.progress = resume, 0
                Machine.loaded = resume ~= "repeat_ready" and Machine.paper ~= nil
                Machine.paperTravel = Machine.loaded and 0.35 or 0
                Machine._resetResume, Machine._blockedResume = nil, nil
                message(state, resume == "repeat_ready"
                    and "Safety controls reset. Run the next verified lift when ready."
                    or resume == "cut_complete"
                        and "Safety controls reset. Return the completed lift to its pallet."
                        or "Safety controls reset. Reposition the paper before cutting.")
                bumpRevision()
            end
        end
    end
    return false
end

local function centi(value, minimum, maximum)
    return math.max(minimum or 0, math.min(maximum or 100000,
        math.floor((tonumber(value) or 0) * 100 + 0.5)))
end

local function phasePermille()
    local duration = 1
    if Machine.step == "loading" or Machine.step == "positioning"
        or Machine.step == "unloading" or Machine.step == "lift_returning"
    then
        duration = Machine.transferTime
    elseif Machine.step == "armed" or Machine.step == "cutting" then
        duration = Machine.cycleTime
    elseif Machine.step == "resetting" then
        duration = 0.35
    elseif Machine.step == "finished" then
        return 1000
    else
        return 0
    end
    return math.max(0, math.min(1000,
        math.floor((Machine.progress / math.max(0.001, duration)) * 1000 + 0.5)))
end

function Machine.networkView(state, includeCandidates)
    local memory = {}
    for _, value in ipairs(Machine.savedMeasurements(state, Machine.programIndex)) do
        memory[#memory + 1] = centi(value, 0, 2500)
    end
    local view = {
        runtimeRevision = math.floor(tonumber(Machine.runtimeRevision) or 0),
        step = Machine.step,
        phasePermille = phasePermille(),
        loaded = Machine.loaded == true,
        clamp = Machine.clamp == true,
        clampPermille = math.floor(math.max(0, math.min(1,
            tonumber(Machine.clampProgress) or 0)) * 1000 + 0.5),
        bladePermille = math.floor(math.max(0, math.min(1,
            tonumber(Machine.bladeProgress) or 0)) * 1000 + 0.5),
        barrierClear = Machine.barrierClear == true,
        emergencyStopped = Machine.emergencyStopped == true,
        gaugeCentiInch = centi(Machine.gauge, 0, 2500),
        programIndex = math.max(1, math.min(4, math.floor(Machine.programIndex or 1))),
        memoryCentiInch = memory,
    }
    if Machine.paper and Machine.pallet then
        local selected = Machine.paper.cuts and Machine.paper.cuts[view.programIndex]
        view.paper = {
            palletId = tostring(Machine.pallet.id),
            orientation = math.floor(tonumber(Machine.paper.orientation) or 0),
            status = tostring(Machine.paper.status or "uncut"),
            activeCut = math.max(1, math.min(5, math.floor(Machine.paper.activeCut or 1))),
            cutCount = math.max(1, math.min(4, #(Machine.paper.cuts or {}))),
            activeLift = math.max(1, math.floor(Machine.pallet.activeLift or 1)),
            requiredLifts = math.max(1, math.floor(Machine.pallet.requiredLifts or 1)),
            remainingSheets = math.max(0, math.floor(Machine.pallet.remainingSheets or 0)),
        }
        if selected then
            view.paper.selectedCut = {
                number = math.max(1, math.min(4, math.floor(selected.number or view.programIndex))),
                edge = tostring(selected.edge),
                marginCentiInch = centi(selected.margin, 0, 100000),
                gaugeCentiInch = centi(selected.gauge, 0, 2500),
                orientation = math.floor(tonumber(selected.orientation) or 0),
                active = view.programIndex == view.paper.activeCut,
            }
        end
    elseif includeCandidates then
        local candidates = {}
        for _, candidate in ipairs(availablePapers(state)) do
            candidates[#candidates + 1] = {
                palletId = tostring(candidate.pallet.id),
                distancePixels = math.max(0, math.min(100000, math.floor(
                    math.sqrt(math.max(0, tonumber(candidate.inputDistance)
                        or tonumber(candidate.distance) or 0)) + 0.5))),
            }
            if #candidates >= 3 then break end
        end
        view.candidates = candidates
        if #candidates == 0 and not PalletState.hasUnfinishedCustomerPaper(state) then
            local genericSheets = Procurement.paperAvailable(state)
            if genericSheets > 0 then
                view.genericSheets = math.min(100000, math.floor(genericSheets))
            end
        end
    end
    return view
end

function Machine.applyNetworkView(view)
    if type(view) ~= "table" then return false end
    local revision = tonumber(view.runtimeRevision)
    if not revision or revision < (tonumber(Machine.runtimeRevision) or 0) then return false end
    Machine.runtimeRevision = revision
    Machine.step = tostring(view.step)
    Machine.loaded = view.loaded == true
    Machine.clamp = view.clamp == true
    Machine.clampProgress = (tonumber(view.clampPermille) or 0) / 1000
    Machine.bladeProgress = (tonumber(view.bladePermille) or 0) / 1000
    Machine.barrierClear = view.barrierClear == true
    Machine.emergencyStopped = view.emergencyStopped == true
    Machine.gauge = (tonumber(view.gaugeCentiInch) or 0) / 100
    Machine.programIndex = math.max(1, math.min(4, math.floor(view.programIndex or 1)))
    return true
end

function Machine.resetNetworkReplica()
    Machine.runtimeRevision = -1
    Machine.step, Machine.progress, Machine.loaded = "idle", 0, false
    Machine.clamp, Machine.clampProgress, Machine.bladeProgress = false, 0, 0
    Machine.barrierClear, Machine.emergencyStopped = true, false
    Machine.leftDown, Machine.rightDown = false, false
    Machine.paper, Machine.pallet, Machine.job = nil, nil, nil
    Machine._resetResume, Machine._blockedResume = nil, nil
    return true
end

function Machine.hasActiveBatch()
    return Machine.paper ~= nil
end

function Machine.validateSale(item, cutterLeaseActive)
    if type(item) ~= "table" or item.modelId ~= "polar_115" or item.status ~= "installed" then
        return true
    end
    if cutterLeaseActive == true then
        return false, "Close the active cutter console before listing the cutter for sale."
    end
    if Machine.hasActiveBatch() then
        return false, "Finish or safely unload the cutter batch before listing the cutter for sale."
    end
    return true
end

function Machine.paperTooltip() return PaperWork.tooltip(Machine.paper) end

return Machine
