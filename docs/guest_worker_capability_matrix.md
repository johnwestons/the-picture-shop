# Guest Worker capability matrix

This is the authoritative Local Play parity inventory. Runtime declarations live in
`src/multiplayer_capabilities.lua`; the smoke suite rejects undeclared interaction kinds and authority
resources. A durable change always executes on the host and only the host writes the multiplayer save.

## September 13, 2026 — full guest printing-job regression (source only)

The guest journey now also completes a two-color print order through the shared computer, cutter,
plate-room, press setup/proof/run, wrapper and truck GUIs. It cuts 500 supplied sheets and delivers
exactly 450 finished copies, prepares both plates, completes all six setup games for each color, waits
for first-color drying and reloads for the second pass. Disconnect during production shuts off the
motor/feed/impression; a fresh guest lease resumes the confirmed counts. Replayed requests and repeated
clicks must not duplicate plate supplies, proof sheets, ink, packing, wash, stock or payment. Final
host/guest totals and a serialized offline-load round trip are checked.

This exposed a stale protocol allowlist that blocked FAN + LOAD and the separate suction/air buttons.
The allowed feeder actions now match the GUI, with a protocol regression covering every visible setup
control. Protocol remains v16; use matching current builds, not earlier v16 packages.

Desktop and forced-mobile smoke each pass **2,285 checks**, including **197 new printing-journey
checks**. Equipment/supplies, navigation/staging, intake and plate timing are controlled fixtures; job
production and financial changes use real host authority callbacks. No player saves or connected
devices were accessed, and no builds were deployed. Real-device touch/text entry, both hosting
directions, extended latency/recovery/soak and disk-save reload remain the next acceptance work.

## Earlier September 13 — full guest cutting-job regression (source only)

The shared guest GUIs now have an automated estimate-to-payment journey using the application's real
host authority callbacks: delayed quote acceptance, customer stock delivery, an intentionally wrong cut,
one exact 500-sheet replacement and spoil claim, reconnect during cutting with a fresh lease, finished
stock wrapping, bill payment, scheduled pickup and final payment. Repeated clicks and replayed requests
must leave stock and finances correct; the guest receives the host's final totals and a serialized
offline-load round trip preserves the result. Intake, navigation and inbound dock/staging are fixtures.
This first journey covers a cutting job; the later printing scenario above extends that coverage.

The test exposed and now guards a guest loading bug: the cutter retained its old paper reference after
discard/unload and therefore omitted the next load candidates. Finished/idle snapshots now advertise
available stock instead of the departed batch, without changing protocol v16 or its packet limits.

Desktop and forced-mobile smoke each pass **2,088 checks**, including **53 new journey checks**. No
player saves or connected devices were used, no builds were deployed, and no physical acceptance is
claimed. Real touch/text entry, both hosting directions, extended network recovery/soak and disk-save
reload on the devices remain required.

## September 12, 2026 — shared host GUI parity (source only)

Protocol v16 uses shared host screens for the full CritterNet computer (all nine pages, shopping sites,
cart, typed email and estimates), wall phone, cutter production/help/load/service, wrapper production and
service, all Windmill tabs and six illustrated setup tasks, reception, suppliers, and truck manifests.
Pallet work orders already use the shared read-only screen. Reception still requests written email
details; the bounded reception view leaves detailed notes/handling to the subsequent specifications email.

New host-owned office commands cover estimates, declines, promotions, notice archiving, checkout,
machine sales, and bills. Cart prices come from the host catalog; checkout stages changes before commit.
The phone is an exclusive ninth workstation, with host range checks, call-ID validation, and exact-once
answer/respond/dismiss commands. GUI instances draw detached projections and never run guest-side
production, repair scoring, purchasing, or saves. Press setup visuals and the exact removed-bolt mask
come from the host. Pending financial/phone actions cannot be repeated; urgent machine stops retain
their independent safety path.

