# LAN multiplayer slice

Protocol v4 makes LAN hosting device-neutral. Any Windows or Android device that can open and write its selected local save may host the authoritative shop; up to three Windows or Android workers can join over the same local network. The host owns the save and advances every durable shop system regardless of which device is hosting.

## What works now

- Manual IPv4 or hostname join on UDP port `22122`.
- One authoritative host plus up to three guests.
- Versioned, bounded, data-only protocol messages; received packets are never executed as Lua.
- Reliable connection, welcome, initial shop snapshot, leave, interaction result, and error messages.
- Unreliable realtime input, movement snapshots, and live shop state on separate ENet channels.
- The selected host save is copied to each guest when it joins. Guests do not write a second multiplayer save.
- Host-authoritative worker movement with client prediction, correction, collision, directional gait animation, name labels, and shared roster visibility.
- Revisioned synchronization of the host's date, money, inventory, jobs, pallets, machines, procurement, bills, client-email state, visitors, loading-bay door, and delivery truck.
- A nearby guest can operate the loading-bay wall switch. The host derives identity from the network peer, checks the authoritative worker position, rate-limits and deduplicates the request, and returns a correlated result.
- A nearby guest can talk to the reception customer and submit the displayed quote or decline the job.
- A nearby guest can use the office computer to inspect host-owned shop/job information and request an eligible pickup.
- A nearby guest can use the skid-wrapper console, inspect eligible finished pallets, select one, and request a wrap cycle.
- Workshop resources use exclusive, expiring host-side leases, range checks, revisions, request deduplication, and disconnect cleanup. The host device follows the same ownership rules as remote workers.
- Durable changes are accepted and saved only by the host and are sent only to fully joined peers. A shop-state update never resets or teleports a guest worker.
- Android hosting performs a writable-save preflight before opening the LAN session, keeps the display awake while hosting, and safely ends the session if the game loses foreground focus. This avoids silently suspending an authoritative mobile host.
- Android packaging asserts that the final APK contains the `INTERNET` permission.

## Physical acceptance status — August 28, 2026

The new Android-host direction was exercised with protocol v4 and APK `0.1.0-android.7`:

- A Samsung SM-S938U hosted its writable local shop at `192.168.1.137:22122`.
- The Windows PC joined as a worker and passed join, movement, and loading-bay door control.
- The PC worker opened and used both the office-computer GUI and reception-client order GUI successfully.
- The PC worker acquired the remote skid-wrapper console, first received the Android host's correct empty-pallet result, and passed the exclusive resource-lock test against a simultaneous host attempt.
- After the PC worker accepted Blue Ridge `JOB-0001`, the Android host received and cut pallet `JOB-0001-P01`, then parked it at the wrapper. The PC worker selected it and started the wrap cycle successfully. The Android save records `status = "wrapped"`, `wrapped = true`, film uses reduced from 11 to 10, and one wrapper cycle.
- APK `0.1.0-android.8` was installed on both phones. The SM-S938U resumed hosting and the Windows PC plus older Samsung SM-J410G joined simultaneously; every device reported `3/4 WORKERS`.
- The older phone held the office-computer lease while the PC was correctly refused, then released it and the PC acquired the computer normally. This physically validates two-guest workshop contention and handoff on the Android host.
- Build `.8` also disables **START CYCLE** until an eligible pallet is selected and refreshes an open wrapper panel as host-side pallets move in or out of range. Those presentation refinements have automated coverage; their dedicated physical wrapper-panel check is still pending.

The earlier, fully verified Windows-PC-host plus two-Android-guest baseline remains valid and is recorded separately in `docs/lan_multiplayer_device_test.md`.

## Player flow

1. Put every device on the same normal Wi-Fi or hotspot network.
2. On the device that owns the desired writable save, select the save slot and choose **LOCAL PLAY > HOST THIS SHOP**.
3. Read the address from the host HUD. The normal endpoint is `<host IPv4>:22122`.
4. On each worker device, choose **LOCAL PLAY > JOIN A SHOP**, enter that address, and connect.
5. Keep an Android host awake and in the game. Backgrounding it deliberately ends the LAN session; workers can then return and manually reconnect after a new host session starts.
6. Move a worker into interaction range and press **USE**. The worker waits for the host's decision before a door, client, computer, or skid-wrapper action changes authoritative state.

## Deliberate boundaries

- No internet matchmaking, relay, or NAT traversal.
- No automatic host discovery yet; manual address entry is the dependable fallback.
- No automatic reconnect or host migration.
- Guest-safe workshop access currently covers the loading-bay door, reception customer quote/decline actions, office-computer inspection and pickup request, and skid-wrapper selection/start request.
- The pallet jack, cutter, windmill, vendor, and delivery truck remain host-only. Their movement, minigames, inventories, or multi-step transactions need their own authority rules before guest control is enabled.
- The skid-wrapper control path has completed one physical Android-host/PC-worker cycle. Additional-device contention and disconnect scenarios remain in the acceptance matrix.
- A device that cannot pass the writable-save preflight cannot host. It may still join as a worker; this is the expected role for the older Android phone with its known local-save-directory limitation.
- All devices must run the same protocol-compatible build. APK `.8` has passed the Android-host three-worker join and office-resource contention checks; its live wrapper-list presentation still needs a dedicated physical pass.
- A router's guest-network or client-isolation setting can block LAN traffic even when every device has internet access.

Use `docs/lan_multiplayer_device_test.md` for the exact acceptance matrix and the preserved PC-host three-device results.
