-- Remote wrapper production and maintenance presentation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.drawWrapperTabs(pointerX, pointerY)
        local activeService = tostring(Runtime.Screen.view and Runtime.Screen.view.serviceStep or "idle") ~= "idle"
        Runtime.button(Runtime.WRAPPER_TABS.production, "PRODUCTION", pointerX, pointerY,
            not Runtime.Screen.waiting and not activeService, Runtime.Screen.wrapperTab == "production")
        Runtime.button(Runtime.WRAPPER_TABS.service, activeService and "SERVICE ACTIVE" or "SERVICE",
            pointerX, pointerY, not Runtime.Screen.waiting, Runtime.Screen.wrapperTab == "service")
    end

    function Runtime.drawWrapperProduction(state, pointerX, pointerY)
        local runtime = Runtime.Wrapper.snapshot()
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("HOST CYCLE", 142, 174)
        love.graphics.print(string.upper(runtime.step), 270, 174)
        local ratio = math.min(1, runtime.progress / math.max(0.001, runtime.cycleTime))
        love.graphics.setColor(0.18, 0.21, 0.22)
        love.graphics.rectangle("fill", 420, 174, 380, 18, 3, 3)
        love.graphics.setColor(0.92, 0.72, 0.20)
        love.graphics.rectangle("fill", 420, 174, 380 * ratio, 18, 3, 3)
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("NEARBY FINISHED PALLETS", 142, 198)
        local rows = Runtime.wrapperRows(state)
        if #rows == 0 then
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf("No eligible pallet is parked by the wrapper.", Runtime.ROW_X, 254, Runtime.ROW_W, "center")
        end
        for index, item in ipairs(rows) do
            local rect = Runtime.wrapperRowRect(index)
            local selected = item.palletId == Runtime.Screen.selectedPalletId
            love.graphics.setColor(selected and 0.91 or 0.79, selected and 0.72 or 0.78,
                selected and 0.24 or 0.73)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
            love.graphics.setColor(0.08, 0.10, 0.11)
            love.graphics.print(tostring(item.palletId), rect.x + 14, rect.y + 9)
            love.graphics.printf(tostring(item.jobLabel or "Client pallet"),
                rect.x + 170, rect.y + 9, 300, "left")
            love.graphics.printf(string.upper(tostring(item.packaging or "flat")),
                rect.x + 520, rect.y + 9, 134, "right")
        end
        Runtime.button(Runtime.CONFIRM, runtime.step == "wrapping" and "WRAPPING..." or "START CYCLE",
            pointerX, pointerY, Runtime.Screen.wrapperStartEnabled(state), true)
    end

    function Runtime.drawWrapperService(state, pointerX, pointerY)
        local view = Runtime.Screen.view or {}
        local stock = state and state.inventory and state.inventory.stock or {}
        local item = Runtime.MachineFleet.installed(state, "skid_wrapper")
        local step = tostring(view.serviceStep or "idle")
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("WRAPPER SERVICE  ·  HOST-OWNED QUALITY + SAVE", 142, 174)
        love.graphics.printf(string.format("KITS %d  ·  CONDITION %.1f%%",
            tonumber(stock.maintenance_kit) or 0,
            item and Runtime.MachineFleet.condition(item) or 0), 490, 174, 328, "right")
        love.graphics.setColor(0.18, 0.21, 0.22)
        love.graphics.rectangle("fill", 142, 198, 676, 12, 3, 3)
        love.graphics.setColor(0.18, 0.58, 0.29)
        love.graphics.rectangle("fill", 142, 198,
            676 * math.max(0, math.min(1, (tonumber(view.servicePermille) or 0) / 1000)),
            12, 3, 3)

        if step == "idle" then
            local plan = item and Runtime.MachineFleet.maintenancePlan(state, item.id)
            for index, task in ipairs(plan and plan.tasks or {}) do
                local column = (index - 1) % 2
                local row = math.floor((index - 1) / 2)
                local x, y = 142 + column * 342, 230 + row * 94
                love.graphics.setColor(0.79, 0.78, 0.72)
                love.graphics.rectangle("fill", x, y, 326, 78, 4, 4)
                love.graphics.setColor(0.10, 0.12, 0.13)
                love.graphics.print(string.upper(tostring(task.componentLabel)), x + 12, y + 10)
                love.graphics.printf(tostring(task.label), x + 12, y + 34, 302, "left")
            end
            love.graphics.setColor(0.22, 0.27, 0.27)
            love.graphics.printf("The turntable must be empty. One delivered maintenance kit is consumed only after all four host-ordered tasks are complete.",
                166, 424, 628, "center")
            Runtime.button(Runtime.WRAPPER_SERVICE_BEGIN, "START FULL SERVICE", pointerX, pointerY,
                Runtime.wrapperServiceBeginEnabled(state), true)
            return
        end

        local target, task = Runtime.wrapperServiceTarget(view)
        love.graphics.setColor(0.74, 0.76, 0.72)
        love.graphics.rectangle("fill", Runtime.WRAPPER_SERVICE_WORK.x, Runtime.WRAPPER_SERVICE_WORK.y + 18,
            Runtime.WRAPPER_SERVICE_WORK.width, Runtime.WRAPPER_SERVICE_WORK.height - 18, 5, 5)
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print(string.format("STEP %d / %d  ·  %s",
            tonumber(view.serviceTaskIndex) or 1,
            tonumber(view.serviceTaskCount) or 4,
            task and task.component or "SERVICE TASK"), 166, 236)
        love.graphics.printf(task and task.instruction or "Use the active service marker.",
            166, 266, 420, "left")
        love.graphics.print(string.format("TARGET %d / %d",
            tonumber(view.servicePhase) or 1,
            tonumber(view.serviceTargetCount) or 1), 166, 438)
        if target then
            local cx, cy = target.x + target.width / 2, target.y + target.height / 2
            local pulse = 24 + math.sin((Runtime.Screen.wrapperClock or 0) * 6) * 5
            love.graphics.setColor(0.98, 0.72, 0.18, 0.24)
            love.graphics.circle("fill", cx, cy, pulse)
            love.graphics.setColor(0.95, 0.58, 0.08)
            love.graphics.circle("fill", cx, cy, 17)
            love.graphics.setColor(0.12, 0.14, 0.14)
            love.graphics.circle("fill", cx, cy, 6)
        end
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.printf(string.format("ATTEMPTS %d\nMISSES %d",
            tonumber(view.serviceAttempts) or 0, tonumber(view.serviceMisses) or 0),
            650, 254, 150, "left")
        love.graphics.setColor(0.22, 0.27, 0.27)
        love.graphics.printf("Tap the gold marker. Taps elsewhere in the service bay count as misses and reduce repair quality.",
            640, 354, 170, "center")
        Runtime.button(Runtime.WRAPPER_SERVICE_CANCEL, "CANCEL SERVICE", pointerX, pointerY,
            not Runtime.Screen.waiting, false)
    end

    function Runtime.drawWrapper(state, pointerX, pointerY)
        Runtime.drawWrapperTabs(pointerX, pointerY)
        if Runtime.Screen.wrapperTab == "service" then
            Runtime.drawWrapperService(state, pointerX, pointerY)
        else
            Runtime.drawWrapperProduction(state, pointerX, pointerY)
        end
    end
end

return Component
