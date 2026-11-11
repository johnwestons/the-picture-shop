# iOS compatibility

The iOS play path uses the same Lua game source inside a LÖVE archive opened by
the LÖVE2D Studio app. Keep that path compatible alongside Windows and Android
as gameplay, networking, and interface changes land.

## Multiplayer client identity

LAN hosting does not need a local resident identity. Joining as a client creates
and saves a 256-bit resident identity before it opens the network connection;
the host hashes that identity to reconnect the same household resident later.
The shared native crypto library is not included by every LÖVE2D Studio iOS
runtime. `src/net/secure_random.lua` therefore tries Apple's system
`arc4random_buf` through LuaJIT FFI, then `/dev/urandom`, while retaining the
native provider on builds that have it. It fails closed if all secure random
sources are unavailable.

The client transport also retries ENet host creation once with an explicit
ephemeral local socket (`*:0`) on iOS when the usual unbound-client form fails.
It uses the same remote endpoint, channel count, and packet validation.

## Connection watchdog

Options > Debug records connection startup, incoming workers, approval waits,
successful joins, timeouts, transport failures, and recovery in the game
watchdog. Reports classify failures without storing endpoints, player names,
packets, invitation codes, or resident tokens. Repeated reports are throttled
and history is bounded by the existing watchdog limit.

LAN recovery now covers a first join that opens a transport but times out,
as well as a lost established connection. The existing reconnect scheduler
retries the same host with bounded backoff. Cancel, protocol rejection, a full
shop, and host removal retain their existing stop behavior. Internet Direct
approval and cryptographic checks remain required; the watchdog does not
reuse expired invitations or downgrade connection security.

Run `tools/run_delivery_route_smoke.ps1 -Focus connection-watchdog -Runs 1`
for the iOS adapter fixtures, connection reports, ENet transport, multiplayer
session, and reconnect checks. These fixtures do not confirm which secure
random API a particular LÖVE2D Studio release exposes on a physical iPad.

## Compatibility review

For each substantial platform or multiplayer update, include the iOS LÖVE2D
Studio archive made from the same source revision in the mobile review. Check:

- Launch, touch controls, text entry, orientation, safe areas, suspend/resume,
  and save/reload on iPad.
- LAN hosting from iOS with Windows and Android guests.
- LAN joining from iOS to Windows and Android hosts, including first launch
  when no resident identity file exists and reconnect after relaunch.
- Any changed delivery, worker, or vehicle flow on both PC and mobile layouts.
- Multiplayer parity in both host and guest roles; a successful host check does
  not establish that client startup works.

Desktop and Android automated checks remain useful for shared Lua behavior but
do not replace launching the archive in the iOS LÖVE runtime. Record the archive
version and physical-device result with the corresponding multiplayer review.
