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
- The player uses five two-frame directional idle strips paired with five eight-frame directional walk strips. North/south are direct, northeast/southeast are mirrored for their western counterparts, and east is mirrored for west. The last nonzero movement direction selects both states, so stopping preserves facing. Every gait follows contact, down, passing, up, opposite contact, down, passing, up. All walk-prefixed actions share one distance-synchronized frame clock: 20 world pixels per frame, or about a 1.032-second eight-frame cycle at the 155-pixel/second base speed. A smooth gait curve makes contact and weight-loading slightly slower, then passing and knee-up slightly faster; its average is the configured base pace, and it also modulates acceleration without changing release or reversal braking.
- `polar-115-sprite-sheet-clear-table-transparent.png` keeps the two large machine tables empty. Paper is a separate optional layer and appears only after the player explicitly loads it.
- `empty-pallet.png`, `paper-stack.png`, `toolbox-small.png`, and `toolbox-large.png` are standalone transparent props. `paper-storage-boxes-strip.png` is a three-variant strip: closed box, open empty box, and open box with paper; the runtime registers each variant as a separate quad.
- All runtime images use nearest-neighbor filtering and hard pixel edges.

Run `tools/asset_doctor.py` after changing a runtime PNG. It checks required files, warehouse/mask alignment, strict binary mask values, player-strip dimensions and cells, prop transparency, and alpha support. Repairs remain preview-first and non-destructive, following Mouse Frontier's sprite-doctor policy.

## Character sprite intake

Drop authored character PNGs in `assets/Characters/`. `tools/stage_character_sources.py` creates doctor-ready strips without changing those originals. The local `tools/character_sprite_doctor.py` audits every significant-alpha component, top-bound consistency, panel-boundary fragments, adjacent scale, palette, silhouette and identity continuity, exact duplicates, low effective motion, and idle/walk loop seams. Approved previews are copied to `output/sprite-doctor/approved/`.

Run `python tools/install_character_assets.py` to clean the approved strips and generate a non-destructive preview, JSON report, and required contact sheets under `output/sprite-doctor/install-review/`. A clean technical audit is not visual approval. Inspect every contact sheet, then run `python tools/install_character_assets.py --apply --reviewed-contact-sheets`; the installer backs up existing runtime files before atomically replacing them under `assets/generated/characters/<character>/`. The runtime loader in `src/character_assets.lua` slices those strips into nearest-filtered quads and the smoke test verifies every registered action and frame count. Only actions actually supplied are registered; missing combat or other poses are not invented.

The rabbit player has a dedicated repeatable source build because its approved walk, idle, and directional studies have different layouts. Run `python tools/build_player_character_assets.py`, review all contact sheets under `output/sprite-doctor/player-review/`, then rerun with `--apply`. The builder removes connected checkerboard backgrounds, normalizes every pose to a shared scale and foot baseline, emits Sprite Doctor metadata, and installs exact 512px strips. `tools/build_business_cat_character_assets.py` applies the same preview-first contract to the first NPC overhaul. To add another playable character, register paired directional idle/walk strips in `Config.characters`, add its motion profile, and supply precomputed anchors/metrics through the same audit step; the shared direction resolver and renderer require no character-specific drawing code.

## Loading-bay layers

The warehouse background remains the closed-door base. `loading-bay-door-strip.png` is a five-frame transparent overlay built from the approved ImageGen open-door edit. Frames progressively reveal the parking lot from the bottom of the shutter upward; pixels outside the steel-framed aperture stay transparent so the warehouse, controls, bollards, and floor remain unchanged.

`tools/build_loading_bay_layers.py` rebuilds the strip and `output/loading-bay-animation-preview.png` from the preserved open-bay source in `output/loading-bay-open-generated.png`. Runtime placement uses the native crop origin `(200, 170)`, a `260×260` frame, and the warehouse background's X/Y scale. The first frame is intentionally transparent because the closed shutter is already baked into the warehouse base.

`tools/normalize_walkmask_binary.py` converts the active mask using the same 90-percent-white threshold used by navigation. This preserves gameplay classification while enforcing the documented strict `{0,255}` contract.

## Delivery truck layers

The delivery vehicle is independent of the warehouse and loading-bay art. `delivery-truck-open.png` is a transparent `512×512` base with an empty cargo opening. `truck-cargo-door-strip.png` is a five-frame, `2560×512` overlay: frames 1–4 animate the fitted roll-up door upward, while frame 5 is intentionally transparent so the open base shows through unchanged.

