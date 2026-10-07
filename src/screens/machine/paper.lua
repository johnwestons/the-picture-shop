-- Paper selection, loading, and sheet presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

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
                detail = string.format("%s  |  %d sheets  |  %.0f px from feed zone",
                    tostring(candidate.paper.artworkKey or "artwork"),
                    candidate.pallet.remainingSheets or candidate.pallet.initialSheets or 0,
                    math.sqrt(candidate.inputDistance or 0)),
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
        if #options == 0 then
            state.message = "No unfinished pallet is inside the cutter's expanded load radius."
            return false
        end
        Runtime.Screen.loadMenu = { options = options, selected = 1 }
        Runtime.Screen.gaugeFocused = false
        state.message = "Choose which nearby pallet to load onto the cutter."
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
        love.graphics.printf(button.label, button.x, button.y + 9 + (active and 2 or 0), button.width, "center")
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

    function Runtime.drawPaper(assets, machine)
        local paper = machine.paper
        if not machine.loaded or not paper then return end
        local step, t = machine.step, 1
        if step == "loading" then t = math.min(1, machine.progress / machine.transferTime)
        elseif step == "positioning" then t = math.min(1, machine.progress / machine.transferTime)
        elseif step == "unloading" or step == "lift_returning" then
            t = 1 - math.min(1, machine.progress / machine.transferTime)
        end
        local startY, bedY, gaugeY = 355, 264, 218
        local y
        if step == "loading" then y = startY + (bedY - startY) * t
        elseif step == "loaded" then y = bedY
        elseif step == "positioning" then y = bedY + (gaugeY - bedY) * t
        elseif step == "unloading" or step == "lift_returning" then y = startY + (gaugeY - startY) * t
        else y = gaugeY end
        local rotated = paper.orientation % 180 == 90
        local widthValue = rotated and paper.currentSize.height or paper.currentSize.width
        local heightValue = rotated and paper.currentSize.width or paper.currentSize.height
        local width = math.max(100, math.min(270, widthValue / 25 * 270))
        local height = math.max(50, math.min(125, heightValue / 25 * 125))
        local x = 662 - width / 2
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.rectangle("fill", x + 5, y + 8, width, height)
        love.graphics.setColor(0.96, 0.95, 0.86)
        love.graphics.rectangle("fill", x, y, width, height)
        love.graphics.setColor(0.72, 0.74, 0.72)
        love.graphics.rectangle("line", x, y, width, height)
        local removed = {}
        for _, cut in ipairs(paper.history or {}) do removed[cut.edge] = true end
        local margins = {
            left = removed.left and 0 or paper.margins.left,
            right = removed.right and 0 or paper.margins.right,
            top = removed.top and 0 or paper.margins.top,
            bottom = removed.bottom and 0 or paper.margins.bottom,
        }
        local orientation = paper.orientation % 360
        local screenMargins
        if orientation == 90 then
            screenMargins = { left = margins.bottom, right = margins.top, top = margins.left, bottom = margins.right }
        elseif orientation == 180 then
            screenMargins = { left = margins.right, right = margins.left, top = margins.bottom, bottom = margins.top }
        elseif orientation == 270 then
            screenMargins = { left = margins.top, right = margins.bottom, top = margins.right, bottom = margins.left }
        else
            screenMargins = margins
        end
        local innerX = x + math.min(width * 0.45, screenMargins.left / widthValue * width)
        local innerY = y + math.min(height * 0.45, screenMargins.top / heightValue * height)
        local innerRight = x + width - math.min(width * 0.45, screenMargins.right / widthValue * width)
        local innerBottom = y + height - math.min(height * 0.45, screenMargins.bottom / heightValue * height)
        local innerWidth, innerHeight = math.max(8, innerRight - innerX), math.max(8, innerBottom - innerY)
        local r1, g1, b1 = Runtime.artworkColor(paper.artworkId, 1)
        local r2, g2, b2 = Runtime.artworkColor(paper.artworkId, 2)
        love.graphics.setColor(r1, g1, b1)
        love.graphics.rectangle("fill", innerX, innerY, innerWidth, innerHeight)
        local artwork = assets and assets.getArtwork and assets.getArtwork(paper.artworkKey)
        if artwork then
            local angle = Runtime.Screen.artworkRotation(paper)
            local quarterTurn = paper.orientation % 180 == 90
            local scaleX = (quarterTurn and innerHeight or innerWidth) / artwork:getWidth()
            local scaleY = (quarterTurn and innerWidth or innerHeight) / artwork:getHeight()
            love.graphics.setColor(1, 1, 1, 0.96)
            love.graphics.draw(artwork, innerX + innerWidth / 2, innerY + innerHeight / 2,
                angle, scaleX, scaleY, artwork:getWidth() / 2, artwork:getHeight() / 2)
        else
            love.graphics.setColor(r2, g2, b2)
            love.graphics.rectangle("fill", innerX + innerWidth * 0.25, innerY + innerHeight * 0.25,
                innerWidth * 0.5, innerHeight * 0.5)
        end
        love.graphics.setColor(0.86, 0.18, 0.18, 0.9)
        love.graphics.setLineStyle("rough")
        love.graphics.rectangle("line", innerX, innerY, innerWidth, innerHeight)
        local guide=Runtime.CutGuide.current(paper,machine.programIndex)
        local band=Runtime.CutGuide.band(guide,x,y,width,height,widthValue,heightValue)
        if band then
            local ready=guide.rotationReady
            love.graphics.setColor(1,.71,.10,.70)
            love.graphics.rectangle("fill",band.x,band.y,band.width,band.height)
            love.graphics.setLineWidth(3)
            love.graphics.setColor(ready and .35 or 1,ready and 1 or .87,ready and .48 or .18,1)
            love.graphics.rectangle("line",band.x,band.y,band.width,band.height)
            local ax,ay=band.x+band.width/2,band.y+band.height/2
            local dx=guide.screenEdge=="left" and -1 or guide.screenEdge=="right" and 1 or 0
            local dy=guide.screenEdge=="top" and -1 or guide.screenEdge=="bottom" and 1 or 0
            local distance=(dx~=0 and band.width/2 or band.height/2)+16
            local tipX,tipY=ax+dx*distance,ay+dy*distance
            love.graphics.line(tipX+dx*12,tipY+dy*12,tipX,tipY)
            love.graphics.polygon("fill",tipX,tipY,tipX+dx*7-dy*5,tipY+dy*7+dx*5,
                tipX+dx*7+dy*5,tipY+dy*7-dx*5)
            love.graphics.setLineWidth(1)
        end
        if paper.offSpec then
            local lineWidth = love.graphics.getLineWidth()
            love.graphics.setLineWidth(3)
            love.graphics.line(x, y, x + width, y + height)
            love.graphics.line(x + width, y, x, y + height)
            love.graphics.setLineWidth(lineWidth)
        end
        love.graphics.setLineStyle("smooth")
    end
end

return Component
