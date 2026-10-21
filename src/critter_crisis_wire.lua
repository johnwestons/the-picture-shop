-- Bounded, atomically assembled encounter frames. A dropped shard never exposes half a world.
local Codec=require('src.net.codec')
local Wire={PART_BYTES=600,MAX_PARTS=80,LIMITS={maxBytes=48000,maxDepth=14,maxEntries=6000,maxStringBytes=512,maxNumberBytes=32}}
local excluded={weaponSession=true,weaponSessions=true,arcadeHit=true,arcadeSound=true,input=true,touchAim=true}
local function clean(value,depth)
    if type(value)=='number' then return math.floor(value*10000+.5)/10000 end
    if type(value)=='function' then return nil end
    if type(value)~='table' then return value end
    assert(depth<14,'arcade frame nesting exceeds its budget')
    local result={}
    for key,item in pairs(value) do if not excluded[key] then result[key]=clean(item,depth+1) end end
    return result
end
function Wire.parts(session)
    if not session.frontier then return {} end
    local data,err=Codec.encode(clean(session.frontier,0),Wire.LIMITS)
    if not data then return nil,err end
    local parts={}
    for offset=1,#data,Wire.PART_BYTES do parts[#parts+1]=data:sub(offset,offset+Wire.PART_BYTES-1) end
    return parts
end
local function number(n,a,b) return type(n)=='number' and n==n and n>=a and n<=b end
function Wire.decode(bytes)
    local frame,err=Codec.decode(bytes,Wire.LIMITS)
    if not frame then return nil,err end
    if type(frame)~='table' or not ({range=true,stand=true,train=true})[frame.kind]
        or type(frame.pilots)~='table' or #frame.pilots~=2 or type(frame.world)~='table'
        or type(frame.worldData)~='table' then return nil,'invalid arcade frame' end
    local weapons=require('src.arcade_frontier.catalog').weaponCombat
    for _,p in ipairs(frame.pilots) do
        if type(p)~='table' or type(p.data)~='table' or not number(p.data.health,0,20)
            or not number(p.coverProgress,0,1) or type(p.covered)~='boolean' or type(p.quest)~='table'
            or type(p.data.ammo)~='table' then return nil,'invalid arcade pilot' end
        local gun=frame.kind=='range' and p.range or p.gun
        if type(gun)~='table' or not weapons[gun.weapon] or not number(gun.aimX,0,960)
            or not number(gun.aimY,0,720) then return nil,'invalid arcade weapon' end
    end
    if frame.kind=='stand' then
        if type(frame.objective)~='table' or type(frame.world.targets)~='table' or #frame.world.targets~=8 then return nil,'invalid defense' end
        local atlases={};for _,path in ipairs(require('src.arcade_frontier.window_scene').targetAtlases) do atlases[path]=true end
        for _,target in ipairs(frame.world.targets) do
            if type(target)~='table' or not atlases[target.atlas] or not number(target.slot,1,8) then return nil,'invalid defense target' end
        end
    elseif frame.kind=='train' then
        if type(frame.world.vehicles)~='table' or #frame.world.vehicles~=3 then return nil,'invalid convoy' end
        for _,vehicle in ipairs(frame.world.vehicles) do
            if type(vehicle)~='table' then return nil,'invalid vehicle' end
            local def=require('src.arcade_frontier.train_ambush_rules').vehicleDefs[vehicle.id]
            if not def or vehicle.art~=def.art or vehicle.cellW~=def.cellW or vehicle.cellH~=def.cellH
                or vehicle.sourceY~=def.sourceY or type(vehicle.crew)~='table' or #vehicle.crew~=def.crewCount then return nil,'invalid vehicle' end
        end
    end
    return frame
end
function Wire.accept(store,payload,now)
    local bay=payload.bayId;local cache=store[bay]
    if cache and payload.serverTick<cache.tick then return nil end
    if not cache or payload.serverTick>cache.tick then
        cache={tick=payload.serverTick,roundId=payload.roundId,total=payload.total,parts={},count=0,bytes=0,at=now}
        store[bay]=cache
    end
    if cache.total~=payload.total or cache.roundId~=payload.roundId or cache.done or now-cache.at>1 then return nil end
    if not cache.parts[payload.part] then
        cache.parts[payload.part]=payload.data;cache.count=cache.count+1;cache.bytes=cache.bytes+#payload.data
    end
    if cache.bytes>Wire.LIMITS.maxBytes then cache.done=true;return nil end
    if cache.count~=cache.total then return nil end
    cache.done=true
    local frame=Wire.decode(table.concat(cache.parts));cache.parts={}
    return frame
end
return Wire
