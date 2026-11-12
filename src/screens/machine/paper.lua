-- Paper selection, loading, and sheet presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}
local CutterMotion = require("src.screens.cutter_motion")
local PAPER_STOP_CLEARANCE = 8

function Component.install(Runtime)
    function Runtime.openLoadMenu(state)
        if Runtime.Machine.step ~= "idle" and Runtime.Machine.step ~= "finished" then
            state.message = "Finish or unload the current cutter batch before choosing another pallet."
            return false
        end
        local options = {}
        for _, candidate in ipairs(Runtime.Machine.availablePapers(state)) do
            local world = candidate.pallet.world or {}
            options[#options + 1] = {
                palletId = candidate.pallet.id,
                title = candidate.pallet.id .. "  |  " .. tostring(candidate.job.company or candidate.job.id),
                detail = string.format("%s  |  %d sheets  |  %d lifts\n%.2f x %.2f -> %.2f x %.2f in",
                    tostring(candidate.paper.artworkKey or "artwork"),
                    candidate.pallet.remainingSheets or candidate.pallet.initialSheets or 0,
                    candidate.pallet.requiredLifts or 1,
                    candidate.paper.sourceSize.width,candidate.paper.sourceSize.height,
                    candidate.paper.finishedSize.width,candidate.paper.finishedSize.height),
                x = world.x, y = world.y,
            }
        end
        if #options == 0 and Runtime.Procurement.paperAvailable(state) > 0 then
            options[1] = {
                palletId = "__generic_stock__",
                title = "GENERIC SHOP STOCK",
                detail = string.format("%d stock sheets available", Runtime.Procurement.paperAvailable(state)),
            }
        end
        Runtime.Screen.loadMenu = { options = options, selected = 1 }
        Runtime.Screen.gaugeFocused = false
        state.message = #options > 0
            and "Choose which nearby pallet to load onto the cutter."
            or "No eligible paper is inside the cutter's expanded load radius. Move a skid closer or add generic stock."
        return true
    end

    function Runtime.loadSelected(state, index)
        local menu = Runtime.Screen.loadMenu
        local option = menu and menu.options[index or menu.selected]
        if not option then return false end
        local succeeded = Runtime.Machine.load(state, option.palletId)
        if succeeded then
            Runtime.Screen.loadMenu = nil
            Runtime.formatGauge()
        end
        return succeeded
    end

    function Runtime.Screen.syncGauge()
        Runtime.formatGauge()
    end

    function Runtime.drawButton(button, assets, pointerX, pointerY)
        if button.action == "cut_left" or button.action == "cut_right" or button.action == "estop" then return end
        local active = Runtime.Screen.pressedAction == button.action
        if button.action == "program" then active = Runtime.Machine.programIndex == button.value end
        local hovered = pointerX and pointerY and Runtime.inside(button, pointerX, pointerY)
        local visual = active and (button.action == "program" and "selected" or "pressed")
            or (hovered and "hover" or "normal")
        Runtime.CutterSkin.button(assets, button.x, button.y + (active and 2 or 0), button.width, button.height, visual)
        love.graphics.setColor(0.97, 0.97, 0.92)
        local label = button.label
        if button.action == "position" and Runtime.Machine.step == "positioned" then label = "PULL BACK" end
        love.graphics.printf(label, button.x, button.y + 9 + (active and 2 or 0), button.width, "center")
    end

    function Runtime.drawSpriteButton(assets, button, red, pressed)
        local image = assets.get("cutterControlButtons")
        local frame = red and (pressed and 4 or 3) or (pressed and 2 or 1)
        local sprite = assets.getQuad("cutterControlButton" .. frame)
        if not image or not sprite then return end
        local scale = math.min(button.width / sprite.width, button.height / sprite.height)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, sprite.quad, button.x + button.width / 2, button.y,
            0, scale, scale, sprite.width / 2, 0)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(button.label, button.x, button.y + button.height - 12, button.width, "center")
    end

    function Runtime.Screen.drawCutterButton(assets, button, red, pressed)
        Runtime.drawSpriteButton(assets, button, red, pressed)
    end

    function Runtime.artworkColor(id, offset)
        local hash = offset * 97
        for index = 1, #(id or "ART") do hash = (hash * 33 + id:byte(index)) % 997 end
        return 0.25 + (hash % 55) / 100, 0.25 + ((hash * 3) % 55) / 100, 0.25 + ((hash * 7) % 55) / 100
    end

    function Runtime.drawPaper(assets, machine, visualOrientation, turnProgress)
        local paper = machine.paper
        if not machine.loaded or not paper then return end
        local step = machine.step
        local transfer = math.max(0.001, tonumber(machine.transferTime) or 1)
        local t = math.max(0, math.min(1, (tonumber(machine.progress) or 0) / transfer))
        local function ease(value)
            value = math.max(0, math.min(1, value))
            return value * value * (3 - 2 * value)
        end
        local startY, cutLineY = 355, CutterMotion.cutLineY
        local orientation = (tonumber(paper.orientation) or 0) % 360
        visualOrientation = (tonumber(visualOrientation) or orientation) % 360
        local angle = math.rad(visualOrientation)
        local sourceWidth = tonumber(paper.currentSize.width) or 10
        local sourceHeight = tonumber(paper.currentSize.height) or 10
        local paperWidth = math.max(100, math.min(270, sourceWidth / 25 * 270))
        local paperHeight = math.max(50, math.min(270, sourceHeight / 25 * 270))
        local depthScale = 0.45
        local cosAngle, sinAngle = math.abs(math.cos(angle)), math.abs(math.sin(angle))
        local boundsWidth = cosAngle * paperWidth + sinAngle * paperHeight
        local boundsHeight = (sinAngle * paperWidth + cosAngle * paperHeight) * depthScale
        local bedY = math.max(cutLineY + 4, 271 - boundsHeight)
        local centerX, topY = 662, bedY
        local rotated = orientation % 180 == 90
        local gaugeAxisInches = rotated and sourceWidth or sourceHeight
        gaugeAxisInches = math.max(0.01, gaugeAxisInches)
        local gaugeInches = math.max(0, tonumber(machine.gauge) or gaugeAxisInches)
        local gaugePixels = gaugeInches / gaugeAxisInches * boundsHeight
        local workingY = cutLineY - gaugePixels

        if step == "loading" then
            if t < 0.56 then
                local phase = ease(t / 0.56)
                centerX = 690 - 16 * phase
                topY = startY + (296 - startY) * phase
            else
                local phase = ease((t - 0.56) / 0.44)
                centerX = 674 + (662 - 674) * phase
                topY = 296 + (bedY - 296) * phase
            end
        elseif step == "loaded" then
            -- On successive cuts the clamp still has to lift before the
            -- operator can draw the stock forward for the next turn.
            local withdrawal = ease(1 - (tonumber(machine.clampProgress) or 0) / 0.72)
            topY = workingY + (bedY - workingY) * withdrawal
        elseif step == "positioning" then
            -- Most of the push happens immediately, followed by a short settle against the stop.
            local phase = 1 - (1 - math.min(1, t / 0.82)) ^ 2
            topY = bedY + (workingY + PAPER_STOP_CLEARANCE - bedY) * phase
        elseif step == "retracting" then
            local phase = 1 - (1 - math.min(1, t / 0.82)) ^ 2
            topY = workingY + PAPER_STOP_CLEARANCE
                + (bedY - workingY - PAPER_STOP_CLEARANCE) * phase
        elseif step == "unloading" or step == "lift_returning" then
            if t < 0.54 then
                local phase = ease(t / 0.54)
                centerX = 662 + 6 * phase
                topY = workingY + (296 - workingY) * phase
            else
                local phase = ease((t - 0.54) / 0.46)
                centerX = 668 + (690 - 668) * phase
                topY = 296 + (startY - 296) * phase
            end
        elseif step == "positioned" then
            topY = workingY + PAPER_STOP_CLEARANCE
        else
            topY = workingY
        end

        local boundsX = centerX - boundsWidth / 2
        local boundsY = topY
        local centerY = boundsY + boundsHeight / 2
        local skidAlpha = 0
        if step == "loading" then skidAlpha = 1 - ease(t / 0.48)
        elseif step == "unloading" or step == "lift_returning" then skidAlpha = ease((t - 0.72) / 0.28) end
        if skidAlpha > 0.01 then
            local skidWidth = math.min(310, boundsWidth + 22)
            local skidX = 690 - skidWidth / 2
            local skidY = startY + boundsHeight + 5
            love.graphics.setColor(0.15, 0.11, 0.08, 0.26 * skidAlpha)
            love.graphics.rectangle("fill", skidX + 4, skidY + 6, skidWidth, 9, 2, 2)
            love.graphics.setColor(0.37, 0.25, 0.15, 0.96 * skidAlpha)
            love.graphics.rectangle("fill", skidX, skidY, skidWidth, 7, 2, 2)
            love.graphics.setColor(0.61, 0.43, 0.25, 0.92 * skidAlpha)
            for plank = 1, 4 do
                local plankX = skidX + skidWidth * (plank - 1) / 4 + 4
                love.graphics.rectangle("fill", plankX, skidY + 1, 3, 5)
            end
            love.graphics.setColor(0.21, 0.15, 0.1, 0.9 * skidAlpha)
            love.graphics.line(skidX + 3, skidY + 7, skidX + skidWidth - 3, skidY + 7)
        end

        -- A small rear stop sits in the throat. As the stack moves off the skid,
        -- its back edge advances up to this fixed gauge line.
        local stopAlpha = 1
        if step == "unloading" or step == "lift_returning" then
            stopAlpha = 1 - ease(t / 0.42)
        end
        if stopAlpha > 0.01 then
            local stopWidth = 192
            local stopX = 662 - stopWidth / 2
            local stopY = workingY - 10
            love.graphics.setColor(0.06, 0.08, 0.09, 0.8 * stopAlpha)
            love.graphics.rectangle("fill", stopX + 2, stopY + 5, stopWidth, 8, 2, 2)
            love.graphics.setColor(0.29, 0.34, 0.36, 0.96 * stopAlpha)
            love.graphics.rectangle("fill", stopX, stopY, stopWidth, 10, 2, 2)
            love.graphics.setColor(0.64, 0.69, 0.69, 0.92 * stopAlpha)
            love.graphics.line(stopX + 4, stopY + 1, stopX + stopWidth - 4, stopY + 1)
            love.graphics.setColor(0.14, 0.17, 0.18, 0.95 * stopAlpha)
            love.graphics.rectangle("fill", stopX + 5, stopY + 3, 4, 4, 1, 1)
            love.graphics.rectangle("fill", stopX + stopWidth - 9, stopY + 3, 4, 4, 1, 1)
        end

        love.graphics.push()
        love.graphics.translate(centerX, centerY)
        love.graphics.scale(1, depthScale)
        love.graphics.rotate(angle)
        local left, top = -paperWidth / 2, -paperHeight / 2
        local right, bottom = left + paperWidth, top + paperHeight
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.rectangle("fill", left + 5, top + 7, paperWidth, paperHeight, 2, 2)
        for layer = 5, 1, -1 do
            local shade = 0.72 + layer * 0.025
            love.graphics.setColor(shade, shade * 0.99, shade * 0.92)
            love.graphics.rectangle("fill", left, top + layer * 1.35, paperWidth, paperHeight, 1, 1)
        end
        love.graphics.setColor(0.91, 0.90, 0.82)
        for layer = 1, 5 do
            love.graphics.line(left + 1, bottom + layer * 1.35, right - 1, bottom + layer * 1.35)
            love.graphics.line(right + layer * 1.35, top + 3, right + layer * 1.35, bottom + layer * 1.35)
        end
        love.graphics.setColor(0.98, 0.97, 0.90)
        love.graphics.rectangle("fill", left, top, paperWidth, paperHeight)
        love.graphics.setColor(0.70, 0.71, 0.68)
        love.graphics.rectangle("line", left, top, paperWidth, paperHeight)
        local removed = {}
        for _, cut in ipairs(paper.history or {}) do removed[cut.edge] = true end
        local margins = {
            left = removed.left and 0 or paper.margins.left,
            right = removed.right and 0 or paper.margins.right,
            top = removed.top and 0 or paper.margins.top,
            bottom = removed.bottom and 0 or paper.margins.bottom,
        }
        -- Measure the guide in projected pixels, including after a quarter turn.
        local scaleX = math.sqrt(cosAngle^2 + (depthScale * sinAngle)^2)
        local scaleY = math.sqrt(sinAngle^2 + (depthScale * cosAngle)^2)
        local function inset(margin, size, inches, scale)
            return Runtime.CutGuide.marginPixels(margin, size * scale, inches) / scale
        end
        local innerX = left + inset(margins.left, paperWidth, sourceWidth, scaleX)
        local innerY = top + inset(margins.top, paperHeight, sourceHeight, scaleY)
        local innerRight = right - inset(margins.right, paperWidth, sourceWidth, scaleX)
        local innerBottom = bottom - inset(margins.bottom, paperHeight, sourceHeight, scaleY)
        local innerWidth, innerHeight = math.max(8, innerRight - innerX), math.max(8, innerBottom - innerY)
        local r1, g1, b1 = Runtime.artworkColor(paper.artworkId, 1)
        local r2, g2, b2 = Runtime.artworkColor(paper.artworkId, 2)
        love.graphics.setColor(r1, g1, b1)
        love.graphics.rectangle("fill", innerX, innerY, innerWidth, innerHeight)
        local artwork = assets and assets.getArtwork and assets.getArtwork(paper.artworkKey)
        if artwork then
            local scaleX = innerWidth / artwork:getWidth()
            local scaleY = innerHeight / artwork:getHeight()
            love.graphics.setColor(1, 1, 1, 0.96)
            love.graphics.draw(artwork, innerX + innerWidth / 2, innerY + innerHeight / 2,
                0, scaleX, scaleY, artwork:getWidth() / 2, artwork:getHeight() / 2)
        else
            love.graphics.setColor(r2, g2, b2)
            love.graphics.rectangle("fill", innerX + innerWidth * 0.25, innerY + innerHeight * 0.25,
                innerWidth * 0.5, innerHeight * 0.5)
        end
        love.graphics.setColor(0.86, 0.18, 0.18, 0.9)
        love.graphics.setLineStyle("rough")
        love.graphics.rectangle("line", innerX, innerY, innerWidth, innerHeight)
        if paper.offSpec then
            local lineWidth = love.graphics.getLineWidth()
            love.graphics.setLineWidth(3)
            love.graphics.line(left, top, right, bottom)
            love.graphics.line(right, top, left, bottom)
            love.graphics.setLineWidth(lineWidth)
        end
        love.graphics.pop()

        local orientationDifference = math.abs((visualOrientation - orientation + 180) % 360 - 180)
        local turning = orientationDifference > 0.5 or (tonumber(turnProgress) or 1) < 0.999
        if not turning and (step == "loading" or step == "loaded") then
            local guide = Runtime.CutGuide.current(paper, machine.programIndex)
            local widthValue = rotated and sourceHeight or sourceWidth
            local heightValue = rotated and sourceWidth or sourceHeight
            local band = Runtime.CutGuide.band(guide,
                boundsX, boundsY, boundsWidth, boundsHeight, widthValue, heightValue)
            if band then
                local ready = guide.rotationReady
                love.graphics.setColor(1, 0.71, 0.10, 0.70)
                love.graphics.rectangle("fill", band.x, band.y, band.width, band.height)
                love.graphics.setLineWidth(3)
                love.graphics.setColor(ready and 0.35 or 1, ready and 1 or 0.87, ready and 0.48 or 0.18, 1)
                love.graphics.rectangle("line", band.x, band.y, band.width, band.height)
                local ax, ay = band.x + band.width / 2, band.y + band.height / 2
                local dx = guide.screenEdge == "left" and -1 or guide.screenEdge == "right" and 1 or 0
                local dy = guide.screenEdge == "top" and -1 or guide.screenEdge == "bottom" and 1 or 0
                local distance = (dx ~= 0 and band.width / 2 or band.height / 2) + 16
                local tipX, tipY = ax + dx * distance, ay + dy * distance
                love.graphics.line(tipX + dx * 12, tipY + dy * 12, tipX, tipY)
                love.graphics.polygon("fill", tipX, tipY, tipX + dx * 7 - dy * 5, tipY + dy * 7 + dx * 5,
                    tipX + dx * 7 + dy * 5, tipY + dy * 7 - dx * 5)
                love.graphics.setLineWidth(1)
            end
        end
        love.graphics.setLineStyle("smooth")
    end
end

return Component
