-- Cutter oiling, lubrication, and blade service presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.drawSmallAction(rect, label, active, complete, pointerX, pointerY)
        local hovered = pointerX and Runtime.inside(rect, pointerX, pointerY)
        Runtime.box(rect.x, rect.y, rect.width, rect.height,
            complete and { 0.12, 0.38, 0.24, 1 } or active and { 0.12, 0.34, 0.36, 1 }
                or hovered and { 0.15, 0.22, 0.23, 1 } or { 0.08, 0.12, 0.13, 1 },
            complete and { 0.35, 0.88, 0.48, 1 } or { 0.34, 0.56, 0.56, 1 }, 3)
        love.graphics.setColor(complete and { 0.55, 1, 0.65 } or { 0.88, 0.91, 0.88 })
        love.graphics.printf(label, rect.x, rect.y + rect.height / 2 - 7, rect.width, "center")
    end

    function Runtime.drawToolSprite(assets, frame, x, y, scale)
        local image, quad = assets.get("cutterMaintenanceTools"), assets.getQuad("cutterMaintenanceTool" .. frame)
        if image and quad then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(image, quad.quad, x, y, 0, scale or 0.45, scale or 0.45,
                quad.width / 2, quad.height / 2)
        end
    end

    function Runtime.drawOilingGame(state, assets, pointerX, pointerY)
        local session = Runtime.Screen.oilSession
        Runtime.box(18, 18, 924, 642, { 0.025, 0.04, 0.05, 0.995 }, { 0.42, 0.72, 0.61, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("POLAR 115 LUBRICATION PROCEDURE", 42, 34)
        love.graphics.setColor(0.70, 0.80, 0.81)
        love.graphics.print("Lock out power, prepare the grease gun, clean each fitting, couple, then pump 2-3 strokes.", 42, 62)
        love.graphics.setColor(0.10, 0.14, 0.14)
        love.graphics.rectangle("fill", 42, 88, 860, 10, 3, 3)
        love.graphics.setColor(0.30, 0.82, 0.48)
        love.graphics.rectangle("fill", 42, 88, 860 * Runtime.MachineMaintenance.lubricationProgress(session), 10, 3, 3)
        if session.stage == "lockout" then
            love.graphics.setColor(0.92, 0.70, 0.22)
            love.graphics.printf("STEP 1  /  LOCKOUT-TAGOUT — COMPLETE IN ORDER", 80, 135, 800, "center")
            Runtime.drawSmallAction(Runtime.lockoutButtons.disconnect, "1. MAIN DISCONNECT OFF",
                not session.lockout.disconnect, session.lockout.disconnect, pointerX, pointerY)
            Runtime.drawSmallAction(Runtime.lockoutButtons.key, "2. REMOVE KEY",
                session.lockout.disconnect and not session.lockout.key, session.lockout.key, pointerX, pointerY)
            Runtime.drawSmallAction(Runtime.lockoutButtons.tag, "3. APPLY LOCK + TAG",
                session.lockout.key and not session.lockout.tag, session.lockout.tag, pointerX, pointerY)
            Runtime.drawToolSprite(assets, 5, 750, 310, 0.46)
            love.graphics.setColor(0.70, 0.78, 0.78)
            love.graphics.printf("The cutter cannot be serviced while energized.", 170, 455, 620, "center")
        elseif session.stage == "prep" then
            love.graphics.setColor(0.92, 0.70, 0.22)
            love.graphics.printf("STEP 2  /  PREPARE THE HIGH-PRESSURE GREASE GUN", 80, 135, 800, "center")
            Runtime.drawSmallAction(Runtime.prepButtons.cartridge, "1. INSTALL GREASE CARTRIDGE",
                not session.prep.cartridge, session.prep.cartridge, pointerX, pointerY)
            Runtime.drawSmallAction(Runtime.prepButtons.prime, "2. PRIME THE GUN",
                session.prep.cartridge and not session.prep.primed, session.prep.primed, pointerX, pointerY)
            Runtime.drawToolSprite(assets, 6, 310, 325, 0.55)
            Runtime.drawToolSprite(assets, session.prep.cartridge and 2 or 1, 650, 325, 0.50)
        else
            for index, view in ipairs(Runtime.lubricationViews) do
                local rect = { x = 42 + (index - 1) * 113, y = 112, width = 105, height = 34 }
                local disabled = view == "central" and not session.centralInstalled
                Runtime.drawSmallAction(rect, disabled and "CENTRAL N/A" or view:upper(),
                    session.activeView == view, false, pointerX, pointerY)
            end
            Runtime.box(42, 158, 570, 386, { 0.06, 0.075, 0.08, 1 }, { 0.25, 0.39, 0.40, 1 }, 4)
            local sceneFrames = { rear = 1, front = 2, side = 3, central = 2, gear = 4 }
            local image = assets.get("cutterMaintenanceScenes")
            local quad = assets.getQuad("cutterMaintenanceScene" .. sceneFrames[session.activeView])
            if image and quad then
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(image, quad.quad, 48, 160, 0, 1.09, 1.0)
            end
            if session.activeView == "gear" then
                love.graphics.setColor(session.gear.inspected and { 0.30, 0.90, 0.48 } or { 1, 0.76, 0.22 })
                love.graphics.circle("line", 490, 340, 34 + math.sin(session.animationClock * 4) * 3)
                love.graphics.printf(string.format("SIGHT GLASS  %d%%", math.floor(session.gear.level * 100 + 0.5)), 350, 475, 230, "center")
            elseif session.activeView == "central" then
                local p = session.central
                love.graphics.setColor(p.complete and { 0.30, 0.90, 0.48 } or { 1, 0.76, 0.22 })
                love.graphics.circle("line", 370, 330, 23 + math.sin(session.animationClock * 4) * 3)
            else
                for _, p in ipairs(session.points) do if p.view == session.activeView then
                    love.graphics.setColor(p.complete and { 0.30, 0.90, 0.48 }
                        or p.cleaned and { 0.32, 0.76, 0.88 } or { 1, 0.72, 0.18 })
                    love.graphics.circle("fill", p.x, p.y, p.complete and 11 or 8)
                    love.graphics.circle("line", p.x, p.y, 18 + math.sin(session.animationClock * 5) * 3)
                end end
            end
            Runtime.box(632, 158, 270, 386, { 0.055, 0.09, 0.095, 1 }, { 0.25, 0.43, 0.42, 1 }, 4)
            for index, tool in ipairs(Runtime.lubricationTools) do
                local rect = { x = 650, y = 176 + (index - 1) * 48, width = 234, height = 39 }
                Runtime.drawSmallAction(rect, ({ rag="CLEANING RAG", grease="GREASE GUN", inspect="INSPECT LIGHT", gear_oil="GEAR OIL" })[tool],
                    session.activeTool == tool, false, pointerX, pointerY)
            end
            local status = session.coupledPoint and (session.coupledPoint == "central" and session.central
                or Runtime.MachineMaintenance.lubricationPoint(session, session.coupledPoint)) or nil
            love.graphics.setColor(0.72, 0.82, 0.82)
            love.graphics.printf("NEXT: " .. Runtime.MachineMaintenance.nextCutterLubricationStep(session),
                650, 370, 234, "center")
            if status then
                local gunFrame = session.pumpPulse and session.pumpPulse > 0
                    and (session.pumpPulse > 0.14 and 3 or 2) or 1
                Runtime.drawToolSprite(assets, gunFrame, 767, 424, 0.25)
            end
            Runtime.drawSmallAction(Runtime.pumpButton, "PUMP GREASE-GUN LEVER", status ~= nil, false, pointerX, pointerY)
            Runtime.drawSmallAction(Runtime.finishLubricationButton, "RETURN TO SERVICE",
                Runtime.MachineMaintenance.canFinishCutterLubrication(session), false, pointerX, pointerY)
        end
        Runtime.drawSmallAction(Runtime.maintenanceBack, "CANCEL PROCEDURE", false, false, pointerX, pointerY)
    end

    function Runtime.bladeBoltPositions()
        local positions = {}
        for index, sourceX in ipairs({ 181, 244, 305, 366, 426 }) do
            positions[index] = { 480 + (sourceX - 256) * 1.2, 310 + (295 - 256) * 1.2 }
        end
        return positions
    end

    function Runtime.drawBladeGame(state, assets, pointerX, pointerY)
        local screen = Runtime.Screen
        local now = love.timer.getTime()
        local stage = screen.bladeStage
        local removed = 0
        for index = 1, 5 do
            if screen.bladeBolts[index] then removed = removed + 1 end
        end
        if stage == "lifting" and now - (screen.bladeLiftStarted or now) >= 0.62 then
            stage = "sleeve"
            screen.bladeStage = stage
        end

        local function drawPart(frame, x, y, scale, rotation)
            local image = assets and assets.get("cutterBladeRemoval")
            local sprite = assets and assets.getQuad("cutterBladeRemoval" .. frame)
            if image and sprite then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(image, sprite.quad, x, y, rotation or 0,
                    scale, scale, sprite.width / 2, sprite.height / 2)
                return true
            end
            return false
        end

        Runtime.box(18, 18, 924, 642, { 0.03, 0.045, 0.055, 0.995 }, { 0.55, 0.46, 0.30, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("CUTTER BLADE REMOVAL", 42, 34)
        love.graphics.setColor(0.72, 0.80, 0.81)
        local instruction = stage == "bolts" and "Back out each of the five carrier bolts and set them in the parts tray."
            or stage == "blade" and "All five bolts are clear. Lift the blade by its safe ends."
            or stage == "lifting" and "Supporting the blade... keep it level and clear of the carrier."
            or "Place the blade fully inside its wooden safety sleeve."
        love.graphics.print(instruction, 42, 64)
        Runtime.box(140, 120, 680, 420, { 0.08, 0.09, 0.095, 1 }, { 0.34, 0.36, 0.37, 1 }, 4)
        love.graphics.setColor(0.12, 0.15, 0.16, 1)
        love.graphics.rectangle("fill", 154, 134, 652, 392, 6, 6)

        if stage == "bolts" then
            drawPart(1, 480, 310, 1.2)
        elseif stage == "blade" or stage == "lifting" then
            drawPart(3, 480, 310, 1.2)
            local lift = stage == "lifting" and math.min(1, (now - (screen.bladeLiftStarted or now)) / 0.62) or 0
            drawPart(4, 480, 420 + lift * 20, 0.68, lift * 0.035)
            drawPart(6, 765, 442, 0.31)
        else
            drawPart(5, 480, 430, 0.5)
            drawPart(4, 480, 454, 0.52)
            drawPart(6, 765, 442, 0.31)
        end

        if stage == "bolts" then
            local tray = { x = 704, y = 436, width = 184, height = 76 }
            love.graphics.setColor(0.045, 0.06, 0.065, 0.96)
            love.graphics.rectangle("fill", tray.x, tray.y, tray.width, tray.height, 8, 8)
            love.graphics.setColor(0.46, 0.56, 0.58, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", tray.x, tray.y, tray.width, tray.height, 8, 8)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(0.88, 0.83, 0.65, 1)
            love.graphics.printf("FASTENERS  " .. removed .. " / 5", tray.x, tray.y + 7, tray.width, "center")
            local boltImage = assets and assets.get("cutterBladeRemoval")
            local boltQuad = assets and assets.getQuad("cutterBladeRemoval2")
            for index = 1, 5 do
                local pos = Runtime.bladeBoltPositions()[index]
                local targetX, targetY = tray.x + 30 + (index - 1) * 30, tray.y + 50
                local isRemoved = screen.bladeBolts[index] == true
                local animation = screen.bladeBoltAnimations and screen.bladeBoltAnimations[index]
                if boltImage and boltQuad and not isRemoved then
                    love.graphics.setColor(0.78, 0.83, 0.84, 1)
                    love.graphics.draw(boltImage, boltQuad.quad, pos[1], pos[2], 0, 0.105, 0.105,
                        boltQuad.width / 2, boltQuad.height / 2)
                elseif boltImage and boltQuad and isRemoved then
                    local progress = animation and math.min(1, math.max(0, (now - animation) / 0.42)) or 1
                    local x = pos[1] + (targetX - pos[1]) * progress
                    local y = pos[2] + (targetY - pos[2]) * progress
                    local scale = 0.105 - progress * 0.054
                    love.graphics.setColor(0.85, 0.88, 0.86, 1)
                    love.graphics.draw(boltImage, boltQuad.quad, x, y,
                        (1 - progress) * 3.6, scale, scale, boltQuad.width / 2, boltQuad.height / 2)
                end
            end
        elseif stage == "sleeve" then
            love.graphics.setColor(0.88, 0.83, 0.65, 1)
            love.graphics.printf("BLADE SECURED IN WOODEN SAFETY SLEEVE", 275, 500, 410, "center")
        end

        love.graphics.setColor(0.12, 0.15, 0.16, 1)
        love.graphics.rectangle("fill", 42, 96, 860, 8, 4, 4)
        love.graphics.setColor(0.34, 0.73, 0.65, 1)
        love.graphics.rectangle("fill", 42, 96, 860 * (stage == "bolts" and removed / 5 or 1), 8, 4, 4)
        Runtime.drawMaintenanceCard(Runtime.maintenanceBack, "CANCEL BLADE WORK", "", true, pointerX, pointerY)
    end
end

return Component
