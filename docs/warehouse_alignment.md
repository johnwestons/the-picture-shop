# Warehouse registration

The B6 warehouse and three separate room backgrounds use a 960 × 678 world canvas. The calibration in `src/warehouse_registration.lua` separates a character's floor approach from the visible object to click or tap. Interaction eligibility still depends on the player's distance to the floor approach; clicking a distant object does not grant remote access. Keyboard and controller selection continue to use the floor contacts.

| Object | Floor contact | Visible contact |
| --- | --- | --- |
| Expansion-room passage | 648, 212 | 648, 161 |
| Exterior entrance / employee exit | 720, 202 | 720, 151 |
| Computer | 909, 241 | 909, 175 |
| Phone | 875, 238 | 879, 144 |
| Clock | 843, 234 | 843, 121 |
| Radio | 638, 230 | 638, 86 |
| Loading-bay controls | 194, 213 | 184, 129 |
| Truck cargo | 127, 242 | 109, 169 |
| Separate room exit | 100, 225 | 78, 167 |
| Stock-room shelves | 530, 285 | 530, 170 |
| Break-room seating | 775, 260 | 765, 184 |

The floor follows the painted seams beside the racks, passage wall, lounge and open office. Warehouse furniture has separate ground footprints for the remaining chair, sofa, divider, cabinet, desk and desk chair. The removed chair/plant area is kept clear for the relocated exterior door. Break-room furniture and room floor seams use that room's artwork. Scene adapters remain cached by source assets, scene and room kind. Collision queries return fresh copies so clearance inflation cannot enlarge the scenery permanently.

All three remaining lobby seating approaches remain reachable with the actual furniture and machines present. Chair fronts are restored over seated clients and suppliers. The lobby coffee table and its collision/foreground mask were removed in the lobby seating edit, and the chair beside the new exterior door was removed from collision and seating registration. The remaining reception chair and break-room chair contacts are aligned to the new furniture. Shelf registrations retain their measured deck contacts and foreground lips. Machine defaults, equipment starts, pallet receiving slots and cutter output staging fit the open production floor. The unloading origin and truck's rear opening now meet the dock, with its shutter and truck clipped inside the painted opening.

The previous employee exit `(645, 235)` belonged to the former warehouse layout. Employees and applicants now use the relocated exterior door registration at `(720, 202)`, separate from the expansion-room passage. Departing workers choose a free contact near the door when its center is occupied, wait with a blocked-path bubble if necessary, and keep collision checks while replanning. They leave after the greeting and after reaching a real door contact; proximity across a wall is insufficient. A full ten-worker roster can clear the doorway without leaving a permanent queue. Workers finish unsafe machine cycles and release pallet-jack ownership before departure. Hidden employees are omitted from guest pose snapshots.

`PICTURE_SHOP_SMOKE_FOCUS=warehouse-alignment` exercises the actual warehouse floor, visible-object selection, room masks, furniture collisions, receiving and machine footprints, all reception seats, employees leaving from several positions, a blocked doorway and recovery, a crowded full roster, safe machine shutdown, loaded-jack release, applicant arrivals/departures and live host simulation. It also runs the room, shared navigation, interaction and employee transport regressions. The full smoke suite includes the registration checks.

Set `PICTURE_SHOP_ALIGNMENT_CAPTURE_DIR` to an existing output directory to render `warehouse-calibrated.png`, `warehouse-contacts.png`, the four reception seats and `warehouse-truck-dock.png`. The contacts image overlays floor approaches, visible controls, ground footprints and the wall/floor seam for visual review. Tests can use a fresh workspace APPDATA and `PICTURE_SHOP_TEST_IDENTITY` to avoid writing to other game saves.
