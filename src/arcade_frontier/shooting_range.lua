local WorldView=require("src.arcade_frontier.world_view")
local SoundProfiles=require("src.arcade_frontier.weapon_sound_profiles")
local FirstPersonWeaponManifest=require("src.arcade_frontier.first_person_weapon_manifest")
local WeaponActions=require("src.arcade_frontier.first_person_weapon_actions")
local MobileAim=require("src.arcade_frontier.mobile_weapon_aim")
local Typography=require("src.arcade_frontier.typography")
local Items=require("src.arcade_frontier.item_instances")
local Range={}

local function text(value,x,y,w,h,scale,minimum,align,singleLine)
    return Typography.drawText(love.graphics,value,x,y,w,h,{scale=scale or 1,minScale=minimum or .78,align=align or "center",valign="center",singleLine=singleLine})
end

Range.version=4
Range.roundSeconds=45
Range.stageLengths={30,45,60,90}
Range.hostStops={2,8,14,20,26,32,38,44,50}
Range.motionModes={"stationary","moving","mixed"}
Range.targetTypes={"paper","steel","clay","sectioned"}
Range.targetPatterns={"stay-up","pop-up"}
Range.targetDistances={25,50,75,100,125,150,175,200,225,250,275,300}
Range.motionScoreMultipliers={stationary=1,mixed=1.15,moving=1.30}
Range.ammoBundles={
    rocks={amount=16,cost=1},arrows={amount=8,cost=2},["ball-bearings"]={amount=12,cost=2},
    ["12-gauge"]={amount=6,cost=3},["22lr"]={amount=18,cost=3},default={amount=12,cost=3},
}

local hostLookup={}
for _,location in ipairs(Range.hostStops) do hostLookup[location]=true end

local lanes={
    {x=205,y=332,scale=.27,radius=34},
    {x=370,y=300,scale=.24,radius=29},
    {x=525,y=350,scale=.29,radius=37},
    {x=690,y=292,scale=.23,radius=28},
    {x=800,y=382,scale=.31,radius=40},
    {x=470,y=255,scale=.26,radius=27},
}

local function shotgunPellets(weapon)
    local radius=weapon=="sawed-off-shotgun" and 18 or 14
    local pellets={}
    for index=1,7 do
        local x,y
        for attempt=1,24 do
            local angle=math.random()*math.pi*2
            local distance=math.sqrt(math.random())*radius
            x,y=math.cos(angle)*distance,math.sin(angle)*distance
            local separated=true
            for _,previous in ipairs(pellets) do
                local dx,dy=x-previous.x,y-previous.y
                if dx*dx+dy*dy<9 then separated=false; break end
            end
            if separated then break end
        end
        pellets[index]={x=x,y=y}
    end
    return pellets
end

local lobbyRows={
    {kind="weapon",y=270,label="WEAPON"},
    {kind="motion",y=365,label="TARGET MOTION"},
    {kind="material",y=460,label="TARGET TYPE"},
}

local DEFAULT_SIGHT_ANCHOR={x=.5,y=.35}
local MOBILE_FIRE_BUTTON={x=410,y=654,w=132,h=42}
local MOBILE_MODE_BUTTON={x=548,y=654,w=126,h=42}
local DESKTOP_MODE_BUTTON={x=548,y=654,w=126,h=42}
local MONOCULAR_BUTTON={x=366,y=50,w=228,h=40}
local MONOCULAR_CENTER={x=480,y=330}
local MONOCULAR_ZOOM=1.5

local function title(value)
    return (value or "unknown"):gsub("%-"," "):gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end)
end

local function contains(list,value)
    for _,entry in ipairs(list or {}) do if entry==value then return true end end
    return false
end

local function hit(rect,x,y)
    return rect and x>=rect.x and x<=rect.x+rect.w and y>=rect.y and y<=rect.y+rect.h
end

local function availableAmmo(data,combat)
    if not combat or not combat.ammo then return math.huge end
    return math.max(0,math.floor(tonumber(data and data.ammo and data.ammo[combat.ammo]) or 0))
end

local function validDistance(value)
    value=math.floor(tonumber(value) or 50)
    for _,distance in ipairs(Range.targetDistances) do
        if distance==value then return value end
    end
    return 50
end

local function distanceScale(distance)
    local progress=(validDistance(distance)-25)/275
    return 1-.4*progress
end

local function distanceProgress(distance)
    return (validDistance(distance)-25)/275
end

local function weaponDurability(data,name)
    local value=Items.condition(data,name)
    return math.max(0,math.min(100,math.floor(tonumber(value) or 100)))
end

local function weaponIssue(data,catalog,name)
    local selector=name
    if Items.enabled(data) then
        local entry=Items.selection(data,selector,catalog)
        if not entry then return "WEAPON NO LONGER AVAILABLE" end
        name=entry.name
    end
    local combat=name and catalog.weaponCombat[name]
    if not combat or combat.kind~="ranged" then return "NOT A RANGED WEAPON" end
    if weaponDurability(data,selector)<=0 then return "THIS WEAPON IS BROKEN" end
    if availableAmmo(data,combat)<=0 then return "THIS WEAPON NEEDS AMMO" end
    return nil
end

local function weaponReady(data,catalog,name)
    return weaponIssue(data,catalog,name)==nil
end

function Range.isHost(location)
    return hostLookup[math.floor(tonumber(location) or 0)]==true
end

function Range.ensure(layout,location,settlements)
    if not layout or not Range.isHost(location) then return nil end
    if type(layout.shootingRange)~="table" or layout.shootingRange.version~=Range.version then
        local x,y=760,565
        if settlements and settlements.clamp then x,y=settlements.clamp(x,y,location) end
        local previous=type(layout.shootingRange)=="table" and layout.shootingRange or {}
        layout.shootingRange={version=Range.version,x=x,y=y,rewarded=previous.rewarded==true,rewardTier=previous.rewardTier,
            highScores=type(previous.highScores)=="table" and previous.highScores or {},preferences=previous.preferences}
    end
    local spot=layout.shootingRange
    spot.highScores=type(spot.highScores)=="table" and spot.highScores or {}
    spot.preferences=type(spot.preferences)=="table" and spot.preferences or {motion="stationary",material="paper"}
    spot.preferences.distance=validDistance(spot.preferences.distance)
    local rewardTier=tonumber(spot.rewardTier)
    if rewardTier==nil then rewardTier=spot.rewarded==true and 3 or 0 end
    spot.rewardTier=math.max(0,math.min(3,math.floor(rewardTier)))
    spot.rewarded=spot.rewardTier>0
    spot.x=tonumber(spot.x) or 760; spot.y=tonumber(spot.y) or 565
    return spot
end

function Range.near(spot,x,y)
    if not spot then return false end
    local dx,dy=(x or 0)-spot.x,(y or 0)-spot.y
    return dx*dx+dy*dy<=66*66
end

function Range.scoreMultiplier(session)
    local mode=type(session)=="table" and session.motion or session
    return Range.motionScoreMultipliers[mode] or 1
end

