-- Game integration checks with the original assertions and shared scenario state.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.receivingState = Context.context.State.new()
    Context.receivingState.money = 1000
    Context.receivingJob = Context.jobs.createOffer({
        id = "JOB-RECEIVING",
        company = "Receiving Lane Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500, 500, 500, 500, 500 },
    })
    Context.jobs.accept(Context.receivingJob)
    Context.receivingState.jobs.active[1] = Context.receivingJob
    for index, pallet in ipairs(Context.receivingJob.pallets) do
        local succeeded, unloadedPallet = Context.context.PalletLogistics.unload(
            Context.receivingState, Context.receivingJob.id, pallet.id,
            Context.context.config.palletLogistics.spawnPoints, Context.context.config.palletLogistics.unloadOrigin)
        local lane = Context.context.config.palletLogistics.spawnPoints[index]
        Context.check("receiving_lane_unique_customer_" .. index, succeeded
            and unloadedPallet.world.x == lane.x
            and unloadedPallet.world.y == lane.y)
    end
    Context.fullReceiving = Context.context.Receiving.snapshot(Context.receivingState,
        Context.context.config.palletLogistics.spawnPoints, Context.context.config.palletLogistics.receivingLaneRadius)
    Context.check("receiving_lanes_report_full", Context.fullReceiving.open == 0 and Context.fullReceiving.total == 5)

    Context.vendorBought, Context.blockedOrder = Context.context.procurement.buy(Context.receivingState, 3, 1)
    Context.check("receiving_vendor_order_setup", Context.vendorBought and Context.blockedOrder.status == "awaiting_delivery")
    Context.stockBeforeBlocked = Context.receivingState.inventory.stock.shipping_cartons or 0
    Context.blockedUnload, Context.blockedReason = Context.context.procurement.unload(
        Context.receivingState, Context.blockedOrder.id, Context.blockedOrder.pallets[1].id,
        Context.context.config.palletLogistics.spawnPoints, Context.context.config.palletLogistics.unloadOrigin)
    Context.check("receiving_full_blocks_vendor_unload", not Context.blockedUnload
        and tostring(Context.blockedReason):find("Receiving lanes are full", 1, true) ~= nil
        and Context.blockedOrder.status == "awaiting_delivery"
        and Context.blockedOrder.delivery.status == "awaiting_schedule"
        and Context.blockedOrder.pallets[1].location == "awaiting_delivery"
        and (Context.receivingState.inventory.stock.shipping_cartons or 0) == Context.stockBeforeBlocked)

    Context.movedPallet = Context.receivingJob.pallets[1]
    Context.check("receiving_lane_pallet_lift_for_move",
        Context.context.PalletState.transition(Context.receivingState, Context.movedPallet, "on_pallet_jack"))
    Context.movedWorld = {
        x = 820, y = 580, direction = "southeast", rotation = 4,
        fromX = 820, fromY = 580, spawnProgress = 1,
    }
    Context.check("receiving_lane_pallet_moved_clear",
        Context.context.PalletState.transition(Context.receivingState, Context.movedPallet, "warehouse", { world = Context.movedWorld }))
    Context.reopenedReceiving = Context.context.Receiving.snapshot(Context.receivingState,
        Context.context.config.palletLogistics.spawnPoints, Context.context.config.palletLogistics.receivingLaneRadius)
    Context.check("receiving_lane_reopens_after_move", Context.reopenedReceiving.open == 1
        and not Context.reopenedReceiving.lanes[1].occupied)
    Context.vendorUnloaded, Context.receivedVendorPallet = Context.context.procurement.unload(
        Context.receivingState, Context.blockedOrder.id, Context.blockedOrder.pallets[1].id,
        Context.context.config.palletLogistics.spawnPoints, Context.context.config.palletLogistics.unloadOrigin)
    Context.check("receiving_mixed_delivery_reuses_clear_lane", Context.vendorUnloaded
        and Context.receivedVendorPallet.world.x == Context.context.config.palletLogistics.spawnPoints[1].x
        and Context.receivedVendorPallet.world.y == Context.context.config.palletLogistics.spawnPoints[1].y
        and Context.receivingState.inventory.stock.shipping_cartons == Context.stockBeforeBlocked + 100
        and Context.context.PalletState.validate(Context.receivingState))

    Context.serviceState = Context.context.State.new()
    Context.serviceState.reputation.score = 20
    Context.serviceState.screen = "world"
    Context.serviceOffer = Context.context.jobService.createNextOffer(Context.serviceState, 111)
    Context.serviceOfferValue = Context.serviceOffer and Context.serviceOffer.quote.totalPrice
    Context.check("paperwork_offer_created", Context.serviceOffer
        and Context.serviceOffer.id == "JOB-0001"
        and Context.serviceOffer.company == "Blue Ridge Packaging"
        and Context.serviceOffer.quote.totalPrice == 648
        and #Context.serviceOffer.pallets == 2
        and Context.serviceOffer.deliveryService.id == "express"
        and Context.serviceOffer.deliveryService.delayHours >= 2
        and Context.serviceOffer.deliveryService.delayHours <= 6)
    Context.acceptX, Context.acceptY = Context.context.jobOfferScreen.buttonCenter("accept")
    Context.check("paperwork_accept_hit_target", Context.context.jobOfferScreen.hitTest(Context.acceptX, Context.acceptY) == "accept")
    Context.check("paperwork_ignores_outside_click", Context.context.jobOfferScreen.hitTest(10, 10) == nil)
    Context.cashBeforeOffer = Context.serviceState.money
    Context.check("paperwork_service_accept", Context.context.jobService.acceptOffer(Context.serviceState, Context.serviceOffer, 222))
    Context.check("paperwork_accept_records_job", #Context.serviceState.jobs.active == 1
        and Context.serviceState.jobs.active[1].status == "awaiting_delivery"
        and Context.serviceState.jobs.active[1].delivery.status == "pending_arrival"
        and not Context.context.jobService.deliveryReady(Context.serviceState, Context.serviceOffer)
        and Context.serviceState.accountsReceivable == Context.serviceOfferValue
        and Context.serviceState.money == Context.cashBeforeOffer
        and Context.serviceState.nextJobId == 2)
    Context.check("paperwork_cannot_accept_twice", not Context.context.jobService.acceptOffer(Context.serviceState, Context.serviceOffer, 333)
        and #Context.serviceState.jobs.active == 1
        and Context.serviceState.accountsReceivable == Context.serviceOfferValue)
    Context.serviceDecline = Context.context.jobService.createNextOffer(Context.serviceState, 444)
    Context.standardState = Context.context.State.new()
    Context.standardState.reputation.score = 20
    Context.standardState.nextJobId = 3
    Context.standardOffer = Context.context.jobService.createNextOffer(Context.standardState, 445)
    Context.check("job_delivery_service_timeframes", Context.serviceDecline.deliveryService.id == "quick"
        and Context.serviceDecline.deliveryService.delayHours >= 6
        and Context.serviceDecline.deliveryService.delayHours <= 12
        and Context.standardOffer.deliveryService.id == "standard"
        and Context.standardOffer.deliveryService.delayHours >= 12
        and Context.standardOffer.deliveryService.delayHours <= 24)
    Context.check("paperwork_service_decline", Context.context.jobService.declineOffer(Context.serviceState, Context.serviceDecline, 555))
    Context.check("paperwork_decline_records_job", #Context.serviceState.jobs.declined == 1
        and Context.serviceState.jobs.declined[1].id == "JOB-0002"
        and Context.serviceState.jobs.declined[1].pallets[1].status == "cancelled"
        and Context.serviceState.jobs.declined[1].pallets[1].location == "none"
        and Context.serviceState.accountsReceivable == Context.serviceOfferValue
        and Context.serviceState.nextJobId == 3)
    Context.purchaseSucceeded, Context.purchaseOrder = Context.context.procurement.buy(Context.serviceState, 1, 1)
    Context.check("office_purchase_order_setup", Context.purchaseSucceeded and Context.purchaseOrder.id == "PO-0001")

    Context.navigationState = Context.context.State.new()
    Context.context.computerScreen.enter(Context.navigationState)
    Context.allTabsReachable = true
    for _, tabId in ipairs({
        "active", "completed", "deliveries", "estimating", "calendar",
        "inventory", "www", "email", "bills",
    }) do
        local result = Context.selectComputerTab(Context.context.computerScreen, Context.navigationState, tabId)
        Context.allTabsReachable = Context.allTabsReachable and result and result.tab == tabId
            and type(Context.context.computerScreen.activeUrl()) == "string"
            and Context.context.computerScreen.activeUrl():find("www.thecritternet.com", 1, true) == 1
    end
    Context.check("computer_dropdown_reaches_every_section", Context.allTabsReachable)

    Context.context.computerScreen.enter(Context.serviceState)
    Context.arrowX, Context.arrowY = Context.context.computerScreen.dropdownCenter()
    Context.dropdownOpened = Context.context.computerScreen.mousepressed(Context.serviceState, Context.arrowX, Context.arrowY, 1)
    Context.activeTabX, Context.activeTabY = Context.context.computerScreen.tabCenter("active")
    Context.activeResult = Context.context.computerScreen.mousepressed(
        Context.serviceState, Context.activeTabX, Context.activeTabY, 1)
    Context.check("computer_dropdown_opens_from_address_arrow", Context.dropdownOpened
        and Context.dropdownOpened.action == "dropdown_opened")
    Context.check("computer_active_tab_click", Context.activeResult and Context.activeResult.tab == "active"
        and Context.context.computerScreen.activeUrl()
            == "www.thecritternet.com/job-desk/active")
    Context.rowX, Context.rowY = Context.context.computerScreen.rowCenter(1)
    Context.selectedActive = Context.context.computerScreen.mousepressed(Context.serviceState, Context.rowX, Context.rowY, 1)
    Context.check("computer_job_row_click", Context.selectedActive
        and Context.selectedActive.action == "select"
        and Context.selectedActive.job.id == "JOB-0001")
    Context.check("computer_job_packaging_instructions", Context.context.computerScreen.packagingText(Context.serviceOffer)
        == "Boxed paper on pallets; stretch-wrap each finished pallet"
        and Context.context.computerScreen.packagingText({ packaging = "flat" })
            == "Flat stacked on pallets; stretch-wrap each finished pallet")
    Context.layoutPallets = {}
    for index = 1, 5 do Context.layoutPallets[index] = { number = index } end
    Context.printDetailLayout = Context.context.computerScreen.jobDetailLayout({
        sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 7, height = 10 },
        stockSpec = { description = "100 lb gloss cover" },
        packaging = "boxed",
        press = {
            colors = 4,
            colorSequence = { "Warm Red", "Process Blue", "Metallic Gold", "Black" },
            actual = { impressions = 1575, spoilage = 75 },
        },
        quote = { orderedCopies = 1500, suppliedSheets = 1575, totalSheets = 1575 },
        pallets = Context.layoutPallets,
    })
    Context.check("computer_print_job_detail_text_clears_pallet_table",
        Context.printDetailLayout.textBottom < Context.printDetailLayout.tableY)
    Context.check("computer_print_job_detail_table_clears_action_button",
        Context.printDetailLayout.tableBottom + 4 <= Context.printDetailLayout.actionTop,
        string.format("tableBottom=%.1f actionTop=%.1f",
            Context.printDetailLayout.tableBottom, Context.printDetailLayout.actionTop))
    Context.completeX, Context.completeY = Context.context.computerScreen.completeCenter()
    Context.completionResult = Context.context.computerScreen.mousepressed(Context.serviceState, Context.completeX, Context.completeY, 1)
    Context.check("computer_completion_gate", Context.completionResult
        and Context.completionResult.action == "completion_blocked"
        and Context.completionResult.job.id == "JOB-0001")
    Context.check("computer_completed_tab_click",
        Context.selectComputerTab(Context.context.computerScreen, Context.serviceState, "completed").tab == "completed")
    Context.check("computer_deliveries_tab_click",
        Context.selectComputerTab(Context.context.computerScreen, Context.serviceState, "deliveries").tab == "deliveries")
    Context.selectedDelivery = Context.context.computerScreen.mousepressed(Context.serviceState, Context.rowX, Context.rowY, 1)
    Context.check("computer_inbound_delivery_list", Context.selectedDelivery
        and Context.selectedDelivery.job.status == "awaiting_delivery")
    Context.purchaseRowX, Context.purchaseRowY = Context.context.computerScreen.rowCenter(2)
    Context.selectedPurchase = Context.context.computerScreen.mousepressed(
        Context.serviceState, Context.purchaseRowX, Context.purchaseRowY, 1)
    Context.check("computer_purchase_order_delivery_list", Context.selectedPurchase
        and Context.selectedPurchase.job == Context.purchaseOrder
        and Context.context.computerScreen.statusLabel(Context.purchaseOrder.delivery.status)
            == "Awaiting truck schedule")
end

return Component
