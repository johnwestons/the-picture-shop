# Apartment and Ride Home completion goal

User-directed integration goal, November 2, 2026. This supersedes the older prohibition
on procedural building geometry in the commute concept document.

## Accepted scope and order

1. Detailed procedural structures, with textures deferred. Design geometry in
   local coordinates; placement, rotation, dimensions, entrances, foundation,
   collision and vegetation clearance must share the same data.
2. Player-selectable numeric town seeds at new-game creation, a preview and named
   reusable presets, a terrain/topography underlay toggle, and a frozen town definition saved for the whole playthrough.
   Old saves retain their original town; multiplayer uses the host's saved town.
3. Complete and enable the apartment/travel playthrough, including all apartment
   destinations, explicit gear changes and dismounting, save/load and multiplayer.
4. Motorcycle suspension/airborne motion, gravity and landings; raise the stock
   road cap to 45 mph, reduce the off-road penalty, and support mechanic upgrades
   reaching 75 mph with boost at the top tier.
5. Required missing apartment art, performance/regression checks and end-to-end
   acceptance; prepare/run physical-device checks when available.

Required town buildings: Picture Shop; four selectable apartment buildings;
mechanic; small grocery; post office; modest police station; fire station; diner;
coffee shop; general store; and additional apartment-style residences for townspeople.

Architecture should draw on southeastern North American small towns: brick
storefronts, human-scale civic buildings, deep porches/awnings, parapets/cornices,
pitched roofs and practical service buildings. Textures remain explicitly deferred.

Town layouts must support future shapes, dimensions and generator versions.
Geometry cannot depend on the current world coordinates. Saved games and presets
must preserve the generated layout rather than silently rerolling after an update.

## Initial implementation checkpoint (generator version 1)

The game now creates a seeded town during new-game setup, previews and saves named
local presets, and persists the complete town specification: sampled relief,
roads, bridge flags, placements, dimensions, and local building designs. Loading
a game or preset does not rerun the generator. Disk serialization preserves the
full precision of terrain heights. Multiplayer carries the host's same definition.

The preview's Terrain button (keyboard T) toggles water, shaded elevation and
2m contour bands beneath the roads and buildings. Sampling uses the saved world,
including road and foundation grading. Toggling changes no playthrough data.
Tap a building to identify it. New maps currently use the version-1 512m town
boundary and shared inland river corridor; road bends, home assignments, service
lots, building sizes, relief and vegetation vary with the seed. Factory interfaces
keep placement, geometry, roads and boundaries separate for later layout versions.

All 16 required buildings use geometry, including windows, frames, awnings,
cornices, roofs, civic entrances and service bays. Textures remain deferred.
Building collision, entrance, foundation, vegetation exclusion and rendering share
one rotated/scaled site definition. The bridge has a solid deck, parapets and piers.

Travel is enabled by default (PICTURE_SHOP_COMMUTE=0 retains the explicit legacy
test path). Routes, doors, parking and recovery follow the saved town. Motorcycle
suspension supports airborne motion and gravity, with safe stopped/grounded
dismounts. Dirt retains 82% of the road speed limit. The stock road cap is 45 mph;
three sequential garage upgrades raise the boosted maximum to 60, 70 and 75 mph.
Purchases use household funds and host-side rider/door/revision
checks, and persist per resident.

## Initial validation and remaining acceptance

- Generation: 100 seeds, 16 buildings each; 237,984 road centerline samples,
  475,968 lane-edge samples, 33,600 entrance corridor samples and 1,600 connected
  routes passed. Four-rider parking now uses each building's local orientation.
- New-game seed/preset and terrain-toggle engine checks passed; both preview modes
  were captured under output/town-integration-tests/town-ui-2.
- Final seeded ride rendering (seed 712345, RTX 3050, 1280×880): p95 4.38–10.04ms
  across outside/first-person stationary, moving, rotating and zooming scenarios.
  One of 1,500 frames exceeded 16.7ms (20.65ms); the other scenarios had maxima
  below 13.25ms. Initial renderer construction was 480ms and first-person
  initialization 52.43ms; actual play prepares both behind a visible loading frame.
  Evidence: output/performance/town-712345-final/measurements.json.
