-- Shared species and individual-character voice routing for dialogue playback.
local Voices={}
local INDIVIDUAL_VOICE_ONLY={['tinker-fox-worker']=true}
local REPTILE_MARKERS={'dragon','lizard','reptil','gecko','iguana','chameleon','snake','turtle'}
local CANINE_MARKERS={'fox','dog','canine','wolf','hound'}

local function hasMarker(id,markers)
    for _,marker in ipairs(markers)do
        if id:find(marker,1,true)then return true end
    end
    return false
end

function Voices.resolve(available,character)
    if type(available)~='table' or type(character)~='string' then return nil end
    local id=character:lower()
    local profile
    if id:find('cat',1,true)then
        profile='cat-worker'
    elseif id:find('raccoon',1,true)then
        profile='mechanic-raccoon'
    elseif hasMarker(id,REPTILE_MARKERS)then
        profile='business-dragon'
    elseif INDIVIDUAL_VOICE_ONLY[id]then
        profile=id
    elseif hasMarker(id,CANINE_MARKERS)then
        profile=available[id] and id or 'medic-fox-worker'
    else
        profile=available[id] and id or nil
    end
    return profile and type(available[profile])=='table' and profile or nil
end

function Voices.path(available,character,emotion)
    local profile=Voices.resolve(available,character)
    local clips=profile and available[profile]
    local path=clips and (clips[emotion or 'neutral'] or clips.neutral)
    return path,profile
end

return Voices
