local Config = require("src.config")
local BayDoor = require("src.bay_door")
local BusinessCalendar = require("src.business_calendar")
local CutterPlacement = require("src.cutter_placement")
local CutterZones = require("src.cutter_zones")
local Customer = require("src.customer")
local Interaction = require("src.interaction")
local JobService = require("src.job_service")
local Machine = require("src.machine")
local MachineFleet = require("src.machine_fleet")
local MachinePose = require("src.machine_pose")
local MultiplayerCapabilities = require("src.multiplayer_capabilities")
local Navigation = require("src.navigation")
local PlacementGrid = require("src.placement_grid")
local PalletLogistics = require("src.pallet_logistics")
local PalletJack = require("src.pallet_jack")
local PlayerController = require("src.player_controller")
local Procurement = require("src.procurement")
local Truck = require("src.truck")
local Technician = require("src.technician")
local WrapperPlacement = require("src.wrapper_placement")
local Wrapper = require("src.wrapper")
local WorldRenderer = require("src.world_renderer")
local Windmill = require("src.windmill")
local WindmillPlacement = require("src.windmill_placement")
local Forklift = require("src.forklift")
local WarehouseGameplay = require("src.warehouse_gameplay")
local WarehouseLayout = require("src.warehouse_layout")
local WarehouseConstruction = require("src.warehouse_construction")

local World = {
    player = {
        id = nil,
        character = Config.player.character,
        x = Config.player.spawnX,
        y = Config.player.spawnY,
        speed = Config.player.speed,
        moving = false,
        facing = 1,
        velocityX = 0,
        velocityY = 0,
        animationDistance = 0,
        idleClock = 0,
        interactionClock = 0,
    },
    bayDoor = BayDoor.new(Config.loadingBay),
    truck = Truck.new(Config.truck),
    customer = Customer.new(Config.customer),
    vendor = Customer.new(Config.vendor),
    selectedInteraction = nil,
    placementSelection = nil,
}

