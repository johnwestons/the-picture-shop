# Warehouse build status

Updated September 26, 2026. Current status supersedes the earlier foundation-only handoff.

## Playable now

**Both warehouse bays can now be purchased and built in the normal game**, offline and through host-authoritative multiplayer commands. Each bay independently offers open floor, pallet shelving, or an employee breakroom. The room project remains durable and uses the existing visitor, four-day construction schedule and locked-until-complete access rules.

Completed open-floor bays are walkable. Each shelving bay has its own two-row, five-column rack and separate ten-slot inventory; the shared forklift is still required for upper-row transfers. Completed breakrooms show their own bay-oriented furniture with registered collision footprints. The existing floor stack and forklift behavior remain available.

The office catalog and purchase authority no longer hide or reject the right bay, open floor, or breakroom choices.

### Controls

- Near the forklift: **V** drive; **V** again parks at a valid clear standing point.
- Driving: ordinary movement controls; **E** pick up/drop; **G** ground; **T** travel; **R** upper.
- Stop before changing height or transferring stock. Carry pallets at travel height; raised-load driving is blocked.
- Near the rack: **H** opens shelves. Select a slot, then use the screen's Store/Retrieve buttons.
- Inside shelves: **G** ground, **T** travel, **U** upper. The rack keeps **R** for Retrieve.
- Floor stacking: face the supporting skid, stop, raise fully, then **K** to stack your load or take the top skid. The supporting skid stays locked until the upper skid is removed.
- Matching on-screen buttons are available for touch. Lower-row transfers support the pallet jack; the upper row requires the forklift.

## What is integrated

- Additive two-bay layout, independent rack IDs/slots, collision and loading anchors over the existing warehouse. Existing core walkable pixels and character/machine/pallet/jack draw scales remain unchanged.
- Durable construction visitor, phone-before-arrival timing, collision-aware front-door routing, four 24-hour stages, visible progress, departure and save/shared-state recovery.
- Normal office purchase configuration and validation, safe paid forklift spawn, mounting/dismounting, exclusive vehicle ownership, eight-direction driving, fork-height progression and canonical floor cargo.
- Shared rack presenter and local/guest command bridge, fresh host-computed access checks, revisioned single-owner transfers and visible isometric stock.
- Multiplayer protocol **v19**, a warehouse lease/action and 12 Hz forklift state updates. Compatible pallet-jack leases can submit lower-row transfers without losing the jack. Reconnect/lease-loss cleanup clears pending rack and stack controls.
- Save schema remains **v15** with optional construction-worker/work-clock state; older valid saves still begin locked/unowned without charges. Two-high stacking now has shared keyboard/touch controls, fresh host geometry/height checks and replay-safe canonical transfers.

Main integration files: `src/warehouse_layout.lua`, `warehouse_construction.lua`, `warehouse_gameplay.lua`, `warehouse_renderer.lua`, `warehouse_intent.lua`, `warehouse_authority.lua`, `screens/warehouse_controls.lua`, `world.lua` and `app.lua`.

## Art boundary: playable expansion using provisional art

The taller upper architecture from `warehouse-base-v3-top-remake.png` now fills the top gaps through `src/warehouse_scene.lua`. It is registered above the existing roof silhouette while the original lower base, dock animation, phone, entrance, lounge, collision mask and all actor/equipment scales stay unchanged. A render comparison verifies every pixel from world y=190 down remains identical before/after this upper-wall change. **The full candidate floor/front trim is not a drop-in replacement and remains unfinished.** Left storage still uses the additive extension.

`Config.warehouse.provisionalArt=true` explicitly enables reviewed draft forklift and expansion imagery and marks the scene as development artwork. Source entries remain `approved=false`.

