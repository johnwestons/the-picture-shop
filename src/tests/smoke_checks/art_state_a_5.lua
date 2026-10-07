-- Game integration checks with the original assertions and shared scenario state.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.artStateA, Context.artStateB = Context.context.State.new(), Context.context.State.new()
    Context.artStateA.reputation.score, Context.artStateB.reputation.score = 20, 20
    Context.artStateA.jobs.artworkSeed, Context.artStateB.jobs.artworkSeed = 101, 90901
    Context.differentArt = false
    for sequence = 1, 12 do
        Context.artStateA.nextJobId, Context.artStateB.nextJobId = sequence, sequence
        local offerA = Context.context.jobService.createNextOffer(Context.artStateA, sequence)
        local offerB = Context.context.jobService.createNextOffer(Context.artStateB, sequence)
        if offerA.artworkKey ~= offerB.artworkKey then Context.differentArt = true; break end
    end
    Context.check("artwork_order_changes_with_each_playthrough_seed", Context.differentArt)

    function Context.verifyVendorInventory()
        local vendorState = Context.context.State.new()
        local starterCartons = vendorState.inventory.stock.shipping_cartons or 0
    local pressSupplyState = Context.context.State.new()
    pressSupplyState.money = 500
    local pressSupplyBought, pressSupplyOrder = Context.context.procurement.buy(pressSupplyState, 2, 1)
    Context.check("vendor_sells_real_cost_press_supplies_for_windmill", pressSupplyBought
        and pressSupplyOrder.item == "black_ink" and pressSupplyOrder.price == 184
        and pressSupplyOrder.pallets[1].quantity == 140)
    vendorState.money = 1000
    local bought, purchaseOrder = Context.context.procurement.buy(vendorState, 3, 1)
    Context.check("vendor_catalog_purchase", bought and purchaseOrder.id == "PO-0001"
        and purchaseOrder.pallets[1].category == "packaging"
        and vendorState.money == 593)
    local retailState = Context.context.State.new()
    retailState.money = 500
    local retailBought, retailOrder = Context.context.procurement.buyRetail(retailState, 3, 1)
    Context.check("computer_retail_matches_vendor_product", retailBought
        and retailOrder.item == purchaseOrder.item
        and retailOrder.channel == "computer"
        and retailOrder.pallets[1].quantity == 20
        and retailOrder.price == 84
        and retailOrder.price / retailOrder.pallets[1].quantity
            > purchaseOrder.price / purchaseOrder.pallets[1].quantity)
    local groupedState = Context.context.State.new()
    groupedState.money = 1000
    local groupBuyA, groupOrderA = Context.context.procurement.buyRetail(groupedState, 1, 1)
    local groupBuyB, groupOrderB = Context.context.procurement.buyRetail(groupedState, 2, 4)
    local groupedBeforeDue = Context.context.procurement.nextInbound(groupedState)
    Context.context.businessCalendar.update(groupedState,
        Context.context.config.businessCalendar.secondsPerDay * (4 / 24) + 0.1)
    local groupedShipment = Context.context.procurement.nextInbound(groupedState)
    local _, groupedInventory = Context.context.procurement.truckInventory(
        groupedState, groupedShipment and groupedShipment.id)
    Context.check("close_supply_orders_wait_and_share_one_truck",
        groupBuyA and groupBuyB and groupOrderA.shipmentId == groupOrderB.shipmentId
        and groupedBeforeDue == nil and groupedShipment
        and groupedShipment.id == groupOrderA.shipmentId and #groupedInventory == 2)
    groupedShipment.delivery.status = "at_bay"
    Context.check("saved_vendor_manifest_reschedules_after_truck_reset",
        Context.context.procurement.nextInbound(groupedState) == groupedShipment)
    groupedInventory[1].pallet.location = "warehouse"
    groupedInventory[2].pallet.location = "warehouse"
    Context.check("empty_vendor_manifest_does_not_schedule_truck",
        Context.context.procurement.nextInbound(groupedState) == nil)
    local vendorManifest, vendorItems = Context.context.procurement.truckInventory(vendorState, purchaseOrder.id)
    Context.check("vendor_delivery_manifest", vendorManifest == purchaseOrder and #vendorItems == 1
        and vendorItems[1].productName == "Shipping cartons, 12 x 12 x 12 in, 275 lb, 100")
    local unloaded, productPallet, vendorRemaining = Context.context.procurement.unload(vendorState,
        purchaseOrder.id, purchaseOrder.pallets[1].id,
        Context.context.config.palletLogistics.spawnPoints, Context.context.config.palletLogistics.unloadOrigin)
    Context.check("vendor_product_unloads_to_pallet", unloaded and vendorRemaining == 0
        and productPallet.location == "warehouse"
        and vendorState.inventory.stock.shipping_cartons == starterCartons + 100)
    vendorState.palletJack.x, vendorState.palletJack.y = productPallet.world.x, productPallet.world.y
    Context.check("vendor_pallet_jack_mount", Context.context.PalletJack.use(vendorState, Context.context.config.palletJack, function() return true end))
    local vendorLifted, vendorAction = Context.context.PalletJack.use(vendorState, Context.context.config.palletJack, function() return true end)
    Context.check("vendor_product_pallet_lifts", vendorLifted and vendorAction == "lifted"
        and productPallet.location == "on_pallet_jack")
    Context.context.PalletJack.move(vendorState, 1, 0, 0.1, Context.context.config.palletJack, function() return true end)
    local vendorLowered, vendorLowerAction = Context.context.PalletJack.use(vendorState, Context.context.config.palletJack, function() return true end)
    Context.check("vendor_product_pallet_lowers_with_direction", vendorLowered and vendorLowerAction == "lowered"
        and productPallet.world.direction == "east"
        and productPallet.world.rotation == 2)

    local filmBought, filmOrder = Context.context.procurement.buy(vendorState, 3, 2)
    local filmUnloaded = filmBought and Context.context.procurement.unload(vendorState,
        filmOrder.id, filmOrder.pallets[1].id,
        Context.context.config.palletLogistics.spawnPoints, Context.context.config.palletLogistics.unloadOrigin)
    Context.check("vendor_film_delivery_credits_wrapper_inventory", filmUnloaded
        and vendorState.inventory.plasticWrapRolls == 13
        and vendorState.inventory.plasticWrapUses == 11
        and vendorState.inventory.stock.stretch_film == nil)
    local vendorBoxedPallet = {
        id = "VENDOR-SUPPLY-WRAP-P01", number = 1, status = "cut", location = "cutter_output",
        packaging = "boxed", wrapped = false,
        world = { x = vendorState.wrapper.x - 60, y = vendorState.wrapper.y, spawnProgress = 1 },
    }
    vendorState.jobs.active = { {
        id = "VENDOR-SUPPLY-WRAP", packaging = "boxed", pallets = { vendorBoxedPallet },
    } }
    Context.context.wrapper.reset(vendorState)
    Context.check("vendor_carton_and_film_feed_wrapper", Context.context.wrapper.start(vendorState))
    Context.context.wrapper.update(Context.context.wrapper.cycleTime + 0.01, vendorState)
    Context.check("vendor_wrapper_consumes_delivered_supplies", vendorBoxedPallet.wrapped
        and vendorState.inventory.stock.shipping_cartons == starterCartons + 99
        and vendorState.inventory.plasticWrapRolls == 13
        and vendorState.inventory.plasticWrapUses == 10)
    local visibleStock = Context.context.procurement.inventoryRows(vendorState)
    Context.check("vendor_supplies_visible_in_office_inventory", visibleStock[3].id == "shipping_cartons"
        and visibleStock[3].quantity == starterCartons + 99
        and visibleStock[4].id == "stretch_film"
        and visibleStock[4].quantity == 13)
    Context.context.wrapper.reset(vendorState)

    local noCartonState = Context.context.State.new()
    noCartonState.inventory.stock.shipping_cartons = 0
    noCartonState.jobs.active = { {
        id = "NO-CARTON-JOB", packaging = "boxed", pallets = { {
            id = "NO-CARTON-P01", number = 1, status = "cut", location = "cutter_output",
            packaging = "boxed", wrapped = false,
            world = { x = noCartonState.wrapper.x - 60, y = noCartonState.wrapper.y, spawnProgress = 1 },
        } },
    } }
    Context.context.wrapper.reset(noCartonState)
    Context.check("boxed_wrapper_requires_delivered_carton", not Context.context.wrapper.start(noCartonState)
        and Context.context.wrapper.step == "idle"
        and noCartonState.inventory.plasticWrapUses == 11)

    local paperSupplyState = Context.context.State.new()
    paperSupplyState.money = 500
    paperSupplyState.inventory.paper = 0
    local paperBought, paperOrder = Context.context.procurement.buy(paperSupplyState, 1, 1)
    local paperUnloaded = paperBought and Context.context.procurement.unload(paperSupplyState,
        paperOrder.id, paperOrder.pallets[1].id,
        Context.context.config.palletLogistics.spawnPoints, Context.context.config.palletLogistics.unloadOrigin)
    Context.check("vendor_paper_delivery_enters_production_stock", paperUnloaded
        and Context.context.procurement.paperAvailable(paperSupplyState) == 1000
        and paperSupplyState.inventory.stock.house_sheets == 1000)
    Context.context.machine.reset(paperSupplyState)
    Context.check("vendor_paper_loads_sample_cutter", Context.context.machine.load(paperSupplyState))
    Context.context.machine.update(Context.context.machine.transferTime + 0.01, paperSupplyState)
    for cutNumber = 1, 4 do
        Context.context.machine.selectProgram(cutNumber, paperSupplyState)
        Context.context.machine.keypressed("q", paperSupplyState)
        Context.context.machine.setGauge(Context.context.machine.paper.cuts[cutNumber].gauge, paperSupplyState)
        Context.context.machine.saveGauge(paperSupplyState)
        Context.context.machine.autoGauge(paperSupplyState)
        Context.context.machine.position(paperSupplyState)
        Context.context.machine.update(Context.context.machine.transferTime + 0.01, paperSupplyState)
        Context.context.machine.toggleClamp(paperSupplyState)
        Context.context.machine.keypressed("j", paperSupplyState)
        Context.context.machine.keypressed("k", paperSupplyState)
        Context.context.machine.keyreleased("j")
        Context.context.machine.keyreleased("k")
        Context.context.machine.update(0.01, paperSupplyState)
        Context.context.machine.update(Context.context.machine.cycleTime + 0.05, paperSupplyState)
    end
    Context.check("vendor_paper_sample_cut_complete", Context.context.machine.step == "cut_complete")
    Context.context.machine.keypressed("u", paperSupplyState)
    Context.context.machine.update(Context.context.machine.transferTime + 0.01, paperSupplyState)
    Context.check("sample_cutter_consumes_delivered_paper", paperSupplyState.inventory.stock.house_sheets == 999
        and paperSupplyState.inventory.paper == 0
        and paperSupplyState.inventory.prints == 1)
    Context.context.machine.reset(paperSupplyState)
    end
    Context.verifyVendorInventory()

    Context.jobs = Context.context.jobs or Context.context.Jobs
    Context.check("jobs_module_loaded", Context.jobs and type(Context.jobs.calculateQuote) == "function")
    if Context.jobs then
        local q500 = Context.jobs.calculateQuote({ 500 })
        local q750 = Context.jobs.calculateQuote({ 750 })
        local q3000 = Context.jobs.calculateQuote({ 3000 })
        local qMixed = Context.jobs.calculateQuote({ 500, 750, 3000 })
        local qMaximum = Context.jobs.calculateQuote({ 3000, 3000, 3000, 3000, 3000 })
        Context.check("job_quote_500", q500 and q500.totalPrice == 150)
        Context.check("job_quote_750", q750 and q750.totalPrice == 300)
        Context.check("job_quote_3000", q3000 and q3000.totalPrice == 900)
        Context.check("job_quote_mixed", qMixed and qMixed.totalPrice == 1350)
        Context.check("job_quote_maximum", qMaximum
            and qMaximum.palletCount == 5
            and qMaximum.totalPrice == 4500)
        Context.check("job_quote_partial_lift", q750 and q750.totalLifts == 2)
        Context.check("job_id_format", Context.jobs.formatId(12) == "JOB-0012")

        local offer = {
            id = "JOB-0001",
            company = "Smoke Test Co.",
            sourceSize = { width = 25, height = 25 },
            finishedSize = { width = 8.5, height = 11 },
            sheetCounts = { 500, 750 },
            details = { stockDescription = "Customer-owned test stock" },
        }
        local valid = Context.jobs.validateOffer(offer)
        Context.check("job_offer_valid", valid == true)

        local tooManyPallets = {
            company = "Invalid Co.",
            sourceSize = { width = 25, height = 25 },
            finishedSize = { width = 8.5, height = 11 },
            sheetCounts = { 500, 500, 500, 500, 500, 500 },
        }
        local tooLarge = {
            company = "Invalid Co.",
            sourceSize = { width = 26, height = 25 },
            finishedSize = { width = 8.5, height = 11 },
            sheetCounts = { 500 },
        }
        local badPallets = Context.jobs.validateOffer(tooManyPallets)
        local badSize = Context.jobs.validateOffer(tooLarge)
        local badSheetCount = Context.jobs.calculateQuote({ 3001 })
        local badFinishedSize = Context.jobs.validateOffer({
            company = "Invalid Co.",
            sourceSize = { width = 20, height = 20 },
            finishedSize = { width = 21, height = 10 },
            sheetCounts = { 500 },
        })
        Context.check("job_offer_max_five_pallets", badPallets == false)
        Context.check("job_offer_max_source_size", badSize == false)
        Context.check("job_offer_max_sheets", badSheetCount == nil)
        Context.check("job_offer_finished_fits_source", badFinishedSize == false)

        local job, createErrors = Context.jobs.createOffer(offer)
        Context.check("job_create", job ~= nil, createErrors and table.concat(createErrors, "; "))
        if job then
            Context.check("job_pallet_tracking", #job.pallets == 2
                and job.pallets[2].remainingSheets == 750
                and job.pallets[2].requiredLifts == 2)
            local accepted = Context.jobs.accept(job)
            Context.check("job_accept", accepted == true and job.status == "awaiting_delivery")
            Context.check("job_accept_once", Context.jobs.accept(job) == false)
            local declinedJob = Context.jobs.createOffer({
                id = "JOB-0002",
                company = "Decline Test Co.",
                sourceSize = { width = 25, height = 25 },
                finishedSize = { width = 8.5, height = 11 },
                sheetCounts = { 500 },
            })
            Context.check("job_decline_create", declinedJob ~= nil)
            if declinedJob then
                local declined = Context.jobs.decline(declinedJob)
                Context.check("job_decline", declined == true and declinedJob.status == "declined")
            end
        end
    end
end

return Component
