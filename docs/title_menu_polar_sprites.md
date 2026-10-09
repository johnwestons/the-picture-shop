# Polar 115 title-menu sprites

Generated with the built-in `image_gen` tool on 2026-10-08. The direct visual reference is `assets/generated/polar-115-sprite-sheet-clear-table-transparent.png`, the original cutter sprite from the old title screen. Generated PNGs were copied unchanged into the project; runtime quads and nine-slicing extract their frames and preserve genuine alpha.

Runtime assets:

- `assets/generated/title-menu-polar-shell-v1.png` — 1629×965; casing used for confirmations and shop setup.
- `assets/generated/title-menu-polar-fields-v1.png` — 1536×1024; normal, hover, selected and pressed display fields in four rows. Also supplies the setup value field and slider.
- `assets/generated/title-menu-polar-buttons-v1.png` — 1254×1254; normal, hover, pressed and disabled states, charcoal controls in the left column and red controls in the right column. Used for the title Options shortcut, confirmation actions and setup controls.

`src/screens/title_skin.lua` defines the casing source rectangles, preserved edge widths and expected PNG dimensions. Text remains dynamic in the screen renderers. All title sprites load only with the menu pack; switching to the cutter pack retains its existing console textures without retaining the menu sprites.

## Paper pallets, ink containers and toolboxes

The approved low timber pallet is used for each shop slot as two shorter pallets side by side. Version 2 supplies distinct left and right ends: perspective remains on the outside edges, while square inner ends meet across a 2-unit seam. The left paper carries the slot number and cash; the right paper carries the dynamic shop status. Both pallets select the same save slot and share normal, hover, selected and pressed states. The amber paper edge identifies the selected slot.

- `assets/generated/title-menu-paper-pallet-pairs-v2.png` — 1536×1024; complementary left/right pallets in two columns, with normal, hover, selected and pressed states in four rows. Supersedes `title-menu-paper-pallet-states-v1.png`, which remains as its source reference.
- `assets/generated/title-menu-shop-shelf-v1.png` — 2152×731; three-tier shelf with ivory bolted uprights, steel ledges, dark back panels and a blank header beam. Drawn around and behind the three slot rows. The ink and toolbox actions remain below the shelf.
- `assets/generated/title-menu-ink-container-states-v1.png` — 1536×1024; teal ink tins for New Shop and Continue, red tins for Delete Slot and Quit. Rows are normal, hover, pressed and disabled; columns are teal and red. Disabled tins turn gray.
- `assets/generated/title-menu-toolbox-states-v1.png` — 1536×1024; the game's blue enamel toolbox, with carry handle and brass latches. Used for Local Play and the conditional Direct Play entry. Rows are normal, hover, pressed and disabled.

These PNGs were generated with built-in ImageGen using the approved cutter and pallet artwork and the existing blue toolbox as direct references. They were copied unchanged. Exact ink/toolbox prompts and reference paths are in `assets/source/title-menu-props-v1/prompts.json`; the flush pallet edit and shelf prompts are in `assets/source/title-menu-shelf-v1/prompts.json`. All paper faces and nameplates are blank so labels and save data remain dynamic.

`src/screens/title_props.lua` extracts atlas quads, preserves the outer perspective and inner end blocks while stretching the fork pockets, and tracks each state's label position. Asset dimensions are validated during loading, and the textures are released when leaving the menu pack.

## Physical hover and click animations

The physical hover sheets are generated edits of the approved static sprites. Each has two focus frames, played in a 0.9-second loop. Pointer hover, keyboard focus and controller focus use the same animation. Leaving focus restores the resting or selected sprite; disabled actions retain their disabled artwork.

