# Warehouse and separate shop rooms

The approved B6 open-office artwork is the active warehouse. The concrete floor reaches the screen edges, with a loading dock to the left, base shelves on the back wall, reception beside the front entrance and an open computer office at the rear right.

## Playing

- Walk to the front entrance beside reception and press **E**, or tap **ROOMS** on mobile. Choose room A or B. Each player's travel is independent.
- Buy a storage room, break room or empty utility room from the computer's Warehouse page. Existing construction notices, worker arrival, four construction stages, prices and purchase receipts still apply. A room opens after construction completes.
- Storage rooms contain ten stock spaces. Move delivered shop supplies to the warehouse entrance with the pallet jack, put the pallet down and park the jack. Enter the storage room, approach its shelves and use **STOCK**. Store the staged pallet or retrieve an existing one. Retrieval finds a clear drop position at the warehouse entrance; it fails safely when that area is full.
- Customer job pallets can use the base warehouse shelves. Their lower row accepts a pallet jack; their upper row still needs a forklift. A storage-room purchase requires no forklift acknowledgement.
- In the break room, approach the seating and press **E** or **REST**. Move or use **STAND** to get up. Employees with a completed break-room upgrade recover there using their existing break schedule.
- Use the rear-left exit in any room to return to the warehouse. Vehicles must be parked before entering a room.

## Scene and inventory boundaries

Player records carry a host-authoritative `sceneId`: `warehouse`, `front_left` (room A), or `front_right` (room B). Reliable interaction requests validate actual player location, completed room ownership and the relevant doorway or stock-desk range. Scene changes snap player position instead of interpolating across different maps. Remote avatars and employees draw only in their current room; workshop access and vehicle shortcuts check the warehouse scene. The host keeps simulating warehouse visitors, deliveries, production and workers even while its player is in another room. Players can remain in three different scenes at once.

Room stock remains on its original procurement pallet, using the existing rack placement fields. Transfers move that same record, preserve quantities, choose a free slot on the host and update the shared stock revision. Client retries cannot add a second copy. Other rooms cannot retrieve the stock, supporting pallets cannot be moved, and invalid storage records or exhausted revisions reject mutations.

The old upgrade IDs and save schema remain compatible: `storage` purchases become storage rooms, `breakroom` purchases become break rooms and `floor` purchases become empty utility rooms. The two persistent bay IDs still own construction projects and purchases. The base `warehouse-rack` is added when normalizing existing storage registries. Stored pallets and room ownership persist; customer pallets already on old paid shelves can be retrieved from the room menu, although new room storage accepts only delivered shop supplies. An offline reload starts the player in the warehouse. Old foreground triangle geometry and its presentation fixtures are retained only for the legacy configuration.

## Runtime sprites and registration

| Sprite | Runtime file | Size |
| --- | --- | --- |
| Selected open-office warehouse | `assets/generated/warehouse-open-office-v1.png` | 1536×1024 |
| Stock room | `assets/generated/shop-storage-room-v1.png` | 1536×1024 |
| Break room | `assets/generated/shop-breakroom-v1.png` | 1536×1024 |
| Empty utility room | `assets/generated/shop-utility-room-v1.png` | 1536×1024 |
| Rabbit seated pose, transparent | `assets/generated/characters/rabbit-worker/sit-room-v1.png` | 1254×1254 |

All backgrounds map to the existing 960×678 logical game space. `src/shop_rooms.lua` registers authored floor seams and room furniture; `src/warehouse_room_layout.lua` registers shelf contacts and the base service apron. Dynamic pallets render behind the painted shelf lips. The loading shutter uses the selected warehouse's own pixels, clipped to its aperture. Room backgrounds load on demand through a bounded texture cache. `tools/build_mobile_package.py` includes these generated assets and scene modules in both PC and mobile `.love` packages.

New room and seated sprites were generated with the built-in ImageGen tool. The exact prompt set is saved in `assets/source/warehouse-redesign-v1/room-sprite-prompts.json` and `rabbit-seated-prompt.txt`. The selected warehouse source and its original edit prompt are in the same source directory.

## Verification

`PICTURE_SHOP_SMOKE_FOCUS=warehouse-rooms` runs live scene and session tests plus the warehouse purchase, construction, stock, rack UI, save, truck, computer viewport and multiplayer regressions. The room tests verify independent host/guest scene travel and walking, host-owned guest stock transfers, blocked/full transfer handling, base shelf transfers against actual World collision, save/reload, seating and PC/mobile menu input mapping. They also render loaded warehouse shelves, the stock room, a seated break room, the entrance menu and an open loading dock for visual review.

The multiplayer tests use the real Session protocol with an in-memory transport. Physical Android devices and a live LAN are not exercised by this test harness.

October 8 verification: **771 focused checks passed** in both the source game and the built `.love` package with mobile controls enabled; **17 packaging tool tests passed** and the Lua limits audit passed for 502 files. The packaged scene modules and all five new sprites match the current source. A full-suite run reached 2,990 passing checks before stopping in the concurrent employee pallet-jack test fixture (`recent_updates_test.lua`, missing `jackApproachPoint`); that fixture is outside this room rebuild.
