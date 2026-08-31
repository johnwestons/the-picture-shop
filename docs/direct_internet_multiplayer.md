# Direct Internet Multiplayer

## Product promise

Direct Internet Play is intended to let players connect to a host on another network without an
account, fee, subscription, matchmaking service, or vendor-operated relay/gameplay server. Local Play
remains available and unchanged. This direct-connect design cannot be universal: restrictive
carrier-grade NAT (CGNAT), double NAT, or a router the host cannot configure can make inbound play
impossible without usable IPv6 or a relay. Direct hosting must fail closed when its security or
reachability support is not available; it must never fall back to an unencrypted public listener.

The supported connection path is:

1. The host creates a one-session invitation containing an endpoint and a 32-byte random master secret.
2. ENet establishes the underlying UDP connection.
3. A bundled native security provider derives separate admission and Noise keys, authenticates the
   invitation, and establishes encrypted traffic keys.
4. Only then does the secure transport report a logical connection to the existing multiplayer session.
5. The host validates the protocol-v9 `hello` but quarantines the peer: no player slot is allocated and
   no welcome or shop snapshot is sent until the host explicitly approves the displayed request.
6. After approval, `welcome`, snapshots, and gameplay packets travel inside the encrypted channel.

Production builds must not expose a public listener until the native security provider and every release
gate below are approved. Guarded engineering probes may open only an isolated, bounded test listener;
they do not expose Direct Play in the normal game.

## Architecture boundary

`src/net/transport_direct.lua` wraps the existing ENet transport. Security stays below
`src/net/session.lua`, which means the host-authoritative simulation and Local Play handshake do not
need a second implementation.

The Direct transport is responsible for:

- withholding raw connect events until authentication succeeds;
- accepting only bounded handshake frames on reliable control channel 0 before authentication;
- encrypting every application packet and authenticating its actual ENet channel;
- preserving protocol channel 2 for larger durable snapshots while channels 0 and 1 keep realtime limits;
- maintaining separate replay protection for each ENet channel;
- encrypting broadcasts independently for every authenticated peer;
- expiring unauthenticated peers promptly; and
- destroying handshake and traffic-key state on failure, disconnect, or shutdown.

Direct admission is deliberately bounded before native handshake state is allocated. A valid invitation
prefilter may consume at most four new permits at once and refills by one permit per second; the wrapper
also caps incomplete handshakes at four and authenticated guests at three. A wrong prefilter token is
rejected without consuming a permit or allocating crypto state. Invalid or backward clock readings make
the limiter fail closed for the lifetime of that transport.

A Direct host supports up to three guests, or four players total. Because each invitation is deliberately
single-connection, the host admits those guests with sequential fresh invitations rather than reusing one
invitation across several joins.

ENet receive events identify the channel but do not report whether the sender selected reliable
delivery. The wrapper therefore enforces channel 0 and always sends its own four handshake flights
reliably. Those flights are the two NNpsk0 messages, an encrypted transcript-bound finish, and an
encrypted transcript-bound acknowledgement. Invalid duplicates, truncation, tampering, and replays
fail the native state closed.

ENet channels are independent, so authenticated host game data can overtake the final acknowledgement
on the way to a client. The initiator alone may hold a small, frame-and-byte-bounded set of those raw
ciphertexts without decrypting them or announcing a connection. After the acknowledgement authenticates,
all held frames must authenticate before the wrapper emits `connect`, followed by their `receive` events.
The responder never accepts pre-ready game data.

The native provider treats the invitation value only as a master secret. It derives the Noise PSK and
the admission key under distinct libsodium KDF contexts, then derives a 31-bit ENet connection prefilter
from the admission key; raw invitation bytes are never used as the token. The provider must return an integer from 0
through 2147483647, and Direct Play fails closed if derivation fails or returns anything else. This is
not authentication, is visible and replayable on the network, and does not replace the security
handshake. It lets the host reject ordinary Internet scans
before allocating a Noise state. A Direct host reserves 12 physical ENet peers while the game still
admits only three guests, and caps incomplete security handshakes separately.

The engineering provider uses a pinned Noise PSK handshake and libsodium AEAD
primitives. The invitation key is generated by the provider's operating-system CSPRNG. Lua's random
number generators are never used for invitation keys or cryptographic nonces.

## Current engineering status

