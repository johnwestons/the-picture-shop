# Warehouse expansion art — source pack v1

Prepared September 18, 2026; expansion update September 26, 2026. **The user approved the two-bay rack, breakroom and construction-stage art on September 26, 2026. Forklift and construction-worker source art remains unapproved for production. Both warehouse bays and all three room choices have a playable purchase path; visual registration and remaining vehicle/worker reviews are still open.**

[Implementation plan](../../../docs/warehouse_expansion_plan.md) · [Exact generation prompts](prompts.json)

[Current build status](../../../docs/warehouse_build_status.md) records the dual-bay catalog, current controls and the older verification baseline. Both bays offer open floor, storage and breakroom. `Config.warehouse.provisionalArt=true` remains enabled for the unapproved forklift and construction-worker imagery; expansion module and construction-stage catalog entries are approved.

## Expansion module art — September 26

These registered PNGs are user-approved art for the two bay orientations. Each is 1536×1024 RGBA. Their in-game position, scale, slot anchors and collision footprints still need calibration. The image files are copied into the runtime source pack; generated originals remain in the Codex generated-image history.

| Runtime file | Use | Status |
| --- | --- | --- |
| [rack-world-left-v2.png](modules/rack-world-left-v2.png) | Left-bay world rack | User-approved September 26; first-pass world and ten-slot registration still needs in-game calibration |
| [rack-world-right-v1.png](modules/rack-world-right-v1.png) | Right-bay world rack | User-approved September 26; independently oriented, ten-slot registration still needs in-game calibration |
| [breakroom-world-left-v1.png](modules/breakroom-world-left-v1.png) | Left-bay finished breakroom | User-approved September 26; furniture collision registration still needs in-game calibration |
| [breakroom-world-right-v1.png](modules/breakroom-world-right-v1.png) | Right-bay finished breakroom | User-approved September 26; furniture collision registration still needs in-game calibration |
| `left-storage-stage-1.png` … `left-storage-stage-4.png` | Left-bay storage construction | User-approved September 26; registered to the left bay |
| `rack-right-stage-1.png` … `rack-right-stage-3.png` | Right-bay storage construction | User-approved September 26; stage 4 uses the finished rack sprite |
| `breakroom-left-stage-1.png` … `breakroom-left-stage-3.png` | Left-bay breakroom construction | User-approved September 26; stage 4 uses the finished breakroom sprite |
| `breakroom-right-stage-1.png` … `breakroom-right-stage-3.png` | Right-bay breakroom construction | User-approved September 26; stage 4 uses the finished breakroom sprite |

The world racks are distinct from `rack-front-2x5-approved.png`, which is only the first-person shelf backdrop. The user-approved expansion art covers both rack orientations, both breakroom orientations and their construction stages. Open-floor work uses the sampled concrete surface because the finished option is an empty floor. Transform, slot, floor-seam and obstacle registrations still need visual calibration in the running game. The breakroom tool produced a four-panel wall-room study, but those panels did not match the floor-only module contract and were not added to the runtime pack.

## Selected warehouse and approved designs

- **Latest base:** [warehouse-base-v3-top-remake.png](warehouse-base-v3-top-remake.png), 1672×941 RGB. Rebuilds the top with brick, steel and conduit reaching the image boundaries. Preserves the approved lower floor outline, short flat front edge and black lower upgrade areas visually. No foreground apron.
- **Approved lower-layout reference:** [warehouse-base-v2-approved-bottom.png](warehouse-base-v2-approved-bottom.png), 1672×941 RGB. Retained so the approved footprint can be checked independently of the top remake.
- **User-approved shelf design:** [rack-front-2x5-approved.png](rack-front-2x5-approved.png), 1536×1024 RGB. Exactly five columns and two rows, all empty. This is the first-person background, not an isometric module.

The top remake is a new candidate, not an additional user approval. It is **layout-preserving, not pixel-identical**: comparison of v2/v3 rows 460–940 found 41.104% exact pixels, 58.896% changed, mean absolute RGB changes 1.887/1.562/1.319 out of 255. Do not describe it as an untouched lower raster. The visible floor perimeter and black bay positions remain aligned.

The candidate's **upper architecture is now registered** above the current background's roof silhouette through `src/warehouse_scene.lua`, filling the top gaps. The lower base remains the original 1536×1024 runtime image/walk mask: dock overlays, entrance/phone/office anchors, lounge foregrounds and all actor/equipment scales remain unchanged. The candidate's full floor/front trim is not yet registered and must not directly replace the live PNG.

## Vehicle and pallet source art

