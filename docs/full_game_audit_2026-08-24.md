# The Picture Shop — Full Game Audit and Cleanup Report

Date: 2026-08-24
Engine verified: LÖVE 11.5
Audit scope: implemented runtime systems, save/state flow, input and UI routes, live assets, smoke coverage, project hygiene, performance risks, and the currently reachable gameplay loop.

## Executive summary

The implemented vertical slice now completes its full tested loop: protect/create a shop, accept work, receive and stage pallets, cut every lift, package, schedule pickup, load the outbound truck, collect payment, archive the job, save, and recover. All four original P0 findings, all five P1 blockers, all eight P2 integration findings, and the four P3 cleanup/scaling findings have been addressed through the ordered steps below.

The final engine run completes **559 named checks with 0 failures** plus the required three rendered frames. The raster doctor completes **162 checks with 0 failures**. An audit coverage manifest ties every resolved P0/P1/P2 finding to required regressions, and the working texture footprint at startup is **42.69 MiB**, about 74.4% below the original ~167 MiB baseline.

The project is ready for balancing, playtesting, and carefully scoped content expansion. Remaining ideas at the end of this report are recommendations rather than known correctness blockers.

## Project snapshot

- 54 Lua files and about 9,900 lines of Lua after the added gameplay systems and modular regression suites.
- 517 workspace files totaling about 144 MiB, excluding Git internals.
- `assets/` is about 90 MiB; `output/` is about 52 MiB.
- The retained startup texture set is 42.69 MiB; machine and visitor packs load on demand.
- `assets/Machines/movingPicturePress_files/` alone contains 161 downloaded webpage-support files totaling about 37 MiB.
- Git is a separate repository rooted at The Picture Shop, on `master`, using `John <johnwestontattoos@gmail.com>`. It has no remote and is not connected to Mouse Frontier.

## Validation results

### Passed

- LÖVE 11.5 launched the project successfully.
- The hidden watchdog smoke test completed: 559 passes, 0 failures, three frames rendered.
- Required warehouse, walkmask, machine, loading-bay, truck, pallet, pallet-jack, wrapper, and registered character assets loaded.
- Warehouse/walkmask dimensions and binary mask values passed.
- Current sprite strips and atlases satisfy exact dimension/grid contracts with nonempty cells.
- The full accept-to-payment loop, vendor supply consumers, receiving occupancy, multi-lift production, physical ownership, save v1/v2 migration, crash recovery, and input parity pass.
- Focused domain suites, engine integrations, duplicate-name detection, and audit-to-regression coverage pass.

### Intentional boundaries

- The picture press and unplaced prop/machine art remain outside the live runtime contract until complete gameplay consumers exist.
- The suite validates deterministic workflows and three render frames; extended human playtesting is still needed for pacing, learnability, economy balance, and visual comfort.
- Disposable generated previews and the large downloaded press-reference mirror remain source/artifact hygiene opportunities, not runtime correctness issues.

## Original findings and resolutions

Severity guide:

- **P0:** possible data loss, crash, or contradictory ownership/state corruption.
- **P1:** blocks or materially breaks the main gameplay loop.
- **P2:** reachable inconsistency, missing integration, or significant polish/maintainability problem.
- **P3:** cleanup, diagnostics, documentation, or future scaling concern.

### P0 — fix before expanding the game

#### P0-01: New Shop can silently overwrite an occupied save

Resolution: **Fixed in Step 1.** Occupied slots require confirmation, Cancel preserves the original bytes, and mouse/keyboard routes share the same tested action.

`src/screens/title_screen.lua:27-30` creates a new payload immediately, and the New Shop click path at `src/screens/title_screen.lua:53` has no occupied-slot confirmation. The live title-screen check also confirmed that the advertised keyboard workflow is absent, making a mistaken mouse click the only active route.

Implemented scope: show a clear overwrite confirmation for an occupied slot, preserve the existing slot until confirmation, and add a regression check that Cancel leaves the original save byte-for-byte readable.

#### P0-02: Exiting during skid wrapping can crash the world update

