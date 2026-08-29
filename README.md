# The Picture Shop

A playable LÖVE 2D vertical slice for an isometric pixel-art print-shop management game.

## Run on Windows

1. Install [LÖVE 11.x](https://love2d.org/) with the 64-bit Windows installer.
2. Double-click `RUN_GAME.bat` in this folder.

The launcher finds LÖVE on `PATH`, in a local `runtime` folder, or in the normal Program Files locations. LÖVE must receive the whole project folder; do not open `main.lua` by itself.

## Run on Android

The Android edition is built from this same Lua source tree; there is no copied mobile gameplay fork.
With one USB-debugging-enabled phone connected, run `./BUILD_ANDROID.ps1 -Install` in PowerShell.
The command packages the current game, runs the smoke suite, builds and verifies a signed development
APK, installs it without deleting existing saves, launches it, and verifies the Picture Shop startup marker.
Use `./BUILD_ANDROID.ps1 -PackageOnly` when only the testable `.love` archive is needed. See
`ANDROID_PORT.md` for the phone, controller, build, and release checklist.

## Local multiplayer

Choose a writable save, then use **LOCAL PLAY > HOST THIS SHOP** on Windows or Android. Up to three
Windows/Android workers can join the host's displayed IPv4 address over normal Wi-Fi or a compatible
phone hotspot. The host alone owns and saves the shop; guests receive the live shop and can move,
operate the dock door, talk to clients, use the office computer and skid wrapper, inspect pallet work
orders read-only, run the Polar cutter's production and safety controls, and share the host-authoritative
pallet jack. Protocol v8 keeps a full four-device
session within the 1,200-byte realtime packet ceiling: a reliable welcome contains the host and the
newly assigned worker, then fixed 12 Hz motion arrives as MTU-safe one-player shards that each client
merges by player ID. The same authoritative tick carries the live and terminal poses of a host-relocated
cutter, skid wrapper, or Windmill, so every worker sees the machine remain mounted while it moves.
Guests can observe relocation but cannot initiate or place a machine. The durable save retains the last
committed floor pose until the host completes a valid placement. The cutter uses its own 12 Hz bounded
runtime stream, an exclusive host lease, host-validated setup/cut commands, either-button multiplayer cutting,
an urgent E-STOP/barrier lane,
and safe disconnect/revision recovery. See `docs/lan_multiplayer_slice.md` for the supported protocol-v8
scope and `docs/lan_multiplayer_device_test.md` for the physical-device matrix.

The protocol-v7 / Android `.11` targeted four-device pass completed on August 28, 2026: an SM-S938U
Android host, two Android workers, and a Windows worker reached `4/4 WORKERS`, passed independent
movement and live cutter/wrapper/Windmill observation, and returned cleanly to `4/4` after the SM-J410G
left and rejoined. The broader 15-minute, hotspot, and offline-reload checks remain unclaimed.

The protocol-v8 / Android `.13` targeted cutter pass completed on August 29, 2026: an SM-S938U Android
host, an SM-J410G worker, and a Windows worker reached `3/4 WORKERS` and passed the full remote cutter
workflow, host and guest one-button cuts, two-worker contention, urgent E-STOP, disconnect/reacquire,
and clean rejoin. It also fixed and physically verified the carried-pallet/background-overlay crash found
in `.12`. A fourth device, the 15-minute soak, hotspot coverage, and the final offline reload remain open.

## Release gate

From a clean, pushed `main` branch, run `./RELEASE.ps1`. This single command
checks Git/upstream integrity, versions, the engine regression suite, raster
assets, licensed audio sources, mobile-package provenance and contents, and the
final SHA-256 checksum. It writes `output/release/release-report.json` and fails
without producing a passing report if any gate is not satisfied. Use
`./RELEASE.ps1 -BuildApk` to additionally build and verify the signed development
APK; physical-device installation remains a separate release-checklist step.

## Phone and controller input

- Touch: drag the lower-left control to move and use the contextual lower-right work button. Extra
  **Park**, **Move**, and **Turn** buttons appear when the pallet jack or a relocating machine needs them.
- The shop floor fills ultrawide phone displays. Two-finger pinch-zoom and pan works on the title,
  shop floor, computer, machine consoles, manifests, quotes, vendor, and press screens. Each screen
  remembers its own view; one-finger taps and the movement/action controls keep their normal behavior.
- Touch every menu, computer, manifest, quote, and machine panel directly. Numeric/text fields open the
  Android keyboard. Android Back closes the current panel through the same safe exit route as Escape.
- Controller: left stick or D-pad moves; **A** uses the current shop interaction; **X** parks the pallet
  jack; **Y** begins machine relocation; right shoulder turns a relocating machine; **Start** saves and
  returns to the shop menu.
- Keyboard movement accelerates and brakes smoothly, slides along blocked edges, and keeps diagonal speed
  consistent. Press **E** or click the gold-marked nearby target to interact; controller prompts show **A**.
- On panels and menus, either stick moves the gold controller cursor, **A** clicks, **B/Back** closes,
  and the D-pad retains menu/help navigation. At the Polar cutter, left and right shoulder are the two
  independent guarded cut controls; **X** clamps and **Y** rotates the sheet.
- The launcher icon is generated only from the supplied front-facing Polar paper-cutter image at
  `mobile/android/polar-cutter-launcher.png`, without a character, border, or added badge.

## Title and saves

The title screen has three local save slots. Use **W/S** or the arrow keys to select a slot, **N** for a new shop, **C** or **Enter** to continue, **D** to delete, and **Q** or **Escape** to quit. Confirmation prompts accept **Y** or **Enter** and cancel with **N** or **Escape**. Starting a new shop in an occupied slot always shows an overwrite warning; cancelling it leaves the existing save unchanged. Saves are versioned and retain money, stock, finished prints, completed cuts, and player position.

Save format 13 retains active, completed, and declined jobs, accounts receivable, grouped procurement shipments,
stock, film, machine placements, pallet-jack ownership, wrapper placement, and the next stable
job number, the cutter's player-saved measurement history, the business calendar, and unpaid bill
ledger, pending, received, and answered client emails, sent promotions and player quotes, plus uniquely tracked machine condition,
component wear, cycles, maintenance history, pending machine deliveries, client artwork and stock specifications,
and physical press-pass progress. Version-1 through version-12 slots migrate
when loaded. Saves are validated in a temporary
file before promotion and retain the previous valid slot as a backup. A damaged primary recovers
automatically; a slot with no valid recovery copy is marked as damaged instead of appearing empty.

## Job rules foundation

- A cutting job accepts 1–5 customer pallets with 500–3,000 sheets on each pallet.
- The largest incoming parent sheet is 25×25 inches, and the finished size must fit the parent sheet.
- The Polar lift capacity is 500 sheets. A partial final lift is allowed and billed as a full lift.
- Each lift is quoted at $150. Five 3,000-sheet pallets therefore quote at $4,500.
- Optional Original Heidelberg 10x15 printing work adds a separate cost budget for processed plates,
  ink, chemistry, tympan, makeready, wash-up, labor and machine overhead. The machine's 5,500-impression/hour
  maximum is retained as a specification while quotes use a conservative 3,000 sellable impressions/hour.
  Cutting-only prices remain unchanged; see `docs/heidelberg_windmill_10x15_report.md` for the sourced model.
- Job offers retain a recommended production estimate, the player's submitted quote, and separate mutable progress for every pallet.
- Every pallet now owns a stable paper-batch ID, job artwork ID, live width/height, orientation,
  four margins, four-cut program, and complete cut history. Easy jobs use matching opposing margins;
  medium and hard work uses asymmetric margins that require different backgauge positions.
- Every print order names the client's supplied artwork file, exact stock grade/weight/finish/color/grain,
  ordered copies, supplied sheets, and the allowance available for proofs and spoilage. The first offer after
  a Windmill is installed is guaranteed to be a print order; later offers mix cutting and print work.
- Each generated job carries a structured artwork record and compatible `artworkKey`; every paper batch keeps
  that identity. Every 128x128 texture in `assets/generated/artwork/` is registered and rotates through new
  print offers, proofs, plates, press sheets, pallet previews, and finished-job records.
- Accepting a ticket adds it to active jobs as `awaiting_delivery` and records accounts receivable;
  cash and physical pallet inventory do not increase until their later workflow events.
- Declining archives the numbered ticket, cancels its quoted pallets, and sends the customer out.

## Controls

- Move: **WASD** or arrow keys
- Interact with the office computer or Polar 115: **E**
- At reception, press **E** to open the customer's cutting or print-order paperwork.
- Type your price into the quote field and click **Send Quote**, or click **Decline**. Clients weigh price,
  urgency, and prior completed work when responding. **Back** and **Escape**
  both close the paperwork without deciding, so the customer remains available at reception.
- At the office computer, press **E** and use the mouse to view Active Jobs, Completed Jobs,
  Deliveries, Calendar, Inventory, the Online machine website, Email, Bills, cash, and accounts receivable. Deliveries includes customer inbound jobs,
  outbound pickups, and vendor purchase orders; Inventory includes every currently usable supply.
- Click a job row to inspect its cutting ticket and pallet progress; click **Back** to close the computer.
- Completing, delivering, and receiving payment for a client's first job establishes a repeat-client
  relationship. That company can send a varied follow-up request by email 1-3 game days later. The
  computer's **Email** tab shows the sender, proposed dimensions, pallet and sheet quantities,
  packaging, and stock-arrival service. Enter and send a quote or decline the request. From a completed
  job, **Email 10% Promo** opens a message composer where the player can add a personal note. Email jobs
  use separate stable IDs and the same delayed truck workflow as walk-ins.
- One in-game day lasts five real minutes. The viewable office calendar advances through weekdays, months,
  leap years, and years and automatically projects job stock, product and machine deliveries, incoming emails,
  pickups, completions, rent, and bills. On the first of each new month the
  shop receives a $1,650 operating invoice: $1,200 warehouse rent, $240 power, $85 water, and $125
  internet. Use the computer's **Bills** tab to pay the full outstanding balance; unpaid months carry forward.
- Every scene and GUI has a visible mouse-clickable **Back**, **Exit**, or **Exit to Menu** control using
  the shared Polar-style physical button sprite. The visible button and **Escape** use the same close
  behavior on every screen; customer and vendor closes leave the visitor waiting. The vendor catalog
  also has a Polar-panel `NO THANKS` button that dismisses the salesperson without buying.
- Reception visits begin after randomized opening intervals, then customers return after 60-150 seconds
  and salespeople after 120-240 seconds. A waiting, reviewing, entering, or exiting visitor pauses the
  other visitor's timer so the shared entrance and reception desk never become overcrowded.
- Reception is closed on Saturdays and Sundays. Scheduled customer and salesperson countdowns pause
  for the entire weekend and resume with their remaining time on Monday; no new visitor enters while closed.
- Accepting a job records its promised stock-arrival service instead of spawning a truck immediately.
  **Express / Urgent** deliveries arrive after 2-6 in-game hours, **Quick** deliveries arrive the next
  day, and **Standard** deliveries arrive after 2-3 days. The service and remaining estimate appear on
  the customer ticket and office computer. Only after that calendar window opens can the inbound truck
  schedule; the loading bay then opens automatically before it reverses rear-first along its isometric
  body axis into the door.
- At a parked truck's rear, press **E** to open or close its animated cargo door. The wall door cannot close while a truck occupies the bay.
- When the truck cargo door is open, press **E** to open its manifest. Click **Unload** for each
  pallet; every click animates a uniquely tracked paper pallet from the truck onto the warehouse floor.
- Customer and vendor pallets share five marked receiving lanes. Each unload reserves a clear lane;
  when all five are occupied, unloading pauses without changing the job, order, stock, or money. Use
  the pallet jack to move a staged pallet away from the dock, then return to the manifest to unload.
- Hover a warehouse pallet to see its company, job ID, sheet count, paper ID, current dimensions,
  status, and location. Pallets are saved, depth-sorted, and block walking.
- Near the yellow pallet jack, press **E** to operate it. Drive with **WASD/arrow keys**, press **E**
  near a pallet to lift it, click a green floor-grid space, and press **E** to lower it precisely.
- Press **F** to park and release an empty pallet jack. Loaded jacks move more slowly and use a larger
  collision footprint; placement is rejected when walls, machines, trucks, or other pallets are too close.
- After the manifest is empty, click **Close Cargo Door**. The truck leaves and the bay closes automatically.
- Warehouse purchasing is handled by visiting salespeople at reception. Paper, press-supply, packaging,
  and maintenance representatives arrive in rotation and wait until the player talks to them with **E**.
- Each salesperson opens a mouse-clickable category catalog. Purchases deduct cash immediately and create
  a tracked purchase order; the goods arrive later by truck at the loading dock instead of appearing instantly.
- The office computer Inventory tab sells the same currently unlocked supplies in smaller retail quantities.
  Salespeople offer larger pallet quantities at a lower per-unit bulk price; both channels use dock delivery.
- The office computer's **Online** tab sells professionally inspected machines in strong condition and shows
  every uniquely numbered shop machine, its weakest component, cycles, installation state, and condition-based
  resale value. An online purchase reserves its unique machine immediately but does not add it to the shop yet:
  a dedicated loaded flatbed truck brings it to the dock, where the player opens the manifest and clicks
  **Unload**. The flatbed visibly becomes empty and can then be released. Used-machinery salesmen offer cheaper
  units that tend to have substantially more wear.
- Cutter and skid-wrapper use degrades model-specific components and total condition. Maintenance kits are
  available from the tools supplier; the machine-service contract exposes stable interactive scene IDs so each
  machine can receive its own moving-sprite maintenance minigame without changing saved machine records.
- Vendor goods unload as distinct directional product pallets. They show product/quantity tooltips and can be
  lifted, driven, and lowered with the pallet jack while retaining their last assigned direction.
- Near an unoccupied loading bay, press **E** to open or close the roll-up door manually.
- Operate an empty pallet jack and drive it beside an unloaded cutter or skid wrapper to reveal **M: Relocate**.
  Press **M** to lift the machine, use **WASD/arrow keys** to move it slowly, **Q** to rotate it, click a
  green floor-grid space, and press **E** to lock it there. Red spaces are blocked. Relocation is unavailable
  without the pallet jack.
- Cutter: lower unfinished customer pallets into the expanded feed-side staging area beside the cutter, then open the console. The feed side follows the cutter's current orientation. **LOAD JOB** or **L** opens a nearby-pallet menu, where the operator chooses the exact pallet to load. A pallet still owned by the jack, on the wrong side, or outside the 140-pixel feed radius cannot load. Click the **TYPE** field, enter a backgauge position, and press **Enter** or click **SET**.
  **M** saves the current measurement for the selected cut number. **G / AUTO SET** recalls only player-saved measurements, newest first, and cycles through the last three values saved separately for CUT 1, CUT 2, CUT 3, or CUT 4. **P** pushes/positions;
  **Q** rotate the paper counter-clockwise into the next front-edge cutting position, **Space** clamp,
  and **J + K** together start the guarded cut. The active margin is always nearest the screen.
- Cutter repeat programming: **V** recalls the newest measurement for the selected cut, **[ / ]** changes
  the selected cut program, and **U** pulls each completed lift off the bed and returns it to its pallet.
  **Run Next Lift** reloads uncut sheets but never performs cuts automatically; every lift requires the full
  rotate, position, clamp, and four-cut sequence.
- Cutter output searches the surrounding floor for a walkable position clear of walls, the truck,
  equipment, the pallet jack, and other pallets. If every output zone is blocked, move the obstruction,
  reopen the console, press **L** to resume the completed batch, and then press **U** again.
- Every cutter action is also mouse-clickable. The two on-screen cut controls must be clicked within
  the same 0.30-second safety window as the keyboard controls.
- Cutter safety: **B** toggles the light barrier; **X** triggers emergency stop; **R** resets
- The **Original Heidelberg 10x15 Windmill** appears in the machine website and used-machinery dealer.
  Its flatbed delivery must be unloaded before use. The installed press has four floor-facing views and
  a saved position. With the press idle and unloaded, operate an empty pallet jack beside it and press **M**
  to relocate it; **WASD** moves, **Q** rotates, and **E** locks it on the floor. A carried machine renders
  above the jack forks.
- Open the Windmill with **E**. Its Polar-panel-inspired screen is fully mouse-clickable and contains
  **Run, Plates, Setup, Proof, Service, Help,** and a sprite **Exit** button. Physical shortcuts use the same
  control functions: **M** motor, **F** feeder, **I** impression, **+/-** speed, **X** emergency stop,
  **R** reset, and **Space** start/stop production.
- Every ink color needs its own stable, job-numbered plate. Order a processed plate with a one-day lead
  time or use one plate-room kit to expose, wash, dry, and mount it through the timing minigame. Cut stock
  must be staged within the marked press-side working radius, its next plate must be mounted, and prior colors
  must be dry before loading. The load screen compares the client's ordered copies with the physically supplied sheets.
- Complete chase lockup, tympan/packing, roller stripe, ink, feeder, and register checks; then run the
  motor, feeder, and impression to pull a proof. Each proof consumes one supplied sheet and displays the
  actual client artwork. Inspect it, verify the art/file match (**V**), and approve only when registration
  reaches 82%. Once approved,
  production tracks actual impressions, good sheets, spoilage, run hours, component wear, and plate life.
  High speed, poor setup, and worn rollers, grippers, suction, or ink distribution raise waste.
- A finished color pass requires press wash before unloading. Uncoated work dries for two game hours;
  gloss work dries for eight. Two-color work returns for another complete plate/setup/proof/run/wash pass.
  The office job ticket shows its press sequence, actual production totals, actual supply spend, and quoted
  supply budget; printed pallets continue
  through boxing/wrapping and truck pickup normally.
- Press supplies are sold from the office computer in smaller retail packs or by the press-supply salesman
  in discounted bulk quantities: black/color ink, press wash, tympan, and plate-room kits. Routine service
  uses maintenance kits and an ordered lockout sequence. A $350 field technician visit restores timing,
  suction, lubrication, and safety systems on the following game day and sends a service email.
- Computer and salesman supply purchases wait four game-hours before dispatch. Purchases placed within one
  game-hour share one grouped truck manifest instead of spawning separate trucks. Maintenance kits remain
  physical product pallets until used; the empty kit pallet despawns after service.
- Cutter and Windmill Help use forward/back pages with complete job, supply, setup, production, cleanup,
  safety, blade-change, and maintenance instructions. Scheduled field calls spawn a differently dressed
  mouse blade technician or lizard press technician who enters through reception, services the machine,
  and walks back out.
- Close a GUI: **Esc**

The cutter table starts clear and paper appears only after **L**. Inventory is consumed only when a safe cut finishes.

New shops begin with 20 shipping cartons and one full stretch-film roll (11 wraps), enough to run the first basic boxed and flat packaging work without an immediate supply order. A completed flat pallet uses the finished wrapped-pallet sprite in the warehouse.

Artwork rendering keeps the structured job artwork as the saved identity and resolves it through the artwork
library at draw time. The same client image is composited onto the order, plate, proof, live press sheet,
pallet, and completion views, while the reusable inspection sprites remain blank underneath. New artwork
should be added as a 128x128 transparent nearest-filtered PNG and registered in `Config.paths.artwork`.

## Validation

- Double-click `RUN_SMOKE_TEST.bat` to run the isolated domain suites, focused engine integrations,
  audit-coverage manifest, and three-frame render gate. Its report is written to
  `.stabilization/smoke-report.rpt`; the suite layout is documented in `docs/testing.md`.
- Double-click `RUN_SPRITE_MOTION_TEST.bat` for the visible sprite motion lab. It runs the same smoke
  checks, then keeps an animated raw-versus-normalized character comparison open until **Esc**.
- Run `python tools/asset_doctor.py --report output/asset-audit.json` to audit the project-bound raster assets without changing them.
- Audio credits ship in `assets/audio/SOURCES.md`. Run
  `python tools/generate_sfx.py --verify-only` to verify every licensed source
  recording against the release manifest without rewriting cues.
- Warehouse props are ready in `assets/generated/`: `empty-pallet.png`, `paper-stack.png`, `toolbox-small.png`, `toolbox-large.png`, and the three-variant `paper-storage-boxes-strip.png`.
- The active warehouse background is `assets/generated/warehouse-layout-final.png`: the approved 1536x1024 warehouse sprite with factory floor in front, loading dock upper-left, separate office upper-middle, and a client lounge in the upper-right with a couch, two armchairs, and a coffee table. Its matching walkmask is `warehouse-layout-final-walkmask.png`.
- The starter shop includes a movable skid wrapper based on the `stretchWrapper` references. Customer paperwork specifies flat or boxed pallet packaging. Move finished pallets beside the wrapper, press **E**, click the exact pallet ID in the nearby-pallet list, then press **L**, **Space**, or **WRAP PALLET**. Once its three-second cycle starts, finish the cycle before exiting, resetting, or relocating the wrapper. Each film roll wraps 11 pallets; order replacement rolls from the packaging salesperson and receive them at the loading bay. Use **M** near the wrapper to relocate it and **Q** to rotate it.
- Character sources in `assets/Characters/` are processed with the Mouse Frontier sprite doctor and installed as transparent, nearest-filtered strips in `assets/generated/characters/`. The playable rabbit now uses this same modular contract, with a clean four-pose distance-synchronized walk and two-pose idle, so later playable characters do not require a custom renderer. The loader also registers the original visitor types plus the business-dragon, business-fox, and business-cat client roster with idle, walk, and sit actions. Clients rotate through the lounge seats, remain seated while waiting, and leave after five minutes without a conversation.
- `loading-bay-door-strip.png` contains five transparent closed-to-open layers. The open state reveals the exterior parking lot while preserving the approved warehouse pixels outside the doorway.
- `delivery-truck-open.png` is the independent open-body truck sprite. `truck-cargo-door-strip.png` supplies five aligned rear-door layers from closed to fully open.
- `machine-delivery-flatbed-loaded.png` and `machine-delivery-flatbed-empty.png` are aligned machine-delivery
  truck states. Machine deliveries use these instead of the box truck and switch states when the player unloads.
- `polar-operator-console.png` supplies the new front-view machine. Separate button, clamp, and blade
  strips animate the physical controls while the touchscreen and work-order program remain interactive.
- `polar-cutter-directions-strip.png` supplies eight 45-degree shop-floor views. The cardinal intermediates
  smooth the cutter's rotation while the rear views correctly show the machine's service panels.
- `loaded-paper-pallet-directions-strip.png` contains four correctly oriented loaded pallets with the
  paper resting directly on the deck. Empty and loaded pallet-jack strips use eight movement directions
  while reusing those approved four pallet views unchanged.
- `vendor-product-pallets-atlas.png` contains four-direction pallet art for paper stock, press supplies,
  packaging supplies, and maintenance equipment.
- `heidelberg-windmill-directions-atlas-v1.png` contains the four saved floor directions for the authentic
  compact platen press. Its light generated backdrop is removed at runtime by the Windmill-only shader.

LÖVE is required for the in-engine smoke test. The asset doctor can run independently with Python and Pillow.

## Project structure

`main.lua` delegates every callback to `src/app.lua`. World simulation and rendering are separate,
screens share `src/screens/ui.lua`, and domain/integration checks live under `src/tests/`. See
`docs/asset_manifest.md`, `docs/testing.md`, `docs/coding_conventions.md`, `docs/asset_pipeline.md`,
and `docs/polar115_research.md` for the runtime boundary, test map, conventions, and production research.
