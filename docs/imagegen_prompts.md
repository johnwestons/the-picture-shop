# Built-in ImageGen prompt record

The project-bound raster drafts were created with the built-in ImageGen tool, not the CLI/API fallback.

## Warehouse

Create an original cutaway isometric warehouse interior for a LÖVE print-shop management game: a large mostly empty concrete production floor, decorated industrial walls, beams, hanging lights, electrical panels, safety markings, roll-up loading door, and a compact office with desk and computer. Use crisp hand-authored 32-bit-era pixel art, hard edges, a warm industrial palette, a fixed orthographic isometric camera, and no characters, machines, boxes, UI, text, logos, or watermark. Move the office to the lower-left foreground while preserving the warehouse composition. The user selected the resulting `warehouse-selected.png` version.

## Warehouse layout v2

Use case: stylized-concept. Asset type: game environment concept art / playable warehouse background. Create an original wide 2D isometric pixel-art print-shop warehouse: the factory floor dominates the lower foreground, a loading dock sits at upper left, a separate office room with a wide open doorway sits in the upper middle, and a separate lobby/reception room with a wide open doorway sits at upper right. Keep the factory floor mostly empty for machines and walking. Use industrial brick/concrete walls, steel beams, warm lamps, utility conduit, an office desk/computer, and a reception counter/seating. Use detailed hand-authored 32-bit-era pixel art, hard edges, no characters, no machines on the open floor, no labels, no UI, no logos, and no watermark. A second background-extraction pass removed only the outside black area and preserved genuine transparent alpha.

## Warehouse layout v3 entrance edit

Use case: precise-object-edit. Input image 1 was the clean v2 warehouse sprite and input image 2 was the user's marked guide. Remove only the wall segment covered by the red guide, place a customer-facing double glass door in the purple-marked position, preserve the loading dock, office, lobby, factory floor, furniture, lighting, and pixel-art style, and remove all guide colors from the final. Keep the outside genuinely transparent and preserve the 1536x1024 canvas.

## Warehouse layout v4 entrance orientation edit

Use case: precise-object-edit. Preserve the v3 warehouse and change only the entrance orientation. Use the user's lower-left-to-upper-right arrow as the approach direction: redraw the double glass doorway as a diagonal isometric storefront entry with its customer-facing side and handles toward the lower-left factory floor, its hinge/frame side toward the upper-right lobby wall, and a threshold that projects slightly into the factory floor. Preserve all other architecture, objects, lighting, transparency, and the 1536x1024 canvas; remove the guide arrow and dots.

## Approved warehouse reference preparation

The user supplied the approved transparent warehouse reference. The visible alpha bounds were cropped and placed without distortion on a 1536x1024 runtime canvas, preserving the full 1536px artwork width and centering the 990px-tall visible layout vertically. No architectural pixels were regenerated or altered.

## Polar 115 sheet

Using the supplied Polar 115 XT photographs as functional references, create a modular transparent pixel-art sprite sheet containing a three-quarter isometric machine, a flat front operator view, and isolated cutouts for the clamp/blade assembly, backgauge/table component, paper stack, pedal, touchscreen, two cut buttons, and emergency stop. Preserve recognizable proportions, guarded machinery, stainless work surfaces, and a restrained gray industrial palette. Remove all paper from both large machine tables while retaining paper only as an isolated optional sprite. Finally, remove the baked checker background and replace it with genuine transparent alpha without changing sprite positions, clear tables, components, hard edges, or dimensions.

## Rabbit worker atlas

Create one consistent upright warehouse-worker rabbit in blue coveralls, warm-gray shirt, work boots, and utility belt as a genuinely transparent 6-column × 4-row pixel-art atlas. Row 1: two idle, two sit, two crouch/rest frames. Row 2: coherent six-frame walk loop. Row 3: three machine-use and three computer-use frames. Row 4: three carry-paper and three pick-up-paper frames. Keep the same identity, proportions, palette, baseline, isometric down-right facing, hard pixel edges, complete ears/hands/feet, and no grid lines, text, logos, extra characters, or watermark.

## Warehouse props

- Empty pallet: Create a single centered empty wooden shipping pallet as a genuinely transparent isometric pixel-art prop. Use warm honey-brown boards, visible gaps and support blocks, crisp hard pixel edges, no paper, no boxes, no text, no logo, and no watermark.
- Paper stack: Create a single centered neat stack of cut white paper sheets as a genuinely transparent isometric pixel-art prop. Show layered sheet edges and a cool blue-gray shadow, with hard pixel edges and no wrapper, text, logo, or watermark.
- Toolboxes: Create two separate genuinely transparent isometric pixel-art props: a compact closed steel hand toolbox with handle and latches, and a larger rolling workshop toolbox cabinet with drawers, casters, and side handle. Keep a restrained blue-gray industrial palette, hard pixel edges, and no text, logo, or watermark.
- Paper storage boxes: Create a horizontal transparent strip of three isometric kraft-cardboard storage boxes: closed taped box, open empty box, and open box containing a white paper stack. Keep each variant isolated with generous spacing, blank label panels, hard pixel edges, and no readable text or watermark.

## Open loading bay

Use case: precise-object-edit. Asset type: isometric pixel-art game environment layer. Edit only the upper-left loading-bay roll-up door so it is fully open. Through the exact doorway opening, show a quiet asphalt parking lot continuing the warehouse's isometric perspective, with muted gray pavement, subtle loading markings, and neutral daylight. Roll the metal shutter into a compact housing under the existing lintel. Preserve the full warehouse composition, dimensions, camera, brick wall, steel frame, lamps, controls, personnel door, bollards, hazard stripe, concrete floor, office, reception, and all other objects. Keep the doorway empty for a future separate truck sprite. No people, vehicles, pallets, text, logos, watermark, photorealism, perspective changes, or altered architecture.