Resolution: **Fixed in Step 2.** Active wrapping blocks both exit routes and relocation until the single-use cycle finishes with valid state.

Escape or the Exit button returns to the world without stopping the active wrapper cycle (`src/input.lua:18-23`, `src/input.lua:147-153`). The world branch then calls `Wrapper.update(dt)` without the state object (`src/app.lua:116-120`). Once the cycle reaches completion, `src/wrapper.lua:47-48` dereferences `state.inventory`.

Implemented scope: define one lifecycle policy—finish in the background, pause, or prevent exit during the three-second cycle—and always update the wrapper with valid state. Test Escape and mouse Exit at the start, middle, and final frame of wrapping.

#### P0-03: Save/new-game schema loses intended state

Resolution: **Fixed in Step 3.** Save format 3 owns exact defaults, migration, validation, reconciliation, film, equipment, and pallet ownership.

`State.new()` supplies one plastic-wrap roll with 11 uses (`src/state.lua:13-21`), but `Save.newGame()` omits both fields (`src/save.lua:145-173`). After `State.applySave()`, a newly created shop therefore starts with zero film. The save payload also omits `state.wrapper` (`src/save.lua:193-215`), even though load code expects it (`src/state.lua:79-84`), so wrapper relocation is lost on reload.

Implemented scope: introduce a new save version with explicit defaults and v1/v2 migration; persist wrapper placement and film state; verify all three slot operations and round-trip every persistent field.

#### P0-04: Cutter and pallet jack can own the same pallet

Resolution: **Fixed in Step 5.** Central pallet transitions enforce one owner and reject cutter claims on carried or unstaged pallets.

The cutter accepts any incomplete paper whose location is not `awaiting_delivery` or `none` (`src/machine.lua:32-45`). This includes `on_pallet_jack`. Loading changes the pallet to `at_cutter` (`src/machine.lua:71-90`) but does not clear the jack's `carriedPalletId`, creating contradictory ownership and allowing later movement/output code to manipulate the same pallet.

Implemented scope: centralize legal pallet-location transitions, reject cutter loading unless the pallet is staged on clear floor near the cutter, and add invariant checks ensuring one pallet has exactly one owner/location.

### P1 — main-loop blockers

#### P1-01: Jobs cannot be completed, picked up, or paid

Resolution: **Fixed in Step 6.** The outbound pickup, payment, pallet removal, archive, and autosave loop is complete.

The computer's completion button only returns `completion_ready` (`src/screens/computer_screen.lua:178-181`). Input then displays that completion and pickup scheduling are not connected (`src/input.lua:164-168`). No code moves a job from active to completed, removes wrapped pallets, changes accounts receivable into cash, or schedules an outbound truck.

Implemented scope: implement `in_production -> ready_for_pickup -> pickup_in_progress -> completed`, an outbound manifest/truck flow, active/completed collection transfer, pallet removal, AR settlement, and autosaves at each irreversible transition.

#### P1-02: Repeated deliveries overlap pallets at fixed coordinates

Resolution: **Fixed in Step 7.** Receiving lanes reserve clear positions, block atomically when full, and reopen after pallets move.

Customer and vendor unloads reuse the same five configured spawn points (`src/config.lua:118-134`, `src/pallet_logistics.lua:65-76`, `src/procurement.lua:104-114`). No occupancy check reserves a receiving position. Later jobs and every single-pallet vendor order can stack directly on existing pallets, producing ambiguous tooltips and collision.

Implemented scope: create receiving-lane slots with occupancy checks, block an unload when no slot is clear, and guide the player to move staged pallets before continuing.

#### P1-03: Cutter input/output ignores physical logistics

Resolution: **Fixed in Step 8.** Input requires a nearby feed-side pallet and output searches validated clear floor positions.

The cutter selects the first eligible pallet anywhere in the warehouse rather than a nearby staged pallet (`src/machine.lua:32-45`, `src/machine.lua:71-78`). Finished output uses a fixed offset from the cutter without testing the walkmask or other objects (`src/machine.lua:17-29`, `src/machine.lua:316-320`). A relocated cutter can therefore teleport input or place output inside walls, machines, or other pallets.

