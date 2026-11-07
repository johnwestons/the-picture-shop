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
stopped when the user took the phone away. Android gameplay FPS was unmeasured at
that point; a later S25 capture is recorded below.

- [Pre-fix exact crash reproduction](../output/terrain-touch-crash/reproduction/report.rpt)
- [Full desktop checks](../output/terrain-touch-crash/full-desktop/report.rpt)
- [Full forced-mobile checks](../output/terrain-touch-crash/full-mobile/report.rpt)
- [Standalone packaged terrain/touch checks](../output/terrain-touch-crash/packaged-focus/report.rpt)
- [Archive/source/asset verification](../output/terrain-coverage-audit/pc-touch-fix-package/archive-validation.json)

The focused test uses `PICTURE_SHOP_SMOKE_FOCUS=apartment-journey` with
`PICTURE_SHOP_TOUCH_LOADING=1` and the usual fresh smoke identity/report settings.


## Ongoing cross-platform optimization — November 6, 2026

### Resident terrain draw culling

The shared commute renderer keeps every terrain mesh resident for complete map
coverage, but submits tiles only when their closest point is inside the active
terrain fog radius. This applies to outside and first-person views. The renderer
reuses its draw-list table, sorts the submitted subset, and reports resident,
submitted, and culled tile counts separately. The coverage probe distinguishes
resident coverage from actual draw coverage inside the visible radius.

Two alternating pre-change/current runs used seed 1, the same NVIDIA RTX 3050,
OpenGL 3.3, 1280×880, and the same 3,701-check coverage probe. All four runs
passed; each captured 1,130 projected ground samples with zero missing points
inside the visible radius. Every scene retained all 484 meshes. The baseline
submitted all 484 per frame; the current build submitted 32–37 in outside riding
and 64–69 in first-person riding. Outside stationary views submitted 36 and
first-person stationary views submitted 67.

| Scenario | Baseline p95 range, ms | Current p95 range, ms |
|---|---:|---:|
| Outside cold camera jump | 5.02–5.16 | 4.15–4.57 |
| Outside max zoom / low tilt | 5.10–5.80 | 4.42–4.63 |
| Outside riding | 7.24–7.39 | 6.79–7.39 |
| First-person wide lens | 3.07–3.33 | 2.71–2.72 |
| First-person riding | 5.34–5.47 | 4.65–4.87 |

The repeated desktop results show lower p95s in most tested views; outside
riding did not show a repeatable change. Selected screenshot/readback frames
spiked as high as 59 ms, while every scene's p95 stayed below 16.7 ms. Captures
of the low-tilt outside view and first-person riding were visually reviewed.

The draw-list pass now computes camera depth only after a tile passes the fog
radius check. That reduces depth projections from 484 resident meshes to the
36 outside and 69 first-person submitted tiles in the current seeded routes,
without changing the draw lists or terrain coverage. Cross-policy probes did
not establish a separate full-frame p95 gain from this CPU-work reduction.

- [Baseline run 1](../output/performance/terrain-cull-ab-precoverage-20261106/measurements.json)
- [Current run 1](../output/performance/terrain-cull-ab-postcoverage-20261106/measurements.json)
- [Baseline run 2](../output/performance/terrain-cull-ab-precoverage2-20261106/measurements.json)
- [Current run 2](../output/performance/terrain-cull-ab-postcoverage2-20261106/measurements.json)

### Whole-game desktop scene sweep

The current source also passed the presented-frame sweep on the RTX 3050 at
desktop and forced-mobile window sizes. The forced-mobile run is a 1600×720
layout on the PC GPU, not an Android measurement.

| Presented scene p95 | Desktop, ms | Forced mobile layout, ms |
|---|---:|---:|
| Crowded shop | 6.79 | 6.42 |
| Crowded shop at 10× clock | 9.12 | 9.75 |
| Crowded office | 3.20 | 3.48 |
| Cutter screen | 1.42 | 1.51 |
| Furnished home | 0.70 | 1.22 |
| Arcade | 0.44 | 0.47 |

All six presented-scene p95s stayed below 10 ms. The real asynchronous cold
image paths kept main-thread maxima below 1 ms for a forklift image and below
10 ms for cutter art. The much slower asset-pack roundtrip rows intentionally
disable asynchronous loading and are comparison diagnostics, not normal runtime
measurements.

- [Desktop report](../output/performance/perf-broad-desktop-20261106/measurements.json)
- [Forced-mobile-layout report](../output/performance/perf-broad-mobile-layout-20261106/measurements.json)

### Gameplay update and save preparation

The capacity fixture also exercises 14 machines, 80 pallets, and 10 staff.
Crowded gameplay updates with periodic saves measured p95 3.71 ms on desktop
and 4.33 ms at the forced-mobile PC window size. Putting all 10 staff into
machine-seeking work measured p95 8.78 ms and 7.95 ms respectively. Individual
route stress calls measured p95 9.85/9.20 ms for a detour and 11.92/10.16 ms
for a 640-contact machine search. These independent cases stay below 16.7 ms on
this PC, but are candidates to recheck on the S25 if its gameplay trace shows
CPU-bound frames.

Runtime saves already send disk writes to a worker. Before the follow-up below,
building the detached save snapshot also normalized it on the main thread: in
the populated capacity fixture, queueing that snapshot measured p95 6.42 ms
desktop and 6.02 ms forced-mobile layout. This was a better follow-up target
than the 38.62/27.46 ms direct synchronous-save diagnostic, which is not the
normal gameplay save route.

- [Desktop capacity report](../output/performance/perf-broad-desktop-20261106/measurements.json)
- [Forced-mobile capacity report](../output/performance/perf-broad-mobile-layout-20261106/measurements.json)

The writer now copies the live state into a channel-safe tree immediately, then
lets the save worker normalize and validate that detached copy. This preserves
the point-in-time capture while removing the schema pass from the gameplay
thread. If the live state contains a value the thread channel cannot carry, the
writer falls back to the prior normalized main-thread snapshot. One pre-change
and two post-change PC probe runs measured populated queue time at 4.49 ms p95 /
4.15 ms mean before, then 4.21 and 4.16 ms p95 / 3.58 and 3.62 ms mean after.
That is a 6–8% p95 and 13–14% mean reduction in these runs; the result remains
run-sensitive, and the separate copy and normalization timings also vary. The
live state is still copied and transferred synchronously, so this does not
eliminate the save-related frame cost.

- [Pre-change save profile](../output/performance/save-profile-20261106/measurements.json)
- [Worker-normalization save profile](../output/performance/save-worker-normalization-20261106/measurements.json)
- [Repeated worker-normalization profile](../output/performance/save-worker-normalization-repeat-20261106/measurements.json)

### Navigation with many machine contacts

The shared NPC navigator now builds an exact nearest-goal tree and local goal
buckets for searches with more than 32 contacts. This avoids rescanning every
machine contact from each A* node while preserving the input priority when a
node can reach more than one contact. On the same PC capacity probe, the
640-contact machine route fell from 11.92 ms p95 to 6.21 ms and 6.05 ms in two
post-change runs. The focused employee-transport check passed, including the
route-and-contact-order regression. This is a desktop measurement; the Android
cost still needs a device trace.

- [Pre-change capacity report](../output/performance/perf-broad-desktop-20261106/measurements.json)
- [Navigation run 1](../output/performance/nav-tree-20261106/measurements.json)
- [Navigation run 2](../output/performance/nav-tree-repeat-20261106/measurements.json)
- [Focused navigation regression](../output/performance/nav-tree-20261106/route-regression/report.rpt)

### Employee movement obstacle snapshots

A CPU profile of crowded employee movement showed repeated construction and
inflation of the same collision obstacle list when a worker checked machine
access and then planned or executed movement. Training, assigned-work, and idle
machine-access paths now reuse one per-worker obstacle snapshot for that
decision and move. The next worker still gets a fresh snapshot after earlier
workers may have moved.

In the machine-access stress case, one immediately preceding run measured
7.84 ms p95 / 3.24 ms mean; two runs after the change measured 7.32 and 5.71 ms
p95 / 2.58 and 2.16 ms mean. General 10×-clock simulation p95 measured 7.40 ms
before and 7.49 / 6.91 ms after, so the broader update improvement is not yet
consistent. These are desktop CPU probes, and the stress case includes ten
workers rather than a typical shop.

- [Profile locating repeated obstacle work](../output/performance/profile-followup-20261106/measurements.json)
- [Machine-access run 1](../output/performance/employee-obstacle-snapshot-20261106/measurements.json)
- [Machine-access run 2](../output/performance/employee-obstacle-snapshot-repeat-20261106/measurements.json)

### Outdoor vegetation and plant asset work

The outdoor trace showed that terrain submission was only part of the scene
cost. The commute renderer now spreads missing vegetation patch generation
across frames, starts with nearby patches, and reuses plant lifecycle data for
the current in-game day. Plant atlas pages and motion strips use the existing
background image decode and bounded texture upload path in normal runtime.
These changes target main-thread spikes when entering or crossing the large
terrain area while retaining the synchronous path used by smoke tests.

The seeded 3,701-check terrain sweep passed after these changes. On the same
RTX 3050 at 1280×880 with vsync disabled, the latest default desktop run had
outside fast-ride p95 4.59 ms and first-person fast-ride p95 4.75 ms. A previous
synchronous plant-preparation run measured 6.19 ms and 4.73 ms respectively;
the outside result improved in that pair while the first-person result was
similar. Plant sprite preparation has varied between runs as its pages and
motion strips become resident. Before the work-slice follow-up below, grass
collection was the largest repeated prepare component at about 2.54 ms p95 in
both views. Captured frames were
visually reviewed; sampled ride frames varied in actor pose, as expected from
separate runs.

Android now gets a smaller scenery-work slice: mobile grass patches sample a 5×5
grid instead of 7×7, and their selection probability is scaled to preserve
expected tuft coverage under the existing density cap. The initial mobile grass
generation cap was 1.0 ms and 96 coroutine steps per frame; the current cap is
0.7 ms, while vegetation generation retains its 1.2 ms slice. In two seeded runs
with the mobile policy forced on the PC, grass
collection p95 measured 1.05/1.07 ms outside and 1.06/1.07 ms first-person,
down from 1.57 ms with the prior 1.5 ms cap. Peak cached grass mesh memory fell
from 0.22 to 0.11–0.12 MiB outside and 0.17 to 0.10 MiB first-person. The median
visible patch count stayed at 11 outside and changed from 8 to 7 first-person.
Both runs passed all 3,701 terrain checks and ended with all 484 terrain meshes
resident and no uncovered rays. Their frame p95 ranged from 5.98–6.05 ms outside
and 3.22–3.29 ms first-person, but the disabled-VSync PC capture runs cannot show
how this will affect the S25's frame pacing or temperature.

The mobile renderer now builds visual ground at 1.5 m spacing while desktop
remains at 1 m. Vehicle physics and authoritative world heights are unchanged;
mobile cache files use a spacing-specific path so they cannot load the desktop
mesh shape. Three seeded forced-mobile PC runs each finished with 132,496
vertices and 14.81 MiB of resident terrain meshes, compared with 285,156
vertices and 32.11 MiB at 1 m. All 3,701 terrain checks passed; all 484 tiles
were resident, 36 were submitted, and no coverage rays were missing. Steady
outside fast-ride p95 was 6.05–6.28 ms and first-person was 3.32–3.53 ms, close
to the 1 m comparison at 6.05 ms and 3.22 ms. Cold fill time varied from 1.25 to
3.23 seconds across runs (197–500 frames), so the evidence supports the geometry
and memory reduction but not a consistent loading-speed gain. Captured outside
and first-person rides showed no obvious road seams or ground gaps. A separate
desktop run reported spacing 1 m and the original 32.11 MiB mesh footprint.

