# Performance audit — November 2, 2026

The motorcycle slowdown was primarily repeated CPU terrain sampling in rendering, with additional scenery-generation stalls. The final measured ride scenarios fit a 60 FPS frame budget without reducing render distance, plant density, or terrain resolution.

## Findings and fixes

- Camera projection eagerly evaluated its ground-height fallback even when the caller supplied a cached height. It now samples only when a valid height is absent.
- Chunk sorting queried terrain inside its comparison function thousands of times per frame. Each chunk now caches its static center height and computes one depth key per frame.
- First-person mode generated terrain behind the camera before discarding it during drawing. Generation now uses the existing conservative visibility test.
- A terrain chunk could overrun the old 6 ms budget because the budget was checked only between complete chunks. Generation now resumes between 13-vertex rows within a 4 ms work budget; completed meshes retain identical vertices and indices. Only one partial CPU job is retained.
- Vegetation generated all missing patches synchronously. It now generates nearby patches first, at most two per frame with a 2 ms budget checked between patches. Existing patch caching and deterministic placement remain intact.
- Warehouse navigation took a square root for every possible machine contact at each search node. It now compares squared distances first. A 640-contact search fell from 13–14 ms to approximately 10 ms in isolated LuaJIT measurements; single-goal searches stayed near 4 ms. Route and collision behavior match the baseline.

## Motorcycle measurements

Windows, NVIDIA GeForce RTX 3050, LÖVE 11.5, 1280×880, vsync disabled. Both runs use the same deterministic scenario and fresh private identities. These are clean runs with the sampling profiler and screenshots disabled. Frame wall time includes update, scenery preparation, draw/flush and presentation. GPU work can queue, so these are measured frame-processing times, not a promise of identical FPS on other hardware. The normal game retains vsync.

| Scenario | Before mean, ms | After mean, ms | After p95, ms |
|---|---:|---:|---:|
| Outside, stationary | 10.62 | 3.69 | 4.85 |
| Outside, riding | 13.54 | 5.15 | 7.86 |
| Outside, zoomed out | 13.46 | 3.88 | 5.26 |
| First person, stationary | 47.53 | 3.13 | 4.52 |
| First person, riding | 56.73 | 7.83 | 9.82 |
| First person, rotating camera | 37.90 | 6.92 | 8.29 |

All 1,500 stationary, riding, zoomed and rotating-camera samples were under 16.7 ms. Across 1,706 samples including cold scenery stages, 1,705 were under that budget. The remaining 49.61 ms frame initializes first-person shaders/art for the first time. Renderer construction still takes approximately 380 ms once, mostly texture loading; this is separate from sustained gameplay. Terrain streaming is progressive and can briefly show incomplete distant scenery during initial loading or large camera changes.

The outside stationary view retains 413 terrain chunks, 1,340 props, 1,623 draw calls and the same texture memory as the baseline. Outside/first-person render radii remain 64/96. Before/after settled captures and final riding/rotation captures were inspected for missing ground, roads and scenery.

Authoritative clean reports:

- [Before](../output/performance/motorcycle-clean-before/measurements.json)
- [After](../output/performance/motorcycle-clean-after/measurements.json)
- [Final visual captures](../output/performance/motorcycle-visual-final/)

Earlier profiled runs were diagnostic only: profiling overhead and residual coasting in early fixtures inflated their steady-state numbers. They are not the basis of this comparison.

## Broader game audit

The scene probe measures real app update, drawing and window presentation, with a final GPU readback included in total series throughput. Each scene has 30 warm-up frames and 180 measured frames. The crowded fixture contains 14 machines, 80 pallets and 10 staff. Desktop is 960×678; forced-mobile layout is 1600×720 on the same Windows GPU.

| Scene | Desktop p95, ms | Mobile-layout p95, ms |
|---|---:|---:|
| crowded shop | 5.81 | 4.87 |
| crowded shop 10x clock | 7.95 | 7.60 |
| crowded office | 4.57 | 4.27 |
| cutter screen | 1.35 | 1.08 |
| furnished home | 0.50 | 0.86 |
| arcade kombat | 0.42 | 0.35 |

Every measured frame in these six scenes was below 16.7 ms, including the 10× game clock. Captures confirm the intended home and active arcade scenes were actually drawn. This is representative scene coverage, not an exhaustive device or long-session guarantee. No physical Android device was tested.

