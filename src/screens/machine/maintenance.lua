-- Cutter help and maintenance hub presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}
local BladeProfiles = require("src.machine.cutter.blade_profiles")
local bladeUpgradeFont

local function drawBladeUpgradeCard(rect, label, enabled, pointerX, pointerY)
    local hovered = enabled and pointerX and pointerX >= rect.x and pointerX <= rect.x + rect.width
        and pointerY >= rect.y and pointerY <= rect.y + rect.height
    love.graphics.push("all")
    local fillRed = enabled and (hovered and 0.13 or 0.08) or 0.08
    local fillGreen = enabled and 0.20 or 0.10
    local fillBlue = enabled and 0.20 or 0.11
    love.graphics.setColor(fillRed, fillGreen, fillBlue, 1)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4)
    love.graphics.setColor(enabled and 0.34 or 0.25, enabled and 0.65 or 0.29, enabled and 0.57 or 0.30, 1)
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 4)
    bladeUpgradeFont = bladeUpgradeFont or require('src.screens.typography').get(12)
    love.graphics.setFont(bladeUpgradeFont)
    love.graphics.setColor(enabled and 0.92 or 0.49, enabled and 0.85 or 0.54, enabled and 0.63 or 0.54, 1)
    love.graphics.printf(label, rect.x + 8, rect.y + 8, rect.width - 16, "center")
    love.graphics.pop()
