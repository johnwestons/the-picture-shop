local Config = require("src.config")
local BayDoor = require("src.bay_door")
local BusinessCalendar = require("src.business_calendar")
local CutterPlacement = require("src.cutter_placement")
local CutterZones = require("src.cutter_zones")
local Customer = require("src.customer")
local Interaction = require("src.interaction")
local JobService = require("src.job_service")
local MachineFleet = require("src.machine_fleet")
local Navigation = require("src.navigation")
local PlacementGrid = require("src.placement_grid")
local PalletLogistics = require("src.pallet_logistics")
local PalletJack = require("src.pallet_jack")
local Procurement = require("src.procurement")
local Truck = require("src.truck")
local Technician = require("src.technician")
local WrapperPlacement = require("src.wrapper_placement")
local Wrapper = require("src.wrapper")
local WorldRenderer = require("src.world_renderer")
local Windmill = require("src.windmill")
local WindmillPlacement = require("src.windmill_placement")

local World = {
    player = {
        x = Config.player.spawnX,
        y = Config.player.spawnY,
        speed = Config.player.speed,
        moving = false,
        facing = 1,
        animationClock = 0,
    },
    bayDoor = BayDoor.new(Config.loadingBay),
    truck = Truck.new(Config.truck),
    customer = Customer.new(Config.customer),
    vendor = Customer.new(Config.vendor),
    selectedInteraction = nil,
    placementSelection = nil,
}

