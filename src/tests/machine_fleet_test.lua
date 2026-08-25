local Test = {}

function Test.run(context, check)
    local state = context.State.new()
    local fleet = context.machineFleet
    local cutter = fleet.installed(state, "polar_115")
    local wrapper = fleet.installed(state, "skid_wrapper")
    check("machine_fleet_starts_with_unique_installed_units", cutter and wrapper
        and cutter.id == "MCH-0001" and wrapper.id == "MCH-0002"
        and cutter.variables ~= wrapper.variables
        and fleet.validState(state.machines))

    local SaveSchema = require("src.save_schema")
    local oldState = context.State.new()
    oldState.machines = nil
    local migrated = SaveSchema.migrate({
        version = 6, slot = 1, createdAt = 1, updatedAt = 2,
        state = oldState, player = { x = 400, y = 500 },
    })
    check("save_v6_migrates_machine_fleet_defaults", migrated
        and migrated.version == context.save.VERSION
        and #migrated.state.machines.items == 2
        and fleet.validState(migrated.state.machines))

    local cutterBefore = fleet.condition(cutter)
    local bladeBefore = cutter.variables.bladeSharpness
    check("machine_use_degrades_model_specific_condition",
        fleet.recordUse(state, "polar_115", 10)
        and cutter.cycles == 10
        and cutter.variables.bladeSharpness < bladeBefore
        and fleet.condition(cutter) < cutterBefore
        and wrapper.cycles == 0)

    local online = fleet.offers("online")
    local dealer = fleet.offers("dealer")
    check("dealer_machines_are_lower_condition_and_cheaper", #online == #dealer
        and dealer[1].condition < online[1].condition
        and dealer[1].price < online[1].price
        and dealer[2].condition < online[2].condition)

    state.money = 10000
    local bought, usedCutter = fleet.buy(state, "dealer", 1)
    check("dealer_purchase_creates_unique_stored_machine", bought
        and usedCutter.id == "MCH-0003" and usedCutter.source == "dealer"
        and usedCutter.status == "stored"
        and usedCutter.condition < cutter.condition
        and #fleet.owned(state) == 3)

    local plan = fleet.maintenancePlan(state, usedCutter.id)
    local beforeService = usedCutter.condition
    state.inventory.stock.maintenance_kit = 1
    local session = context.machineMaintenance.begin(state, usedCutter.id)
    context.machineMaintenance.update(session, 0.25)
    for _, task in ipairs(plan.tasks) do
        check("maintenance_session_accepts_" .. task.id,
            context.machineMaintenance.submitTask(session, task.id, 1))
    end
    local serviced = context.machineMaintenance.commit(state, session)
    check("maintenance_hook_restores_components_and_tracks_history", serviced
        and usedCutter.condition > beforeService
        and usedCutter.maintenance.serviceCount == 1
        and usedCutter.maintenance.lastServiceQuality == 1
        and state.inventory.stock.maintenance_kit == 0
        and session.animationClock == 0.25
        and context.machineMaintenance.progress(session) == 1
        and plan.tasks[1].sceneId:find(usedCutter.modelId, 1, true) == 1)

    local cutterServiceState = context.State.new()
    cutterServiceState.screen = "machine"
    cutterServiceState.machineType = "cutter"
    cutterServiceState.inventory.stock.maintenance_kit = 1
    local serviceCutter = fleet.installed(cutterServiceState, "polar_115")
    fleet.recordUse(cutterServiceState, "polar_115", 20)
    local conditionBeforeOiling = fleet.condition(serviceCutter)
    context.machineScreen.enter()
    local maintenanceX, maintenanceY = context.machineScreen.maintenanceCenter()
    local maintenanceHub = context.machineScreen.mousepressed(
        cutterServiceState, maintenanceX, maintenanceY, 1)
    local oilX, oilY = context.machineScreen.maintenanceTaskCenter("oil")
    local oilGame = context.machineScreen.mousepressed(cutterServiceState, oilX, oilY, 1)
    context.machineScreen.update(0.25)
    for _, action in ipairs({ "disconnect", "key", "tag" }) do
        local x, y = context.machineScreen.lubricationLockoutCenter(action)
        context.machineScreen.mousepressed(cutterServiceState, x, y, 1)
    end
    for _, action in ipairs({ "cartridge", "prime" }) do
        local x, y = context.machineScreen.lubricationPrepCenter(action)
        context.machineScreen.mousepressed(cutterServiceState, x, y, 1)
    end
    local pointGroups = {
        rear = { "backgauge_left", "backgauge_right" },
        front = { "knife_guide", "clamp_guide" },
        side = { "eccentric", "crank_pin" },
    }
    for _, view in ipairs({ "rear", "front", "side" }) do
        local viewX, viewY = context.machineScreen.lubricationViewCenter(view)
        context.machineScreen.mousepressed(cutterServiceState, viewX, viewY, 1)
        for _, pointId in ipairs(pointGroups[view]) do
            local ragX, ragY = context.machineScreen.lubricationToolCenter("rag")
            context.machineScreen.mousepressed(cutterServiceState, ragX, ragY, 1)
            local pointX, pointY = context.machineScreen.lubricationPointCenter(pointId)
            context.machineScreen.mousepressed(cutterServiceState, pointX, pointY, 1)
            local gunX, gunY = context.machineScreen.lubricationToolCenter("grease")
            context.machineScreen.mousepressed(cutterServiceState, gunX, gunY, 1)
            context.machineScreen.mousepressed(cutterServiceState, pointX, pointY, 1)
            local pumpX, pumpY = context.machineScreen.lubricationPumpCenter()
            context.machineScreen.mousepressed(cutterServiceState, pumpX, pumpY, 1)
            context.machineScreen.mousepressed(cutterServiceState, pumpX, pumpY, 1)
        end
    end
    local gearX, gearY = context.machineScreen.lubricationViewCenter("gear")
    context.machineScreen.mousepressed(cutterServiceState, gearX, gearY, 1)
    local inspectX, inspectY = context.machineScreen.lubricationToolCenter("inspect")
    context.machineScreen.mousepressed(cutterServiceState, inspectX, inspectY, 1)
    local sightX, sightY = context.machineScreen.lubricationGearSightCenter()
    context.machineScreen.mousepressed(cutterServiceState, sightX, sightY, 1)
    local finishX, finishY = context.machineScreen.lubricationFinishCenter()
    context.machineScreen.mousepressed(cutterServiceState, finishX, finishY, 1)
    check("cutter_maintenance_hub_launches_detailed_lubrication_minigame",
        maintenanceHub and maintenanceHub.action == "maintenance_hub"
        and oilGame and oilGame.game == "cutter_lubrication"
        and cutterServiceState.inventory.stock.maintenance_kit == 0
        and serviceCutter.maintenance.cutter.oilServices == 1
        and serviceCutter.maintenance.cutter.lubricationServices == 1
        and fleet.condition(serviceCutter) > conditionBeforeOiling)
    local centralState = context.State.new()
    centralState.inventory.stock.maintenance_kit = 1
    fleet.installed(centralState, "polar_115").maintenance.cutter.centralLubricationInstalled = true
    local central = context.machineMaintenance.beginCutterLubrication(centralState)
    context.machineMaintenance.lubricationLockout(central, "disconnect")
    context.machineMaintenance.lubricationLockout(central, "key")
    context.machineMaintenance.lubricationLockout(central, "tag")
    context.machineMaintenance.lubricationPrepare(central, "cartridge")
    context.machineMaintenance.lubricationPrepare(central, "prime")
    context.machineMaintenance.selectLubricationView(central, "central")
    context.machineMaintenance.selectLubricationTool(central, "rag")
    context.machineMaintenance.serviceLubricationPoint(central, "central")
    context.machineMaintenance.selectLubricationTool(central, "grease")
    context.machineMaintenance.serviceLubricationPoint(central, "central")
    for _ = 1, 4 do context.machineMaintenance.pumpLubricationGun(central) end
    context.machineMaintenance.selectLubricationView(central, "gear")
    context.machineMaintenance.selectLubricationTool(central, "inspect")
    context.machineMaintenance.inspectGearOil(central)
    local centralCompleted = context.machineMaintenance.finishCutterLubrication(centralState, central)
    check("central_lubrication_variant_requires_two_indicator_flashes",
        centralCompleted and central.central.flashes == 2 and central.central.complete
        and centralState.inventory.stock.maintenance_kit == 0)
    local bladeX, bladeY = context.machineScreen.maintenanceTaskCenter("blade")
    local bladeGame = context.machineScreen.mousepressed(cutterServiceState, bladeX, bladeY, 1)
    for bolt = 1, 4 do
        local boltX, boltY = context.machineScreen.bladeBoltCenter(bolt)
        context.machineScreen.mousepressed(cutterServiceState, boltX, boltY, 1)
    end
    local bladeCenterX, bladeCenterY = context.machineScreen.bladeCenter()
    context.machineScreen.mousepressed(cutterServiceState, bladeCenterX, bladeCenterY, 1)
    local sleeveX, sleeveY = context.machineScreen.bladeSleeveCenter()
    local bladeSleeved = context.machineScreen.mousepressed(cutterServiceState, sleeveX, sleeveY, 1)
    check("cutter_blade_removal_minigame_secures_blade_in_wooden_sleeve",
        bladeGame and bladeGame.game == "blade_removal"
        and bladeSleeved and bladeSleeved.action == "blade_sleeved"
        and serviceCutter.maintenance.cutter.bladeRemoved
        and serviceCutter.maintenance.cutter.bladeInSleeve)
    local cutterOperable, cutterBlockedReason = fleet.canOperate(cutterServiceState, "polar_115")
    check("cutter_cannot_run_while_blade_is_out_for_sharpening",
        not cutterOperable and cutterBlockedReason:find("blade is removed", 1, true))
    local weeklyX, weeklyY = context.machineScreen.maintenanceTaskCenter("weekly")
    local weeklyScheduled = context.machineScreen.mousepressed(cutterServiceState, weeklyX, weeklyY, 1)
    context.businessCalendar.update(cutterServiceState,
        7 * context.config.businessCalendar.secondsPerDay)
    local technicianUpdated = context.machineMaintenance.updateTechnician(cutterServiceState)
    context.Technician.update(0, cutterServiceState, false)
    local technicianArrived = cutterServiceState.technicianVisit
        and cutterServiceState.technicianVisit.visible
        and cutterServiceState.technicianVisit.species == "mouse"
    context.Technician.update(20, cutterServiceState, false)
    context.Technician.update(context.config.technician.serviceDuration, cutterServiceState, false)
    check("weekly_blade_technician_services_sleeved_blade_and_emails_shop",
        weeklyScheduled and weeklyScheduled.action == "technician_schedule"
        and technicianUpdated and technicianArrived and serviceCutter.variables.bladeSharpness == 100
        and not serviceCutter.maintenance.cutter.bladeInSleeve
        and serviceCutter.maintenance.cutter.nextTechnicianDay == 14
        and #fleet.serviceInbox(cutterServiceState) == 1
        and context.jobService.emailInbox(cutterServiceState)[1].serviceNotice == true)
    local missedVisitState = context.State.new()
    context.businessCalendar.update(missedVisitState,
        context.config.businessCalendar.secondsPerDay)
    context.machineMaintenance.prepareBladeForTechnician(missedVisitState)
    local visitRequested = context.machineMaintenance.requestTechnician(missedVisitState)
    context.businessCalendar.update(missedVisitState,
        context.config.businessCalendar.secondsPerDay)
    local missedVisit = context.machineMaintenance.updateTechnician(missedVisitState)
    local missedCutter = fleet.installed(missedVisitState, "polar_115").maintenance.cutter
    check("blade_technician_can_miss_visit_and_email_reschedule_notice",
        visitRequested and missedVisit and missedCutter.bladeInSleeve
        and missedCutter.nextTechnicianDay == 9
        and #fleet.serviceInbox(missedVisitState) == 1
        and fleet.serviceInbox(missedVisitState)[1].subject == "Technician unable to attend")

    local saleValue = fleet.resaleValue(usedCutter, "online")
    local sold, sale = fleet.sell(state, usedCutter.id, "online")
    check("machine_condition_controls_resale_value", sold and sale.price == saleValue
        and sale.price > 0 and fleet.byId(state, usedCutter.id) == nil)

    local wrapperServiceState = context.State.new()
    wrapperServiceState.screen = "machine"
    wrapperServiceState.machineType = "skid_wrapper"
    wrapperServiceState.inventory.stock.maintenance_kit = 1
    local serviceWrapper = fleet.installed(wrapperServiceState, "skid_wrapper")
    fleet.recordUse(wrapperServiceState, "skid_wrapper", 18)
    local wrapperConditionBefore = fleet.condition(serviceWrapper)
    context.machineScreen.enter()
    local wrapperHubX, wrapperHubY = context.machineScreen.wrapperMaintenanceCenter()
    local wrapperHub = context.machineScreen.mousepressed(wrapperServiceState, wrapperHubX, wrapperHubY, 1)
    local wrapperStartX, wrapperStartY = context.machineScreen.wrapperServiceCenter()
    local wrapperGame = context.machineScreen.mousepressed(wrapperServiceState, wrapperStartX, wrapperStartY, 1)
    local wrapperSteps = 0
    while wrapperGame and context.machineScreen.wrapperTaskTargetCenter() and wrapperSteps < 12 do
        local targetX, targetY = context.machineScreen.wrapperTaskTargetCenter()
        context.machineScreen.mousepressed(wrapperServiceState, targetX, targetY, 1)
        wrapperSteps = wrapperSteps + 1
    end
    check("wrapper_maintenance_hub_launches_four_step_service_game",
        wrapperHub and wrapperHub.action == "maintenance_hub"
        and wrapperGame and wrapperGame.game == "wrapper_service"
        and wrapperSteps == 10
        and wrapperServiceState.inventory.stock.maintenance_kit == 0
        and serviceWrapper.maintenance.serviceCount == 1
        and fleet.condition(serviceWrapper) > wrapperConditionBefore)

    local physicalKitState = context.State.new()
    physicalKitState.money = 500
    local kitBought, kitOrder = context.procurement.buy(physicalKitState, 4, 1)
    local kitUnloaded = kitBought and context.procurement.unload(physicalKitState,
        kitOrder.id, kitOrder.pallets[1].id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
    local kitMachine = fleet.installed(physicalKitState, "skid_wrapper")
    local kitPlan = fleet.maintenancePlan(physicalKitState, kitMachine.id)
    local kitScores = {}
    for _, task in ipairs(kitPlan.tasks) do kitScores[task.id] = 1 end
    local kitConsumed = fleet.completeMaintenance(physicalKitState, kitMachine.id, kitScores)
    check("used_maintenance_kit_despawns_its_product_pallet",
        kitUnloaded and #context.procurement.physicalPallets(physicalKitState) == 0
        and kitOrder.pallets[1].location == "none" and kitOrder.pallets[1].status == "consumed"
        and kitConsumed and physicalKitState.inventory.stock.maintenance_kit == 0)

    local websiteState = context.State.new()
    websiteState.money = 10000
    context.computerScreen.enter(websiteState)
    local websiteX, websiteY = context.computerScreen.tabCenter("online")
    local websiteTab = context.computerScreen.mousepressed(websiteState, websiteX, websiteY, 1)
    local buyX, buyY = context.computerScreen.machineBuyCenter(1)
    local websitePurchase = context.computerScreen.mousepressed(websiteState, buyX, buyY, 1)
    local onlineOrder = websitePurchase and websitePurchase.order
    check("computer_online_website_orders_machine_delivery", websiteTab and websiteTab.tab == "online"
        and websitePurchase and websitePurchase.action == "machine_ordered"
        and onlineOrder and onlineOrder.item.source == "online"
        and onlineOrder.item.status == "stored"
        and onlineOrder.delivery.status == "awaiting_delivery"
        and #fleet.owned(websiteState) == 2
        and #fleet.pendingDeliveries(websiteState) == 1
        and fleet.validState(websiteState.machines))

    context.world.load()
    context.world.update(0, 0, 0, context.assets, websiteState)
    check("online_machine_uses_dedicated_flatbed_schedule",
        context.world.truckSnapshot().mode == "machine_delivery"
        and context.world.truckSnapshot().jobId == onlineOrder.id
        and onlineOrder.delivery.status == "scheduled")
    context.world.update(context.config.truck.scheduleDelay + 0.1, 0, 0, context.assets, websiteState)
    context.world.update(context.config.loadingBay.duration + 0.1, 0, 0, context.assets, websiteState)
    context.world.update(context.config.truck.backingDuration + 0.1, 0, 0, context.assets, websiteState)
    local flatbedInteraction = context.world.truck:getInteraction()
    check("machine_flatbed_parks_without_box_truck_cargo_door",
        context.world.truckSnapshot().state == "parked_closed"
        and onlineOrder.delivery.status == "at_bay"
        and flatbedInteraction and flatbedInteraction.prompt:find("flatbed", 1, true)
        and context.world.openTruckInventory(websiteState))
    local _, deliveryInventory = fleet.truckInventory(websiteState, onlineOrder.id)
    local unloadX, unloadY = context.truckInventoryScreen.unloadButtonCenter(1)
    local unloadResult = context.truckInventoryScreen.mousepressed(
        websiteState, context.world, unloadX, unloadY, 1)
    local deliveredMachine = unloadResult and unloadResult.machine
    check("player_unloads_online_machine_before_ownership", unloadResult
        and unloadResult.action == "unloaded"
        and deliveredMachine.id == onlineOrder.machineId
        and deliveredMachine.status == "stored"
        and fleet.byId(websiteState, deliveredMachine.id) == deliveredMachine
        and fleet.remainingOnTruck(websiteState, onlineOrder.id) == 0
        and onlineOrder.delivery.status == "received"
        and #fleet.owned(websiteState) == 3
        and fleet.validState(websiteState.machines))
    check("unloaded_stored_machine_has_visible_receiving_floor_position",
        deliveredMachine.world
        and deliveredMachine.world.x == context.config.machineReceiving.polar_115.x
        and deliveredMachine.world.y == context.config.machineReceiving.polar_115.y)
    local wrapperDeliveryState = context.State.new()
    wrapperDeliveryState.money = 10000
    local wrapperOrdered, wrapperOrder = fleet.orderOnline(wrapperDeliveryState, 2)
    local wrapperUnloaded, deliveredWrapper = false, nil
    if wrapperOrdered then
        wrapperUnloaded, deliveredWrapper = fleet.unloadDelivery(
            wrapperDeliveryState, wrapperOrder.id, wrapperOrder.machineId, os.time())
    end
    check("unloaded_duplicate_skid_wrapper_appears_on_receiving_floor",
        wrapperUnloaded and deliveredWrapper.modelId == "skid_wrapper"
        and deliveredWrapper.status == "stored" and deliveredWrapper.world
        and deliveredWrapper.world.x == context.config.machineReceiving.skid_wrapper.x
        and deliveredWrapper.world.y == context.config.machineReceiving.skid_wrapper.y
        and fleet.validState(wrapperDeliveryState.machines))
    check("empty_machine_flatbed_releases_directly",
        context.world.closeTruckAfterUnload(websiteState)
        and context.world.truckSnapshot().state == "departing")
    context.world.load()

    local dealerState = context.State.new()
    dealerState.money = 10000
    dealerState.vendorCategory = #context.procurement.categories
    local dealerX, dealerY = context.vendorScreen.buyButtonCenter(2)
    local dealerPurchase = context.vendorScreen.mousepressed(dealerState, dealerX, dealerY, 1)
    check("machinery_salesman_buys_lower_condition_machine", dealerPurchase
        and dealerPurchase.action == "machine_purchased"
        and dealerPurchase.machine.modelId == "skid_wrapper"
        and dealerPurchase.machine.source == "dealer"
        and dealerPurchase.machine.condition < fleet.offers("online")[2].condition)

    if os.getenv("PICTURE_SHOP_MACHINE_FLATBED_PREVIEW") == "1" then
        local previewState = context.State.new()
        previewState.money = 10000
        fleet.orderOnline(previewState, 1)
        context.State.applySave(context.state, { slot = 1, state = previewState })
        context.world.load()
        context.world.update(0, 0, 0, context.assets, context.state)
        context.world.update(context.config.truck.scheduleDelay + 0.1,
            0, 0, context.assets, context.state)
        context.world.update(context.config.loadingBay.duration + 0.1,
            0, 0, context.assets, context.state)
        context.world.update(context.config.truck.backingDuration + 0.1,
            0, 0, context.assets, context.state)
        local previewTruck = context.world.truckSnapshot()
        if previewTruck.state ~= "parked_closed" then
            error("machine flatbed preview did not park: " .. tostring(previewTruck.state))
        end
    end
end

return Test
