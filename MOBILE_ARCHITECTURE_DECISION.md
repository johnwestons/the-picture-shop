# Mobile architecture decision

**Date:** August 25, 2026  
**Status:** Active

## Decision

Windows and Android ship from the same `main.lua`, `conf.lua`, `src/`, generated runtime artwork,
save identity, save schema, and smoke suite. Android is not a copied gameplay fork.

The platform boundary is intentionally small:

- `src/mobile_controls.lua` translates multi-touch into the shared keyboard/pointer actions.
- `src/controller.lua` translates standard LÖVE gamepad input and supplies a panel cursor.
- `main.lua` and `src/app.lua` wire platform callbacks into the shared input router.
- `mobile/`, `BUILD_ANDROID.ps1`, and the two Android build tools describe packaging only.

Every build stages the current shared source directly into an ignored `output/mobile` area. Runtime
art remains canonical under `assets/generated`; generated packages, wrapper sources, SDKs, and APKs
are never a second source tree.

## Lessons retained from Mouse Frontier

- Keep mobile adaptation at the input and packaging edges.
- Use the same private save identity across PC and Android builds.
- Lock modern Android devices to sensor landscape in the wrapper.
- Force the embedded `.love` archive to mount, verify its byte size, and cache it only until a newer APK.
- Remove unused app permissions, use a unique application ID, and verify signature and identity.
- Rebuild LÖVE 11.5 native libraries with 16 KB ELF/ZIP alignment and static libc++ so modern Android
  devices do not fall into page-size compatibility mode.
- Fail installation unless exactly one authorized device is present and the real game reaches a unique
  startup marker rather than LÖVE's fallback screen.
- Treat focus loss as an input-cancel and save boundary so touch or controller buttons cannot stick.

## Verification boundary

Each Android update must pass the desktop smoke suite, packaged `.love` smoke suite, APK embedded-game,
signature and application-ID checks, and physical-device startup verification. Touch and controller
checks are part of the input regression suite.
