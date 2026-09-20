# LAN multiplayer slice

The current host/guest parity inventory and ordered completion record are maintained in
`docs/guest_worker_capability_matrix.md`.

Current source uses protocol v16. LAN hosting remains device-neutral: any Windows or Android device that can open and write its selected local save may host the authoritative shop; up to three Windows or Android workers can join over the same local network. The host owns the save and advances every durable shop system regardless of which device is hosting.

September 12 source-only GUI parity update: guests now use shared host renderers and hit targets for
cutter production/service, wrapper production/service, all Windmill pages, the full CritterNet computer,
reception, vendors, trucks, and the wall phone. V16 adds bounded office transactions, a phone lease and
call-ID commands, exact blade-bolt display, and compact host-owned press setup visuals. It preserves the
v15 actual paper dimensions/spoil fields and the 1,200-byte realtime packet ceiling. The September 13
guest cutting/printing regressions add spoil/replacement, two-color production, reconnect and
estimate-to-payment coverage. They fix next-pallet loading after discard/unload and the feeder setup
network allowlist. Both desktop and forced-mobile smoke pass 2,285 checks.
No connected devices were accessed or updated; old installs must
be updated together before testing this protocol. No v16 physical-device pass is claimed.

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
- A nearby guest can open a ready delivery truck, inspect a compact host-owned paged manifest, unload customer, supplier, and machine deliveries, load completed-job pickups, and release the truck only after its manifest is empty.
- A nearby guest can use the Polar cutter console. The host owns pallet/generic-stock loading, program and backgauge setup, rotation, positioning, clamp and guarded cut validation, safety reset, lift return/repeat, and final unload. During multiplayer, either cut button on the host or a guest sends the same single host-validated cut request; ordinary offline play retains the original two-control operation. Idle load candidates and the live machine cycle refresh at 12 Hz. E-STOP and barrier-block use a separate urgent pending lane, remain available while an ordinary command reply is delayed, and are serviced before the host advances the blade that frame.
- A nearby guest can use the complete Windmill console. Plate ordering and in-house platemaking, all six setup checks, operating controls, proof/artwork approval, the production run, cleanup/unload, maintenance lockout/tasks, and technician booking execute on the host. Clients send only bounded control intent: plate timing accuracy and setup scores are calculated from host-owned sessions. A dedicated 12 Hz runtime stream carries counters, controls, candidates, setup/service progress, and the plate marker without forcing a save for every sheet. E-STOP has the urgent safety lane and is processed before the host advances the press that frame.
- A guest can inspect a pallet's mirrored paper work order locally without taking a workshop lease, sending a mutation request, or writing a guest save.
- The pallet jack is a host-authoritative shared vehicle. One worker at a time may acquire it, drive it with predicted local input, lift an exact host-validated pallet, carry it across the shop, lower it on a host-snapped clear grid cell, and park it. Other devices receive the live jack, operator, candidate, and carried-pallet view.
- A Guest Worker with the exclusive pallet-jack lease can relocate the cutter, skid wrapper, or Windmill. The guest submits only a machine index, turn intent, or bounded grid-cell token; the host validates installation, idle/unloaded state, console occupancy, range, and floor clearance.
- Protocol v14 sends all three terminal/live machine poses at a fixed 12 Hz in the pallet-jack snapshot. The machine pose and jack share one authoritative server tick, so peers validate and render the active machine attached to the worker-owned empty jack throughout movement, stops, and turns. A successful green-cell placement commits the new pose; disconnect recovery locks to a valid snapped cell or the relocation origin before releasing the jack.
- Pallet-jack ownership is cleaned up on timeout or disconnect. A loaded jack is parked without losing or duplicating its pallet, then can be reclaimed by another worker.
- Workshop resources use exclusive, expiring host-side leases, range checks, revisions, request deduplication, and disconnect cleanup. The host device follows the same ownership rules as remote workers.
- Durable changes are accepted and saved only by the host and are sent only to fully joined peers. A shop-state update never resets or teleports a guest worker.
- Android hosting performs a writable-save preflight before opening the LAN session, keeps the display awake while hosting, and safely ends the session if the game loses foreground focus. This avoids silently suspending an authoritative mobile host. Windows is therefore the recommended stable host whenever the host may need to switch apps; true Android background hosting remains a separate foreground-service task.
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
6. Move a worker into interaction range and press **USE**. The worker waits for the host's decision before a door, client, computer, cutter, Windmill, skid-wrapper, or pallet-jack action changes authoritative state.

## Deliberate boundaries

