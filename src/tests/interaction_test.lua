local Interaction = require("src.interaction")

local Test = {}

function Test.run(context, check)
    local player = { x = 0, y = 0 }
    local targets = {
        nearPlayer = { x = 10, y = 0, radius = 100, hoverRadius = 8 },
        nearCursor = { x = 50, y = 0, radius = 100, hoverRadius = 8 },
    }

    local hovered = Interaction.select(player, targets, 50, 0)
    check("interaction_hover_priority_matches_mouse_frontier",
        hovered and hovered.kind == "nearCursor" and hovered.hovered
        and hovered.cursorDistance == 0 and hovered.playerDistance == 50)

    local cursorLed = Interaction.select(player, targets, 80, 0)
    check("interaction_cursor_proximity_selects_between_player_range_actions",
        cursorLed and cursorLed.kind == "nearCursor" and not cursorLed.hovered)

    local nearestFallback = Interaction.select(player, targets)
    check("interaction_without_cursor_falls_back_to_nearest_player_action",
        nearestFallback and nearestFallback.kind == "nearPlayer")

    local filtered = Interaction.select(player, {
        eligible = { x = 25, y = 0, radius = 30 },
        cursorOnly = { x = 100, y = 0, radius = 20, hoverRadius = 30 },
    }, 100, 0)
    check("interaction_cursor_cannot_select_an_action_outside_player_range",
        filtered and filtered.kind == "eligible")

    local tied = Interaction.select(player, {
        zebra = { x = 20, y = 0, radius = 50 },
        alpha = { x = 20, y = 0, radius = 50 },
    }, 20, 0)
    check("interaction_equal_scores_have_a_stable_tie_breaker", tied and tied.kind == "alpha")

    local facingLed = Interaction.select({ x = 0, y = 0, intentX = 1, intentY = 0 }, {
        behind = { x = -9, y = 0, radius = 50 },
        ahead = { x = 14, y = 0, radius = 50 },
    }, nil, nil, nil, { facingWeight = 18 })
    check("interaction_without_pointer_prefers_facing_direction",
        facingLed and facingLed.kind == "ahead")

    local sticky = Interaction.select(player, {
        previous = { x = 22, y = 0, radius = 50 },
        challenger = { x = 20, y = 0, radius = 50 },
    }, nil, nil, { kind = "previous" }, { stickiness = 5 })
    check("interaction_previous_target_resists_prompt_flicker",
        sticky and sticky.kind == "previous")

    local world, state = context.world, context.State.new()
    local previousWorldState = world._state
    world.bayDoor:reset()
    world.truck:reset()
    local switch = world.bayDoor:getInteraction()
    local nearWorker = {
        x = switch.x + switch.radius + 9,
        y = switch.y,
        intentX = 1,
        intentY = 0,
        facing = 1,
    }
    local farWorker = {
        x = switch.x + switch.radius + 11,
        y = switch.y,
        intentX = 1,
        intentY = 0,
        facing = 1,
    }
    local farAccepted, farCode = world.performNetworkInteraction(
        farWorker, state, "loadingBayDoor", "open")
    check("network_door_use_requires_authoritative_host_range",
        not farAccepted and farCode == "out_of_range"
        and world.bayDoor.state == "closed")

    local hostOnlyAccepted, hostOnlyCode = world.performNetworkInteraction(
        nearWorker, state, "computer", "open")
    check("network_door_allowlist_keeps_other_shop_controls_host_only",
        not hostOnlyAccepted and hostOnlyCode == "not_allowed"
        and world.bayDoor.state == "closed")

    local opened, openCode = world.performNetworkInteraction(
        nearWorker, state, "loadingBayDoor", "open")
    local repeated, repeatedCode = world.performNetworkInteraction(
        nearWorker, state, "loadingBayDoor", "open")
    local reversed, reverseCode = world.performNetworkInteraction(
        nearWorker, state, "loadingBayDoor", "closed")
    check("network_door_desired_state_is_idempotent_during_motion",
        opened and openCode == "accepted" and repeated and repeatedCode == "in_progress"
        and not reversed and reverseCode == "state_changed"
        and world.bayDoor.state == "opening")

    world.bayDoor.state, world.bayDoor.progress = "open", 1
    local alreadyOpen, alreadyOpenCode = world.performNetworkInteraction(
        nearWorker, state, "loadingBayDoor", "open")
    local closed, closeCode = world.performNetworkInteraction(
        nearWorker, state, "loadingBayDoor", "closed")
    check("network_door_desired_state_applies_once_after_stable_state",
        alreadyOpen and alreadyOpenCode == "already_applied"
        and closed and closeCode == "accepted"
        and world.bayDoor.state == "closing")
    world.bayDoor:reset()
    world.truck:reset()
    world._state = previousWorldState
end

return Test
