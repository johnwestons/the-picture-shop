# Android 118 development pre-release

## Build identity

- Version: `0.1.0-android.118` (`versionCode` 118)
- Application ID: `com.thepictureshop.game`
- Multiplayer protocol: 79
- Source commit: `c9767f0a9aa71b103f2ff335b5bc1e492764d67f`
- APK: `ThePictureShop-0.1.0-android.118-debug.apk` (1,039,853,942 bytes)
- APK SHA-256: `a67a79bb1a7c37075d1ae1687d04655f4f97cf3d39704582832f55a81a8aa975`
- Package SHA-256: `e70c481558331788894561ede955e5e9c72d4ef484918b8c01adf6e01b6633a9`
- Android 117 and 118 use the same signing certificate, so 118 can update 117 in place.

## Included updates

- Clients join on the New Haven bridge with motorcycle controls, receive an
  apartment not used by the host or other clients, and keep their own household,
  deliveries, money, bills, and shop employment. Hosts can claim an existing
  client save for an unrecognized device or clear a client slot for a new identity.
- Apartment deliveries use food bags and small, medium, or large cartons, placed
  where they are visible and easy to reach.
- New households start with a directional sleeping bag. Sleeping bags and beds
  support time advancement and alarms; sleeping directly on the floor remains
  available.
- Trucks already queued can finish loading or unloading after a company stops
  dispatching. A truck at the head of the queue can reach its dock without
  waiting for an employee to be present or on shift.
- The update also includes town, medical, calendar, and household improvements.

## Verification

- Gameplay readiness: **PASS**, 56 stages and 48,074 checks. This includes
  12,195 core checks each for desktop and forced-mobile layouts, the full ordered
  town-route coverage, and the client apartment, profile reset, employment,
  delivery, bridge arrival, and sleep checks.
- Tooling regression suite: **PASS**, 108 tests.
- Raster asset audit: **PASS**, 593 checks.
- APK signature, permissions, package identity, embedded game archive, and
  16 KB native-library alignment: **PASS**. The APK certificate fingerprint
  matches Android 117.
- The S25 was not visible to ADB, so the APK was not installed or launched on a
  physical phone. The automated forced-mobile and packaged-APK checks do not
  certify physical-device or public-Internet multiplayer behavior.
- This is a debug development build. The bundled native Android gateway and
  crypto components are marked non-production by their build reports.

## Download

[Download Android 118](https://github.com/johnwestons/the-picture-shop/releases/download/0.1.0-android.118/ThePictureShop-0.1.0-android.118-debug.apk)
