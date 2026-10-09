-- Game integration checks with the original assertions and shared scenario state.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.healthy, Context.failures = Context.context.assets.assertHealthy()
    Context.check("asset_contract", Context.healthy, Context.failures)
    Context.check("startup_texture_memory_below_100_mib",
        Context.context.startupTextureBytes < 100 * 1024 * 1024,
        string.format("%.2f MiB", Context.context.startupTextureBytes / 1024 / 1024))
    Context.check("screen_packs_start_unloaded", Context.context.assets.activePackName() == nil
        and Context.context.assets.get("polarOperatorConsole") == nil
        and Context.context.assets.get("wrappedPalletStages") ~= nil)
    Context.check("shared_back_button_stays_loaded", Context.context.assets.get("polarBackButton") ~= nil)
    Context.dimensionsValid, Context.dimensionError = Context.context.assets.dimensionDiagnostic(
        "assets/generated/test-malformed-atlas.png", 1251, 1252, 1252, 1252)
    Context.startupDiagnostics = Context.context.assetErrorScreen.normalize(
        "assets/generated/test-missing.png: missing required asset", Context.dimensionError)
    Context.check("asset_diagnostic_names_missing_path", not Context.dimensionsValid
        and Context.startupDiagnostics[1]:find("assets/generated/test-missing.png", 1, true)
        and Context.startupDiagnostics[2]:find("assets/generated/test-malformed-atlas.png", 1, true))
    Context.check("asset_diagnostic_explains_malformed_dimensions",
        Context.startupDiagnostics[2]:find("expected 1252x1252, got 1251x1252", 1, true))
    Context.check("skid_wrapper_loaded", Context.context.assets.get("skidWrapperDirections") ~= nil)
    for frame = 1, Context.context.config.wrapperPlacement.frameCount do
        Context.check("skid_wrapper_direction_" .. frame, Context.context.assets.getQuad("skidWrapperDirection" .. frame) ~= nil)
    end
    Context.check("wall_vent_fan_three_frame_asset", Context.context.assets.get("wallVentFan") ~= nil
        and Context.context.assets.getQuad("wallVentFan1") ~= nil
        and Context.context.assets.getQuad("wallVentFan2") ~= nil
        and Context.context.assets.getQuad("wallVentFan3") ~= nil)
    Context.check("lounge_seating_foregrounds_loaded",
        Context.context.assets.get("loungeLeftChairForeground") ~= nil
        and Context.context.assets.get("loungeCoffeeTableForeground") ~= nil
        and Context.context.assets.get("loungeRightChairForeground") ~= nil)
    Context.check("lounge_has_three_registered_seat_positions",
        #Context.context.config.customer.seatSpots == 3
        and Context.context.config.customer.seatSpots[1].name == "sofa-left"
        and Context.context.config.customer.seatSpots[2].name == "sofa-right"
        and Context.context.config.customer.seatSpots[3].name == "right-chair")
    Context.check("wall_vent_fan_is_thirty_five_percent_larger",
        math.abs(Context.context.config.wallVentFan.drawScale - 0.405) < 0.0001)
    Context.check("pallet_jack_twenty_percent_smaller_without_shrinking_loose_pallets",
        math.abs(Context.context.config.palletJack.drawScale - 0.416) < 0.0001
        and math.abs(Context.context.config.palletJack.drawScale
            * Context.context.config.palletJack.carriedPalletArtRatio
            - Context.context.config.palletLogistics.drawScale) < 0.0001)
    Context.singleFrameClient = Context.context.Customer.new(Context.context.config.customer)
    Context.singleFrameClient.animationClock = 123.45
    Context.check("seated_clients_draw_exactly_one_atlas_frame",
        Context.singleFrameClient:frameForAction("sit", 2) == 1
        and Context.singleFrameClient:frameForAction("idle", 2) == 1)
    Context.singleFrameClient.animationClock = 0.5
    Context.check("explicit_use_action_animates",
        Context.singleFrameClient:frameForAction("use", 3) == 2)
    Context.check("character_action_lookup_matches_promoted_pack",
        Context.context.characterAssets.hasAction("green-blazer-cat", "use")
        and not Context.context.characterAssets.hasAction("tan-cat", "use"))
    Context.wrapperState = Context.context.State.new()
    Context.wrapperState.inventory.stock.shipping_cartons = 1
    Context.wrapperState.jobs.active = { { id = "WRAP-TEST", packaging = "boxed", pallets = { {
        id = "WRAP-TEST-P01", number = 1, status = "cut", location = "cutter_output",
        packaging = "boxed", wrapped = false, world = { x = Context.wrapperState.wrapper.x - 60, y = Context.wrapperState.wrapper.y, spawnProgress = 1 },
    } } } }
    Context.context.wrapper.reset(Context.wrapperState)
    Context.check("skid_wrapper_requires_nearby_pallet", Context.context.wrapper.nearbyPallet(Context.wrapperState) ~= nil)
    Context.check("skid_wrapper_cycle", Context.context.wrapper.keypressed("l", Context.wrapperState))
    Context.context.wrapper.update(Context.context.wrapper.cycleTime + 0.1, Context.wrapperState)
    Context.check("skid_wrapper_finished", Context.context.wrapper.step == "finished"
        and Context.wrapperState.jobs.active[1].pallets[1].status == "wrapped"
        and Context.wrapperState.inventory.plasticWrapUses == 10
        and Context.wrapperState.inventory.stock.shipping_cartons == 0)
    Context.printWrapperState = Context.context.State.new()
    Context.printWrapperPallet = {
        id = "WRAP-PRINT-P01", number = 1, status = "cut", location = "cutter_output",
        packaging = "flat", wrapped = false, press = { status = "awaiting_cut" },
        world = { x = Context.printWrapperState.wrapper.x - 60, y = Context.printWrapperState.wrapper.y,
            spawnProgress = 1 },
    }
    Context.printWrapperState.jobs.active = { {
        id = "WRAP-PRINT", packaging = "flat", press = { colors = 1 },
        pallets = { Context.printWrapperPallet },
    } }
    Context.context.wrapper.reset(Context.printWrapperState)
    Context.check("print_pallet_cannot_wrap_before_press_completion",
        Context.context.wrapper.nearbyPallet(Context.printWrapperState) == nil)
    Context.printWrapperPallet.press.status, Context.printWrapperPallet.status = "complete", "printed"
    Context.check("completed_print_pallet_can_enter_wrapper",
        Context.context.wrapper.nearbyPallet(Context.printWrapperState) ~= nil)
    Context.wrapperSelectionState = Context.context.State.new()
    Context.wrapperSelectionState.jobs.active = { { id = "WRAP-SELECT", packaging = "flat", pallets = {
        { id = "WRAP-SELECT-P01", number = 1, status = "cut", location = "warehouse",
            packaging = "flat", wrapped = false,
            world = { x = Context.wrapperSelectionState.wrapper.x - 72, y = Context.wrapperSelectionState.wrapper.y,
                spawnProgress = 1 } },
        { id = "WRAP-SELECT-P02", number = 2, status = "finished", location = "warehouse",
            packaging = "flat", wrapped = false,
            world = { x = Context.wrapperSelectionState.wrapper.x + 72, y = Context.wrapperSelectionState.wrapper.y,
                spawnProgress = 1 } },
    } } }
    Context.context.wrapper.reset(Context.wrapperSelectionState)
    Context.check("skid_wrapper_lists_all_nearby_pallets",
        #Context.context.wrapper.nearbyPallets(Context.wrapperSelectionState) == 2)
    Context.wrapperSelectionState.machineType = "skid_wrapper"
    Context.wrapperPalletX, Context.wrapperPalletY = Context.context.machineScreen.wrapperPalletCenter(2)
    Context.check("skid_wrapper_picker_selects_clicked_or_controller_cursor_pallet",
        Context.context.machineScreen.mousepressed(Context.wrapperSelectionState, Context.wrapperPalletX, Context.wrapperPalletY, 1)
        and Context.context.wrapper.start(Context.wrapperSelectionState)
        and Context.context.wrapper.pallet.id == "WRAP-SELECT-P02")
    Context.context.wrapper.update(Context.context.wrapper.cycleTime + 0.1, Context.wrapperSelectionState)
    Context.context.wrapper.reset(Context.wrapperSelectionState)
    Context.wrapperDirection = Context.wrapperState.wrapper.direction
    Context.wrapperState.palletJack.operating = true
    Context.wrapperState.palletJack.carriedPalletId = nil
    Context.wrapperState.palletJack.x, Context.wrapperState.palletJack.y = Context.wrapperState.wrapper.x, Context.wrapperState.wrapper.y
    Context.check("skid_wrapper_move_mode", Context.context.world.beginWrapperMove(Context.wrapperState))
    Context.check("skid_wrapper_rotate", Context.context.world.rotateWrapper(Context.wrapperState)
        and Context.wrapperState.wrapper.direction ~= Context.wrapperDirection)
    Context.check("skid_wrapper_place", Context.context.world.placeWrapper(Context.wrapperState)
        and Context.wrapperState.wrapper.moving == false)

    function Context.wrapperLifecycleState(id)
        local testState = Context.context.State.new()
        testState.screen = "machine"
        testState.machineType = "skid_wrapper"
        testState.inventory.stock.shipping_cartons = 1
        local pallet = {
            id = id, number = 1, status = "cut", location = "cutter_output",
            packaging = "boxed", wrapped = false,
            world = { x = testState.wrapper.x - 60, y = testState.wrapper.y, spawnProgress = 1 },
        }
        testState.jobs.active = { { id = id .. "-JOB", packaging = "boxed", pallets = { pallet } } }
        Context.context.wrapper.reset(testState)
        Context.check(id .. "_starts", Context.context.wrapper.start(testState))
        return testState, pallet
    end

    Context.exitSamples = {
        { name = "start", advance = 0 },
        { name = "middle", advance = Context.context.wrapper.cycleTime / 2 },
        { name = "final_frame", advance = Context.context.wrapper.cycleTime - 0.0001 },
    }
    for _, inputKind in ipairs({ "keyboard", "mouse" }) do
        for _, sample in ipairs(Context.exitSamples) do
            local name = "wrapper_" .. inputKind .. "_" .. sample.name
            local testState, pallet = Context.wrapperLifecycleState(name)
            if sample.advance > 0 then Context.context.wrapper.update(sample.advance, testState) end
            local progressBeforeExit = Context.context.wrapper.progress
            local saveCalls = 0
            local testInputContext = {}
            for key, value in pairs(Context.context.inputContext) do testInputContext[key] = value end
            testInputContext.state = testState
            testInputContext.saveCurrent = function() saveCalls = saveCalls + 1; return true end
            local handled
            if inputKind == "keyboard" then
                handled = Context.context.input.keypressed("escape", testInputContext)
            else
                local exitX, exitY = Context.context.machineScreen.exitCenter()
                handled = Context.context.input.mousepressed(exitX, exitY, 1, testInputContext)
            end
            Context.check(name .. "_exit_keeps_cycle_running",
                handled
                and testState.screen == "world"
                and Context.context.wrapper.step == "wrapping"
                and Context.context.wrapper.progress == progressBeforeExit
                and testState.inventory.plasticWrapUses == 11
                and not pallet.wrapped
                and saveCalls == 1)

            Context.context.wrapper.update(Context.context.wrapper.cycleTime, testState)
            Context.context.wrapper.update(1, testState)
            Context.check(name .. "_finishes_once",
                testState.screen == "world"
                and Context.context.wrapper.step == "finished"
                and pallet.wrapped
                and pallet.status == "wrapped"
                and testState.inventory.plasticWrapUses == 10
                and saveCalls == 1)
        end
    end

    Context.relocationState, Context.relocationPallet = Context.wrapperLifecycleState("wrapper_interruption_guards")
    Context.context.wrapper.update(Context.context.wrapper.cycleTime / 2, Context.relocationState)
    Context.relocationContext = {}
    for key, value in pairs(Context.context.inputContext) do Context.relocationContext[key] = value end
    Context.relocationContext.state = Context.relocationState
end

return Component
