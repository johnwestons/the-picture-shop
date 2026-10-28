local Config = require("src.config")
local CutterPlacement = require("src.cutter_placement")
local MachineMaintenance = require("src.machine_maintenance")
local WindmillPlacement = require("src.windmill_placement")
local Navigator = require("src.npc_navigation")
local Fleet = require("src.machine_fleet")
local GaitMotion = require("src.gait_motion")
local Animation = require("src.character_animation")

local Technician = {}
local servicePoints=setmetatable({},{__mode="k"})
local speeds=setmetatable({},{__mode="k"})

local function servicePoint(state,visit,context,dt)
    local model=visit.kind=="windmill" and "heidelberg_10x15" or "polar_115"
    local machine=Fleet.installedUnits(state,model)[1]
    if not machine then return nil end
    local pose=machine.world or (visit.kind=="windmill"
        and WindmillPlacement.ensure(state,Config.windmillPlacement)
        or CutterPlacement.ensure(state,Config.cutterPlacement))
    if pose.moving then return nil end
    local key=string.format("%s:%g:%g:%s",machine.id,pose.x,pose.y,pose.direction)
    local cached=servicePoints[visit]
    local obstacles=context.obstacles(visit)
    local Navigation=require("src.navigation")
    if cached and cached.key==key then
        cached.retry=math.max(0,cached.retry-dt)
        if cached.goal and Navigation.isWalkable(context.assets,cached.goal.x,cached.goal.y,obstacles) then
            return cached.goal
        end
        if cached.retry>0 then return nil end
    end
    local candidates={}
    local operator=context.operatorPoint and context.operatorPoint(machine.id,visit)
    if operator then candidates[#candidates+1]=operator end
    -- Service can be performed from either side. Prefer the operator position,
    -- then find accessible ground beside the machine, including wall placements.
    for _,radius in ipairs({52,64,80,96}) do
        for index=0,7 do
            local angle=index*math.pi/4
            candidates[#candidates+1]={x=pose.x+math.cos(angle)*radius,y=pose.y+math.sin(angle)*radius}
        end
    end
    local goal=Navigator.findReachablePoint(visit,candidates,{
        assets=context.assets,obstacles=function() return obstacles end})
    servicePoints[visit]={key=key,goal=goal,retry=.75}
    return goal
end

local function copyRoute(route)
    local result = {}
    for _, point in ipairs(route or {}) do result[#result + 1] = { x = point.x, y = point.y } end
    return result
end

local function targetFor(state, kind)
    if kind == "windmill" then
        return WindmillPlacement.operatorPosition(state, Config.windmillPlacement)
    end
    return CutterPlacement.operatorPosition(state, Config.cutterPlacement)
end

function Technician.schedule(state, kind, appointmentDay, recurring)
    if state.technicianVisit then return false end
    local route = copyRoute(Config.technician.route)
    local x, y = targetFor(state, kind)
    route[#route + 1] = { x = x, y = y }
    state.technicianVisit = {
        kind = kind, species = kind == "windmill" and "lizard" or "mouse",
        name = kind ~= "windmill" and "Mara Mouse" or nil,
        status = "scheduled", visible = false, x = route[1].x, y = route[1].y,
        route = route, waypoint = 2, facing = 1, directionFrame = 4,
        animationClock = 0, serviceTimer = 0,
        animationDistance = 0, idleClock = 0, intentX = 1, intentY = 0, inMotion = false,
        appointmentDay = appointmentDay, recurring = recurring == true,
    }
    return true, state.technicianVisit
end

function Technician.ensure(state)
    local visit = state and state.technicianVisit
    if type(visit) ~= "table" then return nil end
    visit.route = type(visit.route) == "table" and visit.route or copyRoute(Config.technician.route)
    if visit.kind ~= "windmill" then visit.name = visit.name or "Mara Mouse" end
    if #visit.route < 2 then
        local x, y = targetFor(state, visit.kind)
        visit.route[#visit.route + 1] = { x = x, y = y }
    end
    visit.x = tonumber(visit.x) or visit.route[1].x
    visit.y = tonumber(visit.y) or visit.route[1].y
    visit.waypoint = tonumber(visit.waypoint) or 2
    visit.animationClock = tonumber(visit.animationClock) or 0
    visit.serviceTimer = tonumber(visit.serviceTimer) or 0
    visit.animationDistance = math.max(0, tonumber(visit.animationDistance) or 0)
    visit.idleClock = math.max(0, tonumber(visit.idleClock) or 0)
    if not visit.intentX or not visit.intentY then
        local v=({{-1,0},{0,-1},{0,1},{1,0}})[visit.directionFrame or 4] or {1,0}
        visit.intentX,visit.intentY=v[1],v[2]
    end
    return visit
end

local function moveToward(visit, target, distance)
    local dx, dy = target.x - visit.x, target.y - visit.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length > .0001 then visit.intentX,visit.intentY=dx/length,dy/length end
    if dx ~= 0 then visit.facing = dx < 0 and -1 or 1 end
    if math.abs(dx) >= math.abs(dy) then
        visit.directionFrame = dx < 0 and 1 or 4
    else
        visit.directionFrame = dy < 0 and 2 or 3
    end
    if length == 0 or length <= distance then
        visit.x, visit.y = target.x, target.y
        return true, math.max(0, distance - length)
    end
    visit.x, visit.y = visit.x + dx / length * distance, visit.y + dy / length * distance
    return false, 0
end

function Technician.update(dt, state, pauseEntrance, motionDt, navigationContext)
    local visit = Technician.ensure(state)
    if not visit then return false end
    dt = math.max(0, tonumber(dt) or 0)
    motionDt = math.max(0, tonumber(motionDt) or dt)
    visit.inMotion = false
    local function finishMotion()
        if visit.inMotion then visit.idleClock=0
        else
            visit.idleClock=visit.idleClock+motionDt
            if motionDt>0 then speeds[visit]=nil end
        end
    end
    visit.animationClock = visit.animationClock + motionDt
    if visit.status == "scheduled" then
        if pauseEntrance then finishMotion();return false end
        visit.status, visit.visible, visit.animationClock = "entering", true, 0
        state.message = visit.kind == "windmill"
            and "The lizard press technician arrived and is walking to the machine."
            or (visit.name .. ", the blade exchange courier, arrived and is walking to the cutter.")
        return true
    elseif visit.status == "servicing" then
        speeds[visit]=nil
        visit.idleClock=visit.idleClock+motionDt
        visit.serviceTimer = visit.serviceTimer + dt
        if visit.serviceTimer < Config.technician.serviceDuration then return false end
        MachineMaintenance.completeTechnicianVisit(state, visit.kind, visit)
        visit.status, visit.waypoint, visit.animationClock = "exiting", #visit.route - 1, 0
        state.message = visit.kind == "windmill"
            and "The technician finished the service and is heading out."
            or (visit.name .. " fitted a freshly sharpened cutter blade and is taking the dull one back.")
        return true
    end
    if visit.status ~= "entering" and visit.status ~= "exiting" then finishMotion();return false end
    local speedMultiplier,accelerationMultiplier=GaitMotion.sample(visit.animationDistance,Config.technician)
    visit.gaitSpeedMultiplier,visit.gaitAccelerationMultiplier=speedMultiplier,accelerationMultiplier
    speeds[visit]=math.min(Config.technician.speed*speedMultiplier,
        (speeds[visit] or 0)+Config.technician.acceleration*accelerationMultiplier*motionDt)
    local travel = speeds[visit] * motionDt
    while travel > 0 do
        local target = visit.route[visit.waypoint]
        if target and visit.status=="entering" and visit.waypoint==#visit.route
            and navigationContext and navigationContext.operatorPoint then
            -- A machine's old fixed operator offset may be behind a wall or
            -- another machine. Share the employees' reachable service approach
            -- selection and follow relocated machines before starting service.
            target=servicePoint(state,visit,navigationContext,motionDt)
            if not target then finishMotion();return false end
            visit.route[#visit.route]={x=target.x,y=target.y}
        end
        if not target then
            if visit.status == "entering" then
                visit.status, visit.serviceTimer, visit.animationClock = "servicing", 0, 0
                visit.inMotion=false;speeds[visit]=nil;finishMotion()
                state.message = visit.kind == "windmill"
                    and "The technician is servicing the Heidelberg Windmill."
                    or (visit.name .. " is exchanging the Polar 115 blade.")
                return true
            end
            state.technicianVisit = nil
            state.message = "The technician left through the main entrance."
            return true
        end
        local startX,startY=visit.x,visit.y
        local reached,remaining,blocked,actualDistance
        if navigationContext then
            reached,remaining,actualDistance,blocked=Navigator.travel(visit,target,travel,motionDt,navigationContext)
            local dx,dy=visit.x-startX,visit.y-startY
            if actualDistance>.001 then
                visit.directionFrame=math.abs(dx)>=math.abs(dy) and (dx<0 and 1 or 4) or (dy<0 and 2 or 3)
            end
        else
            reached,remaining=moveToward(visit,target,travel)
            actualDistance=math.sqrt((visit.x-startX)^2+(visit.y-startY)^2)
        end
        if actualDistance>.0001 then
            visit.inMotion=true
            visit.animationDistance=visit.animationDistance+actualDistance
        end
        visit.navigationBlockedFor=blocked and (visit.navigationBlockedFor or 0)+motionDt or 0
        if visit.navigationBlockedFor>=2 then
            servicePoints[visit]=nil
            local candidates={}
            local direction=visit.status=="entering" and 1 or -1
            local last=visit.status=="entering" and #visit.route or 1
            for index=visit.waypoint+direction,last,direction do
                local point=visit.route[index]
                candidates[#candidates+1]={x=point.x,y=point.y,index=index}
            end
            local points,goal=Navigator.findPath(visit,candidates,navigationContext)
            if points then visit.waypoint=goal.index;Navigator.reset(visit) end
            visit.navigationBlockedFor=0
        end
        if not reached then break end
        travel = remaining
        visit.waypoint = visit.waypoint + (visit.status == "entering" and 1 or -1)
    end
    finishMotion()
    return false
end

function Technician.obstacle(state)
    local visit = Technician.ensure(state)
    return visit and visit.visible and { x = visit.x, y = visit.y, radius = 16, actor = visit } or nil
end

function Technician.pose(visit)
    if not visit then return 0, 0, 0 end
    local clock = math.max(0, tonumber(visit.animationClock) or 0)
    if visit.status == "entering" or visit.status == "exiting" then
        if visit.inMotion ~= true then return 0,0,0 end
        local phase = (visit.animationDistance or 0) / (Config.technician.walkPixelsPerFrame * 8) * math.pi * 2
        return 0, -math.abs(math.sin(phase)) * 2, math.sin(phase) * 0.018
    elseif visit.status == "servicing" then
        local phase = clock * Config.technician.serviceAnimationRate
        return math.sin(phase) * 1.5, -math.abs(math.sin(phase * 0.5)), math.sin(phase) * 0.025
    end
    return 0, 0, 0
end

function Technician.spritePose(visit,characterAssets)
    if not visit or not characterAssets then return nil end
    local character=Config.technician.characters[visit.species=="lizard" and "lizard" or "mouse"]
    local prefix=visit.status=="servicing" and "service" or visit.inMotion and "walk" or "idle"
    local action=Animation.authoredAction(prefix,visit.intentX,visit.intentY)
    -- Missing art remains explicit; never substitute a reversed, mirrored or
    -- duplicated walk strip to make an incomplete pack look complete.
    if not characterAssets.hasAction(character,action) then return nil end
    local _,_,count=characterAssets.get(character,action,1)
    local frame=prefix=="walk" and Animation.frameForGait(count,visit.animationDistance,Config.technician.walkPixelsPerFrame)
        or prefix=="idle" and Animation.frameForIdle(count,visit.idleClock,.65)
        or Animation.frameForClock(count,visit.animationClock,Config.technician.serviceAnimationRate)
    return character,action,frame
end

function Technician.presentation(state)
    if state and state._technicianPose~=nil then return state._technicianPose or nil end
    return Technician.ensure(state)
end

function Technician.draw(assets, state, characterAssets)
    local visit = Technician.presentation(state)
    if not visit or not visit.visible then return end
    local character,action,frame=Technician.spritePose(visit,characterAssets)
    if character then
        local image,quad=characterAssets.get(character,action,frame)
        local ax,ay=characterAssets.getAnchor(character,action,frame)
        local scale=Config.technician.worldHeight/Config.characterRendering.referenceHeight
            *characterAssets.getNormalization(character,action)
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(image,quad,visit.x,visit.y,0,scale,scale,ax,ay)
        return
    end
    local image = assets.get("technicianNpcs")
    local species = visit.species == "lizard" and 2 or 1
    local sprite = assets.getQuad("technician" .. species .. "_" .. tostring(visit.directionFrame or 1))
    if not image or not sprite then return end
    local offsetX, offsetY, rotation = Technician.pose(visit)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, visit.x + offsetX, visit.y + offsetY, rotation,
        Config.technician.drawScale, Config.technician.drawScale,
        sprite.width / 2, sprite.height * 0.96)
end

return Technician