| Installed PNG under `assets/generated/` | Dimensions | Frames used at runtime |
|---|---:|---|
| `title-menu-pallet-focus-v2.png` | 1536×1024 | Left/right pallets in two columns; outer paper corners curl upward in two rows. Square inner ends and flat label areas remain intact. |
| `title-menu-ink-focus-v2.png` | 1536×1024 | Teal/red tins in two columns; lids open progressively, exposing ink and producing a small edge drip. Labels stay dry. |
| `title-menu-toolbox-focus-v2.png` | 1536×1024 | Two vertically stacked opening frames, showing a wrench, screwdriver and pliers inside the blue case. |
| `title-menu-pallet-animations-v1.png` | 1536×1024 | Click-down and rebound in rows 3–4, with left/right pallets in two columns. |
| `title-menu-ink-animations-v1.png` | 1536×1024 | Click-down and rebound in rows 3–4, with teal/red tins in two columns. |
| `title-menu-toolbox-animations-v1.png` | 1536×1024 | Click-down and rebound in rows 3–4. |

The initial animation sheets' first two glint rows are superseded by the physical hover sheets. All six PNGs are unchanged built-in ImageGen outputs with genuine alpha; source registration and runtime extraction are in `src/screens/title_props.lua`. Exact prompts and reference paths are saved in [physical hover prompts](../assets/source/title-menu-focus-v2/prompts.json) and [click animation prompts](../assets/source/title-menu-animations-v1/prompts.json).

`src/screens/title_motion.lua` drives every frame from title-screen elapsed time. Quick clicks/taps retain their click frame after release: 0.08 seconds down, then rebound until 0.18 seconds. Actions that leave the title or open a dialog run once after that animation; repeated activation is ignored during the short interval. Entering the title clears pending actions. Slot selection changes immediately and shares the same visual timing across its two pallets.

Tab/Shift+Tab and left/right cycle through slots and enabled actions. Up/down and W/S select slots as before. Enter/Space activates the focused action. Controller D-pad focus uses the same path and A activates it; moving the controller cursor switches back to pointer control. Toolbox spacing reserves room for its fully opened lid without covering the ink labels.

## Selected paper-title control

The user selected concept 2's operator-console cutter, with concept 1's single clamped paper stack. `assets/generated/title-control-polar-paper-v3.png` is the resulting 1882×836 transparent sprite. The paper contains the exact title `The Picture Shop` and catch phrase `Print , Cut , Keep the Doors Open`. Its LCD contains no baked text.

`src/screens/title_control.lua` draws the whole cutter at a uniform scale and fits runtime text inside the LCD. It wraps messages, reduces font size for longer text, and shortens excess lines without breaking UTF-8 codepoints. The title menu reserves more vertical space for the actual cutter silhouette and moves the save slots and action buttons below it.

The LCD cycles through the following exact messages, in order, for five seconds each, and then repeats:

1. `Hello Trevor, welcome back to work.`
2. `Happy Printing`
3. `Have a Great Day`
4. `Be a Nice Critter`
5. `Sponsored by The CritterNet`

Menu feedback (`TitleScreen.message`) takes priority for three seconds during normal browsing. Dialog notices remain until the dialog is resolved. A programmed override takes priority over both feedback and the cycle; the cycle pauses while either is visible. To display a programmed player message after entering the menu:

```lua
local TitleScreen = require("src.screens.title_screen")
TitleScreen.setDisplayMessage("GOOD MORNING!\nYour next shop starts here.")
```

Pass `nil` to `setDisplayMessage` to resume normal menu feedback and the cycle; entering the title menu clears the override and restarts at the first phrase. The footer continues to show input hints. The selected edit's exact built-in ImageGen prompt is saved in `assets/source/title-control-concepts-v2/selected-hybrid-prompt.json`.

## Typography

