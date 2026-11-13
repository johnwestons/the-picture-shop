# Android 114 test release

Android 114 is the development test build produced from source commit
`642c8c2599a265aa243c12ca33a74fefae633ced` (`sourceDirty: false`). It pairs with
Windows build `0.1.0-test.114` and multiplayer protocol 75.

- Application ID: `com.thepictureshop.game`
- Android version: `0.1.0-android.114` (version code 114)
- APK download: [Android 114 installer](https://github.com/johnwestons/the-picture-shop/releases/download/0.1.0-android.114/ThePictureShop-0.1.0-android.114-Install.apk)
- APK size: 1,032,002,733 bytes (about 984 MiB)
- APK SHA-256: `c6de31b827923a1e9f4196295f3f61bc0a8010df764326cd9652c0d837956ab0`
- Signing certificate SHA-256: `a755c90e21eb3f39d83445b353af53b337afe6a1d879dacb854643b127e58223`
- Embedded game package SHA-256: `a099c1748ee64091613d7596f35bf6f382ab75afce589175ab573d6064c0a2f5`
- 16 KB native-library compatibility: verified

## Changes in this update

- Uses the selected restored warehouse image as the base artwork, with a matching lights-off version.
- Replaces floor repaint and checklist-driven cleaning with two large, asymmetric spills. The player can steer while mopping; repeated mop contact fades the contacted pixels and saves progress.
- Removes wall repainting from the restoration flow. Spill cleanup updates the checklist automatically; breaker repair, light switching, and utility calls are direct actions.
- Keeps the landline usable without building power. Calling the power and water utilities reconnects service; the repaired breaker switches the lights on afterward.
- Carries forward the warehouse menu-rendering fix, cutscene and mobile UI changes, and other current branch updates.

## Validation

- Full gameplay release plan: 43 stages, 49 feature groups, 42,278 checks passed; source remained unchanged.
- Python tool suite: 108 tests passed.
- Packaged Android runtime smoke: 11,911 checks passed, including three-frame rendering.
- Packaged story-opening smoke: 138 checks passed, including packing and travel scenes.
- Windows portable package smoke: 11,912 checks passed. The Windows installer was not built because Inno Setup is unavailable; the portable package is produced separately under `output/windows-114/`.
- APK signature, application ID, version, embedded package hash, and 16 KB native libraries verified.
- No physical Android install or play session was performed; the connected-device state was not queried.

This is a signed development test build. Native crypto and Android gateway
discovery remain engineering candidates and are not marked production ready.
