# Android 68 private development build

Android 68 is the private mobile build for source commit
`8eaecb8d2133c77e1a1bc2af91b20b951af13902`. It uses application ID
`com.thepictureshop.game`, version `0.1.0-android.68` (version code 68), and
multiplayer protocol 47. Local Play participants need matching builds.

## Changes in this update

- Fixed machine travel through expansion-room doors. The cutter, skid wrapper,
  and printing press can enter completed rooms and return to the warehouse.
  Door interaction range and doorway clearance now account for the attached
  machine's footprint, so a larger machine or its operator cannot get stranded
  at the threshold.
- Room-side placement keeps the machine centered on the walkable doorway and
  checks surrounding obstacles while allowing its footprint to overlap the
  passage mask during the crossing.

## Build and verification

- Installer: `output/android-share/0.1.0-android.68/ThePictureShop-0.1.0-android.68-Install.apk`
- Size: 457,829,825 bytes (436.6 MiB)
- SHA-256: `b4ee85ded7c708ebc23dd0756b30b59aa8717f9d21c04bc8b4847824b0a7cab9`
- Signing certificate SHA-256: `a755c90e21eb3f39d83445b353af53b337afe6a1d879dacb854643b127e58223`
- The signing certificate matches the previous Android build. The installer
  folder includes `READ-ME.txt` and `SHA256SUMS.txt`.
- Focused machine-transport checks passed for cutter, wrapper, and press room
  entry, placement, and return through the room exit. Desktop and packaged
  mobile smoke checks passed. APK signature, version, checksum, and 16 KB
  compatibility checks passed.
- Installed and launched on the connected Samsung Galaxy S24 Ultra
  (SM-S928U1, `R5CX41W577Y`). Android reports version `0.1.0-android.68`,
  version code 68, and a running game process. The app data was cleared before
  installation under the project's test-save instructions; the doorway path
  was verified in the focused desktop regression run, not manually played on
  the phone.
- This is a private development build, not a public GitHub release. Native
  crypto and gateway discovery remain non-production candidates; Direct Play
  is unavailable.

Build this exact configured version with
`tools/pack_android_share.ps1 -UseConfiguredVersion`. Use `PACK_ANDROID.bat` to
advance the version for a later update and create another private installer.
