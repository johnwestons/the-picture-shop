# Mouse west K5 contact correction, v1

Status: one generated correction candidate staged for parent review; no retry authorized or made. This does not approve the full gait cycle or runtime use.

## Exact prompt

```text
Make ONE constrained full-character sprite edit, using reference image 1 as the authoritative artwork to edit. Return a single mouse sprite on a transparent square canvas, not a sheet. This is canonical west-facing walk frame K5, the opposite contact from K1. Keep the exact established gray field-mouse technician identity, west-facing camera and nose to screen-left, head and torso proportions, vest/belt, colors, white outlines, lighting, pose scale and overall body axis from reference 1. Preserve exactly two anatomical ears total: the visible near ear is pink and the far ear is gray; do not add an ear or detached ear-like mark. Preserve exactly two arms, two legs, one pink tail, and the same single black hard case held by the same anatomical RIGHT/FAR hand on screen-right behind the hip. Do not mirror the image or swap the case hand/side. The only major pose changes are the legs and free near arm: make the un-pocketed FAR/RIGHT leg the forward planted contact leg, extending ahead toward screen-left with its boot sole flat on the ground; make the pocketed NEAR/LEFT leg trail behind toward screen-right, clearly un-pocketed far thigh leading and cargo-pocket near thigh trailing. Keep the pants pocket attached to the trailing near leg. Swing the near/free LEFT arm forward toward screen-left to counterbalance the far leg, while the far/right case arm continues holding the same case. Keep both boots at the same common ground height and do not change whole-character scale or torso/head/body proportions. Use reference 2 only to confirm the correct two-ear west identity and outfit. Use reference 3 only as a directional gait cue: K5 contact is the opposite-leg contact to K1. Do not copy any labels or markings. No floor, shadow, checkerboard, props other than the existing black case, text, or annotations. Maintain transparent background and clean complete silhouette.
```

## Input references and roles

| Order | Path | Role | SHA-256 |
|---|---|---|---|
| 1 | `output/animation-overhaul/luna-worker-actions/mouse-west/contact5-correction-v1/field-mouse-worker-k1-contact1-full-character-edit-target.png` | Sole artwork to edit: extracted K1 full-body contact pose, preserving its pose scale and outfit/case identity | `41ca9432535a9f1954a80389cedd1202cbb96b6d7dd2f1f93a020c48358905d1` |
| 2 | `assets/source/technician-motion-v2/references/mouse-west.png` | Corrected two-ear west identity and outfit reference | `b6f0a9f39aa0f908bffe70b3b4b939343850c7c54432c7ff35bfc3aaa97cc239` |
| 3 | `assets/source/technician-motion-v2/references/guide-west.png` | West gait-direction cue only; no guide markings copied | `21b1866fa702fb0b96c8cb5c6cf4bc232970aa7c881f29f06f1377ab09566825` |

The older `mouse-west-right-swing.png` was intentionally excluded because it contains an extra-ear failure.

## Output

- Raw output: `field-mouse-worker-k5-opposite-contact-v1-imagegen.png`
- Generation output ID: `exec-aa09b69b-5e3a-4be1-9ffe-d6116d0b2df6.png`
- Raw SHA-256: `fc586fcab55a59d139f3309fa4850d2d139bf974045875ec4aa0bfd81a2f5451`
- Raw size: 1254×1254 RGBA, unchanged from ImageGen.
- First visual audit: two ears (near pink, far gray), two arms, two legs, one pink tail, and one black case are present. The far/un-pocketed leg leads screen-left, the near/pocketed leg trails screen-right, the near arm swings forward, and the case remains behind the screen-right hip. This is an agent visual audit, not parent acceptance.

No machine/game or save files were touched.
