# POLAR 115 paper cutter — research and game interaction brief

## Scope and identification

The supplied reference image (`references/machineRef/cp-listing-polar-115-xt-paper-cutter-detail-1.jpg`) appears to be a **POLAR 115 XT** (legacy programmable cutter), not the current N 115. The visual language is still appropriate for the game: broad stainless front table, central knife/clamp throat, two side cut-button housings, a front control display, a clamp foot pedal, and a rear-table safety guard. Do not mix the current N-series touchscreen layout into the XT sprite as exact historical detail; use it as a functional reference.

The 115 designation is the nominal cutting/feeding format: 1,150 mm (45.28 in). The newer N 115 is specified for up to 165 mm loading height and 25 mm minimum automatic cut without a false plate. These are useful gameplay balancing anchors, not requirements for a literal simulation.

## Real machine elements worth animating

* **Backgauge / rear stop:** motor-driven fence moves toward/away from the operator to set the cut dimension. In the GUI, show a paper stack sliding against the backgauge and a numeric target/actual value.
* **Clamp (press beam):** descends before the knife and rises after the cycle. The clamp pressure is adjustable; current N 115 documentation lists 30 daN safety pressure, 150–4,500 daN working range. For gameplay, low pressure can cause shifting and high pressure can damage delicate stock.
* **Knife/blade bar:** a heavy guillotine blade makes one downward swing/cut and returns to the upper position. The current N 115 is rated at 45 cycles/min; animate a deliberate, readable 0.6–1.0 second down/up cycle rather than real-time speed.
* **Two side cut buttons:** the legacy operating manual describes a two-handed cutting release with simultaneity control and anti-repeat circuit. Require both buttons to be pressed within a short window (for example 0.3 s) and released before the next cut. This is the most important interaction cue.
* **Light barrier / safety curtain:** the legacy 115 safety element is a 20-channel light barrier; interruption inhibits or interrupts the cycle. Add a red beam/status state and a “clear throat” condition. This is a safety abstraction, not a challenge to bypass.
* **Clamp foot pedal:** the manual lists a pedal for lowering the clamp, with maximum 300 N for types including 115. Represent it as a separate “pre-clamp/jog” input; it should never directly trigger the knife.
* **Emergency stop/main switch:** include a large red stop control in the flat machine GUI. E-stop cancels the job, stops motion, and requires reset; it should not be a consumable failure mechanic.
* **Cut-line LEDs:** later D/N literature describes LEDs marking the cutting line. A thin illuminated line over the paper is a strong visual confirmation, even if the pictured XT predates that exact feature.
* **Air table jets (variant-dependent):** current D/N literature describes air jets on stainless tables to make stacks easier to handle. Treat as an optional upgrade/toggle, not a mandatory XT feature.

## Safe, simplified operating sequence

This is a game representation of the documented order; it is not operator training. Real knife changes, maintenance, installation, and fault repair require trained/authorized personnel.

1. Power on and clear the work area; machine reports safety system ready.
2. Load a paper stack onto the table. Jog/align it against the side guide and rear backgauge.
3. Enter a job or cut list on the control panel (metric/inch choice, target dimensions, number of cuts). Move the backgauge to the first target.
4. Optionally lower the clamp with the pedal to hold/jog the stack; verify alignment and material type.
5. Start the cycle only when the light barrier is clear and the clamp/knife are in the correct home state.
6. Press both cut buttons together. The clamp descends, the knife cuts, then both return. The two-button release must be released before another cycle.
7. Remove or jog the finished pieces, advance to the next programmed cut, and repeat. A cut list can award quality/time bonuses for accuracy and clean cycles.
8. If the barrier is interrupted, an E-stop is pressed, or a fault occurs, freeze the cycle, show the cause, and require a safe reset before continuing.

## Flat 2D machine GUI proposal

Use a modal “Operate Polar 115” screen opened by interacting with the isometric machine. Keep the paper/cutter body as one flat sprite and layer separate cutout sprites for the moving parts.

**Layout:** top strip = job name, stock size, remaining sheets, money/time; center = paper stack, backgauge, clamp, knife, and cut-line; left = cut list and target/actual dimensions; right = control panel; bottom = two cut buttons, pedal indicator, safety-barrier indicator, and E-stop/reset.

**States:** `idle → loaded → positioned → clamped → armed → cutting → finished`; interrupting the barrier or E-stop sends any active state to `blocked`, then `resetting`, then `idle`. Never allow a cut from `blocked` or while either button is held from the previous cycle.

**Controls and feedback:**

* Numeric target / “move backgauge” button: animate fence movement and a progress value.
* Clamp pedal: short press clamps; release raises it unless the selected job requires hold.
* Left + right cut buttons: simultaneous press starts the cut; flash both buttons and play a mechanical click.
* Barrier: green when clear, red when blocked; blocked state prevents cutting and shows a plain-language reason.
* E-stop: immediate stop with a reset prompt.
* Program list: save/replay a short sequence of dimensions, making the machine valuable for repeat print jobs.

## Gameplay hooks

The cutter should make money through accuracy and throughput rather than dangerous timing. A correct stack height, appropriate clamp pressure, and complete cut list improve yield. Wrong dimensions, misalignment, excessive pressure, or dull-knife condition can create waste and rework. Upgrades can unlock air-table handling, faster backgauge, better process visualization, automatic trim/waste removal, or more program memory. Safety failures should be recoverable interruptions and training feedback, not graphic injury.

## Sources

* [POLAR / Heidelberg, High-Speed Cutter POLAR N 115 product sheet (2024)](https://www.heidelberg.com/global/media/en/global_media/products___postpress_cutting/pdf_11/07_polar_high_speed_cutter_115_producsheet.pdf) — current N 115 variants, 1,150 mm cutting/feeding format, 165 mm loading height, clamp pressures, backgauge speed, knife cycles, minimum cuts, touchscreen/process features.
* [POLAR-Mohr, D 115 PLUS product sheet (2019)](https://www.papercutters.com/assets/uploads/cp-POLAR-D-115-PLUS-Productsheet.pdf) — hydraulic swing cut, adjustable clamp pressure, air-jet table, cutting-line LEDs, touchscreen/process visualization, program memory, and 1,150 mm dimensions.
* [POLAR 115/176 operating-manual mirror (Scribd)](https://www.scribd.com/document/878245467/Polar-115ed-Operators-Manual-78-Ed-176ed-e) — legacy 115 safety layout and operating behavior: 20-channel light barrier, two-handed simultaneity/anti-repeat cut release, clamp pedal, safety latch, rear guard, and documented safety precautions. The mirror is not the manufacturer site; use it for historical XT/EMC control details and defer to the machine’s actual manual for real operation.
* [POLAR high-speed cutter options/generations sheet](https://www.noysystems.co.il/wp-content/uploads/2018/01/POLAR_high-speed-cutter-115_Producsheet.pdf) — legacy/current feature comparison including 20-channel barriers, touchscreen generations, process visualization, program memory, and backgauge/knife cycle capabilities.

## Art implementation notes

Create separate pixel layers for `body`, `table_left/right`, `control_panel`, `paper_stack`, `backgauge`, `clamp`, `knife_bar`, `cut_line`, `left_button`, `right_button`, `pedal`, `barrier_status`, and `e_stop`. Keep the knife and clamp as independent animation strips so the same machine sprite supports idle, alignment, clamping, cutting, blocked, and reset states. The provided XT photo is a visual reference only; simplify small labels and display text into readable iconography at game resolution.
