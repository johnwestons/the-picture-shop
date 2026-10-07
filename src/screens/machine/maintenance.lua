-- Cutter help and maintenance hub presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.drawHelp(state, assets, pointerX, pointerY)
        Runtime.box(18, 18, 924, 642, { 0.035, 0.055, 0.065, 0.995 }, { 0.35, 0.68, 0.61, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("POLAR 115 OPERATOR HELP", 46, 38)
        love.graphics.setColor(0.11, 0.15, 0.17)
        love.graphics.rectangle("fill", 72, 104, 814, 430, 7, 7)
        local page = Runtime.cutterHelp[Runtime.Screen.helpStep]
        love.graphics.setColor(0.96, 0.82, 0.28)
        love.graphics.printf(page[1], 108, 142, 742, "center")
        love.graphics.setColor(0.86, 0.91, 0.90)
        love.graphics.printf(page[2], 118, 208, 722, "left")
        love.graphics.setColor(0.66, 0.76, 0.76)
        love.graphics.printf(string.format("PAGE %d / %d", Runtime.Screen.helpStep, #Runtime.cutterHelp), 118, 490, 722, "center")
        Runtime.BackButton.draw(assets, Runtime.helpBack, "BACK", pointerX, pointerY, false)
        Runtime.BackButton.draw(assets, Runtime.helpPrevious, "◀ PREV", pointerX, pointerY, false)
        Runtime.BackButton.draw(assets, Runtime.helpNext, Runtime.Screen.helpStep == #Runtime.cutterHelp and "DONE" or "NEXT ▶", pointerX, pointerY, false)
    end

    function Runtime.drawHelpButton(assets, pointerX, pointerY)
        local hovered = pointerX and Runtime.inside(Runtime.helpButton, pointerX, pointerY)
        Runtime.CutterSkin.button(assets, Runtime.helpButton.x, Runtime.helpButton.y, Runtime.helpButton.width, Runtime.helpButton.height,
            hovered and "hover" or "normal")
        love.graphics.setColor(0.94, 0.97, 0.92)
        love.graphics.printf("HELP / INSTRUCTIONS", Runtime.helpButton.x, Runtime.helpButton.y + 13, Runtime.helpButton.width, "center")
    end

    function Runtime.drawMaintenanceButton(assets, pointerX, pointerY)
        local hovered = pointerX and Runtime.inside(Runtime.maintenanceButton, pointerX, pointerY)
        Runtime.CutterSkin.button(assets, Runtime.maintenanceButton.x, Runtime.maintenanceButton.y,
            Runtime.maintenanceButton.width, Runtime.maintenanceButton.height, hovered and "hover" or "normal")
        love.graphics.setColor(0.94, 0.97, 0.92)
        love.graphics.printf("MAINTENANCE", Runtime.maintenanceButton.x, Runtime.maintenanceButton.y + 13,
            Runtime.maintenanceButton.width, "center")
    end

    function Runtime.drawMaintenanceCard(rect, title, detail, enabled, pointerX, pointerY)
        local hovered = enabled and pointerX and Runtime.inside(rect, pointerX, pointerY)
        Runtime.box(rect.x, rect.y, rect.width, rect.height,
            enabled and (hovered and { 0.13, 0.34, 0.31, 1 } or { 0.08, 0.20, 0.20, 1 })
                or { 0.09, 0.10, 0.11, 1 },
            enabled and { 0.34, 0.65, 0.57, 1 } or { 0.25, 0.29, 0.30, 1 }, 4)
        love.graphics.setColor(enabled and 0.96 or 0.48, enabled and 0.84 or 0.53, enabled and 0.30 or 0.52)
        love.graphics.print(title, rect.x + 18, rect.y + 16)
        love.graphics.setColor(enabled and 0.76 or 0.46, enabled and 0.84 or 0.51, enabled and 0.83 or 0.51)
        love.graphics.printf(detail, rect.x + 18, rect.y + 46, rect.width - 36, "left")
    end

    function Runtime.drawMaintenanceHub(state, assets, pointerX, pointerY)
        local item, cutter = Runtime.MachineMaintenance.cutterStatus(state)
        local stock = state.inventory and state.inventory.stock or {}
        Runtime.box(18, 18, 924, 642, { 0.035, 0.055, 0.065, 0.995 }, { 0.35, 0.68, 0.61, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("POLAR 115 MAINTENANCE CENTER", 46, 38)
        love.graphics.setColor(0.72, 0.82, 0.82)
        love.graphics.print("Choose a service procedure. Each task opens its own interactive work area.", 46, 68)
        Runtime.drawCondition(state, "polar_115", 580, 36, 310)
        Runtime.box(54, 108, 836, 92, { 0.07, 0.10, 0.12, 1 }, { 0.25, 0.42, 0.43, 1 }, 3)
        love.graphics.setColor(0.76, 0.84, 0.84)
        love.graphics.print("MAINTENANCE KITS", 74, 126)
        love.graphics.setColor((stock.maintenance_kit or 0) > 0 and 0.48 or 0.94,
            (stock.maintenance_kit or 0) > 0 and 0.88 or 0.34, 0.36)
        love.graphics.print(tostring(stock.maintenance_kit or 0) .. " AVAILABLE", 74, 153)
        love.graphics.setColor(0.76, 0.84, 0.84)
        love.graphics.print("BLADE", 330, 126)
        love.graphics.print(cutter.bladeInSleeve and "SECURED IN WOODEN SLEEVE"
            or cutter.bladeRemoved and "REMOVED" or "INSTALLED", 330, 153)
        love.graphics.print("TECHNICIAN", 620, 126)
        local appointment = cutter.nextTechnicianDay
            and Runtime.BusinessCalendar.dateFromTotalDay(cutter.nextTechnicianDay) or nil
        love.graphics.print(appointment and string.format("%s %d", Runtime.BusinessCalendar.monthName(appointment.month), appointment.day)
            or "NOT SCHEDULED", 620, 153)
        Runtime.drawMaintenanceCard(Runtime.oilServiceButton, "LUBRICATE THE CUTTER",
            "Lockout, clean and grease the service fittings, then inspect the gearbox sight glass. Uses one kit.",
            (stock.maintenance_kit or 0) > 0 and not cutter.bladeRemoved, pointerX, pointerY)
        Runtime.drawMaintenanceCard(Runtime.bladeServiceButton, "REMOVE & SLEEVE BLADE",
            cutter.bladeInSleeve and "Blade is ready for Precision Blade Service."
                or "Release the fasteners, remove the knife, and secure it inside the wooden transport sleeve.",
            not cutter.bladeInSleeve, pointerX, pointerY)
        Runtime.drawMaintenanceCard(Runtime.technicianButton, "REQUEST TECHNICIAN",
            cutter.bladeInSleeve and "Book the next available blade-sharpening visit."
                or "Prepare the blade in its sleeve before booking.",
            cutter.bladeInSleeve and not cutter.nextTechnicianDay, pointerX, pointerY)
        Runtime.drawMaintenanceCard(Runtime.weeklyButton, cutter.weeklyTechnician and "WEEKLY SERVICE: ON" or "WEEKLY SERVICE: OFF",
            cutter.weeklyTechnician and "Click to cancel the recurring appointment."
                or "Schedule a technician every seven game days. Delays or missed visits arrive by email.",
            true, pointerX, pointerY)
        Runtime.drawMaintenanceCard(Runtime.maintenanceBack, "RETURN TO CUTTER", "", true, pointerX, pointerY)
        love.graphics.setColor(0.70, 0.78, 0.79)
        love.graphics.print(state.message or "", 270, 610)
    end

    Runtime.wrapperServiceButton = { x = 650, y = 520, width = 240, height = 54 }
end

return Component
