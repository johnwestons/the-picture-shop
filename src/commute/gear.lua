-- Equipment is independent of character identity and scene. Transition clocks
-- are real seconds; only coherent equipment states belong in save snapshots.
local Gear={VERSION=1}
local sequences={
    equip={{'suit_on',1.2},{'zip_up',.8},{'boots_gloves',.7},{'helmet_on',1}},
    remove={{'helmet_off',.8},{'unzip',.7},{'suit_off',1.2}},
    mount={{'mount',.8},{'ignition',.9}},
    dismount={{'engine_off',.3},{'dismount',.8}},
}
local function finite(value) return type(value)=='number' and value==value and value>=0 and value<1e12 end
Gear.poseNames={normal_idle=true,geared_idle=true,riding=true,seated=true,crash=true}
for _,steps in pairs(sequences) do for _,step in ipairs(steps) do Gear.poseNames[step[1]]=true end end
function Gear.new() return {version=1,outfit='normal',mounted=false,engine=false,revision=0} end
function Gear.valid(g)
    local base=type(g)=='table' and g.version==Gear.VERSION
        and (g.outfit=='normal' or g.outfit=='geared') and type(g.mounted)=='boolean'
        and type(g.engine)=='boolean' and finite(g.revision) and g.revision%1==0
        and (not g.mounted or g.outfit=='geared') and (not g.engine or g.mounted)
        and (g.transition==nil or type(g.transition)=='table' and sequences[g.transition.kind]~=nil
            and finite(g.transition.elapsed))
    if not base then return false end
    local t=g.transition
    if not t then return true end
    if t.elapsed>=Gear.duration(t.kind) then return false end
    if t.kind=='equip' then return g.outfit=='normal' and not g.mounted end
    if t.kind=='remove' or t.kind=='mount' then return g.outfit=='geared' and not g.mounted end
    return g.outfit=='geared' and g.mounted and not g.engine
end
function Gear.duration(kind)
    local n=0;for _,step in ipairs(sequences[kind] or {}) do n=n+step[2] end;return n
end
function Gear.pose(g)
    if g.transition then
        if g.transition.kind=='mount' then
            -- The authored mount strip takes .8 seconds. Keep its seated final
            -- frame visible while the separate ignition step finishes, so the
            -- rider does not jump from a half-mounted pose onto the bike atlas.
            return 'mount',math.min(1,g.transition.elapsed/sequences.mount[1][2])
        end
        if g.transition.kind=='dismount' then
            return 'dismount',math.min(1,g.transition.elapsed/Gear.duration('dismount'))
        end
        local elapsed=g.transition.elapsed
        for _,step in ipairs(sequences[g.transition.kind]) do
            if elapsed<step[2] then return step[1],elapsed/step[2] end
            elapsed=elapsed-step[2]
        end
    end
    return g.mounted and (g.engine and 'riding' or 'seated') or g.outfit..'_idle',0
end
function Gear.allowed(g,action)
    if g.transition then return false,'Finish changing gear or getting on/off the bike first.' end
    local function result(okay,message) if okay then return true end;return false,message end
    if action=='ride' then return result(g.outfit=='geared' and g.mounted and g.engine,'Put on your full riding gear and start the bike first.') end
    if action=='walk' or action=='door' then return result(not g.mounted,'Park and dismount first.') end
    if action=='household' or action=='work' or action=='eat' then
        return result(g.outfit=='normal' and not g.mounted,'Take off your riding gear first.')
    end
    return false,'That action is unavailable in riding gear.'
end
function Gear.begin(g,kind,context)
    context=context or {}
    if not Gear.valid(g) then return false,'Invalid riding equipment.' end
    if not sequences[kind] then return false,'Unknown equipment action.' end
    if g.transition then return false,'Finish the current action first.' end
    if context.moving or math.abs(context.speed or 0)>.05 then return false,'Stop before changing gear or getting on/off the bike.' end
    if kind=='equip' then
        if g.outfit~='normal' or g.mounted then return false,'Your riding gear is already on.' end
        if not context.nearBike then return false,'Go to your motorcycle to put your gear on.' end
    elseif kind=='remove' then
        if g.outfit~='geared' or g.mounted then return false,'Dismount before taking your gear off.' end
    elseif kind=='mount' then
        if g.outfit~='geared' or g.mounted then return false,'Put on your complete riding gear first.' end
        if not context.nearBike then return false,'Go to your motorcycle first.' end
    elseif kind=='dismount' then
        if not g.mounted then return false,'You are already on foot.' end
        if not context.safeFooting then return false,'Park where there is room to stand beside the bike.' end
    end
    g.transition={kind=kind,elapsed=0};g.revision=g.revision+1
    if kind=='dismount' then g.engine=false end
    return true
end
function Gear.update(g,dt)
    if not g.transition or not finite(dt) then return false end
    local t=g.transition;t.elapsed=t.elapsed+dt
    if t.elapsed<Gear.duration(t.kind) then return false end
    if t.kind=='equip' then g.outfit='geared'
    elseif t.kind=='remove' then g.outfit='normal'
    elseif t.kind=='mount' then g.mounted=true;g.engine=true
    elseif t.kind=='dismount' then g.mounted=false;g.engine=false end
    g.transition=nil;g.revision=g.revision+1;return true
end
function Gear.snapshot(g)
    assert(Gear.valid(g),'Invalid riding equipment')
    local saved={version=Gear.VERSION,outfit=g.outfit,mounted=g.mounted,engine=g.engine,revision=g.revision}
    -- Save/disconnect during a dismount safely completes it. Other actions roll
    -- back to their last stable state; no half-dressed character is ride-ready.
    if g.transition and g.transition.kind=='dismount' then saved.mounted=false;saved.engine=false end
    return saved
end
function Gear.restore(saved)
    if saved==nil then return Gear.new() end
    if not Gear.valid(saved) then return nil,'Invalid riding equipment.' end
    return Gear.snapshot(saved)
end
return Gear
