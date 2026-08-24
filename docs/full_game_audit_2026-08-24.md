# The Picture Shop — Full Game Audit and Cleanup Plan

Date: 2026-08-24
Engine verified: LÖVE 11.5
Audit scope: implemented runtime systems, save/state flow, input and UI routes, live assets, smoke coverage, project hygiene, performance risks, and the currently reachable gameplay loop.

## Executive summary

The vertical slice is healthy enough to boot and run its tested happy path. The current engine smoke test completed with **323 passes and 0 failures**, and the raster audit completed with **145 passes and 0 failures**. Every image registered as a required runtime asset exists and can be loaded.

The green checks do not mean the game is ready for a general cleanup commit yet. The audit found four urgent state/data problems, several incomplete gameplay connections, and a large amount of asset/test material that needs a source-control boundary. The highest-risk issues are:

1. Starting a new shop on an occupied slot overwrites it without confirmation.
2. Leaving the skid-wrapper screen during a wrap can lead to a nil-state runtime crash.
3. New-game/save payloads do not preserve the intended starter film inventory or skid-wrapper placement.
4. The cutter can claim a pallet that is still carried by the pallet jack, leaving two systems owning the same pallet.
5. A job cannot actually be completed, picked up, paid, or moved to the Completed list.

The recommended approach is to establish a clean Git baseline first, then fix one numbered item at a time in the order given below. Each fix should include its own regression check before moving to the next item.

## Project snapshot

- 37 Lua files and 6,790 lines of Lua.
- 456 workspace files totaling about 144 MiB, excluding Git internals.
- `assets/` is about 91 MiB; `output/` is about 51 MiB.
- The configured runtime image set decodes to about 167 MiB before counting the retained walkmask CPU copy and other engine overhead.
- `assets/Machines/movingPicturePress_files/` alone contains 161 downloaded webpage-support files totaling about 37 MiB.
- Git is now a separate repository rooted at The Picture Shop, on `master`, using `John <johnwestontattoos@gmail.com>`. It has no remote and no commits. It is not connected to Mouse Frontier.

## Validation results

### Passed

- LÖVE 11.5 launched the project successfully.
- The hidden watchdog smoke test completed: 323 passes, 0 failures, three frames rendered.
- Required warehouse, walkmask, machine, loading-bay, truck, pallet, pallet-jack, wrapper, and registered character assets loaded.
- Warehouse/walkmask dimensions and binary mask values passed.
- Current sprite strips produced valid quads under the existing loader rules.
- Job quoting, inbound delivery, pallet unloading, pallet-jack movement, cutter happy path, basic wrapper cycle, and save v1 migration passed their existing smoke checks.

### Coverage gaps

The smoke suite does not test occupied-slot overwrite protection, new-game film defaults, skid-wrapper save persistence, exit during a wrapper cycle, press routing, successful job completion/payment, repeated deliveries to occupied receiving points, cutter loading from a carried pallet, atomic save recovery, or title-screen keyboard controls.

## Findings by severity

Severity guide:

- **P0:** possible data loss, crash, or contradictory ownership/state corruption.
- **P1:** blocks or materially breaks the main gameplay loop.
- **P2:** reachable inconsistency, missing integration, or significant polish/maintainability problem.
- **P3:** cleanup, diagnostics, documentation, or future scaling concern.

### P0 — fix before expanding the game

#### P0-01: New Shop can silently overwrite an occupied save

`src/screens/title_screen.lua:27-30` creates a new payload immediately, and the New Shop click path at `src/screens/title_screen.lua:53` has no occupied-slot confirmation. The live title-screen check also confirmed that the advertised keyboard workflow is absent, making a mistaken mouse click the only active route.

Expected fix: show a clear overwrite confirmation for an occupied slot, preserve the existing slot until confirmation, and add a regression check that Cancel leaves the original save byte-for-byte readable.

#### P0-02: Exiting during skid wrapping can crash the world update

Escape or the Exit button returns to the world without stopping the active wrapper cycle (`src/input.lua:18-23`, `src/input.lua:147-153`). The world branch then calls `Wrapper.update(dt)` without the state object (`src/app.lua:116-120`). Once the cycle reaches completion, `src/wrapper.lua:47-48` dereferences `state.inventory`.

Expected fix: define one lifecycle policy—finish in the background, pause, or prevent exit during the three-second cycle—and always update the wrapper with valid state. Test Escape and mouse Exit at the start, middle, and final frame of wrapping.

#### P0-03: Save/new-game schema loses intended state

`State.new()` supplies one plastic-wrap roll with 11 uses (`src/state.lua:13-21`), but `Save.newGame()` omits both fields (`src/save.lua:145-173`). After `State.applySave()`, a newly created shop therefore starts with zero film. The save payload also omits `state.wrapper` (`src/save.lua:193-215`), even though load code expects it (`src/state.lua:79-84`), so wrapper relocation is lost on reload.