- Windows x64 builds and loads the exact suite through LuaJIT, passes native and Lua conformance,
  consumes the complete pinned independent Cacophony vector, passes a deterministic end-to-end
  TPS-provider-v2 known-answer fixture plus an independent bridge-cipher vector, and produces a
  byte-identical ABI-v3 DLL across two clean builds.
- Android builds `armeabi-v7a`, `arm64-v8a`, and `x86_64` candidates. Every ELF has 16 KiB-aligned
  load segments, the exact 24-symbol provider surface, immediate binding, and only Android system
  dependencies. A physical API 27 ARM32 phone and API 36 ARM64 phone pass the native self-test, LuaJIT
  provider conformance, and the ABI-v3 response/opening/bridge-cipher checks. Real encrypted ENet/Direct
  traffic and the full protocol-v9 player flow pass across separate Wi-Fi and cellular routes. The
  redacted device runs prove package removal on both phones and record no address, code, key, or other
  secret. The API 36 device uses a 4 KiB kernel, so an actual 16 KiB-kernel execution pass and x86_64
  runtime pass remain.
- Hostile tests now cover wrong keys, truncated/tampered/duplicate finish and acknowledgement flights,
  cross-session finish replay, a valid low-order X25519 input, data replay, channel substitution,
  reserved sequence exhaustion, bounded cross-channel reordering, opening-packet tampering/replay,
  restart replay, final-flight loss, wrong-source floods, and cleanup on every tested failure path.
- Engineering-only automatic-reachability layers now include bounded PCP and NAT-PMP codecs, a
  serialized finite-lease coordinator, and strict pure UPnP IGD parsing/request construction. These
  components do not yet have a live router socket adapter and are not production router-mapping support.
- A same-port simultaneous IPv6 opening passes between the physical Wi-Fi and cellular phones with
  authenticated proof in both directions and complete redacted cleanup. A subsequent guarded run
  transferred those exact sockets into the authenticated bridge and encrypted ENet transport, moved game
  traffic in both directions while exercising channels 0, 1, and 2, and observed bridge fragmentation on
  both phones.
- The strict `src/net/ipv6_address.lua` boundary and fixed-layout `TPS2H` host / `TPS2R` reply codec in
  `src/net/direct_opening_code.lua` are implemented. They use canonical unpadded base64url, public-IPv6
  filtering, bounded lifetimes and clock skew, exact echo matching, injected fail-closed response-tag
  verification, and opaque redaction. ABI-v3 native response tags and 92-byte challenge/echo checks now
  authenticate the exact endpoint pair. A bounded controller handles loss, reordering, duplicates,
  250 ms retry, a three-second final-confirmation grace, and replay-safe restart with fresh challenges.
- The authenticated IPv6-to-loopback bridge and ENet adapter are implemented and have passed the
  separate-network physical exchange. They enforce an outer
  1232-byte budget, fragment a bounded 1400-byte inner datagram into at most two authenticated pieces,
  reassemble under fixed memory/time/work limits, reject wrong sources and replays, and preserve ENet
  channels and delivery choices.
- The guarded `Host Direct Game` / `Join Direct Game` coordinator and screen are implemented. They bind
  before generating an invitation, preflight the host save, accept only a matching authenticated reply,
  hand a one-session bridge factory to the existing protocol-v9 session, distinguish Direct from LAN in
  recovery/HUD state, and clear retained fields and clipboard content owned by the screen on use,
  cancellation, expiry, failure, foreground loss, or shutdown. Codes are never included in status/error
  text. Players currently enter the global IPv6 address shown by their own device; no discovery service is
  contacted.
- Direct hosts now receive a mandatory in-game approval request only after encrypted authentication and
  a valid protocol hello. Until approval, the peer receives no player record, welcome, or durable shop
  snapshot. The host can decline a pending request or remove a connected guest from the same keyboard,
  mouse, or touch panel. Approval expires after 60 seconds. Decline, removal, timeout, or disconnect
  closes the one-connection invitation, so its old host/reply codes cannot be used to reconnect.
- The guarded Windows-PC-host plus two-Android run passed with one Wi-Fi guest and one cellular guest.
  Sequential fresh invitations and explicit approval brought all three devices to Direct `3/4`; removing
  the first guest left the second active at `2/4`, and its graceful departure returned the host to `1/4`.
  The exact UDP `57842`/`57844` Windows engineering firewall scope was verified; afterward the
  helper-owned narrow rule was removed and the pre-run firewall state was restored.
