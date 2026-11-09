# Field mouse west K5 proportion correction v1

Status: one ImageGen edit attempt requested by root; pending visual review. No runtime installation or per-part image scaling.

## References

1. **Primary identity and proportion reference:** `output/animation-overhaul/luna-worker-actions/mouse-west/contact5-proportion-correction-v1/approved-idleW-frame1-identity-reference.png`, an unscaled pixel crop of the first 256x256 cell from approved runtime west idle `assets/generated/technician-motion-v2/field-mouse-technician/idle_west.png` (SHA-256 `886efc1ad1bf57bedb3a1b98927b82135281b9d53599f080b592e37a979a0f66`). Crop SHA-256: `DAD1E9B6913B2EBFAAFDC018859B6238E47E31EF3FABD315B17A7F0AD0CF9A00`.
2. **Pose, appendage, and gear reference:** `assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/contact5-correction-v1/field-mouse-worker-k5-opposite-contact-v1-imagegen.png` (SHA-256 `FC586FCAB55A59D139F3309FA4850D2D139BF974045875EC4AA0BFD81A2F5451`). This is the already corrected K5 image; its accepted staging registration is `output/animation-overhaul/luna-worker-actions/mouse-west/contact5-correction-v1/field-mouse-worker-k5-opposite-contact-v1-registered-256.png` (SHA-256 `EE4F0F2EB3A8C852771C9C9418C69550677A00951EE490FA6F08E3EE0C2BA46F`).

Reference order supplied to ImageGen: the identity crop is image 1; corrected K5 raw source is image 2. Image 1 is the primary authority for identity and body proportions. Image 2 is the primary authority for K5 pose, appendage placement, and gear.

## Exact prompt

Edit the second reference image as the only image canvas. Image 1 is the primary identity and proportion authority: preserve the approved west-facing gray field mouse design, exactly two ears with the near ear pink and the single far ear gray, the same head width and head-to-torso proportions, blue shirt, orange reflective vest and silver bands, brown belt and pocket, navy trousers and cargo pocket, brown boots, pink tail, outline, shading, palette, and light. Do not add another ear, duplicate a limb, or change species anatomy.

Image 2 is the primary pose, appendage, and equipment reference. Keep this corrected K5 west-facing walking contact pose: the far/plain leg leads and plants toward screen-left, the near cargo-pocket leg trails toward screen-right, the free arm counter-swings, and the black case remains in the same far hand. Keep the tail on the same side and flowing toward screen-right. Preserve the pose and gear while correcting the body proportions to match Image 1: restore the upright idle's torso and trouser segment lengths, including the taller vest span; a natural stride may lower the pelvis modestly, but do not compress the vest or shorten the trouser segments to create the walk. Keep the head at the same visual width as Image 1. Make a coherent articulated pose with naturally bent joints; do not resize individual body parts independently or add props.

Return one full-character transparent RGBA sprite on a square canvas, with the entire mouse, case, and tail inside the canvas. Preserve the west profile camera and screen-left facing direction. Use the same clean outlined illustrated style, palette, texture, and lighting as the references. No floor, shadow, scene, text, border, checkerboard, extra character, or sprite-sheet layout.

## Generation result

ImageGen returned one RGBA PNG at `C:\Users\johnw\.codex\generated_images\01a17bff-cf8e-7f63-8e8d-221432232467\exec-0270c6ba-c7aa-4ace-bf47-dd2f72f1d41a.png`. The original generated file was left in place and copied byte-for-byte to `assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/contact5-proportion-correction-v1/field-mouse-worker-k5-proportion-v1-imagegen.png` (SHA-256 `3CB33FE62981454B7EB8E13B91BFAF1C69D61F1A55DB30255F0B0FD7E5E67404`, dimensions `1254x1254`, RGBA). The result was stored and displayed via `generatedImage(result)`; no `.content` parsing or folder scan was used.

## Review evidence

- Fixed-head source comparison: `output/animation-overhaul/luna-worker-actions/mouse-west/contact5-proportion-correction-v1/k5-proportion-v1-source-fixed-head-comparison.png` (SHA-256 `7ff1c4c15facc322e084fc13e6b485f6e43d6096e0f2d137d8bfba302285a448`). Entire characters are uniformly scaled to a 94.5px broad head and rigidly aligned at torso axis x=128 and ground y=229; no part-level resizing.
- 64-world-pixel projection: `output/animation-overhaul/luna-worker-actions/mouse-west/contact5-proportion-correction-v1/k5-proportion-v1-64-world-px-current-action-comparison.png` (SHA-256 `8dd329b62ab15bc63659db58e84b9306c171806b90ec3b18e192d149adc30405`). The idle scale comes from the approved idle set's 192px maximum. Walk scale uses the maximum of the existing eight-frame walk v2 set and this new candidate (187px); old/new K5 share one walk scale. Recompute if the final accepted full action has another maximum.
- Metrics and build code: `output/animation-overhaul/luna-worker-actions/mouse-west/contact5-proportion-correction-v1/k5-proportion-v1-review-metrics.json` and `build_k5_proportion_review.py`.

At a common head scale, approved idle W1 measures 192px total height, 49px central vest span, 67px head-top-to-vest-top, and 76px trouser-onset-to-ground proxy. Previous corrected K5 measures 181px, 45px, 65px, and 70px. This candidate measures 187px, 48px, 66px, and 68px. It restores nearly all of the vest height while retaining a modestly lowered gait silhouette; the lower-body proxy remains 8px shorter than idle and 2px shorter than the previous K5. At the projected action scales, idle head width is 31.67wu and candidate K5 is 32.51wu, about 2.7% larger; the candidate becomes the projected walk action's tallest frame at 187px. This is review evidence, not an approval or runtime install.

Visual anatomy QA on the generated result: exactly two ears (one near pink ear and one far gray ear), two arms, two legs, one pink tail, and the case in the far hand; no extra detached marks observed. The alpha>=16 foreground bbox is `(209,118)-(1193,1162)` and no alpha>=16 foreground pixels touch any source-canvas edge, so the connected silhouette is not clipped at this threshold.

## Full-cycle acceptance gate

Use this candidate as the primary outfit, head, vest, leg-proportion, and style reference for later west gait work; use approved idle W1 as the secondary proportion/two-ear reference. It is not a promoted or approved full cycle. A complete cycle must show one consistent body/head/vest/trouser scale in all eight cells, opposite lead legs at contacts 1 and 5, the far-leg weight-down/near heel release at 6, and the near-leg knee-up/opposite swing at 8. Keep exactly two ears, the same far-hand black case, vest reflectors, trousers and pocket, and pink tail in all cells. Remaining mixed-height legacy cells and the earlier wrong-owner K8 do not pass this gate.
