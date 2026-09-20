local Test = {}
local Presentation = require("src.forklift_presentation")
local Config = require("src.config")
local Renderer = require("src.warehouse_renderer")
local function close(a,b) return math.abs(a-b)<0.000001 end

function Test.run(_, check)
    local function test(name, value) check("forklift_presentation_" .. name, value) end
    local directions = { "northwest", "north", "northeast", "east",
        "southeast", "south", "southwest", "west" }
    local originalMultiplier,originalWarehouse=Config.forklift.visualScaleMultiplier,Config.warehouse
    local palletScale,workerScale=Config.palletLogistics.drawScale,Config.player.drawScale
    Config.warehouse={provisionalArt=true}
    for index,direction in ipairs(directions) do
        local operatingExact,parkedExact,loadRegistered=true,true,true
        for _,height in ipairs({0,0.08,0.5,1}) do
            local resized={owned=true,x=420,y=510,direction=direction,operating=true,forkHeight=height,carriedPalletId="SAME-PALLET"}
            Config.forklift.visualScaleMultiplier=1
            local before=Renderer.forkliftPlan(resized)
            resized.operating=false
            local parkedBefore=Renderer.parkedForkliftPlan(resized,1774,887)
            Config.forklift.visualScaleMultiplier=1.4
            resized.operating=true
            local after=Renderer.forkliftPlan(resized)
            resized.operating=false
            local parkedAfter=Renderer.parkedForkliftPlan(resized,1774,887)
            operatingExact=operatingExact and close(after.scale,before.scale*1.4)
                and after.directionFrame==index and before.frameIndex==after.frameIndex
                and before.originX==after.originX and before.originY==after.originY
                and before.x==after.x and before.y==after.y
            parkedExact=parkedExact and close(parkedAfter.scale,parkedBefore.scale*1.4)
                and parkedAfter.directionFrame==index and parkedAfter.source.x==parkedBefore.source.x
                and parkedAfter.source.y==parkedBefore.source.y and parkedAfter.originX==parkedBefore.originX
                and parkedAfter.originY==parkedBefore.originY and parkedAfter.x==parkedBefore.x and parkedAfter.y==parkedBefore.y
            loadRegistered=loadRegistered and close(after.loadX-after.x,(before.loadX-before.x)*1.4)
                and close(after.loadY-after.y,(before.loadY-before.y)*1.4)
                and close(parkedAfter.loadX-parkedAfter.x,(parkedBefore.loadX-parkedBefore.x)*1.4)
                and close(parkedAfter.loadY-parkedAfter.y,(parkedBefore.loadY-parkedBefore.y)*1.4)
                and after.carriedPalletId=="SAME-PALLET"
        end
        test("operating_exact_40_percent_resize_"..direction,operatingExact)
        test("parked_exact_40_percent_resize_"..direction,parkedExact)
        test("loaded_registration_scales_without_resizing_cargo_"..direction,loadRegistered)
    end
    Config.forklift.visualScaleMultiplier=originalMultiplier;Config.warehouse=originalWarehouse
    test("forklift_only_scale_does_not_resize_pallet_or_worker",Config.palletLogistics.drawScale==palletScale and Config.player.drawScale==workerScale)
    test("larger_forklift_updates_physical_footprint_and_ground_reach",originalMultiplier==1.4
        and close(Config.forklift.collisionHalfWidth,34*1.4) and close(Config.forklift.collisionHalfHeight,14*1.4)
        and close(Config.forklift.loadedCollisionHalfWidth,42*1.4) and close(Config.forklift.loadedCollisionHalfHeight,18*1.4)
        and close(Config.forklift.forkOffsetX,46*1.4) and close(Config.forklift.forkOffsetY,27*1.4))
    test("forklift_resize_preserves_speed_and_lift_timing",Config.forklift.speed==100 and Config.forklift.loadedSpeed==72
        and Config.forklift.liftDuration==3 and Config.forklift.lowerDuration==2.5 and Config.forklift.travelHeight==0.08)
    local catalog = Presentation.reviewCatalog()
    local vehicle = { owned = true, x = 400, y = 300, direction = "northwest",
        operating = true, forkHeight = 0, carriedPalletId = "P-LOAD" }
    for index, direction in ipairs(directions) do
        local sheet = catalog[direction]
        test("metadata_" .. direction, Presentation.validateSheet(sheet)
            and #sheet.frames == 4 and sheet.width == 2048 and sheet.height == 768)
        vehicle.direction = direction
        local blocked, reason = Presentation.plan(vehicle)
        test("rejects_unapproved_" .. direction, not blocked and reason == "art_not_approved")
        local previousY, previousContinuousY = math.huge, math.huge
        local monotonic, continuousMonotonic, attached = true, true, true
        for step = 0, 100 do
            vehicle.forkHeight = step / 100
            local plan = Presentation.plan(vehicle, { review = true, catalog = catalog, scale = 0.22 })
            if not plan or plan.directionFrame ~= index or plan.loadY > previousY then
                monotonic = false
            end
            local continuousY = plan and plan.sample.loadOffset.y or math.huge
            if continuousY >= previousContinuousY then continuousMonotonic = false end
            if plan then
                local frame = sheet.frames[plan.frameIndex]
                attached = attached and math.abs(plan.loadX - vehicle.x
                    - (frame.loadAnchor.x - frame.wheelAnchor.x) * plan.scale) < 0.000001
                    and math.abs(plan.loadY - vehicle.y
                    - (frame.loadAnchor.y - frame.wheelAnchor.y) * plan.scale) < 0.000001
            else attached = false end
            previousY = plan and plan.loadY or math.huge
            previousContinuousY = continuousY
        end
        test("visual_load_never_descends_during_raise_" .. direction, monotonic)
        test("continuous_monotonic_sample_" .. direction, continuousMonotonic)
        test("cargo_stays_on_selected_tines_between_frames_" .. direction, attached)
    end
    test("north_review_selects_corrected_heading", catalog.north.path:match("north%-raise%-v2%.png$")
        and catalog.north.approved == false and catalog.north.frames[1].wheelAnchor.y == 738)
    test("south_review_selects_extended_mast", catalog.south.path:match("south%-raise%-v3%.png$")
        and catalog.south.approved == false and catalog.south.frames[4].wheelAnchor.y == 675)
    vehicle.direction, vehicle.forkHeight = "east", 0
    local ground = Presentation.plan(vehicle, { review = true, scale = 0.22 })
    vehicle.forkHeight = 1
    local upper = Presentation.plan(vehicle, { review = true, scale = 0.22 })
    test("height_selects_first_and_last_frames", ground.frameIndex == 1 and upper.frameIndex == 4
        and ground.loadY > upper.loadY)
    test("source_crop_exact", upper.source.x == 1536 and upper.source.y == 0
        and upper.source.width == 512 and upper.source.height == 768)
    test("wheel_contact_stays_world_anchored", ground.x == upper.x and ground.y == upper.y
        and ground.scale == upper.scale)
    vehicle.forkHeight = 0.9
    local raising = Presentation.plan(vehicle, { review = true })
    vehicle.forkHeight = 0.6
    local lowering = Presentation.plan(vehicle, { review = true })
    test("reversal_tracks_actual_height_not_clock", lowering.loadY > raising.loadY
        and lowering.frameIndex < raising.frameIndex)
    vehicle.targetForkHeight = 0.9
    local differentTarget = Presentation.plan(vehicle, { review = true })
    test("target_does_not_teleport_art", differentTarget.frameIndex == lowering.frameIndex
        and differentTarget.loadY == lowering.loadY)
    test("cargo_uses_id_without_mutation", differentTarget.carriedPalletId == "P-LOAD"
        and vehicle.carriedPalletId == "P-LOAD" and vehicle.forkHeight == 0.6)
    local sample = Presentation.heightSample(catalog.east, -10)
    test("height_sample_clamps_low", sample.height == 0 and sample.frameIndex == 1)
    sample = Presentation.heightSample(catalog.east, 10)
    test("height_sample_clamps_high", sample.height == 1 and sample.frameIndex == 4)
    for index, invalid in ipairs({ 0 / 0, math.huge, -math.huge, "1" }) do
        test("height_rejects_nonfinite_" .. index, not Presentation.heightSample(catalog.east, invalid))
    end
    catalog.east.frames[2].loadAnchor.y = 700
    local valid, reason = Presentation.validateSheet(catalog.east)
    test("rejects_downward_forks_in_raise_metadata", not valid and reason == "non_monotonic_forks")
    catalog = Presentation.reviewCatalog()
    catalog.east.frames[2].source.width = 5000
    test("rejects_crop_outside_image", not Presentation.validateSheet(catalog.east))
    catalog = Presentation.reviewCatalog()
    catalog.east.frames[2].wheelAnchor.x = nil
    test("rejects_missing_anchor", not Presentation.validateSheet(catalog.east))
    catalog = Presentation.reviewCatalog()
    test("catalog_reads_are_detached", catalog.east.frames[2].wheelAnchor.x ~= nil
        and catalog.east.frames[2].source.width == 512)
    catalog.east.approved = true
    vehicle.operating = false
    local plan
    plan, reason = Presentation.plan(vehicle, { catalog = catalog })
    test("parked_cannot_draw_baked_driver", not plan and reason == "driver_mismatch")
    plan = Presentation.plan(vehicle, { catalog = catalog, review = true })
    test("review_flags_driver_mismatch", plan and plan.driverMismatch)
    vehicle.operating = true
    plan = Presentation.plan(vehicle, { catalog = catalog })
    test("explicitly_approved_catalog_can_plan", plan and plan.approved and not plan.review)

    local pushes, pops, draws, released = 0, 0, 0, 0
    local graphics = {
        newQuad = function(x, y, w, h, tw, th)
            assert(w == 512 and h == 768 and tw == 2048 and th == 768)
            return { release = function() released = released + 1 end }
        end,
        push = function(mode) assert(mode == "all"); pushes = pushes + 1 end,
        pop = function() pops = pops + 1 end,
        setColor = function() end,
        draw = function() draws = draws + 1 end,
    }
    local image = { getDimensions = function() return 2048, 768 end }
    local function getImage() return image end
    local drawn = Presentation.draw(vehicle, getImage, { review = true }, graphics)
    test("review_draw_balanced_and_releases_quad", drawn and draws == 1
        and pushes == 1 and pops == 1 and released == 1)
    drawn, reason = Presentation.draw(vehicle, getImage, nil, graphics)
    test("default_draw_never_loads_unapproved_art", not drawn and reason == "art_not_approved" and draws == 1)
    test("missing_image_rejected", not Presentation.draw(vehicle, function() end, { review = true }, graphics))
    image.getDimensions = function() return 512, 512 end
    drawn, reason = Presentation.draw(vehicle, getImage, { review = true }, graphics)
    test("wrong_image_dimensions_rejected", not drawn and reason == "image_dimensions")
    image.getDimensions = function() return 2048, 768 end
    graphics.draw = function() error("test draw failure") end
    drawn = Presentation.draw(vehicle, getImage, { review = true }, graphics)
    test("graphics_state_restored_after_draw_error", not drawn and pushes == pops and released == 2)
end

return Test
