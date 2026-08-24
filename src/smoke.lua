local Smoke = {
    active = false,
    completed = false,
    failed = false,
    drawCount = 0,
    report = nil,
}

local function requested()
    return os.getenv("PICTURE_SHOP_SMOKE") == "1"
end

local function writeLine(text)
    if not Smoke.report then return end
    Smoke.report:write(text .. "\n")
    Smoke.report:flush()
end

local function check(name, condition, detail)
    if not condition then
        error(name .. ": " .. tostring(detail or "check failed"))
    end
    writeLine("PASS " .. name)
end

local function maskHasBothValues(mask)
    if not mask then return false, "mask image data missing" end
    local width, height = mask:getDimensions()
    local white, black = 0, 0
    for y = 0, height - 1, 24 do
        for x = 0, width - 1, 24 do
            local red, green, blue = mask:getPixel(x, y)
            if red > 0.9 and green > 0.9 and blue > 0.9 then
                white = white + 1
            else
                black = black + 1
            end
        end
    end
    return white > 20 and black > 20, "white=" .. white .. " black=" .. black
end

local function routeIsWalkable(mask, route, config)
    if not mask or type(route) ~= "table" or #route < 2 then return false, "route unavailable" end
    local width, height = mask:getDimensions()
    for segment = 1, #route - 1 do
        local startPoint, endPoint = route[segment], route[segment + 1]
        local dx, dy = endPoint.x - startPoint.x, endPoint.y - startPoint.y
        local samples = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / 3))
        for sample = 0, samples do
            local ratio = sample / samples
            local x = startPoint.x + dx * ratio
            local y = startPoint.y + dy * ratio
            local pixelX = math.floor(x / config.baseWidth * width)
            local pixelY = math.floor(y / config.baseHeight * height)
            local red, green, blue = mask:getPixel(pixelX, pixelY)
            if red < 0.9 or green < 0.9 or blue < 0.9 then
                return false, string.format("segment=%d point=%.1f,%.1f", segment, x, y)
            end
        end
    end
    return true
end

