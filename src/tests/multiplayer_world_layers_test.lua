local Test = {}

function Test.run(context, check)
    local world, state = context.world, context.state
    local previousScreen = state.screen
    local previousPlayer = world.snapshot()
    local previousWeekday = state.calendar.weekday
    state.calendar.weekday = 4
    world.load({ x = 300, y = 335, character = previousPlayer.character })
    state.screen = "computer"
    world.customer.timer = 0
    world.vendor.timer = 1000
    local scheduled = world.truck:schedule("layered-world-test", "delivery")
    local playerX, playerY = world.player.x, world.player.y

    -- Exercise the real app loop. Both arrivals must progress while the host
    -- keeps the computer open, without moving the host or selecting a target.
    for _ = 1, 160 do context.app.update(0.1) end
    check("host_menu_keeps_truck_delivery_moving",
        scheduled and world.truck.state == "parked_closed")
    check("host_menu_keeps_reception_visitor_moving",
        world.customer.state == "waiting")
    check("host_menu_only_pauses_host_player_controls",
        state.screen == "computer" and world.player.x == playerX
        and world.player.y == playerY and world.getInteraction() == nil)

    world.load(previousPlayer)
    state.screen = previousScreen
    state.calendar.weekday = previousWeekday
    world._state = state
end

return Test
