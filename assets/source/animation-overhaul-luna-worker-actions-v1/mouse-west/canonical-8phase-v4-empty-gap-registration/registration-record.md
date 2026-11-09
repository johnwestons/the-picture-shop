# Field mouse west walk, v4 gap registration

Status: **review proposal only**. Root owns visual acceptance and runtime integration. No runtime assets, manifests, tests, or character-motion specifications were changed.

V4 uses the single existing v3 ImageGen master; no generation or repaint was performed. The verbatim prompt, result handling, generation provenance, and reference roles remain in [`../canonical-8phase-v3-proportion-consistent/generation-record.md`](../canonical-8phase-v3-proportion-consistent/generation-record.md), SHA-256 `d5b2262b5559ba382cb4c30a448231c6dc501f07c2bd5db938dea44a46255859`. Original ImageGen output path: `C:\Users\johnw\.codex\generated_images\01a17bff-cf8e-7f63-8e8d-221432232467\exec-a9a38e7a-ccc3-4aa2-9fa3-25267e5f7aa9.png`. The byte-identical staged master is `field-mouse-technician-west-canonical-8phase-v3-master-raw.png`, 1774×887 RGBA, SHA-256 `5465fe188fea59a8d9484f27b738a9078dcb77eb0b0724b96ce53a41dbce5ef5`.

The selection is frozen in [`selection.json`](selection.json). A root-side reproducible packager needs only the staged raw master and this selection: the file records the full source crops, the content crop used per pose, one uniform scale, per-frame resized dimensions, rigid paste offsets, target anchors, both strip hashes, and source-pixel partition proof. The source-owned builder is `register_v4_gap_crops.py`; it uses only Python, NumPy, and Pillow and does not import output review helpers.

The six vertical split lines are placed in alpha≥16 empty runs between each row's four figures. Their zero-alpha evidence is also recorded; one bottom-row line has a single weak-alpha pixel in its left adjacent column, but both adjacent columns are clear at alpha≥16. The horizontal split is at y=460, inside the alpha≥16 empty row run [423,490), with row 460 in the nearest all-alpha-empty run [460,461). Four weak-alpha pixels lie in the preceding source row and are assigned once to the upper row. The exact half-open crops are in the JSON.

The source registration uses global scale `27/56` (`0.48214285714285715`), torso axis x=128, ground y=229, and approved idle body reference height 192px. It does not resize cells independently or fit body parts. Render crops retain all alpha≥16 pixels plus an 8px source fringe; pixels below alpha 16 outside that region remain assigned to their original source crop but are excluded from the rendered cell. The JSON records those low-alpha counts/bounds, and the magenta audit sheet shows them for inspection. No alpha≥16 source foreground lies outside a render crop. All source atlas pixels belong to exactly one of the eight frozen crops. All registered cell edges have zero nonzero-alpha pixels.

Raw-border QA: the six split lines are clear at alpha≥16; every adjacent split column is also zero at alpha≥16. One bottom-row split column has one weak-alpha pixel on its left side. The source crop edges contain weak-alpha-only counts at K2 bottom=3, K3 bottom=1, K4 right=7, K7 right=1, K8 right=15; the other crop-edge counts are zero. The last two are near the tail tips at the outer image edge, while no alpha≥16 pixels touch those crop boundaries. The zoomed border review and magenta weak-alpha sheet show the near-edge specks; classify as a low-alpha margin risk, not a strong paw/body clip. All stronger figure pixels are included, and the 8px content fringe retains these near-edge taper pixels where the raw master contains them. There are 398 weak-alpha pixels outside the final registered content crops (per phase `60,14,61,3,125,92,41,2`); the review sheet exposes their isolated locations. Root should decide if any faint mark is an intended final antialias tail/whisker point before runtime use.

## Phase owners

1. Near/pocketed leg leads screen-left; far/plain leg trails.
2. Near/pocketed leg supports; far/plain trailing heel releases.
3. Far/plain leg passes compactly under the pelvis; near/pocketed leg supports.
4. Far/plain leg lifts forward screen-left; near/pocketed leg supports.
5. Far/plain leg leads screen-left; near/pocketed leg trails.
6. Far/plain leg supports; near/pocketed trailing heel releases.
7. Near/pocketed leg passes under the pelvis; far/plain leg supports.
8. Near/pocketed leg lifts forward screen-left; far/plain leg supports.

Visual phase/anatomy audit of the raw, registered, and fixed-idle-scale sheets found two ears total (near pink and one far gray), two arms, two legs, one pink tail, and the black case consistently in the same far hand. Contact owners alternate at K1/K5; knee-up owners alternate at K4/K8. K3/K7 remain compact passing poses and merit root's own leg-ownership review. The west-facing mouse still has the recorded body/vest-shortening finding against approved idle; at a fixed 64/192 scale, walk body heights are 58.7–60 world units against 64 for idle. Keep this as an open continuity concern.

## Review artifacts

- `field-mouse-technician-west-canonical-8phase-v4-gap-registered-8x1.png` is the straight 2048×256 runtime-format strip, SHA-256 `55cb2cd186b169dc9ae5acc6814b40a3ca6ad6a7207c8456b9a1e7244b21992c`.
- `field-mouse-technician-west-canonical-8phase-v4-gap-registered-4x2.png` is the same cells in a 4×2 source review layout, SHA-256 `744a660390028bd8d461c157cb8a64414541e6344634562ae9336ee761a3a1f7`.
- `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v4-empty-gap-registration/field-mouse-technician-west-v4-8phase-contact-sheet.png` shows all eight phases at 2× display zoom, SHA-256 `5ceaa6317d48a2c47c7c2e67fe4714fd0d7581f08c2e0078b0adc9a7231ec8e3`.
- `.../field-mouse-technician-west-v4-fixed-64-world-scale-contact.png` compares both approved west idle frames and all eight phases with the same 64/192 scale, SHA-256 `b1d6622a18b23d6e08db13aa4fef2a820e22c1f8f7ddac45f3a4dc27ea601381`.
- `.../field-mouse-west-idle-walk-idle-fixed64-170ms.gif` and `.../field-mouse-west-idle-walk-idle-fixed64-330ms.gif` each contain idle W1/W2, K1–K8, then idle W1/W2 (12 frames); their hashes are `eec4600d69c0733aec0a1f3aafe5ea0816d21437e7ed39cb25be5afe45752bd1` and `1c5ec298ded0334d3b65448d0c4891c5f977fea8f68a600939c9d29af9f4767e`.
- `.../field-mouse-technician-west-v4-omitted-weak-alpha-review.png` shows the weak-alpha pixels outside the registered art crop in magenta.
- `.../installed-mouse-lizard-walk-north-south-east-audit.png` reviews the six installed technician cycles.

The installed-art audit found authored mouse and lizard walk strips for north, south, and east (the east action is named `walk`); each strip has eight 256×256 cells, and all 48 frames have zero alpha≥16 pixels on their canvas edges. Neither technician currently has an authored west walk in `technician_art.lua`. The field mouse has a matching approved west idle and the staged west walk above, making mouse west the most supported missing view. The lizard has a west idle/reference but no west walk source in this batch.

Support-foot x annotations and foot-slide acceptance are not claimed here; root can measure those against current 13px-per-pose movement after reviewing the frozen art.
