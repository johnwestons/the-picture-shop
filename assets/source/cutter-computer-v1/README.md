# Cutter computer artwork v1

Generated with the built-in ImageGen tool on 2026-11-11. The source PNGs are preserved unchanged; runtime files retain their original alpha. No post-generation raster editing was used.

## Files

- Runtime housing: `assets/generated/cutter-computer-v1/computer.png`
- Runtime key atlas: `assets/generated/cutter-computer-v1/keys.png`
- Preserved sources: `computer-source.png` and `keys-source.png` beside this file.
- Sprite registration and font roles: `src/screens/cutter_computer_art.lua`.
- Interactive console: `src/screens/machine/operator.lua`.

## References and visual decisions

The computer mounted on `assets/generated/polar-operator-console.png` is the style reference. The original cutter and its animation assets remain unchanged. The housing blends the approved large-screen and physical-keybay concepts: roughly two-thirds readout, one-third keys, with no lower key shelf.

The keypad atlas contains three widths in two rows: number, function, Enter; raised on top and pressed underneath. Rendering selects separate registered bitmap frames. A press holds the recessed frame until release, then returns to raised after a short 140 ms minimum visual pulse. Labels are live Barlow Condensed SemiBold text; they follow the pressed key face. The display combines VT323 for the large numeric readout, Courier Prime Bold for program rows and status data, and Barlow Condensed SemiBold for headings. These are existing project fonts.

Housing source: `exec-e38c7698-7686-4adf-ae71-675478f82f10.png`.
Key source: `exec-7024f7f3-7b85-4b27-b98c-d0db1fd6d1a8.png`.

## Final housing prompt

Use case: precise-object-edit. Blend the two provided versions of this game cutter computer. Keep the polished dark charcoal industrial housing and beveled dark metal style. From image 1 retain the impressive large tall blue readout; from image 2 retain a blank dark-gray metal physical keypad mounting bay to the right. REMOVE the entire separate bottom button shelf from image 2 and extend the LCD vertically down into that space. The blue screen should occupy nearly TWO THIRDS of the usable interior width, and the right physical-key mounting bay the remaining ONE THIRD. The screen and the keypad mounting bay have the same top and bottom alignment and both span nearly the entire inner height. Maximize the blue screen while leaving room for a physical numeric keypad and function keys on the right. No keys or text baked into this housing asset: our game code overlays actual raised physical key sprites on the right bay and live text only on the blue display. Screen border near x=9% through 65% of overall canvas and y=14% through 86%; right metal bay near x=67% through 92%. Exterior housing approximately 1.85:1 landscape, front facing, tiny transparent outside margin. Crisp faithful game illustration matching these references, no photographic noise, no logos, no bottom shelf, no extra panels, no cutter body.

## Final key atlas prompt

Use case: stylized-concept. Asset type: transparent game UI sprite atlas of physical industrial keycaps. Use the attached cutter computer ONLY as a MATERIAL, PALETTE, LIGHTING and front-facing STYLE REFERENCE. Do not reproduce the computer or screen. Create SIX isolated blank physical keyboard key sprites, perfectly registered in a clean THREE COLUMN by TWO ROW grid on a truly transparent background. Left column: compact number key with 1.55:1 width-to-height; middle column: wider function key with 1.85:1 width-to-height; right column: long ENTER key with 3.3:1 width-to-height. Top row is raised/unpressed; bottom row is the EXACT SAME respective three keys pressed down, same outlines and size, cap depressed into its black recessed socket, visibly lower and darker. Each key has a machined dark metal mounting rim and a sculpted charcoal gray hard plastic keycap, a subtly dished flat blank face, rounded bevels, bright but fine silver top-edge highlights, shaded thick sidewall, and a black inset socket. Tangible solid analog keys, convincingly part of this reference machine. Straight-on orthographic view, centered in equal cells, no perspective skew. SIX distinct separate keys ONLY, no board, no cables, no labels, no numbers, no letters, no symbols, no lines dividing cells, no background. Keep all key faces large and clean for runtime text legends. All six keys same HEIGHT, long ENTER varies WIDTH only. Ample clear alpha gutter between cells. Crisp polished hand-painted game sprite illustration matching the attached housing, slight realistic wear at edges only, no photographic noise. Output a landscape 3-column x 2-row atlas.
