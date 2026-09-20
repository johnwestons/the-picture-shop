local Protocol = require("src.net.protocol")
local TruckAuthority = require("src.truck_authority")
local WorkshopAuthority = require("src.workshop_authority")

local Test = {}

local function parkTruck(context, state, mode, jobId, truckState)
    context.world.load()
    local truck = context.world.truck
    truck.state = truckState or (mode == "machine_delivery" and "parked_closed" or "cargo_open")
    truck.mode = mode
    truck.jobId = jobId
    truck.backingProgress = 1
    truck.cargoProgress = truck.state == "cargo_open" and 1 or 0
    context.world._state = state
    local target = assert(truck:getInteraction())
    return { id = 2, x = target.x, y = target.y },
        { id = 3, x = target.x, y = target.y }
end

local function authorityFor(state, world, saves, prefix)
    return WorkshopAuthority.new({
        tokenGenerator = function(serial)
            return tostring(prefix) .. "-truck-lease-" .. tostring(serial)
        end,
        resources = {
            truck = TruckAuthority.resource({
                state = state,
                world = world,
                save = function() saves.count = saves.count + 1 end,
            }),
        },
    })
end

local function makeDelivery(context, state, id, palletCount)
    local counts = {}
    for index = 1, palletCount do counts[index] = 500 + index end
    local job = assert(context.jobs.createOffer({
        id = id,
        company = "Authority Delivery Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = counts,
        packaging = "flat",
    }))
    assert(context.jobService.acceptOffer(state, job, 100))
    return job
end

local function acquire(authority, worker)
    return authority:acquire(worker, { requestId = 1, resourceId = "truck" }, {})
end