local function runChecks(context)
    local healthy, failures = context.assets.assertHealthy()
    check("asset_contract", healthy, failures)
    check("skid_wrapper_loaded", context.assets.get("skidWrapperDirections") ~= nil)
    for frame = 1, context.config.wrapperPlacement.frameCount do
        check("skid_wrapper_direction_" .. frame, context.assets.getQuad("skidWrapperDirection" .. frame) ~= nil)
    end
    local wrapperState = context.State.new()
    wrapperState.inventory.stock.shipping_cartons = 1
    wrapperState.jobs.active = { { id = "WRAP-TEST", packaging = "boxed", pallets = { {
        id = "WRAP-TEST-P01", number = 1, status = "cut", location = "cutter_output",
        packaging = "boxed", wrapped = false, world = { x = wrapperState.wrapper.x - 60, y = wrapperState.wrapper.y, spawnProgress = 1 },
    } } } }
    context.wrapper.reset(wrapperState)
    check("skid_wrapper_requires_nearby_pallet", context.wrapper.nearbyPallet(wrapperState) ~= nil)
    check("skid_wrapper_cycle", context.wrapper.keypressed("l", wrapperState))
    context.wrapper.update(context.wrapper.cycleTime + 0.1, wrapperState)
    check("skid_wrapper_finished", context.wrapper.step == "finished"
        and wrapperState.jobs.active[1].pallets[1].status == "wrapped"
        and wrapperState.inventory.plasticWrapUses == 10
        and wrapperState.inventory.stock.shipping_cartons == 0)
    local wrapperDirection = wrapperState.wrapper.direction
    check("skid_wrapper_move_mode", context.world.beginWrapperMove(wrapperState))
    check("skid_wrapper_rotate", context.world.rotateWrapper(wrapperState)
        and wrapperState.wrapper.direction ~= wrapperDirection)
    check("skid_wrapper_place", context.world.placeWrapper(wrapperState)
        and wrapperState.wrapper.moving == false)

    local function wrapperLifecycleState(id)
        local testState = context.State.new()
        testState.screen = "machine"
        testState.machineType = "skid_wrapper"
        testState.inventory.stock.shipping_cartons = 1
        local pallet = {
            id = id, number = 1, status = "cut", location = "cutter_output",
            packaging = "boxed", wrapped = false,
            world = { x = testState.wrapper.x - 60, y = testState.wrapper.y, spawnProgress = 1 },
        }
        testState.jobs.active = { { id = id .. "-JOB", packaging = "boxed", pallets = { pallet } } }
        context.wrapper.reset(testState)
        check(id .. "_starts", context.wrapper.start(testState))
        return testState, pallet
    end

    local exitSamples = {
        { name = "start", advance = 0 },
        { name = "middle", advance = context.wrapper.cycleTime / 2 },
        { name = "final_frame", advance = context.wrapper.cycleTime - 0.0001 },
    }
    for _, inputKind in ipairs({ "keyboard", "mouse" }) do
        for _, sample in ipairs(exitSamples) do
            local name = "wrapper_" .. inputKind .. "_" .. sample.name
            local testState, pallet = wrapperLifecycleState(name)
            if sample.advance > 0 then context.wrapper.update(sample.advance, testState) end
            local progressBeforeExit = context.wrapper.progress
            local saveCalls = 0
            local testInputContext = {}
            for key, value in pairs(context.inputContext) do testInputContext[key] = value end
            testInputContext.state = testState
            testInputContext.saveCurrent = function() saveCalls = saveCalls + 1; return true end
            local handled
            if inputKind == "keyboard" then
                handled = context.input.keypressed("escape", testInputContext)
            else
                local exitX, exitY = context.machineScreen.exitCenter()
                handled = context.input.mousepressed(exitX, exitY, 1, testInputContext)
            end
            check(name .. "_exit_blocked",
                handled
                and testState.screen == "machine"
                and context.wrapper.step == "wrapping"
                and context.wrapper.progress == progressBeforeExit
                and testState.inventory.plasticWrapUses == 11
                and not pallet.wrapped
                and saveCalls == 0)

            context.wrapper.update(context.wrapper.cycleTime, testState)
            if inputKind == "keyboard" then
                context.input.keypressed("escape", testInputContext)
            else
                local exitX, exitY = context.machineScreen.exitCenter()
                context.input.mousepressed(exitX, exitY, 1, testInputContext)
            end
            context.wrapper.update(1, testState)
            check(name .. "_finishes_once",
                testState.screen == "world"
                and context.wrapper.step == "finished"
                and pallet.wrapped
                and pallet.status == "wrapped"
                and testState.inventory.plasticWrapUses == 10
                and saveCalls == 1)
        end
    end

    local relocationState, relocationPallet = wrapperLifecycleState("wrapper_interruption_guards")
    context.wrapper.update(context.wrapper.cycleTime / 2, relocationState)
    local relocationContext = {}
    for key, value in pairs(context.inputContext) do relocationContext[key] = value end
    relocationContext.state = relocationState
    relocationContext.saveCurrent = function() error("blocked relocation must not save") end
    check("skid_wrapper_reset_blocked_while_wrapping",
        not context.wrapper.keypressed("r", relocationState)
        and context.wrapper.step == "wrapping"
        and not relocationPallet.wrapped)
    check("skid_wrapper_direct_relocation_blocked_while_wrapping",
        not context.world.beginWrapperMove(relocationState)
        and not relocationState.wrapper.moving)
    check("skid_wrapper_console_relocation_blocked_while_wrapping",
        context.input.keypressed("m", relocationContext)
        and relocationState.screen == "machine"
        and not relocationState.wrapper.moving)
    context.wrapper.update(context.wrapper.cycleTime, relocationState)
    check("skid_wrapper_interruption_guards_preserve_single_use",
        relocationPallet.wrapped and relocationState.inventory.plasticWrapUses == 10)
    context.wrapper.reset(relocationState)
    local expectedCharacters = {
        ["tan-cat"] = { idle = 2, walk = 3, sit = 2 },
        ["green-blazer-cat"] = { idle = 2, walk = 3, sit = 2, use = 3 },
        ["blue-coaler-cat"] = { idle = 2, walk = 3, sit = 2 },
        ["business-dragon"] = { idle = 2, walk = 4, sit = 2 },
        ["business-fox"] = { idle = 2, walk = 4, sit = 2 },
        ["business-cat"] = { idle = 2, walk = 4, sit = 2 },
    }
    local charactersHealthy, characterFailures = context.characterAssets.assertHealthy()
    check("character_asset_contract", charactersHealthy, characterFailures)
    for character, actions in pairs(expectedCharacters) do
        for action, count in pairs(actions) do
            local image, quad, actual = context.characterAssets.get(character, action, 1)
            check(character .. "_" .. action .. "_loaded", image ~= nil and quad ~= nil and actual == count)
        end
    end

    local background = context.assets.get("warehouse")
    local mask = context.assets.get("walkmask")
    local loadingBayDoor = context.assets.get("loadingBayDoor")
    local deliveryTruck = context.assets.get("deliveryTruck")
    local truckCargoDoor = context.assets.get("truckCargoDoor")
    local polarOperatorConsole = context.assets.get("polarOperatorConsole")
    check("warehouse_loaded", background ~= nil)
    check("walkmask_loaded", mask ~= nil)
    check("loading_bay_door_asset_loaded", loadingBayDoor ~= nil)
    check("delivery_truck_asset_loaded", deliveryTruck ~= nil)
    check("truck_cargo_door_asset_loaded", truckCargoDoor ~= nil)
    check("polar_operator_console_loaded", polarOperatorConsole ~= nil)
    check("picture_press_excluded_from_runtime", context.assets.get("picturePress") == nil
        and context.config.paths.picturePress == nil)
    check("polar_direction_strip_loaded", context.assets.get("polarDirections") ~= nil)
    check("cutter_button_strip_loaded", context.assets.get("cutterControlButtons") ~= nil)
    check("cutter_clamp_strip_loaded", context.assets.get("cutterClamp") ~= nil)
    check("cutter_blade_strip_loaded", context.assets.get("cutterBlade") ~= nil)
    check("loaded_paper_pallet_asset_loaded", context.assets.get("loadedPaperPallet") ~= nil)
    check("loaded_paper_pallet_directions_loaded", context.assets.get("loadedPaperPalletDirections") ~= nil)
    check("pallet_jack_asset_loaded", context.assets.get("palletJack") ~= nil)
    check("loaded_pallet_jack_asset_loaded", context.assets.get("palletJackLoaded") ~= nil)
    check("vendor_product_pallet_atlas_loaded", context.assets.get("vendorProductPallets") ~= nil)
    check("boxed_paper_pallet_stages_loaded", context.assets.get("boxedPaperPalletStages") ~= nil)
    check("polar_back_button_strip_loaded", context.assets.get("polarBackButton") ~= nil)
    for frame = 1, 3 do
        check("polar_back_button_frame_" .. frame, context.assets.getQuad("polarBackButton" .. frame) ~= nil)
    end
    for frame = 1, context.config.loadingBay.frameCount do
        check("loading_bay_door_frame_" .. frame,
            context.assets.getQuad("loadingBayDoor" .. frame) ~= nil)
    end
    for frame = 1, context.config.truck.cargoFrameCount do
        check("truck_cargo_door_frame_" .. frame,
            context.assets.getQuad("truckCargoDoor" .. frame) ~= nil)
    end
    for frame = 1, context.config.cutterGui.motionFrameCount do
        check("cutter_clamp_frame_" .. frame, context.assets.getQuad("cutterClamp" .. frame) ~= nil)
        check("cutter_blade_frame_" .. frame, context.assets.getQuad("cutterBlade" .. frame) ~= nil)
    end
    for frame = 1, context.config.cutterPlacement.frameCount do
        check("polar_direction_frame_" .. frame,
            context.assets.getQuad("polarDirection" .. frame) ~= nil)
    end
    for frame = 1, context.config.palletJack.frameCount do
        check("loaded_pallet_direction_" .. frame, context.assets.getQuad("loadedPaperPallet" .. frame) ~= nil)
        check("pallet_jack_direction_" .. frame, context.assets.getQuad("palletJack" .. frame) ~= nil)
        check("loaded_pallet_jack_direction_" .. frame, context.assets.getQuad("palletJackLoaded" .. frame) ~= nil)
        for row = 1, 4 do
            check("vendor_product_pallet_" .. row .. "_direction_" .. frame,
                context.assets.getQuad("vendorProductPallet" .. row .. "_" .. frame) ~= nil)
        end
    end
    for stage = 1, 5 do
        for frame = 1, 4 do
            check("boxed_paper_pallet_stage_" .. stage .. "_direction_" .. frame,
                context.assets.getQuad("boxedPaperPalletStage" .. stage .. "_" .. frame) ~= nil)
        end
    end
    if background and mask then
        local backgroundWidth, backgroundHeight = background:getDimensions()
        local maskWidth, maskHeight = mask:getDimensions()
        check(
            "walkmask_alignment",
            backgroundWidth == maskWidth and backgroundHeight == maskHeight,
            string.format("warehouse=%dx%d mask=%dx%d", backgroundWidth, backgroundHeight, maskWidth, maskHeight)
        )
    end
    local varied, maskDetail = maskHasBothValues(context.assets.getData("walkmask"))
    check("walkmask_values", varied, maskDetail)
    local routeValid, routeDetail = routeIsWalkable(
        context.assets.getData("walkmask"),
        context.config.customer.route,
        context.config
    )
    check("customer_reception_route_walkable", routeValid, routeDetail)

    local door = context.BayDoor.new(context.config.loadingBay)
    check("bay_door_starts_closed", door.state == "closed"
        and door:frame() == 1
        and door:getObstacle() ~= nil)
    check("bay_door_begins_opening", door:open() and door.state == "opening")
    check("bay_door_ignores_toggle_while_moving", not door:toggle())
    door:update(context.config.loadingBay.duration * 0.5)
    check("bay_door_half_open_frame", door.state == "opening" and door:frame() == 3)
    door:update(context.config.loadingBay.duration * 0.5)
    check("bay_door_opens", door.state == "open"
        and door:frame() == context.config.loadingBay.frameCount
        and door:getObstacle() == nil)
    check("bay_door_begins_closing", door:close() and door.state == "closing")
    door:update(context.config.loadingBay.duration)
    check("bay_door_closes", door.state == "closed" and door:frame() == 1)

    local truck = context.Truck.new(context.config.truck)
    check("truck_keeps_constant_scale",
        context.config.truck.start.scale == context.config.truck.parked.scale)
    check("truck_starts_absent", truck.state == "absent" and not truck:isVisible())
    check("truck_schedules_job", truck:schedule("JOB-TRUCK-TEST", "delivery")
        and truck.state == "scheduled")
    check("truck_requests_bay", truck:update(context.config.truck.scheduleDelay + 0.1, "closed")
        == "request_bay_open" and truck.state == "waiting_for_bay")
    check("truck_begins_backing", truck:update(0, "open") == "backing_started"
        and truck.state == "backing")
    truck:update(context.config.truck.backingDuration * 0.5, "open")
    local midTruck = truck:snapshot()
    local startX, parkedX = context.config.truck.start.x, context.config.truck.parked.x
    check("truck_backing_interpolates", midTruck.backingProgress > 0.45
        and midTruck.backingProgress < 0.55
        and midTruck.x > math.min(startX, parkedX)
        and midTruck.x < math.max(startX, parkedX))
    local apertureCenterX = 0
    for _, point in ipairs(context.config.truck.aperture) do apertureCenterX = apertureCenterX + point.x end
    apertureCenterX = apertureCenterX / #context.config.truck.aperture
    local parkedRearX = context.config.truck.parked.x
        + context.config.truck.rearOpeningOffsetX * context.config.truck.parked.scale
    check("truck_rear_centers_on_dock", math.abs(parkedRearX - apertureCenterX) <= 3)
    check("truck_parks", truck:update(context.config.truck.backingDuration, "open") == "parked"
        and truck.state == "parked_closed"
        and truck:getInteraction() ~= nil
        and truck:getObstacle() ~= nil)
    check("truck_cargo_begins_opening", truck:toggleCargoDoor()
        and truck.state == "cargo_opening")
    truck:update(context.config.truck.cargoDuration * 0.5, "open")
    check("truck_cargo_half_open_frame", truck:cargoFrame() == 3)
    check("truck_cargo_opens", truck:update(context.config.truck.cargoDuration, "open")
        == "cargo_opened" and truck.state == "cargo_open"
        and truck:cargoFrame() == context.config.truck.cargoFrameCount)
    check("truck_cargo_closes", truck:toggleCargoDoor()
        and truck:update(context.config.truck.cargoDuration, "open") == "cargo_closed"
        and truck.state == "parked_closed")
    check("truck_can_depart", truck:depart() and truck.state == "departing")
    check("truck_departure_finishes", truck:update(context.config.truck.backingDuration, "open")
        == "departed" and truck.state == "absent" and not truck:isVisible())

    local rabbit = context.assets.get("rabbit")
    if rabbit then
        local width, height = rabbit:getDimensions()
        check("rabbit_atlas_6x4", width % 6 == 0 and height % 4 == 0)
    end

    local customer = context.Customer.new({
        character = "green-blazer-cat",
        route = { { x = 0, y = 0 }, { x = 40, y = 0 }, { x = 40, y = 40 } },
        speed = 100,
        arrivalDelay = 0.1,
    })
    check("customer_starts_scheduled", customer.state == "scheduled" and not customer.visible)
    customer:update(0.05, { x = 500, y = 500 })
    check("customer_honors_arrival_delay", customer.state == "scheduled")
    customer:update(0.50, { x = 500, y = 500 })
    check("customer_enters_building", customer.state == "entering" and customer.visible)
    customer:update(0.50, { x = 500, y = 500 })
    check("customer_waits_at_reception", customer.state == "waiting" and customer.x == 40 and customer.y == 40)
    check("customer_reception_interaction", customer:getInteraction() ~= nil)
    check("customer_begins_review", customer:beginReview() and customer.state == "reviewing")
    check("customer_accepts", customer:resolve("accepted") and customer.state == "exiting")
    customer:update(1, { x = 500, y = 500 })
    check("customer_exits_after_decision", customer.state == "finished"
        and not customer.visible
        and customer.decision == "accepted")

    local declinedCustomer = context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 10, y = 0 } },
        speed = 100,
        arrivalDelay = 0,
    })
    declinedCustomer:update(1, { x = 500, y = 500 })
    check("customer_decline_review", declinedCustomer:beginReview())
    check("customer_declines", declinedCustomer:resolve("declined")
        and declinedCustomer.decision == "declined")
    local worldCustomer = context.world.customerSnapshot()
    local expectedSeat = context.config.customer.seatSpots[worldCustomer.seatIndex]
    check("customer_world_render_ready", worldCustomer.visible
        and worldCustomer.state == "waiting"
        and worldCustomer.x == expectedSeat.x
        and worldCustomer.y == expectedSeat.y)

    local timedCustomer = context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 10, y = 0 } },
        speed = 100,
        arrivalDelay = 0,
        maxWaitSeconds = 0.1,
    })
    timedCustomer:update(1, { x = 500, y = 500 })
    check("customer_wait_timeout", timedCustomer:update(0.11, { x = 500, y = 500 }) == "timed_out"
        and timedCustomer.state == "exiting"
        and timedCustomer.decision == "timed_out")

    local economy = context.State.new()
    economy.screen = "world"
    local startingMoney = economy.money
    check("shop_buy", context.shop.buyPaper(economy))
    check("shop_buy_balance", economy.money == startingMoney - 25 and economy.inventory.paper == 65)
    economy.inventory.prints = 1
    check("shop_sell", context.shop.sellPrint(economy))
    check("shop_sell_balance", economy.money == startingMoney - 13 and economy.inventory.prints == 0)

    local function verifyVendorInventory()
    local vendorState = context.State.new()
    vendorState.money = 500
    local moneyBeforeLockedSupply = vendorState.money
    check("vendor_blocks_supply_without_consumer", not context.procurement.buy(vendorState, 2, 1)
        and vendorState.money == moneyBeforeLockedSupply
        and #vendorState.procurement.orders == 0)
    local bought, purchaseOrder = context.procurement.buy(vendorState, 3, 1)
    check("vendor_catalog_purchase", bought and purchaseOrder.id == "PO-0001"
        and purchaseOrder.pallets[1].category == "packaging"
        and vendorState.money == 428)
    local vendorManifest, vendorItems = context.procurement.truckInventory(vendorState, purchaseOrder.id)
    check("vendor_delivery_manifest", vendorManifest == purchaseOrder and #vendorItems == 1
        and vendorItems[1].productName == "Shipping cartons, 100")
    local unloaded, productPallet, vendorRemaining = context.procurement.unload(vendorState,
        purchaseOrder.id, purchaseOrder.pallets[1].id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
    check("vendor_product_unloads_to_pallet", unloaded and vendorRemaining == 0
        and productPallet.location == "warehouse"
        and vendorState.inventory.stock.shipping_cartons == 100)
    vendorState.palletJack.x, vendorState.palletJack.y = productPallet.world.x, productPallet.world.y
    check("vendor_pallet_jack_mount", context.PalletJack.use(vendorState, context.config.palletJack, function() return true end))
    local vendorLifted, vendorAction = context.PalletJack.use(vendorState, context.config.palletJack, function() return true end)
    check("vendor_product_pallet_lifts", vendorLifted and vendorAction == "lifted"
        and productPallet.location == "on_pallet_jack")
    context.PalletJack.move(vendorState, 1, 0, 0.1, context.config.palletJack, function() return true end)
    local vendorLowered, vendorLowerAction = context.PalletJack.use(vendorState, context.config.palletJack, function() return true end)
    check("vendor_product_pallet_lowers_with_direction", vendorLowered and vendorLowerAction == "lowered"
        and productPallet.world.direction == "northeast")

    local filmBought, filmOrder = context.procurement.buy(vendorState, 3, 2)
    local filmUnloaded = filmBought and context.procurement.unload(vendorState,
        filmOrder.id, filmOrder.pallets[1].id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
    check("vendor_film_delivery_credits_wrapper_inventory", filmUnloaded
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
    context.wrapper.reset(vendorState)
    check("vendor_carton_and_film_feed_wrapper", context.wrapper.start(vendorState))
    context.wrapper.update(context.wrapper.cycleTime + 0.01, vendorState)
    check("vendor_wrapper_consumes_delivered_supplies", vendorBoxedPallet.wrapped
        and vendorState.inventory.stock.shipping_cartons == 99
        and vendorState.inventory.plasticWrapRolls == 13
        and vendorState.inventory.plasticWrapUses == 10)
    local visibleStock = context.procurement.inventoryRows(vendorState)
    check("vendor_supplies_visible_in_office_inventory", visibleStock[3].id == "shipping_cartons"
        and visibleStock[3].quantity == 99
        and visibleStock[4].id == "stretch_film"
        and visibleStock[4].quantity == 13)
    context.wrapper.reset(vendorState)

    local noCartonState = context.State.new()
    noCartonState.jobs.active = { {
        id = "NO-CARTON-JOB", packaging = "boxed", pallets = { {
            id = "NO-CARTON-P01", number = 1, status = "cut", location = "cutter_output",
            packaging = "boxed", wrapped = false,
            world = { x = noCartonState.wrapper.x - 60, y = noCartonState.wrapper.y, spawnProgress = 1 },
        } },
    } }
    context.wrapper.reset(noCartonState)
    check("boxed_wrapper_requires_delivered_carton", not context.wrapper.start(noCartonState)
        and context.wrapper.step == "idle"
        and noCartonState.inventory.plasticWrapUses == 11)

    local paperSupplyState = context.State.new()
    paperSupplyState.money = 500
    paperSupplyState.inventory.paper = 0
    local paperBought, paperOrder = context.procurement.buy(paperSupplyState, 1, 1)
    local paperUnloaded = paperBought and context.procurement.unload(paperSupplyState,
        paperOrder.id, paperOrder.pallets[1].id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
    check("vendor_paper_delivery_enters_production_stock", paperUnloaded
        and context.procurement.paperAvailable(paperSupplyState) == 1000
        and paperSupplyState.inventory.stock.house_sheets == 1000)
    context.machine.reset(paperSupplyState)
    check("vendor_paper_loads_sample_cutter", context.machine.load(paperSupplyState))
    context.machine.update(context.machine.transferTime + 0.01, paperSupplyState)
    for cutNumber = 1, 4 do
        context.machine.selectProgram(cutNumber, paperSupplyState)
        context.machine.keypressed("q", paperSupplyState)
        context.machine.autoGauge(paperSupplyState)
        context.machine.position(paperSupplyState)
        context.machine.update(context.machine.transferTime + 0.01, paperSupplyState)
        context.machine.toggleClamp(paperSupplyState)
        context.machine.keypressed("j", paperSupplyState)
        context.machine.keypressed("k", paperSupplyState)
        context.machine.keyreleased("j")
        context.machine.keyreleased("k")
        context.machine.update(0.01, paperSupplyState)
        context.machine.update(context.machine.cycleTime + 0.05, paperSupplyState)
    end
    check("vendor_paper_sample_cut_complete", context.machine.step == "cut_complete")
    context.machine.keypressed("u", paperSupplyState)
    context.machine.update(context.machine.transferTime + 0.01, paperSupplyState)
    check("sample_cutter_consumes_delivered_paper", paperSupplyState.inventory.stock.house_sheets == 999
        and paperSupplyState.inventory.paper == 0
        and paperSupplyState.inventory.prints == 1)
    context.machine.reset(paperSupplyState)
    end
    verifyVendorInventory()

    local jobs = context.jobs or context.Jobs
    check("jobs_module_loaded", jobs and type(jobs.calculateQuote) == "function")
    if jobs then
        local q500 = jobs.calculateQuote({ 500 })
        local q750 = jobs.calculateQuote({ 750 })
        local q3000 = jobs.calculateQuote({ 3000 })
        local qMixed = jobs.calculateQuote({ 500, 750, 3000 })
        local qMaximum = jobs.calculateQuote({ 3000, 3000, 3000, 3000, 3000 })
        check("job_quote_500", q500 and q500.totalPrice == 150)
        check("job_quote_750", q750 and q750.totalPrice == 300)
        check("job_quote_3000", q3000 and q3000.totalPrice == 900)
        check("job_quote_mixed", qMixed and qMixed.totalPrice == 1350)
        check("job_quote_maximum", qMaximum
            and qMaximum.palletCount == 5
            and qMaximum.totalPrice == 4500)
        check("job_quote_partial_lift", q750 and q750.totalLifts == 2)
        check("job_id_format", jobs.formatId(12) == "JOB-0012")

        local offer = {
            id = "JOB-0001",
            company = "Smoke Test Co.",
            sourceSize = { width = 25, height = 25 },
            finishedSize = { width = 8.5, height = 11 },
            sheetCounts = { 500, 750 },
            details = { stockDescription = "Customer-owned test stock" },
        }
        local valid = jobs.validateOffer(offer)
        check("job_offer_valid", valid == true)

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
        local badPallets = jobs.validateOffer(tooManyPallets)
        local badSize = jobs.validateOffer(tooLarge)
        local badSheetCount = jobs.calculateQuote({ 3001 })
        local badFinishedSize = jobs.validateOffer({
            company = "Invalid Co.",
            sourceSize = { width = 20, height = 20 },
            finishedSize = { width = 21, height = 10 },
            sheetCounts = { 500 },
        })
        check("job_offer_max_five_pallets", badPallets == false)
        check("job_offer_max_source_size", badSize == false)
        check("job_offer_max_sheets", badSheetCount == nil)
        check("job_offer_finished_fits_source", badFinishedSize == false)

        local job, createErrors = jobs.createOffer(offer)
        check("job_create", job ~= nil, createErrors and table.concat(createErrors, "; "))
        if job then
            check("job_pallet_tracking", #job.pallets == 2
                and job.pallets[2].remainingSheets == 750
                and job.pallets[2].requiredLifts == 2)
            local accepted = jobs.accept(job)
            check("job_accept", accepted == true and job.status == "awaiting_delivery")
            check("job_accept_once", jobs.accept(job) == false)
            local declinedJob = jobs.createOffer({
                id = "JOB-0002",
                company = "Decline Test Co.",
                sourceSize = { width = 25, height = 25 },
                finishedSize = { width = 8.5, height = 11 },
                sheetCounts = { 500 },
            })
            check("job_decline_create", declinedJob ~= nil)
            if declinedJob then
                local declined = jobs.decline(declinedJob)
                check("job_decline", declined == true and declinedJob.status == "declined")
            end
        end
    end

    local receivingState = context.State.new()
    receivingState.money = 1000
    local receivingJob = jobs.createOffer({
        id = "JOB-RECEIVING",
        company = "Receiving Lane Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500, 500, 500, 500, 500 },
    })
    jobs.accept(receivingJob)
    receivingState.jobs.active[1] = receivingJob
    for index, pallet in ipairs(receivingJob.pallets) do
        local succeeded, unloadedPallet = context.PalletLogistics.unload(
            receivingState, receivingJob.id, pallet.id,
            context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
        local lane = context.config.palletLogistics.spawnPoints[index]
        check("receiving_lane_unique_customer_" .. index, succeeded
            and unloadedPallet.world.x == lane.x
            and unloadedPallet.world.y == lane.y)
    end
    local fullReceiving = context.Receiving.snapshot(receivingState,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.receivingLaneRadius)
    check("receiving_lanes_report_full", fullReceiving.open == 0 and fullReceiving.total == 5)

    local vendorBought, blockedOrder = context.procurement.buy(receivingState, 3, 1)
    check("receiving_vendor_order_setup", vendorBought and blockedOrder.status == "awaiting_delivery")
    local stockBeforeBlocked = receivingState.inventory.stock.shipping_cartons or 0
    local blockedUnload, blockedReason = context.procurement.unload(
        receivingState, blockedOrder.id, blockedOrder.pallets[1].id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
    check("receiving_full_blocks_vendor_unload", not blockedUnload
        and tostring(blockedReason):find("Receiving lanes are full", 1, true) ~= nil
        and blockedOrder.status == "awaiting_delivery"
        and blockedOrder.delivery.status == "awaiting_schedule"
        and blockedOrder.pallets[1].location == "awaiting_delivery"
        and (receivingState.inventory.stock.shipping_cartons or 0) == stockBeforeBlocked)

    local movedPallet = receivingJob.pallets[1]
    check("receiving_lane_pallet_lift_for_move",
        context.PalletState.transition(receivingState, movedPallet, "on_pallet_jack"))
    local movedWorld = {
        x = 820, y = 580, direction = "southeast", rotation = 4,
        fromX = 820, fromY = 580, spawnProgress = 1,
    }
    check("receiving_lane_pallet_moved_clear",
        context.PalletState.transition(receivingState, movedPallet, "warehouse", { world = movedWorld }))
    local reopenedReceiving = context.Receiving.snapshot(receivingState,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.receivingLaneRadius)
    check("receiving_lane_reopens_after_move", reopenedReceiving.open == 1
        and not reopenedReceiving.lanes[1].occupied)
    local vendorUnloaded, receivedVendorPallet = context.procurement.unload(
        receivingState, blockedOrder.id, blockedOrder.pallets[1].id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
    check("receiving_mixed_delivery_reuses_clear_lane", vendorUnloaded
        and receivedVendorPallet.world.x == context.config.palletLogistics.spawnPoints[1].x
        and receivedVendorPallet.world.y == context.config.palletLogistics.spawnPoints[1].y
        and receivingState.inventory.stock.shipping_cartons == stockBeforeBlocked + 100
        and context.PalletState.validate(receivingState))

    local serviceState = context.State.new()
    serviceState.screen = "world"
    local serviceOffer = context.jobService.createNextOffer(serviceState, 111)
    check("paperwork_offer_created", serviceOffer
        and serviceOffer.id == "JOB-0001"
        and serviceOffer.company == "Blue Ridge Packaging"
        and serviceOffer.quote.totalPrice == 600
        and #serviceOffer.pallets == 2)
    local acceptX, acceptY = context.jobOfferScreen.buttonCenter("accept")
    local declineX, declineY = context.jobOfferScreen.buttonCenter("decline")
    check("paperwork_accept_hit_target", context.jobOfferScreen.hitTest(acceptX, acceptY) == "accept")
    check("paperwork_decline_hit_target", context.jobOfferScreen.hitTest(declineX, declineY) == "decline")
    check("paperwork_ignores_outside_click", context.jobOfferScreen.hitTest(10, 10) == nil)
    local cashBeforeOffer = serviceState.money
    check("paperwork_service_accept", context.jobService.acceptOffer(serviceState, serviceOffer, 222))
    check("paperwork_accept_records_job", #serviceState.jobs.active == 1
        and serviceState.jobs.active[1].status == "awaiting_delivery"
        and serviceState.accountsReceivable == 600
        and serviceState.money == cashBeforeOffer
        and serviceState.nextJobId == 2)
    check("paperwork_cannot_accept_twice", not context.jobService.acceptOffer(serviceState, serviceOffer, 333)
        and #serviceState.jobs.active == 1
        and serviceState.accountsReceivable == 600)
    local serviceDecline = context.jobService.createNextOffer(serviceState, 444)
    check("paperwork_service_decline", context.jobService.declineOffer(serviceState, serviceDecline, 555))
    check("paperwork_decline_records_job", #serviceState.jobs.declined == 1
        and serviceState.jobs.declined[1].id == "JOB-0002"
        and serviceState.jobs.declined[1].pallets[1].status == "cancelled"
        and serviceState.jobs.declined[1].pallets[1].location == "none"
        and serviceState.accountsReceivable == 600
        and serviceState.nextJobId == 3)

    context.computerScreen.enter(serviceState)
    local activeTabX, activeTabY = context.computerScreen.tabCenter("active")
    local completedTabX, completedTabY = context.computerScreen.tabCenter("completed")
    local deliveryTabX, deliveryTabY = context.computerScreen.tabCenter("deliveries")
    local inventoryTabX, inventoryTabY = context.computerScreen.tabCenter("inventory")
    check("computer_active_tab_click", context.computerScreen.mousepressed(
        serviceState, activeTabX, activeTabY, 1).tab == "active")
    local rowX, rowY = context.computerScreen.rowCenter(1)
    local selectedActive = context.computerScreen.mousepressed(serviceState, rowX, rowY, 1)
    check("computer_job_row_click", selectedActive
        and selectedActive.action == "select"
        and selectedActive.job.id == "JOB-0001")
    local completeX, completeY = context.computerScreen.completeCenter()
    local completionResult = context.computerScreen.mousepressed(serviceState, completeX, completeY, 1)
    check("computer_completion_gate", completionResult
        and completionResult.action == "completion_blocked"
        and completionResult.job.id == "JOB-0001")
    check("computer_completed_tab_click", context.computerScreen.mousepressed(
        serviceState, completedTabX, completedTabY, 1).tab == "completed")
    check("computer_deliveries_tab_click", context.computerScreen.mousepressed(
        serviceState, deliveryTabX, deliveryTabY, 1).tab == "deliveries")
    local selectedDelivery = context.computerScreen.mousepressed(serviceState, rowX, rowY, 1)
    check("computer_inbound_delivery_list", selectedDelivery
        and selectedDelivery.job.status == "awaiting_delivery")
    check("computer_inventory_tab_click", context.computerScreen.mousepressed(
        serviceState, inventoryTabX, inventoryTabY, 1).tab == "inventory")
    local closeX, closeY = context.computerScreen.closeCenter()
    check("computer_close_hit_target", context.computerScreen.mousepressed(
        serviceState, closeX, closeY, 1).action == "close")
    check("computer_ignores_outside_click", context.computerScreen.mousepressed(
        serviceState, 10, 10, 1) == nil)

    local function verifyFullJobLoop()
    local fullLoopState = context.State.new()
    fullLoopState.screen = "world"
    local fullLoopOffer = jobs.createOffer({
        id = "JOB-FULL-LOOP",
        company = "Complete Workflow Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
        packaging = "flat",
    })
    local fullLoopStartingCash = fullLoopState.money
    check("full_loop_accepts_job", context.jobService.acceptOffer(fullLoopState, fullLoopOffer, 100)
        and fullLoopState.accountsReceivable == 150
        and fullLoopState.money == fullLoopStartingCash)
    check("full_loop_receives_inbound_pallet", context.PalletLogistics.unload(
        fullLoopState, fullLoopOffer.id, fullLoopOffer.pallets[1].id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin))
    local fullLoopPallet = fullLoopOffer.pallets[1]
    local inputX, inputY = context.CutterZones.inputAnchor(fullLoopState, context.config.cutterPlacement)
    check("full_loop_lifts_inbound_pallet",
        context.PalletState.transition(fullLoopState, fullLoopPallet, "on_pallet_jack"))
    check("full_loop_stages_cutter_input", context.PalletState.transition(
        fullLoopState, fullLoopPallet, "warehouse", { world = {
            x = inputX, y = inputY, direction = "northwest", rotation = 1,
            fromX = inputX, fromY = inputY, spawnProgress = 1,
        } }))

    context.machine.reset(fullLoopState)
    check("full_loop_loads_cutter", context.machine.load(fullLoopState))
    context.machine.update(context.machine.transferTime + 0.01, fullLoopState)
    for cutNumber = 1, 4 do
        context.machine.selectProgram(cutNumber, fullLoopState)
        context.machine.keypressed("q", fullLoopState)
        context.machine.autoGauge(fullLoopState)
        check("full_loop_positions_cut_" .. cutNumber, context.machine.position(fullLoopState))
        context.machine.update(context.machine.transferTime + 0.01, fullLoopState)
        context.machine.toggleClamp(fullLoopState)
        context.machine.keypressed("j", fullLoopState)
        context.machine.keypressed("k", fullLoopState)
        context.machine.keyreleased("j")
        context.machine.keyreleased("k")
        context.machine.update(0.01, fullLoopState)
        context.machine.update(context.machine.cycleTime + 0.05, fullLoopState)
    end
    check("full_loop_finishes_cutting", fullLoopPallet.paper.status == "complete"
        and fullLoopPallet.remainingSheets == 0
        and fullLoopPallet.completedLifts == 1
        and fullLoopPallet.lastLiftSheets == 500
        and context.machine.step == "cut_complete")
    context.machine.keypressed("u", fullLoopState)
    context.machine.update(context.machine.transferTime + 0.01, fullLoopState)
    check("full_loop_returns_cut_pallet", fullLoopPallet.location == "cutter_output"
        and fullLoopPallet.status == "cut"
        and fullLoopPallet.remainingSheets == 0
        and fullLoopPallet.finishedSheets == 500)

    local wrapWorld = {
        x = fullLoopState.wrapper.x - 60, y = fullLoopState.wrapper.y,
        direction = "northwest", rotation = 1,
        fromX = fullLoopState.wrapper.x - 60, fromY = fullLoopState.wrapper.y, spawnProgress = 1,
    }
    check("full_loop_lifts_cut_pallet",
        context.PalletState.transition(fullLoopState, fullLoopPallet, "on_pallet_jack"))
    check("full_loop_stages_wrapper", context.PalletState.transition(
        fullLoopState, fullLoopPallet, "warehouse", { world = wrapWorld }))
    context.wrapper.reset(fullLoopState)
    check("full_loop_starts_wrapping", context.wrapper.start(fullLoopState))
    context.wrapper.update(context.wrapper.cycleTime + 0.01, fullLoopState)
    check("full_loop_finishes_wrapping", fullLoopPallet.status == "wrapped"
        and fullLoopPallet.wrapped
        and fullLoopState.inventory.plasticWrapUses == 10)

    context.computerScreen.enter(fullLoopState)
    fullLoopState.screen = "computer"
    local fullLoopSaveCalls = 0
    local fullLoopInput = {}
    for key, value in pairs(context.inputContext) do fullLoopInput[key] = value end
    fullLoopInput.state = fullLoopState
    fullLoopInput.saveCurrent = function() fullLoopSaveCalls = fullLoopSaveCalls + 1; return true end
    local pickupX, pickupY = context.computerScreen.completeCenter()
    check("full_loop_requests_pickup", context.input.mousepressed(
        pickupX, pickupY, 1, fullLoopInput)
        and fullLoopOffer.status == "ready_for_pickup"
        and fullLoopOffer.pickup.status == "awaiting_schedule"
        and fullLoopSaveCalls == 1)

    context.world.load()
    fullLoopState.screen = "world"
    local pickupScheduledSave = context.world.update(
        context.config.truck.scheduleDelay + 0.1, 0, 0, context.assets, fullLoopState)
    check("full_loop_pickup_truck_scheduled", pickupScheduledSave
        and context.world.truckSnapshot().mode == "pickup"
        and context.world.truckSnapshot().state == "waiting_for_bay"
        and fullLoopOffer.status == "pickup_in_progress", string.format(
            "save=%s mode=%s truck=%s job=%s pickup=%s",
            tostring(pickupScheduledSave), tostring(context.world.truckSnapshot().mode),
            tostring(context.world.truckSnapshot().state), tostring(fullLoopOffer.status),
            tostring(fullLoopOffer.pickup and fullLoopOffer.pickup.status)))
    context.world.update(context.config.loadingBay.duration + 0.1, 0, 0, context.assets, fullLoopState)
    context.world.update(context.config.truck.backingDuration + 0.1, 0, 0, context.assets, fullLoopState)
    check("full_loop_pickup_truck_parked", context.world.truckSnapshot().state == "parked_closed"
        and fullLoopOffer.pickup.status == "at_bay")
    context.world.toggleTruckCargoDoor(fullLoopState)
    context.world.update(context.config.truck.cargoDuration + 0.1, 0, 0, context.assets, fullLoopState)
    check("full_loop_pickup_cargo_open", context.world.truckSnapshot().state == "cargo_open"
        and fullLoopOffer.pickup.status == "cargo_open")

    fullLoopState.screen = "truck_inventory"
    local loadX, loadY = context.truckInventoryScreen.unloadButtonCenter(1)
    check("full_loop_manifest_loads_pallet", context.input.mousepressed(
        loadX, loadY, 1, fullLoopInput)
        and fullLoopPallet.location == "outbound_truck"
        and fullLoopPallet.world == nil
        and fullLoopOffer.pickup.status == "loaded"
        and fullLoopState.inventory.finishedPallets == 0
        and fullLoopSaveCalls == 2)
    check("full_loop_pickup_checkpoint_saves", context.save.save(
        3, fullLoopState, { x = 500, y = 455 }))
    local savedPickup = context.save.load(3)
    check("full_loop_pickup_checkpoint_round_trip", savedPickup
        and savedPickup.state.jobs.active[1].status == "pickup_in_progress"
        and savedPickup.state.jobs.active[1].pickup.status == "loaded"
        and savedPickup.state.jobs.active[1].pallets[1].location == "outbound_truck"
        and savedPickup.state.inventory.finishedPallets == 0
        and savedPickup.state.accountsReceivable == 150)
    context.save.delete(3)
    local pickupDoorX, pickupDoorY = context.truckInventoryScreen.closeDoorCenter()
    check("full_loop_closes_loaded_pickup", context.input.mousepressed(
        pickupDoorX, pickupDoorY, 1, fullLoopInput)
        and fullLoopState.screen == "world"
        and context.world.truckSnapshot().state == "cargo_closing"
        and fullLoopSaveCalls == 3)
    context.world.update(context.config.truck.cargoDuration + 0.1, 0, 0, context.assets, fullLoopState)
    local pickupCompletedSave = context.world.update(
        context.config.truck.backingDuration + 0.1, 0, 0, context.assets, fullLoopState)
    check("full_loop_pickup_archives_and_pays", pickupCompletedSave
        and context.world.truckSnapshot().state == "absent"
        and #fullLoopState.jobs.active == 0
        and #fullLoopState.jobs.completed == 1
        and fullLoopState.jobs.completed[1] == fullLoopOffer
        and fullLoopOffer.status == "completed"
        and fullLoopPallet.location == "none"
        and fullLoopPallet.status == "picked_up"
        and fullLoopState.accountsReceivable == 0
        and fullLoopState.money == fullLoopStartingCash + 150)
    local cashAfterPickup = fullLoopState.money
    check("full_loop_payment_cannot_repeat", not context.jobService.completePickup(
        fullLoopState, fullLoopOffer.id, 999)
        and fullLoopState.money == cashAfterPickup)
    context.computerScreen.enter(fullLoopState)
    local fullLoopCompletedX, fullLoopCompletedY = context.computerScreen.tabCenter("completed")
    context.computerScreen.mousepressed(fullLoopState, fullLoopCompletedX, fullLoopCompletedY, 1)
    local completedRowX, completedRowY = context.computerScreen.rowCenter(1)
    local completedSelection = context.computerScreen.mousepressed(
        fullLoopState, completedRowX, completedRowY, 1)
    check("full_loop_completed_job_visible", completedSelection
        and completedSelection.job == fullLoopOffer
        and fullLoopOffer.paymentAmount == 150
        and fullLoopOffer.paidAt ~= nil)
    context.world.update(context.config.loadingBay.duration + 0.1, 0, 0, context.assets, fullLoopState)
    context.wrapper.reset(fullLoopState)
    context.machine.reset(fullLoopState)
    context.world.load()
    context.world.update(10, 0, 0, context.assets, context.state)
    end
    verifyFullJobLoop()

    local function verifySixLiftRepeatRun()
        local repeatState = context.State.new()
        local repeatJob = jobs.createOffer({
            id = "JOB-SIX-LIFTS", company = "Six Lift Co.",
            sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
            sheetCounts = { 3000 },
        })
        jobs.accept(repeatJob)
        repeatState.jobs.active[1] = repeatJob
        context.PalletLogistics.unload(repeatState, repeatJob.id, repeatJob.pallets[1].id,
            context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
        local pallet = repeatJob.pallets[1]
        local anchorX, anchorY = context.CutterZones.inputAnchor(repeatState, context.config.cutterPlacement)
        pallet.world.x, pallet.world.y = anchorX, anchorY
        pallet.world.fromX, pallet.world.fromY = anchorX, anchorY
        context.PalletState.transition(repeatState, pallet, "at_cutter", {
            status = "in_process", cutterRadius = context.config.cutterPlacement.palletInputZoneRadius,
        })
        pallet.paper.status = "complete"
        pallet.paper.activeCut = #pallet.paper.cuts + 1
        pallet.paper.currentSize.width = pallet.paper.finishedSize.width
        pallet.paper.currentSize.height = pallet.paper.finishedSize.height
        pallet.completedLifts, pallet.remainingSheets, pallet.finishedSheets = 1, 2500, 500
        pallet.activeLift, pallet.lastLiftSheets, pallet.programVerified = 2, 500, true
        context.machine.reset(repeatState)
        check("six_lift_program_resumes", context.machine.load(repeatState)
            and context.machine.step == "repeat_ready")
        for completed = 2, 6 do
            check("six_lift_repeat_starts_" .. completed, context.machine.repeatLift(repeatState))
            context.machine.update(context.machine.repeatCycleTime + 0.01, repeatState)
            check("six_lift_progress_" .. completed,
                pallet.completedLifts == completed
                and pallet.remainingSheets == 3000 - completed * 500
                and pallet.finishedSheets == completed * 500
                and pallet.lastLiftSheets == 500
                and context.machine.step == (completed == 6 and "cut_complete" or "repeat_ready"))
            if completed == 3 then
                check("six_lift_checkpoint_write", context.save.save(3, repeatState, { x = 400, y = 400 }))
                local checkpoint = context.save.load(3)
                local savedPallet = checkpoint and checkpoint.state.jobs.active[1].pallets[1]
                check("six_lift_checkpoint_round_trip", savedPallet
                    and savedPallet.completedLifts == 3
                    and savedPallet.activeLift == 4
                    and savedPallet.remainingSheets == 1500
                    and savedPallet.finishedSheets == 1500
                    and savedPallet.lastLiftSheets == 500
                    and savedPallet.programVerified
                    and checkpoint.state.inventory.inProcessPallets == 1
                    and checkpoint.state.inventory.finishedPallets == 0)
                context.save.delete(3)
            end
        end
        context.machine.reset(repeatState)
    end
    verifySixLiftRepeatRun()

    local cutterState = context.State.new()
    cutterState.screen = "machine"
    local cutterJob = jobs.createOffer({
        id = "JOB-CUTTER",
        company = "Cutter Test Co.",
        difficulty = "hard",
        sourceSize = { width = 25, height = 19 },
        finishedSize = { width = 12.5, height = 9.5 },
        sheetCounts = { 750 },
    })
    jobs.accept(cutterJob)
    cutterJob.pallets[1].location = "warehouse"
    cutterJob.pallets[1].world = {
        x = cutterState.cutter.x + 82,
        y = cutterState.cutter.y + 42,
        direction = "northwest",
        rotation = 1,
        fromX = cutterState.cutter.x + 82,
        fromY = cutterState.cutter.y + 42,
        spawnProgress = 1,
    }
    cutterState.jobs.active[1] = cutterJob
    local trackedPaper = cutterJob.pallets[1].paper
    check("paper_unique_id", trackedPaper.id == "JOB-CUTTER-P01-PAPER"
        and trackedPaper.artworkId == "ART-JOB-CUTTER"
        and #trackedPaper.cuts == 4)
    check("hard_job_asymmetric_margins", trackedPaper.margins.left ~= trackedPaper.margins.right
        or trackedPaper.margins.top ~= trackedPaper.margins.bottom)

    context.machine.reset(cutterState)
    check("cutter_table_starts_clear", not context.machine.loaded and context.machine.step == "idle")
    check("cutter_load", context.machine.load(cutterState))
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    check("cutter_load_animation", context.machine.step == "loaded" and context.machine.paper == trackedPaper)
    check("cutter_rejects_wrong_gauge", not context.machine.position(cutterState))
    context.machineScreen.enter()
    local typedGauge = string.format("%.2f", trackedPaper.cuts[1].gauge)
    for character in typedGauge:gmatch(".") do
        check("cutter_accepts_typed_character_" .. character,
            context.machineScreen.textinput(cutterState, character))
    end
    check("cutter_enter_commits_typed_gauge", context.machineScreen.keypressed(cutterState, "return")
        and math.abs(context.machine.gauge - trackedPaper.cuts[1].gauge) < 0.001)
    local expectedBedOrientations = { 90, 0, 270, 180 }

    for cutNumber = 1, 4 do
        check("cutter_select_program_" .. cutNumber, context.machine.selectProgram(cutNumber, cutterState))
        check("cutter_front_edge_orientation_" .. cutNumber,
            trackedPaper.cuts[cutNumber].orientation == expectedBedOrientations[cutNumber])
        if cutNumber == 1 then
            check("cutter_keyboard_rotate_" .. cutNumber, context.machine.keypressed("q", cutterState))
            local autoX, autoY = context.machineScreen.buttonCenter("auto")
            check("cutter_mouse_auto_gauge", context.machineScreen.mousepressed(cutterState, autoX, autoY, 1))
            context.machineScreen.mousereleased(cutterState, autoX, autoY, 1)
        else
            check("cutter_keyboard_rotate_" .. cutNumber, context.machine.keypressed("q", cutterState))
            check("cutter_keyboard_auto_gauge_" .. cutNumber, context.machine.keypressed("g", cutterState))
        end
        check("cutter_auto_selects_next_program_" .. cutNumber,
            context.machine.programIndex == cutNumber
            and math.abs(context.machine.gauge - trackedPaper.cuts[cutNumber].gauge) < 0.001)
        check("cutter_position_" .. cutNumber, context.machine.keypressed("p", cutterState))
        context.machine.update(context.machine.transferTime + 0.01, cutterState)
        check("cutter_position_animation_" .. cutNumber, context.machine.step == "positioned")
        check("cutter_clamp_" .. cutNumber, context.machine.keypressed("space", cutterState))
        context.machine.update(0.3, cutterState)
        if cutNumber == 1 then
            local leftX, leftY = context.machineScreen.buttonCenter("cut_left")
            local rightX, rightY = context.machineScreen.buttonCenter("cut_right")
            check("cutter_mouse_left_control", context.machineScreen.mousepressed(cutterState, leftX, leftY, 1))
            context.machineScreen.mousereleased(cutterState, leftX, leftY, 1)
            check("cutter_mouse_right_control", context.machineScreen.mousepressed(cutterState, rightX, rightY, 1))
            context.machineScreen.mousereleased(cutterState, rightX, rightY, 1)
        else
            context.machine.keypressed("j", cutterState)
            context.machine.keypressed("k", cutterState)
            context.machine.keyreleased("j")
            context.machine.keyreleased("k")
        end
        context.machine.update(0.01, cutterState)
        context.machine.update(context.machine.cycleTime + 0.05, cutterState)
        check("cutter_applies_margin_" .. cutNumber, trackedPaper.activeCut == cutNumber + 1)
    end
    check("cutter_manual_lift_verifies_program", trackedPaper.status == "complete"
        and trackedPaper.currentSize.width == 12.5
        and trackedPaper.currentSize.height == 9.5
        and context.machine.step == "repeat_ready"
        and cutterJob.pallets[1].completedLifts == 1
        and cutterJob.pallets[1].remainingSheets == 250
        and cutterJob.pallets[1].finishedSheets == 500
        and cutterJob.pallets[1].programVerified)
    check("paper_tooltip_updates_size", context.machine.paperTooltip():find("12.50 x 9.50", 1, true) ~= nil)
    check("cutter_blocks_early_unload_between_lifts", not context.machine.keypressed("u", cutterState)
        and context.machine.step == "repeat_ready"
        and cutterJob.pallets[1].remainingSheets == 250)
    check("cutter_repeat_lift_starts", context.machine.keypressed("t", cutterState)
        and context.machine.step == "repeat_producing")
    context.machine.update(context.machine.repeatCycleTime + 0.01, cutterState)
    check("cutter_partial_final_lift_completes", context.machine.step == "cut_complete"
        and cutterJob.pallets[1].completedLifts == 2
        and cutterJob.pallets[1].remainingSheets == 0
        and cutterJob.pallets[1].finishedSheets == 750
        and cutterJob.pallets[1].lastLiftSheets == 250
        and cutterJob.pallets[1].activeLift == 2)
    local finishedBeforeBlockedOutput = cutterState.inventory.finishedPallets
    context.machine.setOutputResolver(function()
        return nil, "No clear cutter output zone is available. Move pallets or equipment away from the cutter."
    end)
    check("cutter_full_output_zone_blocks_unload", not context.machine.keypressed("u", cutterState)
        and context.machine.step == "cut_complete"
        and cutterJob.pallets[1].location == "at_cutter"
        and cutterState.inventory.finishedPallets == finishedBeforeBlockedOutput)
    context.machine.reset(cutterState)
    check("cutter_completed_pallet_resumes_after_console_exit", context.machine.load(cutterState)
        and context.machine.step == "cut_complete"
        and context.machine.paper == trackedPaper
        and cutterJob.pallets[1].location == "at_cutter"
        and cutterState.inventory.inProcessPallets == 1)
    context.machine.setOutputResolver(function(targetState, pallet)
        return context.world.findCutterOutput(targetState, context.assets, pallet and pallet.id)
    end)
    check("cutter_unload", context.machine.keypressed("u", cutterState))
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    check("cutter_returns_to_pallet", context.machine.step == "finished"
        and cutterJob.pallets[1].status == "cut"
        and cutterJob.pallets[1].location == "cutter_output"
        and cutterState.inventory.finishedPallets == 1)
    check("cutter_output_is_safe_floor", context.world.isPalletPlacementClear(
        cutterState, context.assets,
        cutterJob.pallets[1].world.x, cutterJob.pallets[1].world.y, cutterJob.pallets[1].id))

    context.machine.reset(cutterState)
    cutterJob.pallets[1].paper.status = "uncut"
    cutterJob.pallets[1].paper.activeCut = 1
    cutterJob.pallets[1].paper.orientation = 0
    cutterJob.pallets[1].paper.currentSize = {
        width = cutterJob.pallets[1].paper.sourceSize.width,
        height = cutterJob.pallets[1].paper.sourceSize.height,
    }
    cutterJob.pallets[1].paper.history = {}
    cutterJob.pallets[1].remainingSheets = cutterJob.pallets[1].initialSheets
    cutterJob.pallets[1].finishedSheets = 0
    cutterJob.pallets[1].completedLifts = 0
    cutterJob.pallets[1].activeLift = 1
    cutterJob.pallets[1].lastLiftSheets = 0
    cutterJob.pallets[1].programVerified = false
    cutterJob.pallets[1].location = "warehouse"
    context.machine.load(cutterState)
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    context.machine.autoGauge(cutterState)
    context.machine.keypressed("q", cutterState)
    context.machine.position(cutterState)
    context.machine.update(context.machine.transferTime + 0.01, cutterState)
    context.machine.toggleClamp(cutterState)
    context.machine.setBarrier(false, cutterState)
    context.machine.keypressed("j", cutterState)
    context.machine.keypressed("k", cutterState)
    check("cutter_barrier_blocks", context.machine.step == "blocked")
    context.machine.reset(context.state)

    local function ownershipState(id, x, y)
        local testState = context.State.new()
        local testJob = jobs.createOffer({
            id = id,
            company = "Ownership Test Co.",
            sourceSize = { width = 20, height = 16 },
            finishedSize = { width = 10, height = 8 },
            sheetCounts = { 500 },
        })
        jobs.accept(testJob)
        local pallet = testJob.pallets[1]
        pallet.location = "warehouse"
        pallet.world = { x = x, y = y, direction = "northwest", rotation = 1,
            fromX = x, fromY = y, spawnProgress = 1 }
        testState.jobs.active[1] = testJob
        return testState, testJob, pallet
    end

    local cutterDirections = { "northwest", "northeast", "southwest", "southeast" }
    for _, direction in ipairs(cutterDirections) do
        local orientedState, _, orientedPallet = ownershipState("JOB-INPUT-" .. direction, 0, 0)
        orientedState.cutter.direction = direction
        local anchorX, anchorY = context.CutterZones.inputAnchor(
            orientedState, context.config.cutterPlacement)
        orientedPallet.world.x, orientedPallet.world.y = anchorX, anchorY
        orientedPallet.world.fromX, orientedPallet.world.fromY = anchorX, anchorY
        local candidates = context.PalletState.cutterCandidates(
            orientedState, context.config.cutterPlacement.palletInputZoneRadius)
        check("cutter_input_zone_" .. direction, candidates[1]
            and candidates[1].pallet == orientedPallet)
    end

    local fartherState, fartherJob, fartherPallet = ownershipState(
        "JOB-INPUT-FARTHER", context.config.cutterPlacement.spawnX + 116,
        context.config.cutterPlacement.spawnY + 38)
    local nearerJob = jobs.createOffer({
        id = "JOB-INPUT-NEARER", company = "Nearest Input Co.",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    jobs.accept(nearerJob)
    local nearerPallet = nearerJob.pallets[1]
    nearerPallet.location = "warehouse"
    nearerPallet.world = {
        x = fartherState.cutter.x + 80, y = fartherState.cutter.y + 38,
        direction = "northwest", rotation = 1,
        fromX = fartherState.cutter.x + 80, fromY = fartherState.cutter.y + 38,
        spawnProgress = 1,
    }
    fartherState.jobs.active[1], fartherState.jobs.active[2] = fartherJob, nearerJob
    local sortedInputs = context.PalletState.cutterCandidates(
        fartherState, context.config.cutterPlacement.palletInputZoneRadius)
    check("cutter_selects_nearest_input_pallet", sortedInputs[1]
        and sortedInputs[1].pallet == nearerPallet
        and sortedInputs[2].pallet == fartherPallet)

    local outputZoneState = context.State.new()
    local cutterLocations = {
        { x = context.config.cutterPlacement.spawnX, y = context.config.cutterPlacement.spawnY },
        { x = 520, y = 460 },
    }
    for locationIndex, location in ipairs(cutterLocations) do
        outputZoneState.cutter.x, outputZoneState.cutter.y = location.x, location.y
        for _, direction in ipairs(cutterDirections) do
            outputZoneState.cutter.direction = direction
            local output = context.world.findCutterOutput(outputZoneState, context.assets)
            check(string.format("cutter_output_safe_location_%d_%s", locationIndex, direction), output
                and context.world.isPalletPlacementClear(
                    outputZoneState, context.assets, output.x, output.y))
        end
    end

    local blockedPreferredState, _, outputBlocker = ownershipState("JOB-OUTPUT-BLOCKER", 0, 0)
    local preferredOutput = context.CutterZones.outputCandidates(
        blockedPreferredState, context.config.cutterPlacement)[1]
    outputBlocker.world.x, outputBlocker.world.y = preferredOutput.x, preferredOutput.y
    outputBlocker.world.fromX, outputBlocker.world.fromY = preferredOutput.x, preferredOutput.y
    local alternateOutput = context.world.findCutterOutput(blockedPreferredState, context.assets)
    check("cutter_output_avoids_occupied_preferred_zone", alternateOutput
        and (alternateOutput.x ~= preferredOutput.x or alternateOutput.y ~= preferredOutput.y)
        and context.world.isPalletPlacementClear(
            blockedPreferredState, context.assets, alternateOutput.x, alternateOutput.y))

    local farState, _, farPallet = ownershipState("JOB-FAR", 40, 620)
    context.machine.reset(farState)
    check("cutter_rejects_far_floor_pallet", not context.machine.load(farState)
        and farPallet.location == "warehouse"
        and farState.palletJack.carriedPalletId == nil)
    check("cutter_far_rejection_preserves_invariants", context.PalletState.validate(farState))

    local carriedState, _, carriedPallet = ownershipState(
        "JOB-CARRIED", context.config.cutterPlacement.spawnX + 70, context.config.cutterPlacement.spawnY + 30)
    check("pallet_transition_to_jack", context.PalletState.transition(carriedState, carriedPallet, "on_pallet_jack"))
    context.machine.reset(carriedState)
    check("cutter_rejects_pallet_owned_by_jack", not context.machine.load(carriedState)
        and carriedPallet.location == "on_pallet_jack"
        and carriedState.palletJack.carriedPalletId == carriedPallet.id
        and context.machine.pallet == nil)
    check("cutter_carried_rejection_preserves_invariants", context.PalletState.validate(carriedState))

    local stagedState, _, stagedPallet = ownershipState(
        "JOB-STAGED", context.config.cutterPlacement.spawnX + 72, context.config.cutterPlacement.spawnY + 28)
    context.machine.reset(stagedState)
    check("cutter_accepts_nearby_floor_pallet", context.machine.load(stagedState)
        and stagedPallet.location == "at_cutter"
        and stagedPallet.status == "in_process"
        and stagedState.palletJack.carriedPalletId == nil)
    check("cutter_load_preserves_single_owner", context.PalletState.validate(stagedState))
    context.machine.reset(stagedState)
    check("cutter_reopens_its_owned_pallet", context.machine.load(stagedState)
        and stagedPallet.location == "at_cutter"
        and stagedState.inventory.inProcessPallets == 1
        and context.PalletState.validate(stagedState))
    context.machine.reset(stagedState)

    local illegalState = context.State.new()
    local illegalJob = jobs.createOffer({
        id = "JOB-ILLEGAL", company = "Illegal Transition Co.",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    jobs.accept(illegalJob)
    illegalState.jobs.active[1] = illegalJob
    local illegalPallet = illegalJob.pallets[1]
    check("pallet_illegal_transition_rejected",
        not context.PalletState.transition(illegalState, illegalPallet, "at_cutter", {
            cutterRadius = context.config.cutterPlacement.palletInputZoneRadius,
        })
        and illegalPallet.location == "awaiting_delivery"
        and illegalPallet.world == nil
        and illegalState.palletJack.carriedPalletId == nil)

    local contestedState, _, firstCutterPallet = ownershipState(
        "JOB-FIRST-CUTTER", context.config.cutterPlacement.spawnX + 60, context.config.cutterPlacement.spawnY + 20)
    local secondJob = jobs.createOffer({
        id = "JOB-SECOND-CUTTER", company = "Second Cutter Co.",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
    })
    jobs.accept(secondJob)
    local secondCutterPallet = secondJob.pallets[1]
    secondCutterPallet.location = "warehouse"
    secondCutterPallet.world = { x = contestedState.cutter.x + 80, y = contestedState.cutter.y + 20,
        direction = "northwest", rotation = 1, fromX = contestedState.cutter.x + 80,
        fromY = contestedState.cutter.y + 20, spawnProgress = 1 }
    contestedState.jobs.active[2] = secondJob
    check("pallet_first_cutter_owner", context.PalletState.transition(
        contestedState, firstCutterPallet, "at_cutter",
        { status = "in_process", cutterRadius = context.config.cutterPlacement.palletInputZoneRadius }))
    check("pallet_second_cutter_owner_rejected", not context.PalletState.transition(
        contestedState, secondCutterPallet, "at_cutter",
        { status = "in_process", cutterRadius = context.config.cutterPlacement.palletInputZoneRadius })
        and secondCutterPallet.location == "warehouse"
        and secondCutterPallet.status == "raw"
        and context.PalletState.validate(contestedState))

    local legacyOwnershipState, _, legacyOwnershipPallet = ownershipState(
        "JOB-LEGACY-OWNER", context.config.cutterPlacement.spawnX + 50, context.config.cutterPlacement.spawnY + 20)
    legacyOwnershipPallet.location = "at_cutter"
    legacyOwnershipPallet.status = "in_process"
    legacyOwnershipState.palletJack.carriedPalletId = legacyOwnershipPallet.id
    check("pallet_legacy_double_owner_detected", not context.PalletState.validate(legacyOwnershipState))
    check("pallet_legacy_double_owner_reconciled", context.PalletState.reconcile(legacyOwnershipState)
        and legacyOwnershipPallet.location == "at_cutter"
        and legacyOwnershipState.palletJack.carriedPalletId == nil
        and context.PalletState.validate(legacyOwnershipState))

    local payload = context.save.newGame(1)
    economy.jobs.active[1] = jobs.createOffer({
        id = "JOB-0099",
        company = "Saved Job Co.",
        sourceSize = { width = 20, height = 20 },
        finishedSize = { width = 10, height = 10 },
        sheetCounts = { 1200 },
    })
    jobs.accept(economy.jobs.active[1])
    economy.jobs.active[1].pallets[1].location = "on_pallet_jack"
    economy.jobs.active[1].pallets[1].world = {
        x = 612, y = 498, direction = "southeast", rotation = 4,
        fromX = 612, fromY = 498, spawnProgress = 1,
    }
    economy.jobs.completed[1] = jobs.createOffer({
        id = "JOB-0098", company = "Completed Save Co.",
        sourceSize = { width = 18, height = 12 }, finishedSize = { width = 9, height = 6 },
        sheetCounts = { 500 }, packaging = "flat",
    })
    jobs.accept(economy.jobs.completed[1])
    economy.jobs.completed[1].status = "completed"
    economy.jobs.declined[1] = jobs.createOffer({
        id = "JOB-0097", company = "Declined Save Co.",
        sourceSize = { width = 16, height = 12 }, finishedSize = { width = 8, height = 6 },
        sheetCounts = { 500 }, packaging = "boxed",
    })
    jobs.decline(economy.jobs.declined[1])
    economy.accountsReceivable = economy.jobs.active[1].quote.totalPrice
    economy.nextJobId = 100
    economy.shopProgress.completedCuts = 9
    economy.inventory.plasticWrapRolls = 3
    economy.inventory.plasticWrapUses = 7
    economy.inventory.stock.shipping_cartons = 18
    economy.cutter.x = 590
    economy.cutter.y = 430
    economy.cutter.direction = "southeast"
    economy.palletJack.x = 612
    economy.palletJack.y = 498
    economy.palletJack.direction = "southeast"
    economy.palletJack.operating = true
    economy.palletJack.carriedPalletId = "JOB-0099-P01"
    economy.wrapper.x = 705
    economy.wrapper.y = 455
    economy.wrapper.direction = "northeast"
    economy.vendorCategory = 4
    check("save_procurement_setup", context.procurement.buy(economy, 1, 1))
    local savedPlayer = { x = 701, y = 502 }
    check("save_write_v3", context.save.save(1, economy, savedPlayer))
    local loaded = context.save.load(1)
    check("save_round_trip", loaded and loaded.state.money == economy.money)
    check("save_jobs_round_trip", loaded
        and loaded.version == context.save.VERSION
        and loaded.state.jobs.active[1].id == "JOB-0099"
        and loaded.state.jobs.active[1].pallets[1].remainingSheets == 1200
        and loaded.state.jobs.completed[1].id == "JOB-0098"
        and loaded.state.jobs.declined[1].id == "JOB-0097")
    check("save_finance_round_trip", loaded
        and loaded.state.accountsReceivable == 450
        and loaded.state.nextJobId == 100)
    check("save_inventory_round_trip", loaded
        and loaded.state.inventory.plasticWrapRolls == 3
        and loaded.state.inventory.plasticWrapUses == 7
        and loaded.state.inventory.stock.shipping_cartons == 18
        and loaded.state.inventory.rawPallets == 1
        and loaded.state.shopProgress.completedCuts == 9)
    check("save_pallet_jack_round_trip", loaded
        and loaded.state.palletJack.x == 612
        and loaded.state.palletJack.y == 498
        and loaded.state.palletJack.direction == "southeast"
        and loaded.state.palletJack.carriedPalletId == "JOB-0099-P01"
        and loaded.state.jobs.active[1].pallets[1].location == "on_pallet_jack")
    check("save_cutter_placement_round_trip", loaded
        and loaded.state.cutter.x == 590
        and loaded.state.cutter.y == 430
        and loaded.state.cutter.direction == "southeast")
    check("save_wrapper_placement_round_trip", loaded
        and loaded.state.wrapper.x == 705
        and loaded.state.wrapper.y == 455
        and loaded.state.wrapper.direction == "northeast")
    check("save_procurement_round_trip", loaded
        and loaded.state.vendorCategory == 4
        and loaded.state.procurement.nextOrderId == 2
        and loaded.state.procurement.orders[1].id == "PO-0001")
    check("save_player_round_trip", loaded and loaded.player.x == 701 and loaded.player.y == 502)
    local appliedRoundTrip = context.State.new()
    check("save_state_apply_round_trip", context.State.applySave(appliedRoundTrip, loaded)
        and appliedRoundTrip.wrapper.x == 705
        and appliedRoundTrip.wrapper.direction == "northeast"
        and appliedRoundTrip.inventory.plasticWrapUses == 7
        and appliedRoundTrip.palletJack.carriedPalletId == "JOB-0099-P01"
        and appliedRoundTrip.jobs.active[1].pallets[1].location == "on_pallet_jack")
    context.save.delete(1)

    love.filesystem.createDirectory("saves")
    love.filesystem.write("saves/slot2.lua", [[{
        version = 1,
        slot = 2,
        createdAt = 10,
        updatedAt = 20,
        state = {
            money = 321,
            inventory = { paper = 12, prints = 3 },
            shopProgress = { completedCuts = 7 },
        },
        player = { x = 444, y = 555 },
    }]])
    local migrated = context.save.load(2)
    check("save_v1_migration", migrated
        and migrated.version == context.save.VERSION
        and migrated.state.money == 321
        and migrated.state.inventory.paper == 12
        and migrated.state.inventory.rawPallets == 0
        and migrated.state.inventory.plasticWrapRolls == 1
        and migrated.state.inventory.plasticWrapUses == 11
        and migrated.state.wrapper.x == context.config.wrapperPlacement.spawnX
        and migrated.state.wrapper.direction == context.config.wrapperPlacement.defaultDirection
        and #migrated.state.jobs.active == 0
        and migrated.player.x == 444)
    context.save.delete(2)

    love.filesystem.write("saves/slot2.lua", [[{
        version = 2,
        slot = 2,
        createdAt = 30,
        updatedAt = 40,
        state = {
            money = 222,
            inventory = { paper = 8, prints = 2, rawPallets = 7, inProcessPallets = 6, finishedPallets = 5 },
            shopProgress = { completedCuts = 4 },
            jobs = { active = {}, completed = {}, declined = {} },
            nextJobId = 4,
            accountsReceivable = 15,
            procurement = { orders = {}, nextOrderId = 2 },
            vendorCategory = 3,
            cutter = { x = 610, y = 420, direction = "southwest", moving = false },
            palletJack = { x = 600, y = 500, direction = "northeast", operating = false, moving = false },
        },
        player = { x = 410, y = 520 },
    }]])
    local migratedV2 = context.save.load(2)
    check("save_v2_migration", migratedV2
        and migratedV2.version == context.save.VERSION
        and migratedV2.state.money == 222
        and migratedV2.state.inventory.plasticWrapRolls == 1
        and migratedV2.state.inventory.plasticWrapUses == 11
        and migratedV2.state.inventory.rawPallets == 0
        and migratedV2.state.wrapper.x == context.config.wrapperPlacement.spawnX
        and migratedV2.state.wrapper.direction == context.config.wrapperPlacement.defaultDirection
        and migratedV2.state.cutter.direction == "southwest"
        and migratedV2.player.y == 520)
    context.save.delete(2)

    for slot = 1, context.save.SLOT_COUNT do
        context.save.delete(slot)
        local fresh = context.save.newGame(slot)
        check("save_slot_" .. slot .. "_new_defaults", fresh
            and fresh.version == context.save.VERSION
            and fresh.slot == slot
            and fresh.state.money == 180
            and fresh.state.inventory.paper == 40
            and fresh.state.inventory.plasticWrapRolls == 1
            and fresh.state.inventory.plasticWrapUses == 11
            and fresh.state.wrapper.x == context.config.wrapperPlacement.spawnX
            and fresh.state.wrapper.y == context.config.wrapperPlacement.spawnY
            and fresh.state.wrapper.direction == context.config.wrapperPlacement.defaultDirection)
        fresh.state.money = 180 + slot
        fresh.state.wrapper.x = context.config.wrapperPlacement.spawnX + slot
        check("save_slot_" .. slot .. "_write", context.save.save(slot, fresh.state, fresh.player))
        local slotListing = context.save.listSlots()[slot]
        local slotLoaded = context.save.load(slot)
        check("save_slot_" .. slot .. "_load_and_list", slotLoaded
            and not slotListing.empty
            and slotListing.money == 180 + slot
            and slotLoaded.state.wrapper.x == context.config.wrapperPlacement.spawnX + slot)
        check("save_slot_" .. slot .. "_delete", context.save.delete(slot)
            and context.save.listSlots()[slot].empty)
    end

    local invalidNested = context.State.new()
    invalidNested.jobs.active = { { id = "BROKEN-JOB", pallets = "not-a-list" } }
    local preservedState = context.State.new()
    preservedState.money = 515
    check("save_invalid_write_setup", context.save.save(1, preservedState, { x = 1, y = 1 }))
    local beforeInvalidWrite = love.filesystem.read("saves/slot1.lua")
    check("save_nested_validation_rejects_invalid_job",
        not context.save.save(1, invalidNested, { x = 1, y = 1 })
        and love.filesystem.read("saves/slot1.lua") == beforeInvalidWrite
        and context.save.load(1).state.money == 515)
    context.save.delete(1)

    local backupState = context.State.new()
    backupState.money = 111
    check("save_backup_first_primary", context.save.save(1, backupState, { x = 101, y = 201 }))
    backupState.money = 222
    check("save_backup_second_primary", context.save.save(1, backupState, { x = 102, y = 202 }))
    check("save_last_known_good_backup_created", love.filesystem.getInfo("saves/slot1.lua.bak") ~= nil)
    love.filesystem.write("saves/slot1.lua", "{")
    local recoveredBackup, backupStatus = context.save.load(1)
    check("save_truncated_primary_recovers_backup", recoveredBackup
        and backupStatus == "recovered"
        and recoveredBackup.recoverySource == "backup"
        and recoveredBackup.state.money == 111
        and context.save.listSlots()[1].recovered)
    local restoredBackup = context.save.load(1)
    check("save_backup_recovery_restores_primary", restoredBackup and restoredBackup.state.money == 111)

    local temporaryState = context.State.new()
    temporaryState.money = 333
    check("save_temporary_recovery_setup", context.save.save(1, temporaryState, { x = 103, y = 203 }))
    local validTemporaryBytes = love.filesystem.read("saves/slot1.lua")
    love.filesystem.write("saves/slot1.lua.tmp", validTemporaryBytes)
    love.filesystem.write("saves/slot1.lua", "truncated")
    love.filesystem.remove("saves/slot1.lua.bak")
    local recoveredTemporary, temporaryStatus = context.save.load(1)
    check("save_invalid_primary_recovers_valid_temporary", recoveredTemporary
        and temporaryStatus == "recovered"
        and recoveredTemporary.recoverySource == "temporary"
        and recoveredTemporary.state.money == 333
        and context.save.load(1).state.money == 333)
    context.save.delete(1)

    love.filesystem.createDirectory("saves")
    love.filesystem.write("saves/slot1.lua", "{")
    love.filesystem.write("saves/slot1.lua.tmp", "also invalid")
    love.filesystem.write("saves/slot1.lua.bak", "still invalid")
    local corruptedListing = context.save.listSlots()[1]
    local corruptedPayload, corruptedStatus = context.save.load(1)
    check("save_unrecoverable_slot_is_visible", corruptedPayload == nil
        and corruptedStatus == "corrupted"
        and corruptedListing.corrupted
        and not corruptedListing.empty)
    local corruptedBytes = love.filesystem.read("saves/slot1.lua")
    local corruptStarts = 0
    context.state.screen = "title"
    context.title.enter(function() corruptStarts = corruptStarts + 1 end)
    context.input.keypressed("c", context.inputContext)
    check("title_corrupted_slot_cannot_continue", corruptStarts == 0
        and context.title.message:find("damaged", 1, true) ~= nil)
    context.input.keypressed("n", context.inputContext)
    check("title_corrupted_slot_requires_overwrite_confirmation",
        context.title.mode == "overwrite-confirm" and corruptStarts == 0)
    context.input.keypressed("n", context.inputContext)
    check("title_corrupted_overwrite_cancel_preserves_bytes",
        context.title.mode == "normal"
        and love.filesystem.read("saves/slot1.lua") == corruptedBytes)
    love.filesystem.write("saves/slot1.lua.bak.tmp", "invalid backup temporary")
    check("save_delete_removes_all_recovery_files", context.save.delete(1)
        and love.filesystem.getInfo("saves/slot1.lua") == nil
        and love.filesystem.getInfo("saves/slot1.lua.tmp") == nil
        and love.filesystem.getInfo("saves/slot1.lua.bak") == nil
        and love.filesystem.getInfo("saves/slot1.lua.bak.tmp") == nil)

    -- Title actions share one mouse/keyboard path. Exercise them against the
    -- smoke identity so the player's real save directory is never touched.
    context.save.delete(3)
    local occupiedState = context.State.new()
    occupiedState.money = 777
    check("title_occupied_slot_setup", context.save.save(3, occupiedState, { x = 333, y = 444 }))
    local occupiedBytes = love.filesystem.read("saves/slot3.lua")
    local titleStarts = {}
    local function captureTitleStart(startPayload, mode)
        local event = { payload = startPayload, mode = mode }
        titleStarts[#titleStarts + 1] = event
        if mode == "new" then
            event.saved = context.save.save(startPayload.slot, startPayload.state, startPayload.player)
        end
    end

    context.state.screen = "title"
    context.title.enter(captureTitleStart)
    context.input.keypressed("down", context.inputContext)
    check("title_keyboard_down_selects", context.title.selected == 2)
    context.input.keypressed("s", context.inputContext)
    check("title_keyboard_s_selects", context.title.selected == 3)
    context.input.keypressed("down", context.inputContext)
    check("title_keyboard_down_wraps", context.title.selected == 1)
    context.input.keypressed("up", context.inputContext)
    check("title_keyboard_up_wraps", context.title.selected == 3)
    context.input.keypressed("w", context.inputContext)
    check("title_keyboard_w_selects", context.title.selected == 2)
    context.input.keypressed("s", context.inputContext)

    local newX, newY = context.title.buttonCenter("new")
    local confirmX, confirmY = context.title.buttonCenter("yes")
    local cancelX, cancelY = context.title.buttonCenter("no")
    check("title_mouse_new_requires_overwrite_confirmation",
        context.input.mousepressed(newX, newY, 1, context.inputContext)
        and context.title.mode == "overwrite-confirm"
        and #titleStarts == 0
        and love.filesystem.read("saves/slot3.lua") == occupiedBytes)
    context.input.mousereleased(newX, newY, 1, context.inputContext)
    check("title_mouse_overwrite_cancel_preserves_bytes",
        context.input.mousepressed(cancelX, cancelY, 1, context.inputContext)
        and context.title.mode == "normal"
        and #titleStarts == 0
        and love.filesystem.read("saves/slot3.lua") == occupiedBytes)
    context.input.mousereleased(cancelX, cancelY, 1, context.inputContext)

    context.input.keypressed("n", context.inputContext)
    check("title_keyboard_new_requires_overwrite_confirmation",
        context.title.mode == "overwrite-confirm" and #titleStarts == 0)
    context.input.keypressed("n", context.inputContext)
    check("title_keyboard_overwrite_cancel_preserves_bytes",
        context.title.mode == "normal"
        and #titleStarts == 0
        and love.filesystem.read("saves/slot3.lua") == occupiedBytes)

    context.input.mousepressed(newX, newY, 1, context.inputContext)
    check("title_mouse_overwrite_confirmation_starts",
        context.input.mousepressed(confirmX, confirmY, 1, context.inputContext)
        and #titleStarts == 1
        and titleStarts[1].mode == "new"
        and titleStarts[1].saved
        and context.save.load(3).state.money == 180)
    context.input.mousereleased(confirmX, confirmY, 1, context.inputContext)

    occupiedState.money = 888
    context.save.save(3, occupiedState, { x = 333, y = 444 })
    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("n", context.inputContext)
    context.input.keypressed("y", context.inputContext)
    check("title_keyboard_overwrite_confirmation_starts",
        #titleStarts == 2
        and titleStarts[2].mode == "new"
        and titleStarts[2].saved
        and context.save.load(3).state.money == 180)

    context.save.delete(3)
    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("n", context.inputContext)
    check("title_empty_slot_new_starts_immediately",
        #titleStarts == 3
        and titleStarts[3].mode == "new"
        and titleStarts[3].saved
        and context.save.load(3) ~= nil)

    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("c", context.inputContext)
    check("title_keyboard_c_continues",
        #titleStarts == 4 and titleStarts[4].mode == "continue" and titleStarts[4].payload.slot == 3)
    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("return", context.inputContext)
    check("title_keyboard_enter_continues",
        #titleStarts == 5 and titleStarts[5].mode == "continue" and titleStarts[5].payload.slot == 3)

    local beforeDeleteCancel = love.filesystem.read("saves/slot3.lua")
    context.title.enter(captureTitleStart)
    context.input.keypressed("up", context.inputContext)
    context.input.keypressed("d", context.inputContext)
    check("title_keyboard_delete_requires_confirmation", context.title.mode == "delete-confirm")
    context.input.keypressed("n", context.inputContext)
    check("title_keyboard_delete_cancel_preserves_bytes",
        context.title.mode == "normal"
        and love.filesystem.read("saves/slot3.lua") == beforeDeleteCancel)
    context.input.keypressed("d", context.inputContext)
    context.input.keypressed("y", context.inputContext)
    check("title_keyboard_delete_confirmation_removes_slot",
        context.title.mode == "normal" and love.filesystem.getInfo("saves/slot3.lua") == nil)

    context.state.screen = "world"
    local reception = context.world.customerSnapshot()
    context.world.player.x, context.world.player.y = reception.x, reception.y + 28
    context.world.update(0, 0, 0, context.assets, context.state)
    local paperworkInteraction = context.world.getInteraction()
    local paperworkCustomer = context.world.customerSnapshot()
    check("paperwork_customer_selected", paperworkInteraction
        and paperworkInteraction.kind == "customer", string.format(
            "selected=%s customer=%s at %.1f,%.1f player=%.1f,%.1f",
            paperworkInteraction and paperworkInteraction.kind or "nil",
            paperworkCustomer.state, paperworkCustomer.x, paperworkCustomer.y,
            context.world.player.x, context.world.player.y))
    context.input.keypressed("e", context.inputContext)
    check("paperwork_popup_opens", context.state.screen == "job_offer"
        and context.state.currentOffer ~= nil
        and context.world.customerSnapshot().state == "reviewing")
    local popupAcceptX, popupAcceptY = context.jobOfferScreen.buttonCenter("accept")
    check("paperwork_mouse_accept", context.input.mousepressed(
        popupAcceptX, popupAcceptY, 1, context.inputContext))
    check("paperwork_mouse_accept_flow", context.state.screen == "world"
        and context.state.currentOffer == nil
        and #context.state.jobs.active == 1
        and context.world.customerSnapshot().state == "exiting"
        and context.world.customerSnapshot().decision == "accepted")

    context.world.player.x, context.world.player.y = 500, 235
    context.world.update(0, 0, 0, context.assets, context.state)
    check("computer_world_interaction_selected", context.world.getInteraction()
        and context.world.getInteraction().kind == "computer")
    context.input.keypressed("e", context.inputContext)
    check("computer_opens_from_world", context.state.screen == "computer")
    local liveInventoryX, liveInventoryY = context.computerScreen.tabCenter("inventory")
    check("computer_live_mouse_tab", context.input.mousepressed(
        liveInventoryX, liveInventoryY, 1, context.inputContext)
        and context.computerScreen.tab == "inventory")
    local liveCloseX, liveCloseY = context.computerScreen.closeCenter()
    check("computer_live_mouse_close", context.input.mousepressed(
        liveCloseX, liveCloseY, 1, context.inputContext)
        and context.state.screen == "world")
    context.input.keypressed("e", context.inputContext)
    check("computer_render_ready", context.state.screen == "computer"
        and #context.state.jobs.active == 1)
    check("computer_final_close", context.input.mousepressed(
        liveCloseX, liveCloseY, 1, context.inputContext)
        and context.state.screen == "world")

    context.world.player.x, context.world.player.y = 300, 335
    context.world.update(context.config.truck.scheduleDelay + 0.1, 0, 0, context.assets, context.state)
    check("accepted_job_schedules_truck", context.world.truckSnapshot().state == "waiting_for_bay"
        and context.world.truckSnapshot().jobId == context.state.jobs.active[1].id
        and context.state.jobs.active[1].delivery.status == "scheduled")
    check("truck_auto_opens_bay", context.world.bayDoorSnapshot().state == "opening")
    context.world.update(context.config.loadingBay.duration + 0.1, 0, 0, context.assets, context.state)
    check("truck_backs_after_bay_opens", context.world.bayDoorSnapshot().state == "open"
        and context.world.truckSnapshot().state == "backing")
    context.world.update(context.config.truck.backingDuration + 0.1, 0, 0, context.assets, context.state)
    check("truck_parks_for_accepted_job", context.world.truckSnapshot().state == "parked_closed"
        and context.state.jobs.active[1].delivery.status == "at_bay")
    check("occupied_bay_cannot_close", not context.world.toggleBayDoor(context.state)
        and context.world.bayDoorSnapshot().state == "open")
    if os.getenv("PICTURE_SHOP_TRUCK_DOCK_PREVIEW") == "1" then return end

    context.world.player.x = context.config.truck.interaction.x
    context.world.player.y = context.config.truck.interaction.y + 36
    context.world.update(0, 0, 0, context.assets, context.state)
    check("truck_cargo_world_interaction_selected", context.world.getInteraction()
        and context.world.getInteraction().kind == "truckCargoDoor")
    context.input.keypressed("e", context.inputContext)
    check("truck_cargo_world_opening", context.world.truckSnapshot().state == "cargo_opening")
    context.world.update(context.config.truck.cargoDuration + 0.1, 0, 0, context.assets, context.state)
    check("truck_cargo_world_open", context.world.truckSnapshot().state == "cargo_open"
        and context.world.truckSnapshot().cargoFrame == context.config.truck.cargoFrameCount)
    context.world.update(0, 0, 0, context.assets, context.state)
    context.input.keypressed("e", context.inputContext)
    check("truck_inventory_opens", context.state.screen == "truck_inventory")
    if os.getenv("PICTURE_SHOP_TRUCK_INVENTORY_PREVIEW") == "1" then return end
    local unload1X, unload1Y = context.truckInventoryScreen.unloadButtonCenter(1)
    local unload2X, unload2Y = context.truckInventoryScreen.unloadButtonCenter(2)
    check("truck_inventory_unload_first", context.input.mousepressed(
        unload1X, unload1Y, 1, context.inputContext))
    check("first_pallet_spawns", #context.world.palletsSnapshot(context.state) == 1
        and context.state.jobs.active[1].pallets[1].location == "warehouse"
        and context.state.inventory.rawPallets == 1)
    context.world.update(context.config.palletLogistics.unloadDuration + 0.1,
        0, 0, context.assets, context.state)
    local firstPhysical = context.world.palletsSnapshot(context.state)[1]
    local palletTooltip = context.world.palletTooltipAt(context.state, firstPhysical.x, firstPhysical.y - 30)
    check("physical_pallet_tooltip", palletTooltip
        and palletTooltip.title:find(context.state.jobs.active[1].company, 1, true)
        and palletTooltip.line1:find("1,000 sheets", 1, true)
        and palletTooltip.line2:find("JOB-0001-P01-PAPER", 1, true))
    check("truck_inventory_unload_second", context.input.mousepressed(
        unload2X, unload2Y, 1, context.inputContext))
    context.world.update(context.config.palletLogistics.unloadDuration + 0.1,
        0, 0, context.assets, context.state)
    check("all_pallets_received", #context.world.palletsSnapshot(context.state) == 2
        and context.state.jobs.active[1].status == "in_production"
        and context.state.jobs.active[1].delivery.status == "received"
        and context.state.inventory.rawPallets == 2)
    local closeDoorX, closeDoorY = context.truckInventoryScreen.closeDoorCenter()
    check("truck_inventory_close_empty_cargo", context.input.mousepressed(
        closeDoorX, closeDoorY, 1, context.inputContext)
        and context.state.screen == "world"
        and context.world.truckSnapshot().state == "cargo_closing")
    context.world.update(context.config.truck.cargoDuration + 0.1, 0, 0, context.assets, context.state)
    check("empty_truck_departs", context.world.truckSnapshot().state == "departing")
    context.world.update(context.config.truck.backingDuration + 0.1, 0, 0, context.assets, context.state)
    check("truck_departed_and_bay_closing", context.world.truckSnapshot().state == "absent"
        and context.world.bayDoorSnapshot().state == "closing")
    context.world.update(context.config.loadingBay.duration + 0.1, 0, 0, context.assets, context.state)
    check("bay_auto_closes_after_delivery", context.world.bayDoorSnapshot().state == "closed")
    check("pallets_render_ready", context.state.screen == "world"
        and #context.world.palletsSnapshot(context.state) == 2)
    check("loose_and_carried_pallet_scale_match",
        context.config.palletLogistics.drawScale
            == context.config.palletJack.drawScale * context.config.palletJack.carriedPalletArtRatio)

    local jackStart = context.world.palletJackSnapshot(context.state)
    context.world.player.x, context.world.player.y = jackStart.x, jackStart.y + 38
    context.world.update(0, 0, 0, context.assets, context.state)
    check("pallet_jack_interaction_selected", context.world.getInteraction()
        and context.world.getInteraction().kind == "palletJack")
    context.input.keypressed("e", context.inputContext)
    check("pallet_jack_mount", context.world.palletJackSnapshot(context.state).operating)
    local operatorX, operatorY = context.PalletJack.operatorPosition(context.state, context.config.palletJack)
    check("pallet_jack_operator_stands_at_handle", context.world.player.x == operatorX
        and context.world.player.y == operatorY
        and math.abs(operatorX - jackStart.x) >= context.config.palletJack.obstacleRadius)
    local beforeDriveX = context.world.palletJackSnapshot(context.state).x
    context.world.update(0.15, -1, 0, context.assets, context.state)
    check("pallet_jack_empty_drive", context.world.palletJackSnapshot(context.state).x < beforeDriveX
        and context.world.palletJackSnapshot(context.state).direction == "southwest")
    context.world.update(0.04, 1, 0, context.assets, context.state)
    check("pallet_jack_faces_northeast", context.world.palletJackSnapshot(context.state).direction == "northeast")
    context.world.update(0.04, 0, -1, context.assets, context.state)
    check("pallet_jack_faces_northwest", context.world.palletJackSnapshot(context.state).direction == "northwest")
    context.world.update(0.04, 0, 1, context.assets, context.state)
    check("pallet_jack_faces_southeast", context.world.palletJackSnapshot(context.state).direction == "southeast")

    local pickupTarget = context.world.palletsSnapshot(context.state)[1]
    context.state.palletJack.x = pickupTarget.x - 48
    context.state.palletJack.y = pickupTarget.y
    context.world.update(0, 0, 0, context.assets, context.state)
    context.input.keypressed("e", context.inputContext)
    check("pallet_jack_lifts_pallet", context.world.palletJackSnapshot(context.state).carriedPalletId
        == pickupTarget.pallet.id
        and pickupTarget.pallet.location == "on_pallet_jack"
        and #context.world.palletsSnapshot(context.state) == 1)
    context.state.palletJack.x, context.state.palletJack.y = 520, 500
    context.world.player.x, context.world.player.y = 520, 504
    context.world.update(0.18, 0, -1, context.assets, context.state)
    local loadedJack = context.world.palletJackSnapshot(context.state)
    check("pallet_jack_loaded_drive", loadedJack.direction == "northwest"
        and loadedJack.y < 500
        and pickupTarget.pallet.world.x == loadedJack.x
        and pickupTarget.pallet.world.y == loadedJack.y)
    local carriedTooltip = context.world.palletTooltipAt(context.state, loadedJack.x, loadedJack.y - 40)
    check("carried_pallet_tooltip", carriedTooltip
        and carriedTooltip.title:find(pickupTarget.pallet.id, 1, true))
    if os.getenv("PICTURE_SHOP_PALLET_JACK_PREVIEW") == "1" then return end
    context.world.update(0, 0, 0, context.assets, context.state)
    context.input.keypressed("e", context.inputContext)
    check("pallet_jack_lowers_pallet", context.world.palletJackSnapshot(context.state).carriedPalletId == nil
        and pickupTarget.pallet.location == "warehouse"
        and #context.world.palletsSnapshot(context.state) == 2
        and pickupTarget.pallet.world.direction == "northwest"
        and pickupTarget.pallet.world.rotation == 1)
    context.state.palletJack.direction = "southeast"
    context.world.update(0, 0, 0, context.assets, context.state)
    check("dropped_pallet_keeps_last_direction", pickupTarget.pallet.world.direction == "northwest"
        and pickupTarget.pallet.world.rotation == 1)
    context.input.keypressed("f", context.inputContext)
    check("pallet_jack_parks", not context.world.palletJackSnapshot(context.state).operating)
    local parkedJack = context.world.palletJackSnapshot(context.state)
    context.world.player.x, context.world.player.y = parkedJack.x, parkedJack.y
    context.world.update(0.25, 1, 0, context.assets, context.state)
    check("player_can_escape_pallet_jack_overlap", context.world.player.x > parkedJack.x)
    local overlapPallet = context.world.palletsSnapshot(context.state)[1]
    context.world.player.x, context.world.player.y = overlapPallet.x, overlapPallet.y
    context.world.update(0.25, -1, 0, context.assets, context.state)
    check("player_can_escape_pallet_overlap", context.world.player.x < overlapPallet.x)
    context.state.cutter.x = context.config.cutterPlacement.spawnX
    context.state.cutter.y = context.config.cutterPlacement.spawnY
    context.state.cutter.direction = "northwest"
    context.state.cutter.moving = false
    context.world.player.x = context.state.cutter.x
    context.world.player.y = context.state.cutter.y + 70
    context.world.update(0, 0, 0, context.assets, context.state)
    check("cutter_floor_interaction_selected", context.world.getInteraction()
        and context.world.getInteraction().kind == "cutter")
    context.input.keypressed("m", context.inputContext)
    check("cutter_relocation_begins", context.world.cutterSnapshot(context.state).moving)
    local cutterBeforeMove = context.world.cutterSnapshot(context.state)
    context.world.update(0.15, -1, 0, context.assets, context.state)
    check("cutter_relocation_moves", context.world.cutterSnapshot(context.state).x < cutterBeforeMove.x)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_northeast", context.world.cutterSnapshot(context.state).frame == 2)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_southeast", context.world.cutterSnapshot(context.state).frame == 4)
    if os.getenv("PICTURE_SHOP_CUTTER_PLACEMENT_PREVIEW") == "1" then return end
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_southwest", context.world.cutterSnapshot(context.state).frame == 3)
    context.input.keypressed("q", context.inputContext)
    check("cutter_rotates_northwest", context.world.cutterSnapshot(context.state).frame == 1)
    context.input.keypressed("e", context.inputContext)
    check("cutter_relocation_places", not context.world.cutterSnapshot(context.state).moving)
    if os.getenv("PICTURE_SHOP_TITLE_PREVIEW") == "1" then
        context.state.screen = "title"
    elseif os.getenv("PICTURE_SHOP_CUTTER_PREVIEW") == "1" then
        context.state.screen = "machine"
        context.machine.reset(context.state)
        context.machine.load(context.state)
        context.machine.update(context.machine.transferTime + 0.01, context.state)
        context.machine.autoGauge(context.state)
        context.machine.keypressed("q", context.state)
        context.machine.position(context.state)
        context.machine.update(context.machine.transferTime + 0.01, context.state)
        context.machine.toggleClamp(context.state)
        context.machine.update(0.3, context.state)
    elseif os.getenv("PICTURE_SHOP_VENDOR_PREVIEW") == "1" then
        context.state.screen = "vendor"
        context.state.vendorCategory = 3
    end
end

function Smoke.requested()
    return requested()
end

function Smoke.start(context)
    if not requested() then return end
    Smoke.active = true
    local reportPath = os.getenv("PICTURE_SHOP_SMOKE_REPORT") or "smoke-report.rpt"
    local report, errorMessage = io.open(reportPath, "w")
    if not report then
        io.stderr:write("SMOKE_REPORT_ERROR: " .. tostring(errorMessage) .. "\n")
        love.event.quit(1)
        return
    end
    Smoke.report = report
    writeLine("THE_PICTURE_SHOP_SMOKE version=2")

    local ok, message = xpcall(function() runChecks(context) end, debug.traceback)
    if not ok then
        Smoke.failed = true
        writeLine("FAIL " .. tostring(message))
        io.stderr:write("SMOKE_ERROR: " .. tostring(message) .. "\n")
        io.stderr:flush()
    else
        Smoke.completed = true
        writeLine("CHECKS_COMPLETE")
    end
end

function Smoke.drawn()
    if not Smoke.active then return end
    Smoke.drawCount = Smoke.drawCount + 1
    if Smoke.drawCount == 1 and os.getenv("PICTURE_SHOP_SMOKE_SCREENSHOT") == "1" then
        love.graphics.captureScreenshot("step6-smoke-preview.png")
    end
    if Smoke.failed then
        if Smoke.report then Smoke.report:close() end
        love.event.quit(1)
    elseif Smoke.completed and Smoke.drawCount >= 3 then
        writeLine("PASS render_three_frames")
        writeLine("SMOKE_OK")
        Smoke.report:close()
        print("SMOKE_OK: module checks and three draw frames completed")
        io.flush()
        love.event.quit(0)
    end
end

return Smoke
