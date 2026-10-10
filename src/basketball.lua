-- One physical ball per purchased hoop. The host owns possession and shots.
local Games=require("src.breakroom_games")
local Trajectory=require("src.basketball_trajectory")
local Art=require("src.basketball_art")
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
function Ball.command(state,player,action,aim)
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
                return true,"accepted","Ball picked up. Hold Space or drag the court to aim; release to shoot. Q: drop."
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
            startX=player.x,startY=player.y,directionX=dx,aimX=0,arcHeight=105}
        return true,"accepted","Drag to aim the arc. Release at the jump apex."
    elseif action=="shot_release" then
        local shot=bayId and Ball.shots[bayId]
        if not shot or shot.phase~="charge" or shot.shooterId~=playerId then
            return false,"no_shot","Start a jump shot first."
        end
        if aim then
            if type(aim)~="table" or type(aim.aimX)~="number" or aim.aimX~=aim.aimX
                or math.abs(aim.aimX)>100 or type(aim.arcHeight)~="number"
                or aim.arcHeight~=aim.arcHeight or aim.arcHeight<45 or aim.arcHeight>190
                or aim.elapsed~=nil and (type(aim.elapsed)~="number" or aim.elapsed~=aim.elapsed
                    or aim.elapsed<0 or aim.elapsed>Trajectory.MAX_CHARGE
                    or math.abs(aim.elapsed-shot.elapsed)>.35) then
                return false,"invalid_aim","That shot aim or release time is invalid."
            end
            shot.aimX,shot.arcHeight=aim.aimX,aim.arcHeight
        end
        local release=aim and aim.elapsed or shot.elapsed
        local x,y=Art.releasePoint(player,release)
        local path=Trajectory.path(x,y,shot.aimX,shot.arcHeight,release)
        shot.phase,shot.elapsed="flight",0
        shot.quality,shot.perfect=path.quality,path.perfect
        shot.releaseTime,shot.releaseElapsed=release,0
        shot.path,shot.displayY=path,y
        shot.duration=path.duration
        ball.x,ball.y=x,clamp(y,0,678)
        ball.mode,ball.holderPlayerId="flight",nil
        return true,"accepted",path.perfect and "Perfect release!"
            or path.quality>.6 and "Good release." or "The release was off the apex."
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
function Ball.setAim(state,playerId,aimX,arcHeight)
    local bayId=holder(state,playerId)
    local shot=bayId and Ball.shots[bayId]
    if not shot or shot.phase~="charge" then return false end
    shot.aimX,shot.arcHeight=clamp(aimX,-100,100),clamp(arcHeight,45,190)
    return true
end
local function finishAttempt(shot,bayId,scored)
    shot.scored=scored
    if scored then
        local contest=Ball.contests[bayId]
        if contest and contest.phase=="playing" then
            if shot.shooterId==contest.leftId then contest.leftScore=contest.leftScore+1
            elseif shot.shooterId==contest.rightId then contest.rightScore=contest.rightScore+1 end
            if contest.leftScore>=11 or contest.rightScore>=11 then contest.phase="finished" end
        end
        Ball.streaks[bayId]=(Ball.streaks[bayId] or 0)+1
    else Ball.streaks[bayId]=0 end
