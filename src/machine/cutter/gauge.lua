-- Cutter programs, gauge measurements, clamps, and cut controls.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    function Context.Machine.selectProgram(index, state)
        if not Context.Machine.paper or type(index) ~= "number" then return false end
        index = math.max(1, math.min(#Context.Machine.paper.cuts, math.floor(index)))
        Context.Machine.programIndex = index
        Context.Machine.autoCycle[index] = 1
        local cut = Context.Machine.paper.cuts[index]
        Context.message(state, string.format("Program %d: trim %s margin %.2f in.", index, cut.edge, cut.margin))
        Context.bumpRevision()
        return true
    end

    function Context.Machine.adjustGauge(amount, state)
        if not Context.Machine.paper or Context.Machine.clamp or Context.Machine.step == "cutting" then return false end
        Context.Machine.gauge = math.max(0, math.min(25,
            math.floor((Context.Machine.gauge + amount) * 100 + 0.5) / 100))
        Context.message(state, string.format("Backgauge set to %.2f in.", Context.Machine.gauge))
        Context.bumpRevision()
        return true
    end

    function Context.Machine.setGauge(value, state)
        value = tonumber(value)
        if not Context.Machine.paper or Context.Machine.clamp or Context.Machine.step == "cutting" then return false end
        if not value or value < 0 or value > 25 then
            Context.message(state, "Enter a backgauge position from 0.00 to 25.00 inches.")
            return false
        end
        Context.Machine.gauge = math.floor(value * 100 + 0.5) / 100
        Context.message(state, string.format("Backgauge typed in at %.2f in.", Context.Machine.gauge))
        Context.bumpRevision()
        return true
    end

    function Context.measurements(state, cutNumber, create)
        if type(state) ~= "table" then return nil end
        local memory = state.cutterMemory
        if Context.machineId then
            local item = Context.MachineFleet.byId(state, Context.machineId)
            if not item then return nil end
            memory = item.memory
            if type(memory) ~= "table" and create then
                item.memory = {}
                memory = item.memory
            end
        end
        if type(memory) ~= "table" then
            if not create then return nil end
            state.cutterMemory = {}
            memory = state.cutterMemory
        end
        local key = tostring(math.max(1, math.min(4, math.floor(cutNumber or 1))))
        if type(memory[key]) ~= "table" then
            if not create then return nil end
            memory[key] = {}
        end
        return memory[key]
    end

    function Context.Machine.savedMeasurements(state, cutNumber)
        local source, result = Context.measurements(state, cutNumber or Context.Machine.programIndex, false), {}
        for index, value in ipairs(source or {}) do result[index] = value end
        return result
    end

    function Context.Machine.autoGauge(state)
        if not Context.Machine.paper or Context.Machine.clamp or Context.Machine.step == "cutting" then return false end
        local cutNumber = Context.Machine.programIndex
        local saved = Context.measurements(state, cutNumber, false)
        if not saved or #saved == 0 then
            Context.message(state, string.format(
                "AUTO SET P%d has no player-saved measurement. Type a gauge and press SAVE first.", cutNumber))
            return false
        end
        local cursor = math.max(1, math.min(#saved, Context.Machine.autoCycle[cutNumber] or 1))
        Context.Machine.gauge = saved[cursor]
        Context.Machine.savedGauge = Context.Machine.gauge
        Context.Machine.autoCycle[cutNumber] = cursor % #saved + 1
        Context.message(state, string.format("AUTO SET P%d recalled %.2f in. (%d of %d saved).",
            cutNumber, Context.Machine.gauge, cursor, #saved))
        Context.bumpRevision()
        return true
    end

    function Context.Machine.saveGauge(state)
        if not Context.Machine.paper or Context.Machine.clamp or Context.Machine.step == "cutting" then return false end
        Context.Machine.savedGauge = Context.Machine.gauge
        local cutNumber = Context.Machine.programIndex
        local saved = Context.measurements(state, cutNumber, true)
        for index = #saved, 1, -1 do
            if math.abs(saved[index] - Context.Machine.gauge) < 0.001 then table.remove(saved, index) end
        end
        table.insert(saved, 1, Context.Machine.gauge)
        while #saved > 3 do table.remove(saved) end
        Context.Machine.autoCycle[cutNumber] = 1
        Context.message(state, string.format("Saved P%d gauge %.2f in. (%d of 3 memory slots used).",
            cutNumber, Context.Machine.savedGauge, #saved))
        Context.bumpRevision()
        return true
    end

    function Context.Machine.recallGauge(state)
        if Context.Machine.clamp then return false end
        local saved = Context.measurements(state, Context.Machine.programIndex, false)
        if not saved or #saved == 0 then
            Context.message(state, string.format("No saved measurement exists for P%d.", Context.Machine.programIndex))
            return false
        end
        Context.Machine.gauge, Context.Machine.savedGauge = saved[1], saved[1]
        Context.message(state, string.format("Recalled newest P%d gauge %.2f in.", Context.Machine.programIndex, Context.Machine.gauge))
        Context.bumpRevision()
        return true
    end

    function Context.Machine.rotate(state)
        if not Context.Machine.paper or Context.Machine.clamp then return false end
        if Context.Machine.step ~= "loaded" and Context.Machine.step ~= "positioned" then return false end
        if not Context.PaperWork.rotate(Context.Machine.paper) then return false end
        Context.Machine.step, Context.Machine.paperTravel = "loaded", 0.35
        Context.message(state, string.format("Paper rotated counter-clockwise into the %s cutting position. Reposition it.",
            Context.PaperWork.currentCut(Context.Machine.paper).edge))
        Context.bumpRevision()
        return true
    end

    function Context.Machine.position(state)
        if Context.Machine.step ~= "loaded" then return false end
        local cut = Context.PaperWork.currentCut(Context.Machine.paper)
        if not cut then return false end
        Context.Machine.step, Context.Machine.progress = "positioning", 0
        Context.message(state, "Pushing the paper stack against the selected backgauge. Verify the ticket before cutting.")
        Context.bumpRevision()
        return true
    end

    function Context.Machine.toggleClamp(state)
        if Context.Machine.step ~= "positioned" and Context.Machine.step ~= "clamped" then return false end
        Context.Machine.clamp = not Context.Machine.clamp
        Context.Machine.step = Context.Machine.clamp and "clamped" or "positioned"
        Context.message(state, Context.Machine.clamp
            and (Context.Machine.multiplayerSingleControl
                and "Clamp engaged. Press either cut control."
                or "Clamp engaged. Hold both cut controls.")
            or "Clamp released.")
        Context.bumpRevision()
        return true
    end

    function Context.Machine.setClamp(down, state)
        if type(down) ~= "boolean" then return false end
        if Context.Machine.clamp == down then return true end
        return Context.Machine.toggleClamp(state)
    end

    function Context.Machine.setBarrier(clear, state)
        Context.Machine.barrierClear = clear ~= false
        if not Context.Machine.barrierClear and (Context.Machine.step == "cutting" or Context.Machine.step == "armed") then
            Context.enterBlocked(state, "Safety barrier interrupted. Clear the cutter and reset.", "loaded")
        end
        Context.bumpRevision()
        return true
    end

    function Context.Machine.emergencyStop(state)
        local resumeStep = Context.safeResumeStep(Context.Machine.step)
        Context.Machine.emergencyStopped = true
        Context.enterBlocked(state, "Emergency stop active. Reset the cutter before continuing.", resumeStep)
        Context.bumpRevision()
        return true
    end

    function Context.tryCut(state)
        if Context.Machine.step ~= "clamped" or not Context.Machine.loaded then return false end
        local operable, machineOrError = Context.MachineFleet.canOperate(state, "polar_115")
        if not operable then Context.message(state, machineOrError); return false end
        if not Context.Machine.barrierClear or Context.Machine.emergencyStopped then
            Context.enterBlocked(state, "Cut blocked: check the safety barrier and emergency stop.", "loaded")
            return false
        end
        if not Context.PaperWork.currentCut(Context.Machine.paper) then return false end
        Context.Machine.step, Context.Machine.progress = "armed", 0
        Context.message(state, "Safety controls validated. Blade cycle starting.")
        Context.bumpRevision()
        return true
    end

    function Context.Machine.guardedCut(state)
        return Context.tryCut(state)
    end

    -- NPCs always press both controls. Multiplayer's human single-button option
    -- never changes this input path or any of tryCut's stock/safety checks.
    function Context.Machine.pressBothControls(state)
        if Context.Machine.step ~= "clamped" then return false end
        Context.Machine.leftDown, Context.Machine.rightDown = true, true
        Context.Machine._leftAt, Context.Machine._rightAt = Context.Machine._clock, Context.Machine._clock
        return Context.Machine.leftDown and Context.Machine.rightDown
            and math.abs(Context.Machine._leftAt-Context.Machine._rightAt)<=Context.Machine.simultaneity
            and Context.tryCut(state)
    end

    function Context.Machine.setMultiplayerSingleControl(enabled)
        Context.Machine.multiplayerSingleControl = enabled == true
    end

    function Context.Machine.resetSafety(state)
        if Context.Machine.step ~= "blocked" and Context.Machine.step ~= "finished" then return false end
        Context.Machine._resetResume = Context.Machine.step == "blocked"
            and (Context.Machine._blockedResume or Context.safeResumeStep(Context.Machine.step)) or "idle"
        Context.Machine.emergencyStopped, Context.Machine.barrierClear = false, true
        Context.Machine.clamp, Context.Machine.leftDown, Context.Machine.rightDown = false, false, false
        Context.Machine.step, Context.Machine.progress, Context.Machine.bladeProgress = "resetting", 0, 0
        Context.message(state, "Resetting safety controls...")
        Context.bumpRevision()
        return true
    end

    function Context.Machine.releaseOperator(state)
        local changed = Context.Machine.leftDown or Context.Machine.rightDown
        Context.Machine.leftDown, Context.Machine.rightDown = false, false
        Context.Machine._leftAt, Context.Machine._rightAt = -math.huge, -math.huge
        if Context.Machine.step == "clamped" then
            Context.Machine.clamp, Context.Machine.step = false, "positioned"
            changed = true
            Context.message(state, "Cutter controls released safely; the clamp was raised.")
        end
        if changed then Context.bumpRevision() end
        return changed
    end
end

return Component
