# The Picture Shop: Tester Packaging and Distribution Report

**Date:** August 29, 2026<br>
**Scope:** Windows PC and Android tester builds

## Executive recommendation

The best near-term setup is:

1. Build both platforms from the **same clean commit and shared tester version**.
2. Give Windows testers one x64 installer named like:
   `ThePictureShop-0.1.0-test.15-Windows-x64-Setup.exe`.
3. Give Android testers a consistently release-signed package named like:
   `ThePictureShop-0.1.0-test.15-Android.apk`.
4. Use one **GitHub pre-release** as the canonical record for the matching Windows and Android builds, release notes, commit, and SHA-256 checksums.
5. For recurring private Android tests, also deliver that same APK through **Firebase App Distribution**. It provides invitations and build-update notices without requiring a Google Play release.
6. Move Android to **Google Play Internal Testing** later, after the project produces a signed AAB and updates its target API level.

Android cannot install an `.exe`. An Android tester either taps an `.apk` on the phone or follows a Firebase/Google Play testing link. The `.exe` installer is only for Windows.

GitHub can host these files, but use **GitHub Releases**, not commits in the source repository, Git LFS, or GitHub Actions artifacts. The present Android APK is about 98 MiB, far below GitHub Releases' 2 GiB per-asset limit. GitHub states that Releases have no fixed total-release-size or bandwidth quota for normal use.

## Recommended release layout

Use one release page for both platforms so multiplayer testers do not accidentally mix protocol versions:

| Release item | Purpose |
|---|---|
| `ThePictureShop-0.1.0-test.15-Windows-x64-Setup.exe` | Windows installer |
| `ThePictureShop-0.1.0-test.15-Android.apk` | Direct/Firebase Android install |
| `SHA256SUMS.txt` | File-integrity checks |
| GitHub release notes | Exact build, commit, known issues, testing focus, and install instructions |

Use a shared tag such as `v0.1.0-test.15`. Android should use a higher integer `versionCode` for every update. The game version, Git tag, source commit, multiplayer protocol, filenames, and release notes should all agree.

Do not create separate unrelated Windows and Android release pages for the same test wave. Separate files on one release page are easier for testers and make cross-platform compatibility obvious.

## Current repository readiness

### What is already in good shape

- The game uses LÖVE 11.5 and one shared Lua source tree.
- Android packaging already creates a `.love` archive, runs automated checks, builds an APK, verifies its signature and application ID, checks the INTERNET permission, and checks 16 KiB ZIP/native-library alignment.
- The release gate checks a clean synchronized branch, versions, automated engine tests, raster assets, licensed audio sources, package provenance, contents, and SHA-256.
- Windows-to-Android LAN play has already received physical-device testing on earlier builds.
- The current package sizes are practical for release hosting: the newest local `.love` is about 79.45 MiB and the newest APK is about 97.76 MiB.

### What is not ready yet

1. **There is no Windows standalone build or installer.** The current Windows instructions require testers to install LÖVE and run the source folder through `RUN_GAME.bat`. That is a developer workflow, not a tester package.
2. **The current Android build is development/debug signed.** The build script runs `assembleEmbedNoRecordDebug`. A debug key is insecure by design and becomes an update problem if a different computer or a clean CI runner generates the next build with a different debug key.
3. **Build 14 is not currently distributable.** `mobile/config.json` and `ANDROID_PORT.md` identify `0.1.0-android.14`, but there is no `.14` APK in `output/mobile`. The latest local APK is `.13`, comes from an older commit, and the `.14` physical-device checklist is still pending.
4. **The working tree is currently modified.** The existing release gate intentionally refuses a dirty tree and requires local `main` to match `origin/main`. This is correct release behavior, but it means a tester build should wait until the intended changes are reviewed, committed, pushed, and accepted.
5. **The runtime packager omits a referenced font.** `src/config.lua` references `assets/fonts/SpecialElite-Regular.ttf`, while `tools/build_mobile_package.py` copies only `assets/generated` plus runtime audio. The current `.love` therefore omits the font and `SpecialElite-LICENSE.txt`, causing a silent fallback and a missing notice. Fix this before calling the package complete.
6. **There is no GitHub release automation.** The repository has no tags and no `.github` workflow. `output/**`, APKs, and `.love` files are ignored, which is correct; a separate release-upload step is needed.
7. **The Play path is not ready today.** The built APK targets API 34. Starting August 31, 2026, new Google Play apps and updates must target API 36 unless an eligible extension applies. Direct APK and Firebase testing can continue while the wrapper is upgraded and retested.

