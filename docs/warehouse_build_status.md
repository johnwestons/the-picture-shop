# Warehouse build status

Updated September 19, 2026. Current status supersedes the earlier foundation-only handoff.

## Playable now

**The first storage-and-forklift path is enabled in the normal game**, offline and through host-authoritative multiplayer commands:

1. Use the office computer's warehouse page to buy **left storage** ($4,500), acknowledging that the upper five slots require a forklift.
2. The raccoon calls before visiting, enters through the front entrance, walks to the work area and builds four stages. Each stage requires a full game day after actual arrival; blocked work pauses progress.
3. After completion, the left bay is walkable and its two-row, five-column rack is usable. Stored pallets appear both in the warehouse and the first-person shelf view.
4. Buy the **forklift** ($6,500), mount it, pick up actual stock, drive at travel height, raise the forks and store/retrieve the same pallet on the upper shelf.
5. Use **STACK / TAKE TOP** to place and retrieve a second customer paper skid on a matching-footprint floor skid. Wrapped and unwrapped paper skids are supported; unrelated supplies and third levels are not.

Only left storage and the forklift are sold in this slice. Other bay/room choices say **NOT READY YET** and are rejected by the purchase authority. No payment is taken for unsupported options.

### Controls

- Near the forklift: **V** drive; **V** again parks at a valid clear standing point.
- Driving: ordinary movement controls; **E** pick up/drop; **G** ground; **T** travel; **R** upper.
- Stop before changing height or transferring stock. Carry pallets at travel height; raised-load driving is blocked.
- Near the rack: **H** opens shelves. Select a slot, then use the screen's Store/Retrieve buttons.
- Inside shelves: **G** ground, **T** travel, **U** upper. The rack keeps **R** for Retrieve.
- Floor stacking: face the supporting skid, stop, raise fully, then **K** to stack your load or take the top skid. The supporting skid stays locked until the upper skid is removed.
- Matching on-screen buttons are available for touch. Lower-row transfers support the pallet jack; the upper row requires the forklift.

## What is integrated

- Additive left-bay layout, collision and loading anchors over the existing warehouse. Existing core walkable pixels and character/machine/pallet/jack draw scales remain unchanged.
- Durable construction visitor, phone-before-arrival timing, collision-aware front-door routing, four 24-hour stages, visible progress, departure and save/shared-state recovery.
- Normal office purchase configuration and validation, safe paid forklift spawn, mounting/dismounting, exclusive vehicle ownership, eight-direction driving, fork-height progression and canonical floor cargo.
- Shared rack presenter and local/guest command bridge, fresh host-computed access checks, revisioned single-owner transfers and visible isometric stock.
- Multiplayer protocol **v19**, a warehouse lease/action and 12 Hz forklift state updates. Compatible pallet-jack leases can submit lower-row transfers without losing the jack. Reconnect/lease-loss cleanup clears pending rack and stack controls.
- Save schema remains **v15** with optional construction-worker/work-clock state; older valid saves still begin locked/unowned without charges. Two-high stacking now has shared keyboard/touch controls, fresh host geometry/height checks and replay-safe canonical transfers.

Main integration files: `src/warehouse_layout.lua`, `warehouse_construction.lua`, `warehouse_gameplay.lua`, `warehouse_renderer.lua`, `warehouse_intent.lua`, `warehouse_authority.lua`, `screens/warehouse_controls.lua`, `world.lua` and `app.lua`.

## Art boundary: playable development slice, not finished warehouse art

The taller upper architecture from `warehouse-base-v3-top-remake.png` now fills the top gaps through `src/warehouse_scene.lua`. It is registered above the existing roof silhouette while the original lower base, dock animation, phone, entrance, lounge, collision mask and all actor/equipment scales stay unchanged. A render comparison verifies every pixel from world y=190 down remains identical before/after this upper-wall change. **The full candidate floor/front trim is not a drop-in replacement and remains unfinished.** Left storage still uses the additive extension.

`Config.warehouse.provisionalArt=true` explicitly enables reviewed draft forklift imagery and marks the scene as development artwork. Source entries remain `approved=false`.

- The first-person shelf uses the user-approved empty rack design. Its isometric projection and construction stages are interim renderings, not finished seam-certified module sprites.
- Forks raise/lower in all eight headings using four-pose studies. Parked vehicles now retain their real fork height with matching empty-seat sheets, including a raised carried load. Rear-facing cargo is drawn behind the vehicle. Visible stepping, edge fringe and detailed mast/cargo occlusion still need production polish.
- The raccoon uses the existing Mouse Frontier directional walk/idle strips with distance-based gait timing. All four stage-specific work loops are now integrated from the repaired `mechanic-work-atlas-v2.png`: concrete float, hammer, drill and paint roller. Individual source crops and foot anchors prevent neighboring poses from being cut into each frame. Host-timed work pauses when blocked and resets at stage changes; body scale is independent of raised tools. These 4-pose loops remain draft art with minor fringe/pose polish outstanding.
- Remaining room choices, right-bay modules, complete stock variants, rabbit jack-pushing animations and full environment registration remain unfinished.

The [art index](../assets/source/warehouse-expansion-v1/ART_STATUS.md) preserves source provenance and individual cleanup notes. The [full plan](warehouse_expansion_plan.md) remains the broader design specification, not a completion claim.

## Verification

- September 24 forklift polish: desktop and forced-mobile smoke each pass **3,415 checks, zero failures**. Eight selected empty-seat lift sheets have the expected 2048×768 RGBA geometry and transparent corners; the runtime packaging tests pass. The real-engine acceptance run passes **62 checks**, including suspended-load preservation and remount after operator loss. The parked raised-load capture was visually inspected.

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