Desktop and forced-mobile smoke each pass **2,035 checks**, including all nine computer-page pixel
comparisons, shared-screen rendering and click/keyboard intent, strict packets, and real in-process
Session/authority phone orders, cart checkout, bills, typed estimates, promotions and archiving.
Captured renders were visually reviewed. No connected devices were used or updated, and no APK was
deployed. Earlier device evidence is historical; all devices need a matching v16 build for the next test.

Still required on devices: all GUI hit targets and text entry, phone contention/reacquisition,
cash/inventory/email convergence, latency/recovery/soak, Android-host and PC-host topologies, and offline
host-save reload. Automated mobile mode is not a substitute for physical touch/keyboard acceptance.

## Earlier September 12 slice — cutter production presentation

Protocol v15 adds bounded host-reported actual paper dimensions and spoil status. The guest production
console now loads the cutter asset pack and uses the same read-only scene renderer as the local/host
console: cabinet, artwork rotation, moving paper, clamp, blade, and physical cut-button sprites. Motion
interpolates only between confirmed snapshots, freezes at the last confirmed phase if updates stop,
and resets immediately on a safety/phase change or console close. Host keyboard bindings are also
available for load, program, gauge memory, rotation, positioning, clamp, lift return/repeat and safety.

Desktop and forced-mobile smoke each pass 1,893 checks, including pixel comparisons for blade and
paper-transfer frames and a real in-process Session/authority/Machine production flow. That flow checks
duplicate cut intent, next-program synchronization, E-STOP, and a deliberately wrong cut whose actual
spoiled dimensions reach the guest. Guest rendering never advances Machine or edits mirrored paperwork.
No connected devices were used, no APK was deployed, and previous v14 physical evidence remains historical.
All devices must receive the same v15-compatible build before the next multiplayer test.

That earlier production-only slice is superseded by the shared-GUI implementation above; its physical
device/recovery/soak evidence remains pending.

| Shop interaction | Guest status | Available now | Work still required | Roadmap step |
|---|---|---|---|---|
| Office computer | Candidate | Shared CritterNet pages; inspect jobs; request pickup; typed estimates/promotions; archive mail; checkout; sell machines; pay bills | Physical transaction/text-entry acceptance | Shared GUI parity |
| Wall phone | Candidate | Shared phone sprites/call light; answer; respond/order; decline/hang up | Physical contention and transaction acceptance | Shared GUI parity |
| Reception customer | Full | Shared job ticket; request written email details | — | — |
| Supplier representative | Candidate | Inspect the live host catalog; buy stock or used machinery; dismiss the visit | Three-phone physical acceptance | Vendor purchasing |
| Loading-bay door | Full | Open and close through host validation | — | — |
| Delivery truck | Candidate | Open the cargo door; inspect paged manifests; unload customer/vendor/machine deliveries; load completed-job pickups; release an empty truck | Two-phone guest physical acceptance | Truck delivery/pickup |
| Pallet work order | Read-only | Inspect mirrored paperwork | Mutations intentionally remain unavailable here | — |
| Polar cutter | Candidate | Production, urgent safety controls, host-owned maintenance, and guest-controlled relocation | Maintenance, multi-worker, and recovery physical acceptance | Cutter maintenance; relocation |
| Skid wrapper | Candidate | Pallet selection, wrapping cycle, host-owned four-component service, and guest-controlled relocation | Maintenance, multi-worker, and recovery physical acceptance | Wrapper maintenance; relocation |
| Heidelberg Windmill | Candidate | Plate, setup, proof, production, safety, service, and guest-controlled relocation | Console, multi-worker, and recovery physical acceptance | Relocation |
| Pallet jack | Candidate | Drive, lift/lower pallets, park, and relocate all three installed production machines | Multi-worker contention, rejected-cell, final-build Android-host, and offline-reload acceptance | Relocation |

## Required implementation order

1. Capability registry and regression audit.
2. Vendor purchasing.
3. Delivery-truck delivery and pickup.
4. Cutter maintenance.
5. Wrapper maintenance.
6. Guest-controlled machine relocation.
7. Guest-facing multiplayer UX improvements.
8. LAN discovery and reconnect resilience.
9. Automated and three-phone physical acceptance.
10. Clean tester release.

