# Android 93 engineering test build

- Version: `0.1.0-android.93` (version code `93`)
- Artifact: `ThePictureShop-0.1.0-android.93-debug.apk`
- APK SHA-256: `7d2109a446e2e1724de43de5088773381e219d3f6bc9eb6396f1d1ee1717a8cb`
- Built from the same source revision as the PC game.

This build packages the delivery-truck traffic and livery work, independent
multiplayer scene work, terrain and road updates, and the 64-view machine art
package. The Polar cutter and Heidelberg Windmill use their 64-angle turntables
in gameplay. Other machine atlases are packaged as candidate assets and are not
all wired into gameplay yet. Truck company branding remains a runtime overlay;
the base truck sprite does not bake in the Picture Shop logo.

## Validation

- Android package audit passed: signed APK, version code/name match, embedded
  game archive hash match, and 16 KB native-library compatibility.
- Focused `machine-64-views` smoke passed (8 checks) and focused
  `delivery-traffic` smoke passed (6 checks); both also rendered three frames.
- Runtime source package tests passed (14 checks).
- The broad Android package health gate reports startup texture memory at
  117.04 MiB, above its 100 MiB limit. The full domain smoke also stops in
  `town_generation_test.lua` with a nil-value error.
- The APK was not installed or launch-verified on a physical device for this
  release.

This is a debug engineering build. The bundled native crypto module and Android
gateway discovery are both marked as engineering foundations, not production
ready. Do not treat this APK as a production release.
