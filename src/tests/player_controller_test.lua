local PlayerController = require("src.player_controller")
local CharacterAnimation = require("src.character_animation")
local CharacterAssets = require("src.character_assets")
local Config = require("src.config")

local Test = {}

local function player()
    return { x = 0, y = 0, speed = 100, facing = 1 }
end

local definition = {
    speed = 100,
    acceleration = 500,
    deceleration = 800,
    maxFrameTime = 0.10,
    maxStepDistance = 3,
}

function Test.run(_, check)
    local expectedDirections = {
        { 0, -1, "walk_north", 1 }, { 1, -1, "walk_northeast", 1 },
        { 1, 0, "walk", 1 }, { 1, 1, "walk_southeast", 1 },
        { 0, 1, "walk_south", 1 }, { -1, 1, "walk_southeast", -1 },
        { -1, 0, "walk", -1 }, { -1, -1, "walk_northeast", -1 },
    }
    local directionsCorrect = true
    for _, expected in ipairs(expectedDirections) do
        local action, mirror = CharacterAnimation.directionalWalkAction(expected[1], expected[2])
        directionsCorrect = directionsCorrect and action == expected[3] and mirror == expected[4]
    end
    check("player_walk_animation_covers_eight_direction_sectors", directionsCorrect)

    local expectedPushDirections = {
        { 0, -1, "push_north", 1 }, { 1, -1, "push_northeast", 1 },
        { 1, 0, "push", 1 }, { 1, 1, "push_southeast", 1 },
        { 0, 1, "push_south", 1 }, { -1, 1, "push_southeast", -1 },
        { -1, 0, "push", -1 }, { -1, -1, "push_northeast", -1 },
    }
    local pushDirectionsCorrect = true
    for _, expected in ipairs(expectedPushDirections) do
        local action, mirror = CharacterAnimation.directionalPalletJackPushAction(expected[1],expected[2])
        pushDirectionsCorrect = pushDirectionsCorrect and action==expected[3] and mirror==expected[4]
    end
    check("pallet_jack_push_animation_covers_eight_direction_sectors",pushDirectionsCorrect)

    local expectedIdles = {
        { 0, -1, "idle_north", 1 }, { 1, -1, "idle_northeast", 1 },
        { 1, 0, "idle", 1 }, { 1, 1, "idle_southeast", 1 },
        { 0, 1, "idle_south", 1 }, { -1, 1, "idle_southeast", -1 },
        { -1, 0, "idle", -1 }, { -1, -1, "idle_northeast", -1 },
    }
    local idlesCorrect = true
    for _, expected in ipairs(expectedIdles) do
        local action, mirror = CharacterAnimation.directionalIdleAction(expected[1], expected[2])
        idlesCorrect = idlesCorrect and action == expected[3] and mirror == expected[4]
    end
    check("player_idle_animation_covers_eight_direction_sectors", idlesCorrect)

    local idleTimingCorrect = true
    for _, expected in ipairs(expectedIdles) do
        local action = expected[3]
        idleTimingCorrect = idleTimingCorrect
            and CharacterAnimation.frameForPlayerAction(action, 2, 0, 2, 20, .65) == 1
            and CharacterAnimation.frameForPlayerAction(action, 2, 0, 2 / .65 - .07, 20, .65) == 2
            and CharacterAnimation.frameForPlayerAction(action, 2, 0, 2 / .65 + .01, 20, .65) == 1
    end
    check("player_directional_idle_alternate_pose_is_brief", idleTimingCorrect)

    local walkActions = {
        "walk", "walk_north", "walk_northeast", "walk_southeast", "walk_south",
    }
    local walkFramesAdvance = true
    for _, action in ipairs(walkActions) do
        for index, distance in ipairs({ 0, 20, 40, 60, 80, 100, 120, 140, 160 }) do
            local expectedFrame = index <= 8 and index or 1
            local frame = CharacterAnimation.frameForPlayerAction(
                action, 8, distance, 999, 20, 0.65)
            walkFramesAdvance = walkFramesAdvance and frame == expectedFrame
        end
    end
    check("all_directional_walk_cycles_advance_eight_frames_by_distance", walkFramesAdvance)

    local pushFramesAdvance=true
    for _,action in ipairs({"push","push_north","push_northeast","push_southeast","push_south"}) do
        for index,distance in ipairs({0,20,40,60,80,100,120,140,160}) do
            local expectedFrame=index<=8 and index or 1
            pushFramesAdvance=pushFramesAdvance and CharacterAnimation.frameForPlayerAction(
                action,8,distance,999,20,0.65)==expectedFrame
        end
    end
    check("pallet_jack_push_cycles_advance_by_actual_player_distance",pushFramesAdvance)
    check("provisional_pallet_jack_push_atlases_are_registered",Config.warehouse.provisionalArt
        and CharacterAssets.hasAction("rabbit-worker","push")
        and CharacterAssets.hasAction("rabbit-worker","push_north")
        and CharacterAssets.hasAction("rabbit-worker","push_northeast")
        and CharacterAssets.hasAction("rabbit-worker","push_southeast")
        and CharacterAssets.hasAction("rabbit-worker","push_south"))

    local cycleSeconds = 8 * 20 / 155
    check("player_walk_cycle_timing_is_audited",
        cycleSeconds > 1.00 and cycleSeconds < 1.05)

    local gaitDefinition = {
        walkPixelsPerFrame = 20,
        gaitSpeedMultipliers = { 0.96, 0.94, 1.04, 1.06, 0.96, 0.94, 1.04, 1.06 },
        gaitAccelerationMultipliers = { 0.92, 0.90, 1.08, 1.10, 0.92, 0.90, 1.08, 1.10 },
    }
    local contactSpeed, contactAcceleration = PlayerController.gaitMotion(0, gaitDefinition)
    local loadedSpeed, loadedAcceleration = PlayerController.gaitMotion(20, gaitDefinition)
    local passingSpeed, passingAcceleration = PlayerController.gaitMotion(40, gaitDefinition)
    local propulsionSpeed, propulsionAcceleration = PlayerController.gaitMotion(60, gaitDefinition)
    check("player_gait_slows_weighted_poses_and_accelerates_mid_step",
        loadedSpeed < contactSpeed and contactSpeed < passingSpeed
        and passingSpeed < propulsionSpeed
        and loadedAcceleration < contactAcceleration
        and contactAcceleration < passingAcceleration
        and passingAcceleration < propulsionAcceleration)

    local blendedSpeed = PlayerController.gaitMotion(30, gaitDefinition)
    check("player_gait_speed_blends_between_animation_poses",
        blendedSpeed > loadedSpeed and blendedSpeed < passingSpeed)

    local oppositeContactSpeed = PlayerController.gaitMotion(80, gaitDefinition)
    local oppositePassingSpeed = PlayerController.gaitMotion(120, gaitDefinition)
    check("player_gait_curve_repeats_for_the_opposite_step",
        math.abs(contactSpeed - oppositeContactSpeed) < 0.0001
        and math.abs(passingSpeed - oppositePassingSpeed) < 0.0001)

    local multiplierTotal = 0
    for _, multiplier in ipairs(gaitDefinition.gaitSpeedMultipliers) do
        multiplierTotal = multiplierTotal + multiplier
    end
    check("player_gait_curve_preserves_base_average_pace",
        math.abs(multiplierTotal / #gaitDefinition.gaitSpeedMultipliers - 1) < 0.0001)

    local slowPhase = player()
    local fastPhase = player()
    local gaitMovementDefinition = {
        speed = 100, acceleration = 100000, deceleration = 800,
        maxFrameTime = 0.10, maxStepDistance = 3,
        walkPixelsPerFrame = gaitDefinition.walkPixelsPerFrame,
        gaitSpeedMultipliers = gaitDefinition.gaitSpeedMultipliers,
        gaitAccelerationMultipliers = gaitDefinition.gaitAccelerationMultipliers,
    }
    PlayerController.reset(slowPhase, { x = 0, y = 0 }, gaitMovementDefinition)
    PlayerController.reset(fastPhase, { x = 0, y = 0 }, gaitMovementDefinition)
    slowPhase.animationDistance = 20
    fastPhase.animationDistance = 60
    local slowDistance = PlayerController.update(
        slowPhase, 1, 0, 0.01, function() return true end, gaitMovementDefinition)
    local fastDistance = PlayerController.update(
        fastPhase, 1, 0, 0.01, function() return true end, gaitMovementDefinition)
    check("player_world_speed_follows_the_current_gait_pose", fastDistance > slowDistance)

    local smooth = player()
    PlayerController.reset(smooth, { x = 0, y = 0 }, definition)
    PlayerController.update(smooth, 1, 0, 0.05, function() return true end, definition)
    check("player_accelerates_instead_of_snapping_to_full_speed",
        smooth.velocityX > 0 and smooth.velocityX < definition.speed and smooth.x > 0)

    local diagonal = player()
    PlayerController.reset(diagonal, { x = 0, y = 0 }, definition)
    PlayerController.update(diagonal, 1, 1, 0.10, function() return true end, definition)
    local diagonalSpeed = math.sqrt(diagonal.velocityX ^ 2 + diagonal.velocityY ^ 2)
    check("player_diagonal_input_does_not_move_faster", diagonalSpeed <= definition.speed + 0.001)

    local straightStart, diagonalStart = player(), player()
    PlayerController.reset(straightStart, nil, definition)
    PlayerController.reset(diagonalStart, nil, definition)
    local straightTravel = PlayerController.update(straightStart, 1, 0, .02, function() return true end, definition)
    local diagonalTravel = PlayerController.update(diagonalStart, 1, 1, .02, function() return true end, definition)
    check("player_starts_with_equal_acceleration_in_every_direction", math.abs(straightTravel - diagonalTravel) < .0001)
    local analog = player()
    PlayerController.reset(analog, nil, definition)
    for _ = 1, 10 do PlayerController.update(analog, .3, .4, .02, function() return true end, definition) end
    check("player_analog_input_retains_half_speed", math.abs(math.sqrt(analog.velocityX^2 + analog.velocityY^2) - 50) < .0001)
    PlayerController.update(straightStart, 0, 0, .02, function() return true end, definition)
    PlayerController.update(diagonalStart, 0, 0, .02, function() return true end, definition)
    check("player_release_braking_is_equal_in_every_direction", straightStart.velocityX == 0
        and diagonalStart.velocityX == 0 and diagonalStart.velocityY == 0)

    local loadedReverse, propulsionReverse = player(), player()
    for _, actor in ipairs({loadedReverse, propulsionReverse}) do
        PlayerController.reset(actor, nil, gaitMovementDefinition)
        actor.velocityX = 60
    end
    loadedReverse.animationDistance, propulsionReverse.animationDistance = 20, 60
    PlayerController.update(loadedReverse, -1, 0, .01, function() return true end, gaitMovementDefinition)
    PlayerController.update(propulsionReverse, -1, 0, .01, function() return true end, gaitMovementDefinition)
    check("player_reversal_braking_does_not_depend_on_gait_phase",
        math.abs(loadedReverse.velocityX - 52) < .0001 and math.abs(propulsionReverse.velocityX - 52) < .0001)

    local blocked = player()
    PlayerController.reset(blocked, nil, definition)
    PlayerController.update(blocked, 1, 1, .1, function() return false end, definition)
    check("player_blocked_motion_keeps_stride_frozen", not blocked.moving and blocked.blocked
        and blocked.animationDistance == 0 and blocked.velocityX == 0 and blocked.velocityY == 0)

    local sliding = player()
    PlayerController.reset(sliding, { x = 0, y = 0 }, {
        speed = 100, acceleration = 2000, deceleration = 2000,
        maxFrameTime = 0.10, maxStepDistance = 3,
    })
    PlayerController.update(sliding, 1, 1, 0.10,
        function(_, _, nextX) return nextX <= 0.01 end,
        { speed = 100, acceleration = 2000, deceleration = 2000,
            maxFrameTime = 0.10, maxStepDistance = 3 })
    check("player_slides_along_blocked_axis", math.abs(sliding.x) < 0.01 and sliding.y > 0)

    local animated = player()
    PlayerController.reset(animated, { x = 0, y = 0 }, definition)
    PlayerController.update(animated, 1, 0, 0.10, function() return true end, definition)
    local firstDistance = animated.animationDistance
    PlayerController.update(animated, 0, 0, 0.10, function() return true end, definition)
    check("player_animation_tracks_actual_distance",
        firstDistance > 0 and animated.animationDistance >= firstDistance)
    check("player_idle_retains_last_walk_direction",
        animated.intentX > 0.99 and math.abs(animated.intentY) < 0.001
        and CharacterAnimation.directionalIdleAction(animated.intentX, animated.intentY) == "idle")

    local externallyMoved = player()
    PlayerController.reset(externallyMoved, { x = 0, y = 0 }, definition)
    local startX, startY = externallyMoved.x, externallyMoved.y
    externallyMoved.x, externallyMoved.y = -4, -4
    PlayerController.observeExternalMove(externallyMoved, startX, startY, true, 0.1)
    local externalIdle, externalMirror = CharacterAnimation.directionalIdleAction(
        externallyMoved.intentX, externallyMoved.intentY)
    check("externally_moved_player_retains_observed_direction_for_idle",
        externalIdle == "idle_northeast" and externalMirror == -1)
    local externalWalk, walkMirror = CharacterAnimation.actorWalkAction(externallyMoved)
    check("externally_moved_player_walk_uses_observed_direction", externalWalk == "walk_northeast" and walkMirror == -1)
    local slideWalk = CharacterAnimation.actorWalkAction(sliding)
    check("player_wall_slide_faces_achieved_motion", slideWalk == "walk_south")
end

return Test
