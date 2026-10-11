local Config = require("src.config")
local StatusLabels = require("src.status_labels")
local Ui = require("src.screens.ui")

local Screen = { item = nil, fonts = {} }

local PAPER = { x = 30, y = 25, width = 900, height = 600 }
local CLOSE = { x = 734, y = 548, width = 150, height = 42 }
local ART = { x = 669, y = 151, width = 188, height = 188 }
local INK = { 0.18, 0.16, 0.13, 1 }
local MUTED_INK = { 0.36, 0.31, 0.25, 1 }
local STAMP = { 0.40, 0.16, 0.12, 1 }

local function workOrderFont(size)
    if Screen.fonts[size] then return Screen.fonts[size] end
    local ok, font = pcall(love.graphics.newFont, Config.paths.workOrderFont, size)
    if not ok or not font then font = love.graphics.newFont(size) end
    Screen.fonts[size] = font
    return font
end

local function setFont(size)
    love.graphics.setFont(workOrderFont(size))
end

local function line(text, x, y, width, align)
    love.graphics.printf(tostring(text or "--"), x, y, width or 300, align or "left")
end

local function money(value)
    return string.format("$%.2f", tonumber(value) or 0)
end

local function sizeText(size)
    if type(size) ~= "table" or not tonumber(size.width) or not tonumber(size.height) then return "--" end
    return string.format("%g x %g in", size.width, size.height)
end

local function labelValue(label, value, x, y, width)
    setFont(12)
    love.graphics.setColor(MUTED_INK)
    line(string.upper(label), x, y, width)
    setFont(16)
    love.graphics.setColor(INK)
    line(value, x, y + 14, width)
end

