local Settings = {}
local Video=require('src.video_settings')
local PlayerProfile = require('src.player_profile')
local RabbitColorways = require("src.rabbit_colorways")
local MotorcycleBindings = require('src.commute.bindings')
local SilhouetteStyle = require('src.commute.silhouette_style')

local PATH = "settings.lua"
local CONTROL_LAYOUT_VIEWS = {
    "shared", "walking", "warehouse", "home", "room", "overworld", "motorcycle", "truck",
    "grocery", "gas_station", "mechanic_shop",
}
local CONTROL_LAYOUT_KEYS = {
    "joystick", "primary", "extra1", "extra2", "stick",
    "touch1", "touch2", "touch3", "touch4", "touch5", "touch6", "move", "use",
}
local DEFAULTS = {
    dynamicShadows=true,vegetationShadows=false,shadowDistance='medium',renderDistance='medium',
    playerName = PlayerProfile.DEFAULT_NAME,
    fullscreen = false,
    vsync = true,
    followPlayerCamera = false,
    twelveHourTime = true,
    hudVisible = true,
    gpsMiniMapScale = 1,
    notificationClipboardDarkMode = false,
    furColorway = 1,
    overallsColorway = 1,
    muted = false,
    lanConnectionMode = "auto",
    lanAutoJoin = false,
    masterVolume = 100,
    sfxVolume = 85,
    ambientVolume = 42,
    dialogueVolume = 100,
    dialogueVoicesEnabled = true,
    mobileWalkSensitivity = 100,
    mobileDriveSensitivity = 100,
    mobileVehicleSteering = "radial",
    mobileBikeSteering = "radial",
    occlusionHighlightColor = SilhouetteStyle.DEFAULT_COLOR,
    occlusionHighlightStyle = SilhouetteStyle.DEFAULT_STYLE,
    controlLayout = {
        joystick = { x = 0.105, y = 0.846 },
        primary = { x = 0.906, y = 0.846 },
        extra1 = { x = 0.799, y = 0.891 },
        extra2 = { x = 0.799, y = 0.764 },
    },
    controlLayoutProfiles = {},
}

local function clampPercent(value, fallback)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.max(0, math.min(100, math.floor(value + 0.5)))
end

local function clampSensitivity(value)
    value = tonumber(value)
    if not value or value ~= value then return 100 end
    return math.max(50, math.min(150, math.floor(value + 0.5)))
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

local function normalizeLayoutProfiles(value)
    value = type(value) == "table" and value or {}
    local result = {}
    for _, view in ipairs(CONTROL_LAYOUT_VIEWS) do
        local source = type(value[view]) == "table" and value[view] or {}
        local profile = {}
        for _, key in ipairs(CONTROL_LAYOUT_KEYS) do
            local point = source[key]
            if type(point) == "table" then
                local x, y = tonumber(point.x), tonumber(point.y)
                if x and x == x and y and y == y then
                    profile[key] = {
                        x = math.max(0.04, math.min(0.96, x)),
                        y = math.max(0.06, math.min(0.94, y)),
                    }
                end
            end
        end
        if next(profile) then result[view] = profile end
    end
    return result
end

