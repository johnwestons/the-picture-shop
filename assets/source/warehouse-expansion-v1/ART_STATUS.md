# Warehouse expansion art — source pack v1

Prepared September 18, 2026; expansion update September 26, 2026. **The normal game now offers both expansion bays with storage, open-floor, and breakroom choices. Source art remains provisional for production.**

[Implementation plan](../../../docs/warehouse_expansion_plan.md) · [Exact generation prompts](prompts.json)

[Current build status](../../../docs/warehouse_build_status.md) records the playable choices, controls, verification and remaining art/device gates. `Config.warehouse.provisionalArt=true` exposes the draft forklift and warehouse imagery with a development-art notice; generated scene and construction entries remain `approved=false`.

## Selected warehouse and approved designs

- **Latest base:** [warehouse-base-v3-top-remake.png](warehouse-base-v3-top-remake.png), 1672×941 RGB. Rebuilds the top with brick, steel and conduit reaching the image boundaries. Preserves the approved lower floor outline, short flat front edge and black lower upgrade areas visually. No foreground apron.
- **Approved lower-layout reference:** [warehouse-base-v2-approved-bottom.png](warehouse-base-v2-approved-bottom.png), 1672×941 RGB. Retained so the approved footprint can be checked independently of the top remake.
- **User-approved shelf design:** [rack-front-2x5-approved.png](rack-front-2x5-approved.png), 1536×1024 RGB. Exactly five columns and two rows, all empty. This is the first-person background, not an isometric module.

The top remake is a new candidate, not an additional user approval. It is **layout-preserving, not pixel-identical**: comparison of v2/v3 rows 460–940 found 41.104% exact pixels, 58.896% changed, mean absolute RGB changes 1.887/1.562/1.319 out of 255. Do not describe it as an untouched lower raster. The visible floor perimeter and black bay positions remain aligned.

The candidate's **upper architecture is now registered** above the current background's roof silhouette through `src/warehouse_scene.lua`, filling the top gaps. The lower base remains the original 1536×1024 runtime image/walk mask: dock overlays, entrance/phone/office anchors, lounge foregrounds and all actor/equipment scales remain unchanged. The candidate's full floor/front trim is not yet registered and must not directly replace the live PNG.

## Both expansion bays and room art — September 26

The live game has three choices for either mirrored front bay. `src/warehouse_construction_presentation.lua` registers all four construction stages for both bays and each choice; the right bay keeps the same source ground anchor under a negative horizontal scale. Runtime room assets are included in the mobile source package.

| File | Dimensions | Runtime role and status |
| --- | --- | --- |
| [breakroom-furnishings-v1.png](rooms/breakroom-furnishings-v1.png) | 1536×1024 RGBA | Superseded rectangular reference shell, retained for comparison; `approved=false` |
| [breakroom-triangle-v1-candidate.png](rooms/breakroom-triangle-v1-candidate.png) | 1536×1024 RGBA | First triangular-layout draft; retained as a comparison source after its visible floor edge proved smaller than its registration corners; `approved=false` |
| [breakroom-triangle-v2-candidate.png](rooms/breakroom-triangle-v2-candidate.png) | 1536×1024 RGBA | Intermediate floor-triangle redesign; retained for comparison; `approved=false` |
| [breakroom-triangle-v3-candidate.png](rooms/breakroom-triangle-v3-candidate.png) | 1536×1024 RGBA | Compact room with a measured floor triangle, open diagonal entrance, and inward trim overlap; `approved=false` |
| [breakroom-triangle-v5-candidate.png](rooms/breakroom-triangle-v5-candidate.png) | 1536×1024 RGBA | Current reviewed fit candidate; vending machine inset from the diagonal floor edge, transparent exterior; `approved=false` |
| [breakroom-construction-atlas-v1.png](rooms/breakroom-construction-atlas-v1.png) | 1536×1024 RGBA | Four 768×512 construction crops, reused for either bay with mirrored registration; `approved=false` |
| [floor-construction-atlas-v2-clean.png](rooms/floor-construction-atlas-v2-clean.png) | 1536×1024 RGBA | Cleaned four-stage floor construction atlas; removes the stray “BUG 4/4” text from the preserved [v1 source](rooms/floor-construction-atlas-v1.png); `approved=false` |

