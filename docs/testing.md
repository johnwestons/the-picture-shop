# Test layout

## Small-tree motorcycle collisions

Tree collision now uses species, visual variant, growth stage and rendered
scale. Young stems are thinner than adult trunks; understory/open variants
also use narrower profiles. Trunks with a world-space radius below 0.14 m
are passable scenery. Small scaled mature trees therefore do not leave solid
walls, while visibly large variants and thick mature trunks still block.
Rock collision shapes are unchanged.

The `vegetation-collision` smoke focus passes 75 checks, including actual
motorcycle traversal through small trees and slender variants without speed
loss, damage or ejection, and a collision with a thick oak on the same route.
It also checks all five young tree species, growth across cached days, large
variants, rocks, airborne clearance, overlap recovery and collision damage.
Source-art comparisons and reports are under `output/tree-collision-review/`.

## Motorcycle direction rendering and jump-camera landing look

Brake/back input now brakes to a complete stop and then backs up automatically;
forward input brakes reversing motion and then drives ahead. This uses the same
authoritative driving axis for remapped keyboard/controller inputs and Android
buttons/sticks. Grounded direction changes require zero horizontal speed;
airborne back input still levels the bike. The condition gauge sits below the
left-side ride messages, clear of Options, Exit, camera and map buttons.
`auto_reverse_test.lua` covers stop/reversal, analog strength, frame rates and
all three camera modes; `auto_reverse_runtime_test.lua` exercises actual app
updates with keyboard state and touch press/move/release events. Native HUD
captures show the gauge at 63% condition on desktop and simulated mobile.

Earlier November 3, 2026 upright-only checkpoint: fixed third person used an upright 64-view turntable during
steady riding at every speed and during banked turns. It selects exact nominal
5.625-degree camera-relative sectors. All 64 sprites have now been regenerated
at higher source resolution, using the accepted views as exact cell templates.
One uniform scale/anchor contract replaces the previous interleaved generations.
The generated artwork's physical angles
are visually approximate; this is not a claim of measured 3D angular accuracy.
At that checkpoint, follow retained its 16-view rear/lean/tuck art, and brief
boost, shift and impact events retained 16-view midpoint/target poses. The
mounted-action rollout below supersedes those limits. Every bike draw
selects one opaque pose and one direction; heading and pose alpha crossfades
have both been removed.

The original renderer could reach all 16 cells. Uneven intermediate artwork and
overlaid transparent directions made heading changes harder to read. The old
native review also used a 45-degree step with a 16-entry direction list, repeating
eight physical headings, and its 660-pixel canvas clipped the lower two rows.
`tools/commute_lab/bike_review.lua` now uses 22.5-degree steps and shows all rows.

The upright-only checkpoint used `tools/commute_lab/review_bike_turning.ps1`
for 320 native checks, a 64-view production draw sheet and 128 sequential native
turn frames. Its `-Runtime` and `-Runtime -Mobile` runs exercised the real
application's input, camera, preference persistence and draw paths, passing
241 checks each. Each wrote
`actual-draw-coverage.json`, proving every original 16-view and new 64-view cell
was drawn once with alpha 1, through `App.draw`. Its full isolated run with
`-Runtime -Full` passed 10,056 checks. The LuaJIT compiler guard passed 906 files
and 11,611 functions. Evidence is under `output/bike-turning-quality-review/`.
The native comparison shows previous and regenerated 64-view sets over the same
revolution. `size-and-transition-audit.json` records adjacent helmet-width
changes averaging 0.9375 px instead of 1.875 px, with the worst step reduced
from 5 px to 3 px, including the wrap transition. Mean silhouette change falls
from 0.10388 to 0.08609 and its 95th percentile from 0.18884 to 0.15438.
These are image comparison metrics, not input-latency or device-frame-rate
measurements. Packaged-pixel regression checks guard all 64 distinct newly
authored cells, helmet height, scale and adjacent size changes. The 3-degree
steering-angle test still selects the finer sector between old 32-view angles.

The jump camera predicts touchdown along actual horizontal and vertical travel,
sampling support surfaces including bridge decks. First person eases its gaze
toward that ground while retaining physical bike pitch and cockpit attachment.
Automatic head movement is limited to 45 degrees; manual look fades the assist.
It settles after touchdown. Outside cameras lower their focus slightly to keep
the landing ground visible. Tests cover a real gravity-driven jump, ascent/apex,
support surfaces, frame rates, manual look, network telemetry and recovery.

The generated sources, exact built-in ImageGen prompts, immutable references
and generation history are in `assets/source/commute-bike-turning-v3/`; the
runtime asset is `assets/commute/bike/mounted-upright-64-v2.png`. The preceding
64-view asset remains the before/after baseline. Rebuild staging and review
strips with `tools/commute_lab/compile_bike_turning_quality.py`, then native
comparisons with `tools/commute_lab/compare_bike_turning_quality.py`. The bundled walking auditor
finds no image issues or warnings; its two remaining schema messages concern
missing walking direction/gait declarations, which do not apply to vehicle yaw
views. These checks used native desktop LÖVE and simulated mobile controls;
no phone installation was performed.

Current November 3, 2026 mounted-action rollout: acceleration, hard braking,
physical left/right lean, aerodynamic tuck, left-foot shift and impact brace
each have 64 newly authored midpoint and full-pose views. The 56 selected
source sheets contain 896 action cells; the accepted upright 64-view asset and
its SHA-256 are unchanged. Fixed, follow and perspective other-rider billboards
now use 64 directions for every mounted pose. The parked bike remains 16-view.
All camera modes select exact nominal 5.625-degree sectors, one opaque pose
and one unmirrored direction; generated physical yaw angles remain approximate.
Ordinary acceleration and hard braking use smoothed physical riding feedback
and share that feedback in trip snapshots. Follow keeps its smaller continuous
bank limit.

The current native review, `tools/commute_lab/review_bike_actions.ps1`, passes
460 checks and captures all 960 mounted pose/direction combinations through the
production renderer. This includes brake-priority release and four-rider cache
reuse, plus the tire and particle unit checks. Final desktop and simulated
mobile effects checks each pass 99 checks with `-Runtime -Focus motorcycle-effects`
(add `-Mobile` for touch mode). Reports are `runtime-motorcycle-effects-smoke.rpt`
and `runtime-motorcycle-effects-mobile-smoke.rpt`. Native scenes verify trail
dust separately because the legacy application test town has no dirt paths. The earlier
action-only runs passed 332 checks each and recorded 1,920 successful
`App.draw` samples per run: 15 mounted poses, 64 directions, fixed and follow,
with one bike draw at alpha 1. The broader `-Runtime -Focus commute` run now
passes 1,195 checks, including real home/work routes, bridges and destination
entry. Its test driver releases back/brake in the arrival zone so the new
automatic reverse does not drive it away from the destination. These are
native desktop and simulated mobile checks, not an installed phone build.

The current full isolated run (`-Runtime -Full`) stops at
`performance_machine_screen_reuses_textures_after_options` in the separate
cutter-screen texture-cache check. An isolated probe reproduces the cause
without loading motorcycle code: the current cutter pack parks 40,367,488
bytes (38.5 MiB) in its 32 MiB inactive cache and evicts the original clamp
texture. It is not a passing full-suite result. The failure report is
`output/bike-actions-64-review/full-smoke.rpt`.