Expected fix: introduce a new save version with explicit defaults and v1/v2 migration; persist wrapper placement and film state; verify all three slot operations and round-trip every persistent field.

#### P0-04: Cutter and pallet jack can own the same pallet

The cutter accepts any incomplete paper whose location is not `awaiting_delivery` or `none` (`src/machine.lua:32-45`). This includes `on_pallet_jack`. Loading changes the pallet to `at_cutter` (`src/machine.lua:71-90`) but does not clear the jack's `carriedPalletId`, creating contradictory ownership and allowing later movement/output code to manipulate the same pallet.

Expected fix: centralize legal pallet-location transitions, reject cutter loading unless the pallet is staged on clear floor near the cutter, and add invariant checks ensuring one pallet has exactly one owner/location.

### P1 — main-loop blockers

#### P1-01: Jobs cannot be completed, picked up, or paid

The computer's completion button only returns `completion_ready` (`src/screens/computer_screen.lua:178-181`). Input then displays that completion and pickup scheduling are not connected (`src/input.lua:164-168`). No code moves a job from active to completed, removes wrapped pallets, changes accounts receivable into cash, or schedules an outbound truck.

Expected fix: implement `in_production -> ready_for_pickup -> pickup_in_progress -> completed`, an outbound manifest/truck flow, active/completed collection transfer, pallet removal, AR settlement, and autosaves at each irreversible transition.

#### P1-02: Repeated deliveries overlap pallets at fixed coordinates

Customer and vendor unloads reuse the same five configured spawn points (`src/config.lua:118-134`, `src/pallet_logistics.lua:65-76`, `src/procurement.lua:104-114`). No occupancy check reserves a receiving position. Later jobs and every single-pallet vendor order can stack directly on existing pallets, producing ambiguous tooltips and collision.

Expected fix: create receiving-lane slots with occupancy checks, block an unload when no slot is clear, and guide the player to move staged pallets before continuing.

#### P1-03: Cutter input/output ignores physical logistics

The cutter selects the first eligible pallet anywhere in the warehouse rather than a nearby staged pallet (`src/machine.lua:32-45`, `src/machine.lua:71-78`). Finished output uses a fixed offset from the cutter without testing the walkmask or other objects (`src/machine.lua:17-29`, `src/machine.lua:316-320`). A relocated cutter can therefore teleport input or place output inside walls, machines, or other pallets.

Expected fix: require a specific nearby pallet, add a pallet selector when more than one is valid, reserve a clear cutter input/output zone, and reject/redirect unsafe output placement.

#### P1-04: Quoted lift workload is bypassed

Jobs quote one charge for every 500-sheet lift (`src/jobs.lua:13-14`, `src/jobs.lua:137-159`), but the cutter performs one four-margin program for an entire pallet and then marks every required lift complete (`src/machine.lua:273-325`). A 500-sheet pallet and a 3,000-sheet pallet require essentially the same player work despite a sixfold quote difference.

Expected fix: represent the active lift and remaining sheets explicitly. To avoid excessive repetition, make the first lift a manual setup/quality check and allow safe repeat production for the remaining programmed lifts.

#### P1-05: Saves are not crash-safe

`src/save.lua:221-222` writes directly over the only slot file. A crash, disk interruption, or OneDrive sync conflict during the write can turn the slot into an unreadable empty listing. Validation is also shallow and does not reconcile cached inventory totals against pallet records.

Expected fix: write and validate a temporary payload, preserve a last-known-good backup, then promote it; recover automatically from a valid backup; validate nested job/pallet/paper fields; and rebuild derived inventory totals on load.

### P2 — incomplete or inconsistent integrations

#### P2-01: Picture press is visually present in code but unreachable and inert

The press asset and a press UI branch exist, but the world has no press placement/interactable, input never assigns `machineType = "picture_press"`, and the machine-screen update/input routes do not run `Press.update` or `Press.keypressed`. The prototype also increments an internal sheet count without consuming inventory, producing saved output, or affecting jobs.

Expected fix: either remove it from the live runtime contract until ready, or add a complete placement, interaction, update, input, inventory, save, and production flow.

#### P2-02: Vendor purchases are delivered but mostly have no gameplay use

Vendor unloading adds quantities to `inventory.stock` (`src/procurement.lua:104-117`), but that stock is not displayed in the computer inventory and is not consumed by production. Delivered `stretch_film` does not add `plasticWrapRolls`; boxed jobs do not require cartons; paper and press supplies do not feed a press. The separate computer button bypasses delivery and buys film instantly.

Expected fix: give every catalog item a defined inventory effect and consumer, show all stock, and use the same delivery-based purchasing model for film instead of maintaining two unrelated film systems.

#### P2-03: Input documentation and actual behavior disagree