function Test.run(context, check)
    local deliveryState = context.State.new()
    local delivery = makeDelivery(context, deliveryState, "TRUCK-AUTH-DELIVERY", 4)
    local worker, other = parkTruck(
        context, deliveryState, "delivery", delivery.id, "cargo_open")
    local deliverySaves = { count = 0 }
    local deliveryAuthority = authorityFor(
        deliveryState, context.world, deliverySaves, "delivery")
    local grant = acquire(deliveryAuthority, worker)
    local busy = acquire(deliveryAuthority, other)
    check("truck_guest_acquires_paged_host_manifest_with_exclusive_lease",
        grant.accepted and grant.data and grant.data.mode == "delivery"
        and grant.data.page == 1 and grant.data.pageCount == 2
        and #grant.data.items == 3 and grant.data.remaining == 4
        and not busy.accepted and busy.code == "resource_busy")

    local nextPage = deliveryAuthority:command(worker, {
        requestId = 2, resourceId = "truck", leaseId = grant.leaseId,
        action = "page_next", args = {}, expectedRevision = grant.revision,
    }, {})
    local moveRequest = {
        requestId = 3, resourceId = "truck", leaseId = grant.leaseId,
        action = "move_item", args = { itemIndex = 1 },
        expectedRevision = nextPage.revision,
    }
    local moved = deliveryAuthority:command(worker, moveRequest, {})
    local replay = deliveryAuthority:command(worker, moveRequest, {})
    check("truck_delivery_row_is_host_resolved_saved_and_exactly_once",
        nextPage.accepted and nextPage.data.page == 2
        and moved.accepted and moved.code == "cargo_unloaded"
        and delivery.pallets[4].location == "warehouse"
        and delivery.pallets[1].location == "awaiting_delivery"
        and deliveryState.inventory.rawPallets == 1 and moved.data.remaining == 3
        and replay.accepted and deliveryState.inventory.rawPallets == 1
        and deliverySaves.count == 1)

    worker.x = worker.x + 1000
    local outOfRange = deliveryAuthority:command(worker, {
        requestId = 4, resourceId = "truck", leaseId = grant.leaseId,
        action = "page_previous", args = {}, expectedRevision = moved.revision,
    }, {})
    worker.x = other.x
    local closeBlocked = deliveryAuthority:command(worker, {
        requestId = 5, resourceId = "truck", leaseId = grant.leaseId,
        action = "close_truck", args = {}, expectedRevision = moved.revision,
    }, {})
    check("truck_host_revalidates_range_and_remaining_cargo",
        not outOfRange.accepted and outOfRange.code == "out_of_range"
        and not closeBlocked.accepted and closeBlocked.code == "cargo_remaining"
        and deliverySaves.count == 1)

    local cleanup = deliveryAuthority:cleanupPlayer(worker, "disconnected", {})
    local reacquired = deliveryAuthority:acquire(other, {
        requestId = 2, resourceId = "truck",
    }, {})
    check("truck_disconnect_releases_manifest_for_another_guest",
        #cleanup == 1 and cleanup[1].resourceId == "truck"
        and reacquired.accepted and reacquired.data.page == 1)

    local pickupState = context.State.new()
    local pickup = makeDelivery(context, pickupState, "TRUCK-AUTH-PICKUP", 1)
    local pickupPallet = pickup.pallets[1]
    pickup.status = "pickup_in_progress"
    pickup.pickup = { status = "cargo_open" }
    pickupPallet.remainingSheets = 0
    pickupPallet.finishedSheets = pickupPallet.initialSheets
    pickupPallet.status = "wrapped"
    pickupPallet.wrapped = true
    pickupPallet.location = "warehouse"
    pickupPallet.world = { x = 500, y = 500, direction = "northwest", rotation = 1,
        fromX = 500, fromY = 500, spawnProgress = 1 }
    pickupState.inventory.finishedPallets = 1
    local pickupWorker = parkTruck(
        context, pickupState, "pickup", pickup.id, "cargo_open")
    local pickupSaves = { count = 0 }
    local pickupAuthority = authorityFor(pickupState, context.world, pickupSaves, "pickup")
    local pickupGrant = acquire(pickupAuthority, pickupWorker)
    local loaded = pickupAuthority:command(pickupWorker, {
        requestId = 2, resourceId = "truck", leaseId = pickupGrant.leaseId,
        action = "move_item", args = { itemIndex = 1 },
        expectedRevision = pickupGrant.revision,
    }, {})
    local closed = pickupAuthority:command(pickupWorker, {
        requestId = 3, resourceId = "truck", leaseId = pickupGrant.leaseId,
        action = "close_truck", args = {}, expectedRevision = loaded.revision,
    }, {})
    check("truck_pickup_load_and_release_are_host_owned_and_saved",
        pickupGrant.accepted and loaded.accepted and loaded.code == "pallet_loaded"
        and pickupPallet.location == "outbound_truck"
        and pickupState.inventory.finishedPallets == 0
        and loaded.data.remaining == 0 and loaded.data.canClose
        and closed.accepted and closed.code == "truck_released"
        and context.world.truckSnapshot().state == "cargo_closing"
        and pickupSaves.count == 2)

    local machineState = context.State.new()
    machineState.money = 1000000
    local ordered, machineOrder = context.machineFleet.orderOnline(machineState, 1)
    local machineWorker = ordered and parkTruck(
        context, machineState, "machine_delivery", machineOrder.id, "parked_closed")
    local machineSaves = { count = 0 }
    local machineAuthority = authorityFor(machineState, context.world, machineSaves, "machine")
    local machineGrant = acquire(machineAuthority, machineWorker)
    local machineMove = machineAuthority:command(machineWorker, {
        requestId = 2, resourceId = "truck", leaseId = machineGrant.leaseId,
        action = "move_item", args = { itemIndex = 1 },
        expectedRevision = machineGrant.revision,
    }, {})
    local machineClose = machineAuthority:command(machineWorker, {
        requestId = 3, resourceId = "truck", leaseId = machineGrant.leaseId,
        action = "close_truck", args = {}, expectedRevision = machineMove.revision,
    }, {})
    check("truck_machine_flatbed_receive_and_release_are_host_owned",
        ordered and machineGrant.accepted and machineGrant.data.mode == "machine_delivery"
        and machineMove.accepted and machineOrder.delivery.status == "received"
        and machineMove.data.remaining == 0 and machineMove.data.canClose
        and machineClose.accepted and context.world.truckSnapshot().state == "departing"
        and machineSaves.count == 2)

    local vendorState = context.State.new()
    vendorState.money = 1000
    local vendorPaperBefore = vendorState.inventory.stock.house_sheets or 0
    local bought, vendorOrder = context.procurement.buy(vendorState, 1, 1)
    local vendorWorker = bought and parkTruck(
        context, vendorState, "vendor_delivery", vendorOrder.id, "cargo_open")
    local vendorSaves = { count = 0 }
    local vendorAuthority = authorityFor(vendorState, context.world, vendorSaves, "vendor")
    local vendorGrant = acquire(vendorAuthority, vendorWorker)
    local vendorMove = vendorAuthority:command(vendorWorker, {
        requestId = 2, resourceId = "truck", leaseId = vendorGrant.leaseId,
        action = "move_item", args = { itemIndex = 1 },
        expectedRevision = vendorGrant.revision,
    }, {})
    check("truck_vendor_delivery_updates_host_inventory_once",
        bought and vendorGrant.accepted and vendorGrant.data.mode == "vendor_delivery"
        and vendorMove.accepted
        and vendorState.inventory.stock.house_sheets == vendorPaperBefore + 1000
        and vendorOrder.pallets[1].location == "warehouse"
        and vendorSaves.count == 1)

    local packet = Protocol.encode("workshop_grant", {
        sessionId = "truck-packet-test", requestId = 1, resourceId = "truck",
        granted = true, leaseId = "truck-packet-lease", code = "granted",
        message = "Truck manifest connected.", revision = 1,
        view = grant.data,
    })
    local movePacket = Protocol.encode("workshop_command", {
        sessionId = "truck-packet-test", commandId = 2,
        leaseId = "truck-packet-lease", resourceId = "truck",
        action = "move_item", expectedRevision = 1, itemIndex = 1,
    })
    local pagePacket = Protocol.encode("workshop_command", {
        sessionId = "truck-packet-test", commandId = 3,
        leaseId = "truck-packet-lease", resourceId = "truck",
        action = "page_next", expectedRevision = 1,
    })
    local closePacket = Protocol.encode("workshop_command", {
        sessionId = "truck-packet-test", commandId = 4,
        leaseId = "truck-packet-lease", resourceId = "truck",
        action = "close_truck", expectedRevision = 1,
    })
    local spoofedCargoId = Protocol.encode("workshop_command", {
        sessionId = "truck-packet-test", commandId = 5,
        leaseId = "truck-packet-lease", resourceId = "truck",
        action = "move_item", expectedRevision = 1, itemIndex = 1,
        palletId = delivery.pallets[1].id,
    })
    grant.data.items[1].cargoId = delivery.pallets[1].id
    local leakedManifestId = Protocol.encode("workshop_grant", {
        sessionId = "truck-packet-test", requestId = 1, resourceId = "truck",
        granted = true, leaseId = "truck-packet-lease", code = "granted",
        message = "Truck manifest connected.", revision = 1, view = grant.data,
    })
    grant.data.items[1].cargoId = nil
    local openRequest = Protocol.encode("interaction_request", {
        sessionId = "truck-packet-test", requestId = 6,
        targetKind = "truckCargoDoor", desiredState = "open",
    })
    check("truck_live_paged_manifest_fits_validated_multiplayer_packet",
        packet ~= nil and #packet <= Protocol.MAX_PACKET_BYTES
        and Protocol.decode(packet) ~= nil
        and movePacket ~= nil and pagePacket ~= nil and closePacket ~= nil
        and spoofedCargoId == nil and leakedManifestId == nil
        and openRequest ~= nil)

    context.inputContext.workshopRemoteScreen.enter({
        resourceId = "truck", leaseId = "screen-truck-lease", revision = 1,
        message = "Truck manifest connected.", view = grant.data,
    }, deliveryState)
    local sent = {}
    local function send(action, arguments)
        sent[#sent + 1] = { action = action, arguments = arguments }
        return true
    end
    local moveX, moveY = context.inputContext.workshopRemoteScreen.truckMoveCenter(1)
    context.inputContext.workshopRemoteScreen.mousepressed(
        deliveryState, moveX, moveY, 1, send)
    context.inputContext.workshopRemoteScreen.applyResult({
        resourceId = "truck", action = "move_item", accepted = true,
        revision = 2, message = "Moved.", view = grant.data,
    })
    local nextX, nextY = context.inputContext.workshopRemoteScreen.truckPageCenter("next")
    context.inputContext.workshopRemoteScreen.mousepressed(
        deliveryState, nextX, nextY, 1, send)
    local closeView = TruckAuthority.view(pickupState, context.world, 1)
    closeView.mode, closeView.state, closeView.remaining, closeView.canClose =
        "pickup", "cargo_open", 0, true
    context.inputContext.workshopRemoteScreen.applyResult({
        resourceId = "truck", action = "page_next", accepted = true,
        revision = 3, message = "Paged.", view = closeView,
    })
    local closeX, closeY = context.inputContext.workshopRemoteScreen.truckCloseCenter()
    context.inputContext.workshopRemoteScreen.mousepressed(
        deliveryState, closeX, closeY, 1, send)
    check("truck_remote_screen_sends_only_bounded_manifest_intent",
        #sent == 3 and sent[1].action == "move_item"
        and sent[1].arguments.itemIndex == 1
        and sent[2].action == "page_next" and next(sent[2].arguments) == nil
        and sent[3].action == "close_truck" and next(sent[3].arguments) == nil)
    context.inputContext.workshopRemoteScreen.clear()

    context.world.truck.state = "parked_closed"
    context.world.truck.cargoProgress = 0
    local doorTarget = context.world.truck:getInteraction()
    local doorWorker = { id = 2, x = doorTarget.x, y = doorTarget.y }
    local closeWithoutManifest = context.world.performNetworkInteraction(
        doorWorker, vendorState, "truckCargoDoor", "closed")
    local opened, openCode = context.world.performNetworkInteraction(
        doorWorker, vendorState, "truckCargoDoor", "open")
    local movingMapping = context.world.workshopResourceId("truckCargoDoor")
    context.world.truck.state = "cargo_open"
    context.world.truck.cargoProgress = 1
    local openMapping = context.world.workshopResourceId("truckCargoDoor")
    check("truck_cargo_door_open_is_host_validated_before_manifest_authority",
        not closeWithoutManifest and opened and openCode == "accepted"
        and context.world.truckSnapshot().state == "cargo_open"
        and movingMapping == nil and openMapping == "truck")

    context.world.load()
end

return Test
