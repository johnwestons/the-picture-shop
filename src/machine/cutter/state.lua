-- Per-cutter state, safety helpers, reset, and paper loading.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.Machine = {
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

    Context.UINT32_MODULUS = 4294967296

    function Context.bumpRevision()
        Context.Machine.runtimeRevision = (math.floor(tonumber(Context.Machine.runtimeRevision) or 0) + 1)
            % Context.UINT32_MODULUS
    end

    function Context.message(state, text)
        if state then state.message = text end
    end

    function Context.safeResumeStep(step)
        if step == "blocked" and Context.Machine._blockedResume then return Context.Machine._blockedResume end
        if step == "resetting" and Context.Machine._resetResume then return Context.Machine._resetResume end
        if step == "repeat_ready" then return "repeat_ready" end
        if step == "finished" or step == "idle" then return "idle" end
        if step == "cut_complete" or step == "lift_returning" or step == "unloading" then
            return "cut_complete"
        end
        return Context.Machine.paper and "loaded" or "idle"
    end

    function Context.enterBlocked(state, text, resumeStep)
        Context.Machine._blockedResume = resumeStep or Context.safeResumeStep(Context.Machine.step)
        Context.Machine.step, Context.Machine.progress = "blocked", 0
        Context.message(state, text)
    end

    function Context.availablePapers(state)
        return Context.PalletState.cutterCandidates(state, Context.Config.cutterPlacement.palletInputZoneRadius)
    end

    function Context.makeLegacyPaper()
        return Context.PaperWork.createStockPaper()
    end

    function Context.syncProgram()
        if Context.Machine.paper then Context.Machine.programIndex = math.min(Context.Machine.paper.activeCut, #Context.Machine.paper.cuts) end
    end

    function Context.ensureLiftProgress(pallet)
        if type(pallet) ~= "table" then return end
        pallet.completedLifts = math.max(0, math.floor(pallet.completedLifts or 0))
        pallet.remainingSheets = math.max(0, math.floor(pallet.remainingSheets or pallet.initialSheets or 0))
        pallet.finishedSheets = math.max(0, math.floor(pallet.finishedSheets or 0))
        pallet.activeLift = math.min(pallet.requiredLifts or 1, pallet.completedLifts + 1)
        pallet.lastLiftSheets = math.max(0, math.floor(pallet.lastLiftSheets or 0))
        pallet.programVerified = pallet.programVerified == true or pallet.completedLifts > 0
        pallet.awaitingPalletReturn = pallet.awaitingPalletReturn == true
    end

    function Context.completeLift(state)
        local pallet = Context.Machine.pallet
        if Context.Machine.legacyPaper or not pallet then
            Context.Machine.step = "cut_complete"
            return
        end
        Context.ensureLiftProgress(pallet)
        if pallet.remainingSheets <= 0 or pallet.completedLifts >= pallet.requiredLifts then
            Context.Machine.step = "cut_complete"
            pallet.awaitingPalletReturn = true
            Context.message(state, "All quoted lifts are complete. Press TO PALLET to return this lift.")
            return
        end
        local sheets = math.min(Context.Jobs.LIFT_CAPACITY, pallet.remainingSheets)
        pallet.remainingSheets = pallet.remainingSheets - sheets
        pallet.finishedSheets = pallet.finishedSheets + sheets
        pallet.completedLifts = pallet.completedLifts + 1
        pallet.lastLiftSheets = sheets
        pallet.lastLiftSpoiled = false
        pallet.programVerified = true
        pallet.awaitingPalletReturn = true
        pallet.activeLift = math.min(pallet.requiredLifts, pallet.completedLifts + 1)
        Context.Machine.step = "cut_complete"
        if pallet.remainingSheets == 0 or pallet.completedLifts >= pallet.requiredLifts then
            Context.message(state, string.format("Lift %d/%d complete (%d sheets). All paper is ready to unload.",
                pallet.completedLifts, pallet.requiredLifts, sheets))
        else
            Context.message(state, string.format(
                "Lift %d/%d cut (%d sheets). Press TO PALLET before loading lift %d.",
                pallet.completedLifts, pallet.requiredLifts, sheets, pallet.activeLift))
        end
    end

    function Context.Machine.reset(state)
        Context.Machine.step, Context.Machine.progress, Context.Machine.loaded = "idle", 0, false
        Context.Machine.clamp, Context.Machine.clampProgress, Context.Machine.bladeProgress = false, 0, 0
        Context.Machine.leftDown, Context.Machine.rightDown = false, false
        Context.Machine.barrierClear, Context.Machine.emergencyStopped = true, false
        Context.Machine.gauge, Context.Machine.programIndex, Context.Machine.savedGauge, Context.Machine.autoCycle = 0, 1, nil, {}
        Context.Machine.paper, Context.Machine.pallet, Context.Machine.job = nil, nil, nil
        Context.Machine.legacyPaper, Context.Machine.paperTravel, Context.Machine.pendingOutput = false, 0, nil
        Context.Machine._leftAt, Context.Machine._rightAt = -math.huge, -math.huge
        Context.Machine._resetResume, Context.Machine._blockedResume = nil, nil
        Context.bumpRevision()
        Context.message(state, "Cutter ready. Select a pallet paper batch and load it.")
    end

    function Context.statePallet(state, palletId)
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
    function Context.Machine.open(state)
        if Context.Machine.legacyPaper and Context.Machine.paper then return true end
        if Context.Machine.pallet and Context.statePallet(state, Context.Machine.pallet.id) == Context.Machine.pallet then
            return true
        end
        Context.Machine.reset(state)
        for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
            for _, pallet in ipairs(job.pallets or {}) do
                local owner = pallet.cutterMachineId or "MCH-0001"
                if pallet.location == "at_cutter" and owner == (Context.machineId or "MCH-0001") then
                    return Context.Machine.load(state, pallet.id)
                end
            end
        end
        return true
    end

    function Context.Machine.availablePapers(state) return Context.availablePapers(state) end

    function Context.Machine.setOutputResolver(resolver)
        Context.Machine.outputResolver = type(resolver) == "function" and resolver or nil
    end

    function Context.Machine.load(state, palletId)
        if Context.Machine.step ~= "idle" and Context.Machine.step ~= "finished" then return false end
        local operable, machineOrError = Context.MachineFleet.canOperate(state, "polar_115")
        if not operable then Context.message(state, machineOrError); return false end
        local candidates = Context.availablePapers(state)
        local selected
        if palletId ~= "__generic_stock__" then
            if palletId then
                for _, candidate in ipairs(candidates) do
                    if candidate.pallet.id == palletId then selected = candidate; break end
                end
                if not selected then
                    Context.message(state, "That pallet is no longer available in the cutter load zone.")
                    return false
                end
            else
                selected = candidates[1]
            end
        end
        if selected then
            local wasWarehouse = selected.pallet.location == "warehouse"
            if wasWarehouse then
                local transitioned, transitionError = Context.PalletState.transition(state, selected.pallet, "at_cutter", {
                    status = "in_process",
                    cutterRadius = Context.Config.cutterPlacement.palletInputZoneRadius,
                })
                if not transitioned then Context.message(state, transitionError); return false end
            end
            Context.Machine.paper, Context.Machine.pallet, Context.Machine.job = selected.paper, selected.pallet, selected.job
            Context.Machine.legacyPaper = false
            Context.ensureLiftProgress(selected.pallet)
            if wasWarehouse and state and state.inventory then
                state.inventory.rawPallets = math.max(0, (state.inventory.rawPallets or 0) - 1)
                state.inventory.inProcessPallets = (state.inventory.inProcessPallets or 0) + 1
            end
            if selected.paper.status == "complete" then
                if not selected.paper.offSpec and selected.pallet.completedLifts == 0
                    and selected.pallet.remainingSheets > 0
                then
                    Context.completeLift(state)
                end
                local resumeStep = selected.pallet.awaitingPalletReturn and "cut_complete"
                    or (selected.pallet.remainingSheets > 0 and "repeat_ready" or "cut_complete")
                Context.Machine.loaded, Context.Machine.step, Context.Machine.progress, Context.Machine.paperTravel =
                    resumeStep ~= "repeat_ready", resumeStep, 0,
                    resumeStep == "repeat_ready" and 0 or 1
                Context.syncProgram()
                Context.bumpRevision()
                Context.message(state, resumeStep == "repeat_ready"
                    and string.format("Verified program restored. Press T to run lift %d/%d.",
                        selected.pallet.activeLift, selected.pallet.requiredLifts)
                    or "Finished paper is still at the cutter. Press U to place its pallet in a clear output zone.")
                return true
            end
        elseif Context.PalletState.hasUnfinishedCustomerPaper(state) then
            Context.message(state, "Stage an unfinished pallet on clear floor beside the cutter before loading.")
            return false
        elseif state and state.inventory and Context.Procurement.paperAvailable(state) > 0 then
            Context.Machine.paper, Context.Machine.pallet, Context.Machine.job = Context.makeLegacyPaper()
            Context.Machine.legacyPaper = true
        else
            Context.message(state, "No eligible paper is in the warehouse or generic stock inventory.")
            return false
        end
        Context.Machine.loaded, Context.Machine.step, Context.Machine.progress, Context.Machine.paperTravel = true, "loading", 0, 0
        Context.Machine.gauge = 0
        Context.syncProgram()
        Context.bumpRevision()
        Context.message(state, "Paper batch " .. Context.Machine.paper.id .. " is moving onto the cutting bed.")
        return true
    end
end

return Component
