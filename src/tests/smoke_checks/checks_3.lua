-- Game integration checks with the original assertions and shared scenario state.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.check("cutter_button_strip_loaded", Context.context.assets.get("cutterControlButtons") ~= nil)
    Context.check("cutter_clamp_strip_loaded", Context.context.assets.get("cutterClamp") ~= nil)
    Context.check("cutter_blade_strip_loaded", Context.context.assets.get("cutterBlade") ~= nil)
    Context.check("polar_back_button_strip_loaded", Context.context.assets.get("polarBackButton") ~= nil)
    for frame = 1, 3 do
        Context.check("polar_back_button_frame_" .. frame,
            Context.context.assets.getQuad("polarBackButton" .. frame) ~= nil)
    end
    for frame = 1, Context.context.config.cutterGui.motionFrameCount do
        Context.check("cutter_clamp_frame_" .. frame, Context.context.assets.getQuad("cutterClamp" .. frame) ~= nil)
        Context.check("cutter_blade_frame_" .. frame, Context.context.assets.getQuad("cutterBlade" .. frame) ~= nil)
    end
    Context.check("wrapper_pack_replaces_cutter_pack", Context.context.assets.activatePack("wrapper")
        and Context.context.assets.activePackName() == "wrapper"
        and Context.context.assets.get("polarOperatorConsole") == nil
        and Context.context.assets.get("wrappedPalletStages") ~= nil
        and Context.context.assets.get("loadedPaperPallet") ~= nil)
    for frame = 1, 3 do
        Context.check("wrapped_pallet_stage_" .. frame,
            Context.context.assets.getQuad("wrappedPalletStage" .. frame) ~= nil)
    end
    Context.check("press_pack_replaces_wrapper_pack", Context.context.assets.activatePack("press")
        and Context.context.assets.activePackName() == "press"
        and Context.context.assets.get("wrapperMaintenanceAtlas") == nil
        and Context.context.assets.get("pressProcessStages") ~= nil
        and Context.context.assets.get("pressOperatorHandbook") ~= nil)
    for frame = 1, 4 do
        Context.check("press_process_stage_" .. frame,
            Context.context.assets.getQuad("pressProcessStage" .. frame) ~= nil)
    end
    for frame = 1, 6 do
        Context.check("press_handbook_page_" .. frame,
            Context.context.assets.getQuad("pressHandbookPage" .. frame) ~= nil)
    end
    Context.check("screen_pack_releases_to_world", Context.context.assets.activatePack(nil)
        and Context.context.assets.activePackName() == nil
        and Context.context.assets.get("wrappedPalletStages") ~= nil
        and Context.context.assets.get("loadedPaperPallet") == nil
        and Context.context.assets.get("pressProcessStages") == nil
        and Context.context.assets.get("pressOperatorHandbook") == nil)
    if Context.background and Context.mask then
        local backgroundWidth, backgroundHeight = Context.background:getDimensions()
        local maskWidth, maskHeight = Context.mask:getDimensions()
        Context.check(
            "walkmask_alignment",
            backgroundWidth == maskWidth and backgroundHeight == maskHeight,
            string.format("warehouse=%dx%d mask=%dx%d", backgroundWidth, backgroundHeight, maskWidth, maskHeight)
        )
    end
    Context.varied, Context.maskDetail = Context.maskHasBothValues(Context.context.assets.getData("walkmask"))
    Context.check("walkmask_values", Context.varied, Context.maskDetail)
    Context.routeValid, Context.routeDetail = Context.routeIsWalkable(
        Context.context.assets.getData("walkmask"),
        Context.context.config.customer.route,
        Context.context.config
    )
    Context.check("customer_reception_route_walkable", Context.routeValid, Context.routeDetail)
    do
        local footprints = {
            { name = "cutter", width = Context.context.config.cutterPlacement.collisionHalfWidth,
                height = Context.context.config.cutterPlacement.collisionHalfHeight },
            { name = "wrapper", width = Context.context.config.wrapperPlacement.collisionHalfWidth,
                height = Context.context.config.wrapperPlacement.collisionHalfHeight },
            { name = "loaded_jack", width = Context.context.config.palletJack.loadedCollisionHalfWidth,
                height = Context.context.config.palletJack.loadedCollisionHalfHeight },
        }
        for _, footprint in ipairs(footprints) do
            local edgeX, edgeY = Context.centerOnlyWalkmaskPoint(Context.context, footprint.width, footprint.height)
            Context.check(footprint.name .. "_full_footprint_rejects_blocked_corner", edgeX
                and Context.context.Navigation.isWalkable(Context.context.assets, edgeX, edgeY, {})
                and not Context.context.Navigation.canMoveAreaFrom(Context.context.assets,
                    edgeX, edgeY, edgeX, edgeY, footprint.width, footprint.height, {}))
        end
        local palletX, palletY = Context.centerOnlyWalkmaskPoint(Context.context,
            Context.context.config.palletLogistics.collisionHalfWidth,
            Context.context.config.palletLogistics.collisionHalfHeight)
        Context.check("pallet_drop_rejects_blocked_corner", palletX
            and not Context.context.world.isPalletPlacementClear(
                Context.context.State.new(), Context.context.assets, palletX, palletY))
    end

    Context.door = Context.context.BayDoor.new(Context.context.config.loadingBay)
    Context.check("bay_door_starts_closed", Context.door.state == "closed"
        and Context.door:frame() == 1)
    Context.check("bay_door_sprite_never_blocks_floor_movement", Context.door:getObstacle() == nil)
    Context.doorObstacles = {}
    if Context.door:getObstacle() then Context.doorObstacles[1] = Context.door:getObstacle() end
    Context.check("closed_bay_apron_uses_walkmask_only",
        Context.context.Navigation.canMoveFrom(Context.context.assets, 170, 267, 180, 267, Context.doorObstacles))
    Context.check("bay_door_begins_opening", Context.door:open() and Context.door.state == "opening")
    Context.check("bay_door_ignores_toggle_while_moving", not Context.door:toggle())
    Context.door:update(Context.context.config.loadingBay.duration * 0.5)
    Context.check("bay_door_half_open_frame", Context.door.state == "opening" and Context.door:frame() == 3)
    Context.door:update(Context.context.config.loadingBay.duration * 0.5)
    Context.check("bay_door_opens", Context.door.state == "open"
        and Context.door:frame() == Context.context.config.loadingBay.frameCount)
    Context.check("bay_door_begins_closing", Context.door:close() and Context.door.state == "closing")
    Context.door:update(Context.context.config.loadingBay.duration)
    Context.check("bay_door_closes", Context.door.state == "closed" and Context.door:frame() == 1)

    Context.truck = Context.context.Truck.new(Context.context.config.truck)
    Context.check("truck_keeps_constant_scale",
        Context.context.config.truck.start.scale == Context.context.config.truck.parked.scale)
    Context.check("truck_starts_absent", Context.truck.state == "absent" and not Context.truck:isVisible())
    Context.check("truck_schedules_job", Context.truck:schedule("JOB-TRUCK-TEST", "delivery")
        and Context.truck.state == "scheduled")
    Context.check("truck_requests_bay", Context.truck:update(Context.context.config.truck.scheduleDelay + 0.1, "closed")
        == "request_bay_open" and Context.truck.state == "waiting_for_bay")
    Context.check("truck_begins_backing", Context.truck:update(0, "open") == "backing_started"
        and Context.truck.state == "backing")
    Context.truck:update(Context.context.config.truck.backingDuration * 0.5, "open")
    Context.midTruck = Context.truck:snapshot()
    Context.startX, Context.parkedX = Context.context.config.truck.start.x, Context.context.config.truck.parked.x
    Context.startY, Context.parkedY = Context.context.config.truck.start.y, Context.context.config.truck.parked.y
    Context.travelX, Context.travelY = Context.parkedX - Context.startX, Context.parkedY - Context.startY
    Context.travelLength = math.sqrt(Context.travelX * Context.travelX + Context.travelY * Context.travelY)
    Context.bodyAxis = Context.context.config.truck.bodyAxis
    Context.axisLength = math.sqrt(Context.bodyAxis.x * Context.bodyAxis.x + Context.bodyAxis.y * Context.bodyAxis.y)
    Context.alignmentError = math.abs(Context.travelX * Context.bodyAxis.y - Context.travelY * Context.bodyAxis.x)
        / (Context.travelLength * Context.axisLength)
    Context.rearwardDot = Context.travelX * Context.bodyAxis.x + Context.travelY * Context.bodyAxis.y
    Context.check("truck_reverses_straight_toward_dock", Context.midTruck.backingProgress > 0.45
        and Context.midTruck.backingProgress < 0.55
        and Context.midTruck.x > math.min(Context.startX, Context.parkedX)
        and Context.midTruck.x < math.max(Context.startX, Context.parkedX)
        and Context.midTruck.y > math.min(Context.startY, Context.parkedY)
        and Context.midTruck.y < math.max(Context.startY, Context.parkedY)
        and Context.rearwardDot > 0
        and Context.alignmentError < 0.02)
    Context.apertureCenterX = 0
    for _, point in ipairs(Context.context.config.truck.aperture) do Context.apertureCenterX = Context.apertureCenterX + point.x end
    Context.apertureCenterX = Context.apertureCenterX / #Context.context.config.truck.aperture
    Context.parkedRearX = Context.context.config.truck.parked.x
        + Context.context.config.truck.rearOpeningOffsetX * Context.context.config.truck.parked.scale
    Context.check("truck_rear_centers_on_dock", math.abs(Context.parkedRearX - Context.apertureCenterX) <= 3)
    Context.check("truck_parks", Context.truck:update(Context.context.config.truck.backingDuration, "open") == "parked"
        and Context.truck.state == "parked_closed"
        and Context.truck:getInteraction() ~= nil
        and Context.truck:getObstacle() ~= nil)
    Context.check("truck_cargo_begins_opening", Context.truck:toggleCargoDoor()
        and Context.truck.state == "cargo_opening")
    Context.truck:update(Context.context.config.truck.cargoDuration * 0.5, "open")
    Context.check("truck_cargo_half_open_frame", Context.truck:cargoFrame() == 3)
    Context.check("truck_cargo_opens", Context.truck:update(Context.context.config.truck.cargoDuration, "open")
        == "cargo_opened" and Context.truck.state == "cargo_open"
        and Context.truck:cargoFrame() == Context.context.config.truck.cargoFrameCount)
    Context.check("truck_cargo_closes", Context.truck:toggleCargoDoor()
        and Context.truck:update(Context.context.config.truck.cargoDuration, "open") == "cargo_closed"
        and Context.truck.state == "parked_closed")
    Context.check("truck_can_depart", Context.truck:depart() and Context.truck.state == "departing")
    Context.check("truck_departure_finishes", Context.truck:update(Context.context.config.truck.backingDuration, "open")
        == "departed" and Context.truck.state == "absent" and not Context.truck:isVisible())

    Context._, Context._, Context.rabbitIdleFrames = Context.context.characterAssets.get("rabbit-worker", "idle", 1)
    Context._, Context._, Context.rabbitWalkFrames = Context.context.characterAssets.get("rabbit-worker", "walk", 1)
    Context.directionalFramesHealthy = true
    for _, action in ipairs({
        "walk_north", "walk_northeast", "walk_southeast", "walk_south",
        "idle_north", "idle_northeast", "idle_southeast", "idle_south",
    }) do
        local _, _, frameCount = Context.context.characterAssets.get("rabbit-worker", action, 1)
        Context.directionalFramesHealthy = Context.directionalFramesHealthy
            and frameCount == (action:match("^walk") and 8 or 2)
            and Context.context.characterAssets.hasAction("rabbit-worker", action)
    end
    Context.check("rabbit_player_character_pack",
        Context.rabbitIdleFrames == 2 and Context.rabbitWalkFrames == 8 and Context.directionalFramesHealthy
        and Context.context.characterAssets.hasAction("rabbit-worker", "idle")
        and Context.context.characterAssets.hasAction("rabbit-worker", "walk"))

    Context.customer = Context.context.Customer.new({
        character = "green-blazer-cat",
        route = { { x = 0, y = 0 }, { x = 40, y = 0 }, { x = 40, y = 40 } },
        speed = 100,
        arrivalDelay = 0.1,
    })
    Context.check("customer_starts_scheduled", Context.customer.state == "scheduled" and not Context.customer.visible)
    Context.customer:update(0.05, { x = 500, y = 500 })
    Context.check("customer_honors_arrival_delay", Context.customer.state == "scheduled")
    Context.customer:update(0.50, { x = 500, y = 500 })
end

return Component