Acceptance captures exercise all six completed choices and every mirrored floor/breakroom construction stage at game scale. A consolidated [six-choice review board](../../../output/warehouse-expansion-v1/live-acceptance/20260927-074650-room-choice-review.png) shows storage, open floor, and breakroom for both mirrored bays. It helps compare orientation and room coverage; it does not replace production art approval. The module sprites and lower-floor integration are playable draft art, not a finished seamless warehouse-base replacement.

The open-floor fill now samples the existing warehouse concrete along each bay's shared underlap edge and reflects that source into the expansion triangle. Both left/right floor joins and stage-1 construction are captured in LÖVE acceptance run `20260927-044946`; the live base bitmap, movement mask and gameplay scale remain unchanged. This removes the earlier stretched-triangle texture break without introducing a mismatched floor tile. The overall base/source art is still provisional pending the complete seam, edge and production-art review.

### Earlier five-opening world rack — September 27

[rack-world-left-v5-triangle-aligned-candidate.png](rack-world-left-v5-triangle-aligned-candidate.png) is a 1536×1024 RGBA comparison candidate with five openings across two levels. Its affine shear matched the bay seam but also leaned its upright supports, so it is no longer the selected runtime source. The older v4 candidate remains preserved for comparison.

### Triangular expansion fit — October 6

`breakroom-triangle-v5-candidate.png` maps its measured floor vertices to the three vertices of each bay; the right room mirrors the same transform. The vending machine is smaller and set in from the diagonal edge, with its collision footprint updated to match. The renderer preserves a narrow overlap for the left/bottom wall trim while clipping the diagonal edge to the bay seam. Construction-stage art remains clipped to the exact bay polygon. The candidate remains `approved=false` pending production-art approval.

`rack-world-left-v6-triangle-fit-candidate.png` has five openings and six vertical front supports. Its X/Y registration scales the beam angle to the bay seam while keeping the supports vertical; the narrower rack and support obstacles fit inside the triangular floor. LÖVE run `20261006-234800` captured both rack orientations and passed the loaded forklift aisle, upper-shelf transfer, parking, and remount journey. Layout checks verify both rails are seam-aligned and all six supports remain vertical in both mirrored bays. Both new assets remain `approved=false`; production-art approval remains open.

The real-engine run `20261006-234800` passes **115 checks** with the updated triangular fit active. It captures both mirrored breakrooms, floor bays, and storage racks in the full warehouse scene, drives the loaded forklift through the service aisle, transfers and retrieves upper stock, and checks all ten slots. It also verifies that breakroom collision footprints fit both bay triangles, rack beams align with each seam, and supports remain vertical. Review the [left breakroom](../../../output/warehouse-expansion-v1/live-acceptance/20261006-234800-left-breakroom-complete.png), [right breakroom](../../../output/warehouse-expansion-v1/live-acceptance/20261006-234800-right-breakroom-complete.png), [left rack](../../../output/warehouse-expansion-v1/live-acceptance/20261006-234800-left-storage-complete.png), [right rack](../../../output/warehouse-expansion-v1/live-acceptance/20261006-234800-right-storage-complete.png), [upper-rack alignment](../../../output/warehouse-expansion-v1/live-acceptance/20261006-234800-forklift-upper-rack-alignment.png), and [stored upper pallet](../../../output/warehouse-expansion-v1/live-acceptance/20261006-234800-rack-world-upper-stock.png) captures. The source remains a candidate with `approved=false`; production-art approval remains open.

## Vehicle and pallet source art

