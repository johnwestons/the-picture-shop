# Android 66 private development build

Android 66 is the private mobile build for source commit
`408d8a9ddb38a0402dda3f72f03089944dcb64ac`. It uses application ID
`com.thepictureshop.game`, version `0.1.0-android.66` (version code 66), and
multiplayer protocol 47. Local Play participants need matching builds.

## Changes in this update

- Expanded warehouse rooms can hold moved machines. The computer's pallet
  staging and output-area controls include the applicable room. Each purchased
  dock door serves that room's machines and pallet traffic; the original main
  warehouse dock remains the primary door. Dock views use the room's
  perspective.
- Jobs are generated for installed machines, including the printing press
  after purchase. Machine output areas and staging reservations are handled per
  machine and room.
- The player can take an employee-operated pallet jack with the normal
  interaction action. The jack and its cargo transfer to the player, and the
  employee is released to resume its assigned work. In online play, the host
  must take the jack.
- Late-game updates reduce repeated work as skids, workers and trucks accumulate.
  Running machines use independent audio sources, so multiple cutters can be
  heard at once.

## Build and verification

- Installer: `output/android-share/0.1.0-android.66/ThePictureShop-0.1.0-android.66-Install.apk`
- Size: 457,828,066 bytes (436.6 MB)
- SHA-256: `db67029b72a0b4acfb3e3da3a74b126544b61c42948071fc6439e47058b6d07d`
- Signing certificate SHA-256: `a755c90e21eb3f39d83445b353af53b337afe6a1d879dacb854643b127e58223`
- The signing certificate matches the previous Android build, so installing
  over it retains that game's saves. The installer folder includes
  `READ-ME.txt` and `SHA256SUMS.txt`.
- Desktop and packaged-mobile smoke checks passed, including the three-frame
  render check. APK signature, version, checksum and 16 KB compatibility checks
  passed.
- No Android device was connected. Physical installation, touch controls,
  background/resume behavior and multiplayer play were not verified on a phone
  or tablet.
- This is a private development build, not a public GitHub release. Native
  crypto and gateway discovery remain non-production candidates; Direct Play
  is unavailable.

Build this exact configured version with
`tools/pack_android_share.ps1 -UseConfiguredVersion`. Use `PACK_ANDROID.bat` to
advance the version for a later update and create another private installer.
