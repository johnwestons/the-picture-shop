local Config=require("src.config")
local Controller=require("src.player_controller")
local Motion={}

local function distanceTo(player,point)
    local dx,dy=point.x-player.x,point.y-player.y
    return dx,dy,math.sqrt(dx*dx+dy*dy)
end

function Motion.pathInput(player,path)
    if type(path)~="table" then return 0,0 end
    local speed=math.max(1,tonumber(Config.player.speed) or 1)
    local deceleration=math.max(1,tonumber(Config.player.deceleration) or 1)
    while #path>0 do
        local goal=path[1]
        local arrival=goal.arrivalRadius or 8
        local dx,dy,distance=distanceTo(player,goal)
        if distance<=arrival then
            table.remove(path,1)
        else
            local targetSpeed=math.min(speed,math.sqrt(2*deceleration*math.max(0,distance-arrival)))
            local strength=targetSpeed/speed
            return dx/distance*strength,dy/distance*strength
        end
    end
    return 0,0
end

function Motion.update(player,inputX,inputY,dt,canMove,state)
    if state then
        player.needsSpeedMultiplier=require("src.home_residents").speedScale(state,player)
    end
    return Controller.update(player,inputX or 0,inputY or 0,dt,function(_,_,nextX,nextY)
        return canMove(nextX,nextY)
    end,Config.player)
end

function Motion.consumeReached(player,path)
    if type(path)~="table" then return end
    while #path>0 do
        local _,_,distance=distanceTo(player,path[1])
        if distance>(path[1].arrivalRadius or 8) then break end
        table.remove(path,1)
    end
end

return Motion
