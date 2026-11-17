local Config = require('src.config')
local Settings = require('src.settings')

local Overlay = {}
local cache = {}

function Overlay.points(runtime)
    local scene = runtime.World and runtime.World.player and runtime.World.player.sceneId
    local view = scene == 'warehouse' and 'warehouse'
        or scene == 'home' and 'home'
        or scene == 'grocery' and 'grocery'
        or 'walking'
    local host = runtime.multiplayer and runtime.multiplayer:isHost() or false
    local settings = runtime.App.settings or {}
    if cache.settings == settings and cache.profiles == settings.controlLayoutProfiles
        and cache.controls == settings.controlLayout and cache.view == view
        and cache.host == host then
        return cache.points
    end
    local points = Settings.controlLayoutFor(settings, view, host)
    cache = { settings = settings, profiles = settings.controlLayoutProfiles,
        controls = settings.controlLayout, view = view, host = host, points = points }
    return points
end

function Overlay.rect(points, key, width, height, defaultX, defaultY)
    local point = points and points[key]
    if not point then
        return { x = defaultX, y = defaultY, width = width, height = height }
    end
    return {
        x = math.max(4, math.min(Config.baseWidth - width - 4,
            point.x * Config.baseWidth - width / 2)),
        y = math.max(4, math.min(Config.baseHeight - height - 4,
            point.y * Config.baseHeight - height / 2)),
        width = width,
        height = height,
    }
end

function Overlay.pockets(runtime)
    return Overlay.rect(Overlay.points(runtime), 'pockets', 130, 40, 820, 390)
end

return Overlay