## Progress record

| Step | Status | Evidence | Physical acceptance still required |
|---|---|---|---|
| Capability registry and regression audit | Complete | Runtime declaration guard; registry/resource coverage tests; current full smoke suite passed 1,816 checks with 0 failures on September 7, 2026 | None; this step changes classification and safeguards only |
| Vendor purchasing | Automated complete; physical pending | Protocol v10 host-owned catalog and exclusive lease; bounded purchase intent; range/catalog/cash revalidation; exact-once replay protection; host-only save; all five live catalogs fit the 1,200-byte packet ceiling; full smoke suite passed 1,733 checks with 0 failures on September 7, 2026 | Two-guest contention; one rapid/repeated stock purchase; synchronized cash and purchase order; used-machine purchase; disconnect/reacquire; host-save offline reload |
| Delivery-truck delivery and pickup | Automated complete; physical pending | Protocol v11 host-owned paged manifest and exclusive lease; row-index-only intent; live range/truck/cargo revalidation; exact-once replay protection; customer/vendor/machine delivery plus outbound pickup coverage; real guest-to-host session round trip; full smoke suite passed 1,744 checks with 0 failures on September 7, 2026 | PC host plus two phone guests: contention, paged rows, repeated cargo action, synchronized delivery and pickup, disconnect/reacquire, offline host-save reload |
| Cutter maintenance | Automated complete; physical pending | Protocol v12 host-owned lockout, lubrication, gearbox, blade, and technician sessions; bounded row/button intent; live range and idle-machine revalidation; production interlock; exact-once kit consumption and host saving; disconnect-safe transient rollback; real guest-to-host session round trip; full smoke suite passed 1,757 checks with 0 failures on September 7, 2026 | PC host plus two phone guests: contention; synchronized lockout/lubrication progress; repeated finish with one kit consumed; blade sleeve and technician schedule; disconnect/reacquire; offline host-save reload |
| Wrapper maintenance | Automated complete; physical pending | Protocol v13 host-owned four-component service order, active target and miss scoring, bounded target-index intent, production/sale/relocation interlocks, exact-once kit consumption and host save, disconnect rollback, strict packets, and impaired guest-to-host session coverage; full smoke suite passed 1,766 checks with 0 failures on September 7, 2026 | PC host plus two phone guests: contention; synchronized four-component task/target progress; host-recorded misses and repair quality; repeated final target with one kit consumed and one service saved; production interlock; disconnect/reacquire; offline host-save reload |
| Guest-controlled machine relocation | Automated complete; physical partial | Protocol v14 exclusive pallet-jack lease; bounded machine-index/grid-cell intent; host readiness, range, console, and floor-clearance validation; fixed-rate attached poses; exact-once attach/rotate/place saving; disconnect recovery; all three machines plus impaired real-session coverage. An SM-J410G guest previously completed the cutter flow against an SM-S938U Android host. On September 7, 2026, the same J4 guest joined an isolated Windows acceptance host and completed attach, TURN, green-cell selection, and PLACE for both the skid wrapper and Windmill. This pass exposed a host snapshot bug when an empty jack was beside a pallet; the candidate pallet ID was not cleared during machine relocation, so the safety validator rejected the realtime pose. The explicit-clear fix is covered by the 1,816-check smoke suite and the repeated physical wrapper/Windmill flows. A forced J4 process stop while the Windmill was attached also made the host lock the machine safely and park the jack before a clean rejoin. | Final fixed Android-host build; two-guest contention/observer checks; red and stale cell rejection; cutter/wrapper disconnect recovery; offline host-save reload |
| Guest-facing multiplayer UX | Automated complete; physical partial | Every active LAN/Direct player can open a read-only session panel showing host-save authority, the bounded four-worker roster with HOST/YOU badges, measured link quality, shared-control occupancy by display name, the guest's active console, and waiting/urgent host-verification state. Direct-host approval/removal controls remain isolated from read-only panels. Full smoke suite passed 1,786 checks with 0 failures on September 7, 2026. On the exact `.25` APK, SM-J410G, SM-S928U1, and SM-S938U guests joined one disposable Windows host at 4/4; all three session panels fit, retained visible close targets, stated host-save authority, showed the same roster, and independently marked the host and viewing phone with HOST/YOU. | GOOD/FAIR/SLOW link label; BUSY owner; ordinary and urgent pending feedback; Direct-host management regression |
| LAN discovery and reconnect | Automated complete; physical partial | Best-effort bounded UDP discovery supplies address hints only; every selected host still passes the protocol-v14 hello and authoritative snapshot. Results are nonce-correlated, deduplicated, capped, sanitized, and expired. An established LAN guest gets six cancelable fresh-session retries with bounded backoff; rejection/kick/full/version failures do not loop, and reconnect never retains a lease, player ID, snapshot, or guest save. Android `.22` exposed missing live routed-address detection and `.23` exposed an IPv6 wildcard listener. `.24` detects the routed address and binds IPv4; the full smoke suite passes 1,809 checks with 0 failures. On `.25`, all three phones safely showed no found shop after eight seconds on the broadcast-blocking router, manually joined the Windows host at 4/4, and automatically returned to 4/4 after a prompt host restart with a fresh fixture date/cash snapshot and no changed phone save fingerprint. Historical `.24` evidence also verifies exhaustion/manual fallback. | Broadcast-capable router/hotspot discovery; Android-host topology; two-host selection/expiry; cancel; changed host IP/manual rediscovery; explicit fresh lease-state inspection; `.25` exhaustion/manual fallback |
| Full acceptance and tester release | Automated acceptance complete; three-phone physical pass in progress; clean release pending | Current September 7, 2026 source revalidation passes 1,816 engine checks, 74 tooling tests, 393 raster-asset checks, and all 9 licensed-audio sources. Android `.25` is reproducibly packaged and smoke-tested, signed, permission-checked, ABI-checked, and 16 KB compatible; consecutive full builds produced exact SHA-256 `0321a1506b15a929b312c0793539d2cd2cd4b9bc303526aaba5eab3faca6749d`. The guarded in-place `.25` install and cold launch passed on SM-J410G, SM-S928U1, and SM-S938U with all 12 recorded save files unchanged. All three joined disposable Windows host `the-picture-shop-acceptance-20260907-200308101` at 4/4, the session panels displayed consistent host-save authority and HOST/YOU roles, and distinct simultaneous movement converged across every phone. The broadcast-blocking router produced a safe empty discovery result and successful manual fallback; all three guests then rejoined a prompt replacement host automatically with a fresh snapshot. A post-session inventory still matched all 12 phone save fingerprints. Prior `.24` evidence remains historical and is not treated as final-build acceptance. Tester assembly fails closed unless a strict report binds the exact clean source and normal APK to three phones, all required physical rows, and operator confirmation. The prior Windows installer passed install/launch/uninstall and save preservation but must be rebuilt from final source. | Complete remaining vendor/truck/maintenance/relocation/session-state rows, broadcast-capable router and hotspot discovery, Android-host topology, reconnect cancel/exhaustion/changed-address cases and disconnect recovery, 15-minute soak, offline host-save reload and full-pass guest-save absence; record the artifact-bound pass report; then run the clean-source release gate and separate tester-download assembly |

## Definition of full Guest Worker support

- The guest sees a current projection of the host-owned state.
- The guest sends bounded intent rather than authoritative results or coordinates.
- The host rechecks player identity, range, prerequisites, resource revision, and exclusivity.
- Replayed, stale, malformed, or unauthorized requests cannot mutate state.
- Disconnect or timeout releases ownership and leaves the shop in a recoverable state.
- Accepted durable changes are saved once by the host and synchronized to every joined player.
- The interaction has automated authority, contention, replay, disconnect, and state-sync coverage.
- Required physical-device acceptance is recorded before the capability is marked Full.
