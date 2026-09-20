# Forklift simulation integration contract

Current integration: the normal game now calls this domain through `warehouse_gameplay.lua`, `world.lua` and the shared warehouse authority/controls. See [playable slice status](warehouse_build_status.md). Draft lift art is explicitly enabled as development artwork; this contract does not imply final art approval.

`src/forklift.lua` is a pure Lua vehicle domain. It does not load images, depend on animation frame counts, create pallet inventory, or mutate save files. `src/tests/forklift_test.lua` is a standard `Test.run(context, check)` suite; it can also run with an empty context.

## State and entitlement

The module owns `state.forklift` with these fields:

| Field | Meaning |
| --- | --- |
| `owned` | Boolean vehicle entitlement/materialization flag; default false. Purchase integration must also keep `state.warehouse.forkliftOwned` consistent because storage validates that entitlement. |
| `x`, `y`, `direction` | Position and eight-sector fork heading. Coordinates must be finite and within ±1,000,000. |
| `carriedPalletId` | Optional existing stable pallet ID, not a second pallet object. |
| `forkHeight` | Continuous normalized current fork height: ground0, travel normally0.08, upper rack1. |
| `targetForkHeight`, `lifting` | Active commanded height and whether a lift is underway. |
| `operating`, `operatorPlayerId` | Exclusive live operator, ID1–4. |
| `moving`, `animationDistance` | Actual collision-resolved movement, not requested input. |

Save/reopen should preserve owned/position/direction/cargo/current fork height, clear the live operator and motion, and set target height equal to current height. A suspended load must never silently fall, duplicate, disappear or finish an unattended lift. Validate saved fields before normalization so corruption is not mistaken for an intentional cargo release.

Defaults: position600,480; northwest heading; speed100; loaded speed72; full upward travel3 seconds; full downward travel2.5 seconds; travel height0.08; collision substeps at most4 world pixels. All are configurable without changing art. Existing characters/machines are not resized.

## Public API

All game-level methods take the shared root state. `config` is a table or nil.

- `defaultState(config)` returns a new unowned, parked vehicle value.
- `normalize(value, config)` returns a new canonical vehicle value. Does not modify its input. A parked vehicle's target becomes its current height.
- `ensure(state, config)` installs/normalizes `state.forklift` while preserving an existing table's identity.
- `validState(value, config)` returns boolean and optional reason. Checks finite values, bounded IDs, ownership consistency and unsafe motion combinations.
- `snapshot(state, config)` returns a detached vehicle value with only supported fields.
- `applySnapshot(state, snapshot, config)` validates before committing. Returns `awaiting_durable` if reliable canonical `on_forklift` pallet custody or durable vehicle ownership does not yet agree, if multiple canonical pallets claim the forklift, or an owned snapshot lacks entitlement in a present warehouse table. Realtime motion cannot purchase, materialize or revoke a vehicle. Returns `cargo_conflict` for a simultaneous jack cargo claim and `operator_conflict` for a simultaneous seat claim. Every refusal preserves authoritative state. This supports either arrival order across realtime/durable network channels.
- `acquire(state, config, playerId)` grants one operator, with idempotent repeat acquire. Rejects an unowned vehicle, another worker, invalid IDs, or that worker already operating the pallet jack, including on repeated acquisition. World integration must enforce proximity; the jack's mount path already enforces the reverse cross-vehicle rule.
- `isOperator(state, config, playerId)` checks exclusive ownership.
- `release(state, config, playerId)` allows voluntary dismount only when stationary, not lifting, and forks are on the ground. A grounded carried pallet may remain parked on the forks.
- `forceRelease(state, config, playerIdOrNil)` is the host cleanup/disconnect path. Stops movement, releases the operator, freezes the fork target at its actual current height, and preserves cargo. Nil is for trusted host cleanup, never a client-supplied operator bypass.
- `setForkHeight(state, config, playerId, target)` requests a finite height0–1 without teleporting. Requires a stopped owned vehicle. Repeating the target does not restart the motion; reversing begins from the current interpolated height.
- `update(state, dt, config)` advances only active, attended lifting; returns changed boolean and reason. Full-range duration is independent of frame partition. Negative/nonfinite elapsed time is rejected; large finite time saturates at the target.
- `move(state, dx, dy, dt, config, canMove, playerId)` returns moved boolean, reason, actual distance. Input magnitude is capped at1 while subunit analog strength is preserved; diagonal speed is not faster. `canMove(nextX, nextY, loaded, direction)` is mandatory and must reject obstacles/bounds at each substep. Motion elapsed time is finite0–60. No driving during lifts or above travel height; a loaded pallet must be raised to travel height before driving. Call with zero input to clear the current moving flag when controls stop. Motion does not automatically update pallet world metadata: the canonical cargo adapter must derive it from the forklift pose.
- `attachCargo(state, config, playerId, palletId, transfer)` and `detachCargo(...)` validate operator, stationary state, one cargo slot, exact pallet ID and conflicting jack custody, then call `transfer(id, "attach" or "detach", vehicleView)`. The mandatory trusted callback must atomically validate and transfer canonical cargo; false refusal must mutate nothing. Repeated attach/detach never invokes a second transfer. Callback errors are not swallowed.
- `frame(state, config)` returns direction frame1–8, loaded boolean, continuous fork height. Direction order is **NW,N,NE,E,SE,S,SW,W**.
- `directionFor(dx, dy, previousDirection)` uses eight45-degree sectors and retains last heading while stopped.
- `dropPosition(state, config)` returns the directional fork-contact anchor, using configurable horizontal/vertical offsets.
- `operatorPosition(state, config)` returns the vehicle seat/world anchor; the actor renderer should not draw a separate standing worker while mounted.
- `obstacle(state, config)` returns the owned vehicle's loaded/unloaded footprint even while operated; omit this same vehicle only from its own movement collision query, not from other actors' collision queries.