- Frozen-town snapshot pipeline: 4.49ms mean/5.54ms p95; crowded 80-job,
  14-machine, 10-employee state: 11.93/14.25ms and 304,877 encoded bytes,
  within current reliable packet and entry limits. These are desktop Lua timings,
  separate from graphics frame measurements.
- All four apartments passed the seeded end-to-end journey suite (seed 712345):
  140 journey checks plus the final render check, eight physical motorcycle
  routes, parking, dismounting and walks to the registered building doors. Midride,
  apartment and returned-shop reloads preserve the exact frozen town; gear changes,
  an actual apartment routine, the held weekend clock and Friday-payment replay
  protection also passed. Evidence: output/town-integration-tests/
  apartment-journey-runtime-2/report.rpt and 12 captured exterior/interior frames.
- Final packaged suites passed 9,424 checks each in desktop and mobile modes,
  with separate fresh test profiles and working directories outside the source
  checkout. The packaged all-apartment journey also passed all 141 checks. The seeded host/guest commute protocol suite
  passed 63 checks, including shared frozen town, a real garage purchase, replay
  rejection and no duplicate debit. Four-rider parking passed 6,400 placements
  across 100 seeds. Packaged builds and physical-device acceptance are checked
  separately from source-only smoke tests. The final suite includes 17 actual
  touch-command checks for gear, mounting, ignition, dismounting and removal.
  A 1600×720 PC render also verified the visible gear button and its disabled
  changing-gear state, using the actual packaged runtime and touch handler.
- Household activity art now decodes off-thread through the existing image queue,
  uploads in 2MiB strips, and prepares every animation phase before replacing the
  ordinary actor pose. The apartment stays interactive; clocks and rewards are
  unchanged. Active local/remote families remain resident; unused families are
  evicted to a 96MiB budget, with active families allowed to exceed it temporarily.
  Shared mug/bundle requests are protected when another family is evicted.
- The 22-action desktop probe passed all fixtures. After preparation, the eight
  GPU-readback frames per action peaked at 5.53ms; warm p95 values stayed at or below
  2.92ms. Managed action textures peaked at 96MiB. A food shader initially took
  23.25ms to compile; it now compiles after the visible apartment opening frame and
  survives texture eviction. The focused drink rerun peaked at 3.49ms preparing and
  2.85ms ready. Three tiny uploads during sleep were identified as the ordinary
  rabbit sit pose, not delayed household phases. Evidence:
  output/performance/home-actions-prepared-final/measurements.json and
  output/performance/home-actions-drink-sleep/measurements.json. These are desktop
  results, not phone performance claims. Thirty-five focused regressions cover
  async readiness, phase completeness, shared requests, eviction and shader reuse.
- Cold furniture loading remains separate: the focused first-room baseline
  observed a 33.7ms synchronous laptop texture load. Existing furniture rendering
  is unchanged; physical-device frame and memory checks remain necessary.
- Apartment routines, seated/sleep poses, held props and bathroom privacy are
  integrated. Dedicated TV/sleep transition cycles, distinct cereal/pizza/takeout
  props, non-rabbit routine coverage and more dressing directions remain art polish.
  Prepare/change currently combine existing work poses with registered props.
- Physical-device testing was stopped at the user's request when the phone was
  needed elsewhere. On Samsung SM-S938U / Android 17, the terrain toggle, named
  preset save, reroll and reload worked. Corrected disposable fixture saves loaded
  as active shops. Native presentation timing measured only the title screen
  (about 116 FPS); this is not Android riding or apartment FPS acceptance.
- Android 77, still on that phone, is the preliminary test build. Device and
  isolated packaged-PC testing exposed omitted commute terrain/art and a
  staging-only art registration dependency. Final Android 78 packages those
  assets and fixes default touch gear access and keyboard focus synchronization.
  The signed debug APK passed native, packaging, signing, permission and 16KB
  compatibility audits; its embedded archive matches the tested package exactly.
  Its final installation, gameplay frame timing and thermal checks await the next
  phone session; no device commands were issued after testing was withdrawn.


