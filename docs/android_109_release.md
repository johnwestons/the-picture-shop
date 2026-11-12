# Android 109 test release

Android 109 is the phone-test build for source commit
`4a69258064e4e54d3233e8d46e1f6e888df59193`.

- Application ID: `com.thepictureshop.game`
- Version: `0.1.0-android.109` (version code 109)
- Multiplayer protocol: 75
- APK: [download Android 109](https://github.com/johnwestons/the-picture-shop/releases/download/0.1.0-android.109/ThePictureShop-0.1.0-android.109-Install.apk)
- Size: 1,031,994,071 bytes (about 984 MiB)
- SHA-256: `b1ffcb551d05bb282131f1427f38e689f03cee22cdcd9daccbfb82f7583ff996`
- Signing certificate SHA-256: `a755c90e21eb3f39d83445b353af53b337afe6a1d879dacb854643b127e58223` (matches Android 108)

## Changes in this update

- Added the original Groovy Slab and Arcade Flash bitmap font atlases and applied them to the approved menus, shop signage, Critter Crisis arcade screens, and mission card.
- Added the timed Critter Crisis mission intro and its network snapshot coverage.
- Included the current cutscene and character-footprint work in the Android package.

## Validation

- Gameplay plan: 43 stages, 49 feature groups, 42,204 checks passed.
- Engine smoke: 11,899 checks passed.
- Packaged Android smoke: 11,898 checks passed; story package smoke: 112 checks passed.
- Tooling: 108 Python tests and both PowerShell regression scripts passed.
- Asset audit: 593 checks passed; all 9 licensed audio sources verified.
- LuaJIT limits: 1,139 Lua files and 14,585 compiled functions passed the project budgets.
- APK signature, package ID, signing certificate compatibility, and 16 KB load alignment passed. The package report confirms a clean source commit.
- No physical Android installation or play session was performed.

This is a signed development test build. Native crypto and gateway discovery are
bundled as engineering candidates and remain marked not production-ready. Install
the same protocol 75 build on every multiplayer device. Installing over Android
108 keeps its game data; uninstall first without retaining data to start with
fresh disposable test saves.
