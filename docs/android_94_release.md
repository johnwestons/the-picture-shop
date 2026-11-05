# Android 94 engineering test build

- Version: `0.1.0-android.94` (version code `94`)
- Artifact: `ThePictureShop-0.1.0-android.94-debug.apk`
- APK SHA-256: `0ad2350e1f28dcacce6016cfd23d17bce86235ef1d9df362d4f63136c948978a`
- The PC and Android version markers are both `0.1.0-android.94`.

This build fixes the Android GLES shader link failure when entering the
outdoors. Rabbit colorway uniforms and helpers are now fragment-stage only, so
`furTint` is not linked with mismatched vertex-stage precision. It also keeps
the generated mainland connector attached to the authored road endpoint's
exact position and elevation, preserving route-graph connectivity.

## Validation

- Scene-exit smoke passed 52 checks, including two exterior terrain loads,
  renderer creation, travel, and return-to-title flows.
- Island variation smoke passed 19 checks, including the mainland-exit route
  and safe roads at multiple road densities.
- Route-map smoke passed 38 checks.
- Packaged scene-exit smoke passed 54 checks; runtime source package tests
  passed 14 checks. The signed APK audit confirmed the matching embedded
  archive hash and 16 KB native-library compatibility.
- The broad startup health gate stops at 117.04 MiB texture memory against its
  100 MiB limit. The domain suite reaches the town-center frontage checks and
  stops at `town_center_core_frontages_join_main_and_residences_join_side_streets_1`.
- No Android device was connected for a handset launch check.

This is a debug engineering build. The bundled native crypto and Android
gateway discovery components are engineering foundations, not production
ready. Do not treat this APK as a production release.
