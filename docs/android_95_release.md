# Android 95 engineering test build

- Version: `0.1.0-android.95` (version code `95`)
- Artifact: `ThePictureShop-0.1.0-android.95-debug.apk`
- APK SHA-256: pending build

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
- The packaged Android archive passed the camera/cockpit, wall-collision, and
  commute smokes after adding the missing cab textures. Runtime package tests
  passed 14 checks.
- ADB started but listed no connected devices, so this build has no handset
  launch verification.
- The full all-domain suite was not run; the previous build's startup texture
  memory gate and town-center frontage assertion remain outside this fix.

This is a debug engineering build, not a production release.