- Local Play performs no internet matchmaking, relay, or NAT traversal.
- A separate engineering-only Direct path has passed Android/Android and PC/Android Wi-Fi-to-cellular
  tests, including one guarded packet-privacy run, but remains unavailable in production.
- Best-effort host discovery is available on Local Play. It supplies only an expiring address hint; manual address entry remains the dependable fallback on client-isolated or broadcast-blocking networks, and the normal protocol hello/snapshot still gates entry.
- An established LAN guest makes up to six cancelable fresh-session reconnect attempts with backoff. Reconnect never resumes a prior lease or guest state. There is still no automatic host migration, and a changed host address requires selecting the newly discovered host or entering it manually.
- Guest-safe workshop access currently covers the loading-bay door, reception customer quote/decline actions, office-computer inspection and pickup request, supplier catalog inspection and purchasing, delivery-truck manifests and cargo actions, Polar cutter production/safety/maintenance controls, the complete Windmill plate/setup/proof/run/service workflow, skid-wrapper selection/start request, read-only pallet paperwork, and pallet-jack transport.
- Guest relocation requires the pallet-jack lease and an empty jack. Non-owners observe the live machine but cannot attach, turn, place, or persist it.
- A device that cannot pass the writable-save preflight cannot host. It may still join as a worker; this is the expected role for the older Android phone with its known local-save-directory limitation.
- All devices must run the same protocol-compatible build. APK `.9` passed the Android-host three-device pallet-logistics, contention, read-only paperwork, and loaded-disconnect recovery checks. `.10` was not accepted after its fourth-player overflow. `.11` passed the targeted four-device join, independent-movement, machine-relocation observation, concurrent guest-interaction, and clean leave/rejoin scope. `.12` was rejected after its cross-snapshot overlay crash. `.13` passed the targeted Android-host three-device cutter workflow, contention, urgent E-stop, disconnect/reacquire, and rejoin checks. Protocol-v9 Windmill candidates did not complete their normal-app physical gate. Protocol-v10 / Android `.16` vendor purchasing, protocol-v11 / Android `.17` truck logistics, protocol-v12 / Android `.18` cutter maintenance, protocol-v13 / Android `.19` wrapper maintenance, and protocol-v14 / Android `.20` guest machine relocation have automated acceptance but still require normal-app physical acceptance. Isolated Direct engineering packages do not satisfy that gate.
- A router's guest-network or client-isolation setting can block LAN traffic even when every device has internet access.

## Completed roadmap target

