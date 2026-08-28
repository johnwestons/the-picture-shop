# LAN multiplayer device test

Use this checklist for protocol v5's supported LAN direction: any Windows or Android device with a writable selected save can host and own the authoritative shop, while up to three PC or Android devices join as workers. Use the same protocol-compatible game build throughout one pass.

## Prepare the build and devices

1. Run `./BUILD_ANDROID.ps1` once and keep the resulting APK unchanged for the entire pass. Confirm `output/mobile/apk-report.json` contains `"internetPermission": true`.
2. Install that exact APK on each participating phone. If multiple authorized phones remain connected, select each one explicitly rather than relying on an arbitrary device choice.
3. Record each device's model, operating-system version, CPU ABI, build version, and role.
4. Put the host and workers on the same normal Wi-Fi network. Do not use a guest SSID, and temporarily disable VPNs on every device.
5. Record the host IPv4 address shown in the game rather than reusing an address from an earlier test; DHCP can change it.

## Host preparation

### Windows host

1. In Windows Settings, verify the active Wi-Fi or Ethernet connection is a **Private network**. Only do this on a trusted home or test network.
2. If Windows Defender Firewall asks, allow LÖVE on **Private networks only**. Do not disable the firewall. If no prompt appears and joining fails, add only the narrow inbound UDP rule needed for the gameplay port.
3. Keep the PC awake during the pass.

### Android host

1. Select a local slot that the phone can write. **HOST THIS SHOP** must fail clearly before listening if the save preflight cannot safely write, read, promote, and clean up a temporary save.
2. Leave the game in the foreground. While hosting, the game keeps the display awake.
3. Backgrounding or unfocusing the Android game intentionally ends the authoritative LAN session. This is a safety rule, not automatic reconnect behavior.
4. Record the Android host address shown in the HUD, including UDP port `22122`.

## Protocol v5 interaction pass

1. On the chosen host, select the save slot and choose **LOCAL PLAY > HOST THIS SHOP**.
2. On each worker, choose **LOCAL PLAY > JOIN A SHOP**, enter the host's IPv4 address manually, and join. Entering `address:port` is also supported.
3. Confirm every worker loads the host's selected shop, receives its own spawn, and shows the full connected roster.
4. Move all workers, including simultaneous movement when more than one guest is present. Verify independent movement, sensible collision, walk animation, name labels, camera behavior, and host-authoritative corrections.
5. Advance or alter the shop on the host. Confirm workers receive date, money, inventory, jobs, pallet, machine, visitor, door, and truck state without rejoining or being reset to spawn.
6. At the loading-bay wall switch, press **USE** as a guest. Confirm the guest waits for host verification, every device shows the same door result exactly once, and the contextual action disappears when the worker leaves range.
7. At reception, use the customer as a guest. Confirm the client-order GUI is based on host state and that submitting the displayed quote or declining is committed exactly once by the host.
8. At the office computer, use it as a guest. Confirm the GUI shows host-owned read-only shop/job information and that only an eligible pickup request can change state.
9. At the skid wrapper, use it as a guest. Confirm the console shows the host's live cycle and eligible-pallet state. When no pallet is eligible, the list must explain that condition and **START CYCLE** must be disabled in build `.8` or later. While the panel stays open, park and remove an eligible pallet on the host and confirm the row appears and disappears live. Select an available pallet, start once, and verify the host owns the cycle and saved result.
10. Inspect a nearby pallet's paper work order as a guest. Confirm it uses the host-mirrored record, closes locally, sends no mutation request, and creates no guest save.
11. At the pallet jack, acquire it as a guest and confirm no blocking console opens. Drive empty, lift one exact eligible pallet, drive loaded, and lower it on a green cell. Verify the host validates every action, all observers keep the operator attached to the jack, the pallet never duplicates or disappears, and a non-owner sees **BUSY** and cannot take control.
12. Try the cutter, windmill, vendor, delivery truck, and machine relocation as a guest. Each must remain host-only and must not open an unsafe guest screen, alter the shop, or create a guest save.
13. Disconnect a worker while it owns a workshop console, then have another worker acquire it. Repeat while the worker owns a loaded pallet jack: the loaded jack must park safely, keep its pallet, and be reclaimable.
14. Play for 15 minutes, watching for warping, stuck input, stale shop values, duplicate actions, mismatched sound/animation, or a visitor that appears on only one device. End the host session, reload the host's save offline, and verify the final durable state.

## Disconnect and hotspot matrix

| Scenario | Required result |
| --- | --- |
| Android guest backgrounds the app for 15 seconds, then returns | No held touch input remains. If Android dropped the connection, a clear error appears and the phone can manually rejoin for a fresh snapshot. |
| Android host backgrounds the app | The authoritative session ends safely and workers receive a clear host-ended/disconnected result; it does not continue invisibly in the background. |
| A guest disables Wi-Fi, then restores it | The host and other workers continue. The disconnected worker reports the loss or times out, then can cancel and manually rejoin. |
| A guest force-stops the app while holding a workshop lease or loaded pallet jack | Its worker disappears and its lease is released after the host detects the disconnect; a loaded jack parks without dropping or duplicating its pallet, and the remaining session continues. |
| Host closes unexpectedly | Workers show a clear host-ended message; the last committed host save remains valid. |
| PC creates a Windows Mobile Hotspot | Manual IPv4 join works without external internet access when the hotspot does not isolate clients. |
| New phone creates a system hotspot and also hosts | PC and older phone can join manually when the handset permits communication between hotspot clients and the host app; otherwise record the platform/network limitation. |
| Devices use different router bands, such as 2.4 GHz and 5 GHz | Joining works when both bands share the same LAN; a blocked guest/client-isolated network fails clearly. |

