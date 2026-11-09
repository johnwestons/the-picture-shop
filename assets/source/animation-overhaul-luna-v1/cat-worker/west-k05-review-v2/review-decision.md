# West K5 review v2 decision

Status: rejected; review-only. No runtime art or shared documentation was changed.

West-facing means the cat faces viewer-left: viewer-left is the forward side and viewer-right trails. The authored K1 contact is the opposite support owner from K5. For K5 the intended far/right foot must plant at viewer-left while the near/left foot trails slightly lifted at viewer-right; K6 retains the far/right support. The source K5 still reads with the same broad olive-trouser leg reaching to the viewer-left plant as K1.

One ImageGen edit was attempted using the original K5 as the edit target, K1/K4/K6 as gait references, and the labeled owner guide. At 64px, the candidate still shows the olive near/left boot planted toward viewer-left and the far/right dark boot lifted under the satchel. It therefore does not prove the required ownership change. The candidate also has no transparent exterior: it is 1254x1254 RGBA with alpha fixed at 255, zero transparent pixels, a full-canvas alpha16 bbox, and all 5016 border pixels visible. The displayed checkerboard is baked into the raw image. The raw is preserved unchanged. The contact preview uses only one whole-canvas nearest-neighbor scale of 512/1254 for visual comparison; it is explicitly labeled as opaque raw output, not normalized sprite art.

The eight source keys were rendered at the fixed source-to-64px scale 64/(2*194) using the registered West anchors and checkerboard tiles. The candidate cycle row is only diagnostic because the opaque output cannot be used as a sprite. The 180ms and 360ms sequence previews are included to show the proposed cycle timing and the failed cell; neither implies acceptance.

Rebuild the contact evidence with the bundled Python runtime:

`C:\Users\johnw\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe assets/source/animation-overhaul-luna-v1/cat-worker/west-k05-review-v2/build_review_pack.py`

The immutable source strip and all eight extracted key hashes, exact prompt hash, generation cache path/time, and candidate alpha/edge audit are recorded in `hash-manifest.json` and `generation-result.json`.