The current `.13` APK should be treated as a prior development artifact, not renamed and published as the new tester build.

## Windows packaging plan

### Package format

Create a Windows x64 distribution from the same tested `.love` archive:

1. Obtain the official **LÖVE 11.5 Windows x64 ZIP runtime**.
2. Verify the downloaded runtime before using it.
3. Fuse the tested `.love` archive with the matching `love.exe` to produce `ThePictureShop.exe`.
4. Bundle that executable with every required same-architecture LÖVE DLL and the LÖVE license/notices.
5. Wrap the complete runtime folder with **Inno Setup 7** to produce one Setup `.exe`.

The official LÖVE distribution guide requires the Windows game executable to travel with the matching runtime DLLs and license. A fused LÖVE executable is not truly a single-file game by itself; the Inno installer is what turns the whole folder into the one download the tester expects.

### Why Inno Setup

Inno Setup is the best fit for this game because it produces one familiar `.exe`, supports per-user installs, shortcuts, upgrades, Installed Apps registration, an automatic uninstaller, compression, architecture rules, and code-signing integration. NSIS is a reasonable fully free alternative, but it is lower-level. WiX/MSI and MSIX add complexity that is not justified for this self-contained tester build.

### Installer behavior

The Windows installer should:

- Install per user to `%LocalAppData%\Programs\The Picture Shop`, avoiding an administrator prompt.
- Use one permanent Inno `AppId` so future versions upgrade the same installation.
- Create a Start Menu shortcut.
- Offer a desktop shortcut as an optional checkbox.
- Register an uninstaller in Windows Installed Apps.
- Offer **Launch The Picture Shop** on the final page.
- Preserve all save data during both upgrades and normal uninstall.
- Install all LÖVE DLLs and required notices.
- Use one game icon consistently for the game executable, installer, shortcuts, and uninstaller.
- Avoid creating a broad firewall exception. When LAN play first listens for connections, tell testers to allow the game on **Private networks** if Windows asks. Local Play needs only inbound UDP `22122`. Direct Play must not reuse a shared `love.exe` or `lovec.exe` application allowance in the shipped build: after the tester explicitly chooses to host, a signed elevated helper should create one rule for the stable fused `ThePictureShop.exe`, inbound UDP `57842`, and only the approved active profiles. The uninstaller must validate and remove only that immutable owned rule.

Only produce Windows x64 initially. Add a 32-bit build only if an actual tester has 32-bit Windows. The x64 build is also the practical target for current Windows 11 ARM PCs through Windows' x64 compatibility layer.

### Existing Windows saves

There is one LÖVE-specific transition to decide before packaging. The current non-fused developer launcher stores saves under the non-fused LÖVE location, while a fused game uses the direct application-data location. Existing development testers may therefore appear to lose their saves even though the old files still exist.

Before the first installer is shared, choose one of these approaches:

- Have the installer copy an existing `the-picture-shop` save folder from the old LÖVE location to the fused location; or
- Deliberately keep a non-fused runtime layout inside the installer and launch the `.love` file through the bundled engine.

The standard fused executable with a one-time save migration is the cleaner long-term package. Once that decision is made, keep the application identity and save path stable.

## Android packaging plan

### Immediate tester package

Produce a **release-signed universal APK**. The tester opens the link on the Android phone, downloads the APK, permits that browser or file manager to install apps when prompted, and taps Install. No PC, USB cable, ADB, or `.exe` should be involved.

Before distributing it:

1. Create a protected Android release/tester keystore.
2. Store the keystore and passwords outside the repository, with an offline backup.
3. Make the build script produce and verify a release-signed APK instead of relying on the machine's debug key.
4. Keep `com.thepictureshop.game` stable.
5. Increment `versionCode` for every tester release.
6. Confirm that an APK update installs over the previous tester APK without uninstalling it and without losing saves.

Android accepts an update only when the package name and signing identity match and the version is allowed. Losing or changing the signing key can force testers to uninstall, which removes the app's private saves.

### Direct APK, Firebase, or Google Play