| File | Dimensions | Contents and status |
| --- | --- | --- |
| [forklift-eight-directions-unmanned-v1.png](forklift-eight-directions-unmanned-v1.png) | 1774×887 RGBA | Eight empty static headings, two rows of four |
| [forklift-eight-directions-manned-v2.png](forklift-eight-directions-manned-v2.png) | 1774×887 RGBA | Matching eight rabbit-occupied headings; driver-facing correction applied |
| [pallet-front-variants-v1.png](pallet-front-variants-v1.png) | 2172×724 RGBA | Three 724×724 frontal source cells: raw paper, strapped cut stacks, fully wrapped |

Forklift row-major order is **NW, N, NE, E / SE, S, SW, W**, matching the jack direction contract. The selected manned sheet shows rear-facing rabbit views toward N and front-facing rabbit views toward S, with driver facing the mast/forks. The earlier incorrect driver-facing candidate is not selected.

These original two sheets are static direction sources, **not a complete driving/lifting animation set**. Their nominal 4×2 cells are 443.5×443.5; do not blindly integer-divide into runtime frames. Normalize individually with reviewed wheel-contact, steering, mast and load anchors. Verify manned/unmanned geometry alignment before toggling them at runtime. See the new lift studies below; final fork-height layers, wheel/lift states, enter/exit and cargo occlusion still need production.

The pallet trio has matching bottom baselines around source y=648. Preserve translucent wrapping highlights. Empty pallets, partial wrap, printed/boxed/vendor variants and elevated isometric load registration remain pending.

## Fork raising/lowering studies — September 19

[forklift-lift](forklift-lift) contains one four-pose strip per direction, plus non-destructive correction attempts. Each v1/v2 source is 2048×768 RGBA with four 512×768 cells: ground, one-third, two-thirds and high. All eight directions are authored; lowering reads the same actual-height poses in reverse. Exact prompts, original generated paths and local filenames are in [forklift-lift/prompts.json](forklift-lift/prompts.json). Generated with the built-in image tool, not an API/CLI fallback.

`src/forklift.lua` supplies continuous height, lift/lower timing, safe travel height and reversal; `src/forklift_presentation.lua` selects source poses from current height. Four full-body poses still visibly step. This is not yet a seamless layered mast animation. Every catalog entry remains `approved=false`; ordinary production presentation refuses them unless the caller explicitly requests review art. The playable development slice intentionally uses that review path.

The isolated [forklift lift lab](../../../RUN_FORKLIFT_LIFT_LAB.bat) supports all eight views, raise/lower, travel height, pause and real simulated movement. It uses its own save identity and no live inventory. The initial 24 lower/mid/high captures ran successfully. Visual review of E lower/high, N high, NW high and S high confirmed the following **release blockers**, despite passing behavioral tests:

- Soft golden/gray alpha fringe remains around v1 sources; v2 cleanup requests did not reliably remove it.
- North v1 is the wrong rear three-quarter heading. North v2 corrects that heading and is now selected in the review catalog with recalibrated provisional anchors; the hidden ground carriage remains an estimate.
- South v1/v2 high forks read as dangling blades rather than a mechanically correct elevated carriage. [South v3](forklift-lift/south-raise-v3.png) extends the mast above the stationary cab and improves the high carriage connection. Its alpha fringe and nonuniform pose-height spacing still need correction; [exact correction prompt](forklift-lift/south-v3-prompt.json). This is a review candidate, not production approval.
- Some wheel-ground anchors and body proportions drift between frames/directions. A crosshair calibration is a review aid, not proof of stable ground contact.
- Load/mast/cage occlusion layers and continuous playback at normal/half speed remain unapproved.

Captures are review evidence, not production acceptance. The later playable development slice was enabled only after world, authority, collision, construction and upper-shelf integration tests; it does not claim that the art is finished on the basis of the 24 lab captures.

The refreshed catalog explicitly selects N v2 and S v3; other headings remain v1. Selected-frame cargo anchors keep a load on the visible tines instead of interpolating away from a held pose. Final captures in `output/warehouse-expansion-v1/forklift-lab-captures/` use a shared fit for all 32 source rectangles, fixing preview clipping at lowered south forks without zooming between directions. Refreshed N-high and S-low/high were inspected. Earlier captures are retained in `forklift-lab-captures-v1/` and `forklift-lab-captures-v2/`; none of these sources has been promoted to approved runtime art.

### Empty-seat raised poses — September 24