The README advertises W/S or arrows, N, C/Enter, D, and Y/N on the title screen, while `src/input.lua:26-28` intentionally ignores all title keys. The README also says Escape closes a GUI, but job paperwork blocks Escape while a clickable Back button exists.

Expected fix: implement the documented keyboard routes (recommended for accessibility) or rewrite the controls section and on-screen prompts to exactly match behavior. Test mouse and keyboard parity for every screen.

#### P2-04: Vendor Back behavior is inconsistent

Mouse Back cancels the vendor review and leaves the representative waiting (`src/input.lua:125-133`), but Escape calls `resolveVendor` and sends the representative away (`src/input.lua:18-23`). This conflicts with the README's statement that Back actions leave NPCs waiting.

Expected fix: route Back and Escape through one screen-close action and one documented visitor policy.

#### P2-05: Moving equipment can clip the walkmask, and operator walk animation is reset

The cutter checks several footprint edge points, but the wrapper, pallet jack, and dropped pallets mostly validate only a center point against the walkmask. Large objects can therefore cross a wall/floor boundary. Separately, `CutterPlacement.ensure()` resets `inMotion` and `PalletJack.ensure()` resets `moving`; later calls during the same update clear the values before player animation reads them.

Expected fix: use oriented footprint/corner checks for every movable object and separate data validation from per-frame mutation so animation state survives through draw.

#### P2-06: Asset load failures are recorded but hidden in normal play

`Assets` and `CharacterAssets` collect failure messages, but `src/app.lua:70-76` does not call their health assertions or show a diagnostic screen. A missing sprite can silently become an invisible object or fallback rectangle outside the smoke environment.

Expected fix: fail into a readable asset-error screen in development/release startup, listing the exact missing or malformed paths, while retaining safe fallbacks only where intentional.

#### P2-07: Office status views are incomplete

The label table omits the live `in_production` status, so it appears as a raw internal string. The Deliveries tab excludes vendor purchase orders, and the Inventory tab omits `inventory.stock`. Completed jobs stay empty because completion is not connected.

Expected fix: define one status vocabulary, include inbound purchase orders and outbound pickups, and display every inventory bucket the player can buy or consume.

#### P2-08: Two live atlases do not have exact grid dimensions

The vendor atlas is 1254×1254 for a 4×4 grid, and the boxed-pallet atlas is 1402×1122 for a 5×4 grid. Runtime registration floors the cell dimensions and leaves edge pixels unused. The asset doctor does not currently validate these three newer contracts (vendor atlas, boxed atlas, Polar Back strip), although smoke verifies that quads exist.

Expected fix: normalize the atlases to exact cell multiples, validate exact dimensions/divisibility and nonempty cells, and add the omitted contracts to the asset doctor.

### P3 — cleanup and scaling debt

#### P3-01: Large assets are loaded eagerly, including unused content

All configured images load at startup, roughly 167 MiB decoded. About 30 MiB comes from the unused base Polar sheet and unplaced prop sheets (empty pallet, paper stack, boxes, and toolboxes). The inaccessible press adds another 4 MiB, and an unused character `use` strip adds about 3 MiB. The retained walkmask image data adds CPU memory on top of its texture.

Expected fix: separate always-on world assets from screen/machine/character packs, load on demand, release inactive packs, and stop loading assets that have no reachable renderer.

#### P3-02: Project artifact boundaries are unclear

Runtime art, canonical sources, generated drafts, doctor previews, reports, and a downloaded webpage mirror are mixed across `assets/` and `output/`. Many files are byte-for-byte duplicates. There is no root `.gitignore`; Python bytecode is currently visible to Git. `output/` cannot simply be ignored yet because some documented build scripts treat selected files there as preserved sources.

Expected fix: create an asset manifest and move canonical inputs to a stable source folder, keep promoted runtime files in `assets/generated`, route disposable previews/reports to an ignored build-output folder, ignore caches and smoke output, and archive or exclude the 37 MiB webpage mirror.

#### P3-03: Test and UI helper code is becoming monolithic

`src/smoke.lua` is 907 lines and `src/world.lua` is 840 lines. Screen modules duplicate rectangle hit tests, panels, number formatting, button rendering, and pagination behavior. `src/press.lua` and `src/wrapper_placement.lua` use dense one-line functions inconsistent with the rest of the project.

Expected fix: split domain tests from rendered integration tests, extract shared UI primitives, divide world simulation/rendering/logistics, and reformat dense modules without changing behavior.

#### P3-04: Stale implementation text remains visible

Examples include “Pallet inventory arrives in step seven” in `src/world.lua:155`, the outdated future-popup comment in `src/customer.lua:1-3`, and the completion placeholder message in input. These make implemented features look unfinished or obscure what is truly missing.