For every scenario, record the APK SHA-256, host address and port, device details and roles, join time, movement quality, interaction results, disconnect reason, and pass/fail result. Automatic discovery, reconnect, and host migration are not part of this slice.

## Android-host protocol v5 pallet-logistics results — August 28, 2026

- Samsung SM-S938U (Android 16, `arm64-v8a`) hosted writable slot 3 at `192.168.1.137:22122`.
- Samsung SM-J410G (Android 8.1, 32-bit `armeabi-v7a`) and the Windows PC joined as workers. Host and both guests reported `3/4 WORKERS`.
- Both phones ran APK `0.1.0-android.9` (`versionCode` 9). The physically tested APK SHA-256 is `09e789a567b7c6e40c08d2d46639d651ee7e5dad0e8ad458b74919aadfa2ba76`.
- The older phone acquired the pallet jack without opening a modal, drove it across the shop, lifted exact pallet `JOB-0001-P02`, drove loaded, and lowered it at the host-snapped clear grid position. Host, owner, and PC observer showed the same jack, operator, carried pallet, and final drop.
- The Android host approached the occupied jack, displayed **BUSY**, and received `Another worker is using that workshop control.` Its rejected request did not disturb the older phone's ownership.
- The PC observer opened and closed P2's mirrored paper work order read-only. No guest save or host mutation was involved.
- The older phone was force-stopped while carrying P2. After disconnect detection, the host roster fell to `2/4`, the loaded jack stayed safely parked, the Android host reclaimed it, lowered P2, and parked the jack.
- Representative evidence captures: `output/multiplayer-captures/v9-old-p2-lifted.png`, `output/multiplayer-captures/v9-host-contention-rejected.png`, `output/multiplayer-captures/v9-host-loaded-recovery.png`, and `output/multiplayer-captures/v9-host-recovery-complete.png`.
- Host exit returned the PC worker to the join screen with `The host connection ended.` and preserved the authoritative save.

## Android-host protocol v4 results — August 28, 2026

This is a physical Android-host pass and remains distinct from the earlier PC-host baseline below.

- Samsung SM-S938U hosted a writable local shop at `192.168.1.137:22122` using APK `0.1.0-android.7` and protocol v4.
- The Windows PC joined as a worker and passed joining, movement, and loading-bay dock-door control.
- The connected PC worker opened and used the office-computer GUI and reception-client order GUI successfully.
- The PC worker acquired the skid-wrapper console and received the Android host's correct empty eligible-pallet result. While the PC held the console, the Android host was rejected; after the PC released it, the host acquired it, passing both halves of the exclusive-lock check.
- The PC worker accepted Blue Ridge `JOB-0001`; the Android host received, cut, and staged `JOB-0001-P01`; and the PC selected that pallet and started the wrap cycle. The user reported the cross-device result working perfectly. A read-only post-test save check confirms `status = "wrapped"`, `wrapped = true`, film uses `10` (from `11`), and skid-wrapper cycles `1`.
- Evidence capture: `output/multiplayer-captures/android-v4-host-wrapper-cycle-pass.png`.
- APK `0.1.0-android.8` was installed on both Android devices. The SM-S938U hosted while the Windows PC and older SM-J410G joined simultaneously; all three screens reported `3/4 WORKERS`.
- The tested `.8` APK SHA-256 is `c99228edbb881daa1057d561fbcfa79cc3646435446246ddb017a4908ea7880d`.
- The older phone acquired the office computer, the PC was correctly told `Another worker is using that resource.`, and after the older phone closed the panel the PC acquired it normally. This passed two-guest contention and lease handoff.
- Build `.8`'s disabled empty **START CYCLE** button and live open-panel pallet refresh later passed their physical wrapper-panel test; the synchronized cycle and sound also completed successfully.
- Three-worker evidence captures: `output/multiplayer-captures/android-v4-eight-host-three-player.png` and `output/multiplayer-captures/android-v4-eight-old-phone-three-player.png`.

## Verified PC-host three-device baseline — August 28, 2026

This preserved baseline used the earlier loading-bay-door interaction slice. It does not by itself validate protocol v4 workshop access or Android hosting.

- Windows PC host at `192.168.1.246:22122` with two simultaneous Android guests; all devices reported `3/4 WORKERS`.
- Samsung SM-S938U running Android 16 on `arm64-v8a`.
- Samsung SM-J410G running Android 8.1 on 32-bit `armeabi-v7a`. Its first launch took about 15 seconds while the 83 MB game package was copied and initialized, then it ran normally.
- APK `0.1.0-android.6` (`versionCode` 6), SHA-256 `b857676b51765c7bee10eca49b63ba309b425bfe3d2d4e3737d4ef1387d2ee3b`.
- Manual IPv4 join, simultaneous three-worker visibility, independent guest movement, authoritative host position, and contextual **DOOR** action all passed on both phones.
- A phone press opened the loading-bay door across the PC and both Android devices; another press after it settled closed it across all three. Door animation and opening sound remained synchronized everywhere.
- Both phones displayed `Loading-bay switch activated. Door movement is synced from the PC host.` No fatal, Lua, protocol, invalid-environment, or ANR error appeared in either post-test runtime log.
- Evidence captures: `output/multiplayer-captures/android-v3-new-phone-three-player.png` and `output/multiplayer-captures/android-v3-old-phone-three-player.png`.

The older phone reports that Android 8.1 cannot create the normal local save directory. It can still join as a worker because the active host exclusively owns and writes the multiplayer save, but it should not be counted as a host until it passes the writable-save preflight.
