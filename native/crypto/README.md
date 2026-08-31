# Direct Play native crypto candidate

This directory describes an engineering candidate for The Picture Shop's free, accountless Direct Internet Play security boundary. It is not a production security claim and it does not enable Direct Play, open a public listener, or make the Lua provider `productionReady`. The feature must continue to fail closed until every release gate below is independently satisfied.

The candidate is entirely bundled with the game. It needs no hosted cryptography service, account, subscription, matchmaking server, relay, telemetry endpoint, or recurring fee. Noise-C and libsodium are third-party open-source code whose exact sources and license notices are pinned in `dependencies.json`; the independent Cacophony vector snapshot used by the known-answer test is pinned there as well.

## Boundary and ABI

LÖVE 11.5 uses LuaJIT on the target platforms. Lua calls a small, versioned C ABI through LuaJIT FFI. The ABI exposes only opaque provider and peer-state handles, byte buffers with explicit lengths and capacities, fixed-width integers, and status codes. Noise-C structs, libsodium state, keys, counters, and replay bitmaps never cross into Lua.

This boundary is intentional:

- it avoids binding the provider to a particular Lua C-module ABI or exposing third-party struct layouts;
- the same semantic API can be loaded from a Windows DLL and Android ABI-specific shared libraries;
- buffer ownership and output bounds remain explicit at the native boundary;
- secret comparison, authenticated decryption, CSPRNG use, counters, replay state, and zeroization remain native; and
- Lua receives only public outputs or generic failure codes, never a secret-bearing diagnostic.

ABI version, provider capabilities, and suite identifier must be queried before state creation. The
current boundary is ABI version 3 with an exact 24-symbol export allowlist. The exact suite identifier is:

```text
TPS-Direct-v3/Noise_NNpsk0_25519_ChaChaPoly_BLAKE2s/XChaCha20-Poly1305
```

An unknown ABI version, a different suite string, a failed native self-test, a missing library, or a missing required symbol leaves Direct Play unavailable. Handles have one owner; destruction wipes and frees all PSK, contribution, transcript, Noise cipher, traffic-root, channel-key, nonce, counter, and replay state. Cleanup must be safe on every partial-construction and authentication-failure path.

Every call involving one peer handle is serialized by the Lua transport on its owner thread. The C ABI deliberately does not permit simultaneous operations on the same handle or overlapping input/output buffers; the header records both requirements. State destruction is allowed only after all calls for that handle have returned.

## Reproducible candidate builds

Run `tools/build_native_crypto.ps1` for the clean pinned Windows x64 build and native conformance test.
Run `tools/verify_native_crypto_reproducible.ps1` to perform two clean Windows builds and require a
byte-for-byte identical DLL. Run `tools/build_native_crypto_android.ps1` for direct NDK builds of
`armeabi-v7a`, `arm64-v8a`, and `x86_64`, including export-surface, dependency, immediate-binding,
and 16 KiB ELF segment checks.

The evidence is written beneath `output/native-crypto/build`. These scripts deliberately report
`productionReady: false`. The deterministic provider fixture passes, and
`tools/run_android_native_crypto_probe.ps1` runs the no-network ABI-v3 response, opening, and bridge-cipher
conformance on selected physical ARM devices, removes the fixed probe package in `finally`, proves package
absence, and writes redacted evidence beneath `output/native-crypto/device-tests`. This does not replace
the remaining runtime matrix or public release gates.

## Response authentication and simultaneous opening

The fixed `TPS2R` response transcript is exactly 120 bytes. A 32-byte response key is derived from the
invitation master with libsodium KDF context `TPSRSPK1`; keyed BLAKE2b-256 over the complete transcript
produces the response tag. Verification is constant-time and the Lua boundary returns only success,
ordinary authentication rejection, or an opaque infrastructure failure.

Each host and guest opening state derives a separate check key under `TPSCHKK1` and `TPSCHK01`, creates a
fresh 16-byte operating-system CSPRNG challenge, and exchanges exact 92-byte `TPSO` version-1 packets.
The invitation ID, guest nonce, sender role, flags, sender challenge, peer-challenge echo, big-endian
counter, and 16-byte keyed BLAKE2b tag are fixed and authenticated. Readiness requires both an exact echo
of the local challenge and the peer's authenticated verification flag.