end

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
        love.graphics.push('all')
        local hovered = enabled and pointerX and Runtime.inside(rect, pointerX, pointerY)
        Runtime.box(rect.x, rect.y, rect.width, rect.height,
            enabled and (hovered and { 0.13, 0.34, 0.31, 1 } or { 0.08, 0.20, 0.20, 1 })
                or { 0.09, 0.10, 0.11, 1 },
            enabled and { 0.34, 0.65, 0.57, 1 } or { 0.25, 0.29, 0.30, 1 }, 4)
        love.graphics.setColor(enabled and 0.96 or 0.48, enabled and 0.84 or 0.53, enabled and 0.30 or 0.52)
        love.graphics.setFont(require('src.screens.typography').get(14,'bold'))
        love.graphics.print(title, rect.x + 18, rect.y + 13)
        love.graphics.setColor(enabled and 0.76 or 0.46, enabled and 0.84 or 0.51, enabled and 0.83 or 0.51)
        love.graphics.setFont(require('src.screens.typography').get(14))
        love.graphics.printf(detail, rect.x + 18, rect.y + 36, rect.width - 36, "left")
        love.graphics.pop()
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
        local bladeState = cutter.spareBladeInstalled and "SPARE INSTALLED • DULL SLEEVED"
            or cutter.bladeInSleeve and "SECURED IN WOODEN SLEEVE"
            or cutter.bladeRemoved and "REMOVED" or "INSTALLED"
        local installedGrade = BladeProfiles.get(cutter.bladeGrade) or BladeProfiles.get("standard")
        love.graphics.printf(installedGrade.shortName .. " / " .. bladeState, 330, 153, 270, "left")
        love.graphics.print("TECHNICIAN", 620, 126)
        local appointment = cutter.nextTechnicianDay
            and Runtime.BusinessCalendar.dateFromTotalDay(cutter.nextTechnicianDay) or nil
        love.graphics.print(appointment and string.format("%s %d", Runtime.BusinessCalendar.monthName(appointment.month), appointment.day)
            or "NOT SCHEDULED", 620, 153)
        Runtime.drawMaintenanceCard(Runtime.oilServiceButton, "LUBRICATE THE CUTTER",
            "Lockout, clean and grease the service fittings, then inspect the gearbox sight glass. Uses one kit.",
            (stock.maintenance_kit or 0) > 0 and not cutter.bladeRemoved, pointerX, pointerY)
        Runtime.drawMaintenanceCard(Runtime.bladeServiceButton, "REMOVE & SLEEVE BLADE",
            cutter.bladeInSleeve and "Dull blade is sleeved and ready for the exchange courier."
                or "Release the fasteners, remove the knife, and secure it inside the wooden transport sleeve.",
            not cutter.bladeInSleeve, pointerX, pointerY)
        Runtime.drawMaintenanceCard(Runtime.technicianButton, "REQUEST BLADE COURIER",
            cutter.bladeInSleeve and cutter.spareBladeInstalled
                and "Book Mara Mouse to collect the dull blade. Your spare stays installed."
                or cutter.bladeInSleeve and "Book Mara Mouse to collect this blade and fit a sharpened replacement."
                or "Prepare the blade in its sleeve before booking.",
            cutter.bladeInSleeve and not cutter.nextTechnicianDay, pointerX, pointerY)
        local bladeStock = stock.cutter_blade or 0
        local spareReady = cutter.bladeRemoved and cutter.bladeInSleeve
            and not cutter.spareBladeInstalled and bladeStock > 0
        local spareDetail
        if spareReady then
            spareDetail = string.format("%d sharp spare(s); dull blade stays sleeved.", bladeStock)
        elseif cutter.spareBladeInstalled then
            spareDetail = "Spare installed; dull blade remains sleeved."
        elseif bladeStock <= 0 then
            spareDetail = "Buy a spare on CritterNet WrenchWorks."
        else
            spareDetail = "Sleeve the dull blade, then install a spare."
        end
        Runtime.drawMaintenanceCard(Runtime.spareBladeButton, "INSTALL SPARE BLADE", spareDetail,
            spareReady, pointerX, pointerY)
        for _, grade in ipairs(BladeProfiles.ORDER) do
            local profile = BladeProfiles.get(grade)
            local rect = Runtime.bladeUpgradeButtons[grade]
            local alreadyInstalled = cutter.bladeGrade == grade
            local isUpgrade = BladeProfiles.isUpgrade(cutter.bladeGrade, grade)
            local pending = cutter.orderedBladeGrade ~= nil
            local affordable = (state.money or 0) >= profile.price
            local enabled = isUpgrade and not pending and not cutter.spareBladeInstalled and affordable
            local label
            if pending then
                label = "ORDERED: " .. BladeProfiles.get(cutter.orderedBladeGrade).name .. " / MARA FITS NEXT EXCHANGE"
            elseif alreadyInstalled then label = "INSTALLED: " .. profile.name
            elseif not isUpgrade then label = "CURRENT BLADE IS A HIGHER GRADE"
            elseif cutter.spareBladeInstalled then label = "FINISH CURRENT SPARE-BLADE EXCHANGE FIRST"
            elseif not affordable then label = string.format("NEED $%d AVAILABLE", profile.price)
            else
                local wearReduction = math.floor((1 - profile.wearMultiplier) * 100 + 0.5)
                label = string.format("%s $%d  ·  %d%% SLOWER  ·  %d%% EDGE FLOOR",
                    profile.shortName, profile.price, wearReduction, math.floor(profile.qualityFloor * 100 + 0.5))
            end
            drawBladeUpgradeCard(rect, label, enabled, pointerX, pointerY)
        end
        Runtime.drawMaintenanceCard(Runtime.weeklyButton, cutter.weeklyTechnician and "WEEKLY SERVICE: ON" or "WEEKLY SERVICE: OFF",
            cutter.weeklyTechnician and "Click to cancel the recurring blade exchange."
                or "Blade exchange every 7 game days. Delays arrive by email.",
            true, pointerX, pointerY)
        Runtime.drawMaintenanceCard(Runtime.maintenanceBack, "RETURN TO CUTTER", "", true, pointerX, pointerY)
        love.graphics.setColor(0.70, 0.78, 0.79)
        love.graphics.print(state.message or "", 270, 610)
    end

    Runtime.wrapperServiceButton = { x = 650, y = 520, width = 240, height = 54 }
end

return Component