Vehicle-specific asset acceptance verifies all 896 selected authored cells,
64 unique cells in every action state, current source hashes, clipping margins,
and adjacent upper-rig-envelope movement of at most 3 pixels, including wrap.
All 14 action contact sheets were visually reviewed for scale, articulation,
physical turn side and tire placement. The walking auditor reports two
inapplicable schema errors (`missing_directions`, `missing_gait`) and 20
whole-strip range warnings (14 baseline, four centre, two top-bound). Those
warnings compare a full yaw revolution as though it were a fixed-direction
walking cycle; its report contains no alpha, clipping or detached-component
findings. In a deep tuck the upper envelope can be shoulder/back, so envelope
width is a review diagnostic, not a helmet-diameter measurement.

Multiplayer observer-facing review: first-person rider billboards select their
view from each rider's physical heading relative to the actual eye-to-rider
bearing, including interpolated positions and off-center riders. Head look
changes framing, not the physical side visible from an unchanged eye position.
Fixed/follow cameras retain their parallel projection direction. Camera choices
stay local; changing either participant's view does not change replicated rider
heading, pose, paint or tire distance. Explicit local-player tags hide copied
local actor objects in first person, including the on-foot entry.

Run `tools/commute_lab/review_bike_multiplayer.ps1` (optionally `-Mobile`) for
two simulated observers, real network-codec snapshot round trips, all 64 views,
all nine independent camera-mode pairs and all 15 mounted poses. It renders
through the production perspective view and writes `observer-views.png` and
`draw-coverage.json` under `output/bike-multiplayer-review/`. This is a bounded
native rendering/snapshot review; it does not claim a live LAN-device test.

Runtime pages are in `assets/commute/bike/actions-64/`: four 1280-square pages
per state with unchanged 320-pixel cells and protected paint-region bounds.
The maximum of 12 resident action pages plus upright and parked textures uses
111,411,200 bytes (106.25 MiB), below the previous 117,964,800-byte (112.5 MiB)
art budget. This is a texture-memory bound, not a frame-rate claim.

Exact prompts, selected source hashes and immutable generation records are in
`assets/source/commute-bike-actions-v1/`. Rebuild in order with
`tools/commute_lab/compile_bike_actions.py`,
`tools/commute_lab/register_bike_action_profiles.py`, visual review of the
matched contact sheets, then `tools/commute_lab/publish_bike_actions.py --publish`.
The selected lean revisions explicitly project physical left/right for each
view; the rejected translucent left-lean study remains outside selection.
Review evidence is under `output/bike-actions-64-review/`, including
`asset-acceptance.json`, `native-draw-coverage.json`, and
`native-actions-64.gif`, assembled from native draw captures by
`tools/commute_lab/preview_bike_actions.py`.

Procedural tire motion uses resolved travel distance and speed, confined to
dark rubber in each mounted cell's lower wheel regions. It stops with the bike;
parked sprites and stopped pixels stay unchanged. Rebuild the region metadata
with `tools/commute_lab/compile_bike_wheel_regions.py` after publishing art;
the builder fits geometry without editing sprite pixels. The shared material
path preserves bike paint, sprite alpha and perspective depth/fog.

Local particles add stronger trail dust every 0.32 m, with lower emission on
paved roads, and exhaust from the physical right rear pipe. Dust requires
ground contact and actual movement; idling emits exhaust only, and engine-off
idling emits neither. Trail dust strength is 0.62 with a 1.25–1.75 s lifetime;
exhaust emits 6–14 puffs/s with strength 0.40–0.50 according to throttle. The
pipe sits 0.83 m above the bike support height; outside projection matches the
sprite's 48/22 vertical scale. The system caps 192 particles and eight emitters,
keeps no save fields and does not consume the global random generator.

`tools/commute_lab/review_bike_motion_fx.ps1` passes 49 checks. Its 120 native
tire samples cover all 15 poses and eight angle blocks, checking exact stopped
pixels, distance-driven changes confined to lower wheel regions, and unchanged
alpha. Particle captures compare the same motion on trail and paved surfaces,
engine-off stopping and idling. Evidence is in `output/bike-motion-fx-review/`,
including `particles-preview.png`, `bike-motion-fx.gif`,
`tire-motion-closeup.gif` and `tire-motion-acceptance.json`.

## Android workshop, ride and apartment smoke

Use `tools/android_town_journey.py` with the installed tester APK in landscape.
Select a disposable slot and an output folder. Run `new --seed 52` from the
title, then `departure`, `mount`, `ride` and `arrive`. Repeat those four
commands from the apartment exit. Run `verify --require-return` against the
same output folder and inspect the screenshots. The short seed provides a
roughly 41 m connected route. The runner uses actual touch controls and reads
save checkpoints for position and scene. It taps during cold terrain loading
to exercise the workshop exit regression. Checkpoints also inspect game logs,
the foreground activity and the screen for a LÖVE error.

For a human-driven test, `monitor --until home --apk-report <apk-report.json>`
observes the screen, scene and APK identity without sending input. Pass
`--serial`, `--port`, `--slot` and `--output` before the command when needed.

Android 80 was tested on a Galaxy S25 Ultra running Android 17. The final
signed APK completed both legs, an apartment reload, and separate physical
mechanic and collision checks. Evidence is in
`output/mobile/android80-workshop-journey/physical/`.

## Procedural town infrastructure and trails

The `town-infrastructure` focus checks version-3 town formation, road metadata,
bidirectional destination access, frozen save compatibility, trail shortcuts,
recreation clearings, fixture placement, collision and road paint. Native App
captures cover the main street, campsite, picnic table, stop sign, curve warning,
guardrail and town map in both riding cameras. The fixture mesh checks observe
actual draw calls rather than testing a separate preview implementation.

November 2 validation: desktop and simulated-mobile PC focuses each pass 66
checks, and the full desktop suite passes 9,981 checks. Fresh isolated profiles,
reports and captures are under `output/bike-paint/infrastructure-final-92902f86a3/`,
`infrastructure-mobile-input-f4d6b2ad54/` and `infrastructure-full-2ecb4013a7/`.
The compiler guard passes 890 files and 11,422 functions. A separate 100-seed
sweep produced 49 strips, 51 crossroads, 295 trails and 261 recreation areas;
all generated towns passed validation. Existing v2 seed 712345 retains its exact
fingerprint. New towns require regeneration in new-game setup to adopt v3.

The seed-712345 PC benchmark at 1280×880 on an RTX 3050 measured riding p95
6.98 ms, zoomed-out p95 6.28 ms and first-person riding p95 3.68 ms. Every steady
stage remained below 9 ms and ended with zero pending terrain or vegetation.
Cold preparation peaked at 41.86 ms; the first first-person stage peaked at
59.08 ms in this standalone probe, which does not use the runtime's camera
prewarm. These are PC measurements with vsync disabled and a GPU readback after
each stage, not physical-phone acceptance or a guarantee for every seed/device.
Raw measurements and a compact acceptance report are under
`output/town-infrastructure/`.

## Travel map navigation

The `route-map` focus checks a generated 16-building town through real App input
and draw callbacks. It verifies live mounted and on-foot coordinates, cardinal
headings, independence from camera rotation, every building's name, static cache
reuse, keyboard/mouse/touch toggles, Options access and release on menu exit.
Both desktop and simulated mobile runs pass 29 checks using fresh profiles;
native captures are under `output/bike-paint/travel-map-*`. The separate preview
run in `output/travel-map/preview-049ee536c1/` checks its map button, remappable M
toggle, Escape and mounted/on-foot rendering with the same generated town.

