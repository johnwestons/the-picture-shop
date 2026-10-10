-- Cut completion, timed machine steps, and host network views.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    function Context.finishCut(state)
        local succeeded, result = Context.PaperWork.applyCut(Context.Machine.paper, Context.Machine.gauge, Context.Machine.programIndex)
        if not succeeded then Context.enterBlocked(state, result, "loaded"); return false end
        Context.MachineFleet.recordUse(state, "polar_115", 1)
        if state and state.shopProgress then
            state.shopProgress.completedCuts = (state.shopProgress.completedCuts or 0) + 1
        end
        Context.Machine.clamp, Context.Machine.leftDown, Context.Machine.rightDown = false, false, false
        if result.offSpec then
            Context.spoilLift(state, result)
            return true
        end
        if Context.Machine.paper.status == "complete" then
            Context.completeLift(state)
        else
            Context.Machine.step, Context.Machine.paperTravel = "loaded", 0.35
            Context.syncProgram()
            Context.message(state, "Cut complete. Rotate 90 degrees, set the next gauge, and reposition.")
        end
        return true
    end

    function Context.Machine.update(dt, state)
        Context.bumpRevision()
        Context.Machine._clock = Context.Machine._clock + dt
        if Context.Machine.step == "clamped" then
            if Context.Machine.leftDown and not Context.Machine.rightDown and Context.Machine._clock - Context.Machine._leftAt > Context.Machine.simultaneity then
                Context.Machine.leftDown = false
            elseif Context.Machine.rightDown and not Context.Machine.leftDown and Context.Machine._clock - Context.Machine._rightAt > Context.Machine.simultaneity then
                Context.Machine.rightDown = false
            end
        end
        local target, speed = Context.Machine.clamp and 1 or 0, dt / 0.25
        if Context.Machine.clampProgress < target then Context.Machine.clampProgress = math.min(target, Context.Machine.clampProgress + speed)
        elseif Context.Machine.clampProgress > target then Context.Machine.clampProgress = math.max(target, Context.Machine.clampProgress - speed) end

        if Context.Machine.step == "loading" or Context.Machine.step == "positioning" or Context.Machine.step == "unloading"
            or Context.Machine.step == "lift_returning"
        then
            Context.Machine.progress = Context.Machine.progress + dt
            Context.Machine.paperTravel = math.min(1, Context.Machine.progress / Context.Machine.transferTime)
            if Context.Machine.progress >= Context.Machine.transferTime then
                if Context.Machine.step == "loading" then
                    Context.Machine.step, Context.Machine.paperTravel = "loaded", 0.35
                    Context.message(state, "Paper is on the bed. Program the first backgauge position.")
                elseif Context.Machine.step == "positioning" then
                    Context.Machine.step, Context.Machine.paperTravel = "positioned", 1
                    Context.message(state, "Paper is against the backgauge. Engage the clamp.")
                elseif Context.Machine.step == "lift_returning" then
                    if Context.Machine.pallet then Context.Machine.pallet.awaitingPalletReturn = false end
                    Context.Machine.loaded, Context.Machine.step, Context.Machine.paperTravel = false, "repeat_ready", 0
                    Context.message(state, string.format("Lift returned to pallet. Press RUN NEXT LIFT for lift %d/%d.",
                        Context.Machine.pallet.activeLift, Context.Machine.pallet.requiredLifts))
                    return true
                else
                    if Context.Machine.legacyPaper and state and state.inventory then
                        local consumed, consumeError = Context.Procurement.consumePaper(state, 1)
                        if not consumed then
                            Context.enterBlocked(state,
                                consumeError or "Production paper is no longer available.", "cut_complete")
                            return false
                        end
                        state.inventory.prints = (state.inventory.prints or 0) + 1
                    elseif Context.Machine.pallet then
                        local output = Context.Machine.pendingOutput
                        if not output then
                            Context.enterBlocked(state,
                                "Could not return the pallet: the reserved output zone was lost.",
                                "cut_complete")
                            return false
                        end
                        -- A player can move stock into a reserved space while the
                        -- return animation runs. Revalidate against real floor
                        -- stock and other cutters before creating an output pallet.
                        local checked,outputError=Context.Machine.outputResolver(state,Context.Machine.pallet,
                            Context.machineId or "MCH-0001")
                        if not checked then
                            Context.Machine.pendingOutput=nil
                            Context.Machine.step,Context.Machine.progress="cut_complete",0
                            Context.message(state,outputError or "Clear the finished-pallet staging area.")
                            Context.bumpRevision()
                            return false
                        end
                        output=checked
                        local world = {}
                        for key, value in pairs(Context.Machine.pallet.world or {}) do world[key] = value end
                        world.x, world.y = output.x, output.y
                        world.direction = output.direction or world.direction or "northwest"
                        world.rotation = output.rotation or world.rotation
                        world.fromX, world.fromY = output.x, output.y
                        world.spawnProgress = 1
                        local transitioned, transitionError = Context.PalletState.transition(state, Context.Machine.pallet, "cutter_output", {
                            status = "cut",
                            world = world,
                        })
                        if not transitioned then
                            Context.enterBlocked(state,
                                "Could not return the pallet: " .. tostring(transitionError),
                                "cut_complete")
                            return false
                        end
                        Context.Machine.pendingOutput = nil
                        if state and state.inventory then
                            -- Printed work remains in process after cutting; it is
                            -- only finished after the final Windmill color pass.
                            if not (Context.Machine.job and Context.Machine.job.press) then
                                state.inventory.inProcessPallets = math.max(0,
                                    (state.inventory.inProcessPallets or 0) - 1)
                                state.inventory.finishedPallets = (state.inventory.finishedPallets or 0) + 1
                            end
                        end
                    end
                    Context.Machine.loaded, Context.Machine.step, Context.Machine.paperTravel = false, "finished", 0
                    Context.message(state, Context.Machine.job and Context.Machine.job.press
                        and "Cut client stock returned to its pallet. Stage it beside the Windmill for printing."
                        or "Finished paper returned to its pallet. Reset for the next batch.")
                    return true
                end
            end
            return false
        end
        if Context.Machine.step == "armed" then Context.Machine.step, Context.Machine.progress = "cutting", 0 end
        if Context.Machine.step == "cutting" then
            Context.Machine.progress = Context.Machine.progress + dt
            local phase = math.min(1, Context.Machine.progress / Context.Machine.cycleTime)
            Context.Machine.bladeProgress = phase < 0.5 and phase * 2 or (1 - phase) * 2
            if Context.Machine.progress >= Context.Machine.cycleTime then
                Context.Machine.bladeProgress = 0
                return Context.finishCut(state)
            end
        elseif Context.Machine.step == "resetting" then
            Context.Machine.progress = Context.Machine.progress + dt
            if Context.Machine.progress >= 0.35 then
                local resume = Context.Machine._resetResume
                if resume == nil or resume == "idle" then
                    Context.Machine.reset(state)
                else
                    Context.Machine.step, Context.Machine.progress = resume, 0
                    Context.Machine.loaded = resume ~= "repeat_ready" and Context.Machine.paper ~= nil
                    Context.Machine.paperTravel = Context.Machine.loaded and 0.35 or 0
                    Context.Machine._resetResume, Context.Machine._blockedResume = nil, nil
                    Context.message(state, resume == "repeat_ready"
                        and "Safety controls reset. Run the next verified lift when ready."
                        or resume == "cut_complete"
                            and "Safety controls reset. Return the completed lift to its pallet."
                            or "Safety controls reset. Reposition the paper before cutting.")
                    Context.bumpRevision()
                end
            end
        end
        return false
    end

    function Context.centi(value, minimum, maximum)
        return math.max(minimum or 0, math.min(maximum or 100000,
            math.floor((tonumber(value) or 0) * 100 + 0.5)))
    end

    function Context.phasePermille()
        local duration = 1
        if Context.Machine.step == "loading" or Context.Machine.step == "positioning"
            or Context.Machine.step == "unloading" or Context.Machine.step == "lift_returning"
        then
            duration = Context.Machine.transferTime
        elseif Context.Machine.step == "armed" or Context.Machine.step == "cutting" then
            duration = Context.Machine.cycleTime
        elseif Context.Machine.step == "resetting" then
            duration = 0.35
        elseif Context.Machine.step == "finished" then
            return 1000
        else
            return 0
        end
        return math.max(0, math.min(1000,
            math.floor((Context.Machine.progress / math.max(0.001, duration)) * 1000 + 0.5)))
    end

    function Context.Machine.networkView(state, includeCandidates)
        local memory = {}
        for _, value in ipairs(Context.Machine.savedMeasurements(state, Context.Machine.programIndex)) do
            memory[#memory + 1] = Context.centi(value, 0, 2500)
        end
        local view = {
            runtimeRevision = math.floor(tonumber(Context.Machine.runtimeRevision) or 0),
            step = Context.Machine.step,
            phasePermille = Context.phasePermille(),
            loaded = Context.Machine.loaded == true,
            clamp = Context.Machine.clamp == true,
            clampPermille = math.floor(math.max(0, math.min(1,
                tonumber(Context.Machine.clampProgress) or 0)) * 1000 + 0.5),
            bladePermille = math.floor(math.max(0, math.min(1,
                tonumber(Context.Machine.bladeProgress) or 0)) * 1000 + 0.5),
            barrierClear = Context.Machine.barrierClear == true,
            emergencyStopped = Context.Machine.emergencyStopped == true,
            gaugeCentiInch = Context.centi(Context.Machine.gauge, 0, 2500),
            programIndex = math.max(1, math.min(4, math.floor(Context.Machine.programIndex or 1))),
            memoryCentiInch = memory,
        }
        -- The runtime retains the previous paper after unloading/discarding. An
        -- empty, finished cutter must advertise next-load choices, not that old batch.
        if Context.Machine.paper and Context.Machine.pallet and Context.Machine.step ~= "idle" and Context.Machine.step ~= "finished" then
            local selected = Context.Machine.paper.cuts and Context.Machine.paper.cuts[view.programIndex]
            view.paper = {
                palletId = tostring(Context.Machine.pallet.id),
                orientation = math.floor(tonumber(Context.Machine.paper.orientation) or 0),
                status = tostring(Context.Machine.paper.status or "uncut"),
                activeCut = math.max(1, math.min(5, math.floor(Context.Machine.paper.activeCut or 1))),
                cutCount = math.max(1, math.min(4, #(Context.Machine.paper.cuts or {}))),
                activeLift = math.max(1, math.floor(Context.Machine.pallet.activeLift or 1)),
                requiredLifts = math.max(1, math.floor(Context.Machine.pallet.requiredLifts or 1)),
                remainingSheets = math.max(0, math.floor(Context.Machine.pallet.remainingSheets or 0)),
                widthCentiInch = Context.centi(Context.Machine.paper.currentSize.width, 1, 100000),
                heightCentiInch = Context.centi(Context.Machine.paper.currentSize.height, 1, 100000),
                offSpec = Context.Machine.paper.offSpec == true,
            }
            if selected then
                view.paper.selectedCut = {
                    number = math.max(1, math.min(4, math.floor(selected.number or view.programIndex))),
                    edge = tostring(selected.edge),
                    marginCentiInch = Context.centi(selected.margin, 0, 100000),
                    gaugeCentiInch = Context.centi(selected.gauge, 0, 2500),
                    orientation = math.floor(tonumber(selected.orientation) or 0),
                    active = view.programIndex == view.paper.activeCut,
                }
            end
        elseif includeCandidates then
            local candidates = {}
            for _, candidate in ipairs(Context.availablePapers(state)) do
                candidates[#candidates + 1] = {
                    palletId = tostring(candidate.pallet.id),
                    distancePixels = math.max(0, math.min(100000, math.floor(
                        math.sqrt(math.max(0, tonumber(candidate.inputDistance)
                            or tonumber(candidate.distance) or 0)) + 0.5))),
                }
                if #candidates >= 3 then break end
            end
            view.candidates = candidates
            if #candidates == 0 and not Context.PalletState.hasUnfinishedCustomerPaper(state) then
                local genericSheets = Context.Procurement.paperAvailable(state)
                if genericSheets > 0 then
                    view.genericSheets = math.min(100000, math.floor(genericSheets))
                end
            end
        end
        return view
    end
end

return Component
