# Android 110 test release

Android 110 is the phone test build for source commit
`38c6b3b6e99be555ad4920cac489f4c8e8605181`.

- Application ID: `com.thepictureshop.game`
- Version: `0.1.0-android.110` (version code 110)
- Multiplayer protocol: 75
- APK: [download Android 110](https://github.com/johnwestons/the-picture-shop/releases/download/0.1.0-android.110/ThePictureShop-0.1.0-android.110-Install.apk)
- Size: 1,031,994,468 bytes (about 984 MiB)
- SHA-256: `2ea31f9b01fa22d20e357b5268d15337c95700baf001751b58d2726459e35a3c`
- Signing certificate SHA-256: `a755c90e21eb3f39d83445b353af53b337afe6a1d879dacb854643b127e58223` (matches Android 109)

## Changes in this update

- Reset graphics transform, clipping, stencil, shader, blend, and color state at the start of each frame. This addresses the warehouse art covering other interfaces after breaker repair.
- Added a regression check that opens CritterNet after breaker repair with stale clip, stencil, and camera state present.
- Kept multiplayer protocol 75, so Android 110 can join Android 109 sessions.

## Validation

- Gameplay release plan: 43 stages, 49 feature groups, 42,206 checks passed.
- Focused warehouse overlay checks: 22 desktop checks and 22 phone-layout checks passed.
- Android package built from a clean source tree; package report identifies commit `38c6b3b6e99be555ad4920cac489f4c8e8605181` and `sourceDirty: false`.
- APK signature, application ID, embedded game payload, and 16 KB native library compatibility verified. Signing certificate matches Android 109.
- No physical Android installation or play session was performed. Please verify the restored save on the affected phone after installing this build.

This is a signed development test build. Native crypto and gateway discovery
are bundled as engineering candidates and remain marked not production ready.
Installing the update over Android 109 keeps existing game data; uninstalling
without retaining data starts with fresh test saves.