The map samples terrain once and reuses its canvas while navigation markers move.
The measured first complete map draw was 14.124 ms on this PC, including the test
capture canvas allocation. This is a draw timing, not a device frame-rate claim.

## Scene exits and outdoor rider scale

The `scene-exits` focus runs the real PC mouse/keyboard/touch callbacks through
terrain loading, riding, dismounting, apartment activities, and both scenes'
header exits. It checks immediate disk saves, failed-save retry, guest authority,
stationary ride restoration, unchanged apartment needs/time, and title-screen
simulation/audio/renderer cleanup. A held-joystick regression covers entering
Motorcycle Controls and resuming when a submenu consumes the original release.
Both desktop and forced-mobile PC runs pass 47 checks using fresh isolated saves.
Reports and native UI captures are under `output/bike-paint/scene-exits-*-final-*`.

`src/commute/tests/rider_scale_test.lua` checks outdoor size across directions,
outfits, walking, zoom, dressing and fallback rendering, while retaining indoor
scale, anchors and all 16 bike views. Run `output/rider-scale/run-review.ps1` for
the native production-art comparison. The reviewed comparison and seven passing
scale checks are in `output/rider-scale/native-1070822015/`; the unchanged strip
audit and contact sheets are in `output/rider-scale/motion-audit/`. No phone or
installed build was used for this validation.

## Employee speech reasons

The `employee-speech` focus exercises low skill on personal and shared schedules,
empty versus paused queues, removal of stale warnings, and resumption after a
skill increase. Real scheduling checks distinguish missing stretch film, delivery,
player and employee machine ownership, blade exchange, and pallet-jack access.
Blocked reasons persist while walking to the idle point and take priority over
greetings. All caption lengths are checked against the rendered bubble's wrapped
height; a capture can be written with `PICTURE_SHOP_EMPLOYEE_SPEECH_CAPTURE_DIR`.

Protocol 45 extends the caption code catalog without adding text to realtime
packets. Guest tests check host reason delivery, stale packet suppression,
unknown-code rejection, and the full eleven-actor packet ceiling. Reports and
fresh isolated profiles are in `output/employee-speech-20261026/`.

October 26 validation: 22 focused checks, 6,316 desktop checks and 6,317 forced
mobile checks pass. The compiler guard passes 609 files and 8,546 functions.
The three-caption gameplay capture was reviewed for wrapping and head placement.

## Room loading bays and employee shipping

The `room-shipping` smoke focus covers garage purchases through CritterNet and
host authority, catalog prices, replay safety, eligibility, and disk persistence.
It drives two independent loaded pallet jacks through each completed room's
entrance, loads only the matching truck manifest, and returns both jacks to clear
warehouse parking. Blocked destination floors reject the whole room transfer.
The host loading boundary rechecks the job, room, jack custody, distance, and
player manifest lease. Player manifests also reject skids in another room.

The full host cycle requests pickup for completed employee work, waits while a
player uses the manifest, handles the garage and cargo doors, loads, departs,
and pays once. It reloads a parked, loaded extra jack inside the room and again
after every skid is aboard the truck. Environment/employee wire cases exercise
room identities, separate garage-door progress, client delivery, malformed
updates, and the packet ceiling. Protocol 44 adds these room dock states.

Reports and disposable identities are in `output/room-shipping/`. Set
`PICTURE_SHOP_SMOKE_FOCUS=room-shipping` for the focused run and optionally set
`PICTURE_SHOP_ROOM_SHIPPING_CAPTURE_DIR` to an existing absolute directory for
CritterNet and both open/closed room bay captures. Phone checks use forced-mobile
LÖVE rendering and input; they do not replace testing on a physical device.

October 26 validation: the focused run passes 28 checks; desktop and forced-mobile
full runs each pass 6,292 checks. The Lua guard compiles 607 files and 8,525
functions within the slot/upvalue budgets. Purchase UI and both open/closed room
doors were reviewed in the capture directory.

## Service visit reliability

The blade courier now has a 2% call-out band and a 5% late band, down from
15% and 20%. A booking waits for an active technician visit to finish before
its outcome is evaluated. A postponed booking keeps its replacement date
without another random disruption, including across save/reload; completion
or a new booking resets that protection. Blade preparation is still required.

`src/tests/service_reliability_test.lua` tests 100 independent appointment dates
(93 on-time, five late, two call-outs), 500 busy-actor updates without extra
rolls or notices, single notices, replacement dates after disk reload, and
resetting the next booking. The `service-reliability` smoke focus also runs
machine-fleet, cutter authority/session, and technician motion/network checks.
Reports and disposable test identities are under `output/service-reliability/`.

## Pallet jack shelf and staging routes

The `pallet-routing` smoke focus reproduces the shelf-edge driving lock, a
cached shelf approach blocked by another parked jack, and a pickup pocket that
an empty jack can enter but a loaded jack cannot leave. It also exercises every
slot in a full six-pallet staging area, two simultaneous stock-to-shelf routes,
parking outside staging and shelf service space, and releasing a jack when the
last stock pallet disappears. The eight cases live in
`src/tests/pallet_jack_navigation_test.lua` and also run in the full suite.

Pickup selection and its final load check now require a continuous loaded exit.
Shelf access refreshes when blocked, and employees clear the rack aisle after
stocking. Parking avoids the painted staging rectangles, including the vehicle
footprint and a margin. Manual vehicle recovery permits bounded steps toward a
verified clear footprint after loading at a floor edge; collision and wall
checks still apply.

Desktop and forced-mobile full suites each pass 6,245 checks, including all
eight routing cases and the three-frame render check. Reports are in
`output/pallet-routing/full-desktop.rpt` and
`output/pallet-routing/full-mobile.rpt`; the original failures are recorded in
the baseline reports alongside them. Tests use fresh disposable identities under
`output/pallet-routing/appdata`. The Lua compiler guard passes 600 files and
8,459 functions within the project budgets.

## Purchasable pallet jacks

`src/tests/pallet_jack_fleet_test.lua` covers salesman and CritterNet purchase
buttons, channel prices, dock unloading, repeat-delivery protection, independent
cargo ownership, loaded disk saves, legacy saves, player selection, simultaneous
employee movement, collision with another loaded jack, and two complete
pickup/delivery/parking routes to separate cutters. It also verifies extra-jack
realtime packets, guest application, replay suppression, and reliable shop
updates retaining a live employee operator. Multiplayer protocol 42 adds
per-vehicle extra-jack updates within the existing 1,200-byte packet limit.

The `pallet-fleet` smoke focus runs the fleet checks alongside employee
transport/scheduling, pallet/storage ownership, save contracts, vendor authority,
and computer viewport coverage. Use an output-local `APPDATA` directory and a
fresh `the-picture-shop-test-...` identity for disposable saves. Set
`PICTURE_SHOP_PALLET_FLEET_CAPTURE_DIR` to an existing absolute directory to render
the salesman catalog, CritterNet Tools page, and two employees pushing loads.

The full desktop and forced-mobile suites each pass 6,216 checks, including the
three-frame render check, with reports in `output/pallet-fleet-full-desktop.rpt`
and `output/pallet-fleet-full-mobile.rpt`. Visual captures are in
`output/pallet-fleet-review/`. The compiler guard passes 596 Lua files and 8,404
functions; all 11 runtime-source packaging tests pass. These checks use the
desktop LÖVE engine; physical Android device testing is separate.

## Lua modules and compiler headroom

