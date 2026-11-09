# Field mouse west canonical walk v3, proportion-consistent

Status: one ImageGen attempt requested by root; candidate only, pending full-cycle review. Do not install or treat as approved.

## Reference files and roles

1. **Primary identity, proportion, style, outfit, and contact-pose reference:** `assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/contact5-proportion-correction-v1/field-mouse-worker-k5-proportion-v1-imagegen.png` (SHA-256 `3CB33FE62981454B7EB8E13B91BFAF1C69D61F1A55DB30255F0B0FD7E5E67404`). This is the newly corrected K5 image and supplies the primary head/vest/trouser/body proportions, outfit, palette, west camera, far-hand case, tail, and far/plain-leg lead pose for phase 5.
2. **Secondary identity, upright body-proportion, and two-ear reference:** `output/animation-overhaul/luna-worker-actions/mouse-west/contact5-proportion-correction-v1/approved-idleW-frame1-identity-reference.png` (SHA-256 `DAD1E9B6913B2EBFAAFDC018859B6238E47E31EF3FABD315B17A7F0AD0CF9A00`), an unscaled crop of the first approved runtime idle-west cell. Its parent strip `assets/generated/technician-motion-v2/field-mouse-technician/idle_west.png` has SHA-256 `886efc1ad1bf57bedb3a1b98927b82135281b9d53599f080b592e37a979a0f66`.
3. **Lower-body phase-role guide only:** `output/animation-overhaul/luna-worker-actions/mouse-west/field-mouse-technician-west-canonical-8phase-v2-torso-axis-registered-4x2.png` (SHA-256 `dabb127c54e06133449edbba7901fcafc14fe861cc619ec93a1b1ba77b063e16`). Do not copy its old contact duplication, same-leg knee-up pairing, shorter vest/body proportions, or identity styling. Explicit roles below supersede errors in this reference.

The images were supplied in this order. Image 1 is the primary outfit and body-proportion source. Image 2 is the secondary upright/two-ear source. Image 3 is solely a lower-body gait-cycle visual reference.

## Exact prompt

Create one complete, internally consistent eight-phase west-facing walk sprite sheet using the supplied references in their stated roles. Return exactly eight separate full-character poses in a regular four-column by two-row grid, read row-major from top-left to bottom-right. Use equal-sized cells and generous, evenly spaced transparent gutters around every character. Keep each mouse fully inside its cell; do not overlap cells. No text, numbers, labels, cell borders, floor, shadow, scene, or checkerboard.

Image 1 is the primary authority for this same field mouse's head, body, proportions, vest, trousers, clothing, equipment, palette, outline, shading, camera, and west-facing identity. Image 2 is the secondary authority for upright body proportions and the exact two-ear anatomy. Keep the head, vest torso height, waistband, and trouser segment lengths consistent with Image 1 and Image 2 across all eight poses. The torso must not compress in gait; use only a modest natural body bob. Do not make one frame shorter or larger than another, do not resize separate body parts independently, and do not alter head-to-body scale from cell to cell.

Preserve exactly one gray field mouse with exactly two ears total: the near ear is pink and the single far ear is gray. Keep exactly two arms, two legs, and one pink tail. Preserve the same blue rolled-sleeve shirt, orange safety vest with both silver reflective bands, brown belt and pouches, navy trousers with the pocket on the near leg, brown work boots, and one black rectangular case held in the same far hand in all eight poses. Keep the west profile, facing screen-left. Do not mirror the character, switch the case hand, duplicate the case, add props, or invent extra anatomy. Let only the free near arm counter-swing naturally; keep the far-hand case near the hip and visible to screen-right of the body.

Image 3 is only a guide to the lower-body role sequence. Ignore its old body scale and upper-body proportions, and do not repeat its duplicated contacts or same-leg knee lifts. Draw these eight distinct phases in this exact row-major order:

