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