`main.lua` delegates LÖVE callbacks and diagnostic modes to `src/bootstrap.lua`.
`src/app.lua` assembles the components in `src/runtime/` around one private live
context. Separate folders now own world interactions, movement, deliveries,
relocation, warehouse operations and employees; office and machine screens;
protocol validation, multiplayer sessions and direct transport; fleet operations;
job services; UPnP discovery; and save validation and migration. Their original
public module APIs remain the entry points. Office and cutter factories create a
fresh context for each instance, so guest consoles and installed machines keep
independent state.

The compiler audit checks actual compiled functions, including nested closures,
without executing game source or accessing saves. Run
`python tools/audit_lua_limits.py` with the installed LÖVE LuaJIT library, or pass
`--library` / `LUAJIT_LIBRARY`. Its JSON report defaults to
`output/lua-module-audit/limits.json`. The project budgets are **180 stack slots**
and **45 captured variables** per function, below LuaJIT's
[200-local, 250-slot and 60-upvalue limits](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_def.h).
`src/tests/lua_limits_test.lua` enforces the same budgets in the full engine smoke
suite. The largest integration and network test functions are divided into
scenario modules, retaining their original assertions and invocation state.

For new systems, add a component to the appropriate folder and wire it through
the owning module. Keep mutable shared bindings in that owner's context instead
of copying them into component-local variables. Keep module installation in
dependency order; forward callbacks may be registered before their implementations
are installed, but must be invoked after initialization. Run the compiler guard,
desktop/mobile smoke suites, and package checks after changing those boundaries.

The 2026-10-07 audit found an office-screen compiler failure above the captured
variable limit, plus 180 app stack slots and 50 app captured variables. After
extraction, the app components peak at 29 slots and five captures. Entry files
now assemble their systems rather than carrying their implementations:

| Entry module | Original lines | Assembly lines | Component slots / captures |
| --- | ---: | ---: | ---: |
| `src/app.lua` | 4,730 | 34 | 29 / 5 |
| `src/screens/computer_screen.lua` | 2,964 | 24 | 49 / 3 |
| `src/net/protocol.lua` | 2,833 | 17 | 31 / 1 |
| `src/net/session.lua` | 2,900 | 16 | 30 / 4 |
| `src/world.lua` | 2,500 | 18 | 34 / 6 |
| `src/save_schema.lua` | 1,530 | 13 | 27 / 1 |

The final audit compiles 477 source files and 6,606 functions; production peaks
are 61 slots and 30 captures. All source files match the generated `.love` package
byte for byte, and 19 auditor/packaging tests pass. Strict gameplay checks retain
one existing warehouse forklift-route failure. The same route fails at the same
position with the pre-extraction world code. Review-only continuation runs pass
4,863 other checks and three draw frames in each of desktop and forced-mobile
modes; they record that failure and leave the shipped suite strict. Audit data,
package validation, and the baseline comparison are in `output/lua-module-audit/`.

## Performance measurements

`tools/run_performance_probe.ps1 -Label review` runs the real LÖVE app with a
fresh test identity and an output-local save directory. It measures startup,
screen changes, rendering, updates, populated saves and worker routes, and counts
image loads and file operations. Reports are written under `output/performance/`.
Set `PICTURE_SHOP_MOBILE=1` for the 1600×720 touch layout. Measurements cover CPU
work and render submission on this Windows machine, rather than Android hardware
or completed GPU frame time.

The 2026-10-07 comparison used 80 job records and 200 emails for its populated
shop. Before/after reports are in `output/performance/before/measurements.json`
and `output/performance/after/measurements.json`:

| Operation | Before | After |
| --- | ---: | ---: |
| Cutter → options → cutter images, repeated | 115 ms | 0.072 ms after first load |
| Press → world → press images, repeated | 133 ms | 0.026 ms after first load |
| Player images through a brief menu | 9.0 ms | 0.010 ms after first load |
| Populated save commit | 44.0 ms | approximately 14 ms |
| Title render with populated slot | 3.18 ms / 180 save reads | 0.060 ms / 1 save read |
| Worker search with blocked destination | 2.69 ms | below 0.01 ms |

Image packs still unload from the active screen API; their inactive textures use
a 32 MiB screen cache, a 16 MiB character cache and a 64 MiB warehouse cache,
expire after 20 seconds, and
clear when the app loses focus. Character eviction favors the poses most recently
drawn. The warehouse cache retires artwork unused by the current scene. Cycling
all parked/driving forklift views retained 90 MiB before this change and 72 MiB
afterward, with no additional image uploads; repeated driving views reload no
textures. Idle expiry and loss of focus release the unused views. First-time
asset decoding remains synchronous: the measured cold cutter
and press loads are approximately 106 and 133 ms, and app/asset startup remains
about 0.52 seconds. Asset dimensions, authored frames and rendering quality are
unchanged. Active textures and inactive cache bytes are reported separately.

Save commits validate the new payload, verify written/promoted bytes, and preserve
the existing recovery-file behavior. Only an exact match with a previously
validated primary skips repeated parsing; external edits and other save identities
still require full checks. This cache holds at most 2 MiB per slot. Simulation
changes in one update request one final commit; explicit commands, focus changes
and shutdown retain immediate saves. The title listing refreshes after local save
changes, identity changes, and every half-second for external edits. Hosts waiting
for guests defer snapshot construction and encoding while continuing simulation,
admission and workshop servicing. Worker routes reject blocked goals before
searching and build their waypoint lists in linear time.

The performance focus (`PICTURE_SHOP_SMOKE_FOCUS=performance`) passes 2,323 checks
plus three draw frames in desktop and forced-mobile layouts. It covers short save
writes, external corruption and recovery, bounded texture eviction, title refresh,
simultaneous simulation saves, worker collision/path traversal, multiplayer shop
updates and guest work. All 479 source files compile within the Lua budgets; 19
compiler/package tests pass. Strict full-suite validation currently stops at
`breakroom_seat_points_are_mirrored`: the warehouse redraw moved the left/right
seat coordinates to 95/865 while that test still expects 82/878. The performance
changes do not alter those coordinates or suppress the strict assertion. An
extended forklift-presentation check also reports stale lift-height expectations
after the rack redraw; it remains in the full suite. Packaging now includes the
current rack/breakroom art and excludes their superseded packaged versions.

## Engine smoke tests

The hidden LÖVE smoke run uses the isolated `the-picture-shop-smoke` save identity. It never reads or writes the player's normal save directory. To use a fresh profile without touching earlier test saves, set `PICTURE_SHOP_TEST_IDENTITY` to a unique name beginning `the-picture-shop-test-`; that override is accepted only in smoke mode.

`RUN_SPRITE_MOTION_TEST.bat` uses that same isolated identity and smoke suite, then opens a visible motion lab. Use Left/Right to switch characters, Space to pause on a frame, and Esc to close. Visitors and the player show all eight directions together: enlarged walking poses use distance timing, while matching idle poses show actual shop size and brief blinks. Older auxiliary character actions retain the raw/normalized comparison.

The lab also covers employees and technicians. Tab switches to individual action contact sheets; Up/Down selects an action. `tools/run_animation_review.ps1` captures the paired local/remote eight-frame high-five, employee directions/work/break poses, technician idles and north/south/east walks through host/interpolated guest poses at desktop and phone sizes. The `animation` smoke focus covers movement, character timing, visitors, technician wire/presentation, pallet-jack motion, title animation, mechanic work and world layers. See `docs/animation_overhaul.md` for source provenance, rebuild steps, evidence and the remaining active goal.

