# Android 65 development build

Android 65 is the next private development build configured for the current
source. It uses application ID `com.thepictureshop.game`, version code 65 and
multiplayer protocol 47. Every player in a Local Play session needs a matching
build. The latest public GitHub release remains Android 61; this handoff does
not publish a GitHub Release asset.

This source includes the current character animation runtime and reviewed art,
player reward feedback, and the gameplay changes already present in the shared
project checkout. Money changes receive a brief HUD pulse and signed amount;
email, incoming-call, customer and supplier arrivals use compact notices. The
phone cue is a single quiet confirmation sound per call. These cues run on each
client from its replicated shop and visitor state.

The animation overhaul is still active. North V7 remains installed because its
support foot still slides; the October 28 V31 study was rejected. Missing walk
directions, work poses and contact transitions remain documented in the
[animation handoff](character_animation_handoff.md). This build does not promote
unfinished art.

Run `PACK_ANDROID.bat` to advance the development version and produce a private
installer under `output/android-share`. A committed version can be packaged
without changing its version code with
`tools/pack_android_share.ps1 -UseConfiguredVersion`. The package script runs
the desktop and packaged-mobile checks, verifies the APK checksum and signing
certificate, and writes install instructions. Installing over a compatible
signed version keeps its saves; a clean test install requires uninstalling only
The Picture Shop and choosing to remove its app data.

Automated checks do not replace a physical phone/tablet acceptance pass. This
development handoff does not claim physical-device, touch, background/resume or
multiplayer soak testing.

## Build verification, October 28

The private installer was built from source commit
`ddb25649973ef721be194908b8abdd07a7d9cdc0` with a clean working tree. The full
desktop smoke suite passed 6,464 checks; the packaged-mobile smoke passed 6,463
checks. Both completed the three-frame render check. APK manifest, signing
certificate continuity and checksum verification passed; the installer is
457,807,571 bytes, SHA-256
`0a2f44965d9733753a405bc99f7bed23463bd42f1eeb7b04eb22e0e0d5e20e18`.

No Android device was connected, so the build was not installed or launched on
a phone or tablet. Native crypto and gateway discovery remain explicitly
non-production candidates in the APK report.