| Android channel | Use now? | Tester experience | Main tradeoff |
|---|---:|---|---|
| GitHub Release APK | Yes, as a simple fallback/archive | Tap a direct link and install | Tester must allow installation from that source; updates are manual |
| Firebase App Distribution | **Recommended for recurring private tests** | Email invitation, release notes, tester groups, update notices | Tester signs in with Google and may still approve installs outside Play |
| Google Play Internal Testing | Later | Best install/update experience through Play; up to 100 internal testers | Requires Play setup, signed AAB, and the project must first move from target API 34 to the current Play requirement |

Firebase App Distribution is currently no-cost, accepts signed APKs, supports tester groups and invitations, and retains builds for 150 days. The GitHub Release should remain the canonical build record even if Firebase is used as the tester-facing Android delivery mechanism.

### 2026 Android developer verification

Android's new developer-verification system is now relevant. Direct sideloading is not part of the initial September 30, 2026 participating-store enforcement, but the rules expand globally in 2027. Register `com.thepictureshop.game` and its durable signing key before that broader rollout.

If the game stays outside Google Play, use Android Developer Console. A no-cost limited-distribution account is intended for hobbyists and permits a small explicitly authorized device set; broader distribution uses the full verified path. If the game moves to Play, use Play Console registration and Play App Signing.

This is another reason to stop using the debug key before the tester channel becomes established.

## GitHub hosting plan

### Yes: use GitHub Releases

GitHub Releases is designed for deployable binaries. It currently allows up to 1,000 assets per release, requires each asset to be below 2 GiB, and states no fixed total release-size or bandwidth limit. The Picture Shop's approximately 98 MiB APK and expected similarly sized Windows installer are a comfortable fit.

Use a **pre-release** for alpha/test builds. Create it as a draft first, upload both platform files and checksums, test the actual download links, and publish only after clean-install checks pass.

### No: do not commit builds to the repository

Do not add APKs, installers, generated `.love` files, Android SDK/JDK caches, or the `output/mobile` directory to Git history. Binary versions would permanently bloat the clone, and the local output directory contains several gigabytes of ignored tooling and intermediate products that testers do not need.

Do not use Git LFS as the release channel. GitHub's own large-file guidance recommends Releases for binary distribution, while LFS has metered storage/bandwidth and stores each changed binary version again.

Do not use GitHub Actions artifacts as tester links. They are temporary CI products, default to 90-day retention, and normally require the downloader to sign in with repository read access. Actions artifacts are useful between build jobs; Releases are for testers.

### Access and source-code privacy

The current GitHub remote is not anonymously visible, so plan as though the source repository is private.

- If anyone may download the test build, create a separate **public downloads-only repository** containing a short README and Release assets. Keep the source repository private.
- If builds must remain gated and testers already use GitHub, use an organization-owned private downloads repository and grant testers the Read role.
- Avoid adding outside testers as collaborators to a private repository owned by a personal account. Personal-account collaborators receive write access, which is inappropriate merely to download a build.
- If gated testers should not need GitHub accounts, use a restricted itch.io page for Windows and Firebase App Distribution for Android.

Public GitHub repositories are discoverable; GitHub does not offer an "unlisted public repository" mode. A restricted itch.io project can instead use download keys or a password and remain out of search results.

GitHub automatically shows source ZIP/TAR links on release pages. Give testers the exact platform asset link so they do not download the source archive by mistake.

## Signing and tester trust

### Windows

An unsigned early build can be used by a small group of known testers, but Windows SmartScreen will commonly identify a new installer as unrecognized, and managed PCs may block it. A self-signed certificate does not improve SmartScreen reputation.

Before the test expands beyond known participants:

- Sign the final fused game executable and the installer with the same trusted publisher identity on every release.
- Timestamp signatures and verify them after signing.
- Make every icon/resource change before signing.
- Publish a SHA-256 checksum.
- Never instruct testers to disable antivirus or Windows security.

Microsoft currently recommends Artifact Signing for non-Store distribution; it starts at about $9.99/month. Even a properly signed new binary may warn until publisher/file reputation develops, but consistent trusted signing displays a verified publisher and allows reputation to carry between releases. EV certificates no longer automatically bypass SmartScreen.

### Android

Use a private release/tester key, not the debug certificate. Back it up securely and never commit it. If Google Play becomes the distribution channel, use a separate upload key with Play App Signing where practical.

## Release procedure