The completed visitor pack covers the dragon, fox and tabby clients plus the tan-cardigan, blue-shirt and green-blazer cat salespeople. Five authored views and deliberate western mirrors give every design eight directions, an eight-frame forward walk loop and two-frame matching idles. Suppliers stand while waiting; seated clients keep the existing lounge poses. Walk phase follows achieved path distance, including turns, and freezes during courtesy stops. LAN snapshots already carry that distance and facing.

Immutable imagegen masters and generation prompts are in `assets/source/visitor-motion-v1/source-manifest.json`; the initial dragon idle record explicitly labels its abbreviated prompt as a summary. Superseded attempts stay separate from selected assets. `tools/build_visitor_character_assets.py` previews only the selected sheets, preserves one scale per loop and the authored body bob, then installs the reviewed pack with `--apply`. It emits static anchors/alpha bounds, preserving seated/use actions and avoiding runtime pixel scans. Only explicitly reviewed adjacent-cell fragments receive the larger detached-component cleanup. The body stays within six source pixels of its axis and the foot baseline within one pixel; the wider alpha-box-center allowance in `character-motion/*.json` accommodates tails crossing behind the legs.

Run `tools/run_visitor_motion_preview.ps1` for an isolated LÖVE check using the actual character loader and lab. The runner creates a fresh test identity and starts `tools/visitor_motion_preview/main.lua` from the game project root. This mode bypasses the game and smoke suite and writes 96 captures covering six designs, eight walk phases, all eight directions, and desktop/landscape-phone viewports, with no game-save access. Its report also records peak character texture memory. `tools/build_visitor_gait_guides.py` produces the engineering pose references; those guides are never runtime art.

The completed pack passes six strict motion audits, 593 asset checks, and 3,887 full game checks in each of desktop and forced-mobile modes. The 96-capture rendering check passes with peak character textures of 50 MiB.

## Layers

The pallet jack motion pack is rebuilt with `tools/build_pallet_jack_motion_v2.py`.
Its immutable image-generation masters and reference records live in
`assets/source/pallet-jack-motion-v2/`; runtime art lives in the corresponding
generated directory. The jack uses 32 authored turning views, and the rabbit uses
16 pushing drawings per authored direction plus planted directional idles. Each
eight-pose gait is subdivided into two drawings per pose, with an 80-pixel cycle.
The grip is shared by the jack and worker; turns use a bounded continuous heading,
while steps use collision-resolved jack distance and freeze against walls.

`character-motion/rabbit-pallet-jack.json` audits both the full 16-frame strips and
eight-pose core previews, matching the skill auditor's eight-phase contract. Run
the build before this audit because its core previews are staged under `output/`.
`tools/run_pallet_jack_preview.ps1` runs focused motion/ownership/control checks
and captures 32 empty/loaded desktop and phone scenes through the real renderer.
Set `PICTURE_SHOP_PALLET_JACK_MOVIE=1` for the 120-frame in-engine turning/gait
capture. Both modes use isolated test identities and never access normal saves.

`tools/run_pallet_jack_audit.ps1` runs the `pallet-jack` smoke focus, including
pickup reservations and stacked loads, operator ownership, local and network
machine relocation, client turn/stride continuity, storage, protocol/session
checks, and save round trips. It redirects test saves into
`output/pallet-jack-audit/appdata` with a fresh identity and writes its report to
`output/pallet-jack-audit/smoke-report.rpt`.

- `src/tests/guest_job_journey_test.lua` drives the shared guest computer, cutter, wrapper and truck
  GUIs through real Session transport and the application's production authority callbacks. It covers
  typed estimates and delayed acceptance, inbound stock, a deliberately spoiled 500-sheet lift and exact
  replacement, disconnect during a cut, fresh-lease recovery, wrapping, spoil-bill payment, pickup and
  final payment. Repeated clicks and application-level replays cannot duplicate the financial/stock
  outcomes. Host/guest totals converge and the completed state survives a serialized offline-load
  round trip. Intake, worker navigation and inbound dock/staging positions are fixtures; pickup uses
  the real world scheduler. The second scenario uses `src/tests/support/guest_print_production.lua`
  for a two-color job: cut 500 supplied sheets, make both plates through all four visible processing
  steps, complete all six setup games per color, proof/verify/approve, print, disconnect/reconnect during
  production, wash/unload, wait for drying, reload the second color, and deliver exactly 450 finished
  copies. Duplicate requests must not double-consume plate materials, proofs, ink, packing or wash.
  Installed equipment and starting supplies are fixtures; plate timing uses a fixed clock while the
  real host computes scores. Desktop and forced-mobile smoke each pass 2,285 checks, including the
  original 53 cutting-journey checks and 197 printing-journey checks. Neither is physical acceptance.
- `src/tests/network_protocol_test.lua` checks that every visible press-setup control encodes and
  decodes inside the existing packet ceiling. This catches stale network allowlists such as the old
  feeder actions that rejected FAN + LOAD and the separate suction/air adjustment buttons.
- `src/tests/shared_gui_test.lua` exercises the production `useHostLayout` guest route: all nine
  computer pages are pixel-compared with host instances; machine/service/press/phone/vendor/reception/
  truck pages render with their real asset packs. Visible controls send bounded intent without modifying
  guest stock, money, or paper. Preview PNGs named `gui-parity-*.png` are written only to the isolated
  smoke save directory. The earlier v16 GUI-only baseline passed 2,035 checks in each mode.
- `src/tests/office_phone_session_test.lua` uses the real Session and impairment harness: phone lease
  contention, answer/order/dismiss, duplicate delivery, stale call IDs, host range checks, cart prices,
  atomic failed checkout, bill payments, delayed email estimates, declines, service archiving and typed
  promotions. Forged prices/quantities and oversized/unknown intents are rejected. No physical devices
  or player saves are involved.
- `src/tests/cutter_presentation_test.lua` compares host/guest blade and paper-transfer frames using
  the same artwork, checks host-bound keyboard intent and invisible-hitbox regressions, validates
  interpolation across per-frame runtime revisions, and proves drawing cannot mutate the machine or
  mirrored ticket. It writes `cutter-guest-preview.png` and `cutter-guest-unloaded-preview.png` only in
  the isolated smoke save directory for visual review.
- `src/tests/cut_stock_margin_test.lua` checks the one-inch minimum excess in both stock dimensions,
  all difficulty layouts and four real cuts, exact finished sizes, next-lift resets, generated offers,
  and rotated repeat orders from older tickets. The starter now supplies 17 × 12 stock for its
  8.5 × 11 target. Hard layouts leave at least 0.25 inches on each edge; the cutter draws remaining
  trim at a minimum of six scene pixels and keeps already-cut edges flush. The `cut-stock-margin`
  focus includes the job loop, cutter integration, host/guest presentation and production, progression,
  press economics, save contracts, and guest production journeys. Desktop and forced-mobile runs each
  pass 1,412 checks. Set `PICTURE_SHOP_CUT_STOCK_CAPTURE_DIR` to an existing output directory to capture
  the starter and minimum-margin hard stock at desktop and mobile scene sizes.
- `src/tests/cutter_production_session_test.lua` runs the real Session, workshop authority, remote
  controls and Machine together without device sockets. It covers loading through a completed cut,
  duplicated cut requests, next-program synchronization, stalled guest animation, an interrupted
  second cut, and actual spoiled geometry from an intentionally wrong cut. Protocol v15 validates
  the added dimension/spoil fields and keeps cutter messages inside the 1,200-byte ceiling.
