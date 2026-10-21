-- Two pilots, one authoritative encounter. Personal weapons never advance the world twice.
local Range=require('src.arcade_frontier.shooting_range')
local Stand=require('src.arcade_frontier.last_stand_shootout')
local Shooting=require('src.arcade_frontier.first_person_shooting')
local Rules=require('src.arcade_frontier.train_ambush_rules')
local Scene=require('src.arcade_frontier.train_ambush_scene')
local Catalog=require('src.arcade_frontier.catalog')
local Frontier={FIRE=1,COVER=2,RELOAD=4,ADS=8,WEAPON=16,MODE=32,CONTINUE=64,SUPPLY=128}
local objectiveKeys={'originStop','holdElapsed','kills','enemyMorale','positionIntegrity','completedPhase','phaseCheckpoint','recoveries','suppressionElapsed'}
local function held(bits,bit) return math.floor((bits or 0)/bit)%2==1 end
local function profile()
    return {location=12,health=20,maxHealth=20,scrap=250,equipment={weapon='frontier-22-lever-rifle'},
        inventory={'frontier-22-lever-rifle','frontier-9mm-service-pistol','sawed-off-shotgun'},
        ammo={['22lr']=240,['9mm']=240,['12-gauge']=60},weaponDurability={},weaponProficiency={},
        maintenance={condition=100},resources={food=20,water=20},accessibility={}}
end
local function copyKeys(to,from,keys) for _,key in ipairs(keys) do to[key]=from[key] end end
local function standPilot(f,p,action)
    local w=f.world
    copyKeys(p.quest,f.objective,objectiveKeys)
    w.quest=p.quest;w.gun=p.gun;w.ducking=p.covered;w.coverProgress=p.coverProgress
    action(w,p.data)
    p.gun=w.gun;copyKeys(f.objective,p.quest,objectiveKeys)
    w.quest=f.objective;w.gun=f.pilots[1].gun
end
function Frontier.new(kind)
    local f={kind=kind,pilots={},clock=0,worldData=profile()}
    for slot=1,2 do
        local p={data=profile(),quest={},covered=false,coverProgress=0,previous=0,shots=0,score=0,shot=0}
        if kind=='range' then
            p.range=assert(Range.new(p.data,{highScores={},preferences={motion='mixed',material='paper',targetPattern='pop-up',distance=50}},Catalog))
            Range.keypressed(p.range,'return',p.data,Catalog)
        else p.gun=Shooting.new(p.data,Catalog,p.quest,960,720) end
        f.pilots[slot]=p
    end
    if kind=='range' then
        f.world=f.pilots[1].range
        f.pilots[2].range.targets=f.world.targets
    elseif kind=='stand' then
        f.objective={originStop=12}
        f.world=Stand.new(f.objective,f.worldData,Catalog,'wide',960,720)
        f.objective.weaponSession=nil
        f.world.arcadeCoop=true
    else f.world=Rules.start(f.worldData) end
    return f