The spacing-specific terrain cache now passes a cold-write and warm-read check.
With the mobile policy forced on PC, the cold run wrote all 484 tiles and took
448 loading frames / 2.97 s. A second process using the same private cache loaded
all terrain in 25 frames / 171 ms; its cache marker and a sample tile checksum
were valid, all 484 meshes were resident, and no coverage rays were missing.
The warm loading-frame p95 was 9.57 ms versus 7.72 ms cold, so the cache greatly
shortened total load time but did not lower every loading-frame sample. Outside
fast-ride and first-person fast-ride p95 measured 5.73 ms and 3.21 ms on the warm
run. These remain PC measurements with the mobile policy simulated. The probe
now accepts a separate private cache root and test identity so Windows path
lengths do not prevent cache writes when report artifacts are stored deeply.

Terrain mesh preparation also had a 12 ms per-frame allowance on Android. It
now uses a 6 ms mobile allowance while desktop retains 12 ms. In the seeded
3,701-check coverage probe, loading-frame p95 fell from 12.71 ms to 8.03 ms and
8.06 ms in two runs with the mobile policy forced on PC. Both runs finished
with all 484 meshes resident and no missing coverage rays. The loading pass
took 248 frames before and 413/501 frames after; its PC wall time was 3.08 s
before and 2.79/3.37 s after. This spreads terrain preparation across more
frames while the game draws the resident area. The largest loading-frame samples
include the probe's screenshot readbacks. This is a PC policy simulation, not
an S25 result.

### Grass patch build slices

The commute probe now reports resident and submitted terrain tile counts,
per-frame grass collection time, build steps, visible patch count, and cached
grass mesh bytes. It confirms that terrain streaming submits 36 tiles outside
and 69 in first-person while keeping all 484 meshes resident. Grass collection
was the largest repeated CPU component during movement, so its work slice is
smaller on both policies: 0.7 ms mobile and 2.0 ms desktop, down from 1.0 ms and
2.5 ms.

Across two matched seed-1 runs on the RTX 3050 with the mobile policy forced on,
grass collection p95 fell from 1.07–1.08 ms to 0.78 ms outside and from 1.06 ms
to 0.77 ms in first-person. Desktop runs measured 2.54 ms before and 2.07–2.08
ms after outside, and 2.54 ms before and 2.04–2.05 ms after in first-person.
At the 2.5 ms desktop cap, frame p95 ranged from 4.10–4.26 ms outside and
4.06–4.20 ms first-person; at 2.0 ms it ranged from 3.89–4.05 ms and
3.67–3.72 ms. The forced-mobile PC full-frame percentiles varied between runs,
so the supported mobile-policy result is lower grass CPU work; a general FPS
gain was not established. No run exceeded 16.67 ms. Visible props, draw calls,
terrain tile counts, and grass mesh memory stayed stable. The mobile median
visible grass patch count fell by one in both views; final ride and
first-person captures looked unchanged.
These captures are PC measurements and do not establish S25 temperature or
battery improvement.

- [Mobile 1.0 ms baseline](../output/performance/outdoor-mobile-grass-budget10-captures-20261106/measurements.json)
- [Mobile 0.7 ms run 1](../output/performance/outdoor-mobile-grass-budget07-20261106/measurements.json)
- [Mobile 0.7 ms run 2 and captures](../output/performance/outdoor-mobile-grass-budget07-captures-20261106/)
- [Desktop 2.5 ms baseline](../output/performance/outdoor-desktop-grass-budget25-captures-20261106/measurements.json)
- [Desktop 2.0 ms run 1 and captures](../output/performance/outdoor-desktop-grass-budget20-captures-20261106/)
- [Desktop 2.0 ms repeat](../output/performance/outdoor-desktop-grass-budget20-repeat-20261106/measurements.json)

### Mobile ground shading and draw profile

A follow-up corrected the PC mobile-policy fixture: the renderer had selected
mobile mesh spacing while `Ground.new()` still loaded the desktop atlas. The
renderer now passes its mobile policy through. The forced-mobile probe uses the
512 px, 1.40 MiB mobile atlas; the desktop probe retains the 1024 px, 5.59 MiB
desktop atlas. Earlier forced-mobile PC figures for mesh geometry and coverage
remain valid, but their ground-atlas residency did not match Android.

Mobile ground material detail now fades smoothly from 42% to 70% of the view
radius, before the existing horizon fog begins at 74%. This skips material-atlas
sampling in the fogged distance while retaining full detail nearby. The desktop
fade starts beyond its view radius and leaves its visible ground detail
unchanged. The shader also receives pre-normalized lighting directions and
skips moon-light calculations while moonlight is zero. The captured mobile ride
showed no obvious visual change. These changes reduce shader work by design;
the PC does not provide a reliable mobile GPU or heat measurement.

Both corrected-policy runs passed all 3,701 terrain checks, with 484/484 tiles
resident and no uncovered rays. The mobile-policy PC run reported 132,496
vertices / 15.53 MB of mesh memory and outside / first-person fast-ride p95 of
4.06 / 3.22 ms. Desktop retained 285,156 vertices / 33.67 MB and measured 5.35 /
4.89 ms. A new draw profile separates CPU terrain submission from draw-list
preparation: terrain submission p95 was 0.067 ms mobile-policy and 0.071 ms
desktop. Those numbers are CPU submission time, not completion time on the GPU.
On-device GPU timing and thermal traces are still needed to confirm the mobile
shader benefit.

- [Corrected mobile-policy ground and terrain run](../output/performance/outdoor-mobile-terrain-submit-20261106/measurements.json)
- [Desktop ground and terrain run](../output/performance/outdoor-desktop-terrain-submit-20261106/measurements.json)
- [Mobile ride capture](../output/performance/outdoor-mobile-terrain-submit-20261106/outside_fast_ride-frame-360.png)

The mobile far-water simplification was tested and then removed. Two matched,
GPU-fenced runs per setting on the RTX 3050 used the same seed, mobile terrain
policy, resolution and scene stages. The full-water runs averaged 504.4 GPU-
drained FPS during the outdoor ride; the simplified-water runs averaged 440.7.
Camera rotation averaged 716.6 versus 666.5 FPS, and zoomed-out steady averaged
721.6 versus 686.5 FPS. First-person streaming was effectively tied at 580.3
versus 579.7 FPS. CPU draw-submission p95 stayed close, so the mobile-only
per-pixel branch did not deliver the expected end-to-end gain on this GPU and
reduced throughput in the third-person scenes. The branch and its probe toggles
have been removed; the normal detailed water shader is active on both platforms.
This is a PC result, not a prediction for S25 performance or heat.

- [Full-water GPU-fenced run 1](../output/performance/mobile-full-water-gpu-fence2-20261106/measurements.json)
- [Simplified-water GPU-fenced run 1](../output/performance/mobile-lite-water-gpu-fence-20261106/measurements.json)
- [Simplified-water GPU-fenced repeat](../output/performance/mobile-lite-water-gpu-fence-repeat-20261106/measurements.json)
- [Full-water GPU-fenced repeat](../output/performance/mobile-full-water-gpu-fence-repeat-20261106/measurements.json)
- [Earlier mobile-policy terrain coverage](../output/performance/outdoor-mobile-water-lite-final-20261106/measurements.json)
- [Earlier desktop terrain coverage](../output/performance/outdoor-desktop-water-lite-final-20261106/measurements.json)

These are PC renderer measurements, not S25 FPS or device-temperature data.
The latest default and mobile-policy outside rides each had four over-16.7-ms
samples; their maxima (51–53 ms) occurred on selected capture/readback frames,
while p95 stayed below the 60 FPS frame budget. More repeat runs and on-device
traces are needed before drawing conclusions about heat or mobile frame pacing.

- [Latest default desktop run](../output/performance/outdoor-final-desktop-20261106/measurements.json)
- [Forced mobile-policy run on PC](../output/performance/outdoor-mobile-budget-20261106/measurements.json)
- [Mobile grass grid and budget run 1](../output/performance/outdoor-mobile-grid-budget-20261106/measurements.json)
- [Mobile grass grid and budget run 2](../output/performance/outdoor-mobile-grid-budget-repeat-20261106/measurements.json)
- [Mobile terrain LOD run 1](../output/performance/outdoor-mobile-terrain-lod-20261106/measurements.json)
- [Mobile terrain LOD run 2](../output/performance/outdoor-mobile-terrain-lod-repeat-20261106/measurements.json)
- [Mobile terrain LOD run 3](../output/performance/outdoor-mobile-terrain-lod-final-20261106/measurements.json)
- [Desktop terrain LOD check](../output/performance/outdoor-desktop-terrain-lod-check-20261106/measurements.json)
- [Mobile terrain cache cold write](../output/performance/mobile-terrain-cache-warm-source-20261106/measurements.json)
- [Mobile terrain cache warm load](../output/performance/mobile-terrain-cache-warm-validation-20261106/measurements.json)
- [Mobile terrain-load run 1](../output/performance/terrain-mobile-load-budget-20261106/measurements.json)
- [Mobile terrain-load run 2](../output/performance/terrain-mobile-load-budget-repeat-20261106/measurements.json)
- [Initial integrated async plant and incremental vegetation run](../output/performance/outdoor-final-optimized-20261106/measurements.json)
- [Synchronous comparison run](../output/performance/outdoor-cached-presentation-20261106/measurements.json)

### Runtime-faithful outdoor asset profiling and mobile foliage range

The standalone commute probe now enables the same background image decoder and
per-frame bounded texture upload used in normal play. It also passes the forced
mobile policy into plant-sprite cache setup. Earlier commute-probe plant-prep
times used synchronous image creation and overstated the runtime cost; those
figures should not be used to rank current foliage work. The probe now times
sprite-key collection, page selection/cache work, image loading, and plant
preparation separately. Its settle gate waits for terrain, vegetation, and
currently visible atlas pages, while animation poses continue to warm with the
renderer’s normal fallback behavior.

With those runtime paths enabled, the initial 72 m mobile-policy run measured
3.12 ms frame p95 during the outside ride and 2.67 ms first-person. The current
56 m mobile default measured 2.83/4.90 ms p95/p99 outside and 2.26/2.62 ms
first-person. Current plant-sprite preparation p95 was 0.22 ms outside and
0.13 ms first-person; image-loader update p95 was 0.05 ms and 0.002 ms. At 64 m,
the cold scene briefly reached 21.1 MiB of plant pages; at 56 m it peaked at
18.1 MiB cold and 19.6 MiB during the ride. The mobile cache target remains
20 MiB. The matching desktop-policy run kept its 32 MiB target; its ride and
first-person-streaming frame p95 were 3.85 and 4.20 ms. These are uncapped PC
results, not S25 predictions.

