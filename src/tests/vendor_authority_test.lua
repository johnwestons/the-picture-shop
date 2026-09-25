local VendorAuthority = require("src.vendor_authority")
local WorkshopAuthority = require("src.workshop_authority")
local Protocol = require("src.net.protocol")

local Test = {}

local function vendorWorld(context)
    local vendor = context.Customer.new(context.config.vendor)
    vendor.state = "waiting"
    vendor.visible = true
    vendor.x, vendor.y = 710, 340
    return {
        vendor = vendor,
        validateNetworkWorkshopAccess = function(player, _, resourceId)
            if resourceId ~= "vendor" then return false, "not_allowed", "Wrong resource." end
            local dx, dy = player.x - vendor.x, player.y - vendor.y
            if dx * dx + dy * dy > (vendor.interactionRadius + 10) ^ 2 then
                return false, "out_of_range", "Move closer to the supplier representative."
            end
            return true, "available", "Vendor is in range."
        end,
        resolveVendor = function(_, decision)
            return vendor:resolve(decision == "declined" and "declined" or "accepted")
        end,
    }
end

local function authorityFor(context, state, world, saves, prefix)
    return WorkshopAuthority.new({
        tokenGenerator = function(serial)
            return tostring(prefix or "vendor") .. "-lease-" .. tostring(serial)
        end,
        resources = {
            vendor = VendorAuthority.resource({
                state = state,
                world = world,
                save = function() saves.count = saves.count + 1 end,
            }),
        },
    })
end

