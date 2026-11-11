-- Project-authored mix; read at process start, independent of gameplay saves.
local Soundscape={}
local ok,manifest=pcall(require,'assets.audio.custom.manifest')
if not ok or type(manifest)~='table' then manifest={} end
local function unit(value,default)
    if type(value)~='number' or value~=value then return default end
    return math.max(0,math.min(1,value))
end
function Soundscape.path(id,fallback)
    local entry=manifest.slots and manifest.slots[id]
    local path=entry and entry.path
    if type(path)=='string' and path:match('^assets/audio/custom/%x+%.wav$')
        and love and love.filesystem and love.filesystem.getInfo(path) then return path end
    return fallback
end
function Soundscape.gain(id,bus)
    local entry=manifest.slots and manifest.slots[id] or {}
    local mix=manifest.mix or {}
    return unit(entry.gain,1)*unit(mix.master,1)*unit(mix[bus or entry.bus or 'sfx'],1)
end
return Soundscape