An authenticated no-echo packet is not yet fresh for a newly created state. Its peer challenge remains a
replaceable provisional candidate and does not enter the main replay window. An exact candidate duplicate
is rejected, while a same-counter packet with a different authenticated current challenge may replace a
captured stale candidate. Permanent challenge pinning and the 64-packet replay window begin only after an
authenticated packet exactly echoes this state's fresh local challenge. The Lua controller additionally
keeps the final packet alive for a bounded three-second confirmation grace so one lost final UDP datagram
does not strand the other peer.

## IPv6-to-loopback bridge cipher

After simultaneous opening, the exact authenticated UDP6 socket transfers once to the bridge. Each
direction receives a separate XChaCha20-Poly1305 key under KDF contexts `TPSBRGK1`, `TPSBGKY1`, and
`TPSBGNN1`. A bridge body is an authenticated 64-bit sequence followed by ciphertext and a 16-byte tag;
the fixed 32-byte `TPSB` fragment header is associated data. Receive state uses a 64-packet replay window,
and authentication failures do not consume a sequence.

The bridge accepts inner loopback ENet datagrams no larger than 1400 bytes. It splits them into at most
two independently authenticated plaintext fragments of at most 1176 bytes, keeping every complete outer
UDP6 datagram at or below 1232 bytes. Reassembly count, bytes, lifetime, completed identifiers, and work
per update are bounded. Wrong sources, malformed headers, unauthenticated fragments, and replays are
discarded before reaching ENet. The bundled provider remains non-production despite this implementation.

## Handshake

The exact Noise protocol name is `Noise_NNpsk0_25519_ChaChaPoly_BLAKE2s`. The 32-byte invitation is a master secret, not PSK 0 itself. The provider derives a dedicated 32-byte Noise PSK with libsodium's KDF using subkey id `0` and context `TPSNPSK1`. It separately derives the admission-filter key with subkey id `0` and context `TPSADMK1`, then wipes both temporary subkeys. The derived Noise PSK is used only inside Noise; the invitation master is used only by the KDF. No static identity key, account, or certificate exists: possession of the invitation is the authorization. A new ephemeral keypair and new random contributions are required for every connection. The Noise prologue is the exact 23-byte ASCII string `TPS-DIRECT-HANDSHAKE-v1`, without a trailing NUL; in hex it is `5450532D4449524543542D48414E445348414B452D7631`.

The provider uses four reliable control-channel frames, all inside the outer `TPSD`, version 1, handshake framing:

1. The initiator generates a 32-byte contribution with `randombytes_buf()` and sends it as the encrypted payload of Noise handshake flight 1.
2. The responder authenticates flight 1, generates its own 32-byte contribution with `randombytes_buf()`, and sends that contribution as the encrypted payload of Noise handshake flight 2. The `ee` result and PSK protect this payload. Both parties retain the post-flight-2 Noise handshake hash.
3. Both calculate the same 32-byte root with keyed BLAKE2b-256: the initiator contribution is the key, and the message is the exact eight ASCII bytes `TPSROOT1`, followed by the Noise handshake hash, followed by the responder contribution. After Noise Split, the initiator sends its first initiator-to-responder Noise transport message with exact plaintext `TPSFIN01 || handshake_hash`. The responder must authenticate the ciphertext and validate the complete label and hash before becoming ready.
4. The responder sends its first responder-to-initiator Noise transport message with exact plaintext `TPSACK01 || handshake_hash`. The initiator must authenticate the ciphertext and validate the complete label and hash before becoming ready.

The finish and acknowledgement provide explicit key confirmation in both directions. The responder may become ready only after accepting the finish and successfully producing the acknowledgement; the initiator may become ready only after accepting that acknowledgement. Neither message contains a root contribution. Unexpected flights, duplicate state transitions, wrong payload lengths, wrong labels, wrong hashes, failed Noise operations, and packets received after readiness are fatal to that peer.

After the acknowledgement, the provider wipes both contributions, the handshake hash, and the transient root-derivation input, then destroys the Noise handshake and transport cipher states. The transcript-bound root remains only inside the opaque native peer state so channel keys and nonce prefixes can be derived lazily; it is wiped when that peer state closes. Noise transport encryption is not used for game packets because the game permits durable payloads larger than Noise's 65,535-byte message limit.

Noise-C's `rev32` branch is an unreleased, stale implementation candidate. For the supported NNpsk0 suite, the upstream branch omits the standard PSK-mode `MixKey(e.public_key)` step for message-token `e` and advances its handshake cipher nonce after a failed decrypt. The maintained patch repairs those exact supported paths, replaces the bundled Curve25519-DONNA calculation with libsodium's checked X25519 operation, and removes unused algorithm factories. It is not a general repair for other Noise patterns. The exact Cacophony vector must pass after those changes. Merely compiling the upstream snapshot is insufficient.

