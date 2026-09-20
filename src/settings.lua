local Settings = {}

local PATH = "settings.lua"
local DEFAULTS = {
    fullscreen = false,
    vsync = true,
    muted = false,
    masterVolume = 100,
    sfxVolume = 85,
    ambientVolume = 42,
    controlLayout = {
        joystick = { x = 0.105, y = 0.846 },
        primary = { x = 0.906, y = 0.846 },
        extra1 = { x = 0.799, y = 0.891 },
        extra2 = { x = 0.799, y = 0.764 },
    },
}

local function clampPercent(value, fallback)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.max(0, math.min(100, math.floor(value + 0.5)))
end

local function normalizePoint(value, fallback)
    value = type(value) == "table" and value or {}
    local x, y = tonumber(value.x), tonumber(value.y)
    if not x or x ~= x then x = fallback.x end
    if not y or y ~= y then y = fallback.y end
    return {
        x = math.max(0.05, math.min(0.95, x)),
        y = math.max(0.08, math.min(0.92, y)),
    }
end

local function normalizeLayout(value)
    value = type(value) == "table" and value or {}
    return {
        joystick = normalizePoint(value.joystick, DEFAULTS.controlLayout.joystick),
        primary = normalizePoint(value.primary, DEFAULTS.controlLayout.primary),
        extra1 = normalizePoint(value.extra1, DEFAULTS.controlLayout.extra1),
        extra2 = normalizePoint(value.extra2, DEFAULTS.controlLayout.extra2),
    }
end

function Settings.normalize(value)
    value = type(value) == "table" and value or {}
    return {
        fullscreen = value.fullscreen == true,
        vsync = value.vsync ~= false,
        muted = value.muted == true,
        masterVolume = clampPercent(value.masterVolume, DEFAULTS.masterVolume),
        sfxVolume = clampPercent(value.sfxVolume, DEFAULTS.sfxVolume),
        ambientVolume = clampPercent(value.ambientVolume, DEFAULTS.ambientVolume),
        controlLayout = normalizeLayout(value.controlLayout),
    }
end

local function parse(source)
    if type(source) ~= "string" then return nil end
    local chunk = loadstring("return " .. source)
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok, value = pcall(chunk)
    if not ok or type(value) ~= "table" then return nil end
    return Settings.normalize(value)
end

local function encode(value)
    value = Settings.normalize(value)
    return string.format(
        "{ fullscreen = %s, vsync = %s, muted = %s, masterVolume = %d, sfxVolume = %d, ambientVolume = %d, controlLayout = { joystick = { x = %.6f, y = %.6f }, primary = { x = %.6f, y = %.6f }, extra1 = { x = %.6f, y = %.6f }, extra2 = { x = %.6f, y = %.6f } } }",
        tostring(value.fullscreen), tostring(value.vsync), tostring(value.muted),
        value.masterVolume, value.sfxVolume, value.ambientVolume,
        value.controlLayout.joystick.x, value.controlLayout.joystick.y,
        value.controlLayout.primary.x, value.controlLayout.primary.y,
        value.controlLayout.extra1.x, value.controlLayout.extra1.y,
        value.controlLayout.extra2.x, value.controlLayout.extra2.y)
end

function Settings.load()
    if not love or not love.filesystem or not love.filesystem.getInfo
        or not love.filesystem.getInfo(PATH, "file")
    then
        return Settings.normalize(DEFAULTS)
    end
    return parse(love.filesystem.read(PATH)) or Settings.normalize(DEFAULTS)
end

function Settings.save(value)
    if not love or not love.filesystem or not love.filesystem.write then return false end
    local source = encode(value)
    if not parse(source) then return false end
    return love.filesystem.write(PATH, source) == true
end

function Settings.applyAudio(value, sound)
    value = Settings.normalize(value)
    if sound and sound.setLevels then
        sound:setLevels(value.masterVolume / 100, value.sfxVolume / 100,
            value.ambientVolume / 100)
        sound:setMuted(value.muted)
    end
end

function Settings.applyDisplay(value)
    value = Settings.normalize(value)
    if not love or not love.window then return false end
    local android = love.system and love.system.getOS and love.system.getOS() == "Android"
    if not android and love.window.setFullscreen then
        pcall(love.window.setFullscreen, value.fullscreen, "desktop")
    end
    if love.window.setVSync then pcall(love.window.setVSync, value.vsync and 1 or 0) end
    return true
end

Settings.DEFAULTS = DEFAULTS
Settings.normalizeControlLayout = normalizeLayout
return Settings
