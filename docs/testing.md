# Test layout

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

Run `RUN_SMOKE_TEST.bat` for domain, integration, audit-coverage, screen-pack transitions, and three-frame render checks. Set `PICTURE_SHOP_SMOKE_FOCUS=employee-shifts` to run the employee, schedule, and payroll suites, or `employee-schedule` to run only the schedule suite while diagnosing worker queues and shifts. Run `python tools/asset_doctor.py --report output/asset-audit.json` for full raster decoding, alpha, dimension, 2x2 press-atlas grid, and nonempty-cell checks.

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
