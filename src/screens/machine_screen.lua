local Config = require("src.config")
local Machine = require("src.machine")
local Press = require("src.press")
local Wrapper = require("src.wrapper")
local BackButton = require("src.screens.back_button")
local utf8 = require("utf8")

local Screen = {
    pressedAction = nil,
    gaugeFocused = false,
    gaugeText = "0.00",
    gaugeReplaceOnType = true,
}
local buttons = {}
local gaugeInput = { x = 55, y = 263, width = 182, height = 28 }
local exitButton = { x = 790, y = 28, width = 132, height = 42 }
local wrapButton = { x = 650, y = 520, width = 220, height = 54 }

local function box(x, y, width, height, fill, line, radius)
    love.graphics.setColor(fill)
    love.graphics.rectangle("fill", x, y, width, height, radius or 0, radius or 0)
    love.graphics.setColor(line)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, width, height, radius or 0, radius or 0)
end

local function addButton(action, label, x, y, width, height, key, value)
    buttons[#buttons + 1] = { action = action, label = label, x = x, y = y, width = width, height = height, key = key, value = value }
end

local function layout()
    buttons = {}
    for index = 1, 4 do addButton("program", "CUT " .. index, 55 + (index - 1) * 72, 228, 64, 28, nil, index) end
    addButton("set_gauge", "SET", 245, 263, 46, 28)
    addButton("gauge", "-1", 55, 298, 48, 28, nil, -1)
    addButton("gauge", "-.1", 109, 298, 48, 28, nil, -0.1)
    addButton("gauge", "+.1", 163, 298, 48, 28, nil, 0.1)
    addButton("gauge", "+1", 217, 298, 48, 28, nil, 1)
    addButton("auto", "AUTO SET", 271, 298, 72, 28, "g")
    addButton("save", "SAVE", 55, 334, 62, 28, "m")
    addButton("recall", "RECALL", 123, 334, 70, 28, "v")
    addButton("load", "LOAD BED", 54, 478, 96, 34, "l")
    addButton("position", "PUSH / POS", 158, 478, 100, 34, "p")
    addButton("rotate", "ROTATE CCW", 266, 478, 100, 34, "q")
    addButton("clamp", "CLAMP", 374, 478, 84, 34, "space")
    addButton("unload", "TO PALLET", 466, 478, 96, 34, "u")
    addButton("barrier", "BARRIER", 570, 478, 86, 34, "b")
    addButton("reset", "RESET", 664, 478, 72, 34, "r")
    addButton("estop", "E-STOP", 752, 470, 74, 74, "x")
    addButton("cut_left", "J", 674, 565, 82, 82, "j")
    addButton("cut_right", "K", 804, 565, 82, 82, "k")
end

local function formatGauge()
    Screen.gaugeText = string.format("%.2f", Machine.gauge or 0)
    Screen.gaugeReplaceOnType = true
end

local function commitGauge(state)
    local succeeded = Machine.setGauge(Screen.gaugeText, state)
    if succeeded then formatGauge() end
    return succeeded
end

function Screen.enter()
    Screen.pressedAction = nil
    Screen.gaugeFocused = true
    formatGauge()
end

function Screen.syncGauge()
    formatGauge()
end

local function inside(button, x, y)
    return x >= button.x and x <= button.x + button.width and y >= button.y and y <= button.y + button.height
end

local function drawButton(button)
    if button.action == "cut_left" or button.action == "cut_right" or button.action == "estop" then return end
    local active = Screen.pressedAction == button.action
    if button.action == "program" then active = Machine.programIndex == button.value end
    box(button.x, button.y + (active and 2 or 0), button.width, button.height,
        active and { 0.18, 0.52, 0.68, 1 } or { 0.13, 0.18, 0.23, 1 },
        active and { 0.55, 0.90, 1, 1 } or { 0.35, 0.48, 0.56, 1 }, 3)
    love.graphics.setColor(0.92, 0.95, 0.95)
    love.graphics.printf(button.label, button.x, button.y + 9 + (active and 2 or 0), button.width, "center")
end

local function drawSpriteButton(assets, button, red, pressed)
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

local function artworkColor(id, offset)
    local hash = offset * 97
    for index = 1, #(id or "ART") do hash = (hash * 33 + id:byte(index)) % 997 end
    return 0.25 + (hash % 55) / 100, 0.25 + ((hash * 3) % 55) / 100, 0.25 + ((hash * 7) % 55) / 100
end

local function drawPaper()
    local paper = Machine.paper
    if not Machine.loaded or not paper then return end
    local step, t = Machine.step, 1
    if step == "loading" then t = math.min(1, Machine.progress / Machine.transferTime)
    elseif step == "positioning" then t = math.min(1, Machine.progress / Machine.transferTime)
    elseif step == "unloading" then t = 1 - math.min(1, Machine.progress / Machine.transferTime) end
    local startY, bedY, gaugeY = 355, 264, 218
    local y
    if step == "loading" then y = startY + (bedY - startY) * t
    elseif step == "loaded" then y = bedY
    elseif step == "positioning" then y = bedY + (gaugeY - bedY) * t
    elseif step == "unloading" then y = startY + (gaugeY - startY) * t
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
    local r1, g1, b1 = artworkColor(paper.artworkId, 1)
    local r2, g2, b2 = artworkColor(paper.artworkId, 2)
    love.graphics.setColor(r1, g1, b1)
    love.graphics.rectangle("fill", innerX, innerY, innerWidth, innerHeight)
    love.graphics.setColor(r2, g2, b2)
    love.graphics.rectangle("fill", innerX + innerWidth * 0.25, innerY + innerHeight * 0.25, innerWidth * 0.5, innerHeight * 0.5)
    love.graphics.setColor(0.86, 0.18, 0.18, 0.9)
    love.graphics.setLineStyle("rough")
    love.graphics.rectangle("line", innerX, innerY, innerWidth, innerHeight)
    love.graphics.setLineStyle("smooth")
end

local function motionFrame(progress)
    return math.max(1, math.min(5, math.floor(progress * 4 + 0.5) + 1))
end

local function drawMotion(assets, name, imageName, progress)
    local image, sprite = assets.get(imageName), assets.getQuad(name .. motionFrame(progress))
    if not image or not sprite then return end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, 400, 78, 0, 520 / 768, 347 / 512)
