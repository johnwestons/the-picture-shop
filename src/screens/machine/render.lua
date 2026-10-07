-- Machine scene, touchscreen, and console rendering.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.motionFrame(progress)
        return math.max(1, math.min(5, math.floor(progress * 4 + 0.5) + 1))
    end

    function Runtime.drawMotion(assets, name, imageName, progress)
        local image, sprite = assets.get(imageName), assets.getQuad(name .. Runtime.motionFrame(progress))
        if not image or not sprite then return end
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, sprite.quad, 400, 78, 0, 520 / 768, 347 / 512)
    end

    function Runtime.drawMachine(assets, machine)
        machine = machine or Runtime.Machine
        local image = assets.get("polarOperatorConsole")
        if image then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(image, 400, 78, 0, 520 / image:getWidth(), 347 / image:getHeight())
        end
        Runtime.drawPaper(assets, machine)
        Runtime.drawMotion(assets, "cutterClamp", "cutterClamp", machine.clampProgress)
        if machine.step == "cutting" then Runtime.drawMotion(assets, "cutterBlade", "cutterBlade", machine.progress / machine.cycleTime) end
    end

    -- Shared, read-only scene: remote callers supply a presentation model, never
    -- replace the Machine singleton or execute local production to animate it.
    function Runtime.Screen.drawCutterScene(assets, machine, rect)
        love.graphics.push("all")
        love.graphics.translate(rect.x, rect.y)
        love.graphics.scale(rect.width / 520, rect.height / 347)
        love.graphics.translate(-400, -78)
        Runtime.drawMachine(assets, machine)
        love.graphics.pop()
    end

    function Runtime.drawTouchscreen(assets, pointerX, pointerY)
        if Runtime.Screen.gaugeReplaceOnType then
            Runtime.Screen.gaugeText = string.format("%.2f", Runtime.Machine.gauge or 0)
        end
        Runtime.CutterSkin.panel(38, 54, 326, 334)
        Runtime.CutterSkin.panel(50, 66, 302, 150, false, true)
        love.graphics.setColor(0.64, 0.83, 0.96)
        love.graphics.print("PROGRAMMABLE BACKGAUGE", 62, 76)
        love.graphics.setColor(0.92, 0.96, 0.92)
        love.graphics.print(string.format("GAUGE  %06.2f in", Runtime.Machine.gauge), 62, 101)
        if Runtime.Machine.paper then
            local cut = Runtime.Machine.paper.cuts[Runtime.Machine.programIndex]
            love.graphics.print(string.format("P%d  %-6s  trim %.2f", Runtime.Machine.programIndex, cut.edge:upper(), cut.margin), 62, 126)
            love.graphics.print(string.format("TARGET %06.2f   ROT %03d", cut.gauge, cut.orientation), 62, 149)
            love.graphics.print(string.format("NOW    %.2f x %.2f in", Runtime.Machine.paper.currentSize.width, Runtime.Machine.paper.currentSize.height), 62, 172)
            if Runtime.Machine.pallet then
                love.graphics.setColor(0.35, 0.95, 0.38)
                love.graphics.print(string.format("LIFT %d/%d   %d SHEETS LEFT",
                    Runtime.Machine.pallet.activeLift or 1, Runtime.Machine.pallet.requiredLifts or 1,
                    Runtime.Machine.pallet.remainingSheets or 0), 62, 195)
            else
                love.graphics.setColor(Runtime.Machine.programIndex == Runtime.Machine.paper.activeCut and 0.35 or 0.95,
                    Runtime.Machine.programIndex == Runtime.Machine.paper.activeCut and 0.95 or 0.45, 0.38)
                love.graphics.print(Runtime.Machine.programIndex == Runtime.Machine.paper.activeCut and "PROGRAM READY" or "SELECT NEXT CUT", 62, 195)
            end
        else
            love.graphics.print("NO PAPER BATCH LOADED", 62, 130)
        end
        Runtime.CutterSkin.panel(Runtime.gaugeInput.x, Runtime.gaugeInput.y, Runtime.gaugeInput.width, Runtime.gaugeInput.height,
            Runtime.Screen.gaugeFocused, true)
        love.graphics.setColor(0.68, 0.78, 0.80)
        love.graphics.print("TYPE", Runtime.gaugeInput.x + 7, Runtime.gaugeInput.y + 8)
        love.graphics.setColor(0.96, 0.98, 0.92)
        local shown = Runtime.Screen.gaugeText .. (Runtime.Screen.gaugeFocused and "_" or "")
        love.graphics.printf(shown, Runtime.gaugeInput.x + 50, Runtime.gaugeInput.y + 8, Runtime.gaugeInput.width - 58, "right")
        for _, button in ipairs(Runtime.buttons) do
            if button.y < 400 then Runtime.drawButton(button, assets, pointerX, pointerY) end
        end
    end

    function Runtime.drawLoadMenu()
        local menu = Runtime.Screen.loadMenu
        if not menu then return end
        love.graphics.setColor(0, 0, 0, 0.72)
        love.graphics.rectangle("fill", 0, 0, Runtime.Config.baseWidth, Runtime.Config.baseHeight)
        local pageStart = math.floor((menu.selected - 1) / Runtime.loadMenuPageSize) * Runtime.loadMenuPageSize + 1
        local pageEnd = math.min(#menu.options, pageStart + Runtime.loadMenuPageSize - 1)
        local visibleCount = pageEnd - pageStart + 1
        local height = 86 + visibleCount * Runtime.loadMenuRect.rowHeight
        Runtime.box(Runtime.loadMenuRect.x, Runtime.loadMenuRect.y, Runtime.loadMenuRect.width, height,
            { 0.035, 0.07, 0.095, 0.99 }, { 0.48, 0.76, 0.83, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("SELECT A PALLET FOR THE CUTTER", Runtime.loadMenuRect.x + 20, Runtime.loadMenuRect.y + 16)
        love.graphics.setColor(0.70, 0.80, 0.82)
        love.graphics.print("Click a row or press 1-7. Up/Down pages; Esc cancels.", Runtime.loadMenuRect.x + 20, Runtime.loadMenuRect.y + 40)
        for index = pageStart, pageEnd do
            local option = menu.options[index]
            local displayIndex = index - pageStart + 1
            local y = Runtime.loadMenuRect.y + 68 + (displayIndex - 1) * Runtime.loadMenuRect.rowHeight
            local selected = menu.selected == index
            Runtime.box(Runtime.loadMenuRect.x + 16, y, Runtime.loadMenuRect.width - 32, Runtime.loadMenuRect.rowHeight - 6,
                selected and { 0.12, 0.35, 0.43, 1 } or { 0.08, 0.12, 0.15, 1 },
                selected and { 0.52, 0.88, 1, 1 } or { 0.26, 0.39, 0.43, 1 }, 3)
            love.graphics.setColor(0.96, 0.98, 0.92)
            love.graphics.print(tostring(displayIndex) .. ".  " .. option.title, Runtime.loadMenuRect.x + 28, y + 8)
            love.graphics.setColor(0.67, 0.78, 0.80)
            love.graphics.print(option.detail, Runtime.loadMenuRect.x + 48, y + 27)
        end
    end

    function Runtime.Screen.draw(state, assets, pointerX, pointerY)
        if Runtime.Screen.helpOpen then Runtime.drawHelp(state, assets, pointerX, pointerY); return end
        if Runtime.Screen.maintenanceView == "hub" then
            Runtime.drawMaintenanceHub(state, assets, pointerX, pointerY)
            return
        elseif Runtime.Screen.maintenanceView == "wrapper_hub" then
            Runtime.drawWrapperMaintenanceHub(state, pointerX, pointerY)
            return
        elseif Runtime.Screen.maintenanceView == "wrapper_task" then
            Runtime.drawWrapperMaintenanceTask(state, assets, pointerX, pointerY)
            return
        elseif Runtime.Screen.maintenanceView == "oil" then
            Runtime.drawOilingGame(state, assets, pointerX, pointerY)
            return
        elseif Runtime.Screen.maintenanceView == "blade" then
            Runtime.drawBladeGame(state, pointerX, pointerY)
            return
        end
        if state.machineType == "skid_wrapper" then
            Runtime.box(18, 18, 924, 642, { 0.045, 0.055, 0.07, 0.99 }, { 0.38, 0.56, 0.62, 1 }, 5)
            love.graphics.setColor(0.96, 0.82, 0.26)
            love.graphics.print("SKID WRAPPER / PALLET PACKAGING CONSOLE", 38, 30)
            Runtime.drawCondition(state, "skid_wrapper", 366, 28, 280)
            Runtime.BackButton.draw(assets, Runtime.exitButton, "EXIT", pointerX, pointerY, false)
            local image = assets.get("skidWrapperDirections")
            local sprite = assets.getQuad("skidWrapperDirection1")
            if image and sprite then
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(image, sprite.quad, 520, 360, 0, 0.72, 0.72, sprite.width / 2, sprite.height * 0.92)
            end
            local nearbyPallets = Runtime.Wrapper.nearbyPallets(state)
            local nearby = Runtime.Wrapper.nearbyPallet(state)
            local inventory = state.inventory or {}
            local packaging = nearby and (nearby.pallet.packaging or nearby.job.packaging or "flat") or nil
            local hasPackaging = packaging ~= "boxed" or Runtime.Procurement.cartonsAvailable(state) > 0
            if nearby then
                local palletImage, palletQuad
                if Runtime.Wrapper.step == "wrapping" or Runtime.Wrapper.step == "finished" then
                    local stage = Runtime.Wrapper.step == "finished" and 3
                        or math.max(1, math.min(3, math.ceil(Runtime.Wrapper.progress / Runtime.Wrapper.cycleTime * 3)))
                    palletImage = assets.get("wrappedPalletStages")
                    palletQuad = assets.getQuad("wrappedPalletStage" .. stage)
                else
                    palletImage = assets.get("loadedPaperPallet")
                end
                love.graphics.setColor(1, 1, 1)
                if palletImage and palletQuad then
                    love.graphics.draw(palletImage, palletQuad.quad, 450, 390, 0, 0.42, 0.42, palletQuad.width / 2, palletQuad.height * 0.94)
                elseif palletImage then
                    love.graphics.draw(palletImage, 450, 390, 0, 0.72, 0.72, palletImage:getWidth() / 2, palletImage:getHeight() * 0.94)
                end
            end
            love.graphics.setColor(0.96, 0.82, 0.26)
            love.graphics.print("CLICK A NEARBY PALLET", Runtime.wrapperPalletList.x, Runtime.wrapperPalletList.y - 22)
            if #nearbyPallets == 0 then
                Runtime.box(Runtime.wrapperPalletList.x, Runtime.wrapperPalletList.y, Runtime.wrapperPalletList.width,
                    Runtime.wrapperPalletList.rowHeight - 6, { 0.09, 0.11, 0.13, 0.94 },
                    { 0.28, 0.34, 0.36, 1 }, 3)
                love.graphics.setColor(0.58, 0.66, 0.67)
                love.graphics.print("No finished pallets in range", Runtime.wrapperPalletList.x + 12,
                    Runtime.wrapperPalletList.y + 13)
            else
                for index = 1, math.min(#nearbyPallets, Runtime.wrapperPalletList.maxRows) do
                    local option = nearbyPallets[index]
                    local y = Runtime.wrapperPalletList.y + (index - 1) * Runtime.wrapperPalletList.rowHeight
                    local selected = nearby and nearby.pallet.id == option.pallet.id
                    local hovered = pointerX and Runtime.inside({ x = Runtime.wrapperPalletList.x, y = y,
                        width = Runtime.wrapperPalletList.width, height = Runtime.wrapperPalletList.rowHeight - 6 },
                        pointerX, pointerY)
                    Runtime.box(Runtime.wrapperPalletList.x, y, Runtime.wrapperPalletList.width,
                        Runtime.wrapperPalletList.rowHeight - 6,
                        selected and { 0.12, 0.38, 0.27, 0.98 }
                            or (hovered and { 0.13, 0.24, 0.27, 0.98 } or { 0.08, 0.12, 0.14, 0.96 }),
                        selected and { 0.42, 0.90, 0.54, 1 } or { 0.28, 0.43, 0.46, 1 }, 3)
                    love.graphics.setColor(0.94, 0.98, 0.92)
                    love.graphics.print(tostring(index) .. ".  " .. option.pallet.id,
                        Runtime.wrapperPalletList.x + 12, y + 6)
                    love.graphics.setColor(0.66, 0.78, 0.78)
                    love.graphics.print(string.format("%s  |  %s  |  %d px away",
                        tostring(option.job.company or option.job.id or "JOB"),
                        tostring(option.pallet.packaging or option.job.packaging or "flat"):upper(),
                        math.floor(math.sqrt(option.distance) + 0.5)),
                        Runtime.wrapperPalletList.x + 30, y + 23)
                end
            end
            love.graphics.setColor(0.82, 0.88, 0.89)
            love.graphics.print("STATUS: " .. Runtime.Wrapper.step:upper(), 50, 410)
            love.graphics.print("NEARBY PALLET: " .. (nearby and nearby.pallet.id or "NONE"), 50, 438)
            love.graphics.print("PACKAGE: " .. (packaging and packaging:upper() or "--"), 50, 466)
            love.graphics.print(string.format("PLASTIC: %d ROLL(S)  |  %d / 11 WRAPS", inventory.plasticWrapRolls or 0, inventory.plasticWrapUses or 0), 50, 494)
            local serviceHovered = pointerX and Runtime.inside(Runtime.wrapperMaintenanceButton, pointerX, pointerY)
            Runtime.box(Runtime.wrapperMaintenanceButton.x, Runtime.wrapperMaintenanceButton.y,
                Runtime.wrapperMaintenanceButton.width, Runtime.wrapperMaintenanceButton.height,
                serviceHovered and { 0.16, 0.43, 0.34, 1 } or { 0.11, 0.30, 0.26, 1 },
                { 0.42, 0.72, 0.58, 1 }, 3)
            love.graphics.setColor(0.94, 0.97, 0.92)
            love.graphics.printf("SERVICE MACHINE", Runtime.wrapperMaintenanceButton.x,
                Runtime.wrapperMaintenanceButton.y + 19, Runtime.wrapperMaintenanceButton.width, "center")
            Runtime.box(Runtime.wrapButton.x, Runtime.wrapButton.y, Runtime.wrapButton.width, Runtime.wrapButton.height,
                nearby and hasPackaging and (inventory.plasticWrapUses or 0) > 0
                    and { 0.15, 0.40, 0.27, 1 } or { 0.15, 0.17, 0.18, 1 },
                { 0.35, 0.65, 0.48, 1 }, 3)
            love.graphics.setColor(0.95, 0.98, 0.92)
            local jackReady = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack).operating
                and not state.palletJack.carriedPalletId
            local wrapLabel = Runtime.Wrapper.step == "wrapping"
                and string.format("WRAPPING %d%%", math.floor(Runtime.Wrapper.progress / Runtime.Wrapper.cycleTime * 100))
                or (jackReady and "WRAP PALLET [L]  RELOCATE [M]" or "WRAP PALLET [L]")
            love.graphics.printf(wrapLabel, Runtime.wrapButton.x, Runtime.wrapButton.y + 19, Runtime.wrapButton.width, "center")
            love.graphics.print(state.message or "", 48, 635)
            return
        end
        Runtime.layout()
        Runtime.CutterSkin.shell(assets)
        Runtime.CutterSkin.panel(392, 54, 530, 334, false, true)
        love.graphics.setColor(0.97, 0.97, 0.92)
        love.graphics.print("POLAR 115 / JOB CUTTING CONSOLE", 38, 30)
        Runtime.drawCondition(state, "polar_115", 366, 28, 280)
        local exitHovered = pointerX and pointerY and Runtime.inside(Runtime.exitButton, pointerX, pointerY)
        local exitPressed = exitHovered and love.mouse and love.mouse.isDown and love.mouse.isDown(1)
        Runtime.CutterSkin.button(assets, Runtime.exitButton.x, Runtime.exitButton.y, Runtime.exitButton.width, Runtime.exitButton.height,
            exitPressed and "pressed" or exitHovered and "hover" or "normal")
        love.graphics.setColor(0.94, 0.94, 0.90)
        love.graphics.printf("EXIT", Runtime.exitButton.x, Runtime.exitButton.y + Runtime.exitButton.height / 2 - 6,
            Runtime.exitButton.width, "center")
        Runtime.drawTouchscreen(assets, pointerX, pointerY)
        Runtime.drawMachine(assets)
        -- Top-level controls are deliberately drawn after the machine art so the
        -- cabinet can never cover them.
        Runtime.drawHelpButton(assets, pointerX, pointerY)
        Runtime.drawMaintenanceButton(assets, pointerX, pointerY)
        Runtime.CutterSkin.panel(38, 400, 884, 58, false, true)
        love.graphics.setColor(0.82, 0.88, 0.89)
        love.graphics.print("STATUS: " .. Runtime.Machine.step:upper(), 50, 411)
        love.graphics.print("BARRIER: " .. (Runtime.Machine.barrierClear and "CLEAR" or "BLOCKED"), 260, 411)
        love.graphics.print("CLAMP: " .. (Runtime.Machine.clamp and "DOWN" or "UP"), 460, 411)
        love.graphics.print(Runtime.Machine.paperTooltip(), 50, 435)
        for _, button in ipairs(Runtime.buttons) do
            if button.y >= 400 and button.action ~= "cut_left" and button.action ~= "cut_right" and button.action ~= "estop" then Runtime.drawButton(button, assets, pointerX, pointerY) end
        end
        for _, button in ipairs(Runtime.buttons) do
            if button.action == "cut_left" then Runtime.drawSpriteButton(assets, button, false, Runtime.Machine.leftDown)
            elseif button.action == "cut_right" then Runtime.drawSpriteButton(assets, button, false, Runtime.Machine.rightDown)
            elseif button.action == "estop" then Runtime.drawSpriteButton(assets, button, true, Runtime.Machine.emergencyStopped) end
        end
        love.graphics.setColor(0.75, 0.82, 0.83)
        love.graphics.print("Gauge + ENTER | L load | G auto | P position | Q rotate | SPACE clamp | "
            .. (Runtime.Machine.multiplayerSingleControl and "J or K cut" or "J+K cut")
            .. " | T repeat | U unload", 48, 535)
        local memory = Runtime.Machine.savedMeasurements(state, Runtime.Machine.programIndex)
        local formattedMemory = {}
        for index, value in ipairs(memory) do formattedMemory[index] = string.format("%.2f", value) end
        local memoryText = #formattedMemory > 0 and table.concat(formattedMemory, " / ") or "NONE"
        love.graphics.print(string.format("P%d SAVED: %s", Runtime.Machine.programIndex, memoryText), 50, 563)
        love.graphics.print(state.message or "", 48, 635)
        Runtime.drawLoadMenu()
    end
end

return Component
