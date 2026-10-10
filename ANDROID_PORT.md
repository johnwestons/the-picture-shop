# The Picture Shop for Android

## Current source build

- Application ID: `com.thepictureshop.game`
- Version: `0.1.0-android.49` (`versionCode` 49)
- Multiplayer protocol: 36; host and guests need matching current code.
- Build command: `./BUILD_ANDROID.ps1`
- Local output: `output/mobile/ThePictureShop-0.1.0-android.49-debug.apk`
- Remote download: [Android 49 installer](https://github.com/johnwestons/the-picture-shop/releases/download/android.49/ThePictureShop-0.1.0-android.49-Install.apk)
- The development APK uses the same gameplay and art source as Windows, including
  warehouse staging controls, seasonal customer-demand tuning, updated pallet and
  supplies flow, performance improvements, and current gameplay and multiplayer changes.
- The package ID and signing certificate are kept compatible with the previous
  Android build, so installing over it preserves existing saves.
- A connected phone is required to verify installation and physical gameplay.

## Android 43 historical build notes

- Application ID: `com.thepictureshop.game`
- Version: `0.1.0-android.43` (`versionCode` 43)
- Engine: LÖVE 11.5
- Orientation: sensor landscape, fullscreen
- Native libraries: verified 16 KB page-size compatible for Android 15+ devices
- Saves: private Android app storage under the shared `the-picture-shop` LÖVE identity
- Expected output after building: `output/mobile/ThePictureShop-0.1.0-android.43-debug.apk`
- Download: [Android 43 installer](https://github.com/johnwestons/the-picture-shop/releases/download/android.43/ThePictureShop-0.1.0-android.43-Install.apk)
  and [development release notes](https://github.com/johnwestons/the-picture-shop/releases/tag/android.43).
- Contents: all current shared game changes, including the warehouse expansion, finer pallet/machine
  placement, Credit-tab fix, and complete eight-direction walking and matching idle animations for the
  three client designs and three salesperson designs. Radio Cat, Tinker Fox and Ferret Engineer,
  **HIRING** and **SCHEDULE** are playable: emailed resumes, negotiated contracts, agreed shifts, ordered cutter job queues with
  automatic progression through every pallet, pause/resume, reorder/remove and completion history,
  fatigue/focus and breakroom recovery, hourly wages, negotiated 4–12 hour daytime/overnight shifts,
  1–4 week payroll cycles and weekly overtime. Queues survive
  save reload and wait for staged stock and clear output. Unfinished cuts resume on the next agreed
  shift, including across days off and save/reload. Employees may be sent home for the day, can move
  finished cutter skids to the pallet wrapper, and can be trained on skills they lack; training uses
  paid shift hours. New quotes show negotiated staff budgets and raise
  cutting recommendations when needed to cover labor and margin; agreed customer prices stay fixed.
  Job details and Payroll track actual job wages separately from idle/break/shop labor. Bills includes
  due wages and settles the same payroll ledger once. **Payroll > SHOP BUDGET** plans full shifts,
  shop bills, machine loans, shared-cutter capacity, break-even work, profit and payroll reserves.
  **Shop Setup Options** sets a new save's day to any whole minute from 5–60, defaulting to 20.
  Live HUD/computer time and calendar shifts/paydays show shop time. The computer uses a digital clock
  and lets the host set 1x, 2x, 5x or 10x time; guests cannot change it. Player options recolor rabbit fur
  and overalls and share those colorways online. Early game offers more Express jobs and estimate emails
  include expected arrival time. The computer's RADIO tab includes only the nine-track Vibes playlist.
  Cutter margins are highlighted with correct-rotation feedback; finished pallets occupy six ordered
  front staging slots, safely waiting when full. All three walk/idle sets use the reviewed Mouse Frontier
  source art. Fox/ferret work/rest use original single poses; dedicated machine action sequences remain
  planned. All 825 runtime files, including the worker and visitor strips, match the package source.
  The latest refresh includes the perspective-fitted breakroom and shelves, compact employee arrival,
  departure and action bubbles, Schedule job choices restricted to fully unloaded stock, online
  high-five requests with opposite player facing, USB discovery, pallet jack motion, shared day/night
  scheduling, runtime module extraction and texture/save/menu performance improvements.
- LAN: protocol v28, with host-owned worker captions and poses and owner-only employment/schedule/wage
  actions. Local Play participants should use matching builds. Cable play uses Android USB tethering
  and a USB Ethernet link; Android-to-Android depends on compatible phone host/client support.
- Verification: all 825 archived runtime files match the current shared source and artwork byte for
  byte, including the newest employee, Schedule, high-five and warehouse files. APK signature,
  application ID/version, embedded game checksum and 16 KiB compatibility pass the Android build
  checks. The signing certificate matches the published Android 41 installer. No new full gameplay
  smoke run is claimed for this packaging update.
- Installer: 317,685,023 bytes (303.0 MiB), SHA-256
  `bbc91a4f7debb12e4ff9bdb286631fd6ae9250ab52f6adca6629fb1e38adeb44`.
  Clean source commit: `b5ab6c00691b052eb6a40021db71c65c6ff4af27`. Its development signing certificate
  matches Android 41, so it can update that build while retaining saves. The package includes only the
  allowlisted Vibes music tracks; local preview files are excluded.
- Device status: no phone was reachable from the build computer, so this development update was not
  remotely installed or physically playtested. The normal physical-device checklist remains open.
- Direct engineering: isolated Android/Android and PC/Android guests have passed separate-network
  gameplay, and the PC/Android repeat also passed guarded packet-privacy validation. Those engineering
  packages were removed after testing; they do not count as normal game-app acceptance, expose Direct
  Play, or change the bundled provider's `productionReady = false` state. The latest redacted evidence is
  `output/native-crypto/device-tests/pc_android_direct_packet_capture_report.json`.

## Build and install

For a remote phone update, download the APK from GitHub on the phone, then open it from **Downloads**
or **My Files** and follow Android's install prompt. Allow that download source to install apps if asked.
To perform the requested test-save reset, download first, uninstall only **The Picture Shop** without
keeping its app data, then install the downloaded APK and start a new shop. Installing over the existing
app instead preserves its saves. The release also includes `READ-ME.txt` and `SHA256SUMS.txt`.

From PowerShell in the project root:

```powershell
./BUILD_ANDROID.ps1 -Install
```

The first run prepares a local LÖVE Android wrapper and can take several minutes. Existing verified
JDK/Android tooling from the Mouse Frontier workspace is reused when present; otherwise the build
downloads pinned tooling. Later builds reuse the native engine cache.

`-PackageOnly` stops after building and smoke-testing the shared `.love` package. Omitting both switches
builds and verifies an APK without installing it.

The APK is development/debug signed for direct testing. A store release needs a protected release
keystore and Android App Bundle.

## Verified four-device acceptance — August 28, 2026

- Exact APK: `output/mobile/ThePictureShop-0.1.0-android.11-debug.apk`, 102,485,249 bytes,
  SHA-256 `88549621c829201171475cb38513ac1433b3292595b32cc3b0dd30fb67017940`.
- The packaged build reports clean source commit `8b5b80d28334853986a30e5e84b42ed88c53cbce`.
- Samsung SM-S938U hosted at `192.168.1.137:22122`; Samsung SM-S928U1, Samsung SM-J410G,
  and the Windows PC joined from the same protocol-v7 source. Every screen reached `4/4 WORKERS`, and
  all four participants moved independently.
- The cutter, skid wrapper, and Windmill stayed attached and synchronized on all three observers through
  live relocation, rotation, stops, restarts, and placement. The cutter remained live beyond 30 seconds;
  a red placement was rejected before a green placement succeeded, with no snap-back or duplicate sprite.
- A guest used the dock door during wrapper relocation and opened the computer/client screen during
  Windmill relocation without disturbing either live machine pose.
- When the SM-J410G left, every remaining device fell cleanly to `3/4 WORKERS` with no stale avatar. Its
  rejoin restored exactly one avatar, `4/4 WORKERS`, and independent movement.
- Android LÖVE logs were clean. The automated smoke suite completed 1,113 passes with 0 failures.

This targeted pass did not include the full 15-minute soak, hotspot matrix, or final offline save reload;
those broader checklist items remain open and are not implied by this acceptance record.

## Physical device checklist

- Fresh install reaches the three save slots and starts a new shop.
- Updating with `-Install` retains each save slot.
- Landscape remains locked while the phone rotates between its two landscape edges.
- Touch joystick movement is smooth and simultaneous touches do not produce duplicate mouse clicks.
- The shop floor fills the phone width; two-finger pan and pinch-zoom works on every screen and GUI.
  Each screen remembers its own camera without leaking gestures into taps, HUD actions, or shop controls.
- Contextual Use, Park, Move, Turn, machine placement, and pallet-jack controls all work.
- Moving machines or a loaded pallet jack shows the selectable green/red warehouse placement grid;
  touch selection remains aligned after zooming or panning.
- With an Android host, two connected Android workers and a PC observer, confirm every screen reaches
  `4/4 WORKERS` without a packet-size error. Confirm all three guests show a host-relocated cutter, skid
  wrapper, or Windmill attached to the pallet jack throughout movement and rotation. Guests cannot
  initiate or place the relocation, and only a successful placement replaces the durable floor pose.
- Disconnect and rejoin one worker. The remaining roster falls cleanly to `3/4 WORKERS`, the returning
  worker receives a fresh host-plus-assigned welcome, and every screen returns to `4/4 WORKERS` without
  stale or duplicated players.
- The skid-wrapper console lists every nearby eligible pallet and allows touch or controller-cursor selection.
- The remote Windmill console completes plate, setup, proof, production, cleanup, service, urgent E-STOP,
  disconnect/reacquire, and lease-contention checks on touch and controller cursor without client-authored scores.
- Quote, email, promotion, and cutter gauge fields summon the Android keyboard only after the field is tapped,
  dismiss it after an outside tap, and accept input normally.
- Cutter guarded controls recognize simultaneous touch and controller shoulder presses.
- A Bluetooth or USB standard controller can move, interact, operate the pallet jack, relocate machines,
  navigate panels with its cursor, close panels, and return safely to the title menu.
- Home/app switching releases held touch/controller state and preserves progress.
- Relaunch restores the latest shop state without showing the LÖVE fallback screen.

The Android launcher icon is generated directly from the supplied front-facing Polar cutter image in
`mobile/android/polar-cutter-launcher.png`. The build only resizes and centers that transparent artwork.

Before a distributable update, increment both values in `mobile/config.json`, run the normal smoke suite,
build/install, complete this checklist, and retain the APK report SHA-256.
