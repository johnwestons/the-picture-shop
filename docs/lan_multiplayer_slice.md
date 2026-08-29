# LAN multiplayer slice

Protocol v7 makes LAN hosting device-neutral. Any Windows or Android device that can open and write its selected local save may host the authoritative shop; up to three Windows or Android workers can join over the same local network. The host owns the save and advances every durable shop system regardless of which device is hosting.

## What works now

- Manual IPv4 or hostname join on UDP port `22122`.
- One authoritative host plus up to three guests.
- Versioned, bounded, data-only protocol messages; received packets are never executed as Lua.
- Reliable connection, initial shop snapshot, leave, interaction result, and error messages. A joining
  worker's bounded welcome contains the host and that assigned worker; the rest of the roster arrives on
  the next motion ticks.
- Unreliable realtime input, pallet-jack state, and machine poses use separate ENet channels. At 12 Hz,
  player motion is sent as one MTU-safe player shard per packet and merged by player ID on each client.
  This keeps all four full-precision players below the 1,200-byte realtime packet ceiling.
- The selected host save is copied to each guest when it joins. Guests do not write a second multiplayer save.
- Host-authoritative worker movement with client prediction, correction, collision, directional gait animation, name labels, and shared roster visibility.
- Revisioned synchronization of the host's date, money, inventory, jobs, pallets, machines, procurement, bills, client-email state, visitors, loading-bay door, and delivery truck.
- A nearby guest can operate the loading-bay wall switch. The host derives identity from the network peer, checks the authoritative worker position, rate-limits and deduplicates the request, and returns a correlated result.
- A nearby guest can talk to the reception customer and submit the displayed quote or decline the job.
- A nearby guest can use the office computer to inspect host-owned shop/job information and request an eligible pickup.
- A nearby guest can use the skid-wrapper console, inspect eligible finished pallets, select one, and request a wrap cycle.
- A guest can inspect a pallet's mirrored paper work order locally without taking a workshop lease, sending a mutation request, or writing a guest save.
- The pallet jack is a host-authoritative shared vehicle. One worker at a time may acquire it, drive it with predicted local input, lift an exact host-validated pallet, carry it across the shop, lower it on a host-snapped clear grid cell, and park it. Other devices receive the live jack, operator, candidate, and carried-pallet view.
- When the host relocates the cutter, skid wrapper, or Windmill, protocol v7 sends all three terminal/live machine poses at a fixed 12 Hz in the pallet-jack snapshot. The machine pose and jack share one authoritative server tick, so peers validate and render the active machine attached to the empty host-owned jack throughout movement, stops, and turns.
- Relocation remains a host-only floor operation. While a machine is moving, durable snapshots and saves retain its last committed floor pose. A successful green-cell placement commits the new pose; an interrupted or rejected placement cannot persist an in-transit machine.
- Pallet-jack ownership is cleaned up on timeout or disconnect. A loaded jack is parked without losing or duplicating its pallet, then can be reclaimed by another worker.
- Workshop resources use exclusive, expiring host-side leases, range checks, revisions, request deduplication, and disconnect cleanup. The host device follows the same ownership rules as remote workers.
- Durable changes are accepted and saved only by the host and are sent only to fully joined peers. A shop-state update never resets or teleports a guest worker.
- Android hosting performs a writable-save preflight before opening the LAN session, keeps the display awake while hosting, and safely ends the session if the game loses foreground focus. This avoids silently suspending an authoritative mobile host.
- Android packaging asserts that the final APK contains the `INTERNET` permission.

## Physical acceptance status — August 28, 2026

Protocol v7 and Android build `0.1.0-android.11` completed their targeted Android-host four-device physical
acceptance on August 28, 2026. The exact APK is
`output/mobile/ThePictureShop-0.1.0-android.11-debug.apk`, 102,485,249 bytes, SHA-256
`88549621c829201171475cb38513ac1433b3292595b32cc3b0dd30fb67017940`; its mobile package reports clean
source commit `8b5b80d28334853986a30e5e84b42ed88c53cbce`. Automated smoke completed 1,113 passes with 0 failures.

- Samsung SM-S938U hosted at `192.168.1.137:22122`; Samsung SM-S928U1, Samsung SM-J410G, and a Windows PC
  worker ran the same protocol-v7 source. Every device reached `4/4 WORKERS`, and all participants moved
  independently.
- Cutter, skid-wrapper, and Windmill live relocation remained synchronized across the host and all three
  observers through rotations, stop/restart transitions, and placement. The cutter stayed live beyond the
  30-second durable fallback; a red placement rejection followed by a green placement produced no snap-back
  or duplicate sprite.
- A guest operated the dock door during wrapper relocation and opened the computer/client screen during
  Windmill relocation without disturbing the live machine pose.
- The SM-J410G exited cleanly: every remaining screen showed `3/4 WORKERS` with no stale avatar. Rejoining
  restored exactly one avatar, `4/4 WORKERS`, and independent movement.
- Android LÖVE logs were clean.

This was a targeted join, movement, machine-pose, concurrent-interaction, and rejoin pass. It did not run
the full 15-minute soak, hotspot matrix, or final offline save reload, so those broader checks remain open.

The superseded `.10` APK, SHA-256
`151a0958d0d8215ee3c38c64cbf35db3af9a58d5182d01d2e2018cd824159155` (102,481,341 bytes), reached an
Android host plus two Android guests (`3/4 WORKERS`), but adding the Windows PC as the fourth participant
exposed the roster overflow. That diagnostic run is not a physical acceptance result.

The previous completed physical acceptance was the pallet-logistics slice exercised with protocol v5 and APK `0.1.0-android.9`:

