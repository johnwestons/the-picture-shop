local Entries = require("src.update_notes")

local Panel = {}

local OPEN = { x = 710, y = 148, width = 140, height = 30 }
local BACK = { x = 710, y = 148, width = 140, height = 30 }
local VIEW = { x = 110, y = 185, width = 740, height = 418 }
local VIEWPORT = { x = 120, y = 194, width = 710, height = 397 }
local CARD = { x = 120, width = 706 }
local titleFont, bodyFont, smallFont

local function ensureFonts()
    local g = love.graphics
    titleFont = titleFont or g.newFont(14)
    bodyFont = bodyFont or g.newFont(12)
    smallFont = smallFont or g.newFont(10)
end

local function versionParts(version)
    local parts = {}
    for part in tostring(version or ""):gmatch("%d+") do
        parts[#parts + 1] = tonumber(part) or 0
    end
    return parts
end

function Panel.entries()
    local result = {}
    for index, entry in ipairs(Entries) do result[index] = entry end
    table.sort(result, function(left, right)
        local a, b = versionParts(left.version), versionParts(right.version)
        for index = 1, math.max(#a, #b) do
            local av, bv = a[index] or 0, b[index] or 0
            if av ~= bv then return av > bv end
        end
        return tostring(left.date or "") > tostring(right.date or "")
    end)
    return result
end

local function linesFor(text, width)
    local _, lines = bodyFont:getWrap(tostring(text or ""), width)
    return math.max(1, type(lines) == "table" and #lines or 1)
end

local function entryHeight(entry)
    local height = 55
    for _, change in ipairs(entry.changes or {}) do
        height = height + linesFor(change, CARD.width - 48) * 16 + 5
    end
    return height + 8
end

local function contentHeight(entries)
    local height = 8
    for _, entry in ipairs(entries) do height = height + entryHeight(entry) + 8 end
    return height
end

function Panel.maxOffset()
    ensureFonts()
    return math.max(0, contentHeight(Panel.entries()) - VIEWPORT.height)
end

function Panel.hitTest(x, y, page)
    local rect = page == "notes" and BACK or OPEN
    if x >= rect.x and x <= rect.x + rect.width
        and y >= rect.y and y <= rect.y + rect.height then
        return page == "notes" and "back" or "open"
    end
end

function Panel.inViewport(x, y)
    return x >= VIEWPORT.x and x <= VIEWPORT.x + VIEWPORT.width
        and y >= VIEWPORT.y and y <= VIEWPORT.y + VIEWPORT.height
end

local function drawButton(g, rect, label, active)
    g.setColor(active and .19 or .10, active and .27 or .15, active and .24 or .18, 1)
    g.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
    g.setColor(.77, .70, .42, 1)
    g.rectangle("line", rect.x, rect.y, rect.width, rect.height, 4, 4)
    g.setFont(smallFont)
    g.setColor(.96, .91, .73, 1)
    g.printf(label, rect.x, rect.y + 8, rect.width, "center")
end

function Panel.drawOpenButton()
    ensureFonts()
    local g = love.graphics
    g.push("all")
    drawButton(g, OPEN, "UPDATE NOTES", false)
    g.pop()
end

function Panel.drawOptions(offset)
    ensureFonts()
    local g = love.graphics
    local entries = Panel.entries()
    local maximum = Panel.maxOffset()
    offset = math.max(0, math.min(maximum, tonumber(offset) or 0))

    g.push("all")
    g.setShader()
    g.setColor(.92, .95, .89, 1)
    g.setFont(titleFont)
    g.print(("UPDATE NOTES · %d RELEASES"):format(#entries), 116, 151)
    drawButton(g, BACK, "BACK TO DEBUG", true)

    g.setColor(.045, .061, .064, .98)
    g.rectangle("fill", VIEW.x, VIEW.y, VIEW.width, VIEW.height, 5, 5)
    g.setColor(.29, .37, .36, 1)
    g.rectangle("line", VIEW.x, VIEW.y, VIEW.width, VIEW.height, 5, 5)

    local fullHeight = contentHeight(entries)
    local y = VIEWPORT.y - offset + 8
    g.setScissor(VIEWPORT.x, VIEWPORT.y, VIEWPORT.width, VIEWPORT.height)
    for _, entry in ipairs(entries) do
        local height = entryHeight(entry)
        if y + height > VIEWPORT.y and y < VIEWPORT.y + VIEWPORT.height then
            g.setColor(.075, .098, .098, 1)
            g.rectangle("fill", CARD.x, y, CARD.width, height, 4, 4)
            g.setColor(.31, .39, .36, 1)
            g.rectangle("line", CARD.x, y, CARD.width, height, 4, 4)
            g.setColor(.84, .68, .28, 1)
            g.rectangle("fill", CARD.x, y + 5, 3, height - 10)

            g.setFont(titleFont)
            g.setColor(.96, .83, .43, 1)
            g.print(tostring(entry.version or "Unknown version"), CARD.x + 13, y + 7)
            g.setFont(smallFont)
            g.setColor(.67, .78, .72, 1)
            g.printf(tostring(entry.date or "Date unavailable"), CARD.x + 365, y + 11,
                CARD.width - 378, "right")

            g.setFont(bodyFont)
            g.setColor(.88, .91, .84, 1)
            g.printf(tostring(entry.title or "Update"), CARD.x + 13, y + 29,
                CARD.width - 26, "left")
            local changeY = y + 51
            for _, change in ipairs(entry.changes or {}) do
                local lineCount = linesFor(change, CARD.width - 48)
                g.setColor(.84, .68, .28, 1)
                g.circle("fill", CARD.x + 17, changeY + 7, 2)
                g.setColor(.76, .83, .78, 1)
                g.printf(tostring(change), CARD.x + 27, changeY,
                    CARD.width - 40, "left")
                changeY = changeY + lineCount * 16 + 5
            end
        end
        y = y + height + 8
    end
    g.setScissor()

    if maximum > 0 then
        local trackX, trackY, trackH = 837, VIEWPORT.y + 3, VIEWPORT.height - 6
        local thumbH = math.max(30, trackH * VIEWPORT.height / fullHeight)
        local thumbY = trackY + (trackH - thumbH) * offset / maximum
        g.setColor(.10, .14, .14, 1)
        g.rectangle("fill", trackX, trackY, 5, trackH, 2, 2)
        g.setColor(.66, .59, .36, 1)
        g.rectangle("fill", trackX, thumbY, 5, thumbH, 2, 2)
    end
    g.pop()
    return offset
end

return Panel