Two alternating GPU-fenced pairs compared a 64 m and 56 m mobile foliage limit
on the same RTX 3050 with seed 1. The desktop limit remains 96 m. At 56 m, the
outside ride reduced p95 visible props from 535 to 413 and p95 draw calls from
646 to 520; frame p95 averaged 3.14 to 2.91 ms across the two runs. First-person
streaming reduced p95 props from 235 to 199 and draw calls from 367 to 322;
frame p95 averaged 2.52 to 2.33 ms. Camera rotation and zoomed-out steady frame
p95 also improved by about 10%. Outside-ride GPU-drained throughput was nearly
flat, and p99 varied upward in that small sample, so the result supports fewer
draw submissions and a modest p95 gain, not a proven reduction in every hitch.
Captures retained the nearby road and roadside plants; fewer distant horizon
trees remain visible, with the fade still gradual. The renderer now defaults to
56 m on mobile and 96 m on PC at this stage of the audit; the latest 48 m mobile
follow-up is recorded below.

- [Initial 72 m mobile runtime-faithful profile](../output/performance/mobile-runtime-asset-profile-final2-20261106/measurements.json)
- [Current 56 m mobile runtime-faithful profile](../output/performance/outdoor-mobile-foliage56-20261106/measurements.json)
- [Desktop runtime-faithful profile](../output/performance/desktop-runtime-asset-profile-20261106/measurements.json)
- [Mobile 64 m pair, run 1](../output/performance/outdoor-mobile-foliage64-20261106/measurements.json)
- [Mobile 56 m pair, run 1](../output/performance/outdoor-mobile-foliage56-20261106/measurements.json)
- [Mobile 56 m pair, run 2](../output/performance/outdoor-mobile-foliage56-repeat-20261106/measurements.json)
- [Mobile 64 m pair, run 2](../output/performance/outdoor-mobile-foliage64-repeat-20261106/measurements.json)
- [Current mobile 3,701-check terrain coverage](../output/performance/outdoor-mobile-foliage56-coverage-verified-20261106/measurements.json)
- [64 m ride capture](../output/performance/outdoor-mobile-foliage64-20261106/ride_streaming-gpu-final.png)
- [56 m ride capture](../output/performance/outdoor-mobile-foliage56-20261106/ride_streaming-gpu-final.png)

### Texture residency and frame pacing

The forced-mobile PC scene sweep ended with 360.9 MiB reported by the GPU;
individual presented scenes ranged from about 307.7 MiB in the crowded shop to
391.0 MiB in the arcade after the complete screen sweep. The same report counted
139 MiB of active asset textures, 84 MiB in the general texture caches, and
60 MiB in the warehouse source-art cache. These are whole-sequence PC readings,
not measurements of a typical Android session or a device memory limit.

The default display mode enables VSync, while the options screen allows it to
be turned off. The mobile setting and native presentation intervals need to be
captured on the S25 before deciding whether its heat or uneven frame pacing is
related to refresh behavior. The measured cache sizes and per-scene texture
residency should also be compared with Android's actual graphics-memory and
thermal readings before adjusting mobile cache budgets.

- [Forced-mobile-layout texture and frame report](../output/performance/perf-broad-mobile-layout-20261106/measurements.json)
- [VSync default](../conf.lua)
- [VSync setting](../src/settings.lua)

### Current integrated mobile-layout check

After the latest terrain and simulation changes, the full desktop probe was run
at the 1600×720 mobile-layout size on the RTX 3050 with VSync disabled. The six
presented scene p95s ranged from 0.42 to 9.39 ms; the crowded shop measured
6.79 ms at normal clock and 9.39 ms at 10× clock. That 10× case is above an
8.33 ms 120 Hz frame budget, though below 16.67 ms for 60 Hz. In the same run,
crowded worker machine-seeking measured 5.30 ms p95, the 640-contact route
fixture 4.75 ms, and populated async-save dispatch 4.29 ms. Asynchronous image
loading held the main-thread maximum to 0.84 ms for a cold forklift image and
6.27 ms while opening the cutter screen. Reported GPU texture memory peaked at
372.9 MiB during the arcade sweep (360.9 MiB total at the end); these are PC
readings and do not establish Android memory or thermal behavior.

- [Current integrated mobile-layout report](../output/performance/whole-mobile-integrated-20261106/measurements.json)

### Mobile cache-budget experiment

A 25% across-the-board reduction in inactive texture-cache limits lowered the
full-sweep peak from 372.9 to 331.9 MiB, but it raised title-screen texture
uploads from 21 to 196 and title-draw p95 from 0.16 to 39.97 ms. File reads
during that title stage also rose from one to 13. The broad reduction was
reverted because the reload churn creates a larger interaction hitch than the
memory savings justify. Any further cache tuning should isolate a cache family
or screen lifecycle and measure its return path before being retained.

- [Baseline integrated mobile-layout report](../output/performance/whole-mobile-integrated-20261106/measurements.json)
- [Reduced-cache experiment](../output/performance/whole-mobile-cache75-20261106/measurements.json)

### Targeted warehouse cache limit

After the broad cache reduction showed title-screen reload churn, the Android
policy was narrowed to the warehouse renderer's inactive source-art cache: its
limit is 48 MiB on mobile and remains 64 MiB on PC. Two forced-mobile PC scene
sweeps reduced that cache from 60 to 48 MiB and peak GPU texture memory from
372.9 to 360.9 MiB. General caches stayed at 84 MiB, title-screen texture
uploads stayed at 21, and title-draw p95 stayed near baseline at 0.19/0.22 ms
(0.16 ms in the prior run). Crowded-shop texture residency fell by 12 MiB, with
normal-clock p95 at 5.23/6.30 ms and 10× p95 at 9.28/9.10 ms. The forklift-view
fixture added one texture upload (17 vs. 16) and no file reads. The narrower
policy avoids the broad cut's title hitch in these PC runs; Android temperature
and memory pressure still need device measurements.

- [Targeted warehouse-cache run 1](../output/performance/whole-mobile-warehouse-cache-20261106/measurements.json)
- [Targeted warehouse-cache run 2](../output/performance/whole-mobile-warehouse-cache-repeat-20261106/measurements.json)

The follow-up desktop run with the mobile override unset retained the 64 MiB
warehouse cache (60 MiB resident) and the same 21 title-screen uploads. Presented
scene p95 ranged from 0.37 ms in the arcade to 9.69 ms in the crowded shop at 10×
clock, below the 16.67 ms 60 Hz budget on the RTX 3050.

- [Desktop cache-policy check](../output/performance/whole-desktop-warehouse-cache-20261106/measurements.json)

### Crowded employee obstacle updates

A whole-game CPU profile found repeated footprint expansion while workers built
fresh movement snapshots. Employee circles are created for that snapshot and
are not shared with world state, so the movement radius can be applied directly
to each circle instead of copying it through the generic footprint expander.
Other obstacle shapes still use the generic path, and each moving worker still
gets a fresh snapshot after earlier workers move.

Two forced-mobile-layout runs on the RTX 3050 moved crowded world-update p95
from 4.39 ms to 4.23/4.20 ms, and the 10× clock case from 7.28 ms to 6.62/6.89
ms. Mean update time changed from 1.36 to 1.33/1.35 ms and from 2.20 to
2.16/2.16 ms, respectively. Route-heavy results did not show a reliable gain:
crowded route-detour p95 was 7.46 ms before and 10.76/8.66 ms after, while the
presented crowded-shop p95 varied between 6.38 and 6.92 ms (6.79 ms baseline).
This is a small, localized update-path reduction, not evidence of a general FPS
or thermal improvement; the S25 measurement remains outstanding.

- [Baseline whole-game report](../output/performance/whole-mobile-integrated-20261106/measurements.json)
- [Employee-circle run 1](../output/performance/whole-mobile-employee-circle-20261106/measurements.json)
- [Employee-circle run 2](../output/performance/whole-mobile-employee-circle-repeat-20261106/measurements.json)

### Route floor-mask sampling

Route validation sampled three floor-mask pixels for each foot position and
re-read the same mask dimensions for every pixel. It now reads dimensions once
per position, area check, or route segment and reuses them for all samples.
This leaves the pixel coordinates, colors, bounds, and traversal stride
unchanged. Compared with the preceding employee-circle runs, two whole-game
mobile-layout runs lowered crowded detour mean time from 6.27/6.48 ms to
5.98/5.98 ms. The route p95s still varied widely (10.76/8.66 ms before and
12.21/6.77 ms after), and the 640-contact search stayed essentially flat in
mean time, so these probes do not establish a consistent broad FPS gain.

- [Employee-circle baseline, run 1](../output/performance/whole-mobile-employee-circle-20261106/measurements.json)
- [Walk-mask dimensions run 1](../output/performance/whole-mobile-walkmask-dimensions-20261106/measurements.json)
- [Employee-circle baseline, run 2](../output/performance/whole-mobile-employee-circle-repeat-20261106/measurements.json)
- [Walk-mask dimensions run 2](../output/performance/whole-mobile-walkmask-dimensions-repeat-20261106/measurements.json)

### Mobile foliage range: 48 m follow-up

The runtime-faithful outdoor probe compared 56 m and 48 m mobile foliage
ranges on the same RTX 3050, seed 1, forced-mobile renderer, and GPU-fenced
stages. Both capture-free runs at 48 m submitted 281–282 plants and 407–408
draw calls during outside riding, compared with 413–417 plants and 520 calls at
56 m. Outside-ride frame p95 was 3.02–3.17 ms at 56 m and 2.02–2.12 ms at
48 m; mean frame time was 2.01–2.09 ms and 1.53–1.57 ms. In first-person
streaming, visible plants fell from 199 to 162 and draw calls from 322 to 283;
frame p95 changed from 2.31–2.45 ms to 2.26–2.35 ms. Zoomed-out steady p95
also fell from 1.54–1.55 ms to 1.20–1.43 ms. Camera-rotation p95 varied, so the
gain is strongest during riding and steady zoomed-out viewing rather than every
stage.

The 48 m ride and first-person captures retain the road, nearby trees, and
roadside plants with a gradual fade. They remove some small distant plants; the
reviewed captures looked nearly identical at the tested views. The mobile
default is now 48 m; PC remains 96 m. Terrain tile residency, terrain draw
coverage, and collision are unchanged. This is still a forced-mobile PC GPU
measurement and does not establish S25 frame-time or temperature improvement.

- [56 m run 1, current source](../output/performance/outdoor-mobile-foliage56-current-20261106/measurements.json)
- [56 m run 2, current source](../output/performance/outdoor-mobile-foliage56-current-repeat-20261106/measurements.json)
- [48 m run 1](../output/performance/outdoor-mobile-foliage48-repeat-20261106/measurements.json)
- [48 m run 2](../output/performance/outdoor-mobile-foliage48-clean-20261106/measurements.json)
- [48 m default-policy confirmation](../output/performance/outdoor-mobile-default48-20261106/measurements.json)
- [Desktop 96 m policy check](../output/performance/outdoor-desktop-default96-20261106/measurements.json)
- [48 m ride and zoom captures](../output/performance/outdoor-mobile-foliage48-20261106/)
- [56 m ride and zoom captures](../output/performance/outdoor-mobile-foliage56-20261106/)

### Mobile canopy and brush range split

A uniform 40 m foliage range removed several distant trees in the sampled
first-person view. Mobile now keeps canopy trees out to 48 m and fades brush,
flowers, and other non-canopy props by 40 m. Both outside and first-person
renderers use each prop's own fade and culling range. The road, terrain,
collision, and desktop 96 m range are unchanged.

