-- Unloading, repeated lifts, keyboard controls, and replacement stock.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    function Context.Machine.unload(state)
        if not Context.Machine.paper or Context.Machine.paper.status ~= "complete" or Context.Machine.step ~= "cut_complete" then return false end
        if Context.Machine.pallet and Context.Machine.pallet.discardAfterSpoil
            and (Context.Machine.pallet.remainingSheets or 0) == 0
            and (Context.Machine.pallet.finishedSheets or 0) == 0
        then
            local discarded, discardError = Context.PalletState.transition(
                state, Context.Machine.pallet, "none", { status = "spoiled_discarded" })
            if not discarded then Context.message(state, discardError); return false end
            if state and state.inventory then
                state.inventory.inProcessPallets = math.max(0,
                    (state.inventory.inProcessPallets or 0) - 1)
            end
            Context.Machine.loaded, Context.Machine.step, Context.Machine.paperTravel = false, "finished", 0
            Context.message(state, "The ruined skid was discarded. Wait for the customer's replacement skid to arrive.")
            Context.bumpRevision()
            return true
        end
        if Context.Machine.pallet and (Context.Machine.pallet.remainingSheets or 0) > 0 then
            Context.Machine.step, Context.Machine.progress = "lift_returning", 0
            Context.message(state, "Returning the completed lift to its pallet...")
            Context.bumpRevision()
            return true
        end
        if Context.Machine.pallet then
            if not Context.Machine.outputResolver then
                Context.message(state, "Cutter output safety is unavailable. Return to the warehouse and reopen the console.")
                return false
            end
            local output, outputError = Context.Machine.outputResolver(state, Context.Machine.pallet)
            if not output then Context.message(state, outputError); return false end
            Context.Machine.pendingOutput = output
        end
        Context.Machine.step, Context.Machine.progress = "unloading", 0
        Context.message(state, "Pulling finished paper from the bed and returning it to its pallet.")
        Context.bumpRevision()
        return true
    end

    function Context.Machine.repeatLift(state)
        if Context.Machine.step ~= "repeat_ready" or not Context.Machine.pallet
            or (not Context.Machine.pallet.programVerified and not Context.Machine.pallet.lastLiftSpoiled)
        then return false end
        if (Context.Machine.pallet.remainingSheets or 0) <= 0 then
            Context.Machine.step = "cut_complete"
            return false
        end
        if not Context.PaperWork.resetForNextLift(Context.Machine.paper) then return false end
        Context.Machine.programIndex, Context.Machine.gauge = 1, 0
        Context.Machine.autoCycle = {}
        Context.Machine.loaded, Context.Machine.step, Context.Machine.progress, Context.Machine.paperTravel = true, "loading", 0, 0
        Context.message(state, string.format("Loading lift %d/%d. Make every programmed cut again.",
            Context.Machine.pallet.activeLift, Context.Machine.pallet.requiredLifts))
        Context.bumpRevision()
        return true
    end

    function Context.Machine.keypressed(key, state)
        key = string.lower(key)
        if key == "l" then return Context.Machine.load(state)
        elseif key == "p" then return Context.Machine.position(state)
        elseif key == "q" then return Context.Machine.rotate(state)
        elseif key == "space" then return Context.Machine.toggleClamp(state)
        elseif key == "g" then return Context.Machine.autoGauge(state)
        elseif key == "m" then return Context.Machine.saveGauge(state)
        elseif key == "v" then return Context.Machine.recallGauge(state)
        elseif key == "u" then return Context.Machine.unload(state)
        elseif key == "t" then return Context.Machine.repeatLift(state)
        elseif key == "[" then return Context.Machine.selectProgram(Context.Machine.programIndex - 1, state)
        elseif key == "]" then return Context.Machine.selectProgram(Context.Machine.programIndex + 1, state)
        elseif key == "b" then Context.Machine.setBarrier(not Context.Machine.barrierClear, state); return true
        elseif key == "x" then Context.Machine.emergencyStop(state); return true
        elseif key == "r" then
            return Context.Machine.resetSafety(state)
        end
        if Context.Machine.step ~= "clamped" then return false end
        if Context.Machine.multiplayerSingleControl and (key == "j" or key == "k") then
            Context.tryCut(state)
            return true
        end
        if key == "j" then Context.Machine.leftDown, Context.Machine._leftAt = true, Context.Machine._clock
        elseif key == "k" then Context.Machine.rightDown, Context.Machine._rightAt = true, Context.Machine._clock
        else return false end
        if Context.Machine.leftDown and Context.Machine.rightDown
            and math.abs(Context.Machine._leftAt - Context.Machine._rightAt) <= Context.Machine.simultaneity
        then Context.tryCut(state) end
        return true
    end

    function Context.Machine.keyreleased(key)
        key = string.lower(key)
        if key == "j" then Context.Machine.leftDown = false; return true
        elseif key == "k" then Context.Machine.rightDown = false; return true end
        return false
    end

    function Context.stockReplacementCost(job, sheets)
        local stock = job and job.stockSpec or {}
        local rate = stock.grade == "cover" and 0.34 or stock.finish == "gloss" and 0.28 or 0.18
        rate = rate + math.min(0.12, math.max(0, (tonumber(stock.weight) or 0) - 60) * 0.002)
        return math.max(25, math.floor(sheets * rate + 25 + 0.5))
    end

    function Context.replacementPalletId(job)
        local sequence = 1
        local used = {}
        for _, pallet in ipairs(job and job.pallets or {}) do used[pallet.id] = true end
        while used[string.format("%s-R%02d", job.id, sequence)] do sequence = sequence + 1 end
        return string.format("%s-R%02d", job.id, sequence), sequence
    end

    function Context.scheduleReplacementSkid(state, job, source, sheets)
        local palletId, sequence = Context.replacementPalletId(job)
        local sourceRequested = math.max(0, math.floor(tonumber(source.requestedCopies)
            or tonumber(source.initialSheets) or sheets))
        local replacementRequested = math.min(sheets, sourceRequested)
        sourceRequested = sourceRequested - replacementRequested
        source.requestedCopies = sourceRequested > 0 and sourceRequested or nil
        local sourceAvailable = math.max(0,
            (source.initialSheets or 0) - (source.damagedSheets or 0))
        source.spoilageAllowance = math.max(0, sourceAvailable - sourceRequested)
        if job.press then
            if sourceRequested > 0 then
                source.press = source.press or {}
                source.press.requiredGoodSheets = sourceRequested
                source.press.availableSheets = math.min(
                    source.press.availableSheets or sourceAvailable, sourceAvailable)
            else
                -- Nothing from this skid is still needed for the print target.
                -- Any untouched remainder is returned with the ruined lift rather
                -- than creating an unprintable zero-target production pallet.
                source.remainingSheets = 0
                source.press = nil
                source.discardAfterSpoil = true
            end
        end

        local replacement = {
            id = palletId,
            number = #(job.pallets or {}) + 1,
            replacementFor = source.replacementFor or source.id,
            replacementSequence = sequence,
            initialSheets = sheets,
            requestedCopies = math.max(1, replacementRequested),
            spoilageAllowance = math.max(0, sheets - replacementRequested),
            remainingSheets = sheets,
            finishedSheets = 0,
            damagedSheets = 0,
            requiredLifts = math.max(1, math.ceil(sheets / Context.Jobs.LIFT_CAPACITY)),
            completedLifts = 0,
            activeLift = 1,
            lastLiftSheets = 0,
            programVerified = false,
            awaitingPalletReturn = false,
            status = "replacement_in_transit",
            location = "awaiting_delivery",
            packaging = source.packaging or job.packaging or "flat",
            wrapped = false,
        }
        if job.press then
            replacement.press = {
                status = "awaiting_cut",
                completedColors = 0,
                goodSheets = 0,
                spoilage = 0,
                dryUntilHours = nil,
                requiredGoodSheets = replacement.requestedCopies,
                availableSheets = sheets,
                passHistory = {},
            }
        end
        replacement.paper = Context.PaperWork.create(
            job, replacement, job.difficulty or "easy", source.number or 1)
        job.pallets[#job.pallets + 1] = replacement
        job.replacementSkids = math.max(0, math.floor(tonumber(job.replacementSkids) or 0)) + 1
        job.replacementSheets = math.max(0, math.floor(tonumber(job.replacementSheets) or 0)) + sheets

        local nowHours = Context.BusinessCalendar.absoluteHours(state)
        local service = job.deliveryService or (job.delivery and job.delivery.service)
        local delay = math.max(1, math.min(8,
            tonumber(service and service.delayHours) or 4))
        local palletIds = {}
        local priorReadyAt
        if job.delivery and job.delivery.kind == "replacement"
            and job.delivery.status ~= "received"
        then
            priorReadyAt = tonumber(job.delivery.readyAtHours)
            local pending = {}
            for _, pallet in ipairs(job.pallets or {}) do
                if pallet.location == "awaiting_delivery" then pending[pallet.id] = true end
            end
            for _, id in ipairs(job.delivery.palletIds or {}) do
                if pending[id] and id ~= palletId then palletIds[#palletIds + 1] = id end
            end
        end
        palletIds[#palletIds + 1] = palletId
        job.delivery = {
            status = "replacement_pending",
            kind = "replacement",
            service = service,
            acceptedGameHours = nowHours,
            readyAtHours = math.max(priorReadyAt or 0, nowHours + delay),
            palletIds = palletIds,
        }
        return replacement, delay
    end

    function Context.spoilLift(state, result)
        local pallet = Context.Machine.pallet
        if Context.Machine.legacyPaper or not pallet then
            Context.Machine.step = "cut_complete"
            Context.message(state, string.format("OFF-SIZE CUT: %.2f in instead of %.2f in. The stock was spoiled.",
                result.actualGauge or Context.Machine.gauge, result.expectedGauge or 0))
            return
        end
        Context.ensureLiftProgress(pallet)
        local sheets = math.min(Context.Jobs.LIFT_CAPACITY, math.max(1, pallet.remainingSheets))
        local stockCost = Context.stockReplacementCost(Context.Machine.job, sheets)
        local redoCost = math.ceil(sheets / Context.Jobs.LIFT_CAPACITY) * Context.Jobs.PRICE_PER_LIFT
        local cost = stockCost + redoCost
        pallet.damagedSheets = (pallet.damagedSheets or 0) + sheets
        pallet.remainingSheets = math.max(0, pallet.remainingSheets - sheets)
        pallet.requiredLifts = math.max(1, (pallet.requiredLifts or 1) - 1)
        pallet.activeLift = math.min(pallet.requiredLifts,
            math.max(1, (pallet.completedLifts or 0) + 1))
        pallet.lastLiftSheets = sheets
        pallet.lastLiftSpoiled = true
        pallet.awaitingPalletReturn = true
        if pallet.remainingSheets == 0 and (pallet.finishedSheets or 0) == 0 then
            pallet.discardAfterSpoil = true
        end
        local replacement, delay = Context.scheduleReplacementSkid(
            state, Context.Machine.job, pallet, sheets)
        Context.Machine.job.spoiledSheets = (Context.Machine.job.spoiledSheets or 0) + sheets
        Context.Machine.job.spoilCost = (Context.Machine.job.spoilCost or 0) + cost
        local invoice = Context.BusinessCalendar.addCharge(state,
            string.format("Redo lift and replace client stock for %s (%d sheets)", Context.Machine.job.id, sheets),
            cost, Context.Machine.job.id)
        local demanding = Context.Machine.job.clientTemperament == "demanding"
        local loss, score = Context.Reputation.spoilLift(state, sheets, cost, demanding)
        Context.Machine.step = "cut_complete"
        Context.message(state, string.format(
            "OFF-SIZE CUT: %.2f in instead of %.2f in. %d client sheets spoiled; %s billed $%d for replacement stock and the redo. Replacement skid %s arrives in about %d game hour%s. Reputation -%d (%d).",
            result.actualGauge or Context.Machine.gauge, result.expectedGauge or 0, sheets,
            demanding and "the demanding client" or "the client", invoice.total,
            replacement.id, delay, delay == 1 and "" or "s", loss, score))
    end
end

return Component
