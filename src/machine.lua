local PaperWork = require("src.paper_work")
local Config = require("src.config")
local PalletState = require("src.pallet_state")

local Machine = {
    step = "idle", progress = 0, loaded = false, clamp = false,
    clampProgress = 0, bladeProgress = 0, barrierClear = true,
    emergencyStopped = false, leftDown = false, rightDown = false,
    _leftAt = -math.huge, _rightAt = -math.huge, _clock = 0,
    simultaneity = 0.30, cycleTime = 1.25, transferTime = 0.45,
    gauge = 0, programIndex = 1, savedGauge = nil,
    paper = nil, pallet = nil, job = nil, legacyPaper = false, paperTravel = 0,
}

local function message(state, text)
    if state then state.message = text end
end

local function cutterOutputPosition(state, palletNumber)
    local cutter = state and state.cutter or { x = 625, y = 405, direction = "northwest" }
    local offsets = {
        northwest = { x = 96, y = 72, rowX = 1, rowY = 1 },
        northeast = { x = -96, y = 72, rowX = -1, rowY = 1 },
        southwest = { x = 96, y = -72, rowX = 1, rowY = -1 },
        southeast = { x = -96, y = -72, rowX = -1, rowY = -1 },
    }
    local offset = offsets[cutter.direction] or offsets.northwest
    local index = math.max(0, (palletNumber or 1) - 1)
    local column, row = index % 2, math.floor(index / 2)
    return cutter.x + offset.x + column * 58 * offset.rowX,
        cutter.y + offset.y + row * 44 * offset.rowY
end

local function availablePapers(state)
    return PalletState.cutterCandidates(state, Config.cutterPlacement.palletInputRadius)
end

local function makeLegacyPaper()
    local job = { id = "STOCK", sourceSize = { width = 13, height = 10 }, finishedSize = { width = 12, height = 9 } }
    local pallet = { id = "STOCK-P01" }
    return PaperWork.create(job, pallet, "easy", 1), pallet, job
end

