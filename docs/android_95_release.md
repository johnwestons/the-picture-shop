# Android 95 engineering test build

- Version: `0.1.0-android.95` (version code `95`)
- Artifact: `ThePictureShop-0.1.0-android.95-debug.apk`
- APK size: 904,131,079 bytes (about 862 MiB)
- APK SHA-256: `d2ff6708b859ed359cd2948f8a8b84a08ba88417045de5bf7b204f0421093934`

This build fixes a motorcycle draw crash during a small turn blend. Bike art
cache warming now reads lean from the rider presentation or actor instead of
an undefined global. A regression renders the first-person turn blend with no
global `lean` value.

It also fixes truck first-person entry on Android. The cab interior textures
were missing from the shared mobile package allowlist; all five runtime cab
images are now included and required by the package regression test.

It also gives shoulder-view rider billboards a small depth precision margin at
the road and parking paint plane. This clears tire-edge pixels while preserving
foreground wall occlusion. The truck first-person cockpit now has a runtime draw
check covering its dashboard and cab panels.

## Validation

- Bike art and condition mobile smoke passed, including the first-person lean
  regression and three rendered frames.
- Motorcycle camera runtime smoke passed on desktop and forced-mobile layouts,
  including the truck cockpit draw, shoulder tire coverage, and wall occlusion.
- Motorcycle wall-collision and recovery mobile smoke passed, including the
  real shop wall impact, rider fall, recovery, remount, and repair flow.
- Mobile commute smoke passed both home and work route loops, save/network
  checks, and three rendered frames.
- Scene exit/re-entry runtime smoke passed 54 checks on desktop and 54 on the
  forced-mobile layout, including terrain loading, outdoor reveal/streaming,
  trip save/reload, apartment return, and three rendered frames.
- The packaged Android archive passed the camera/cockpit, wall-collision, and
  commute smokes after adding the missing cab textures. Runtime package tests
  passed 14 checks.
- The full desktop smoke was attempted but stopped before gameplay checks at
  the existing startup texture-memory gate: 117.04 MiB against a 100 MiB limit.
  The town-center frontage assertion was not reached in this run.
- ADB listed no connected devices, so this build has no handset install or
  launch verification. The APK report confirms a signed, 16 KB-compatible
  package; native crypto remains an engineering candidate, not production-ready.

This is a debug engineering build, not a production release.
