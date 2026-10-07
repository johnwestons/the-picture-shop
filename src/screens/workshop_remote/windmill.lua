-- Remote Windmill run, plate, setup, and service presentation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.drawWindmillTabs(pointerX, pointerY)
        for _, tab in ipairs(Runtime.WINDMILL_TAB_ORDER) do
            Runtime.button(Runtime.WINDMILL_TABS[tab], tab:upper(), pointerX, pointerY, true,
                Runtime.Screen.windmillTab == tab)
        end
    end

    function Runtime.drawWindmillRun(state, pointerX, pointerY)
        local view = Runtime.Screen.view or {}
        local proof = view.proofPermille and string.format("%d%%",
            math.floor((tonumber(view.proofPermille) or 0) / 10 + 0.5)) or "NOT PULLED"
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("STATUS  " .. tostring(view.status or "idle"):gsub("_", " "):upper(), 112, 170)
        love.graphics.printf(string.format("SPEED  %d IPH", tonumber(view.speed) or 3000), 592, 170, 236, "right")
        love.graphics.print("JOB  " .. tostring(view.jobId or "NO PALLET LOADED"), 112, 194)
        love.graphics.printf(string.format("COLOR  %s / %s", tostring(view.colorIndex or "—"),
            tostring(view.colorCount or "—")), 592, 194, 236, "right")
        love.graphics.print(string.format("COUNTER  %d   GOOD  %d / %d   SPOIL  %d",
            tonumber(view.counter) or 0, tonumber(view.goodSheets) or 0,
            tonumber(view.targetSheets) or 0, tonumber(view.spoilage) or 0), 112, 218)
        love.graphics.printf(string.format("FEED  %d / %d   PROOF  %s",
            tonumber(view.feedRemaining) or 0, tonumber(view.feedStart) or 0, proof),
            468, 218, 360, "right")
        if view.warning then
            love.graphics.setColor(0.78, 0.24, 0.18)
            love.graphics.printf(tostring(view.warning), 112, 235, 716, "center")
        end

        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.toggle_motor, view.motor and "STOP MOTOR" or "START MOTOR",
            pointerX, pointerY, Runtime.windmillButtonEnabled("toggle_motor", state), true)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.toggle_feeder, view.feeder and "FEEDER OFF" or "FEEDER ON",
            pointerX, pointerY, Runtime.windmillButtonEnabled("toggle_feeder", state), true)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.toggle_impression,
            view.impression and "IMPRESSION OFF" or "IMPRESSION ON",
            pointerX, pointerY, Runtime.windmillButtonEnabled("toggle_impression", state), true)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.speed_down, "SPEED −", pointerX, pointerY,
            Runtime.windmillButtonEnabled("speed_down", state), true)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.speed_up, "SPEED +", pointerX, pointerY,
            Runtime.windmillButtonEnabled("speed_up", state), true)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.emergency_stop, "E-STOP", pointerX, pointerY,
            Runtime.windmillButtonEnabled("emergency_stop", state), false)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.reset_safety, "RESET", pointerX, pointerY,
            Runtime.windmillButtonEnabled("reset_safety", state), true)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.take_proof, "PULL PROOF", pointerX, pointerY,
            Runtime.windmillButtonEnabled("take_proof", state), true)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.verify_artwork,
            view.artworkVerified and "ART VERIFIED" or "VERIFY ART", pointerX, pointerY,
            Runtime.windmillButtonEnabled("verify_artwork", state), true)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.approve_proof,
            view.proofApproved and "APPROVED" or "APPROVE", pointerX, pointerY,
            Runtime.windmillButtonEnabled("approve_proof", state), true)
        local runAction = view.status == "production" and "stop_run" or "start_run"
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.run, view.status == "production" and "STOP RUN" or "START RUN",
            pointerX, pointerY, Runtime.windmillButtonEnabled(runAction, state), true)
        Runtime.button(Runtime.WINDMILL_RUN_CONTROLS.clean_unload, "CLEAN + UNLOAD", pointerX, pointerY,
            Runtime.windmillButtonEnabled("clean_unload", state), true)

        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print(view.status == "idle" and "PRINT-READY PALLETS" or "ACTIVE PRESS PASS",
            112, 408)
        if view.status == "idle" then
            local candidates = Runtime.windmillCandidates()
            if #candidates == 0 then
                love.graphics.setColor(0.40, 0.42, 0.43)
                love.graphics.printf("Stage cut stock beside the press and prepare its mounted plate.",
                    112, 456, 716, "center")
            end
            for index, candidate in ipairs(candidates) do
                local label = string.format("LOAD %s  ·  COLOR %d",
                    Runtime.compactLabel(Runtime.cutterPalletLabel(state, candidate.palletId), 44),
                    tonumber(candidate.colorIndex) or 1)
                Runtime.button(Runtime.windmillCandidateRect(index), label, pointerX, pointerY,
                    Runtime.windmillButtonEnabled("load_pallet", state), true)
            end
        else
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf(tostring(view.palletId or "The host owns the active pallet."),
                112, 448, 716, "center")
        end
    end

    function Runtime.drawWindmillPlates(state, pointerX, pointerY)
        local selected, plates, job, jobs = Runtime.windmillSelectedPlate(state)
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("ACTIVE PRINT JOBS", 112, 164)
        love.graphics.print("JOB PLATES", 344, 164)
        if #jobs == 0 then
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf("No active Windmill jobs require plates.", 112, 260, 716, "center")
            return
        end
        for index, item in ipairs(jobs) do
            Runtime.button(Runtime.windmillPlateJobRect(index), Runtime.compactLabel(tostring(item.id), 24), pointerX, pointerY,
                not Runtime.Screen.waiting, item.id == Runtime.Screen.windmillJobId)
        end
        for index, plate in ipairs(plates) do
            if index > 4 then break end
            local quality = math.floor((tonumber(plate.quality) or 0) * 100 + 0.5)
            local label = string.format("%s  ·  %s  ·  %d%%  ·  %s",
                Runtime.compactLabel(plate.id, 25), tostring(plate.status or "unprepared"):upper(), quality,
                plate.mounted and "MOUNTED" or tostring(plate.inkColor or "INK"))
            Runtime.button(Runtime.windmillPlateRect(index), label, pointerX, pointerY, not Runtime.Screen.waiting,
                plate.id == Runtime.Screen.windmillPlateId)
        end
        if not selected then return end
        Runtime.button(Runtime.WINDMILL_PLATE_CONTROLS.order_plate, "ORDER PROCESSED PLATE", pointerX, pointerY,
            Runtime.windmillButtonEnabled("order_plate", state), true)
        Runtime.button(Runtime.WINDMILL_PLATE_CONTROLS.begin_plate, "START IN-HOUSE PLATE", pointerX, pointerY,
            Runtime.windmillButtonEnabled("begin_plate", state), true)
        local processNames = { "EXPOSE", "WASH", "DRY", "MOUNT" }
        local processLabel = processNames[math.max(1, math.min(4,
            math.floor(tonumber(selected.processStep) or 1)))]
        Runtime.button(Runtime.WINDMILL_PLATE_CONTROLS.process_plate, "TIME + LOCK " .. processLabel,
            pointerX, pointerY, Runtime.windmillButtonEnabled("process_plate", state), true)

        love.graphics.setColor(0.18, 0.21, 0.22)
        love.graphics.rectangle("fill", 112, 508, 716, 24, 3, 3)
        love.graphics.setColor(0.18, 0.58, 0.29)
        love.graphics.rectangle("fill", 112 + 716 * 0.58, 508, 716 * 0.18, 24, 3, 3)
        local marker = math.max(0, math.min(1000,
            tonumber(Runtime.Screen.view and Runtime.Screen.view.plateMarkerPermille) or 0)) / 1000
        love.graphics.setColor(0.92, 0.72, 0.20)
        love.graphics.rectangle("fill", 108 + 716 * marker, 502, 8, 36)
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.printf("Lock the host-timed marker inside the green quality window.",
            112, 544, 716, "center")
        if job then
            love.graphics.printf(Runtime.compactLabel(tostring(job.company or job.id), 56), 112, 570, 716, "center")
        end
    end

    function Runtime.drawWindmillSetup(state, pointerX, pointerY)
        local view = Runtime.Screen.view or {}
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.printf("Host-verified chase, packing, roller, ink, feeder, and register checks",
            112, 170, 716, "center")
        if view.setupTask then
            love.graphics.setColor(0.10, 0.12, 0.13)
            love.graphics.printf(tostring(view.setupTask):upper() .. " SETUP", 112, 218, 716, "center")
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf(tostring(view.setupSummary or "Use the controls to finish this check."),
                112, 260, 716, "center")
            for index, control in ipairs(Runtime.PressSetupGames.controls(view.setupTask)) do
                Runtime.button(Runtime.windmillSetupControlRect(view.setupTask, index), control[2], pointerX, pointerY,
                    Runtime.windmillButtonEnabled("setup_action", state), true)
            end
            Runtime.button(Runtime.WINDMILL_SETUP_CANCEL, "CANCEL SETUP", pointerX, pointerY,
                Runtime.windmillButtonEnabled("cancel_setup", state), false)
            return
        end
        for index, task in ipairs(Runtime.WINDMILL_SETUP_TASKS) do
            local score = tonumber((view.setupPermille or {})[index]) or 0
            local label = task:upper() .. "\n" .. (score > 0
                and string.format("COMPLETE %d%%", math.floor(score / 10 + 0.5)) or "BEGIN CHECK")
            Runtime.button(Runtime.windmillSetupTaskRect(index), label, pointerX, pointerY,
                Runtime.windmillButtonEnabled("begin_setup", state), score > 0)
        end
        if not view.palletId then
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf("Load a print-ready pallet from RUN before beginning setup.",
                112, 470, 716, "center")
        end
    end

    function Runtime.drawWindmillService(state, pointerX, pointerY)
        local view = Runtime.Screen.view or {}
        local machine
        for _, item in ipairs(state and state.machines and state.machines.items or {}) do
            if item.modelId == "heidelberg_10x15" and item.status == "installed" then machine = item; break end
        end
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.printf(string.format("MACHINE CONDITION  %d%%   ·   MAINTENANCE KITS  %d",
            tonumber(machine and machine.condition) or 0,
            tonumber(state and state.inventory and state.inventory.stock
                and state.inventory.stock.maintenance_kit) or 0), 112, 176, 716, "center")
        love.graphics.setColor(0.18, 0.21, 0.22)
        love.graphics.rectangle("fill", 160, 224, 640, 20, 3, 3)
        love.graphics.setColor(0.18, 0.58, 0.29)
        love.graphics.rectangle("fill", 160, 224, 640 * math.max(0, math.min(1000,
            tonumber(view.servicePermille) or 0)) / 1000, 20, 3, 3)
        local step = tostring(view.serviceStep or "idle")
        if step == "idle" then
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf("Routine service requires an idle, unloaded press and one maintenance kit.",
                112, 300, 716, "center")
            Runtime.button(Runtime.WINDMILL_SERVICE_CONTROLS.begin_service, "BEGIN LOCKOUT + SERVICE",
                pointerX, pointerY, Runtime.windmillButtonEnabled("begin_service", state), true)
            Runtime.button(Runtime.WINDMILL_SERVICE_CONTROLS.book_technician, "BOOK TECHNICIAN  $350",
                pointerX, pointerY, Runtime.windmillButtonEnabled("book_technician", state), true)
        elseif step == "task" then
            love.graphics.setColor(0.10, 0.12, 0.13)
            love.graphics.printf(tostring(view.serviceTask or "Inspect and service the active component."),
                160, 282, 640, "center")
            Runtime.button(Runtime.WINDMILL_SERVICE_CONTROLS.service_task, "COMPLETE INTERACTIVE CHECK",
                pointerX, pointerY, Runtime.windmillButtonEnabled("service_task", state), true)
        else
            local labels = {
                lockout_disconnect = "1. DISCONNECT POWER",
                lockout_key = "2. REMOVE + KEEP KEY",
                lockout_tag = "3. ATTACH LOCKOUT TAG",
            }
            love.graphics.setColor(0.10, 0.12, 0.13)
            love.graphics.printf("Complete energy isolation in the host-verified order.",
                160, 282, 640, "center")
            Runtime.button(Runtime.WINDMILL_SERVICE_CONTROLS.service_lockout, labels[step] or "ADVANCE LOCKOUT",
                pointerX, pointerY, Runtime.windmillButtonEnabled("service_lockout", state), true)
        end
    end

    function Runtime.drawWindmill(state, pointerX, pointerY)
        Runtime.drawWindmillTabs(pointerX, pointerY)
        if Runtime.Screen.windmillTab == "run" then Runtime.drawWindmillRun(state, pointerX, pointerY)
        elseif Runtime.Screen.windmillTab == "plates" then Runtime.drawWindmillPlates(state, pointerX, pointerY)
        elseif Runtime.Screen.windmillTab == "setup" then Runtime.drawWindmillSetup(state, pointerX, pointerY)
        else Runtime.drawWindmillService(state, pointerX, pointerY) end
    end
end

return Component
