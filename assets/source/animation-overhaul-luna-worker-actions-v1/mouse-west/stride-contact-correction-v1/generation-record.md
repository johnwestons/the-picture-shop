# West Mouse Stride Contact Correction V1

Status: **rejected review attempt; do not install or register**.

The authorized one-shot lower-body correction attempt did not satisfy the fixed support-foot travel, and the returned image has the checkerboard flattened into RGB pixels (no alpha channel). The raw output is preserved unchanged. It must not be treated as sprite art, cleaned into a production strip, or promoted. The full eight-pose West set remains rejected for runtime use.

## Generation provenance

- ImageGen result was awaited and stored as the complete result object. The result exposed `image_url` and `output_hint`; the generated image was surfaced with `generatedImage(result)`. No `.content` field was assumed.
- ImageGen output path: `C:\Users\johnw\.codex\generated_images\01a17bff-cf8e-7f63-8e8d-221432232467\exec-d1350ea0-fb7a-490b-8f13-16b0798425e8.png`.
- Preserved raw copy: `field-mouse-west-stride-contact-correction-v1-raw.png`.
- Raw dimensions/mode: 1774×887, RGB. The checkerboard is baked in; there is no alpha channel.
- Raw SHA-256: `65b7f15974d481c78cd95c0b0a2b819580100bfed103aaa9b17805fd5480c2d2`.
- Reference 1, V4 West walk proposal / phase and gear guide: `assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/canonical-8phase-v4-empty-gap-registration/field-mouse-technician-west-canonical-8phase-v4-gap-registered-8x1.png`, SHA-256 `55cb2cd186b169dc9ae5acc6814b40a3ca6ad6a7207c8456b9a1e7244b21992c`.
- Reference 2, explicit support-contact target guide: `field-mouse-west-v4-contact-target-guide-4x2.png`, SHA-256 `35d3b7d31b18d31ce20e630772e461123e91fe0a024d7636c8d442d6c0ee5236`.
- Reference 3, approved runtime West idle for mouse identity, proportions and styling: `assets/generated/technician-motion-v2/field-mouse-technician/idle_west.png`, SHA-256 `886efc1ad1bf57bedb3a1b98927b82135281b9d53599f080b592e37a979a0f66`.

## Exact prompt

```text
Make ONE new transparent-background sprite master as a bounded correction attempt to the West field-mouse walk in the references. Return a clean 4-column by 2-row atlas with eight square 512x512 pose cells (overall 2048x1024), no gutters between cells, no text, no labels, no grid lines, no target dots, no axes, no floor or shadow. All eight drawings must use the same whole-character scale; each 512px cell is exactly a 2x display of the 256px target guide, so after one uniform 1/2 scale and rigid translations every head should be about 94-95px wide at the review cell scale, torso center x=128 and planted-sole line y=229. Do not resize any pose or body part separately.

Reference roles: image 1 is the current eight-pose West mouse proposal and primary identity/gear/phase reference. Image 2 is the exact target-coordinate guide; ignore its blue/red guide lines and lettering in output, but obey the cyan sole target in each panel. Image 3 is the approved West idle and secondary authority for mouse anatomy, ear count, outfit, proportions, palette and outline style.

Preserve precisely one gray field mouse with exactly two ears total (one pink near ear and one gray far ear), exactly two arms, two legs, one pink tail, blue shirt, orange reflective vest with both silver bands, navy work trousers with one near-side thigh pocket, brown work boots, belt and pouches, and one black case held in the same far hand in all eight views. Keep the side-facing-west camera and facing direction. Keep head, torso, vest, arms, hands, case and tail at their same identity scale and position; articulate the lower body only. No mirroring, extra limbs, extra ears, ghost marks, floating feet, or changed gear.

The cyan sole centers in image 2 are exact 256-cell coordinates; all are on ground y=229. The target x values in order are K1=104, K2=143, K3=182, K4=221, K5=104, K6=143, K7=182, K8=221. Because output cells are 2x, place the boot sole centers at twice those local x values and y=458 in the 512px output cells. This is the required 13-world-pixel-per-phase path under the fixed 64/192 display scale: the near/pocketed support advances through K1-K4, then the far/plain support advances through K5-K8. Keep K1/K5 opposite lead contacts, K2/K6 opposite weight-down with only the trailing heel released, K3/K7 opposite compact passes, and K4/K8 opposite forward knee lifts. Each support boot must actually touch its cyan ground target; the non-support leg must remain visibly separate and anatomically plausible.

Maintain a natural body silhouette and realistic mouse-leg proportions. Do not lengthen or distort a leg to force a target if it cannot be reached from the fixed pelvis/torso; preserve the character and make the miss visible for review. This is one review candidate, not an installed asset.
```

## Fixed-registration contact audit

The generated image does not meet its requested 2048×1024 dimensions; its 1774×887 canvas divides into 443/444px cells. The audit uses one uniform whole-cell scale and rigid registration only: manually identified torso axis maps to x=128, one support-sole point maps vertically to y=229, with no per-cell resizing. Sole and torso-axis measurements are manual estimates (about ±4 canonical cell pixels); K3, K7 and K8 support-foot attribution is less certain because the legs overlap.

Explicit target x positions are `[104, 143, 182, 221, 104, 143, 182, 221]`. Measured support x positions after fixed-axis registration are approximately `[76.1, 93.3, 116.4, 128.0, 73.2, 94.5, 129.2, 132.0]`. Thus near support K1→K4 travels only 51.9 cell px against 117 required; far support K5→K8 travels only 58.8 against 117. The planted foot remains roughly 28–93 cell px left of target across the cycle. The pose cannot meet the 104-world-pixel stride while preserving the torso axis, scale and character proportions, so this set stays rejected.

The JSON contains the phase-by-phase target, manual support mark, confidence, registration and errors. The annotated sheet places each figure at the fixed torso axis and ground line; cyan circles mark targets, yellow crosses mark observed soles. The checkerboard remains visible as evidence of the invalid RGB result.

- Measurements: `output/animation-overhaul/luna-worker-actions/mouse-west/stride-contact-correction-v1/stride-correction-v1-foot-path-measurements.json` (SHA-256 `dd0f98370c946124a58c7133e3ec94a43c40a1700ab2dd431e09e89c649748a18`).
- Review sheet: `output/animation-overhaul/luna-worker-actions/mouse-west/stride-contact-correction-v1/stride-correction-v1-target-vs-sole-review.png` (SHA-256 `fc17e30ae5358418a9ba2e00bacba022d8dc20e5c7fd1f5eef097497c1e59009`).
- Reproducible audit script: `audit_stride_correction_v1.py`.

The anatomy visible in the invalid checkerboard result appears to retain two ears, two arms, two legs, one tail, the vest and the far-hand case. That observation does not override its rejected status or make the flattened background usable.