Implemented scope: require a specific nearby pallet, add a pallet selector when more than one is valid, reserve a clear cutter input/output zone, and reject/redirect unsafe output placement.

#### P1-04: Quoted lift workload is bypassed

Resolution: **Fixed in Step 9.** One manual verified lift establishes the program and each remaining lift advances saved sheet counts explicitly.

Jobs quote one charge for every 500-sheet lift (`src/jobs.lua:13-14`, `src/jobs.lua:137-159`), but the cutter performs one four-margin program for an entire pallet and then marks every required lift complete (`src/machine.lua:273-325`). A 500-sheet pallet and a 3,000-sheet pallet require essentially the same player work despite a sixfold quote difference.

Implemented scope: represent the active lift and remaining sheets explicitly. To avoid excessive repetition, make the first lift a manual setup/quality check and allow safe repeat production for the remaining programmed lifts.

#### P1-05: Saves are not crash-safe

Resolution: **Fixed in Step 4.** Validated temporary writes, last-known-good backup, automatic recovery, and damaged-slot display are live.

`src/save.lua:221-222` writes directly over the only slot file. A crash, disk interruption, or OneDrive sync conflict during the write can turn the slot into an unreadable empty listing. Validation is also shallow and does not reconcile cached inventory totals against pallet records.

Implemented scope: write and validate a temporary payload, preserve a last-known-good backup, then promote it; recover automatically from a valid backup; validate nested job/pallet/paper fields; and rebuild derived inventory totals on load.

### P2 — incomplete or inconsistent integrations

#### P2-01: Picture press is visually present in code but unreachable and inert

Resolution: **Fixed in Step 11.** The unfinished press is excluded from the runtime contract while its reference art remains available for later development.

The press asset and a press UI branch exist, but the world has no press placement/interactable, input never assigns `machineType = "picture_press"`, and the machine-screen update/input routes do not run `Press.update` or `Press.keypressed`. The prototype also increments an internal sheet count without consuming inventory, producing saved output, or affecting jobs.

Implemented scope: either remove it from the live runtime contract until ready, or add a complete placement, interaction, update, input, inventory, save, and production flow.

#### P2-02: Vendor purchases are delivered but mostly have no gameplay use

Resolution: **Fixed in Step 10.** Active catalog items feed production paper, cartons, and wrapper film through the tracked delivery flow.

Vendor unloading adds quantities to `inventory.stock` (`src/procurement.lua:104-117`), but that stock is not displayed in the computer inventory and is not consumed by production. Delivered `stretch_film` does not add `plasticWrapRolls`; boxed jobs do not require cartons; paper and press supplies do not feed a press. The separate computer button bypasses delivery and buys film instantly.

Implemented scope: give every catalog item a defined inventory effect and consumer, show all stock, and use the same delivery-based purchasing model for film instead of maintaining two unrelated film systems.

#### P2-03: Input documentation and actual behavior disagree

Resolution: **Fixed in Steps 1 and 15.** Title controls, overlay closes, visible buttons, Escape, prompts, and README instructions agree.

The README advertises W/S or arrows, N, C/Enter, D, and Y/N on the title screen, while `src/input.lua:26-28` intentionally ignores all title keys. The README also says Escape closes a GUI, but job paperwork blocks Escape while a clickable Back button exists.

Implemented scope: implement the documented keyboard routes (recommended for accessibility) or rewrite the controls section and on-screen prompts to exactly match behavior. Test mouse and keyboard parity for every screen.

#### P2-04: Vendor Back behavior is inconsistent

Resolution: **Fixed in Step 15.** Back and Escape both close the catalog and leave the vendor waiting.

Mouse Back cancels the vendor review and leaves the representative waiting (`src/input.lua:125-133`), but Escape calls `resolveVendor` and sends the representative away (`src/input.lua:18-23`). This conflicts with the README's statement that Back actions leave NPCs waiting.

Implemented scope: route Back and Escape through one screen-close action and one documented visitor policy.

#### P2-05: Moving equipment can clip the walkmask, and operator walk animation is reset

