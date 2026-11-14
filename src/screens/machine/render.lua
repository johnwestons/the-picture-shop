-- Machine scene, touchscreen, and console rendering.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}
local WrapperScene = require("src.screens.wrapper_scene")
local CutterMotion = require("src.screens.cutter_motion")

function Component.install(Runtime)
    function Runtime.motionFrame(progress)
        return CutterMotion.frame(progress)
    end

    function Runtime.drawMotion(assets, name, imageName, progress)
        local detailName = name == "cutterBlade" and "cutterBladeDetail"
            or name == "cutterClamp" and "cutterClampDetail"
        local detail = detailName and assets.get(detailName)
        if detail then
            local pose = name == "cutterBlade"
                and CutterMotion.bladeDepthPose(progress)
                or CutterMotion.clampPose(progress)
            -- Keep both parts inside the rear throat at rest. Their full stroke
            -- ends at the table's red cut line instead of hanging over the bed.
            local baseX, baseY = 660, name == "cutterBlade" and 191 or 192
            local scale = name == "cutterBlade" and 0.111 or 0.122
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(detail, baseX + pose.x, baseY + pose.y, pose.angle,
                scale, scale * (pose.scaleY or 1), detail:getWidth() / 2, detail:getHeight() / 2)
            return
        end
        local frame, offsetY = CutterMotion.sample(name, name == "cutterBlade" and progress / 2 or progress)
        local image, sprite = assets.get(imageName), assets.getQuad(name .. frame)
        if not image or not sprite then return end
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, sprite.quad, 400, 78 + offsetY * 347 / 512, 0, 520 / 768, 347 / 512)
    end

    -- All pieces register in the original texture's coordinates, including in
    -- the scaled guest console. A quad's source offset is not its draw offset.
    local function piece(assets, image, name, x, y, height)
        local part = image and assets.getQuad(name)
        if not part then return end
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, part.quad, 400 + x * 520 / 768, 78 + y * 347 / 512,
            0, 520 / 768, 347 / 512 * (height or part.height) / part.height)
    end

    function Runtime.drawMachine(assets, machine)
        machine = machine or Runtime.Machine
        local image = assets.get("polarOperatorConsole")
        if image then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(image, 400, 78, 0, 520 / image:getWidth(), 347 / image:getHeight())
        end
        local paper = machine.paper
        local visualOrientation = machine.paperVisualOrientation
            or (paper and paper.visualOrientation)
        local turnProgress = machine.paperTurnProgress or (paper and paper.turnProgress)
        if paper and Runtime.Screen.paperTurn and Runtime.Screen.paperTurn.paperKey == paper.id then
            visualOrientation = visualOrientation or Runtime.Screen.paperVisualOrientation
            turnProgress = turnProgress or Runtime.Screen.paperTurnProgress
        end
        -- Continue the steel bed through the opening, covering the old painted
        -- laser. The stick and rear bed are now behind the front of the head.
        piece(assets, image, "cutterRearBed", 236, 188, 51)
        local left, right = 400 + 236 * 520 / 768, 400 + 532 * 520 / 768
        love.graphics.push("all")
        local paperX, paperY = love.graphics.transformPoint(392, 78 + 202 * 347 / 512)
        local farX, farY = love.graphics.transformPoint(922, 550)
        love.graphics.intersectScissor(paperX, paperY, farX - paperX, farY - paperY)
        Runtime.drawPaper(assets, machine, visualOrientation, turnProgress)
        love.graphics.pop()
        -- Shadow cast by the underside of the head across the rear deck and stock.
        for row = 0, 9 do
            love.graphics.setColor(0.045, 0.055, 0.06, (10 - row) * 0.042)
            love.graphics.rectangle("fill", left, CutterMotion.cutLineY - 10 + row, right - left, 1)
        end
        love.graphics.setColor(0.87, 0.14, 0.09, 0.74)
        love.graphics.line(left, CutterMotion.cutLineY, right, CutterMotion.cutLineY)
        love.graphics.push("all")
        -- The lower edge of the sloped knife progressively enters the stick.
        -- Crop at the stick in screen coordinates, also on the scaled remote view.
        local x1, y1 = love.graphics.transformPoint(left, 78)
        local x2, y2 = love.graphics.transformPoint(right, CutterMotion.cutLineY)
        love.graphics.intersectScissor(x1, y1, x2 - x1, y2 - y1)
        Runtime.drawMotion(assets, "cutterClamp", "cutterClamp", machine.clampProgress)
        if (machine.bladeProgress or 0) > 0 then
            Runtime.drawMotion(assets, "cutterBlade", "cutterBlade", machine.bladeProgress)
        end
        love.graphics.pop()
        piece(assets, image, "cutterHead", 0, 0)
        piece(assets, image, "cutterFace", 212, 171, 31)
        piece(assets, image, "cutterLeftPost", 0, 188)
        piece(assets, image, "cutterRightPost", 532, 188)
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

    function Runtime.drawTouchscreen(state, assets, pointerX, pointerY)
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
        local cutter = Runtime.MachineFleet.installed(state, "polar_115", state and state.machineId)
        local blade = cutter and cutter.variables and tonumber(cutter.variables.bladeSharpness) or 0
        blade = math.max(0, math.min(100, blade))
        local bladeRemoved = cutter and cutter.maintenance and cutter.maintenance.cutter
            and cutter.maintenance.cutter.bladeRemoved
        love.graphics.setColor(0.68, 0.78, 0.80)
        love.graphics.print(bladeRemoved and "BLADE OUT" or string.format("BLADE %d%%", math.floor(blade + 0.5)), 246, 76)
        love.graphics.setColor(0.12, 0.15, 0.17)
        love.graphics.rectangle("fill", 246, 91, 90, 5, 2, 2)
        if bladeRemoved then love.graphics.setColor(0.89, 0.31, 0.22)
        elseif blade >= 70 then love.graphics.setColor(0.28, 0.72, 0.43)
        elseif blade >= 40 then love.graphics.setColor(0.88, 0.67, 0.22)
        else love.graphics.setColor(0.89, 0.31, 0.22) end
        if not bladeRemoved then love.graphics.rectangle("fill", 246, 91, 90 * blade / 100, 5, 2, 2) end
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

    function Runtime.drawLoadMenu(assets, pointerX, pointerY)
        local menu = Runtime.Screen.loadMenu
        if not menu then return end
        local layout = Runtime.loadMenuLayout(menu)
        love.graphics.setColor(0, 0, 0, 0.72)
        love.graphics.rectangle("fill", 0, 0, Runtime.Config.baseWidth, Runtime.Config.baseHeight)
        Runtime.box(layout.x, layout.y, layout.width, layout.height,
            { 0.035, 0.07, 0.095, 0.99 }, { 0.48, 0.76, 0.83, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("SELECT A PALLET FOR THE CUTTER", layout.x + 20, layout.y + 16)
        love.graphics.setColor(0.70, 0.80, 0.82)
        love.graphics.print("Choose a row or press 1-7. Up/Down moves; Esc or BACK returns.",
            layout.x + 20, layout.y + 40)
        if layout.visibleCount == 0 then
            love.graphics.setColor(0.78, 0.84, 0.85)
            love.graphics.printf("No eligible paper pallet is inside the cutter's load radius.\nMove an unfinished pallet closer.",
                layout.x + 24, layout.y + 82, layout.width - 48, "center")
        end
        for index = layout.pageStart, layout.pageEnd do
            local option = menu.options[index]
            local displayIndex = index - layout.pageStart + 1
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
        Runtime.BackButton.draw(assets, layout.back, "BACK", pointerX, pointerY, false)
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
            Runtime.drawBladeGame(state, assets, pointerX, pointerY)
            return
        end
        if state.machineType == "skid_wrapper" then
            Runtime.box(18, 18, 924, 642, { 0.045, 0.055, 0.07, 0.99 }, { 0.38, 0.56, 0.62, 1 }, 5)
            love.graphics.setColor(0.96, 0.82, 0.26)
            love.graphics.print("SKID WRAPPER / PALLET PACKAGING CONSOLE", 38, 30)
            Runtime.drawCondition(state, "skid_wrapper", 366, 28, 280)
            Runtime.BackButton.draw(assets, Runtime.exitButton, "EXIT", pointerX, pointerY, false)
            local nearbyPallets = Runtime.Wrapper.nearbyPallets(state)
            local nearby = Runtime.Wrapper.nearbyPallet(state)
            local inventory = state.inventory or {}
            local packaging = nearby and (nearby.pallet.packaging or nearby.job.packaging or "flat") or nil
            local cartonsRequired = nearby and Runtime.Procurement.cartonsRequired(nearby.job, nearby.pallet) or 0
            local cartonsAvailable = Runtime.Procurement.cartonsAvailable(state)
            local hasPackaging = packaging ~= "boxed" or cartonsAvailable >= cartonsRequired
            local cycle = Runtime.Wrapper
            local load = cycle.step == "idle" and nearby and nearby.pallet or cycle.pallet
            local wrapType = load and (load.packagedAs or load.packaging or (cycle.job and cycle.job.packaging)) or packaging
            WrapperScene.draw(assets, cycle, load ~= nil, wrapType == "boxed", 392, 48, 0.72)
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
                    local optionCartons = Runtime.Procurement.cartonsRequired(option.job, option.pallet)
                    local packageText = tostring(option.pallet.packaging or option.job.packaging or "flat"):upper()
                    if optionCartons > 0 then packageText = packageText .. string.format(" · %d BOXES", optionCartons) end
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
                        packageText,
                        math.floor(math.sqrt(option.distance) + 0.5)),
                        Runtime.wrapperPalletList.x + 30, y + 23)
                end
            end
            love.graphics.setColor(0.82, 0.88, 0.89)
            love.graphics.print("STATUS: " .. Runtime.Wrapper.step:upper(), 50, 410)
            love.graphics.print("TURNTABLE PALLET: " .. (load and load.id or "NONE"), 50, 438)
            love.graphics.print("PACKAGE: " .. (wrapType and wrapType:upper() or "--"), 50, 466)
            love.graphics.print(packaging == "boxed"
                and string.format("CARTONS: %d REQUIRED  |  %d AVAILABLE", cartonsRequired, cartonsAvailable)
                or string.format("PLASTIC: %d ROLL(S)  |  %d / 11 WRAPS", inventory.plasticWrapRolls or 0, inventory.plasticWrapUses or 0), 50, 494)
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
        Runtime.drawTouchscreen(state, assets, pointerX, pointerY)
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
        love.graphics.print("Gauge + ENTER | L load | G auto | P position | Q rotate CCW | SPACE clamp | "
            .. (Runtime.Machine.multiplayerSingleControl and "J or K cut" or "J+K cut")
            .. " | T repeat | U unload", 48, 535)
        local memory = Runtime.Machine.savedMeasurements(state, Runtime.Machine.programIndex)
        local formattedMemory = {}
        for index, value in ipairs(memory) do formattedMemory[index] = string.format("%.2f", value) end
        local memoryText = #formattedMemory > 0 and table.concat(formattedMemory, " / ") or "NONE"
        love.graphics.print(string.format("P%d SAVED: %s", Runtime.Machine.programIndex, memoryText), 50, 563)
        love.graphics.print(state.message or "", 48, 635)
        Runtime.drawLoadMenu(assets, pointerX, pointerY)
    end
end

return Component