function Range.ownedWeapons(data,catalog)
    if Items.enabled(data) then
        local result={}
        for _,entry in ipairs(Items.weapons(data,catalog)) do
            if catalog.weaponCombat[entry.name] and catalog.weaponCombat[entry.name].kind=="ranged" then result[#result+1]=entry.key end
        end
        return result
    end
    local result,seen={},{}
    local function add(name)
        local combat=name and catalog.weaponCombat[name]
        if combat and combat.kind=="ranged" and not seen[name] then
            seen[name]=true; result[#result+1]=name
        end
    end
    for _,name in pairs(data.equipment or {}) do add(name) end
    for _,name in pairs(data.inventory or {}) do add(name) end
    table.sort(result,function(a,b)
        local pa,pb=0,0
        for index,name in ipairs(catalog.weaponProgression or {}) do
            if name==a then pa=index elseif name==b then pb=index end
        end
        return pa==pb and a<b or pa<pb
    end)
    return result
end

function Range.hasMonocular(data)
    local inventory=data and data.inventory or {}
    local capacity=math.max(0,math.floor(tonumber(data and data.inventoryCapacity) or 6))
    for index=1,capacity do if inventory[index]=="monocular" then return true end end
    return false
end

function Range.magnification(session)
    return session and session.phase=="play" and session.hasMonocular and session.monocularActive and MONOCULAR_ZOOM or 1
end

local function firstReady(data,catalog,weapons)
    for index,name in ipairs(weapons) do if weaponReady(data,catalog,name) then return index end end
    return nil
end

local function firstServiceable(data,weapons)
    for index,name in ipairs(weapons) do if weaponDurability(data,name)>0 then return index end end
    return nil
end

local function clearWeaponViewSequence(session)
    session.weaponViewSequence=nil
    session.weaponViewState=nil
    session.weaponViewPlacement=nil
end

local function applyWeaponViewSequenceStep(session)
    local sequence=session.weaponViewSequence
    local step=sequence and sequence.definition.steps[sequence.index]
    if not step then return false end
    session.weaponViewState=step.state
    session.weaponViewPlacement=step.placement
    return true
end

local function startWeaponViewSequence(session)
    local definition=FirstPersonWeaponManifest.shotSequenceFor(session.weapon)
    clearWeaponViewSequence(session)
    if not definition then return false end
    session.weaponViewSequence={definition=definition,index=1,elapsed=0}
    return applyWeaponViewSequenceStep(session)
end

local function updateWeaponViewSequence(session,dt)
    local sequence=session.weaponViewSequence
    if not sequence then return end
    local remaining=dt
    while sequence do
        local step=sequence.definition.steps[sequence.index]
        if not step or step.duration==nil then return end
        local untilNext=step.duration-sequence.elapsed
        if remaining<untilNext then
            sequence.elapsed=sequence.elapsed+remaining
            return
        end
        remaining=remaining-untilNext
        sequence.index=sequence.index+1
        sequence.elapsed=0
        if applyWeaponViewSequenceStep(session) then
            sequence=session.weaponViewSequence
        else
            local restoresLoaded=sequence.definition.restoresLoaded==true
            clearWeaponViewSequence(session)
            if restoresLoaded then
                session.loaded=session.capacity or 1
                session.needsReload=false
                if session.message=="PROJECTILE RETURNING" or session.message=="PROJECTILE NOT READY" then session.message=nil end
            end
            return
        end
    end
end

local function loadWeapon(session,data,catalog)
    local selector=session.weapons[session.selected]
    if Items.enabled(data) then
        local entry=Items.selection(data,selector,catalog)
        if not entry then session.message="WEAPON NO LONGER AVAILABLE"; return false end
        session.weapon,session.itemId=entry.name,entry.id
    else session.weapon=selector end
    local combat=catalog.weaponCombat[session.weapon]
    session.ammoType=combat.ammo
    session.capacity=math.max(1,math.floor(combat.capacity or 1))
    session.loaded=math.min(session.capacity,availableAmmo(data,combat))
    session.needsReload=false
    session.cooldown=0
    session.reloadTimer=0
    session.fireHeld=false
    if not FirstPersonWeaponManifest.fireModeValid(session.weapon,session.fireMode) then session.fireMode="single" end
    WeaponActions.finish(session)
    clearWeaponViewSequence(session)
    MobileAim.refresh(session,session.weapon,session.aimMode)
    return true
end

function Range.new(data,spot,catalog,options)
    spot.preferences=type(spot.preferences)=="table" and spot.preferences or {motion="stationary",material="paper"}
    local stageLength=math.floor(tonumber(spot.preferences.stageLength) or Range.roundSeconds)
    local validStageLength=false
    for _,value in ipairs(Range.stageLengths) do if stageLength==value then validStageLength=true; break end end
    if not validStageLength then stageLength=Range.roundSeconds end
    local targetPattern=spot.preferences.targetPattern=="pop-up" and "pop-up" or "stay-up"
    local weapons=Range.ownedWeapons(data,catalog)
    local selected=firstReady(data,catalog,weapons) or firstServiceable(data,weapons)
    if #weapons==0 then return nil,"Bring a ranged weapon if you want to practice at the range." end
    if not selected then return nil,"Your ranged weapons need repairs before you can practice at the range." end
    local session={
        phase="lobby",spot=spot,weapons=weapons,selected=selected,location=data.location,
        npc=options and options.npc,aimX=480,aimY=330,clock=0,score=0,shots=0,hits=0,
        targets={},dirtImpacts={},spawnIndex=0,nextSpawn=.15,time=Range.roundSeconds,message=nil,
        hasMonocular=Range.hasMonocular(data),monocularActive=false,
        menuRow=1,motion=spot.preferences.motion or "stationary",material=spot.preferences.material or "paper",
        aimMode="hip",needsReload=false,reloadPulse=0,targetPattern=targetPattern,stageLength=stageLength,
        distance=validDistance(spot.preferences.distance),fireMode="single",sectionsHit=0,
    }
    loadWeapon(session,data,catalog)
    return session
end

local function spawnTarget(session)
    session.spawnIndex=session.spawnIndex+1
    local lane=lanes[((session.spawnIndex-1)%#lanes)+1]
    local moving=session.motion=="moving" or (session.motion=="mixed" and session.spawnIndex%2==0)
    local direction=session.spawnIndex%2==0 and 1 or -1
    local material=session.material
    local sprite=material=="paper" and ((session.spawnIndex-1)%4+1) or material=="steel" and ((session.spawnIndex-1)%4+5) or 10
    local depth=distanceProgress(session.distance)
    local sizeScale=distanceScale(session.distance)
    local positionScale=.55+.45*sizeScale
    local x=480+(lane.x-480)*positionScale
    -- The practice lanes recede toward the horizon: near targets sit low on
    -- the berm, while far targets rise toward the smaller backstop silhouettes.
    local laneSpread=.50-.15*depth
    local y=465+(300-465)*depth+(lane.y-320)*laneSpread
    local points=math.floor(100*Range.scoreMultiplier(session)+.5)
    session.targets[#session.targets+1]={
        x=x,y=y,baseX=x,scale=lane.scale*sizeScale,material=material,sprite=sprite,
        radius=lane.radius*sizeScale,points=points,
        life=(material=="sectioned" or session.targetPattern=="stay-up") and math.huge or (moving and 3.4 or 2.8),age=0,
        velocity=moving and direction*(48+session.spawnIndex%4*8)*positionScale or 0,hit=false,impacts={},
        sections=material=="sectioned" and {} or nil,
    }
end

local SECTION_RINGS={
    {outer={56,81},inner={40,60},score="7"},
    {outer={40,60},inner={26,40},score="8"},
    {outer={26,40},inner={12,17},score="9"},
}

local function superellipseValue(x,y,radii)
    local nx=math.abs(x)/radii[1]
    local ny=math.abs(y)/radii[2]
    return nx^4+ny^4
end

local function sectionAtPoint(target,x,y)
    local localX=(x-target.x)/target.scale
    local localY=(y-target.y)/target.scale
    for ringIndex,ring in ipairs(SECTION_RINGS) do
        if superellipseValue(localX,localY,ring.outer)<=1 then
            if superellipseValue(localX,localY,ring.inner)>1 then
                local sector=math.floor((math.atan2(localY,localX)+math.pi)/(math.pi/2))+1
                sector=math.max(1,math.min(4,sector))
                return (ringIndex-1)*4+sector
            end
        else
            return nil
        end
    end
    if superellipseValue(localX,localY,{12,17})<=1 then return 13 end
    return nil
end

local function superellipsePoint(rx,ry,angle)
    local cosine,sine=math.cos(angle),math.sin(angle)
    local function signedRoot(value)
        return (value<0 and -1 or 1)*math.abs(value)^.5
    end
    return rx*signedRoot(cosine),ry*signedRoot(sine)
end

local sectionedQuadCache=setmetatable({}, {__mode="k"})

local function sectionedQuad(image,index)
    local quads=sectionedQuadCache[image]
    if not quads then
        quads={}
        local imageWidth,imageHeight=image:getDimensions()
        local cellWidth,cellHeight,padding=128,174,2
        local slotWidth,slotHeight=cellWidth+padding*2,cellHeight+padding*2
        for sectionIndex=1,13 do
            local column=(sectionIndex-1)%4
            local row=math.floor((sectionIndex-1)/4)
            quads[sectionIndex]=love.graphics.newQuad(column*slotWidth+padding,row*slotHeight+padding,
                cellWidth,cellHeight,imageWidth,imageHeight)
        end
        sectionedQuadCache[image]=quads
    end
    return quads[index]
end

local function drawSectionedTarget(target,image,frame)
    if not image then return end
    love.graphics.push()
    love.graphics.translate(target.x,target.y)
    love.graphics.scale(target.scale)
    local frameAlpha=target.clearing and math.max(0,target.life/.55) or 1
    if frame then
        love.graphics.setColor(1,1,1,frameAlpha)
        love.graphics.draw(frame,-64,-87,0,128/frame:getWidth(),174/frame:getHeight())
    end
    local font=love.graphics.getFont()
    for index=1,13 do
        local section=target.sections[index]
        if not (section and section.broken) then
            local elapsed=section and section.breaking and section.breakElapsed or 0
            local progress=math.max(0,math.min(1,elapsed/.5))
            local shard=math.max(0,(progress-.20)/.80)
            local dx,dy,rotation=0,0,0
            if shard>0 then
                local angle=-math.pi+(index-1)*math.pi*2/13
                dx=math.cos(angle)*shard*27
                dy=math.sin(angle)*shard*18+shard*shard*43
                rotation=math.cos(angle)*shard*.24
            end
            local alpha=1-shard*.95
            love.graphics.push()
            love.graphics.translate(dx,dy)
            love.graphics.rotate(rotation)
            love.graphics.setColor(1,1,1,alpha)
            love.graphics.draw(image,sectionedQuad(image,index),-64,-87)
            if section and section.breaking and progress<=.22 then
                local hitX=(section.impactX-target.x)/target.scale
                local hitY=(section.impactY-target.y)/target.scale
                local crackLength=math.max(1,progress/.22*18)
                love.graphics.setColor(.29,.23,.18,alpha)
                love.graphics.setLineWidth(1.25)
                for branch=0,3 do
                    local angle=(index*2.399+branch*math.pi/2)
                    local length=crackLength*(branch%2==0 and 1 or .66)
                    love.graphics.line(hitX,hitY,hitX+math.cos(angle)*length,hitY+math.sin(angle)*length)
                end
            elseif not section and index<=12 then
                local ringIndex=math.floor((index-1)/4)+1
                local sector=(index-1)%4
                local angle=-math.pi+sector*math.pi/2+math.pi/4
                local ring=SECTION_RINGS[ringIndex]
                local x,y=superellipsePoint((ring.outer[1]+ring.inner[1])/2,
                    (ring.outer[2]+ring.inner[2])/2,angle)
                local labelWidth=font:getWidth(ring.score)
                love.graphics.setColor(.96,.93,.85,alpha)
                love.graphics.print(ring.score,x-labelWidth/2,y-font:getHeight()/2)
            end
            love.graphics.pop()
        end
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
end

local shoot

local function resetRound(session,data,catalog)
    session.phase="play"; session.clock=0; session.score=0; session.shots=0; session.hits=0
    session.targets={}; session.dirtImpacts={}; session.spawnIndex=0; session.nextSpawn=.1; session.time=session.stageLength or Range.roundSeconds
    session.sectionsHit=0
    session.message=nil; session.completed=false; session.result=nil
    session.aimMode=session.aimMode or "hip"; session.needsReload=false; session.reloadPulse=0
    session.spot.preferences={motion=session.motion,material=session.material,targetPattern=session.targetPattern,
        stageLength=session.stageLength,distance=validDistance(session.distance)}
    loadWeapon(session,data,catalog)
end

function Range.update(session,dt,data,catalog)
    if not session or session.phase~="play" then return nil end
    dt=math.min(.08,math.max(0,dt or 0))
    session.clock=session.clock+dt; session.time=math.max(0,session.time-dt)
    updateWeaponViewSequence(session,dt)
    WeaponActions.update(session,dt)
    session.cooldown=math.max(0,(session.cooldown or 0)-dt)
    if (session.reloadTimer or 0)>0 then
        local tubeReload=session.tubeReloadTotalRounds~=nil
        if tubeReload then
            local inserted=WeaponActions.consumeTubeRounds(session)
            local combat=session.ammoType and {ammo=session.ammoType} or {}
            local target=math.min(session.capacity,availableAmmo(data or {},combat))
            for _=1,inserted do
                if session.loaded<target then session.loaded=session.loaded+1 end
            end
        end
        session.reloadTimer=math.max(0,session.reloadTimer-dt)
        if session.reloadTimer==0 then
            local combat=session.ammoType and {ammo=session.ammoType} or {}
            if not tubeReload then
                session.loaded=math.min(session.capacity,availableAmmo(data or {},combat))
            end
            session.needsReload=session.loaded<=0 and combat.ammo~=nil
            session.message=session.needsReload and "NO MORE AMMO" or "RELOADED"
            WeaponActions.finish(session)
        end
    end
    session.reloadPulse=(session.reloadPulse or 0)+dt
    session.dirtImpacts=session.dirtImpacts or {}
    for index=#session.dirtImpacts,1,-1 do
        local impact=session.dirtImpacts[index]
        impact.age=impact.age+dt
        if impact.age>=impact.duration then table.remove(session.dirtImpacts,index) end
    end
    session.nextSpawn=session.nextSpawn-dt
    if session.nextSpawn<=0 and #session.targets<(session.material=="sectioned" and 1 or 4) then
        spawnTarget(session)
        session.nextSpawn=.8+(session.spawnIndex%3)*.18
    end
    for index=#session.targets,1,-1 do
        local target=session.targets[index]
        target.age=target.age+dt; target.life=target.life-dt
        if target.breaking then target.breaking=target.breaking+dt end
        if target.sections then
            local allBroken=true
            for sectionIndex=1,13 do
                local section=target.sections[sectionIndex]
                if section and section.breaking then
                    section.breakElapsed=section.breakElapsed+dt
                    if section.breakElapsed>=.5 then section.breaking=false; section.broken=true end
                end
                if not section or not section.broken then allBroken=false end
            end
            if allBroken and not target.clearing then
                target.clearing=true
                target.life=.55
            end
        end
        target.x=target.x+target.velocity*dt
        if target.x<145 or target.x>830 then target.velocity=-target.velocity end
        if target.life<=0 then table.remove(session.targets,index) end
    end
    local autoOutcome
    if session.fireHeld and session.fireMode=="auto" and data and catalog and session.cooldown<=0 and session.time>0 then
        autoOutcome=shoot(session,data,catalog,session.aimX,session.aimY)
    end
    if session.time<=0 and not session.completed then session.completed=true; return "complete" end
    if autoOutcome=="shot" then return "shot" end
end

function Range.sway(session,catalog)
    -- The reticle and muzzle remain fixed to authored weapon art. Shot and
    -- reload motion is shown by swapping sprite frames, never by code offsets.
    return 0,0
end

shoot=function(session,data,catalog,x,y)
    local issue=weaponIssue(data,catalog,session.itemId or session.weapon)
    if issue then session.message=issue; return "dry" end
    local combat=catalog.weaponCombat[session.weapon]
    if FirstPersonWeaponManifest.fireModeValid(session.weapon,session.fireMode) then
        if session.fireMode=="safe" then session.message="SAFE"; return "safe" end
        if session.reloadTimer>0 or session.cooldown>0 then return "busy" end
    end
    if session.loaded<=0 then
        if not combat.ammo then
            session.needsReload=false
            session.message=session.weaponViewSequence and "PROJECTILE RETURNING" or "PROJECTILE NOT READY"
        else
            session.needsReload=true; session.message="RELOAD REQUIRED"
        end
        return "dry"
    end
    if combat.ammo then
        local reserve=availableAmmo(data,combat)
        if reserve<=0 then session.loaded=0; session.needsReload=true; session.message="OUT OF "..string.upper(combat.ammo); return "dry" end
        data.ammo[combat.ammo]=reserve-1
    end
    session.loaded=session.loaded-1; session.shots=session.shots+1
    session.needsReload=session.loaded<=0 and combat.ammo~=nil
    startWeaponViewSequence(session)
    if FirstPersonWeaponManifest.fireModeValid(session.weapon,session.fireMode) then
        session.cooldown=FirstPersonWeaponManifest.fireCooldownFor(session.weapon,session.fireMode)
        WeaponActions.beginFire(session)
    end
    local swayX,swayY=Range.sway(session,catalog)
    local shotX,shotY=(x or session.aimX)+swayX,(y or session.aimY)+swayY
    shotX,shotY=WorldView.toWorld(shotX,shotY)
    local magnification=Range.magnification(session)
    if magnification>1 then
        shotX=MONOCULAR_CENTER.x+(shotX-MONOCULAR_CENTER.x)/magnification
        shotY=MONOCULAR_CENTER.y+(shotY-MONOCULAR_CENTER.y)/magnification
    end
    local pellets=combat.ammo=="12-gauge" and shotgunPellets(session.weapon) or {{x=0,y=0}}
    local struck={}
    local struckSections={}
    local missedPellets={}
    for pelletIndex,pellet in ipairs(pellets) do
        local pelletX,pelletY=shotX+pellet.x,shotY+pellet.y
        local best,bestDistance
        local bestSection
        for _,target in ipairs(session.targets) do
            local dx,dy=pelletX-target.x,pelletY-target.y
            local distance=math.sqrt(dx*dx+dy*dy)
            if target.material=="sectioned" then
                local sectionIndex=sectionAtPoint(target,pelletX,pelletY)
                local section=sectionIndex and target.sections[sectionIndex]
                if sectionIndex and not (section and (section.hit or section.broken))
                    and (not bestDistance or distance<bestDistance) then
                    best,bestDistance,bestSection=target,distance,sectionIndex
                end
            elseif distance<=target.radius and (not bestDistance or distance<bestDistance) then
                best,bestDistance=target,distance
            end
        end
        if best then
            if best.material=="sectioned" then
                local sections=struckSections[best] or {}
                struckSections[best]=sections
                if not sections[bestSection] then
                    sections[bestSection]={distance=bestDistance,x=pelletX,y=pelletY}
                end
            else
                local previous=struck[best]
                if not previous or bestDistance<previous then struck[best]=bestDistance end
                if best.material=="clay" then
                    if not best.hit then best.breaking=.001; best.life=math.min(best.life,.48) end
                else
                    best.impacts[#best.impacts+1]={offsetX=pelletX-best.x,offsetY=pelletY-best.y,
                        variant=(session.shots+pelletIndex-2)%4+1,material=best.material}
                end
            end
        else
            missedPellets[#missedPellets+1]={x=pelletX,y=pelletY}
        end
    end
    local hitTarget
    for target,distance in pairs(struck) do
        hitTarget=hitTarget or target
        if not target.hit then
            target.hit=true; session.hits=session.hits+1
            local precision=math.max(.25,1-distance/(target.radius+1))
            session.score=session.score+math.floor(target.points*precision+25)
        end
    end
    for target,sections in pairs(struckSections) do
        hitTarget=hitTarget or target
        local newlyHit=0
        for index,impact in pairs(sections) do
            local section=target.sections[index] or {}
            target.sections[index]=section
            if not section.hit and not section.broken then
                section.hit=true; section.breaking=true; section.breakElapsed=0
                section.impactX=impact.x; section.impactY=impact.y
                newlyHit=newlyHit+1
                local precision=math.max(.25,1-impact.distance/(target.radius+1))
                session.score=session.score+math.floor(target.points*precision+25)
            end
        end
        if newlyHit>0 then session.hits=session.hits+1; session.sectionsHit=session.sectionsHit+newlyHit end
    end
    if #missedPellets>0 then
        local miss=missedPellets[math.random(1,#missedPellets)]
        local rangeScale=distanceScale(session.distance)
        session.dirtImpacts=session.dirtImpacts or {}
        session.dirtImpacts[#session.dirtImpacts+1]={x=miss.x,y=miss.y,variant=5,
            age=0,duration=.85,size=72*rangeScale,lift=19*rangeScale}
    end
    if hitTarget then
        session.message=session.needsReload and "RELOAD REQUIRED" or "HIT"; return "shot"
    end
    session.message=session.needsReload and "RELOAD REQUIRED" or "MISS"; return "shot"
end

function Range.reload(session,data,catalog)
    if session.phase~="play" then return false end
    if weaponIssue(data,catalog,session.itemId or session.weapon) then return false end
    local combat=catalog.weaponCombat[session.weapon]
    if not combat.ammo then
        session.needsReload=false
        session.message=session.weaponViewSequence and "PROJECTILE RETURNING" or "READY"
        return false
    end
    if session.reloadTimer>0 then return false end
    local amount=math.min(session.capacity,availableAmmo(data,combat))
    if amount<=session.loaded then session.needsReload=session.loaded<=0 and combat.ammo~=nil; session.message=combat.ammo and "NO MORE AMMO" or "READY"; return false end
    clearWeaponViewSequence(session)
    if FirstPersonWeaponManifest.reloadProfileFor(session.weapon) then
        local profile=FirstPersonWeaponManifest.reloadProfileFor(session.weapon)
        local rounds
        if profile.style=="tubeLever" then rounds=amount end
        if profile.style=="pumpTube" then rounds=math.max(1,amount-session.loaded) end
        session.reloadTimer=WeaponActions.reloadDuration(session,rounds)
        session.needsReload=false
        session.message="RELOADING"
        WeaponActions.beginReload(session,rounds)
        if rounds and profile.style=="tubeLever" then session.loaded=0 end
    else
        session.loaded=amount; session.needsReload=false; session.message="RELOADED"
    end
    return true
end

function Range.cycleFireMode(session,direction)
    if not session then return nil end
    local modes=FirstPersonWeaponManifest.fireModesFor(session.weapon)
    if #modes<2 then return nil end
    local selected=1
    for index,mode in ipairs(modes) do if mode==session.fireMode then selected=index; break end end
    selected=((selected-1+(direction or 1))%#modes)+1
    session.fireMode=modes[selected]
    session.fireHeld=false
    session.message="FIRE MODE: "..string.upper(session.fireMode)
    return session.fireMode
end

function Range.mousereleased(session,button)
    if not session then return false end
    if button==nil or button==1 or button==4 or button==5 then session.fireHeld=false end
    return true
end

function Range.keyreleased(session,key)
    if not session then return false end
    if key=="space" then session.fireHeld=false; return true end
    return false
end

function Range.select(session,data,catalog,direction)
    if session.phase~="lobby" and session.phase~="results" then return false end
    if Items.enabled(data) then
        local current=session.itemId
        session.weapons=Range.ownedWeapons(data,catalog)
        if #session.weapons==0 then session.message="WEAPON NO LONGER AVAILABLE"; return false end
        session.selected=0
        for index,id in ipairs(session.weapons) do if id==current then session.selected=index; break end end
    end
    session.selected=((session.selected-1+(direction or 1))%#session.weapons)+1
    if not loadWeapon(session,data,catalog) then return false end
    session.message=nil
    return true
end

local function cycle(list,value,direction)
    local selected=1
    for index,entry in ipairs(list) do if entry==value then selected=index; break end end
    return list[((selected-1+(direction or 1))%#list)+1]
end

lobbyRows={
    {kind="weapon",label="PRACTICE WEAPON",y=205},
    {kind="motion",label="TARGET MOTION",y=255},
    {kind="material",label="TARGET TYPE",y=305},
    {kind="pattern",label="TARGET STYLE",y=355},
    {kind="distance",label="TARGET DISTANCE",y=405},
    {kind="length",label="STAGE LENGTH",y=455},
}

function Range.changeSetup(session,data,catalog,kind,direction)
    if session.phase~="lobby" and session.phase~="results" then return false end
    if kind=="weapon" then return Range.select(session,data,catalog,direction) end
    if kind=="motion" then session.motion=cycle(Range.motionModes,session.motion,direction)
    elseif kind=="material" then session.material=cycle(Range.targetTypes,session.material,direction)
    elseif kind=="pattern" then session.targetPattern=cycle(Range.targetPatterns,session.targetPattern,direction)
    elseif kind=="distance" then session.distance=cycle(Range.targetDistances,validDistance(session.distance),direction)
    elseif kind=="length" then session.stageLength=cycle(Range.stageLengths,session.stageLength,direction)
    else return false end
    session.spot.preferences={motion=session.motion,material=session.material,targetPattern=session.targetPattern,
        stageLength=session.stageLength,distance=validDistance(session.distance)}; session.message=nil
    return true
end

function Range.ammoOffer(session,catalog)
    if not session or not catalog then return nil end
    local combat=catalog.weaponCombat[session.weapon] or {}
    if not combat.ammo then return nil end
    local bundle=Range.ammoBundles[combat.ammo] or Range.ammoBundles.default
    return {ammo=combat.ammo,amount=bundle.amount,cost=bundle.cost}
end

function Range.buyAmmo(session,data,catalog)
    if not session or session.phase~="lobby" then return false end
    local offer=Range.ammoOffer(session,catalog)
    if not offer then session.message="THIS WEAPON DOES NOT NEED AMMO"; return false end
    local scrap=math.max(0,math.floor(tonumber(data.scrap) or 0))
    if scrap<offer.cost then session.message="NEED "..offer.cost.." SCRAP FOR AMMO"; return false end
    data.ammo=type(data.ammo)=="table" and data.ammo or {}
    data.scrap=scrap-offer.cost
    data.ammo[offer.ammo]=availableAmmo(data,{ammo=offer.ammo})+offer.amount
    session.message="BOUGHT "..offer.amount.." "..string.upper(offer.ammo).." FOR "..offer.cost.." SCRAP"
    return true,offer
end

function Range.toggleAim(session)
    if not session or session.phase~="play" then return false end
    session.aimMode=session.aimMode=="sights" and "hip" or "sights"
    MobileAim.refresh(session,session.weapon,session.aimMode)
    return true
end

function Range.setAim(session,aiming)
    if not session or session.phase~="play" then return false end
    session.aimMode=aiming and "sights" or "hip"
    MobileAim.refresh(session,session.weapon,session.aimMode)
    return true
end

function Range.toggleMonocular(session)
    if not session or session.phase~="play" or not session.hasMonocular then return false end
    session.monocularActive=not session.monocularActive
    return true
end

function Range.setWeaponViewState(session,state)
    if not session then return false end
    clearWeaponViewSequence(session)
    session.weaponViewState=type(state)=="string" and state~="" and state or nil
    return true
end

function Range.returnToSetup(session)
    if not session or session.phase~="play" then return false end
    clearWeaponViewSequence(session)
    session.phase="lobby"; session.targets={}; session.needsReload=false
    session.time=session.stageLength or Range.roundSeconds
    session.message="COURSE RESET - ADJUST YOUR SETUP"
    return true
end

function Range.weaponViewPlacement(session)
    if session and (session.weaponViewPlacement=="hip" or session.weaponViewPlacement=="sights") then
        return session.weaponViewPlacement
    end
    return session and session.aimMode=="sights" and "sights" or "hip"
end

function Range.mousemoved(session,x,y,touch)
    if not session or session.phase~="play" then return end
    if touch then
        MobileAim.set(session,x,y,session.weapon,session.aimMode,960,720,{left=30,top=55,right=930,bottom=625})
        return
    end
    session.touchAim=nil
    session.aimX=math.max(30,math.min(930,x)); session.aimY=math.max(55,math.min(625,y))
end

function Range.mousepressed(session,x,y,data,catalog,button)
    if not session then return nil end
    button=button or 1
    if session.phase=="play" and session.hasMonocular and (button==1 or button==4 or button==5)
        and hit(MONOCULAR_BUTTON,x,y) then
        Range.toggleMonocular(session); return "monocular"
    end
    if button==2 and session.phase=="play" then Range.setAim(session,true); return "aim" end
    if session.phase=="lobby" then
        for index,row in ipairs(lobbyRows) do
            if hit({x=218,y=row.y-21,w=62,h=46},x,y) then session.menuRow=index; Range.changeSetup(session,data,catalog,row.kind,-1); return "select" end
            if hit({x=680,y=row.y-21,w=62,h=46},x,y) then session.menuRow=index; Range.changeSetup(session,data,catalog,row.kind,1); return "select" end
        end
        if hit({x=185,y=542,w=290,h=54},x,y) then
            local purchased=Range.buyAmmo(session,data,catalog); return purchased and "purchase" or "dry"
        end
        if hit({x=500,y=542,w=275,h=54},x,y) then
            if weaponReady(data,catalog,session.itemId or session.weapon) then resetRound(session,data,catalog); return "start" end
            session.message=weaponIssue(data,catalog,session.itemId or session.weapon); return "dry"
        end
        if hit({x=800,y=654,w=130,h=42},x,y) then return "close" end
    elseif session.phase=="play" then
        if hit(DESKTOP_MODE_BUTTON,x,y) or hit(MOBILE_MODE_BUTTON,x,y) then return Range.cycleFireMode(session) and "mode" or "dry" end
        if hit({x=18,y=654,w=126,h=42},x,y) then return Range.reload(session,data,catalog) and "reload" or "dry" end
        if hit({x=154,y=654,w=126,h=42},x,y) then Range.toggleAim(session); return "aim" end
        if hit({x=680,y=654,w=126,h=42},x,y) then Range.returnToSetup(session); return "setup" end
        if hit({x=816,y=654,w=126,h=42},x,y) then return "close" end
        if (button==4 or button==5) and hit(MOBILE_FIRE_BUTTON,x,y) then
            session.fireHeld=true
            return shoot(session,data,catalog,session.aimX,session.aimY)
        end
        if button==5 then session.fireHeld=true; return shoot(session,data,catalog,session.aimX,session.aimY) end
        Range.mousemoved(session,x,y,button==4)
        if button==4 then return "aimPointer" end
        session.fireHeld=true
        return shoot(session,data,catalog,session.aimX,session.aimY)
    elseif session.phase=="results" then
        if hit({x=238,y=548,w=150,h=58},x,y) then
            if weaponReady(data,catalog,session.itemId or session.weapon) then resetRound(session,data,catalog); return "start" end
            session.message=weaponIssue(data,catalog,session.itemId or session.weapon); return "dry"
        end
        if hit({x=405,y=548,w=150,h=58},x,y) then session.phase="lobby"; session.message=nil; return "setup" end
        if hit({x=572,y=548,w=150,h=58},x,y) then return "close" end
    end
end

function Range.keypressed(session,key,data,catalog)
    if key=="escape" or key=="e" then return "close" end
    if session.phase=="lobby" then
        if key=="up" or key=="w" then session.menuRow=((session.menuRow-2)%#lobbyRows)+1; return "select" end
        if key=="down" or key=="s" then session.menuRow=(session.menuRow%#lobbyRows)+1; return "select" end
        if key=="left" or key=="a" then Range.changeSetup(session,data,catalog,lobbyRows[session.menuRow].kind,-1); return "select" end
        if key=="right" or key=="d" then Range.changeSetup(session,data,catalog,lobbyRows[session.menuRow].kind,1); return "select" end
        if key=="b" then local purchased=Range.buyAmmo(session,data,catalog); return purchased and "purchase" or "dry" end
        if key=="return" or key=="space" then
            if weaponReady(data,catalog,session.itemId or session.weapon) then resetRound(session,data,catalog); return "start" end
            session.message=weaponIssue(data,catalog,session.itemId or session.weapon); return "dry"
        end
    elseif session.phase=="play" then
        if key=="o" then return Range.toggleMonocular(session) and "monocular" or nil end
        if key=="r" then return Range.reload(session,data,catalog) and "reload" or "dry" end
        if key=="v" then return Range.cycleFireMode(session) and "mode" or "dry" end
        if key=="tab" then Range.returnToSetup(session); return "setup" end
        if key=="lshift" or key=="rshift" then Range.toggleAim(session); return "aim" end
        if key=="space" then session.fireHeld=true; return shoot(session,data,catalog,session.aimX,session.aimY) end
    elseif session.phase=="results" and (key=="return" or key=="space") then session.phase="lobby"; return "setup" end
end

function Range.sound(session,catalog)
    local family=catalog.weaponFamily(session.weapon)
    if family=="bows" then return "bow" end
    if family=="slingshots" then return "bow" end
    return "gunshot"
end

function Range.soundProfile(session,catalog)
    return session and SoundProfiles.forWeapon(session.weapon,catalog) or nil
end

function Range.complete(session,data,spot,stopHelp)
    if not session or session.phase~="play" then return session and session.result end
    local accuracy=session.shots>0 and session.hits/session.shots or 0
    local rank=session.score>=1150 and accuracy>=.55 and "SHARPSHOOTER" or session.score>=650 and "MARKSMOUSE" or session.score>=250 and "TRAIL HAND" or "BEGINNER"
    local previous=math.floor(tonumber(spot.highScores[session.weapon]) or 0)
    spot.highScores[session.weapon]=math.max(previous,session.score)
    local earnedTier=session.score>=1150 and accuracy>=.55 and 3 or session.score>=550 and 2 or session.hits>0 and 1 or 0
    local previousTier=tonumber(spot.rewardTier)
    if previousTier==nil then previousTier=spot.rewarded==true and 3 or 0 end
    previousTier=math.max(0,math.min(3,math.floor(previousTier)))
    local rewardTier=math.max(previousTier,earnedTier)
    local gained=rewardTier-previousTier
    spot.rewardTier=rewardTier; spot.rewarded=rewardTier>0
    if gained>0 then stopHelp.add(data,gained,"shooting-range",session.npc,data.location) end
    session.result={score=session.score,accuracy=accuracy,rank=rank,gained=gained,rewardTier=rewardTier,earnedRewardTier=earnedTier,
        highScore=spot.highScores[session.weapon],newBest=session.score>previous}
    session.phase="results"; session.message=nil
    return session.result
end

local targetQuadCache=setmetatable({},{__mode="k"})
local impactQuadCache=setmetatable({},{__mode="k"})
local dirtImpactQuadCache=setmetatable({},{__mode="k"})
local function atlasQuads(image,columns,rows,cache)
    if not image then return nil end
    if cache[image] then return cache[image] end
    local width,height=image:getDimensions(); local cellW=math.floor(width/columns); local cellH=math.floor(height/rows)
    local quads={cellW=cellW,cellH=cellH}
    for index=1,columns*rows do
        local column,row=(index-1)%columns,math.floor((index-1)/columns)
        quads[index]=love.graphics.newQuad(column*cellW,row*cellH,cellW,cellH,width,height)
    end
    cache[image]=quads; return quads
end

local function drawButton(label,rect,enabled)
    love.graphics.setColor(enabled==false and .16 or .28,enabled==false and .15 or .20,enabled==false and .14 or .10,.94)
    love.graphics.rectangle("fill",rect.x,rect.y,rect.w,rect.h,7,7)
    love.graphics.setColor(enabled==false and .45 or .93,enabled==false and .43 or .75,enabled==false and .40 or .30,1)
    love.graphics.rectangle("line",rect.x,rect.y,rect.w,rect.h,7,7)
    text(label,rect.x+8,rect.y+6,rect.w-16,rect.h-12,1,rect.h<50 and .74 or .82)
end

local function drawWeapon(ui,name)
    local atlas=ui.atlasItems and ui.atlasItems[name]
    local image=ui.propImages and ui.propImages[name]
    love.graphics.setColor(1,1,1,1)
    if atlas then
        local scale=math.min(230/atlas.w,150/atlas.h)
        love.graphics.draw(atlas.image,atlas.quad,930,650,-.10,scale,scale,atlas.w,atlas.h)
    elseif image then
        local width,height=image:getDimensions(); local scale=math.min(230/width,150/height)
        love.graphics.draw(image,930,650,-.10,scale,scale,width,height)
    end
end

local function drawFirstPersonWeapon(assets,ui,session,aimX,aimY,swayX,swayY,placement)
    local views=assets and assets.weaponViews and assets.weaponViews[session.weapon]
    local state=session.weaponViewState or session.aimMode
    local image
    if assets and assets.weaponViews and type(assets.weaponViews.get)=="function" then
        views=assets.weaponViews
        image=views:get(session.weapon,state)
        if not image and state~=session.aimMode then image=views:get(session.weapon,session.aimMode) end
    else
        image=views and (views[state] or views[session.aimMode])
    end
    if not image then drawWeapon(ui,session.weapon); return false end
    local width,height=image:getDimensions()
    local actionImage,actionQuad,actionWidth,actionHeight,adsFrame
    if placement=="sights" and session.weaponAction~="reload"
        and FirstPersonWeaponManifest.adsActionAtlasFor(session.weapon)
        and views and type(views.adsActionFrame)=="function" then
        adsFrame=WeaponActions.adsFrameIndex(session)
        actionImage,actionQuad,actionWidth,actionHeight=views:adsActionFrame(session.weapon,adsFrame)
    elseif FirstPersonWeaponManifest.actionAtlasFor(session.weapon)
        and (placement~="sights" or session.weaponAction=="reload")
        and views and type(views.actionFrame)=="function" then
        actionImage,actionQuad,actionWidth,actionHeight=views:actionFrame(session.weapon,WeaponActions.frameIndex(session))
    end
    love.graphics.setColor(1,1,1,1)
    if actionImage then
        if placement=="sights" and session.weaponAction~="reload" then
            local place=MobileAim.adsActionPlacement(session.weapon,aimX,aimY,960,720,
                actionWidth,actionHeight,560,650,adsFrame)
            if place then love.graphics.draw(actionImage,actionQuad,place.x,place.y,0,place.scale,place.scale) end
        else
            local place=MobileAim.placement(session.weapon,"hip","hip",aimX,aimY,960,720)
            local actionScale=place.height/actionHeight
            love.graphics.draw(actionImage,actionQuad,
                place.gripX-place.gripAnchor.x*actionWidth*actionScale,
                place.gripY-place.gripAnchor.y*actionHeight*actionScale,0,actionScale,actionScale)
        end
    elseif placement=="sights" then
        local anchor=DEFAULT_SIGHT_ANCHOR
        if views and type(views.anchor)=="function" then anchor=select(1,views:anchor(session.weapon)) end
        local scale=math.min(560/width,650/height)
        love.graphics.draw(image,aimX-anchor.x*width*scale,aimY-anchor.y*height*scale,0,scale,scale)
    else
        local place=MobileAim.placement(session.weapon,state,session.aimMode,aimX,aimY,960,720)
        love.graphics.draw(image,place.x,place.y,0,place.width/width,place.height/height)
    end
    return true
end


function Range.releaseWeaponViews(assets)
    local views=assets and assets.weaponViews
    if views and type(views.release)=="function" then views:release(); return true end
    return false
end

function Range.draw(session,data,assets,ui,catalog,mobile)
    WorldView.begin()
    local magnification=Range.magnification(session)
    if magnification>1 then
        love.graphics.push()
        love.graphics.translate(MONOCULAR_CENTER.x,MONOCULAR_CENTER.y)
        love.graphics.scale(magnification)
        love.graphics.translate(-MONOCULAR_CENTER.x,-MONOCULAR_CENTER.y)
    end
    local background=assets and session.distance>=150 and assets.longRangeBackground or assets and assets.background
    if background then
        love.graphics.setColor(1,1,1); love.graphics.draw(background,0,0,0,960/background:getWidth(),720/background:getHeight())
    else love.graphics.setColor(.18,.12,.07); love.graphics.rectangle("fill",0,0,960,720) end
    love.graphics.setColor(0,0,0,.18); love.graphics.rectangle("fill",0,0,960,720)

    if session.phase=="play" then
        local combat=catalog.weaponCombat[session.weapon] or {}
        local targetImage=assets and assets.targets; local targetQuads=atlasQuads(targetImage,4,3,targetQuadCache)
        local impactImage=assets and assets.impacts; local impactQuads=atlasQuads(impactImage,4,2,impactQuadCache)
        local dirtImage=assets and assets.dirtImpacts; local dirtQuads=atlasQuads(dirtImage,5,1,dirtImpactQuadCache)
        for _,impact in ipairs(session.dirtImpacts or {}) do
            local quad=dirtQuads and dirtQuads[impact.variant]
            if dirtImage and quad then
                local progress=math.max(0,math.min(1,impact.age/impact.duration))
                local expansion=math.min(1,progress*3.2)
                local scale=impact.size/dirtQuads.cellH*(.85+.60*expansion)
                local rise=impact.lift*progress
                local alpha=(1-progress)^1.4
                love.graphics.setColor(1,1,1,alpha)
                love.graphics.draw(dirtImage,quad,impact.x,impact.y-rise,0,scale,scale,
                    dirtQuads.cellW/2,dirtQuads.cellH-12)
            end
        end
        for _,target in ipairs(session.targets) do
            local sprite=target.sprite
            if target.material=="clay" and target.breaking then sprite=target.breaking<.13 and 11 or 12 end
            if target.material=="sectioned" then
                drawSectionedTarget(target,assets and assets.sectionedTarget,assets and assets.sectionedFrame)
            elseif targetImage and targetQuads and targetQuads[sprite] then
                local reveal=session.targetPattern=="pop-up" and math.max(0,math.min(1,target.age/.15,target.life/.15)) or 1
                love.graphics.setColor(1,1,1,(target.hit and .88 or 1)*reveal)
                love.graphics.draw(targetImage,targetQuads[sprite],target.x,target.y+(1-reveal)*18,0,target.scale,target.scale,targetQuads.cellW/2,targetQuads.cellH*.46)
            end
            for _,impact in ipairs(target.impacts) do
                local index=impact.variant+(impact.material=="steel" and 4 or 0)
                if impactImage and impactQuads and impactQuads[index] then
                    local scale=16/math.max(impactQuads.cellW,impactQuads.cellH)
                    love.graphics.setColor(1,1,1,1)
                    love.graphics.draw(impactImage,impactQuads[index],target.x+impact.offsetX,target.y+impact.offsetY,0,scale,scale,impactQuads.cellW/2,impactQuads.cellH/2)
                end
            end
        end
        if magnification>1 then love.graphics.pop() end
        WorldView.finish()
        love.graphics.setColor(.08,.055,.035,.91); love.graphics.rectangle("fill",14,12,210,82,8,8); love.graphics.rectangle("fill",736,12,210,82,8,8)
        love.graphics.setColor(1,.88,.58); text(string.format("TIME  %02d",math.ceil(session.time)),28,18,180,28,1.15,.92,"left",true)
        text("DISTANCE  "..session.distance.." M",355,18,250,27,.92,.80,"center",true)
        if session.hasMonocular then
            local label="MONO 1.5X "..(session.monocularActive and "ON" or "OFF")
            drawButton(label,MONOCULAR_BUTTON,true)
        end
        text("AMMO  "..(combat.ammo and tostring(session.loaded) or "--"),28,56,180,24,.84,.74,"left",true)
        text("SCORE\n"..session.score,750,16,180,48,1,.88)
        if session.material=="sectioned" then
            local remaining=13
            for _,target in ipairs(session.targets) do
                if target.sections then
                    remaining=0
                    for index=1,13 do
                        local section=target.sections[index]
                        if not (section and section.hit) then remaining=remaining+1 end
                    end
                    break
                end
            end
            love.graphics.setColor(1,.88,.58)
            text("PANELS LEFT  "..remaining,745,67,192,19,.74,.68,"center",true)
        end
        local sx,sy=Range.sway(session,catalog); local x,y=session.aimX+sx,session.aimY+sy
        local placement=Range.weaponViewPlacement(session)
        drawFirstPersonWeapon(assets,ui,session,x,y,sx,sy,placement)
        if placement~="sights" then
            love.graphics.setColor(1,.25,.16,.95); love.graphics.circle("line",x,y,13); love.graphics.line(x-20,y,x-5,y); love.graphics.line(x+5,y,x+20,y); love.graphics.line(x,y-20,x,y-5); love.graphics.line(x,y+5,x,y+20)
        end
        if session.needsReload then
            local pulse=.72+.28*math.abs(math.sin((session.reloadPulse or 0)*5))
            love.graphics.setColor(.32,.035,.02,.94); love.graphics.rectangle("fill",310,108,340,58,8,8)
            love.graphics.setColor(1,.28,.12,pulse); love.graphics.rectangle("line",310,108,340,58,8,8)
            text(mobile and "RELOAD REQUIRED\nTAP RELOAD" or "RELOAD REQUIRED\nPRESS R",320,113,320,48,1.08,.92)
        elseif session.message then love.graphics.setColor(1,.45,.25); text(session.message,320,108,320,60,1,.82) end
        local reloadLabel=combat.ammo and (session.needsReload and "RELOAD!  [R]" or "RELOAD  [R]")
            or (session.weaponViewSequence and "RETURNING" or "REUSABLE")
        if mobile then reloadLabel=combat.ammo and (session.needsReload and "RELOAD!" or "RELOAD") or reloadLabel end
        drawButton(reloadLabel,{x=18,y=654,w=126,h=42},combat.ammo~=nil)
        drawButton(session.aimMode=="sights" and "AIMING" or (mobile and "AIM" or "AIM  [RMB]"),{x=154,y=654,w=126,h=42},true)
        drawButton(mobile and "SETUP" or "SETUP  [TAB]",{x=680,y=654,w=126,h=42},true)
        drawButton(mobile and "LEAVE" or "LEAVE  [E]",{x=816,y=654,w=126,h=42},true)
        love.graphics.setColor(.045,.03,.02,.93); love.graphics.rectangle("fill",286,mobile and 592 or 648,388,mobile and 128 or 62,7,7)
        local fireModes=FirstPersonWeaponManifest.fireModesFor(session.weapon)
        if #fireModes>1 then
            drawButton("MODE: "..string.upper(session.fireMode or "single"),
                mobile and MOBILE_MODE_BUTTON or DESKTOP_MODE_BUTTON,true)
        end
        if mobile then
            love.graphics.setColor(1,.88,.58)
            text(title(session.weapon),292,596,376,26,.90,.78,"center",true)
            text("HOLD THE GRIP • SECOND TOUCH / FIRE",292,624,376,24,.86,.78)
            drawButton("FIRE",MOBILE_FIRE_BUTTON,true)
            love.graphics.setColor(1,.88,.58)
            text(string.upper(session.motion).." "..string.upper(session.material).." | "
                ..string.upper(session.targetPattern).." | "..session.distance.." M | "..session.stageLength.." SEC",292,698,376,20,.78,.72,"center",true)
        else
            love.graphics.setColor(1,.88,.58); text(title(session.weapon).."  |  "..string.upper(session.motion).." "..string.upper(session.material)
                .."  |  "..session.distance.." M  |  "..string.upper(session.targetPattern).."  |  "..session.stageLength.." SEC",292,650,244,56,.82,.72)
        end
        return
    end

    WorldView.finish()
    love.graphics.setColor(.055,.04,.03,.91); love.graphics.rectangle("fill",154,92,652,544,12,12)
    love.graphics.setColor(.87,.65,.25); love.graphics.rectangle("line",154,92,652,544,12,12)
    if session.phase=="lobby" then
        love.graphics.setColor(1,.86,.58); text("COMMUNITY TARGET RANGE",180,118,600,33,1.35,1.1)
        love.graphics.setColor(.92,.86,.72); text("Live ammo is used. Buy more below.",220,155,520,23,.95,.85)
        local combat=catalog.weaponCombat[session.weapon]; local reserve=availableAmmo(data or {},combat); local durability=weaponDurability(data,session.itemId or session.weapon)
        for index,row in ipairs(lobbyRows) do
            local selected=session.menuRow==index
            love.graphics.setColor(selected and 1 or .74,selected and .77 or .70,selected and .28 or .62)
            text(row.label,300,row.y-14,165,28,.84,.76,"left",true)
            local value=row.kind=="weapon" and title(session.weapon) or row.kind=="motion" and title(session.motion)
                or row.kind=="material" and title(session.material) or row.kind=="pattern" and title(session.targetPattern)
                or row.kind=="distance" and (validDistance(session.distance).." Meters") or tostring(session.stageLength).." Seconds"
            love.graphics.setColor(1,.89,.68); text(value,468,row.y-14,192,28,row.kind=="weapon" and 1 or .96,.78,"center",true)
            drawButton("<",{x=218,y=row.y-21,w=62,h=46},true); drawButton(">",{x=680,y=row.y-21,w=62,h=46},true)
        end
        local offer=Range.ammoOffer(session,catalog)
        local scrap=math.max(0,math.floor(tonumber(data.scrap) or 0))
        love.graphics.setColor(.78,.77,.70)
        local status=durability<=0 and "BROKEN - REPAIR IN THE TRAIN WORKSHOP"
            or combat.ammo and (string.upper(combat.ammo).." AVAILABLE: "..reserve) or "REUSABLE PROJECTILE"
        text(status.."  |  SCRAP: "..scrap,185,489,590,25,.86,.75)
        text("SCORE MULTIPLIER x"..string.format("%.2f",Range.scoreMultiplier(session)),300,516,360,22,.86,.78)
        local ammoLabel=offer and ("BUY "..offer.amount.." "..string.upper(offer.ammo).."\n"..offer.cost.." SCRAP"..(mobile and "" or "  [B]")) or "NO AMMO NEEDED"
        drawButton(ammoLabel,{x=185,y=542,w=290,h=54},offer~=nil and scrap>=offer.cost)
        drawButton("START COURSE",{x=500,y=542,w=275,h=54},weaponReady(data,catalog,session.itemId or session.weapon))
        drawButton("LEAVE",{x=800,y=654,w=130,h=42},true)
    else
        local result=session.result
        love.graphics.setColor(1,.86,.58); text("ROUND COMPLETE",180,123,600,38,1.45,1.15)
        love.graphics.setColor(1,.72,.24); text(result.rank,220,200,520,45,1.45,1.15)
        love.graphics.setColor(.92,.86,.72)
        text("SCORE  "..result.score.."\nACCURACY  "..math.floor(result.accuracy*100+.5).."%\nHIGH SCORE  "..result.highScore,250,275,460,105,1.18,1)
        local reward=result.gained>0 and ("GOODWILL +"..result.gained)
            or result.rewardTier==0 and "HIT A TARGET TO EARN GOODWILL"
            or result.earnedRewardTier<result.rewardTier and ("GOODWILL BEST TIER +"..result.rewardTier)
            or "GOODWILL TIER ALREADY EARNED"
        love.graphics.setColor(.52,1,.57); text(reward,230,410,500,40,1,.85)
        love.graphics.setColor(.82,.78,.68); text(string.upper(session.motion).."  •  "..string.upper(session.material)
            .."  •  "..string.upper(session.targetPattern).."  •  "..validDistance(session.distance).." M  •  "..session.stageLength.." SEC  •  SCORE x"..string.format("%.2f",Range.scoreMultiplier(session)),220,464,520,36,.92,.78)
        drawButton("REPLAY",{x=238,y=548,w=150,h=58},weaponReady(data,catalog,session.itemId or session.weapon))
        drawButton("SETUP",{x=405,y=548,w=150,h=58},true)
        drawButton("DONE",{x=572,y=548,w=150,h=58},true)
    end
    if session.message then
        love.graphics.setColor(1,.42,.28)
        text(session.message,190,session.phase=="lobby" and 600 or 501,580,42,.92,.78)
    end
end

function Range.drawSpot(spot,image,clock)
    if not spot then return end
    local bob=math.sin((clock or 0)*1.5)*1.2
    if image then
        local scale=112/math.max(image:getWidth(),image:getHeight())
        love.graphics.setColor(1,1,1); love.graphics.draw(image,spot.x,spot.y+bob,0,scale,scale,image:getWidth()/2,image:getHeight())
    else
        love.graphics.setLineWidth(2)
        love.graphics.setColor(.24,.13,.065,1); love.graphics.line(spot.x,spot.y-2,spot.x,spot.y-30)
        love.graphics.setColor(.78,.07,.045,1)
        love.graphics.polygon("fill",spot.x+1,spot.y-29,spot.x+17,spot.y-24,spot.x+1,spot.y-18)
        love.graphics.setColor(.12,.065,.03,.42); love.graphics.ellipse("fill",spot.x,spot.y,7,3)
        love.graphics.setLineWidth(1)
    end
end

local TRAIL_FLAG_FRAMES={
    {column=0,row=0,anchorX=354,anchorY=552,height=353},
    {column=1,row=0,anchorX=295.5,anchorY=552,height=353},
    {column=1,row=1,anchorX=293,anchorY=456,height=357},
    {column=0,row=1,anchorX=322.5,anchorY=456,height=357},
}
local trailFlagQuadCache=setmetatable({},{__mode="k"})

local function animatedTrailFlagQuads(image)
    local cached=trailFlagQuadCache[image]
    if cached then return cached end
    local width,height=image:getDimensions()
    local cellWidth,cellHeight=width/2,height/2
    cached={cellWidth=cellWidth,cellHeight=cellHeight,quads={}}
    for index,frame in ipairs(TRAIL_FLAG_FRAMES) do
        cached.quads[index]=love.graphics.newQuad(frame.column*cellWidth,frame.row*cellHeight,cellWidth,cellHeight,width,height)
    end
    trailFlagQuadCache[image]=cached
    return cached
end

local function drawAnimatedTrailFlag(spot,image,clock)
    if not spot or not image then return end
    local frameIndex=math.floor((clock or 0)*5)%#TRAIL_FLAG_FRAMES+1
    local frame=TRAIL_FLAG_FRAMES[frameIndex]
    local cached=animatedTrailFlagQuads(image)
    local scale=34/frame.height
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,cached.quads[frameIndex],spot.x,spot.y,0,scale,scale,frame.anchorX,frame.anchorY)
end

Range.drawSpot=drawAnimatedTrailFlag

function Range.audit(catalog)
    local data={location=2,equipment={"trail-slingshot","hunting-bow","scrap-boomerang"},inventory={},ammo={rocks=3,arrows=0},weaponDurability={},scrap=5,goodwill=0,helpHistory={}}
    local spot={version=Range.version,x=760,y=565,rewarded=false,highScores={}}
    local session=assert(Range.new(data,spot,catalog,{npc="range-host.png"}))
    Range.changeSetup(session,data,catalog,"motion",1); Range.changeSetup(session,data,catalog,"material",1)
    Range.changeSetup(session,data,catalog,"pattern",1); Range.changeSetup(session,data,catalog,"length",1)
    local configured=session.motion=="moving" and session.material=="steel" and session.targetPattern=="pop-up" and session.stageLength==60
    local movingMultiplier=Range.scoreMultiplier(session)
    local offer=Range.ammoOffer(session,catalog); local purchased=Range.buyAmmo(session,data,catalog)
    resetRound(session,data,catalog); local stageTime=session.time
    local setupReturned=Range.returnToSetup(session); resetRound(session,data,catalog); Range.setAim(session,true)
    local adsX=select(1,Range.sway(session,catalog)); Range.setAim(session,false); local hipX=select(1,Range.sway(session,catalog))
    session.score=700; session.shots=5; session.hits=3
    local fakeHelp={add=function(save,amount) save.goodwill=(save.goodwill or 0)+amount; return amount end}
    local result=Range.complete(session,data,spot,fakeHelp)
    local second=Range.new(data,spot,catalog,{npc="range-host.png"}); resetRound(second,data,catalog); second.score=900; second.shots=5; second.hits=4
    local replay=Range.complete(second,data,spot,fakeHelp)
    local sparseWeapons=Range.ownedWeapons({equipment={[2]="trail-slingshot"},inventory={[4]="hunting-bow"}},catalog)
    local broken=Range.new({location=2,equipment={[2]="trail-slingshot"},inventory={},ammo={rocks=3},weaponDurability={["trail-slingshot"]=0}},
        {version=Range.version,x=760,y=565,rewarded=false,highScores={}},catalog)
    local zeroSpot={version=Range.version,x=760,y=565,rewarded=false,highScores={}}
    local zero=assert(Range.new(data,zeroSpot,catalog,{npc="range-host.png"})); resetRound(zero,data,catalog)
    local zeroResult=Range.complete(zero,data,zeroSpot,fakeHelp)
    local soundAudit=SoundProfiles.audit(catalog)
    local calibration=FirstPersonWeaponManifest.calibrationSummary()
    return {ready=Range.isHost(2) and not Range.isHost(3) and result.gained==2 and replay.gained==0 and data.goodwill==2 and spot.highScores["trail-slingshot"]==900
            and configured and math.abs(adsX)<=math.abs(hipX) and #soundAudit.missing==0 and #sparseWeapons==2 and broken==nil
            and zeroResult.gained==0 and zeroSpot.rewarded==false and movingMultiplier==1.30
            and offer and purchased and data.scrap==4 and data.ammo.rocks==19 and stageTime==60 and setupReturned
            and calibration.calibrated==45 and calibration.provisional==0 and calibration.withoutAnchor==1,
        hostCount=#Range.hostStops,ownedWeapons=#session.weapons,goodwill=result.gained,replayGoodwill=replay.gained,
        sparseOwned=#sparseWeapons,brokenRejected=broken==nil,zeroGoodwill=zeroResult.gained,
        movingMultiplier=movingMultiplier,targetPattern=session.targetPattern,stageLength=stageTime,ammoPurchased=purchased,scrapAfterAmmo=data.scrap,
        calibratedViews=calibration.calibrated,provisionalViews=calibration.provisional,
        modes=#Range.motionModes,targetTypes=#Range.targetTypes,assignedSounds=soundAudit.assigned,version=Range.version}
end

return Range
