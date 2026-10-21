# Android installation readiness — October 20, 2026

**Android 57 is ready for private installation and device testing. Physical
phone/tablet acceptance remains pending.** No authorized Android device was
connected during packaging. The installation follow-up below records the later
device installation and requested test-data reset.

## Connected-device installation follow-up

On October 20, Android 57 was installed successfully on the connected Samsung
SM-S938U. The installed package reports version code 57 and version name
`0.1.0-android.57`. Only `com.thepictureshop.game` app data was cleared, honoring
the user's fresh-test-save choice. The app launched, emitted its startup-complete
marker with no detected startup errors, and remained running after startup.
The app was left open. Full touch/gameplay/multiplayer acceptance is still pending.
Evidence: `output/android-share/0.1.0-android.57/device-install-report.json`.

## Installer

- Version: `0.1.0-android.57`, version code 57.
- Application ID: `com.thepictureshop.game`.
- Installer: `output/android-share/0.1.0-android.57/ThePictureShop-0.1.0-android.57-Install.apk`.
- Size: 440,906,462 bytes (420.5 MiB).
- SHA-256: `e245bce325737b4b9e6565ab6dbe0e3b370951f1ab0f056164856591c30bc443`.
- Private development signing certificate matches the previous local APK.
- Includes ARM32, ARM64 and x86-64 native libraries; 16 KB APK/ARM64 ELF alignment checks passed.
- Built from the current working tree, including existing uncommitted game changes.
  It is not a clean-source public/store release.
- This APK has not been published to GitHub. Copy it to the devices or use the
  project's OneDrive folder once it has synced.

## Verification

| Check | Result |
| --- | --- |
| Desktop gameplay suite | 6,074 passing checks, including three rendered frames |
| Packaged mobile gameplay suite | 6,073 passing checks, including three rendered frames |
| Asset audit | 593 passing checks |
| Packaging, reproducibility and Lua-limit tooling | 21 passing tests |
| Native cache regression | Matching cache retained; old-drive/corrupt cache removed; absent cache accepted; compiled objects retained |
| Runtime inventory and contents | All 1,089 archive files verified against expected source or generated build metadata |
| Actual APK | Signature, application identity/version, permissions, native library hashes, gateway bridge and embedded game checksum passed |
| Installer copy | SHA-256 matches the verified APK |

The mobile suite runs the packaged game on the desktop with mobile controls
enabled. It covers touch gestures, pinch/zoom, keyboard focus, controls, lifecycle,
saving and multiplayer logic, but does not establish performance or touch quality
on real phones/tablets.

The first APK attempt exposed Gradle metadata containing an obsolete `N:` build
path after the wrapper was mounted at `M:`. The Android builder now detects this
condition and clears only its generated native configuration cache, retaining
compiled objects. Targeted regression checks passed, and the subsequent complete
APK build passed the previously failing step. Android 56 was an unsuccessful
intermediate build; distribute Android 57.

Evidence is preserved beside the installer: `readiness-report.json` (including
per-file SHA-256 values), `share-report.json`, `apk-report.json`, `build-report.json`,
both smoke reports, asset/tooling reports, `SHA256SUMS.txt`, and `READ-ME.txt`.

## Install with fresh test saves

The user chose to wipe this game's test saves for mobile testing. On each device:

1. Download/copy the Android 57 APK first.
2. Uninstall only **The Picture Shop**, declining any option to keep its app data.
3. Open the APK in Downloads/My Files, allow that source to install apps if asked,
   and complete installation.
4. Open The Picture Shop and create a new shop.

Installing over the old app instead preserves its saves. No separate LÖVE app is
needed. Other games, desktop saves and existing backups were not changed.

## Remaining physical acceptance

- Fresh install reaches the title/save slots and starts a shop on a phone and tablet.
- Check both landscape orientations, joystick plus simultaneous action touches,
  machine controls, text keyboard, pinch/zoom, and small/large screen layouts.
- Background/resume releases held controls; close/reopen restores saved progress.
- Check offline play and a 15-minute session for performance, audio and stability.
- For Local Play, use matching current protocol 40 builds on all participants;
  verify host/join, shared machine work, disconnect/rejoin and save reload.

Internet Direct Play remains gated in the normal game. This build does not claim
remote internet multiplayer acceptance. Historical device results from older APKs
do not count as acceptance of Android 57.
