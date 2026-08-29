# The Picture Shop for Android

## Current development build

- Application ID: `com.thepictureshop.game`
- Version: `0.1.0-android.10` (`versionCode` 10)
- Engine: LÖVE 11.5
- Orientation: sensor landscape, fullscreen
- Native libraries: verified 16 KB page-size compatible for Android 15+ devices
- Saves: private Android app storage under the shared `the-picture-shop` LÖVE identity
- Output: `output/mobile/ThePictureShop-0.1.0-android.10-debug.apk`
- LAN: protocol v6 includes fixed 12 Hz terminal/live poses for a host-relocated cutter, skid wrapper,
  or Windmill on the authoritative pallet-jack tick. The `.10` three-device physical pass is pending.

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
- With an Android host, a connected Android worker and PC observer show a host-relocated cutter, skid
  wrapper, or Windmill attached to the pallet jack throughout movement and rotation. Guests cannot
  initiate or place the relocation, and only a successful placement replaces the durable floor pose.
- The skid-wrapper console lists every nearby eligible pallet and allows touch or controller-cursor selection.
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
