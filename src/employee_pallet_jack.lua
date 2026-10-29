-- Host-owned employee transport uses the same physical jack and pallet owner as players.
local Jack = require("src.pallet_jack")
local Pallets = require("src.pallet_state")
local Navigator = require("src.npc_navigation")
local Gait = require("src.gait_motion")
local Config = require("src.config")
local Storage = require("src.pallet_storage")
local Procurement = require("src.procurement")
local Fleet = require("src.pallet_jack_fleet")
local Transport = {}

function Transport.owns(state, worker)
    local jack = Fleet.owned(state,worker.id)
    return jack and jack.operating and jack.operatorEmployeeId == worker.id
end

local function align(state, worker)
    worker.x, worker.y = Jack.operatorPosition(state, Config.palletJack)
    worker.sceneId=state.palletJack.sceneId or "warehouse"
    worker.jackDistance = Jack.animationDistance(state, Config.palletJack)
    worker.phase, worker.moving = "pushing", state.palletJack.moving
    local pose = Jack.visualPose(state, Config.palletJack)
    worker.intentX, worker.intentY = math.cos(pose.heading), math.sin(pose.heading)
end

function Transport.move(state, worker, goal, dt, context)
    state=Fleet.employeeView(state,worker)
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
    worker._shippingPalletId=nil
    if not Transport.owns(state, worker) then return true end
    state=Fleet.employeeView(state,worker)
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

function Transport.takeFromEmployee(state, employeeId, playerId)
    local worker=require("src.employees").worker(state,employeeId)
    local jack=Fleet.owned(state,employeeId)
    if not worker or not jack then return false,"not_operating" end
    local jackState=Fleet.view(state,jack)
    Jack.stop(jackState,Config.palletJack)
    Jack.releaseEmployee(jackState,Config.palletJack,employeeId)
    local mounted,reason=Jack.mount(jackState,Config.palletJack,playerId)
    if not mounted then
        Jack.mountEmployee(jackState,Config.palletJack,employeeId)
        return false,reason or "busy"
    end
    worker._jackNavigator,worker._jackTarget,worker.jackDistance=nil,nil,nil
    worker._jackParkingTarget,worker._parkingJack,worker._shippingPalletId=nil,nil,nil
    worker._waitingForJack,worker._scheduleBlockedReason,worker._waitingMachineId=nil,nil,nil
    worker._scheduleRetryAtHours=nil
    worker.phase,worker.moving="idle",false
    worker.activity="The player took the pallet jack; returning to assigned work"
    return true,jack
end

function Transport.park(state, worker, dt, context)
    state=Fleet.employeeView(state,worker)
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
    if not Fleet.employee(state,worker,pallet.id) then
        worker.phase,worker.moving="idle",false
        worker.activity="Waiting for an available pallet jack"
        return false,worker.activity
    end
    state=Fleet.employeeView(state,worker,pallet.id)
    local jack = Jack.ensure(state, Config.palletJack)
    local name = stage == "cutter" and "cutter" or stage == "press" and "printing press" or "skid wrapper"
    if (worker.sceneId or "warehouse")~=jack.sceneId and not Transport.owns(state,worker) then
        if context.travelScene then
            local _,changed=context.travelScene(worker,jack.sceneId,dt)
            return changed
        end
        return false,"Waiting for the pallet jack to return to the warehouse"
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
        if goal.dropDirection then Jack.face(state, Config.palletJack, goal.dropDirection) end
        local lowered, reason = Jack.lower(state, Config.palletJack, function(x, y)
            return context.jackDropClear(worker, pallet.id, x, y)
        end, nil, nil, pallet.id)
        if not lowered then
            worker._jackTarget=nil
            worker.activity = "Clear floor beside the " .. name .. " is blocked"
            return false, reason
        end
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

function Transport.storeSupplies(state,worker,dt,context)
    if not Fleet.employee(state,worker) then return false,false end
    state=Fleet.employeeView(state,worker)
    if worker._parkingJack and Transport.owns(state,worker) then
        return true,Transport.park(state,worker,dt,context)==true
    end
    local jack=Jack.ensure(state,Config.palletJack)
    local function finishStocking()
        if not Transport.owns(state,worker) then return false,false end
        if jack.carriedPalletId then
            Transport.release(state,worker,context)
            return true,true
        end
        worker._parkingJack=true
        return true,Transport.park(state,worker,dt,context)==true
    end
    local rackId="warehouse-rack"
    local rack=state.storage and state.storage.racks[rackId]
    if not rack or jack.sceneId~="warehouse" then return finishStocking() end
    local slots=Storage.slots(state,rackId)
    local column
    for index=1,Storage.COLUMNS do
        if not slots[1][index] then column=index;break end
    end
    if not column then return finishStocking() end
    local pallet
    if jack.carriedPalletId then
        local item=Pallets.find(state,jack.carriedPalletId)
        if item and item.vendor and item.pallet.kind=="vendor_product" then pallet=item.pallet end
    else
        for _,item in ipairs(Procurement.physicalPallets(state)) do
            if item.pallet.kind=="vendor_product"
                and not Storage.isSupporting(state,item.pallet.id) then
                pallet=item.pallet;break
            end
        end
    end
    if not pallet then return finishStocking() end
    if jack.operating and jack.operatorEmployeeId~=worker.id then return false,false end
    if not Transport.owns(state,worker) then
        local goal=context.jackApproachPoint and context.jackApproachPoint(worker)
        if not goal then return false,false end
        local reached=context.move(worker,goal,dt)
        worker.phase,worker.activity="walking","Walking to pallet jack for stock"
        if reached then
            local mounted=Jack.mountEmployee(state,Config.palletJack,worker.id)
            if mounted then align(state,worker);return true,true end
        end
        return true,false
    end
    if not jack.carriedPalletId then
        local goal=context.jackPickupPoint and context.jackPickupPoint(worker,pallet)
        if not goal then worker.activity="Stock pallet access is blocked";return true,false end
        worker.activity="Pushing pallet jack to stock supplies"
        local reached,blocked=Transport.move(state,worker,goal,dt,context)
        if blocked then worker.activity="Stock pallet jack route is blocked" end
        if reached then
            if context.jackLoadClear and not context.jackLoadClear(worker,pallet.id,jack.x,jack.y) then
                worker.activity="Stock pallet pickup route is blocked"
                return true,false
            end
            local lifted=Jack.lift(state,Config.palletJack,pallet.id)
            if lifted then align(state,worker);return true,true end
        end
        return true,false
    end
    local goal
    if context.jackShelfPoint then
        for candidate=1,Storage.COLUMNS do
            if not slots[1][candidate] then
                goal=context.jackShelfPoint(worker,rackId,candidate)
                if goal then column=candidate;break end
            end
        end
    end
    if not goal then worker.activity="Stock shelf access is blocked";return true,false end
    worker.activity="Putting stock supplies on the shelf"
    local reached,blocked=Transport.move(state,worker,goal,dt,context)
    if blocked then
        worker._jackShelfKey,worker._jackShelfPoint=nil,nil
        worker.activity="Stock shelf route is blocked"
    end
    if not reached then return true,false end
    Jack.face(state,Config.palletJack,"north")
    Jack.stop(state,Config.palletJack)
    local stored=Storage.employeeStore(state,worker.id,pallet.id,rackId,column)
    if stored then
        worker._jackShelfKey,worker._jackShelfPoint=nil,nil
        worker._parkingJack=true
        worker.activity="Stock supplies stored; clearing the shelf aisle"
        return true,true
    end
    worker.activity="Stock shelf slot needs attention"
    return true,false
end

return Transport
