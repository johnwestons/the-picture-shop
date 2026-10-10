-- Host-owned arcade fight simulation. Positions, hits and rounds never enter saves.
local Games=require("src.breakroom_games")
local Kombat={matches={},BODY_HEIGHT=150,JUMP_SPEED=660}
local STEP=1/60
local JUMP,PUNCH,KICK,BLOCK=1,2,4,8
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function pressed(mask,flag) return math.floor((mask or 0)/flag)%2==1 end
local function fighter(x,face,character)
    return {x=x,z=0,vz=0,face=face,character=character or "mouse",variant=1,
        health=100,action="idle",actionTime=0,punchCount=0,kickCount=0,
        hitApplied=false,stun=0,hitGrace=0,wins=0,previousButtons=0}
end
local function startRound(match)
    local leftWins,rightWins=match.left.wins,match.right.wins
    match.left,match.right=fighter(255,1,match.left.character),fighter(545,-1,match.right.character)
    match.left.wins,match.right.wins=leftWins,rightWins
    match.seconds,match.roundDelay=60,0
    match.aiNextAttack=match.clock+1.8
    match.aiAttacks=0
    match.draw=false
    match.phase="playing"
end
local function newMatch(bayId,id,mode)
    local match={bayId=bayId,leftId=id,rightId=nil,mode=mode,
        phase="selecting",leftReady=false,rightReady=mode=="solo",round=1,
        seconds=60,roundDelay=0,accumulator=0,clock=0,
        aiNextAttack=1.8,aiAttacks=0,
        left=fighter(255,1,"mouse"),right=fighter(545,-1,"fox")}
    return match
end
local function near(player,fixture)
    return (player.x-fixture.interactionX)^2+(player.y-fixture.interactionY)^2<=80^2
end
function Kombat.command(state,player,action)
    local bay=player and player.sceneId
    if not Games.BAYS[bay] or not Games.owns(state,bay,"critter_kombat") then
        return false,"room_locked","There is no Critter Kombat cabinet here."
    end
    if not near(player,Games.CATALOG.critter_kombat) then
        return false,"out_of_range","Stand at the arcade cabinet."
    end
    local id=tonumber(player.id) or 1
    local match=Kombat.matches[bay]
    if action=="start_solo" or action=="start_versus" then
        if match and match.phase~="finished" then return false,"cabinet_busy","Finish or leave this match first." end
        Kombat.matches[bay]=newMatch(bay,id,action=="start_solo" and "solo" or "versus")
        return true,"accepted","Choose your fighter, then confirm."
    elseif action=="rematch" then
        if not match or match.phase~="finished" or (match.leftId~=id and match.rightId~=id) then
            return false,"not_finished","Finish this match before choosing fighters again."
        end
        local fresh=newMatch(bay,match.leftId,match.mode)
        fresh.rightId=match.rightId
        fresh.left.character,fresh.right.character=match.left.character,match.right.character
        Kombat.matches[bay]=fresh
        return true,"accepted","Choose your fighters for the rematch."
    elseif action=="join" then
        if not match or match.phase~="selecting" or match.rightId or match.leftId==id
            or match.mode~="versus" then
            return false,"not_joinable","No open versus match at this cabinet."
        end
        match.rightId=id
        return true,"accepted","Choose your fighter, then confirm."
    elseif action=="ready_mouse" or action=="ready_fox" then
        if not match or match.phase~="selecting" or (match.leftId~=id and match.rightId~=id) then
            return false,"not_selecting","Join this cabinet before choosing a fighter."
        end
        local character=action=="ready_mouse" and "mouse" or "fox"
        local side=match.leftId==id and "left" or "right"
        if match[side.."Ready"] then
            if match[side].character==character then return true,"already_applied","Your fighter is ready." end
            return false,"already_ready","Go back before changing your confirmed fighter."
        end
        if match.leftId==id then
            match.left.character,match.leftReady=character,true
            if match.mode=="solo" then match.right.character=character=="mouse" and "fox" or "mouse" end
        else match.right.character,match.rightReady=character,true end
        if match.leftReady and match.rightReady and (match.mode=="solo" or match.rightId) then
            match.phase,match.countdown="intro",1.2
        end
        return true,"accepted",match.phase=="intro" and "Fighters ready!" or "Waiting for the other fighter."
    elseif action=="leave" then
        if match and (match.leftId==id or match.rightId==id) then
            Kombat.matches[bay]=nil
            return true,"accepted","Critter Kombat match ended."
        end
        return true,"already_applied","You are not in a match."
    end
    return false,"not_allowed","Unknown arcade action."