end

local function drawMachine(assets)
    local image = assets.get("polarOperatorConsole")
    if image then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, 400, 78, 0, 520 / image:getWidth(), 347 / image:getHeight())
    end
    drawPaper()
    drawMotion(assets, "cutterClamp", "cutterClamp", Machine.clampProgress)
    if Machine.step == "cutting" then drawMotion(assets, "cutterBlade", "cutterBlade", Machine.progress / Machine.cycleTime) end
end

local function drawTouchscreen()
    if Screen.gaugeReplaceOnType then
        Screen.gaugeText = string.format("%.2f", Machine.gauge or 0)
    end
    box(38, 54, 326, 334, { 0.04, 0.075, 0.105, 1 }, { 0.44, 0.64, 0.72, 1 }, 4)
    box(50, 66, 302, 150, { 0.055, 0.13, 0.19, 1 }, { 0.20, 0.55, 0.72, 1 }, 2)
    love.graphics.setColor(0.52, 0.88, 1)
    love.graphics.print("PROGRAMMABLE BACKGAUGE", 62, 76)
    love.graphics.setColor(0.92, 0.96, 0.92)
    love.graphics.print(string.format("GAUGE  %06.2f in", Machine.gauge), 62, 101)
    if Machine.paper then
        local cut = Machine.paper.cuts[Machine.programIndex]
        love.graphics.print(string.format("P%d  %-6s  trim %.2f", Machine.programIndex, cut.edge:upper(), cut.margin), 62, 126)
        love.graphics.print(string.format("TARGET %06.2f   ROT %03d", cut.gauge, cut.orientation), 62, 149)
        love.graphics.print(string.format("NOW    %.2f x %.2f in", Machine.paper.currentSize.width, Machine.paper.currentSize.height), 62, 172)
        love.graphics.setColor(Machine.programIndex == Machine.paper.activeCut and 0.35 or 0.95,
            Machine.programIndex == Machine.paper.activeCut and 0.95 or 0.45, 0.38)
        love.graphics.print(Machine.programIndex == Machine.paper.activeCut and "PROGRAM READY" or "SELECT NEXT CUT", 62, 195)
    else
        love.graphics.print("NO PAPER BATCH LOADED", 62, 130)
    end
    box(gaugeInput.x, gaugeInput.y, gaugeInput.width, gaugeInput.height,
        Screen.gaugeFocused and { 0.07, 0.22, 0.29, 1 } or { 0.08, 0.11, 0.14, 1 },
        Screen.gaugeFocused and { 0.52, 0.88, 1, 1 } or { 0.32, 0.46, 0.52, 1 }, 3)
    love.graphics.setColor(0.68, 0.78, 0.80)
    love.graphics.print("TYPE", gaugeInput.x + 7, gaugeInput.y + 8)
    love.graphics.setColor(0.96, 0.98, 0.92)
    local shown = Screen.gaugeText .. (Screen.gaugeFocused and "_" or "")
    love.graphics.printf(shown, gaugeInput.x + 50, gaugeInput.y + 8, gaugeInput.width - 58, "right")
    for _, button in ipairs(buttons) do
        if button.y < 400 then drawButton(button) end
    end
