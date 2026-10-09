-- Game integration checks with the original assertions and shared scenario state.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.relocationContext.saveCurrent = function() error("blocked relocation must not save") end
    Context.check("skid_wrapper_reset_blocked_while_wrapping",
        not Context.context.wrapper.keypressed("r", Context.relocationState)
        and Context.context.wrapper.step == "wrapping"
        and not Context.relocationPallet.wrapped)
    Context.check("skid_wrapper_direct_relocation_blocked_while_wrapping",
        not Context.context.world.beginWrapperMove(Context.relocationState)
        and not Context.relocationState.wrapper.moving)
    Context.check("skid_wrapper_console_relocation_blocked_while_wrapping",
        Context.context.input.keypressed("m", Context.relocationContext)
        and Context.relocationState.screen == "machine"
        and not Context.relocationState.wrapper.moving)
    Context.context.wrapper.update(Context.context.wrapper.cycleTime, Context.relocationState)
    Context.check("skid_wrapper_interruption_guards_preserve_single_use",
        Context.relocationPallet.wrapped and Context.relocationState.inventory.plasticWrapUses == 10)
    Context.context.wrapper.reset(Context.relocationState)
    Context.expectedCharacters = {
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
    for _, character in ipairs({ "tan-cat", "green-blazer-cat", "blue-coaler-cat", "business-dragon", "business-fox" }) do
        for _, direction in ipairs({ "", "_north", "_northeast", "_southeast", "_south" }) do
            Context.expectedCharacters[character]["walk" .. direction] = 8
            Context.expectedCharacters[character]["idle" .. direction] = 2
        end
    end
    Context.charactersHealthy, Context.characterFailures = Context.context.characterAssets.assertHealthy()
    Context.check("character_asset_contract", Context.charactersHealthy, Context.characterFailures)
    Context.check("character_anchor_scans_eliminated", Context.context.characterAssets.anchorPixelScans() == 0)
    Context.check("character_packs_start_unloaded", Context.context.characterAssets.residentActionCount() == 0)
    for character, actions in pairs(Context.expectedCharacters) do
        Context.context.characterAssets.retainCharacters({ [character] = true })
        for action, count in pairs(actions) do
            local image, quad, actual = Context.context.characterAssets.get(character, action, 1)
            Context.check(character .. "_" .. action .. "_loaded", image ~= nil and quad ~= nil and actual == count)
            local maximumHeight, minimumHeight = 0, math.huge
            for frame = 1, count do
                local metrics = Context.context.characterAssets.normalizedFrameMetrics(character, action, frame)
                maximumHeight = math.max(maximumHeight, metrics and metrics.height or 0)
                minimumHeight = math.min(minimumHeight, metrics and metrics.height or math.huge)
            end
            local gait = action == "walk" or action:match("^walk_")
            -- Uniform loop scale keeps the authored weight-down / knee-up bob.
            -- Bound that bob to 6%; keep non-gait poses on the tighter contract.
            Context.check(character .. "_" .. action .. "_normalized_frame_height_stable",
                minimumHeight > 0 and maximumHeight / minimumHeight <= (gait and 1.06 or 1.03))
        end
        local idle = Context.context.characterAssets.normalizedFrameMetrics(character, "idle", 1)
        for action in pairs(actions) do
            local metrics = Context.context.characterAssets.normalizedFrameMetrics(character, action, 1)
            local gait = action == "walk" or action:match("^walk_")
            Context.check(character .. "_" .. action .. "_matches_character_scale",
                idle and metrics and math.abs(metrics.height - idle.height) / idle.height <= (gait and .06 or .03))
            Context.check(character .. "_" .. action .. "_matches_player_world_height",
                metrics and math.abs(
                    metrics.height * Context.context.config.customer.drawScale
                    - Context.context.config.characterRendering.referenceHeight
                        * Context.context.config.player.drawScale) <= (gait and 4 or 1))
        end
    end
    Context.check("business_seated_art_receives_source_scale_correction",
        math.abs(Context.context.characterAssets.getNormalization("business-dragon", "sit") - 256 / 192) < .01)
    Context.check("character_actions_load_on_demand", Context.context.characterAssets.residentActionCount() > 0)
    Context.context.characterAssets.retainCharacters({ ["business-dragon"] = true })
    for action in pairs(Context.expectedCharacters["business-dragon"]) do
        Context.context.characterAssets.get("business-dragon", action, 1)
    end
    Context.check("inactive_character_packs_release",
        Context.context.characterAssets.residentActionCount() == 11)
    Context.context.characterAssets.retainCharacters({})
    Context.check("all_character_packs_release", Context.context.characterAssets.residentActionCount() == 0
        and Context.context.characterAssets.textureBytes() == 0)

    Context.background = Context.context.assets.get("warehouse")
    Context.mask = Context.context.assets.getData("walkmask")
    Context.loadingBayDoor = Context.context.assets.get("loadingBayDoor")
    Context.deliveryTruck = Context.context.assets.get("deliveryTruck")
    Context.truckCargoDoor = Context.context.assets.get("truckCargoDoor")
    Context.machineFlatbedLoaded = Context.context.assets.get("machineFlatbedLoaded")
    Context.machineFlatbedEmpty = Context.context.assets.get("machineFlatbedEmpty")
    Context.check("warehouse_loaded", Context.background ~= nil)
    Context.check("walkmask_cpu_copy_loaded", Context.mask ~= nil)
    Context.check("walkmask_gpu_texture_omitted", Context.context.assets.get("walkmask") == nil)
    Context.check("loading_bay_door_asset_loaded", Context.loadingBayDoor ~= nil)
    Context.check("delivery_truck_asset_loaded", Context.deliveryTruck ~= nil)
    Context.check("truck_cargo_door_asset_loaded", Context.truckCargoDoor ~= nil)
    Context.check("machine_flatbed_loaded_asset_loaded", Context.machineFlatbedLoaded ~= nil)
    Context.check("machine_flatbed_empty_asset_loaded", Context.machineFlatbedEmpty ~= nil)
    Context.check("picture_press_excluded_from_runtime", Context.context.assets.get("picturePress") == nil
        and Context.context.config.paths.picturePress == nil)
    Context.check("polar_direction_strip_loaded", Context.context.assets.get("polarDirections") ~= nil)
    Context.check("loaded_paper_pallet_directions_loaded", Context.context.assets.get("loadedPaperPalletDirections") ~= nil)
    Context.check("pallet_jack_asset_loaded", Context.context.assets.get("palletJack") ~= nil)
    Context.check("loaded_pallet_jack_asset_loaded", Context.context.assets.get("palletJackLoaded") ~= nil)
    Context.check("vendor_product_pallet_atlas_loaded", Context.context.assets.get("vendorProductPallets") ~= nil)
    Context.check("boxed_paper_pallet_stages_loaded", Context.context.assets.get("boxedPaperPalletStages") ~= nil)
    for artworkKey in pairs(Context.context.config.paths.artwork or {}) do
        Context.check("artwork_" .. artworkKey .. "_loaded", Context.context.assets.getArtwork(artworkKey) ~= nil)
    end
    Context.artworkRegistry, Context.artworkOrderValid = {}, true
    for _, artworkKey in ipairs(Context.context.config.artworkOrder or {}) do
        if Context.artworkRegistry[artworkKey] or not Context.context.config.paths.artwork[artworkKey] then
            Context.artworkOrderValid = false
        end
        Context.artworkRegistry[artworkKey] = true
    end
    Context.artworkPathCount = 0
    for artworkKey in pairs(Context.context.config.paths.artwork or {}) do
        Context.artworkPathCount = Context.artworkPathCount + 1
        if not Context.artworkRegistry[artworkKey] then Context.artworkOrderValid = false end
    end
    Context.check("artwork_job_rotation_covers_full_registry", Context.artworkOrderValid
        and Context.artworkPathCount == #(Context.context.config.artworkOrder or {}))
    Context.artworkOfferState = Context.context.State.new()
    Context.artworkOfferState.reputation.score = 20
    Context.observedArtwork = {}
    for sequence = 1, math.max(12, #(Context.context.config.artworkOrder or {})) do
        Context.artworkOfferState.nextJobId = sequence
        local offer = Context.context.jobService.createNextOffer(Context.artworkOfferState, 1000 + sequence)
        if not offer or not Context.artworkRegistry[offer.artworkKey] then Context.artworkOrderValid = false; break end
        Context.observedArtwork[offer.artworkKey] = true
    end
    Context.observedCount = 0
    for _ in pairs(Context.observedArtwork) do Context.observedCount = Context.observedCount + 1 end
    Context.check("randomized_artwork_reaches_job_offers", Context.artworkOrderValid and Context.observedCount >= 4)
    for frame = 1, Context.context.config.loadingBay.frameCount do
        Context.check("loading_bay_door_frame_" .. frame,
            Context.context.assets.getQuad("loadingBayDoor" .. frame) ~= nil)
    end
    for frame = 1, Context.context.config.truck.cargoFrameCount do
        Context.check("truck_cargo_door_frame_" .. frame,
            Context.context.assets.getQuad("truckCargoDoor" .. frame) ~= nil)
    end
    for frame = 1, Context.context.config.cutterPlacement.frameCount do
        Context.check("polar_direction_frame_" .. frame,
            Context.context.assets.getQuad("polarDirection" .. frame) ~= nil)
    end
    for frame = 1, Context.context.config.palletJack.palletFrameCount do
        Context.check("loaded_pallet_direction_" .. frame, Context.context.assets.getQuad("loadedPaperPallet" .. frame) ~= nil)
        for row = 1, 4 do
            Context.check("vendor_product_pallet_" .. row .. "_direction_" .. frame,
                Context.context.assets.getQuad("vendorProductPallet" .. row .. "_" .. frame) ~= nil)
        end
    end
    for frame = 1, Context.context.config.palletJack.frameCount do
        Context.check("pallet_jack_direction_" .. frame, Context.context.assets.getQuad("palletJack" .. frame) ~= nil)
        Context.check("loaded_pallet_jack_direction_" .. frame, Context.context.assets.getQuad("palletJackLoaded" .. frame) ~= nil)
    end
    Context.wrappedImage, Context.wrappedSprite, Context.wrappedScale = Context.context.worldRenderer.palletVisual({
        vendor = false,
        pallet = { packaging = "flat", wrapped = true, direction = "northwest", rotation = 1 },
    })
    Context.check("wrapped_flat_pallet_uses_finished_sprite_without_overlay",
        Context.wrappedImage == "wrappedPalletStages"
        and Context.wrappedSprite == "wrappedPalletStage3"
        and math.abs(Context.wrappedScale - Context.context.config.palletLogistics.drawScale * 0.5) < 0.0001)
    for stage = 1, 5 do
        for frame = 1, 4 do
            Context.check("boxed_paper_pallet_stage_" .. stage .. "_direction_" .. frame,
                Context.context.assets.getQuad("boxedPaperPalletStage" .. stage .. "_" .. frame) ~= nil)
        end
    end
    Context.check("menu_pack_activates", Context.context.assets.activatePack("menu")
        and Context.context.assets.activePackName() == "menu"
        and Context.context.assets.get("polarOperatorConsole") ~= nil
        and Context.context.assets.get("cutterControlButtons") ~= nil
        and Context.context.assets.get("cutterClamp") == nil)
    Context.check("cutter_pack_replaces_menu_pack", Context.context.assets.activatePack("cutter")
        and Context.context.assets.activePackName() == "cutter")
    Context.check("polar_operator_console_loaded", Context.context.assets.get("polarOperatorConsole") ~= nil)
end

return Component