- `src/tests/purchased_machine_transport_test.lua` runs actual MOVE, TURN, and PLACE controls for additional
  cutters, wrappers, and presses bought from dealers or unloaded from online deliveries. It checks movement,
  original-unit isolation, mobile host/guest buttons, placement, save/reload, loaded/occupied machines, ownership,
  sale/operation blocking, doorway blocking, and disconnect recovery. `machine_relocation_session_test.lua` also
  repeats the guest session journey for a purchased cutter, with duplicate requests and overlapping durable saves.
  The `machine-transport` focus includes fleet, placement, pallet-jack, save, authority, session, and wire-protocol
  checks. Desktop and forced-mobile runs each pass 886 checks; the broader domain run passes 2,204 checks before
  the existing camera-edge follow check fails. Set `PICTURE_SHOP_MACHINE_TRANSPORT_CAPTURE_DIR` to an existing
  directory for live carrying/placed captures.

- `src/smoke.lua` owns reporting, the final three-frame render gate, and shared engine integration setup.
- `src/tests/lan_discovery_test.lua`, `src/tests/lan_reconnect_test.lua`, and
  `src/tests/lan_reconnect_session_test.lua` cover bounded address-hint discovery, retry/backoff/cancel state,
  and a fresh authoritative session generation after disconnect.
- `tools/tests/test_lan_device_acceptance_preflight.py` keeps the physical-test installer in-place,
  save-preserving, exact-APK-bound, and unable to turn a launch request into implicit install authority.
- `src/tests/asset_pack_test.lua` checks PNG header contracts, precomputed anchors, and pack loading/release.
- `src/tests/sound_test.lua` checks the complete audio catalog, physical-action transition cues, payment
  de-duplication, and ownership of persistent warehouse and press loops.
- `src/tests/pallet_state_test.lua` checks legal ownership transitions without rendering.
- `src/tests/save_contract_test.lua` checks exact defaults, nested validation, and a focused round trip.
- `src/tests/input_status_test.lua` checks Back/Escape parity and office projections.
- `src/tests/machine_fleet_test.lua` checks condition, maintenance, online machine-order reservation, dedicated
  flatbed scheduling, player unloading, ownership transfer, technician NPC completion, physical maintenance-kit
  consumption/despawn, and empty-truck release.
- `src/tests/job_loop_integration_test.lua` owns the accept-to-payment end-to-end workflow.
- `src/tests/cutter_integration_test.lua` owns guarded cutting, multi-lift production, physical staging, safe output, and pallet ownership scenarios.
- `src/tests/windmill_integration_test.lua` owns client-art verification, physical proof sheets, exact ordered-copy targets, spoilage allowance, multicolor pass state, wash-up, and press output.
- `src/tests/press_economics_test.lua` owns structured print orders, ordered-versus-supplied quoting, print-offer cadence, and repeat/promotion preservation.
- `src/tests/save_integration_test.lua` owns migration, recovery, validation, and all-slot scenarios.
- `src/tests/ui_integration_test.lua` owns title controls, cutter/wrapper/Windmill relocation, and the live
  mouse/keyboard warehouse journey. The core smoke suite also verifies delayed grouped supply manifests.
- `src/tests/audit_coverage.lua` maps every fixed P0, P1, and P2 audit finding to required named checks. The run fails if a mapped regression disappears or is renamed without updating the manifest.
- `src/tests/multiplayer_impairment_test.lua` runs one host and three clients through a deterministic,
  test-only packet lab. It covers unreliable loss, delayed reordering, duplication, malformed bursts larger
  than the 64-event frame budget, and peer-scoped failure without opening real sockets or changing protocol v14.
  Host intake defaults to `enet_round_robin`, matching ENet's peer dispatch and the Direct Composite link
  rotation while retaining FIFO order inside each peer. `adversarial_fifo` remains available for tests that
  explicitly need a transport with one global queue. Automatic malformed/forbidden replies share a one-second
  per-connection limit so an invalid burst cannot create a reliable response burst.
  Delay controls advance explicit packet-ordering steps; timeout tests must separately advance their injected
  Session clock. Reliable traffic remains ordered and cannot be dropped by this Session-layer lab.
- `src/tests/multiplayer_soak_test.lua` rotates nine disconnect/rejoin cycles across all three guest slots.
  Every cycle combines a full 64-packet malformed burst, quiet-peer liveness, delayed stale-generation input,
  a fresh connection, and healthy traffic from every worker. It also asserts bounded admission, rejection,
  transport-generation, and queued-packet state before requiring complete teardown.
- `src/tests/multiplayer_workshop_boundary_test.lua` uses the real workshop authority at exact lease deadlines.
  It proves the current owner's valid packet is handled before timeout evaluation during another guest's full
  malformed burst, then proves malformed, wrong-session, wrong-channel, and stale-generation packets cannot
  renew ownership or transfer liveness to a replacement connection.
- `src/tests/multiplayer_workshop_reliable_test.lua` drives reliable office commands through the real workshop
  authority. It proves application replays and delayed delivery mutate once in order, an in-flight ordinary
  command blocks a second command, and a command delayed behind disconnect cannot execute against a replacement
  worker that reuses the same network slot and player ID.
- `src/tests/cutter_maintenance_authority_test.lua` exercises the host-owned cutter-service state machine:
  ordered lockout/preparation, point/tool validation, gearbox work, production interlocks, exact-once kit use
  and saving, blade service, technician scheduling, contention, disconnect rollback, and bounded remote UI intent.
- `src/tests/cutter_maintenance_session_test.lua` carries cutter-service commands through the real Session and
  impairment transport. It verifies exact-once duplicated scheduling and an ordered preparation/view-selection
  round trip in which the guest sends only bounded control choices and the host owns the resulting state.
- `src/tests/wrapper_maintenance_authority_test.lua` covers the host-owned four-component service order,
  active-target validation, miss scoring, production and relocation interlocks, exact-once kit use and saving,
  cancellation/disconnect rollback, strict packets, and the Guest Worker service controls.
- `src/tests/wrapper_maintenance_session_test.lua` completes the same service through a real impaired Session,
  duplicating a miss and the final target to prove bounded intent and exactly one durable host result.
- `src/tests/machine_relocation_authority_test.lua` drives the cutter, skid wrapper, and Windmill through
  guest-owned attachment, host motion, rotation, bounded grid placement, contention, invalid intent,
  exact-once replay, and disconnect recovery.
- `src/tests/machine_relocation_session_test.lua` carries relocation through a real impaired Session and
  proves duplicated attach/place requests save once without transmitting client coordinates.
- `src/tests/placement_precision_test.lua` checks the 8-by-6 grid, continuous touch targets, close
  pallet/machine corners for all three models, overlap and wall rejection, rotated cutter feed
  sides, edge-based wrapper/press detection, fine poses in saves, exact guest drop cells,
  changed-clearance rejection, analog precision, short-step movement, and rendered arrangements.

## Gates

### Crowded-shop performance and scaling rules (2026-10-09)

Run `tools/run_performance_probe.ps1 -Label crowd-review -TimeoutSeconds 180`.
It launches LÖVE with a fresh, private test identity under `output/performance/`,
and writes timings, texture uploads, filesystem reads/writes, and save counts to
`measurements.json`. The capacity fixture contains 14 installed machines, 80
physical job pallets, 10 employees, 80 archived jobs, and 200 archived messages.
It exercises updates, rendering, saves, dense navigation, and character actions.
The fixture passes save-schema validation before benchmarking persistence.

