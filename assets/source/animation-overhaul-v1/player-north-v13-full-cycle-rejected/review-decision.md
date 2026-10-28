# North V13 complete-cycle study — rejected

Decision: **reject; do not install**. Image generation returned a realistic, bare rabbit in side view instead of the orange rabbit worker in rear view. It omitted the overalls, pouch, tools and V7 outline style. The output also has strong red/yellow edge halos and did not provide the requested taller frame layout.

The raw output is 1774x887 RGBA (generation `exec-2e8a46a0-e96a-4634-a30c-45dc96ad1aae.png`; SHA-256 `89681C08630F31D034B1BDFE0D235E39B0DB474DFD7BDAA48F1AC73387866D69`). The exact prompt SHA-256 is `41C5A837F75BA8B24D6356407B1D93E23E063F9B45942BCEF222A0F49FB1D87C`. Visual inspection shows the identity and direction mismatch; transparency counters also show extensive partial-alpha pixels. The generated strip is retained for audit only. No cells were cropped, rescaled or integrated.

The exact prompt is in `exact-prompt.txt`. The attempt reinforces that full-cycle generation from the strip alone is not a dependable way to preserve the worker's identity or transparent edges. Continue to use the measured V7 body/outline reference and review one canonical pose set before generating in-betweens.
