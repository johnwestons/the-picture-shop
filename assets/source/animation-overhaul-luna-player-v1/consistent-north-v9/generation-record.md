# North V9 passing-pose source record

Root reviewed and installed this two-pose North correction as runtime V7 on October 27, 2026. It replaces only phases 3 and 7 in the V6 strip. The six untouched phases remain pixel-identical. The rejected complete-cycle drafts and earlier raw attempts remain preserved alongside this record.

## Selected generated sources

This is a rear-facing view. Character-left/right maps to viewer-left/right in the source references. The selected generated raws are therefore intentionally crossed relative to the anatomical-side wording in their filenames/prompts:

| Runtime phase | Selected raw | Leg ownership and pose | Uniform fit factor |
| --- | --- | --- | --- |
| 3 | `generated/north-phase7-imagegen-raw-v2.png` | Viewer-right / character-left boot passes; viewer-left / character-right boot supports. | 0.995169 |
| 7 | `generated/north-phase3-imagegen-raw-v2.png` | Viewer-left / character-right boot passes; viewer-right / character-left boot supports. | 0.987893 |

SHA-256 `north-phase7-imagegen-raw-v2.png`: `651246a523225921a700a237c642b82766c9d838058bb2ca2ae02ba824c27c3f`.

SHA-256 `north-phase3-imagegen-raw-v2.png`: `ed64d18039587538a0d729efed32a4dcd8c2e8a5f446b36e137d22d9a7f8ce46`.

## Registration and acceptance

Both poses were fitted as complete characters to the existing frame and baseline. A lower-body-only composite was rejected because it introduced a visible horizontal splice. The full-body registration retains the shared character scale and pose continuity. The original prompts described anatomical sides; review against the rear-view phase references exposed the side-label inversion, so root assigned the two generated poses to the opposite numbered phases before installation.

The installed strip `assets/generated/player-walk-v7/walk_north.png` has SHA-256 `8a182527de78fe8d0da5a5b8068ec0019ef08da9513bf29dbb2a74b126bcba33`. It is built reproducibly by `tools/build_player_north_v9_review.py` and installed by `tools/install_player_north_v9.py --apply`. V6 remains preserved. The candidate has zero flagged red/magenta or green fringe pixels, remains within the 408–412px cycle height band, and leaves the other six phases pixel-identical.

The north pass silhouettes are distinct at 64px, but the support sole still travels only 0–1 source pixels while the character root advances about 40 project pixels from contact to pass. This is a remaining gait-motion problem; this pose correction does not claim foot lock. No additional in-betweens were added.
