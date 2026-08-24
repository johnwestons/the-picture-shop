# The Picture Shop

A playable LÖVE 2D vertical slice for an isometric pixel-art print-shop management game.

## Run on Windows

1. Install [LÖVE 11.x](https://love2d.org/) with the 64-bit Windows installer.
2. Double-click `RUN_GAME.bat` in this folder.

The launcher finds LÖVE on `PATH`, in a local `runtime` folder, or in the normal Program Files locations. LÖVE must receive the whole project folder; do not open `main.lua` by itself.

## Title and saves

The title screen has three local save slots. Use **W/S** or the arrow keys to select a slot, **N** for a new shop, **C** or **Enter** to continue, **D** to delete, and **Q** or **Escape** to quit. Confirmation prompts accept **Y** or **Enter** and cancel with **N** or **Escape**. Starting a new shop in an occupied slot always shows an overwrite warning; cancelling it leaves the existing save unchanged. Saves are versioned and retain money, stock, finished prints, completed cuts, and player position.

Save format 3 retains active, completed, and declined jobs, accounts receivable, procurement,
stock, film, machine placements, pallet-jack ownership, wrapper placement, and the next stable
job number. Version-1 and version-2 slots migrate when loaded. Saves are validated in a temporary
file before promotion and retain the previous valid slot as a backup. A damaged primary recovers
automatically; a slot with no valid recovery copy is marked as damaged instead of appearing empty.

## Job rules foundation

- A cutting job accepts 1–5 customer pallets with 500–3,000 sheets on each pallet.
- The largest incoming parent sheet is 25×25 inches, and the finished size must fit the parent sheet.
- The Polar lift capacity is 500 sheets. A partial final lift is allowed and billed as a full lift.
- Each lift is quoted at $150. Five 3,000-sheet pallets therefore quote at $4,500.
- Job offers retain an immutable quote breakdown and separate mutable progress for every pallet.
- Every pallet now owns a stable paper-batch ID, job artwork ID, live width/height, orientation,
  four margins, four-cut program, and complete cut history. Easy jobs use matching opposing margins;
  medium and hard work uses asymmetric margins that require different backgauge positions.
- Accepting a ticket adds it to active jobs as `awaiting_delivery` and records accounts receivable;
  cash and physical pallet inventory do not increase until their later workflow events.
- Declining archives the numbered ticket, cancels its quoted pallets, and sends the customer out.

## Controls

- Move: **WASD** or arrow keys
- Interact with the office computer or Polar 115: **E**
- At reception, press **E** to open the customer's cutting-job paperwork.
- Use the mouse to click **Accept Job** or **Decline** on the paperwork. **Back** and **Escape**
  both close the paperwork without deciding, so the customer remains available at reception.
- At the office computer, press **E** and use the mouse to view Active Jobs, Completed Jobs,
  Deliveries, Inventory, cash, and accounts receivable. Deliveries includes customer inbound jobs,
  outbound pickups, and vendor purchase orders; Inventory includes every currently usable supply.
- Click a job row to inspect its cutting ticket and pallet progress; click **Back** to close the computer.
- Every scene and GUI has a visible mouse-clickable **Back**, **Exit**, or **Exit to Menu** control using
  the shared Polar-style physical button sprite. The visible button and **Escape** use the same close
  behavior on every screen; customer and vendor closes leave the visitor waiting.
- Accepting a job schedules its inbound truck. The loading bay opens automatically before the truck backs in.
- At a parked truck's rear, press **E** to open or close its animated cargo door. The wall door cannot close while a truck occupies the bay.
- When the truck cargo door is open, press **E** to open its manifest. Click **Unload** for each
  pallet; every click animates a uniquely tracked paper pallet from the truck onto the warehouse floor.
- Customer and vendor pallets share five marked receiving lanes. Each unload reserves a clear lane;
  when all five are occupied, unloading pauses without changing the job, order, stock, or money. Use
  the pallet jack to move a staged pallet away from the dock, then return to the manifest to unload.
- Hover a warehouse pallet to see its company, job ID, sheet count, paper ID, current dimensions,
  status, and location. Pallets are saved, depth-sorted, and block walking.
- Near the yellow pallet jack, press **E** to operate it. Drive with **WASD/arrow keys**, press **E**
  near a pallet to lift it, and press **E** again to lower it at a clear floor position.
- Press **F** to park and release an empty pallet jack. Loaded jacks move more slowly and use a larger
  collision footprint; placement is rejected when walls, machines, trucks, or other pallets are too close.
- After the manifest is empty, click **Close Cargo Door**. The truck leaves and the bay closes automatically.
- Warehouse purchasing is handled by visiting salespeople at reception. Paper, press-supply, packaging,
  and maintenance representatives arrive in rotation and wait until the player talks to them with **E**.
- Each salesperson opens a mouse-clickable category catalog. Purchases deduct cash immediately and create
  a tracked purchase order; the goods arrive later by truck at the loading dock instead of appearing instantly.
- Vendor goods unload as distinct directional product pallets. They show product/quantity tooltips and can be
  lifted, driven, and lowered with the pallet jack while retaining their last assigned direction.
- Near an unoccupied loading bay, press **E** to open or close the roll-up door manually.
- Near an unloaded cutter, press **M** to enter machine-relocation mode. Use **WASD/arrow keys** to
  move it slowly, **Q** to rotate it 90 degrees, and **E** to lock it in its new floor position.
- Cutter: lower an unfinished customer pallet into the feed-side staging area beside the cutter, then open the console. The feed side follows the cutter's current orientation; when several pallets are staged there, the nearest one loads first. A pallet still owned by the jack, on the wrong side, or too far away cannot load. Click the **TYPE** field, enter a backgauge position, and press **Enter** or click **SET**.
  **L** loads the staged paper, **G** selects the next unfinished cut and loads its saved backgauge value, and **P** pushes/positions;
  **Q** rotate the paper counter-clockwise into the next front-edge cutting position, **Space** clamp,
  and **J + K** together start the guarded cut. The active margin is always nearest the screen.
- Cutter repeat programming: **M** saves the current gauge, **V** recalls it, **[ / ]** changes the
  selected cut program, and **U** pulls completed paper off the bed and returns it to its pallet.
- Cutter output searches the surrounding floor for a walkable position clear of walls, the truck,
  equipment, the pallet jack, and other pallets. If every output zone is blocked, move the obstruction,
  reopen the console, press **L** to resume the completed batch, and then press **U** again.
- Every cutter action is also mouse-clickable. The two on-screen cut controls must be clicked within
  the same 0.30-second safety window as the keyboard controls.
- Cutter safety: **B** toggles the light barrier; **X** triggers emergency stop; **R** resets
- Close a GUI: **Esc**

The cutter table starts clear and paper appears only after **L**. Inventory is consumed only when a safe cut finishes.

## Validation

- Double-click `RUN_SMOKE_TEST.bat` to run the isolated domain suites, focused engine integrations,
  audit-coverage manifest, and three-frame render gate. Its report is written to
  `.stabilization/smoke-report.rpt`; the suite layout is documented in `docs/testing.md`.
- Run `python tools/asset_doctor.py --report output/asset-audit.json` to audit the project-bound raster assets without changing them.
- Warehouse props are ready in `assets/generated/`: `empty-pallet.png`, `paper-stack.png`, `toolbox-small.png`, `toolbox-large.png`, and the three-variant `paper-storage-boxes-strip.png`.
- The active warehouse background is `assets/generated/warehouse-layout-final.png`: the approved 1536x1024 warehouse sprite with factory floor in front, loading dock upper-left, separate office upper-middle, and a client lounge in the upper-right with a couch, two armchairs, and a coffee table. Its matching walkmask is `warehouse-layout-final-walkmask.png`.
- The starter shop includes a movable skid wrapper based on the `stretchWrapper` references. Customer paperwork specifies flat or boxed pallet packaging. Move a finished pallet beside the wrapper, press **E**, then **L** or **Space** to wrap it. Once its three-second cycle starts, finish the cycle before exiting, resetting, or relocating the wrapper. Plastic film costs $20 per roll and wraps 11 pallets; buy rolls from the office computer Inventory tab. Use **M** near the wrapper to relocate it and **Q** to rotate it.
- Character sources in `assets/Characters/` are processed with the Mouse Frontier sprite doctor and installed as transparent, nearest-filtered strips in `assets/generated/characters/`. The modular loader registers the original visitor types plus the business-dragon, business-fox, and business-cat client roster with idle, walk, and sit actions. Clients rotate through the lounge seats, remain seated while waiting, and leave after five minutes without a conversation.
- `loading-bay-door-strip.png` contains five transparent closed-to-open layers. The open state reveals the exterior parking lot while preserving the approved warehouse pixels outside the doorway.
- `delivery-truck-open.png` is the independent open-body truck sprite. `truck-cargo-door-strip.png` supplies five aligned rear-door layers from closed to fully open.
- `polar-operator-console.png` supplies the new front-view machine. Separate button, clamp, and blade
  strips animate the physical controls while the touchscreen and work-order program remain interactive.
- `polar-cutter-directions-strip.png` supplies northwest, northeast, southwest, and southeast shop-floor
  views. The rear rotations correctly hide the operator console and show the machine's rear service panels.
- `loaded-paper-pallet-directions-strip.png` contains four correctly oriented loaded pallets with the
  paper resting directly on the deck. Matching empty and loaded pallet-jack strips use the same directions.
- `vendor-product-pallets-atlas.png` contains four-direction pallet art for paper stock, press supplies,
  packaging supplies, and maintenance equipment.

LÖVE is required for the in-engine smoke test. The asset doctor can run independently with Python and Pillow.

## Project structure

`main.lua` is intentionally tiny and delegates every callback to `src/app.lua`. State, saves, assets, viewport scaling, input, navigation, interactions, world behavior, economy, the Polar simulation, smoke checks, and every UI screen live in focused modules. See `docs/coding_conventions.md`, `docs/asset_pipeline.md`, and `docs/polar115_research.md` for the adapted Mouse Frontier conventions and production research.