- Samsung SM-S938U hosted its writable slot 3 shop at `192.168.1.137:22122`; a Windows PC and Samsung SM-J410G joined simultaneously and every active device reported `3/4 WORKERS`.
- The older Android worker acquired the pallet jack, drove it across the workshop, lifted exact pallet `JOB-0001-P02`, moved it while loaded, and lowered it on the host-validated grid. The host and PC observer stayed synchronized throughout.
- While the older phone owned the loaded jack, the Android host displayed **BUSY** and its acquisition attempt was rejected without changing ownership.
- The PC observer kept the remote operator attached to the moving jack and showed the carried/lowered pallet in the same position. It also opened and closed P2's mirrored paper work order read-only.
- The older phone was force-stopped while carrying P2. After disconnect detection the worker disappeared, the loaded jack remained safely parked, the Android host reclaimed it, lowered P2, and parked the empty jack.
- The tested `.9` APK SHA-256 is `09e789a567b7c6e40c08d2d46639d651ee7e5dad0e8ad458b74919aadfa2ba76`.

The preceding Android-host workshop pass used protocol v4 and APK `0.1.0-android.7`/`.8`:

- A Samsung SM-S938U hosted its writable local shop at `192.168.1.137:22122`.
- The Windows PC joined as a worker and passed join, movement, and loading-bay door control.
- The PC worker opened and used both the office-computer GUI and reception-client order GUI successfully.
- The PC worker acquired the remote skid-wrapper console, first received the Android host's correct empty-pallet result, and passed the exclusive resource-lock test against a simultaneous host attempt.
- After the PC worker accepted Blue Ridge `JOB-0001`, the Android host received and cut pallet `JOB-0001-P01`, then parked it at the wrapper. The PC worker selected it and started the wrap cycle successfully. The Android save records `status = "wrapped"`, `wrapped = true`, film uses reduced from 11 to 10, and one wrapper cycle.
- APK `0.1.0-android.8` was installed on both phones. The SM-S938U resumed hosting and the Windows PC plus older Samsung SM-J410G joined simultaneously; every device reported `3/4 WORKERS`.
- The older phone held the office-computer lease while the PC was correctly refused, then released it and the PC acquired the computer normally. This physically validates two-guest workshop contention and handoff on the Android host.
- Build `.8` also disables **START CYCLE** until an eligible pallet is selected and refreshes an open wrapper panel as host-side pallets move in or out of range. The later physical wrapper pass completed successfully, including the synchronized cycle result and sound.

The earlier, fully verified Windows-PC-host plus two-Android-guest baseline remains valid and is recorded separately in `docs/lan_multiplayer_device_test.md`.

## Player flow

1. Put every device on the same normal Wi-Fi or hotspot network.
2. On the device that owns the desired writable save, select the save slot and choose **LOCAL PLAY > HOST THIS SHOP**.
3. Read the address from the host HUD. The normal endpoint is `<host IPv4>:22122`.
4. On each worker device, choose **LOCAL PLAY > JOIN A SHOP**, enter that address, and connect.
5. Keep an Android host awake and in the game. Backgrounding it deliberately ends the LAN session; workers can then return and manually reconnect after a new host session starts.
6. Move a worker into interaction range and press **USE**. The worker waits for the host's decision before a door, client, computer, skid-wrapper, or pallet-jack action changes authoritative state.

## Deliberate boundaries

- No internet matchmaking, relay, or NAT traversal.
- No automatic host discovery yet; manual address entry is the dependable fallback.
- No automatic reconnect or host migration.
- Guest-safe workshop access currently covers the loading-bay door, reception customer quote/decline actions, office-computer inspection and pickup request, skid-wrapper selection/start request, read-only pallet paperwork, and pallet-jack transport.
- Cutter and Windmill consoles, vendor and delivery-truck inventory/actions, and initiating or placing a machine relocation remain host-only. Their minigames, inventories, or multi-step transactions need their own authority rules before guest control is enabled.
- Protocol v7 peers observe the host's live cutter, wrapper, or Windmill relocation, including its final stationary pose, on the pallet-jack tick. Observation does not grant a guest relocation control or write authority.
- A device that cannot pass the writable-save preflight cannot host. It may still join as a worker; this is the expected role for the older Android phone with its known local-save-directory limitation.
- All devices must run the same protocol-compatible build. APK `.9` passed the Android-host three-device pallet-logistics, contention, read-only paperwork, and loaded-disconnect recovery checks. `.10` was not accepted after its fourth-player overflow. `.11` passed the targeted four-device join, independent-movement, machine-relocation observation, concurrent guest-interaction, and clean leave/rejoin scope described above.
- A router's guest-network or client-isolation setting can block LAN traffic even when every device has internet access.

## Completed roadmap target

- Protocol v7 replicates the fixed-rate live and terminal pose of a host-relocated cutter, skid wrapper, or Windmill, tied to the same authoritative tick as the pallet jack. Automated coverage includes the MTU-safe one-player motion shards, and the targeted `.11` four-device physical pass is complete.

## Next roadmap targets

1. Add a host-authoritative cutter console for guest loading, setup, guarded cutting, repeat lifts, unload, and maintenance transitions.
2. Add the Windmill console with the same explicit lease, command, revision, and disconnect rules.
3. Add vendor and delivery-truck interactions, including inventory and manifest operations, without allowing guest-side durable writes.
4. Improve session convenience after the gameplay systems are covered: LAN discovery, reconnect/resume, and eventually deliberate host migration.

Use `docs/lan_multiplayer_device_test.md` for the exact verified four-device result, its remaining untested matrix items, and the preserved historical three-device results.
