# Warehouse redesign concepts

These are the concept sprites reviewed for the warehouse redesign. **B6 — Open computer office** is now the running warehouse background. See [warehouse rooms](warehouse_rooms.md) for the integrated layout, separate room upgrades, multiplayer behavior and asset registrations.

## Options

- **A — Industrial back wall:** Keeps the familiar warm brick and steel look. The loading bay remains to the left, the lobby sits on the rear wall, and a single five-bay rack run is placed against the back wall. This is the most conservative floor-plan change and leaves the center open.
- **B — Bright back wall:** Uses pale masonry and brighter lighting. Storage occupies the rear-left wall and the lobby the rear-right, with a broad, clearly readable operating floor. This has the clearest value separation for gameplay objects.
- **C — Marked aisle:** Keeps the warm industrial palette and adds a marked circulation loop. Storage is grouped along the rear-right wall and the lobby remains near the center. The markings help communicate vehicle paths, though their final placement must avoid machine and pallet interaction areas.

## Option B floor-space refinements

These four follow-up concepts retain B's pale masonry, loading door, back-wall shelving, and rear-right lobby. They address the three spaces marked in the review screenshot by extending the continuous concrete floor through both front corners and the aisle beside the lobby, with the platform edge kept outside the visible room.

- **B1 — Direct extension:** Keeps B's layout and framing closest to the first version; the same concrete floor reaches the lower and side image edges.
- **B2 — Wider footprint:** Broadens the room and carries the usable floor around both outer wall returns.
- **B3 — Recessed lobby:** Tucks the lobby farther into the back wall to open a wider, level aisle on its right and in front.
- **B4 — Maximum floor:** Frames more of the operational floor and pushes the room perimeter beyond the crop.
- **B5 — Office bay:** Uses the marked far-right back-wall area for a compact, enclosed computer office with an interior window, a floor-facing door, and a visible desktop terminal. The main aisle remains open.
- **B6 — Open office:** Removes the office front wall, door, and window to expose the desk and computer directly. A level office floor joins the warehouse through a broad opening, giving players a visible entry and computer approach area. Retain this opening in the walk mask and register the computer interaction point inside the office when implementing the selected layout.

## Earlier upgrade presentation proposal

This wall-bay proposal was superseded by separate room scenes reached from the front entrance. The existing room A/B purchase IDs and four construction stages remain, but upgrades no longer consume any of the warehouse's visible floor.

Each unbuilt bay should read as a closed, inactive wall section. Its four construction states should visibly transform that same wall opening: preparation, structural framing, room fit-out, and completed option. An open-floor choice becomes an accessible production or staging opening with floor continuous to the main room; a storage choice installs rear rack structure; a breakroom choice encloses and furnishes the bay. The warehouse purchase screen should preview those wall outcomes instead of showing wedge-shaped floor patches.

Keep rack uprights and back structure behind the pallet sprites, with front beams in front, so the existing ten-slot rack interaction can continue to draw and move individual pallets. Preserve the forklift requirement for upper slots and leave a clear service aisle in front of the rack. The loading dock, lobby route, movable machines, pallet staging, and a continuous vehicle path need reserved space in the new floor plan.

For implementation, register the selected art to the game's 960×678 world and recalculate wall-bay polygons, construction work points, rack anchors, collision posts, and interaction approaches from that master image. Keep persistent bay IDs stable where possible so existing purchases retain their ownership and construction state. Compose the same room at PC and mobile viewport sizes without enlarging gameplay objects to compensate for framing.

## Candidate files

- [Option A — Industrial back wall](../assets/source/warehouse-redesign-v1/warehouse-option-a-industrial-back-wall.png)
- [Option B — Bright back wall](../assets/source/warehouse-redesign-v1/warehouse-option-b-bright-back-wall.png)
- [Option C — Marked aisle](../assets/source/warehouse-redesign-v1/warehouse-option-c-marked-aisle.png)
- [Option B1 — Direct floor extension](../assets/source/warehouse-redesign-v1/warehouse-option-b-floor-expansion-01.png)
- [Option B2 — Wider footprint](../assets/source/warehouse-redesign-v1/warehouse-option-b-floor-expansion-02.png)
- [Option B3 — Recessed lobby](../assets/source/warehouse-redesign-v1/warehouse-option-b-floor-expansion-03.png)
- [Option B4 — Maximum floor](../assets/source/warehouse-redesign-v1/warehouse-option-b-floor-expansion-04.png)
- [Option B5 — Computer office in marked bay](../assets/source/warehouse-redesign-v1/warehouse-option-b-office-in-marked-bay.png)
- [Option B6 — Open computer office](../assets/source/warehouse-redesign-v1/warehouse-option-b-open-office-v1.png)
- [Open-office edit prompt](../assets/source/warehouse-redesign-v1/warehouse-option-b-open-office-v1-prompt.txt)

All nine concept images are 1536×1024. The B refinements use the supplied screenshots as layout guidance and exclude red annotations. B6's shelves, open office, loading dock, lobby seats, entrance and floor seams are registered in the runtime; stock remains drawn from each pallet's canonical inventory record.