Future generator/terrain-rule changes must retain the saved version's interpretation
or explicitly migrate it; do not silently regenerate an existing playthrough.

## Town variety, weekday outings and mechanic interior follow-up

Newly generated towns now use generator version 2. A connected randomized road
graph changes neighborhood spacing, orientation, branches and loops. River bends
and tributaries, lakes, relief and vegetation vary independently. The 16 required
sites still share the placement, road grading, collision and entrance definitions.
Roads use linear segments at bridge and driveway junctions to avoid spline
backtracking. Version-0 and version-1 playthroughs and presets keep their original
interpretation; loading never rerolls them. Regenerate a seed in new-game setup
to create a version-2 town. The current map boundary remains 512m.

Version-2 physical validation passed 1,000 seeds with no failed routes or
placements. The detailed 100-seed sweep checked 420,024 road center samples,
840,048 lane edges, 33,600 door approaches, 1,600 connected routes and 6,400 rider
parking positions. Fifty committed town regression checks include the formerly
failing bridge/driveway seeds. The four-apartment journey also passes on version 2.
See `output/town-v2/seed-comparison.png` for six distinct layouts.

The warehouse front entrance now offers **Explore Town** on any day. An ordinary
outing preserves the normal business clock, can return through the origin door,
and can visit the apartment before returning to work. It does not manufacture a
Friday payment or force a weekend phase. Visit purpose and location survive
reloads; actual weekend closing, payroll and reopening retain their domain rules.
Thirty-eight actual runtime checks cover the weekday round trip, exact frozen
town reloads, parking/gear/doors, clock advancement and an apartment activity.
Additional pure and network-session checks cover ordinary and weekly travel.

When all humans are outside the warehouse, existing authoritative services run
at a bounded cadence. Workers still need their jobs, materials and equipment;
production, delivery and payroll use the existing rules. Any human remaining in
the shop retains full cadence. The 60-second production fixture made 82% fewer
world-service calls and used about 55% less mean update CPU time, with matching
final inventory, cash, wages and calendar. Its first finished cutter job arrived
0.67 seconds later. These are CPU update measurements, not rendered FPS, and
apply to this fixture. Forty-two focused background checks passed; details and
reproduction commands are in `docs/performance_audit_20261102.md`.

WrenchWorks now has a customer interior adapted from the explicitly approved
Majic Blue Mechanics workshop. The copied backdrop and mechanic animations are
registered under `assets/generated/mechanic-shop-v1`, with source hashes and
provenance. The reference project is unchanged. Furniture-aware navigation,
counter/bay interactions and touch buttons lead to a three-kit catalog, explicit
price confirmation, short installation presentation and receipt. Purchases charge
household funds once and persist the resident and motorcycle upgrade. An exact
expected bike level protects against replay without invalidating the quote when
the ordinary household clock advances. Guests wait for authoritative replicated
installation rather than treating a transport acknowledgement as payment success.
The rider and bike retain their authoritative exterior parking position while
this local interior view is open.

Twenty-four interior checks, 26 shop integration checks and 11 actual engine checks
passed, including a real $350 purchase, saved funds/upgrade and unchanged parking.
The 640x480 and 960x678 interior, catalog, confirmation, installation and receipt
were visually inspected in `output/mechanic-interior/runtime-4`.

The broad source suites passed 9,598 checks each in desktop and forced-mobile
control modes on PC (`output/town-outings/full-desktop-3` and `full-mobile-1`).
Final review then found and fixed local interior walking behind the options menu;
four new regression checks reproduced that issue before the guard. All 50 focused
mechanic domain checks pass on the final source. Background fixture cleanup now
restores its private scene cache so later menu tests remain isolated.

