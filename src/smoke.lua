local Suites = require("src.tests.suites")
local CutterIntegration = require("src.tests.cutter_integration_test")
local JobLoopIntegration = require("src.tests.job_loop_integration_test")
local SaveIntegration = require("src.tests.save_integration_test")
local UiIntegration = require("src.tests.ui_integration_test")

local Smoke = {
    active = false,
    completed = false,
    failed = false,
    drawCount = 0,
    report = nil,
    passed = {},
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
    if Smoke.passed[name] then error("duplicate smoke check name: " .. name) end
    Smoke.passed[name] = true
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

local function centerOnlyWalkmaskPoint(context, halfWidth, halfHeight)
    for y = 92, context.config.baseHeight - 48, 2 do
        for x = 56, context.config.baseWidth - 56, 2 do
            if context.Navigation.isWalkable(context.assets, x, y, {})
                and not context.Navigation.isAreaWalkable(
                    context.assets, x, y, halfWidth, halfHeight)
            then
                return x, y
            end
        end
    end
end

local function runChecks(context)
    local healthy, failures = context.assets.assertHealthy()
    check("asset_contract", healthy, failures)
    check("startup_texture_memory_below_100_mib",
        context.startupTextureBytes < 100 * 1024 * 1024,
        string.format("%.2f MiB", context.startupTextureBytes / 1024 / 1024))
    check("screen_packs_start_unloaded", context.assets.activePackName() == nil
        and context.assets.get("polarOperatorConsole") == nil
        and context.assets.get("wrappedPalletStages") == nil)
    check("shared_back_button_stays_loaded", context.assets.get("polarBackButton") ~= nil)
    local dimensionsValid, dimensionError = context.assets.dimensionDiagnostic(
        "assets/generated/test-malformed-atlas.png", 1251, 1252, 1252, 1252)
    local startupDiagnostics = context.assetErrorScreen.normalize(
        "assets/generated/test-missing.png: missing required asset", dimensionError)
    check("asset_diagnostic_names_missing_path", not dimensionsValid
        and startupDiagnostics[1]:find("assets/generated/test-missing.png", 1, true)
        and startupDiagnostics[2]:find("assets/generated/test-malformed-atlas.png", 1, true))
    check("asset_diagnostic_explains_malformed_dimensions",
        startupDiagnostics[2]:find("expected 1252x1252, got 1251x1252", 1, true))
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
    check("character_anchor_scans_eliminated", context.characterAssets.anchorPixelScans() == 0)
    check("character_packs_start_unloaded", context.characterAssets.residentActionCount() == 0)
    for character, actions in pairs(expectedCharacters) do
        for action, count in pairs(actions) do
            local image, quad, actual = context.characterAssets.get(character, action, 1)
            check(character .. "_" .. action .. "_loaded", image ~= nil and quad ~= nil and actual == count)
        end
    end
    check("character_actions_load_on_demand", context.characterAssets.residentActionCount() > 0)
    context.characterAssets.retainCharacters({ ["business-dragon"] = true })
    check("inactive_character_packs_release",
        context.characterAssets.residentActionCount() == 3)
    context.characterAssets.retainCharacters({})
    check("all_character_packs_release", context.characterAssets.residentActionCount() == 0
        and context.characterAssets.textureBytes() == 0)

    local background = context.assets.get("warehouse")
    local mask = context.assets.getData("walkmask")
    local loadingBayDoor = context.assets.get("loadingBayDoor")
    local deliveryTruck = context.assets.get("deliveryTruck")
    local truckCargoDoor = context.assets.get("truckCargoDoor")
    check("warehouse_loaded", background ~= nil)
    check("walkmask_cpu_copy_loaded", mask ~= nil)
    check("walkmask_gpu_texture_omitted", context.assets.get("walkmask") == nil)
    check("loading_bay_door_asset_loaded", loadingBayDoor ~= nil)
    check("delivery_truck_asset_loaded", deliveryTruck ~= nil)
    check("truck_cargo_door_asset_loaded", truckCargoDoor ~= nil)
    check("picture_press_excluded_from_runtime", context.assets.get("picturePress") == nil
        and context.config.paths.picturePress == nil)
    check("polar_direction_strip_loaded", context.assets.get("polarDirections") ~= nil)
    check("loaded_paper_pallet_directions_loaded", context.assets.get("loadedPaperPalletDirections") ~= nil)
    check("pallet_jack_asset_loaded", context.assets.get("palletJack") ~= nil)
    check("loaded_pallet_jack_asset_loaded", context.assets.get("palletJackLoaded") ~= nil)
    check("vendor_product_pallet_atlas_loaded", context.assets.get("vendorProductPallets") ~= nil)
    check("boxed_paper_pallet_stages_loaded", context.assets.get("boxedPaperPalletStages") ~= nil)
    for frame = 1, context.config.loadingBay.frameCount do
        check("loading_bay_door_frame_" .. frame,
            context.assets.getQuad("loadingBayDoor" .. frame) ~= nil)
    end
    for frame = 1, context.config.truck.cargoFrameCount do
        check("truck_cargo_door_frame_" .. frame,
            context.assets.getQuad("truckCargoDoor" .. frame) ~= nil)
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
    check("menu_pack_activates", context.assets.activatePack("menu")
        and context.assets.activePackName() == "menu"
        and context.assets.get("polarOperatorConsole") ~= nil
        and context.assets.get("cutterControlButtons") ~= nil
        and context.assets.get("cutterClamp") == nil)
    check("cutter_pack_replaces_menu_pack", context.assets.activatePack("cutter")
        and context.assets.activePackName() == "cutter")
    check("polar_operator_console_loaded", context.assets.get("polarOperatorConsole") ~= nil)
    check("cutter_button_strip_loaded", context.assets.get("cutterControlButtons") ~= nil)
    check("cutter_clamp_strip_loaded", context.assets.get("cutterClamp") ~= nil)
    check("cutter_blade_strip_loaded", context.assets.get("cutterBlade") ~= nil)
    check("polar_back_button_strip_loaded", context.assets.get("polarBackButton") ~= nil)
    for frame = 1, 3 do
        check("polar_back_button_frame_" .. frame,
            context.assets.getQuad("polarBackButton" .. frame) ~= nil)
    end
    for frame = 1, context.config.cutterGui.motionFrameCount do
        check("cutter_clamp_frame_" .. frame, context.assets.getQuad("cutterClamp" .. frame) ~= nil)
        check("cutter_blade_frame_" .. frame, context.assets.getQuad("cutterBlade" .. frame) ~= nil)
    end
    check("wrapper_pack_replaces_cutter_pack", context.assets.activatePack("wrapper")
        and context.assets.activePackName() == "wrapper"
        and context.assets.get("polarOperatorConsole") == nil
        and context.assets.get("wrappedPalletStages") ~= nil
        and context.assets.get("loadedPaperPallet") ~= nil)
    for frame = 1, 3 do
        check("wrapped_pallet_stage_" .. frame,
            context.assets.getQuad("wrappedPalletStage" .. frame) ~= nil)
    end
    check("screen_pack_releases_to_world", context.assets.activatePack(nil)
        and context.assets.activePackName() == nil
        and context.assets.get("wrappedPalletStages") == nil
        and context.assets.get("loadedPaperPallet") == nil)
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
    do
        local footprints = {
            { name = "cutter", width = context.config.cutterPlacement.collisionHalfWidth,
                height = context.config.cutterPlacement.collisionHalfHeight },
            { name = "wrapper", width = context.config.wrapperPlacement.collisionHalfWidth,
                height = context.config.wrapperPlacement.collisionHalfHeight },
            { name = "loaded_jack", width = context.config.palletJack.loadedCollisionHalfWidth,
                height = context.config.palletJack.loadedCollisionHalfHeight },
        }
        for _, footprint in ipairs(footprints) do
            local edgeX, edgeY = centerOnlyWalkmaskPoint(context, footprint.width, footprint.height)
            check(footprint.name .. "_full_footprint_rejects_blocked_corner", edgeX
                and context.Navigation.isWalkable(context.assets, edgeX, edgeY, {})
                and not context.Navigation.canMoveAreaFrom(context.assets,
                    edgeX, edgeY, edgeX, edgeY, footprint.width, footprint.height, {}))
        end
        local palletX, palletY = centerOnlyWalkmaskPoint(context,
            context.config.palletLogistics.collisionHalfWidth,
            context.config.palletLogistics.collisionHalfHeight)
        check("pallet_drop_rejects_blocked_corner", palletX
            and not context.world.isPalletPlacementClear(
                context.State.new(), context.assets, palletX, palletY))
    end

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
    local purchaseSucceeded, purchaseOrder = context.procurement.buy(serviceState, 1, 1)
    check("office_purchase_order_setup", purchaseSucceeded and purchaseOrder.id == "PO-0001")

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
    local purchaseRowX, purchaseRowY = context.computerScreen.rowCenter(2)
    local selectedPurchase = context.computerScreen.mousepressed(
        serviceState, purchaseRowX, purchaseRowY, 1)
    check("computer_purchase_order_delivery_list", selectedPurchase
        and selectedPurchase.job == purchaseOrder
        and context.computerScreen.statusLabel(purchaseOrder.delivery.status)
            == "Awaiting truck schedule")
    check("computer_status_vocabulary", context.computerScreen.statusLabel("in_production")
        == "In production"
        and context.computerScreen.statusLabel("pickup_in_progress") == "Pickup in progress"
        and context.computerScreen.statusLabel("completed") == "Completed and paid")
    check("computer_inventory_tab_click", context.computerScreen.mousepressed(
        serviceState, inventoryTabX, inventoryTabY, 1).tab == "inventory")
    local officeInventory = context.procurement.inventoryRows(serviceState)
    check("computer_inventory_exposes_purchasable_stock", #officeInventory == 4
        and officeInventory[1].id == "house_sheets"
        and officeInventory[3].id == "shipping_cartons"
        and officeInventory[4].id == "stretch_film")
    local closeX, closeY = context.computerScreen.closeCenter()
    check("computer_close_hit_target", context.computerScreen.mousepressed(
        serviceState, closeX, closeY, 1).action == "close")
    check("computer_ignores_outside_click", context.computerScreen.mousepressed(
        serviceState, 10, 10, 1) == nil)

    JobLoopIntegration.run(context, check, jobs)

    CutterIntegration.run(context, check, jobs)

    SaveIntegration.run(context, check, economy, jobs)

    UiIntegration.run(context, check)
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
    Smoke.passed = {}
    writeLine("THE_PICTURE_SHOP_SMOKE version=3")

    local ok, message = xpcall(function()
        runChecks(context)
        Suites.runDomain(context, check)
        Suites.verifyAuditCoverage(Smoke.passed, check)
    end, debug.traceback)
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
        love.graphics.captureScreenshot("smoke-preview.png")
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