end
local function damage(f,amount)
    local exposed={}
    for _,p in ipairs(f.pilots) do if p.data.health>0 and not p.covered and p.coverProgress==0 then exposed[#exposed+1]=p end end
    if #exposed>0 then
        f.damageCursor=(f.damageCursor or 0)%#exposed+1
        local p=exposed[f.damageCursor];p.data.health=math.max(0,p.data.health-amount)
    end
    f.worldData.health=(f.pilots[1].data.health>0 or f.pilots[2].data.health>0) and 20 or 1
end
local function cycleTrain(p)
    local options={}
    for _,option in ipairs(Shooting.weaponOptions(p.data,Catalog)) do if not option.borrowed then options[#options+1]=option end end
    local index=1
    for i,option in ipairs(options) do if option.name==p.gun.weapon then index=i%#options+1 end end
    p.gun=Shooting.chooseWeapon(p.gun,options[index],p.data,Catalog,p.quest)
end
local function useInput(f,p,input,dt)
    input=input or {};local bits=input.buttons or 0
    local edges=require('src.critter_crisis_actions').consume(p,input)
    local function pressed(bit) return held(edges,bit) end
    p.continuePressed=pressed(Frontier.CONTINUE)
    p.covered=held(bits,Frontier.COVER) or p.data.health<=0
    local target=p.covered and 1 or 0
    local step=dt/.28
    p.coverProgress=p.coverProgress+math.max(-step,math.min(step,target-p.coverProgress))
    if p.covered or input.suspended then p.waitingShot=false
    elseif pressed(Frontier.FIRE) and p.coverProgress>0 then p.waitingShot=true end
    p.shot=math.max(0,p.shot-dt)
    local x=math.max(0,math.min(960,480+(input.x or 0)*480))
    local y=math.max(0,math.min(720,360+(input.y or 0)*360))
    if f.kind=='range' then
        local r=p.range
        Range.mousemoved(r,x,y);Range.setAim(r,held(bits,Frontier.ADS))
        if pressed(Frontier.RELOAD) then Range.reload(r,p.data,Catalog) end
        if pressed(Frontier.WEAPON) then
            local phase=r.phase;r.phase='lobby';Range.select(r,p.data,Catalog,1);r.phase=phase
        end
        if pressed(Frontier.MODE) then Range.cycleFireMode(r) end
        if not p.covered and (pressed(Frontier.FIRE) or held(bits,Frontier.FIRE) and r.fireMode=='auto') then
            local result=Range.keypressed(r,'space',p.data,Catalog)
            if result=='shot' then p.shot=.14 end
        end
        r.fireHeld=false;p.shots=r.shots;p.score=r.score
    else
        Shooting.setAim(p.gun,x,y);Shooting.setADS(p.gun,held(bits,Frontier.ADS))
        if pressed(Frontier.RELOAD) then Shooting.reload(p.gun,p.data,p.quest) end
        if pressed(Frontier.MODE) then Shooting.cycleFireMode(p.gun) end
        if pressed(Frontier.WEAPON) then
            if f.kind=='stand' then standPilot(f,p,function(w,data)Stand.cycleWeapon(w,data,Catalog)end)
            else cycleTrain(p) end
        end
        if pressed(Frontier.SUPPLY) and f.kind=='stand' then standPilot(f,p,function(w,data)Stand.supply(w,data,Catalog)end) end
        if p.data.health>0 and not p.covered and p.coverProgress==0
            and (pressed(Frontier.FIRE) or p.waitingShot or held(bits,Frontier.FIRE) and p.gun.fireMode=='auto') then
            p.waitingShot=false
            local fired=false
            if f.kind=='stand' then
                standPilot(f,p,function(w,data)
                    local kills=w.quest.kills
                    fired=Stand.fire(w,data,960,720,Catalog)
                    p.score=p.score+(w.quest.kills-kills)*100
                end)
            elseif f.world.phase=='combat' and Scene.pointOpen(f.world,960,720,x,y) then
                fired=Shooting.fire(p.gun,p.data,p.quest)
                if fired then
                    f.world.cover=false;f.world.coverProgress=0
                    if Rules.hit(f.worldData,f.world,Scene.target(f.world,960,720,x,y),p.gun) then p.score=p.score+25 end
                    f.world.shots=f.world.shots+1
                end
            end
            if fired then p.shots=p.shots+1;p.shot=.14 end
        end
    end
    p.previous=bits
end
function Frontier.update(session,dt,inputFor)
    local f=session.frontier;f.clock=f.clock+dt
    local ids={session.ownerId,session.partnerId}
    for slot,p in ipairs(f.pilots) do
        local input=inputFor and inputFor(ids[slot],session) or nil
        p.input=input or {}
        if f.kind~='range' then Shooting.update(p.gun,dt,p.data,p.quest,960,720) end
    end
    if f.kind=='range' then
        local w=f.world
        Range.update(w,dt,f.pilots[1].data,Catalog)
        local r=f.pilots[2].range
        r.targets={};r.nextSpawn=1000000;r.time=w.time+math.min(dt,.08)
        Range.update(r,dt,f.pilots[2].data,Catalog)
        r.targets=w.targets;r.clock=w.clock;r.time=w.time
    end
    for _,p in ipairs(f.pilots) do useInput(f,p,p.input,dt);p.input=nil end
    if f.kind=='stand' then
        local w=f.world
        w.gun=f.pilots[1].gun;w.quest=f.objective
        w.ducking=f.pilots[1].covered and f.pilots[2].covered
        w.coverProgress=w.ducking and 1 or 0
        w.arcadeHit=function(amount)damage(f,amount)end
        Stand.update(w,dt,f.worldData,Catalog,960,720)
        w.arcadeHit=nil
        if w.result=='intermission' then
            for _,p in ipairs(f.pilots) do
                if held(p.previous,Frontier.CONTINUE) or p.continuePressed then
                    w.result=nil;w.stageBanner=2.8
                    for _,other in ipairs(f.pilots) do if other.data.health<=0 then other.data.health=10 end end
                    break
                end
            end
        elseif w.result=='victory' then session.phase='finished'
        elseif w.result=='retreat' then session.phase='failed' end
    elseif f.kind=='train' then
        f.world.cover=f.pilots[1].covered and f.pilots[2].covered
        f.world.coverProgress=f.world.cover and 1 or 0
        Rules.update(f.worldData,f.world,dt,function()damage(f,2);return true end)
        if f.world.phase=='result' then
            session.phase=(f.world.outcome=='disabled' or f.world.outcome=='crew') and 'finished' or 'failed'
        end
    elseif f.world.time<=0 then
        for _,p in ipairs(f.pilots) do Range.complete(p.range,p.data,p.range.spot,{add=function()end}) end
        session.phase='finished'
    end
    session.score=f.pilots[1].score+f.pilots[2].score
    for slot,p in ipairs(f.pilots) do
        local player=session.players[ids[slot]]
        if player then
            player.hp=math.ceil(p.data.health/4);player.ammo=f.kind=='range' and p.range.loaded or p.gun.magazine
            player.covered=p.covered;player.reload=math.min(1.2,f.kind=='range' and p.range.reloadTimer or p.gun.reloadTimer)
            player.shot=p.shot
        end
    end
end
function Frontier.view(f,slot)
    local p=f.pilots[slot];local w={}
    for key,value in pairs(f.world) do w[key]=value end
    if f.kind=='range' then return p.range,p.data end
    if f.kind=='stand' then
        local quest={};for key,value in pairs(p.quest) do quest[key]=value end
        copyKeys(quest,f.objective,objectiveKeys)
        w.quest=quest;w.gun=p.gun;w.ducking=p.covered;w.coverProgress=p.coverProgress
    else w.cover=p.covered;w.coverProgress=p.coverProgress end
    return w,p.data,p.gun
end
return Frontier