The admission token is only a public, deterministic, 31-bit load-shedding hint sent in ENet connection data. It can collide, be observed, correlated, copied, and replayed. It never authenticates a player and never replaces the complete Noise exchange; a matching token merely lets the host allocate a bounded handshake slot.

## Data keys, framing, and replay

The transcript-bound root is only a KDF master. It is never used directly as an AEAD key. For each direction and observed ENet channel, libsodium derives a distinct 32-byte XChaCha20-Poly1305 key using context `TPSDKEY1`. It separately derives a 16-byte nonce prefix using context `TPSDNON1`. The 64-bit subkey identifier is exactly `((uint64_t) direction << 8) | channel`, where direction is `0` for initiator-to-responder and `1` for responder-to-initiator and channel is the observed unsigned 8-bit ENet channel. This prevents accidental cross-direction or cross-channel subkey reuse.

Each direction has an independent unsigned 64-bit sequence counter per channel. Sequence values are serialized in network byte order. A data-frame body is:

```text
sequence_be64 || xchacha20_poly1305_ciphertext || tag_16
```

The 24-byte XChaCha nonce is `derived_nonce_prefix_16 || sequence_be64`. The native provider appends `sequence_be64` to the Lua wrapper's associated data, which is already `TPSD || 0x01 || DATA || observed_channel`. Consequently the protocol version, packet type, observed ENet channel, and sequence are all authenticated. Sequence `2^64 - 1` is reserved; reaching it closes the peer before nonce reuse.

Receive state uses a separate 64-packet sliding replay window for every direction/channel key. The provider may parse and range-check a sequence before decryption, but it must not advance the highest sequence or set a replay bit until AEAD authentication succeeds. Authenticated duplicates, sequences more than 63 behind the highest accepted value, tag failures, channel substitution, and malformed or truncated bodies are rejected. Valid out-of-order packets inside the window are accepted once.

## Release gates

`productionReady` must remain false until all of the following are evidenced in a release artifact, not merely planned:

- Every downloaded archive matches `dependencies.json`; source and tool updates require an explicit provenance review and new hashes. All required notices ship with the game.
- The native ABI reports the exact version and suite above and fails closed on any capability, symbol, allocation, entropy, initialization, self-test, or version mismatch.
- The exact pinned independent Cacophony NNpsk0 vector passes from handshake through post-split transport messages, along with libsodium XChaCha20-Poly1305 and KDF known-answer tests.
- A deterministic provider fixture pins the exact 23-byte prologue above and produces byte-identical handshake, finish, acknowledgement, root, key, nonce, and data results on Windows x64 and every supported Android ABI.
- Regression tests cover the Noise-C failed-decrypt nonce fix and prove that all failed authentication paths leave handshake and data counters unchanged.
- Negative tests cover wrong invitations, modified prologues, every handshake flight, contribution, finish and acknowledgement labels/hashes, ciphertext, tag, AAD, channel, direction, sequence, length, truncation, replay, too-old packets, counter exhaustion, and use-after-close.
- Session tests prove fresh roots on reconnect, direction and channel separation, accepted in-window reordering, rejected duplicates, bounded allocations, handshake timeouts, pending-peer exhaustion, and cleanup after every failure point.
- Fuzzing or equivalent structured malformed-input testing exercises every native entry point without crashes, out-of-bounds access, secret-bearing errors, or unbounded work.
- All key material and partially constructed state are wiped on normal close, remote disconnect, timeout, authentication failure, allocation failure, and library shutdown; this receives manual native-code review.
- Windows packaging contains only the pinned provider binary and intended system dependencies. Android packages `armeabi-v7a`, `arm64-v8a`, and debug `x86_64` variants, and every packaged native library passes 16 KiB ELF segment and final APK ZIP-alignment audits.
- Real Windows-to-Android and Android-to-Android sessions pass under latency, loss, reordering, reconnect, and four-player load. Packet captures reveal neither invitation material nor player/gameplay plaintext.
- An external security review approves the final native code, dependency patches, ABI wrapper, protocol construction, build provenance, and release binaries before a public port can be opened.

Passing these gates establishes eligibility for integration testing; it does not remove the product-level NAT limitation. If neither player is publicly reachable through IPv4 mapping/forwarding or usable inbound IPv6, a direct connection cannot be created without a relay.
