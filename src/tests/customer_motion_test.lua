local Customer = require("src.customer")
local CharacterAnimation = require("src.character_animation")
local Config = require("src.config")

local Test = {}

local function definition()
    return {
        character = "business-cat",
        route = { { x = 0, y = 0 }, { x = 100, y = 0 } },
        speed = 72,
        initialArrivalDelay = 0,
        arrivalDelay = 0,
        motionProfiles = {
            ["business-cat"] = {
                walkPixelsPerFrame = 13,
                acceleration = 420,
                deceleration = 620,
                gaitSpeedMultipliers = { 0.96, 0.94, 1.04, 1.06, 0.96, 0.94, 1.04, 1.06 },
                gaitAccelerationMultipliers = { 0.92, 0.90, 1.08, 1.10, 0.92, 0.90, 1.08, 1.10 },
            },
        },
    }
end

function Test.run(_, check)
    local assets = { hasAction = function() return true end }
    for _, character in ipairs({ "business-dragon", "business-fox", "business-cat", "tan-cat", "blue-coaler-cat", "green-blazer-cat" }) do
        local role = Config.customer.motionProfiles[character] and Config.customer or Config.vendor
        local visitor = Customer.new({ character = character, speed = role.speed,
            motionProfiles = role.motionProfiles, initialArrivalDelay = 0,
            route = { { x = 0, y = 0 }, { x = 100, y = -100 } } })
        visitor:update(.1, { x = 500, y = 500 })
        local actual = math.sqrt(visitor.x * visitor.x + visitor.y * visitor.y)
        check(character .. "_walk_is_accelerated_and_uses_achieved_distance",
            visitor.currentSpeed > 0 and visitor.currentSpeed < role.speed
            and math.abs(visitor.animationDistance - actual) < .0001)
        local action, mirror = visitor:poseAction(assets)
        check(character .. "_walk_uses_diagonal_back_view", action == "walk_northeast" and mirror == 1)
        local distance, phase = visitor.animationDistance, visitor:frameForAction("walk_northeast", 8)
        visitor:update(.5, { x = visitor.x, y = visitor.y })
        action, mirror = visitor:poseAction(assets)
        check(character .. "_blocked_walk_freezes_and_idles_in_last_direction",
            visitor.animationDistance == distance and visitor:frameForAction("walk_northeast", 8) == phase
            and not visitor.inMotion and action == "idle_northeast" and mirror == 1)
        visitor.idleClock = 2 / visitor.idleAnimationRate - .07
        check(character .. "_directional_idle_animates", visitor:frameForAction("idle_northeast", 2) == 2)
        visitor.idleClock = .5
        check(character .. "_idle_holds_open_eyes_between_brief_blinks", visitor:frameForAction("idle_northeast", 2) == 1)
    end

    local corner = Customer.new({ character = "tan-cat", speed = 100, initialArrivalDelay = 0,
        route = { { x = 0, y = 0 }, { x = 3, y = 0 }, { x = 3, y = -20 } } })
    corner:update(.1, { x = 500, y = 500 })
    check("visitor_turn_counts_every_path_segment_and_faces_latest_segment",
        math.abs(corner.animationDistance - 10) < .0001 and corner.motionX == 0 and corner.motionY == -1)
    corner:update(.2, { x = 500, y = 500 })
    local standingAction = corner:poseAction(assets)
    check("standing_salesman_waits_in_directional_idle_instead_of_sitting",
        corner.state == "waiting" and standingAction == "idle_north")
    corner:beginReview()
    local noUse = { hasAction = function(_, action) return action ~= "use" end }
    check("standing_salesman_without_use_action_idles_during_review", corner:poseAction(noUse) == "idle_north")

    local customer = Customer.new(definition())
    local distanceBefore = customer.animationDistance
    customer:update(0.1, { x = 500, y = 500 })
    check("business_cat_accelerates_into_its_gait",
        customer.currentSpeed > 0 and customer.currentSpeed < customer.speed)
    check("business_cat_gait_clock_uses_actual_distance",
        customer.animationDistance > distanceBefore
        and math.abs(customer.animationDistance - customer.x) < 0.0001)
    check("business_cat_remembers_walk_direction_for_idle",
        customer.intentX > 0.99 and math.abs(customer.intentY) < 0.001)

    local seated = Customer.new({
        character = "business-cat",
        route = { { x = 0, y = 0 }, { x = 20, y = 0 } },
        seatSpots = {
            { name = "chair", x = 50, y = 25, facing = -1,
                approach = { { x = 30, y = 5 }, { x = 40, y = 15 } },
                foreground = "chair-front" },
            { name = "sofa", x = 75, y = 30, facing = 1,
                approach = { { x = 45, y = 10 }, { x = 60, y = 20 } },
                foreground = "table-front" },
        },
        speed = 100,
        initialArrivalDelay = 0,
        arrivalDelay = 0,
    })
    check("customer_builds_a_seat_specific_approach_route",
        #seated.route == 5 and seated.route[3].x == 30 and seated.route[4].x == 40
        and seated.route[5].x == 50 and seated.route[5].y == 25
        and seated.seat.name == "chair" and seated.seatFacing == -1)
    seated:update(0.46, { x = 500, y = 500 })
    check("customer_stops_in_front_of_chair_before_sitting",
        seated.state == "entering" and seated.x == 40 and seated.y == 15
        and seated.seatingPause > 0 and seated.waypoint == 5)
    seated:update(0.30, { x = 500, y = 500 })
    check("customer_changes_pose_only_after_occupying_the_seat",
        seated.state == "waiting" and seated.x == 50 and seated.y == 25
        and seated.seatingPause == 0)
    check("customer_stands_clear_of_furniture_before_departing",
        seated:beginReview() and seated:resolve("accepted")
        and seated.state == "exiting" and seated.x == 40 and seated.y == 15
        and seated.waypoint == 3 and not seated.inMotion)
    seated:reset(false)
    check("customer_rotates_through_individual_sofa_and_chair_positions",
        seated.seatIndex == 2 and #seated.route == 5
        and seated.route[5].x == 75 and seated.route[5].y == 30
        and seated.seat.name == "sofa" and seated.seat.foreground == "table-front")

    customer.animationDistance = 39
    local frame = customer:frameForAction("walk", 8)
    check("business_cat_walk_frames_are_distance_synchronized", frame == 4)

    local idleAction, mirror = CharacterAnimation.directionalIdleAction(
        customer.intentX, customer.intentY)
    check("business_cat_idle_resolves_from_last_walk_sector",
        idleAction == "idle" and mirror == 1)

    local hostVisitor = {
        state = "reviewing",
        visible = true,
        x = 88,
        y = 14,
        waypoint = 2,
        seatIndex = 1,
        character = "business-cat",
        facing = -1,
        intentX = -1,
        intentY = 0,
        motionX = 0,
        motionY = 0,
        currentSpeed = 0,
        animationDistance = 52,
        animationClock = 3,
        idleClock = 4,
        inMotion = false,
        waitTimer = 37,
        arrivalTimer = 0,
    }
    local applied = customer:applySnapshot(hostVisitor)
    check("lan_guest_installs_complete_host_visitor_snapshot",
        applied and customer.state == "reviewing" and customer.visible
        and customer.x == 88 and customer.y == 14 and customer.waypoint == 2
        and customer.seatIndex == 1 and customer.character == "business-cat"
        and customer.facing == -1 and customer.intentX == -1
        and customer.animationDistance == 52 and customer.animationClock == 3
        and customer.idleClock == 4 and customer.waitTimer == 37
        and customer.timer == 0 and not customer.inMotion)

    hostVisitor.x = math.huge
    hostVisitor.state = "finished"
    check("lan_guest_rejects_invalid_visitor_snapshot_atomically",
        not customer:applySnapshot(hostVisitor)
        and customer.state == "reviewing" and customer.x == 88)
end

return Test