1. Contact: near leg with the cargo pocket leads left and plants; far/plain leg trails right.
2. Weight-down: near/pocketed leg accepts weight beneath the pelvis; far/plain trailing heel begins to release.
3. Passing: far/plain leg passes compactly beneath the pelvis; near/pocketed leg remains the planted support.
4. Knee-up: far/plain leg bends and lifts forward toward screen-left; near/pocketed leg supports.
5. Opposite contact: far/plain leg leads left and plants; near/pocketed leg trails right. Match Image 1's corrected K5 lead-leg relationship.
6. Weight-down: far/plain leg accepts weight beneath the pelvis; near/pocketed trailing heel begins to release.
7. Passing: near/pocketed leg passes compactly beneath the pelvis; far/plain leg remains the planted support.
8. Opposite knee-up: near/pocketed leg bends and lifts forward toward screen-left; far/plain leg supports. This must be the opposite-leg counterpart of phase 4.

Give every phase a clearly different, readable lower-body pose while preserving the same head, torso, clothing, and equipment proportions. Keep planted support boots near one shared ground line. The pink tail stays on the same side and flows to screen-right. Use the same crisp illustrated style, outline weight, texture, color, and lighting as the primary reference. Return a transparent RGBA sprite sheet, not a scene or a collection of separate images.

## Generation result

ImageGen returned one RGBA PNG at `C:\Users\johnw\.codex\generated_images\01a17bff-cf8e-7f63-8e8d-221432232467\exec-a9a38e7a-ccc3-4aa2-9fa3-25267e5f7aa9.png`. The original generated file remains in place and was copied byte-for-byte to `assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/canonical-8phase-v3-proportion-consistent/field-mouse-technician-west-canonical-8phase-v3-imagegen.png` (SHA-256 `5465fe188fea59a8d9484f27b738a9078dcb77eb0b0724b96ce53a41dbce5ef5`, `1774x887` RGBA). The result was stored and displayed via `generatedImage(result)`; no `.content` parsing or output-folder scan was used.

Derived review assets, built without editing the raw generation:

- Raw owner contact sheet: `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/field-mouse-technician-west-canonical-8phase-v3-raw-owner-review.png` (SHA-256 `af17c82127f376583932d2d90a26203453e1d30903d31a16e2bbd5add366946d`).
- Uniform-head/rigid-ground registered contact sheet: `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/field-mouse-technician-west-canonical-8phase-v3-uniform-head-contact-sheet.png` (SHA-256 `8ab235fe416d0a5143d9ce3dda83e6ce773f6720b1a5648ce4e89c6ac4f4389d`).
- Shared-head comparison against approved idle: `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/field-mouse-technician-west-v3-vs-idle-shared-head-scale.png` (SHA-256 `9094f187ee5c177303c30452380dc27f7a82b01859eafd91e38552c5d0d187ea`).
- 64-world-pixel preview: `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/field-mouse-technician-west-v3-vs-idle-64-world-px.png` (SHA-256 `ad4704441501a4b7487aa3bca858a45dd4f3fd8b5cdb868a2b34481f27459c6f`).
- Fixed-idle-scale 64wu comparison: `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/field-mouse-technician-west-v3-vs-idle-fixed-idle-64-world-scale.png` (SHA-256 `46fb8e156cfae50c7b59d5896ecf5e19bb5cfcf894d551357b3dc89f24f045c8`). It applies the approved idle's `64/192` scale to every idle and walk cell; there is no walk-specific normalization, so heads remain at 31.33–31.67wu.
- Metrics and reproducible isolated review script: `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/canonical-walk-v3-review-metrics.json` and `build_canonical_walk_v3_review.py`.

## Review gate

Review all eight source cells against the owner map above. Check two opposite lead contacts (1/5), alternating support/weight-down (2/6), opposite pass-under poses (3/7), and opposite knee-up legs (4/8). Check that all eight share one head/vest/trouser scale, the same two-ear identity, case-in-far-hand, vest reflectors, near trouser pocket, and pink tail. Register using one uniform scale for the whole atlas plus rigid torso-axis/ground translations; do not fit or resize individual cells. Compare at matched head scale and at one action-level 64-world-pixel scale. Any missed role, anatomy error, clipping, or scale mismatch is a reported defect; no retry or runtime installation is authorized in this batch.

## Visual and metric audit

