-- Host-owned fixed-step air hockey for the break room.
local Games = require("src.breakroom_games")
local Hockey = { matches = {} }
local STEP = 1 / 60
local function clamp(n, a, b) return math.max(a, math.min(b, n)) end
local function near(player, point)
    return (player.x-point.x)^2+(player.y-point.y)^2 <= 75^2
end
local function reset(match, direction)
    match.puckX, match.puckY = 400, 200
    match.puckVX, match.puckVY = 265 * direction, 95 * (match.serve % 2 == 0 and 1 or -1)
    match.faceoff = 0.8
    match.serve = match.serve + 1
end
local function newMatch(bayId, ownerId, mode)
    local match = { bayId=bayId, mode=mode, leftId=ownerId, rightId=nil,
        leftX=200, leftY=200, rightX=600, rightY=200,
        puckX=400, puckY=200, puckVX=0, puckVY=0,
        leftScore=0, rightScore=0, faceoff=0, serve=0, elapsed=0,
        phase=mode=="versus" and "waiting" or "playing", accumulator=0 }
    reset(match, 1)
    return match
end
function Hockey.command(state, player, command)
    local bayId = player and player.sceneId
    if not Games.BAYS[bayId] or not Games.owns(state,bayId,"air_hockey") then
        return false,"room_locked","The air hockey table is not available here."
    end
    local fixture=Games.CATALOG.air_hockey
    if not near(player,{x=fixture.interactionX,y=fixture.interactionY}) then
        return false,"out_of_range","Stand beside the air hockey table."
    end
    local playerId=tonumber(player.id) or 1
    local match=Hockey.matches[bayId]
    if command=="start_solo" or command=="start_versus" then
        if match and match.phase~="finished" then
            return false,"table_busy","Finish or leave the current match first."
        end
        Hockey.matches[bayId]=newMatch(bayId,playerId,command=="start_solo" and "solo" or "versus")
        return true,"accepted","Air hockey match ready."
    elseif command=="join" then
        if not match or match.mode~="versus" or match.phase~="waiting"
            or match.leftId==playerId then return false,"not_joinable","No open match at this table." end
        match.rightId=playerId
        match.phase="playing"
        reset(match,1)
        return true,"accepted","Joined the air hockey match."
    elseif command=="leave" then
        if match and (match.leftId==playerId or match.rightId==playerId) then
            Hockey.matches[bayId]=nil
            return true,"accepted","Air hockey match ended."
        end
        return true,"already_applied","You are not in a match."
    end
    return false,"not_allowed","Unknown air hockey action."
end
local function movePaddle(match,side,inputX,inputY,dt)
    local xKey,yKey=side=="left" and "leftX" or "rightX",side=="left" and "leftY" or "rightY"
    local x,y=match[xKey],match[yKey]
    local magnitude=math.sqrt(inputX*inputX+inputY*inputY)
    if magnitude>1 then inputX,inputY=inputX/magnitude,inputY/magnitude end
    x=clamp(x+inputX*355*dt,side=="left" and 63 or 427,side=="left" and 373 or 737)
    y=clamp(y+inputY*355*dt,63,337)
    match[xKey],match[yKey]=x,y
end
local function collide(match,x,y,oldX,oldY,dt)
    local dx,dy=match.puckX-x,match.puckY-y
    local d2=dx*dx+dy*dy
    if d2>=42*42 or d2<0.01 then return end
    local distance=math.sqrt(d2)
    local nx,ny=dx/distance,dy/distance
    local paddleVX,paddleVY=(x-oldX)/dt,(y-oldY)/dt
    local relative=(match.puckVX-paddleVX)*nx+(match.puckVY-paddleVY)*ny
    if relative<0 then
        match.puckVX=match.puckVX-1.85*relative*nx
        match.puckVY=match.puckVY-1.85*relative*ny
    end
    local speed=math.sqrt(match.puckVX^2+match.puckVY^2)
    if speed<220 then match.puckVX,match.puckVY=nx*220,ny*220
    elseif speed>650 then match.puckVX,match.puckVY=match.puckVX*650/speed,match.puckVY*650/speed end
    match.puckX,match.puckY=x+nx*42,y+ny*42
end
local function score(match,side)
    local key=side=="left" and "leftScore" or "rightScore"
    match[key]=match[key]+1
    if match[key]>=7 then
        match.phase="finished"
        match.faceoff=0
        match.puckVX,match.puckVY=0,0
    else reset(match,side=="left" and -1 or 1) end
end
function Hockey.update(dt,inputs)
    for bayId,match in pairs(Hockey.matches) do
        match.accumulator=math.min(STEP*5,match.accumulator+math.max(0,math.min(dt,0.2)))
        while match.accumulator>=STEP do
            match.accumulator=match.accumulator-STEP
            if match.phase=="playing" then
                local left=inputs and inputs(match.leftId) or nil
                local oldLX,oldLY=match.leftX,match.leftY
                movePaddle(match,"left",left and left.x or 0,left and left.y or 0,STEP)
                local oldRX,oldRY=match.rightX,match.rightY
                local right=match.rightId and inputs and inputs(match.rightId) or nil
                if match.mode=="solo" then
                    local targetX=match.puckX>415 and clamp(match.puckX+32,510,660) or 625
                    local targetY=clamp(match.puckY,100,300)
                    right={x=clamp((targetX-match.rightX)/85,-0.72,0.72),
                        y=clamp((targetY-match.rightY)/85,-0.72,0.72)}
                end
                movePaddle(match,"right",right and right.x or 0,right and right.y or 0,STEP)
                if match.faceoff>0 then match.faceoff=math.max(0,match.faceoff-STEP)
                else
                    match.puckX=match.puckX+match.puckVX*STEP
                    match.puckY=match.puckY+match.puckVY*STEP
                    if match.puckY<55 then match.puckY=55;match.puckVY=math.abs(match.puckVY) end
                    if match.puckY>345 then match.puckY=345;match.puckVY=-math.abs(match.puckVY) end
                    if match.puckX<55 then
                        if match.puckY>148 and match.puckY<252 then score(match,"right")
                        else match.puckX=55;match.puckVX=math.abs(match.puckVX) end
                    elseif match.puckX>745 then
                        if match.puckY>148 and match.puckY<252 then score(match,"left")
                        else match.puckX=745;match.puckVX=-math.abs(match.puckVX) end
                    end
                    if match.phase=="playing" and match.faceoff==0 then
                        collide(match,match.leftX,match.leftY,oldLX,oldLY,STEP)
                        collide(match,match.rightX,match.rightY,oldRX,oldRY,STEP)
                    end
                end
                match.elapsed=match.elapsed+STEP
            end
        end
    end
end
function Hockey.snapshot()
    local result={}
    for _,bayId in ipairs({"front_left","front_right"}) do
        local m=Hockey.matches[bayId]
        if m then result[#result+1]={bayId=m.bayId,mode=m.mode,phase=m.phase,
            leftId=m.leftId,rightId=m.rightId,leftX=m.leftX,leftY=m.leftY,
            rightX=m.rightX,rightY=m.rightY,puckX=m.puckX,puckY=m.puckY,
            leftScore=m.leftScore,rightScore=m.rightScore,faceoff=m.faceoff} end
    end
    return result
end
function Hockey.prune(players)
    for bayId,match in pairs(Hockey.matches) do
        local left=players[match.leftId]
        local right=match.rightId and players[match.rightId] or nil
        if not left or left.sceneId~=bayId
            or match.rightId and (not right or right.sceneId~=bayId) then
            Hockey.matches[bayId]=nil
        end
    end
end
function Hockey.clear() Hockey.matches={} end
return Hockey
