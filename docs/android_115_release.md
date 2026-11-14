# Android 115 test release

Android 115 is the development test build packaged from source commit
`37655a65953aac5c300c6db2ca6bfd07244b215a` (`sourceDirty: false`). Its gameplay
changes were fully tested on parent gameplay commit `cd41bde4d68052f5d6229c8a0c43b423379bf589`; the Android version and release packaging metadata were then advanced for in-place updates.

- Application ID: `com.thepictureshop.game`
- Android version: `0.1.0-android.115` (`versionCode` 115)
- GitHub release: [The Picture Shop Android 115](https://github.com/johnwestons/the-picture-shop/releases/tag/0.1.0-android.115)
- APK download: [Android 115 installer](https://github.com/johnwestons/the-picture-shop/releases/download/0.1.0-android.115/ThePictureShop-0.1.0-android.115-Install.apk)
- APK size: 1,032,015,698 bytes (984.21 MiB)
- APK SHA-256: `e318d0b62d2c567c429f2014a04817a7b605f794e1ca2d27e8c897c7392dccde`
- Signing certificate SHA-256: `a755c90e21eb3f39d83445b353af53b337afe6a1d879dacb854643b127e58223` (matches Android 114)
- Embedded game package SHA-256: `9097983943489628db049cd99512027e77f87377f0277a9b2a455b093523ea9c`
- 16 KB native-library compatibility: verified

## Changes

- Employees sign for pallets during a free gap between queued tasks, walk to the delivery driver, and complete the signature interaction. The unloading screen confirms when the truck is empty and ready to close.
- Mobile action controls, work phone directory actions, bike cargo access, and bike cargo presentation have been improved.
- Vehicle fuel use and delivery mileage, plus commute movement and walking animation speed, have been tuned.

## Validation

- Full gameplay plan: 43 stages and 49 feature groups passed. Desktop and forced-mobile core runs each passed 11,913 checks on commit `cd41bde4`.
- Android package version, application ID, embedded game package, APK signature, and native libraries were verified for commit `37655a6`.
- The APK uses the same signing certificate as Android 114 and can update that install in place while retaining app data.
- No physical Android installation/play session or public internet multiplayer session was performed. Native crypto and Android gateway discovery remain development candidates.