Resolution: **Fixed in Step 12.** Oriented footprints validate every movable object and motion flags survive through rendering.

The cutter checks several footprint edge points, but the wrapper, pallet jack, and dropped pallets mostly validate only a center point against the walkmask. Large objects can therefore cross a wall/floor boundary. Separately, `CutterPlacement.ensure()` resets `inMotion` and `PalletJack.ensure()` resets `moving`; later calls during the same update clear the values before player animation reads them.

Implemented scope: use oriented footprint/corner checks for every movable object and separate data validation from per-frame mutation so animation state survives through draw.

#### P2-06: Asset load failures are recorded but hidden in normal play

Resolution: **Fixed in Step 13.** Startup stops on a readable, path-specific diagnostic screen for missing or malformed required assets.

`Assets` and `CharacterAssets` collect failure messages, but `src/app.lua:70-76` does not call their health assertions or show a diagnostic screen. A missing sprite can silently become an invisible object or fallback rectangle outside the smoke environment.

Implemented scope: fail into a readable asset-error screen in development/release startup, listing the exact missing or malformed paths, while retaining safe fallbacks only where intentional.

#### P2-07: Office status views are incomplete

Resolution: **Fixed in Step 15.** Shared labels, customer deliveries, outbound pickups, purchase orders, and all usable stock appear in the office.

The label table omits the live `in_production` status, so it appears as a raw internal string. The Deliveries tab excludes vendor purchase orders, and the Inventory tab omits `inventory.stock`. Completed jobs stay empty because completion is not connected.

Implemented scope: define one status vocabulary, include inbound purchase orders and outbound pickups, and display every inventory bucket the player can buy or consume.

#### P2-08: Two live atlases do not have exact grid dimensions

Resolution: **Fixed in Step 13.** Promoted atlases use exact grids and both runtime and doctor validate every cell.

The vendor atlas is 1254×1254 for a 4×4 grid, and the boxed-pallet atlas is 1402×1122 for a 5×4 grid. Runtime registration floors the cell dimensions and leaves edge pixels unused. The asset doctor does not currently validate these three newer contracts (vendor atlas, boxed atlas, Polar Back strip), although smoke verifies that quads exist.

Implemented scope: normalize the atlases to exact cell multiples, validate exact dimensions/divisibility and nonempty cells, and add the omitted contracts to the asset doctor.

### P3 — cleanup and scaling debt

#### P3-01: Large assets are loaded eagerly, including unused content

Resolution: **Fixed in Step 14.** CPU-only collision data, on-demand screen/visitor packs, precomputed anchors, and right-sized UI art reduce startup textures by 74.4%.

All configured images load at startup, roughly 167 MiB decoded. About 30 MiB comes from the unused base Polar sheet and unplaced prop sheets (empty pallet, paper stack, boxes, and toolboxes). The inaccessible press adds another 4 MiB, and an unused character `use` strip adds about 3 MiB. The retained walkmask image data adds CPU memory on top of its texture.

Implemented scope: separate always-on world assets from screen/machine/character packs, load on demand, release inactive packs, and stop loading assets that have no reachable renderer.

#### P3-02: Project artifact boundaries are unclear

Resolution: **Fixed in Steps 0 and 17.** Git ignore/allowlist rules, source-control documentation, and the runtime asset manifest define the boundary.

Runtime art, canonical sources, generated drafts, doctor previews, reports, and a downloaded webpage mirror are mixed across `assets/` and `output/`. Many files are byte-for-byte duplicates. There is no root `.gitignore`; Python bytecode is currently visible to Git. `output/` cannot simply be ignored yet because some documented build scripts treat selected files there as preserved sources.

Implemented scope: create an asset manifest and move canonical inputs to a stable source folder, keep promoted runtime files in `assets/generated`, route disposable previews/reports to an ignored build-output folder, ignore caches and smoke output, and archive or exclude the 37 MiB webpage mirror.

#### P3-03: Test and UI helper code is becoming monolithic

Resolution: **Fixed in Steps 16 and 17.** Domain and integration suites, audit coverage, a shared UI module, and a separate world renderer divide responsibilities.

