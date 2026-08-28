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

function Smoke.spriteLabRequested()
    return requested() and os.getenv("PICTURE_SHOP_SPRITE_LAB") == "1"
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
        and context.assets.get("wrappedPalletStages") ~= nil)
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
    check("wall_vent_fan_three_frame_asset", context.assets.get("wallVentFan") ~= nil
        and context.assets.getQuad("wallVentFan1") ~= nil
        and context.assets.getQuad("wallVentFan2") ~= nil
        and context.assets.getQuad("wallVentFan3") ~= nil)
    check("wall_vent_fan_is_thirty_five_percent_larger",
        math.abs(context.config.wallVentFan.drawScale - 0.405) < 0.0001)
    check("pallet_jack_twenty_percent_smaller_without_shrinking_loose_pallets",
        math.abs(context.config.palletJack.drawScale - 0.416) < 0.0001
        and math.abs(context.config.palletJack.drawScale
            * context.config.palletJack.carriedPalletArtRatio
            - context.config.palletLogistics.drawScale) < 0.0001)
    local singleFrameClient = context.Customer.new(context.config.customer)
    singleFrameClient.animationClock = 123.45
    check("seated_clients_draw_exactly_one_atlas_frame",
        singleFrameClient:frameForAction("sit", 2) == 1
        and singleFrameClient:frameForAction("idle", 2) == 1)
    singleFrameClient.animationClock = 0.5
    check("explicit_use_action_animates",
        singleFrameClient:frameForAction("use", 3) == 2)
    check("character_action_lookup_matches_promoted_pack",
        context.characterAssets.hasAction("green-blazer-cat", "use")
        and not context.characterAssets.hasAction("tan-cat", "use"))
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
    local printWrapperState = context.State.new()
    local printWrapperPallet = {
        id = "WRAP-PRINT-P01", number = 1, status = "cut", location = "cutter_output",
        packaging = "flat", wrapped = false, press = { status = "awaiting_cut" },
        world = { x = printWrapperState.wrapper.x - 60, y = printWrapperState.wrapper.y,
            spawnProgress = 1 },
    }
    printWrapperState.jobs.active = { {
        id = "WRAP-PRINT", packaging = "flat", press = { colors = 1 },
        pallets = { printWrapperPallet },
    } }
    context.wrapper.reset(printWrapperState)
    check("print_pallet_cannot_wrap_before_press_completion",
        context.wrapper.nearbyPallet(printWrapperState) == nil)
    printWrapperPallet.press.status, printWrapperPallet.status = "complete", "printed"
    check("completed_print_pallet_can_enter_wrapper",
        context.wrapper.nearbyPallet(printWrapperState) ~= nil)
    local wrapperSelectionState = context.State.new()
    wrapperSelectionState.jobs.active = { { id = "WRAP-SELECT", packaging = "flat", pallets = {
        { id = "WRAP-SELECT-P01", number = 1, status = "cut", location = "warehouse",
            packaging = "flat", wrapped = false,
            world = { x = wrapperSelectionState.wrapper.x - 72, y = wrapperSelectionState.wrapper.y,
                spawnProgress = 1 } },
        { id = "WRAP-SELECT-P02", number = 2, status = "finished", location = "warehouse",
            packaging = "flat", wrapped = false,
            world = { x = wrapperSelectionState.wrapper.x + 72, y = wrapperSelectionState.wrapper.y,
                spawnProgress = 1 } },
    } } }
    context.wrapper.reset(wrapperSelectionState)
    check("skid_wrapper_lists_all_nearby_pallets",
        #context.wrapper.nearbyPallets(wrapperSelectionState) == 2)
    wrapperSelectionState.machineType = "skid_wrapper"
    local wrapperPalletX, wrapperPalletY = context.machineScreen.wrapperPalletCenter(2)
    check("skid_wrapper_picker_selects_clicked_or_controller_cursor_pallet",
        context.machineScreen.mousepressed(wrapperSelectionState, wrapperPalletX, wrapperPalletY, 1)
        and context.wrapper.start(wrapperSelectionState)
        and context.wrapper.pallet.id == "WRAP-SELECT-P02")
    context.wrapper.update(context.wrapper.cycleTime + 0.1, wrapperSelectionState)
    context.wrapper.reset(wrapperSelectionState)
    local wrapperDirection = wrapperState.wrapper.direction
    wrapperState.palletJack.operating = true
    wrapperState.palletJack.carriedPalletId = nil
    wrapperState.palletJack.x, wrapperState.palletJack.y = wrapperState.wrapper.x, wrapperState.wrapper.y
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
        ["business-cat"] = {
            idle = 2, idle_north = 2, idle_northeast = 2,
            idle_southeast = 2, idle_south = 2,
            walk = 8, walk_north = 8, walk_northeast = 8,
            walk_southeast = 8, walk_south = 8, sit = 2,
        },
    }
    local charactersHealthy, characterFailures = context.characterAssets.assertHealthy()
    check("character_asset_contract", charactersHealthy, characterFailures)
    check("character_anchor_scans_eliminated", context.characterAssets.anchorPixelScans() == 0)
    check("character_packs_start_unloaded", context.characterAssets.residentActionCount() == 0)
    for character, actions in pairs(expectedCharacters) do
        for action, count in pairs(actions) do
            local image, quad, actual = context.characterAssets.get(character, action, 1)
            check(character .. "_" .. action .. "_loaded", image ~= nil and quad ~= nil and actual == count)
            local maximumHeight, minimumHeight = 0, math.huge
            for frame = 1, count do
                local metrics = context.characterAssets.normalizedFrameMetrics(character, action, frame)
                maximumHeight = math.max(maximumHeight, metrics and metrics.height or 0)
                minimumHeight = math.min(minimumHeight, metrics and metrics.height or math.huge)
            end
            check(character .. "_" .. action .. "_normalized_frame_height_stable",
                minimumHeight > 0 and maximumHeight / minimumHeight <= 1.03)
        end
        local idle = context.characterAssets.normalizedFrameMetrics(character, "idle", 1)
        for action in pairs(actions) do
            local metrics = context.characterAssets.normalizedFrameMetrics(character, action, 1)
            check(character .. "_" .. action .. "_matches_character_scale",
                idle and metrics and math.abs(metrics.height - idle.height) / idle.height <= 0.03)
            check(character .. "_" .. action .. "_matches_player_world_height",
                metrics and math.abs(
                    metrics.height * context.config.customer.drawScale
                    - context.config.characterRendering.referenceHeight
                        * context.config.player.drawScale) <= 1)
        end
    end
    check("business_seated_art_receives_source_scale_correction",
        context.characterAssets.getNormalization("business-dragon", "sit") > 2
        and context.characterAssets.getNormalization("business-dragon", "sit") < 3)
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
    local machineFlatbedLoaded = context.assets.get("machineFlatbedLoaded")
    local machineFlatbedEmpty = context.assets.get("machineFlatbedEmpty")
    check("warehouse_loaded", background ~= nil)
    check("walkmask_cpu_copy_loaded", mask ~= nil)
    check("walkmask_gpu_texture_omitted", context.assets.get("walkmask") == nil)
    check("loading_bay_door_asset_loaded", loadingBayDoor ~= nil)
    check("delivery_truck_asset_loaded", deliveryTruck ~= nil)
    check("truck_cargo_door_asset_loaded", truckCargoDoor ~= nil)
    check("machine_flatbed_loaded_asset_loaded", machineFlatbedLoaded ~= nil)
    check("machine_flatbed_empty_asset_loaded", machineFlatbedEmpty ~= nil)
    check("picture_press_excluded_from_runtime", context.assets.get("picturePress") == nil
        and context.config.paths.picturePress == nil)
    check("polar_direction_strip_loaded", context.assets.get("polarDirections") ~= nil)
    check("loaded_paper_pallet_directions_loaded", context.assets.get("loadedPaperPalletDirections") ~= nil)
    check("pallet_jack_asset_loaded", context.assets.get("palletJack") ~= nil)
    check("loaded_pallet_jack_asset_loaded", context.assets.get("palletJackLoaded") ~= nil)
    check("vendor_product_pallet_atlas_loaded", context.assets.get("vendorProductPallets") ~= nil)
    check("boxed_paper_pallet_stages_loaded", context.assets.get("boxedPaperPalletStages") ~= nil)
    for artworkKey in pairs(context.config.paths.artwork or {}) do
        check("artwork_" .. artworkKey .. "_loaded", context.assets.getArtwork(artworkKey) ~= nil)
    end
    local artworkRegistry, artworkOrderValid = {}, true
    for _, artworkKey in ipairs(context.config.artworkOrder or {}) do
        if artworkRegistry[artworkKey] or not context.config.paths.artwork[artworkKey] then
            artworkOrderValid = false
        end
        artworkRegistry[artworkKey] = true
    end
    local artworkPathCount = 0
    for artworkKey in pairs(context.config.paths.artwork or {}) do
        artworkPathCount = artworkPathCount + 1
        if not artworkRegistry[artworkKey] then artworkOrderValid = false end
    end
    check("artwork_job_rotation_covers_full_registry", artworkOrderValid
        and artworkPathCount == #(context.config.artworkOrder or {}))
    local artworkOfferState = context.State.new()
    local observedArtwork = {}
    for sequence = 1, math.max(12, #(context.config.artworkOrder or {})) do
        artworkOfferState.nextJobId = sequence
        local offer = context.jobService.createNextOffer(artworkOfferState, 1000 + sequence)
        if not offer or not artworkRegistry[offer.artworkKey] then artworkOrderValid = false; break end
        observedArtwork[offer.artworkKey] = true
    end
    local observedCount = 0
    for _ in pairs(observedArtwork) do observedCount = observedCount + 1 end
    check("randomized_artwork_reaches_job_offers", artworkOrderValid and observedCount >= 4)
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
    for frame = 1, context.config.palletJack.palletFrameCount do
        check("loaded_pallet_direction_" .. frame, context.assets.getQuad("loadedPaperPallet" .. frame) ~= nil)
        for row = 1, 4 do
            check("vendor_product_pallet_" .. row .. "_direction_" .. frame,
                context.assets.getQuad("vendorProductPallet" .. row .. "_" .. frame) ~= nil)
        end
    end
    for frame = 1, context.config.palletJack.frameCount do
        check("pallet_jack_direction_" .. frame, context.assets.getQuad("palletJack" .. frame) ~= nil)
        check("loaded_pallet_jack_direction_" .. frame, context.assets.getQuad("palletJackLoaded" .. frame) ~= nil)
    end
    local wrappedImage, wrappedSprite, wrappedScale = context.worldRenderer.palletVisual({
        vendor = false,
        pallet = { packaging = "flat", wrapped = true, direction = "northwest", rotation = 1 },
    })
    check("wrapped_flat_pallet_uses_finished_sprite_without_overlay",
        wrappedImage == "wrappedPalletStages"
        and wrappedSprite == "wrappedPalletStage3"
        and math.abs(wrappedScale - context.config.palletLogistics.drawScale * 0.5) < 0.0001)
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
    check("press_pack_replaces_wrapper_pack", context.assets.activatePack("press")
        and context.assets.activePackName() == "press"
        and context.assets.get("wrapperMaintenanceAtlas") == nil
        and context.assets.get("pressProcessStages") ~= nil
        and context.assets.get("pressOperatorHandbook") ~= nil)
    for frame = 1, 4 do
        check("press_process_stage_" .. frame,
            context.assets.getQuad("pressProcessStage" .. frame) ~= nil)
    end
    for frame = 1, 6 do
        check("press_handbook_page_" .. frame,
            context.assets.getQuad("pressHandbookPage" .. frame) ~= nil)
    end
    check("screen_pack_releases_to_world", context.assets.activatePack(nil)
        and context.assets.activePackName() == nil
        and context.assets.get("wrappedPalletStages") ~= nil
        and context.assets.get("loadedPaperPallet") == nil
        and context.assets.get("pressProcessStages") == nil
        and context.assets.get("pressOperatorHandbook") == nil)
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
        and door:frame() == 1)
    check("bay_door_sprite_never_blocks_floor_movement", door:getObstacle() == nil)
    local doorObstacles = {}
    if door:getObstacle() then doorObstacles[1] = door:getObstacle() end
    check("closed_bay_apron_uses_walkmask_only",
        context.Navigation.canMoveFrom(context.assets, 170, 267, 180, 267, doorObstacles))
    check("bay_door_begins_opening", door:open() and door.state == "opening")
    check("bay_door_ignores_toggle_while_moving", not door:toggle())
    door:update(context.config.loadingBay.duration * 0.5)
    check("bay_door_half_open_frame", door.state == "opening" and door:frame() == 3)
    door:update(context.config.loadingBay.duration * 0.5)
    check("bay_door_opens", door.state == "open"
        and door:frame() == context.config.loadingBay.frameCount)
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
    local startY, parkedY = context.config.truck.start.y, context.config.truck.parked.y
    local travelX, travelY = parkedX - startX, parkedY - startY
    local travelLength = math.sqrt(travelX * travelX + travelY * travelY)
    local bodyAxis = context.config.truck.bodyAxis
    local axisLength = math.sqrt(bodyAxis.x * bodyAxis.x + bodyAxis.y * bodyAxis.y)
    local alignmentError = math.abs(travelX * bodyAxis.y - travelY * bodyAxis.x)
        / (travelLength * axisLength)
    local rearwardDot = travelX * bodyAxis.x + travelY * bodyAxis.y
    check("truck_reverses_straight_toward_dock", midTruck.backingProgress > 0.45
        and midTruck.backingProgress < 0.55
        and midTruck.x > math.min(startX, parkedX)
        and midTruck.x < math.max(startX, parkedX)
        and midTruck.y > math.min(startY, parkedY)
        and midTruck.y < math.max(startY, parkedY)
        and rearwardDot > 0
        and alignmentError < 0.02)
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

    local _, _, rabbitIdleFrames = context.characterAssets.get("rabbit-worker", "idle", 1)
    local _, _, rabbitWalkFrames = context.characterAssets.get("rabbit-worker", "walk", 1)
    local directionalFramesHealthy = true
    for _, action in ipairs({
        "walk_north", "walk_northeast", "walk_southeast", "walk_south",
        "idle_north", "idle_northeast", "idle_southeast", "idle_south",
    }) do
        local _, _, frameCount = context.characterAssets.get("rabbit-worker", action, 1)
        directionalFramesHealthy = directionalFramesHealthy
            and frameCount == (action:match("^walk") and 8 or 2)
            and context.characterAssets.hasAction("rabbit-worker", action)
    end
    check("rabbit_player_character_pack",
        rabbitIdleFrames == 2 and rabbitWalkFrames == 8 and directionalFramesHealthy
        and context.characterAssets.hasAction("rabbit-worker", "idle")
        and context.characterAssets.hasAction("rabbit-worker", "walk"))

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

    local spacedVisitor = context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 10, y = 0 } },
        initialArrivalDelay = 2,
        arrivalDelayMin = 10,
        arrivalDelayMax = 20,
    })
    check("visitor_uses_initial_arrival_delay", spacedVisitor.timer == 2)
    spacedVisitor:update(1, { x = 500, y = 500 }, true)
    check("visitor_cooldown_pauses_for_occupied_reception", spacedVisitor.timer == 2
        and spacedVisitor.state == "scheduled")
    spacedVisitor:reset(false)
    check("visitor_repeat_arrival_is_randomized_in_range",
        spacedVisitor.timer >= 10 and spacedVisitor.timer <= 20)

    local declinedCustomer = context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 10, y = 0 } },
        speed = 100,
        arrivalDelay = 0,
    })
    declinedCustomer:update(1, { x = 500, y = 500 })
    check("customer_decline_review", declinedCustomer:beginReview())
    check("customer_declines", declinedCustomer:resolve("declined")
        and declinedCustomer.decision == "declined")
    local blockedCustomer = context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 100, y = 0 } },
        speed = 100, arrivalDelay = 0,
    })
    blockedCustomer.state, blockedCustomer.visible = "entering", true
    blockedCustomer:update(0.25, { x = 0, y = 0 })
    check("blocked_customer_does_not_walk_in_place",
        blockedCustomer.x == 0 and not blockedCustomer:isMoving()
        and blockedCustomer.animationClock == 0)
    blockedCustomer:update(0.25, { x = 500, y = 500 })
    check("customer_walk_clock_tracks_real_movement",
        blockedCustomer.x > 0 and blockedCustomer:isMoving()
        and blockedCustomer.animationClock == 0.25)
    local walkingX, walkingY, walkingRotation = context.Technician.pose({
        status = "entering", animationClock = 0.1,
    })
    local serviceX, serviceY, serviceRotation = context.Technician.pose({
        status = "servicing", animationClock = 0.1,
    })
    check("technician_walk_and_service_poses_animate",
        walkingX == 0 and (walkingY ~= 0 or walkingRotation ~= 0)
        and (serviceX ~= 0 or serviceY ~= 0 or serviceRotation ~= 0))
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

    local calendarState = context.State.new()
    calendarState.money = 2000
    local calendarChanged, invoice = context.businessCalendar.update(calendarState,
        31 * context.config.businessCalendar.secondsPerDay)
    check("calendar_five_minute_days_and_month_rollover", calendarChanged and invoice
        and calendarState.calendar.year == 2026 and calendarState.calendar.month == 2
        and calendarState.calendar.day == 1 and calendarState.calendar.totalDays == 31
        and context.businessCalendar.weekNumber(calendarState) == 5
        and context.businessCalendar.daysInMonth(2028, 2) == 29)
    check("calendar_posts_flat_monthly_bills", invoice.total == 1650
        and invoice.charges[1].amount == 1200 and invoice.charges[2].amount == 240
        and invoice.charges[3].amount == 85 and invoice.charges[4].amount == 125
        and calendarState.bills.balance == 1650)
    local paidBills, paidAmount = context.businessCalendar.pay(calendarState)
    check("calendar_monthly_bills_require_payment", paidBills and paidAmount == 1650
        and calendarState.money == 350 and calendarState.bills.balance == 0
        and calendarState.bills.ledger[1].status == "paid")
    local calendarEvents = context.businessCalendar.events(calendarState)
    check("calendar_automatically_lists_bill_due_dates", calendarEvents[1]
        and calendarEvents[1].title == "Rent and bills due")

    local weekendState = context.State.new()
    context.businessCalendar.update(weekendState,
        2 * context.config.businessCalendar.secondsPerDay)
    local weekendVisitor = context.Customer.new({
        route = { { x = 0, y = 0 }, { x = 10, y = 0 } }, arrivalDelay = 0,
    })
    weekendVisitor:update(30, { x = 500, y = 500 },
        context.businessCalendar.isWeekend(weekendState))
    check("weekend_pauses_client_and_salesman_arrivals",
        context.businessCalendar.isWeekend(weekendState)
        and weekendState.calendar.weekday == 6
        and weekendVisitor.state == "scheduled" and weekendVisitor.timer == 0)
    context.businessCalendar.update(weekendState,
        2 * context.config.businessCalendar.secondsPerDay)
    weekendVisitor:update(0.1, { x = 500, y = 500 },
        context.businessCalendar.isWeekend(weekendState))
    check("monday_resumes_visitor_arrivals", not context.businessCalendar.isWeekend(weekendState)
        and weekendState.calendar.weekday == 1 and weekendVisitor.visible)

    local emailState = context.State.new()
    local priorClientJob = context.jobs.createOffer({
        id = "PRIOR-CLIENT-JOB", company = "Returning Client Co.",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 }, packaging = "flat",
    })
    check("email_requires_completed_client_relationship",
        not context.jobService.scheduleRepeatEmail(emailState, priorClientJob))
    context.jobs.accept(priorClientJob)
    priorClientJob.status = "completed"
    check("completed_client_schedules_followup_email",
        context.jobService.scheduleRepeatEmail(emailState, priorClientJob)
        and #emailState.clientEmails.pending == 1 and #emailState.clientEmails.inbox == 0)
    context.businessCalendar.update(emailState,
        47 / 24 * context.config.businessCalendar.secondsPerDay)
    check("repeat_client_email_observes_delay", not context.jobService.updateClientEmails(emailState)
        and #emailState.clientEmails.inbox == 0)
    context.businessCalendar.update(emailState,
        1 / 24 * context.config.businessCalendar.secondsPerDay + 0.01)
    check("repeat_client_email_arrives", context.jobService.updateClientEmails(emailState)
        and #emailState.clientEmails.pending == 0 and #emailState.clientEmails.inbox == 1
        and emailState.clientEmails.inbox[1].sender == "Returning Client Co."
        and emailState.clientEmails.inbox[1].job.requestChannel == "email")
    local normalSequenceBeforeEmail = emailState.nextJobId
    context.computerScreen.enter(emailState)
    local emailTabX, emailTabY = context.computerScreen.tabCenter("email")
    context.computerScreen.mousepressed(emailState, emailTabX, emailTabY, 1)
    local emailAcceptX, emailAcceptY = context.computerScreen.emailButtonCenter("accept")
    local emailAccepted = context.computerScreen.mousepressed(emailState, emailAcceptX, emailAcceptY, 1)
    check("computer_accepts_repeat_client_email", emailAccepted
        and emailAccepted.action == "quote_accepted" and #emailState.jobs.active == 1
        and emailState.jobs.active[1].company == "Returning Client Co."
        and emailState.jobs.active[1].delivery.status == "pending_arrival"
        and emailState.nextJobId == normalSequenceBeforeEmail
        and #emailState.clientEmails.archive == 1)
    priorClientJob.status = "completed"
    check("second_completed_job_schedules_email",
        context.jobService.scheduleRepeatEmail(emailState, priorClientJob))
    context.businessCalendar.update(emailState,
        3 * context.config.businessCalendar.secondsPerDay + 0.01)
    context.jobService.updateClientEmails(emailState)
    context.computerScreen.enter(emailState)
    context.computerScreen.mousepressed(emailState, emailTabX, emailTabY, 1)
    local emailDeclineX, emailDeclineY = context.computerScreen.emailButtonCenter("decline")
    local emailDeclined = context.computerScreen.mousepressed(emailState, emailDeclineX, emailDeclineY, 1)
    check("computer_declines_repeat_client_email", emailDeclined
        and emailDeclined.action == "email_declined" and #emailState.jobs.declined == 1
        and emailState.jobs.declined[1].requestChannel == "email"
        and emailState.nextJobId == normalSequenceBeforeEmail
        and #emailState.clientEmails.archive == 2)
    local quoteProbe = context.jobService.createNextOffer(emailState, os.time())
    local baseTerms = context.jobService.quoteTerms(emailState, quoteProbe, quoteProbe.quote.totalPrice)
    local highTerms = context.jobService.quoteTerms(emailState, quoteProbe,
        math.floor(quoteProbe.quote.totalPrice * 1.30))
    check("client_quote_probability_uses_price_urgency_and_relationship",
        baseTerms.acceptanceChance == 1
        and highTerms.acceptanceChance < baseTerms.acceptanceChance
        and type(highTerms.urgency) == "string"
        and type(highTerms.relationshipJobs) == "number")
    priorClientJob.status = "completed"
    local promotionSent, promotion = context.jobService.sendPromotion(
        emailState, priorClientJob, "We appreciated your last project.")
    check("player_can_send_personalized_ten_percent_promotion", promotionSent
        and promotion.discountPercent == 10
        and promotion.customMessage == "We appreciated your last project."
        and #emailState.clientEmails.sentPromotions == 1)
    emailState.money = 10000
    local productOrdered, productOrder = context.procurement.buyRetail(emailState, 1, 1)
    local machineOrdered, machineOrder = context.machineFleet.orderOnline(emailState, 1)
    local scheduledEvents = context.businessCalendar.events(emailState)
    local eventIds = {}
    for _, event in ipairs(scheduledEvents) do eventIds[event.id] = true end
    local productShipment = context.procurement.orderById(emailState, productOrder.shipmentId)
    local productEventDay = math.floor(productShipment.delivery.expectedAtHours / 24)
    check("calendar_auto_adds_jobs_products_emails_and_machine_arrivals",
        productOrdered and machineOrdered
        and eventIds[productShipment.id .. ":expected:" .. tostring(productEventDay)]
        and eventIds[machineOrder.id .. ":expected:" .. tostring(emailState.calendar.totalDays)]
        and #scheduledEvents >= 4)

    local artStateA, artStateB = context.State.new(), context.State.new()
    artStateA.jobs.artworkSeed, artStateB.jobs.artworkSeed = 101, 90901
    local differentArt = false
    for sequence = 1, 12 do
        artStateA.nextJobId, artStateB.nextJobId = sequence, sequence
        local offerA = context.jobService.createNextOffer(artStateA, sequence)
        local offerB = context.jobService.createNextOffer(artStateB, sequence)
        if offerA.artworkKey ~= offerB.artworkKey then differentArt = true; break end
    end
    check("artwork_order_changes_with_each_playthrough_seed", differentArt)

    local function verifyVendorInventory()
        local vendorState = context.State.new()
        local starterCartons = vendorState.inventory.stock.shipping_cartons or 0
    local pressSupplyState = context.State.new()
    pressSupplyState.money = 500
    local pressSupplyBought, pressSupplyOrder = context.procurement.buy(pressSupplyState, 2, 1)
    check("vendor_sells_real_cost_press_supplies_for_windmill", pressSupplyBought
        and pressSupplyOrder.item == "black_ink" and pressSupplyOrder.price == 168
        and pressSupplyOrder.pallets[1].quantity == 140)
    vendorState.money = 500
    local bought, purchaseOrder = context.procurement.buy(vendorState, 3, 1)
    check("vendor_catalog_purchase", bought and purchaseOrder.id == "PO-0001"
        and purchaseOrder.pallets[1].category == "packaging"
        and vendorState.money == 428)
    local retailState = context.State.new()
    retailState.money = 500
    local retailBought, retailOrder = context.procurement.buyRetail(retailState, 3, 1)
    check("computer_retail_matches_vendor_product", retailBought
        and retailOrder.item == purchaseOrder.item
        and retailOrder.channel == "computer"
        and retailOrder.pallets[1].quantity == 20
        and retailOrder.price == 20
        and retailOrder.price / retailOrder.pallets[1].quantity
            > purchaseOrder.price / purchaseOrder.pallets[1].quantity)
    local groupedState = context.State.new()
    groupedState.money = 1000
    local groupBuyA, groupOrderA = context.procurement.buyRetail(groupedState, 1, 1)
    local groupBuyB, groupOrderB = context.procurement.buyRetail(groupedState, 2, 4)
    local groupedBeforeDue = context.procurement.nextInbound(groupedState)
    context.businessCalendar.update(groupedState,
        context.config.businessCalendar.secondsPerDay * (4 / 24) + 0.1)
    local groupedShipment = context.procurement.nextInbound(groupedState)
    local _, groupedInventory = context.procurement.truckInventory(
        groupedState, groupedShipment and groupedShipment.id)
    check("close_supply_orders_wait_and_share_one_truck",
        groupBuyA and groupBuyB and groupOrderA.shipmentId == groupOrderB.shipmentId
        and groupedBeforeDue == nil and groupedShipment
        and groupedShipment.id == groupOrderA.shipmentId and #groupedInventory == 2)
    local vendorManifest, vendorItems = context.procurement.truckInventory(vendorState, purchaseOrder.id)
    check("vendor_delivery_manifest", vendorManifest == purchaseOrder and #vendorItems == 1
        and vendorItems[1].productName == "Shipping cartons, 100")
    local unloaded, productPallet, vendorRemaining = context.procurement.unload(vendorState,
        purchaseOrder.id, purchaseOrder.pallets[1].id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
    check("vendor_product_unloads_to_pallet", unloaded and vendorRemaining == 0
        and productPallet.location == "warehouse"
        and vendorState.inventory.stock.shipping_cartons == starterCartons + 100)
    vendorState.palletJack.x, vendorState.palletJack.y = productPallet.world.x, productPallet.world.y
    check("vendor_pallet_jack_mount", context.PalletJack.use(vendorState, context.config.palletJack, function() return true end))
    local vendorLifted, vendorAction = context.PalletJack.use(vendorState, context.config.palletJack, function() return true end)
    check("vendor_product_pallet_lifts", vendorLifted and vendorAction == "lifted"
        and productPallet.location == "on_pallet_jack")
    context.PalletJack.move(vendorState, 1, 0, 0.1, context.config.palletJack, function() return true end)
    local vendorLowered, vendorLowerAction = context.PalletJack.use(vendorState, context.config.palletJack, function() return true end)
    check("vendor_product_pallet_lowers_with_direction", vendorLowered and vendorLowerAction == "lowered"
        and productPallet.world.direction == "east"
        and productPallet.world.rotation == 2)

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
        and vendorState.inventory.stock.shipping_cartons == starterCartons + 99
        and vendorState.inventory.plasticWrapRolls == 13
        and vendorState.inventory.plasticWrapUses == 10)
    local visibleStock = context.procurement.inventoryRows(vendorState)
    check("vendor_supplies_visible_in_office_inventory", visibleStock[3].id == "shipping_cartons"
        and visibleStock[3].quantity == starterCartons + 99
        and visibleStock[4].id == "stretch_film"
        and visibleStock[4].quantity == 13)
    context.wrapper.reset(vendorState)

    local noCartonState = context.State.new()
    noCartonState.inventory.stock.shipping_cartons = 0
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
        context.machine.setGauge(context.machine.paper.cuts[cutNumber].gauge, paperSupplyState)
        context.machine.saveGauge(paperSupplyState)
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
        and #serviceOffer.pallets == 2
        and serviceOffer.deliveryService.id == "express"
        and serviceOffer.deliveryService.delayHours >= 2
        and serviceOffer.deliveryService.delayHours <= 6)
    local acceptX, acceptY = context.jobOfferScreen.buttonCenter("accept")
    local declineX, declineY = context.jobOfferScreen.buttonCenter("decline")
    check("paperwork_accept_hit_target", context.jobOfferScreen.hitTest(acceptX, acceptY) == "accept")
    check("paperwork_decline_hit_target", context.jobOfferScreen.hitTest(declineX, declineY) == "decline")
    check("paperwork_ignores_outside_click", context.jobOfferScreen.hitTest(10, 10) == nil)
    local cashBeforeOffer = serviceState.money
    check("paperwork_service_accept", context.jobService.acceptOffer(serviceState, serviceOffer, 222))
    check("paperwork_accept_records_job", #serviceState.jobs.active == 1
        and serviceState.jobs.active[1].status == "awaiting_delivery"
        and serviceState.jobs.active[1].delivery.status == "pending_arrival"
        and not context.jobService.deliveryReady(serviceState, serviceOffer)
        and serviceState.accountsReceivable == 600
        and serviceState.money == cashBeforeOffer
        and serviceState.nextJobId == 2)
    check("paperwork_cannot_accept_twice", not context.jobService.acceptOffer(serviceState, serviceOffer, 333)
        and #serviceState.jobs.active == 1
        and serviceState.accountsReceivable == 600)
    local serviceDecline = context.jobService.createNextOffer(serviceState, 444)
    local standardState = context.State.new()
    standardState.nextJobId = 3
    local standardOffer = context.jobService.createNextOffer(standardState, 445)
    check("job_delivery_service_timeframes", serviceDecline.deliveryService.id == "quick"
        and serviceDecline.deliveryService.delayHours == 24
        and standardOffer.deliveryService.id == "standard"
        and (standardOffer.deliveryService.delayHours == 48
            or standardOffer.deliveryService.delayHours == 72))
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
    check("computer_job_packaging_instructions", context.computerScreen.packagingText(serviceOffer)
        == "Boxed paper on pallets; stretch-wrap each finished pallet"
        and context.computerScreen.packagingText({ packaging = "flat" })
            == "Flat stacked on pallets; stretch-wrap each finished pallet")
    local layoutPallets = {}
    for index = 1, 5 do layoutPallets[index] = { number = index } end
    local printDetailLayout = context.computerScreen.jobDetailLayout({
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
        pallets = layoutPallets,
    })
    check("computer_print_job_detail_text_clears_pallet_table",
        printDetailLayout.textBottom < printDetailLayout.tableY)
    check("computer_print_job_detail_table_clears_action_button",
        printDetailLayout.tableBottom + 4 <= printDetailLayout.actionTop,
        string.format("tableBottom=%.1f actionTop=%.1f",
            printDetailLayout.tableBottom, printDetailLayout.actionTop))
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
    check("computer_inventory_exposes_purchasable_stock", #officeInventory >= 10
        and officeInventory[1].id == "house_sheets"
        and officeInventory[3].id == "shipping_cartons"
        and officeInventory[4].id == "stretch_film"
        and officeInventory[5].id == "maintenance_kit"
        and officeInventory[6].id == "black_ink"
        and officeInventory[10].id == "raw_press_plates")
    local retailX, retailY = context.computerScreen.retailButtonCenter(1)
    local computerOrder = context.computerScreen.mousepressed(serviceState, retailX, retailY, 1)
    check("computer_supply_store_places_delivery_order", computerOrder
        and computerOrder.action == "supply_order"
        and computerOrder.order.channel == "computer"
        and computerOrder.order.pallets[1].quantity == 250)
    local closeX, closeY = context.computerScreen.closeCenter()
    check("computer_close_hit_target", context.computerScreen.mousepressed(
        serviceState, closeX, closeY, 1).action == "close")
    check("computer_ignores_outside_click", context.computerScreen.mousepressed(
        serviceState, 10, 10, 1) == nil)
    local billUiState = context.State.new()
    billUiState.money = 2000
    context.businessCalendar.update(billUiState, 31 * context.config.businessCalendar.secondsPerDay)
    context.computerScreen.enter(billUiState)
    local billsTabX, billsTabY = context.computerScreen.tabCenter("bills")
    local billsTabResult = context.computerScreen.mousepressed(billUiState, billsTabX, billsTabY, 1)
    local payBillsX, payBillsY = context.computerScreen.payBillsCenter()
    local billPayment = context.computerScreen.mousepressed(billUiState, payBillsX, payBillsY, 1)
    check("computer_bills_tab_pays_monthly_expenses", billsTabResult and billsTabResult.tab == "bills"
        and billPayment and billPayment.action == "bill_paid" and billPayment.amount == 1650
        and billUiState.money == 350 and billUiState.bills.balance == 0)

    local calendarUiState = context.State.new()
    calendarUiState.clientEmails.pending = {}
    for index = 1, 12 do
        calendarUiState.clientEmails.pending[index] = {
            id = "CAL-EMAIL-" .. index, sender = "Client " .. index, subject = "Scheduled request",
            readyAtHours = (index - 1) * 24,
        }
    end
    context.computerScreen.enter(calendarUiState)
    local calendarTabX, calendarTabY = context.computerScreen.tabCenter("calendar")
    context.computerScreen.mousepressed(calendarUiState, calendarTabX, calendarTabY, 1)
    local calendarDayX, calendarDayY = context.computerScreen.calendarDayCenter(5)
    local selectedCalendarDay = context.computerScreen.mousepressed(
        calendarUiState, calendarDayX, calendarDayY, 1)
    check("computer_calendar_days_are_clickable", selectedCalendarDay
        and selectedCalendarDay.action == "calendar_day" and selectedCalendarDay.day == 5
        and context.computerScreen.calendarSelectedDay == 5)
    context.computerScreen.calendarScroll = 0
    check("computer_calendar_event_list_mouse_wheel_scrolls",
        context.computerScreen.wheelmoved(calendarUiState, 0, -1)
        and context.computerScreen.calendarScroll == 1)
    local calendarDownX, calendarDownY = context.computerScreen.calendarScrollCenter("down")
    local calendarScrollResult = context.computerScreen.mousepressed(
        calendarUiState, calendarDownX, calendarDownY, 1)
    check("computer_calendar_event_list_buttons_scroll", calendarScrollResult
        and calendarScrollResult.action == "calendar_scroll"
        and context.computerScreen.calendarScroll == 2)

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
        local maintenancePreview = os.getenv("PICTURE_SHOP_CUTTER_MAINTENANCE_PREVIEW")
        local wrapperMaintenancePreview = os.getenv("PICTURE_SHOP_WRAPPER_MAINTENANCE_PREVIEW")
        local previewTab = os.getenv("PICTURE_SHOP_COMPUTER_ACTIVE_PREVIEW") == "1" and "active"
            or (os.getenv("PICTURE_SHOP_COMPUTER_CALENDAR_PREVIEW") == "1" and "calendar")
            or (os.getenv("PICTURE_SHOP_COMPUTER_INVENTORY_PREVIEW") == "1" and "inventory")
            or (os.getenv("PICTURE_SHOP_COMPUTER_EMAIL_PREVIEW") == "1" and "email")
        local pressPreview = os.getenv("PICTURE_SHOP_PRESS_PREVIEW")
        if os.getenv("PICTURE_SHOP_WORK_ORDER_PREVIEW") == "1" then
            local previewJob = assert(context.jobs.createOffer({
                id = "JOB-0042", company = "Blue Ridge Packaging",
                sourceSize = { width = 25, height = 19 },
                finishedSize = { width = 12.5, height = 9.5 },
                sheetCounts = { 1000 }, packaging = "boxed", difficulty = "medium",
                artworkKey = "ad-pizza",
                artwork = { key = "ad-pizza", displayName = "Blue Ridge Pizza Card",
                    fileName = "blue-ridge-pizza-final.png", suppliedBy = "client" },
                stockSpec = { suppliedBy = "client", grade = "cover", weight = 80,
                    finish = "uncoated", color = "warm white", grain = "long",
                    description = "80 lb customer-supplied cover stock" },
                details = { stockDescription = "80 lb customer-supplied cover stock" },
            }))
            previewJob.status = "in_production"
            previewJob.delivery = previewJob.delivery or {}
            previewJob.delivery.status = "received"
            local pallet = previewJob.pallets[1]
            pallet.location, pallet.status = "warehouse", "raw"
            context.state.jobs.active = { previewJob }
            context.palletWorkOrderScreen.enter({ job = previewJob, pallet = pallet })
            context.state.screen = "pallet_work_order"
        elseif maintenancePreview == "hub" or maintenancePreview == "oil" then
            context.state.screen = "machine"
            context.state.machineType = "cutter"
            context.state.inventory.stock.maintenance_kit = 2
            context.machineScreen.enter()
            local x, y = context.machineScreen.maintenanceCenter()
            context.machineScreen.mousepressed(context.state, x, y, 1)
            if maintenancePreview == "oil" then
                x, y = context.machineScreen.maintenanceTaskCenter("oil")
                context.machineScreen.mousepressed(context.state, x, y, 1)
                for _, action in ipairs({ "disconnect", "key", "tag" }) do
                    x, y = context.machineScreen.lubricationLockoutCenter(action)
                    context.machineScreen.mousepressed(context.state, x, y, 1)
                end
                for _, action in ipairs({ "cartridge", "prime" }) do
                    x, y = context.machineScreen.lubricationPrepCenter(action)
                    context.machineScreen.mousepressed(context.state, x, y, 1)
                end
                x, y = context.machineScreen.lubricationPointCenter("backgauge_left")
                context.machineScreen.mousepressed(context.state, x, y, 1)
                local tx, ty = context.machineScreen.lubricationToolCenter("grease")
                context.machineScreen.mousepressed(context.state, tx, ty, 1)
                context.machineScreen.mousepressed(context.state, x, y, 1)
                tx, ty = context.machineScreen.lubricationPumpCenter()
                context.machineScreen.mousepressed(context.state, tx, ty, 1)
                context.machineScreen.update(0.35)
            end
        elseif wrapperMaintenancePreview == "hub" or wrapperMaintenancePreview == "task" then
            context.state.screen = "machine"
            context.state.machineType = "skid_wrapper"
            context.state.inventory.stock.maintenance_kit = 2
            context.machineScreen.enter()
            local x, y = context.machineScreen.wrapperMaintenanceCenter()
            context.machineScreen.mousepressed(context.state, x, y, 1)
            if wrapperMaintenancePreview == "task" then
                x, y = context.machineScreen.wrapperServiceCenter()
                context.machineScreen.mousepressed(context.state, x, y, 1)
                context.machineScreen.update(0.35)
            end
        elseif pressPreview == "world" then
            context.state.money = 20000
            assert(context.machineFleet.buy(context.state, "dealer", 3))
            context.state.screen = "world"
        elseif pressPreview == "run" or pressPreview == "plates" or pressPreview == "proof"
            or pressPreview == "finished" or (pressPreview and pressPreview:match("^setup_"))
            or pressPreview == "drying"
            or pressPreview == "help"
        then
            local previewJob = assert(context.jobs.createOffer({
                id = "PRESS-PREVIEW", company = "Harbor Pizza Club",
                sourceSize = { width = 10, height = 15 }, finishedSize = { width = 6, height = 9 },
                sheetCounts = { 1050 }, packaging = "flat", difficulty = "medium",
                artworkKey = "ad-pizza",
                artwork = { key = "ad-pizza", displayName = "Harbor Pizza Night Poster",
                    fileName = "harbor-pizza-night-final.png", suppliedBy = "client", orientation = "portrait" },
                stockSpec = { suppliedBy = "client", grade = "cover", weight = 80,
                    finish = "uncoated", color = "warm white", grain = "long",
                    description = "80 lb warm-white uncoated cover" },
                press = { colors = 2, coverage = 0.44, artworkSize = { width = 5.4, height = 8.2 },
                    colorSequence = { "Tomato Red", "Black" }, requestedCopies = { 1000 } },
                details = { stockDescription = "80 lb warm-white uncoated cover" },
            }))
            previewJob.status = "in_production"
            local pallet = previewJob.pallets[1]
            pallet.paper.status, pallet.remainingSheets, pallet.finishedSheets = "complete", 0, 1050
            pallet.location, pallet.status = "at_press", "press_setup"
            pallet.press.status, pallet.press.availableSheets = "proof", 1050
            context.state.jobs.active = { previewJob }
            local plates = context.plateService.ensureJob(previewJob)
            for _, plate in ipairs(plates) do
                plate.status, plate.source, plate.quality, plate.mounted = "ready", "in_house", 0.94, true
            end
            local process = context.windmill.ensure(context.state)
            process.jobId, process.palletId, process.colorIndex = previewJob.id, pallet.id, 1
            process.status, process.speed = pressPreview == "run" and "production"
                or pressPreview == "finished" and "pass_complete"
                or (pressPreview and pressPreview:match("^setup_")) and "setup" or "proof", 3000
            process.setup = { chase = 0.91, packing = 0.88, rollers = 0.93,
                ink = 0.86, feeder = 0.92, register = 0.84 }
            process.proofQuality, process.proofApproved, process.artworkVerified = 0.87, false, false
            process.targetSheets, process.feedStart, process.feedRemaining = 1025, 1050, 1049
            process.counter, process.goodSheets, process.spoilage = 1, 0, 1
            process.motor, process.feeder, process.impression = true, true, true
            if pressPreview == "drying" then
                pallet.location, pallet.status = "press_output", "press_setup"
                pallet.press.status, pallet.press.completedColors = "drying", 1
                pallet.press.availableSheets, pallet.press.goodSheets = 1025, 1025
                pallet.press.dryUntilHours = context.businessCalendar.absoluteHours(context.state) + 1
                process.status, process.jobId, process.palletId, process.colorIndex = "idle", nil, nil, nil
                process.setup, process.motor, process.feeder, process.impression = {}, false, false, false
            end
            context.state.screen = "press"
            context.pressScreen.enter(context.state)
            local setupTask = pressPreview and pressPreview:match("^setup_(.+)$")
            context.pressScreen.tab = pressPreview == "drying" and "run"
                or pressPreview == "finished" and "run"
                or setupTask and "setup" or pressPreview
            if setupTask then assert(context.pressScreen.beginSetup(context.state, setupTask)) end
            if pressPreview == "help" then
                context.pressScreen.tutorialStep = math.max(1, math.min(15,
                    tonumber(os.getenv("PICTURE_SHOP_PRESS_HELP_PAGE")) or 4))
            end
        elseif previewTab then
            context.state.screen = "computer"
            context.computerScreen.enter(context.state)
            local x, y = context.computerScreen.tabCenter(previewTab)
            context.computerScreen.mousepressed(context.state, x, y, 1)
        elseif os.getenv("PICTURE_SHOP_WORLD_FAN_PREVIEW") == "1" then
            context.state.screen = "world"
        end
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
        writeLine(Smoke.spriteLabRequested() and "SMOKE_OK_SPRITE_LAB" or "SMOKE_OK")
        Smoke.report:close()
        Smoke.report = nil
        print("SMOKE_OK: module checks and three draw frames completed")
        io.flush()
        if Smoke.spriteLabRequested() then
            Smoke.active = false
        else
            love.event.quit(0)
        end
    end
end

return Smoke