PNG decoding and periodic saves already use background workers. The existing probe deliberately disables asynchronous images for some comparison rows: those synchronous cold-load rows do not represent the normal streaming path. Separate async transition rows confirm responsive asset loading. CPU-only offscreen draw rows are also labeled separately from the new presented-frame scenes.

Final isolated broader reports:

- [Desktop](../output/performance/audit-20261102-verified/measurements.json)
- [Mobile layout](../output/performance/audit-20261102-mobile/measurements.json)
- [Navigation equivalence and timings](../output/performance/navigation-20261102/)

## Validation and reproduction

- Full desktop: 9,183 checks passed.
- Full forced-mobile layout: 9,183 checks passed.
- Commute domain: 370 checks passed, including height-sampling counts, one depth key per chunk, culling, generation budgets, exact mesh parity and deterministic foliage completion.
- Commute integration: 1,079 checks passed, including travel, multiplayer and saves.
- Lua compiler budget audit and whitespace checks passed.
- Relevant main-game test slots were reset as requested; existing backup files were retained. Probe runs used fresh workspace-local save identities.

Reports are under [output/performance/audit-20261102-tests](../output/performance/audit-20261102-tests/). An initial commute integration invocation omitted its required feature flag and was corrected; the authoritative result is commute-runtime-final.rpt.