The final version-2 seed-1 graphics probe includes six bridges and 435,804
structure vertices. All 2,220 measured ride/zoom/orbit/bridge frames stayed below
16.67ms; worst scenario p95 was 10.43ms and maximum 16.65ms. These are PC timings
with vsync disabled and GPU completion checked, not phone or physical display FPS.
An instant move to an uncached, wide bridge view required 780 updates (6.20 seconds
uncapped, about 13 seconds at 60 updates/second) to fill its terrain queue. Frames
continued rendering during preparation; fixed views then stayed fully prepared.
Cold renderer and first-person initialization remain behind the visible loading
screen. See the final seed-1 probe in the performance audit for detailed limits.

The standalone `.love` package passed all 61 final mechanic checks (50 domain and
11 actual service/render checks) from an isolated working directory and fresh
test profile. Archive validation matched all 849 source Lua modules and the 18
required mechanic modules/resources, including copied artwork and navigation.
Evidence: `output/town-v2/final-package/acceptance.json`,
`archive-validation.json` and `validation/report.rpt`. No APK or device install
was made for this follow-up; the existing package version label was retained.

This follow-up is being accepted on PC. Physical phone work remains deferred at
the user's request; the earlier Android 78 artifact predates these changes.

## Resident terrain follow-up

The later terrain-loading request supersedes the progressive-fill limitation
above. Terrain now builds once into a complete one-metre surface before the
outdoor scene appears. The preparation screen reports progress and keeps riding
controls gated until ground and initial roadside scenery are ready. The same
484 tiles remain resident across camera rotations, zooms and movement; ground
does not use the old radius/cone culling or 120-frame eviction policy. Both views
submit the complete terrain, and the outside view also uses depth testing so
triangles within larger tiles occlude correctly.

The 512m map uses 285,156 vertices and about 32.11MiB of mesh/index data. Preparation
is bounded by rows with a 12ms loading budget, while ordinary ride frames perform
no terrain construction. Reused height/normal samples reduce repeated road and
relief queries. Shared tile boundaries retain identical heights, normals and
texture coordinates. A visual soil clearance envelope keeps terrain below all
overlapping road/bridge surfaces; saved towns, authoritative physics heights and
collision remain unchanged. The envelope passed 100-seed road and entrance checks.

The PC immediate-coverage probe passed 3,701 assertions across 1,830 rendered
frames, including cold camera jumps, minimum zoom/tilt, fast continuous rides,
both camera orbits and return after the former eviction interval. Every revealed
frame retained complete ground with no subsequent terrain mesh allocations.
Independent viewport-to-ground samples also remained covered. Complete terrain
preparation took 113 updates/1.389 seconds uncapped (about 1.88 seconds at 60 updates
per second), separate from renderer/art and first-person setup. Worst scenario
p95 was 9.44ms; one screenshot-readback sample took 17.35ms. Results and first/early
view captures are under `output/performance/terrain-coverage-diagnostic-2`.

Both full source suites passed 9,630 checks (desktop and forced-mobile controls).
The final Android-79 archive passed 8,475 domain checks and 189 all-apartment
journey checks, including 16 complete-terrain loading gates. It was exercised from
an isolated working directory with an explicit Windows native crypto dependency;
Lua and artwork came from the archive. At packaging, 858 production/test source
files matched the checkout apart from the generated build-version stamp.

A subsequent tests-only regression confirmed the existing safe-stop reload
semantics with real elapsed updates: rider position remained fixed throughout
loading, the calendar continued, and a guest rebind stopped only that guest while
the host kept moving. No production or protocol change was needed, and Android 79
is unchanged by these additional regression tests.

The user subsequently connected the phone for testing. Android 79 was built,
audited and installed on the Samsung SM-S938U. Only primary test saves were reset;
the three existing backup files were preserved. After unlock, loading progress
was visible, but a touch reached warehouse interaction code during the outdoor
scene and crashed before gameplay acceptance or native frame recording. The user
then took the phone away and requested PC-only testing again; all device commands
stopped. No Android gameplay FPS claim has been made. Final packaged evidence is under
`output/terrain-coverage-audit/final-acceptance.json`; install/reset evidence is
under `output/mobile/terrain-resident-device`.

