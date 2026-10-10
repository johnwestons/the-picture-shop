-- Host-owned employee transport uses the same physical jack and pallet owner as players.
local Jack = require("src.pallet_jack")
local Pallets = require("src.pallet_state")
local Navigator = require("src.npc_navigation")
local Gait = require("src.gait_motion")
local Config = require("src.config")
local Transport = {}

function Transport.owns(state, worker)
    local jack = state.palletJack
    return jack and jack.operating and jack.operatorEmployeeId == worker.id
end

local function align(state, worker)
    worker.x, worker.y = Jack.operatorPosition(state, Config.palletJack)
    worker.jackDistance = Jack.animationDistance(state, Config.palletJack)
    worker.phase, worker.moving = "pushing", state.palletJack.moving
    local pose = Jack.visualPose(state, Config.palletJack)
    worker.intentX, worker.intentY = math.cos(pose.heading), math.sin(pose.heading)
end

function Transport.move(state, worker, goal, dt, context)
    local jack = Jack.ensure(state, Config.palletJack)
    local actor = worker._jackNavigator
    if not actor then actor = {}; worker._jackNavigator = actor end
    actor.x, actor.y = jack.x, jack.y
    local elapsed = math.max(0, math.min(.1, dt * (context.motionScale or 1)))
    local speed = jack.carriedPalletId and Config.palletJack.loadedSpeed or Config.palletJack.speed
    local multiplier = Gait.sample(Jack.animationDistance(state, Config.palletJack), {
        walkPixelsPerFrame = Config.palletJack.gaitPixelsPerFrame or 20,
        gaitSpeedMultipliers = Config.player.gaitSpeedMultipliers,
        gaitAccelerationMultipliers = Config.player.gaitAccelerationMultipliers })
    local reached, _, _, blocked = Navigator.travel(actor, goal, speed * multiplier * elapsed,
        elapsed, context.jackNavigation(worker, jack.carriedPalletId))
    Jack.followNavigation(state, actor.x, actor.y, elapsed, Config.palletJack)
    align(state, worker)
    return reached, blocked
end

function Transport.release(state, worker, context)
    if not Transport.owns(state, worker) then return true end
    local jack = state.palletJack
    if jack.carriedPalletId then
        local point = context and context.jackEmergencyDropPoint and context.jackEmergencyDropPoint(worker)
        if point then
            Jack.lower(state, Config.palletJack, function() return true end, point.x, point.y)
        end
        -- If every safe space is blocked, park loaded. Ownership stays on the
        -- jack, allowing the assigned employee or a player to resume safely.
    end
    Jack.releaseEmployee(state, Config.palletJack, worker.id)
    worker._jackNavigator, worker.jackDistance, worker._jackTarget = nil, nil, nil
    worker._jackParkingTarget, worker._parkingJack = nil, nil
    worker.phase,worker.moving = "idle",false
    return true
end

function Transport.park(state, worker, dt, context)
    local jack=Jack.ensure(state,Config.palletJack)
    if not Transport.owns(state,worker) or jack.carriedPalletId then
        worker._jackParkingTarget,worker._parkingJack=nil,nil
        return true
    end
    local goal=worker._jackParkingTarget
    if not goal then
        goal=context.jackParkingPoint and context.jackParkingPoint(worker)
        worker._jackParkingTarget=goal
    end
    if not goal then
        Transport.release(state,worker,context)
        return true
    end
    worker.activity="Parking pallet jack in a clear space"
    local reached,blocked=Transport.move(state,worker,goal,dt,context)
    if blocked then
        worker._jackParkingTarget=nil
        return false,"Pallet jack parking route is blocked"
    end
    if not reached then return false end
    Jack.releaseEmployee(state,Config.palletJack,worker.id)
    worker._jackNavigator,worker.jackDistance,worker._jackTarget=nil,nil,nil
    worker._jackParkingTarget,worker._parkingJack=nil,nil
    worker.phase,worker.moving="walking",false
    worker.activity="Pallet jack parked in a clear space"
    return true
end

