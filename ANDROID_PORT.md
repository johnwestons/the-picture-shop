# The Picture Shop for Android

## Current development build

- Application ID: `com.thepictureshop.game`
- Version: `0.1.0-android.15` (`versionCode` 15)
- Engine: LÖVE 11.5
- Orientation: sensor landscape, fullscreen
- Native libraries: verified 16 KB page-size compatible for Android 15+ devices
- Saves: private Android app storage under the shared `the-picture-shop` LÖVE identity
- Expected output after building: `output/mobile/ThePictureShop-0.1.0-android.15-debug.apk`
- LAN: protocol v9 adds the host-authoritative Windmill console, bounded 12 Hz runtime snapshots,
  host-owned plate/setup/service sessions, urgent E-STOP preemption, and safe disconnect recovery on top
  of the existing MTU-safe four-worker movement, cutter, wrapper, pallet-jack, and machine-pose systems.
- Status: a signed `.15` debug APK is packaged, and `output/mobile/apk-report.json` verifies its Internet
  and network-state permissions, audited Android gateway bridge ABI/lifecycle call sites, three exact native
  gateway ABIs, and 16 KiB compatibility. The read-only gateway foundation remains non-production and
  sends no traffic.
  The report records no normal-app device launch, the Windmill physical-device checklist remains pending,
  and the build report identifies a dirty development tree; this is not a release artifact.
- Direct engineering: isolated Android/Android and PC/Android guests have passed separate-network
  gameplay, and the PC/Android repeat also passed guarded packet-privacy validation. Those engineering
  packages were removed after testing; they do not count as normal `.15` app acceptance, expose Direct
  Play, or change the bundled provider's `productionReady = false` state. The latest redacted evidence is
  `output/native-crypto/device-tests/pc_android_direct_packet_capture_report.json`.

## Build and install

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