## Cargo integration gate

Canonical cargo location is `on_forklift`. Floor pickup/drop callbacks must validate reach, correct height, floor occupancy, destination permission, and support dependencies. In particular, reject removing a floor pallet when `PalletStorage.isSupporting(state, pallet.id)` is true. Rack/stack actions can use `PalletStorage.apply`, which already updates the actual pallet and vehicle ID after all validation; do not nest a second pickup/drop transaction around it.

Network caller authorization, request deduplication/revisions, transaction persistence and interaction range remain host authority responsibilities. Module callbacks are trusted integration boundaries, not arbitrary code/data supplied by guests.

`src/forklift_cargo.lua` now supplies the tested floor-transfer callback and carried-pallet world-pose synchronizer. Its [integration contract](forklift_cargo_domain.md) requires fresh host-world clearance and alignment checks. It is not yet wired to normal-game controls or network actions.

## Current verification

The standalone forklift domain suite passes 125 assertions covering finite validation, all eight headings, analog/diagonal speed, collision substeps, blocked movement, lift timing and reversals, elapsed-time partitioning, duplicate ownership/cargo attempts, durable/realtime ownership arrival order, disconnect freezing, remount recovery and normal dismount safety. Persistence and cargo now have their own tested modules; renderer, controls, purchased physical spawn and connected-device behavior still require world integration and end-to-end tests.

## Source-review lift presentation

`src/forklift_presentation.lua` is deliberately gated source-review presentation. Its companion suite adds 66 assertions. No production renderer or asset registry was changed by this module.

- `reviewCatalog()` returns detached metadata for all eight sources in `assets/source/warehouse-expansion-v1/forklift-lift/`. It selects north v2 (corrected rear heading), south v3 (extended mast) and v1 for the other six directions. Each is 2048-by-768 with four 512-by-768 cells. Every source is marked `approved=false` and `manned=true`.
- Per-frame wheel-ground and fork-carriage anchor points are provisional manual visual calibration, not pixel-perfect production measurements. They compensate approximate body drift for review. Collision still comes only from the simulation.
- `validateSheet(sheet)` validates dimensions/crops, finite anchors and heights, ground/upper endpoint coverage, and monotonic upward fork movement relative to wheel-ground contact.
- `heightSample(sheet, actualHeight)` selects the nearest authored lift pose and retains a continuously interpolated anchor sample for review only. It uses actual fork height, never target height or a separate clock, so lowering/reversal match the authoritative lift. Four full-vehicle frames still create discrete visual steps; this is not a claim of a fully smooth layered mast/fork animation. The interpolation is not a cargo draw position while using discrete full-vehicle frames.
- `plan(vehicle, options)` returns source crop, source wheel origin, world draw position, fixed scale, **selected-frame** `loadX/loadY`, carried pallet ID and review flags without mutating the vehicle. Keeping cargo on the displayed frame's tines prevents it floating between authored poses. Defaults refuse unapproved art. `options.review=true` explicitly allows lab viewing; `options.catalog` can supply later reviewed metadata and `options.scale` selects only the forklift's established world scale.
- `draw(vehicle, getImage, options, graphics)` draws that plan using a caller-managed image. It checks actual image dimensions, preserves graphics state, releases its temporary quad and never loads files or substitutes placeholder shapes. Production calls reject a baked-in driver on a parked vehicle; review calls expose `driverMismatch` instead of hiding the issue.

Original source blockers included broad soft golden/gray edge halos, north's wrong three-quarter view and south's high-carriage geometry. The catalog now explicitly selects inspected N v2/S v3 corrections with recalibrated provisional anchors, without approving them. Alpha edges, cross-direction body scale, nonuniform pose spacing and in-engine load alignment still need production review; the hidden north ground carriage is only an anchor estimate. Empty-vehicle raised poses, cargo occlusion layers and a smoothly moving layered mast remain integration requirements.