In matched seed-1 runs on the RTX 3050 with the mobile renderer forced on, the
split retained all 37 canopy props in outside riding while reducing brush from
254 to 178. Total visible props fell from 282 to 211–212 and draw calls from
405 to 337. Zoomed-out steady props/draw calls fell from 278/364 to 191/277;
first-person streaming fell from 162/283 to 129/248. Side-by-side ride and
first-person captures retain the trees, road, and roadside landmarks while
removing some small distant brush.

Frame p95 moved modestly and varied between the two split runs: outside riding
was 2.46/2.85 ms versus 2.66 ms at uniform 48 m; first-person streaming was
2.07/2.35 ms versus 2.22 ms. Reported texture memory stayed near 106.5 MiB
outside and 124.8 MiB first-person, about 1 MiB above the 48 m comparison, so
this change demonstrates fewer submissions but not a memory reduction or a
confirmed S25 thermal gain.

The performance probe's scenery-settle gate now requires idle image work and
ready visible plant and bike pages. It reports retained, unclaimed decoded
image bytes without waiting for them to expire; that cache can hold images for
reuse even after all visible scenery is ready.

- [48 m baseline](../output/performance/outdoor-mobile-foliage48-plain-20261106/measurements.json)
- [Hybrid run 1](../output/performance/outdoor-mobile-foliage-hybrid-repeat-20261106/measurements.json)
- [Hybrid run 2](../output/performance/outdoor-mobile-foliage-hybrid-verified-repeat-20261106/measurements.json)
- [Hybrid visual captures](../output/performance/outdoor-mobile-foliage-hybrid-captures-20261106/)

### Mobile vegetation lifecycle-copy filtering

Mobile vegetation selection now rejects props beyond their per-kind range
before creating lifecycle presentation copies and sorting the result. This
avoids CPU work for brush that the renderer would fade out anyway; canopy
selection and the visible brush/tree counts remain unchanged.

Two matched seed-1 GPU-fenced runs on the RTX 3050 with the mobile renderer
forced on measured outside-ride `props_ms` p95 at 0.69/0.79 ms, down from
0.91 ms, and first-person streaming at 0.40/0.43 ms, down from 0.57 ms.
Frame-time p95 moved from 2.85 to 2.51/2.61 ms outside and from 2.35 to
2.08/2.15 ms in first-person. Visible counts stayed at 211–212 props and
337–338 draws outside, and 129 props and 248 draws in first-person. These
repeatable CPU and frame-time reductions are from forced-mobile PC runs; they
do not establish Android temperature or battery improvement.

- [Lifecycle-filter run 1](../output/performance/outdoor-mobile-prop-filter-20261106/measurements.json)
- [Lifecycle-filter repeat](../output/performance/outdoor-mobile-prop-filter-repeat-20261106/measurements.json)

### Plant page and motion preparation

Plant preparation used to run `Flora.visual` once while selecting visible atlas
pages and again while collecting animation requests. It now carries the action
and variant out of `plantKey` and collects those requests during the same
visible-plant pass. Landmark ordering, extra-prop page requests, motion dedupe,
and animation-page residency remain unchanged.

The runtime-faithful traces put `plant_prepare` below 0.25 ms p95 in steady
outside and first-person riding; the current 48 m default measured 0.13 ms on
outside riding and 0.08 ms in first-person streaming. Earlier 56 m runs measured
0.20–0.22 ms and 0.13–0.14 ms, respectively. The lower plant count at 48 m
contributes to that difference, so it does not isolate the code change or prove
a broad frame-time improvement.

- [56 m runtime baseline, run 1](../output/performance/outdoor-mobile-foliage56-20261106/measurements.json)
- [56 m runtime baseline, run 2](../output/performance/outdoor-mobile-foliage56-repeat-20261106/measurements.json)
- [Current 48 m mobile runtime profile](../output/performance/outdoor-mobile-default48-20261106/measurements.json)
- [Runtime LuaJIT call profile](../output/performance/outdoor-mobile-profile-plant-keys-20261106/measurements.json)

### Motorcycle action-page upload pacing

The outdoor CPU profile also found a first-use hitch when a rider switched to
one of the large 64-view action atlases. Action pages now use the existing
background PNG decoder and its 2 MiB-per-update texture upload budget. Until a
page is ready, the bike stays visible with the resident upright atlas; action
pages remain lazily loaded and the existing 12-page cache limit is retained.

In paired 300-frame outside-ride runs with the mobile renderer forced on the
RTX 3050, the first-frame spike fell from 48.87 ms to 6.78 ms. The outside
ride p95 was 3.27 ms before and 3.44 ms after, so this removes a large transient
hitch without demonstrating a sustained frame-time gain. The async run reached
two resident action pages and at most two pending pages. The standalone probe
still recorded a 57.42 ms first-person draw on its first frame, nearly the
same as the 57.72 ms synchronous run. That frame includes lazy first-person
cockpit resource creation: the live commute runtime calls
`prewarmFirstPerson()` during the ride preparation screen, before the loading
phase ends. Treat this as setup work rather than evidence of a live camera
switch hitch. The PC probe does not establish S25 frame-time or thermal results.

- [Synchronous action-page baseline](../output/performance/outdoor-mobile-bike-pages-sync-20261106/measurements.json)
- [Async action-page run](../output/performance/outdoor-mobile-bike-pages-async-20261106/measurements.json)

### Android measurement still outstanding

The elevated, read-only `adb devices -l` inventory this pass successfully
started the daemon and found no attached Android devices; the sandboxed call
could not start its daemon. No current S25 gameplay frame or temperature/thermal
trace was captured. The PC forced-mobile policy run does not substitute for
one. The next
device pass should measure outside and first-person gameplay over a sustained
ride, native present intervals, current VSync setting, graphics memory, and
thermal status before choosing further mobile quality or frame-pacing changes.

### Follow-up: asset uploads and frame pacing

The shared image loader transfers at most one 2 MiB strip per update. Plant
pages and motion strips use their own upload path; during the mobile-policy
ride trace, the largest observed plant upload was 1 MiB and plant preparation
stayed below 0.49 ms. `image_loader_update` reached 0.16 ms at p95 and 1.23 ms
at its single-frame maximum outside, and 0.002 ms at p95 and 0.19 ms maximum
in first-person. These RTX 3050 runs do not show uploads as a steady-state
frame bottleneck, so lowering their limits is not currently supported by the
measurements and could only delay asset readiness.

The broader forced-mobile scene sweep measured the crowded shop at 6.42 ms
p95, rising to 9.75 ms at 10x simulation speed; the furnished home, office,
and cutter screens were lower. This puts accelerated shop simulation on the
whole-game follow-up list, while the outdoor ride remains the current mobile
priority. These are PC measurements and do not establish S25 performance.

The shipped window configuration requests VSync and the settings screen can
toggle it; no separate frame-rate cap is present. At the time this PC-based
section was written, the effective present rate on the S25 had not been
measured. See the later device capture below. That capture measures displayed
frame intervals, not game CPU or GPU execution time, so it still cannot isolate
device-side pacing from workload limits.

### Follow-up: mobile grass mesh work

The mobile grass builder now samples a 4×4 grid per patch instead of 5×5,
while density compensation retains the same broad meadow distribution. Its
per-frame grass work cap is 0.45 ms, down from 0.7 ms. Desktop still uses its
7×7 grid and 2 ms cap.

Two matched seed-1 runs on the RTX 3050 with the mobile policy forced on
measured outside-ride grass collection p95 at 0.51/0.52 ms, down from 0.78 ms.
First-person p95 was 0.51/0.51 ms, down from 0.77 ms. Summed grass collection
time fell about 47% outside and 20% in first-person; p95 grass mesh bytes fell
33% and 37%, respectively. Draw counts stayed effectively unchanged. The
captures keep the road, trees, and large roadside plants; small grass tufts
are visibly a little sparser. The mobile-only tradeoff is acceptable for the
measured CPU and memory savings, while desktop settings remain unchanged.

These measurements were taken on a PC with VSync disabled; they do not prove
S25 FPS, frame pacing, or temperature improvement. The read-only ADB inventory
at the time found no attached Android device. A later phone capture is recorded
below. Reports and captures:

- [Mobile grid 4 and 0.7 ms cap](../output/performance/outdoor-mobile-grass-grid4-captures-20261106/measurements.json)
- [Mobile grid 4 and 0.45 ms cap, run 1](../output/performance/outdoor-mobile-grass-grid4-budget045-captures-20261106/measurements.json)
- [Mobile grid 4 and 0.45 ms cap, repeat](../output/performance/outdoor-mobile-grass-grid4-budget045-repeat-captures-20261106/measurements.json)

### Follow-up: crowded-shop collision snapshot work

The crowded whole-game profile found repeated scans and temporary filtered
arrays for the installed machine fleet while building each employee movement
snapshot. `movementObstacles()` now obtains one ordered installed-unit list,
uses it to select the first cutter, wrapper, and press as before, then reuses
that same list to add installed machine obstacles.

In the 14-machine, 80-pallet, 10-staff workload, one unprofiled forced-mobile PC run
measured world-update p95 at 4.11 ms, down from 5.00 ms; the 10x-clock update
measured 7.23 ms, down from 7.46 ms. Workers seeking machine access measured
5.99 ms, down from 7.38 ms. Presented crowded-shop p95 improved from 6.29 to
5.13 ms at normal speed; the 10x presented scene remained effectively tied at
9.25 ms. The change reduces CPU snapshot work but does not establish an Android
or thermal gain.

- [Pre-change crowded-scene profile](../output/performance/whole-mobile-profile-followup-20261106/measurements.json)
- [Post-change crowded-scene profile](../output/performance/whole-mobile-crowded-after-20261106/measurements.json)
- [Pre-change CPU stacks](../output/performance/whole-mobile-crowded-profile-20261106/measurements.json)
- [Post-change CPU stacks, repeat 1](../output/performance/whole-mobile-crowded-profile-followup-20261106/measurements.json)
- [Post-change CPU stacks, repeat 2](../output/performance/whole-mobile-crowded-profile-repeat-20261106/measurements.json)

### Follow-up: cold player character streaming

The `character_action_working_set` row is a synthetic pass that visits every
`rabbit-worker` action and caches the textures; it took about 265 ms, but does
not represent a single gameplay frame. I added a separate first-use measurement
that clears the character cache, requests the player's `walk_south` pose through
the normal asynchronous loader, and records update/draw time while it streams.

The cold pose completed in 13 frames with a 6.65 ms maximum update/draw interval
at 960×678, and in 12 frames with a 5.42 ms maximum at the forced mobile
1600×720 policy. The latter uses mobile settings and resolution on the same PC,
so neither run demonstrates Android FPS, frame pacing, or heat improvement.
This was a probe-only change; gameplay loading behavior is unchanged.

- [PC-resolution async character probe](../output/performance/whole-mobile-character-async-20261106/measurements.json)
- [Forced-mobile-policy async character probe](../output/performance/whole-mobile-character-async-mobilepolicy-20261106/measurements.json)

### Follow-up: mobile terrain height sampling

The cold terrain profile showed the mobile builder repeatedly sampling terrain
height at four extra offsets per vertex to construct normals. Mobile terrain
now uses a rolling three-row window of the existing 1.5 m mesh heights for its
normals and material slope. This keeps terrain vertex positions, road grading,
and gameplay height queries unchanged. Desktop keeps its existing 1 m mesh and
height sampling path.

