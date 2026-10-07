# Warehouse build status

Updated October 6, 2026. The first left-storage-only rollout has been superseded: both expansion bays and all three room options are available in the normal game.

## Playable now

The office computer offers storage, open floor, and breakroom for either front bay. That makes six supported bay-and-room choices. Purchases still follow the shared construction schedule; a contractor calls before arrival, enters through the front door, and completes four visible stages over four full game days. Blocked work pauses progress.

- **Storage** creates a walkable bay with a two-row, five-column rack. Canonical pallets appear in world space and in the shelf screen; upper slots require the forklift.
- **Open floor** unlocks the bay as usable floor space without adding rack obstacles.
- **Breakroom** places a cutaway staff room with furnishings. Press **E / USE** near the table to sit; stand again or walk away to leave. Rest is a presentation interaction and does not add a needs or bonus system.
- Both bays have mirrored construction, room, rack, and collision registrations. The right-bay mirror uses the same registered ground anchor as its source art.
- The forklift handles real stock. It picks up a pallet, carries it at travel height, and stores or retrieves that same pallet from an upper shelf. **STACK / TAKE TOP** moves canonical stock between a carried pallet and a compatible floor skid; it does not clone inventory.

### Controls

- Near the forklift: **V** drive; **V** again parks at a valid clear standing point.
- Driving: normal movement controls; **E** pick up/drop; **G** ground; **T** travel; **R** upper. Stop before changing height or transferring stock. Raised-load driving is blocked.
- Near a rack: **H** opens shelves. Choose a slot and use Store/Retrieve. Inside shelves, **G** is ground, **T** is travel, **U** is upper, and **R** retrieves.
- Floor stacking: face the supporting skid, stop, raise fully, then **K** to stack or take the top skid. A supporting skid stays locked until its top pallet is removed.
- Matching touch controls are available. Lower-row transfers support the pallet jack; upper-row transfers require the forklift.

## Integrated systems

- Both bays are in the normal purchase catalog and host authority accepts all three options. Invalid bay/room combinations remain rejected.
- Construction visitor timing, front-door routing, collision-aware work access, four-day stage timing, save recovery, and shared project state are retained.
- Rack, floor, and breakroom collisions follow the purchased room choice. Construction and completed room sprites are registered for both bay orientations and every stage; mobile packaging includes the runtime room art.
- The forklift keeps exclusive vehicle ownership, eight-direction driving, fork-height progression, rack transfers, and floor cargo. The renderer preserves carried-pallet ownership and draw depth through mount, dismount, and recovery.
- Multiplayer protocol is **v19** and save schema **v15**. Host checks, revisioned transfers, lease cleanup, reconnect handling, and touch/keyboard stacking remain in place.

### Current triangular-fit pass

The breakroom uses the `breakroom-triangle-v5-candidate.png` cutaway sprite, with the measured floor vertices registered to each bay and the vending machine inset from the diagonal edge. Its collision footprint follows the smaller placement. Storage uses a narrower five-bay rack with straight, seam-aligned rails and vertical supports. Separate horizontal and vertical scaling keeps its rails aligned without leaning the uprights, and all six support obstacles sit on the visible posts. The diagonal seam stays clipped to each bay; a small shared-rim overlap preserves the room's left and bottom trim. The new room and rack sprites remain provisional pending production-art approval.

Main integration files include `src/warehouse_layout.lua`, `src/warehouse_construction_presentation.lua`, `src/warehouse_renderer.lua`, `src/warehouse_authority.lua`, `src/world.lua`, and `src/app.lua`.

## Remaining release gates

The expansion is playable end to end, but its art is still explicitly provisional. `Config.warehouse.provisionalArt=true` exposes development artwork with an on-screen notice; the catalog's art entries remain `approved=false`. The clean floor construction atlas removes a stray text artifact, but that cleanup does not certify the whole art set.