Expected fix: remove milestone language from player-facing copy and update comments/README after each completed fix.

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

Either complete its world/input/save/economy route or remove it from runtime loading until its gameplay is ready.

Acceptance: there is no unreachable live system; if enabled, the press produces saved, inventory-backed output and updates on the correct screen.

### Step 12 — Correct movement footprints and animation state

Use full footprints against walkmask/obstacles and stop validation helpers from resetting frame state.

Acceptance: wrapper/jack/pallet corners cannot enter blocked pixels and the operator visibly walks while moving equipment.

### Step 13 — Surface asset failures and strengthen the doctor

Add startup diagnostics and exact contracts for the newer atlases/button strip.

Acceptance: a deliberately missing or malformed test asset produces a readable path-specific error; all atlas cells are exact and nonempty.

### Step 14 — Reduce runtime memory and startup work

Introduce screen/pack-based loading, resize/crop oversized UI/prop sheets, and precompute character anchors.

Acceptance: startup and scene transitions remain green while measured texture memory drops substantially from the current ~167 MiB baseline.

### Step 15 — Unify input, status labels, and office views

Make mouse/keyboard Back behavior consistent, add title keyboard controls, normalize statuses, and expose purchase-order/stock data.

Acceptance: README, on-screen prompts, and actual behavior match for every screen.

### Step 16 — Expand regression coverage

Add small deterministic domain tests plus focused engine integration tests for every issue above. Keep the three-frame render smoke as a final gate.

Acceptance: each fixed finding has a named regression test, and no single smoke module owns unrelated domain/UI/save scenarios.

### Step 17 — Final cleanup pass

Remove stale milestone text, consolidate UI helpers, split oversized modules, document the asset manifest, and update README controls/workflows.

Acceptance: no TODO-style player-facing copy, no known dead runtime load, clean Git status, and all validation green.

## Optimization suggestions

1. **Lazy-load by pack:** keep the warehouse core resident; load cutter GUI, wrapper GUI, press GUI, and visitor character packs only while needed.
2. **Crop and right-size textures:** the 2172×724 Back-button strip, 1536×1024 prop sheets, and mostly transparent 3840×512 motion strips are much larger than their display footprint.
3. **Precompute character anchors:** store per-frame baseline/center metadata during the asset pipeline instead of scanning every pixel with Lua `getPixel` calls at startup.
4. **Keep the walkmask CPU-only:** do not retain a GPU texture unless it is needed for a debug overlay; consider a compact occupancy representation for collision queries.
5. **Use an asset manifest:** record stable IDs, paths, dimensions, atlas grids, source lineage, and load packs in one machine-readable file shared by runtime and asset doctor.
6. **Add spatial indexing when pallet counts grow:** a simple grid for pallets/interactables will avoid rebuilding and scanning every obstacle list for every movement query.
7. **Use stable depth keys:** sort by Y plus a deterministic tie-breaker to prevent equal-depth flicker.
8. **Use integer pixel scaling where possible:** render to a fixed logical canvas and prefer integer window scales for crisp pixel art; letterbox fractional sizes deliberately.
9. **Debounce noncritical autosaves:** save immediately for irreversible economy/production transitions, but coalesce position-only saves to reduce OneDrive churn.
10. **Separate runtime and test code:** keep the production app lean and load large test fixtures only in the smoke identity.

## Gameplay suggestions

1. **Finish one satisfying core loop before adding more machines:** accept → receive → stage → cut → package → ship → get paid should be the game's dependable heartbeat.
2. **Add a compact current-task tracker:** show the next useful action, selected job, pallet location, due state, and blocked reason without requiring repeated computer visits.
3. **Turn the receiving area into gameplay:** marked inbound lanes and staging zones make pallet movement legible and give the pallet jack a necessary role.
4. **Balance lift realism with repetition:** make the first lift hands-on, then unlock programmed repeat runs with faster timing, quality checks, or optional automation.
5. **Make supplies matter visibly:** cartons for boxed pallets, film for wrapping, paper/ink/chemistry for printing, and maintenance supplies for reliability.
6. **Add due dates and service quality gradually:** late delivery, damage/waste, correct dimensions, and packaging quality can affect payout and repeat customers after the base loop works.
7. **Use the machine backlog as progression:** laminator, folder-gluer, die cutter, baler, and larger presses can unlock new job families rather than appearing as decorative machines all at once.
8. **Give visitors pacing rules:** customer/vendor cooldowns, appointment windows, and a visible waiting queue will prevent constant arrivals from competing for attention.
9. **Improve feedback:** distinct sounds, button travel, machine motion, pallet placement cues, payment feedback, and short completion summaries will make existing systems feel much more finished.
10. **Add accessibility and comfort options:** full keyboard/mouse parity, remappable controls, UI scale, text speed/contrast choices, and pause behavior should be defined before the control surface grows further.