Measured on this Windows host (milliseconds; synthetic workload, not a phone FPS
claim):

| Work | Before | After |
| --- | ---: | ---: |
| Clear 750-unit route with 100 obstacles, mean | 0.608 | 0.008 |
| Lookup all 14 machines, mean | 0.155 | <0.001 |
| Rabbit action history, active plus cached textures | 120.5 MiB | 13 MiB |
| Crowded updates with saves, p95 | 7.221 | 5.947 |
| Crowded updates with saves, maximum | 29.739 | 19.989 |

The first three baselines are in `output/performance/crowd-before`. The save
baseline is `crowd-with-saves-valid`, after the collision/texture/fleet changes
but before checkpoint coalescing; it isolated the remaining save stalls.
`crowd-final` is the combined result. Timings vary between runs. These measurements
cover CPU update and draw submission, not GPU completion, present/vsync, or a
networked phone session. Employees exercise live shifts, idle travel, and payroll;
this is not a claim that ten simultaneous production/transport jobs were measured.

#### Implemented ownership and lifetime rules

- **Fleet:** normalize at explicit repair/load boundaries and collection changes.
  Runtime reads use a weak-key cache and an ID index. Buying, selling, loading,
  delivery insertion, and array replacement invalidate through identity/length
  checks. Code performing arbitrary in-place structural edits must call
  `Fleet.ensure(state)`. Installed status and placement are read live. Never put
  these indexes in a save or multiplayer snapshot.
- **Collision:** each path search builds a 64-unit spatial grid from its current
  obstacle snapshot when there are at least 16 obstacles. Point/segment queries
  narrow the candidates, then retain the exact footprint and walkmask checks.
  Rebuild for the next search so moved pallets and employees cannot leave stale
  blockers. Continuous segment checks happen once; per-pixel obstacle checks are
  limited to actors escaping an initial overlap. Thin walls still block travel.
- **Pallets:** single-pallet lookup scans live owners and allocates only the result,
  rather than allocating a temporary record for every pallet on every query.
  Physical ownership and transfers retain their existing validation.
- **Animation assets:** `CharacterAssets.beginFrame/endFrame` pins every action
  actually drawn that frame, including concurrent actions of the same species.
  Unused actions enter the existing shared 16 MiB / 20-second inactive LRU.
  Visible actors and remote players using GUIs keep their required animations.
  Active textures can exceed the idle budget; they are never evicted to meet it.
- **Screen assets:** Options retains the current screen pack. It uses procedural
  UI and no longer loads title art or displaces machine textures. Ten real cutter
  → Options → cutter draw roundtrips averaged 0.56 ms each with zero decodes.
- **Persistence:** continuous employee/construction/accelerated-clock checkpoints
  coalesce at a five-second real-time interval. Durable gameplay events, explicit
  actions, focus loss, and quit still use immediate saves. Failed checkpoints keep
  their dirty flag and retry after the interval. Successful explicit saves clear
  pending checkpoints; loading another shop resets the scheduler.
  Employee GUI synchronization still marks the host shop dirty each second,
  independently of disk checkpoints; pose snapshots keep their existing cadence.
  Save encoding,
  validation, verified temporary writes, and recovery semantics are unchanged.
  An abrupt process failure can lose up to roughly five seconds of periodic
  simulation progress, rather than the previous one-second checkpoint interval.

#### Remaining stalls and the next capacity boundary

This pass bounds historical texture growth and removes repeated work; it does not
make all loading and saving asynchronous. The same probe still measures roughly
17 ms for a crowded save, 7 ms average / 10 ms p95 for a dense new route, and large
cold texture loads (about 78 ms for a new forklift view, 536 ms for a cold title).
Those are separate from the steady crowded draw submission, approximately 0.4 ms.

Before increasing employee capacity or room count, use this design for the next
stage, in priority order:

1. **Budget route planning:** give the host one shared resumable search queue,
   initially a 2 ms total planning budget per rendered frame. Keep actor movement,
   collision, machine cycles, and multiplayer input at their existing cadence.
   Stagger blocked-route retries. Version search snapshots, cancel searches after
   layout changes, and recheck every returned segment against live obstacles.
   Offscreen workers must continue completing authoritative work.
2. **Stream cold textures:** decode PNGs in a worker and upload on the graphics
   thread under a small per-frame budget (initial target 2 ms). Prefetch the next
   room and known upcoming action directions. Pin current-frame and pending-transition
   dependencies, and show a transition/loading state until mandatory assets are
   ready. Never hide multiplayer actors or substitute a wrong-facing action to
   satisfy a texture budget. Use separate measured budgets for active assets,
   decoded staging data, and inactive GPU images.
3. **Move periodic save serialization/writes off the frame:** capture an immutable,
   validated snapshot, hand it to one ordered writer, and coalesce queued older
   checkpoints. Explicit saves must flush/join that writer before reporting success.
   Preserve slot/identity isolation, verified atomic promotion, and recovery;
   a worker must never serialize mutable live state or race an explicit save.

Acceptance targets for the next stage: sustained p95 frame time below 16.7 ms on
the target hardware; no unbounded increase in resident bytes during a 20-minute
action/room loop; bounded route queues with live-obstacle rejection; and successful
save recovery under interrupted writes. Measure real production, pallet transport,
fully upgraded rooms, accelerated time, and a host with multiple guests on actual
phones before claiming that these targets have been met.

`PICTURE_SHOP_SMOKE_FOCUS=performance` includes spatial-index equivalence for mixed
footprints, thin-obstacle/escape checks, fleet mutation/snapshot invalidation,
concurrent animation residency, bounded historical action memory, and checkpoint
failure/retry checks alongside employee, machine, save, and multiplayer suites.

Run `RUN_SMOKE_TEST.bat` for domain, integration, audit-coverage, screen-pack transitions, and three-frame render checks. `tools/check_weekend_playthrough.bat` runs a focused Friday-to-Monday apartment smoke test in a separate disposable save identity. It uses the travel and home controls to eat, drink, bathe and sleep across Saturday and Sunday, then returns through the Monday travel panel. Its report and apartment captures are written to `output/weekend-playthrough/`; pass `weekend-flow` to the batch file to run related suites with results in `output/weekend-flow/`. The full smoke suite also runs this playthrough. Set `PICTURE_SHOP_SMOKE_FOCUS=employee-shifts` to run the employee, schedule, and payroll suites, or `employee-schedule` to run only the schedule suite while diagnosing worker queues and shifts. Run `python tools/asset_doctor.py --report output/asset-audit.json` for full raster decoding, alpha, dimension, 2x2 press-atlas grid, and nonempty-cell checks.

`PICTURE_SHOP_SMOKE_FOCUS=friday-closing` runs the Friday shutdown, inbound unloading, late customer pickup, employee exit, room shipping, truck authority, multiplayer session, travel, and save checks. Friday remains playable until the host chooses Go Home at the front entrance. The shutdown checklist requires employees to leave and every active truck and loading bay door to clear before travel begins.

Before regenerating or releasing audio, run
`python tools/generate_sfx.py --verify-only`. It validates all nine licensed
source recordings against `assets/audio/source_manifest.json`; generation fails
before writing cues when a source is absent or has different bytes. Android
packages must contain `assets/audio/SOURCES.md` and the manifest, and must not
contain the generated audition reel.

## Unified release gate

