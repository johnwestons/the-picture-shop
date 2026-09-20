# Test layout

The hidden LÖVE smoke run uses the isolated `the-picture-shop-smoke` save identity. It never reads or writes the player's normal save directory.

`RUN_SPRITE_MOTION_TEST.bat` uses that same isolated identity and smoke suite, then opens a visible motion lab. Use Left/Right to switch characters, Space to pause on a frame, and Esc to close. The upper row shows raw source-frame bounds; the lower row normalizes every visitor action to the player character's 256-pixel source height. This makes size mismatches, cropped cells, and frame-to-frame silhouette jumps visible without touching a player save.

## Layers

- `src/tests/guest_job_journey_test.lua` drives the shared guest computer, cutter, wrapper and truck
  GUIs through real Session transport and the application's production authority callbacks. It covers
  typed estimates and delayed acceptance, inbound stock, a deliberately spoiled 500-sheet lift and exact
  replacement, disconnect during a cut, fresh-lease recovery, wrapping, spoil-bill payment, pickup and
  final payment. Repeated clicks and application-level replays cannot duplicate the financial/stock
  outcomes. Host/guest totals converge and the completed state survives a serialized offline-load
  round trip. Intake, worker navigation and inbound dock/staging positions are fixtures; pickup uses
  the real world scheduler. The second scenario uses `src/tests/support/guest_print_production.lua`
  for a two-color job: cut 500 supplied sheets, make both plates through all four visible processing
  steps, complete all six setup games per color, proof/verify/approve, print, disconnect/reconnect during
  production, wash/unload, wait for drying, reload the second color, and deliver exactly 450 finished
  copies. Duplicate requests must not double-consume plate materials, proofs, ink, packing or wash.
  Installed equipment and starting supplies are fixtures; plate timing uses a fixed clock while the
  real host computes scores. Desktop and forced-mobile smoke each pass 2,285 checks, including the
  original 53 cutting-journey checks and 197 printing-journey checks. Neither is physical acceptance.
- `src/tests/network_protocol_test.lua` checks that every visible press-setup control encodes and
  decodes inside the existing packet ceiling. This catches stale network allowlists such as the old
  feeder actions that rejected FAN + LOAD and the separate suction/air adjustment buttons.
- `src/tests/shared_gui_test.lua` exercises the production `useHostLayout` guest route: all nine
  computer pages are pixel-compared with host instances; machine/service/press/phone/vendor/reception/
  truck pages render with their real asset packs. Visible controls send bounded intent without modifying
  guest stock, money, or paper. Preview PNGs named `gui-parity-*.png` are written only to the isolated
  smoke save directory. The earlier v16 GUI-only baseline passed 2,035 checks in each mode.
- `src/tests/office_phone_session_test.lua` uses the real Session and impairment harness: phone lease
  contention, answer/order/dismiss, duplicate delivery, stale call IDs, host range checks, cart prices,
  atomic failed checkout, bill payments, delayed email estimates, declines, service archiving and typed
  promotions. Forged prices/quantities and oversized/unknown intents are rejected. No physical devices
  or player saves are involved.
- `src/tests/cutter_presentation_test.lua` compares host/guest blade and paper-transfer frames using
  the same artwork, checks host-bound keyboard intent and invisible-hitbox regressions, validates
  interpolation across per-frame runtime revisions, and proves drawing cannot mutate the machine or
  mirrored ticket. It writes `cutter-guest-preview.png` and `cutter-guest-unloaded-preview.png` only in
  the isolated smoke save directory for visual review.
- `src/tests/cutter_production_session_test.lua` runs the real Session, workshop authority, remote
  controls and Machine together without device sockets. It covers loading through a completed cut,
  duplicated cut requests, next-program synchronization, stalled guest animation, an interrupted
  second cut, and actual spoiled geometry from an intentionally wrong cut. Protocol v15 validates
  the added dimension/spoil fields and keeps cutter messages inside the 1,200-byte ceiling.

- `src/smoke.lua` owns reporting, the final three-frame render gate, and shared engine integration setup.
- `src/tests/lan_discovery_test.lua`, `src/tests/lan_reconnect_test.lua`, and
  `src/tests/lan_reconnect_session_test.lua` cover bounded address-hint discovery, retry/backoff/cancel state,
  and a fresh authoritative session generation after disconnect.
- `tools/tests/test_lan_device_acceptance_preflight.py` keeps the physical-test installer in-place,
  save-preserving, exact-APK-bound, and unable to turn a launch request into implicit install authority.
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
- `src/tests/multiplayer_impairment_test.lua` runs one host and three clients through a deterministic,
  test-only packet lab. It covers unreliable loss, delayed reordering, duplication, malformed bursts larger
  than the 64-event frame budget, and peer-scoped failure without opening real sockets or changing protocol v14.
  Host intake defaults to `enet_round_robin`, matching ENet's peer dispatch and the Direct Composite link
  rotation while retaining FIFO order inside each peer. `adversarial_fifo` remains available for tests that
  explicitly need a transport with one global queue. Automatic malformed/forbidden replies share a one-second
  per-connection limit so an invalid burst cannot create a reliable response burst.
  Delay controls advance explicit packet-ordering steps; timeout tests must separately advance their injected
  Session clock. Reliable traffic remains ordered and cannot be dropped by this Session-layer lab.