Eight [empty-seat lift sheets](forklift-lift/empty-seat-prompts.json) now pair with the eight occupied lift sheets. Each is a 2048×768 RGBA strip with four 512×768 height poses. The built-in image tool removed the driver and restored the empty cab, seat and controls without replacing the source sheets. The southeast sheet received cleanup passes for residual orange pixels and background alpha; v2 is selected. The runtime selects these strips whenever the forklift is parked, preserving the actual fork height and any suspended load after operator loss. The engine acceptance capture `output/warehouse-expansion-v1/live-acceptance/20260924-201026-parked-raised-load.png` shows the empty seat, raised cargo and worker standing beside the vehicle; the original pallet stayed in canonical forklift custody and remount succeeded. These sheets remain development art with `approved=false`; four-step motion, edge cleanup and detailed cargo/mast occlusion remain open.

Loaded in-engine reviews on September 24 captured all eight directions at 0%, 50% and 100% height in `output/warehouse-expansion-v1/live-acceptance/20260924-204158-forklift-parked-*.png`. The revised per-frame anchors center the original pallet on the visible blades rather than at the mast root, especially in east/west and diagonal views. The carried pallet's world label no longer covers its tine contact; its ID appears beside fork height in the vehicle badge. A rear-facing low load can still be hidden by the full-body source sprite, and lift motion still steps through four body poses. Neither issue is approved as final art.

The game and lift lab now use transparency-aware bilinear sampling for these four-cell sheets. It prevents color stored in fully transparent pixels from bleeding into the silhouette, and clamps samples within the selected cell so adjacent poses cannot leak across a frame edge. The PNG sources are unchanged and still need direct alpha-edge review before approval; physical mobile performance is unverified.

### Continuous eight-direction lift study — September 24

[Separate lift layers](forklift-layer-study/prompts.json) now provide fixed occupied and empty-seat bodies with moving carriages for all eight headings. West, southwest and northwest mirror the east, southeast and northeast layers. The north layer rises behind the cab guard and is clipped below its roof line; south uses a narrower front-facing carriage. The development-art renderer keeps the bodies and wheels still while the carriage follows actual continuous height. The original four-pose strips remain the loading fallback. Isolated previews and loaded low/mid/high in-engine captures were inspected for north and south as well as the earlier six views. These generated layers are **not approved production art**. Empty/occupied body geometry still differs slightly, detailed cargo occlusion and device review remain open.

## Raccoon construction tool studies

### Repaired runtime draft — September 19

[mechanic-work-atlas-v2.png](mechanic-work-atlas-v2.png) is a new 1254×1254 transparent atlas with four rows (concrete, hammer, drill, paint) and four poses per action. Generated with the built-in image tool; [exact prompt and references](mechanic-work-atlas-v2-prompt.json). It repairs the overlapping-pose problem in the original studies below.

`src/mechanic_work_presentation.lua` registers each complete pose individually: raised tools cross nominal row boundaries, so equal-cell cuts remain inappropriate. The body reference controls scale, not tool-inclusive bounds. Four host-timed frames per second match the existing shared-workshop snapshot cadence; paused/blocked/travelling visitors do not animate tool work. Sources remain `approved=false` and are used only under the explicit development-art option.

Native contact preview: `output/warehouse-expansion-v1/mechanic-work-review/contact-runtime.png`. Combined motion audit: 20 strips, zero errors, five expected work-pose bounding-box warnings from crouching/tool extension; no clipping/detached pieces/duplicate-frame/gait warnings. Minor alpha fringe and final continuous work-loop polish remain. Source files were preserved; no automated repaint or destructive cleanup was applied.

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

## Next production gates

1. Approve the new upper architecture, register the complete master, define exact bay seams/masks and keep all existing object scales.
2. Prove one seamless open-floor bay, then derive both orientations × three choices × four construction stages plus finished states (30 registered state sets).
3. Split approved rack background/foreground and define ten pallet anchors in both perspectives.
4. Normalize and repair vehicle/worker source frames; finish the reviewed lift states, remaining stock views and rabbit pushing-jack animation.
5. Expand the now-connected left-storage workflow to the remaining module options only after their geometry and visible outcomes are ready; retain the explicit provisional-art boundary until production art passes review.
6. Run desktop/mobile simulation and host/guest conservation/reconnect tests before later device-dependent testing.

## Generation and scope

All new art used the **built-in image_gen tool** via the imagegen skill; no CLI/API fallback or external key. The [prompt set](prompts.json) records exact prompts, generated originals, selected workspace files and rejected iterations. Superseded all-floor, apron and incorrect-driver images are not production selections.

The sprite-gait-overhaul skill supplied anchor, direction, gait and audit gates. The September 18 art pass did not change gameplay. The September 19 integration now includes a playable first storage/vehicle slice, registered upper architecture, construction work loops and two-high stack controls; see the build status for scope. No player save, installed device build, authored NPC dialogue or character/machine scale was changed.