Run the motorcycle benchmark with Node.js (the batch wrapper also locates Codex's bundled Node):

~~~bat
tools\run_commute_performance_probe.bat --output output/performance/motorcycle-review --timeout 300
~~~

Optional flags: --profile for diagnosis; --captures or --capture-only for visual inspection. Capture runs are separate from comparable timing runs. The launcher finds LÖVE in Program Files, or accepts LOVE_EXE. It creates a private save identity and enforces a timeout. Close other game/benchmark processes for comparable measurements.

The broader probe remains tools/run_performance_probe.ps1; pass -TimeoutSeconds 180 if necessary. Set PICTURE_SHOP_MOBILE=1 for the desktop mobile-layout check. Reopen RUN_MOTORCYCLE_PREVIEW.bat to use the updated source.


## Later validation: seeded town with solid procedural structures

These results extend the initial audit after the procedural building/bridge and seeded-town changes. Seed 712345 contains 16 buildings, 45 structure pieces and 379,068 cached vertices. The clean run used Windows, NVIDIA GeForce RTX 3050, OpenGL 3.3, 1280×880 and vsync off. Frame wall time includes update, preparation, drawing/flush and presentation. It does not fence every GPU frame, so these are frame-processing times, not native display FPS.

| Seeded-town scenario | Mean, ms | p95, ms | Maximum, ms |
|---|---:|---:|---:|
| Outside, stationary | 3.51 | 4.53 | 6.29 |
| Outside, riding and streaming | 7.99 | 10.04 | 20.65 |
| Outside, camera rotation | 5.05 | 8.23 | 9.64 |
| Outside, zoomed out | 3.85 | 5.38 | 6.38 |
| First person, stationary | 3.03 | 4.38 | 5.05 |
| First person, riding and streaming | 7.54 | 9.70 | 13.25 |
| First person, camera rotation | 7.42 | 8.96 | 10.45 |

Of 1,500 regular stationary/moving/rotation samples, 1,499 were below 16.7 ms. The single 20.65 ms outside-riding frame included 10.30 ms in plant preparation with no new texture uploads. The earlier isolated vegetation spike did not recur. The route advances at 18 m/s and wraps at its end; stationary stages explicitly freeze actor position and speed.

Cold renderer construction remained 480.01 ms: structures accounted for 186.05 ms and motorcycle atlases for 266.74 ms. The deliberately cold first-person stage included one 52.43 ms initialization frame. Runtime now presents a loading screen and prewarms first-person resources before riding; this relocates the work rather than eliminating its cost. Terrain and vegetation continue to fill progressively during initial views and large camera changes.

The 100-seed data stress passed road/edge collision, parking-to-door corridor and route checks: 237,984 road samples, 475,968 lane-edge samples, 33,600 door-corridor samples and 1,600 routes. A separate comparison confirmed current road support heights match the legacy road → parking-pad → foundation formula within 8.9e-16 m. The maximum 0.377 m difference from authored road heights is existing parking-pad blending, not an apron regression. Settled mechanic and fire-station outside/first-person captures show connected entrances and no missing meshes; some hillside cuts remain steep away from entrances.

Evidence:

- [Final seeded-town timings](../output/performance/town-712345-final/measurements.json)
- [100-seed stress](../output/town-generation/stress100.txt) and [grading parity](../output/town-generation/grade-pad-parity.txt)
- [Final graded-lot captures](../output/town-712345-graded-final/)

Reproduce:

    tools/run_commute_performance_probe.bat --seed 712345 --output output/performance/town-review --timeout 300

## Later validation: apartment action loading and readiness

The original furnished-home scene row did not exercise first-use action art. A separate real-app probe executes actual resident commands, with eight phase samples per action and 120 warm frames. Cold/ready phase samples include window presentation and a screenshot GPU readback on every frame; PNG encoding is outside timing. Warm samples include presentation and a final GPU readback. Ordinary room/avatar settling is recorded separately. The baseline clears public action-art caches only; OS and driver caches are uncontrolled.

The baseline covered 21 actions and found synchronous PNG loads of roughly 32–42 ms each. Laundry loaded three atlases in its first frame and additional body atlases in later phases. The revised family loader decodes asynchronously and uploads in slices, showing the ordinary avatar until all action phases are ready.

| Action | Baseline cold maximum, ms | Streamed preparation maximum, ms | Ready-phase maximum, ms |
|---|---:|---:|---:|
| Wash hands/face | 58.52 | 5.35 | 3.16 |
| Wipe surfaces | 85.70 | 5.83 | 4.03 |
| Load washer | 107.38 | 3.88 | 3.09 |
| Unload washer | 111.33 | 2.95 | 3.25 |
| Cook | 84.33 | 3.91 | 5.04 |
| Sleep on floor | 46.18 | 4.24 | 3.93 |

The revised full run passed all 22 fixtures, adding tap-water drinking: 176 ready-phase frames and 2,640 warm frames. Ready-phase maximum was 5.53 ms; warm maximum was 6.87 ms, with the worst per-action p95 at 2.91 ms. The managed action cache peaked at exactly 96 MiB, versus 208 MiB of distinct image pixels encountered across baseline families; total GPU texture memory peaked at 243.05 MiB. These are desktop results, not phone action-performance results.

A subsequent focused check validated the final food-shader loading gate: tap-water preparation maximum 3.49 ms, ready maximum 2.85 ms and warm maximum 2.35 ms. Shader creation occurs behind the apartment-opening frame. The full run's earlier 26.88 ms drinking preparation frame was traced to that shader and is superseded by the focused check.

Three small uploads after sleep readiness were identified as the generic avatar's sit-room-v1.png, not missing sleeping-action phases. Each took about 0.10–0.13 ms in the focused check, whose sleep ready-frame maximum was 3.44 ms. The probe retains those raw timings and distinguishes background avatar uploads from action-readiness failures. The household action families were ready for the sampled phases.

Remaining first-entry work is reported separately: the focused room baseline included a 39.04 ms frame, dominated by the starter laptop furniture image's 33.72 ms synchronous load. Furniture loading was outside the action-family change. No exhaustive four-resident or long-session action-cache stress is claimed.

Evidence:

- [Cold 21-action baseline](../output/performance/home-actions-final/measurements.json)
- [Prepared 22-action run](../output/performance/home-actions-prepared-final/measurements.json)
- [Final drinking/sleeping check with source-path telemetry](../output/performance/home-actions-drink-sleep/measurements.json)

Reproduce the prepared path:

    tools/run_performance_probe.ps1 -Label home-actions -HomePrewarm -TimeoutSeconds 180

Use -HomeActions instead for the resource-cache-cold comparison. The launcher creates a fresh private save identity. PICTURE_SHOP_PERFORMANCE_HOME_FILTER and PICTURE_SHOP_PERFORMANCE_HOME_APARTMENT optionally select actions and an apartment.

## Physical phone calibration — title screen only

A later read-only calibration used the Samsung SM-S938U on Android 17, build 77, after the title screen was verified healthy. This extends the earlier statement about no physical Android testing only to the title-screen calibration. It does not establish motorcycle, apartment-action or other gameplay performance on Android; the phone was subsequently disconnected.

The recorder sampled the game's native BLAST SurfaceView using SurfaceFlinger actual present-fence timestamps, rather than Java gfxinfo or CPU submission time. A 250 ms polling delay merged the 127-record histories without gaps. Android 17 layer-list wrappers were stripped while preserving the layer's sequence suffix. Timestamp ordering follows [AOSP FrameTracker](https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/services/surfaceflinger/FrameTracker.cpp).

| Healthy title-screen calibration | Result |
|---|---:|
| Display refresh period | 8.333 ms, about 120 Hz |
| Observed presentation intervals | 1,190 |
| Native presented FPS | 115.96 |
| Mean / p95 interval | 8.62 / 8.32 ms |
| p99 / maximum interval | 24.97 / 33.29 ms |
| Intervals above 16.67 ms | 18 |
| Intervals above 33.33 ms / ring-history gaps | 0 / 0 |

This is observed presentation while polling, not uninstrumented throughput. Host ADB query roundtrips averaged 50.5 ms and occurred outside the app's frame-timing calculation. The helper sends no input, launches/installs nothing and changes no device properties or profiling counters.

- [Title-only native frame report](../output/mobile/town-device-tests/title-v77-calibration-surfaceflinger.json)
- [Read-only native recorder](../tools/android_frame_probe.cjs)

When a device is available and the intended scene has independently been verified healthy:

    node tools/android_frame_probe.cjs capture <scene-label> 10


## Weekday warehouse operation while outside

The live authoritative warehouse now continues while the household explores town or visits an apartment on weekdays. When every human is outside the shop, the existing truck, pallet, visitor, technician, employee and payroll services run at a 0.1-second real-time cadence. Machine, wrapper, calendar and finance rules remain the existing domain services. Employee routes, collision, reservations and safety controls remain active; transient employee work-pose presentation is skipped until someone returns. Any human in a shop room retains the usual update cadence, and network clients never advance the authoritative simulation.

Pending work flushes before calendar-minute boundaries and return to the shop. Friday closing uses full cadence. Long live-frame intervals retain bounded clock debt instead of creating an immediate catch-up burst. Sleep acceleration waits for that debt to drain. Monday reopening consumes time only up to the reopening boundary, checkpoints the last closed interval without production or wages, then preserves later time for subsequent open-shop updates. There is no offline elapsed-time source.

The final isolated LÖVE probe uses the actual App.update path, a hired employee, a real 500-sheet cutter job and payroll. Both modes run 3,600 updates at 1/60 second, with identical starting state, ordinary clock speed and the same open-menu update path. These are CPU update timings, excluding rendering and presentation. The observed run precedes the unattended run, so the maximum includes different JIT/cache history and is not a hardware-independent guarantee.

| 60-second production fixture | Human observing shop | Everyone outside |
|---|---:|---:|
| Mean App update | 0.084 ms | 0.038 ms |
| p95 App update | 0.241 ms | 0.121 ms |
| Maximum App update | 7.968 ms | 1.090 ms |
| World service updates | 3,600 | 648 |
| First 500 finished sheets | 14.18 seconds | 14.85 seconds |
| Final cut history / completed lifts | 4 / 1 | 4 / 1 |
| Accrued wages / paid hours | 12,000 cents / 1.2 hours | 12,000 cents / 1.2 hours |

This fixture reduces mean CPU update cost by about 55% and world-service calls by 82%. Cadence adds bounded reaction latency: the measured cutter job finished 0.67 seconds later outside. Final calendar, wages, cash, inventory and stock match, and the final pending interval is applied once on return. This is one production fixture, not a claim that every shop workload has the same cost or completion delay.

All 42 focused checks pass: 29 cadence/boundary/domain checks plus 13 actual App checks covering production parity, return, guest occupancy, client authority, Monday closed-hour accounting, configured employee attendance and sleep debt. Broad-suite validation is reported separately by the main audit.

- [Final CPU measurements](../output/performance/background-warehouse-final/measurements.json)
- [42 focused checks](../output/performance/background-warehouse-final/background-checks.json)
- [Probe console](../output/performance/background-warehouse-final/console.log)
- [Production fixture](../src/tests/support/background_warehouse_fixture.lua)

Reproduce with a fresh private test identity:

    powershell -File tools/run_performance_probe.ps1 -Label background-warehouse-review -BackgroundWarehouse -TimeoutSeconds 180


## Generator version 2: presented town and bridge stress

The final PC graphics check generates seed 1 with generator version 2: 1,666 road segments, 16 buildings, six bridges, 110 bridge pieces and 435,804 total structure vertices. The densest tested bridge location has 55 nearby bridge pieces; the outside pass submitted 52 structural pieces per frame. Hardware remains Windows / NVIDIA RTX 3050 / OpenGL 3.3, 1280×880, vsync off.

Each sample draws and presents the real window. Every stage's final frame requests a screenshot readback, draining queued GPU work before stage throughput is calculated. PNG encoding occurs afterward. Frame percentiles are update/prepare/draw/present wall time; the final sample includes the readback. GPU-drained throughput includes all stage wall time through that fence. These are uncapped application throughput measurements, not physical monitor refresh or native display-FPS measurements.

| Version-2 scenario | Mean, ms | p95, ms | Max, ms | GPU-drained throughput, frames/s |
|---|---:|---:|---:|---:|
| Outside stationary | 3.40 | 4.76 | 6.71 | 279 |
| Outside riding/streaming | 8.53 | 10.43 | 16.65 | 117 |
| Outside rotation | 6.44 | 9.13 | 12.99 | 153 |
| Outside zoomed out | 4.26 | 6.04 | 7.41 | 224 |
| First-person stationary | 3.30 | 4.88 | 6.79 | 289 |
| First-person riding/streaming | 7.24 | 9.71 | 12.64 | 138 |
| First-person rotation | 7.07 | 8.43 | 15.06 | 141 |
| Dense bridge outside, settled | 3.62 | 4.81 | 7.22 | 264 |
| Dense bridge outside rotation | 3.76 | 4.76 | 7.57 | 255 |
| Dense bridge first-person, settled | 3.12 | 3.57 | 7.28 | 307 |
| Dense bridge first-person rotation | 7.24 | 8.21 | 11.51 | 138 |

All 2,220 regular ride/view samples were below 16.67ms. Bridge-specific outside CPU draw submission was at most 0.65ms at p95, including per-piece canvas/compositing calls. The added solid bridges therefore did not exhaust the 60Hz frame budget in this fixture. This is a larger, different layout with a GPU fence, not a controlled before/after comparison against the earlier seed-712345 table.

Loading remains visible and must be distinguished from settled performance:

| Preparation | Frames to complete scenery | Measured uncapped elapsed | p95 frame | Maximum frame |
|---|---:|---:|---:|---:|
| Initial exterior | 206 | 1.723 s | 11.38 ms | 13.77 ms |
| First first-person view | 112 | 0.901 s | 9.57 ms | 52.13 ms |
| Cold teleport to dense bridge, wide zoom | 780 | 6.203 s | 9.39 ms | 13.63 ms |
| Dense bridge first-person view | 157 | 1.163 s | 8.78 ms | 11.08 ms |

Cold renderer construction was 517.86ms, including 216.37ms for structures and 268.58ms for motorcycle art; town generation/world assembly took 24.39ms. The runtime's visible preparation screen and view prewarming cover constructor/first-person initialization. This benchmark deliberately measures those resources cold.

The dense-bridge teleport requested about 412 initially missing terrain chunks. The first run stopped at the probe's 600-frame readiness limit with 98 still pending; the sole retry increased that test limit and reached zero at frame 780. The queue then stayed at zero for all 180 outside steady frames and 180 outside-rotation frames. First-person readiness likewise reached zero and stayed there for 180 steady frames. This is finite progressive fill, not a held view repeatedly evicting its own required chunks.

The loading delay is a real limitation: 780 update/render steps correspond to about 13 seconds at 60 updates per second, although this uncapped run executed them in 6.20 seconds. The 152m route also deliberately wraps back to its start, creating a large position jump; moving/first-person-orbit stages may end before all newly requested distant chunks are ready. The first-person streaming capture shows missing distant terrain under already visible vegetation after that wrap. Settled bridge captures show continuous ground, solid deck and parapets. Good frame pacing does not mean every new view is immediately complete.

Evidence and reproduction:

- [Complete version-2 GPU-fenced report](../output/performance/town-v2-seed1-gpu-final-2/measurements.json)
- [Complete console and readiness progression](../output/performance/town-v2-seed1-gpu-final-2/console.log)
- [Settled exterior bridge](../output/performance/town-v2-seed1-gpu-final-2/bridge_steady-gpu-final.png)
- [Settled first-person bridge](../output/performance/town-v2-seed1-gpu-final-2/bridge_first_person_steady-gpu-final.png)
- [Partially streamed first-person view after route wrap](../output/performance/town-v2-seed1-gpu-final-2/first_person_streaming-gpu-final.png)
- [Original run stopped at the shorter readiness limit](../output/performance/town-v2-seed1-gpu-final/console.log)

    tools/run_commute_performance_probe.bat --seed 1 --gpu-fence --bridge-stress --output output/performance/town-v2-review --timeout 180


## Resident terrain: immediate coverage during jumps, zoom and riding

This follow-up supersedes the progressive terrain-fill limitation in the version-2 section above. The same seed 1 now builds the entire terrain once, at a fixed 1 m surface lattice in 24 m tiles, behind the visible preparation screen. Both camera modes submit every resident terrain tile. Camera motion no longer requests, replaces or evicts terrain meshes. Vegetation still streams separately; these results establish complete ground coverage, not instantaneous readiness of every decorative asset.

The isolated PC acceptance run used the same RTX 3050, OpenGL 3.3, 1280×880 and vsync-off configuration. It rendered 1,830 frames across ten stages without waiting for scenery readiness after initial terrain preparation: first reveal, cold camera jumps, maximum outside zoom at minimum tilt, outside tilt/orbit, 26.8 m/s riding in both views, 100° first-person lens, first-person orbit, and a return to the starting view. The 629 m warehouse–mechanic route does not wrap; each fast-ride stage covers approximately 161 m. Real rider and camera updates are included, with route position scripted for repeatability.

All 3,701 acceptance assertions passed. Every scene frame retained and submitted all 484 tiles, with zero uncovered tiles and zero new terrain/road mesh allocations after loading. Independent inverse-camera rays at the first, eighth, sixtieth and final frame of each stage found 1,130 actual ground intersections and zero uncovered points. This avoids using the renderer's own requested-tile list as the sole coverage oracle. Captures of the first reveal, early camera turns, wide views and moving views were inspected: ground and river banks remain continuous, including beneath distant vegetation.

| Initial preparation | Measured result |
|---|---:|
| World assembly | 25.91 ms |
| Renderer construction | 508.23 ms |
| View/cockpit prewarming | 54.20 ms |
| Complete terrain build | 113 steps / 1.389 s uncapped |
| Terrain loading frame mean / p95 / maximum | 12.28 / 12.48 / 15.49 ms |
| Resident tiles / vertices | 484 / 285,156 |
| Resident terrain mesh memory | 32.11 MiB |

The old dense-bridge view required 780 progressive steps, approximately 13 seconds at 60 updates per second. The replacement performs 113 steps once, approximately 1.88 seconds at 60 updates per second, before revealing the world; later view changes have no terrain-fill delay. The measured 1.389 seconds is uncapped execution time, not measured 60 Hz wall time. Constructor and view-prewarming costs are additional and remain separately reported. The fixed 1 m lattice is an explicit surface-resolution choice rather than a distance-based detail transition.

| Immediate-coverage scenario | Mean, ms | p95, ms | Maximum, ms | GPU-drained throughput, frames/s |
|---|---:|---:|---:|---:|
| Outside first reveal | 5.72 | 9.44 | 17.35 | 175 |
| Outside cold jump | 4.44 | 6.61 | 11.66 | 225 |
| Outside maximum zoom / low tilt | 3.98 | 6.07 | 7.84 | 251 |
| Outside orbit / tilt | 3.82 | 5.40 | 6.93 | 261 |
| Outside fast ride | 4.35 | 6.85 | 13.65 | 230 |
| First-person cold jump | 2.82 | 6.32 | 9.65 | 347 |
| First-person wide lens | 2.76 | 4.25 | 7.14 | 361 |
| First-person orbit | 3.48 | 5.14 | 10.42 | 287 |
| First-person fast ride | 3.96 | 6.56 | 8.57 | 252 |
| Outside revisit | 4.06 | 6.20 | 10.40 | 246 |

All stage p95 values are below 16.67 ms. Of 1,830 frames, 1,829 are below that threshold. The sole 17.3496 ms frame is the first stage's final screenshot/readback frame: presentation/readback accounts for 14.2965 ms and CPU draw submission for 2.0048 ms. It is retained in the table rather than removed as an outlier. Frame measurements include update, preparation, real drawing and presentation; selected frames force a GPU readback. PNG encoding and the independent CPU ray audit are excluded. Stage throughput drains the GPU and subtracts only that audit's measured CPU time; it is application throughput, not physical display FPS. Peak reported texture memory is 170.50 MiB, separate from terrain mesh memory.

A separate actual-app town-outing run passed 53 checks, including loading-gate coverage across five cold transitions with cancellation/restart and midride reloads. It verifies blocked movement and exterior drawing during preparation, visible terrain progress, and complete map/corner coverage on the first exterior frame. The standalone graphics probe's loading display alone is not the evidence for that production gate.

Evidence and reproduction:

- [Complete coverage and frame report](../output/performance/terrain-coverage-diagnostic-2/measurements.json)
- [Coverage console](../output/performance/terrain-coverage-diagnostic-2/console.log)
- [First exterior reveal](../output/performance/terrain-coverage-diagnostic-2/outside_first_visible-frame-1.png)
- [Immediate maximum zoom / low tilt](../output/performance/terrain-coverage-diagnostic-2/outside_max_zoom_low_tilt-frame-1.png)
- [First-person cold jump](../output/performance/terrain-coverage-diagnostic-2/first_person_cold_jump-frame-1.png)
- [First-person fast ride](../output/performance/terrain-coverage-diagnostic-2/first_person_fast_ride-frame-360.png)
- [Actual runtime loading-gate checks](../output/terrain-coverage-audit/outing-1/report.rpt)
- [Independent ray-sampler checks](../output/terrain-coverage/ray-check.txt)

    tools/run_commute_performance_probe.bat --seed 1 --coverage --output output/performance/terrain-coverage-review --timeout 180

The launcher uses a fresh private save identity. The first diagnostic attempt stopped on a probe-only multiple-return handling error in the ray sampler; the accepted report above is the complete successful rerun. No extra game process ran concurrently with its timing window.


## Final resident-terrain acceptance and real-time loading recovery

The frozen terrain source passed **9,630 checks in desktop mode** and **9,630 in
forced-mobile control mode**. The final Android 79 archive then passed **189
actual four-apartment journey checks**, including sixteen cold loading gates,
physical travel in both directions, parking, gear, registered doors and midride
save/reload. Its packaged domain suite passed **8,475 checks**, including the
24 terrain geometry/lifecycle regressions. Every run used a fresh isolated save
profile. The packaged tests ran from working directories without a source tree.

The first packaged-domain attempt passed the terrain checks but stopped when
resident identity creation could not find the Windows native crypto library.
The Android-ready archive obtains native libraries from its application wrapper;
the successful PC rerun explicitly supplied the existing Windows provider through
`TPS_CRYPTO_LIBRARY`. No Lua source or asset fallback was added. At the packaging
freeze, 858 Lua/GLSL/entry-point files matched the archive byte-for-byte, excluding
the generated build-version stamp and the packager's pre-existing exclusion of
`src/screens/frontier_arcade.lua`. The verified archive SHA-256 is
`20655bf4be2ad2b1ebe69e9df8ceb69857b9d96c1d72e3e2d014ce45ea81b954`.

A subsequent review questioned whether a moving motorcycle could coast unseen
while terrain loaded. A **new tests-only regression added after archive 79**
reproduced the actual save/load path, then called App.update(1/60) with real draws
and presentation until loading finished. This passed all six checks: the bike
was moving at 26.8m/s before saving, recovery safely stopped it before the first
loading update, and its restored position, heading, height, speed and vertical
velocity stayed exact throughout 147 loading frames (2.45 simulated seconds).
The ordinary weekday calendar continued. A live guest rebind stopped only the
reconnecting guest; the other rider retained its velocity and could continue
moving.

This is the existing recovery contract: rider snapshots retain pose and gear but
do not persist motion, and both save recovery and guest rebind construct a stopped
motorcycle. The suspected loading-coast bug did not reproduce, so no production
or network change was made. **Archive/APK 79 production is unchanged.** The new
regression and its optional test dispatch were added afterward and are not in
that archive; the earlier full-source hash comparison describes the packaging
freeze, not the current test files. These acceptance runs are not additional
frame-rate measurements.

Evidence:

- [Source and packaged acceptance summary](../output/terrain-coverage-audit/final-acceptance.json)
- [Archive source parity at packaging freeze](../output/terrain-coverage-audit/final-package-source-parity.json)
- [Packaged four-apartment journey](../output/terrain-coverage-audit/final-package-apartments/report.rpt)
- [Packaged domain with Windows native dependency](../output/terrain-coverage-audit/final-package-domain-native/report.rpt)
- [Real-time recovery and guest-rebind checks](../output/terrain-loading-coast/final-regression-2/report.rpt)
- [Exact recovery measurements](../output/terrain-loading-coast/final-regression-2/measurements.json)

To rerun only the later recovery regression, use a fresh test APPDATA directory
and identity, set `PICTURE_SHOP_SMOKE=1`, `PICTURE_SHOP_COMMUTE=1`,
`PICTURE_SHOP_SMOKE_FOCUS=apartment-journey`, and
`PICTURE_SHOP_LOADING_COAST=1`. Set `PICTURE_SHOP_LOADING_COAST_OUTPUT` to an
existing output directory and `PICTURE_SHOP_SMOKE_REPORT` to its report path.


## Android build 79: interrupted gameplay validation

Build 79 was installed on the Samsung SM-S938U and reached the terrain-preparation/ride flow, but touch input triggered a nil-state error in the warehouse interaction fallback (basketball.lua:289 via input.pressPointer). The run stopped before any valid native gameplay frame trace was recorded. The phone was then removed; no further device operations were performed. There is therefore no measured Android riding FPS for the resident-terrain implementation. The earlier build-77 title-only calibration remains title-only and cannot substitute for this missing gameplay validation. Subsequent PC touch-fix checks do not establish phone performance.

- [Build-79 installation metadata](../output/mobile/terrain-resident-device/installed-build.json)
- [Phone error log](../output/mobile/terrain-resident-device/phone-logcat.txt)


## PC fix for the Android 79 outdoor-touch crash

Actual phone testing reached the terrain loading screen, then an unhandled tap
fell through the commute controls into warehouse interaction selection. On this
cold exterior-only load, the warehouse state cache was still nil, so basketball
target enumeration crashed. The exact App.touchpressed route reproduced the same
failure on PC before the fix.

The correction changes only three production modules: `src/input.lua` consumes
outdoor pointers before the warehouse fallback; `src/commute/runtime.lua` blocks
loading touches, cockpit presses and camera drags before they can latch input;
and `src/world/interactions.lua` clears stale selection and returns no target
until its state is bound. Global options, ordinary warehouse interaction,
on-foot gear/use, mounting, dismounting, mechanic controls and cockpit BOOST
release retain their existing routes. Basketball behavior was not changed.

Full source desktop and forced-mobile suites each passed **9,638 checks**. The
rebuilt standalone archive passed **65 focused terrain/touch checks** from an
empty working directory and fresh profile, including the real App crash route,
loading/release boundaries, synthetic mouse suppression, gear/mount/dismount,
BOOST press/release and touch access to options. Independent source review found
no blocking dispatch issue. These checks are acceptance evidence, not FPS tests;
the renderer is unchanged from the earlier measured terrain benchmark.

The PC-only archive under `output/terrain-coverage-audit/pc-touch-fix-package`
has SHA-256 `48e6e097d00d95c2044214ab469947086b7b21326e067eaf65cd56be7d037cb9`.
Its existing android.79 filename label was retained, but it contains newer source
than the previously installed Android 79 APK. **No new APK was built or installed;
the phone's installed build does not contain this touch fix.** Device operations
stopped when the user took the phone away. Android gameplay FPS remains unmeasured.

- [Pre-fix exact crash reproduction](../output/terrain-touch-crash/reproduction/report.rpt)
- [Full desktop checks](../output/terrain-touch-crash/full-desktop/report.rpt)
- [Full forced-mobile checks](../output/terrain-touch-crash/full-mobile/report.rpt)
- [Standalone packaged terrain/touch checks](../output/terrain-touch-crash/packaged-focus/report.rpt)
- [Archive/source/asset verification](../output/terrain-coverage-audit/pc-touch-fix-package/archive-validation.json)

The focused test uses `PICTURE_SHOP_SMOKE_FOCUS=apartment-journey` with
`PICTURE_SHOP_TOUCH_LOADING=1` and the usual fresh smoke identity/report settings.
