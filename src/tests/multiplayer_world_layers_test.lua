local Test = {}

function Test.run(context, check)
    local world, state = context.world, context.state
    local previousPlayer = world.snapshot()
    -- Earlier suites deliberately park machines and stock in visitor access
    -- areas. This clock/host-menu fixture needs a fresh, accessible reception.
    local previousState={}
    for key,value in pairs(state) do previousState[key]=value end
    for key in pairs(state) do state[key]=nil end
    for key,value in pairs(context.State.new()) do state[key]=value end
    state.employment.recruiting = false
    state.calendar.weekday = 4
    world.load({ x = 300, y = 335, character = previousPlayer.character })
    state.screen = "computer"
    world.customer.timer = 0
    world.vendor.timer = 1000
    local scheduled = world.truck:schedule("layered-world-test", "delivery")
    local playerX, playerY = world.player.x, world.player.y

    -- Exercise the real app loop. Both arrivals must progress while the host
    -- keeps the computer open, without moving the host or selecting a target.
    local transitions={}
    local lastState=world.customer.state
    for _ = 1, 160 do
        context.app.update(0.1)
        if lastState~=world.customer.state then
            transitions[#transitions+1]=world.customer.state.."@"..world.customer.waypoint
                ..":"..math.floor(world.customer.x)..","..math.floor(world.customer.y)
            lastState=world.customer.state
        end
    end
    check("host_menu_keeps_truck_delivery_moving",
        scheduled and world.truck.state == "parked_closed")
    check("host_menu_keeps_reception_visitor_moving",
        world.customer.state == "waiting",
        world.customer.state.." at "..world.customer.x..","..world.customer.y
            .." waypoint "..world.customer.waypoint.." vendor="..world.vendor.state
            .." applicant="..tostring(require("src.employee_ai").receptionOccupied(state))
            .." message="..tostring(state.message).." transitions="..table.concat(transitions,";"))
    check("host_menu_only_pauses_host_player_controls",
        state.screen == "computer" and world.player.x == playerX
        and world.player.y == playerY and world.getInteraction() == nil)

    world.load(previousPlayer)
    for key in pairs(state) do state[key]=nil end
    for key,value in pairs(previousState) do state[key]=value end
    world._state = state
end

return Test