local function movementObstacles(state, excludeJack, inflate, excludeCutter, excludeWrapper,
    excludedPalletId, excludeWindmill)
    inflate = inflate or { x = 0, y = 0 }
    if type(inflate) == "number" then inflate = { x = inflate, y = inflate } end
    local obstacles = {}
    if not excludeCutter and MachineFleet.isInstalled(state, "polar_115") then
        local cutterObstacle = CutterPlacement.obstacle(state, Config.cutterPlacement)
        if cutterObstacle then obstacles[#obstacles + 1] = cutterObstacle end
    end
    if not excludeWrapper and MachineFleet.isInstalled(state, "skid_wrapper") then
        local wrapperObstacle = WrapperPlacement.obstacle(state, Config.wrapperPlacement)
        if wrapperObstacle then obstacles[#obstacles + 1] = wrapperObstacle end
    end
    if not excludeWindmill and MachineFleet.isInstalled(state, "heidelberg_10x15") then
        local pressObstacle = WindmillPlacement.obstacle(state, Config.windmillPlacement)
        if pressObstacle then obstacles[#obstacles + 1] = pressObstacle end
    end
    local customerObstacle = World.customer:getObstacle()
    if customerObstacle then obstacles[#obstacles + 1] = customerObstacle end
    local vendorObstacle = World.vendor:getObstacle()
    if vendorObstacle then obstacles[#obstacles + 1] = vendorObstacle end
    local technicianObstacle = Technician.obstacle(state)
    if technicianObstacle then obstacles[#obstacles + 1] = technicianObstacle end
    local bayObstacle = World.bayDoor:getObstacle()
    if bayObstacle then obstacles[#obstacles + 1] = bayObstacle end
    local truckObstacle = World.truck:getObstacle()
    if truckObstacle then obstacles[#obstacles + 1] = truckObstacle end
    for _, obstacle in ipairs(PalletLogistics.obstacles(state,
        Config.palletLogistics.collisionHalfWidth,
        Config.palletLogistics.collisionHalfHeight,
        excludedPalletId)) do
        obstacles[#obstacles + 1] = obstacle
    end
    if not excludeJack then
        local jackObstacle = PalletJack.obstacle(state, Config.palletJack)
        if jackObstacle then obstacles[#obstacles + 1] = jackObstacle end
    end
    if inflate.x > 0 or inflate.y > 0 then
        for _, obstacle in ipairs(obstacles) do
            if obstacle.halfWidth and obstacle.halfHeight then
                obstacle.halfWidth = obstacle.halfWidth + inflate.x
                obstacle.halfHeight = obstacle.halfHeight + inflate.y
            else
                obstacle.radius = obstacle.radius + math.max(inflate.x, inflate.y)
            end
        end
    end
    return obstacles
end

function World.isPalletPlacementClear(state, assets, x, y, excludedPalletId)
    local halfWidth = Config.palletLogistics.collisionHalfWidth
    local halfHeight = Config.palletLogistics.collisionHalfHeight
    if not Navigation.isAreaWalkable(assets, x, y, halfWidth, halfHeight) then return false end
    return Navigation.isWalkable(assets, x, y, movementObstacles(state, false,
        { x = halfWidth, y = halfHeight }, false, false, excludedPalletId))
end

local function isMachinePlacementClear(state, assets, kind, x, y)
    if not assets then return false end
    local config = kind == "cutter" and Config.cutterPlacement
        or (kind == "wrapper" and Config.wrapperPlacement or Config.windmillPlacement)
    if not Navigation.isAreaWalkable(assets, x, y,
        config.collisionHalfWidth, config.collisionHalfHeight)
    then return false end
    local obstacles = movementObstacles(state, true, {
        x = config.collisionHalfWidth,
        y = config.collisionHalfHeight,
    }, kind == "cutter", kind == "wrapper", nil, kind == "windmill")
    return Navigation.isWalkable(assets, x, y, obstacles)
end

local function activePlacement(state)
    if state and state.cutter and state.cutter.moving then
        return "cutter", state.cutter.x, state.cutter.y
    elseif state and state.wrapper and state.wrapper.moving then
        return "wrapper", state.wrapper.x, state.wrapper.y
    elseif state and state.windmill and state.windmill.moving then
        return "windmill", state.windmill.x, state.windmill.y
    end
    local jack = state and PalletJack.ensure(state, Config.palletJack)
    if jack and jack.operating and jack.carriedPalletId then
        local x, y = PalletJack.dropPosition(state, Config.palletJack)
        return "pallet", x, y
    end
end

function World.placementGridSnapshot(state, assets)
    local kind, centerX, centerY = activePlacement(state)
    if not kind then World.placementSelection = nil; return nil end
    assets = assets or World._assets
    local carriedId = kind == "pallet" and state.palletJack.carriedPalletId or nil
    local cells, snappedX, snappedY = PlacementGrid.cells(
        centerX, centerY, Config.placementGrid, function(x, y)
            if kind == "pallet" then
                return World.isPalletPlacementClear(state, assets, x, y, carriedId)
            end
            return isMachinePlacementClear(state, assets, kind, x, y)
        end)
    local selected = World.placementSelection
    if not selected or selected.kind ~= kind then
        selected = nil
        for _, cell in ipairs(cells) do
            if cell.x == snappedX and cell.y == snappedY and cell.valid then
                selected = { kind = kind, x = cell.x, y = cell.y }
                break
            end
        end
    end
    return { kind = kind, cells = cells, selected = selected, config = Config.placementGrid }
end

function World.selectPlacement(state, assets, x, y)
    local snapshot = World.placementGridSnapshot(state, assets)
    if not snapshot then return false end
    local cell = PlacementGrid.hit(snapshot.cells, x, y, snapshot.config)
    if not cell then return false end
    if not cell.valid then
        state.message = "That red grid space is blocked. Choose a green space."
        return true
    end
    World.placementSelection = { kind = snapshot.kind, x = cell.x, y = cell.y }
    state.message = "Placement selected. Press E to set it down, or choose another green space."
    return true
end

function World.findCutterOutput(state, assets, excludedPalletId)
    return CutterZones.findOutput(state, Config.cutterPlacement, function(x, y)
        return World.isPalletPlacementClear(state, assets, x, y, excludedPalletId)
    end)
end

local function interactables()
    local targets = {
        computer = Config.interactables.computer,
    }
    local customerInteraction = World.customer:getInteraction()
    if customerInteraction then targets.customer = customerInteraction end
    local vendorInteraction = World.vendor:getInteraction()
    if vendorInteraction then
        vendorInteraction.prompt = "E: talk to the " .. Procurement.category(World._state and World._state.vendorCategory).name:lower() .. " salesman"
        targets.vendor = vendorInteraction
    end
    targets.loadingBayDoor = World.bayDoor:getInteraction()
    local truckInteraction = World.truck:getInteraction()
    if truckInteraction then targets.truckCargoDoor = truckInteraction end
    if World._state then
        local jack = PalletJack.ensure(World._state, Config.palletJack)
        local jackReady = jack.operating and not jack.carriedPalletId
        if MachineFleet.isInstalled(World._state, "polar_115") then
            targets.cutter = CutterPlacement.interaction(World.player, World._state,
                Config.cutterPlacement, jackReady)
        end
        if MachineFleet.isInstalled(World._state, "skid_wrapper") then
            targets.skidWrapper = WrapperPlacement.interaction(World.player, World._state,
                Config.wrapperPlacement, jackReady)
        end
        if MachineFleet.isInstalled(World._state, "heidelberg_10x15") then
            targets.windmill = WindmillPlacement.interaction(World.player, World._state,
                Config.windmillPlacement, jackReady)
        end
        targets.palletJack = PalletJack.interaction(World.player, World._state, Config.palletJack)
        if jackReady then
            local cutter = CutterPlacement.ensure(World._state, Config.cutterPlacement)
            local wrapper = WrapperPlacement.ensure(World._state, Config.wrapperPlacement)
            local windmill = WindmillPlacement.ensure(World._state, Config.windmillPlacement)
            local cutterNear = (jack.x - cutter.x) ^ 2 + (jack.y - cutter.y) ^ 2
                <= Config.cutterPlacement.interactionRadius ^ 2
            local wrapperNear = (jack.x - wrapper.x) ^ 2 + (jack.y - wrapper.y) ^ 2
                <= Config.wrapperPlacement.interactionRadius ^ 2
            local windmillNear = (jack.x - windmill.x) ^ 2 + (jack.y - windmill.y) ^ 2
                <= Config.windmillPlacement.interactionRadius ^ 2
            if cutterNear then
                targets.palletJack.prompt = "E: park pallet jack  |  M: RELOCATE CUTTER"
            elseif wrapperNear then
                targets.palletJack.prompt = "E: park pallet jack  |  M: RELOCATE WRAPPER"
            elseif windmillNear then
                targets.palletJack.prompt = "E: park pallet jack  |  M: RELOCATE WINDMILL"
            end
        end
    end
    return targets
end

function World.load(position)
    World.player.x = position and position.x or Config.player.spawnX
    World.player.y = position and position.y or Config.player.spawnY
    World.player.animationClock = 0
    World.bayDoor:reset()
    World.truck:reset()
    World.customer:reset(true)
    World.vendor:reset(true)
    World.selectedInteraction = nil
    World.placementSelection = nil
end

local function activeJobById(state, jobId)
    if not state or not state.jobs or type(state.jobs.active) ~= "table" then return nil end
    for _, job in ipairs(state.jobs.active) do
        if job.id == jobId then return job end
    end
    return nil
end

local function scheduleTruck(state)
    if not state or World.truck.state ~= "absent" then return false end
    local pickup = JobService.nextPickup(state)
    if pickup and World.truck:schedule(pickup.id, "pickup") then
        JobService.schedulePickup(pickup, os.time())
        state.message = "Customer pickup scheduled for " .. pickup.id .. "."
        return true
    end
    local machineOrder = MachineFleet.nextInbound(state)
    if machineOrder then
        if World.truck:schedule(machineOrder.id, "machine_delivery") then
            machineOrder.delivery.status = "scheduled"
            machineOrder.delivery.scheduledAt = os.time()
            state.message = "Machine flatbed delivery scheduled for " .. machineOrder.id .. "."
            return true
        end
        return false
    end
    local purchase = Procurement.nextInbound(state)
    if purchase then
        if World.truck:schedule(purchase.id, "vendor_delivery") then
            purchase.delivery.status = "scheduled"
            state.message = "Vendor delivery scheduled for " .. purchase.id .. "."
            return true
        end
        return false
    end
    local activeJobs = state.jobs and state.jobs.active or {}
    for _, job in ipairs(activeJobs) do
        local deliveryStatus = job.delivery and job.delivery.status
        if job.status == "awaiting_delivery" and deliveryStatus ~= "received"
            and JobService.deliveryReady(state, job)
        then
            if World.truck:schedule(job.id, "delivery") then
                job.delivery = job.delivery or {}
                job.delivery.status = "scheduled"
                state.message = "Inbound truck scheduled for " .. job.id .. "."
                return true
            end
            return false
        end
    end
    return false
end

local function updateTruck(dt, state)
    local saveNeeded = scheduleTruck(state)
    local truckJobId, truckMode = World.truck.jobId, World.truck.mode
    local event = World.truck:update(dt, World.bayDoor.state)
    if not event then return saveNeeded end
    local job = activeJobById(state, truckJobId)
    local purchase = Procurement.orderById(state, truckJobId)
    local machineOrder = truckMode == "machine_delivery" and MachineFleet.orderById(state, truckJobId) or nil
    local pickup = truckMode == "pickup" and job or nil
    if event == "request_bay_open" then
        if World.bayDoor.state == "closed" then World.bayDoor:open() end
        if state then
            state.message = pickup and "Pickup truck arrived. Opening the loading bay..."
                or (machineOrder and "Machine flatbed arrived. Opening the loading bay..."
                    or "Delivery truck arrived. Opening the loading bay...")
        end
    elseif event == "backing_started" then
        if pickup then
            JobService.setPickupStatus(pickup, "backing")
        elseif job and job.delivery then job.delivery.status = "backing" end
        if purchase and purchase.delivery then purchase.delivery.status = "backing" end
        if machineOrder then machineOrder.delivery.status = "backing" end
        if state then
            state.message = pickup and "The customer pickup truck is backing into the loading bay."
                or (machineOrder and "The machine flatbed is backing into the loading bay."
                    or "The delivery truck is backing into the loading bay.")
        end
        saveNeeded = true
    elseif event == "parked" then
        if pickup then
            JobService.setPickupStatus(pickup, "at_bay", "arrivedAt", os.time())
        elseif job and job.delivery then job.delivery.status = "at_bay" end
        if purchase and purchase.delivery then purchase.delivery.status = "at_bay" end
        if machineOrder then
            machineOrder.delivery.status = "at_bay"
            machineOrder.delivery.arrivedAt = os.time()
        end
        if state then
            state.message = pickup
                and "Pickup truck parked. Open its rear cargo door and load the wrapped pallets."
                or (machineOrder
                    and "Machine flatbed parked. Open its manifest and unload the machine."
                    or "Truck parked. Open its rear cargo door to unload.")
        end
        saveNeeded = true
    elseif event == "cargo_opened" then
        if pickup then JobService.setPickupStatus(pickup, "cargo_open") end
        if state then state.message = pickup
            and "Pickup truck cargo door open. Load every wrapped pallet on the manifest."
            or "Truck cargo door open. Review the manifest and unload each pallet." end
        saveNeeded = pickup ~= nil or saveNeeded
    elseif event == "cargo_closed" then
        local received = (job and job.delivery and job.delivery.status == "received")
            or (purchase and purchase.delivery and purchase.delivery.status == "received")
        local pickupLoaded = pickup and JobService.remainingPickup(state, pickup.id) == 0
        if (received or pickupLoaded) and World.truck:depart() then
            if pickup then JobService.setPickupStatus(pickup, "departing") end
            if state then state.message = pickup
                and "Pickup cargo secured. The customer truck is departing."
                or "Cargo secured. The empty truck is departing." end
            saveNeeded = pickup ~= nil or saveNeeded
        elseif state then
            state.message = "Truck cargo door closed."
        end
    elseif event == "departed" then
        if World.bayDoor.state == "open" then World.bayDoor:close() end
        if pickup then
            local completed, completedJob, payment = JobService.completePickup(state, pickup.id, os.time())
            if completed then
                state.message = string.format("%s picked up and paid $%d. Closing the loading bay door...",
                    completedJob.id, payment)
                saveNeeded = true
            else
                state.message = "Pickup truck left, but the job could not be archived."
            end
        elseif state then
            state.message = "The truck left. Closing the loading bay door..."
        end
    end
    return saveNeeded
end

function World.update(dt, directionX, directionY, assets, state)
    World._assets = assets
    if directionX ~= 0 or directionY ~= 0 then World.placementSelection = nil end
    World._state = state
    local player = World.player
    local jack = PalletJack.ensure(state, Config.palletJack)
    local cutter = CutterPlacement.ensure(state, Config.cutterPlacement)
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local windmill = WindmillPlacement.ensure(state, Config.windmillPlacement)
    if cutter.moving then
        CutterPlacement.move(state, directionX, directionY, dt, Config.cutterPlacement,
            function(nextX, nextY)
                local halfWidth = Config.cutterPlacement.collisionHalfWidth
                local halfHeight = Config.cutterPlacement.collisionHalfHeight
                local obstacles = movementObstacles(state, false,
                    { x = halfWidth, y = halfHeight }, true)
                return Navigation.canMoveAreaFrom(assets, cutter.x, cutter.y, nextX, nextY,
                    halfWidth, halfHeight, obstacles)
            end)
        jack.x, jack.y = cutter.x, cutter.y + 8
        jack.direction, jack.moving = cutter.direction, cutter.inMotion
        jack.animationClock = jack.animationClock + math.max(0, dt)
        player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack)
        player.moving = cutter.inMotion
        player.facing = player.x < cutter.x and 1 or -1
    elseif wrapper.moving then
        WrapperPlacement.move(state, directionX, directionY, dt, Config.wrapperPlacement,
            function(nextX, nextY)
                local halfWidth = Config.wrapperPlacement.collisionHalfWidth
                local halfHeight = Config.wrapperPlacement.collisionHalfHeight
                return Navigation.canMoveAreaFrom(assets, wrapper.x, wrapper.y, nextX, nextY,
                    halfWidth, halfHeight, movementObstacles(state, false, {
                        x = Config.wrapperPlacement.collisionHalfWidth,
                        y = Config.wrapperPlacement.collisionHalfHeight,
                    }, false, true))
            end)
        jack.x, jack.y = wrapper.x, wrapper.y + 8
        jack.direction, jack.moving = wrapper.direction, wrapper.inMotion
        jack.animationClock = jack.animationClock + math.max(0, dt)
        player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack)
        player.moving = wrapper.inMotion
        player.facing = player.x < wrapper.x and 1 or -1
    elseif windmill.moving then
        WindmillPlacement.move(state, directionX, directionY, dt, Config.windmillPlacement,
            function(nextX, nextY)
                local halfWidth = Config.windmillPlacement.collisionHalfWidth
                local halfHeight = Config.windmillPlacement.collisionHalfHeight
                local obstacles = movementObstacles(state, false, {
                    x = halfWidth, y = halfHeight,
                }, false, false, nil, true)
                if not Navigation.isAreaWalkable(assets, windmill.x, windmill.y, 0, 0) then
                    -- The original spawn used an old floor mask and can sit on
                    -- a newly blocked pixel. Permit controlled recovery motion
                    -- until the machine center reaches the current walkable
                    -- factory floor again.
                    return nextX > halfWidth and nextX < Config.baseWidth - halfWidth
                        and nextY > halfHeight and nextY < Config.baseHeight - halfHeight
                end
                if Navigation.canMoveAreaFrom(assets, windmill.x, windmill.y, nextX, nextY,
                    halfWidth, halfHeight, obstacles)
                then return true end
                -- Older/default placements can begin partly inside the edge of
                -- the walk mask. Let the operator move the machine's center
                -- toward open floor until its full footprint clears the edge.
                if not Navigation.isAreaWalkable(assets, windmill.x, windmill.y,
                    halfWidth, halfHeight)
                then
                    return Navigation.canMoveFrom(assets, windmill.x, windmill.y,
                        nextX, nextY, obstacles)
                        and Navigation.isAreaWalkable(assets, nextX, nextY, 0, 0)
                end
                return false
            end)
        jack.x, jack.y = windmill.x, windmill.y + 8
        jack.direction, jack.moving = windmill.direction, windmill.inMotion
        jack.animationClock = jack.animationClock + math.max(0, dt)
        player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack)
        player.moving = windmill.inMotion
        player.facing = player.x < windmill.x and 1 or -1
    elseif jack.operating then
        PalletJack.move(state, directionX, directionY, dt, Config.palletJack, function(nextX, nextY, loaded)
            local inflate = loaded and {
                x = Config.palletJack.loadedCollisionHalfWidth,
                y = Config.palletJack.loadedCollisionHalfHeight,
            } or {
                x = Config.palletJack.collisionHalfWidth,
                y = Config.palletJack.collisionHalfHeight,
            }
            return Navigation.canMoveAreaFrom(assets, jack.x, jack.y, nextX, nextY,
                inflate.x, inflate.y, movementObstacles(state, true, inflate))
        end)
        player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack)
        player.moving = jack.moving
        player.facing = (jack.direction == "northeast" or jack.direction == "east"
            or jack.direction == "southeast") and 1 or -1
    else
        player.moving = directionX ~= 0 or directionY ~= 0
    end
    if player.moving and not jack.operating and not cutter.moving and not wrapper.moving
        and not windmill.moving
    then
        local length = math.sqrt(directionX * directionX + directionY * directionY)
        local nextX = player.x + directionX / length * player.speed * dt
        local nextY = player.y + directionY / length * player.speed * dt
        if Navigation.canMoveFrom(assets, player.x, player.y, nextX, nextY,
            movementObstacles(state, false))
        then
            player.x = nextX
            player.y = nextY
        end
        if directionX ~= 0 then player.facing = directionX < 0 and -1 or 1 end
    end

    player.animationClock = player.animationClock + dt
    local doorEvent = World.bayDoor:update(dt)
    if doorEvent == "opened" and state then
        state.message = "Loading bay door open. The parking lot is visible."
    elseif doorEvent == "closed" and state then
        state.message = "Loading bay door closed."
    end
    local saveNeeded = updateTruck(dt, state)
    PalletLogistics.update(state, dt, Config.palletLogistics.unloadDuration)
    -- Only one reception visitor advances at a time. The other visitor keeps
    -- their full cooldown while the entrance, lounge, or desk is occupied.
    local receptionClosed = BusinessCalendar.isWeekend(state)
    local customerEvent = World.customer:update(dt, player,
        receptionClosed or World.vendor:isPresent())
    if customerEvent == "arrived" and state then
        state.message = "A customer is waiting at reception with a cutting job."
    elseif customerEvent == "timed_out" and state then
        state.message = "The client waited five minutes without being seen and is leaving."
    elseif customerEvent == "exited" and state then
        state.message = World.customer.decision == "timed_out"
            and "The client left after waiting five minutes."
            or (World.customer.decision == "accepted"
                and "The customer left after you accepted the job."
                or "The customer left after you declined the job.")
        -- Bring the next business client into the arrival queue after this
        -- visit so the configured roster is experienced during one session.
        World.customer:reset(false)
    end
    local category = Procurement.category(state and state.vendorCategory)
    World.vendor.character = category.character
    local vendorEvent = World.vendor:update(dt, player,
        receptionClosed or World.customer:isPresent())
    if vendorEvent == "arrived" and state then
        state.message = category.salesman .. " is waiting at reception with the " .. category.name:lower() .. " catalog."
    elseif vendorEvent == "exited" and state then
        state.vendorCategory = state.vendorCategory % #Procurement.categories + 1
        World.vendor:reset(false)
        state.message = "The salesman left. Another supplier representative will visit later."
    end
    if Technician.update(dt, state, World.customer:isPresent() or World.vendor:isPresent()) then
        saveNeeded = true
    end
    World.selectedInteraction = Interaction.select(player, interactables())
    return saveNeeded
end

function World.draw(assets, characterAssets, state, mouseX, mouseY)
    return WorldRenderer.draw(World, assets, characterAssets, state, mouseX, mouseY)
end

function World.prompt()
    return Interaction.prompt(World.selectedInteraction)
end

function World.getInteraction()
    return World.selectedInteraction
end

function World.beginCustomerReview()
    return World.selectedInteraction
        and World.selectedInteraction.kind == "customer"
        and World.customer:beginReview()
        or false
end

function World.cancelCustomerReview(state)
    if not World.customer:cancelReview() then return false end
    if state then state.message = "The customer is still waiting whenever you are ready to review the job." end
    return true
end

function World.beginVendorReview()
    return World.selectedInteraction and World.selectedInteraction.kind == "vendor" and World.vendor:beginReview() or false
end

function World.cancelVendorReview(state)
    if not World.vendor:cancelReview() then return false end
    if state then state.message = "The salesperson is still waiting if you want to reopen the catalog." end
    return true
end

function World.resolveVendor(state, decision)
    decision = decision == "declined" and "declined" or "accepted"
    if not World.vendor:resolve(decision) then return false end
    if state then
        state.message = decision == "declined"
            and "You said no thanks. The supplier representative is heading out."
            or "The supplier representative is heading out."
    end
    return true
end

function World.resolveCustomer(decision, state)
    if not World.customer:resolve(decision) then return false end
    if state then
        state.message = decision == "accepted"
            and "Job accepted. The customer is heading out."
            or "Job declined. The customer is heading out."
    end
    return true
end

function World.toggleBayDoor(state)
    if World.bayDoor.state == "open" and World.truck:blocksBayClosure() then
        if state then state.message = "The truck is occupying the bay. Keep the loading door open." end
        return false
    end
    if not World.bayDoor:toggle() then
        if state then state.message = "Wait for the loading bay door to finish moving." end
        return false
    end
    if state then
        state.message = World.bayDoor.state == "opening"
            and "Opening the loading bay door..."
            or "Closing the loading bay door..."
    end
    return true
end

function World.toggleTruckCargoDoor(state)
    if World.truck.mode == "machine_delivery" then
        if state then state.message = "This flatbed has no cargo door. Open its delivery manifest instead." end
        return false
    end
    if not World.truck:toggleCargoDoor() then
        if state then state.message = "Wait for the truck cargo door to finish moving." end
        return false
    end
    if state then
        state.message = World.truck.state == "cargo_opening"
            and "Opening the truck cargo door..."
            or "Closing the truck cargo door..."
    end
    return true
end

function World.openTruckInventory(state)
    if World.truck.mode == "machine_delivery" then
        return World.truck.state == "parked_closed"
            and MachineFleet.orderById(state, World.truck.jobId) ~= nil
    end
    if World.truck.state ~= "cargo_open" then return false end
    local job = activeJobById(state, World.truck.jobId)
    return job ~= nil or Procurement.orderById(state, World.truck.jobId) ~= nil
end

function World.unloadTruckMachine(state, machineId)
    if World.truck.mode ~= "machine_delivery" or World.truck.state ~= "parked_closed" then
        if state then state.message = "Wait for the machine flatbed to park before unloading." end
        return false
    end
    local succeeded, machine, remaining = MachineFleet.unloadDelivery(
        state, World.truck.jobId, machineId, os.time())
    if state then
        state.message = succeeded
            and string.format("Unloaded %s. Unit %s is now %s.", machine.name, machine.id, machine.status)
            or tostring(machine)
    end
    return succeeded, machine, remaining
end

function World.unloadTruckPallet(state, palletId)
    if World.truck.mode == "pickup" then return false, "Use the outbound loading manifest for this truck." end
    if World.truck.state ~= "cargo_open" then
        if state then state.message = "Open the truck cargo door before unloading." end
        return false
    end
    local succeeded, pallet, remaining = PalletLogistics.unload(
        state,
        World.truck.jobId,
        palletId,
        Config.palletLogistics.spawnPoints,
        Config.palletLogistics.unloadOrigin
    )
    if state then
        state.message = succeeded
            and string.format("Unloaded %s. %d pallet(s) remain in the truck.", pallet.id, remaining)
            or tostring(pallet)
    end
    return succeeded, pallet, remaining
end

function World.loadPickupPallet(state, palletId)
    if World.truck.state ~= "cargo_open" or World.truck.mode ~= "pickup" then
        if state then state.message = "Open the scheduled pickup truck before loading pallets." end
        return false
    end
    local succeeded, pallet, remaining = JobService.loadForPickup(
        state, World.truck.jobId, palletId, os.time())
    if state then
        state.message = succeeded
            and string.format("Loaded %s. %d pallet(s) remain on the floor.", pallet.id, remaining)
            or tostring(pallet)
    end
    return succeeded, pallet, remaining
end

function World.closeTruckAfterUnload(state)
    if World.truck.mode == "machine_delivery" then
        if World.truck.state ~= "parked_closed" then return false end
        if MachineFleet.remainingOnTruck(state, World.truck.jobId) > 0 then
            if state then state.message = "Unload the machine before releasing the flatbed truck." end
            return false
        end
        local departing = World.truck:depart()
        if departing and state then state.message = "The empty machine flatbed is departing." end
        return departing
    end
    if World.truck.state ~= "cargo_open" then return false end
    if World.truck.mode == "pickup" then
        if JobService.remainingPickup(state, World.truck.jobId) > 0 then
            if state then state.message = "Load every pickup pallet before closing the cargo door." end
            return false
        end
        return World.toggleTruckCargoDoor(state)
    end
    if PalletLogistics.remainingOnTruck(state, World.truck.jobId) > 0 then
        if state then state.message = "Unload every pallet before closing the cargo door." end
        return false
    end
    return World.toggleTruckCargoDoor(state)
end

function World.handlePalletJack(state, assets)
    local grid = World.placementGridSnapshot(state, assets)
    local selected = World.placementSelection or (grid and grid.selected)
    local placementX = selected and selected.kind == "pallet" and selected.x or nil
    local placementY = selected and selected.kind == "pallet" and selected.y or nil
    local succeeded, action, pallet = PalletJack.use(state, Config.palletJack, function(x, y)
        return World.isPalletPlacementClear(state, assets, x, y)
    end, placementX, placementY)
    if not succeeded then
        if state then state.message = action == "blocked"
            and "There is not enough clear floor space to lower this pallet."
            or "The carried pallet could not be found." end
        return false
    end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if action == "mounted" then
        World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
        state.message = "Operating pallet jack. Drive with movement keys; E lifts or lowers pallets."
    elseif action == "lifted" then
        World.placementSelection = nil
        state.message = "Lifted " .. pallet.id .. ". Drive it, choose a green grid space, then press E."
    elseif action == "lowered" then
        World.placementSelection = nil
        state.message = "Lowered " .. pallet.id .. " at its new warehouse position."
    else
        state.message = "Pallet jack parked."
    end
    return true, action, pallet
end

function World.parkPalletJack(state)
    if not PalletJack.park(state, Config.palletJack) then
        if state then state.message = "Lower the carried pallet before parking the jack." end
        return false
    end
    if state then state.message = "Pallet jack parked." end
    return true
end

local function cutterHasPaper(state)
    for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.location == "at_cutter" then return true end
        end
    end
    return false
end

function World.beginCutterMove(state)
    if not MachineFleet.isInstalled(state, "polar_115") then return false end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if not jack.operating or jack.carriedPalletId then
        state.message = "Operate an empty pallet jack before relocating the cutter."
        return false
    end
    local cutter = CutterPlacement.ensure(state, Config.cutterPlacement)
    if (jack.x - cutter.x) ^ 2 + (jack.y - cutter.y) ^ 2
        > Config.cutterPlacement.interactionRadius ^ 2
    then
        state.message = "Drive the empty pallet jack beside the cutter before relocating it."
        return false
    end
    if cutterHasPaper(state) then
        state.message = "Unload the paper and clear the cutting bed before relocating the cutter."
        return false
    end
    if not CutterPlacement.beginMove(state, Config.cutterPlacement) then return false end
    World.placementSelection = nil
    jack.x, jack.y, jack.direction = cutter.x, cutter.y + 8, cutter.direction
    World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
    state.message = "Cutter is on the pallet jack. Move, choose a green grid space, then press E. Q rotates."
    return true
end

function World.rotateCutter(state)
    local succeeded, direction = CutterPlacement.rotate(state, Config.cutterPlacement)
    if not succeeded then return false end
    if state.cutter.moving then
        World.player.x, World.player.y = CutterPlacement.operatorPosition(state, Config.cutterPlacement)
    end
    state.message = "Cutter rotated " .. direction .. "."
    return true
end

function World.placeCutter(state, assets)
    local explicit = World.placementSelection
    local grid = World.placementGridSnapshot(state, assets)
    local target = explicit or (grid and grid.selected)
    local originalX, originalY = state.cutter.x, state.cutter.y
    local x, y = originalX, originalY
    if target and target.kind == "cutter" then x, y = target.x, target.y end
    if not isMachinePlacementClear(state, assets or World._assets, "cutter", x, y) then
        if explicit then
            state.message = "The cutter cannot be placed there. Choose a green grid space."
            return false
        end
        x, y = originalX, originalY
    end
    state.cutter.x, state.cutter.y = x, y
    if not CutterPlacement.place(state, Config.cutterPlacement) then return false end
    World.placementSelection = nil
    local jack = PalletJack.ensure(state, Config.palletJack)
    jack.moving = false
    jack.x, jack.y = state.cutter.x, state.cutter.y + 42
    World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
    state.message = "Cutter locked in its new floor position."
    return true
end

function World.cutterSnapshot(state)
    return CutterPlacement.snapshot(state, Config.cutterPlacement)
end

function World.beginWrapperMove(state)
    if not MachineFleet.isInstalled(state, "skid_wrapper") then return false end
    if not Wrapper.canRelocate(state) then return false end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if not jack.operating or jack.carriedPalletId then
        state.message = "Operate an empty pallet jack before relocating the skid wrapper."
        return false
    end
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    if (jack.x - wrapper.x) ^ 2 + (jack.y - wrapper.y) ^ 2
        > Config.wrapperPlacement.interactionRadius ^ 2
    then
        state.message = "Drive the empty pallet jack beside the skid wrapper before relocating it."
        return false
    end
    if not WrapperPlacement.beginMove(state, Config.wrapperPlacement) then return false end
    World.placementSelection = nil
    jack.x, jack.y, jack.direction = wrapper.x, wrapper.y + 8, wrapper.direction
    World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
    state.message = "Skid wrapper is on the pallet jack. Move, choose a green grid space, then press E. Q rotates."
    return true
end

function World.wrapperNearby(state)
    if not MachineFleet.isInstalled(state, "skid_wrapper") then return false end
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local dx, dy = World.player.x - wrapper.x, World.player.y - wrapper.y
    return dx * dx + dy * dy <= Config.wrapperPlacement.interactionRadius ^ 2
end

function World.cutterNearby(state)
    if not MachineFleet.isInstalled(state, "polar_115") then return false end
    local cutter = CutterPlacement.ensure(state, Config.cutterPlacement)
    local jack = PalletJack.ensure(state, Config.palletJack)
    return (jack.x - cutter.x) ^ 2 + (jack.y - cutter.y) ^ 2
        <= Config.cutterPlacement.interactionRadius ^ 2
end

function World.rotateWrapper(state)
    local succeeded, direction = WrapperPlacement.rotate(state, Config.wrapperPlacement)
    if not succeeded then return false end
    if state.wrapper.moving then World.player.x, World.player.y = WrapperPlacement.operatorPosition(state, Config.wrapperPlacement) end
    state.message = "Skid wrapper rotated " .. direction .. "."
    return true
end

function World.placeWrapper(state, assets)
    local explicit = World.placementSelection
    local grid = World.placementGridSnapshot(state, assets)
    local target = explicit or (grid and grid.selected)
    local originalX, originalY = state.wrapper.x, state.wrapper.y
    local x, y = originalX, originalY
    if target and target.kind == "wrapper" then x, y = target.x, target.y end
    if not isMachinePlacementClear(state, assets or World._assets, "wrapper", x, y) then
        if explicit then
            state.message = "The skid wrapper cannot be placed there. Choose a green grid space."
            return false
        end
        x, y = originalX, originalY
    end
    state.wrapper.x, state.wrapper.y = x, y
    if not WrapperPlacement.place(state, Config.wrapperPlacement) then return false end
    World.placementSelection = nil
    local jack = PalletJack.ensure(state, Config.palletJack)
    jack.moving = false
    jack.x, jack.y = state.wrapper.x, state.wrapper.y + 46
    World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
    state.message = "Skid wrapper locked in its new floor position."
    return true
end

function World.wrapperSnapshot(state)
    return WrapperPlacement.snapshot(state, Config.wrapperPlacement)
end

function World.beginWindmillMove(state)
    if not MachineFleet.isInstalled(state, "heidelberg_10x15") then return false end
    local process = Windmill.ensure(state)
    if process.status ~= "idle" or process.palletId then
        state.message = "Unload the press and return the Windmill to idle before relocating it."
        return false
    end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if not jack.operating or jack.carriedPalletId then
        state.message = "Operate an empty pallet jack before relocating the Windmill."
        return false
    end
    local item = WindmillPlacement.ensure(state, Config.windmillPlacement)
    if (jack.x - item.x) ^ 2 + (jack.y - item.y) ^ 2
        > Config.windmillPlacement.interactionRadius ^ 2
    then
        state.message = "Drive the empty pallet jack beside the Windmill before relocating it."
        return false
    end
    if not WindmillPlacement.beginMove(state, Config.windmillPlacement) then return false end
    World.placementSelection = nil
    jack.x, jack.y, jack.direction = item.x, item.y + 8, item.direction
    World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
    state.message = "Windmill is on the pallet jack. Move, choose a green grid space, then press E. Q rotates."
    return true
end

function World.windmillNearby(state)
    if not MachineFleet.isInstalled(state, "heidelberg_10x15") then return false end
    local item = WindmillPlacement.ensure(state, Config.windmillPlacement)
    local jack = PalletJack.ensure(state, Config.palletJack)
    return (jack.x - item.x) ^ 2 + (jack.y - item.y) ^ 2
        <= Config.windmillPlacement.interactionRadius ^ 2
end

function World.rotateWindmill(state)
    local succeeded, direction = WindmillPlacement.rotate(state, Config.windmillPlacement)
    if not succeeded then return false end
    state.message = "Windmill rotated " .. direction .. "."
    return true
end

function World.placeWindmill(state, assets)
    local explicit = World.placementSelection
    local grid = World.placementGridSnapshot(state, assets)
    local target = explicit or (grid and grid.selected)
    local originalX, originalY = state.windmill.x, state.windmill.y
    local x, y = originalX, originalY
    if target and target.kind == "windmill" then x, y = target.x, target.y end
    if not isMachinePlacementClear(state, assets or World._assets, "windmill", x, y) then
        if explicit then
            state.message = "The Windmill cannot be placed there. Choose a green grid space."
            return false
        end
        x, y = originalX, originalY
    end
    state.windmill.x, state.windmill.y = x, y
    if not WindmillPlacement.place(state, Config.windmillPlacement) then return false end
    World.placementSelection = nil
    local jack = PalletJack.ensure(state, Config.palletJack)
    jack.moving = false
    jack.x, jack.y = state.windmill.x, state.windmill.y + 52
    World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
    state.message = "Windmill locked in its new floor position."
    return true
end

function World.windmillSnapshot(state)
    return WindmillPlacement.snapshot(state, Config.windmillPlacement)
end

function World.palletJackSnapshot(state)
    return PalletJack.snapshot(state, Config.palletJack)
end

function World.palletsSnapshot(state)
    return PalletLogistics.physicalPallets(state)
end

function World.palletTooltipAt(state, x, y)
    local hovered = PalletLogistics.hovered(state, x, y)
    if not hovered then
        local carried = PalletJack.carriedItem(state, Config.palletJack)
        if carried and x >= carried.x - 58 and x <= carried.x + 58
            and y >= carried.y - 92 and y <= carried.y + 12
        then hovered = carried end
    end
    return PalletLogistics.tooltip(hovered)
end

function World.bayDoorSnapshot()
    return World.bayDoor:snapshot()
end

function World.customerSnapshot()
    return World.customer:snapshot()
end

function World.truckSnapshot()
    return World.truck:snapshot()
end

function World.snapshot()
    return { x = World.player.x, y = World.player.y }
end

return World
