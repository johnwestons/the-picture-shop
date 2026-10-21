# Arcade menu and air hockey controls — Android 59

The cabinet selector now has its own neon 1980s design: cyan and pink game
cards, a striped sunset, perspective grid and CRT scanlines. Tap either large
card to open Critter Kombat or Critter Crisis. Keyboard arrows plus Enter and
controller D-pad plus A also select either game; number shortcuts still work.

Air hockey now has a movement wheel to the left of the table. Hold and move
inside the wheel to steer your paddle; release to stop. It has a small deadzone,
variable speed and clamped diagonal movement. The table is resized to make room.
The wheel controls the local player's orange or teal paddle, including guests.
Keyboard movement and mouse dragging on the resized table remain available.

Touch uses the same coordinate transform as the renderer, including Android's
letterboxing. One finger owns the wheel until released, even if another finger
touches the screen or a synthetic mouse release occurs. Backgrounding the app
clears held input and the network input values. Spectators cannot move paddles.

The earlier purchase-only Regal Moll folder change is included. The folder is
available through Used Machinery or COMPUTER > WWW > MACHINES and is no longer
placed free on every warehouse floor. These changes require no save reset.

## Validation

Automated regression checks exercise touch at 2340×1080, 1280×800 and 960×678
with asymmetric safe-area insets, two-finger ownership, deadzone, diagonal limits,
release, authoritative paddle movement, guest input, spectators, mouse dragging,
keyboard movement, focus changes, both game choices and exiting the cabinet.
Both screens were rendered and visually inspected at the 960×678 design size.
Preview files are in `output/arcade-ui`.

Physical phone/tablet gameplay acceptance remains pending. This build does not
change the multiplayer protocol (41). All participants need matching current code.

## Installer and results

- Installer: `output/android-share/0.1.0-android.59/ThePictureShop-0.1.0-android.59-Install.apk`.
- Size: 440,912,407 bytes (420.5 MiB).
- SHA-256: `e48ca522f57b3002d636dcd9eeab6ecedf2b7f991add8444bb14a5dc1b3f316e`.
- Focused arcade suite: 694 checks pass, including 41 new interaction checks.
- Full desktop suite: 6,135 checks pass; packaged mobile suite: 6,134 pass.
- All 1,091 runtime files match the expected source or generated metadata.
- APK signature, previous certificate continuity, embedded game hash, native
  library checks and 16 KB alignment pass. Reports are beside the installer.
- Same-day asset and tooling baseline reports are included; no image assets or
  build tooling changed for this update.

ADB reported no connected devices during the build. No device was installed,
cleared or otherwise modified. Earlier installed builds do not have these changes.
