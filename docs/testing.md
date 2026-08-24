# Test layout

The hidden LÖVE smoke run uses the isolated `the-picture-shop-smoke` save identity. It never reads or writes the player's normal save directory.

## Layers

- `src/smoke.lua` owns reporting, the final three-frame render gate, and shared engine integration setup.
- `src/tests/asset_pack_test.lua` checks PNG header contracts, precomputed anchors, and pack loading/release.
- `src/tests/pallet_state_test.lua` checks legal ownership transitions without rendering.
- `src/tests/save_contract_test.lua` checks exact defaults, nested validation, and a focused round trip.
- `src/tests/input_status_test.lua` checks Back/Escape parity and office projections.
- `src/tests/job_loop_integration_test.lua` owns the accept-to-payment end-to-end workflow.
- `src/tests/cutter_integration_test.lua` owns guarded cutting, multi-lift production, physical staging, safe output, and pallet ownership scenarios.
- `src/tests/save_integration_test.lua` owns migration, recovery, validation, and all-slot scenarios.
- `src/tests/ui_integration_test.lua` owns title controls and the live mouse/keyboard warehouse journey.
- `src/tests/audit_coverage.lua` maps every fixed P0, P1, and P2 audit finding to required named checks. The run fails if a mapped regression disappears or is renamed without updating the manifest.

## Gates

Run `RUN_SMOKE_TEST.bat` for domain, integration, audit-coverage, and three-frame render checks. Run `python tools/asset_doctor.py --report output/asset-audit.json` for full raster decoding, alpha, dimension, grid, and nonempty-cell checks.

Every new bug fix should add the smallest deterministic domain check possible. Add an engine integration check only when the behavior depends on LÖVE rendering, input routing, filesystem identity, scene transitions, or multiple live systems.