local function processRoute(order, pallet)
    local steps = { "CUT" }
    local printRequired = type(order.press) == "table"
    if printRequired then steps[#steps + 1] = "PRINT" end
    steps[#steps + 1] = "WRAP"
    steps[#steps + 1] = "SHIP"

    local location = pallet.location
    local status = pallet.status
    local shipped = location == "outbound_truck" or status == "loaded_for_pickup"
        or status == "picked_up"
    local cutComplete = status == "cut" or status == "printed" or status == "finished"
        or status == "wrapped" or location == "at_press" or location == "press_output"
    local current = 1
    if shipped or pallet.wrapped == true or status == "wrapped" then
        current = #steps
    elseif cutComplete and printRequired
        and not (type(pallet.press) == "table" and pallet.press.status == "complete") then
        current = 2
    elseif cutComplete then
        current = #steps - 1
    end
    return steps, current
end

local function labelProcess(order, pallet, x, y, width)
    local steps, current = processRoute(order, pallet)
    setFont(12)
    love.graphics.setColor(MUTED_INK)
    line("JOB PROCESS", x, y, width)

    local font = workOrderFont(15)
    love.graphics.setFont(font)
    local separator = "/"
    local separatorWidth = font:getWidth(separator)
    local gap = 7
    local pad = 4
    local textWidths, totalWidth = {}, 0
    for index, step in ipairs(steps) do
        textWidths[index] = font:getWidth(step)
        totalWidth = totalWidth + textWidths[index] + pad * 2
        if index < #steps then totalWidth = totalWidth + separatorWidth + gap * 2 end
    end
    local scale = totalWidth > width and width / totalWidth or 1
    local cursor = x + math.max(0, (width - totalWidth * scale) / 2)
    local rowY = y + 14
    for index, step in ipairs(steps) do
        local textWidth = textWidths[index] * scale
        local boxWidth = textWidth + pad * 2 * scale
        local textX = cursor + pad * scale
        if index == current then
            love.graphics.setColor(0.55, 0.22, 0.16, 0.13)
            love.graphics.rectangle("fill", cursor, rowY - 1, boxWidth, 19, 2, 2)
            love.graphics.setColor(STAMP)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", cursor, rowY - 1, boxWidth, 19, 2, 2)
            love.graphics.setColor(STAMP)
        else
            love.graphics.setColor(MUTED_INK)
        end
        love.graphics.print(step, textX, rowY, 0, scale, 1)
        cursor = cursor + boxWidth
        if index < #steps then
            cursor = cursor + gap * scale
            love.graphics.setColor(MUTED_INK)
            love.graphics.print(separator, cursor, rowY, 0, scale, 1)
            cursor = cursor + separatorWidth * scale + gap * scale
        end
    end
end

local function artworkKey(order)
    if not order then return nil end
    return order.artwork and order.artwork.key or order.artworkKey
end

local function artworkName(order)
    if not order then return "NO CLIENT ART" end
    local art = order.artwork or {}
    return art.displayName or art.fileName or artworkKey(order) or "NO CLIENT ART"
end

local function drawCropMarks(rect)
    local length = 9
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.20, 0.18, 0.15, 0.75)
    love.graphics.line(rect.x - 5, rect.y, rect.x + length, rect.y)
    love.graphics.line(rect.x, rect.y - 5, rect.x, rect.y + length)
    love.graphics.line(rect.x + rect.width - length, rect.y, rect.x + rect.width + 5, rect.y)
    love.graphics.line(rect.x + rect.width, rect.y - 5, rect.x + rect.width, rect.y + length)
    love.graphics.line(rect.x - 5, rect.y + rect.height, rect.x + length, rect.y + rect.height)
    love.graphics.line(rect.x, rect.y + rect.height - length, rect.x, rect.y + rect.height + 5)
    love.graphics.line(rect.x + rect.width - length, rect.y + rect.height,
        rect.x + rect.width + 5, rect.y + rect.height)
    love.graphics.line(rect.x + rect.width, rect.y + rect.height - length,
        rect.x + rect.width, rect.y + rect.height + 5)
end

local function drawArtwork(assets, order)
    setFont(12)
    love.graphics.setColor(MUTED_INK)
    line("CLIENT ART / JOB COPY", ART.x, 126, ART.width, "center")

    love.graphics.setColor(0.97, 0.95, 0.88, 0.96)
    love.graphics.rectangle("fill", ART.x, ART.y, ART.width, ART.height)
    love.graphics.setColor(0.30, 0.26, 0.21, 0.88)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", ART.x, ART.y, ART.width, ART.height)
    drawCropMarks(ART)

    local key = artworkKey(order)
    local image = key and assets and assets.get and assets.get("artwork:" .. tostring(key)) or nil
    if image then
        local imageWidth, imageHeight = image:getDimensions()
        local maximumWidth, maximumHeight = ART.width - 22, ART.height - 22
        local scale = math.min(maximumWidth / imageWidth, maximumHeight / imageHeight)
        local drawWidth, drawHeight = imageWidth * scale, imageHeight * scale
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, ART.x + (ART.width - drawWidth) / 2,
            ART.y + (ART.height - drawHeight) / 2, 0, scale, scale)
    else
        setFont(14)
        love.graphics.setColor(MUTED_INK)
        line("NO ART FILE ATTACHED", ART.x + 12, ART.y + 82, ART.width - 24, "center")
    end

    setFont(12)
    love.graphics.setColor(MUTED_INK)
    line(artworkName(order), ART.x - 10, ART.y + ART.height + 14, ART.width + 20, "center")
end

local function drawCloseButton(mouseX, mouseY)
    local hovered = mouseX and mouseY and Ui.contains(CLOSE, mouseX, mouseY)
    local down = hovered and love.mouse and love.mouse.isDown and love.mouse.isDown(1)
    local inset = down and 2 or 0
    local rect = {
        x = CLOSE.x + inset,
        y = CLOSE.y + inset,
        width = CLOSE.width,
        height = CLOSE.height,
    }
    love.graphics.setColor(down and { 0.40, 0.16, 0.12, 0.18 }
        or hovered and { 0.62, 0.42, 0.22, 0.16 }
        or { 0.94, 0.89, 0.76, 0.34 })
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 2, 2)
    love.graphics.setColor(hovered and STAMP or MUTED_INK)
    love.graphics.setLineWidth(down and 3 or 2)
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 2, 2)
    setFont(15)
    line("[ ESC ]  CLOSE", rect.x, rect.y + 12, rect.width, "center")
end

local function drawHeader(item)
    setFont(23)
    love.graphics.setColor(STAMP)
    line("PAPER WORK ORDER", 102, 60, 320)
    setFont(13)
    love.graphics.setColor(MUTED_INK)
    line("ATTACHED PALLET", 470, 59, 150)
    setFont(15)
    love.graphics.setColor(INK)
    line(item and item.pallet and item.pallet.id or "UNKNOWN", 470, 78, 350)
end