function Test.run(context, check)
    local allCatalogsFit = true
    for categoryIndex = 1, #context.procurement.categories do
        local packetState = context.State.new()
        packetState.vendorCategory = categoryIndex
        local packet = Protocol.encode("workshop_grant", {
            sessionId = "vendor-packet-test", requestId = categoryIndex,
            resourceId = "vendor", granted = true,
            leaseId = "vendor-packet-lease", code = "granted",
            message = "Vendor catalog connected.", revision = 1,
            view = VendorAuthority.view(packetState),
        })
        allCatalogsFit = allCatalogsFit and packet ~= nil
            and #packet <= Protocol.MAX_PACKET_BYTES
            and Protocol.decode(packet) ~= nil
    end
    check("vendor_live_catalogs_fit_validated_multiplayer_packets", allCatalogsFit)

    local state = context.State.new()
    state.money = 1000
    state.vendorCategory = 1
    local world = vendorWorld(context)
    local saves = { count = 0 }
    local authority = authorityFor(context, state, world, saves, "stock")
    local worker = { id = 2, x = world.vendor.x, y = world.vendor.y }
    local other = { id = 3, x = world.vendor.x, y = world.vendor.y }

    local grant = authority:acquire(worker, {
        requestId = 1, resourceId = "vendor",
    }, {})
    local busy = authority:acquire(other, {
        requestId = 1, resourceId = "vendor",
    }, {})
    check("vendor_guest_acquires_host_catalog_with_exclusive_lease",
        grant.accepted and grant.resourceId == "vendor" and grant.data
        and grant.data.kind == "products" and grant.data.cash == 1000
        and grant.data.items[1].name == "House paper, 25 x 38 in, 20 lb, 1,000 sheets"
        and world.vendor.state == "reviewing"
        and not busy.accepted and busy.code == "resource_busy")

    local purchaseRequest = {
        requestId = 2,
        resourceId = "vendor",
        leaseId = grant.leaseId,
        action = "purchase_stock",
        args = { itemIndex = 1 },
        expectedRevision = grant.revision,
    }
    local purchase = authority:command(worker, purchaseRequest, {})
    local replay = authority:command(worker, purchaseRequest, {})
    local reused = authority:command(worker, {
        requestId = 2, resourceId = "vendor", leaseId = grant.leaseId,
        action = "purchase_stock", args = { itemIndex = 2 },
        expectedRevision = grant.revision,
    }, {})
    check("vendor_stock_purchase_is_host_owned_saved_and_exactly_once",
        purchase.accepted and purchase.code == "stock_purchased"
        and state.money == 900 and #state.procurement.orders == 1
        and state.procurement.orders[1].item == "house_sheets"
        and purchase.data.cash == 900 and saves.count == 1
        and replay.accepted and #state.procurement.orders == 1
        and not reused.accepted and reused.code == "request_id_reused")

    local wrongCatalog = authority:command(worker, {
        requestId = 3, resourceId = "vendor", leaseId = grant.leaseId,
        action = "purchase_machine", args = { itemIndex = 1 },
        expectedRevision = purchase.revision,
    }, {})
    worker.x = world.vendor.x + 1000
    local outOfRange = authority:command(worker, {
        requestId = 4, resourceId = "vendor", leaseId = grant.leaseId,
        action = "purchase_stock", args = { itemIndex = 2 },
        expectedRevision = purchase.revision,
    }, {})
    worker.x, state.money = world.vendor.x, 0
    local insufficient = authority:command(worker, {
        requestId = 5, resourceId = "vendor", leaseId = grant.leaseId,
        action = "purchase_stock", args = { itemIndex = 2 },
        expectedRevision = purchase.revision,
    }, {})
    check("vendor_guest_cannot_cross_catalog_buy_out_of_range_or_overspend",
        not wrongCatalog.accepted and wrongCatalog.code == "catalog_changed"
        and not outOfRange.accepted and outOfRange.code == "out_of_range"
        and not insufficient.accepted and insufficient.code == "purchase_blocked"
        and #state.procurement.orders == 1 and saves.count == 1)

    local released = authority:release(worker, {
        requestId = 6, resourceId = "vendor", leaseId = grant.leaseId, reason = "closed",
    }, {})
    check("vendor_guest_close_releases_lease_and_restores_waiting_salesperson",
        released.accepted and authority:leaseForResource("vendor") == nil
        and world.vendor.state == "waiting")

    local machineState = context.State.new()
    machineState.money = 1000000
    machineState.vendorCategory = #context.procurement.categories
    local machineWorld = vendorWorld(context)
    local machineSaves = { count = 0 }
    local machineAuthority = authorityFor(
        context, machineState, machineWorld, machineSaves, "machine")
    local machineWorker = { id = 2, x = machineWorld.vendor.x, y = machineWorld.vendor.y }
    local machineGrant = machineAuthority:acquire(machineWorker, {
        requestId = 1, resourceId = "vendor",
    }, {})
    local moneyBefore = machineState.money
    local machinesBefore = #machineState.machines.items
    local machinePurchaseRequest = {
        requestId = 2, resourceId = "vendor", leaseId = machineGrant.leaseId,
        action = "purchase_machine", args = { itemIndex = 1 },
        expectedRevision = machineGrant.revision,
    }
    local machinePurchase = machineAuthority:command(
        machineWorker, machinePurchaseRequest, {})
    local machineReplay = machineAuthority:command(
        machineWorker, machinePurchaseRequest, {})
    check("vendor_machine_purchase_is_host_owned_saved_and_exactly_once",
        machineGrant.accepted and machineGrant.data.kind == "machines"
        and machinePurchase.accepted and machinePurchase.code == "machine_purchased"
        and #machineState.machines.items == machinesBefore + 1
        and machineState.money == moneyBefore - machineGrant.data.items[1].price
        and machinePurchase.data.cash == machineState.money
        and machineSaves.count == 1 and machineReplay.accepted
        and #machineState.machines.items == machinesBefore + 1)

    local dismissed = machineAuthority:command(machineWorker, {
        requestId = 3, resourceId = "vendor", leaseId = machineGrant.leaseId,
        action = "dismiss", args = {}, expectedRevision = machinePurchase.revision,
    }, {})
    check("vendor_guest_can_dismiss_visit_through_host_authority",
        dismissed.accepted and dismissed.code == "dismissed"
        and machineWorld.vendor.state == "exiting" and machineSaves.count == 2)

    local screenState = context.State.new()
    screenState.vendorCategory = 1
    local screenView = VendorAuthority.view(screenState)
    context.inputContext.workshopRemoteScreen.enter({
        resourceId = "vendor", leaseId = "screen-vendor-lease", revision = 1,
        message = "Vendor connected.", view = screenView,
    }, screenState)
    local sent = {}
    local function send(action, arguments)
        sent[#sent + 1] = { action = action, arguments = arguments }
        return true
    end
    local buyX, buyY = context.inputContext.workshopRemoteScreen.vendorBuyCenter(1)
    local clicked = context.inputContext.workshopRemoteScreen.mousepressed(
        screenState, buyX, buyY, 1, send)
    context.inputContext.workshopRemoteScreen.applyResult({
        resourceId = "vendor", action = "purchase_stock", accepted = true,
        revision = 2, message = "Purchased.", view = screenView,
    })
    local dismissX, dismissY = context.inputContext.workshopRemoteScreen.vendorDismissCenter()
    local dismissClicked = context.inputContext.workshopRemoteScreen.mousepressed(
        screenState, dismissX, dismissY, 1, send)
    check("vendor_remote_screen_sends_only_catalog_index_and_dismiss_intent",
        clicked and dismissClicked and #sent == 2
        and sent[1].action == "purchase_stock" and sent[1].arguments.itemIndex == 1
        and sent[2].action == "dismiss" and next(sent[2].arguments) == nil)
    context.inputContext.workshopRemoteScreen.clear()

    check("vendor_world_interaction_maps_to_authority_resource",
        context.world.workshopResourceId("vendor") == "vendor")
end

return Test