`src/smoke.lua` is 907 lines and `src/world.lua` is 840 lines. Screen modules duplicate rectangle hit tests, panels, number formatting, button rendering, and pagination behavior. `src/press.lua` and `src/wrapper_placement.lua` use dense one-line functions inconsistent with the rest of the project.

Implemented scope: split domain tests from rendered integration tests, extract shared UI primitives, divide world simulation/rendering/logistics, and reformat dense modules without changing behavior.

#### P3-04: Stale implementation text remains visible

Resolution: **Fixed in Step 17.** Milestone comments, implementation-language catalog messages, and stale workflow documentation were removed or rewritten in player terms.

Examples include “Pallet inventory arrives in step seven” in `src/world.lua:155`, the outdated future-popup comment in `src/customer.lua:1-3`, and the completion placeholder message in input. These make implemented features look unfinished or obscure what is truly missing.

Implemented scope: remove milestone language from player-facing copy and update comments/README after each completed fix.

## Available assets not yet integrated

No rush is recommended on these until the P0/P1 work is stable.

- Generated but unregistered: flannel-otter walk strip.
- Source/reference machine art: 28×40 laminator, GBC laminator, two- and four-color presses, die cutter, folder gluer, recycle baler, windmill views, and paper press references.
- Loaded but unplaced props: empty pallet, paper stack, paper-storage boxes, small toolbox, and large toolbox.
- Generated drafts/alternates: older warehouse layouts and masks, draft rabbit atlas, alternate Polar sheets, and skid-wrapper intermediate sprites.

The picture press is different from the other backlog assets: it is already loaded and has partial code, so it should either be completed or removed from the live contract to avoid carrying a misleading half-system.

## Ordered one-fix-at-a-time plan

### Step 0 — Establish the Git baseline

Status: **Completed 2026-08-24.** The project has a separate repository, documented tracking boundary, validated asset allowlist, and clean initial baseline commit.

1. Add a root `.gitignore` for Python caches, smoke reports/watchdog files, temporary save/build files, and disposable audit previews.
2. Inventory which `output/` files are canonical rebuild inputs before ignoring or moving anything.
3. Track code, documentation, tools, launchers, active runtime assets, and approved canonical source assets.
4. Keep The Picture Shop's repository separate; add a remote only if explicitly chosen later.
5. Run smoke and asset doctor, then create the initial baseline commit.

Acceptance: clean `git status`, reproducible runtime assets, green smoke/asset checks, and no required source hidden by ignore rules.

### Step 1 — Protect occupied save slots

Status: **Completed 2026-08-24.** Occupied slots require an explicit overwrite confirmation; mouse and keyboard Cancel preserve the prior save byte-for-byte, and title actions now have keyboard parity.

Add overwrite confirmation and keyboard parity on the title screen.

Acceptance: New Shop on an occupied slot cannot alter it without explicit confirmation; Cancel preserves it; empty-slot creation still works.

### Step 2 — Fix wrapper screen lifecycle

Status: **Completed 2026-08-24.** Active wrap cycles now remain on the console until completion; Escape, mouse Exit, reset, and relocation are blocked, every update receives valid state, and start/middle/final-frame regressions verify exactly one film use.

Choose and implement a single exit/update policy, pass valid state to all wrapper updates, and prevent relocation while actively wrapping.

Acceptance: Escape and mouse Exit at every point in a wrap cycle never crash, duplicate film use, or lose/duplicate pallet status.

### Step 3 — Upgrade the save schema

Status: **Completed 2026-08-24.** Save format 3 now shares exact defaults with runtime state, migrates v1/v2, persists film and wrapper placement, validates nested jobs/pallets/paper/orders, reconciles pallet totals, and round-trips every persistent field across all three slots.

Add film and wrapper fields, exact defaults, v1/v2 migration, nested validation, and state reconciliation.

Acceptance: new shops start with the intended film; wrapper position/direction, pallet ownership, inventory, jobs, and player position survive all round trips.

### Step 4 — Make saves crash-safe

