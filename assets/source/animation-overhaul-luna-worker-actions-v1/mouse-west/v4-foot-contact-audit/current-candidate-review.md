# West mouse V4 candidate review

Status: review-only; no runtime promotion. No source art was corrected in this pass because the principal failure is pose geometry, not crop registration.

## Candidate and references

- Frozen V4 strip: `../canonical-8phase-v4-empty-gap-registration/field-mouse-technician-west-canonical-8phase-v4-gap-registered-8x1.png`, SHA-256 `55cb2cd186b169dc9ae5acc6814b40a3ca6ad6a7207c8456b9a1e7244b21992c`.
- Raw ImageGen master: 1774×887 RGBA, SHA-256 `5465fe188fea59a8d9484f27b738a9078dcb77eb0b0724b96ce53a41dbce5ef5`.
- Registration uses one whole-master scale of `27/56`, body axis x=128, sole baseline y=229, and common 64/192 display scale. The candidate retains its frozen per-phase crop and translation metadata.
- Source prompt, reference roles and generation record remain in the linked V3 record. No new image was generated in this audit.

## Gait and proportions

The contact/passing/knee-up owners read as intended in the full cycle: K1/K5 alternate lead legs, K2/K6 transfer support, K3/K7 are compact passing poses, and K4/K8 lift opposite legs. K6 remains a soft weight-down pose and may read as a heel-lift/pass; keep that semantic concern open. Contact confidence is lower at K5 and K7 because their support-sole pixels are sparse or overlap the other foot.

At fixed registration, support sole x positions are K1–K4 `[103.5, 112.5, 121.5, 130.5]` and K5–K8 `[105.5, 118.5, 141.5, 132.5]` cell pixels. The near support advances only +3 world pixels per phase, while a planted foot on the westward 13-world-pixel-per-phase walk needs about +13 local pixels per phase. That leaves roughly 10 pixels of foot slide per phase. Far support is irregular: +4.33, +7.67, then −3 world pixels per phase, with K5/K7 measurements low confidence.

Body and vest scale remain short compared with the approved idle at the same head width. The head stays 94–95px wide, while the walk body is 176–180px high versus 191–192px for idle; the orange vest measures 42–45px versus 48px. Some total body-height reduction is natural gait crouch, but it does not explain the shorter vest.

No deterministic rigid translation can fix the support path while holding the torso axis and common scale: moving each frame enough to plant the foot would shift the body axis. Correcting the feet requires changing the pose art itself. The prior one-shot correction attempt is separately preserved and rejected: it returned an RGB checkerboard with no transparency and still missed the path by large margins. Therefore this West set remains rejected for runtime use pending a new viable art source.

## Transparency and fringe review

The registered strip is RGBA and contains no baked checkerboard. Every phase has zero alpha≥16 on all four canvas edges. A full-cycle 2× contact review composited each frame over dark, white, cyan, and magenta backgrounds; no detached red or checker fringe is visible. The source does have 398 omitted alpha-1 pixels outside the rendered content crops. They are documented faint residue, not clipped paws, body, ears, or tail; at game scale they are effectively imperceptible. The crop-boundary trace and connected-component evidence remain in `v4-contact-and-proportion-audit.json`.

## New review artifacts

- High-contrast full-cycle sheet: `output/animation-overhaul/luna-worker-actions/mouse-west/v4-foot-contact-audit/field-mouse-west-v4-contrast-alpha-edge-review.png`, SHA-256 `b41d4b04a4ac99009eb2efbae19c380c352e425cf42ae0294807b8174ad6338a`.
- Combined alpha, gait, support-anchor, and body-proportion evidence: `output/animation-overhaul/luna-worker-actions/mouse-west/v4-foot-contact-audit/v4-transparency-edge-and-gait-audit.json`, SHA-256 `e77e4148b42cd727066b046db5a232bb857e6990bbab81c67adc2ae8f5447517`.
- Reproduction: run `audit_v4_transparency_edges.py` with the bundled Python runtime. It reads the frozen strip and prior source-owned audit JSON; it does not modify either.
