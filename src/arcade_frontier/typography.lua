local Typography = {}
local UIStyle = require("src.arcade_frontier.ui_layout")

Typography.BASE_SIZE = 20
Typography.MIN_SCALE = 0.85
Typography.FONT_PATHS = {
    regular = "assets/generated/frontier-arcade/assets/fonts/CourierPrime-Regular.ttf",
    bold = "assets/generated/frontier-arcade/assets/fonts/CourierPrime-Bold.ttf",
}

local fontCache = setmetatable({}, {__mode="k"})
local fontSizes = setmetatable({}, {__mode="k"})

function Typography.font(Graphics, weight, size)
    weight = weight or "regular"
    size = size or Typography.BASE_SIZE
    local path = assert(Typography.FONT_PATHS[weight], "unknown typewriter font weight: "..tostring(weight))
    local cache = fontCache[Graphics]
    if not cache then cache = {}; fontCache[Graphics] = cache end
    local key = weight..":"..tostring(size)
    if not cache[key] then
        local font = Graphics.newFont(path, size, "normal")
        -- Font antialiasing remains smooth when a phone scales the virtual UI.
        -- This is per-font; pixel-art images retain the nearest-neighbour filter.
        font:setFilter("linear", "linear")
        font:setLineHeight(1.08)
        fontSizes[font] = size
        cache[key] = font
    end
    return cache[key]
end

function Typography.install(Graphics)
    local font = Typography.font(Graphics)
    Graphics.setFont(font)
    return font
end

local function measure(font, text, width, scale, singleLine)
    local lineCount, measuredWidth
    if singleLine then
        lineCount = 1
        measuredWidth = font:getWidth(text)
    else
        local lines
        measuredWidth, lines = font:getWrap(text, math.max(1, width / scale))
        lineCount = math.max(1, #lines)
    end
    local height = font:getHeight() * (1 + (lineCount - 1) * font:getLineHeight()) * scale
    return measuredWidth * scale, height, lineCount
end

-- Return the largest readable scale that fits the actual wrapped font metrics.
-- A false final result asks the caller to make space; the minimum is never
-- bypassed to squeeze a long label into an unreadable sliver of text.
function Typography.fitText(Graphics, text, width, height, preferredScale, minScale, options)
    options = options or {}
    text = tostring(text or "")
    local font = Graphics.getFont()
    local upper = math.max(0.01, preferredScale or 1)
    local lower = math.min(upper, math.max(0.01, minScale or Typography.MIN_SCALE))
    local function metrics(scale)
        local measuredWidth, measuredHeight, lines = measure(font, text, width, scale, options.singleLine)
        local fits = measuredWidth <= width + 0.01 and measuredHeight <= height + 0.01
            and (not options.maxLines or lines <= options.maxLines)
        return measuredHeight, lines, fits
    end
    local measuredHeight, lines, fits = metrics(upper)
    if fits then return upper, measuredHeight, lines, true end
    measuredHeight, lines, fits = metrics(lower)
    if not fits then return lower, measuredHeight, lines, false end
    for _ = 1, 12 do
        local candidate = (lower + upper) / 2
        local _, _, candidateFits = metrics(candidate)
        if candidateFits then lower = candidate else upper = candidate end
    end
    measuredHeight, lines, fits = metrics(lower)
    return lower, measuredHeight, lines, fits
end

function Typography.drawText(Graphics, text, x, y, width, height, options)
    options = options or {}
    text = tostring(text or "")
    local groupScale,groupFont=UIStyle.currentTextStyle()
    local originalFont=Graphics.getFont()
    if groupFont then
        -- The line-box height includes font metrics and is not the requested
        -- font size. Reusing it here enlarges text whenever a style is applied.
        Graphics.setFont(Typography.font(Graphics,groupFont,fontSizes[originalFont] or Typography.BASE_SIZE))
    end
    local preferredScale=(options.scale or 1)*groupScale
    local minimumScale=(options.minScale or Typography.MIN_SCALE)*groupScale
    local scale, measuredHeight, lines, fits = Typography.fitText(
        Graphics, text, width, height, preferredScale, minimumScale, options
    )
    local offset = 0
    if options.valign == "center" then offset = math.max(0, (height - measuredHeight) / 2)
    elseif options.valign == "bottom" then offset = math.max(0, height - measuredHeight) end
    if options.singleLine then
        local measuredWidth = Graphics.getFont():getWidth(text) * scale
        if options.align == "center" then x = x + (width - measuredWidth) / 2
        elseif options.align == "right" then x = x + width - measuredWidth end
        Graphics.print(text, x, y + offset, 0, scale, scale)
    else
        Graphics.printf(text, x, y + offset, math.max(1, width / scale), options.align or "left", 0, scale, scale)
    end
    Graphics.setFont(originalFont)
    return scale, measuredHeight, lines, fits
end

return Typography