Status: **Completed 2026-08-24.** Saves now validate a temporary payload before promotion, rotate the prior valid primary into a last-known-good backup, recover from valid temporary/backup copies, and show an explicit damaged-slot state when recovery is impossible.

Add temporary-write validation, last-known-good backup, recovery, and a visible corrupted-slot status.

Acceptance: simulated truncated/invalid primary saves recover from backup without presenting the slot as empty.

### Step 5 — Enforce pallet ownership/location invariants

Status: **Completed 2026-08-24.** Deliveries, the pallet jack, decline handling, and the cutter now share one transition authority with rollback and whole-state invariant checks. Cutter input accepts only its existing owned pallet or an unfinished floor pallet staged nearby; carried/distant/double-owned pallets are rejected unchanged, and contradictory legacy ownership is reconciled on load.

Centralize allowed location transitions and require cutter staging/proximity.

Acceptance: a pallet cannot be simultaneously on a jack, truck, cutter, wrapper/output zone, or warehouse floor; invalid transitions leave all state unchanged.

### Step 6 — Add occupied receiving lanes

Status: **Completed 2026-08-24.** Customer and vendor manifests now share five occupancy-aware receiving lanes. Full receiving blocks the unload before any job, order, inventory, or pallet mutation; the manifest reports available capacity and tells the player to move a staged pallet before retrying.

Reserve clear unload slots and block unloading when the receiving area is full.

Acceptance: two consecutive five-pallet jobs plus vendor orders never overlap pallets, and the UI explains how to clear the lane.

### Step 7 — Validate cutter input/output zones

Status: **Completed 2026-08-24.** Cutter input is now an orientation-aware feed-side zone, with the nearest eligible floor pallet selected deterministically. Output searches ordered positions around the relocated cutter and validates the full pallet footprint against the walkmask, walls, truck, cutter, wrapper, jack, and every other physical pallet. A full output area leaves production unchanged and completed work at the cutter can be resumed after the player clears space.

Add nearby-pallet selection and safe output placement around every cutter orientation/location.

Acceptance: no input teleporting and no output inside walls, machines, trucks, pallets, or non-walkable space.

### Step 8 — Complete the job/pickup/payment loop

Status: **Completed 2026-08-24.** Fully cut and wrapped jobs can now request customer pickup from the office. A dedicated outbound manifest loads each physical pallet, survives a mid-pickup save/reload, blocks departure until the manifest is complete, and archives the job only after the truck leaves. Completion removes the pallets, settles the exact invoice from accounts receivable into cash once, populates the Completed view, and triggers save checkpoints at pickup request, truck transitions, each load, and final payment.

Implement ready-for-pickup, outbound truck/manifest, job archival, pallet removal, AR settlement, and save checkpoints.

Acceptance: one full accepted job can proceed from customer to inbound truck, cutting, wrapping, outbound pickup, completed list, and cash receipt.

### Step 9 — Implement lift-level production

Status: **Completed 2026-08-24.** The cutter now treats every quoted 500-sheet lift as a production unit. The first lift remains the hands-on four-cut setup and verification cycle; later lifts use a timed saved-program action, advance exactly once per cycle, persist across save/reload, block early unloading, and correctly handle a smaller final lift.

Track active/remaining lifts and create a repeat-production flow after the first verified lift.

Acceptance: completed lifts and remaining sheets advance together; partial final lifts work; quoted workload and production effort are meaningfully related.

### Step 10 — Connect vendor inventory

Status: **Completed 2026-08-24.** Functional vendor goods now enter one visible supply inventory when their pallet is unloaded. Delivered house/cover stock feeds sample cutting, boxed pallets consume one delivered shipping carton, and all wrapping consumes delivered stretch-film rolls. The instant office film purchase was removed; products without a live consumer are visibly locked instead of taking money for unusable stock.

Give every purchased product a real inventory effect and consumer; merge film purchasing into the delivery system.

Acceptance: delivered goods appear in office inventory and at least paper, cartons, and film are consumed by their intended workflows.

### Step 11 — Decide the picture press boundary