The exact touch crash was reproduced through App.touchpressed on PC. The fix
keeps outdoor pointer input out of warehouse controls, consumes loading touches
before driving contacts or boost can latch, and makes an unbound warehouse
selector return no target. Ready gear, mount/dismount, cockpit, mechanic and
options paths remain available. Eighteen actual App checks passed, including
the original nil-state crash path, cross-menu releases and held boost release.
The phone's installed Android 79 predates this touch fix; a future device session
needs an updated APK before repeating mobile acceptance.

After this fix, the full desktop and forced-mobile source suites each passed
9,638 checks. A separately rebuilt standalone `.love` passed 65 focused terrain
and touch checks from an empty working directory and fresh profile. Its 857 Lua
files, three shaders and 1,141 assets matched the frozen source (with the existing
documented source exclusion and generated build stamp). Evidence:
`output/terrain-touch-crash/acceptance.json` and
`output/terrain-coverage-audit/pc-touch-fix-package/archive-validation.json`.
The package kept its development version label; no APK, installation, device
command or phone update was performed after testing was withdrawn. Terrain
rendering is unchanged by the three-file input fix, so the earlier PC coverage
and frame-time measurements still describe this renderer.

## Motorcycle paint and directional sprite follow-up

WrenchWorks offers eight paint finishes for $125 from household funds. The shop
provides a rotating sixteen-view preview, separate quote confirmation, and a
visible raccoon service animation. Its idle and wrench sprites match the Majic
Blue Mechanics originals. Paint persists with each resident through trips,
saving, reload and multiplayer rebind. The host validates the price, actual
service visit, funds and paint revision before committing a purchase.

All fourteen bike/rider pose atlases now use sixteen distinct directions.
The importer previously assumed the wrong source order, discarded useful views
from the full source sheets, and squeezed some intermediates into the wrong
bounding boxes. Explicit per-pose source maps now select the correct views.
Intermediate scaling preserves each pose's height and aspect ratio, with a safe
atlas-cell width limit. Original cardinal/diagonal frames remain byte-identical.
Only six genuinely missing turn/impact views were repaired, as authorized:
hard-left NNE and ENE, hard-right NNE, left-turn transition NNE, impact ENE and SSW.
The original source sheets remain unchanged; repaired source images and review
maps live in assets/source/commute-bike-v4-directions and
assets/staging/commute-bike-v4-directions. Missing full pose atlases report an
error rather than silently reducing direction coverage.

The renderer, first-person billboards and shop previews use the same sixteen
logical sectors. Camera-relative bank signs and first-person head-look selection
are covered by regressions. These are hand-drawn angular views, not geometrically
measured 22.5-degree renders. No left/right mirroring fills a missing bike view.

Blue in the review images is the selected cobalt paint shader, not baked paint
in a subset of sprites. Native pixel comparisons verified that selecting bronze
after blue restores the source exactly in all 224 pose/direction frames.
All 224 frames respond to paint; protected upper regions remain unchanged.
Sixty-four palette switches allocate no images or shaders. Native review also
rendered every pose in all sixteen directions and a 48-frame orbit/action loop.

Final PC acceptance used fresh disposable profiles only. Desktop and simulated
mobile-control suites each passed 9,724 checks. The actual shop purchase,
sixteen-view preview, raccoon animations, cancellation and save/reload flow passed
21 checks plus the render gate, both from source and from the standalone .love
in an empty working directory. The package contains 869 matching source/shader
files and 1,141 matching assets, apart from the documented source exclusion and
generated build stamp. All 867 Lua files compile within the project limits;
24 importer regression checks pass.

The final blue-bike riding probe passed 3,701 checks across 1,830 frames with
complete terrain and no later terrain mesh allocations. Worst scenario p95 was
8.50ms; the first visible frame peaked at 20.52ms, the sole frame above 16.67ms.
These are PC window draw/present measurements with vsync disabled. No APK,
phone installation or device command was performed.

