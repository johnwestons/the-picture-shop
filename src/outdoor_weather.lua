local Calendar = require("src.business_calendar")

local Weather = {}
local SEED_MODULUS = 2147483647
local cachedDay, cachedConditions

local function settings(config)
    return (config and config.outdoorWeather) or require("src.config").outdoorWeather or {}
end

local function hash(day, salt)
    local value = (math.floor(math.max(0, tonumber(day) or 0)) + salt * 69621 + 1) % SEED_MODULUS
    value = (value * 48271) % SEED_MODULUS
    return (value * 48271) % SEED_MODULUS
end

function Weather.conditionsForDay(day, config)
    day = math.floor(math.max(0, tonumber(day) or 0))
    if cachedDay == day and not config then return cachedConditions end
    local options = settings(config)
    local seed = hash(day, 1)
    local chance = math.max(0, math.min(1, tonumber(options.rainChance) or 0.28))
    local conditions = { day = day, seed = seed, rain = seed / SEED_MODULUS < chance }
    if conditions.rain then
        local startMin = math.max(0, tonumber(options.rainStartMinHour) or 5)
        local startSpan = math.max(1, tonumber(options.rainStartHourSpan) or 13)
        local durationMin = math.max(0.25, tonumber(options.rainDurationMinHours) or 2)
        local durationSpan = math.max(0, tonumber(options.rainDurationHourSpan) or 4)
        conditions.rainStart = startMin + hash(day, 2) % startSpan
        conditions.rainEnd = conditions.rainStart + durationMin + hash(day, 3) % (durationSpan + 1)
    end
    if not config then cachedDay, cachedConditions = day, conditions end
    return conditions
end

local function smoothstep(value)
    value = math.max(0, math.min(1, value))
    return value * value * (3 - 2 * value)
end

function Weather.daylightForHour(hour, config)
    local options = settings(config)
    hour = (tonumber(hour) or 0) % 24
    local dawnStart = tonumber(options.dawnStartHour) or 5
    local dawnEnd = tonumber(options.dawnEndHour) or 7
    local duskStart = tonumber(options.duskStartHour) or 18
    local duskEnd = tonumber(options.duskEndHour) or 20
    if hour < dawnStart or hour >= duskEnd then return 0 end
    if hour < dawnEnd then return smoothstep((hour - dawnStart) / math.max(0.01, dawnEnd - dawnStart)) end
    if hour < duskStart then return 1 end
    return 1 - smoothstep((hour - duskStart) / math.max(0.01, duskEnd - duskStart))
end

function Weather.sampleAtHours(hours, config)
    hours = math.max(0, tonumber(hours) or 0)
    local day = math.floor(hours / 24)
    local hour = hours - day * 24
    local conditions = Weather.conditionsForDay(day, config)
    local raining = conditions.rain and hour >= conditions.rainStart and hour < conditions.rainEnd
    return Weather.daylightForHour(hour, config), raining, conditions.seed, hour, day
end

function Weather.sample(state, config)
    return Weather.sampleAtHours(Calendar.absoluteHours(state), config)
end

local function bayOpening(bayDoor, config)
    local graphics = love and love.graphics
    local progress = bayDoor and tonumber(bayDoor.progress) or 0
    local aperture = config and config.truck and config.truck.aperture
    if not graphics or progress <= 0 or type(aperture) ~= "table" or #aperture ~= 4 then return end

    local polygon, bounds = {}, { left = math.huge, right = -math.huge, top = math.huge, bottom = -math.huge }
    for _, point in ipairs(aperture) do
        polygon[#polygon + 1] = point.x
        polygon[#polygon + 1] = point.y
        bounds.left, bounds.right = math.min(bounds.left, point.x), math.max(bounds.right, point.x)
        bounds.top, bounds.bottom = math.min(bounds.top, point.y), math.max(bounds.bottom, point.y)
    end
    return graphics, progress, polygon, bounds
end

function Weather.drawExterior(state, bayDoor, config, assets)
    local graphics, progress, aperture, bounds = bayOpening(bayDoor, config)
    if not graphics then return end
    local sprite = assets and assets.get and assets.get("loadingBayExterior")
    if not sprite then return end
    local daylight, raining = Weather.sample(state, config)
    graphics.push("all")
    graphics.setStencilTest()
    graphics.stencil(function() graphics.polygon("fill", unpack(aperture)) end, "replace", 1)
    graphics.setStencilTest("greater", 0)
    -- The scene is a real asset; the shutter and weather remain independent layers.
    local shade = raining and .78 or 1
    graphics.setColor((.20 + .80 * daylight) * shade,
        (.26 + .74 * daylight) * shade, (.38 + .62 * daylight) * shade, 1)
    graphics.draw(sprite, bounds.left, bounds.top, 0,
        (bounds.right - bounds.left) / sprite:getWidth(),
        (bounds.bottom - bounds.top) / sprite:getHeight())
    graphics.setStencilTest()
    graphics.pop()
end
function Weather.draw(state, bayDoor, config)
    local graphics, progress, aperture, bounds = bayOpening(bayDoor, config)
    if not graphics then return end

    local daylight, raining, seed, hour = Weather.sample(state, config)
    local night = 1 - daylight
    graphics.push("all")
    graphics.setStencilTest()
    graphics.stencil(function()
        graphics.polygon("fill", unpack(aperture))
    end, "replace", 1)
    graphics.setStencilTest("greater", 0)

    local tintAlpha = (0.025 + night * 0.28 + (raining and 0.14 or 0)) * math.min(1, progress)
    graphics.setColor(0.12, 0.18, 0.25, tintAlpha)
    graphics.polygon("fill", unpack(aperture))

    if raining then
        local count = math.max(1, math.floor((settings(config).rainDropCount or 18) * math.min(1, progress)))
        local elapsed = love.timer and love.timer.getTime and love.timer.getTime() or hour * 3600
        local fall = math.floor(elapsed * 116 + seed % 149)
        local spanX = math.max(1, math.floor(bounds.right - bounds.left))
        local spanY = math.max(1, math.floor(bounds.bottom - bounds.top))
        graphics.setLineWidth(1.2)
        graphics.setColor(0.78, 0.88, 0.96, 0.66 * math.min(1, progress))
        for index = 1, count do
            local x = bounds.left + ((index * 37 + seed % 41 + math.floor(elapsed * 13)) % spanX)
            local y = bounds.top + ((index * 53 + fall) % spanY)
            graphics.line(x, y, x - 3, y + 9)
        end
    end

    graphics.setStencilTest()
    graphics.pop()
end

return Weather