end

function Screen.draw(state, assets, pointerX, pointerY)
    if state.machineType == "skid_wrapper" then
        box(18, 18, 924, 642, { 0.045, 0.055, 0.07, 0.99 }, { 0.38, 0.56, 0.62, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("SKID WRAPPER / PALLET PACKAGING CONSOLE", 38, 30)
        BackButton.draw(assets, exitButton, "EXIT", pointerX, pointerY, false)
        local image = assets.get("skidWrapperDirections")
        local sprite = assets.getQuad("skidWrapperDirection1")
        if image and sprite then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(image, sprite.quad, 520, 360, 0, 0.72, 0.72, sprite.width / 2, sprite.height * 0.92)
        end
        local nearby = Wrapper.nearbyPallet(state)
        local inventory = state.inventory or {}
        if nearby then
            local palletImage, palletQuad
            if Wrapper.step == "wrapping" or Wrapper.step == "finished" then
                local stage = Wrapper.step == "finished" and 3
                    or math.max(1, math.min(3, math.ceil(Wrapper.progress / Wrapper.cycleTime * 3)))
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
        love.graphics.setColor(0.82, 0.88, 0.89)
        love.graphics.print("STATUS: " .. Wrapper.step:upper(), 50, 410)
        love.graphics.print("NEARBY PALLET: " .. (nearby and nearby.pallet.id or "NONE"), 50, 438)
        love.graphics.print("PACKAGE: " .. (nearby and (nearby.pallet.packaging or nearby.job.packaging or "flat"):upper() or "--"), 50, 466)
        love.graphics.print(string.format("PLASTIC: %d ROLL(S)  |  %d / 11 WRAPS", inventory.plasticWrapRolls or 0, inventory.plasticWrapUses or 0), 50, 494)
        box(wrapButton.x, wrapButton.y, wrapButton.width, wrapButton.height,
            nearby and (inventory.plasticWrapUses or 0) > 0 and { 0.15, 0.40, 0.27, 1 } or { 0.15, 0.17, 0.18, 1 }, { 0.35, 0.65, 0.48, 1 }, 3)
        love.graphics.setColor(0.95, 0.98, 0.92)
        love.graphics.printf(Wrapper.step == "wrapping" and string.format("WRAPPING %d%%", math.floor(Wrapper.progress / Wrapper.cycleTime * 100)) or "WRAP PALLET  [L]   MOVE [M]", wrapButton.x, wrapButton.y + 19, wrapButton.width, "center")
        love.graphics.print(state.message or "", 48, 635)
        return
    end
    if state.machineType == "picture_press" then
        box(18, 18, 924, 642, { 0.045, 0.055, 0.07, 0.99 }, { 0.38, 0.56, 0.62, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("TWO-COLOR PICTURE PRESS / PRODUCTION CONSOLE", 38, 30)
        BackButton.draw(assets, exitButton, "EXIT", pointerX, pointerY, false)
        local image = assets.get("picturePress")
        if image then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(image, 480, 350, 0, 0.48, 0.48, image:getWidth() / 2, image:getHeight() / 2)
        end
        local running = Press.step == "printing"
        love.graphics.setColor(0.82, 0.88, 0.89)
        love.graphics.print("STATUS: " .. Press.step:upper(), 50, 410)
        love.graphics.print(string.format("SHEETS PRINTED: %d", Press.sheets), 50, 438)
        love.graphics.print(running and string.format("ROLLER CYCLE %d%%", math.floor(Press.progress / Press.cycleTime * 100)) or "Press L / SPACE to start", 50, 466)
        box(50, 510, 220, 54, running and { 0.18, 0.42, 0.28, 1 } or { 0.13, 0.18, 0.23, 1 }, { 0.35, 0.62, 0.48, 1 }, 3)
        love.graphics.setColor(0.95, 0.98, 0.92)
        love.graphics.printf("START PRESS", 50, 528, 220, "center")
        love.graphics.print(state.message or "", 48, 635)
        return
    end
    layout()
    box(18, 18, 924, 642, { 0.045, 0.055, 0.07, 0.99 }, { 0.38, 0.56, 0.62, 1 }, 5)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print("POLAR 115 / JOB CUTTING CONSOLE", 38, 30)
    BackButton.draw(assets, exitButton, "EXIT", pointerX, pointerY, false)
    drawTouchscreen()
    drawMachine(assets)
    box(38, 400, 884, 58, { 0.075, 0.09, 0.11, 1 }, { 0.28, 0.40, 0.44, 1 }, 3)
    love.graphics.setColor(0.82, 0.88, 0.89)
    love.graphics.print("STATUS: " .. Machine.step:upper(), 50, 411)
    love.graphics.print("BARRIER: " .. (Machine.barrierClear and "CLEAR" or "BLOCKED"), 260, 411)
    love.graphics.print("CLAMP: " .. (Machine.clamp and "DOWN" or "UP"), 460, 411)
    love.graphics.print(Machine.paperTooltip(), 50, 435)
    for _, button in ipairs(buttons) do
        if button.y >= 400 and button.action ~= "cut_left" and button.action ~= "cut_right" and button.action ~= "estop" then drawButton(button) end
    end
    for _, button in ipairs(buttons) do
        if button.action == "cut_left" then drawSpriteButton(assets, button, false, Machine.leftDown)
        elseif button.action == "cut_right" then drawSpriteButton(assets, button, false, Machine.rightDown)
        elseif button.action == "estop" then drawSpriteButton(assets, button, true, Machine.emergencyStopped) end
    end
    love.graphics.setColor(0.75, 0.82, 0.83)
    love.graphics.print("Type gauge + ENTER  |  L load  G auto  P position  Q rotate CCW  SPACE clamp  J+K cut  U unload", 48, 535)
    love.graphics.print(state.message or "", 48, 635)
end

function Screen.mousepressed(state, x, y, button)
    if button ~= 1 then return false end
    if inside(exitButton, x, y) then return { action = "exit" } end
    if state.machineType == "skid_wrapper" then
        return inside(wrapButton, x, y) and Wrapper.start(state) or false
    end
    layout()
    if inside(gaugeInput, x, y) then
        Screen.gaugeFocused = true
        Screen.gaugeReplaceOnType = true
        return true
    end
    for _, target in ipairs(buttons) do
        if inside(target, x, y) then
            Screen.pressedAction = target.action
            local succeeded
            if target.action == "program" then succeeded = Machine.selectProgram(target.value, state)
            elseif target.action == "set_gauge" then succeeded = commitGauge(state)
            elseif target.action == "gauge" then succeeded = Machine.adjustGauge(target.value, state)
            elseif target.action == "auto" then succeeded = Machine.autoGauge(state)
            elseif target.action == "save" then succeeded = Machine.saveGauge(state)
            elseif target.action == "recall" then succeeded = Machine.recallGauge(state)
            else succeeded = Machine.keypressed(target.key, state) end
            if succeeded and target.action ~= "program" then formatGauge() end
            return succeeded
        end
    end
    Screen.gaugeFocused = false
    return false
end

function Screen.keypressed(state, key)
    if not Screen.gaugeFocused then return false end
    if key == "backspace" then
        if Screen.gaugeReplaceOnType then
            Screen.gaugeText = ""
            Screen.gaugeReplaceOnType = false
            return true
        end
        local byteOffset = utf8.offset(Screen.gaugeText, -1)
        if byteOffset then Screen.gaugeText = string.sub(Screen.gaugeText, 1, byteOffset - 1) end
        return true
    elseif key == "return" or key == "kpenter" then
        return commitGauge(state)
    end
    return false
end

function Screen.textinput(state, text)
    if not Screen.gaugeFocused then return false end
    local changed = false
    for character in text:gmatch(".") do
        if character:match("%d") and #Screen.gaugeText < 7 then
            if Screen.gaugeReplaceOnType then
                Screen.gaugeText = ""
                Screen.gaugeReplaceOnType = false
            end
            Screen.gaugeText = Screen.gaugeText .. character
            changed = true
        elseif character == "." and not Screen.gaugeText:find(".", 1, true) then
            if Screen.gaugeReplaceOnType then
                Screen.gaugeText = "0"
                Screen.gaugeReplaceOnType = false
            end
            Screen.gaugeText = Screen.gaugeText .. character
            changed = true
        end
    end
    return changed
end

function Screen.gaugeInputCenter()
    return gaugeInput.x + gaugeInput.width / 2, gaugeInput.y + gaugeInput.height / 2
end

function Screen.mousereleased(state, x, y, button)
    if button ~= 1 then return false end
    local action = Screen.pressedAction
    Screen.pressedAction = nil
    -- Mouse cut controls stay latched for the same 0.30-second simultaneity
    -- window used by the physical keys, making a quick J-then-K click valid.
    if action == "cut_left" or action == "cut_right" then return true end
    return action ~= nil
end

function Screen.buttonCenter(action, value)
    layout()
    for _, button in ipairs(buttons) do
        if button.action == action and (value == nil or button.value == value) then
            return button.x + button.width / 2, button.y + button.height / 2
        end
    end
end

function Screen.exitCenter()
    return exitButton.x + exitButton.width / 2, exitButton.y + exitButton.height / 2
end

return Screen
