# Picture Shop asset pipeline

## Warehouse walk mask

`assets/generated/warehouse-layout-final-walkmask.png` is a same-size (1536x1024) binary mask for the approved `warehouse-layout-final.png` sprite.
White (`#ffffff`) means the rabbit may walk on that pixel: the concrete floor, office floor, and the open office doorway route. Black (`#000000`) means blocked: exterior/background, walls, shelving, desks, chair, rug, cabinets, electrical fixtures, and other fixed obstacles. Keep the mask aligned 1:1 with the source image; do not resize or filter it. A runtime collision query should sample the mask at the character's intended footprint (usually feet/center-bottom), treating only white as walkable.

The mask was drawn as deterministic hard-edged polygons from the approved warehouse composition: open factory floor in front, loading dock at upper left, separate office in the upper middle, separate lobby/reception at upper right, and the diagonally oriented double-glass entrance threshold. If the warehouse art changes, revise the mask geometry and verify it visually at native dimensions.

`tools/create_warehouse_layout_walkmask.py` rebuilds the entrance-aware mask at native resolution and preserves the strict black/white contract. `tools/prepare_warehouse_reference.py` prepares the approved reference at the runtime 1536x1024 canvas without distorting its visible 1536px-wide artwork.

## Reusable Mouse Frontier tools

The neighboring project at `C:\Users\johnw\OneDrive\Documents\ChatGPT\Mouse Frontier 8.10` contains useful, project-specific precedents:

- `tools/character_sprite_doctor.py` and `tools/SPRITE_WORKFLOW.md`: audit/repair/import animation sheets, including alpha, crop, baseline, frame counts, and contact sheets.
- `tools/chroma.py` and `tools/prepare_generated_sprite.py`: conservative green-screen removal and transparent PNG preparation.
- `tools/build_character_packs.py` and `tools/generate_character_animations.py`: convert authored/generated atlases into runtime strips.
- `game/character_animation.lua`: quad slicing, nearest-pixel animation playback, facing correction, and baseline anchoring.
- `game/assets.lua` and `game/asset_streamer.lua`: lazy image loading, atlas registration, and retaining only active assets.
- `game/screen_ui.lua`: pixel UI buttons, panels, dialogs, tooltips, and nine-slice frames.
- `game/interior_streamer.lua`, `game/world_renderer.lua`, and `game/interaction_router.lua`: useful patterns for room rendering, layered sprites, and proximity/use interactions.

These scripts should be adapted rather than copied wholesale: they assume Mouse Frontier's train-world paths, action names, dimensions, and save/state model. Existing Mouse Frontier art is reference material unless explicitly approved for Picture Shop use.

## Picture Shop runtime contract

- `warehouse-layout-final.png` and `warehouse-layout-final-walkmask.png` remain exactly the same dimensions and alignment.
- The walkmask contains only black and white pixels. White is walkable; black is blocked.
- `rabbit-worker-atlas.png` is a transparent 6×4 grid. The runtime currently uses row 1 idle frames and row 2's six-frame walk loop; later machine/computer/carry actions remain authored in rows 3–4.
- `polar-115-sprite-sheet-clear-table-transparent.png` keeps the two large machine tables empty. Paper is a separate optional layer and appears only after the player explicitly loads it.
- `empty-pallet.png`, `paper-stack.png`, `toolbox-small.png`, and `toolbox-large.png` are standalone transparent props. `paper-storage-boxes-strip.png` is a three-variant strip: closed box, open empty box, and open box with paper; the runtime registers each variant as a separate quad.
- All runtime images use nearest-neighbor filtering and hard pixel edges.

Run `tools/asset_doctor.py` after changing a runtime PNG. It checks required files, warehouse/mask alignment, strict binary mask values, atlas dimensions, nonempty rabbit cells, prop transparency, and alpha support. Repairs remain preview-first and non-destructive, following Mouse Frontier's sprite-doctor policy.

## Character sprite intake

Drop authored character PNGs in `assets/Characters/`. `tools/stage_character_sources.py` creates doctor-ready strips without changing those originals. The adapted Mouse Frontier `character_sprite_doctor.py` then normalizes each supported action to 512x512 frames; approved previews are copied to `output/sprite-doctor/approved/`. `tools/install_character_assets.py` removes checkerboard residue and installs the final transparent strips under `assets/generated/characters/<character>/`. The runtime loader in `src/character_assets.lua` slices those strips into nearest-filtered quads and the smoke test verifies every registered action and frame count. Only actions actually supplied are registered; missing combat or other poses are not invented.

## Loading-bay layers

The warehouse background remains the closed-door base. `loading-bay-door-strip.png` is a five-frame transparent overlay built from the approved ImageGen open-door edit. Frames progressively reveal the parking lot from the bottom of the shutter upward; pixels outside the steel-framed aperture stay transparent so the warehouse, controls, bollards, and floor remain unchanged.