local function encodeLayoutProfiles(value)
    local views = {}
    for _, view in ipairs(CONTROL_LAYOUT_VIEWS) do
        local profile = value[view]
        if profile then
            local points = {}
            for _, key in ipairs(CONTROL_LAYOUT_KEYS) do
                local point = profile[key]
                if point then
                    points[#points + 1] = string.format("%s = { x = %.6f, y = %.6f }",
                        key, point.x, point.y)
                end
            end
            if #points > 0 then
                views[#views + 1] = view .. " = { " .. table.concat(points, ", ") .. " }"
            end
        end
    end
    return "{ " .. table.concat(views, ", ") .. " }"
end

function Settings.normalize(value)
    value = type(value) == "table" and value or {}
    local video=Video.normalize(value)
    local furColorway, overallsColorway = RabbitColorways.normalize(
        value.furColorway, value.overallsColorway)
    local occlusionHighlightColor,occlusionHighlightStyle=SilhouetteStyle.normalize(
        value.occlusionHighlightColor,value.occlusionHighlightStyle)
    local lanConnectionMode = value.lanConnectionMode
    if lanConnectionMode ~= "wifi" and lanConnectionMode ~= "usb" then
        lanConnectionMode = "auto"
    end
    local mobileVehicleSteering=value.mobileVehicleSteering
    if mobileVehicleSteering=="horizontal" then mobileVehicleSteering="bike-horizontal" end
    if mobileVehicleSteering~="radial" and mobileVehicleSteering~="bike-horizontal"
        and mobileVehicleSteering~="all-horizontal" then
        mobileVehicleSteering=value.mobileBikeSteering=="horizontal" and "bike-horizontal" or "radial"
    end
    local gpsMiniMapScale=tonumber(value.gpsMiniMapScale)
    if not gpsMiniMapScale or gpsMiniMapScale~=gpsMiniMapScale then gpsMiniMapScale=DEFAULTS.gpsMiniMapScale end
    gpsMiniMapScale=math.max(.62,math.min(1,gpsMiniMapScale))
    return {
        dynamicShadows=video.dynamicShadows,vegetationShadows=video.vegetationShadows,
        shadowDistance=video.shadowDistance,renderDistance=video.renderDistance,
        fullscreen = value.fullscreen == true,
        playerName = PlayerProfile.name(value),
        vsync = value.vsync ~= false,
        followPlayerCamera = value.followPlayerCamera == true,
        twelveHourTime = value.twelveHourTime ~= false,
        hudVisible = value.hudVisible ~= false,
        gpsMiniMapScale = gpsMiniMapScale,
        notificationClipboardDarkMode = value.notificationClipboardDarkMode == true,
        furColorway = furColorway,
        overallsColorway = overallsColorway,
        muted = value.muted == true,
        lanConnectionMode = lanConnectionMode,
        lanAutoJoin = value.lanAutoJoin == true,
        masterVolume = clampPercent(value.masterVolume, DEFAULTS.masterVolume),
        sfxVolume = clampPercent(value.sfxVolume, DEFAULTS.sfxVolume),
        ambientVolume = clampPercent(value.ambientVolume, DEFAULTS.ambientVolume),
        dialogueVolume = clampPercent(value.dialogueVolume, DEFAULTS.dialogueVolume),
        dialogueVoicesEnabled = value.dialogueVoicesEnabled ~= false,
        mobileWalkSensitivity = clampSensitivity(value.mobileWalkSensitivity),
        mobileDriveSensitivity = clampSensitivity(value.mobileDriveSensitivity),
        mobileVehicleSteering=mobileVehicleSteering,
        -- Keep the legacy key readable by older builds and settings consumers.
        mobileBikeSteering=mobileVehicleSteering=="radial" and "radial" or "horizontal",
        occlusionHighlightColor = occlusionHighlightColor,
        occlusionHighlightStyle = occlusionHighlightStyle,
        controlLayout = normalizeLayout(value.controlLayout),
        controlLayoutProfiles = normalizeLayoutProfiles(value.controlLayoutProfiles),
        motorcycleControls = MotorcycleBindings.normalize(value.motorcycleControls),
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
    local encoded = string.format(
        "{ fullscreen = %s, vsync = %s, followPlayerCamera = %s, twelveHourTime = %s, hudVisible = %s, gpsMiniMapScale = %.3f, notificationClipboardDarkMode = %s, furColorway = %d, overallsColorway = %d, muted = %s, lanConnectionMode = %q, lanAutoJoin = %s, masterVolume = %d, sfxVolume = %d, ambientVolume = %d, dialogueVolume = %d, dialogueVoicesEnabled = %s, mobileWalkSensitivity = %d, mobileDriveSensitivity = %d, mobileBikeSteering = %q, mobileVehicleSteering = %q, occlusionHighlightColor = %q, occlusionHighlightStyle = %q, controlLayout = { joystick = { x = %.6f, y = %.6f }, primary = { x = %.6f, y = %.6f }, extra1 = { x = %.6f, y = %.6f }, extra2 = { x = %.6f, y = %.6f } } }",
        tostring(value.fullscreen), tostring(value.vsync), tostring(value.followPlayerCamera),
        tostring(value.twelveHourTime), tostring(value.hudVisible), value.gpsMiniMapScale,
        tostring(value.notificationClipboardDarkMode),
        value.furColorway, value.overallsColorway, tostring(value.muted),
        value.lanConnectionMode, tostring(value.lanAutoJoin),
        value.masterVolume, value.sfxVolume, value.ambientVolume,
        value.dialogueVolume, tostring(value.dialogueVoicesEnabled),
        value.mobileWalkSensitivity, value.mobileDriveSensitivity,
        value.mobileBikeSteering,
        value.mobileVehicleSteering,
        value.occlusionHighlightColor,value.occlusionHighlightStyle,
        value.controlLayout.joystick.x, value.controlLayout.joystick.y,
        value.controlLayout.primary.x, value.controlLayout.primary.y,
        value.controlLayout.extra1.x, value.controlLayout.extra1.y,
        value.controlLayout.extra2.x, value.controlLayout.extra2.y)
    return encoded:sub(1,-2)..', playerName = '..string.format('%q',value.playerName)
        ..string.format(', dynamicShadows = %s, vegetationShadows = %s, shadowDistance = %q, renderDistance = %q',
            tostring(value.dynamicShadows),tostring(value.vegetationShadows),value.shadowDistance,value.renderDistance)
        ..', controlLayoutProfiles = '..encodeLayoutProfiles(value.controlLayoutProfiles)
        ..', motorcycleControls = '..MotorcycleBindings.encode(value.motorcycleControls)..' }'
end

function Settings.controlLayoutViews()
    return {
        { id = "shared", label = "Shared controls", kind = "mobile" },
        { id = "walking", label = "Walking", kind = "mobile" },
        { id = "warehouse", label = "Warehouse", kind = "mobile" },
        { id = "home", label = "Home", kind = "mobile" },
        { id = "room", label = "Shop rooms", kind = "mobile" },
        { id = "overworld", label = "Overworld on foot", kind = "commute" },
        { id = "motorcycle", label = "Motorcycle driving", kind = "commute" },
        { id = "truck", label = "Truck driving", kind = "commute" },
        { id = "grocery", label = "Grocery store", kind = "mobile" },
        { id = "gas_station", label = "Gas station", kind = "mobile" },
        { id = "mechanic_shop", label = "Mechanic shop", kind = "mobile" },
    }
end

function Settings.controlLayoutFor(value, view)
    value = Settings.normalize(value)
    local profile = view and value.controlLayoutProfiles[view]
    local result
    if view == "shared" or not view then
        result = normalizeLayout(value.controlLayout)
    elseif view == "overworld" or view == "motorcycle" or view == "truck" then
        result = {}
        for key, point in pairs(value.motorcycleControls.layout or {}) do
            result[key] = { x = point.x, y = point.y }
        end
        local shared = value.controlLayoutProfiles.shared or {}
        if shared.move then result.stick = { x = shared.move.x, y = shared.move.y } end
        if shared.use then
            local token = value.motorcycleControls.touch.interact
            local touchKey = type(token) == "string" and token:match("^touch[1-6]$")
            if touchKey then result[touchKey] = { x = shared.use.x, y = shared.use.y } end
        end
        for key, point in pairs(profile or {}) do
            if key == "stick" or key:match("^touch[1-6]$") then
                result[key] = { x = point.x, y = point.y }
            end
        end
    else
        result = normalizeLayout(value.controlLayout)
        for _, key in ipairs({ "joystick", "primary", "extra1", "extra2" }) do
            if profile and profile[key] then result[key] = { x = profile[key].x, y = profile[key].y } end
        end
    end
    return result
end

function Settings.setControlLayout(value, view, layout, selectedKey)
    value = Settings.normalize(value)
    layout = type(layout) == "table" and layout or {}
    if view == "shared" or not view then
        value.controlLayout = normalizeLayout(layout)
        value.controlLayoutProfiles.shared = value.controlLayoutProfiles.shared or {}
        local keys = selectedKey == "joystick" and { { "move", "joystick" } }
            or selectedKey == "primary" and { { "use", "primary" } }
            or selectedKey == nil and { { "move", "joystick" }, { "use", "primary" } }
            or {}
        for _, alias in ipairs(keys) do
            local point = layout[alias[2]]
            if type(point) == "table" then
                value.controlLayoutProfiles.shared[alias[1]] = {
                    x = math.max(0.04, math.min(0.96, tonumber(point.x) or 0.5)),
                    y = math.max(0.06, math.min(0.94, tonumber(point.y) or 0.5)),
                }
            end
        end
    else
        value.controlLayoutProfiles[view] = value.controlLayoutProfiles[view] or {}
        local keys = (view == "overworld" or view == "motorcycle" or view == "truck")
            and { "stick", "touch1", "touch2", "touch3", "touch4", "touch5", "touch6" }
            or { "joystick", "primary", "extra1", "extra2" }
        for _, key in ipairs(keys) do
            if not selectedKey or selectedKey == key then
                local point = layout[key]
                if type(point) == "table" then
                    local fallback = Settings.controlLayoutFor(value, view)[key]
                        or value.controlLayout[key]
                        or { x = 0.5, y = 0.5 }
                    local x, y = tonumber(point.x), tonumber(point.y)
                    value.controlLayoutProfiles[view][key] = {
                        x = math.max(0.04, math.min(0.96, x or fallback.x)),
                        y = math.max(0.06, math.min(0.94, y or fallback.y)),
                    }
                end
            end
        end
    end
    return Settings.normalize(value)
end

function Settings.resetControlLayout(value, view)
    value = Settings.normalize(value)
    if view == "shared" or not view then
        value.controlLayout = normalizeLayout(DEFAULTS.controlLayout)
        value.controlLayoutProfiles.shared = {
            move = { x = DEFAULTS.controlLayout.joystick.x, y = DEFAULTS.controlLayout.joystick.y },
            use = { x = DEFAULTS.controlLayout.primary.x, y = DEFAULTS.controlLayout.primary.y },
        }
    else
        value.controlLayoutProfiles[view] = nil
    end
    return Settings.normalize(value)
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

-- Preview shares preferences with the game, but never reads a shop save.
function Settings.sharedMotorcycle(profile)
    local identity=love.filesystem.getIdentity()
    love.filesystem.setIdentity('the-picture-shop')
    local okay,result=pcall(function()
        local settings=Settings.load()
        if profile then settings.motorcycleControls=profile;return Settings.save(settings) end
        return settings.motorcycleControls
    end)
    love.filesystem.setIdentity(identity)
    if not okay then return profile and false or MotorcycleBindings.defaults() end
    return result
end

function Settings.applyDisplay(value)
    value = Settings.normalize(value)
    Video.apply(value)
    if not love or not love.window then return false end
    local android = love.system and love.system.getOS and love.system.getOS() == "Android"
    if not android and love.window.setFullscreen then
        if not love.window.getFullscreen or love.window.getFullscreen()~=value.fullscreen then
            pcall(love.window.setFullscreen, value.fullscreen, "desktop")
        end
    end
    if love.window.setVSync and (not love.window.getVSync or love.window.getVSync()~=(value.vsync and 1 or 0)) then
        pcall(love.window.setVSync, value.vsync and 1 or 0)
    end
    return true
end

Settings.DEFAULTS = DEFAULTS
Settings.normalizeControlLayout = normalizeLayout
return Settings