function Transport.update(state, worker, machine, pallet, stage, dt, context)
    local jack = Jack.ensure(state, Config.palletJack)
    local name = stage == "cutter" and "cutter" or stage == "press" and "printing press" or "skid wrapper"
    if jack.sceneId~="warehouse" and not Transport.owns(state,worker) then
        worker.phase,worker.moving="idle",false
        worker.activity="Waiting for the pallet jack to return to the warehouse"
        return false,worker.activity
    end
    if pallet.location == "on_employee" and pallet.carrierEmployeeId == worker.id then
        -- Resume legacy test saves through a real floor-to-jack pickup.
        return Pallets.transition(state, pallet, "warehouse", { world = {
            x = worker.x, y = worker.y, direction = jack.direction, spawnProgress = 1 } })
    end
    if not Transport.owns(state, worker) then
        if jack.operating or (jack.carriedPalletId and jack.carriedPalletId ~= pallet.id)
            or (state.cutter and state.cutter.moving) or (state.wrapper and state.wrapper.moving)
            or (state.windmill and state.windmill.moving) then
            worker.phase, worker.moving = "idle", false
            worker.activity = "Waiting for the pallet jack - could I use it?"
            return false, "Waiting for the pallet jack"
        end
        local goal = context.jackApproachPoint(worker)
        if not goal then worker.activity = "Pallet jack access is blocked"; return false, worker.activity end
        local reached, blocked = context.move(worker, goal, dt)
        worker.phase, worker.activity = "walking", "Walking to the pallet jack"
        if not reached then return false, blocked and "Pallet jack access is blocked" or nil end
        local mounted, reason = Jack.mountEmployee(state, Config.palletJack, worker.id)
        if not mounted then return false, reason end
        align(state, worker)
        return true
    end
    local loaded = jack.carriedPalletId == pallet.id
    if jack.carriedPalletId and not loaded then
        Transport.release(state, worker, context)
        worker.activity="Waiting for the pallet jack"
        return true, "Waiting for the pallet jack"
    end
    local origin = pallet.world or {}
    local machinePose = machine.world or state[stage == "press" and "windmill" or stage == "wrapping" and "wrapper" or "cutter"] or {}
    local key = table.concat({pallet.id, loaded and "loaded" or "empty", machine.id,
        tostring(not loaded and origin.x), tostring(not loaded and origin.y), tostring(machinePose.x), tostring(machinePose.y)}, ":")
    local target = worker._jackTarget
    local goal = target and target.key == key and target.goal
    if not goal then
        goal = loaded and context.jackDropPoint(machine.id, worker, pallet, stage)
            or context.jackPickupPoint(worker, pallet)
        worker._jackTarget = goal and {key=key,goal=goal} or nil
    end
    if not goal then
        Jack.stop(state, Config.palletJack); align(state, worker)
        worker.activity = loaded and "Clear the pallet jack route beside the " .. name or "Assigned pallet access is blocked"
        return false, worker.activity
    end
    worker.activity = loaded and "Pushing pallet to the " .. name or "Pushing pallet jack to assigned pallet"
    local reached, blocked = Transport.move(state, worker, goal, dt, context)
    if not reached then
        if blocked then worker.activity = "Pallet jack route is blocked"; worker._jackTarget=nil end
        return false, blocked and worker.activity or nil
    end
    if loaded then
        -- The route goal is the jack's wheelbase; the pallet lands at the fork tip.
        local lowered, reason = Jack.lower(state, Config.palletJack, function(x, y)
            return context.jackDropClear(worker, pallet.id, x, y)
        end, nil, nil, pallet.id)
        if not lowered then worker.activity = "Clear floor beside the " .. name .. " is blocked"; return false, reason end
        worker._jackTarget=nil
        worker._jackParkingTarget=nil
        worker._parkingJack=true
        worker.activity="Pallet staged; parking the pallet jack"
        return true
    end
    if context.jackLoadClear and not context.jackLoadClear(worker,pallet.id,jack.x,jack.y) then
        Jack.stop(state,Config.palletJack);worker._jackTarget=nil;align(state,worker)
        worker.activity="Assigned pallet access is blocked"
        return false,worker.activity
    end
    local lifted, reason = Jack.lift(state, Config.palletJack, pallet.id)
    if not lifted then worker.activity = "Assigned pallet pickup needs help"; return false, reason end
    worker._jackTarget = nil
    align(state, worker)
    return true
end

return Transport
