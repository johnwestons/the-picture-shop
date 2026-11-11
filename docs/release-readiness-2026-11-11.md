# Release readiness review — November 11, 2026

## Current result

The release 106 candidate passes the complete automated gameplay plan: 41 of 41 stages and all 48 feature groups passed, with 41,908 checks total. The desktop and mobile core stages each passed 11,853 checks. The report confirms the Lua source and smoke tooling stayed unchanged throughout the run.

- Full run: `output/release-validation/gameplay-20261111/summary.txt`
- Machine-readable results: `output/release-validation/gameplay-20261111/summary.json`
- Engine smoke: `.stabilization/smoke-report.rpt` — 2,483 checks, no failures.
- Tooling regression suite: `output/release-validation/tooling-tests-localtmp.log` — 107 tests passed.
- Asset audit: `output/release-validation/asset-audit-localtmp.json` — 593 checks, no failures.
- Lua limits audit: `output/release-validation/lua-limits.json` — 1,124 Lua files and 14,403 compiled functions within the 180-slot/45-upvalue limits.
- Audio source verification: 9 licensed sources verified.
- `git diff --check` found no whitespace errors.

## Release 106 changes covered

- Vehicles now retain continuous steering headings between available truck sprites. Fine steering corrections settle smoothly, and the kei truck resists small steering noise on straight roads.
- Truck ownership, route travel, collision handling, delivery, and multiplayer snapshots have focused coverage.
- Warehouse restoration includes generated dirt and oily water patches, cleaned floor regions, and distinct fading wet/dry footprints. The restoration gate covers utilities, the breaker, paint, and machine service.
- Story mode grants Grandpa's one-time $420 allowance on top of the $180 starting balance. It grants money only; it does not grant service kits.
- The skippable 12.8-second grand-opening sequence reveals the restored shop, raises the banner, flips the door sign, and unlocks customer and job channels only after the final OPEN card.
- Campaign arrival, Grandpa's handoff, and free travel are covered on desktop and mobile layouts.

## Distribution status

The user authorized an Android test prerelease after automated validation. Its game source was committed as `1ec759ce82f80fb41663fac814e2ac939e7144dd` and was clean when packaged; the later branch commit only records validation results. The APK passed package ID, signature, and 16 KB alignment verification:

- APK: `output/mobile/ThePictureShop-0.1.0-android.106-debug.apk` — 1,020,427,280 bytes.
- SHA-256: `cea20a3fce1fbc2df7b3e9b9da1336b58b35966e2b1c5e9e2f4f99049b231979`.
- Build report: `output/mobile/apk-report.json`.

The Android 106 APK is being published as a GitHub test prerelease at https://github.com/johnwestons/the-picture-shop/releases/tag/0.1.0-android.106. The ADB server started, but no Android devices were attached, so no physical-device installation or run was performed. The prerelease is for testing and does not claim physical-device validation or production readiness. It contains the Android APK only; no Windows 106 build is included.

The Android package is development-signed. Remote users must install a matching version because multiplayer protocol 75 is incompatible with protocol 74/version 105.
