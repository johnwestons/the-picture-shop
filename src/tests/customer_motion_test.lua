local Customer = require("src.customer")
local CharacterAnimation = require("src.character_animation")

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