`tools/build_loading_bay_layers.py` rebuilds the strip and `output/loading-bay-animation-preview.png` from the preserved open-bay source in `output/loading-bay-open-generated.png`. Runtime placement uses the native crop origin `(200, 170)`, a `260×260` frame, and the warehouse background's X/Y scale. The first frame is intentionally transparent because the closed shutter is already baked into the warehouse base.

`tools/normalize_walkmask_binary.py` converts the active mask using the same 90-percent-white threshold used by navigation. This preserves gameplay classification while enforcing the documented strict `{0,255}` contract.

## Delivery truck layers

The delivery vehicle is independent of the warehouse and loading-bay art. `delivery-truck-open.png` is a transparent `512×512` base with an empty cargo opening. `truck-cargo-door-strip.png` is a five-frame, `2560×512` overlay: frames 1–4 animate the fitted roll-up door upward, while frame 5 is intentionally transparent so the open base shows through unchanged.

`tools/build_truck_assets.py` rebuilds both runtime files and `output/truck-cargo-door-animation-preview.png` from the preserved open and closed sources. Every cargo-door frame keeps the same full-canvas anchor, so the base and overlay use one transform without visible jitter. At runtime, the composed truck is stencil-clipped to the loading-bay aperture; this makes it appear behind the wall while backing in instead of drawing over the warehouse facade.

## Cutter operator console

`polar-operator-console.png` is the transparent front-view machine base generated from the user's layout reference. Runtime text and measurements are drawn separately so work-order IDs, dimensions, rotation, and backgauge values remain exact and interactive. `cutter-control-buttons-strip.png` contains raised/pressed black dual-hand controls and raised/pressed red emergency-stop controls.

The clamp and blade are independent five-frame overlays in `cutter-clamp-strip.png` and `cutter-blade-strip.png`. The clamp travels down to the paper before a cut; the blade completes a down-and-up cycle. `tools/build_cutter_gui_assets.py` installs the approved source and deterministically rebuilds all aligned overlays. The paper itself is rendered from saved job data because its proportions, artwork colors, remaining margins, orientation, and trimmed dimensions change during play.

## Movable cutter floor sprites

`polar-cutter-directions-strip.png` is a transparent `2048×512` strip ordered northwest, northeast, southwest, southeast. The first two frames show the operator side; the opposite rotations show the plain rear housing and service cabinets instead of incorrectly mirroring the touchscreen and controls. `tools/build_cutter_direction_assets.py` extracts the four approved generated views, removes detached residue, normalizes their baselines, and installs each in a fixed `512×512` frame.

Cutter position and direction are saved independently from the cutter simulation. Machine-relocation mode uses a large collision footprint, edge samples against the walkmask, slow movement, and blocks relocation while paper remains at the cutter. Finished pallets are staged relative to the cutter's saved direction and current floor position.

## Loaded customer pallets

`loaded-paper-pallet-directions-strip.png` is a transparent four-frame `1024×256` strip ordered northwest, northeast, southwest, southeast. Every frame uses the same pallet and paper quantity, with the paper stack physically touching the deck boards. `loaded-paper-pallet.png` retains the northwest frame as a standalone compatibility asset. `tools/build_loaded_pallet_asset.py` extracts and normalizes the four approved generated directions.

The sprite is only the visual layer. Job ID, pallet ID, sheet quantity, paper ID, dimensions, cut status, warehouse position, and unload animation progress live on the saved pallet record. This lets the truck manifest, world tooltip, cutter, office inventory, and pallet jack share one authoritative object.

## Pallet jack

`pallet-jack-directions-strip.png` and `pallet-jack-loaded-directions-strip.png` are matching four-frame `1024×256` strips in the same direction order as the loaded pallets. The loaded strip aligns each directional pallet over both forks at a practical scale. `tools/build_pallet_jack_assets.py` removes neighboring-cell overlap from the generated 2×2 source, normalizes every direction to a fixed `256×256` anchor, and builds the loaded composites without modifying the approved sources.

Pallet-jack position, direction, and carried pallet ID are saved. The runtime uses a smaller empty collision footprint, a larger loaded footprint, slower loaded movement, and validates the pallet's directional drop offset before placement.
# Sprite Grounding Rule

All movable characters, machines, pallets, vehicles, and props must have a true transparent background and must not include a painted oval or circular floor shadow. Do not add procedural ellipse shadows in runtime drawing code. The warehouse artwork supplies the scene lighting and grounding.

Collision uses the visible floor-contact footprint, not the full transparent image canvas. Define narrow `collisionHalfWidth` and `collisionHalfHeight` values for placeable sprites and verify them in-game whenever artwork changes.