| File | Dimensions | Contents and status |
| --- | --- | --- |
| [forklift-eight-directions-unmanned-v1.png](forklift-eight-directions-unmanned-v1.png) | 1774×887 RGBA | Eight empty static headings, two rows of four |
| [forklift-eight-directions-manned-v2.png](forklift-eight-directions-manned-v2.png) | 1774×887 RGBA | Matching eight rabbit-occupied headings; driver-facing correction applied |
| [pallet-front-variants-v1.png](pallet-front-variants-v1.png) | 2172×724 RGBA | Three 724×724 frontal source cells: raw paper, strapped cut stacks, fully wrapped |

Forklift row-major order is **NW, N, NE, E / SE, S, SW, W**, matching the jack direction contract. The selected manned sheet shows rear-facing rabbit views toward N and front-facing rabbit views toward S, with driver facing the mast/forks. The earlier incorrect driver-facing candidate is not selected.

These original two sheets are static direction sources, **not a complete driving/lifting animation set**. Their nominal 4×2 cells are 443.5×443.5; do not blindly integer-divide into runtime frames. Normalize individually with reviewed wheel-contact, steering, mast and load anchors. Verify manned/unmanned geometry alignment before toggling them at runtime. See the new lift studies below; final fork-height layers, wheel/lift states, enter/exit and cargo occlusion still need production.

The original three front views are raw paper, strapped cut stacks and fully wrapped stock. The new [four-state candidate atlas](pallet-front-variants-v2-candidate.png) adds printed sheets, partial wrap, cartons and mixed supplier goods. Its four 768×512 cells are registered in the rack presenter with measured per-cell bounds and baselines; transparent-edge sampling is premultiplied to suppress the hidden RGB fringe during downscaling. The rack screen now selects raw, cut, wrapped, printed, partial-wrap, boxed and supplier views from pallet state. Partial-wrap art is ready when a progress value is present; the current wrapper still completes atomically. The candidate remains `approved=false`, and the elevated world-load views remain separate from these frontal rack images.

The new atlas is 1536×1024 RGBA. Alpha-at-16 bounds have at least seven pixels of cell margin and no clipped shapes. The four variants are exercised by the rack screen regression and captured by the real-engine warehouse acceptance journey. These checks verify registration and state selection; they do not approve the art for production.

### Rabbit pallet-jack push cycles — September 27

Five eight-frame push cycles now cover east, north, northeast, southeast and south; the animation selector mirrors these views for west, northwest and southwest. The normalized strips use a shared 512×512 cell and planted-foot anchor, register only while provisional warehouse art is enabled, and advance from actual movement distance. Direction-specific operator foot anchors tune the hand reach to each handle view. Strict sprite-gait audit: **10 animation entries, 0 errors, 0 warnings**. The LÖVE acceptance run `20261007-003809` captures all five authored views beside the live pallet jack and checks the runtime action mapping. Source atlases, normalized runtime strips, prompts, contact sheets and audit details are retained in [pallet-jack-push](pallet-jack-push/) and `output/warehouse-expansion-v1/pallet-jack-push-review/`. Art remains `approved=false` pending final production review.

## Fork raising/lowering studies — September 19

[forklift-lift](forklift-lift) contains one four-pose strip per direction, plus non-destructive correction attempts. Each v1/v2 source is 2048×768 RGBA with four 512×768 cells: ground, one-third, two-thirds and high. All eight directions are authored; lowering reads the same actual-height poses in reverse. Exact prompts, original generated paths and local filenames are in [forklift-lift/prompts.json](forklift-lift/prompts.json). Generated with the built-in image tool, not an API/CLI fallback.

`src/forklift.lua` supplies continuous height, lift/lower timing, safe travel height and reversal; `src/forklift_presentation.lua` selects source poses from current height. The four-pose strips remain a visibly stepped fallback. In normal development-art play, the renderer uses the continuous layer study when its registered files are available, keeping the body fixed while the mast moves. Both presentations remain approved=false; the production path stays gated. Every catalog entry remains `approved=false`; ordinary production presentation refuses them unless the caller explicitly requests review art. The playable development slice intentionally uses that review path.