- Open-floor bays now continue the existing concrete texture across the shared underlap edge using mirrored source registration; the previous stretched-triangle seam is removed in both orientations. Existing lower-base pixels, walk mask, object scales, and outer-bay trim remain unchanged. The source master and remaining room/forklift art are still provisional and require the broader production art review.
- The mechanic now uses eight individually registered poses for concrete, hammer, drill, and paint work at four frames per second. The active motion spec covers 16 live walk/idle strips plus these four work loops; its refreshed 20-animation audit reports zero errors and eight alpha-bound warnings from tool reach and changing poses; reviewed contact sheets show planted feet aligned at the registered baseline. Superseded four-pose review loops remain archived outside the active spec. Candidate contact sheets and live LÖVE rendering were reviewed. These generated sheets remain unapproved.
- The side-view forklift's full lift moves the pallet by the rack's current registered 45-pixel deck spacing. The rack uses a five-opening candidate and six support posts aligned to the visible vertical frames. Run `20261006-234800` verifies loaded travel through the aisle, upper-row transfer and retrieval, parking, remounting, straight seam-aligned rails, and vertical supports against this triangular placement. The development renderer selects continuous layered lift art for its eight headings; the four-pose strips are fallback. Occupied/empty body alignment, mast/cargo/rack occlusion, and source art remain provisional.
- The rack presenter distinguishes raw, cut, wrapped, printed, partial-wrap, boxed, and supplier pallet art. Four new front-view states are registered from a draft atlas and included in the real-engine acceptance captures; their generated source remains unapproved. Rack access checks the selected shelf slot and carried-load anchor. The rabbit has five authored pallet-jack push views, mirrored to cover eight-way travel, with distance-timed frames and live captures for every authored view. Final rack/stock art review remains open.
- Physical Android touch/framing/performance checks and a real host/guest device walkthrough have not been run. No Android device or ADB bridge is attached to this workspace.

See the [art index](../assets/source/warehouse-expansion-v1/ART_STATUS.md) for asset provenance and cleanup notes, and the [expansion plan](warehouse_expansion_plan.md) for the broader design contract.

## Verification

- The current real-engine warehouse acceptance journey passes **115 checks** (run `20261006-234800`) using the isolated warehouse-acceptance identity. It drives a loaded forklift through the service aisle, transfers and retrieves upper-row stock, parks and remounts, checks clear poses for all ten slots, verifies break-room collision footprints fit both triangles and rack rails/supports stay straight, and captures both mirrored completed breakrooms and racks plus construction stages. Review the live [left breakroom](../output/warehouse-expansion-v1/live-acceptance/20261006-234800-left-breakroom-complete.png), [right breakroom](../output/warehouse-expansion-v1/live-acceptance/20261006-234800-right-breakroom-complete.png), [left rack](../output/warehouse-expansion-v1/live-acceptance/20261006-234800-left-storage-complete.png), [right rack](../output/warehouse-expansion-v1/live-acceptance/20261006-234800-right-storage-complete.png), [upper-rack alignment](../output/warehouse-expansion-v1/live-acceptance/20261006-234800-forklift-upper-rack-alignment.png), and [stored upper pallet](../output/warehouse-expansion-v1/live-acceptance/20261006-234800-rack-world-upper-stock.png) captures. The assets remain provisional pending production-art approval.
- The runtime source-package tests ran **9 tests** after the breakroom art update and passed; the 69-image allowlist now includes the selected v5 triangular breakroom asset.
- The full LÖVE smoke suite passes **3,552 checks with zero failures** in the isolated smoke identity. It includes mobile-control and touchscreen interaction tests; it does not replace a physical-device pass.
- All **83 Python tool tests** pass. The Android `.love` archive includes **69 warehouse source images**, including the five-opening rack candidate, and passes mobile-mode smoke. The refreshed share pack is version **0.1.0-android.31** (`versionCode` 31): [download the installer](../output/android-share/0.1.0-android.31/ThePictureShop-0.1.0-android.31-Install.apk), 201,109,074 bytes (191.8 MiB). Its signing certificate matches the version-29 installer, so Android can update that install; the folder includes a checksum and install/send instructions. No Android device is attached, so install/launch was not verified. The package report still marks native crypto and gateway discovery as not production-ready; a real device and host/guest walkthrough remain open. At this file size, SMS/MMS is unsuitable; use a OneDrive download link if the phone's text app rejects the attachment.
- Warehouse tests use isolated state or the acceptance runner's own identity. Existing game saves were not touched, and no save backup was created.
