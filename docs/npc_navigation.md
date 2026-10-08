# NPC navigation

Employees, applicants, customers, supplier representatives and visiting technicians use `src/npc_navigation.lua` on the authoritative host. The same planner handles their destination selection and movement. Player controls stay in `src/player_controller.lua`.

The planner uses an eight-neighbor A* grid with a binary heap and ten-pixel spacing. It connects the actor's exact position and exact destination to the grid, prevents diagonal corner cutting, and smooths routes only across clear segments. Floor checks use the current walk mask, including unlocked warehouse expansions. Continuous sweeps against circles, rectangles, diamonds and expanded ground footprints prevent tunneling between grid nodes or during a large movement update.

Each actor has a transient route cache. Movement checks the next segment against current machines, pallets, furniture, visitors and players. A changed destination, blocked segment, displacement or lack of progress triggers replanning. Failed searches retry every 0.75 seconds; two failures report a blocked destination to the caller. Actors embedded in a placement can walk out while decreasing penetration. A short, checked connector can recover an actor from an invalid mask edge, without crossing blocked floor after reaching open ground. A genuinely disconnected destination stays blocked until access changes; actors do not teleport or perform work remotely.

Employees select reachable operator and pallet approach positions, and retain the existing blocked-work rescheduling behavior. Visitors skip blocked intermediate route markers, try another reachable chair if necessary, and walk back to the entrance if reception is inaccessible. Technicians choose accessible ground beside the installed machine and follow its placement before starting service. Seating anchors remain presentation positions, separate from walking goals.

## Reusing the system

Supply a context with `assets` and `obstacles(actor)`. Assets expose `getData("walkmask")`; obstacles use the existing ground footprints. Give actor obstacles an `actor` reference so the context can exclude the actor itself. `World.employeeContext(state, assets)` provides the current warehouse context.

```lua
local Navigator = require("src.npc_navigation")
local context = World.employeeContext(state, assets)
local reached, remainingDistance, movedDistance, blocked = Navigator.travel(
    actor, {x = destinationX, y = destinationY}, speed * motionDt, motionDt, context)
```

The caller chooses speed, acceleration and business behavior. Use `movedDistance` for gait/animation timing and the actor's resulting `intentX`/`intentY` for its last movement direction. `remainingDistance` allows continuing to the next logical destination in the same update.

`Navigator.findPath(actor, candidateGoals, context)` returns safe path points and the selected goal, including the supplied goal's metadata. `findReachablePoint` selects and caches a route to an alternative destination. `reset(actor)` clears transient state after a visit or teleport. `status(actor)` returns the current route status and failed search count. Navigation caches are weakly keyed and never serialized.

## Verification

`src/tests/npc_navigation_test.lua` covers U-shaped traps, thin obstacles, dynamic placements, displacement, embedded starts, mask edges, disconnected destinations and reopening routes. Integration cases check employee/client detours, distance-based gait, blocked route markers, alternative chairs, safe departure, all four real lounge approaches and both technician service visits. It runs through the standard smoke suite.