1. Finish and review the intended source changes.
2. Fix the omitted runtime font/license and include all required LÖVE notices.
3. Set one shared tester version and increment Android `versionCode`.
4. Commit and push the release candidate so `main` matches `origin/main` and the tree is clean.
5. Run the existing release gate.
6. Complete the Android physical-device checklist for that exact APK.
7. Build the Windows x64 runtime and Inno Setup installer from the exact same `.love` archive/commit.
8. Build the Android release-signed APK from that commit.
9. Calculate SHA-256 for both deliverables.
10. Test clean install, launch, update, LAN play, save retention, and uninstall on machines that do not have the development tools installed.
11. Create a draft GitHub pre-release, attach the two packages and checksum file, and write focused test notes.
12. Download both files through their real release links and verify the checksums again.
13. Publish the pre-release and send each tester the direct link for their platform.
14. Upload the identical APK to Firebase if using the recurring private Android channel.

Never rebuild a file after publishing it under the same version. If anything changes, increment the build/version and publish a new release so bug reports remain traceable.

## Minimum acceptance checklist

### Windows

- Installs on a clean Windows 10/11 x64 PC without LÖVE installed.
- Starts from Start Menu and optional desktop shortcut.
- Shows the correct name and icon in Windows Installed Apps.
- Hosts and joins LAN play after Private-network firewall approval.
- Updates over the prior installer without losing saves.
- Uninstalls game files while leaving saves intact unless the user explicitly chooses to delete them.
- Does not require administrator rights for the standard install.

### Android

- Fresh APK install succeeds from the selected delivery link.
- The next APK installs over the previous one without uninstalling or losing saves.
- Version name/code, application ID, signature, target SDK, ABIs, and 16 KiB compatibility are verified.
- Landscape, touch, controller, app switching, save/reload, and LAN checks pass on the physical-device matrix.
- The exact APK checksum matches the published release.

### Cross-platform

- Both files report the same tester release and multiplayer protocol.
- Android can host Windows and Windows can host Android on a normal private Wi-Fi network.
- A disconnect/rejoin does not duplicate a player or corrupt the host save.
- Bug reports record release version, platform, OS/device, reproduction steps, and whether the player was host or guest.

## Suggested implementation order

1. **Release correctness:** runtime font/license, shared version naming, clean release candidate.
2. **Android identity:** durable keystore, release APK, update-over-old-build test, developer registration plan.
3. **Windows packaging:** LÖVE x64 runtime staging, game executable, Inno Setup installer, save migration.
4. **Manual tester release:** one draft GitHub pre-release with direct platform links.
5. **Android delivery polish:** Firebase App Distribution; later API 36/AAB/Play Internal Testing.
6. **Automation:** GitHub Actions builds on an explicit version tag, runs the gate, signs with protected secrets/services, publishes the Release assets, and optionally uploads the APK to Firebase.

Build and signing secrets must stay in GitHub encrypted secrets or an external signing service, never in the repository. Actions artifacts should remain temporary staging outputs; only gate-passing, signed files should become Release assets.

## Final decision

**Use GitHub Releases now as the canonical download host, with one pre-release containing two separate platform packages.** Windows receives a proper Inno Setup `.exe`; Android receives a durable release-signed `.apk`. Use Firebase App Distribution as the preferred private delivery layer for repeated Android tests, and revisit Google Play Internal Testing after the Android wrapper targets API 36 and can generate a signed AAB.

This meets the tester goal without exposing development folders, requiring LÖVE, asking Android users to run a PC installer, or bloating Git history.

## Primary references

- [GitHub: About releases and release-asset limits](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [GitHub: Linking directly to releases and assets](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
- [GitHub: Large-file guidance](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)
- [GitHub: Downloading Actions artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)
- [LÖVE: Official game-distribution guide](https://love2d.org/wiki/Game_Distribution)
- [Inno Setup: Setup and uninstaller capabilities](https://jrsoftware.org/ishelp/topic_setupsection.htm)
- [Android: App signing and update identity](https://developer.android.com/studio/publish/app-signing)
- [Android: APK versus release bundle workflows](https://developer.android.com/build/building-cmdline)
- [Firebase: App Distribution](https://firebase.google.com/docs/app-distribution)
- [Google Play: Internal and closed testing](https://support.google.com/googleplay/android-developer/answer/9845334?hl=en)
- [Google Play: 2026 target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
- [Android: 2026 developer-verification rollout](https://developer.android.com/developer-verification/guides)
- [Microsoft: SmartScreen reputation for app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
- [itch.io: Restricted projects and download access](https://itch.io/docs/creators/access-control)