Status: **Completed 2026-08-24.** The unfinished picture press was removed from the live module graph, machine console, interaction vocabulary, update loop, and eager asset load. Its artwork remains available as backlog source material, but the runtime no longer carries an unreachable counter-only production system or spends texture memory presenting it as implemented.

Either complete its world/input/save/economy route or remove it from runtime loading until its gameplay is ready.

Acceptance: there is no unreachable live system; if enabled, the press produces saved, inventory-backed output and updates on the correct screen.

### Step 12 — Correct movement footprints and animation state

Status: **Completed 2026-08-24.** Cutter, wrapper, empty/loaded pallet jack, and lowered pallets now validate their full footprint—including corners and edge centers—against the walkmask and inflated obstacle bounds. Placement no longer accepts a walkable center with blocked corners, while state-normalization helpers preserve live motion flags until the frame consumes them, so equipment operators visibly walk during successful movement.

Use full footprints against walkmask/obstacles and stop validation helpers from resetting frame state.

Acceptance: wrapper/jack/pallet corners cannot enter blocked pixels and the operator visibly walks while moving equipment.

### Step 13 — Surface asset failures and strengthen the doctor

Status: **Completed 2026-08-24.** Startup now stops on a dedicated readable diagnostic screen that lists every missing or malformed runtime path instead of silently drawing invisible fallbacks. The vendor 4x4 atlas, boxed-pallet 5x4 atlas, and three-state Polar Back strip use exact runtime dimensions, and the asset doctor verifies exact grids plus every nonempty cell.

Add startup diagnostics and exact contracts for the newer atlases/button strip.

Acceptance: a deliberately missing or malformed test asset produces a readable path-specific error; all atlas cells are exact and nonempty.

### Step 14 — Reduce runtime memory and startup work

Status: **Completed 2026-08-24.** The retained startup texture set is now **42.69 MiB**, down about **74.4%** from the audited ~167 MiB baseline. The CPU-only walkmask and compact shared Back control stay resident; title, cutter, and wrapper consoles use on-demand packs; visitor action strips load only when drawn and release when inactive; character anchors and PNG dimensions are read without full-image pixel scans at boot. The Polar console and Back strip were right-sized from 1536x1024 and 2172x724 to 768x512 and 384x128. Screen-pack transition regressions and all asset checks are green.

Introduce screen/pack-based loading, resize/crop oversized UI/prop sheets, and precompute character anchors.

Acceptance: startup and scene transitions remain green while measured texture memory drops substantially from the current ~167 MiB baseline.

### Step 15 — Unify input, status labels, and office views

Status: **Completed 2026-08-24.** Every overlay now routes its visible Back/Exit control and Escape through one close policy. Customer paperwork and vendor catalogs consistently leave their visitor waiting; the active wrapper consistently blocks both routes. A shared player-facing status vocabulary covers jobs, deliveries, purchase orders, pallets, and locations. The office Deliveries tab now includes customer inbound work, outbound pickups, and vendor purchase orders with a dedicated order detail view, while Inventory exposes every usable stock bucket. Title keyboard routes and README controls match the live input paths. Five screen-parity regressions and the full 530-check smoke run are green.

Make mouse/keyboard Back behavior consistent, add title keyboard controls, normalize statuses, and expose purchase-order/stock data.

Acceptance: README, on-screen prompts, and actual behavior match for every screen.

### Step 16 — Expand regression coverage

Status: **Completed 2026-08-24.** Smoke version 3 now rejects duplicate check names and runs focused asset-pack, pallet-ownership, save-contract, and input/status domain suites. The accept-to-payment loop, save migration/recovery matrix, and live title/warehouse UI journey have separate integration modules, while the central runner retains the final three-frame engine gate. A coverage manifest maps every fixed P0, P1, and P2 audit finding to required named regressions and fails if one disappears. The reorganized run completes with **559 passes and 0 failures**.

Add small deterministic domain tests plus focused engine integration tests for every issue above. Keep the three-frame render smoke as a final gate.

Acceptance: each fixed finding has a named regression test, and no single smoke module owns unrelated domain/UI/save scenarios.

### Step 17 — Final cleanup pass