- `src/tests/multiplayer_soak_test.lua` rotates nine disconnect/rejoin cycles across all three guest slots.
  Every cycle combines a full 64-packet malformed burst, quiet-peer liveness, delayed stale-generation input,
  a fresh connection, and healthy traffic from every worker. It also asserts bounded admission, rejection,
  transport-generation, and queued-packet state before requiring complete teardown.
- `src/tests/multiplayer_workshop_boundary_test.lua` uses the real workshop authority at exact lease deadlines.
  It proves the current owner's valid packet is handled before timeout evaluation during another guest's full
  malformed burst, then proves malformed, wrong-session, wrong-channel, and stale-generation packets cannot
  renew ownership or transfer liveness to a replacement connection.
- `src/tests/multiplayer_workshop_reliable_test.lua` drives reliable office commands through the real workshop
  authority. It proves application replays and delayed delivery mutate once in order, an in-flight ordinary
  command blocks a second command, and a command delayed behind disconnect cannot execute against a replacement
  worker that reuses the same network slot and player ID.
- `src/tests/cutter_maintenance_authority_test.lua` exercises the host-owned cutter-service state machine:
  ordered lockout/preparation, point/tool validation, gearbox work, production interlocks, exact-once kit use
  and saving, blade service, technician scheduling, contention, disconnect rollback, and bounded remote UI intent.
- `src/tests/cutter_maintenance_session_test.lua` carries cutter-service commands through the real Session and
  impairment transport. It verifies exact-once duplicated scheduling and an ordered preparation/view-selection
  round trip in which the guest sends only bounded control choices and the host owns the resulting state.
- `src/tests/wrapper_maintenance_authority_test.lua` covers the host-owned four-component service order,
  active-target validation, miss scoring, production and relocation interlocks, exact-once kit use and saving,
  cancellation/disconnect rollback, strict packets, and the Guest Worker service controls.
- `src/tests/wrapper_maintenance_session_test.lua` completes the same service through a real impaired Session,
  duplicating a miss and the final target to prove bounded intent and exactly one durable host result.
- `src/tests/machine_relocation_authority_test.lua` drives the cutter, skid wrapper, and Windmill through
  guest-owned attachment, host motion, rotation, bounded grid placement, contention, invalid intent,
  exact-once replay, and disconnect recovery.
- `src/tests/machine_relocation_session_test.lua` carries relocation through a real impaired Session and
  proves duplicated attach/place requests save once without transmitting client coordinates.

## Gates

Run `RUN_SMOKE_TEST.bat` for domain, integration, audit-coverage, screen-pack transitions, and three-frame render checks. Run `python tools/asset_doctor.py --report output/asset-audit.json` for full raster decoding, alpha, dimension, 2x2 press-atlas grid, and nonempty-cell checks.

Before regenerating or releasing audio, run
`python tools/generate_sfx.py --verify-only`. It validates all nine licensed
source recordings against `assets/audio/source_manifest.json`; generation fails
before writing cues when a source is absent or has different bytes. Android
packages must contain `assets/audio/SOURCES.md` and the manifest, and must not
contain the generated audition reel.

## Unified release gate

`RELEASE.ps1` is the authoritative release entry point. It requires a clean
`main` branch synchronized with `origin/main`, runs all automated gates, builds
and smoke-tests the Android-ready `.love` package, validates its allowlisted
contents and provenance, and writes `output/release/release-report.json`.
`RELEASE.ps1 -BuildApk` adds APK construction plus signature, application-ID,
ZIP-alignment, and native-library alignment verification. Device installation
and human playtesting are intentionally retained as manual release gates.

The Android tester-release path also requires
`output/mobile/device-tests/guest-worker-physical-acceptance.json`. The report must bind the exact clean
source commit and APK hash to three or four unique phones, include an Android-host run and at least two
phone guests, record every required Guest Worker interaction/topology/recovery check with evidence, and
carry the physical-test operator's confirmation. `tools/verify_guest_worker_physical_acceptance.py` rejects
missing, incomplete, dirty-source, stale-artifact, two-phone, or engineering-probe reports. Both
`RELEASE.ps1 -BuildApk` and direct use of `tools/assemble_tester_release.ps1` run this verifier before any
tester-download directory is assembled.

Before the LAN device checklist, `tools/prepare_lan_device_acceptance.ps1` can inventory connected phones
without installing. Its explicit `-Install -Launch` mode verifies the exact APK report, upgrades at least two
selected phones in place, and compares the pre/post save manifest so installation cannot silently clear or
change an existing slot.

Every new bug fix should add the smallest deterministic domain check possible. Add an engine integration check only when the behavior depends on LÖVE rendering, input routing, filesystem identity, scene transitions, or multiple live systems.