In matched seed-1 forced-mobile-policy coverage runs on the RTX 3050, complete
terrain residency fell from 198 frames / 1,254 ms to 101 frames / 644 ms, about
49% less build time. Both runs completed all 484 tiles with 132,496 vertices,
15.5 MiB of mesh data, all 3,701 coverage checks passed, and zero uncovered
rays. The per-frame loading p95 stayed near 6.5 ms because the 6 ms work slice
remains in place; this shortens how long terrain generation runs without
reducing that individual slice. Matched outside and first-person captures showed
no obvious visual change. The desktop coverage run also passed all 3,701 checks
at 1 m spacing. These are PC measurements and do not establish S25 frame-time,
heat, or battery changes.

- [Pre-change forced-mobile profile/captures](../output/performance/outdoor-mobile-mesh-normal-window-baseline-20261106/measurements.json)
- [Updated forced-mobile profile/captures](../output/performance/outdoor-mobile-mesh-normal-window-optimized-20261106/measurements.json)
- [Pre-change mobile coverage](../output/performance/outdoor-mobile-mesh-normal-window-coverage-baseline-20261106/measurements.json)
- [Updated mobile coverage](../output/performance/outdoor-mobile-mesh-normal-window-coverage-20261106/measurements.json)
- [Desktop 1 m profile](../output/performance/outdoor-desktop-mesh-normal-window-20261106/measurements.json)
- [Desktop coverage](../output/performance/outdoor-desktop-mesh-normal-window-coverage-20261106/measurements.json)

## Galaxy S25 device capture — November 6, 2026

The current working tree was packaged and installed under the isolated Android
ID `com.thepictureshop.performance`. The installed game and its save data were
left untouched. The isolated package data was reset before the second ride and
the test package was removed afterward. The regular Android build report was
restored to match `mobile/config.json`.

The device was a Samsung SM-S938U running Android 17, with a 1080×2340 native
display in landscape gameplay. SurfaceFlinger reported an 8.333 ms refresh
period, or 120 Hz. The frame probe measures actual presented-buffer intervals;
it does not measure CPU or GPU execution time.

| Scene | Intervals | Presented FPS | p95, ms | p99, ms | Max, ms | Over 16.67 ms | Over 33.33 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Outdoor, stationary at shop | 3,621 | 120.09 | 8.324 | 8.324 | 16.645 | 0 | 0 |
| Outdoor, stationary lakeside | 3,622 | 120.08 | 8.324 | 8.324 | 16.647 | 0 | 0 |
| Outdoor, route movement | 3,170 | 104.78 | 16.646 | 16.648 | 24.970 | 4 | 0 |

All three windows had zero SurfaceFlinger history gaps. The stationary outdoor
scene held 120 Hz. The moving route sample averaged 104.8 FPS and included four
intervals longer than 16.67 ms, with no interval longer than 33.33 ms. This is
the first device evidence that outdoor movement costs more than a stationary
view, but it is a diagnostic sample rather than a clean full trip: the route
automation stopped at waypoint 44 of 253 after a sharp turn.

The existing Android journey helper still uses old touch coordinates for some
mobile controls. The ride was run with corrected coordinates and an H-key
headlight refresh. That automation adds input and save reads, and the headlight
state changed during the ride, so repeat a full route with repaired controls
before treating these values as a normal user gameplay baseline. The app itself
remained alive, the bike had no damage, and no long frame stall occurred.

After outdoor play, Android reported battery temperature 38.7°C, skin sensor
temperature 40.4°C (sensor status 1), AP 45.5°C, and PA 47.6°C. The device was
USB charging at 53% battery. These readings were not taken in a controlled
unplugged comparison, so they show the observed condition but do not isolate
heat caused by the game.

The moving scene memory snapshot reported total PSS of 1,597,781 kB, native
heap of 629,480 kB, and GL tracking of 694,440 kB. The earlier stationary
snapshot was lower, but it used a different generated town and session point;
this is a lead for memory and texture profiling, not a measured movement-only
increase.

The Android runtime archive measured 906,064,250 bytes and the APK measured
925,530,589 bytes. This is a clear install, update, and storage cost to audit.
It is not evidence that package size itself causes frame-time spikes.

- [Stationary S25 frame sample](../output/performance/android-s25/s25-outdoor-stationary-before-surfaceflinger.json)
- [Second stationary S25 frame sample](../output/performance/android-s25/s25-outdoor-lakeside-stationary-surfaceflinger.json)
- [Moving S25 frame sample](../output/performance/android-s25/s25-outdoor-moving-30s-surfaceflinger.json)
- [Isolated Android APK report](../output/performance/android-s25/apk-report-perf.json)

### Open work from the device capture

- Repair `tools/android_town_journey.py` so it uses the current touch layout and
  can complete a repeatable full outdoor route without toggling unrelated
  controls.
- Profile terrain streaming, CPU time, GPU time, and allocations during that
  full route. The current SurfaceFlinger data identifies missed refreshes but
  not which game subsystem caused them.
- Repeat thermal measurements from a controlled starting temperature with the
  phone unplugged. Only then compare frame targets such as 120 Hz and 90 Hz.
- Audit the mobile package asset list and texture lifetime to reduce package
  size and the high native/GL memory footprint without losing visible content.
- Extend the measured sweep to shop, home, office, and accelerated simulation;
  this capture covers outdoor commute only.

### Follow-up: crowded-shop obstacle expansion — November 7, 2026

The CPU profile showed repeated generic footprint expansion while employees
built movement snapshots. These obstacle records are created or copied for
each snapshot, so simple footprints now inflate in place instead of making an
additional table copy. Installed machine footprints use the same cached planes
directly with their current positions. Polygon footprints retain the existing
copy path. Collision bounds and gameplay rules are unchanged.

Three forced-mobile-layout runs used the same Windows PC, RTX 3050, OpenGL,
1600×720 window, and disabled VSync. One run preceded in-place expansion and
two followed it. Crowded normal-update mean fell from 1.35 ms to 1.09/1.10 ms;
the 10×-clock update mean fell from 2.17 ms to 1.65/1.63 ms. In the ten-worker
machine-seeking phase, mean/p95 fell from 2.39/7.87 ms to 2.25/5.08 and
1.80/4.98 ms. These PC measurements support a repeatable CPU update reduction.
The presented 10× scene p95 was 9.25 ms before and 7.19/9.21 ms after, so its
tail improvement is not repeatable yet. No Android frame-time or thermal gain
is established.

- [Before in-place expansion](../output/performance/footprint-expanded-followup-20261107/measurements.json)
- [After, run 1](../output/performance/obstacle-expand-in-place-20261107/measurements.json)
- [After, repeat](../output/performance/obstacle-expand-in-place-repeat-20261107/measurements.json)

### Follow-up: three-client Session baseline — November 7, 2026

The performance probe now starts a host and three real Session clients on the
in-memory transport, completes the normal hello/welcome exchange, and profiles
600 simulated 60 Hz frames. The loop includes host snapshots and encoding,
guest input and packet decoding, guest motion smoothing, and remote-player
movement. The host sent 3,960 peer packets during the sample.

Two runs averaged 0.230/0.273 ms per simulated frame, with p95 values of
0.857/1.060 ms and maxima of 3.520/3.711 ms on the Windows PC. The higher run
enabled LuaJIT sampling; samples appeared in codec decoding/canonical checks,
protocol normalization, movement, and client visual smoothing. No single path
approached a 16.67 ms frame budget in these runs. This does not measure wireless
latency, Direct transport encryption, mobile hardware, rendering, or actual
Android frame presentation. Keep these results as a desktop networking
baseline, not evidence that multiplayer is equally cheap on phones.

- [Three-client Session profile](../output/performance/multiplayer-host-session-probe-repeat-20261107/measurements.json)
- [Three-client Session repeat](../output/performance/multiplayer-host-session-probe-repeat2-20261107/measurements.json)

### Follow-up: crowded employee obstacle allocations — November 7, 2026

The ten-worker machine-seeking profile repeatedly built a list of temporary
physical-pallet descriptors and then copied those values into collision
obstacles. `PalletLogistics.obstacles` now emits job-pallet obstacle records
directly; it preserves the existing scene, exclusion, spawn-position, shape,
and size rules and still refreshes the snapshot for each worker move. Other
callers of `physicalPallets` keep the same API.

In the 14-machine, 80-pallet, ten-worker probe, the immediately preceding run
measured 2.238 ms mean and 6.741 ms p95 while workers sought machine access.
Three runs after the change measured 1.965, 2.048, and 2.157 ms mean, with p95
values of 4.343, 5.595, and 4.186 ms. The ordinary crowded update row varied
upward in the post-change runs, so the measured gain is limited to the targeted
employee-navigation workload; Android impact has not been measured.

- [Before obstacle fusion](../output/performance/pallet-obstacle-fusion-before-20261107/measurements.json)
- [After, run 1](../output/performance/pallet-obstacle-fusion-after-1-20261107/measurements.json)
- [After, repeat](../output/performance/pallet-obstacle-fusion-after-2-20261107/measurements.json)
- [After, final run](../output/performance/pallet-obstacle-fusion-after-final-20261107/measurements.json)

The post-change LuaJIT profile still samples pallet-obstacle generation and
per-route spatial-index construction as recurring costs. Any reuse optimization
there must retain fresh positions after each employee move.
- [Post-change worker profile](../output/performance/pallet-obstacle-fusion-profile-20261107/measurements.json)

The earlier `forklift_all_views` measurement was a synchronous loading stress
case: the performance probe disables `ImageLoader` for that row, while normal
runtime enables it and `WarehouseRenderer` routes forklift images through the
loader. The row is now named `forklift_all_views_sync_loader_disabled` to make
that scope visible. The separate cold-image async timing is useful loader
evidence, but it does not replace a real first-use forklift render capture.

### Follow-up: reuse indexes for immutable movement snapshots — November 7, 2026

Machine access selection checked multiple candidate positions against one
fresh obstacle list, then movement rebuilt the spatial index for that same list
in the same worker update. Large snapshots now reuse an index by weak identity;
small snapshots continue through the direct-scan path. Candidate checks use the
index, while a later worker movement receives a newly built snapshot and index.

In two 14-machine, 80-pallet, ten-worker runs, normal crowded-update mean/p95
was 1.055/1.664 and 1.082/1.907 ms, compared with 1.122/2.367 ms before. The
10×-clock row measured 1.596/2.264 and 1.632/2.755 ms, compared with
1.756/5.357 ms before. Worker-seeking p95 moved from 5.854 ms to 4.872/4.349
ms; its mean was 2.053 ms before and 2.081/1.966 ms after, so the tail improved
more consistently than the mean. These are Windows PC results; no Android
frame-time gain is established.

- [Before index reuse](../output/performance/obstacle-index-cache-before-20261107/measurements.json)
- [After, run 1](../output/performance/obstacle-index-cache-after-1-20261107/measurements.json)
- [After, repeat](../output/performance/obstacle-index-cache-after-2-20261107/measurements.json)

### Follow-up: cache first-person silhouette uniforms — November 7, 2026

The commute profile showed redundant silhouette shader uniform checks and sends
around each first-person plant draw (about 940 draw calls per steady frame).
`SilhouetteStyle` now caches uniform availability and the last values sent for
each shader, using weak shader keys. The first-person steady draw count stayed
at 940 while profiled mean/p95 frame time changed from 3.55/4.77 ms to
2.23/3.32 ms; profiled draw time changed from 3.08/4.26 ms to 1.83/2.06 ms.
Streaming mean/p95 changed from 4.31/7.03 ms to 3.19/5.49 ms. A separate
unprofiled run recorded 2.33/3.14 ms steady and 3.13/5.53 ms streaming. These
are Windows RTX 3050 captures; ADB could not connect to a device, so Android
and Steam Deck performance has not been measured.

