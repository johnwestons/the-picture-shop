local Config = require("src.config")
local CutterPlacement = require("src.cutter_placement")
local MachineMaintenance = require("src.machine_maintenance")
local WindmillPlacement = require("src.windmill_placement")
local Navigator = require("src.npc_navigation")
local Fleet = require("src.machine_fleet")

local Technician = {}
local servicePoints=setmetatable({},{__mode="k"})

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
        status = "scheduled", visible = false, x = route[1].x, y = route[1].y,
        route = route, waypoint = 2, facing = 1, directionFrame = 4,
        animationClock = 0, serviceTimer = 0,
        appointmentDay = appointmentDay, recurring = recurring == true,
    }
    return true, state.technicianVisit
end

function Technician.ensure(state)
    local visit = state and state.technicianVisit
    if type(visit) ~= "table" then return nil end
    visit.route = type(visit.route) == "table" and visit.route or copyRoute(Config.technician.route)
    if #visit.route < 2 then
        local x, y = targetFor(state, visit.kind)
        visit.route[#visit.route + 1] = { x = x, y = y }
    end
    visit.x = tonumber(visit.x) or visit.route[1].x
    visit.y = tonumber(visit.y) or visit.route[1].y
    visit.waypoint = tonumber(visit.waypoint) or 2
    visit.animationClock = tonumber(visit.animationClock) or 0
    visit.serviceTimer = tonumber(visit.serviceTimer) or 0
    return visit
end

local function moveToward(visit, target, distance)
    local dx, dy = target.x - visit.x, target.y - visit.y
    local length = math.sqrt(dx * dx + dy * dy)
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
    visit.animationClock = visit.animationClock + motionDt
    if visit.status == "scheduled" then
        if pauseEntrance then return false end
        visit.status, visit.visible, visit.animationClock = "entering", true, 0
        state.message = (visit.species == "mouse" and "The mouse blade technician"
            or "The lizard press technician") .. " arrived and is walking to the machine."
        return true
    elseif visit.status == "servicing" then
        visit.serviceTimer = visit.serviceTimer + dt
        if visit.serviceTimer < Config.technician.serviceDuration then return false end
        MachineMaintenance.completeTechnicianVisit(state, visit.kind, visit)
        visit.status, visit.waypoint, visit.animationClock = "exiting", #visit.route - 1, 0
        state.message = "The technician finished the service and is heading out."
        return true
    end
    if visit.status ~= "entering" and visit.status ~= "exiting" then return false end
    local travel = Config.technician.speed * motionDt
    while travel > 0 do
        local target = visit.route[visit.waypoint]
        if target and visit.status=="entering" and visit.waypoint==#visit.route
            and navigationContext and navigationContext.operatorPoint then
            -- A machine's old fixed operator offset may be behind a wall or
            -- another machine. Share the employees' reachable service approach
            -- selection and follow relocated machines before starting service.
            target=servicePoint(state,visit,navigationContext,motionDt)
            if not target then visit.inMotion=false;return false end
            visit.route[#visit.route]={x=target.x,y=target.y}
        end
        if not target then
            if visit.status == "entering" then
                visit.status, visit.serviceTimer, visit.animationClock = "servicing", 0, 0
                state.message = "The technician is servicing the "
                    .. (visit.kind == "windmill" and "Heidelberg Windmill." or "Polar cutter blade.")
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
            visit.inMotion=math.abs(dx)+math.abs(dy)>.001
            if visit.inMotion then
                visit.directionFrame=math.abs(dx)>=math.abs(dy) and (dx<0 and 1 or 4) or (dy<0 and 2 or 3)
            end
        else
            reached,remaining=moveToward(visit,target,travel)
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
        if visit.inMotion == false then return 0,0,0 end
        local phase = clock * Config.technician.walkAnimationRate
        return 0, -math.abs(math.sin(phase)) * 2, math.sin(phase) * 0.018
    elseif visit.status == "servicing" then
        local phase = clock * Config.technician.serviceAnimationRate
        return math.sin(phase) * 1.5, -math.abs(math.sin(phase * 0.5)), math.sin(phase) * 0.025
    end
    return 0, 0, 0
end

function Technician.draw(assets, state)
    local visit = Technician.ensure(state)
    if not visit or not visit.visible then return end
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
