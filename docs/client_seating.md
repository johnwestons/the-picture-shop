# Client seating

The three business clients now use two-frame seated atlases authored from their existing character identities and the new warehouse couch. They sit with forward thighs, bent knees, relaxed hands and their backs aligned with the couch. A brief 140 ms blink plays about every three seconds; their hips, feet and body scale stay planted throughout the loop.

The previous action renderer normalized sitting to standing height. The client presentation now uses a 54 px seated silhouette at the default 0.30 scale (70.3125% of standing height). All three atlases use a posterior cushion anchor at cell coordinate `(148, 179)`, rather than a foot anchor. Each lobby seat separately registers its cushion in `src/warehouse_registration.lua`:

| Seat | Cushion contact | Sprite mirror |
| --- | --- | --- |
| Left chair | 718, 178 | -1 |
| Couch left | 754, 176 | 1 |
| Couch right | 794, 185 | 1 |
| Right chair | 811, 201 | 1 |

Both couch positions use the same view facing the room. The approach direction still controls the walking pose. Physical visitor coordinates, navigation routes, interactions, job-review transitions and network snapshot fields keep their existing contract; only rendering adds the cushion offset. Custom seat definitions without cushion data align the new poses to their foot contact. Other visitor and employee art keeps its existing registration.

The subsequent lobby furniture edit uses `assets/generated/warehouse-lobby-seating-v2.png`. It removes the coffee table and gives the couch two broader seat cushions around these existing contacts. The former table collision and sofa/table foreground masks are removed so clients' lower legs remain visible; armchair foreground masks remain. See `docs/lobby_seating_art.md` for the localized artwork and preservation checks.

The built-in ImageGen tool produced the new art. Original sources and the exact prompts are saved in `assets/source/client-seating-v1/`, with source hashes and measured hip contacts in `source-manifest.json`. The existing character source and older seated atlases are retained. Runtime strips are:

| Character | Runtime atlas |
| --- | --- |
| Business dragon | `assets/generated/client-seating-v1/business-dragon/sit.png` |
| Business fox | `assets/generated/client-seating-v1/business-fox/sit.png` |
| Business cat | `assets/generated/client-seating-v1/business-cat/sit.png` |

`tools/build_client_seating_v1.py` reproducibly packs the reviewed source art into 256 px cells, using one uniform scale across each strip and fixed cushion anchors. It removes only export haze below alpha 24; opaque clothing, eye whites and tails are retained. It refuses changed source hashes. Anchors and bounds are precomputed in `src/client_seating_art.lua`; the runtime performs no pixel scans. Each client's existing motion JSON now includes its seated action. All three complete motion specifications passed the sprite-motion audit with zero errors and warnings.

`PICTURE_SHOP_SMOKE_FOCUS=client-seating` runs the client seating, customer motion, shared navigation, Lua limits and asset-pack regressions. The new suite checks every client at all four seats with real navigation, cushion registration, scale, blink stability, job review, matching host/guest poses and safe departures. Set `PICTURE_SHOP_SEATING_CAPTURE_DIR` to an existing directory for the twelve seat captures, a desktop view, a landscape mobile camera view and neutral/blink couch frames. Use isolated test APPDATA and a fresh `PICTURE_SHOP_TEST_IDENTITY` for each full test run.

The broader regression run also exposed an asset-pack swap bug with the new menu textures: unloading the menu could evict cached machine art immediately before reuse. Incoming textures are now claimed before caching the departing pack, within the existing 32 MiB inactive-cache budget.

Validation for this change: 685 focused checks passed, all three sprite audits reported zero errors/warnings, and the complete run passed 3,094 checks including the texture-cache regression before stopping at `camera_follow_centers_body_at_warehouse_edge`. That existing test expects immediate centering while the shared workspace's current camera implementation eases toward its target. Camera code and that test were left intact. Desktop, landscape mobile, all twelve client/seat combinations, and the neutral/blink in-engine previews were visually reviewed in `output/client-seating-v1/`.
