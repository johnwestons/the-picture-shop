# Android 116 test release

Android 116 is the signed development test build packaged from clean source
commit `a946a55d3ab2628dd7b9074de3947ef56a2e8868` on `codex/release-106`.

- Application ID: `com.thepictureshop.game`
- Version: `0.1.0-android.116` (`versionCode` 116)
- GitHub release: [The Picture Shop Android 116](https://github.com/johnwestons/the-picture-shop/releases/tag/0.1.0-android.116)
- APK download: [Android 116 installer](https://github.com/johnwestons/the-picture-shop/releases/download/0.1.0-android.116/ThePictureShop-0.1.0-android.116-Install.apk)
- APK size: 1,032,045,117 bytes (about 984 MiB)
- APK SHA-256: `421e55cfc49a447f700dd95c4e95ee6331b7511b2eb2ca343d59587e2506166b`
- Signing certificate SHA-256: `a755c90e21eb3f39d83445b353af53b337afe6a1d879dacb854643b127e58223` (matches Android 115)
- Embedded game package SHA-256: `de928e9170bffd91129a87702a6b80d4bb295c1f79b2e7aa6c259b4c64a2aad4`
- 16 KB native-library compatibility: verified

## Changes

- Players can finance truck and forklift purchases.
- Company trucks respond to obstacles and handle leaving and returning to the shop.
- Delivery trucks follow the strict picture shop yard protocol, with serialized
  dock access and recovery behavior.
- Includes the prepared story-mode fixes and previous gameplay updates.

## Validation

- Full gameplay matrix: 47/47 stages and 52/52 feature groups passed, with
  42,894 checks. The source fingerprint matched the tested source.
- Desktop regression suite: 12,060 checks passed with zero failures.
- Exact packaged Android runtime: 12,060 checks passed with zero failures,
  including three rendered frames.
- Story-opening package smoke: 138 checks passed with zero failures, including
  both story scenes and three rendered frames.
- Android application ID, version, APK signature, update signing key, embedded
  package hash, and native-library alignment were verified.
- No physical Android installation or play session was performed.

Install Android 116 over a compatible prior build to retain its app data.
Local Play participants should use matching builds.
