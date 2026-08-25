# The Picture Shop for Android

## Current development build

- Application ID: `com.thepictureshop.game`
- Version: `0.1.0-android.1` (`versionCode` 1)
- Engine: LÖVE 11.5
- Orientation: sensor landscape, fullscreen
- Native libraries: verified 16 KB page-size compatible for Android 15+ devices
- Saves: private Android app storage under the shared `the-picture-shop` LÖVE identity
- Output: `output/mobile/ThePictureShop-0.1.0-android.1-debug.apk`

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
- The shop floor fills the phone width; a two-finger gesture pans and pinch-zooms without leaking taps
  into the HUD or shop interactions.
- Contextual Use, Park, Move, Turn, machine placement, and pallet-jack controls all work.
- Quote, email, promotion, and cutter gauge fields summon the Android keyboard and accept input.
- Cutter guarded controls recognize simultaneous touch and controller shoulder presses.
- A Bluetooth or USB standard controller can move, interact, operate the pallet jack, relocate machines,
  navigate panels with its cursor, close panels, and return safely to the title menu.
- Home/app switching releases held touch/controller state and preserves progress.
- Relaunch restores the latest shop state without showing the LÖVE fallback screen.

The Android launcher icon is generated directly from the supplied front-facing Polar cutter image in
`mobile/android/polar-cutter-launcher.png`. The build only resizes and centers that transparent artwork.

Before a distributable update, increment both values in `mobile/config.json`, run the normal smoke suite,
build/install, complete this checklist, and retain the APK report SHA-256.
