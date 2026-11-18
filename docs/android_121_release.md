# Android 121 development update

- Version: `0.1.0-android.121`, version code `121`.
- Application ID: `com.thepictureshop.game`.
- Multiplayer protocol: **82**. Update every participating phone.
- [Download the APK](https://github.com/johnwestons/the-picture-shop/releases/download/0.1.0-android.121/ThePictureShop-0.1.0-android.121-Install.apk).
- APK SHA-256: `138e5fa4c95bc1d937fe2fd93341c51341fd60f3ccbfd3a074acddca618712fb`.
- Packaged game source commit: `d4ac2c88b39a828fc3f8e28beda29875923504fc`.

## Changes

- Bike input replay uses the traffic poses recorded with each input, reducing
  position corrections when moving vehicles contact a client bike.
- The outdoor GPS mini map caches static streets and building footprints instead
  of redrawing them every frame.
- Includes the multiplayer synchronization and weak Wi-Fi fixes completed after
  Android 120.

## Install

Download the APK on each phone and open it from Downloads or My Files. Accept
Android's update prompt. The application ID and signing certificate match
Android 120, so it installs as an update. Every multiplayer participant must
install Android 121 because protocol 82 is incompatible with older builds.

## Verification

The packaged game passed 13,496 smoke checks; the packaged story opening passed
172 checks. The APK is signed and 16 KB aligned. Its SHA-256 matches the build
report, and its signing certificate matches Android 120. The new traffic and
mini map source files match the embedded game archive. The latest bike contact
and frame rate changes have not yet been measured on physical phones.