local function syncProgram()
    if Machine.paper then Machine.programIndex = math.min(Machine.paper.activeCut, #Machine.paper.cuts) end
end

function Machine.reset(state)
    Machine.step, Machine.progress, Machine.loaded = "idle", 0, false
    Machine.clamp, Machine.clampProgress, Machine.bladeProgress = false, 0, 0
    Machine.leftDown, Machine.rightDown = false, false
    Machine.barrierClear, Machine.emergencyStopped = true, false
    Machine.gauge, Machine.programIndex, Machine.savedGauge = 0, 1, nil
    Machine.paper, Machine.pallet, Machine.job = nil, nil, nil
    Machine.legacyPaper, Machine.paperTravel = false, 0
    message(state, "Cutter ready. Select a pallet paper batch and load it.")
end

function Machine.availablePapers(state) return availablePapers(state) end

function Machine.load(state)
    if Machine.step ~= "idle" and Machine.step ~= "finished" then return false end
    local selected = availablePapers(state)[1]
    if selected then
        local wasWarehouse = selected.pallet.location == "warehouse"
        if wasWarehouse then
            local transitioned, transitionError = PalletState.transition(state, selected.pallet, "at_cutter", {
                status = "in_process",
                cutterRadius = Config.cutterPlacement.palletInputRadius,
            })
            if not transitioned then message(state, transitionError); return false end
        end
        Machine.paper, Machine.pallet, Machine.job = selected.paper, selected.pallet, selected.job
        Machine.legacyPaper = false
        if wasWarehouse and state and state.inventory then
            state.inventory.rawPallets = math.max(0, (state.inventory.rawPallets or 0) - 1)
            state.inventory.inProcessPallets = (state.inventory.inProcessPallets or 0) + 1
        end
    elseif PalletState.hasUnfinishedCustomerPaper(state) then
        message(state, "Stage an unfinished pallet on clear floor beside the cutter before loading.")
        return false
    elseif state and state.inventory and (state.inventory.paper or 0) > 0 then
        Machine.paper, Machine.pallet, Machine.job = makeLegacyPaper()
        Machine.legacyPaper = true
    else
        message(state, "No eligible paper is in the warehouse or generic stock inventory.")
        return false
    end
    Machine.loaded, Machine.step, Machine.progress, Machine.paperTravel = true, "loading", 0, 0
    Machine.gauge = 0
    syncProgram()
    message(state, "Paper batch " .. Machine.paper.id .. " is moving onto the cutting bed.")
    return true
end

function Machine.selectProgram(index, state)
    if not Machine.paper or type(index) ~= "number" then return false end
    index = math.max(1, math.min(#Machine.paper.cuts, math.floor(index)))
    Machine.programIndex = index
    local cut = Machine.paper.cuts[index]
    message(state, string.format("Program %d: trim %s margin %.2f in.", index, cut.edge, cut.margin))
    return true
end

function Machine.adjustGauge(amount, state)
    if not Machine.paper or Machine.clamp or Machine.step == "cutting" then return false end
    Machine.gauge = math.max(0, math.floor((Machine.gauge + amount) * 100 + 0.5) / 100)
    message(state, string.format("Backgauge set to %.2f in.", Machine.gauge))
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
    return true
end

function Machine.autoGauge(state)
    if not Machine.paper then return false end
    -- AUTO SET always follows the work order.  The active cut is the next
    -- cut that has not been completed, so the button both selects that
    -- program number and recalls its saved backgauge setting.
    local nextIndex = math.max(1, math.min(#Machine.paper.cuts, Machine.paper.activeCut or 1))
    local cut = Machine.paper.cuts[nextIndex]
    if not cut then return false end
    Machine.programIndex = nextIndex
    Machine.gauge = cut.gauge
    message(state, string.format("AUTO SET selected next cut P%d and moved the backgauge to %.2f in.",
        Machine.programIndex, Machine.gauge))
    return true
end

function Machine.saveGauge(state)
    if not Machine.paper then return false end
    Machine.savedGauge = Machine.gauge
    message(state, string.format("Saved repeat-cut gauge %.2f in.", Machine.savedGauge))
    return true
end

function Machine.recallGauge(state)
    if not Machine.savedGauge or Machine.clamp then return false end
    Machine.gauge = Machine.savedGauge
    message(state, string.format("Recalled gauge %.2f in.", Machine.gauge))
    return true
end

function Machine.rotate(state)
    if not Machine.paper or Machine.clamp then return false end
    if Machine.step ~= "loaded" and Machine.step ~= "positioned" then return false end
    if not PaperWork.rotate(Machine.paper) then return false end
    Machine.step, Machine.paperTravel = "loaded", 0.35
    message(state, string.format("Paper rotated counter-clockwise into the %s cutting position. Reposition it.",
        PaperWork.currentCut(Machine.paper).edge))
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
    return true
end

function Machine.toggleClamp(state)
    if Machine.step ~= "positioned" and Machine.step ~= "clamped" then return false end
    Machine.clamp = not Machine.clamp
    Machine.step = Machine.clamp and "clamped" or "positioned"
    message(state, Machine.clamp and "Clamp engaged. Hold both cut controls." or "Clamp released.")
    return true
end

function Machine.setBarrier(clear, state)
    Machine.barrierClear = clear ~= false
    if not Machine.barrierClear and (Machine.step == "cutting" or Machine.step == "armed") then
        Machine.step, Machine.progress = "blocked", 0
        message(state, "Safety barrier interrupted. Clear the cutter and reset.")
    end
end

function Machine.emergencyStop(state)
    Machine.emergencyStopped, Machine.step, Machine.progress = true, "blocked", 0
    message(state, "Emergency stop active. Reset the cutter before continuing.")
end

local function tryCut(state)
    if Machine.step ~= "clamped" or not Machine.loaded then return false end
    if not Machine.barrierClear or Machine.emergencyStopped then
        Machine.step = "blocked"
        message(state, "Cut blocked: check the safety barrier and emergency stop.")
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
    message(state, "Both cut controls acknowledged. Blade cycle starting.")
    return true
end

function Machine.unload(state)
    if not Machine.paper or Machine.paper.status ~= "complete" or Machine.step ~= "cut_complete" then return false end
    Machine.step, Machine.progress = "unloading", 0
    message(state, "Pulling finished paper from the bed and returning it to its pallet.")
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
    elseif key == "[" then return Machine.selectProgram(Machine.programIndex - 1, state)
    elseif key == "]" then return Machine.selectProgram(Machine.programIndex + 1, state)
    elseif key == "b" then Machine.setBarrier(not Machine.barrierClear, state); return true
    elseif key == "x" then Machine.emergencyStop(state); return true
    elseif key == "r" and (Machine.step == "blocked" or Machine.step == "finished") then
        Machine.step, Machine.progress = "resetting", 0
        message(state, "Resetting safety controls...")
        return true
    end
    if Machine.step ~= "clamped" then return false end
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
    if not succeeded then Machine.step = "blocked"; message(state, result); return end
    if state and state.shopProgress then
        state.shopProgress.completedCuts = (state.shopProgress.completedCuts or 0) + 1
    end
    Machine.clamp, Machine.leftDown, Machine.rightDown = false, false, false
    if Machine.paper.status == "complete" then
        Machine.step = "cut_complete"
        message(state, string.format("All margins removed. %s is now %.2f x %.2f in.",
            Machine.paper.id, Machine.paper.currentSize.width, Machine.paper.currentSize.height))
    else
        Machine.step, Machine.paperTravel = "loaded", 0.35
        syncProgram()
        message(state, "Cut complete. Rotate 90 degrees, set the next gauge, and reposition.")
    end
end

function Machine.update(dt, state)
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

    if Machine.step == "loading" or Machine.step == "positioning" or Machine.step == "unloading" then
        Machine.progress = Machine.progress + dt
        Machine.paperTravel = math.min(1, Machine.progress / Machine.transferTime)
        if Machine.progress >= Machine.transferTime then
            if Machine.step == "loading" then
                Machine.step, Machine.paperTravel = "loaded", 0.35
                message(state, "Paper is on the bed. Program the first backgauge position.")
            elseif Machine.step == "positioning" then
                Machine.step, Machine.paperTravel = "positioned", 1
                message(state, "Paper is against the backgauge. Engage the clamp.")
            else
                if Machine.legacyPaper and state and state.inventory then
                    state.inventory.paper = math.max(0, (state.inventory.paper or 0) - 1)
                    state.inventory.prints = (state.inventory.prints or 0) + 1
                elseif Machine.pallet then
                    local outputX, outputY = cutterOutputPosition(state, Machine.pallet.number)
                    local world = {}
                    for key, value in pairs(Machine.pallet.world or {}) do world[key] = value end
                    world.x, world.y = outputX, outputY
                    world.fromX, world.fromY = outputX, outputY
                    world.spawnProgress = 1
                    local transitioned, transitionError = PalletState.transition(state, Machine.pallet, "cutter_output", {
                        status = "cut",
                        world = world,
                    })
                    if not transitioned then
                        Machine.step = "blocked"
                        message(state, "Could not return the pallet: " .. tostring(transitionError))
                        return
                    end
                    Machine.pallet.remainingSheets = 0
                    Machine.pallet.finishedSheets = Machine.pallet.initialSheets
                    Machine.pallet.completedLifts = Machine.pallet.requiredLifts
                    if state and state.inventory then
                        state.inventory.inProcessPallets = math.max(0, (state.inventory.inProcessPallets or 0) - 1)
                        state.inventory.finishedPallets = (state.inventory.finishedPallets or 0) + 1
                    end
                end
                Machine.loaded, Machine.step, Machine.paperTravel = false, "finished", 0
                message(state, "Finished paper returned to its pallet. Reset for the next batch.")
            end
        end
        return
    end
    if Machine.step == "armed" then Machine.step, Machine.progress = "cutting", 0 end
    if Machine.step == "cutting" then
        Machine.progress = Machine.progress + dt
        local phase = math.min(1, Machine.progress / Machine.cycleTime)
        Machine.bladeProgress = phase < 0.5 and phase * 2 or (1 - phase) * 2
        if Machine.progress >= Machine.cycleTime then Machine.bladeProgress = 0; finishCut(state) end
    elseif Machine.step == "resetting" then
        Machine.progress = Machine.progress + dt
        if Machine.progress >= 0.35 then Machine.reset(state) end
    end
end

function Machine.paperTooltip() return PaperWork.tooltip(Machine.paper) end

return Machine