The built-in ImageGen edit was preserved as `output/loading-bay-open-generated.png`. The deterministic layer builder isolates only its approved doorway pixels into the runtime strip.

## Delivery truck and cargo door

Open truck, built-in ImageGen stylized-concept prompt: Create one transparent isometric pixel-art medium-duty commercial box truck in rear three-quarter view, aligned upper-left to lower-right with the rear facing lower-right. Show its cargo roll-up door fully open and an empty dark cargo interior. Use an off-white cab and box, dark chassis, bumper, taillights, mirrors, and wheels. Include no people, pallets, cargo, roads, buildings, text, logos, or watermark. A background-extraction pass removed the generated gray-white checker while preserving the exact open truck.

Closed-door edit, built-in ImageGen precise-object-edit prompt: Close only the rear roll-up cargo door with fitted silver-gray horizontal slats and a handle. Preserve every other part of the truck, its geometry, canvas, scale, and placement; do not add a background, cargo, people, text, or other changes.

The approved open and closed sources are preserved as `output/truck-open-source.png` and `output/truck-closed-source.png`. The deterministic builder installs the transparent open base and isolates/interpolates only the rear-door region into the aligned animation strip.

## Cutter operator console

Built-in ImageGen style-transfer prompt: Use the supplied cutter-layout image only as a structural reference. Create an original, brand-neutral industrial guillotine paper cutter as crisp detailed 32-bit-era pixel art, viewed straight from the operator side. Include the stainless cutting bed, centered paper opening, side guards, upper housing, touchscreen bezel with blank interface fields, two black dual-hand cut buttons, red emergency stop, and foot clamp pedal. Keep the bed empty and make the blade edge and clamp bar visually distinct for later animated overlays. Center one complete machine with genuine transparent margin; no room, paper, pallets, readable generated text, logos, brand names, or watermark.

Built-in ImageGen background-extraction prompt: Remove only the black/gray backdrop and external glow or shadow. Replace it with genuine transparent alpha while preserving the exact machine, touchscreen, controls, table, pedal, dimensions, placement, hard edges, and internal dark openings. Do not crop, resize, repaint, add text, or alter machine parts.

The selected transparent source is preserved as `output/polar-cutter-console-source.png` and installed by the deterministic cutter asset builder.

## Four-direction movable cutter

Built-in ImageGen style-transfer prompt: Using the existing Polar-style cutter sheet as the exact subject and style reference, create exactly four isolated full-machine isometric views in a 2×2 grid ordered northwest, northeast, southwest, southeast. Preserve the same white/dark-gray guillotine cutter, stainless bed, touchscreen, emergency stop, clamp opening, cabinets, scale, baseline, lighting, and crisp 32-bit-era pixel art. Rotate the whole machine and its controls correctly. Use genuine transparent alpha; no paper, operator, pallet jack, floor, external shadow, labels, text, logos, watermark, checkerboard, grid, crop, extra parts, or front-on orthographic view.

Built-in ImageGen precise-object-edit prompt: Preserve the northwest and northeast operator-side machines exactly. Change only the southwest and southeast cells into true opposite rear rotations showing the plain white rear housing, dark rear service cabinets, access seams, vents, and back table edges. Hide the touchscreen, operator controls, clamp rail, blade opening, front pedal, and operator-facing bed on the far side. Preserve scale, baseline, camera, palette, hard edges, and transparent alpha; no other changes or extra objects.

Built-in ImageGen background-extraction prompt: Remove only the checkerboard/background and replace it with genuine transparent alpha. Preserve the two operator-side machines and two true rear machines exactly, including their complete silhouettes, positions, directions, dimensions, controls, rear panels, colors, and crisp edges. Do not crop, resize, move, rotate, redraw, repaint, mirror, merge, label, or add anything.

The final source is preserved as `output/polar-cutter-four-directions-final-source.png`; `tools/build_cutter_direction_assets.py` installs the runtime strip and writes `output/polar-cutter-directions-preview.png`.

## Four-direction pallet jack

Built-in ImageGen stylized-concept prompt: Create one consistent manual hydraulic pallet jack in industrial safety yellow with dark steel forks, black load wheels, and an upright articulated handle. Arrange exactly four isolated isometric pixel-art views in a 2×2 grid: northwest, northeast, southwest, southeast. Keep identical scale, baseline, proportions, and lighting, with forks clearly pointing in each direction. Use genuine transparent alpha and no pallet, paper, operator, floor, labels, text, logos, watermark, checkerboard, or extra components.

Built-in ImageGen background-extraction prompt: Remove only the black backdrop, yellow glow, and haze; preserve the exact four jacks, positions, directions, hard edges, handles, forks, wheels, paint, and dimensions with genuine transparent alpha.

## Four-direction loaded paper pallets

Built-in ImageGen style-transfer prompt: Using the pallet-jack direction sheet as the scale, direction, and pixel-style reference, create exactly four isolated wooden shipping pallets carrying equal tall stacks of white paper in a 2×2 northwest, northeast, southwest, southeast grid. Match the jack forks' practical scale. The complete bottom face of every paper stack must rest directly on the deck boards with zero air gap. Keep identical paper quantity, pallet proportions, baseline, and lighting; genuine transparent alpha; no jack, operator, floor, glow, labels, text, logos, watermark, checkerboard, or extra objects.

Built-in ImageGen background-extraction prompt: Remove only the checkerboard and replace it with genuine alpha. Preserve all four loaded pallets, their touching paper stacks, directions, dimensions, scale, baseline, colors, and hard edges without moving or repainting anything.

The approved sources are preserved as `output/pallet-jack-directions-source.png` and `output/loaded-pallet-directions-source.png`.
