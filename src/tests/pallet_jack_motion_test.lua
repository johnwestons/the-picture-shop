local Test = {}
local Config = require("src.config")
local PalletJack = require("src.pallet_jack")
local CharacterAnimation = require("src.character_animation")

local function freshJack(direction)
    local state = { palletJack = PalletJack.defaultState(Config.palletJack) }
    state.palletJack.x, state.palletJack.y = 500, 500
    state.palletJack.direction = direction or "northwest"
    PalletJack.mount(state, Config.palletJack, 1)
    return state
end

local function drive(state, x, y, seconds, canMove)
    local frames = math.max(1, math.ceil(seconds * 60))
    local dt = seconds / frames
    for _ = 1, frames do
        PalletJack.move(state, x, y, dt, Config.palletJack, canMove or function() return true end)
    end
end

local function distanceFrom(state, x, y)
    local dx, dy = state.palletJack.x - x, state.palletJack.y - y
    return math.sqrt(dx * dx + dy * dy)
end

function Test.run(_, check)
    local accelerating = freshJack("east")
    local startX, startY = accelerating.palletJack.x, accelerating.palletJack.y
    drive(accelerating, 1, 0, 0.1)
    local initialDistance = distanceFrom(accelerating, startX, startY)
    check("pallet_jack_accelerates_into_motion_instead_of_jumping_to_speed",
        initialDistance > 0 and initialDistance < Config.palletJack.speed * 0.04)

    local straight, diagonal = freshJack("east"), freshJack("east")
    drive(straight, 1, 0, 0.45)
    drive(diagonal, 1, 1, 0.45)
    check("pallet_jack_diagonal_speed_is_normalized",
        math.abs(distanceFrom(straight, 500, 500) - distanceFrom(diagonal, 500, 500)) < 0.01)

    local analog, full = freshJack("east"), freshJack("east")
    drive(analog, 0.25, 0, 0.3)
    drive(full, 1, 0, 0.3)
    check("pallet_jack_keeps_slow_analog_positioning",
        distanceFrom(analog, 500, 500) < distanceFrom(full, 500, 500) * 0.65)

    local braking = freshJack("east")
    drive(braking, 1, 0, 0.55)
    local beforeBrakeX = braking.palletJack.x
    PalletJack.move(braking, 0, 0, 1 / 60, Config.palletJack, function() return true end)
    check("pallet_jack_release_brakes_over_time",
        braking.palletJack.moving and braking.palletJack.x > beforeBrakeX)
    drive(braking, 0, 0, 0.4)
    local stoppedX, stoppedY = braking.palletJack.x, braking.palletJack.y
    PalletJack.move(braking, 0, 0, 0.1, Config.palletJack, function() return true end)
    check("pallet_jack_finishes_braking_and_stays_still",
        not braking.palletJack.moving and braking.palletJack.x == stoppedX
        and braking.palletJack.y == stoppedY)

    local reversing = freshJack("east")
    drive(reversing, 1, 0, 0.5)
    local beforeReverseX = reversing.palletJack.x
    PalletJack.move(reversing, -1, 0, 0.05, Config.palletJack, function() return true end)
    check("pallet_jack_reversal_brakes_before_changing_travel_direction",
        reversing.palletJack.direction == "east" and reversing.palletJack.x > beforeReverseX)
    drive(reversing, -1, 0, 0.4)
    check("pallet_jack_completes_a_smooth_reversal",
        reversing.palletJack.direction == "west" and reversing.palletJack.x < beforeReverseX + 20)

    local beforePose = freshJack("northwest")
    local operatorX, operatorY = PalletJack.operatorPosition(beforePose, Config.palletJack)
    PalletJack.move(beforePose, 1, 0, 1 / 60, Config.palletJack, function() return true end)
    local nextOperatorX, nextOperatorY = PalletJack.operatorPosition(beforePose, Config.palletJack)
    local operatorStep = math.sqrt((nextOperatorX - operatorX)^2 + (nextOperatorY - operatorY)^2)
    check("pallet_jack_operator_turns_around_the_handle_without_teleporting",
        operatorStep > 0 and operatorStep < 12)
    drive(beforePose, 1, 0, 0.35)
    local alignedX, alignedY = PalletJack.operatorPosition(beforePose, Config.palletJack)
    local eastOffset = Config.palletJack.operatorOffsets.east
    check("pallet_jack_operator_eases_into_the_matching_handle_position",
        math.abs(alignedX - (beforePose.palletJack.x + eastOffset.x)) < 0.01
        and math.abs(alignedY - (beforePose.palletJack.y + eastOffset.y)) < 0.01)

    local sectors = {
        {"northwest", -1, -1}, {"north", 0, -1}, {"northeast", 1, -1},
        {"east", 1, 0}, {"southeast", 1, 1}, {"south", 0, 1},
        {"southwest", -1, 1}, {"west", -1, 0},
    }
    local sectorsCorrect = true
    for _, sector in ipairs(sectors) do
        local state = freshJack("east")
        drive(state, sector[2], sector[3], 0.1)
        sectorsCorrect = sectorsCorrect and state.palletJack.direction == sector[1]
    end
    check("pallet_jack_motion_resolves_all_eight_directional_views", sectorsCorrect)

    local operatorAnchorsCorrect = true
    for _, sector in ipairs(sectors) do
        local state = freshJack(sector[1])
        local x, y = PalletJack.operatorPosition(state, Config.palletJack)
        local offset = Config.palletJack.operatorOffsets[sector[1]]
        operatorAnchorsCorrect = operatorAnchorsCorrect and offset ~= nil
            and math.abs(x - (state.palletJack.x + offset.x)) < 0.01
            and math.abs(y - (state.palletJack.y + offset.y)) < 0.01
    end
    check("pallet_jack_operator_anchors_follow_each_handle_view", operatorAnchorsCorrect)

    local wallSlide = freshJack("east")
    drive(wallSlide, 1, 1, 0.1, function(x) return x <= 500.01 end)
    check("pallet_jack_slides_along_a_blocked_axis",
        wallSlide.palletJack.x == 500 and wallSlide.palletJack.y > 500
        and wallSlide.palletJack.moving,
        string.format("x=%g y=%g moving=%s",wallSlide.palletJack.x,
            wallSlide.palletJack.y,tostring(wallSlide.palletJack.moving)))
    local blocked = freshJack("east")
    PalletJack.move(blocked, 1, 0, 0.1, Config.palletJack, function() return false end)
    check("pallet_jack_does_not_advance_when_fully_blocked",
        blocked.palletJack.x == 500 and blocked.palletJack.y == 500 and not blocked.palletJack.moving)

    local pushIdle = CharacterAnimation.frameForPalletJackPush(8, false, 120, 20)
    local pushStep = CharacterAnimation.frameForPalletJackPush(8, true, 120, 20)
    check("pallet_jack_push_pose_stays_planted_when_stopped_and_advances_with_travel",
        pushIdle == 2 and pushStep == 7)
    local pushDirections = {
        {0, -1, "push_north", 1}, {1, -1, "push_northeast", 1},
        {1, 0, "push", 1}, {1, 1, "push_southeast", 1},
        {0, 1, "push_south", 1}, {-1, 1, "push_southeast", -1},
        {-1, 0, "push", -1}, {-1, -1, "push_northeast", -1},
    }
    local pushCoverage = true
    for _, direction in ipairs(pushDirections) do
        local action, mirror = CharacterAnimation.directionalPalletJackPushAction(
            direction[1], direction[2])
        pushCoverage = pushCoverage and action == direction[3] and mirror == direction[4]
    end
    check("pallet_jack_push_art_covers_eight_directions_with_intentional_mirroring", pushCoverage)

    local Art = require("src.pallet_jack_art")
    local Characters = require("src.character_assets")
    local Rig = require("src.pallet_jack_presentation")
    check("pallet_jack_has_32_authored_turn_views_in_phone_sized_atlas",
        #Art.frames == 32 and Config.palletJack.frameColumns == 16
        and Config.palletJack.frameSize * Config.palletJack.frameColumns <= 4096)
    local sixteen = true
    for _, action in ipairs({"push","push_north","push_northeast","push_southeast","push_south"}) do
        local _, _, frames = Characters.get("rabbit-worker", action, 1)
        sixteen = sixteen and frames == 16 and #Art.hands[action] == frames
            and Characters.hasAction("rabbit-worker", action .. "_idle")
    end
    check("pallet_jack_has_16_drawings_and_planted_idle_in_each_push_view", sixteen)
    check("pallet_jack_inbetweens_preserve_the_original_stride_length",
        CharacterAnimation.frameForPalletJackPush(16,true,10,20)==2
        and CharacterAnimation.frameForPalletJackPush(16,true,80,20)==9
        and CharacterAnimation.frameForPalletJackPush(16,true,160,20)==1)

    local turn = freshJack("northwest")
    local prior = PalletJack.visualPose(turn, Config.palletJack)
    PalletJack.move(turn,1,0,1/60,Config.palletJack,function() return true end)
    local following = PalletJack.visualPose(turn,Config.palletJack)
    check("pallet_jack_visual_heading_uses_bounded_turns_instead_of_sector_snaps",
        math.abs((following.heading-prior.heading+math.pi)%(2*math.pi)-math.pi)
        <= Config.palletJack.turnRadiansPerSecond/60+.0001)
    drive(turn,1,0,.4)
    local pose = PalletJack.visualPose(turn,Config.palletJack)
    local view = pose.blend < .5 and pose.frame or pose.nextFrame
    check("pallet_jack_wraps_turn_atlas_continuously_across_east",
        pose.frame>=1 and pose.frame<=32 and pose.nextFrame>=1 and pose.nextFrame<=32
        and (view==1 or view==32))
    local stoppedDistance = PalletJack.animationDistance(blocked,Config.palletJack)
    drive(blocked,1,0,.4,function() return false end)
    check("pallet_jack_gait_phase_freezes_against_a_wall",
        PalletJack.animationDistance(blocked,Config.palletJack)==stoppedDistance)

    local operator = {character="rabbit-worker",id=1,animationDistance=99999}
    local samples = Rig.workerPoses(Characters,operator,turn)
    operator.animationDistance=0
    local repeated = Rig.workerPoses(Characters,operator,turn)
    local pinned, weights = true, 0
    for i, sample in ipairs(samples) do
        pinned = pinned and sample.anchorX==repeated[i].anchorX and sample.anchorY==repeated[i].anchorY
            and sample.weight==repeated[i].weight
        weights=weights+sample.weight
    end
    check("pallet_jack_grip_and_gait_ignore_worker_orbit_distance",
        pinned and math.abs(weights-1)<.00001)
    check("pallet_jack_operator_pose_changes_do_not_advance_walking",
        PalletJack.animationDistance(turn,Config.palletJack)==pose.distance)
end

return Test
