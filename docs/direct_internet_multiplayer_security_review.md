# Direct Internet Multiplayer Security Review

## Purpose and decision boundary

This packet is for an independent security reviewer of the existing Direct Internet multiplayer
implementation. It does not authorize public testing or enable Direct Play. `productionReady` must
remain false until the reviewer signs off and every separate platform/network acceptance gate in
[`direct_internet_multiplayer.md`](direct_internet_multiplayer.md) passes.

The reviewed product has no account, matchmaking service, telemetry, or relay. It uses one-use,
expiring invitation codes shared out of band; an authenticated guest still receives no player slot or
shop snapshot until the host explicitly approves that guest. Local Play is outside the Direct security
boundary and must continue to work if Direct is unavailable.

## Components in review scope

Review the current source at a specific commit, including the exact native binaries and packaged
loader used for any claimed pass. At minimum, cover:

| Boundary | Components and questions |
| --- | --- |
| Native cryptography and packaging | `src/net/crypto_native.lua`, native crypto/provider sources and build scripts: key generation, KDF domain separation, Noise configuration, AEAD nonce handling, error behavior, memory clearing, ABI validation, pinned dependencies, reproducible builds, and packaged-library authenticity limits. |
| Invitation and opening | `src/net/direct_invite.lua`, `src/net/direct_opening_code.lua`, `src/net/direct_opening.lua`, and `src/net/direct_connection.lua`: entropy, parsing/canonicalization, expiry/skew, endpoint binding, replay resistance, retry bounds, and secret redaction. |
| Encrypted transport | `src/net/transport_direct.lua`, `src/net/direct_bridge.lua`, and the bridge/ENet adapters: authentication before connect, channel binding, replay windows, packet/fragment bounds, cross-channel reordering, rate limits, and teardown. |
| Game admission | `src/net/session.lua`, `src/net/transport_direct_composite.lua`, and `src/app.lua`: protocol validation, quarantine before approval, one-use guest links, slot limits, guest removal, and isolation of Local Play behavior. |
| IPv4 reachability | `src/net/direct_ipv4_host.lua`, `src/net/direct_ipv4_listener.lua`, `src/net/gateway_native.lua`, `src/net/gateway_discovery.lua`, `src/net/router_mapping_adapter.lua`, and `src/net/reachability.lua`: exact-interface binding, route revalidation, hostile gateway input, mapping ownership, finite leases, renewal/deletion, and listener-before-router-cleanup ordering. |
| User-visible handling | `src/screens/direct_screen.lua` and status/error reporting: invitation privacy, clipboard ownership, cancellation, expiry, route changes, foreground loss, and safe failure messaging. |

## Required adversarial review

The reviewer should independently assess whether an attacker can:

- cause unauthenticated packets to allocate unbounded state, consume excessive CPU/memory, or trigger
  amplification;
- bypass the handshake, alter an endpoint or channel, replay a handshake/game packet, exploit nonce
  reuse, or inject data before authentication completes;
- reuse an expired, declined, removed, or already-consumed invitation, or gain a player slot or durable
  game state before explicit host approval;
- exploit malformed, truncated, oversized, reordered, duplicated, fragmented, or flood traffic;
- confuse route selection or mapping ownership so the game binds/maps/deletes on a different interface,
  gateway, port, or network generation than the one it validated;
- cause a stale invitation to survive mapping renewal, route change, disconnect, cancellation, or shutdown;
- recover invitation keys, player identity, endpoint details, or gameplay plaintext from ordinary logs,
  errors, crash reports, or retained test evidence; or
- use a test provider, environment override, loose native-library copy, or modified package to cross the
  production gate unintentionally.

Please distinguish exploitable defects from assumptions that require physical-network validation. A
passing deterministic test suite is useful evidence, not a substitute for independent protocol review or
real router/device testing.

## Evidence to review

The review owner should provide a privacy-safe, immutable evidence bundle containing:

1. Exact source commit, working-tree cleanliness, build commands/toolchain versions, native dependency
   revisions, and hashes of the reviewed Windows and Android packages/libraries.
2. Automated results for native conformance, independent protocol vectors, hostile handshake/transport
   tests, Direct/session integration, cleanup fault injection, and the complete packaged-game smoke suite.
3. Results from the required Windows IPv4 create/renew/delete/player-flow acceptance on a genuine public
   IPv4 residential route, plus the cross-network, multi-player, latency/loss/reconnect matrix.
4. Android runtime evidence for every supported ABI, including x86_64 and execution on an actual 16 KiB
   page-size kernel where that configuration is claimed.
5. Repeat packet-capture checks across the remaining platform/network matrix. Retain only redacted
   conclusions and capture hashes; do not distribute raw invitations, keys, addresses, player names,
   gameplay plaintext, or raw captures.
6. Windows install/uninstall and package-provenance evidence, including confirmation that production
   loading cannot be redirected to an unreviewed native binary.

If a required device, router, or network topology is unavailable, record it as an open gate rather than
extrapolating a pass from another topology.

## Finding disposition and sign-off

For each finding, record a severity, affected component, reproducible evidence, impact, and disposition.
No unresolved critical or high-severity finding may remain. Any accepted lower-severity risk must name
the product owner, rationale, mitigation, and review date. A code or dependency change after review
requires the reviewer to identify which conclusions must be repeated.

```text
Reviewer / organization:
Independence or conflicts disclosed:
Review date:
Source commit:
Reviewed package hashes:
Platforms and network paths actually reviewed:
Critical findings open:
High findings open:
Accepted lower-severity risks and owner:
Required follow-up / re-review conditions:
Decision: PASS / FAIL / INCOMPLETE
Reviewer confirmation:
```

`PASS` means only that the reviewer found no release-blocking security issue within the stated review
scope and evidence. It does not waive the physical network/runtime matrix, public-IPv4 router acceptance,
package signing/provenance work, or any other release gate recorded in
[`direct_internet_multiplayer.md`](direct_internet_multiplayer.md).