The isolated [forklift lift lab](../../../RUN_FORKLIFT_LIFT_LAB.bat) supports all eight views, raise/lower, travel height, pause and real simulated movement. It uses its own save identity and no live inventory. The initial 24 lower/mid/high captures ran successfully. Visual review of E lower/high, N high, NW high and S high confirmed the following **release blockers**, despite passing behavioral tests:

- Soft golden/gray alpha fringe remains around v1 sources; v2 cleanup requests did not reliably remove it.
- North v1 is the wrong rear three-quarter heading. North v2 corrects that heading and is now selected in the review catalog with recalibrated provisional anchors; the hidden ground carriage remains an estimate.
- South v1/v2 high forks read as dangling blades rather than a mechanically correct elevated carriage. [South v3](forklift-lift/south-raise-v3.png) extends the mast above the stationary cab and improves the high carriage connection. Its alpha fringe and nonuniform pose-height spacing still need correction; [exact correction prompt](forklift-lift/south-v3-prompt.json). This is a review candidate, not production approval.
- Some wheel-ground anchors and body proportions drift between frames/directions. A crosshair calibration is a review aid, not proof of stable ground contact.
- Load/mast/cage occlusion layers and continuous playback at normal/half speed remain unapproved.

Captures are review evidence, not production acceptance. The later playable development slice was enabled only after world, authority, collision, construction and upper-shelf integration tests; it does not claim that the art is finished on the basis of the 24 lab captures.

The refreshed catalog explicitly selects N v2 and S v3; other headings remain v1. Selected-frame cargo anchors keep a load on the visible tines instead of interpolating away from a held pose. Final captures in `output/warehouse-expansion-v1/forklift-lab-captures/` use a shared fit for all 32 source rectangles, fixing preview clipping at lowered south forks without zooming between directions. Refreshed N-high and S-low/high were inspected. Earlier captures are retained in `forklift-lab-captures-v1/` and `forklift-lab-captures-v2/`; none of these sources has been promoted to approved runtime art.

### Empty-seat raised poses — September 24

Eight [empty-seat lift sheets](forklift-lift/empty-seat-prompts.json) now pair with the eight occupied lift sheets. Each is a 2048×768 RGBA strip with four 512×768 height poses. The built-in image tool removed the driver and restored the empty cab, seat and controls without replacing the source sheets. The southeast sheet received cleanup passes for residual orange pixels and background alpha; v2 is selected. The runtime selects these strips whenever the forklift is parked, preserving the actual fork height and any suspended load after operator loss. The engine acceptance capture `output/warehouse-expansion-v1/live-acceptance/20260924-201026-parked-raised-load.png` shows the empty seat, raised cargo and worker standing beside the vehicle; the original pallet stayed in canonical forklift custody and remount succeeded. These sheets remain development art with `approved=false`; direct alpha-edge review and detailed cargo/mast occlusion remain open. The stepped four-pose set is only the fallback when a layer cannot load.

Loaded in-engine reviews on September 24 captured all eight directions at 0%, 50% and 100% height in `output/warehouse-expansion-v1/live-acceptance/20260924-204158-forklift-parked-*.png`. The revised per-frame anchors center the original pallet on the visible blades rather than at the mast root, especially in east/west and diagonal views. The carried pallet's world label no longer covers its tine contact; its ID appears beside fork height in the vehicle badge. A rear-facing low load can still be hidden by the full-body fallback. The layer study removes stepped lift changes in development play, but rear cargo occlusion and final source-art review remain open.

The game and lift lab now use transparency-aware bilinear sampling for these four-cell sheets. It prevents color stored in fully transparent pixels from bleeding into the silhouette, and clamps samples within the selected cell so adjacent poses cannot leak across a frame edge. The PNG sources are unchanged and still need direct alpha-edge review before approval; physical mobile performance is unverified.

### Continuous eight-direction lift study — September 24

