# Remote multiplayer audit — October 18, 2026

The reported failure was PC-to-PC using a TPS invitation. The invitation prefix,
build versions and exact failed stage are no longer available, so the specific
past attempt cannot be assigned a proven root cause. This audit found and fixed
three connection defects that can prevent remote play, plus broken test-kit
packaging. A fresh connection between the two PCs remains the decisive test.

## Confirmed defects and repairs

| Area | Failure before repair | Repair and evidence |
| --- | --- | --- |
| IPv6 (`TPS2H` / `TPS2R`) | `direct_connection.lua` bound UDP6 to `::`, while the invitation advertised a player-entered address. A PC with multiple IPv6 addresses could send from another address; the exact-peer filter would silently discard its opening packets. | Bind host and guest to their canonical advertised address and verify both address and port with `getsockname()` before generating invitation secrets. A nonlocal address now fails at socket creation. Tests cover both peers, failed binding, a mismatched reported address, canonical equivalence, and cleanup. |
| IPv4 (`TPS1`) route ownership | `direct_ipv4_listener.lua` copied a discovered route without `routePrefixLength`. The real gateway validator requires `routePrefixLength == 0`. Host updates, manual confirmation or session attachment could therefore report a changed network and close a valid listener. | Preserve the complete required route fields in normal and failed-cleanup owners. Host tests now use real gateway normalization/revalidation instead of an identity stub. |
| IPv4 UPnP fallback | The router adapter returns method `upnp_igd`, but invitation publication accepted only `pcp`, `nat_pmp` and `manual`. Even a successful UPnP mapping was rejected. | Accept the exact UPnP method, retaining the global-address check and rejection of unknown methods. |
| Remote test kit | The builder listed top-level modules explicitly. Refactored transport, address and UPnP modules required files missing from the staged package. A new build from current source would not load correctly. | Follow literal `src.*` dependencies recursively before packaging; fail on a missing dependency. Keep external-service checks on every staged dependency and narrowly scope the existing UPnP URL exceptions. Isolated runtime-loading tests exercise the staged closure. |

The repaired code is in the working tree. The follow-up Windows build below
includes it; older installed game binaries and distributed ZIP files do not
receive these fixes automatically.

## What the evidence actually establishes

- The August 30–31 engineering reports contain successful IPv6 remote traffic,
  including PC-to-cellular gameplay and a PC host with Wi-Fi and cellular guests.
  These were isolated engineering builds using the older protocol, not proof
  that today's normal game build connects between this pair of PCs.
- The September 3 IPv4 observation records `mapping_timeout` before invitation
  publication and before the guest phase. It is an operator transcription,
  explicitly diagnostic evidence. It cannot explain a separate attempt that
  already produced an invitation without knowing which build/path was used.
- The September 27 result intake is missing a host result. There is still no
  accepted real-router create/renew/delete plus remote IPv4 result pair.
- Normal Direct Play remains gated by `CryptoNative.productionReady = false`;
  IPv4 hosting has a second readiness gate. The audit does not substitute local
  regression tests for the outstanding release/security review.
- The game protocol is currently version 40. Use the same current build on
  both machines for gameplay tests; the old device reports refer to version 9.

Evidence locations:

- `output/native-crypto/device-tests/pc_android_direct_gameplay_report.json`
- `output/native-crypto/device-tests/pc_two_android_direct_gameplay_report.json`
- `output/public-ipv4-evidence/kit-7a28a30228c1f416/observation.txt`
- `output/public-ipv4-results/verified-remote-result.json`

## Checks completed during this audit

- Focused engine suite: **1,215 checks and three draw frames pass in each of
  desktop and forced-mobile modes**. This exercises Direct IPv4/IPv6, invitations,
  opening/bridge, transports, route/mapping, sessions, protocol, impairment, soak,
  screen and reconnect tests. Forced-mobile is a desktop layout test.
- Old implementations reconstructed in an isolated harness fail the new
  regressions: IPv4 has four failures plus a lifecycle exception; IPv6 has five
  failures. Corrected targeted suites pass **33 IPv4 and 20 IPv6 checks**.
- Real ENet UDP loopback passes **12 checks with three guests**, including
  snapshots, movement, scene/stock replication, disconnect isolation and
  reconnect. Two stale doorway coordinates in this test fixture were repaired.
- **78 tooling tests pass**, covering remote result validation, launcher and
  watchdog behavior, kit dependency closure/loading, and device/guest-worker
  acceptance preparation.
- Native crypto and native route self-tests pass. Read-only gateway discovery
  and exact-source socket/listener checks pass, with no mapping request or
  invitation issued.
- This PC's read-only IPv6 readiness check passes: a global IPv6 address and
  default route exist. **Inbound reachability is still unproven.**