end
local function rebound(shot,ball,boardHit)
    shot.phase,shot.elapsed,shot.duration="rebound",0,.52
    shot.boardHit=boardHit or false
    shot.bounceX,shot.bounceY=ball.x,shot.displayY
    shot.endX=clamp(ball.x+(boardHit and 95 or (ball.x>=HOOP_X and 64 or -64)),35,925)
    shot.endY=HOOP_Y+105
    if boardHit then
        local nx,ny=shot.contactNormalX,shot.contactNormalY
        if not nx then nx,ny=Trajectory.boardNormal(ball.x,shot.displayY) end
        local incoming=shot.bouncePath or shot.path
        local vx,vy=incoming.vx,incoming.vy+Trajectory.GRAVITY*(shot.contactTime or 0)
        local dot=vx*nx+vy*ny
        vx,vy=(vx-2*math.min(0,dot)*nx)*.38,(vy-2*math.min(0,dot)*ny)*.38
        local duration=(-vy+math.sqrt(vy*vy+2*Trajectory.GRAVITY*(shot.endY-shot.displayY)))/Trajectory.GRAVITY
        shot.bouncePath={x=ball.x+nx*.1,y=shot.displayY+ny*.1,vx=vx,vy=vy,duration=duration}
        shot.duration=duration
        shot.endX=clamp(ball.x+vx*duration,18,942)
    end
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
            local step=math.max(0,math.min(dt,0.2))
            shot.elapsed=shot.elapsed+step
            if shot.releaseElapsed then shot.releaseElapsed=math.min(2,shot.releaseElapsed+step) end
            local shooter=players[shot.shooterId]
            if shot.phase=="charge" and shooter and shooter.gameInputX~=nil then
                shot.aimX=clamp(shooter.gameInputX*100,-100,100)
                shot.arcHeight=clamp(105+(shooter.gameInputY or 0)*85,45,190)
            end
            if shot.phase=="charge" and shot.elapsed>=Trajectory.MAX_CHARGE then
                local player=players[shot.shooterId]
                if player then shot.elapsed=Trajectory.MAX_CHARGE;Ball.command(state,player,"shot_release")
                else Ball.shots[entry.bayId]=nil
                    setPlaced(ball,ball.lastSceneId,ball.lastX,ball.lastY);changed=true end
            elseif shot.phase=="flight" then
                local oldX,oldY=ball.x,shot.displayY
                local nextX,nextY=Trajectory.point(shot.path,math.min(shot.elapsed,shot.duration))
                local hitX,hitY,nx,ny=Trajectory.sweepFlight(oldX,oldY,nextX,nextY)
                if hitX then
                    ball.x,ball.y,shot.displayY=hitX,clamp(hitY,0,678),hitY
                    shot.contactTime=shot.elapsed
                    shot.contactNormalX,shot.contactNormalY=nx,ny
                    finishAttempt(shot,entry.bayId,false);rebound(shot,ball,true)
                else
                    ball.x,ball.y,shot.displayY=clamp(nextX,0,960),clamp(nextY,0,678),nextY
                    if shot.elapsed>=shot.duration then
                        local offset=ball.x-HOOP_X
                        local scored=math.abs(offset)<Trajectory.rim.halfWidth and shot.quality>=.45
                        shot.rimHit=not scored and math.abs(offset)<26
                        finishAttempt(shot,entry.bayId,scored)
                        if scored then
                            shot.phase,shot.elapsed,shot.duration="fall",0,.32
                            shot.bounceX,shot.bounceY=ball.x,shot.displayY
                            shot.endX,shot.endY=HOOP_X+18,HOOP_Y+105
                        else rebound(shot,ball,false) end
                    end
                end
            elseif shot.phase=="fall" or shot.phase=="rebound" then
                local t=clamp(shot.elapsed/shot.duration,0,1)
                if shot.bouncePath then
                    local x,y=Trajectory.point(shot.bouncePath,math.min(shot.elapsed,shot.duration))
                    local hx,hy,nx,ny=Trajectory.sweepFlight(ball.x,shot.displayY,x,y)
                    if hx then
                        ball.x,ball.y,shot.displayY=hx,clamp(hy,0,678),hy
                        shot.contactNormalX,shot.contactNormalY=nx,ny
                        shot.contactTime=shot.elapsed;rebound(shot,ball,true);t=0
                    else ball.x,ball.y,shot.displayY=clamp(x,18,942),clamp(y,0,678),y end
                else
                    ball.x=shot.bounceX+(shot.endX-shot.bounceX)*t
                    ball.y=shot.bounceY+(shot.endY-shot.bounceY)*t
                    shot.displayY=shot.phase=="rebound" and ball.y-24*4*t*(1-t) or ball.y
                end
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
            shotStartX=shot and shot.startX,shotStartY=shot and shot.startY,
            directionX=shot and shot.directionX,aimX=shot and shot.aimX,
            arcHeight=shot and shot.arcHeight,releaseTime=shot and shot.releaseTime,
            releaseElapsed=shot and shot.releaseElapsed,boardHit=shot and shot.boardHit or false,
            rimHit=shot and shot.rimHit or false,
            leftId=contest and contest.leftId or nil,rightId=contest and contest.rightId or nil,
            leftScore=contest and contest.leftScore or 0,rightScore=contest and contest.rightScore or 0,
            contestPhase=contest and contest.phase or nil,streak=Ball.streaks[entry.bayId] or 0}
    end
    return result
end
function Ball.renderRecords(state)
    local records=type(state._networkBasketballs)=="table" and #state._networkBasketballs>0
        and state._networkBasketballs or Ball.snapshot(state)
    local aim=state._basketballAim
    if not aim then return records end
    local result={}
    for _,record in ipairs(records) do
        local copy={};for k,v in pairs(record) do copy[k]=v end
        if record.mode=="held" and record.holderPlayerId==aim.playerId then
            copy.shooterId,copy.shotPhase,copy.shotElapsed=aim.playerId,"charge",aim.elapsed
            copy.shotStartX,copy.shotStartY=aim.startX,aim.startY
            copy.directionX,copy.aimX,copy.arcHeight=aim.directionX,aim.aimX,aim.arcHeight
        end
        result[#result+1]=copy
    end
    return result
end
function Ball.heldBy(state,playerId)
    for _,record in ipairs(Ball.renderRecords(state)) do
        if record.mode=="held" and record.holderPlayerId==playerId then return record end
    end
end
function Ball.clear() Ball.shots={};Ball.contests={};Ball.streaks={} end
return Ball