`tools/build_truck_assets.py` rebuilds both runtime files and `output/truck-cargo-door-animation-preview.png` from the preserved open and closed sources. Every cargo-door frame keeps the same full-canvas anchor, so the base and overlay use one transform without visible jitter. At runtime, the composed truck is stencil-clipped to the loading-bay aperture; this makes it appear behind the wall while backing in instead of drawing over the warehouse facade.

Online machine orders use a separate flatbed vehicle contract. `machine-delivery-flatbed-loaded.png` carries one
covered, strapped industrial machine on a skid; `machine-delivery-flatbed-empty.png` preserves the truck and deck
after unloading. Both are transparent `512×512` frames with the same bottom anchor as the box truck. The renderer
selects loaded versus empty from the authoritative machine-delivery manifest and never draws the box-truck cargo
door over a flatbed. `tools/build_machine_flatbed_assets.py` removes the generated checkerboard matte, applies one
shared crop/scale to both preserved sources, and writes the aligned runtime pair.

## Cutter operator console

`polar-operator-console.png` is the transparent front-view machine base generated from the user's layout reference. Runtime text and measurements are drawn separately so work-order IDs, dimensions, rotation, and backgauge values remain exact and interactive. `cutter-control-buttons-strip.png` contains raised/pressed black dual-hand controls and raised/pressed red emergency-stop controls.

The clamp and blade are independent five-frame overlays in `cutter-clamp-strip.png` and `cutter-blade-strip.png`. The clamp travels down to the paper before a cut; the blade completes a down-and-up cycle. `tools/build_cutter_gui_assets.py` installs the approved source and deterministically rebuilds all aligned overlays. The paper itself is rendered from saved job data because its proportions, artwork colors, remaining margins, orientation, and trimmed dimensions change during play.

## Movable cutter floor sprites

`polar-cutter-directions-strip.png` is a transparent `4096×512` strip ordered northwest, north, northeast, east, southeast, south, southwest, west. The corner source supplies the original four views and the intermediate source supplies the four cardinal rotations. Operator-side controls rotate with the machine; rear rotations show the plain rear housing and service cabinets instead of incorrectly mirroring the touchscreen. `tools/build_cutter_direction_assets.py` removes the generated checkerboard/residue, normalizes every baseline, and installs each view in a fixed `512×512` frame.

Cutter position and eight-way direction are saved independently from the cutter simulation. Machine-relocation mode rotates in 45-degree steps, uses a large collision footprint, edge samples against the walkmask, slow movement, and blocks relocation while paper remains at the cutter. Feed and finished-pallet staging anchors follow the cutter's saved direction and current floor position.

## Loaded customer pallets

`loaded-paper-pallet-directions-strip.png` is a transparent four-frame `1024×256` strip ordered northwest, northeast, southwest, southeast. Every frame uses the same pallet and paper quantity, with the paper stack physically touching the deck boards. `loaded-paper-pallet.png` retains the northwest frame as a standalone compatibility asset. `tools/build_loaded_pallet_asset.py` extracts and normalizes the four approved generated directions.

The sprite is only the visual layer. Job ID, pallet ID, sheet quantity, paper ID, dimensions, cut status, warehouse position, and unload animation progress live on the saved pallet record. This lets the truck manifest, world tooltip, cutter, office inventory, and pallet jack share one authoritative object.

## Pallet jack

`pallet-jack-directions-strip.png` and `pallet-jack-loaded-directions-strip.png` are matching eight-frame `2048×256` strips ordered northwest, north, northeast, east, southeast, south, southwest, west. The jack follows all eight keyboard movement vectors instead of collapsing them into four angles. The loaded strip reuses the approved four pallet rotations unchanged, selecting the nearest pallet view for each intermediate jack frame. Pallets are composited or drawn after the jack layer so every carried load stays visibly above the forks. `tools/build_pallet_jack_assets.py` cleans the generated checkerboard/residue, normalizes every jack direction to a fixed `256×256` anchor, and rebuilds both strips from the two approved jack sources plus the existing pallet strip.

Pallet-jack position, direction, and carried pallet ID are saved. The runtime uses a smaller empty collision footprint, a larger loaded footprint, slower loaded movement, and validates the pallet's directional drop offset before placement.
# Sprite Grounding Rule

All movable characters, machines, pallets, vehicles, and props must have a true transparent background and must not include a painted oval or circular floor shadow. Do not add procedural ellipse shadows in runtime drawing code. The warehouse artwork supplies the scene lighting and grounding.

Collision uses the visible floor-contact footprint, not the full transparent image canvas. Define narrow `collisionHalfWidth` and `collisionHalfHeight` values for placeable sprites and verify them in-game whenever artwork changes.