The raw 4x2 master contains eight distinct readable walking poses. The two lead contacts at K1/K5 visibly alternate; K2/K6 show opposite weight-down with heel release; K4/K8 appear to raise opposite legs. K3/K7 read as compact, opposite-leg pass-through poses, though the under-pelvis crossing is less pronounced than the contact and knee-up roles. Each cell visually retains exactly two ears (one pink near ear and one gray far ear), two arms, two legs, one pink tail, the black case in the same far hand, the orange vest and both reflective bands, blue shirt, brown belt/pouches, navy trousers and near-leg pocket, and brown boots. No duplicated anatomy, mirrored outfit, floor, or shadow was seen.

The candidate has an **open body-proportion finding for root review**. At one shared broad-head target (94.5px), generated registered cell visible heights are `177, 179, 180, 180, 177, 178, 178, 178px`; head widths are `94, 94, 94, 95, 94, 95, 95, 95px`; central vest spans are `43, 45, 43, 45, 42, 44, 43, 44px`. The new K5 primary reference measures 187px total height and 48px vest span; approved idle measures 191–192px and 49px. The generated set is internally close in size, but it shortens the body by 7–10px and vest by 3–6px at the same head scale. Trouser-onset-to-ground proxies are 65–69px, compared with 68px for the K5 proportion reference and 76px for idle. Root will judge whether the shortened silhouette reads as natural gait crouch enough to help west coverage while keeping the vest-size mismatch open.

At 64wu **per-action** normalization, the generated walk maximum is 180px versus idle's 192px, giving walk head widths of 33.42–33.78wu against idle's 31.33–31.67wu: a visible head-size pop. The fixed-idle-scale sheet applies `64/192` to every walk frame instead; it preserves the 31.33–31.67wu head size and shows body heights of 59.0–60.0wu versus idle's ~64wu. The source cell foreground does not touch the overall atlas bounds at alpha>=16, but the right boundaries of raw K5/K6/K7 cells contain 5/6/7 alpha>=16 pixels respectively; these appear to be tail-tip pixels tapering into the cell boundary. Treat those three tail margins as a border/clipping risk, not confirmed clean padding.

This is the only generation authorized for this batch. Preserve it and its review evidence as an unapproved candidate; do not retry, promote, or runtime-register it.

## Fixed-idle-scale transition audit

The fixed-scale GIF builder is `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/build_transition_gifs.py`. Both previews use the approved idle scale `64/192` for every idle and walk frame, a single rigid torso-axis/ground anchor, a 256x256 review canvas at 2x display zoom, and the sequence `idle W1, idle W2, K1–K8, idle W1, idle W2` (12 frames total).

- Nominal gait preview at 170ms per pose: `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/field-mouse-west-idle-walk-idle-fixed-idle-scale-170ms.gif` (SHA-256 `4fd0e1d2bccd12a8ee970fc7febe72d0236e9e614245cabdabaf3d2b57a6b504`). 170ms is the nearest 10ms GIF duration to nominal 167ms.
- Half-speed preview at 330ms per pose: `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/field-mouse-west-idle-walk-idle-fixed-idle-scale-330ms.gif` (SHA-256 `5bd9467fd54b6100a4efd6a6037d0ae0b3b45e8a3dddfb2db496229ee9d1f69d`).
- Sequence and duration verification: `output/animation-overhaul/luna-worker-actions/mouse-west/canonical-8phase-v3-proportion-consistent/transition-gif-review-metrics.json`. Both files were checked to contain 12 frames with uniform 170ms and 330ms durations respectively.

Phase/anatomy audit: K1 is near/pocketed-leg lead with far/plain trail; K5 reverses that lead. K2 and K6 show the matching support-leg weight-down with the opposite heel releasing. K3 and K7 show the compact pass-through on opposite legs; the crossing is compact but remains visually readable in the review sheet. K4 lifts the far/plain leg forward, while K8 lifts the near/pocketed leg. Every cell shows two ears, two arms, two legs, one tail, and the same far-hand case/outfit. Root's latest review found the phase owners useful and internally consistent and will assess possible partial use after a review-only render using fixed height 192. Vest shortening and the three tail-tip boundary flags remain open; no full-cycle approval is claimed.