[Separate lift layers](forklift-layer-study/prompts.json) now provide fixed occupied and empty-seat bodies with moving carriages for all eight headings. West, southwest and northwest mirror the east, southeast and northeast layers. The north layer rises behind the cab guard and is clipped below its roof line; south uses a narrower front-facing carriage. The development-art renderer keeps the bodies and wheels still while the carriage follows actual continuous height. The original four-pose strips remain the loading fallback. Isolated previews and loaded low/mid/high in-engine captures were inspected for north and south as well as the earlier six views. These generated layers are **not approved production art**. Empty/occupied body geometry still differs slightly, detailed cargo occlusion and device review remain open.

## Raccoon construction tool studies

### Repaired runtime draft — September 19

[mechanic-work-atlas-v2.png](mechanic-work-atlas-v2.png) is a new 1254×1254 transparent atlas with four rows (concrete, hammer, drill, paint) and four poses per action. Generated with the built-in image tool; [exact prompt and references](mechanic-work-atlas-v2-prompt.json). It repairs the overlapping-pose problem in the original studies below.

`src/mechanic_work_presentation.lua` registers each complete pose individually: raised tools cross nominal row boundaries, so equal-cell cuts remain inappropriate. The body reference controls scale, not tool-inclusive bounds. Four host-timed frames per second match the existing shared-workshop snapshot cadence; paused/blocked/travelling visitors do not animate tool work. Sources remain `approved=false` and are used only under the explicit development-art option.

Native contact preview: `output/warehouse-expansion-v1/mechanic-work-review/contact-runtime.png`. Combined motion audit: 20 strips, zero errors, five expected work-pose bounding-box warnings from crouching/tool extension; no clipping/detached pieces/duplicate-frame/gait warnings. Minor alpha fringe and final continuous work-loop polish remain. Source files were preserved; no automated repaint or destructive cleanup was applied.

### Eight-pose runtime candidates — September 27

The selected runtime candidates are [concrete v3c](mechanic-work-concrete-v3c-candidate.png), [hammer v3](mechanic-work-hammer-v3-candidate.png), [drill v3c](mechanic-work-drill-v3c-candidate.png), and [paint v3](mechanic-work-paint-v3-candidate.png). Each atlas is 1536×1024 RGBA, with eight complete 384×512 cells. Concrete now has a readable back-and-forth float stroke; hammer, drill, and roller show separate working phases. Individual planted-foot anchors keep the worker at a stable 76.8-world-pixel body reference while raised tools extend above the body.

Normalized registration strips remain in `output/warehouse-expansion-v1/mechanic-work-v3-review/`; the current checkerboard contact sheets and 4 fps previews are in `output/warehouse-expansion-v1/mechanic-work-v3-current-audit/`, with additional 0.5x GIFs at 500 ms per frame. The refreshed 20-animation audit at `output/warehouse-expansion-v1/mechanic-work-v3-current-audit/report.json` covers all 16 live walk/idle strips and the four selected work loops; it reports **0 errors and 8 work-loop bounds warnings**. Those are alpha-bound heuristics for tool reach and changing work poses; registered contact anchors keep planted feet on the shared baseline in the reviewed checkerboard contact sheets. No clipping, detached components, exact duplicates, or gait warnings were found. Superseded four-pose review loops remain archived outside the active motion spec. The source sheets render in LÖVE and use premultiplied-alpha sampling to reduce transparent-edge halos. The candidate sheets remain `approved=false`; this audit does not approve the production art set.

### Earlier source studies (not selected for runtime work)

All four are 2172×724 RGBA, eight visible poses each. They preserve the user-approved goggles/scarf/overalls design but are **not audited runtime strips**.

| Source | Planned building stage | Review notes |
| --- | --- | --- |
| [mechanic-concrete-source-v1.png](mechanic-concrete-source-v1.png) | Day 1: foundation/concrete, hand float | Kneeling/leaning pose anchors need individual registration; first pose has only 3px left clearance |
| [mechanic-hammer-source-v1.png](mechanic-hammer-source-v1.png) | Day 2: framing, hammer | User liked the design; first/last poses need tool-continuity review |
| [mechanic-drill-source-v1.png](mechanic-drill-source-v1.png) | Day 3: fixtures/rack assembly, drill | First tail touches left image boundary (21 pixels at alpha ≥16); repair/regenerate clipped pose |
| [mechanic-paint-source-v1.png](mechanic-paint-source-v1.png) | Day 4: finishing, roller | Red fringe around raised arm/roller; apparent working-hand change needs correction |