Manifest version 8 records 224 nonempty unique frames, 112 unchanged original
frames, all source/runtime hashes and the six repaired views. The generic walking
auditor retains two nonapplicable gait-schema errors and 28 vehicle envelope
warnings; its applicable error count is zero. Evidence, native color comparisons,
motion GIF, source maps and package validation are under
output/bike-direction-reorder. Earlier eight-view review artifacts are historical
and do not describe the current renderer.

## Motorcycle traction and solid scenery follow-up — 2026-11-02

The bike now carries world-space horizontal velocity independently of its facing.
Acceleration, brakes and cornering share a limited tire-grip budget, with a smooth
one-metre shoulder transition between pavement and dirt. Steering while braking
can start a dirt slide; easing steering/braking restores grip. Air steering does
not redirect airborne momentum. Existing gears, upgrades, top speeds, suspension,
reverse and all sixteen sprite directions remain in use. Brake and slip feedback
replicate through the authoritative trip snapshot and feed grounded tire audio.

Tree trunks and central rock bodies use swept collision checks, including height
clearance for jumps. Centered impacts stop the bike and trigger the existing
impact reaction; glancing contacts remove inward velocity. Branches, shrubs and
ground clutter are passable. Collision and rendering share seeded vegetation
patches, scale and calendar lifecycle; queries do not depend on render visibility.
Save recovery relocates a bike saved inside a solid prop to safe parking.

PC acceptance passed 9,789 full-suite checks, 1,147 actual round-trip/network
checks, 208 focused checks and 49 native trip/save checks. The return-trip loading
helper now accepts the same already-complete renderer without requiring artificial
loading frames; cold-loading and full-terrain reveal assertions remain enforced.
All 870 Lua files compile within project limits. Independent stress testing passed
115,220 assertions. From 12 m/s, full braking takes 7.36 m on pavement and 11.28 m
on dirt. Across four seeds, 5,644 road-center samples were clear of solid props;
80,000 warmed collision queries generated no additional patches.

The native terrain/performance probe passed 3,701 checks across 1,830 frames:
worst scenario p95 9.17 ms, peak 19.70 ms on the first visible frame, one frame
over 16.67 ms and no uncovered terrain. These are Windows PC draw/present timings
with vsync disabled, not phone measurements. Evidence and CPU runners are under
output/bike-traction; real journey captures are under
output/bike-paint/traction-commute-final-c753ebb4cd. Tests used fresh isolated
profiles. No phone or APK work was performed.

## Motorcycle camera follow-up — 2026-11-02

Outside camera preferences now offer Fixed angle and Follow rider, selectable with
O, controller Left Shoulder, a cockpit button, or the Motorcycle Controls header.
The preference is local, saved with input settings, and honored by the game and
isolated ride preview. Fixed mode preserves manual orbit. Follow mode smooths the
shortest yaw rotation behind the bike's body, including heading wrap, sliding and
reverse. Manual orbit briefly offsets the follow view and then returns behind;
C recenters immediately. On-foot movement suspends heading-follow and dismounting
clears temporary orbit state. P switches first person while retaining the selected
outside mode. All sixteen sprite directions remain supported.

PC first-person middle/right/Alt-middle drag now uses direct mouse-look signs:
right looks right and up looks up. Outside orbit/pan signs remain consistent with
the existing controls. Projection tests cover each axis, both heading-wrap sides,
viewport scaling and production callbacks. First-person pitch also prioritizes
authoritative remote pitch/grade over a local fallback value.

PC acceptance: 9,877 full-suite checks; 213 focused camera checks including the
real app, saved preferences, actual turns, native screenshots, mode switches and
options; 131 isolated preview camera checks. All 873 Lua files compile within
project limits (11,176 functions). Native captures were visually reviewed in
output/bike-paint/camera-focus-final-7bf06f4a3d. Other evidence is in
output/motorcycle-camera and output/bike-paint/camera-desktop-full-96b02718a0.
Fresh isolated profiles were used; no phone testing or APK work was performed.
