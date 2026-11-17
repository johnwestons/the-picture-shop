# Android 120 development update

- Version: `0.1.0-android.120`, version code `120`.
- Application ID: `com.thepictureshop.game`.
- Multiplayer protocol: **80**. Update all participating phones to Android 120.
- [Download the APK](https://github.com/johnwestons/the-picture-shop/releases/download/0.1.0-android.120/ThePictureShop-0.1.0-android.120-Install.apk).
- [Release, checksums and verification](https://github.com/johnwestons/the-picture-shop/releases/tag/0.1.0-android.120).

## Included changes

- Multiplayer movement prediction, smaller state updates, and interaction and
  synchronization fixes from the multiplayer audit.
- Bounded CritterNet receipts and other growing histories, keeping recent entries
  while retaining records still needed for active gameplay or unpaid obligations.
- Physical employee and visitor commutes that respect traffic; truck receiving,
  pickup, departure and disabled-vehicle recovery fixes.
- Commuters retain acceleration at normal display frame rates, avoiding a slow
  crawl that could delay employees well past the start of their shift.
- Employees can process ready skids while another skid dries. Training safely
  releases pallet jacks and pauses when machines need service or are occupied.
  Closed-shop attendance waits for employees to arrive before accruing wages.
- The current calendar artwork and all other shared source changes, including
  the food, household and delivery updates already shipped in Android 119.

## Installing remotely

Download the APK on each phone, open it from Downloads or My Files, and accept
Android's update prompt. If requested, permit installs from the browser or file
manager used to open the APK. The app uses the existing application ID and signing
key, with a higher version code for updating in place. For fresh disposable test
saves, clear The Picture Shop's storage in Android settings before launching.

## Verification

The APK is built from the same committed Lua source and game assets as desktop.
The release attachments record the exact source commit, APK SHA-256, embedded
game checksum, signing-certificate comparison, native-library alignment checks,
and desktop/mobile regression results. These identify the actual uploaded APK.

This is a development pre-release. Automated regression and package checks do
not replace a physical-phone or public-Internet multiplayer play session. Native
networking components retain their existing engineering-candidate status.
