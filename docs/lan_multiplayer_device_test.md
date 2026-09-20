# LAN multiplayer device test

Use this checklist for protocol v16's supported LAN direction: any Windows or Android device with a writable selected save can host and own the authoritative shop, while up to three PC or Android devices join as workers. Use the same protocol-compatible game build throughout one pass. Earlier records below are historical; the v16 shared-GUI and September 13 guest-job updates have not been deployed to phones.

## Next device pass: shared GUIs and guest job recovery

After installing the same current v16 build on all participants, check both PC-host and Android-host:

1. Load customer work from a phone guest. Confirm cabinet/artwork, loading, positioning, rotation, clamp,
   blade, lift return and final unload animate, and on-bed dimensions match the host ticket/state.
2. Confirm gauge typing, program selection, cut buttons, BACK and SERVICE have separate reachable targets
   on the smallest phone; repeat with desktop keyboard controls. Cut either multiplayer button once;
   offline play must still require both controls.
3. Delay an ordinary action, then use E-STOP/barrier block. Confirm prompt safety feedback and no extra
   cut. During a stalled stream the guest must not invent completion; reacquire after disconnect with
   fresh artwork/phase and no retained controls or animation.
4. Deliberately cut the wrong size on a disposable job. Confirm the red spoil marker and actual dimensions
   agree with the host, alongside the host-owned replacement-cost/reputation consequences.
5. Reopen/close production and service repeatedly, then visit wrapper/Windmill consoles; check asset
   loading, touch input, memory stability, ownership contention and guest-save absence.
6. Check every CritterNet page and the wall phone on each screen size, including typed estimates,
   shopping, bills, answering calls, and ownership contention. Repeat the guest estimate-to-payment
   cutting job with spoil/replacement and reconnect; verify the replacement appears in the load menu.
   Finish a printed job separately, then reload the host save offline and compare all outcomes.

All rows remain pending; desktop/forced-mobile smoke is not physical acceptance.

Cross-network Direct Play has separate Android/Android and PC/Android engineering evidence, including a
guarded packet-privacy pass, but remains unavailable in production. That isolated Direct testing does not
change or satisfy this normal-app LAN checklist.

## Prepare the build and devices

1. Run `./BUILD_ANDROID.ps1` once and keep the resulting APK unchanged for the entire pass. Confirm `output/mobile/apk-report.json` contains `"internetPermission": true`.
2. Install that exact APK on each participating phone. If multiple authorized phones remain connected, select each one explicitly rather than relying on an arbitrary device choice.
3. Record each device's model, operating-system version, CPU ABI, build version, and role.
4. Put the host and workers on the same normal Wi-Fi network. Do not use a guest SSID, and temporarily disable VPNs on every device.
5. Record the host IPv4 address shown in the game rather than reusing an address from an earlier test; DHCP can change it.

`./tools/prepare_lan_device_acceptance.ps1` performs the safe preflight without installing: it verifies the
exact reported APK, inventories every authorized phone, and records only each installed version plus save-file
paths, sizes, and checksums in `output/mobile/device-tests/lan-acceptance-preflight.json`. After the operator
has resolved any save concerns, rerun it with `-Install -Launch`; it uses an in-place package upgrade, verifies
the exact reported version on every selected phone, and fails if any pre-existing save file changes during the
installation. It never clears application data.

## Host preparation

### Disposable automated Windows host

For physical Guest Worker checks that do not require a person at the Windows host, use
`tools/start_guest_worker_acceptance_host.ps1`. Pass it a reviewed save under
`tmp/physical-acceptance`; the launcher copies that file into a brand-new
`the-picture-shop-acceptance-*` LÖVE identity, starts the real current-protocol LAN host, waits for an explicit
ready signal, and reports the PC IPv4 address and a run manifest. It cannot open the normal
`the-picture-shop` save identity, cannot run on Android, and never writes back to the source fixture. This is
the preferred way to make truck, maintenance, and relocation checks repeatable while keeping tester saves
out of scope.