- Both world racks now use separate isometric sprites with registered ten-slot anchors; the right rack is authored for the opposite bay orientation instead of mirroring the left sprite. The first-person shelf still uses the user-approved empty rack design.
- The two employee breakrooms have distinct furniture sprites, visible only after their room is purchased (or as a translucent project preview while it is being built). Their first-pass collision footprints follow the registered furniture groups. The open-floor upgrade uses the existing warehouse concrete texture and remains empty by design.
- Both storage orientations and both breakroom orientations now have distinct four-stage construction art. Open-floor construction shows the existing concrete surface with the stage label and worker. The new source art remains provisional and still needs seam, scale and occlusion review in the running game.
- Forks raise/lower in all eight headings using four-pose studies. Parked vehicles retain their real fork height with matching empty-seat sheets, including a raised carried load. Loaded low/mid/high captures calibrate the pallet over the blades in all eight headings; the carried ID appears in the fork-height badge instead of masking the tines. Exiting the cab avoids the fork/load area and remains within immediate remount range when the first clear side position is available. Rear-facing cargo is drawn behind the vehicle. Forklift-only transparency-aware sampling reduces edge color bleed without changing the source PNGs. Visible stepping and detailed mast/cargo occlusion still need production polish.
- The raccoon uses the existing Mouse Frontier directional walk/idle strips with distance-based gait timing. All four stage-specific work loops are now integrated from the repaired `mechanic-work-atlas-v2.png`: concrete float, hammer, drill and paint roller. Individual source crops and foot anchors prevent neighboring poses from being cut into each frame. Host-timed work pauses when blocked and resets at stage changes; body scale is independent of raised tools. These 4-pose loops remain draft art with minor fringe/pose polish outstanding.
- All expansion art needs direct visual review in the running game before it can be approved for production. Rack/deck occlusion and complete stock variants also remain open.

The [art index](../assets/source/warehouse-expansion-v1/ART_STATUS.md) preserves source provenance and individual cleanup notes. The [full plan](warehouse_expansion_plan.md) remains the broader design specification, not a completion claim.

## Verification

The verification results below are the September 24 baseline and predate the September 26 module-art integration. No runtime tests or game-save operations were run for this integration.

- September 24 forklift polish: desktop and forced-mobile smoke each pass **3,415 checks, zero failures**. Eight selected empty-seat lift sheets have the expected 2048×768 RGBA geometry and transparent corners; the runtime packaging tests pass. The real-engine acceptance run passes **62 checks**, including suspended-load preservation, a clear standing position after forced release and remount. The parked raised-load capture was visually inspected.
- Continuous lift candidates now run in all eight headings in development-art mode. Fixed occupied and empty-seat bodies stay still while separate fork carriages follow the actual lift height; north's moving layer passes behind the cab and appears above it as it rises. The four-pose sheets remain a guarded fallback. Loaded low/mid/high engine captures were inspected for north and south, and the real-engine acceptance journey still passes 62 checks. Generated source art and device presentation remain open for final approval.
- September 24 cargo registration review: a clean checkout passes **3,388 desktop and forced-mobile checks each, zero failures**. The real-engine acceptance run passes **62 checks** and captures the same carried pallet at low, mid and high poses in all eight headings. Side/diagonal pallet centers and vertical tine contact were reviewed in the resulting screenshots; the parked west remount and a loaded east-facing exit remain covered.

- Desktop full smoke: **3,319 checks pass, zero failures**. [Report](../output/warehouse-polish-final-desktop.rpt).
- Forced-mobile full smoke: **3,319 checks pass, zero failures**. [Report](../output/warehouse-polish-final-mobile.rpt). This tests mobile settings on desktop, not physical-device touch/performance.
- The real-engine acceptance journey buys via the office authority, waits for the call, routes the worker over the real walk mask, advances four complete days, drives loaded stock through actual collision checks and stores/retrieves the exact upper-shelf pallet. The original ID, 473 sheets, wrapped state and paper reference are conserved.
- The standalone acceptance run passes **60 checks**, including shelf Retrieve and touch TAKE TOP. Nine real-engine captures cover construction, the completed bay, shelf storage, raised cargo and floor-stack round trips in `output/warehouse-expansion-v1/live-acceptance/20260919-210521-*.png`.
- Mechanic combined motion audit: **20 strips, zero errors**, five work-only bounding-box warnings from crouching and tool raising/extension. No detached pieces, clipping, duplicates or gait warnings. The native runtime contact preview was inspected; final continuous-animation polish remains a separate acceptance gate.
- Domain/network tests cover duplicate/stale requests, seat conflicts, ownership conservation and interrupted/reordered state. Physical host/guest device acceptance remains pending.
- Tests use isolated identities/in-memory state. **Existing test saves were not touched**, although the user has authorized wiping this game's test saves when needed. No backup was made.
- No connected device was updated or installation package deployed.

## Next bounded work

1. Finish the registered lower warehouse/module art, rack/mast occlusion and vehicle/work-loop polish without changing actor/equipment scale.
2. Add the remaining room options only when their visible outcomes are ready.
3. Run a real host/guest walkthrough and physical mobile touch/framing tests, then build matching device packages.