end
local function aiInput(match)
    local ai,other=match.right,match.left
    local distance=math.abs(other.x-ai.x)
    local direction=other.x<ai.x and -1 or 1
    local buttons=0
    if ai.stun>0 or ai.action=="hit" then return {x=0,buttons=0} end
    if (other.action=="punch" or other.action=="kick") and distance<100
        and other.actionTime>.13 and math.floor(match.clock*1.4)%3==0 then
        buttons=BLOCK
    elseif match.clock>=match.aiNextAttack and distance<100
        and ai.action~="punch" and ai.action~="kick" then
        match.aiAttacks=match.aiAttacks+1
        buttons=match.aiAttacks%3==0 and KICK or PUNCH
        match.aiNextAttack=match.clock+(match.aiAttacks%3==0 and 1.7 or 1.25)
    end
    if distance>108 then return {x=direction*.50,buttons=buttons} end
    if distance<57 then return {x=-direction*.42,buttons=buttons} end
    return {x=0,buttons=buttons}
end
local function beginAttack(f,action)
    local counter=action.."Count"
    f[counter]=(f[counter] or 0)+1
    f.variant=(f[counter]-1)%2+1
    f.action, f.actionTime, f.hitApplied=action,0,false
end
local function setAction(f,action)
    if f.action~=action then f.action,f.actionTime=action,0 end
end
local function stepFighter(f,other,input,dt)
    local buttons=clamp(math.floor(input and input.buttons or 0),0,15)
    local axis=clamp(input and input.x or 0,-1,1)
    f.face=other.x>=f.x and 1 or -1
    if f.action=="knockout" then return end
    if f.z>0 or f.vz>0 then
        f.z=math.max(0,f.z+f.vz*dt)
        f.vz=f.vz-1180*dt
        if f.z==0 then f.vz=0 end
    end
    f.stun=math.max(0,f.stun-dt)
    f.hitGrace=math.max(0,f.hitGrace-dt)
    f.actionTime=f.actionTime+dt
    local attack=f.action=="punch" or f.action=="kick"
    if attack then
        local duration=f.action=="punch" and .33 or .52
        if f.actionTime>=duration then f.action,f.actionTime="idle",0;attack=false end
    end
    if f.stun>0 then f.action="hit";axis=0
    elseif f.action=="hit" then f.action,f.actionTime="idle",0
    elseif not attack then
        if pressed(buttons,BLOCK) and f.z==0 then setAction(f,"block");axis=0
        elseif pressed(buttons,PUNCH) then beginAttack(f,"punch");axis=0
        elseif pressed(buttons,KICK) then beginAttack(f,"kick");axis=0
        else
            if pressed(buttons,JUMP) and not pressed(f.previousButtons,JUMP) and f.z==0 then
                f.vz=Kombat.JUMP_SPEED;f.z=1
            end
            setAction(f,f.z>0 and "jump" or math.abs(axis)>.12 and "walk" or "idle")
        end
    else axis=axis*.24 end
    f.x=clamp(f.x+axis*162*dt,65,735)
    f.previousButtons=buttons
end
local function separateFighters(match,order)
    local a,b=match.left,match.right
    if math.abs(a.z-b.z)<Kombat.BODY_HEIGHT and math.abs(b.x-a.x)<46 then
        local center=clamp((a.x+b.x)/2,88,712)
        a.x,b.x=center-order*23,center+order*23
    end
    if math.abs(b.x-a.x)>.001 then
        a.face=b.x>a.x and 1 or -1
        b.face=-a.face
    end
