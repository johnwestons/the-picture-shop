-- Wrapper maintenance presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.wrapperHealthColor(value)
        if value >= 75 then return 0.30, 0.82, 0.48
        elseif value >= 50 then return 0.94, 0.70, 0.22 end
        return 0.92, 0.32, 0.24
    end

    function Runtime.drawWrapperHealthBar(x, y, width, value)
        local r, g, b = Runtime.wrapperHealthColor(value)
        love.graphics.setColor(0.10, 0.13, 0.14)
        love.graphics.rectangle("fill", x, y, width, 7, 2, 2)
        love.graphics.setColor(r, g, b)
        love.graphics.rectangle("fill", x, y, width * math.max(0, math.min(100, value)) / 100, 7, 2, 2)
    end

    function Runtime.drawWrapperMaintenanceHub(state, pointerX, pointerY)
        local item = Runtime.MachineFleet.installed(state, "skid_wrapper")
        local stock = state.inventory and state.inventory.stock or {}
        local plan = item and Runtime.MachineFleet.maintenancePlan(state, item.id)
        local nearby = Runtime.Wrapper.nearbyPallet(state)
        local safetyReady = not Runtime.Wrapper.isActive() and not nearby
        local kitReady = (stock.maintenance_kit or 0) > 0
        Runtime.box(18, 18, 924, 642, { 0.025, 0.05, 0.055, 0.995 }, { 0.35, 0.72, 0.60, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("SKID WRAPPER SERVICE BAY", 46, 36)
        love.graphics.setColor(0.70, 0.82, 0.82)
        love.graphics.print("Hands-on inspection follows the turntable, film carriage, drive, and controls.", 46, 66)
        Runtime.drawCondition(state, "skid_wrapper", 562, 36, 328)

        Runtime.box(54, 98, 836, 50, { 0.07, 0.11, 0.12, 1 }, { 0.25, 0.43, 0.43, 1 }, 3)
        love.graphics.setColor(0.76, 0.84, 0.84)
        love.graphics.print("SAFETY CHECK", 74, 116)
        love.graphics.setColor(safetyReady and 0.35 or 0.94, safetyReady and 0.86 or 0.34, 0.42)
        love.graphics.print(safetyReady and "CLEAR: STOPPED / TURNTABLE EMPTY" or
            (Runtime.Wrapper.isActive() and "BLOCKED: WRAPPING CYCLE ACTIVE" or "BLOCKED: MOVE PALLET AWAY FIRST"), 250, 116)
        love.graphics.setColor(0.76, 0.84, 0.84)
        love.graphics.print("KIT", 720, 116)
        love.graphics.setColor(kitReady and 0.35 or 0.94, kitReady and 0.86 or 0.34, 0.42)
        love.graphics.print(tostring(stock.maintenance_kit or 0), 770, 116)

        if plan then
            for index, task in ipairs(plan.tasks) do
                local column = (index - 1) % 2
                local row = math.floor((index - 1) / 2)
                local x, y = 54 + column * 412, 168 + row * 142
                local value = tonumber(item.variables[task.id]) or 0
                local r, g, b = Runtime.wrapperHealthColor(value)
                Runtime.box(x, y, 390, 122, { 0.065, 0.105, 0.11, 1 }, { 0.24, 0.40, 0.41, 1 }, 4)
                love.graphics.setColor(0.95, 0.85, 0.38)
                love.graphics.print(string.format("%d  %s", index, task.componentLabel:upper()), x + 16, y + 14)
                love.graphics.setColor(0.72, 0.81, 0.81)
                love.graphics.printf(task.label, x + 16, y + 42, 350, "left")
                love.graphics.setColor(r, g, b)
                love.graphics.print(string.format("HEALTH  %.1f%%", value), x + 16, y + 78)
                Runtime.drawWrapperHealthBar(x + 150, y + 84, 220, value)
            end
        end
        local startEnabled = item and safetyReady and kitReady
        local hovered = startEnabled and Runtime.inside(Runtime.wrapperServiceButton, pointerX or -1, pointerY or -1)
        Runtime.box(Runtime.wrapperServiceButton.x, Runtime.wrapperServiceButton.y, Runtime.wrapperServiceButton.width, Runtime.wrapperServiceButton.height,
            startEnabled and (hovered and { 0.18, 0.50, 0.36, 1 } or { 0.12, 0.38, 0.28, 1 })
                or { 0.14, 0.17, 0.17, 1 }, { 0.35, 0.70, 0.50, 1 }, 3)
        love.graphics.setColor(0.95, 0.98, 0.92)
        love.graphics.printf(startEnabled and "START FULL SERVICE" or "SERVICE LOCKED",
            Runtime.wrapperServiceButton.x, Runtime.wrapperServiceButton.y + 19, Runtime.wrapperServiceButton.width, "center")
        Runtime.drawMaintenanceCard(Runtime.maintenanceBack, "RETURN TO WRAPPER", "", true, pointerX, pointerY)
        love.graphics.setColor(0.70, 0.78, 0.79)
        love.graphics.print(state.message or "", 270, 610)
    end

    function Runtime.drawWrapperTarget(x, y, active, complete, clock)
        if complete then
            love.graphics.setColor(0.24, 0.85, 0.48, 0.92)
            love.graphics.circle("fill", x, y, 16)
        elseif active then
            local pulse = 24 + math.sin(clock * 6) * 5
            love.graphics.setColor(0.98, 0.72, 0.18, 0.22)
            love.graphics.circle("fill", x, y, pulse)
            love.graphics.setColor(1, 0.84, 0.30, 1)
            love.graphics.circle("line", x, y, 18)
        else
            love.graphics.setColor(0.42, 0.53, 0.52, 0.68)
            love.graphics.circle("line", x, y, 13)
        end
        love.graphics.setColor(0.04, 0.06, 0.06, 1)
        love.graphics.circle("fill", x, y, 5)
    end

    function Runtime.drawWrapperMaintenanceTask(state, assets, pointerX, pointerY)
        local session = Runtime.Screen.wrapperSession
        local task = session and Runtime.MachineMaintenance.activeTask(session)
        local taskState = session and Runtime.MachineMaintenance.wrapperTaskState(session)
        if not session or not task or not taskState then return end
        local image = assets.get("wrapperMaintenanceAtlas")
        local sprite = assets.getQuad("wrapperMaintenance" .. ({
            turntableBearing = 1, filmCarriage = 2, driveBelt = 3, controlBoard = 4,
        })[task.id])
        Runtime.box(18, 18, 924, 642, { 0.025, 0.04, 0.05, 0.995 }, { 0.45, 0.72, 0.60, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print(string.format("WRAPPER SERVICE  /  STEP %d OF %d", session.activeIndex, #session.tasks), 42, 34)
        love.graphics.setColor(0.72, 0.81, 0.81)
        love.graphics.print("Use the marked service points in sequence. Every miss reduces the repair quality.", 42, 62)
        Runtime.box(54, 104, 520, 438, { 0.06, 0.075, 0.08, 1 }, { 0.25, 0.39, 0.40, 1 }, 4)
        if image and sprite then
            local scale = math.min(430 / sprite.width, 360 / sprite.height)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(image, sprite.quad, 314, 324, 0, scale, scale, sprite.width / 2, sprite.height / 2)
        end
        local targetCount = task.id == "driveBelt" and 1 or 3
        for index = 1, targetCount do
            local tx, ty = Runtime.MachineMaintenance.wrapperTarget(session, index)
            if tx and ty then
                Runtime.drawWrapperTarget(tx, ty, index == taskState.phase,
                    index < taskState.phase, session.animationClock)
            end
        end
        local rightX, rightY, rightW = 612, 104, 278
        Runtime.box(rightX, rightY, rightW, 438, { 0.065, 0.10, 0.105, 1 }, { 0.25, 0.43, 0.42, 1 }, 4)
        love.graphics.setColor(0.95, 0.85, 0.38)
        love.graphics.printf(task.componentLabel:upper(), rightX + 18, rightY + 18, rightW - 36, "left")
        love.graphics.setColor(0.82, 0.88, 0.87)
        love.graphics.printf(task.label, rightX + 18, rightY + 52, rightW - 36, "left")
        local instruction = task.id == "turntableBearing" and "Click the three bearing grease fittings around the turntable."
            or task.id == "filmCarriage" and "Follow the carriage service points from the upper roller to the lower guide."
            or task.id == "driveBelt" and "Click the moving tension target when it crosses the green timing band."
            or "Test the control cabinet points in order: power, safety loop, then reset."
        love.graphics.setColor(0.64, 0.75, 0.75)
        love.graphics.printf(instruction, rightX + 18, rightY + 102, rightW - 36, "left")
        love.graphics.setColor(0.78, 0.86, 0.84)
        love.graphics.print(string.format("TARGET  %d / %d", math.min(taskState.phase, targetCount), targetCount), rightX + 18, rightY + 200)
        love.graphics.print(string.format("ATTEMPTS  %d", taskState.attempts), rightX + 18, rightY + 232)
        love.graphics.print(string.format("MISSES  %d", taskState.misses), rightX + 18, rightY + 264)
        local progress = math.min(1, (taskState.phase - 1) / targetCount)
        love.graphics.setColor(0.10, 0.14, 0.14)
        love.graphics.rectangle("fill", rightX + 18, rightY + 310, rightW - 36, 12, 3, 3)
        love.graphics.setColor(0.30, 0.82, 0.48)
        love.graphics.rectangle("fill", rightX + 18, rightY + 310, (rightW - 36) * progress, 12, 3, 3)
        love.graphics.setColor(0.96, 0.74, 0.24)
        love.graphics.printf(task.id == "driveBelt" and "TIMING TARGET MOVING" or "SEQUENCE TARGET ACTIVE",
            rightX + 18, rightY + 346, rightW - 36, "center")
        Runtime.drawMaintenanceCard(Runtime.maintenanceBack, "CANCEL SERVICE", "", true, pointerX, pointerY)
        love.graphics.setColor(0.72,0.82,0.82)
        love.graphics.printf("No kit is consumed until all four tasks are complete.",280,608,590,"left")
    end
end

return Component
