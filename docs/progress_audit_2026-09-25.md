# Picture Shop progress audit — September 25, 2026

## Verified now

- The shared `main` baseline includes independent same-type machine runtime and the host-menu world-event fix. Its smoke suite passed 3,443 checks.
- The older local economy/credit work was merged with that baseline in an isolated checkout. The combined desktop smoke suite passed 3,457 checks, including save-v16 migration, online/dealer financing, same-type machine operation, and world events during host menus. No conflict markers or whitespace errors remain.
- The original local checkout also passed 3,455 smoke checks after a rack fallback repair. It remains four commits behind the prior shared baseline and has unpublished edits; do not treat that checkout as the release source.

## Findings and finish order

1. **P1 — World rack art fallback.** The draft `rack-world-left-v2.png` was connected to the live renderer while its registration was still `nil`. A completed storage bay therefore displayed `SHELF ART UNAVAILABLE` and hid the rack stock. The original local checkout now retains the playable registered rack until the new sprite has measured placement, ten pallet anchors, and foreground masks. Its regression check passes. Keep this art work separate from the release until a real rendered bay and stocked upper/lower shelves are visually checked.
2. **P1 — Guest control of additional machines.** The host can run multiple cutters, wrappers, or Windmills independently, but LAN/Direct guest control still addresses a machine type rather than a physical machine ID. Add per-instance resource IDs, host-side range and ownership checks, per-unit snapshots and commands, then test two workers running two same-type machines at once and surviving disconnect/reconnect.
3. **P1 — Physical multiplayer acceptance.** Automated session coverage is extensive, but the latest host-menu change and same-type machines have not had a real multi-device walkthrough. Run a PC host with two guests: hold the host in the computer/credit UI, let a truck and visitor arrive, operate independent machines, test control contention, disconnect recovery, and offline host-save reload. Record the exact build on all devices.
4. **P2 — Warehouse and forklift art.** Construction stages, world rack placement, mast/load occlusion, work-loop fringe, and the remaining room modules are still draft. Register and visually inspect each scene at the unchanged game scale before enabling further purchases. Keep unavailable choices blocked without charging money.
5. **P2 — Installer and tester release.** Rebuild PC/Android packages only after the integrated source and physical acceptance pass. Verify in-place update, fresh install, save behavior, and reproducible package contents. The existing device evidence predates these changes.

The job-estimating flow already has an estimating tab, emailed quotes, expiry/follow-ups, and automated coverage; it needs a focused playthrough before being described as release-complete. The credit flow is automated-complete in the combined build and still needs normal-device UI and save acceptance alongside the next multiplayer pass.
