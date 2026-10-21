# Garage exterior sprite and Regal folder test bench

The view through the loading-bay door now uses
`assets/generated/loading-bay-exterior-v1.png`, generated to match the warehouse
art. It replaces the flat procedural parking lot. The existing aperture clips
the image, the moving shutter covers it, and day/night tint and rain remain
independent layers. At load time the source is rendered to a 256×256 cached GPU
sprite and the full-sized texture is released; the startup memory budget passes.
The full-resolution source stays available for future art revisions.

The private standalone test page is published at:
https://picture-shop-regal-folder-lab.rockycoot12.chatgpt.site

It runs the game's unchanged folder Lua module via Fengari Web 0.1.4. The eight
machine views use the game's sprite sheet. Controls support mouse, touch and
keyboard. A test-only setup shortcut, pause button, new batch action and JSON
report download help reproduce issues without a shop save. Hidden tabs pause
the test clock. The page does not modify game saves or installed apps.

The Site uses its own Git repository in `sites/regal-folder-lab`. Refresh it from
the game with `python tools/sync_regal_folder_lab.py`, run its `node test.cjs`,
then publish with the persisted Sites identity. The source helper successfully
pushed commit `de6b520690c04aa35d9776f06a738e06bf570f8c`. Its Bash archive wrapper
is unavailable on this Windows host, so the plugin's same Node preparation
helper and Windows tar packaged the unchanged pushed static files instead.
Private deployment succeeded; account sign-in is required to open the hosted page.

## Verification

- Browser engine regression: failed and successful proof, guarded setup,
  24-sheet/four-box completion, jam and reproof, reset and eight-view cycling.
- Live browser: setup, proof, feed, rotate, catch six, box, reset and 390px phone layout.
- Game: exterior asset registration, clipping, closed-door suppression and a
  single sprite draw. Day/night/half-open/closed screenshots visually checked.
- Android 60: full desktop suite 6,139 checks; packaged mobile suite 6,138 checks.
- Existing arcade menu, hockey wheel and buyable-only folder changes are retained.
- Protocol remains 41; physical-device acceptance is still required.

Previews: `output/garage-sprite/garage-day.png` and
`output/regal-folder-web-preview.png`. No device data was changed in this update.

Installer: `output/android-share/0.1.0-android.60/ThePictureShop-0.1.0-android.60-Install.apk`
(443,936,109 bytes). SHA-256:
`d97b86dbfeb96e7fc0415eb9a599a087324df14ddd27951929f2f4e439b10ca9`.
All 1,092 runtime files match the expected source. APK signing continuity,
embedded game hash and 16 KB native alignment checks pass. No Android device
was connected, so this update has not been installed on a phone.
