# Multiplayer device pass — September 25, 2026

## Build and devices

- Normal Android game APK `0.1.0-android.28`, built from clean shared source `26881ee22811b14b59b4a76786855fe9fbfbe781`; SHA-256 `b801cb86d7e30668eb064a2dc477aa4a13964bcda4b823f50daf3390a0f43897` (172,044,118 bytes). The same APK passed guarded in-place installation and launch on Samsung SM-J410G (Android 8.1) and SM-S938U (Android 16). Both had `.26` beforehand; all eight existing save fingerprints were unchanged by installation. See `output/mobile/device-tests/lan-acceptance-preflight.json` and `output/mobile/apk-report.json`.
- Disposable Windows host used the clean shared source and a copied fixture in an isolated `the-picture-shop-acceptance-*` save identity. Both phones joined it over the local router at `192.168.1.239:22122` using manual entry. Neither phone discovered the host through this router's broadcast path, as in earlier device passes.

## Observed on the two phones

- Both showed **LAN GUEST / 3/4 WORKERS** and the same host shop. Simultaneous joystick input moved the two guest workers to different positions, visible on both screens. Screens: `output/mobile/device-tests/screens/20260925-{small,large}-simultaneous-move.png`.
- The J4 opened the Windmill console while the S25 Ultra opened the Polar cutter console. The J4 started the Windmill motor; the S25 Ultra changed the cutter backgauge with **AUTO SET**. Both actions completed on their respective host-owned screens without one guest closing the other's GUI. Screens: `20260925-{small,large}-parallel-action.png`.
- When the S25 Ultra held the cutter, the J4's attempt to open it returned **Another worker is using that resource**. After the J4 acquired the cutter and its app was force-closed, the S25 Ultra opened the same loaded cutter successfully. The J4 then relaunched and manually rejoined a 3/4-worker roster. Screens: `20260925-small-cutter-busy.png`, `20260925-small-cutter-acquired.png`, `20260925-large-cutter-takeover.png`, `20260925-small-rejoined.png`.
- The J4 session panel fit its narrow display, marked the Windows process **HOST** and the phone **YOU**, and identified the other Android worker as controlling the Polar cutter. Screen: `20260925-small-session-panel.png`.

## Host computer screen with one phone

After the S25 Ultra was disconnected for the day, the guarded acceptance host was restarted with its computer screen open. This test-only host option was added after the `.28` APK build; ordinary game simulation code and protocol were unchanged. The J4 automatically rejoined the restarted host and moved while its computer screen remained open. The isolated host save advanced from March 30 to April 2 while on that screen, establishing that the calendar and host save kept progressing. The J4's two pre-existing save files still matched their post-install SHA-256 fingerprints after guest play. See `output/mobile/device-tests/acceptance-host/the-picture-shop-acceptance-20260925-155629509/` and `output/mobile/device-tests/screens/20260925-small-host-menu-world-progress.png`.

This is a **partial physical pass**, not the full multiplayer release gate. We did not confirm a specific truck delivery or visitor arrival during the host-menu run. The S25 Ultra was removed before its post-session save inventory could be checked. Still pending: simultaneous guest control of two machines of the same type (not supported yet), full cutter/press/truck transactions, Android-host topology, reconnect exhaustion and changed-address cases, a 15-minute continuous soak, and final offline host-save outcome checks. The Wi-Fi toggle on the S25 Ultra restored itself quickly, so it is not counted as a controlled network-outage result.
