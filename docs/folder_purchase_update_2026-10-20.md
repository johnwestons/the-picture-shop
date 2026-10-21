# Purchase-only Regal Moll folder — Android 58

The Regal Moll folder no longer appears automatically in the warehouse. Its
unconditional rendering, interaction and collision area were removed. Existing
shops without a purchase also lose the free prop when opened in this build;
no save reset is required.

Buy **Regal Moll practice folder** from the Used Machinery salesman, or through
**COMPUTER > WWW > MACHINES**. Dealer purchases place a machine in a clear floor
location; online orders arrive by flatbed and are placed when unloaded. Normal
financing and resale are available. Ownership and position persist through saves.
The practice minigame remains unchanged and is still unavailable to network guests.
See [folder controls and prices](regal_folder_minigame.md).

The market, dealer and financing layouts now fit four listings, including touch
buttons. These screens were rendered and visually checked.

## Build and checks

- Installer: `output/android-share/0.1.0-android.58/ThePictureShop-0.1.0-android.58-Install.apk`.
- Version: `0.1.0-android.58`, code 58; application ID `com.thepictureshop.game`.
- Multiplayer protocol: **41**. All participants need matching current code.
- Size: 440,907,822 bytes (420.5 MiB).
- SHA-256: `9db80008a1a25fad8f516a4e934a426ea34d4232e3d486969125c92122605967`.
- Desktop suite: **6,092 checks pass**; packaged forced-mobile suite: **6,091 pass**.
- New regression coverage checks an empty default shop, payment, both catalogs,
  dealer placement, online delivery, save/reload, resale, interaction removal,
  and the fourth purchase button in both interfaces.
- All **1,089 runtime files** match the expected source or generated metadata.
- APK signature, certificate continuity, embedded game hash, native libraries and
  16 KB alignment checks pass. Detailed evidence is beside the installer.

No device was connected during this build. Previously installed Android 57 apps
are unchanged and still contain the free floor prop. Android 58 is ready to install
for testing; physical gameplay acceptance is pending. No Windows installer was
rebuilt in this change, but running the current source uses the new behavior.
