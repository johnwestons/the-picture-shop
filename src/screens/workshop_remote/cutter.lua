-- Remote cutter production and maintenance presentation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.compactLabel(value, limit)
        local label = tostring(value or "")
        if #label <= limit then return label end
        return label:sub(1, math.max(1, limit - 3)) .. "..."
    end

    function Runtime.cutterBar(x, y, width, permille, color)
        local ratio = math.max(0, math.min(1, (tonumber(permille) or 0) / 1000))
        love.graphics.setColor(0.18, 0.21, 0.22)
        love.graphics.rectangle("fill", x, y, width, 14, 3, 3)
        love.graphics.setColor(color[1], color[2], color[3])
        love.graphics.rectangle("fill", x, y, width * ratio, 14, 3, 3)
    end

    function Runtime.drawCutterService(state, pointerX, pointerY)
        local view = Runtime.Screen.view or {}
        local status = Runtime.cutterMaintenanceStatus(state)
        local step = tostring(view.serviceStep or "idle")
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("CUTTER SERVICE  ·  HOST-AUTHORITATIVE LOCKOUT", 122, 132)
        love.graphics.printf(string.format("KITS %d  ·  BLADE %s  ·  TECHNICIAN %s",
            status.maintenanceKits,
            status.bladeInSleeve and "SLEEVED" or status.bladeRemoved and "REMOVED" or "INSTALLED",
            status.technicianScheduled and "SCHEDULED" or "NOT SCHEDULED"),
            122, 156, 690, "left")
        Runtime.cutterBar(122, 180, 690, view.servicePermille, { 0.18, 0.58, 0.29 })

        if step == "idle" then
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.lubrication, "LUBRICATION SERVICE", pointerX, pointerY,
                Runtime.cutterServiceButtonEnabled("begin_lubrication", state), true)
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.blade, "REMOVE + SLEEVE BLADE", pointerX, pointerY,
                Runtime.cutterServiceButtonEnabled("begin_blade", state), true)
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.technician,
                status.technicianScheduled and "TECHNICIAN SCHEDULED" or "BOOK BLADE TECHNICIAN",
                pointerX, pointerY, Runtime.cutterServiceButtonEnabled("book_blade_technician", state), true)
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.weekly,
                status.weeklyTechnician and "CANCEL WEEKLY SERVICE" or "SCHEDULE WEEKLY SERVICE",
                pointerX, pointerY, Runtime.cutterServiceButtonEnabled("set_weekly_technician", state), true)
            love.graphics.setColor(0.32, 0.35, 0.36)
            love.graphics.printf("Lubrication consumes one delivered maintenance kit only after every point and the gearbox inspection pass. Blade removal becomes durable only when the blade reaches its wooden sleeve.",
                142, 386, 650, "center")
        elseif step == "lockout_disconnect" or step == "lockout_key"
            or step == "lockout_tag" or step == "prep_cartridge" or step == "prep_prime"
        then
            local labels = {
                lockout_disconnect = "OPEN MAIN DISCONNECT",
                lockout_key = "SECURE LOCKOUT KEY",
                lockout_tag = "ATTACH SERVICE TAG",
                prep_cartridge = "INSTALL GREASE CARTRIDGE",
                prep_prime = "PRIME GREASE GUN",
            }
            love.graphics.setColor(0.24, 0.28, 0.29)
            love.graphics.printf("Complete the displayed host-owned step in order.", 122, 230, 690, "center")
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.advance, labels[step], pointerX, pointerY,
                Runtime.cutterServiceButtonEnabled("service_advance", state), true)
        elseif step == "lubricate" then
            for index, label in ipairs(Runtime.CUTTER_SERVICE_VIEWS) do
                local available = index ~= 5 or view.centralInstalled == true
                Runtime.button(Runtime.cutterServiceViewRect(index), label, pointerX, pointerY,
                    available and Runtime.cutterServiceButtonEnabled("service_view", state),
                    tonumber(view.serviceView) == index)
            end
            for index, label in ipairs(Runtime.CUTTER_SERVICE_TOOLS) do
                Runtime.button(Runtime.cutterServiceToolRect(index), label, pointerX, pointerY,
                    Runtime.cutterServiceButtonEnabled("service_tool", state),
                    tonumber(view.serviceTool) == index)
            end
            for index, item in ipairs(view.serviceItems or {}) do
                local status = item.complete and "DONE" or item.coupled and ("COUPLED · "
                    .. tostring(item.strokes) .. " STROKE(S)") or item.cleaned and "CLEAN" or "DIRTY"
                Runtime.button(Runtime.cutterServiceItemRect(index), tostring(item.label) .. "  ·  " .. status,
                    pointerX, pointerY, Runtime.cutterServiceButtonEnabled("service_point", state), item.complete)
            end
            local gearLabel = view.gearInspected
                and string.format("GEAR %.0f%%", (tonumber(view.gearLevelPermille) or 0) / 10)
                or "INSPECT / TOP UP GEAR"
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.pump, "PUMP GREASE", pointerX, pointerY,
                Runtime.cutterServiceButtonEnabled("service_pump", state), true)
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.gear, gearLabel, pointerX, pointerY,
                Runtime.cutterServiceButtonEnabled("service_gear", state), true)
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.finish, "FINISH + SAVE", pointerX, pointerY,
                Runtime.cutterServiceButtonEnabled("finish_lubrication", state), true)
        elseif step == "blade_bolts" then
            love.graphics.setColor(0.24, 0.28, 0.29)
            love.graphics.printf("Remove each blade bolt. The host tracks every distinct fastener.",
                122, 220, 690, "center")
            local done = tonumber(view.bladeBoltsDone) or 0
            for index = 1, 4 do
                Runtime.button(Runtime.cutterBladeBoltRect(index), index <= done and "REMOVED" or ("BOLT " .. index),
                    pointerX, pointerY, index == done + 1
                        and Runtime.cutterServiceButtonEnabled("remove_blade_bolt", state),
                    index <= done)
            end
        elseif step == "blade_lift" then
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.bladeAction, "LIFT RELEASED BLADE SAFELY",
                pointerX, pointerY, Runtime.cutterServiceButtonEnabled("lift_blade", state), true)
        elseif step == "blade_sleeve" then
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.bladeAction, "PLACE BLADE IN WOODEN SLEEVE + SAVE",
                pointerX, pointerY, Runtime.cutterServiceButtonEnabled("sleeve_blade", state), true)
        end

        if step ~= "idle" then
            Runtime.button(Runtime.CUTTER_SERVICE_CONTROLS.cancel, "CANCEL SERVICE", pointerX, pointerY,
                Runtime.cutterServiceButtonEnabled("cancel_service", state), false)
        end
        Runtime.button(Runtime.CUTTER_SERVICE_NAV, "PRODUCTION", pointerX, pointerY,
            not Runtime.Screen.waiting and not Runtime.Screen.safetyWaiting, false)
    end

    function Runtime.drawCutter(state, pointerX, pointerY, assets)
        local view = Runtime.Screen.view or {}
        if Runtime.Screen.cutterTab == "service" then
            Runtime.drawCutterService(state, pointerX, pointerY)
            return
        end
        local model = Runtime.Screen.cutterPresentation:model(state, view)
        love.graphics.setColor(0.045, 0.055, 0.07)
        love.graphics.rectangle("fill", Runtime.CUTTER_SCENE.x, Runtime.CUTTER_SCENE.y,
            Runtime.CUTTER_SCENE.width, Runtime.CUTTER_SCENE.height, 4, 4)
        Runtime.MachineScreen.drawCutterScene(assets, model,
            { x = Runtime.CUTTER_SCENE.x + 12, y = Runtime.CUTTER_SCENE.y, width = 340, height = 227 })
        if model.paper then
            love.graphics.setColor(model.paper.offSpec and 1 or 0.84,
                model.paper.offSpec and 0.4 or 0.92, model.paper.offSpec and 0.3 or 0.92)
            love.graphics.printf(string.format("%s  %.2f x %.2f in",
                model.paper.offSpec and "SPOILED" or "ON BED",
                model.paper.currentSize.width, model.paper.currentSize.height),
                474, 348, 344, "center")
        end
        local step = tostring(view.step or "idle"):gsub("_", " "):upper()
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("HOST: " .. step, 122, 126)
        if model.loaded and not model.paper then
            love.graphics.setColor(0.84, 0.92, 0.92)
            love.graphics.printf("Waiting for host paper details", 474, 348, 344, "center")
            love.graphics.setColor(0.10, 0.12, 0.13)
        end

        local paper = type(view.paper) == "table" and view.paper or nil
        if paper then
            local label = Runtime.cutterPalletLabel(state, paper.palletId)
            love.graphics.printf(string.format("%s\nLIFT %d/%d  ·  %d LEFT  ·  %d°",
                Runtime.compactLabel(label, 36), tonumber(paper.activeLift) or 1,
                tonumber(paper.requiredLifts) or 1, tonumber(paper.remainingSheets) or 0,
                tonumber(paper.orientation) or 0), 122, 146, 326, "left")
            local cut = type(paper.selectedCut) == "table" and paper.selectedCut or nil
            if cut then
                love.graphics.printf(string.format("TICKET: CUT %d %s · TRIM %.2f · GAUGE %.2f",
                    tonumber(cut.number) or tonumber(paper.activeCut) or 1,
                    tostring(cut.edge or "edge"):upper(),
                    (tonumber(cut.marginCentiInch) or 0) / 100,
                    (tonumber(cut.gaugeCentiInch) or 0) / 100), 122, 344, 326, "left")
            end
        else
            love.graphics.printf("No paper is on the cutting bed.", 122, 154, 326, "left")
        end

        if view.loaded ~= true then
            love.graphics.setColor(0.10, 0.12, 0.13)
            love.graphics.print("NEARBY CUTTER PALLETS [L]", 122, 184)
            local candidates = Runtime.cutterCandidates()
            if #candidates == 0 then
                love.graphics.setColor(0.40, 0.42, 0.43)
                love.graphics.printf("Park an unfinished pallet beside the cutter, or use generic stock.",
                    122, 260, 318, "center")
            end
            for index, candidate in ipairs(candidates) do
                local distance = math.max(0, math.floor(tonumber(candidate.distancePixels) or 0))
                local label = string.format("%s  ·  %d px",
                    Runtime.compactLabel(Runtime.cutterPalletLabel(state, candidate.palletId), 24), distance)
                Runtime.button(Runtime.cutterCandidateRect(index), label, pointerX, pointerY,
                    Runtime.cutterButtonEnabled("load_pallet"), true)
            end
            Runtime.button(Runtime.CUTTER_UNLOADED_CONTROLS.load_stock,
                string.format("LOAD STOCK (%d)", math.max(0, math.floor(tonumber(view.genericSheets) or 0))),
                pointerX, pointerY, Runtime.cutterButtonEnabled("load_stock")
                    and (tonumber(view.genericSheets) or 0) > 0, true)
            Runtime.button(Runtime.CUTTER_UNLOADED_CONTROLS.set_barrier,
                view.barrierClear == true and "BLOCK BARRIER" or "CLEAR BARRIER",
                pointerX, pointerY, Runtime.cutterButtonEnabled("set_barrier"), false)
            Runtime.button(Runtime.CUTTER_UNLOADED_CONTROLS.reset_safety, "RESET SAFETY",
                pointerX, pointerY, Runtime.cutterButtonEnabled("reset_safety"), true)
            Runtime.button(Runtime.CUTTER_UNLOADED_CONTROLS.run_next_lift, "RUN NEXT LIFT",
                pointerX, pointerY, Runtime.cutterButtonEnabled("run_next_lift"), true)
            Runtime.button(Runtime.CUTTER_UNLOADED_CONTROLS.emergency_stop, "E-STOP",
                pointerX, pointerY, Runtime.cutterButtonEnabled("emergency_stop"), false)
            Runtime.button(Runtime.CUTTER_SERVICE_NAV, "SERVICE", pointerX, pointerY,
                not Runtime.Screen.waiting and view.step == "idle", false)
            return
        end

        for index, rect in ipairs(Runtime.CUTTER_PROGRAMS) do
            Runtime.button(rect, "CUT " .. index, pointerX, pointerY,
                Runtime.cutterButtonEnabled("select_program"), tonumber(view.programIndex) == index)
        end
        local memory = {}
        for _, centi in ipairs(view.memoryCentiInch or {}) do
            memory[#memory + 1] = string.format("%.2f", (tonumber(centi) or 0) / 100)
        end
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.printf("P" .. tostring(tonumber(view.programIndex) or 1) .. " MEMORY  "
            .. (#memory > 0 and table.concat(memory, " / ") or "EMPTY"), 122, 328, 326, "left")

        love.graphics.setColor(Runtime.Screen.gaugeFocused and 0.98 or 0.88, 0.96, 0.82)
        love.graphics.rectangle("fill", Runtime.CUTTER_GAUGE_INPUT.x, Runtime.CUTTER_GAUGE_INPUT.y,
            Runtime.CUTTER_GAUGE_INPUT.width, Runtime.CUTTER_GAUGE_INPUT.height, 4, 4)
        love.graphics.setColor(0.08, 0.10, 0.11)
        love.graphics.printf(Runtime.Screen.gaugeText .. " in", Runtime.CUTTER_GAUGE_INPUT.x,
            Runtime.CUTTER_GAUGE_INPUT.y + 13, Runtime.CUTTER_GAUGE_INPUT.width, "center")
        Runtime.button(Runtime.CUTTER_CONTROLS.gauge_set, "SET", pointerX, pointerY,
            Runtime.cutterButtonEnabled("gauge_set"), true)
        Runtime.button(Runtime.CUTTER_CONTROLS.auto_gauge, "AUTO [G]", pointerX, pointerY,
            Runtime.cutterButtonEnabled("auto_gauge"), true)
        Runtime.button(Runtime.CUTTER_CONTROLS.save_gauge, "SAVE [M]", pointerX, pointerY,
            Runtime.cutterButtonEnabled("save_gauge"), true)
        Runtime.button(Runtime.CUTTER_CONTROLS.recall_gauge, "RECALL [V]", pointerX, pointerY,
            Runtime.cutterButtonEnabled("recall_gauge"), true)

        Runtime.button(Runtime.CUTTER_CONTROLS.rotate_paper, "ROTATE PAPER [Q]", pointerX, pointerY,
            Runtime.cutterButtonEnabled("rotate_paper"), true)
        Runtime.button(Runtime.CUTTER_CONTROLS.position_paper, "POSITION PAPER [P]", pointerX, pointerY,
            Runtime.cutterButtonEnabled("position_paper"), true)
        Runtime.button(Runtime.CUTTER_CONTROLS.set_clamp, view.clamp == true and "RAISE CLAMP [SPACE]" or "LOWER CLAMP [SPACE]",
            pointerX, pointerY, Runtime.cutterButtonEnabled("set_clamp"), true)
        Runtime.button(Runtime.CUTTER_CONTROLS.set_barrier,
            view.barrierClear == true and "BLOCK BARRIER [B]" or "CLEAR BARRIER [B]",
            pointerX, pointerY, Runtime.cutterButtonEnabled("set_barrier"), false)
        Runtime.button(Runtime.CUTTER_CONTROLS.reset_safety, "RESET SAFETY [R]", pointerX, pointerY,
            Runtime.cutterButtonEnabled("reset_safety"), true)
        Runtime.button(Runtime.CUTTER_CONTROLS.emergency_stop, "E-STOP [X]", pointerX, pointerY,
            Runtime.cutterButtonEnabled("emergency_stop"), false)
        Runtime.button(Runtime.CUTTER_CONTROLS.return_to_pallet, "RETURN TO PALLET [U]", pointerX, pointerY,
            Runtime.cutterButtonEnabled("return_to_pallet"), true)
        Runtime.button(Runtime.CUTTER_CONTROLS.run_next_lift, "RUN NEXT LIFT [T]", pointerX, pointerY,
            Runtime.cutterButtonEnabled("run_next_lift"), true)

        Runtime.button(Runtime.CUTTER_CONTROLS.cut_left, "CUT  ·  J",
            pointerX, pointerY, Runtime.cutterButtonEnabled("cut_left"), true)
        Runtime.button(Runtime.CUTTER_CONTROLS.cut_right, "CUT  ·  K",
            pointerX, pointerY, Runtime.cutterButtonEnabled("cut_right"), true)
        for _, rect in ipairs({ Runtime.CUTTER_CONTROLS.cut_left, Runtime.CUTTER_CONTROLS.cut_right }) do
            Runtime.MachineScreen.drawCutterButton(assets, { x = rect.x + 10, y = rect.y + 3,
                width = 56, height = 56, label = "" }, false,
                view.step == "armed" or view.step == "cutting")
        end
    end
end

return Component