- [Before profile](../output/performance/current-commute-profile-20261107/measurements.json)
- [After profile](../output/performance/commute-silhouette-uniform-cache-profile-20261107/measurements.json)
- [After unprofiled repeat](../output/performance/commute-silhouette-uniform-cache-repeat-20261107/measurements.json)

### Follow-up: skip silhouette setup for plant billboards — November 7, 2026

Plant billboards never use highlight silhouettes, so their per-draw silhouette
setup and reset calls were removed. Actor billboards still set their requested
mode, and highlighted draws still reset it immediately afterward. With 940
steady plant draw calls unchanged, two unprofiled repeats measured first-person
steady mean/p95 at 2.15/2.80 and 2.20/2.89 ms, versus 2.33/3.14 ms before this
change. Streaming measured 2.92/4.77 and 2.98/5.11 ms, versus 3.13/5.53 ms;
camera rotation measured 2.01/2.76 and 2.04/2.81 ms, versus 2.13/3.22 ms.
These are repeated Windows RTX 3050 captures; device-specific Android/Steam Deck
results remain unverified.

- [Before, unprofiled](../output/performance/commute-silhouette-uniform-cache-repeat-20261107/measurements.json)
- [After profile](../output/performance/commute-firstperson-silhouette-calls-profile-20261107/measurements.json)
- [After, repeat 1](../output/performance/commute-firstperson-silhouette-calls-repeat-20261107/measurements.json)
- [After, repeat 2](../output/performance/commute-firstperson-silhouette-calls-repeat2-20261107/measurements.json)

### Follow-up: skip per-plant sway work while calm — November 7, 2026

Both commute renderers now check once per draw whether a gust or a plant
contact response is active. During calm frames they pass zero sway directly to
the plant renderer; when motion is active, every plant still uses the existing
`sway` calculation. Two same-seed, unprofiled A/B runs kept visible-prop and
draw-call counts identical. Average draw mean/p95 moved from 1.02/1.13 to
0.98/1.06 ms in stationary view, 1.17/1.29 to 1.12/1.23 ms zoomed out, and
0.96/1.15 to 0.93/1.09 ms during first-person camera rotation. First-person
steady frame mean/p95 was 1.51/1.98 before and 1.50/1.96 after; streaming was
1.92/3.59 and 1.91/3.53 ms. This is a modest Windows RTX 3050 CPU-side gain;
Android and Steam Deck results remain unmeasured. An unseeded profiling attempt
timed out during cold startup and is excluded from these comparisons.

- [Before, run 1](../output/performance/commute-sway-before-seed42-20261107/measurements.json)
- [Before, repeat](../output/performance/commute-sway-before-seed42-repeat2-20261107/measurements.json)
- [After, run 1](../output/performance/commute-sway-seed42-unprofiled-20261107/measurements.json)
- [After, repeat](../output/performance/commute-sway-seed42-repeat2-20261107/measurements.json)
- [Timed-out profile attempt](../output/performance/commute-plant-sway-active-profile-20261107/measurements.json)

### Follow-up: navigation and multiplayer profile — November 7, 2026

A sampled full-game profile measured crowded route detours at 6.45 ms mean and
640-contact route selection at 5.00 ms mean. Three-guest host updates measured
0.32 ms mean and 1.14 ms p95; most sampled network time was in packet decoding
and validation, so no network code change was justified. These profile timings
include sampler overhead and are diagnostic rather than unprofiled frame-time
comparisons.

The route probe now includes a deterministic all-white walk-mask case to cover
the path used by real floor masks. Caching the mask and dimensions once per
search did not produce a reliable gain: the two refactor runs measured 5.59 and
6.05 ms warm mean versus 5.12 ms before, and a later run after reverting it
measured 5.82 ms. The production refactor was removed. The earlier lazy
obstacle-result allocation and narrowed candidate bucket scans also failed to
show repeatable gains and were reverted.

- [Sampled full-game profile](../output/performance/current-full-profile-after-town-optimization-20261107/measurements.json)
- [Mask-backed route, before](../output/performance/walkmask-query-before-20261107/measurements.json)
- [Mask-backed route, after run 1](../output/performance/walkmask-query-after-20261107-1/measurements.json)
- [Mask-backed route, after repeat](../output/performance/walkmask-query-after-20261107-2/measurements.json)
- [Mask-backed route after revert](../output/performance/walkmask-query-restored-20261107/measurements.json)

### Follow-up: reuse truck-clearance checks during town generation — November 7, 2026

The seed-42 town-generation profile showed repeated truck-footprint clearance
checks while the same delivery-road samples appeared in multiple route pairs.
`driving_map.compile` now shares the existing rounded-sample cache across all
route checks for one fixed candidate world, including the mainland gate routes.
Every compile gets a fresh cache, and a rejected candidate still stops at its
first blocked sample.

On the same Windows RTX 3050 and seed 42, town generation fell from 3.69 s to
0.71/0.70 s, while calls to `Truck.blocked` fell from 62,918 to 3,945. All three
runs produced the same town ID, 17 buildings, and 2,546 road segments. The full
commute probe also completed after each change. The standalone probe runs town
generation synchronously; the normal town-setup flow runs it on a worker, so
this reduces generation wait time without changing frame mechanics. Android
and Steam Deck timing has not been measured.

- [Seed-42 town-generation profile](../output/performance/motorcycle-2026-11-07T11-14-17-961Z-fb44826e/measurements.json)
- [Unprofiled baseline](../output/performance/motorcycle-2026-11-07T11-16-52-602Z-e55897bd/measurements.json)
- [After, run 1](../output/performance/motorcycle-2026-11-07T11-19-15-797Z-291c734c/measurements.json)
- [After, repeat](../output/performance/motorcycle-2026-11-07T11-19-38-841Z-50e9e76f/measurements.json)

### Refreshed gameplay and mobile-layout probes — November 7, 2026

Two current full-game runs cover the populated shop, 10x game clock, office,
home, cutter, arcade, and a local three-guest session. They use the Windows
RTX 3050 desktop; the mobile-layout run changes the window to 1600x720 on that
same machine, so it is not a physical mobile-device result. Each run uses a
fresh private save identity.

In the crowded 14-machine, 80-pallet, 10-staff fixture, the 10x-clock update
measured 2.34 ms p95 in desktop layout and 2.17 ms in mobile layout. Presented
10x shop frames measured 6.17 and 5.51 ms p95. Presented home frames measured
0.66 and 1.07 ms p95; arcade frames measured 0.49 and 0.47 ms p95. A three-guest
in-memory host/client update measured 1.03 and 1.05 ms p95. That multiplayer
row covers session and serialization work without real network latency.

The largest repeatable main-thread cost in this baseline was saving a populated
state: snapshot plus worker dispatch measured 4.06/4.39 ms mean/p95 on desktop
and 4.02/4.39 ms in mobile layout. The save write and flush run after the timed
section. The follow-up below reduces the duplicate copy while preserving the
state captured for channel dispatch.

- [Current desktop probe](../output/performance/goal-current-baseline-20261107-v2/measurements.json)
- [Current mobile-layout probe](../output/performance/goal-current-mobile-layout-20261107-v2/measurements.json)

### Follow-up: avoid a duplicate Lua save-state copy — November 7, 2026

`Writer:dispatch` used to recursively allocate a second Lua table tree before
passing the save message through LÖVE's thread channel. It now checks that a
state contains only channel-safe keys and values and has no cycles, then sends
the state directly. Channel serialization detaches the queued message; states
with transient unsupported values still use the existing schema-snapshot
fallback, and schema normalization remains in the worker.

The populated save snapshot/dispatch row fell from 4.063 ms mean and 4.385 ms
p95 to 3.391/4.075 ms and 3.394/3.597 ms across two desktop repeats. The
1600x720 mobile-layout run measured 3.235/3.693 ms. Means improved by about
16% on desktop and 20% in the mobile layout. Each probe completed all 42 rows
and flushed its private save. Each row has 12 samples, so its reported p95 is
the sample maximum and varies more than the mean. These are Windows RTX 3050
measurements; the mobile-layout run is not a physical mobile device.

- [Baseline desktop](../output/performance/goal-current-baseline-20261107-v2/measurements.json)
- [After, desktop repeat 1](../output/performance/goal-save-channel-copy-after-1-20261107/measurements.json)
- [After, desktop repeat 2](../output/performance/goal-save-channel-copy-after-2-20261107/measurements.json)
- [After, mobile layout](../output/performance/goal-save-channel-copy-mobile-20261107/measurements.json)

### Follow-up: reuse segment-query scratch during NPC route search — November 7, 2026

The indexed route-detour profile repeatedly sampled temporary candidate and
deduplication tables in `ObstacleIndex.segment`. A single `Navigator.findPath`
now reuses those two buffers for synchronous segment checks, marking visited
obstacles with a per-search generation number. The scratch state is created
fresh for each route plan; obstacle snapshots and collision ordering are
unchanged. Other navigation callers retain the allocating path unless they pass
a scratch buffer.

Two desktop detour runs moved from 6.71/6.95 ms mean and 10.67/11.90 ms p95 to
4.85/5.32 ms mean and 5.23/5.71 ms p95. The forced 1600x720 layout moved from
6.97 ms mean and 8.62 ms p95 to 6.15 ms and 6.95 ms. The many-goal 640-contact
query remained near 4.9-5.1 ms mean, so this gain is specific to indexed
segment queries. Full probes completed all 42 rows; the diagnostic profile is
separate and not used for the timing comparison. These are Windows RTX 3050
results, including a forced layout rather than a physical mobile device.

- [Before, desktop repeat 1](../output/performance/goal-save-channel-copy-after-1-20261107/measurements.json)
- [Before, desktop repeat 2](../output/performance/goal-save-channel-copy-after-2-20261107/measurements.json)
- [After, desktop repeat 1](../output/performance/goal-navigation-scratch-after-1-20261107/measurements.json)
- [After, desktop repeat 2](../output/performance/goal-navigation-scratch-after-2-20261107/measurements.json)
- [Before, mobile layout](../output/performance/goal-save-channel-copy-mobile-20261107/measurements.json)
- [After, mobile layout](../output/performance/goal-navigation-scratch-mobile-20261107/measurements.json)
- [After, diagnostic profile](../output/performance/goal-navigation-scratch-profile-20261107/measurements.json)

### Follow-up: crowded multiplayer session capacity probe — November 7, 2026

Added a benchmark row that runs one host and three guest sessions against the
same dense save used by the single-player capacity rows: 14 machines, 80 active
jobs, and 10 employees. The host rebuilds the durable save snapshot as the game
does and marks it dirty nonurgently, exercising the normal four-per-second
snapshot limit. The probe records host and per-guest update times separately,
along with payload bytes by channel.

Across 600 simulated updates, the host measured 0.71 ms mean and 6.41 ms p95.
Each guest measured 0.73–0.77 ms mean and 9.88–9.97 ms p95. A durable packet
reached 456,226 bytes, close to the protocol's 512 KiB ceiling. Total egress in
the in-memory harness was 51.9 MB over ten simulated seconds, mostly durable
shop snapshots. The three guests run sequentially on this one desktop, so the
combined 36.46 ms p95 is not a per-device frame time. This synthetic maximum
state stayed within the 16.7 ms p95 budget on each simulated host or guest,
though occasional maxima exceeded it. The harness measures serialization and
local delivery only; it does not include real network latency or physical
Android/Steam Deck hardware.