- The actual freshly packaged Windows host launcher passes its no-traffic
  preflight, including native crypto, exact socket, secure listener and UPnP
  transport availability. It creates no router mapping or firewall rule.

The execution sandbox blocks UDP loopback and Windows network-management
queries. Those checks were rerun outside it: loopback and IPv6 readiness then
passed. The initial sandbox failures are not game/network evidence. A separate
read-only .NET interface query also confirmed IPv6 addressing. The Android ADB
query could not start its daemon, so no Android-device availability claim is made.
The hidden preflight launch initially inherited PowerShell 7 module paths into
Windows PowerShell 5.1 and could not load `Get-FileHash`. Giving that child the
Windows PowerShell module paths resolved it; the packaged launcher then passed.

Reports are under `output/multiplayer-audit-20261018/`; failing-before/passing-after
evidence is `output/multiplayer-audit/listener-regression.txt`.

## Follow-up Windows game update

The complete current playable game was rebuilt and installed as
**0.1.0-test.55** at
`C:/Users/johnw/AppData/Local/Programs/The Picture Shop/ThePictureShop.exe`.
The title's shared runtime version is `0.1.0-android.55`; Windows installer
metadata uses `0.1.0-test.55`. Both identify version 55 and protocol 40.

The normal Windows installer had also omitted `tps_crypto.dll`. The builder now
validates the native candidate's exact artifact hash, ABI, suite, x64 target,
conformance checks and current source hashes, and installs it beside the game.
It records that provider in the build report. Runtime production gates remain
false; bundling the library does not expose unrestricted Direct Play.

Validation of this update:

- 582 packaged Lua files and 483 selected runtime assets match the current
  source tree, allowing only generated version and pinned-route-loader changes.
- Both the fused package and actual installed game pass 6,031 checks and three
  rendered frames with isolated output-local test saves.
- All 12 installed application files match the build hashes.
- 17 packaging tests pass; the source-art test count was corrected to the
  existing 70-file allowlist.
- Lua/native cryptographic conformance passes against the installed DLL.
- Current Critter Crisis mission multiplayer integration is included. The
  previously disabled unfinished Frontier modes remain excluded as intended.

Matching installer for the other PC:
`output/windows-multiplayer-2026-10-18/ThePictureShop-Windows-Setup-0.1.0-test.55.exe`.
SHA-256: `06c2df2aef313d22e5c53bc47fbd8e5db77f0105912249b297abe92d8188eb69`.
The build, payload verification, installed-file verification, smoke and native
conformance reports are in that same output directory. This is a dirty-tree,
unsigned private tester build. No new remote-network acceptance is claimed.

## Prepared IPv4 test kit

The fresh kit is
`output/public-ipv4-audit-2026-10-18/ThePictureShop-PublicIPv4-Remote-Test.zip`.
Its host and guest manifests verify, the actual host preflight passes, and its
build records no network traffic. This kit tests IPv4 transport and mapping;
it does not expose the normal game or run the full player approval/shop flow.

- ZIP SHA-256: `821af2d47abfa60f6f70b37662ee99ff86a326e34f49ec2b3685cd11e600fee9`
- Source commit: `33a1f4de9e5f6a7cc589d5dcefe69ae13749aea4`
- Source worktree: dirty, explicitly recorded in the build report.

The historical September 27 kit and default verifier pins remain intact. For
results from this new kit, use the new kit's pinned helper instead of the old
default verification command:

```powershell
.\output\public-ipv4-audit-2026-10-18\verify-results.ps1 `
    -HostResult 'PATH_TO_NEW_HOST_RESULT' -GuestResult 'PATH_TO_NEW_GUEST_RESULT'