Example:

```powershell
.\tools\start_guest_worker_acceptance_host.ps1 `
  -FixturePath .\tmp\physical-acceptance\j4-slot1-monday.lua
```

### Windows host

1. In Windows Settings, verify the active Wi-Fi or Ethernet connection is a **Private network**. Only do this on a trusted home or test network.
2. If Windows Defender Firewall asks, allow LÖVE on **Private networks only**. Do not disable the firewall. If no prompt appears and joining or discovery fails, add only Private-profile inbound UDP rules for the exact game/LÖVE executable and Local Play ports `22122` (game) and `22123` (discovery). UDP `57842` is reserved for the separate engineering Direct Play path and is not needed for a LAN test. Do not add TCP, an all-ports rule, or an all-programs rule. The first `.22` two-instance discovery spot-check reached this firewall prompt and was stopped without approving it; rerun after the tester explicitly allows the trusted Private-network rule.
3. Keep the PC awake during the pass.

### Android host

1. Select a local slot that the phone can write. **HOST THIS SHOP** must fail clearly before listening if the save preflight cannot safely write, read, promote, and clean up a temporary save.
2. Leave the game in the foreground. While hosting, the game keeps the display awake.
3. Backgrounding or unfocusing the Android game intentionally ends the authoritative LAN session. This is a safety rule, not automatic reconnect behavior.
4. Record the Android host address shown in the HUD, including UDP port `22122`.

Windows remains the recommended host when the host operator must switch applications. Keeping an Android host alive while backgrounded requires a future foreground-service/network-loop implementation rather than merely removing the focus-loss shutdown.

## Protocol v14 interaction pass

1. On the chosen host, select the save slot and choose **LOCAL PLAY > HOST THIS SHOP**.
2. On each worker, choose **LOCAL PLAY > JOIN A SHOP**, enter the host's IPv4 address manually, and join. Entering `address:port` is also supported.
3. Confirm every worker loads the host's selected shop, receives its own spawn, and shows the full connected roster.
4. Move all workers, including simultaneous movement when more than one guest is present. Verify independent movement, sensible collision, walk animation, name labels, camera behavior, and host-authoritative corrections.
5. Advance or alter the shop on the host. Confirm workers receive date, money, inventory, jobs, pallet, machine, visitor, door, and truck state without rejoining or being reset to spawn.
6. At the loading-bay wall switch, press **USE** as a guest. Confirm the guest waits for host verification, every device shows the same door result exactly once, and the contextual action disappears when the worker leaves range.
7. At reception, use the customer as a guest. Confirm the client-order GUI is based on host state and that submitting the displayed quote or declining is committed exactly once by the host.
8. At the office computer, use it as a guest. Confirm the GUI shows host-owned read-only shop/job information and that only an eligible pickup request can change state.
9. At the skid wrapper, use it as a guest. Confirm the console shows the host's live cycle and eligible-pallet state. When no pallet is eligible, the list must explain that condition and **START CYCLE** must be disabled in build `.8` or later. While the panel stays open, park and remove an eligible pallet on the host and confirm the row appears and disappears live. Select an available pallet, start once, and verify the host owns the cycle and saved result.
10. At the skid wrapper, switch Guest Worker A to **SERVICE** with the turntable empty and at least one delivered maintenance kit. Guest Worker B must see **BUSY**. Follow all host-ordered targets for the turntable bearing, film carriage, drive belt, and control board; intentionally miss one marker and confirm every device shows exactly one added attempt and miss. While service is active, confirm wrapping, sale, rotation, and relocation are blocked. Rapidly press the final target more than once and verify exactly one kit is consumed, one service is recorded, and repair quality is synchronized. In a separate attempt, disconnect Guest Worker A mid-service; Guest Worker B must reacquire a clean session with no kit consumed. Reload the host save offline and confirm only the completed service persists.
11. Inspect a nearby pallet's paper work order as a guest. Confirm it uses the host-mirrored record, closes locally, sends no mutation request, and creates no guest save.
12. At the Polar cutter, acquire the console as a guest. Confirm nearby staged pallets appear live, then load an exact pallet, select the highlighted program, set/auto-set the backgauge, rotate, position, clamp, and perform one cut with either multiplayer cut button. Repeat once from the Android host's local cutter screen and confirm either local button also starts one cut. Verify every screen shows the same cycle and sound. While an ordinary reply is pending, E-STOP or block the barrier; the host must stop before another cut completes. Reset safely, finish all cuts, return/repeat any remaining lift, and unload. A second worker must see **BUSY**, and the host must not sell, rotate, or relocate the cutter while its lease or batch is active.
13. At the Polar cutter, switch the guest console to **SERVICE**. Guest Worker A starts lubrication while Guest Worker B confirms **BUSY**. Complete the host-owned disconnect, lockout key, tag, cartridge, and prime sequence in order; then service every displayed point across rear, front, side, and central views with the required tools. Inspect and, when offered, top up the gearbox. Rapidly press **FINISH SERVICE** more than once and verify exactly one maintenance kit is consumed, one service is recorded, and all devices converge. In a separate attempt, disconnect the owning guest before completion; another guest must reacquire a clean service session with no kit consumed. Complete the blade path by removing every bolt, lifting the blade, and sleeving it, then book the blade technician and explicitly set the weekly technician schedule. Verify cutter production remains blocked throughout active service and reload the host save offline to confirm only completed service, blade, and technician results persist.
14. At the Windmill, acquire the console as a guest. Prepare one plate in-house and verify the visible timing marker determines host-side accuracy; the client must never submit a score. Load a staged print pallet, complete all six setup checks through their visible controls, pull and inspect a proof, verify client art, approve, and run one color pass through cleanup. Exercise the Service lockout and task path. During a delayed ordinary reply, press **E-STOP** and confirm the host stops before another sheet advances. A second worker must see **BUSY**; the host must not sell, rotate, or relocate the press while the lease is active. Disconnect during setup, service, and production in separate attempts and confirm controls stop safely, emergency state is preserved, the lease clears, and another worker can recover the job.
15. At a supplier representative, open the catalog from Guest Worker A and confirm Guest Worker B sees **BUSY**. Rapidly press one affordable stock purchase more than once; verify exactly one purchase order and one cash deduction appear on every device. Buy one used machine in a separate visit and verify the same result everywhere. Disconnect the owning guest with the catalog open, confirm another guest can reacquire it, then dismiss the visit. Reload the host save offline and verify the accepted purchases remain while no guest created a local durable save.
16. With a ready truck at the dock, open its cargo door and manifest as Guest Worker A; Guest Worker B must see **BUSY**. Use a manifest with at least four rows, move to page 2, and unload or load that displayed row. Rapidly press one cargo action more than once and verify exactly one pallet or pickup moves and one durable result appears everywhere. Confirm the truck cannot close with cargo remaining. Disconnect the owning guest with the manifest open, let Guest Worker B reacquire it, finish the manifest, and release the empty truck. Exercise customer, supplier, machine-delivery, and outbound-pickup trucks across the pass, then reload the host save offline and verify the accepted cargo state persists while neither guest created a durable save.
17. At the pallet jack, acquire it as a guest and confirm no blocking console opens. Drive empty, tap one exact eligible skid to lift it, drive loaded, and use **LOWER** on a green cell. While pushing, also use a nearby ordinary shop control and verify it still responds. Confirm the host validates every jack action, all observers keep the operator attached to the jack, the pallet never duplicates or disappears, invalid jack-only actions stay hidden, and a non-owner sees **BUSY** and cannot take control.
18. As Guest Worker A, acquire the empty pallet jack and relocate the cutter, skid wrapper, and Windmill in turn. For each machine, press **MOVE**, drive, press **TURN**, select a green cell, and press **PLACE**. On every device, confirm the machine leaves its old position once, remains attached to Guest A's jack through movement/stops/turns, and reaches the same terminal pose without snapping back. Guest Worker B must see the pallet jack as **BUSY** and must not be able to control or persist the machine.
19. Exercise relocation rejection and recovery: try an unloaded/active machine, an occupied machine console, and a red or stale placement cell and confirm no durable pose changes. Then disconnect Guest Worker A while each machine is moving; the host must lock it to a safe valid cell or its origin, park the jack, preserve exactly one machine, allow Guest Worker B to reacquire the jack, and retain only the recovered terminal pose after an offline host-save reload.
20. On both phone guests, tap **SESSION**. Confirm the panel fits without covering its close target, identifies the host and current phone with **HOST**/**YOU**, says that the host device owns the save, and shows the same roster as the top bar. Confirm a normal request says it is waiting for the host, urgent cutter/Windmill safety is identified separately, an acquired console says **YOU CONTROL**, another worker's occupied console identifies that worker, and RTT crosses the GOOD/FAIR/SLOW labels without changing game authority. Recheck that only a Direct host sees approval, removal, and invite controls.
21. On normal router Wi-Fi, open Local Play on each guest and verify the host appears under **FOUND SHOPS** within five seconds. Tap it and confirm the ordinary protocol-v14 join succeeds. Repeat with the Windows host and Android host, then on a phone hotspot. If the network blocks broadcast/client traffic, confirm discovery stays nonfatal and manual IPv4 entry still works. With two hosts, confirm both bounded rows are selectable and a stopped host expires from the list.
22. After a guest has joined, interrupt only its connection or restart the same host. Confirm **RECONNECTING** shows a cancelable attempt/countdown, uses at most six fresh attempts, and rejoins with a new host snapshot and clean roster/lease state. Confirm cancellation and exhaustion return to manual/discovered selection. A kick, full shop, or incompatible build must not loop. If DHCP changes the host address, confirm the old address exhausts safely and the newly discovered host can be selected manually. Repeat on router Wi-Fi and a phone hotspot.
23. Disconnect a worker while it owns a workshop console, then have another worker acquire it. Repeat while the worker owns a loaded pallet jack: the loaded jack must park safely, keep its pallet, and be reclaimable.
24. Play for 15 minutes, watching for warping, stuck input, stale shop values, duplicate actions, mismatched sound/animation, or a visitor that appears on only one device. End the host session, reload the host's save offline, and verify the final durable state.

## Protocol v14 `.25` automated candidate — three-phone physical pass in progress

Android source version `0.1.0-android.25` (`versionCode` 25) has passed the current automated candidate
gate: 1,816 engine checks, 74 tooling tests, 393 raster-asset checks, all 9 licensed audio-source checks,
packaged-game smoke, signing, required permissions, packaged ABI validation, and 16 KB compatibility. The
exact reproducible APK is `output/mobile/ThePictureShop-0.1.0-android.25-debug.apk`, 103,129,114 bytes,
SHA-256 `0321a1506b15a929b312c0793539d2cd2cd4b9bc303526aaba5eab3faca6749d`; two consecutive full
builds produced the same package and APK hashes.

The guarded acceptance preflight was run against Samsung SM-J410G (`5cf3c666`), SM-S928U1
(`R5CX41W577Y`), and SM-S938U (`R5CY92V6L6B`). Before installation it recorded the devices' existing
`.24`, `.16`, and `.24` packages plus 2, 6, and 4 save files respectively. The in-place `.25` upgrade and
cold launch then passed on all three phones, and every recorded save path, size, and SHA-256 remained
unchanged. The exact result is in `output/mobile/device-tests/lan-acceptance-preflight.json`.

All three phones manually joined the disposable Windows host
`the-picture-shop-acceptance-20260907-200308101` at `192.168.1.246:22122`. Every phone displayed
**LAN GUEST / 4/4 WORKERS**. The session panel fit the SM-J410G narrow layout and both wide layouts,
kept its close target visible, stated that the host owns and saves the shop, showed the same four-worker
roster, marked the Windows process **HOST**, and marked the viewing phone **YOU**. Three distinct
simultaneous joystick inputs then moved the phone guests apart, with all three screens converging on the
same independent player positions. Evidence screenshots are
`android25-three-phone-roster-*.png`, `android25-session-*.png`, and
`android25-simultaneous-movement-*.png` under `output/mobile/device-tests/screens`.

The same router still blocks discovery broadcast: with the Windows host live, all three `.25` phones stayed
on **Searching for shops on this network...** after an eight-second window. This remained nonfatal, and
manual entry of `192.168.1.246` joined every phone. A prompt restart then replaced acceptance host
`the-picture-shop-acceptance-20260907-200308101` with
`the-picture-shop-acceptance-20260907-201402062` on the same address and port. Without another manual join,
all three guests returned to **4/4 WORKERS** and received the fresh fixture snapshot: the prior live April 1
date and cash state returned to the fixture's March 30 state on every screen. Screenshots are
`android25-router-discovery-*.png`, `android25-before-host-restart-j4.png`, and
`android25-reconnected-*.png`. A second inventory after roster, panel, movement, discovery, and reconnect
checks matched every one of the 12 save-file fingerprints captured after installation, so those guest
interactions created no phone-side durable save.

This is partial final-build evidence only. The vendor, truck, cutter-maintenance, wrapper-maintenance,
machine-relocation, full session-state, broadcast-capable router/hotspot discovery, reconnect
cancel/exhaustion/changed-address cases, Android-host topology, contention, disconnect recovery, 15-minute
soak, final offline host-save reload, and full-pass guest-save-absence rows below remain required. Do not
create the strict passed report or promote the historical `.24` results until all of those rows have been
observed against this unchanged `.25` APK.

## Protocol v14 LAN discovery/reconnect `.24` — physical pass partial

Android source version `0.1.0-android.24` (`versionCode` 24) is installed on the SM-J410G Android 8.1 host
and SM-S938U Android 16 guest. The exact APK is
`output/mobile/ThePictureShop-0.1.0-android.24-debug.apk`, 103,126,101 bytes, SHA-256
`52fd17ccae48681d633f8c5586bbed855527c91284bcfa1795aa8baeabb0113d`; packaging, signing,
permission, ABI, 16 KB compatibility, and the 1,809-check packaged-game smoke suite pass.

On the normal router Wi-Fi test, both discovery and game listeners were verified on IPv4 UDP `22123` and
`22122`. A direct protocol-v14 discovery query from the PC to the Android host received the correct reply,
while both directed and limited broadcast queries received no reply and the S25 discovery list remained
empty. This network therefore blocks the broadcast path. Manual entry of `192.168.1.134` immediately joined
the ordinary host-authoritative session, both phones showed 2/4 workers, and guest movement replicated on
both views. The wide S25 session panel fit and correctly identified host ownership and HOST/YOU roles. A
protected role-swap then used S25 Slot 2 as host and the SM-J410G as guest; the narrow panel also fit, kept its
close target visible, and showed the same host-save authority and two-worker HOST/YOU roster.

Two restart cases also passed their intended safety outcomes. When the host remained unavailable, the guest
showed bounded reconnect progress, exhausted safely, retained only the public address in manual entry, and
rejoined after the host returned. When the host was restored promptly, the guest automatically created a
fresh session and both rosters returned to 2/4 workers. The S25 was guest-only throughout: its Slot 1 remains
empty, while Slots 2 and 3 retain their pre-test hashes. Complete router/hotspot discovery on a network that
permits peer broadcast, the narrow-phone session panel, cancel/changed-address cases, two-host expiry, and
fresh lease/snapshot inspection before promotion. S25 Slot 2 changed only during the temporary host run and
was restored byte-for-byte afterward: main SHA-256 `dd47d20ccea2731aee6b3c413044253b49da6e7d0d8ce7610249755c276df89f`,
backup SHA-256 `5aaec42649821158d8d931dd1b2c52bf2dfa9c1df50a20364b6a23ca80e930a2`.
Slot 3 also retains its original hash and Slot 1 remains absent. Android `.22` and `.23` are rejected
diagnostic builds.

### Windows-host relocation follow-up — September 7, 2026

The SM-J410G `.24` guest joined the disposable Windows host recorded in
`output/mobile/device-tests/acceptance-host/the-picture-shop-acceptance-20260907-170505336/manifest.json`.
The fixture was copied into the isolated LÖVE identity
`the-picture-shop-acceptance-20260907-170505336`; neither the reviewed fixture nor a normal player save was
used as the writable host save. The guest completed the full **MOVE**, **TURN**, green-cell selection, and
**PLACE** sequence for both the skid wrapper and Windmill. Screenshots
`j4-wrapper-relocation-fix-attached.png`, `j4-wrapper-relocation-fix-placed.png`,
`j4-windmill-relocation-attached.png`, and `j4-windmill-relocation-placed.png` are under
`output/mobile/device-tests/screens`.

The first wrapper attempt found a host-side packet rejection: when the empty jack was close enough to a
pallet to expose a lift candidate, the network snapshot used Lua's `and nil or` idiom and accidentally kept
that candidate while a machine was attached. The strict relocation validator correctly rejected the
inconsistent packet, leaving the guest without the placement controls. `World.networkPalletJackSnapshot`
now clears the candidate explicitly during any machine relocation. A domain regression covers the nearby
pallet case, the session regression covers durable/realtime ordering, and the full smoke suite passes 1,816
checks with zero failures. The repeated physical pass logged successful attached snapshots to one recipient
and J4 immediately displayed **PLACE**/**TURN**.

A separate forced J4 process stop while the Windmill was attached dropped the recipient count to zero; the
Windows host then cleared the lease, safely locked the Windmill, and parked the jack. Relaunching J4 and
manually rejoining showed the recovered terminal pose and a parked jack. This completes one-guest Windows-host
wrapper/Windmill relocation and Windmill disconnect recovery. It does not yet claim two-guest contention,
red/stale-cell rejection, cutter/wrapper disconnect recovery, offline save reload, or an Android-host pass
using the not-yet-built post-fix APK.

## Protocol v14 Guest Worker UX `.21` — physical pass pending

Android source version `0.1.0-android.21` (`versionCode` 21) adds the read-only session panel for LAN and
Direct guests while preserving Direct-host-only player management. Automated coverage verifies bounded,
detached roster and occupancy display records; host-save authority messaging; HOST/YOU identity; RTT quality;
active, busy, ordinary-pending, and urgent-safety states; view-only touch behavior; and runtime reset cleanup.
The full smoke suite passes 1,786 checks with 0 failures. Complete checklist step 20 on both phone aspect ratios
before promoting this UX step to Full. The exact candidate is
`output/mobile/ThePictureShop-0.1.0-android.21-debug.apk`, 103,114,525 bytes, SHA-256
`976f75fadc17e4945cba393c250cf7c54692c8229f65f29a50dbe9f80f2316ef`; packaging, signing,
permission, ABI, 16 KB compatibility, and packaged-game smoke checks pass. It has not been installed on
either phone yet, so the existing `.20` saves and the unresolved S25 Slot 1 recovery decision remain untouched.

## Protocol v14 maintenance-and-relocation `.20` — physical pass partial

Android source version `0.1.0-android.20` (`versionCode` 20) is the current protocol-v14 maintenance-and-relocation
candidate and includes the protocol-v12 cutter and protocol-v13 wrapper work. The exact APK is
`output/mobile/ThePictureShop-0.1.0-android.20-debug.apk`, 103,111,447 bytes, SHA-256
`97dc55c209a62049156a42ab704028bdc06cca72e7ee2e8842953d71d26abecd`. Packaging, signing,
permission, ABI, 16 KB compatibility, and packaged-game smoke checks pass. The full smoke suite passes
1,777 checks with 0 failures.

Automated cutter-maintenance coverage exercises strict bounded commands and views, ordered lockout and
preparation, six lubrication points across the available views, gearbox inspection/top-up, production
interlock, blade removal and sleeving, technician booking and explicit weekly scheduling, exclusive
contention, exact-once completion and saving, disconnect rollback/reacquisition, and an impaired real-session
round trip. Automated wrapper-maintenance coverage adds the host-owned four-component order, bounded active
target intent, host-scored misses and repair quality, production/sale/relocation interlocks, exact-once kit
consumption and saving, disconnect rollback, strict packets, and an impaired real-session round trip.
Automated relocation coverage adds all three machines, exclusive pallet-jack ownership, live attached poses,
bounded machine/grid intent, host-side collision and readiness checks, exact-once save behavior, and safe
disconnect recovery. The exact APK is installed and launch-verified on Samsung SM-S938U and SM-J410G;
both report `versionCode` 20. Maintenance and the remaining relocation cases are not yet claimed.

A targeted two-phone relocation pass on September 7, 2026 used the SM-S938U as Android host at
`192.168.1.137:22122` and the SM-J410G as Guest Worker. Both reached `2/4 WORKERS`. The J4 acquired and
drove the pallet jack, attached the cutter, moved it, turned it, and placed it on a green cell; both devices
showed the same attached live pose and rotated terminal pose. The pass exposed and led to fixes for a missing
nearby-machine `MOVE` touch button, an obsolete guest `M`/`Q` interception, the non-owner host's misleading
`PLACE` label, and the moving-jack prompt. The completed cutter flow used interim `.20` APK SHA-256
`0c6410765d3407c3b411b0e9b49538f399aea6bc09f7b2cf9961d3940583b86f`. The exact final APK above was then
installed and cold-launched on both phones, completing the final-build label spot-check. Wrapper/Windmill relocation, two-guest contention, rejected placement,
disconnect recovery, and offline reload remain unclaimed.

Protocol-v10 vendor purchasing and protocol-v11 truck logistics remain automated-complete but
physical-pending as part of this same device pass. The isolated Direct engineering guest is a different
package and does not satisfy normal-app LAN acceptance; complete steps 10 and 13 through 19 and the shared
disconnect/reconnect, soak, and offline-reload checks before promotion.

## Verified protocol v8 three-device cutter pass — August 29, 2026

Status: **completed for the targeted cutter scope below** using APK `0.1.0-android.13`
(`versionCode` 13).

- Exact APK: `output/mobile/ThePictureShop-0.1.0-android.13-debug.apk`, 102,505,718 bytes,
  SHA-256 `a22ec171cdd8983e549902b4c3179c60e0854e58da08c9f8b70882b4d9fd871f`.
- The embedded mobile package reports clean source commit
  `941e2060a125c0195de1c941c2c1079e95b833b3`. The Windows PC ran that same source.
- Automated smoke completed 1,217 passes with 0 failures.
- Samsung SM-S938U hosted at `192.168.1.137:22122`; Samsung SM-J410G and the Windows PC joined as
  workers. Every screen reached `3/4 WORKERS`.
- The host initially advertised its cellular address, `10.11.148.123`, so both workers timed out.
  Enabling Wi-Fi on the host and rehosting on the same `192.168.1.x` LAN resolved both connections.
- With the Windows worker's remote cutter console open, the Android host lifted and moved a loaded pallet.
  The Windows world continued rendering without the `.12` nil-hover-coordinate crash.
- The Windows worker completed the cutter load/setup/run path with one cut button. The Android host also
  completed its local multiplayer cut with one cut button. Multiplayer therefore accepts either cutter
  button as one host-validated action; ordinary offline play retains the two-control requirement.
- Two-worker contention kept the second operator out with the expected busy state while the first worker
  held the cutter lease.
- The urgent E-STOP path passed while an ordinary cutter request was active, and the cutter recovered
  through its safe reset path.
- Closing the Windows worker while it held the cutter released the lease safely. The Android host
  reacquired the same safe batch, and the Windows worker rejoined cleanly at `3/4 WORKERS`.

Build `.12` reached the same Android-host topology but was not accepted. While the Windows worker had the
remote cutter open, the Android host lifted a pallet; the Windows background-world tooltip evaluated that
carried pallet without hover coordinates and stopped in `world_renderer.lua`. Build `.13` is the verified
regression fix.

Not exercised in this targeted pass: a fourth device, the full 15-minute soak, the hotspot matrix, and the
final offline save reload. Those checklist items remain open; this result does not claim them.

## Verified protocol v7 four-device machine-pose pass — August 28, 2026

Status: **completed for the targeted scope below** using APK `0.1.0-android.11` (`versionCode` 11).

- Exact APK: `output/mobile/ThePictureShop-0.1.0-android.11-debug.apk`, 102,485,249 bytes,
  SHA-256 `88549621c829201171475cb38513ac1433b3292595b32cc3b0dd30fb67017940`.
- The embedded mobile package reports clean source commit
  `8b5b80d28334853986a30e5e84b42ed88c53cbce`. The Windows PC ran that same source.
- Automated smoke completed 1,113 passes with 0 failures.
- Samsung SM-S938U hosted at `192.168.1.137:22122`; Samsung SM-S928U1 and Samsung SM-J410G joined as
  Android workers, and the Windows PC joined as the third worker. Every screen reached `4/4 WORKERS`
  and showed independent movement.
- The cutter, skid wrapper, and Windmill stayed attached to the host-operated pallet jack and remained
  synchronized on both Android observers and the PC through live movement, rotations, stops, restarts,
  and placement. The cutter remained active beyond the 30-second durable-state fallback. A red placement
  was rejected before a green placement succeeded; no observer showed snap-back or a duplicate machine.
- A guest operated the dock door while the wrapper relocation remained active. During Windmill relocation,
  a guest opened the computer/client screen. Neither concurrent interaction disturbed the machine pose.
- The SM-J410G exited and every remaining screen fell cleanly to `3/4 WORKERS` with no stale avatar. It
  rejoined through the host-plus-assigned welcome, restored exactly one avatar and `4/4 WORKERS`, and moved
  independently after rejoining.
- Android LÖVE logs were clean.

Protocol v7 therefore physically verifies the fourth-player fix: the bounded host-plus-assigned welcome
and 12 Hz one-player MTU-safe motion shards merged by player ID no longer trigger protocol v6's 1,200-byte
full-roster overflow in this four-device topology.

Not exercised in this targeted pass: the full 15-minute soak, the hotspot matrix, and the final offline
save reload. Those checklist items remain open; this result does not claim them.

The superseded protocol-v6 APK `0.1.0-android.10` (`versionCode` 10), SHA-256
`151a0958d0d8215ee3c38c64cbf35db3af9a58d5182d01d2e2018cd824159155` (102,481,341 bytes),
reached the SM-S938U host plus the two Android workers at `3/4 WORKERS`. The Windows PC's fourth join
then exposed `protocol: codec encode failed: encoded value exceeds maxBytes`. This diagnostic result is
retained to explain the v7 hotfix; it is not a physical acceptance pass.

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