- [Crowded multiplayer probe](../output/performance/goal-crowded-multiplayer-20261107-final/measurements.json)

### Follow-up: avoid re-encoding validated network packets — November 7, 2026

A focused LuaJIT profile of the crowded session placed repeated codec work on
the guest receive path. `Protocol.decode` parsed and normalized a packet, then
encoded the normalized tree again just to compare its bytes with the input.
`Codec.decode` already rejects noncanonical number and length tokens, unsorted
or duplicate map keys, and trailing bytes. Protocol normalization rejects
unknown fields and invalid values. Decoding now compares the normalized wire
shape directly with the decoded tree, including the compact workshop snapshot
representation, avoiding that second full serialization while preserving the
canonicality check.

With the same 14-machine, 80-job, 10-employee save and three guests, three clean
post-change runs reduced the average guest update from 0.758 ms to 0.463 ms
(39%) and the per-guest p95 from 9.94 ms to 6.03 ms (39%). Host update time
stayed near baseline at 0.74 ms mean and 6.91 ms p95. Payload sizes and packet
counts were unchanged; the largest durable packet remained 456,226 bytes. Each
run completed all 43 probe rows and all three guests joined. The host and guests
are simulated sequentially in one Windows RTX 3050 process; per-guest timings
are separate and this does not model real network latency or Steam Deck CPU
performance.

- [Before, crowded session baseline](../output/performance/goal-crowded-multiplayer-20261107-final/measurements.json)
- [After, repeat 1](../output/performance/goal-crowded-session-canonical-compare-20261107/measurements.json)
- [After, repeat 2](../output/performance/goal-crowded-session-canonical-compare-repeat2-20261107/measurements.json)
- [After, repeat 3](../output/performance/goal-crowded-session-canonical-compare-repeat3-20261107/measurements.json)
- [Focused diagnostic profile](../output/performance/goal-crowded-session-targeted-profile-20261107/measurements.json)
- [Post-change diagnostic profile](../output/performance/goal-crowded-session-postchange-profile-20261107/measurements.json)

The post-change profile shows binary parsing and schema normalization as the
remaining large-packet costs. A numeric-token parsing shortcut did not improve
the crowded-session repeats consistently, so it was reverted.

### Follow-up: cache walkmask dimensions during route searches — November 7, 2026

`Navigator.findPath` now fetches the walkmask and its dimensions once per
synchronous route search and reuses them for candidate checks and segment
sampling. The 640-contact synthetic walkmask probe fell from 6,106 asset and
dimension lookups per search to one each; pixel reads were unchanged at about
297,000 per search. The lookup reduction is clear, but route timings are not:
the baseline was 6.01 ms mean / 6.33 ms p95, and three after runs ranged from
5.72–8.90 ms mean / 6.20–9.42 ms p95. Nearby no-mask timings also varied, so
these Windows runs do not establish a frame-time gain. Keep this small cache
as a candidate and remeasure on steadier hardware; it does not change route
selection or collision behavior.

- [Before, route call counts](../output/performance/goal-walkmask-route-callcount-before-20261107/measurements.json)
- [After, repeat 1](../output/performance/goal-walkmask-route-cache-after-20261107-1/measurements.json)
- [After, repeat 2](../output/performance/goal-walkmask-route-cache-after-20261107-2/measurements.json)
- [After, noisy full run](../output/performance/goal-walkmask-route-cache-final-20261107/measurements.json)

### Follow-up: reduce work per decoded value — November 7, 2026

The crowded-session profile still showed repeated codec work while decoding
large snapshots. `Codec.decode` now reads each value tag as a byte instead of
creating a one-character substring, and the length/count scanner reads each
byte once instead of checking it twice. The accepted wire format and error
checks are unchanged.

On the same Windows desktop probe, the average update mean across three guests
fell from 0.606 ms before to 0.477 ms across two after runs (21%). Average
per-guest p95 fell from 8.26 ms to 6.04 ms (27%). Host update mean/p95 stayed
around 0.69/6.66 ms. The separate crowded single-player update row remained
around 1.07 ms mean and 2.4 ms p95. Each run completed all 43 probe rows and
the three guests joined. These are local in-memory session timings on one
Windows RTX 3050; they do not cover real network latency or Steam Deck
hardware.

- [Before, crowded-session baseline](../output/performance/goal-codec-byte-scan-before-20261107/measurements.json)
- [After, repeat 1](../output/performance/goal-codec-byte-scan-after-1-20261107/measurements.json)
- [After, repeat 2](../output/performance/goal-codec-byte-scan-after-2-20261107/measurements.json)

### Follow-up: reuse route segment candidate buffers — November 7, 2026

Current LuaJIT profiles showed route searches repeatedly clearing the temporary
obstacle candidate array before filling it again. Segment queries now return a
valid-prefix count and reuse the existing array slots; navigation checks only
that prefix. Obstacle ordering, deduplication and collision predicates remain
the same. The flat-cell-map experiment was reverted after two runs showed no
consistent route or crowded-update gain.

Across three after runs, the ten-worker machine-access workload averaged
1.60 ms mean and 3.38 ms p95, versus 1.82 ms mean and 4.00 ms p95 in two nearby
before runs (about 12% and 16% lower). Employee detour routing was slightly
lower; general route and full crowded-world timings did not show a broad change.
All 43 probe rows completed in each run. This is a Windows desktop result; it
does not establish performance on Linux or Steam Deck hardware.

- [Before, repeat 1](../output/performance/goal-codec-byte-scan-after-1-20261107/measurements.json)
- [Before, repeat 2](../output/performance/goal-codec-byte-scan-after-2-20261107/measurements.json)
- [After, repeat 1](../output/performance/goal-segment-buffer-after-1-20261107/measurements.json)
- [After, repeat 2](../output/performance/goal-segment-buffer-after-2-20261107/measurements.json)
- [After, repeat 3](../output/performance/goal-segment-buffer-after-3-20261107/measurements.json)
- [Current single-player profile](../output/performance/goal-singleplayer-profile-current-20261107/measurements.json)

### Follow-up: reduce temporary collision-list allocations — November 7, 2026

Employee movement obstacle snapshots now iterate application and staff arrays
directly in their existing order, applying the same pose lookup, visibility and
scene rules without first creating an actor list and wrapper records. Pallet
obstacles can append to the caller's collision list, removing the intermediate
list and copy loop. Collision records and their order are unchanged.

Three full probes before and three after both changes on the same Windows
desktop averaged 1.65 ms mean / 2.32 ms p95 for the crowded world at 10x clock
before and 1.53 ms / 2.25 ms after. Employee route detours averaged
4.04 ms / 6.75 ms before and 3.77 ms / 6.18 ms after; crowded route detours
averaged 5.04 ms / 5.94 ms before and 4.79 ms / 5.31 ms after. The ordinary
crowded-world update changed little. The ten-worker access row's mean rose
slightly (1.60 to 1.67 ms) while its p95 fell (3.38 to 3.16 ms), so that row
does not show a uniform gain. These in-memory desktop probes do not model Linux
or Steam Deck hardware.

- [Before, repeat 1](../output/performance/goal-segment-buffer-after-1-20261107/measurements.json)
- [Before, repeat 2](../output/performance/goal-segment-buffer-after-2-20261107/measurements.json)
- [Before, repeat 3](../output/performance/goal-segment-buffer-after-3-20261107/measurements.json)
- [After, repeat 1](../output/performance/goal-pallet-obstacle-append-after-1-20261107/measurements.json)
- [After, repeat 2](../output/performance/goal-pallet-obstacle-append-after-2-20261107/measurements.json)
- [After, repeat 3](../output/performance/goal-pallet-obstacle-append-after-3-20261107/measurements.json)

### Follow-up: direct employee rack-slot lookup — November 7, 2026

Employee supply stocking only needs the first unoccupied bottom-row rack
column. It now scans the existing job and procurement pallet owners directly,
without building the full three-row slot matrix and temporary per-pallet
wrapper list. The column order and the same rack/row/column validity checks
remain in use. The general `Storage.slots` query is unchanged for screens and
other callers.

A paired 600-call microbenchmark on the 80-active-pallet fixture averaged
0.003284 ms for the previous lookup and 0.000716 ms for the direct lookup
(4.59× faster across three runs). In three full gameplay probes, ordinary
crowded-update mean fell from 1.060 ms to 0.973 ms and 10×-clock mean from
1.527 ms to 1.421 ms. Their p95 results were mixed, and the ten-worker access
row did not improve, so the full-frame benefit remains small and uncertain.
These are Windows RTX 3050 measurements; they do not establish results on
Android, Linux, or Steam Deck hardware.

- [Previous lookup, paired run 1](../output/performance/goal-first-open-slot-paired-1-20261107/measurements.json)
- [Previous lookup, paired run 2](../output/performance/goal-first-open-slot-paired-2-20261107/measurements.json)
- [Previous lookup, paired run 3](../output/performance/goal-first-open-slot-paired-3-20261107/measurements.json)
- [Full probe before, repeat 1](../output/performance/goal-pallet-obstacle-append-after-1-20261107/measurements.json)
- [Full probe before, repeat 2](../output/performance/goal-pallet-obstacle-append-after-2-20261107/measurements.json)
- [Full probe before, repeat 3](../output/performance/goal-pallet-obstacle-append-after-3-20261107/measurements.json)
- [Full probe after, repeat 1](../output/performance/goal-first-open-rack-slot-after-1-20261107/measurements.json)
- [Full probe after, repeat 2](../output/performance/goal-first-open-rack-slot-after-2-20261107/measurements.json)
- [Full probe after, repeat 3](../output/performance/goal-first-open-rack-slot-after-3-20261107/measurements.json)

### Follow-up: refresh the outdoor rendering profile — November 7, 2026

A fresh ten-stage commute profile on the Windows RTX 3050 showed the outdoor
ride-streaming stage at 3.26 ms mean / 5.12 ms p95 and first-person streaming
at 2.92 / 5.31 ms. LuaJIT samples clustered in the per-prop outdoor sprite
pass and first-person billboards. The profiler points to CPU/LÖVE submission
work; it does not separate GPU execution time. A current ADB inventory could
not start the local server, so this does not replace the outstanding phone
measurement.

I tried hoisting static rock-variant lists and precomputing static sprite keys.
Three unprofiled full-run comparisons showed no reliable improvement, so that
experiment was reverted. Frame mean/p95 averages were:

| Stage | Before, ms | After, ms |
|---|---:|---:|
| Stationary | 2.15 / 3.05 | 2.24 / 3.15 |
| Ride streaming | 3.20 / 4.97 | 3.21 / 4.77 |
| First-person steady | 2.08 / 2.75 | 2.14 / 2.85 |
| First-person streaming | 2.85 / 4.82 | 2.93 / 5.08 |

These Windows 1280×880, VSync-off values do not establish Android, Linux, or
Steam Deck performance. Any next outdoor optimization needs to address the
per-prop draw path while preserving depth ordering, seasonal tint, and sway.

