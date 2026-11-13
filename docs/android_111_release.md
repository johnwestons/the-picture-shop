# Android 111 test release candidate

Android 111 is the phone test candidate for source commit
`b328f1c7c2f2a0731fa84282f1d1a85d9fbd9d24`.

- Application ID: `com.thepictureshop.game`
- Version: `0.1.0-android.111` (version code 111)
- Multiplayer protocol: 75
- APK: [Android 111 installer](https://github.com/johnwestons/the-picture-shop/releases/download/0.1.0-android.111/ThePictureShop-0.1.0-android.111-Install.apk)
- Size: 1,031,996,534 bytes (about 984 MiB)
- SHA-256: `f344189681856e1213f890bca3c86ac0907ed5002e351ebd8ac19da1f1c83faf`
- Signing certificate SHA-256: `a755c90e21eb3f39d83445b353af53b337afe6a1d879dacb854643b127e58223` (matches Android 110)
- Embedded game package SHA-256: `cb43b15e9a81e75079feb007200df6d1b406efee8c4964078cae82cc99cb7537`

## Changes in this update

- Reset graphics transform, clipping, stencil, shader, blend, and color state at the start of every frame. A regression saves after breaker repair, reloads through normal startup, clears renderer caches, and opens CritterNet.
- Track the two oily warehouse puddles as separate persistent mop tasks beside the three floor-cleaning stages, including old-save migration and grand-opening requirements.
- Improve barn movement and Grandpa/exit controls on desktop and mobile; taps no longer move the character or trigger interactions directly.
- Keep multiplayer protocol 75, compatible with Android 109 and 110.

## Validation

- Full gameplay plan: 43 stages, 49 feature groups, 42,212 checks passed; source remained unchanged during validation.
- Focused restoration overlay checks: 25 desktop and 25 phone-layout checks passed, including save/reload after breaker repair.
- Packaged mobile smoke: 2,392 checks passed. Packaged story smoke: 137 checks passed, including packing and travel scenes.
- APK signature, package ID, embedded package hash, and 16 KB native library compatibility verified. Signing certificate matches Android 110.
- No physical Android installation or play session was performed. Please verify the affected restored save on the target phone before wider use.

This is a signed development test candidate. Native crypto and gateway
discovery remain engineering candidates and are not marked production ready.
Updating over an earlier build keeps existing game data; uninstalling without
retaining data starts with fresh disposable test saves.
