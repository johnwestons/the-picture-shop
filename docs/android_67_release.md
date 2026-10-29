# Android 67 private development build

Android 67 is the private mobile build for source commit
`6918083fc8d3e66738f6946c8897e75dfa62f1b6`. It uses application ID
`com.thepictureshop.game`, version `0.1.0-android.67` (version code 67), and
multiplayer protocol 47. Local Play participants need matching builds.

## Changes in this update

- Fixed extra-room machine ownership. A printing press or paper cutter moved to
  an expanded room is rendered and interacted with in that room only; it no
  longer leaves a duplicate in the main warehouse. Warehouse movement and
  collision handling now honor the machine's room assignment.
- Restored mobile pallet-jack move, place and rotate controls while inside a
  completed machine room. Machines can be repositioned within the room and
  carried back through the doorway into the main warehouse.

## Build and verification

- Installer: `output/android-share/0.1.0-android.67/ThePictureShop-0.1.0-android.67-Install.apk`
- Size: 457,829,128 bytes (436.6 MiB)
- SHA-256: `6053ba9c15179053157cba677c5df57d6699caef9dfcb7af47706e256e07d2b2`
- Signing certificate SHA-256: `a755c90e21eb3f39d83445b353af53b337afe6a1d879dacb854643b127e58223`
- The signing certificate matches the previous Android build. The installer
  folder includes `READ-ME.txt` and `SHA256SUMS.txt`.
- Fourteen targeted checks cover moving both the starter cutter and purchased
  press into a room, rendering each only in its assigned room, moving it around
  and placing it there, then returning it to the main warehouse. The packaged
  desktop/mobile smoke checks and three-frame render check passed. APK
  signature, version, checksum and 16 KB compatibility checks passed.
- Installed on the connected Samsung Galaxy S24 Ultra (SM-S928U1,
  `R5CX41W577Y`); Android reports version `0.1.0-android.67`, version code
  67, and the game process launched successfully. The app data was cleared
  before install, as required for this test update.
- This is a private development build, not a public GitHub release. Native
  crypto and gateway discovery remain non-production candidates; Direct Play
  is unavailable.

Build this exact configured version with
`tools/pack_android_share.ps1 -UseConfiguredVersion`. Use `PACK_ANDROID.bat` to
advance the version for a later update and create another private installer.