`src/screens/title_fonts.lua` loads and caches material-specific fonts. LCD text uses [VT323](https://github.com/google/fonts/tree/main/ofl/vt323) with nearest filtering for the early-computer digital lettering. Paper labels use the existing [Special Elite](https://github.com/google/fonts/tree/main/apache/specialelite) typewriter face. Ink tins use [Stardos Stencil Bold](https://github.com/google/fonts/tree/main/ofl/stardosstencil); toolbox nameplates and metal controls use [Barlow Condensed SemiBold](https://github.com/google/fonts/tree/main/ofl/barlowcondensed). Paper/ink/metal fonts use linear filtering to remain legible in smaller windows. Label size is fitted to each sprite's available nameplate space.

The new font files and their licenses are bundled at:

- `assets/fonts/VT323-Regular.ttf` and `VT323-LICENSE.txt` (SIL OFL).
- `assets/fonts/StardosStencil-Bold.ttf` and `StardosStencil-LICENSE.txt` (SIL OFL).
- `assets/fonts/BarlowCondensed-SemiBold.ttf` and `BarlowCondensed-LICENSE.txt` (SIL OFL).
- Existing `assets/fonts/SpecialElite-Regular.ttf` and `SpecialElite-LICENSE.txt` (Apache 2.0).

`tools/build_mobile_package.py` includes the fonts directory in shared Windows/Android runtime packages. The packaging regression verifies every font's archived bytes and all four license files.

## Validation

The current review uses the actual LÖVE renderer at 960×678, 1600×720 and 720×509. It checks empty/occupied slots, both physical hover frames, click-down/rebound, all rotating phrases, programmed/long messages, Options, delete/overwrite confirmations, shop setup and the conditional Direct entry. The isolated test identity is `the-picture-shop-test-title-menu-polar-v1`; only its disposable game saves are reset.

- 271 checks passed across asset residency, UI integration, LAN, Direct, options, title animation and save integration.
- 59 screenshots captured successfully; [open toolbox](../output/title-menu-polar-review/desktop-hover-local-open.png), [open ink](../output/title-menu-polar-review/desktop-hover-new-open.png), [curled paper](../output/title-menu-polar-review/desktop-hover-slot-open.png).
- LuaJIT compilation/limits passed for 523 Lua files, with 7195 compiled functions.
- 17 shared runtime packaging and reproducibility tests passed, including bundled fonts and licenses.

Review report: `output/title-menu-polar-review/checks.rpt`. The harness sources are `.stabilization/title-menu-review/main.lua` and `build_review.py`.
The six installed animation PNGs were hash-compared with their original built-in outputs; [asset verification](../assets/source/title-menu-focus-v2/asset-verification.json) records unchanged copies, dimensions and transparency.

## Casing prompt

```text
Use case: stylized-concept
Asset type: transparent raster nine-slice UI casing sprite for The Picture Shop game's title screen.
Input image 1 is the ORIGINAL POLAR 115 CUTTER SPRITE, a direct material and design reference. Design a NEW rectangular game-menu casing, not a picture of the cutter, using exactly its visual language: off-white enameled upper machine housing, cool stainless steel chamfered edges, charcoal black display gasket, narrow aged brass clamp rail, crisp black pixel outlines and small corner fasteners.
Create ONE isolated front-facing flat orthographic rectangle, width about 1000 pixels and height about 560 pixels, centered with 30px transparent margin on a 1080x640 canvas. Outer edges aligned perfectly horizontal/vertical. Thick sturdy square-cut corners with tiny beveled notches, no rounded web-card shape.
Border about 24px thick, narrow ivory upper housing over a very thin continuous brass accent, brushed steel side posts and lower table lip. Place screws only inside the four CORNERS; all middle spans must be straight, quiet and repeatable for nine-slice stretching. No centered decorations, no handles, no bottom legs. Very large empty uniformly dark charcoal interior about 90 percent of area; this is an opaque dark machine display surface for runtime text, with minimal texture and high readability. All artwork including the dark interior is opaque; only outside the silhouette is truly transparent.
Match the source's carefully shaded pixel-art machinery, mild wear and black edge outlines, restrained greys and cream, no rust or heavy distress, no blue sci-fi lighting.
No text, no letters, no logos, no labels, no machine itself, no shadows outside the silhouette, no background, no checkerboard. Production game sprite, not a mockup.
```

## Save-slot fields prompt

```text
Use case: stylized-concept
Asset type: transparent pixel-art game UI SAVE SLOT FIELD STATE SPRITE ATLAS, for The Picture Shop.
Input image 1: original Polar 115 cutter sprite, DIRECT design reference, especially charcoal screen bezel, stainless steel edge, off-white enamel and brass clamp rail. Input image 2: the new menu casing sprite, match this set's materials, outlines and finish.
Create FOUR identical-size wide, low rectangular EMPTY display field sprites stacked in FOUR evenly spaced rows, exactly aligned, no other items. Use a 1536x1024 canvas; each field silhouette approximately 1400x160, horizontal, left x about68, row tops about60, 300, 540, 780. Generous genuinely transparent gaps between rows and outside silhouettes.
Rows top to bottom are NORMAL, HOVER, SELECTED, PRESSED states, with NO labels or text. Same geometry and matching dark blank display center for dynamic runtime slot text. Normal: deep charcoal display with black rubber gasket, brushed steel rectangular bezel, tiny grey status lamp on left edge. Hover: polished highlights and narrow brighter brass bevel. Selected: amber/brass rim and glowing amber status lamp on left. Pressed: inset darker face, subtly compressed steel lower lip; amber status lamp retained.
Front-facing orthographic, no perspective, crisp pixel edges like source, squared beveled corners. Corner fasteners within corner blocks only, continuous side/top/bottom middle spans for nine-slice stretching; EMPTY CENTER occupies at least 88 percent of field area; no internal divisions.
Resemble the cutter's actual industrial control display, not a generic rounded card. Restrained neutral steel and charcoal with small warm brass details. State distinction clear without obscuring text. No blue neon, no hazard stripes, no decorative gadgets.
No words, letters, symbols, numbers, watermarks, instructions, mockup or scene background. Transparent outside each sprite, opaque center. NO checkerboard, no drop shadows beyond silhouettes.
```

## Pushbutton states prompt

```text
Use case: stylized-concept
Asset type: game UI BUTTON STATE SPRITE ATLAS with true transparent alpha, for The Picture Shop title menu.
Input image 1: original Polar 115 cutter sprite, DIRECT inspiration, particularly its black dual-hand pushbuttons mounted on square steel plates and its red emergency-stop with yellow collar. Input image 2: new menu casing, keep matching crisp shaded pixel-art steel, ivory enamel and brass materials.
Create exactly EIGHT empty rectangular label-ready pushbutton sprites, a precise TWO COLUMN by FOUR ROW grid on a 1024x1024 square canvas. Each sprite about420x160, columns centered at x256 and768, rows centered at y128,384,640,896. All sprites identical outer silhouette and alignment. Clear true transparent gaps.
LEFT COLUMN top-to-bottom: NORMAL, HOVER, PRESSED, DISABLED black/charcoal pushbutton states.
RIGHT COLUMN top-to-bottom: NORMAL, HOVER, PRESSED, DISABLED muted deep RED pushbutton states, narrow safety yellow/brass collar as in cutter emergency stop.
Each button: rectangular black raised face with wide EMPTY face for runtime label, chunky squared steel mounting bezel, subtly ivory corner plates, small corner fasteners only at corners; light upper edge and dark lower lip. Crisp black outlines, source-matched pixel art. Most of area is quiet flat face, no circles occupying text area. Aspect ratio about2.6:1. No rounded web pill.
Normal raised face; hover slightly brighter steel bevel and warm amber inner lip; pressed face lowered into housing, darker face and thinner lower shadow; disabled dim low contrast face and desaturated metal. Keep exact mounting footprint across states.
Corners need separate preserved blocks and quiet repeatable edge spans so each can be nine-slice scaled to action buttons and tiny +/- controls.
No text, no numbers, no icons, no logos, no labels, no state captions, no backgrounds, no shadows outside silhouette, no checkerboard, no gradients in empty transparent space. The atlas background MUST be genuinely transparent, not the original reference's dark backdrop. Only each button's silhouette is opaque.
```
