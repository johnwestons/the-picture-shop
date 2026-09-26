# Two-cutter device acceptance — September 26, 2026

Build: Android debug APK from `2d26aaa` (`codex/progress-audit-integration`), SHA-256 `2193942c18096efe16e7e27e619a335b4203ebb7f61ab5afcc30665b527dae02`.

Two Android phones joined one LAN shop: the S25 Ultra hosted and the J4 joined as a guest. A disposable host test save provided two installed Polar 115 cutters and two separate 500-sheet paper jobs. The host operated `MCH-0003`; the guest operated `MCH-0001`.

Both cutter consoles were open at the same time. Each player changed that cutter's safety barrier without changing the other cutter. Each loaded only its own nearby job, then independently rotated, set the gauge, positioned, clamped, and ran all four cuts. Both jobs reached 10 × 8 inches with no sheets remaining. The players unloaded separate finished pallets; the host save recorded `finishedPallets = 2`. Closing and reopening each console selected the same physical cutter and retained its result. The warehouse showed both cutters and both output pallets.

This pass covers concurrent use of two same-type cutters, per-unit commands and wear, job selection, cut completion, output placement, and in-session console reopening. It does not establish physical-device acceptance for duplicate wrappers or Windmills, disconnect/reconnect during production, or a full app restart from this save. The automated multi-machine suite covers additional per-unit lease and command paths.

Only the game's disposable host slot 1 was replaced for this test. Other host slots and the guest's game saves were not reset.
