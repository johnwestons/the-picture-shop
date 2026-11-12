# Cutter operator UI

Implemented locally on 2026-11-11. No release version, APK or GitHub push was produced.

## Interaction plan and result

1. NEARBY PALLETS shows pallet cards with job identity, artwork, sheet count, lift count and starting/finished dimensions. Loading uses the existing production rules and transitions into the machine view.
2. CUTTER enlarges the existing scene without changing its paper, backgauge, blade or clamp rendering. The original computer, emergency stop, two down buttons and foot pedal receive hit targets. Either down button independently starts the existing guarded cut. Stock/table taps push or pull the stack. The shaded curved arrow rotates by tap side or swipe direction; Q retains its programmed direction.
3. Tapping the computer opens the approved large readout and physical keybay. Sprite keys provide numeric entry, clear/delete, Enter, program previous/next, auto, save, recall, units and fine gauge adjustments. The number field still accepts an optional native keyboard. Unit changes convert the draft without moving the gauge; Enter commits it.
4. Raised and pressed key sprites provide tactile feedback while holding and releasing. The screen uses the existing VT323, Courier Prime Bold and Barlow Condensed fonts. The display shows actual gauge, selected program, target cuts, angles, memory and stock dimensions.
5. Local and shared multiplayer consoles use the same layout. Commands remain host-authoritative, with bounded clockwise/counterclockwise intents alongside the existing programmed rotation command. Safety checks and NPC two-control behavior remain intact.

## Validation

- Desktop cutter-operator smoke passed.
- Forced mobile cutter-operator smoke passed, including image comparison of raised, held and released key states.
- Full cut-stock-margin suite passed: complete production cuts/lifts, spoiled stock, save contracts, motion/presentation and guest job journey.
- Network protocol and real-session tests passed for both rotation directions and guarded cutting.
- The cutter-operator smoke target includes the employee and employee-billing suites. They exercise workers running complete real cutter jobs; worker cuts still require both safety controls, including while the player's local UI offers either button independently.
- Screenshots reviewed at the 960 x 678 logical game resolution. Housing, screen text, sprites and hit targets fit without covering the cutter with surrounding controls.
- Each smoke run used fresh isolated test-save storage under output/. This was not a physical Android device test.
- New artwork and fonts are inside assets/generated/ and assets/fonts/, which the existing shared package builder includes. No APK was built.

## References

The layout follows the user's approved machine sprite and computer concepts. Graphic cut programs and measurement unit changeover were informed by the [official POLAR N 115 brochure](https://www.heidelberg.com/global/media/en/global_media/products___postpress_cutting/pdf_11/07_polar_high_speed_cutter_115_producsheet.pdf). The game's physical-key interface is a custom design, not an exact hardware emulator.

Artwork sources, complete ImageGen prompts and registration details are in assets/source/cutter-computer-v1/README.md.
