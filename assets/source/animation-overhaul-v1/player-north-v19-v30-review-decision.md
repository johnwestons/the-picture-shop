# Player North studies V19–V30 — review decision

Reviewed October 27, 2026 against installed V7 and the current runtime clock. `Animation.frameForGait` advances poses uniformly every 20 units of actual travel. The 512px reference art therefore needs 107.29 source pixels of sole travel per pose; phases 1→3 and 5→7 each span two pose intervals and need 214.58px cumulative travel. A proposed nonuniform key-spacing model used in earlier study metrics was not applied to the runtime and was not a valid acceptance target. Metrics and checker target lines for V19–V30 have been corrected to the installed uniform clock. The cross-view baseline remains coherent: all five walk directions are 408–412px tall, with no evidence for a global body-size or outline-weight correction. Keep their directional silhouettes as the model reference. None of these single-pose studies is accepted for runtime; V7 stays installed.

| Study | Support-sole travel | Proportion / edge review | Decision |
| --- | --- | --- | --- |
| V19 phase 6 | 34px / 107.29px target | Torso/head 0.9604; no detected colored edge pixels | Reject: 73.29px short |
| V20 phase 6 | 39px / 107.29px target | Torso/head 0.9906; no detected colored edge pixels | Reject: 68.29px short |
| V21 phase 6 | 48px / 107.29px target | Torso/head 0.9816; no detected colored edge pixels | Reject: 59.29px short |
| V22 phase 6 | 60px / 107.29px target | Torso/head 0.9745; no detected colored edge pixels | Reject: 47.29px short |
| V23 phase 6 | 73px / 107.29px target | Support boot is 27.96% wider; arms and pouch also read broader | Reject: 34.29px short and body/style mismatch |
| V24 phase 7 | 65px / 214.58px cumulative target | Support boot is 27.12% wider; visually moves upward from V23 rather than continuing its path | Reject: 149.58px short and discontinuous support track |
| V25 phase 7 | 12px / 214.58px cumulative target | Torso/head 0.9493; red, green and cyan fringe is present at low alpha | Reject: 202.58px short, proportions and edge quality fail |
| V26 phase 7 | 62px / 214.58px cumulative target | Torso/head 0.9745; support boot is 17.15% wider; no detected colored edge pixels | Reject: 152.58px short and oversized boot |
| V27 phase 7 | 66px / 214.58px cumulative target | Support boot is 3.28% narrower; no detected colored edge pixels | Reject: 148.58px short |
| V28 phase 7 | 66px / 214.58px cumulative target | Torso/head 0.986; support boot is 0.2% narrower; no detected colored edge pixels | Reject: 148.58px short |
| V29 phase 7 | 60px / 214.58px cumulative target | Torso/head 0.997; boot is within 1% of V7 width; low-alpha red/cyan fringe; output canvas is 887x1774 | Reject: 154.58px short, fringe and nonstandard canvas |
| V30 phase 3 | 109px / 214.58px cumulative target | Torso/head 0.997; support boot is 26.33% narrower; low-alpha colored fringe | Reject: 105.58px short; generator produced a left-support pose instead of requested phase 7 |

Passing poses are screened against cumulative travel over two intervals; full acceptance still requires each adjacent phase to remain within the 18px per-interval tolerance. At the proposed half-resolution 256x384 atlas size, the corresponding per-pose target is 53.65px and phase-1-to-3 / phase-5-to-7 target is 107.29px. V29 shows that a taller input canvas alone did not solve phase-7 leg reach or low-alpha edge fringe. V30 produced a more extended left-support pose, but reached only half the required displacement and narrowed the boot. The candidate images, prompts and corrected checker metrics remain in their numbered attempt/review folders. The next art task is a proportion-matched phase-2/3 and phase-6/7 pair with enough vertical room to preserve V7 head/body scale and the full support-leg reach, then toe-off keys. Review the complete eight-key loop at game speed before adding any in-betweens.