- [Current outdoor profile](../output/performance/goal-current-outdoor-profile-20261107/measurements.json)
- [Before, repeat 1](../output/performance/goal-rock-variant-allocation-before-1-20261107/measurements.json)
- [Before, repeat 2](../output/performance/goal-rock-variant-allocation-before-2-20261107/measurements.json)
- [Before, repeat 3](../output/performance/goal-rock-variant-allocation-before-3-20261107/measurements.json)
- [After, repeat 1](../output/performance/goal-rock-variant-allocation-after-1-20261107/measurements.json)
- [After, repeat 2](../output/performance/goal-rock-variant-allocation-after-2-20261107/measurements.json)
- [After, repeat 3](../output/performance/goal-rock-variant-allocation-after-3-20261107/measurements.json)

### Follow-up: reject per-page outdoor plant batching — November 7, 2026

I tried a same-order `SpriteBatch` path carrying depth, fade, and tint in
per-vertex float attributes. It reduced stationary draw calls from 1,334 to
1,140, but stationary draw time rose from 1.85 ms mean / 2.10 ms p95 to
31.49 / 35.45 ms. The interrupted capture run had already completed 180
stationary samples with 1,260 visible props. The batch flushed and updated its
shared attribute mesh at atlas-page changes; preserving prop order left too
many expensive transitions for this design to help. I removed the runtime
change.

A clean probe after the revert returned stationary draw time to 1.85 / 2.14 ms
and ride-streaming to 2.13 / 2.35 ms, consistent with the captured baseline at
1.85 / 2.10 and 2.08 / 2.36 ms. The next outdoor pass should first measure
screen-space rejection or page-run frequency while preserving depth order,
seasonal tint, and sway.

These are Windows RTX 3050, 1280×880, VSync-off measurements. They do not
establish Android, Linux, or Steam Deck performance.

- [Captured baseline](../output/performance/goal-outside-plantbatch-before-20261107/measurements.json)
- [Rejected batch attempt](../output/performance/goal-outside-plantbatch-after-capture-1-20261107/measurements.json)
- [Post-revert check](../output/performance/goal-outside-plantbatch-reverted-check-20261107/measurements.json)

### Follow-up: cull outdoor props beyond the screen — November 7, 2026

A post-frame diagnostic estimated that 1,166 of 1,260 stationary-view props
and 1,212 of 1,318 ride-streaming props were fully outside the 1280×880 scene
canvas. The renderer now skips those billboards before depth, fade, sway, and
draw submission. Its bounds include the full 256-pixel sprite cell, the
maximum plant sway shear, and a two-pixel margin; the remaining props retain
their original order and rendering state.

Three clean full probes showed lower third-person frame and draw time:

| Stage | Frame mean / p95 before → after, ms | Draw mean before → after, ms | Draw calls before → after |
|---|---:|---:|---:|
| Stationary | 2.15 / 3.05 → 0.75 / 1.64 | 1.88 → 0.40 | 1,334 → 168 |
| Ride streaming | 3.20 / 4.97 → 1.49 / 3.05 | 2.15 → 0.48 | 1,390 → 179 |
| Camera rotation | 2.27 / 3.25 → 0.85 / 1.79 | 1.89 → 0.45 | 1,415 → 197 |
| Zoomed-out steady | 2.19 / 3.16 → 1.06 / 2.01 | 1.82 → 0.66 | 1,416 → 379 |

The separate first-person renderer stayed near its prior results. Captured
stationary and riding views showed no visible loss; the stationary first
capture was pixel-identical, and the other matched captures differed by at
most three RGB levels per pixel. These measurements are Windows RTX 3050,
1280×880, VSync-off results and do not establish Android, Linux, or Steam Deck
performance.

- [Pre-change screen-cull diagnostic](../output/performance/goal-outdoor-culling-diagnostic-20261107/measurements.json)
- [Captured views after culling](../output/performance/goal-outdoor-screen-cull-capture-20261107/)
- [Repeat 1](../output/performance/goal-outdoor-screen-cull-after-1-20261107/measurements.json)
- [Repeat 2](../output/performance/goal-outdoor-screen-cull-after-2-20261107/measurements.json)
- [Repeat 3](../output/performance/goal-outdoor-screen-cull-after-3-20261107/measurements.json)

### Follow-up: cull off-screen first-person plant billboards — November 7, 2026

The first-person billboard pass already rejects props by view depth, world
radius, and a broad horizontal bound. A post-frame diagnostic found more
props that passed those checks but whose projected sprite rectangles were
fully outside the canvas: about 186 in steady view, 164 while streaming, and
114 during rotation. The renderer now checks the full sprite bounds, including
the pivot offset, maximum sway, camera roll, and a two-pixel margin, before
sending per-sprite shader values. The optional bound applies only to plant
billboards; actor drawing keeps its existing path.

Three clean full probes show repeatable reductions:

| Stage | Frame mean / p95 before → after, ms | Draw mean before → after, ms | Draw calls before → after |
|---|---:|---:|---:|
| First-person steady | 2.17 / 2.88 → 1.91 / 2.60 | 1.77 → 1.54 | 940 → 756 |
| First-person streaming | 2.96 / 5.05 → 2.78 / 4.98 | 1.82 → 1.62 | 957 → 795 |
| First-person rotation | 1.99 / 2.88 → 1.81 / 2.69 | 1.57 → 1.41 | 822 → 709 |

Matched steady, streaming, and rotation captures were pixel-identical before
and after. These are Windows RTX 3050, 1280×880, VSync-off measurements; they
do not establish Android, Linux, or Steam Deck performance.

- [Pre-change first-person culling diagnostic](../output/performance/goal-firstperson-culling-diagnostic-20261107/measurements.json)
- [Captured views after culling](../output/performance/goal-firstperson-screen-cull-capture-20261107/)
- [Before, repeat 1](../output/performance/goal-outdoor-screen-cull-after-1-20261107/measurements.json)
- [Before, repeat 2](../output/performance/goal-outdoor-screen-cull-after-2-20261107/measurements.json)
- [Before, repeat 3](../output/performance/goal-outdoor-screen-cull-after-3-20261107/measurements.json)
- [After, repeat 1](../output/performance/goal-firstperson-screen-cull-after-1-20261107/measurements.json)
- [After, repeat 2](../output/performance/goal-firstperson-screen-cull-after-2-20261107/measurements.json)
- [After, repeat 3](../output/performance/goal-firstperson-screen-cull-after-3-20261107/measurements.json)

### Follow-up: reuse sequential NPC obstacle-index storage — November 7, 2026

Crowded single-player profiles repeatedly sampled construction of the spatial
obstacle index during employee movement. The index builder can now recycle its
cell tables after a synchronous move finishes. Each move still builds a fresh
collision snapshot; only cleared temporary table storage is reused. A steady
snapshot also skips redundant position interpolation when a pallet's spawn
progress is exactly complete.

Two unprofiled full-game probes improved the crowded update workload and its
10x-clock version:

| Scenario | Control mean / p95, ms | After repeat 1 | After repeat 2 |
|---|---:|---:|---:|
| 14 machines, 80 pallets, 10 staff | 0.99 / 2.42 | 0.80 / 1.48 | 0.82 / 1.43 |
| Same scene at 10x clock | 1.46 / 2.63 | 1.14 / 1.57 | 1.16 / 1.63 |

The profiler also showed index-construction samples falling from 25 to 11 in
the normal crowded update and from 41 to 19 at 10x clock. The dedicated
workers-seeking-machine-access row did not show the same benefit: its control
was 1.79 / 3.20 ms, compared with 1.84 / 3.45 and 1.89 / 4.80 ms after. The
main crowded update gains repeat, but this path-heavy case remains a follow-up
target. Presented-frame timings varied between runs, so no rendering or GPU
gain is claimed.

Measurements use the Windows RTX 3050 desktop probe. They do not establish
Linux or Steam Deck performance; no Steam Deck build was made.

- [Profile before reuse](../output/performance/goal-crowded-obstacle-branch-profile-20261107/measurements.json)
- [Profile after reuse](../output/performance/goal-obstacle-index-reuse-profile-20261107/measurements.json)
- [No-reuse control](../output/performance/goal-obstacle-index-reuse-control-20261107/measurements.json)
- [After, repeat 1](../output/performance/goal-obstacle-index-reuse-unprofiled-20261107/measurements.json)
- [After, repeat 2](../output/performance/goal-obstacle-index-reuse-repeat-20261107/measurements.json)

### Follow-up: avoid redundant protocol tree walks — November 7, 2026

The multiplayer profile still showed time in protocol encoding and canonical
comparison. The canonical comparer now returns immediately for identical table
references, which occur when envelope normalization preserves large state
payloads. The codec also collects a map's keys during its table-classification
pass, then sorts that list for canonical output instead of traversing the map
again to collect the same keys. Wire order, validation, and packet sizes are
unchanged.

The crowded three-guest measurements were noisy and do not establish a
consistent end-to-end gain. The current pre-change run was 2.23 ms mean / 27.52
ms p95 combined host plus guest time. The two reference-check runs were 2.17 /
23.05 and 2.42 / 30.33 ms; the two map-key runs were 2.22 / 27.31 and 2.52 /
31.12 ms. Host and guest sub-times varied between runs, while payload size and
throughput remained unchanged. Treat these as code-path reductions to
remeasure, not a demonstrated multiplayer performance improvement. This
in-memory harness runs host and guests sequentially on one Windows desktop and
does not measure physical network latency or Steam Deck performance.

- [Before](../output/performance/goal-codec-shared-tree-before-20261107/measurements.json)
- [Reference-check repeat 1](../output/performance/goal-codec-shared-tree-after-1-20261107/measurements.json)
- [Reference-check repeat 2](../output/performance/goal-codec-shared-tree-after-2-20261107/measurements.json)
- [Map-key repeat 1](../output/performance/goal-codec-mapkeys-after-1-20261107/measurements.json)
- [Map-key repeat 2](../output/performance/goal-codec-mapkeys-after-2-20261107/measurements.json)
- [Profile after map-key change](../output/performance/goal-codec-mapkeys-profile-after-20261107/measurements.json)

### Follow-up: compress large durable multiplayer packets — November 7, 2026

The dense shop-state packet is now LZ4-compressed when it is at least 4 KiB
and compression saves at least 64 bytes. The `TPSL` frame is recognized by the
protocol decoder; its declared decompressed size is checked against the 512
KiB shop-packet limit before decompression. The network protocol version moved
from 69 to 70 so older clients are rejected during discovery/handshake instead
of receiving an unknown packet format. Save data and gameplay state are
unchanged.

Three full crowded-shop probes connected three guests through the real Session
protocol. The same 456,226-byte shop state encoded to 23,044–23,046 bytes on
the wire, about 95% smaller. Over the ten-second simulated session, total
payload fell from 51,854,877 bytes (5,064 KiB/s) to 4,178,697–4,178,703 bytes
(408 KiB/s), a 92% reduction. The focused LZ4 operation averaged 0.054–0.058
ms to compress and 0.030–0.031 ms to decompress on this Windows RTX 3050
desktop. Protocol encode/decode and combined host/guest frame timings varied
between runs, so no CPU or frame-rate improvement is claimed from this change.

The harness runs host and guests sequentially in one process. It does not
measure physical network latency, Linux, or Steam Deck performance; no Steam
Deck build was made.

- [Uncompressed baseline](../output/performance/goal-crowded-session-postchange-profile-20261107/measurements.json)
- [Compressed probe 1](../output/performance/goal-network-compression-implementation-20261107/measurements.json)
- [Compressed probe 2](../output/performance/goal-network-compression-repeat2-20261107/measurements.json)
- [Compressed probe 3](../output/performance/goal-network-compression-repeat3-20261107/measurements.json)
