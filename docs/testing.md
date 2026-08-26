# Test layout

The hidden LÖVE smoke run uses the isolated `the-picture-shop-smoke` save identity. It never reads or writes the player's normal save directory.

`RUN_SPRITE_MOTION_TEST.bat` uses that same isolated identity and smoke suite, then opens a visible motion lab. Use Left/Right to switch characters, Space to pause on a frame, and Esc to close. The upper row shows raw source-frame bounds; the lower row normalizes every visitor action to the player character's 256-pixel source height. This makes size mismatches, cropped cells, and frame-to-frame silhouette jumps visible without touching a player save.

## Layers

- `src/smoke.lua` owns reporting, the final three-frame render gate, and shared engine integration setup.
- `src/tests/asset_pack_test.lua` checks PNG header contracts, precomputed anchors, and pack loading/release.
- `src/tests/sound_test.lua` checks the complete audio catalog, physical-action transition cues, payment
  de-duplication, and ownership of persistent warehouse and press loops.
- `src/tests/pallet_state_test.lua` checks legal ownership transitions without rendering.
- `src/tests/save_contract_test.lua` checks exact defaults, nested validation, and a focused round trip.
- `src/tests/input_status_test.lua` checks Back/Escape parity and office projections.
- `src/tests/machine_fleet_test.lua` checks condition, maintenance, online machine-order reservation, dedicated
  flatbed scheduling, player unloading, ownership transfer, technician NPC completion, physical maintenance-kit
  consumption/despawn, and empty-truck release.
- `src/tests/job_loop_integration_test.lua` owns the accept-to-payment end-to-end workflow.
- `src/tests/cutter_integration_test.lua` owns guarded cutting, multi-lift production, physical staging, safe output, and pallet ownership scenarios.
- `src/tests/windmill_integration_test.lua` owns client-art verification, physical proof sheets, exact ordered-copy targets, spoilage allowance, multicolor pass state, wash-up, and press output.
- `src/tests/press_economics_test.lua` owns structured print orders, ordered-versus-supplied quoting, print-offer cadence, and repeat/promotion preservation.
- `src/tests/save_integration_test.lua` owns migration, recovery, validation, and all-slot scenarios.
- `src/tests/ui_integration_test.lua` owns title controls, cutter/wrapper/Windmill relocation, and the live
  mouse/keyboard warehouse journey. The core smoke suite also verifies delayed grouped supply manifests.
- `src/tests/audit_coverage.lua` maps every fixed P0, P1, and P2 audit finding to required named checks. The run fails if a mapped regression disappears or is renamed without updating the manifest.

## Gates

Run `RUN_SMOKE_TEST.bat` for domain, integration, audit-coverage, screen-pack transitions, and three-frame render checks. Run `python tools/asset_doctor.py --report output/asset-audit.json` for full raster decoding, alpha, dimension, 2x2 press-atlas grid, and nonempty-cell checks.

Before regenerating or releasing audio, run
`python tools/generate_sfx.py --verify-only`. It validates all nine licensed
source recordings against `assets/audio/source_manifest.json`; generation fails
before writing cues when a source is absent or has different bytes. Android
packages must contain `assets/audio/SOURCES.md` and the manifest, and must not
contain the generated audition reel.

Every new bug fix should add the smallest deterministic domain check possible. Add an engine integration check only when the behavior depends on LÖVE rendering, input routing, filesystem identity, scene transitions, or multiple live systems.
