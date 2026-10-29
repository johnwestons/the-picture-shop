# Crowded shop performance investigation

The saving and cold-image findings below were addressed in the
[October 29 follow-up](save_image_stalls_2026-10-29.md), which records the new
threaded pipelines, validation and measurements.

The capacity fixture contains 14 installed machines, 80 physical job pallets,
10 employees, 80 completed job records and 200 messages. A second phase makes
all ten employees seek cutter access, exercising route selection and movement
instead of measuring only idle workers. Each run starts with a fresh disposable
test identity and output-local saves.

## Findings and changes

- Pickup hints checked stack support and employee reservations for every pallet
  before checking distance. Stack support itself scans the pallet inventory, so
  faraway skids produced unnecessary quadratic work every frame. Pickup range
  and room checks now run first; authoritative pickup checks remain in place.
- Worker movement repeatedly constructed expanded collision planes for the same
  machine and pallet dimensions. A bounded cache now shares the immutable plane
  geometry. Position, room, actor and pallet ownership still come from fresh
  obstacle records.
- One actor move now shares its obstacle snapshot between position checks,
  route validation, route search and traversal. Traversal also uses the existing
  spatial index. The next actor move gets current positions, so this does not
  retain a stale world snapshot across updates.
- Room floor samples repeatedly walked the authored contour segments during
  pathfinding. Room adapters now prepare the floor height for every mask column
  once. The 1536 by 1024 sampling grid, passage and floor boundaries are preserved.

## Measurements

Both compared runs use Windows LÖVE, the 1600 by 720 phone layout and the same
LuaJIT sampling profiler. These measure CPU update time and render submission,
not Android FPS or completed GPU frames. Sample maxima vary and are not a
guaranteed upper bound.

| Scenario | Before mean | After mean | Before p95 | After p95 |
| --- | ---: | ---: | ---: | ---: |
| Crowded updates | 2.684 ms | 1.369 ms | 7.179 ms | 4.182 ms |
| Crowded updates with saves | 2.640 ms | 1.327 ms | 7.820 ms | 4.532 ms |
| Ten workers seeking machine access | 8.631 ms | 3.105 ms | 21.765 ms | 6.992 ms |
| Crowded render submission | 0.539 ms | 0.543 ms | 0.767 ms | 0.729 ms |

Ordinary crowded updates use about 49% less CPU time. The busy-worker case uses
about 64% less, and its largest sampled update fell from 87.572 to 33.387 ms.
Rendering was not the dominant CPU cost in this fixture.

Raw measurements and sampled stacks:

- `output/performance/late-game-profile-before-20261028/measurements.json`
- `output/performance/late-game-profile-final-20261028/measurements.json`

Reproduce with `tools/run_performance_probe.ps1 -Label <new-label>`, setting
`PICTURE_SHOP_MOBILE=1` and `PICTURE_SHOP_PERFORMANCE_PROFILE=1` in that process.
Omit the profile flag for ordinary timing without sampled stacks.

## Validation and remaining measurements

The `late-game-performance` smoke focus passes 525 checks and three draw frames
in each of desktop and forced-mobile layouts. It covers pickup eligibility,
stack supports, live ownership changes, navigation through thin obstacles and
around moved objects, employee transport, room transitions, machine operation
and multiplayer contracts. New floor checks compare every mask column at its
edge and passage boundaries for all four room kinds. New pickup checks confirm
that only the two nearby same-room skids trigger inventory-wide support checks
in a 100-pallet fixture, and that an unstacked support becomes available immediately.

The Lua compiler guard passes 622 files and 8,667 compiled functions within the
project limits. Reports are in `output/performance/validation-20261028/`.

The older general `performance` focus used to stop at `paperwork_offer_created`
because it expected a $648 quote after reputation pricing changed to produce
$660. Its expectation now matches the current quote calculation.

Occasional save and cold texture stalls remain measurable. A crowded save still
takes about 26 ms on this PC, and the final saved-game run includes a 41 ms update.
Cold forklift views also take roughly 122 ms at the slowest sample. The measured
steady crowded phases do not decode new images. These changes do not move disk
or image loading off the main thread.

ADB reports no connected device. Physical Android CPU/GPU frame time, memory
pressure and thermal behavior remain to be measured, particularly with several
different worker species changing poses during actual production. The current
fixture clones one worker profile and cannot establish those device costs.
