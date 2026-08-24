local Config = require("src.config")
local BayDoor = require("src.bay_door")
local CutterPlacement = require("src.cutter_placement")
local CutterZones = require("src.cutter_zones")
local Customer = require("src.customer")
local Interaction = require("src.interaction")
local JobService = require("src.job_service")
local Navigation = require("src.navigation")
local PalletLogistics = require("src.pallet_logistics")
local PalletJack = require("src.pallet_jack")
local Procurement = require("src.procurement")
local Truck = require("src.truck")
local WrapperPlacement = require("src.wrapper_placement")
local Wrapper = require("src.wrapper")
local WorldRenderer = require("src.world_renderer")

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
}

local function movementObstacles(state, excludeJack, inflate, excludeCutter, excludeWrapper, excludedPalletId)
    inflate = inflate or { x = 0, y = 0 }
    if type(inflate) == "number" then inflate = { x = inflate, y = inflate } end
    local obstacles = {}
    if not excludeCutter then
        local cutterObstacle = CutterPlacement.obstacle(state, Config.cutterPlacement)
        if cutterObstacle then obstacles[#obstacles + 1] = cutterObstacle end
    end
    if not excludeWrapper then
        local wrapperObstacle = WrapperPlacement.obstacle(state, Config.wrapperPlacement)
        if wrapperObstacle then obstacles[#obstacles + 1] = wrapperObstacle end
    end
    local customerObstacle = World.customer:getObstacle()
    if customerObstacle then obstacles[#obstacles + 1] = customerObstacle end
    local vendorObstacle = World.vendor:getObstacle()
    if vendorObstacle then obstacles[#obstacles + 1] = vendorObstacle end
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
        targets.cutter = CutterPlacement.interaction(World.player, World._state, Config.cutterPlacement)
        targets.skidWrapper = WrapperPlacement.interaction(World.player, World._state, Config.wrapperPlacement)
        targets.palletJack = PalletJack.interaction(World.player, World._state, Config.palletJack)
    end
    return targets
end

function World.load(position)
    World.player.x = position and position.x or Config.player.spawnX
    World.player.y = position and position.y or Config.player.spawnY
    World.player.animationClock = 0
    World.bayDoor:reset()
    World.truck:reset()
    World.customer:reset()
    World.vendor:reset()
    World.selectedInteraction = nil
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
        if job.status == "awaiting_delivery" and deliveryStatus ~= "received" then
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
    local pickup = truckMode == "pickup" and job or nil
    if event == "request_bay_open" then
        if World.bayDoor.state == "closed" then World.bayDoor:open() end
        if state then state.message = pickup
            and "Pickup truck arrived. Opening the loading bay..."
            or "Delivery truck arrived. Opening the loading bay..." end
    elseif event == "backing_started" then
        if pickup then
            JobService.setPickupStatus(pickup, "backing")
        elseif job and job.delivery then job.delivery.status = "backing" end
        if purchase and purchase.delivery then purchase.delivery.status = "backing" end
        if state then state.message = pickup
            and "The customer pickup truck is backing into the loading bay."
            or "The delivery truck is backing into the loading bay." end
        saveNeeded = true
    elseif event == "parked" then
        if pickup then
            JobService.setPickupStatus(pickup, "at_bay", "arrivedAt", os.time())
        elseif job and job.delivery then job.delivery.status = "at_bay" end
        if purchase and purchase.delivery then purchase.delivery.status = "at_bay" end
        if state then state.message = pickup
            and "Pickup truck parked. Open its rear cargo door and load the wrapped pallets."
            or "Truck parked. Open its rear cargo door to unload." end
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
    World._state = state
    local player = World.player
    local jack = PalletJack.ensure(state, Config.palletJack)
    local cutter = CutterPlacement.ensure(state, Config.cutterPlacement)
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
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
        player.x, player.y = CutterPlacement.operatorPosition(state, Config.cutterPlacement)
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
        player.x, player.y = WrapperPlacement.operatorPosition(state, Config.wrapperPlacement)
        player.moving = wrapper.inMotion
        player.facing = player.x < wrapper.x and 1 or -1
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
        player.facing = (jack.direction == "northeast" or jack.direction == "southeast") and 1 or -1
    else
        player.moving = directionX ~= 0 or directionY ~= 0
    end
    if player.moving and not jack.operating and not cutter.moving and not wrapper.moving then
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
    local customerEvent = World.customer:update(dt, player)
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
        World.customer:reset()
    end
    local category = Procurement.category(state and state.vendorCategory)
    World.vendor.character = category.character
    local vendorEvent = World.vendor:update(dt, player)
    if vendorEvent == "arrived" and state then
        state.message = category.salesman .. " is waiting at reception with the " .. category.name:lower() .. " catalog."
    elseif vendorEvent == "exited" and state then
        state.vendorCategory = state.vendorCategory % #Procurement.categories + 1
        World.vendor:reset()
        state.message = "The salesman left. Another supplier representative will visit soon."
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

function World.resolveVendor(state)
    if not World.vendor:resolve("accepted") then return false end
    if state then state.message = "The supplier representative is heading out." end
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
    if World.truck.state ~= "cargo_open" then return false end
    local job = activeJobById(state, World.truck.jobId)
    return job ~= nil or Procurement.orderById(state, World.truck.jobId) ~= nil
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
    local succeeded, action, pallet = PalletJack.use(state, Config.palletJack, function(x, y)
        return World.isPalletPlacementClear(state, assets, x, y)
    end)
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
        state.message = "Lifted " .. pallet.id .. ". Drive it to a clear warehouse position."
    elseif action == "lowered" then
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
    local jack = PalletJack.ensure(state, Config.palletJack)
    if jack.operating then
        state.message = "Park the pallet jack before relocating the cutter."
        return false
    end
    if cutterHasPaper(state) then
        state.message = "Unload the paper and clear the cutting bed before relocating the cutter."
        return false
    end
    if not CutterPlacement.beginMove(state, Config.cutterPlacement) then return false end
    World.player.x, World.player.y = CutterPlacement.operatorPosition(state, Config.cutterPlacement)
    state.message = "Cutter relocation mode: move slowly, Q rotates, and E locks it in place."
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

function World.placeCutter(state)
    if not CutterPlacement.place(state, Config.cutterPlacement) then return false end
    World.player.x, World.player.y = CutterPlacement.operatorPosition(state, Config.cutterPlacement)
    state.message = "Cutter locked in its new floor position."
    return true
end

function World.cutterSnapshot(state)
    return CutterPlacement.snapshot(state, Config.cutterPlacement)
end

function World.beginWrapperMove(state)
    if not Wrapper.canRelocate(state) then return false end
    if PalletJack.ensure(state, Config.palletJack).operating then
        state.message = "Park the pallet jack before relocating the skid wrapper."
        return false
    end
    if not WrapperPlacement.beginMove(state, Config.wrapperPlacement) then return false end
    World.player.x, World.player.y = WrapperPlacement.operatorPosition(state, Config.wrapperPlacement)
    state.message = "Wrapper relocation mode: move slowly, Q rotates, and E locks it in place."
    return true
end

function World.wrapperNearby(state)
    local wrapper = WrapperPlacement.ensure(state, Config.wrapperPlacement)
    local dx, dy = World.player.x - wrapper.x, World.player.y - wrapper.y
    return dx * dx + dy * dy <= Config.wrapperPlacement.interactionRadius ^ 2
end

function World.rotateWrapper(state)
    local succeeded, direction = WrapperPlacement.rotate(state, Config.wrapperPlacement)
    if not succeeded then return false end
    if state.wrapper.moving then World.player.x, World.player.y = WrapperPlacement.operatorPosition(state, Config.wrapperPlacement) end
    state.message = "Skid wrapper rotated " .. direction .. "."
    return true
end

function World.placeWrapper(state)
    if not WrapperPlacement.place(state, Config.wrapperPlacement) then return false end
    World.player.x, World.player.y = WrapperPlacement.operatorPosition(state, Config.wrapperPlacement)
    state.message = "Skid wrapper locked in its new floor position."
    return true
end

function World.wrapperSnapshot(state)
    return WrapperPlacement.snapshot(state, Config.wrapperPlacement)
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