- Direct Play remains disabled. The normal title screen receives no Direct callback while the bundled
  provider remains `productionReady = false`. The broader residential/mobile network matrix, live router
  mapping on a supported public-IPv4 network, Android x86_64 and physical 16 KiB-kernel runs,
  repeat/independent packet-capture review, and external security review are still release gates.

## No-service reachability plan

The bundled ENet address type is IPv4-only and the Lua binding parses the first colon as a port
separator. The separate-network IPv6 path therefore uses a guarded UDP6 opening controller followed by
an authenticated IPv6-to-loopback-ENet bridge; it is not an address-parser change.

The current Android target SDK needs only `INTERNET` for UDP LAN access. Before raising the target to
Android 17 / API 37, Local Play and PCP/NAT-PMP/UPnP gateway access must adopt Android's
[`ACCESS_LOCAL_NETWORK` runtime-permission flow](https://developer.android.com/privacy-and-security/local-network-permission).
That operating-system permission does not add an account, hosted service, telemetry, or fee.

Reachability is being developed in this order:

1. Manual UDP forwarding is the first working fallback. The host binds the secure Direct listener,
   enters the public endpoint reported by their own router, and receives exact firewall/UDP-port guidance.
2. [PCP MAP](https://www.rfc-editor.org/rfc/rfc6887.html) is the preferred automatic method. It asks the
   active gateway for a finite UDP mapping and accepts the gateway-selected external address and port.
3. [NAT-PMP](https://www.rfc-editor.org/rfc/rfc6886.html) is the serialized legacy fallback, including
   external-address discovery, finite leases, halfway renewal, epoch-change recovery, and lifetime-zero deletion.
4. UPnP IGD2/IGD1 follows for consumer-router compatibility, preferring finite
   `AddAnyPortMapping` and treating every SSDP, HTTP, XML, and SOAP response as hostile bounded LAN input.

The PCP/NAT-PMP wire codecs, serialized coordinator, and strict pure UPnP IGD layer are implemented and
covered by engineering tests. They deliberately do not open a socket or change a router by themselves.
Live gateway discovery, transport adapters, renewal/deletion integration, and physical-router proof are
still open; automatic mapping must therefore be treated as unavailable in production.

No method receives the invitation secret or contacts a matchmaking, STUN, relay, telemetry, or public-IP
service. The secure listener must exist before its exact UDP port is mapped; invitation generation occurs
only after the router returns a globally usable public-unicast endpoint. Shutdown closes the listener first,
then best-effort deletes the finite mapping.

### Windows Firewall guidance

Windows hosting needs one inbound allowance; it never needs TCP, every UDP port, every network profile,
DMZ, or a disabled firewall. The engineering PC/Android runner currently starts the shared LÖVE console at
`C:\Program Files\LOVE\lovec.exe`. Its guarded two-guest mode uses exactly UDP ports `57842` and `57844`.
The dedicated helper owns one immutable engineering rule scoped to that exact executable, those exact two
UDP ports, the one active Wi-Fi profile and interface, Internet IPv6 remotes, and blocked edge traversal.

From the project directory, its default action is read-only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\manage_windows_direct_firewall.ps1
```

The process-only execution-policy option lets this reviewed local script run without changing the PC's
saved execution policy.

`Status` reports whether the exact owned rule is active and whether another, broader LÖVE allowance is
also present. It records and prints no IP address. On the current test PC, Windows' normal application
prompt previously created a separate Public-profile `lovec.exe` rule allowing every UDP port. The helper
reports that caveat but never changes, disables, or deletes that user/Windows-owned rule. Adding the narrow
rule while a broad rule remains does not make the effective policy narrow. A PC owner may review such a
rule in **Windows Defender Firewall with Advanced Security > Inbound Rules**, but must not remove it unless
they understand that other LÖVE games and Local Play may rely on it.

Creating or removing the helper-owned rule requires an explicit action in a PowerShell window already
opened with **Run as administrator**; the helper never silently elevates itself:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\manage_windows_direct_firewall.ps1 -Action Add
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\manage_windows_direct_firewall.ps1 -Action Remove
```

`Add` refuses ambiguous Wi-Fi state, a disabled active firewall profile, policy/name conflicts, or any
existing reserved-name rule whose fields differ. `Remove` first verifies the immutable ownership markers
and every narrow security field, then removes only that one rule. It can remove a valid owned rule after a
Wi-Fi rename or profile change, but never selects a rule by display name, program, or port alone. The
non-administrator synthetic predicate check is available with `-Action SelfTest`.

This is an engineering exception because `lovec.exe` is shared by every LÖVE game. The shipped Windows
build must instead target the stable fused `ThePictureShop.exe` path, retain exact UDP port `57842`, cover
only the player-approved active profiles, and use Internet scope for the supported IPv4/IPv6 paths. The
planned per-user installer must not add a broad or surprise exception. A signed elevated helper should run
only after the player explicitly chooses to allow Direct hosting, and the uninstaller must remove only its
immutable owned production rule.

### First residential-gateway finding (2026-08-30)

A bounded, read-only probe of the current Sagemcom BGW530-900 gateway received no response to PCP
ANNOUNCE, NAT-PMP external-address discovery, or SSDP searches for IGD1, IGD2, `upnp:rootdevice`,
and `ssdp:all`. The gateway itself remained reachable and its local management page identified the
manual feature as **Firewall > NAT/Gaming**. No login was attempted and no setting was changed.

This does not prove that every firmware configuration lacks automatic mapping, but it does mean the
game cannot rely on automatic mapping on this gateway today. The next physical test therefore uses
one temporary **UDP-only** forward on a freshly selected random high port to the Wi-Fi host phone. The
script prints the matching `TPS Direct <port>` rule name and exact port. TCP, DMZ, port ranges, and
permanent rules are not part of the test. AT&T's own BGW530 instructions recommend a separate custom
service for each port and describe the same NAT/Gaming flow:
[BGW530 port forwarding](https://www.att.com/support/article-modal/internet/000103568/).

The host's WAN address must come from the player's own gateway page, be classified locally, and never
be sent to a public “what is my IP” service. It is entered only into a hidden local terminal prompt.
Engineering APKs necessarily contain the endpoint and invitation key the client needs, so they are built
in an isolated operating-system temporary tree outside the OneDrive project. That local tree is removed
immediately after both APKs are installed and before the host listener is accepted as ready. Reports do
not record the public address or invitation key, and Android evidence is read only from each diagnostic
package's process-scoped logs. A private, CGNAT, or other special WAN address blocks this path and is
recorded only by classification, never by value.

The repeatable engineering flow is split deliberately:

1. Run `tools/prepare_android_internet_direct_probe.ps1`. It accepts the router-reported WAN IPv4
   through a hidden local prompt, rejects non-global ranges, confirms the client has Wi-Fi off with a
   cellular default route, selects an unused random UDP port, builds and installs both packages, removes
   the local endpoint/key-bearing build tree, and starts only the Wi-Fi host. It prints the host's private
   address, selected port, and `TPS Direct <port>` rule name only after confirming the production gate is
   closed and the secure host listener is ready.
2. In **Firewall > NAT/Gaming > Custom Services**, use the printed rule name and selected port. Set both
   ends of the global range and the base host port to that same number, select protocol **UDP**, choose the
   displayed Wi-Fi host as **Needed by Device**, and save only that one temporary rule.
3. Run `tools/complete_android_internet_direct_probe.ps1`. It starts the cellular client, requires
   matching run IDs and successful encrypted traffic on channels 0, 1, and 2. It proves before and after
   the exchange that the host is still on its prepared Wi-Fi and the client is on cellular with Wi-Fi
   off. Cleanup force-stops and uninstalls both probes, proves both diagnostic packages are absent and
   the host UDP socket is released, restores the game, and reruns smoke tests.
4. Remove the printed `TPS Direct <port>` rule from Hosted Applications immediately, then confirm its
   removal at the completion script's exact prompt. Evidence stays incomplete unless package absence,
   socket release, and this user-confirmed router cleanup all pass.

A hidden 12-minute watchdog bounds the prepared test and removes the fixed diagnostic packages if the
completion step is not run in time. If that window expires, remove the temporary router rule if it was
created, run the completion script to prove cleanup, and then rerun preparation rather than opening a
rule before a listener exists.

The first guarded two-phone run classified the gateway-reported WAN IPv4 as carrier-grade NAT and
stopped before generating an invitation key, building an APK, opening a listener, or requesting a router
rule. No endpoint value was retained. The redacted blocked-run evidence is in
`output/native-crypto/device-tests/android_two_device_internet_direct_probe_blocked_report.json`.
Manual IPv4 forwarding on this gateway cannot cross the carrier's outer NAT.

Read-only device checks found global IPv6 addresses and working IPv6 default routes on both the Wi-Fi
host and cellular client without recording either address. That makes a native dual-stack IPv6 Direct
transport the next no-fee/no-account/no-relay engineering path. A redacted engineering probe now uses
LÖVE's bundled `socket.udp6()` rather than the API-27 shell's UDP-incapable `netcat`. On the physical
ARM32 Wi-Fi host and ARM64 cellular client, both app runtimes opened IPv6 UDP successfully and the script
verified the separate routes before and after. The packet round trip timed out; neither side received the
authenticated sentinel. This proves socket initialization, a client-side accepted send, and no observed
round trip; it does not identify which path or filter dropped the packets.
Both diagnostic packages and the endpoint/token-bearing temporary tree were removed, and no public IPv6
address was recorded. The redacted evidence is in
`output/native-crypto/device-tests/android_two_device_ipv6_udp_probe_report.json`.

The BGW530 firmware bundle contains the label `IPv6 Pin-holing`, a backend `PinHole` firewall chain, and
device-without-IPv6 validation, but inspection of the live Firewall menu confirmed that this page is not
exposed. Do not use **Packet Filter** as a speculative substitute, disable the firewall, change Reflexive
ACL, or create a broader rule.

The safe no-router-change alternative has now passed on the two physical phones. The guarded runner
`tools/run_android_ipv6_simultaneous_probe.ps1` resolved each phone's actual kernel-selected source
address toward the real peer, bound UDP6 port 57842 on both devices, and had both sides send
one-time-token hello/acknowledgement checks from those exact sockets. The ARM32 phone remained on Wi-Fi,
the ARM64 phone remained on cellular with Wi-Fi off, both phones proved receipt in both directions, and
the separate routes were verified before and after. The runner then proved both diagnostic packages
absent and the endpoint/token-bearing temporary tree removed. It retained no public IPv6 address or
ephemeral credential. Redacted evidence is in
`output/native-crypto/device-tests/android_two_device_ipv6_simultaneous_udp_probe_report.json`.

This result validates the network-opening mechanism, not encrypted game transport. The strict two-code
layer is now implemented: the host authenticates the reply before socket activity, both peers use native
CSPRNG challenges and exact echoes on the final UDP6 sockets, restart replay cannot permanently pin stale
state, and a three-second confirmation phase covers a lost final datagram. The ABI-v3 response, opening,
and bridge-cipher conformance passes on the physical ARM32 and ARM64 phones without network permission; its redacted
cleanup evidence is in
`output/native-crypto/device-tests/android_native_crypto_opening_probe_report.json`.

The current ENet address boundary remains IPv4-only. The authenticated IPv6 UDP-to-loopback-ENet bridge
preserves the existing ENet channels/reliability while the Direct Noise layer remains above it. Its native
cipher, bounded fragmentation/reassembly core, one-way opening-socket handoff, and transport adapter pass
deterministic tests. The guarded `tools/run_android_ipv6_bridge_probe.ps1` run also passed on the physical
 ARM32 Wi-Fi phone and ARM64 cellular phone: authenticated opening became a secure ENet connection, game
 traffic moved in both directions while exercising channels 0, 1, and 2, a 1200-byte client payload and
 an 8192-byte host payload forced authenticated bridge fragmentation, and both phones observed it. The
 separate routes were verified
before and after without a router change. Cleanup proved both diagnostic packages absent and the local
sensitive build tree removed; the retained report contains no public IPv6 address or ephemeral
credential. Redacted evidence is in
`output/native-crypto/device-tests/android_two_device_ipv6_encrypted_bridge_probe_report.json`.

The isolated full-game acceptance passed on August 30, 2026, with the API 27 ARM32 Wi-Fi phone hosting
and the API 36 ARM64 cellular phone joining. It exercised the actual `Host Direct Game` / `Join Direct
Game` two-code flow, opened the host save, applied the protocol-v9 shop snapshot, reached Direct 2/4,
observed remote movement, executed a loading-bay interaction and remote cutter E-STOP on the host,
released the workshop lease during a graceful guest departure, rejected a stale invitation, and
reconnected with a distinct fresh invitation. Both isolated engineering packages and the sensitive
temporary tree were removed. The retained redacted report contains no address, host code, reply code,
or key: `output/native-crypto/device-tests/android_two_device_direct_gameplay_report.json`.

The Windows/Android acceptance passed on August 31, 2026, with the Windows PC hosting over Wi-Fi and an
Android phone joining over cellular on a distinct IPv6 prefix. Two fresh invitations completed the real
player flow. Both required explicit approval through the host's Players panel, authenticated the Direct
opening, applied the protocol-v9 snapshot, reached Direct 2/4, moved the remote player, and exercised the
loading bay and cutter safety control. In one session the PC host used the panel's two-click removal and
the phone observed the kick; the other ended with a graceful phone departure observed by the host.
Process logs contained no endpoint, invitation, or key material. Cleanup proved the engineering package,
PC process, isolated save, and temporary build tree absent. The retained report contains no address,
device serial, code, key, packet, raw log, or internal run identifier:
`output/native-crypto/device-tests/pc_android_direct_gameplay_report.json`. The reusable runner is
`tools/run_pc_android_direct_gameplay_probe.ps1`.

A subsequent guarded run repeated both fresh PC-host/Android-cellular sessions while capturing full
packet bytes only for the selected NIC's IPv6 UDP Direct port. It observed authenticated bridge frames
in both directions and found none of the registered invitation-secret/code representations, player-name
canaries, or shop/gameplay plaintext canaries. PktMon used a validated private per-run output directory;
capture stopped, the sole owned filter and capture artifacts were removed, no outside fallback remained,
and no endpoint or raw capture was retained. The redacted evidence is
`output/native-crypto/device-tests/pc_android_direct_packet_capture_report.json`. This is an engineering
result for one tested topology; it does not enable Direct Play or set `productionReady`.

That PC-plus-one-Android packet-privacy pass remains valid. The separate guarded PC-host plus two-Android
run passed on August 31, 2026, with one Wi-Fi guest and one cellular guest. Two sequential fresh
invitations required explicit approval, all devices reached Direct `3/4`, and host movement checks proved
both guests were active. The host removed the Wi-Fi guest using its unique canary while the cellular guest
remained active at `2/4`; the surviving guest then exited gracefully and the host returned to `1/4`.
The exact engineering ports `57842` and `57844` were staged; afterward the helper-owned narrow rule was
removed and the pre-run firewall state was restored. Cleanup passed, and the redacted report records no
endpoint, device serial, invitation, key, packet, or raw log:
`output/native-crypto/device-tests/pc_two_android_direct_gameplay_report.json`. This is engineering
evidence only; `productionReady = false` remains unchanged.

The approval, denial, kick, timeout, single-use invitation, and transport admission boundaries are all
covered by the complete packaged-game smoke suite, which passes 1,557 checks with zero failures after
these changes.

`src/net/direct_connection.lua` composes the two codes, authenticated opening, bridge, encrypted
transport, and one-session multiplayer factory. `src/screens/direct_screen.lua` supplies the guarded host
and join flow, while `src/net/session.lua` accepts that factory without replacing Local Play's default.
This completes the tested two-device Android/Android and PC/Android engineering gameplay gates and the
physical PC-host plus two-Android three-device gate. It does not open the production gate or substitute
for the remaining network matrix and independent security review.

The bridge must fragment at its own authenticated layer. Bundled ENet uses a 1400-byte IPv4 UDP MTU and
its Lua binding has no MTU setter; a maximum realtime message is already about 1240 bytes after Direct,
native-crypto, and ENet framing, while IPv6's minimum MTU leaves only 1232 bytes for the entire UDP
payload before any bridge header. Durable ENet traffic can also aggregate or fragment near 1400 bytes.
The portable design therefore caps accepted inner ENet datagrams at 1400 bytes and carries them in at
most two independently authenticated outer fragments no larger than the 1232-byte IPv6 UDP budget.

Router results in RFC1918, carrier-grade `100.64.0.0/10`, loopback, link-local, documentation,
multicast, benchmark, or other special-purpose ranges are never advertised as Internet invitations.
A global router-reported endpoint is still a candidate, not proof that inbound traffic works. PCP can
cross some provider NATs when the ISP exposes it, but restrictive carrier-grade NAT and double NAT remain
unsolvable without control of the outer mapping, usable IPv6, or a relay. The product response is to try a
different host/network, not to promise a connection that cannot exist.

## Milestones

### 1. Security foundation

- [x] Define a strict, versioned invitation with an injected 32-byte CSPRNG source.
- [x] Reject malformed invitations without echoing their secret in errors.
- [x] Land and validate the fail-closed Direct transport state machine.
- [x] Add the native crypto-provider interface and foundational known-answer tests.
- [x] Reproducibly build the pinned Windows candidate and ship dependency license notices.
- [x] Build every Android ABI candidate and verify the existing 16 KiB ELF alignment requirement.
- [x] Add the complete deterministic TPS-provider-v2 known-answer fixture.
- [x] Run the native and LuaJIT provider conformance on physical ARM32 and ARM64 Android devices.
- [x] Complete a real encrypted ARM64-host/ARM32-client ENet exchange over channels 0, 1, and 2.
- [ ] Run the provider on Android x86_64 and on physical hardware using a 16 KiB kernel.

### 2. Secure manual Direct Play

- [x] Prove same-port, authenticated IPv6 opening across separate physical Wi-Fi and cellular routes.
- [x] Add strict expiring TPS2 host/reply codes and public IPv6 validation.
- [x] Add native response tags and authenticated simultaneous path checks.
- [x] Carry ENet through the IPv6 UDP-to-loopback bridge without exposing unauthenticated traffic.
- [x] Prove the authenticated, encrypted, fragmenting bridge on separate physical Wi-Fi and cellular routes.
- [x] Add explicit `Host Direct Game` and `Join Direct Game` session entry points.
- [x] Add host and join screens with safe copy/paste and secret redaction.
- [x] Pass the full protocol-v9 two-phone player flow across separate Wi-Fi and cellular routes.
- [x] Pass two full Windows-host/Android-cellular player flows, including host approval, kick, and graceful exit.
- [x] Reject a stale invitation and reconnect with a distinct fresh invitation.
- [x] Add explicit host approval/kick controls and pre-allocation rate limits.
- [x] Add program-and-port-specific Windows Firewall guidance.
- [x] Complete the guarded physical PC-host plus two-Android run with one Wi-Fi guest and one cellular
  guest, including narrow firewall staging, kick isolation, graceful exit, and verified pre-run-state
  restoration.
- [ ] Validate two unrelated residential networks before enabling public testing.

### 3. Automatic router mapping

- [x] Add bounded PCP/NAT-PMP codecs, a serialized finite-lease coordinator, and strict pure UPnP IGD handling.
- [ ] Discover the default gateway without contacting an Internet service.
- [ ] Connect PCP, NAT-PMP, and UPnP IGD to live router adapters and try them in that order.
- [ ] Accept a router-selected external port, renew the finite lease, and remove it on shutdown.
- [x] Detect private and carrier-grade-NAT WAN addresses and explain the limitation clearly.
- [ ] Keep manual UDP forwarding as the fallback.

### 4. Release validation

- [ ] Exercise normal routers, disabled mapping, double NAT, carrier-grade NAT, and mobile hotspots.
- [ ] Test four players across separate networks with realistic latency, loss, and reconnects.
- [ ] Verify wrong invitations, tampering, replay, malformed frames, and connection-slot exhaustion.
- [x] Confirm a guarded PC-host/Android-cellular capture contains no invitation key, player name, or
  shop/gameplay plaintext and retains no raw capture.
- [ ] Repeat packet-capture validation across the remaining network/runtime matrix and obtain an
  independent review of the redacted evidence.
- [ ] Obtain an external security review before opening Direct Play to the public.

The Lua wrapper's `productionReady` provider flag only prevents accidental test-provider use. Direct
Play remains disabled even though the deterministic provider, replay, direction-separation, session-key,
nonce, pinned independent Cacophony, host-admission controls, and tested Windows/Android device gates
pass. The remaining runtime matrix, hostile-network validation, repeat/independent capture coverage, and
external security review must complete before that flag changes.

## Non-negotiable limitation

If every participant is behind restrictive carrier-grade NAT, nobody has usable inbound IPv6, and no
player controls a publicly reachable machine, a direct connection is not possible. The game will state
this honestly and suggest changing host or network. A future optional bridge can be player-operated,
but Direct Play will not depend on a commercial relay.
