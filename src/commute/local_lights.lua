-- Bounded surface lighting. Selection depends on world position, never view angle.
local L={lights={},blockers={},trucks=setmetatable({},{__mode='k'})}
function L.prepare(renderer,camera,actors,daylight)
    local world=renderer.world
    if L.world~=world then
        L.world=world;L.fixtures={};L.slots={};L.lastTime=nil
        for _,f in ipairs(require('src.commute.infrastructure').ensure(world).fixtures) do
            if f.kind=='lamp' then L.fixtures[#L.fixtures+1]={f.x,f.h+3.3,f.z,8,0,0} end
        end
        for _,s in ipairs((world.roads.sites or require('src.commute.sites').default).all) do
            local t=s.design.threshold
            local x,z,h=s:toWorld(t.x,t.z+.35,2.65)
            L.fixtures[#L.fixtures+1]={x,h,z,6,-s.sin,s.cos}
        end
    end
    L.lights={};L.blockers={};L.night=1-(daylight or 0)
    local shadowRange=math.min(24,require('src.video_settings').shadowRadius())
    local nearest={}
    for _,f in ipairs(L.fixtures) do
        local d=(f[1]-camera.centerX)^2+(f[3]-camera.centerZ)^2
        if d<24^2 then
            local at=#nearest+1
            for i,v in ipairs(nearest) do if d<v.d then at=i;break end end
            table.insert(nearest,at,{f=f,d=d});if #nearest>4 then table.remove(nearest) end
        end
    end
    -- Keep departing lamps in their slots until dark; replacements fade in.
    -- This also smooths nearest-four changes in dense streets, not just radius exits.
    local now=renderer.clock or love.timer.getTime()
    local dt=math.max(0,math.min(.1,now-(L.lastTime or now)))
    L.lastTime=now;L.slots=L.slots or {}
    local wanted={}
    for _,v in ipairs(nearest) do
        local t=math.max(0,math.min(1,(24-math.sqrt(v.d))/8))
        wanted[v.f]=t*t*(3-2*t)
    end
    for i=#L.slots,1,-1 do
        local slot=L.slots[i];local target=wanted[slot.f] or 0
        local step=dt/.45
        slot.weight=slot.weight+math.max(-step,math.min(step,target-slot.weight))
        if slot.weight==0 and not wanted[slot.f] then table.remove(L.slots,i) end
    end
    for _,v in ipairs(nearest) do
        local present=false
        for _,slot in ipairs(L.slots) do if slot.f==v.f then present=true;break end end
        if not present and #L.slots<4 then L.slots[#L.slots+1]={f=v.f,weight=0} end
    end
    for _,slot in ipairs(L.slots) do
        local f=slot.f
        L.lights[#L.lights+1]={f[1],f[2],f[3],f[4],f[5],f[6],slot.weight}
    end
    local candidates={}
    for _,e in ipairs(actors or {}) do
        local p=e.actor
        if p then
            L.trucks[p]=e.truck==true
            local distance=(p.x-camera.centerX)^2+(p.z-camera.centerZ)^2
            if distance<shadowRange^2 then
                local at=#candidates+1
                for i,v in ipairs(candidates) do if distance<v.distance then at=i;break end end
                table.insert(candidates,at,{entry=e,distance=distance})
                if #candidates>4 then table.remove(candidates) end
            end
        end
    end
    for _,candidate in ipairs(candidates) do
        local e=candidate.entry;local p=e.actor
        local d=e.truck and require('src.commute.truck_footprint').dimensions(p)
        L.blockers[#L.blockers+1]={p.x,p.h or world:supportHeight(p.x,p.z),p.z,
            d and d.halfLength or .9,d and d.halfWidth or .48,d and d.height or 1.85,p.heading or 0,
            e.truck and 0 or (e.onFoot or e.characterId or (e.gear and not e.gear.mounted and not e.bikeOnly)) and 1 or e.bikeOnly and 3 or 2}
    end
end
function L.release(world)
    if L.world==world then L.world=nil;L.fixtures={};L.lights={};L.blockers={};L.night=0;L.slots={};L.lastTime=nil end
end
function L.send(shader,camera)
    if not shader:hasUniform('localLightCount') then return end
    local pos,dirs,base,size={},{},{},{}
    for i=1,4 do
        local f=L.lights[i] or {0,0,0,1,0,0}
        pos[i]={f[1]-camera.centerX,f[2],f[3]-camera.centerZ,f[4]}
        dirs[i]={f[5],f[6],f[7] or 1}
        local b=L.blockers[i] or {0,0,0,0,0,0,0}
        base[i]={b[1]-camera.centerX,b[2],b[3]-camera.centerZ,b[7]}
        size[i]={b[4],b[5],b[6],b[8] or 0}
    end
    shader:send('localLightCount',#L.lights);shader:send('localNight',L.night or 0)
    shader:send('localLightPosition',unpack(pos));shader:send('localLightDirection',unpack(dirs))
    shader:send('localBlockerCount',require('src.video_settings').current.dynamicShadows and #L.blockers or 0)
    shader:send('localBlockerBase',unpack(base));shader:send('localBlockerSize',unpack(size))
end
return L
