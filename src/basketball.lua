-- One physical ball per purchased hoop. The host owns possession and shots.
local Games=require("src.breakroom_games")
local Ball={shots={},contests={},streaks={}}
local goal=Games.CATALOG.basketball
local HOOP_X,HOOP_Y=goal.rimX,goal.rimY
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function entries(state)
    local result={}
    for _,bayId in ipairs({"front_left","front_right"}) do
        local record=state.breakroomGames and state.breakroomGames.bays[bayId]
        if record and record.ball then result[#result+1]={bayId=bayId,ball=record.ball} end
    end
    return result
end
local function holder(state,playerId)
    for _,entry in ipairs(entries(state)) do
        if entry.ball.mode=="held" and entry.ball.holderPlayerId==playerId then
            return entry.bayId,entry.ball
        end
    end
end
local function dropPoint(state,sceneId,x,y)
    local Rooms=require("src.shop_rooms")
    local kind=Rooms.definition(state,sceneId) or "warehouse"
    local offsets={{0,0},{24,0},{-24,0},{0,24},{0,-24},{36,24},{-36,24}}
    for _,offset in ipairs(offsets) do
        local px,py=clamp(x+offset[1],18,942),clamp(y+offset[2],220,660)
        if Rooms.walkable(px,py,sceneId,kind) then
            local clear=true
            for _,obstacle in ipairs(Rooms.obstacles(state,sceneId)) do
                if math.abs(px-obstacle.x)<(obstacle.halfWidth or 0)+14
                    and math.abs(py-obstacle.y)<(obstacle.halfHeight or 0)+14 then clear=false;break end
            end
            if clear then return px,py end
        end
    end
end
local function setPlaced(ball,sceneId,x,y)
    ball.sceneId,ball.x,ball.y=sceneId,x,y
    ball.lastSceneId,ball.lastX,ball.lastY=sceneId,x,y
    ball.mode,ball.holderPlayerId="placed",nil
end
function Ball.command(state,player,action)
    local playerId=tonumber(player and player.id) or 1
    local sceneId=player and player.sceneId or "warehouse"
    local bayId,ball=holder(state,playerId)
    if action=="pickup" then
        if ball then return false,"already_holding","You already have a basketball." end
        for _,entry in ipairs(entries(state)) do
            local candidate=entry.ball
            if candidate.mode=="placed" and candidate.sceneId==sceneId
                and distance(player,candidate)<=58 then
                candidate.mode,candidate.holderPlayerId="held",playerId
                candidate.x,candidate.y=player.x,player.y
                Ball.streaks[entry.bayId]=Ball.streaks[entry.bayId] or 0
                return true,"accepted","Ball picked up. Dribble as you move; press Space to shoot or Q to drop."
            end
        end
        return false,"out_of_range","Move closer to a loose basketball."
    elseif action=="drop" then
        if not ball then return false,"no_ball","Pick up a basketball first." end
        if Ball.shots[bayId] then return false,"shooting","Finish the shot before dropping the ball." end
        local x,y=dropPoint(state,sceneId,player.x+16,player.y+19)
        if not x then return false,"blocked","Find clear floor space for the ball." end
        setPlaced(ball,sceneId,x,y)
        return true,"accepted","Ball placed on the floor."
    elseif action=="shot_start" then
        if not ball then return false,"no_ball","Pick up a basketball first." end
        if sceneId~=bayId or not Games.owns(state,bayId,"basketball") then
            return false,"wrong_room","Bring the ball back to its break-room goal to shoot."
        end
        if Ball.shots[bayId] then return false,"shooting","Finish the current shot first." end
        local hoop={x=HOOP_X,y=HOOP_Y}
        if distance(player,hoop)>500 then return false,"out_of_range","Move closer to the basket." end
        local dx,dy=hoop.x-player.x,hoop.y-player.y
        local length=math.max(1,math.sqrt(dx*dx+dy*dy))
        player.intentX,player.intentY=dx/length,dy/length
        player.velocityX,player.velocityY=0,0
        Ball.shots[bayId]={phase="charge",shooterId=playerId,elapsed=0,
            startX=player.x,startY=player.y}
        return true,"accepted","Jump shot started. Release Space at the top of the jump."
    elseif action=="shot_release" then
        local shot=bayId and Ball.shots[bayId]
        if not shot or shot.phase~="charge" or shot.shooterId~=playerId then
            return false,"no_shot","Start a jump shot first."
        end
        local release=shot.elapsed
        local delta=release-0.42
        local quality=clamp(1-math.abs(delta)/0.52,0,1)
        local distanceToHoop=distance(player,{x=HOOP_X,y=HOOP_Y})
        -- The same early/late release has a repeatable lateral error.
        local offset=delta*95+(distanceToHoop/480)*math.abs(delta)*45
        shot.phase,shot.elapsed="flight",0
        shot.quality,shot.offset=quality,offset
        shot.duration=clamp(0.58+distanceToHoop/1000,0.58,0.98)
        shot.endX,shot.endY=HOOP_X+offset,HOOP_Y
        shot.startX,shot.startY=player.x,player.y-18
        ball.mode,ball.holderPlayerId="flight",nil
        return true,"accepted",quality>.8 and "Great release!" or "The release was off the apex."
    elseif action=="contest" or action=="join" or action=="end" then
        if not Games.BAYS[sceneId] or not Games.owns(state,sceneId,"basketball")
            or distance(player,{x=goal.interactionX,y=goal.interactionY})>110 then
            return false,"out_of_range","Stand near the break-room hoop."
        end
        local contest=Ball.contests[sceneId]
        if action=="contest" then
            if contest and contest.phase~="finished" then return false,"busy","This contest is already active." end
            Ball.contests[sceneId]={phase="waiting",leftId=playerId,rightId=nil,
                leftScore=0,rightScore=0}
            return true,"accepted","First to eleven: another player can join at the hoop."
        elseif action=="join" then
            if not contest or contest.phase~="waiting" or contest.leftId==playerId then
                return false,"not_joinable","No waiting contest at this hoop."
            end
            contest.rightId,contest.phase=playerId,"playing"
            return true,"accepted","Basketball contest started. First to eleven."
        else
            if contest and (contest.leftId==playerId or contest.rightId==playerId) then
                Ball.contests[sceneId]=nil
                return true,"accepted","Basketball contest ended."
            end
            return false,"no_contest","You are not in this contest."
        end
    end
    return false,"not_allowed","Unknown basketball action."
end
function Ball.onTransition(state,player,destination)
    local _,ball=holder(state,tonumber(player.id) or 1)
    if ball then ball.sceneId,ball.x,ball.y=destination,player.x,player.y end
end
function Ball.isCharging(playerId)
    for _,shot in pairs(Ball.shots) do
        if shot.phase=="charge" and shot.shooterId==playerId then return true end
    end
    return false
end
function Ball.isChargingFor(state,playerId)
    if Ball.isCharging(playerId) then return true end
    for _,record in ipairs(state and state._networkBasketballs or {}) do
        if record.shooterId==playerId and record.shotPhase=="charge" then return true end
    end
    return false
end
function Ball.update(dt,state,players)
    local changed=false
    for _,entry in ipairs(entries(state)) do
        local ball=entry.ball
        if ball.mode=="held" then
            local player=players[ball.holderPlayerId]
            if player then ball.sceneId,ball.x,ball.y=player.sceneId or "warehouse",player.x,player.y
            else setPlaced(ball,ball.lastSceneId,ball.lastX,ball.lastY);changed=true end
        end
        local shot=Ball.shots[entry.bayId]
        if shot then
            shot.elapsed=shot.elapsed+math.max(0,math.min(dt,0.2))
            if shot.phase=="charge" and shot.elapsed>1.3 then
                local player=players[shot.shooterId]
                if player then Ball.command(state,player,"shot_release")
                else Ball.shots[entry.bayId]=nil
                    setPlaced(ball,ball.lastSceneId,ball.lastX,ball.lastY);changed=true end
            elseif shot.phase=="flight" then
                local t=clamp(shot.elapsed/shot.duration,0,1)
                ball.x=shot.startX+(shot.endX-shot.startX)*t
                ball.y=shot.startY+(shot.endY-shot.startY)*t
                shot.displayY=ball.y-(125+math.abs(shot.startY-HOOP_Y)*.23)*4*t*(1-t)
                if not shot.checked and t>=1 then
                    shot.checked=true
                    shot.scored=math.abs(shot.offset)<17 and shot.quality>=.55
                    shot.rimHit=not shot.scored and math.abs(shot.offset)<31
                    if shot.scored then
                        local contest=Ball.contests[entry.bayId]
                        if contest and contest.phase=="playing" then
                            if shot.shooterId==contest.leftId then contest.leftScore=contest.leftScore+1
                            elseif shot.shooterId==contest.rightId then contest.rightScore=contest.rightScore+1 end
                            if contest.leftScore>=11 or contest.rightScore>=11 then contest.phase="finished" end
                        end
                        Ball.streaks[entry.bayId]=(Ball.streaks[entry.bayId] or 0)+1
                    else Ball.streaks[entry.bayId]=0 end
                end
                if t>=1 then
                    shot.phase=shot.scored and "fall" or "rebound"
                    shot.elapsed=0
                    shot.startX,shot.startY=ball.x,ball.y
                    shot.duration=shot.scored and .32 or .52
                    shot.endX=shot.scored and HOOP_X+18
                        or clamp(ball.x+(shot.offset>=0 and 64 or -64),35,925)
                    shot.endY=shot.scored and HOOP_Y+105 or HOOP_Y+100
                end
            elseif shot.phase=="fall" or shot.phase=="rebound" then
                local t=clamp(shot.elapsed/shot.duration,0,1)
                ball.x=shot.startX+(shot.endX-shot.startX)*t
                ball.y=shot.startY+(shot.endY-shot.startY)*t
                shot.displayY=shot.phase=="rebound" and ball.y-46*4*t*(1-t) or ball.y
                if t>=1 then
                    local x,y=dropPoint(state,entry.bayId,shot.endX,shot.endY)
                    if not x then x,y=ball.lastX,ball.lastY end
                    setPlaced(ball,entry.bayId,x,y)
                    Ball.shots[entry.bayId]=nil
                    changed=true
                end
            end
        end
    end
    return changed
end
function Ball.snapshot(state)
    local result={}
    for _,entry in ipairs(entries(state)) do
        local ball,shot,contest=entry.ball,Ball.shots[entry.bayId],Ball.contests[entry.bayId]
        result[#result+1]={bayId=entry.bayId,sceneId=ball.sceneId,x=ball.x,y=ball.y,
            displayY=shot and shot.displayY or ball.y,mode=ball.mode,
            holderPlayerId=ball.holderPlayerId,shooterId=shot and shot.shooterId or nil,
            shotPhase=shot and shot.phase or nil,shotElapsed=shot and shot.elapsed or nil,
            rimHit=shot and shot.rimHit or false,
            leftId=contest and contest.leftId or nil,rightId=contest and contest.rightId or nil,
            leftScore=contest and contest.leftScore or 0,rightScore=contest and contest.rightScore or 0,
            contestPhase=contest and contest.phase or nil,streak=Ball.streaks[entry.bayId] or 0}
    end
    return result
end
function Ball.renderRecords(state)
    if type(state._networkBasketballs)=="table" and #state._networkBasketballs>0 then
        return state._networkBasketballs
    end
    return Ball.snapshot(state)
end
function Ball.heldBy(state,playerId)
    for _,record in ipairs(Ball.renderRecords(state)) do
        if record.mode=="held" and record.holderPlayerId==playerId then return record end
    end
end
function Ball.clear() Ball.shots={};Ball.contests={};Ball.streaks={} end
return Ball
