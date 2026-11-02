**Apartment layers — November 1, 2026**

Four approved apartment designs have been regenerated with built-in ImageGen as separate transparent floor/fixture and wall PNGs. The approved camera angle, material character, and layout direction are retained. There is no surrounding ground, neighboring building, garden, pavement, or scenery layer in the selected PNGs.

All selected images use a 1536 × 1024 RGBA canvas with a shared draw origin of (0, 0). Do not trim or independently resize either member of a pair. The laptop and movable furnishings are absent. Base sprites retain the sinks/counter, toilet, tub/shower and washer/dryer.

| Apartment | Floor + fixed fixtures | Walls |
| --- | --- | --- |
| Brick walk-up | [Floor](brick-walkup-floor-fixtures-v2.png) | [Walls](brick-walkup-walls.png) |
| Garden | [Floor](garden-floor-fixtures.png) | [Walls](garden-walls.png) |
| Courtyard | [Floor](courtyard-floor-fixtures.png) | [Walls](courtyard-walls-v2.png) |
| Corner | [Floor](corner-floor-fixtures.png) | [Walls](corner-walls-v2.png) |

[Open the layer viewer](preview.html) to switch apartments, inspect each layer, change the backdrop, and move a circular wall reveal. It loads only local files and does not load or change game saves. Browser execution was blocked by the available browser's local-file URL policy, so its script is syntax-checked but its visual interactions have not been browser-verified here.

The selected files and exact generation prompts are in [manifest.json](manifest.json). [registration.json](registration.json) records the shared coordinate contract and preliminary fixed-fixture repaint regions used by the viewer. [alpha-audit.json](alpha-audit.json) records read-only PNG checks and hashes. All eight have real alpha transparency and matching dimensions. The strict zero-at-every-corner audit notes a 1/255-alpha residual at one Courtyard wall corner; the other sampled exterior corners are zero. This is faint matting residue, not scenery, and should be removed during final asset import/normalization. The generator also leaves nominally solid pixels at alpha 253–254; production can normalize near-opaque alpha when preparing the runtime textures.

**Draw order and player visibility**

- Floor continues under removed interior walls; hiding a wall should reveal floor rather than an empty stripe.
- Render rear walls behind fixed fixtures. The viewer reuses bounded regions of the floor/fixture texture to keep plumbing above rear walls; these rectangles are review guides, not production collision definitions. Final rendering should use calibrated wall sections/fixture masks and depth ordering.
- Apply the player-radius mask only to the wall draw pass. Keep floors and plumbing intact. Use a soft edge and restore wall opacity after the character moves away.
- Decide which wall sections actually obscure the character before fading them. The viewer demonstrates the radius effect directly; it does not implement world depth tests, navigation or collision.
- Wall collision stays independent of visual transparency. Each multiplayer client calculates the reveal for its own controlled character.
- Add the separate exterior/background underneath both sprites later. Window panes and empty space must show that chosen backdrop.

The asset pairs are ready for art review. They have not been loaded into the game or calibrated against live player movement; exact door clearances, wall segmentation, fixture masks and collision registration remain part of implementation.

The unversioned Brick floor and Courtyard/Corner wall files are retained earlier passes; use the filenames in the table or manifest. The delivery ZIP includes only the selected eight PNGs and their supporting files.