local function movementObstacles(state, excludeJack, inflate, excludeCutter, excludeWrapper,
    excludedPalletId, excludeWindmill, excludeForklift)
    inflate = inflate or { x = 0, y = 0 }
    if type(inflate) == "number" then inflate = { x = inflate, y = inflate } end
    local obstacles = {}
    local firstCutter = MachineFleet.installedUnits(state, "polar_115")[1]
    local firstWrapper = MachineFleet.installedUnits(state, "skid_wrapper")[1]
    local firstWindmill = MachineFleet.installedUnits(state, "heidelberg_10x15")[1]
    if not excludeCutter and firstCutter and not firstCutter.world then
        local cutterObstacle = CutterPlacement.obstacle(state, Config.cutterPlacement)
        if cutterObstacle then obstacles[#obstacles + 1] = cutterObstacle end
    end
    if not excludeWrapper and firstWrapper and not firstWrapper.world then
        local wrapperObstacle = WrapperPlacement.obstacle(state, Config.wrapperPlacement)
        if wrapperObstacle then obstacles[#obstacles + 1] = wrapperObstacle end
    end
    if not excludeWindmill and firstWindmill and not firstWindmill.world then
        local pressObstacle = WindmillPlacement.obstacle(state, Config.windmillPlacement)
        if pressObstacle then obstacles[#obstacles + 1] = pressObstacle end
    end
    for _, item in ipairs(MachineFleet.installedUnits(state)) do
        if item.world and not item.world.moving then
            local config = Config[MachineFleet.definition(item.modelId).placementKey .. "Placement"]
            obstacles[#obstacles + 1] = { x = item.world.x, y = item.world.y - 8,
                halfWidth = config.collisionHalfWidth, halfHeight = config.collisionHalfHeight }
        end
    end
    local customerObstacle = World.customer:getObstacle()
    if customerObstacle then obstacles[#obstacles + 1] = customerObstacle end
    local vendorObstacle = World.vendor:getObstacle()
    if vendorObstacle then obstacles[#obstacles + 1] = vendorObstacle end
    local technicianObstacle = Technician.obstacle(state)
    if technicianObstacle then obstacles[#obstacles + 1] = technicianObstacle end
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
    if not excludeForklift then
        local liftObstacle = Forklift.obstacle(state, Config.forklift)
        if liftObstacle then obstacles[#obstacles + 1] = liftObstacle end
    end
    for _, obstacle in ipairs(WarehouseLayout.obstacles(state)) do obstacles[#obstacles + 1] = obstacle end
    local builder = WarehouseConstruction.worker(state)
    if builder then obstacles[#obstacles + 1] = {x=builder.x,y=builder.y,radius=14,kind="construction_worker"} end
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
    assets = WarehouseGameplay.assets(assets or World._assets, state)
    local halfWidth = Config.palletLogistics.collisionHalfWidth
    local halfHeight = Config.palletLogistics.collisionHalfHeight
    if not Navigation.isAreaWalkable(assets, x, y, halfWidth, halfHeight) then return false end
    return Navigation.isWalkable(assets, x, y, movementObstacles(state, false,
        { x = halfWidth, y = halfHeight }, false, false, excludedPalletId))
end

local function isMachinePlacementClear(state, assets, kind, x, y)
    assets = WarehouseGameplay.assets(assets or World._assets, state)
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

local function activeMachineKind(state)
    if state and state.cutter and state.cutter.moving then return "cutter" end
    if state and state.wrapper and state.wrapper.moving then return "wrapper" end
    if state and state.windmill and state.windmill.moving then return "windmill" end
end

local function moveNetworkAttachedMachine(player, dt, directionX, directionY, assets, state)
    local kind = activeMachineKind(state)
    if not kind then return false end
    local placement = kind == "cutter" and CutterPlacement
        or kind == "wrapper" and WrapperPlacement or WindmillPlacement
    local config = kind == "cutter" and Config.cutterPlacement
        or kind == "wrapper" and Config.wrapperPlacement or Config.windmillPlacement
    local item = placement.ensure(state, config)
    if directionX ~= 0 or directionY ~= 0 then World.placementSelection = nil end
    placement.move(state, directionX, directionY, dt, config, function(nextX, nextY)
        local halfWidth, halfHeight = config.collisionHalfWidth, config.collisionHalfHeight
        local obstacles = movementObstacles(state, false, {
            x = halfWidth, y = halfHeight,
        }, kind == "cutter", kind == "wrapper", nil, kind == "windmill")
        if kind == "windmill"
            and not Navigation.isAreaWalkable(assets, item.x, item.y, 0, 0)
        then
            return nextX > halfWidth and nextX < Config.baseWidth - halfWidth
                and nextY > halfHeight and nextY < Config.baseHeight - halfHeight
        end
        if Navigation.canMoveAreaFrom(assets, item.x, item.y, nextX, nextY,
            halfWidth, halfHeight, obstacles)
        then return true end
        if kind == "windmill"
            and not Navigation.isAreaWalkable(assets, item.x, item.y, halfWidth, halfHeight)
        then
            return Navigation.canMoveFrom(assets, item.x, item.y, nextX, nextY, obstacles)
                and Navigation.isAreaWalkable(assets, nextX, nextY, 0, 0)
        end
        return false
    end)
    local jack = PalletJack.ensure(state, Config.palletJack)
    jack.x, jack.y = item.x, item.y + 8
    jack.direction, jack.moving = item.direction, item.inMotion
    jack.animationClock = jack.animationClock + math.max(0, tonumber(dt) or 0)
    player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack)
    player.moving = item.inMotion
    player.facing = player.x < item.x and 1 or -1
    return true
end

local function activePlacement(state)
    local networkMachineView = state and state._networkMachinePoses ~= nil
    local jack = state and PalletJack.ensure(state, Config.palletJack)
    local localPlayerId = tonumber(World.player.id) or 1
    local localGuestControlsMachine = networkMachineView and jack and jack.operating
        and localPlayerId >= 2 and jack.operatorPlayerId == localPlayerId
        and activeMachineKind(state) ~= nil
    if (not networkMachineView or localGuestControlsMachine)
        and state and state.cutter and state.cutter.moving
    then
        return "cutter", state.cutter.x, state.cutter.y
    elseif (not networkMachineView or localGuestControlsMachine)
        and state and state.wrapper and state.wrapper.moving
    then
        return "wrapper", state.wrapper.x, state.wrapper.y
    elseif (not networkMachineView or localGuestControlsMachine)
        and state and state.windmill and state.windmill.moving
    then
        return "windmill", state.windmill.x, state.windmill.y
    end
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

function World.selectPlacement(state, assets, x, y, readOnly)
    local snapshot = World.placementGridSnapshot(state, assets)
    if not snapshot then return false end
    local cell = PlacementGrid.hit(snapshot.cells, x, y, snapshot.config)
    if not cell then return false end
    if not cell.valid then
        state.message = "That red grid space is blocked. Choose a green space."
        return true
    end
    if readOnly == true and snapshot.kind == "pallet" then
        state.message = "The host will validate the highlighted drop cell."
        return true
    end
    World.placementSelection = { kind = snapshot.kind, x = cell.x, y = cell.y }
    state.message = snapshot.kind == "pallet"
        and "Placement selected. Press L to lower the skid, or choose another green space."
        or "Placement selected. Press E to set it down, or choose another green space."
    return true
end

function World.findCutterOutput(state, assets, excludedPalletId)
    return CutterZones.findOutput(state, Config.cutterPlacement, function(x, y)
        return World.isPalletPlacementClear(state, assets, x, y, excludedPalletId)
    end)
end

local function interactables(player)
    player = player or World.player
    local targets = {}
    local function addTarget(kind, target, key)
        MultiplayerCapabilities.requireInteraction(kind)
        if target then
            target.kind = kind
            targets[key or kind] = target
        end
    end
    addTarget("computer", Config.interactables.computer)
    local phoneTarget = {
        x = Config.interactables.workPhone.x,
        y = Config.interactables.workPhone.y,
        radius = Config.interactables.workPhone.radius,
        prompt = World._state and World._state.workPhone
            and World._state.workPhone.incoming
            and "E: answer ringing wall phone" or "E: use wall phone",
    }
    addTarget("workPhone", phoneTarget)
    local customerInteraction = World.customer:getInteraction()
    addTarget("customer", customerInteraction)
    local vendorInteraction = World.vendor:getInteraction()
    if vendorInteraction then
        vendorInteraction.prompt = "E: talk to the " .. Procurement.category(World._state and World._state.vendorCategory).name:lower() .. " salesman"
        addTarget("vendor", vendorInteraction)
    end
    addTarget("loadingBayDoor", World.bayDoor:getInteraction())
    local truckInteraction = World.truck:getInteraction()
    addTarget("truckCargoDoor", truckInteraction)
    if World._state then
        local networkMachineView = World._state._networkMachinePoses ~= nil
        local nearestPallet
        local nearestDistance
        for _, item in ipairs(PalletLogistics.physicalPallets(World._state)) do
            local distance = (player.x - item.x) ^ 2 + (player.y - item.y) ^ 2
            local radius = Config.palletLogistics.interactionRadius or 92
            if distance <= radius * radius and (not nearestDistance or distance < nearestDistance) then
                nearestPallet, nearestDistance = item, distance
            end
        end
        if nearestPallet then
            addTarget("palletWorkOrder", {
                x = nearestPallet.x, y = nearestPallet.y,
                radius = Config.palletLogistics.interactionRadius or 92,
                prompt = "E: inspect work order",
                item = nearestPallet,
            })
        end
        local jack = PalletJack.ensure(World._state, Config.palletJack)
        local playerId = type(player.id) == "number" and player.id
            or (player == World.player and 1 or nil)
        local jackReady = jack.operating and not jack.carriedPalletId
            and jack.operatorPlayerId == playerId
        local cutters = MachineFleet.installedUnits(World._state, "polar_115")
        if cutters[1] and not cutters[1].world
            and not (networkMachineView and World._state.cutter.moving)
        then
            local target = CutterPlacement.interaction(player, World._state,
                Config.cutterPlacement, jackReady)
            target.machineId = cutters[1].id
            addTarget("cutter", target)
        end
        for index = 1, #cutters do
            local item = cutters[index]
            if item.world then addTarget("cutter", {
                x = item.world.x, y = item.world.y,
                radius = Config.cutterPlacement.interactionRadius,
                prompt = "E: use " .. item.name .. " (" .. item.id .. ")",
                machineId = item.id,
            }, "cutter:" .. item.id) end
        end
        local wrappers = MachineFleet.installedUnits(World._state, "skid_wrapper")
        if wrappers[1] and not wrappers[1].world
            and not (networkMachineView and World._state.wrapper.moving)
        then
            local target = WrapperPlacement.interaction(player, World._state,
                Config.wrapperPlacement, jackReady)
            target.machineId = wrappers[1].id
            addTarget("skidWrapper", target)
        end
        for index = 1, #wrappers do
            local item = wrappers[index]
            if item.world then addTarget("skidWrapper", {
                x = item.world.x, y = item.world.y,
                radius = Config.wrapperPlacement.interactionRadius,
                prompt = "E: use skid wrapper (" .. item.id .. ")",
                machineId = item.id,
            }, "wrapper:" .. item.id) end
        end
        local windmills = MachineFleet.installedUnits(World._state, "heidelberg_10x15")
        if windmills[1] and not windmills[1].world
            and not (networkMachineView and World._state.windmill.moving)
        then
            local target = WindmillPlacement.interaction(player, World._state,
                Config.windmillPlacement, jackReady)
            target.machineId = windmills[1].id
            addTarget("windmill", target)
        end
        for index = 1, #windmills do
            local item = windmills[index]
            if item.world then addTarget("windmill", {
                x = item.world.x, y = item.world.y,
                radius = Config.windmillPlacement.interactionRadius,
                prompt = "E: operate Windmill (" .. item.id .. ")",
                machineId = item.id,
            }, "windmill:" .. item.id) end
        end
        addTarget("palletJack", PalletJack.interaction(player, World._state, Config.palletJack))
        local lift = Forklift.ensure(World._state, Config.forklift)
        if lift.owned then
            addTarget("forklift", {x=lift.x,y=lift.y,radius=(Config.forklift and Config.forklift.interactionRadius) or 76,
                prompt=lift.operating and lift.operatorPlayerId==playerId
                    and "E: forklift controls  |  F: park" or "E: operate forklift"})
        end
        local rackId = World.warehouseNearRack(player, World._state)
        if rackId then
            local approach = WarehouseLayout.rackApproach(rackId)
            addTarget("palletRack", {x=approach.x,y=approach.y,radius=130,rackId=rackId,
                prompt="E: view pallet shelves"})
        end
        if jackReady and activeMachineKind(World._state) then
            targets.palletJack.prompt = "E: place machine  |  Q: TURN"
        elseif jackReady then
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
                targets.palletJack.prompt = "F: park pallet jack  |  M: RELOCATE CUTTER"
            elseif wrapperNear then
                targets.palletJack.prompt = "F: park pallet jack  |  M: RELOCATE WRAPPER"
            elseif windmillNear then
                targets.palletJack.prompt = "F: park pallet jack  |  M: RELOCATE WINDMILL"
            end
        end
    end
    return targets
end

local function selectInteractionFor(player, previous, cursorX, cursorY)
    return Interaction.select(player, interactables(player), cursorX, cursorY, previous, {
        stickiness = Config.player.interactionStickiness,
        facingWeight = Config.player.interactionFacingWeight,
    })
end

local function selectNetworkInteractionFor(player, previous, cursorX, cursorY)
    local previousDoor = previous and previous.kind == "loadingBayDoor" and previous or nil
    local door = Interaction.select(player, {
        loadingBayDoor = World.bayDoor:getInteraction(),
    }, cursorX, cursorY, previousDoor, {
        stickiness = Config.player.interactionStickiness,
        facingWeight = Config.player.interactionFacingWeight,
    })
    -- The only guest-enabled target wins throughout its operating radius, even
    -- when a parked truck's larger prompt overlaps the wall switch.
    return door or selectInteractionFor(player, previous, cursorX, cursorY)
end

function World.interactionAt(x, y, networkClient)
    local selector = networkClient and selectNetworkInteractionFor
        or selectInteractionFor
    World.selectedInteraction = selector(
        World.player, World.selectedInteraction, x, y)
    return World.selectedInteraction
end

function World.load(position)
    local character = position and position.character or Config.player.character
    local playerId = position and tonumber(position.id) or nil
    World.player.id = playerId and playerId >= 1 and playerId <= 4
        and playerId == math.floor(playerId) and playerId or nil
    World.player.character = Config.characters[character] and character or Config.player.character
    PlayerController.reset(World.player, position, Config.player)
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
        local hasInboundPallets = PalletLogistics.remainingOnTruck(state, job.id) > 0
        if (job.status == "awaiting_delivery" or job.status == "in_production")
            and hasInboundPallets and deliveryStatus ~= "received"
            and JobService.deliveryReady(state, job)
        then
            if World.truck:schedule(job.id, "delivery") then
                job.delivery = job.delivery or {}
                job.delivery.status = "scheduled"
                state.message = job.delivery.kind == "replacement"
                    and "The customer's replacement skid is scheduled for delivery."
                    or "Inbound truck scheduled for " .. job.id .. "."
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
    local replacementDelivery = job and job.delivery
        and job.delivery.kind == "replacement" and not pickup
    if event == "request_bay_open" then
        if World.bayDoor.state == "closed" then World.bayDoor:open() end
        if state then
            state.message = pickup and "Pickup truck arrived. Opening the loading bay..."
                or (machineOrder and "Machine flatbed arrived. Opening the loading bay..."
                    or (replacementDelivery
                        and "The customer's replacement-stock truck arrived. Opening the loading bay..."
                        or "Delivery truck arrived. Opening the loading bay..."))
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
                    or (replacementDelivery
                        and "Replacement skid parked at the bay. Open the truck and unload it."
                        or "Truck parked. Open its rear cargo door to unload."))
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

function World.customerArrivalMessage(state)
    return state and state.currentOffer and state.currentOffer.press
        and "A customer is waiting at reception with a print job."
        or "A customer is waiting at reception with a client job."
end

function World.update(dt, directionX, directionY, assets, state, cursorX, cursorY)
    assets = WarehouseGameplay.assets(assets, state)
    World._assets = assets
    if directionX ~= 0 or directionY ~= 0 then World.placementSelection = nil end
    World._state = state
    local player = World.player
    local playerStartX, playerStartY = player.x, player.y
    local jack = PalletJack.ensure(state, Config.palletJack)
    local cutter = CutterPlacement.ensure(state, Config.cutterPlacement)
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local windmill = WindmillPlacement.ensure(state, Config.windmillPlacement)
    local localOperatesJack = jack.operating and jack.operatorPlayerId == 1
    local localOperatesForklift = Forklift.isOperator(state, Config.forklift, tonumber(player.id) or 1)
    local externalMovement = cutter.moving or wrapper.moving or windmill.moving
        or localOperatesJack or localOperatesForklift
    if localOperatesForklift then
        World.updateNetworkForklift(player, dt, directionX, directionY, assets, state)
    elseif cutter.moving then
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
    elseif localOperatesJack then
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
        PlayerController.update(player, directionX, directionY, dt,
            function(currentX, currentY, nextX, nextY)
                return Navigation.canMoveFrom(assets, currentX, currentY, nextX, nextY,
                    movementObstacles(state, false))
            end, Config.player)
    end
    if externalMovement and not localOperatesForklift then
        PlayerController.observeExternalMove(player, playerStartX, playerStartY, player.moving, dt)
    end
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
        state.message = World.customerArrivalMessage(state)
    elseif customerEvent == "timed_out" and state then
        state.message = "The client waited five minutes without being seen and is leaving."
    elseif customerEvent == "exited" and state then
        state.message = World.customer.decision == "timed_out"
            and "The client left after waiting five minutes."
            or (World.customer.decision == "accepted"
                and "The customer left and will email the written job details."
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
    World.selectedInteraction = selectInteractionFor(
        player, World.selectedInteraction, cursorX, cursorY)
    return saveNeeded
end

local function updateWalkingPlayer(player, dt, directionX, directionY, assets, state)
    if type(player) ~= "table" then return false end
    assets = WarehouseGameplay.assets(assets, state)
    PlayerController.update(player, directionX or 0, directionY or 0, dt,
        function(currentX, currentY, nextX, nextY)
            return Navigation.canMoveFrom(assets, currentX, currentY, nextX, nextY,
                movementObstacles(state, false))
        end, Config.player)
    return true
end

-- LAN guests predict only their own walking. Durable shop systems continue to
-- run exclusively on the authoritative host.
function World.updateNetworkPlayer(dt, directionX, directionY, assets, state, cursorX, cursorY)
    assets = WarehouseGameplay.assets(assets, state)
    World._assets, World._state = assets, state
    World.placementSelection = nil
    local updated
    if Forklift.isOperator(state, Config.forklift, World.player.id) then
        updated = World.updateNetworkForklift(World.player, dt, directionX, directionY, assets, state, true)
    else updated = updateWalkingPlayer(World.player, dt, directionX, directionY, assets, state) end
    World.selectedInteraction = selectNetworkInteractionFor(
        World.player, World.selectedInteraction, cursorX, cursorY)
    return updated
end

-- The host uses the same collision and gait controller for every connected
-- worker, while leaving the original single-player World.player seam intact.
function World.updateNetworkPalletJack(
    player, dt, directionX, directionY, assets, state, cursorX, cursorY)
    if type(player) ~= "table" or type(state) ~= "table" then return false end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if not PalletJack.isOperator(state, Config.palletJack, player.id) then return false end
    assets = WarehouseGameplay.assets(assets, state)
    World._assets, World._state = assets, state
    local playerStartX, playerStartY = player.x, player.y
    if not moveNetworkAttachedMachine(
        player, dt, directionX or 0, directionY or 0, assets, state)
    then
        PalletJack.move(state, directionX or 0, directionY or 0, dt, Config.palletJack,
            function(nextX, nextY, loaded)
                local footprint = loaded and {
                    x = Config.palletJack.loadedCollisionHalfWidth,
                    y = Config.palletJack.loadedCollisionHalfHeight,
                } or {
                    x = Config.palletJack.collisionHalfWidth,
                    y = Config.palletJack.collisionHalfHeight,
                }
                return Navigation.canMoveAreaFrom(assets, jack.x, jack.y, nextX, nextY,
                    footprint.x, footprint.y, movementObstacles(state, true, footprint))
            end)
        player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack)
    end
    PlayerController.observeExternalMove(
        player, playerStartX, playerStartY, jack.moving, dt)
    player.facing = (jack.direction == "northeast" or jack.direction == "east"
        or jack.direction == "southeast") and 1 or -1
    if player == World.player then
        World.selectedInteraction = selectNetworkInteractionFor(
            player, World.selectedInteraction, cursorX, cursorY)
    end
    return true
end

function World.updateRemotePlayer(player, dt, directionX, directionY, assets, state)
    assets = WarehouseGameplay.assets(assets, state)
    World._assets, World._state = assets, state
    if Forklift.isOperator(state, Config.forklift, player.id) then
        return World.updateNetworkForklift(player, dt, directionX, directionY, assets, state)
    end
    local jack = type(state) == "table" and PalletJack.ensure(state, Config.palletJack) or nil
    if jack and jack.operating and jack.operatorPlayerId == player.id then
        return World.updateNetworkPalletJack(
            player, dt, directionX, directionY, assets, state)
    end
    return updateWalkingPlayer(player, dt, directionX, directionY, assets, state)
end

-- Find a nearby walkable guest start without trusting a fixed offset that may
-- land across a mask edge or inside a moved machine/pallet.
function World.resolveNetworkSpawn(originX, originY, guestIndex, assets, state, players)
    assets, state = assets or World._assets, state or World._state
    assets = WarehouseGameplay.assets(assets, state)
    originX, originY = tonumber(originX) or Config.player.spawnX,
        tonumber(originY) or Config.player.spawnY
    if not assets or not state then return originX, originY end

    local obstacles = movementObstacles(state, false)
    for _, player in pairs(players or {}) do
        if type(player) == "table" and type(player.x) == "number" and type(player.y) == "number" then
            obstacles[#obstacles + 1] = { x = player.x, y = player.y, radius = 16 }
        end
    end
    local startingAngles = { [2] = 0, [3] = math.pi, [4] = math.pi / 2 }
    local start = startingAngles[tonumber(guestIndex)] or 0
    for _, radius in ipairs({ 32, 48, 64, 80 }) do
        for step = 0, 7 do
            local angle = start + step * math.pi / 4
            local candidateX = originX + math.cos(angle) * radius
            local candidateY = originY + math.sin(angle) * radius
            if Navigation.isWalkable(assets, candidateX, candidateY, obstacles) then
                return candidateX, candidateY
            end
        end
    end

    -- An exact overlap is preferable to trapping the guest off-mask. Normal
    -- movement separates overlapping workers immediately.
    if Navigation.isWalkable(assets, originX, originY, {}) then return originX, originY end
    if Navigation.isWalkable(assets, Config.player.spawnX, Config.player.spawnY, obstacles) then
        return Config.player.spawnX, Config.player.spawnY
    end
    return Config.player.spawnX, Config.player.spawnY
end

function World.draw(assets, characterAssets, state, mouseX, mouseY, remotePlayers)
    return WorldRenderer.draw(World, assets, characterAssets, state, mouseX, mouseY, remotePlayers)
end

function World.prompt()
    return Interaction.prompt(World.selectedInteraction)
end

function World.getInteraction()
    return World.selectedInteraction
end

function World.interactionForPlayer(player)
    return selectInteractionFor(player)
end

local WORKSHOP_RESOURCES = {
    customer = "reception_customer",
    vendor = "vendor",
    computer = "office_computer",
    workPhone = "work_phone",
    cutter = "cutter",
    skidWrapper = "skid_wrapper",
    windmill = "windmill",
    palletJack = "pallet_jack",
}

function World.workshopResourceId(interactionKind)
    if interactionKind == "truckCargoDoor" then
        local truck = World.truck:snapshot()
        if truck.mode == "machine_delivery" and truck.state == "parked_closed" then
            return "truck"
        end
        if truck.state == "cargo_open" then return "truck" end
        return nil
    end
    return WORKSHOP_RESOURCES[interactionKind]
end

-- Workshop requests never carry client coordinates. The host resolves the
-- physical target from its current shop state and checks the authoritative
-- player position directly before granting an exclusive console lease.
function World.validateNetworkWorkshopAccess(player, state, resourceId)
    if type(player) ~= "table" or type(state) ~= "table" then
        return false, "invalid_player", "The host could not verify that worker's position."
    end
    World._state = state
    local target, unavailableMessage
    if resourceId == "reception_customer" then
        target = World.customer:getInteraction()
        if not target or target.customerState ~= "waiting" then
            return false, "customer_unavailable", "That customer is not waiting for a conversation."
        end
        unavailableMessage = "Move closer to the waiting customer at reception."
    elseif resourceId == "vendor" then
        target = World.vendor:getInteraction()
        if not target or (target.customerState ~= "waiting"
            and target.customerState ~= "reviewing")
        then
            return false, "vendor_unavailable", "That salesperson is not available."
        end
        unavailableMessage = "Move closer to the supplier representative."
    elseif resourceId == "truck" then
        local truck = World.truck:snapshot()
        local manifestReady = truck.mode == "machine_delivery"
            and truck.state == "parked_closed" or truck.state == "cargo_open"
        target = World.truck:getInteraction()
        if not target or not manifestReady then
            return false, "truck_unavailable",
                "Open the parked truck before reviewing its manifest."
        end
        if not World.openTruckInventory(state) then
            return false, "manifest_unavailable",
                "That truck no longer has an available manifest."
        end
        unavailableMessage = "Move closer to the truck cargo controls."
    elseif resourceId == "office_computer" then
        target = Config.interactables.computer
        unavailableMessage = "Move closer to the office computer."
    elseif resourceId == "work_phone" then
        target = Config.interactables.workPhone
        unavailableMessage = "Move closer to the wall phone."
    elseif resourceId == "cutter" then
        if not MachineFleet.isInstalled(state, "polar_115") then
            return false, "not_installed", "The paper cutter is not installed in this shop."
        end
        local selected = player.id == 1 and state._localWorkshopMachineId
            and MachineFleet.byId(state, state._localWorkshopMachineId)
        local cutter = selected and selected.modelId == "polar_115" and selected.status == "installed"
            and (selected.world or CutterPlacement.ensure(state, Config.cutterPlacement))
            or CutterPlacement.ensure(state, Config.cutterPlacement)
        if cutter.moving then
            return false, "machine_moving", "Lock the cutter onto the floor before using it."
        end
        target = { x = cutter.x, y = cutter.y, radius = Config.cutterPlacement.interactionRadius }
        unavailableMessage = "Move closer to the cutter controls."
    elseif resourceId == "skid_wrapper" then
        if not MachineFleet.isInstalled(state, "skid_wrapper") then
            return false, "not_installed", "The skid wrapper is not installed in this shop."
        end
        local selected = player.id == 1 and state._localWorkshopMachineId
            and MachineFleet.byId(state, state._localWorkshopMachineId)
        local wrapper = selected and selected.modelId == "skid_wrapper" and selected.status == "installed"
            and (selected.world or WrapperPlacement.ensure(state, Config.wrapperPlacement))
            or WrapperPlacement.ensure(state, Config.wrapperPlacement)
        if wrapper.moving then
            return false, "machine_moving", "Lock the skid wrapper onto the floor before using it."
        end
        target = { x = wrapper.x, y = wrapper.y, radius = Config.wrapperPlacement.interactionRadius }
        unavailableMessage = "Move closer to the skid wrapper controls."
    elseif resourceId == "windmill" then
        if not MachineFleet.isInstalled(state, "heidelberg_10x15") then
            return false, "not_installed", "The Heidelberg Windmill is not installed in this shop."
        end
        local selected = player.id == 1 and state._localWorkshopMachineId
            and MachineFleet.byId(state, state._localWorkshopMachineId)
        local windmill = selected and selected.modelId == "heidelberg_10x15"
            and selected.status == "installed"
            and (selected.world or WindmillPlacement.ensure(state, Config.windmillPlacement))
            or WindmillPlacement.ensure(state, Config.windmillPlacement)
        if windmill.moving then
            return false, "machine_moving", "Lock the Windmill onto the floor before using it."
        end
        target = {
            x = windmill.x,
            y = windmill.y,
            radius = Config.windmillPlacement.interactionRadius,
        }
        unavailableMessage = "Move closer to the Windmill controls."
    elseif resourceId == "pallet_jack" then
        local jack = PalletJack.ensure(state, Config.palletJack)
        local cutter = CutterPlacement.ensure(state, Config.cutterPlacement)
        local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
        local windmill = WindmillPlacement.ensure(state, Config.windmillPlacement)
        if cutter.moving or wrapper.moving or windmill.moving then
            local playerId = tonumber(player.id)
            if not jack.operating or jack.operatorPlayerId ~= playerId then
                return false, "equipment_moving",
                    "Only the worker relocating this machine may use the pallet jack."
            end
        end
        target = { x = jack.x, y = jack.y, radius = Config.palletJack.interactionRadius }
        unavailableMessage = "Move closer to the pallet jack handle."
    else
        return false, "not_allowed", "That workshop control is not available to network workers."
    end
    local dx = (tonumber(player.x) or 0) - target.x
    local dy = (tonumber(player.y) or 0) - target.y
    local radius = math.max(0, tonumber(target.radius) or 0) + 10
    if dx * dx + dy * dy > radius * radius then
        return false, "out_of_range", unavailableMessage
    end
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0.01 then
        player.intentX, player.intentY = -dx / length, -dy / length
        if math.abs(dx) > 0.01 then player.facing = dx > 0 and -1 or 1 end
    end
    return true, "available", "Workshop control is in range."
end

function World.faceInteraction()
    local target = World.selectedInteraction and World.selectedInteraction.target
    if not target then return false end
    local dx, dy = target.x - World.player.x, target.y - World.player.y
    if math.abs(dx) > 0.01 then World.player.facing = dx < 0 and -1 or 1 end
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0.01 then
        World.player.intentX, World.player.intentY = dx / length, dy / length
    end
    return true
end

function World.setPlayerCharacter(character)
    if not Config.characters[character] then return false end
    World.player.character = character
    return true
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
            and "The customer will email the written job details."
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

-- Network workers may request only explicitly allowlisted, non-modal actions.
-- The host resolves the target again from its authoritative worker position;
-- client coordinates and target state are never accepted as authority.
function World.performNetworkInteraction(player, state, requestedKind, desiredState)
    if type(player) ~= "table"
        or (requestedKind ~= "loadingBayDoor" and requestedKind ~= "truckCargoDoor")
        or (desiredState ~= "open" and desiredState ~= "closed")
    then
        return false, "not_allowed", "That shop control is still host-only.", requestedKind
    end
    World._state = state or World._state
    local target = requestedKind == "loadingBayDoor"
        and World.bayDoor:getInteraction() or World.truck:getInteraction()
    if not target then
        return false, "unavailable", "That shop control is no longer available.", requestedKind
    end
    local dx, dy = (tonumber(player.x) or 0) - target.x,
        (tonumber(player.y) or 0) - target.y
    -- One 20 Hz movement sample is roughly eight pixels at normal walking
    -- speed. A small host-side grace avoids boundary flicker without trusting
    -- any coordinate supplied by the client.
    local radius = math.max(0, tonumber(target.radius) or 0) + 10
    if dx * dx + dy * dy > radius * radius then
        return false, "out_of_range", requestedKind == "truckCargoDoor"
            and "Move closer to the truck cargo controls."
            or "Move closer to the loading-bay wall switch.", requestedKind
    end
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0.01 then
        player.intentX, player.intentY = -dx / length, -dy / length
        if math.abs(dx) > 0.01 then player.facing = dx > 0 and -1 or 1 end
    end
    if requestedKind == "truckCargoDoor" then
        if desiredState ~= "open" then
            return false, "manifest_required",
                "Review and finish the host-owned manifest before closing this truck.", requestedKind
        end
        if World.truck.mode == "machine_delivery" then
            return false, "flatbed_manifest",
                "This flatbed opens through its host-owned manifest.", requestedKind
        end
        if World.truck.state == "cargo_open" then
            return true, "already_applied", "The truck cargo door is already open.", requestedKind
        elseif World.truck.state == "cargo_opening" then
            return true, "in_progress", "The truck cargo door is already opening.", requestedKind
        elseif World.truck.state ~= "parked_closed" then
            return false, "state_changed",
                "Wait for the truck to park before opening its cargo door.", requestedKind
        end
        if World.toggleTruckCargoDoor(state) then
            return true, "accepted",
                "Truck cargo door activated. Door movement is synced from the host device.",
                requestedKind
        end
        return false, "blocked",
            state and state.message or "The truck cargo door cannot open right now.", requestedKind
    end
    if World.bayDoor.state == desiredState then
        return true, "already_applied",
            "The loading-bay door is already " .. desiredState .. ".", requestedKind
    end
    local movingTowardDesired = (World.bayDoor.state == "opening" and desiredState == "open")
        or (World.bayDoor.state == "closing" and desiredState == "closed")
    if movingTowardDesired then
        return true, "in_progress",
            "The loading-bay door is already moving " .. desiredState .. ".", requestedKind
    elseif World.bayDoor.state == "opening" or World.bayDoor.state == "closing" then
        return false, "state_changed",
            "The loading-bay door changed state. Wait for it to finish and try again.", requestedKind
    end
    local accepted = World.toggleBayDoor(state)
    if accepted then
        return true, "accepted",
            "Loading-bay switch activated. Door movement is synced from the host device.",
            requestedKind
    end
    local code = World.bayDoor.state == "opening" or World.bayDoor.state == "closing"
        and "busy" or "blocked"
    return false, code, state and state.message or "The loading-bay door cannot move right now.", requestedKind
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

local function validNetworkPlayerId(player)
    local id = type(player) == "table" and tonumber(player.id) or nil
    return id and id == math.floor(id) and id >= 1 and id <= 4 and id or nil
end

local function palletJackHasAttachedMachine(state)
    return type(state) == "table" and ((state.cutter and state.cutter.moving)
        or (state.wrapper and state.wrapper.moving)
        or (state.windmill and state.windmill.moving))
end

function World.operateNetworkPalletJack(player, state)
    local playerId = validNetworkPlayerId(player)
    if not playerId or type(state) ~= "table" then
        return false, "invalid_player", "The host could not identify that worker."
    end
    local mounted, mountCode = PalletJack.mount(state, Config.palletJack, playerId)
    if not mounted then
        return false, mountCode, mountCode == "busy"
            and "Another worker is operating the pallet jack."
            or "The pallet jack could not be mounted safely."
    end
    local operatorX, operatorY = PalletJack.operatorPosition(state, Config.palletJack)
    player.x, player.y = operatorX, operatorY
    if playerId == 1 then World.player.x, World.player.y = operatorX, operatorY end
    state.message = "Operating pallet jack. Tap a skid to lift it; use L to lower it; normal USE actions still work."
    return true, mountCode, state.message, World.networkPalletJackSnapshot(state)
end

function World.releaseNetworkPalletJack(player, state, force)
    local playerId = validNetworkPlayerId(player)
    if not playerId or type(state) ~= "table" then
        return false, "invalid_player", "The host could not identify that worker."
    end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if jack.operatorPlayerId ~= playerId then
        return false, "not_owner", "Another worker owns the pallet jack."
    end
    if not force and palletJackHasAttachedMachine(state) then
        return false, "equipment_moving",
            "Place the moving machine before parking the pallet jack."
    end
    local released, releaseCode
    if force then
        released, releaseCode = PalletJack.forceRelease(
            state, Config.palletJack, playerId)
    else
        released = PalletJack.park(state, Config.palletJack)
        releaseCode = released and "parked" or "loaded"
    end
    if not released then
        local message = releaseCode == "loaded"
            and "Lower the carried pallet before parking the jack."
            or "The pallet jack could not be released safely."
        state.message = message
        return false, releaseCode, message
    end
    state.message = releaseCode == "parked_loaded"
        and "The disconnected worker's loaded pallet jack was parked safely."
        or "Pallet jack parked."
    return true, releaseCode, state.message, World.networkPalletJackSnapshot(state)
end

function World.liftNetworkPallet(player, state, palletId)
    local playerId = validNetworkPlayerId(player)
    if not playerId or not PalletJack.isOperator(state, Config.palletJack, playerId) then
        return false, "not_owner", "Acquire the pallet jack before lifting a pallet."
    end
    if palletJackHasAttachedMachine(state) then
        return false, "equipment_moving",
            "Place the moving machine before lifting a pallet."
    end
    local lifted, liftCode, pallet = PalletJack.lift(
        state, Config.palletJack, palletId)
    if not lifted then
        local messages = {
            missing = "That pallet no longer exists.",
            unavailable = "That pallet is no longer staged on movable floor space.",
            out_of_range = "Drive the forks closer to that exact pallet.",
            already_loaded = "The pallet jack is already carrying a pallet.",
            invalid_pallet = "Choose a valid pallet.",
        }
        state.message = messages[liftCode] or tostring(liftCode)
        return false, liftCode, state.message
    end
    local operatorX, operatorY = PalletJack.operatorPosition(state, Config.palletJack)
    player.x, player.y = operatorX, operatorY
    state.message = "Lifted " .. pallet.id .. ". Drive it into position, then lower it."
    return true, liftCode, state.message, pallet
end

function World.lowerNetworkPallet(player, state, assets, palletId)
    local playerId = validNetworkPlayerId(player)
    if not playerId or not PalletJack.isOperator(state, Config.palletJack, playerId) then
        return false, "not_owner", "Acquire the pallet jack before lowering a pallet."
    end
    if palletJackHasAttachedMachine(state) then
        return false, "equipment_moving",
            "Place the moving machine before lowering a pallet."
    end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if jack.carriedPalletId ~= palletId then
        return false, "wrong_pallet", "The pallet on the forks changed; try again."
    end
    local dropX, dropY = PalletJack.dropPosition(state, Config.palletJack)
    -- LAN workers choose the semantic action, never coordinates. Snap the
    -- host's current fork position to the same deterministic grid cell shown
    -- as selected on clients, then validate that exact cell authoritatively.
    dropX, dropY = PlacementGrid.snap(dropX, dropY, Config.placementGrid)
    local lowered, lowerCode, pallet = PalletJack.lower(
        state, Config.palletJack, function(x, y)
            return World.isPalletPlacementClear(
                state, assets or World._assets, x, y, palletId)
        end, dropX, dropY, palletId)
    if not lowered then
        state.message = lowerCode == "blocked"
            and "There is not enough clear floor space to lower this pallet."
            or (lowerCode == "missing" and "The carried pallet could not be found."
                or "The pallet could not be lowered safely.")
        return false, lowerCode, state.message
    end
    state.message = "Lowered " .. pallet.id .. " at its host-validated warehouse position."
    return true, lowerCode, state.message, pallet
end

function World.handlePalletJack(state, assets, palletId)
    local localPlayerId = tonumber(World.player.id) or 1
    local currentJack = PalletJack.ensure(state, Config.palletJack)
    if palletJackHasAttachedMachine(state) then
        state.message = "Place the moving machine before using the pallet jack."
        return false
    end
    if currentJack.operating and currentJack.operatorPlayerId ~= localPlayerId then
        state.message = "Another worker is operating the pallet jack."
        return false
    end
    local succeeded, action, pallet
    if palletId ~= nil then
        if not PalletJack.isOperator(state, Config.palletJack, localPlayerId) then
            state.message = "Operate the pallet jack before tapping a skid."
            return false
        end
        succeeded, action, pallet = PalletJack.lift(
            state, Config.palletJack, palletId)
    else
        local grid = World.placementGridSnapshot(state, assets)
        local selected = World.placementSelection or (grid and grid.selected)
        local placementX = selected and selected.kind == "pallet" and selected.x or nil
        local placementY = selected and selected.kind == "pallet" and selected.y or nil
        succeeded, action, pallet = PalletJack.use(state, Config.palletJack, function(x, y)
            return World.isPalletPlacementClear(state, assets, x, y)
        end, placementX, placementY, localPlayerId)
    end
    if not succeeded then
        if state then
            local messages = {
                blocked = "There is not enough clear floor space to lower this pallet.",
                missing = "That skid no longer exists.",
                unavailable = "That skid is not staged where the pallet jack can lift it.",
                out_of_range = "Push the pallet jack closer to that skid, then tap it again.",
                already_loaded = "Lower the skid already on the forks before lifting another one.",
                invalid_pallet = "Tap a valid skid to lift it.",
            }
            state.message = messages[action] or "The carried pallet could not be found."
        end
        return false
    end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if action == "mounted" then
        World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
        state.message = "Operating pallet jack. Tap a skid to lift it; L lowers it; normal USE actions still work."
    elseif action == "lifted" then
        World.placementSelection = nil
        state.message = "Lifted " .. pallet.id .. ". Drive it, choose a green grid space, then press L."
    elseif action == "lowered" then
        World.placementSelection = nil
        state.message = "Lowered " .. pallet.id .. " at its new warehouse position."
    else
        state.message = "Pallet jack parked."
    end
    return true, action, pallet
end

function World.parkPalletJack(state)
    local jack = PalletJack.ensure(state, Config.palletJack)
    if palletJackHasAttachedMachine(state) then
        if state then state.message = "Place the moving machine before parking the pallet jack." end
        return false
    end
    local localPlayerId = tonumber(World.player.id) or 1
    if jack.operating and jack.operatorPlayerId ~= localPlayerId then
        if state then state.message = "Another worker is operating the pallet jack." end
        return false
    end
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

local NETWORK_MACHINE_KINDS = {
    [1] = { kind = "cutter", modelId = "polar_115", placement = CutterPlacement,
        config = Config.cutterPlacement, label = "cutter", parkedOffset = 42 },
    [2] = { kind = "wrapper", modelId = "skid_wrapper", placement = WrapperPlacement,
        config = Config.wrapperPlacement, label = "skid wrapper", parkedOffset = 46 },
    [3] = { kind = "windmill", modelId = "heidelberg_10x15", placement = WindmillPlacement,
        config = Config.windmillPlacement, label = "Windmill", parkedOffset = 52 },
}

local function activeNetworkMachine(state)
    local kind = activeMachineKind(state)
    if not kind then return nil end
    for index, record in pairs(NETWORK_MACHINE_KINDS) do
        if record.kind == kind then return record, index end
    end
end

local function networkJackOwner(player, state)
    local playerId = validNetworkPlayerId(player)
    local jack = type(state) == "table" and PalletJack.ensure(state, Config.palletJack)
    if not playerId or not jack then
        return nil, nil, "invalid_player", "The host could not identify that worker."
    end
    if not jack.operating or jack.operatorPlayerId ~= playerId then
        return nil, nil, "not_owner", "Acquire the pallet jack before relocating a machine."
    end
    if jack.carriedPalletId then
        return nil, nil, "jack_loaded", "Lower the carried pallet before relocating a machine."
    end
    return playerId, jack
end

function World.beginNetworkMachineMove(player, state, machineIndex, controlOccupied)
    local playerId, jack, code, message = networkJackOwner(player, state)
    if not playerId then return false, code, message end
    if palletJackHasAttachedMachine(state) then
        return false, "machine_moving", "Place the moving machine before relocating another one."
    end
    local record = NETWORK_MACHINE_KINDS[tonumber(machineIndex)]
    if not record or not MachineFleet.isInstalled(state, record.modelId) then
        return false, "machine_unavailable", "That machine is not installed in this shop."
    end
    if controlOccupied then
        return false, "console_busy", "Close the active " .. record.label .. " console first."
    end
    if record.kind == "cutter" then
        if Machine.hasActiveBatch() or cutterHasPaper(state) then
            return false, "machine_busy", "Unload the cutter and finish its active batch first."
        end
    elseif record.kind == "wrapper" then
        if not Wrapper.canRelocate(state) then
            return false, "machine_busy", tostring(state.message)
        end
    else
        local process = Windmill.ensure(state)
        if process.status ~= "idle" or process.palletId then
            return false, "machine_busy", "Unload the Windmill and return it to idle first."
        end
    end
    local item = record.placement.ensure(state, record.config)
    if (jack.x - item.x) ^ 2 + (jack.y - item.y) ^ 2
        > record.config.interactionRadius ^ 2
    then
        return false, "out_of_range",
            "Drive the empty pallet jack beside the " .. record.label .. " first."
    end
    if not record.placement.beginMove(state, record.config) then
        return false, "machine_changed", "That machine could not be lifted safely."
    end
    World.placementSelection = nil
    jack.x, jack.y, jack.direction = item.x, item.y + 8, item.direction
    jack.moving = false
    player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack)
    state.message = record.label .. " is on the pallet jack. Move, choose a green grid space, then place it."
    return true, "machine_attached", state.message, World.networkPalletJackSnapshot(state)
end

function World.rotateNetworkMachine(player, state)
    local playerId, jack, code, message = networkJackOwner(player, state)
    if not playerId then return false, code, message end
    local record = activeNetworkMachine(state)
    if not record then return false, "no_machine", "No machine is attached to this pallet jack." end
    local rotated, direction = record.placement.rotate(state, record.config)
    if not rotated then return false, "rotation_blocked", "The machine could not be rotated." end
    local item = record.placement.ensure(state, record.config)
    jack.x, jack.y, jack.direction = item.x, item.y + 8, item.direction
    jack.moving = false
    player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack)
    state.message = record.label .. " rotated " .. tostring(direction) .. "."
    return true, "machine_rotated", state.message, World.networkPalletJackSnapshot(state)
end

function World.networkPlacementCellId(state, assets)
    local snapshot = World.placementGridSnapshot(state, assets)
    local selected = World.placementSelection or (snapshot and snapshot.selected)
    if not snapshot or not selected or selected.kind ~= snapshot.kind then return nil end
    local config = snapshot.config or Config.placementGrid
    local column = math.floor((selected.x - (config.originX or 0))
        / (config.cellWidth or 32) + 0.5)
    local row = math.floor((selected.y - (config.originY or 0))
        / (config.cellHeight or 24) + 0.5)
    if column < 0 or column > 64 or row < 0 or row > 64 then return nil end
    return string.format("c%dr%d", column, row)
end

local function finishNetworkMachinePlacement(player, state, record, x, y)
    local item = record.placement.ensure(state, record.config)
    item.x, item.y = x, y
    if not record.placement.place(state, record.config) then return false end
    World.placementSelection = nil
    local jack = PalletJack.ensure(state, Config.palletJack)
    jack.moving = false
    jack.x, jack.y, jack.direction = item.x, item.y + record.parkedOffset, item.direction
    if player then player.x, player.y = PalletJack.operatorPosition(state, Config.palletJack) end
    state.message = record.label .. " locked into its new floor position."
    return true
end

function World.placeNetworkMachine(player, state, assets, placementCell)
    local playerId, _, code, message = networkJackOwner(player, state)
    if not playerId then return false, code, message end
    local record = activeNetworkMachine(state)
    if not record then return false, "no_machine", "No machine is attached to this pallet jack." end
    local column, row
    if type(placementCell) == "string" then
        column, row = placementCell:match("^c(%d+)r(%d+)$")
    end
    column, row = tonumber(column), tonumber(row)
    if not column or not row or column < 0 or column > 64 or row < 0 or row > 64 then
        return false, "invalid_cell", "Choose a valid highlighted placement cell."
    end
    local x = (Config.placementGrid.originX or 0) + column * Config.placementGrid.cellWidth
    local y = (Config.placementGrid.originY or 0) + row * Config.placementGrid.cellHeight
    local grid = World.placementGridSnapshot(state, assets)
    local valid = false
    for _, cell in ipairs(grid and grid.cells or {}) do
        if cell.x == x and cell.y == y and cell.valid then valid = true; break end
    end
    if not valid or not isMachinePlacementClear(state, assets, record.kind, x, y) then
        return false, "placement_blocked", "That placement cell is blocked; choose a green space."
    end
    if not finishNetworkMachinePlacement(player, state, record, x, y) then
        return false, "machine_changed", "The machine changed before it could be placed."
    end
    return true, "machine_placed", state.message, World.networkPalletJackSnapshot(state)
end

function World.recoverNetworkMachineMove(state, assets, player)
    local record = activeNetworkMachine(state)
    if not record then return false end
    local item = record.placement.ensure(state, record.config)
    local origin = item._relocationOrigin
    World.placementSelection = nil
    local grid = World.placementGridSnapshot(state, assets)
    local target = grid and grid.selected
    local x, y = target and target.x, target and target.y
    if not x or not y or not isMachinePlacementClear(state, assets, record.kind, x, y) then
        x, y = origin and origin.x or item.x, origin and origin.y or item.y
    end
    local recovered = finishNetworkMachinePlacement(player, state, record, x, y)
    if recovered then state.message = "Disconnected relocation recovered and the machine was locked safely." end
    return recovered
end

function World.beginCutterMove(state, cutterControlOccupied)
    if cutterControlOccupied then
        state.message = "Close the active cutter console before relocating the machine."
        return false
    end
    if Machine.hasActiveBatch() then
        state.message = "Finish or safely unload the cutter batch before relocating the machine."
        return false
    end
    if palletJackHasAttachedMachine(state) then
        state.message = "Lock the moving machine onto the floor before relocating another one."
        return false
    end
    if not MachineFleet.isInstalled(state, "polar_115") then return false end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if jack.operating and jack.operatorPlayerId ~= 1 then
        state.message = "Another worker is operating the pallet jack."
        return false
    end
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

function World.rotateCutter(state, cutterControlOccupied)
    if cutterControlOccupied then
        state.message = "Close the active cutter console before rotating the machine."
        return false
    end
    if Machine.hasActiveBatch() then
        state.message = "Finish or safely unload the cutter batch before rotating the machine."
        return false
    end
    if cutterHasPaper(state) then
        state.message = "Unload the paper and clear the cutting bed before rotating the cutter."
        return false
    end
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

function World.beginWrapperMove(state, wrapperControlOccupied)
    if wrapperControlOccupied then
        state.message = "Close the active skid-wrapper console before relocating the machine."
        return false
    end
    if palletJackHasAttachedMachine(state) then
        state.message = "Lock the moving machine onto the floor before relocating another one."
        return false
    end
    if not MachineFleet.isInstalled(state, "skid_wrapper") then return false end
    if not Wrapper.canRelocate(state) then return false end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if jack.operating and jack.operatorPlayerId ~= 1 then
        state.message = "Another worker is operating the pallet jack."
        return false
    end
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

function World.rotateWrapper(state, wrapperControlOccupied)
    if wrapperControlOccupied then
        state.message = "Close the active skid-wrapper console before rotating the machine."
        return false
    end
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

function World.beginWindmillMove(state, windmillControlOccupied)
    if windmillControlOccupied then
        state.message = "Close the active Windmill console before relocating the press."
        return false
    end
    if palletJackHasAttachedMachine(state) then
        state.message = "Lock the moving machine onto the floor before relocating another one."
        return false
    end
    if not MachineFleet.isInstalled(state, "heidelberg_10x15") then return false end
    local process = Windmill.ensure(state)
    if process.status ~= "idle" or process.palletId then
        state.message = "Unload the press and return the Windmill to idle before relocating it."
        return false
    end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if jack.operating and jack.operatorPlayerId ~= 1 then
        state.message = "Another worker is operating the pallet jack."
        return false
    end
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

function World.rotateWindmill(state, windmillControlOccupied)
    if windmillControlOccupied then
        state.message = "Close the active Windmill console before rotating the press."
        return false
    end
    local process = Windmill.ensure(state)
    if process.status ~= "idle" or process.palletId then
        state.message = "Unload the press and return the Windmill to idle before rotating it."
        return false
    end
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

function World.networkPalletJackSnapshot(state)
    local snapshot = PalletJack.snapshot(state, Config.palletJack)
    local machineAttached = palletJackHasAttachedMachine(state)
    local candidatePalletId = snapshot.candidatePalletId
    if machineAttached then candidatePalletId = nil end
    return {
        x = snapshot.x,
        y = snapshot.y,
        direction = snapshot.direction,
        operating = snapshot.operating,
        moving = snapshot.moving,
        operatorPlayerId = snapshot.operatorPlayerId,
        carriedPalletId = snapshot.carriedPalletId,
        candidatePalletId = candidatePalletId,
    }
end

function World.networkMachinePoseSnapshot(state)
    return MachinePose.snapshot(state)
end

function World.applyNetworkPalletJackSnapshot(state, snapshot, machinePoses)
    local normalizedMachinePoses, machinePoseError = MachinePose.normalize(
        machinePoses, snapshot, 100000, "network machine poses")
    if not normalizedMachinePoses then return false, machinePoseError end
    local applied, applyError = PalletJack.applySnapshot(
        state, snapshot, Config.palletJack)
    if not applied then return false, applyError end
    local posesApplied, posesError = MachinePose.apply(state, normalizedMachinePoses)
    if not posesApplied then return false, posesError end
    state._networkMachinePoses = MachinePose.activeKind(normalizedMachinePoses)
        and assert(MachinePose.copy(normalizedMachinePoses)) or nil
    local jack = PalletJack.ensure(state, Config.palletJack)
    local localPlayerId = tonumber(World.player.id) or 1
    if jack.operating and jack.operatorPlayerId == localPlayerId then
        World.player.x, World.player.y = PalletJack.operatorPosition(state, Config.palletJack)
        World.player.moving = jack.moving
        World.player.facing = (jack.direction == "northeast" or jack.direction == "east"
            or jack.direction == "southeast") and 1 or -1
    end
    return true
end

function World.palletsSnapshot(state)
    return PalletLogistics.physicalPallets(state)
end

function World.palletAt(state, x, y)
    return PalletLogistics.hovered(state, x, y)
end

function World.palletTooltipAt(state, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
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

function World.vendorSnapshot()
    return World.vendor:snapshot()
end

function World.applyVisitorSnapshot(customer, vendor)
    if type(customer) ~= "table" or type(vendor) ~= "table" then return false end
    -- Network protocol validation is atomic before this seam is reached.
    return World.customer:applySnapshot(customer) and World.vendor:applySnapshot(vendor)
end

function World.environmentSnapshot()
    local door = World.bayDoor:snapshot()
    local truck = World.truck:snapshot()
    return {
        bayDoor = { state = door.state, progress = door.progress },
        truck = {
            state = truck.state,
            jobId = truck.jobId,
            mode = truck.mode,
            backingProgress = truck.backingProgress,
            cargoProgress = truck.cargoProgress,
        },
    }
end

function World.applyEnvironmentSnapshot(bayDoor, truck)
    if type(bayDoor) ~= "table" or type(truck) ~= "table" then return false end
    local previousDoor = World.environmentSnapshot().bayDoor
    if not World.bayDoor:applySnapshot(bayDoor) then return false end
    if World.truck:applySnapshot(truck) then return true end
    World.bayDoor:applySnapshot(previousDoor)
    return false
end

function World.truckSnapshot()
    return World.truck:snapshot()
end

function World.snapshot()
    return { x = World.player.x, y = World.player.y, character = World.player.character }
end

local function warehousePlayer(player)
    if player == World.player and player.id == nil then player.id = 1 end
    return player
end

local function warehouseContext(assets)
    return { assets=assets or World._assets, obstacles=movementObstacles }
end

function World.warehouseAccess(player, state, intent)
    return WarehouseGameplay.access(warehousePlayer(player), state, intent, warehouseContext())
end

function World.warehouseCommand(player, state, intent)
    local okay, code, message = WarehouseGameplay.command(warehousePlayer(player), state, intent, warehouseContext())
    -- Local workshop authority authenticates a detached player view. Copy the
    -- successful seat/exit placement back to the actual local controller;
    -- remote Session players already arrive here by mutable reference.
    if okay and player ~= World.player and type(player) == "table"
        and player.id == (tonumber(World.player.id) or 1)
        and (intent.kind == "operate" or intent.kind == "release") then
        World.player.x, World.player.y = player.x, player.y
        World.player.moving = player.moving == true
        World.player.velocityX, World.player.velocityY = 0, 0
    end
    return okay, code, message
end

function World.forceReleaseForklift(player,state)
    local okay,code,exit=WarehouseGameplay.forceRelease(warehousePlayer(player),state,warehouseContext())
    if okay and exit and player ~= World.player and player.id == (tonumber(World.player.id) or 1) then
        World.player.x,World.player.y=player.x,player.y
        World.player.moving=false
        World.player.velocityX,World.player.velocityY=0,0
    end
    return okay,code,exit
end

function World.warehouseRackContext(player, state, rackId)
    return WarehouseGameplay.rackContext(warehousePlayer(player), state, rackId, warehouseContext())
end

function World.warehouseCandidate(state)
    return WarehouseGameplay.candidate(state)
end

function World.warehouseStackCandidate(state)
    return WarehouseGameplay.stackCandidate(state)
end

function World.warehouseNearRack(player, state)
    return WarehouseGameplay.nearRack(warehousePlayer(player), state)
end

function World.updateNetworkForklift(player, dt, directionX, directionY, assets, state, readOnly)
    if type(player) ~= "table" or type(state) ~= "table" then return false end
    warehousePlayer(player)
    World._assets, World._state = assets or World._assets, state
    local startX, startY = player.x, player.y
    local updated = WarehouseGameplay.move(player, dt, directionX, directionY, state,
        warehouseContext(assets), readOnly == true)
    if updated then
        PlayerController.observeExternalMove(player, startX, startY, player.moving, dt)
    end
    return updated
end

-- The authoritative App calls this before WorkPhone.update, including while
-- a GUI is open. Guests render replicated state without advancing construction.
function World.updateWarehouse(dt, state, assets)
    World._assets, World._state = assets or World._assets, state
    return WarehouseGameplay.update(dt, state, warehouseContext(assets))
end

return World
