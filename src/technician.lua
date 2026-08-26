local Config = require("src.config")
local CutterPlacement = require("src.cutter_placement")
local MachineMaintenance = require("src.machine_maintenance")
local WindmillPlacement = require("src.windmill_placement")

local Technician = {}

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

function Technician.update(dt, state, pauseEntrance)
    local visit = Technician.ensure(state)
    if not visit then return false end
    dt = math.max(0, tonumber(dt) or 0)
    visit.animationClock = visit.animationClock + dt
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
    local travel = Config.technician.speed * dt
    while travel > 0 do
        local target = visit.route[visit.waypoint]
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
        local reached, remaining = moveToward(visit, target, travel)
        if not reached then break end
        travel = remaining
        visit.waypoint = visit.waypoint + (visit.status == "entering" and 1 or -1)
    end
    return false
end

function Technician.obstacle(state)
    local visit = Technician.ensure(state)
    return visit and visit.visible and { x = visit.x, y = visit.y, radius = 16 } or nil
end

function Technician.pose(visit)
    if not visit then return 0, 0, 0 end
    local clock = math.max(0, tonumber(visit.animationClock) or 0)
    if visit.status == "entering" or visit.status == "exiting" then
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