`RELEASE.ps1` is the authoritative release entry point. It requires a clean
`main` branch synchronized with `origin/main`, runs all automated gates, builds
and smoke-tests the Android-ready `.love` package, validates its allowlisted
contents and provenance, and writes `output/release/release-report.json`.
`RELEASE.ps1 -BuildApk` adds APK construction plus signature, application-ID,
ZIP-alignment, and native-library alignment verification. Device installation
and human playtesting are intentionally retained as manual release gates.

The Android tester-release path also requires
`output/mobile/device-tests/guest-worker-physical-acceptance.json`. The report must bind the exact clean
source commit and APK hash to three or four unique phones, include an Android-host run and at least two
phone guests, record every required Guest Worker interaction/topology/recovery check with evidence, and
carry the physical-test operator's confirmation. `tools/verify_guest_worker_physical_acceptance.py` rejects
missing, incomplete, dirty-source, stale-artifact, two-phone, or engineering-probe reports. Both
`RELEASE.ps1 -BuildApk` and direct use of `tools/assemble_tester_release.ps1` run this verifier before any
tester-download directory is assembled.

Before the LAN device checklist, `tools/prepare_lan_device_acceptance.ps1` can inventory connected phones
without installing. Its explicit `-Install -Launch` mode verifies the exact APK report, upgrades at least two
selected phones in place, and compares the pre/post save manifest so installation cannot silently clear or
change an existing slot.

Every new bug fix should add the smallest deterministic domain check possible. Add an engine integration check only when the behavior depends on LÖVE rendering, input routing, filesystem identity, scene transitions, or multiple live systems.

## Basketball presentation and controls

Run `PICTURE_SHOP_SMOKE_FOCUS=basketball` under LÖVE with a fresh disposable
`PICTURE_SHOP_TEST_IDENTITY`; add `PICTURE_SHOP_MOBILE=1` for mobile input coverage.
The focus covers trajectory and backboard collision, shot timing, mouse/touch drag
aim, generated pose gutters, actual customization rendering, flight layering,
strict network payloads, and two-room LAN ball replication. Set
`PICTURE_SHOP_BASKETBALL_CAPTURE_DIR` to an existing directory for engine captures.

On October 9, 2026, the final desktop and mobile-input runs each passed 931 checks;
the broader domain run passed 4,550 checks. Reports are in
`output/basketball-v2/desktop15.rpt`, `mobile16.rpt`, and `domain17.rpt`.
Engine captures confirmed the yellow arc at 75% opacity, restored 24-world-pixel
ball, and removal of the release bar and aiming instruction overlay. These are
desktop LÖVE runs, including simulated mobile input and LAN impairment coverage;
physical-phone acceptance remains a separate release gate.

## Critter Kombat title, selection and animation expansion

Run `PICTURE_SHOP_SMOKE_FOCUS=critter-kombat` under LÖVE with a fresh disposable
test identity, optionally adding `PICTURE_SHOP_MOBILE=1`. The focus validates
title/selection/intro routing, keyboard/mouse/multitouch input, selected characters
across rounds, six-pose attacks and variations, all 96 pose gutters, transient
save state, strict protocol 36 fields, worst-case two-room packet size, and live
LAN join/ready/rematch/cancellation behavior. Set `PICTURE_SHOP_KOMBAT_CAPTURE_DIR`
to capture title, selection, intro and combat screens.

On October 9, 2026, desktop and simulated-mobile runs each passed 823 checks
(`output/critter-kombat-v2/desktop5.rpt` and `mobile6.rpt`). The broader domain run
passed 3,432 checks before stopping at
`stock_consumption_boxed_wrap_rolls_back_film_when_carton_skid_is_stored`.
The same failure reproduced in the separate `warehouse-rooms` focus without the
Critter Kombat suite: current wrapper changes reject inaccessible carton stock
at start, while that test expects rejection at completion. Reports are
`domain7.rpt` and `rooms8.rpt` in the same directory. This unrelated wrapper/test
work was not modified as part of the combat change. Physical-device acceptance
remains separate from these desktop LÖVE runs.

## Critter Kombat jumping and configurable controls

The `critter-kombat` focus also checks crossovers in both directions at 30, 60
and 120 fps, ground/air body collision, correct landing separation, facing,
guarding and retaliation after swapping sides, held-jump edge behavior, and live
LAN jump/facing replication. Controls tests exercise every action on keyboard,
mouse and simulated gamepad input, signed stick/trigger bindings, deadzones,
duplicate-binding transfer, persistence and corrupt-file fallback, controller
menu navigation and capture cancellation, mouse/multitouch layout dragging,
size/opacity/visibility, save failure and discard behavior, and focus recovery.
The separate `critter-kombat-controls` focus runs input/settings checks without
building a shop or rendering the fighter atlases.

On October 9, 2026, the final desktop and simulated-mobile runs each passed 914
checks (`output/critter-kombat-controls/desktop7.rpt` and `mobile8.rpt`). Captures
in that directory include the four device tabs and local/LAN jump crossovers.
Controller events and state were simulated; physical controller and phone
acceptance are still separate. Preferences are tested through an isolated
filesystem adapter and fresh LÖVE identities, leaving real saves untouched.

The broader run passed 3,521 checks before the existing stored-carton wrapping
test failure described above (`output/critter-kombat-controls/domain4.rpt`).

## Returning-client promotion email

Set `PICTURE_SHOP_SMOKE_FOCUS=promotion-email` with a fresh disposable
`PICTURE_SHOP_TEST_IDENTITY` to check the 10% offer composer, text input and
send limit, delayed client replies, old silent offers, estimates, and save
contracts. Add `PICTURE_SHOP_MOBILE=1` for simulated mobile input. A sent offer
gets a reply after 12 shop hours; slower seasons reduce the chance that the
reply includes a new job. `PICTURE_SHOP_COMPUTER_ESTIMATING_PREVIEW=1` with
`PICTURE_SHOP_SMOKE_SCREENSHOT=1` captures the discounted estimate layout.

## Apartment and bike HUD, visibility and camera lock

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/review_scene_hud.ps1`
and repeat with `-Mobile`. Each uses a fresh disposable LÖVE identity and writes
native captures and its report to `output/scene-hud-review/desktop` or `mobile`.
The November 4, 2026 desktop and simulated-mobile runs each pass 96 checks.
Coverage includes live weekday/date/time, the 12/24-hour preference, Home and
Shop balances, and layout at 640×480, 960×678 and 1280×880.

The world HUD has Hide/Show HUD (F9) and riding has Lock Cam/Unlock (F8) in
first person and fixed third person. HUD visibility persists in local settings;
the camera lock is local session state. Tests use actual App callbacks to check
touch restoration, hidden menu hit targets, active drag cancellation, one- and
two-finger gestures, mouse orbit/pan, wheel zoom, keyboard recenter/zoom, polled
look input, held throttle, steering, releases and remapped mouse bike actions.
Follow mode remains automatic and excludes the lock button. Captures also check
the physical first-person cockpit remains visible with the HUD hidden. Mobile
input is simulated in desktop LÖVE; this does not constitute a physical-phone run.

## Procedural commute grass

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/commute_lab/review_grass.ps1`
for placement, geometry, incremental streaming, resource limits, native wind/color
pixels and generated-town camera captures. Use `-UnitOnly` to omit the town review.
The November 4, 2026 review passes 64 checks; captures and timing evidence are in
`output/grass-review`. The existing desktop and simulated-mobile App HUD/camera
reviews also pass 96 checks each with grass integrated. See
[commute_grass.md](commute_grass.md) for source provenance, placement rules,
performance budgets and verification scope.
