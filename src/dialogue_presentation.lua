-- Local-only dialogue presentation. No save state or network payloads.
local P={entries=setmetatable({},{__mode='k'}),clock=0,level=1,voiceVolume=1,enabled=true}
local profile=require('src.dialogue_profile')
local ok,voices=pcall(require,'assets.audio.dialogue.manifest')
if not ok then voices={} end
local Soundscape=require('src.soundscape')
local VoiceRouting=require('src.dialogue_voices')
local function stop(e)if e and e.source then e.source:stop();e.source:release();e.source=nil end end
local function reveal(text,count)
    local utf8=require('utf8');local length=utf8.len(text)
    if not length then return text:sub(1,count) end
    if count>=length then return text end
    return text:sub(1,(utf8.offset(text,count+1) or #text+1)-1)
end
function P.present(key,character,message,emotion)
    local e=P.entries[key]
    if not e or e.input~=message then
        if message then
            stop(e)
            e={input=message,text=message,started=P.clock,last=P.clock,pending=true}
            local path=VoiceRouting.path(voices,character,emotion)
            if path and P.enabled and love and love.audio then
                local loaded,source=pcall(love.audio.newSource,path,'static')
                if loaded then e.source=source;e.source:setLooping(false) end
            end
            local duration=e.source and e.source:getDuration() or 0
            e.expires=P.clock+math.max(profile.hold,profile.delay+duration+.3,profile.cps>0 and #message/profile.cps+.8 or 0)
            P.entries[key]=e
        elseif e then e.input=nil end
    end
    if not e then return nil end
    e.last=P.clock
    if not message and P.clock>=e.expires then stop(e);P.entries[key]=nil;return nil end
    local text=profile.cps==0 and e.text or reveal(e.text,math.floor((P.clock-e.started)*profile.cps))
    return text,e.text
end
function P.update(dt,level,enabled,voiceVolume,voicesEnabled)
    P.clock=P.clock+math.max(0,dt or 0);P.level=level or 1
    P.voiceVolume=math.max(0,math.min(1,tonumber(voiceVolume)or 1))
    P.enabled=enabled~=false and voicesEnabled~=false
    for key,e in pairs(P.entries)do
        if P.clock-e.last>.25 then stop(e);P.entries[key]=nil
        elseif not P.enabled then stop(e);e.pending=false
        elseif e.pending and P.clock-e.started>=profile.delay then
            e.pending=false
            if e.source then e.source:setVolume(profile.gain*P.level*P.voiceVolume*Soundscape.gain('dialogue','sfx'));e.source:play() end
        elseif e.source then e.source:setVolume(profile.gain*P.level*P.voiceVolume*Soundscape.gain('dialogue','sfx')) end
    end
end
function P.reset()for _,e in pairs(P.entries)do stop(e)end;P.entries=setmetatable({},{__mode='k'})end
return P