- Protocol v7 replicates the fixed-rate live and terminal pose of a host-relocated cutter, skid wrapper, or Windmill, tied to the same authoritative tick as the pallet jack. Automated coverage includes the MTU-safe one-player motion shards, and the targeted `.11` four-device physical pass is complete.
- Protocol v8 adds the host-authoritative remote cutter production console, bounded live runtime/candidate snapshots, exact resource revisions, urgent safety preemption, safe disconnect/reset behavior, and sale/relocation interlocks. Automated coverage completed with 1,217 passes and 0 failures, and the targeted `.13` Android-host three-device cutter pass is complete.
- Protocol v9 adds the complete host-authoritative remote Windmill console, a bounded 12 Hz runtime stream, host-owned plate timing/setup scoring/maintenance sessions, urgent E-STOP preemption, safe timeout/disconnect release, and sale/relocation interlocks. Automated coverage is complete; normal-app `.14` LAN/Windmill physical-device acceptance remains pending.
- Protocol v10 adds the host-authoritative supplier catalog and stock/used-machine purchasing. Guests send only a bounded row index; the host revalidates the live catalog, range, cash, availability, resource revision, and exclusive lease, saves an accepted purchase once, and returns a compact refreshed catalog. All five catalogs fit the realtime packet ceiling. Automated coverage completed with 1,733 passes and 0 failures; three-phone physical acceptance remains pending.
- Protocol v11 adds host-authoritative delivery-truck manifests and cargo operations. Guests send only a page-local row index or bounded navigation/close intent; the host resolves the cargo, revalidates range, truck state, manifest contents, revision, and exclusive lease, saves an accepted cargo mutation exactly once, and refuses departure while cargo remains. Customer, supplier, machine, and pickup manifests plus a real impaired guest-to-host session round trip are covered. Automated coverage completed with 1,744 passes and 0 failures; PC-host plus two-phone physical acceptance remains pending.
- Protocol v12 adds the host-authoritative cutter-maintenance experience: ordered lockout and preparation, view/tool/point-based lubrication, gearbox inspection/top-up, blade removal and sleeving, and explicit technician scheduling. The host owns transient progress, revalidates range and idle-machine state, blocks production during service, consumes and saves one maintenance kit only at successful completion, and discards unfinished work on disconnect. Strict packets and an impaired real-session round trip are covered. Automated coverage completed with 1,757 passes and 0 failures; PC-host plus two-phone physical acceptance remains pending.
- Protocol v13 adds the host-authoritative skid-wrapper service experience: all four machine-specific component tasks, current-target selection, host-scored misses and repair quality, cycle/sale/rotation/relocation interlocks, exact-once maintenance-kit consumption and saving, and safe transient rollback on cancellation or disconnect. Strict bounded packets and a duplicated impaired-session completion are covered. Automated coverage completed with 1,766 passes and 0 failures; PC-host plus two-phone physical acceptance remains pending.
- Protocol v14 adds Guest Worker machine relocation for the cutter, skid wrapper, and Windmill. The pallet-jack lease carries bounded machine and placement-cell intent while the host owns readiness checks, motion, collision, rotation, placement, saving, and disconnect recovery. Automated authority and impaired-session coverage completed with 1,777 passes and 0 failures. A two-phone Android-host pass completed cutter attach, movement, rotation, and placement, and the exact final APK cold-launched on both phones; wrapper/Windmill relocation, two-guest contention, invalid-cell rejection, disconnect recovery, offline host-save reload, and the PC-host topology remain pending.
- Protocol v14 / Android `.21` adds a Guest Worker session panel without widening network authority. LAN and Direct guests can inspect the four-worker roster, HOST/YOU identity, host-save ownership, RTT quality, current shared-control owner, their own active control, and ordinary/urgent requests waiting for host verification. Display records are detached from session state and contain no transport peers, positions, lease tokens, or save data. Direct approval, removal, and invitation controls remain exclusive to the Direct host. Automated coverage completed with 1,786 passes and 0 failures; the two-phone aspect-ratio and clarity pass remains pending.
- Protocol v14 / Android `.22` adds bounded UDP LAN discovery and fresh-session reconnect. Discovery replies are nonce-correlated, protocol-matched, sanitized, capped, deduplicated, and expired; they never bypass the existing join handshake. Reconnect keeps only the public host address and display name, performs at most six cancelable attempts with backoff, and receives a fresh authoritative snapshot after the old host generation removes the guest. Automated coverage completed with 1,807 passes and 0 failures; router Wi-Fi, hotspot, client-isolation/manual-fallback, multi-host expiry, restart, cancel, exhaustion, and changed-address physical checks remain pending.
- Android `.22` failed its first normal-router discovery attempt between the SM-J410G host and SM-S938U guest: the live caller omitted the local address, so only the limited broadcast was sent even though the module's test supplied and exercised a directed `/24` broadcast. Android `.23` moves routed-address detection into the discovery module itself and adds a regression proving the directed Wi-Fi target is emitted. Automated coverage completes with 1,808 passes and 0 failures; `.23` physical retest remains required.
- Android `.23` still failed the same physical discovery. Live `/proc/net` evidence showed the working ENet game listener on IPv4 UDP `22122`, but LuaSocket's `"*"` wildcard selected an IPv6 UDP listener for discovery port `22123`; IPv4 broadcasts could not reach it. Android `.24` binds discovery explicitly to `0.0.0.0`, with a regression for both host and search sockets. Automated coverage completes with 1,809 passes and 0 failures.
- The `.24` two-phone retest verified both Android listeners on IPv4 and received a valid discovery reply over direct unicast, while directed and limited broadcast received no reply on the current router and the guest list stayed empty. Manual IPv4 entry then joined normally at 2/4 workers, movement replicated, both phone-aspect session panels fit, bounded exhaustion returned safely to remembered manual entry, and a prompt host restart automatically rejoined with a fresh session. Test discovery on a broadcast-capable router/hotspot, cancel and changed-address flows, two-host expiry, and fresh lease/snapshot state before promotion. The S25 Slot 1 stayed empty; its temporary Slot 2 host run was restored byte-for-byte from the immediate pre-test backup.

## Next roadmap targets

1. Complete the consolidated automated suite and three-phone physical acceptance matrix, including the remaining UX, discovery, reconnect, authority, contention, disconnect, soak, and offline host-save checks.
2. Produce the clean tester release only after that acceptance evidence is complete. Android foreground-service hosting and deliberate host migration remain future work outside this roadmap's safe fresh-session reconnect.

Use `docs/lan_multiplayer_device_test.md` for the exact verified device results, their remaining untested matrix items, and the preserved historical diagnostics.