Status: **Completed 2026-08-24.** Shared geometry, number, money, panel, and box helpers now serve the title and overlay screens. World rendering is isolated from simulation/interaction state, guarded cutter scenarios have their own integration module, and the central smoke runner is reduced from 2,069 to 879 lines. Stale milestone comments and implementation-language catalog messages are gone; the runtime/deferred asset manifest and test map are documented; every resident asset has a live consumer. Final smoke and raster validation are green. The only remaining working-tree changes are the separately preserved artwork additions that predated this cleanup step.

Remove stale milestone text, consolidate UI helpers, split oversized modules, document the asset manifest, and update README controls/workflows.

Acceptance: no TODO-style player-facing copy, no known dead runtime load, clean Git status, and all validation green.

## Optimization suggestions

1. **Measure peak scene memory and transition time:** startup is lean now; add lightweight counters for core, menu, cutter, wrapper, and visitor peaks so new art cannot silently reverse the gain.
2. **Trim the remaining cutter motion strips:** clamp and blade art is still 3840×512 per strip. Per-frame trimmed rectangles or a tighter atlas would reduce the cutter pack and transition decode time.
3. **Compact the walkmask:** its GPU copy is gone; a cached bit grid or coarse occupancy grid would reduce CPU memory and speed repeated footprint queries.
4. **Add spatial indexing when pallet counts grow:** a simple fixed grid for pallets and interactables will avoid rebuilding and scanning every obstacle list for each movement query.
5. **Use stable depth keys:** sort by Y plus a deterministic ID/type tie-breaker to prevent equal-depth flicker as object counts increase.
6. **Debounce noncritical autosaves:** keep immediate saves for money, production, pickup, and delivery changes, but coalesce position-only saves to reduce OneDrive churn.
7. **Make the manifest machine-readable:** the documented manifest should eventually drive both runtime registration and the Python doctor so dimensions and pack membership have one source of truth.
8. **Archive bulky reference mirrors:** move the 37 MiB downloaded press webpage mirror and disposable previews outside the active workspace once its useful sources are identified.
9. **Add screenshot comparisons for key scenes:** title, world, cutter, wrapper, office, vendor, and truck views would catch sprite alignment or fallback regressions that logic checks cannot see.
10. **Profile before deeper refactors:** capture update/draw time with 5, 20, and 50 pallets before adding caching or pooling; optimize the measured hot path rather than object count in the abstract.

## Gameplay suggestions

1. **Teach and balance the completed core loop:** the accept → receive → stage → cut → package → ship → paid loop works; the next pass should tune timing, payout, starting stock, and a first-job tutorial around real playtests.
2. **Add a compact current-task tracker:** show the next useful action, selected job, pallet location, due state, and blocked reason without requiring repeated computer visits.
3. **Make receiving lanes visually explicit:** occupancy rules already matter; floor markings, lane numbers, and a blocked-dock indicator would make the puzzle legible before a manifest refuses an unload.
4. **Tune lift repetition:** the first lift is hands-on and repeats are programmed; adjust repeat duration and consider optional quality checks or later automation so 3,000-sheet work feels valuable without becoming tedious.
5. **Make supplies matter visibly:** paper, cartons, and film are consumed now; show low-stock warnings and per-job material forecasts before adding ink, chemistry, or maintenance consumers.
6. **Add due dates and service quality gradually:** late delivery, damage/waste, correct dimensions, and packaging quality can affect payout and repeat customers after the base loop works.
7. **Use the machine backlog as progression:** laminator, folder-gluer, die cutter, baler, and larger presses can unlock new job families rather than appearing as decorative machines all at once.
8. **Give visitors pacing rules:** customer/vendor cooldowns, appointment windows, and a visible waiting queue will prevent constant arrivals from competing for attention.
9. **Improve feedback:** distinct sounds, button travel, machine motion, pallet placement cues, payment feedback, and short completion summaries will make existing systems feel much more finished.
10. **Add accessibility and comfort options:** full keyboard/mouse parity, remappable controls, UI scale, text speed/contrast choices, and pause behavior should be defined before the control surface grows further.