```

After confirming both original result files came from the same fresh attempt
and the host reported firewall cleanup, add `-SameAttemptConfirmed` and
`-FirewallCleanupConfirmed`. Missing evidence is not acceptance. The helper pins
this ZIP hash, source commit and dirty state; the general verifier now supports
explicit complete reference profiles and rejects partial/malformed ones.

Rebuilding with `tools/build_public_ipv4_mapping_probe.ps1 -OutputName
public-ipv4-audit-2026-10-18` replaces that generated output directory and changes
the ZIP pin. Use a new output name for a subsequent independently retained kit.

## Android-to-Android testing now takes priority

The user selected two Android phones on separate Wi-Fi networks; one is remote.
The next physical test therefore uses a manually operated APK with both roles,
instead of the older ADB runner that assumes both specific phones are connected
to this PC. The normal Windows installation above predates these additional
phone-specific changes and will need a new build before the deferred PC test.

Additional blockers corrected for this test:

- Android focus loss cancelled a pending Direct invitation immediately, making
  a switch to Messages destroy the code being shared. Pending setup now uses
  the existing 120-second background grace, then clears the socket, invitation
  and owned clipboard content. Failed cleanup retains its owner for retry.
- The grace clock now includes wall time as well as monotonic time, so device
  deep sleep does not extend the grace. A backward wall-clock change cannot
  extend the monotonic limit.
- The engineering screen selects a local public IPv6 source and verifies an
  exact bind before offering it. Guest selection uses the actual host address.
  No address service, DNS or application datagram is used by this local check;
  it does not prove remote reachability. Normal UI behavior is unchanged unless
  the engineering callback is explicitly supplied.

The test app is `Picture Shop Direct Test`, version `0.1.0-direct-test.55`,
package `com.thepictureshop.direct_test`, with isolated test saves. It uses the
full current game bootstrap and protocol 40. Only its entry point enables the
native candidate for this process; the ordinary source gates remain false and
Android IPv4 hosting remains unavailable. It embeds no peer or invitation and
does not auto-connect or auto-approve anyone.

The builder verifies the actual shared archive against current source bytes,
records the separate engineering transformations and refuses stale inputs. It
uses a fresh output directory and isolated Android wrapper, and never installs
to a phone. Full steps and first-failure reporting are in
[the Android remote-test guide](android_direct_remote_test.md).

Completed artifact:
`output/android-manual-direct-2026-10-18-ready/ThePictureShop-DirectTest-0.1.0-direct-test.55.apk`
(440,908,060 bytes). SHA-256:
`76a0fc3214d6ab465babb251deca8c95759b5df829f989d15186d79841c260ef`.

Validation completed:

- Full packaged-game smoke: 6,073 checks and three rendered frames, with mobile
  mode enabled in desktop LÖVE and the Windows native candidate. All 1,090
  archived entries match the final APK's game content; only ZIP timestamps
  differ from the smoke-tested archive.
- 15 targeted engineering bootstrap/UI checks and 25 focus/lifecycle checks.
- Fresh native crypto conformance, exact embedded game/native hashes, Android
  signature, app identity/version, permission checks, gateway packaging checks
  and 16 KB alignment checks pass. ABIs: armeabi-v7a, arm64-v8a and x86_64.
- The automatic selector preserves explicitly supplied selectors and is not
  injected during smoke tests; deterministic tests do not use machine routing.
- No Android devices were connected; no device installation, startup or new
  remote connection has been verified. The test APK is signed for private
  engineering use, not a promoted production release.

Reports and smoke output are in `output/android-manual-direct-validation/` and
the final APK's directory. The earlier interrupted attempt is marked superseded.

## Deferred PC-to-PC test

1. Record both build versions, the invitation **prefix only**, and each visible
   stage. Keep the full invitation private: it contains the session secret.
2. Run **Check IPv6 Readiness.bat** on both PCs. If both pass, prioritize the
   corrected IPv6 path in matched engineering builds. Check the scoped Windows
   firewall rule, generate a fresh host code, return the guest reply code, then
   wait for encrypted authentication and the host's explicit approval request.
3. Require a real shop snapshot and movement in both directions, one guest
   interaction, clean disconnect and a new-invitation reconnect. Record the first
   missing stage; “no lobby” is too broad to distinguish routing, opening,
   authentication, version rejection, approval and snapshot failures.
4. If IPv4 is needed, use the refreshed public-IPv4 kit. First prove the host
   creates a mapping and publishes an invitation. Then require remote encrypted
   traffic on all three channels, one lease renewal, listener closure, mapping
   deletion and owned firewall-rule cleanup. Return the original redacted host
   and guest result files from the same attempt.
5. If mapping times out, run the kit's counters-only mapping traffic diagnostic
   on that unchanged host/network. A missing router reply, a rejected reply and
   a packet that never left the PC require different fixes. Manual forwarding is
   a separate fallback test after public-WAN reachability is established.

These steps apply after the requested phone-to-phone test. Broader residential/mobile,
four-player, Android ABI/kernel and independent packet/security reviews remain
separate release work. A public lobby service or automatic universal NAT bypass
is not implemented by this direct-connect architecture.

## Repeating the focused engine checks

Use an isolated output-local profile, as in this audit:

```powershell
$env:APPDATA = Join-Path $PWD 'output/multiplayer-audit-20261018/appdata'
$env:PICTURE_SHOP_TEST_IDENTITY = 'the-picture-shop-test-multiplayer-audit'
$env:PICTURE_SHOP_SMOKE_FOCUS = 'direct-multiplayer'
.\.stabilization\run-smoke.ps1 -ReportPath "$PWD/output/multiplayer-audit-20261018/direct-desktop.rpt"
$env:PICTURE_SHOP_MOBILE = '1'
.\.stabilization\run-smoke.ps1 -ReportPath "$PWD/output/multiplayer-audit-20261018/direct-mobile.rpt"
```