local function drawCustomerOrder(item, assets)
    local order, pallet = item.job, item.pallet or {}
    local details = order.details or {}
    local paper = pallet.paper

    labelValue("Job number", order.id, 103, 126, 195)
    labelValue("Customer", order.company or "--", 103, 175, 195)
    labelValue("Status", StatusLabels.get(order.status), 103, 236, 195)
    labelValue("Inbound", StatusLabels.get((order.delivery or {}).status), 103, 285, 195)
    labelValue("Pallet status", StatusLabels.get(pallet.status), 103, 334, 195)
    labelValue("Location", StatusLabels.get(pallet.location), 103, 383, 195)
    labelValue("Paper", paper and StatusLabels.get(paper.status) or "Not cut", 103, 432, 195)

    labelValue("Parent sheet", sizeText(order.sourceSize), 337, 126, 286)
    labelValue("Finished size", sizeText(order.finishedSize), 337, 175, 286)
    labelValue("Stock", order.stockSpec and order.stockSpec.description
        or details.stockDescription or "Customer supplied", 337, 224, 286)
    labelValue("Pallet sheets", pallet.initialSheets or pallet.remainingSheets or 0, 337, 285, 286)
    labelValue("Current sheet", paper and sizeText(paper.currentSize) or sizeText(order.sourceSize),
        337, 334, 286)

    labelProcess(order, pallet, 337, 383, 286)

    local quote = order.quote or {}
    labelValue("Job value / lifts", string.format("%s / %s", money(quote.totalPrice),
        tostring(quote.totalLifts or "--")), 337, 432, 286)
    local jobPallets=order.pallets or {}
    if #jobPallets>1 then
        local palletNumber=tonumber(pallet.number)
        if not palletNumber then
            for index,jobPallet in ipairs(jobPallets) do
                if jobPallet==pallet or jobPallet.id==pallet.id then palletNumber=index;break end
            end
        end
        labelValue("Pallet", string.format("%s of %s", tostring(palletNumber or 1),
            tostring(#jobPallets)), 520, 432, 103)
    end
    local packaging=pallet.packaging or order.packaging or "flat"
    labelValue("Finishing", packaging=="boxed" and "Box, then stretch-wrap"
        or "Stretch-wrap flat", 337, 481, 286)
    if pallet.press then
        labelValue("Press", string.format("%s good / %s", tostring(pallet.press.goodSheets or 0),
            StatusLabels.get(pallet.press.status)), 669, 393, 188)
    end
    drawArtwork(assets, order)
end

local function drawVendorOrder(item)
    local order, pallet = item.job, item.pallet or {}
    labelValue("Order number", order.id, 103, 126, 195)
    labelValue("Document", "PURCHASE ORDER", 103, 175, 195)
    labelValue("Vendor", order.company or "--", 103, 236, 195)
    labelValue("Order state", StatusLabels.get(order.status), 103, 285, 195)
    labelValue("Delivery", StatusLabels.get((order.delivery or {}).status), 103, 334, 195)
    labelValue("Pallet state", StatusLabels.get(pallet.status), 103, 383, 195)
    labelValue("Location", StatusLabels.get(pallet.location), 103, 432, 195)

    labelValue("Product", pallet.productName or "--", 337, 126, 286)
    labelValue("Quantity", string.format("%s %s", tostring(pallet.quantity or 0),
        tostring(pallet.unit or "units")), 337, 175, 286)
    labelValue("Category", pallet.categoryName or "--", 337, 224, 286)
    labelValue("Purchase price", money(order.price), 337, 285, 286)

    love.graphics.setColor(0.97, 0.95, 0.88, 0.82)
    love.graphics.rectangle("fill", ART.x, ART.y, ART.width, ART.height)
    love.graphics.setColor(MUTED_INK)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", ART.x, ART.y, ART.width, ART.height)
    setFont(14)
    line("SUPPLY ORDER\nNO CLIENT ART", ART.x + 15, ART.y + 75, ART.width - 30, "center")
end

function Screen.enter(item)
    Screen.item = item
end

function Screen.closeCenter()
    return CLOSE.x + CLOSE.width / 2, CLOSE.y + CLOSE.height / 2
end

function Screen.hitTest(x, y)
    return Ui.contains(CLOSE, x, y) and "close" or nil
end

function Screen.artworkKey()
    return Screen.item and Screen.item.job and artworkKey(Screen.item.job) or nil
end

function Screen.mousepressed(x, y, button)
    if button == 1 and Screen.hitTest(x, y) == "close" then return { action = "close" } end
    return nil
end

function Screen.draw(_, assets, mouseX, mouseY)
    love.graphics.push("all")
    love.graphics.setColor(0.01, 0.015, 0.018, 0.72)
    love.graphics.rectangle("fill", 0, 0, Config.baseWidth, Config.baseHeight)
    love.graphics.setColor(0, 0, 0, 0.42)
    love.graphics.rectangle("fill", 49, 49, 866, 568, 8, 8)

    local paper = assets and assets.get and assets.get("palletWorkOrderPaper")
    if paper then
        local width, height = paper:getDimensions()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(paper, PAPER.x, PAPER.y, 0, PAPER.width / width, PAPER.height / height)
    else
        love.graphics.setColor(0.92, 0.86, 0.70, 1)
        love.graphics.rectangle("fill", 48, 39, 864, 574, 3, 3)
    end

    local item = Screen.item
    drawHeader(item)
    if not item or not item.job then
        labelValue("Notice", "No work order is attached to this pallet.", 103, 142, 520)
    elseif item.vendor then
        drawVendorOrder(item)
    else
        drawCustomerOrder(item, assets)
    end

    setFont(12)
    love.graphics.setColor(MUTED_INK)
    line("SHOP COPY - travels with pallet - office record is authoritative", 103, 522, 590)
    drawCloseButton(mouseX, mouseY)
    love.graphics.pop()
end

return Screen