end
local function applyHit(attacker,defender)
    if attacker.hitApplied then return end
    local punch=attacker.action=="punch"
    local kick=attacker.action=="kick"
    if not punch and not kick then return end
    local startup=punch and .11 or .20
    local activeEnd=punch and .22 or .34
    if attacker.actionTime<startup or attacker.actionTime>activeEnd then return end
    local reach=punch and 79 or 103
    if math.abs(attacker.x-defender.x)>reach
        or math.abs(attacker.z-defender.z)>56 then return end
    attacker.hitApplied=true
    if defender.hitGrace>0 then return end
    local guarded=defender.action=="block" and defender.face==-attacker.face
    local damage=guarded and 2 or punch and 8 or 12
    defender.health=math.max(0,defender.health-damage)
    if not guarded and defender.health>0 then
        defender.stun=punch and .16 or .23
        defender.hitGrace=.58
        defender.action,defender.actionTime="hit",0
        defender.x=clamp(defender.x+attacker.face*(punch and 15 or 24),65,735)
    end
    if defender.health<=0 then defender.action,defender.actionTime="knockout",0 end
end
local function concludeRound(match)
    if match.phase~="playing" then return end
    if match.left.health>0 and match.right.health>0 and match.seconds>0 then return end
    local winner=match.left.health>match.right.health and match.left
        or match.right.health>match.left.health and match.right or nil
    match.draw=winner==nil
    if winner then
        winner.wins=winner.wins+1
        winner.action,winner.actionTime="victory",0
    end
    match.roundDelay=2.2
    match.phase="round_over"
end
function Kombat.update(dt,inputs)
    for _,match in pairs(Kombat.matches) do
        match.accumulator=math.min(STEP*5,match.accumulator+math.max(0,math.min(dt,.2)))
        while match.accumulator>=STEP do
            match.accumulator=match.accumulator-STEP
            match.clock=match.clock+STEP
            if match.phase=="intro" then
                match.countdown=math.max(0,match.countdown-STEP)
                if match.countdown<=0 then startRound(match) end
            elseif match.phase=="playing" then
                local left=inputs and inputs(match.leftId) or nil
                local right=match.mode=="solo" and aiInput(match)
                    or inputs and inputs(match.rightId) or nil
                local order=match.right.x>=match.left.x and 1 or -1
                stepFighter(match.left,match.right,left,STEP)
                stepFighter(match.right,match.left,right,STEP)
                separateFighters(match,order)
                applyHit(match.left,match.right)
                applyHit(match.right,match.left)
                match.seconds=math.max(0,match.seconds-STEP)
                concludeRound(match)
            elseif match.phase=="round_over" then
                match.left.actionTime=match.left.actionTime+STEP
                match.right.actionTime=match.right.actionTime+STEP
                match.roundDelay=match.roundDelay-STEP
                if match.roundDelay<=0 then
                    if match.left.wins>=2 or match.right.wins>=2 then match.phase="finished"
                    else
                        if not match.draw then match.round=match.round+1 end
                        startRound(match)
                    end
                end
            elseif match.phase=="finished" then
                match.left.actionTime=math.min(120,match.left.actionTime+STEP)
                match.right.actionTime=math.min(120,match.right.actionTime+STEP)
            end
        end
    end
end
function Kombat.prune(players)
    for bay,match in pairs(Kombat.matches) do
        local left=players[match.leftId]
        local right=match.rightId and players[match.rightId] or nil
        if not left or left.sceneId~=bay or match.rightId and (not right or right.sceneId~=bay) then
            Kombat.matches[bay]=nil
        end
    end
end
local function rounded(n) return math.floor(n*1000+.5)/1000 end
local function pose(f)
    return {x=rounded(f.x),z=rounded(f.z),face=f.face,health=f.health,action=f.action,
        actionTime=rounded(f.actionTime),wins=f.wins,character=f.character,variant=f.variant}
end
function Kombat.snapshot()
    local result={}
    for _,bay in ipairs({"front_left","front_right"}) do
        local match=Kombat.matches[bay]
        if match then result[#result+1]={bayId=bay,mode=match.mode,phase=match.phase,
            leftId=match.leftId,rightId=match.rightId,round=match.round,
            seconds=rounded(match.seconds),countdown=rounded(match.countdown or 0),
            leftReady=match.leftReady,rightReady=match.rightReady,
            left=pose(match.left),right=pose(match.right)} end
    end
    return result
end
function Kombat.clear() Kombat.matches={} end
return Kombat