2172÷8 is 271.5. Equal-width slicing cuts through artwork on multiple poses. Use reviewed individual pose crops, regenerating any inseparable/overlapping/clipped poses. Normalize by body height and contact anchors, not tool-inclusive bounds: raising a tool must not shrink the worker. Check halos on light/dark backgrounds and tool handedness, then inspect complete loops at normal and half speed. No continuous animation playback approval is claimed for these sources.

## Existing Mouse Frontier locomotion

The [mechanic-raccoon](mechanic-raccoon) subfolder contains 18 source-identical PNGs copied from the user-designated sibling project:

- Eight authored directional walking strips and eight matching idles.
- Original identity reference and legacy three-frame `use.png` (reference-only, not a construction loop).
- All 18 SHA-256 comparisons matched their originals.
- Source: `C:/Users/johnw/OneDrive/Documents/ChatGPT/Mouse Frontier 8.10`.
- Reuse basis: explicit user instruction. No separate license document was found; no third-party license is asserted.

[Staging motion specification](../../../character-motion/mechanic-raccoon-warehouse-staging.json) keeps the eight authored directions, source anchors and gait metadata. The sprite-gait-overhaul strict audit passed **16 strips / 80 frames / 0 errors / 0 warnings**. This result applies only to the copied walk/idle set, not the generated tool sheets or forklift. All 16 contact sheets were reviewed; continuous GIF playback remains unverified.

Initial audit outputs are in `output/warehouse-expansion-v1/mechanic-motion-audit/`. The playable visitor uses eight-way distance-based walking at 72 world pixels/second with collision substeps and source-height normalization to the existing 76.8-pixel actor reference. Its locomotion audit is in `output/warehouse-expansion-v1/mechanic-live-motion-audit/` (16 strips, zero errors/warnings). The four work loops now use the repaired v2 atlas described above, with guarded idle fallback when art is unavailable or the visitor is not actively building.

## Remaining production gates

1. Finish the lower warehouse base/front-trim production artwork and certify all room seams/masks. The open-floor material now continues cleanly across the shared edge, but the lower source master itself remains unchanged and the complete art set is not yet production-approved.
2. Finish forklift full-body lift stepping and mast/cargo occlusion. The playable upper-row path now physically aligns with the rack; see the current [forklift-to-rack capture](../../../output/warehouse-expansion-v1/live-acceptance/20260927-074650-forklift-upper-rack-alignment.png). Forklift motion and rack art are still provisional, and the source art remains draft. The raccoon's eight-pose work loops are integrated and audited, but remain unapproved pending the complete art review.
3. Review the five-opening world rack and registered stock views against the live forklift mast and rack front; the [stored upper pallet capture](../../../output/warehouse-expansion-v1/live-acceptance/20260927-074650-rack-world-upper-stock.png) records the current placement. Review the registered rabbit push cycles for production approval.
4. Run physical Android touch/framing/performance checks and a real host/guest device walkthrough. No Android device or ADB bridge is attached here; desktop forced-mobile tests do not replace those checks.
5. Promote catalog entries only after the full art set passes source, transparency, anchor, mirror, occlusion, and in-engine acceptance review.

## Generation and scope

All new art used the **built-in image_gen tool** via the imagegen skill; no CLI/API fallback or external key. The [prompt set](prompts.json) records exact prompts, generated originals, selected workspace files and rejected iterations. Superseded all-floor, apron and incorrect-driver images are not production selections.

The sprite-gait-overhaul skill supplied anchor, direction, gait and audit gates. The expansion update opened all six bay-and-room combinations, added registered breakroom and construction art, and kept the existing actor/equipment scales. No player save or installed device build was changed.
