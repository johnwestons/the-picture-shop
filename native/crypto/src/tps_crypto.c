#include "tps_crypto.h"

#include <noise/protocol.h>
#include <sodium.h>

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define TPS_NOISE_PROTOCOL "Noise_NNpsk0_25519_ChaChaPoly_BLAKE2s"
#define TPS_SUITE "TPS-Direct-v3/" TPS_NOISE_PROTOCOL "/XChaCha20-Poly1305"

#define TPS_HANDSHAKE_FLIGHT_BYTES 80u
#define TPS_FINISH_PLAINTEXT_BYTES 40u
#define TPS_FINISH_WIRE_BYTES 56u
#define TPS_ACK_PLAINTEXT_BYTES 40u
#define TPS_ACK_WIRE_BYTES 56u
#define TPS_REPLAY_WINDOW_BITS 64u

#define TPS_OPENING_MAGIC_OFFSET 0u
#define TPS_OPENING_VERSION_OFFSET 4u
#define TPS_OPENING_TYPE_OFFSET 5u
#define TPS_OPENING_ROLE_OFFSET 6u
#define TPS_OPENING_FLAGS_OFFSET 7u
#define TPS_OPENING_INVITATION_ID_OFFSET 8u
#define TPS_OPENING_GUEST_NONCE_OFFSET 24u
#define TPS_OPENING_CHALLENGE_OFFSET 40u
#define TPS_OPENING_ECHO_OFFSET 56u
#define TPS_OPENING_COUNTER_OFFSET 72u
#define TPS_OPENING_TAG_OFFSET 76u
#define TPS_OPENING_FLAG_ECHO_PRESENT 0x01u
#define TPS_OPENING_FLAG_LOCAL_VERIFIED 0x02u

/*
 * Suite v2 deliberately retains the v1 handshake prologue as its pinned
 * wire-domain identifier.  Changing it is a protocol break and requires a
 * complete regeneration of the provider known-answer vector below.
 */
static const uint8_t tps_prologue[] = "TPS-DIRECT-HANDSHAKE-v1";
static const uint8_t tps_root_domain[] = "TPSROOT1";
static const uint8_t tps_finish_domain[] = "TPSFIN01";
static const uint8_t tps_ack_domain[] = "TPSACK01";
static const uint8_t tps_admission_domain[] = "TPSADMIT1";
static const uint8_t tps_opening_check_domain[] = "TPSCHK01";
static const uint8_t tps_opening_packet_domain[] = "TPS2-CHECK-v1";
static const uint8_t tps_bridge_session_domain[] = "TPSBRG01";
static const char tps_noise_psk_context[crypto_kdf_CONTEXTBYTES] = {
    'T', 'P', 'S', 'N', 'P', 'S', 'K', '1'
};
static const char tps_admission_key_context[crypto_kdf_CONTEXTBYTES] = {
    'T', 'P', 'S', 'A', 'D', 'M', 'K', '1'
};
static const char tps_key_context[crypto_kdf_CONTEXTBYTES] = {
    'T', 'P', 'S', 'D', 'K', 'E', 'Y', '1'
};
static const char tps_nonce_context[crypto_kdf_CONTEXTBYTES] = {
    'T', 'P', 'S', 'D', 'N', 'O', 'N', '1'
};
static const char tps_response_root_context[crypto_kdf_CONTEXTBYTES] = {
    'T', 'P', 'S', 'R', 'S', 'P', 'K', '1'
};
static const char tps_opening_root_context[crypto_kdf_CONTEXTBYTES] = {
    'T', 'P', 'S', 'C', 'H', 'K', 'K', '1'
};
static const char tps_bridge_root_context[crypto_kdf_CONTEXTBYTES] = {
    'T', 'P', 'S', 'B', 'R', 'G', 'K', '1'
};
static const char tps_bridge_key_context[crypto_kdf_CONTEXTBYTES] = {
    'T', 'P', 'S', 'B', 'G', 'K', 'Y', '1'
};
static const char tps_bridge_nonce_context[crypto_kdf_CONTEXTBYTES] = {
    'T', 'P', 'S', 'B', 'G', 'N', 'N', '1'
};

enum tps_phase {
    TPS_PHASE_INITIATOR_NEW = 1,
    TPS_PHASE_INITIATOR_WAIT_FLIGHT_2,
    TPS_PHASE_INITIATOR_WAIT_ACK,
    TPS_PHASE_RESPONDER_NEW,
    TPS_PHASE_RESPONDER_WAIT_FLIGHT_1,
    TPS_PHASE_RESPONDER_WAIT_FINISH,
    TPS_PHASE_READY,
    TPS_PHASE_FAILED
};

typedef struct tps_channel_state {
    uint8_t key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    uint8_t nonce_prefix[16];
    uint64_t next_sequence;
    uint64_t replay_highest;
    uint64_t replay_bitmap;
    uint8_t derived;
    uint8_t replay_started;
} tps_channel_state;

struct tps_crypto_state {
    NoiseHandshakeState *handshake;
    NoiseCipherState *finish_send;
    NoiseCipherState *finish_receive;
    uint8_t initiator_contribution[32];
    uint8_t responder_contribution[32];
    uint8_t handshake_hash[32];
    uint8_t root[crypto_kdf_KEYBYTES];
    tps_channel_state send_channels[256];
    tps_channel_state receive_channels[256];
    uint32_t role;
    uint8_t phase;
    uint8_t root_ready;
};

struct tps_crypto_opening_state {
    uint8_t check_key[crypto_kdf_KEYBYTES];
    uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES];
    uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES];
    uint8_t local_challenge[TPS_CRYPTO_OPENING_CHALLENGE_BYTES];
    uint8_t peer_challenge[TPS_CRYPTO_OPENING_CHALLENGE_BYTES];
    uint64_t next_counter;
    uint64_t replay_bitmap;
    uint32_t replay_highest;
    uint32_t provisional_counter;
    uint32_t role;
    uint8_t peer_challenge_set;
    uint8_t peer_challenge_pinned;
    uint8_t replay_started;
    uint8_t local_verified;
    uint8_t peer_verified;
    uint8_t ready;
};

struct tps_crypto_bridge_state {
    uint8_t send_key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    uint8_t receive_key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES];
    uint8_t send_nonce_prefix[16];
    uint8_t receive_nonce_prefix[16];
    uint64_t next_sequence;
    uint64_t replay_highest;
    uint64_t replay_bitmap;
    uint32_t role;
    uint8_t replay_started;
};

static void tps_store_be32(uint8_t out[4], uint32_t value)
{
    out[0] = (uint8_t) (value >> 24);
    out[1] = (uint8_t) (value >> 16);
    out[2] = (uint8_t) (value >> 8);
    out[3] = (uint8_t) value;
}

static uint32_t tps_load_be32(const uint8_t input[4])
{
    return ((uint32_t) input[0] << 24) |
           ((uint32_t) input[1] << 16) |
           ((uint32_t) input[2] << 8) |
           (uint32_t) input[3];
}

static void tps_store_be64(uint8_t out[8], uint64_t value)
{
    size_t index;
    for (index = 0; index < 8; ++index) {
        out[7 - index] = (uint8_t) value;
        value >>= 8;
    }
}

static uint64_t tps_load_be64(const uint8_t input[8])
{
    uint64_t value = 0;
    size_t index;
    for (index = 0; index < 8; ++index)
        value = (value << 8) | input[index];
    return value;
}

static int32_t tps_noise_error(int error)
{
    if (error == NOISE_ERROR_NONE)
        return TPS_CRYPTO_OK;
    if (error == NOISE_ERROR_MAC_FAILURE ||
            error == NOISE_ERROR_INVALID_PUBLIC_KEY)
        return TPS_CRYPTO_ERR_AUTH;
    if (error == NOISE_ERROR_INVALID_STATE)
        return TPS_CRYPTO_ERR_STATE;
    if (error == NOISE_ERROR_INVALID_PARAM)
        return TPS_CRYPTO_ERR_ARGUMENT;
    if (error == NOISE_ERROR_INVALID_LENGTH)
        return TPS_CRYPTO_ERR_PROTOCOL;
    if (error == NOISE_ERROR_INVALID_NONCE)
        return TPS_CRYPTO_ERR_EXHAUSTED;
    return TPS_CRYPTO_ERR_INTERNAL;
}

static void tps_free_noise(tps_crypto_state *state)
{
    if (state->finish_send) {
        noise_cipherstate_free(state->finish_send);
        state->finish_send = NULL;
    }
    if (state->finish_receive) {
        noise_cipherstate_free(state->finish_receive);
        state->finish_receive = NULL;
    }
    if (state->handshake) {
        noise_handshakestate_free(state->handshake);
        state->handshake = NULL;
    }
}

static int32_t tps_fail(tps_crypto_state *state, int32_t error)
{
    if (state) {
        tps_free_noise(state);
        sodium_memzero(state->initiator_contribution,
                       sizeof state->initiator_contribution);
        sodium_memzero(state->responder_contribution,
                       sizeof state->responder_contribution);
        sodium_memzero(state->handshake_hash, sizeof state->handshake_hash);
        sodium_memzero(state->root, sizeof state->root);
        state->root_ready = 0;
        state->phase = TPS_PHASE_FAILED;
    }
    return error;
}

static void tps_mark_ready(tps_crypto_state *state)
{
    tps_free_noise(state);
    sodium_memzero(state->initiator_contribution,
                   sizeof state->initiator_contribution);
    sodium_memzero(state->responder_contribution,
                   sizeof state->responder_contribution);
    sodium_memzero(state->handshake_hash, sizeof state->handshake_hash);
    state->phase = TPS_PHASE_READY;
}

static int32_t tps_derive_noise_psk(
    uint8_t out[TPS_CRYPTO_KEY_BYTES],
    const uint8_t key[TPS_CRYPTO_KEY_BYTES])
{
    if (crypto_kdf_derive_from_key(
            out, TPS_CRYPTO_KEY_BYTES, 0,
            tps_noise_psk_context, key) != 0) {
        sodium_memzero(out, TPS_CRYPTO_KEY_BYTES);
        return TPS_CRYPTO_ERR_INTERNAL;
    }
    return TPS_CRYPTO_OK;
}

static int32_t tps_create_noise(
    NoiseHandshakeState **out,
    uint32_t role,
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t *fixed_ephemeral_private)
{
    NoiseHandshakeState *handshake = NULL;
    NoiseDHState *fixed_ephemeral = NULL;
    uint8_t noise_psk[TPS_CRYPTO_KEY_BYTES] = {0};
    int noise_role = role == TPS_CRYPTO_ROLE_INITIATOR
        ? NOISE_ROLE_INITIATOR : NOISE_ROLE_RESPONDER;
    int error;
    int32_t result;

    result = tps_derive_noise_psk(noise_psk, key);
    if (result != TPS_CRYPTO_OK)
        return result;
    error = noise_handshakestate_new_by_name(
        &handshake, TPS_NOISE_PROTOCOL, noise_role);
    if (error != NOISE_ERROR_NONE) {
        sodium_memzero(noise_psk, sizeof noise_psk);
        return tps_noise_error(error);
    }
    error = noise_handshakestate_set_pre_shared_key(
        handshake, noise_psk, sizeof noise_psk);
    sodium_memzero(noise_psk, sizeof noise_psk);
    if (error == NOISE_ERROR_NONE) {
        error = noise_handshakestate_set_prologue(
            handshake, tps_prologue, sizeof tps_prologue - 1u);
    }
    if (error == NOISE_ERROR_NONE && fixed_ephemeral_private) {
        fixed_ephemeral =
            noise_handshakestate_get_fixed_ephemeral_dh(handshake);
        if (!fixed_ephemeral)
            error = NOISE_ERROR_NO_MEMORY;
    }
    if (error == NOISE_ERROR_NONE && fixed_ephemeral_private) {
        error = noise_dhstate_set_keypair_private(
            fixed_ephemeral, fixed_ephemeral_private,
            TPS_CRYPTO_KEY_BYTES);
    }
    if (error == NOISE_ERROR_NONE)
        error = noise_handshakestate_start(handshake);
    if (error != NOISE_ERROR_NONE) {
        noise_handshakestate_free(handshake);
        return tps_noise_error(error);
    }
    *out = handshake;
    return TPS_CRYPTO_OK;
}

static int32_t tps_read_noise_payload(
    tps_crypto_state *state,
    const uint8_t *input,
    size_t input_len,
    uint8_t payload_out[32])
{
    uint8_t message_bytes[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    NoiseBuffer message;
    NoiseBuffer payload;
    int error;

    if (input_len > sizeof message_bytes)
        return TPS_CRYPTO_ERR_PROTOCOL;
    memcpy(message_bytes, input, input_len);
    noise_buffer_set_input(message, message_bytes, input_len);
    noise_buffer_set_output(payload, payload_out, 32);
    error = noise_handshakestate_read_message(
        state->handshake, &message, &payload);
    sodium_memzero(message_bytes, sizeof message_bytes);
    if (error != NOISE_ERROR_NONE)
        return tps_noise_error(error);
    if (payload.size != 32)
        return TPS_CRYPTO_ERR_PROTOCOL;
    return TPS_CRYPTO_OK;
}

static int32_t tps_write_noise_payload(
    tps_crypto_state *state,
    const uint8_t payload_bytes[32],
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    NoiseBuffer message;
    NoiseBuffer payload;
    int error;

    noise_buffer_set_output(message, out, out_capacity);
    noise_buffer_set_input(payload, (uint8_t *) payload_bytes, 32);
    error = noise_handshakestate_write_message(
        state->handshake, &message, &payload);
    if (error != NOISE_ERROR_NONE)
        return tps_noise_error(error);
    if (message.size != TPS_HANDSHAKE_FLIGHT_BYTES)
        return TPS_CRYPTO_ERR_PROTOCOL;
    *out_len = message.size;
    return TPS_CRYPTO_OK;
}

static int32_t tps_finish_noise_handshake(tps_crypto_state *state)
{
    uint8_t root_input[sizeof tps_root_domain - 1u + 32u + 32u];
    int error;

    error = noise_handshakestate_get_handshake_hash(
        state->handshake, state->handshake_hash,
        sizeof state->handshake_hash);
    if (error != NOISE_ERROR_NONE)
        return tps_noise_error(error);

    error = noise_handshakestate_split(
        state->handshake, &state->finish_send, &state->finish_receive);
    if (error != NOISE_ERROR_NONE)
        return tps_noise_error(error);

    memcpy(root_input, tps_root_domain, sizeof tps_root_domain - 1u);
    memcpy(root_input + sizeof tps_root_domain - 1u,
           state->handshake_hash, 32);
    memcpy(root_input + sizeof tps_root_domain - 1u + 32u,
           state->responder_contribution, 32);
    if (crypto_generichash(
            state->root, sizeof state->root,
            root_input, sizeof root_input,
            state->initiator_contribution,
            sizeof state->initiator_contribution) != 0) {
        sodium_memzero(root_input, sizeof root_input);
        return TPS_CRYPTO_ERR_INTERNAL;
    }
    sodium_memzero(root_input, sizeof root_input);
    state->root_ready = 1;
    return TPS_CRYPTO_OK;
}

static int32_t tps_derive_channel(
    tps_crypto_state *state,
    tps_channel_state *channel_state,
    uint8_t direction,
    uint8_t channel)
{
    uint64_t subkey_id;
    if (channel_state->derived)
        return TPS_CRYPTO_OK;
    if (!state->root_ready)
        return TPS_CRYPTO_ERR_STATE;
    subkey_id = ((uint64_t) direction << 8) | channel;
    if (crypto_kdf_derive_from_key(
            channel_state->key, sizeof channel_state->key,
            subkey_id, tps_key_context, state->root) != 0 ||
        crypto_kdf_derive_from_key(
            channel_state->nonce_prefix,
            sizeof channel_state->nonce_prefix,
            subkey_id, tps_nonce_context, state->root) != 0) {
        sodium_memzero(channel_state, sizeof *channel_state);
        return TPS_CRYPTO_ERR_INTERNAL;
    }
    channel_state->derived = 1;
    return TPS_CRYPTO_OK;
}

static int tps_replay_allowed(const tps_channel_state *channel, uint64_t sequence)
{
    uint64_t difference;
    if (!channel->replay_started || sequence > channel->replay_highest)
        return 1;
    difference = channel->replay_highest - sequence;
    if (difference >= TPS_REPLAY_WINDOW_BITS)
        return 0;
    return (channel->replay_bitmap & (UINT64_C(1) << difference)) == 0;
}

static void tps_replay_commit(tps_channel_state *channel, uint64_t sequence)
{
    uint64_t difference;
    if (!channel->replay_started) {
        channel->replay_started = 1;
        channel->replay_highest = sequence;
        channel->replay_bitmap = UINT64_C(1);
    } else if (sequence > channel->replay_highest) {
        difference = sequence - channel->replay_highest;
        channel->replay_bitmap = difference >= TPS_REPLAY_WINDOW_BITS
            ? UINT64_C(1)
            : (channel->replay_bitmap << difference) | UINT64_C(1);
        channel->replay_highest = sequence;
    } else {
        difference = channel->replay_highest - sequence;
        channel->replay_bitmap |= UINT64_C(1) << difference;
    }
}

TPS_CRYPTO_API uint32_t tps_crypto_abi_version(void)
{
    return TPS_CRYPTO_ABI_VERSION;
}

TPS_CRYPTO_API const char *tps_crypto_suite(void)
{
    return TPS_SUITE;
}

TPS_CRYPTO_API int32_t tps_crypto_init(void)
{
    if (sodium_init() < 0)
        return TPS_CRYPTO_ERR_INTERNAL;
    if (noise_init() != NOISE_ERROR_NONE)
        return TPS_CRYPTO_ERR_INTERNAL;
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_random(uint8_t *out, size_t out_len)
{
    if ((!out && out_len) || tps_crypto_init() != TPS_CRYPTO_OK)
        return !out && out_len ? TPS_CRYPTO_ERR_ARGUMENT
                               : TPS_CRYPTO_ERR_INTERNAL;
    if (out_len)
        randombytes_buf(out, out_len);
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_admission_token(
    const uint8_t key[TPS_CRYPTO_KEY_BYTES], uint32_t *out_token)
{
    uint8_t admission_key[crypto_kdf_KEYBYTES] = {0};
    uint8_t tag[crypto_generichash_BYTES_MIN] = {0};
    if (!key || !out_token)
        return TPS_CRYPTO_ERR_ARGUMENT;
    if (tps_crypto_init() != TPS_CRYPTO_OK)
        return TPS_CRYPTO_ERR_INTERNAL;
    if (crypto_kdf_derive_from_key(
            admission_key, sizeof admission_key, 0,
            tps_admission_key_context, key) != 0) {
        sodium_memzero(admission_key, sizeof admission_key);
        sodium_memzero(tag, sizeof tag);
        return TPS_CRYPTO_ERR_INTERNAL;
    }
    if (crypto_generichash(tag, sizeof tag,
            tps_admission_domain, sizeof tps_admission_domain - 1u,
            admission_key, sizeof admission_key) != 0) {
        sodium_memzero(admission_key, sizeof admission_key);
        sodium_memzero(tag, sizeof tag);
        return TPS_CRYPTO_ERR_INTERNAL;
    }
    sodium_memzero(admission_key, sizeof admission_key);
    *out_token = ((uint32_t) (tag[0] & 0x7fu) << 24) |
                 ((uint32_t) tag[1] << 16) |
                 ((uint32_t) tag[2] << 8) |
                 (uint32_t) tag[3];
    sodium_memzero(tag, sizeof tag);
    return TPS_CRYPTO_OK;
}

static int32_t tps_response_tag_core(
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t transcript[TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES],
    uint8_t out_tag[TPS_CRYPTO_RESPONSE_TAG_BYTES])
{
    uint8_t root[crypto_kdf_KEYBYTES] = {0};
    int32_t result = TPS_CRYPTO_ERR_INTERNAL;

    if (crypto_kdf_derive_from_key(
            root, sizeof root, 0, tps_response_root_context, key) != 0)
        goto cleanup;
    if (crypto_generichash(
            out_tag, TPS_CRYPTO_RESPONSE_TAG_BYTES,
            transcript, TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES,
            root, sizeof root) != 0)
        goto cleanup;
    result = TPS_CRYPTO_OK;

cleanup:
    sodium_memzero(root, sizeof root);
    return result;
}

TPS_CRYPTO_API int32_t tps_crypto_response_tag(
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t transcript[TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES],
    uint8_t out_tag[TPS_CRYPTO_RESPONSE_TAG_BYTES])
{
    uint8_t tag[TPS_CRYPTO_RESPONSE_TAG_BYTES] = {0};
    int32_t result;

    if (!key || !transcript || !out_tag)
        return TPS_CRYPTO_ERR_ARGUMENT;
    if (tps_crypto_init() != TPS_CRYPTO_OK) {
        sodium_memzero(out_tag, TPS_CRYPTO_RESPONSE_TAG_BYTES);
        return TPS_CRYPTO_ERR_INTERNAL;
    }
    result = tps_response_tag_core(key, transcript, tag);
    if (result == TPS_CRYPTO_OK)
        memcpy(out_tag, tag, sizeof tag);
    else
        sodium_memzero(out_tag, TPS_CRYPTO_RESPONSE_TAG_BYTES);
    sodium_memzero(tag, sizeof tag);
    return result;
}

TPS_CRYPTO_API int32_t tps_crypto_response_verify(
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t transcript[TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES],
    const uint8_t tag[TPS_CRYPTO_RESPONSE_TAG_BYTES])
{
    uint8_t expected[TPS_CRYPTO_RESPONSE_TAG_BYTES] = {0};
    int32_t result;

    if (!key || !transcript || !tag)
        return TPS_CRYPTO_ERR_ARGUMENT;
    if (tps_crypto_init() != TPS_CRYPTO_OK)
        return TPS_CRYPTO_ERR_INTERNAL;
    result = tps_response_tag_core(key, transcript, expected);
    if (result == TPS_CRYPTO_OK &&
            sodium_memcmp(expected, tag, sizeof expected) != 0)
        result = TPS_CRYPTO_ERR_AUTH;
    sodium_memzero(expected, sizeof expected);
    return result;
}

static int32_t tps_opening_derive_check_key(
    uint8_t out_key[crypto_kdf_KEYBYTES],
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES],
    const uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES])
{
    uint8_t root[crypto_kdf_KEYBYTES] = {0};
    uint8_t input[(sizeof tps_opening_check_domain - 1u) +
                  TPS_CRYPTO_INVITATION_ID_BYTES +
                  TPS_CRYPTO_GUEST_NONCE_BYTES] = {0};
    int32_t result = TPS_CRYPTO_ERR_INTERNAL;

    if (crypto_kdf_derive_from_key(
            root, sizeof root, 0, tps_opening_root_context, key) != 0)
        goto cleanup;
    memcpy(input, tps_opening_check_domain,
           sizeof tps_opening_check_domain - 1u);
    memcpy(input + sizeof tps_opening_check_domain - 1u,
           invitation_id, TPS_CRYPTO_INVITATION_ID_BYTES);
    memcpy(input + sizeof tps_opening_check_domain - 1u +
           TPS_CRYPTO_INVITATION_ID_BYTES,
           guest_nonce, TPS_CRYPTO_GUEST_NONCE_BYTES);
    if (crypto_generichash(
            out_key, crypto_kdf_KEYBYTES,
            input, sizeof input, root, sizeof root) != 0)
        goto cleanup;
    result = TPS_CRYPTO_OK;

cleanup:
    sodium_memzero(root, sizeof root);
    sodium_memzero(input, sizeof input);
    return result;
}

static int32_t tps_opening_packet_tag(
    const uint8_t check_key[crypto_kdf_KEYBYTES],
    const uint8_t packet[TPS_CRYPTO_OPENING_PACKET_BYTES],
    uint8_t out_tag[TPS_CRYPTO_OPENING_TAG_BYTES])
{
    uint8_t input[(sizeof tps_opening_packet_domain - 1u) +
                  TPS_OPENING_TAG_OFFSET] = {0};
    int32_t result = TPS_CRYPTO_ERR_INTERNAL;

    memcpy(input, tps_opening_packet_domain,
           sizeof tps_opening_packet_domain - 1u);
    memcpy(input + sizeof tps_opening_packet_domain - 1u,
           packet, TPS_OPENING_TAG_OFFSET);
    if (crypto_generichash(
            out_tag, TPS_CRYPTO_OPENING_TAG_BYTES,
            input, sizeof input, check_key, crypto_kdf_KEYBYTES) == 0)
        result = TPS_CRYPTO_OK;
    sodium_memzero(input, sizeof input);
    return result;
}

static int tps_opening_replay_allowed(
    const tps_crypto_opening_state *state,
    uint32_t counter)
{
    uint32_t difference;

    if (!state->replay_started || counter > state->replay_highest)
        return 1;
    difference = state->replay_highest - counter;
    if (difference >= TPS_REPLAY_WINDOW_BITS)
        return 0;
    return (state->replay_bitmap & (UINT64_C(1) << difference)) == 0;
}

static void tps_opening_replay_commit(
    tps_crypto_opening_state *state,
    uint32_t counter)
{
    uint32_t difference;

    if (!state->replay_started) {
        state->replay_started = 1;
        state->replay_highest = counter;
        state->replay_bitmap = UINT64_C(1);
    } else if (counter > state->replay_highest) {
        difference = counter - state->replay_highest;
        state->replay_bitmap = difference >= TPS_REPLAY_WINDOW_BITS
            ? UINT64_C(1)
            : (state->replay_bitmap << difference) | UINT64_C(1);
        state->replay_highest = counter;
    } else {
        difference = state->replay_highest - counter;
        state->replay_bitmap |= UINT64_C(1) << difference;
    }
}

TPS_CRYPTO_API int32_t tps_crypto_opening_state_new(
    uint32_t role,
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES],
    const uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES],
    tps_crypto_opening_state **out_state)
{
    tps_crypto_opening_state *state;
    int32_t result;

    if (out_state)
        *out_state = NULL;
    if (!key || !invitation_id || !guest_nonce || !out_state ||
            (role != TPS_CRYPTO_OPENING_ROLE_HOST &&
             role != TPS_CRYPTO_OPENING_ROLE_GUEST))
        return TPS_CRYPTO_ERR_ARGUMENT;
    if (tps_crypto_init() != TPS_CRYPTO_OK)
        return TPS_CRYPTO_ERR_INTERNAL;
    state = (tps_crypto_opening_state *) calloc(1, sizeof *state);
    if (!state)
        return TPS_CRYPTO_ERR_INTERNAL;
    result = tps_opening_derive_check_key(
        state->check_key, key, invitation_id, guest_nonce);
    if (result != TPS_CRYPTO_OK) {
        tps_crypto_opening_state_free(state);
        return result;
    }
    memcpy(state->invitation_id, invitation_id,
           TPS_CRYPTO_INVITATION_ID_BYTES);
    memcpy(state->guest_nonce, guest_nonce, TPS_CRYPTO_GUEST_NONCE_BYTES);
    randombytes_buf(state->local_challenge,
                    TPS_CRYPTO_OPENING_CHALLENGE_BYTES);
    state->next_counter = UINT64_C(1);
    state->role = role;
    *out_state = state;
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_opening_state_next(
    tps_crypto_opening_state *state,
    uint8_t out_packet[TPS_CRYPTO_OPENING_PACKET_BYTES])
{
    uint8_t tag[TPS_CRYPTO_OPENING_TAG_BYTES] = {0};
    uint8_t flags = 0;
    int32_t result;

    if (!state || !out_packet)
        return TPS_CRYPTO_ERR_ARGUMENT;
    sodium_memzero(out_packet, TPS_CRYPTO_OPENING_PACKET_BYTES);
    if (state->next_counter > UINT32_MAX)
        return TPS_CRYPTO_ERR_EXHAUSTED;
    if (state->peer_challenge_set)
        flags |= TPS_OPENING_FLAG_ECHO_PRESENT;
    if (state->local_verified)
        flags |= TPS_OPENING_FLAG_LOCAL_VERIFIED;

    memcpy(out_packet + TPS_OPENING_MAGIC_OFFSET, "TPSO", 4u);
    out_packet[TPS_OPENING_VERSION_OFFSET] = 1u;
    out_packet[TPS_OPENING_TYPE_OFFSET] = 1u;
    out_packet[TPS_OPENING_ROLE_OFFSET] = (uint8_t) state->role;
    out_packet[TPS_OPENING_FLAGS_OFFSET] = flags;
    memcpy(out_packet + TPS_OPENING_INVITATION_ID_OFFSET,
           state->invitation_id, TPS_CRYPTO_INVITATION_ID_BYTES);
    memcpy(out_packet + TPS_OPENING_GUEST_NONCE_OFFSET,
           state->guest_nonce, TPS_CRYPTO_GUEST_NONCE_BYTES);
    memcpy(out_packet + TPS_OPENING_CHALLENGE_OFFSET,
           state->local_challenge, TPS_CRYPTO_OPENING_CHALLENGE_BYTES);
    if (state->peer_challenge_set) {
        memcpy(out_packet + TPS_OPENING_ECHO_OFFSET,
               state->peer_challenge,
               TPS_CRYPTO_OPENING_CHALLENGE_BYTES);
    }
    tps_store_be32(out_packet + TPS_OPENING_COUNTER_OFFSET,
                   (uint32_t) state->next_counter);
    result = tps_opening_packet_tag(state->check_key, out_packet, tag);
    if (result != TPS_CRYPTO_OK) {
        sodium_memzero(out_packet, TPS_CRYPTO_OPENING_PACKET_BYTES);
        sodium_memzero(tag, sizeof tag);
        return result;
    }
    memcpy(out_packet + TPS_OPENING_TAG_OFFSET, tag, sizeof tag);
    ++state->next_counter;
    sodium_memzero(tag, sizeof tag);
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_opening_state_receive(
    tps_crypto_opening_state *state,
    const uint8_t *input,
    size_t input_len)
{
    uint8_t expected_tag[TPS_CRYPTO_OPENING_TAG_BYTES] = {0};
    uint8_t expected_role;
    uint8_t flags;
    uint32_t counter;
    int echo_present;
    int32_t result;

    if (!state || !input)
        return TPS_CRYPTO_ERR_ARGUMENT;
    if (input_len != TPS_CRYPTO_OPENING_PACKET_BYTES)
        return TPS_CRYPTO_ERR_PROTOCOL;
    expected_role = state->role == TPS_CRYPTO_OPENING_ROLE_HOST
        ? TPS_CRYPTO_OPENING_ROLE_GUEST : TPS_CRYPTO_OPENING_ROLE_HOST;
    flags = input[TPS_OPENING_FLAGS_OFFSET];
    counter = tps_load_be32(input + TPS_OPENING_COUNTER_OFFSET);
    if (memcmp(input + TPS_OPENING_MAGIC_OFFSET, "TPSO", 4u) != 0 ||
            input[TPS_OPENING_VERSION_OFFSET] != 1u ||
            input[TPS_OPENING_TYPE_OFFSET] != 1u ||
            input[TPS_OPENING_ROLE_OFFSET] != expected_role ||
            (flags & ~(TPS_OPENING_FLAG_ECHO_PRESENT |
                       TPS_OPENING_FLAG_LOCAL_VERIFIED)) != 0 ||
            ((flags & TPS_OPENING_FLAG_LOCAL_VERIFIED) != 0 &&
             (flags & TPS_OPENING_FLAG_ECHO_PRESENT) == 0) ||
            sodium_memcmp(
                input + TPS_OPENING_INVITATION_ID_OFFSET,
                state->invitation_id,
                TPS_CRYPTO_INVITATION_ID_BYTES) != 0 ||
            sodium_memcmp(
                input + TPS_OPENING_GUEST_NONCE_OFFSET,
                state->guest_nonce,
                TPS_CRYPTO_GUEST_NONCE_BYTES) != 0 ||
            counter == 0 ||
            ((flags & TPS_OPENING_FLAG_ECHO_PRESENT) == 0 &&
             !sodium_is_zero(
                 input + TPS_OPENING_ECHO_OFFSET,
                 TPS_CRYPTO_OPENING_CHALLENGE_BYTES)))
        return TPS_CRYPTO_ERR_PROTOCOL;

    result = tps_opening_packet_tag(state->check_key, input, expected_tag);
    if (result != TPS_CRYPTO_OK)
        goto cleanup;
    if (sodium_memcmp(
            expected_tag, input + TPS_OPENING_TAG_OFFSET,
            TPS_CRYPTO_OPENING_TAG_BYTES) != 0) {
        result = TPS_CRYPTO_ERR_AUTH;
        goto cleanup;
    }
    echo_present = (flags & TPS_OPENING_FLAG_ECHO_PRESENT) != 0;
    if (echo_present &&
            sodium_memcmp(
                input + TPS_OPENING_ECHO_OFFSET,
                state->local_challenge,
                TPS_CRYPTO_OPENING_CHALLENGE_BYTES) != 0) {
        result = TPS_CRYPTO_ERR_PROTOCOL;
        goto cleanup;
    }

    /*
     * A no-echo packet proves possession of the invitation key, but not
     * freshness for this state instance.  Keep its challenge only as a
     * replaceable candidate so a captured packet from a destroyed state
     * cannot permanently pin the receiver or consume its counter window.
     * Exact candidate duplicates are suppressed locally, while a different
     * challenge at the same counter may replace the stale candidate.
     * The candidate becomes permanent only when the peer authenticates an
     * exact echo of this state's fresh local challenge.
     */
    if (!state->peer_challenge_pinned && !echo_present) {
        if (state->peer_challenge_set &&
                state->provisional_counter == counter &&
                sodium_memcmp(
                    state->peer_challenge,
                    input + TPS_OPENING_CHALLENGE_OFFSET,
                    TPS_CRYPTO_OPENING_CHALLENGE_BYTES) == 0) {
            result = TPS_CRYPTO_ERR_REPLAY;
            goto cleanup;
        }
        memcpy(state->peer_challenge,
               input + TPS_OPENING_CHALLENGE_OFFSET,
               TPS_CRYPTO_OPENING_CHALLENGE_BYTES);
        state->provisional_counter = counter;
        state->peer_challenge_set = 1;
        result = TPS_CRYPTO_OK;
        goto cleanup;
    }

    if (state->peer_challenge_pinned && sodium_memcmp(
            state->peer_challenge,
            input + TPS_OPENING_CHALLENGE_OFFSET,
            TPS_CRYPTO_OPENING_CHALLENGE_BYTES) != 0) {
        result = TPS_CRYPTO_ERR_PROTOCOL;
        goto cleanup;
    }
    if (!tps_opening_replay_allowed(state, counter)) {
        result = TPS_CRYPTO_ERR_REPLAY;
        goto cleanup;
    }

    if (!state->peer_challenge_pinned) {
        memcpy(state->peer_challenge,
               input + TPS_OPENING_CHALLENGE_OFFSET,
               TPS_CRYPTO_OPENING_CHALLENGE_BYTES);
        state->peer_challenge_set = 1;
        state->peer_challenge_pinned = 1;
        state->provisional_counter = 0;
    }
    tps_opening_replay_commit(state, counter);
    if (echo_present)
        state->local_verified = 1;
    if ((flags & TPS_OPENING_FLAG_LOCAL_VERIFIED) != 0)
        state->peer_verified = 1;
    state->ready = state->local_verified && state->peer_verified;
    result = TPS_CRYPTO_OK;

cleanup:
    sodium_memzero(expected_tag, sizeof expected_tag);
    return result;
}

TPS_CRYPTO_API int32_t tps_crypto_opening_state_is_ready(
    const tps_crypto_opening_state *state)
{
    if (!state)
        return TPS_CRYPTO_ERR_ARGUMENT;
    return state->ready ? 1 : 0;
}

TPS_CRYPTO_API void tps_crypto_opening_state_free(
    tps_crypto_opening_state *state)
{
    if (!state)
        return;
    sodium_memzero(state, sizeof *state);
    free(state);
}

static int32_t tps_bridge_derive_session_root(
    uint8_t out_root[crypto_kdf_KEYBYTES],
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES],
    const uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES])
{
    uint8_t root[crypto_kdf_KEYBYTES] = {0};
    uint8_t input[(sizeof tps_bridge_session_domain - 1u) +
                  TPS_CRYPTO_INVITATION_ID_BYTES +
                  TPS_CRYPTO_GUEST_NONCE_BYTES] = {0};
    int32_t result = TPS_CRYPTO_ERR_INTERNAL;

    if (crypto_kdf_derive_from_key(
            root, sizeof root, 0, tps_bridge_root_context, key) != 0)
        goto cleanup;
    memcpy(input, tps_bridge_session_domain,
           sizeof tps_bridge_session_domain - 1u);
    memcpy(input + sizeof tps_bridge_session_domain - 1u,
           invitation_id, TPS_CRYPTO_INVITATION_ID_BYTES);
    memcpy(input + sizeof tps_bridge_session_domain - 1u +
           TPS_CRYPTO_INVITATION_ID_BYTES,
           guest_nonce, TPS_CRYPTO_GUEST_NONCE_BYTES);
    if (crypto_generichash(
            out_root, crypto_kdf_KEYBYTES,
            input, sizeof input, root, sizeof root) != 0)
        goto cleanup;
    result = TPS_CRYPTO_OK;

cleanup:
    sodium_memzero(root, sizeof root);
    sodium_memzero(input, sizeof input);
    return result;
}

static int32_t tps_bridge_derive_direction(
    uint8_t out_key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES],
    uint8_t out_nonce_prefix[16],
    const uint8_t root[crypto_kdf_KEYBYTES],
    uint64_t direction)
{
    if (crypto_kdf_derive_from_key(
            out_key, crypto_aead_xchacha20poly1305_ietf_KEYBYTES,
            direction, tps_bridge_key_context, root) != 0 ||
        crypto_kdf_derive_from_key(
            out_nonce_prefix, 16u,
            direction, tps_bridge_nonce_context, root) != 0) {
        sodium_memzero(
            out_key, crypto_aead_xchacha20poly1305_ietf_KEYBYTES);
        sodium_memzero(out_nonce_prefix, 16u);
        return TPS_CRYPTO_ERR_INTERNAL;
    }
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_bridge_state_new(
    uint32_t role,
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES],
    const uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES],
    tps_crypto_bridge_state **out_state)
{
    tps_crypto_bridge_state *state = NULL;
    uint8_t root[crypto_kdf_KEYBYTES] = {0};
    uint8_t direction_0_key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES] = {0};
    uint8_t direction_1_key[crypto_aead_xchacha20poly1305_ietf_KEYBYTES] = {0};
    uint8_t direction_0_nonce[16] = {0};
    uint8_t direction_1_nonce[16] = {0};
    int32_t result = TPS_CRYPTO_ERR_INTERNAL;

    if (out_state)
        *out_state = NULL;
    if (!key || !invitation_id || !guest_nonce || !out_state ||
            (role != TPS_CRYPTO_BRIDGE_ROLE_HOST &&
             role != TPS_CRYPTO_BRIDGE_ROLE_GUEST))
        return TPS_CRYPTO_ERR_ARGUMENT;
    if (tps_crypto_init() != TPS_CRYPTO_OK)
        return TPS_CRYPTO_ERR_INTERNAL;
    state = (tps_crypto_bridge_state *) calloc(1, sizeof *state);
    if (!state)
        return TPS_CRYPTO_ERR_INTERNAL;
    result = tps_bridge_derive_session_root(
        root, key, invitation_id, guest_nonce);
    if (result != TPS_CRYPTO_OK)
        goto cleanup;
    result = tps_bridge_derive_direction(
        direction_0_key, direction_0_nonce, root, UINT64_C(0));
    if (result != TPS_CRYPTO_OK)
        goto cleanup;
    result = tps_bridge_derive_direction(
        direction_1_key, direction_1_nonce, root, UINT64_C(1));
    if (result != TPS_CRYPTO_OK)
        goto cleanup;

    if (role == TPS_CRYPTO_BRIDGE_ROLE_GUEST) {
        memcpy(state->send_key, direction_0_key, sizeof state->send_key);
        memcpy(state->send_nonce_prefix,
               direction_0_nonce, sizeof state->send_nonce_prefix);
        memcpy(state->receive_key,
               direction_1_key, sizeof state->receive_key);
        memcpy(state->receive_nonce_prefix,
               direction_1_nonce, sizeof state->receive_nonce_prefix);
    } else {
        memcpy(state->send_key, direction_1_key, sizeof state->send_key);
        memcpy(state->send_nonce_prefix,
               direction_1_nonce, sizeof state->send_nonce_prefix);
        memcpy(state->receive_key,
               direction_0_key, sizeof state->receive_key);
        memcpy(state->receive_nonce_prefix,
               direction_0_nonce, sizeof state->receive_nonce_prefix);
    }
    state->role = role;
    *out_state = state;
    state = NULL;
    result = TPS_CRYPTO_OK;

cleanup:
    tps_crypto_bridge_state_free(state);
    sodium_memzero(root, sizeof root);
    sodium_memzero(direction_0_key, sizeof direction_0_key);
    sodium_memzero(direction_1_key, sizeof direction_1_key);
    sodium_memzero(direction_0_nonce, sizeof direction_0_nonce);
    sodium_memzero(direction_1_nonce, sizeof direction_1_nonce);
    return result;
}

static int tps_bridge_replay_allowed(
    const tps_crypto_bridge_state *state,
    uint64_t sequence)
{
    uint64_t difference;

    if (!state->replay_started || sequence > state->replay_highest)
        return 1;
    difference = state->replay_highest - sequence;
    if (difference >= TPS_REPLAY_WINDOW_BITS)
        return 0;
    return (state->replay_bitmap & (UINT64_C(1) << difference)) == 0;
}

static void tps_bridge_replay_commit(
    tps_crypto_bridge_state *state,
    uint64_t sequence)
{
    uint64_t difference;

    if (!state->replay_started) {
        state->replay_started = 1;
        state->replay_highest = sequence;
        state->replay_bitmap = UINT64_C(1);
    } else if (sequence > state->replay_highest) {
        difference = sequence - state->replay_highest;
        state->replay_bitmap = difference >= TPS_REPLAY_WINDOW_BITS
            ? UINT64_C(1)
            : (state->replay_bitmap << difference) | UINT64_C(1);
        state->replay_highest = sequence;
    } else {
        difference = state->replay_highest - sequence;
        state->replay_bitmap |= UINT64_C(1) << difference;
    }
}

TPS_CRYPTO_API int32_t tps_crypto_bridge_state_seal(
    tps_crypto_bridge_state *state,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *plaintext,
    size_t plaintext_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    uint8_t nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES] = {0};
    uint8_t full_aad[TPS_CRYPTO_BRIDGE_MAX_AAD_BYTES + 8u] = {0};
    uint64_t sequence;
    unsigned long long ciphertext_len = 0;

    if (!state || !out_len || (!aad && aad_len) ||
            (!plaintext && plaintext_len) || !out)
        return TPS_CRYPTO_ERR_ARGUMENT;
    *out_len = 0;
    if (aad_len > TPS_CRYPTO_BRIDGE_MAX_AAD_BYTES ||
            plaintext_len > TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES ||
            out_capacity < plaintext_len + TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES)
        return TPS_CRYPTO_ERR_BUFFER;
    sequence = state->next_sequence;
    if (sequence == UINT64_MAX)
        return TPS_CRYPTO_ERR_EXHAUSTED;

    tps_store_be64(out, sequence);
    memcpy(nonce, state->send_nonce_prefix, 16u);
    memcpy(nonce + 16u, out, 8u);
    if (aad_len)
        memcpy(full_aad, aad, aad_len);
    memcpy(full_aad + aad_len, out, 8u);
    if (crypto_aead_xchacha20poly1305_ietf_encrypt(
            out + 8u, &ciphertext_len,
            plaintext, (unsigned long long) plaintext_len,
            full_aad, (unsigned long long) (aad_len + 8u),
            NULL, nonce, state->send_key) != 0 ||
            ciphertext_len != plaintext_len +
                crypto_aead_xchacha20poly1305_ietf_ABYTES) {
        sodium_memzero(nonce, sizeof nonce);
        sodium_memzero(full_aad, sizeof full_aad);
        sodium_memzero(out, out_capacity);
        return TPS_CRYPTO_ERR_INTERNAL;
    }
    ++state->next_sequence;
    *out_len = (size_t) ciphertext_len + 8u;
    sodium_memzero(nonce, sizeof nonce);
    sodium_memzero(full_aad, sizeof full_aad);
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_bridge_state_open(
    tps_crypto_bridge_state *state,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    uint8_t nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES] = {0};
    uint8_t full_aad[TPS_CRYPTO_BRIDGE_MAX_AAD_BYTES + 8u] = {0};
    uint64_t sequence;
    size_t plaintext_capacity;
    unsigned long long plaintext_len = 0;

    if (!state || !out_len || (!aad && aad_len) || !ciphertext || !out)
        return TPS_CRYPTO_ERR_ARGUMENT;
    *out_len = 0;
    if (aad_len > TPS_CRYPTO_BRIDGE_MAX_AAD_BYTES ||
            ciphertext_len < TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES ||
            ciphertext_len > TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES +
                TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES)
        return TPS_CRYPTO_ERR_PROTOCOL;
    plaintext_capacity = ciphertext_len - TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES;
    if (out_capacity < plaintext_capacity)
        return TPS_CRYPTO_ERR_BUFFER;
    sequence = tps_load_be64(ciphertext);
    if (sequence == UINT64_MAX)
        return TPS_CRYPTO_ERR_EXHAUSTED;
    if (!tps_bridge_replay_allowed(state, sequence))
        return TPS_CRYPTO_ERR_REPLAY;

    memcpy(nonce, state->receive_nonce_prefix, 16u);
    memcpy(nonce + 16u, ciphertext, 8u);
    if (aad_len)
        memcpy(full_aad, aad, aad_len);
    memcpy(full_aad + aad_len, ciphertext, 8u);
    if (crypto_aead_xchacha20poly1305_ietf_decrypt(
            out, &plaintext_len, NULL,
            ciphertext + 8u,
            (unsigned long long) (ciphertext_len - 8u),
            full_aad, (unsigned long long) (aad_len + 8u),
            nonce, state->receive_key) != 0) {
        sodium_memzero(nonce, sizeof nonce);
        sodium_memzero(full_aad, sizeof full_aad);
        if (plaintext_capacity)
            sodium_memzero(out, plaintext_capacity);
        return TPS_CRYPTO_ERR_AUTH;
    }
    tps_bridge_replay_commit(state, sequence);
    *out_len = (size_t) plaintext_len;
    sodium_memzero(nonce, sizeof nonce);
    sodium_memzero(full_aad, sizeof full_aad);
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API void tps_crypto_bridge_state_free(
    tps_crypto_bridge_state *state)
{
    if (!state)
        return;
    sodium_memzero(state, sizeof *state);
    free(state);
}

static int32_t tps_state_new_core(
    uint32_t role,
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t *fixed_ephemeral_private,
    tps_crypto_state **out_state)
{
    tps_crypto_state *state;
    int32_t result;
    if (!key || !out_state ||
            (role != TPS_CRYPTO_ROLE_INITIATOR &&
             role != TPS_CRYPTO_ROLE_RESPONDER))
        return TPS_CRYPTO_ERR_ARGUMENT;
    *out_state = NULL;
    if (tps_crypto_init() != TPS_CRYPTO_OK)
        return TPS_CRYPTO_ERR_INTERNAL;
    state = (tps_crypto_state *) calloc(1, sizeof *state);
    if (!state)
        return TPS_CRYPTO_ERR_INTERNAL;
    state->role = role;
    state->phase = role == TPS_CRYPTO_ROLE_INITIATOR
        ? TPS_PHASE_INITIATOR_NEW : TPS_PHASE_RESPONDER_NEW;
    result = tps_create_noise(
        &state->handshake, role, key, fixed_ephemeral_private);
    if (result != TPS_CRYPTO_OK) {
        tps_crypto_state_free(state);
        return result;
    }
    *out_state = state;
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_state_new(
    uint32_t role,
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    tps_crypto_state **out_state)
{
    return tps_state_new_core(role, key, NULL, out_state);
}

static int32_t tps_initiator_start_core(
    tps_crypto_state *state,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len,
    const uint8_t contribution[32])
{
    int32_t result;
    memcpy(state->initiator_contribution, contribution,
           sizeof state->initiator_contribution);
    result = tps_write_noise_payload(
        state, state->initiator_contribution, out, out_capacity, out_len);
    if (result != TPS_CRYPTO_OK)
        return tps_fail(state, result);
    state->phase = TPS_PHASE_INITIATOR_WAIT_FLIGHT_2;
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_state_start(
    tps_crypto_state *state,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    uint8_t contribution[32] = {0};
    int32_t result;
    if (!state || !out_len)
        return TPS_CRYPTO_ERR_ARGUMENT;
    *out_len = 0;
    if (state->phase == TPS_PHASE_RESPONDER_NEW) {
        state->phase = TPS_PHASE_RESPONDER_WAIT_FLIGHT_1;
        return TPS_CRYPTO_OK;
    }
    if (state->phase != TPS_PHASE_INITIATOR_NEW)
        return TPS_CRYPTO_ERR_STATE;
    if (!out || out_capacity < TPS_HANDSHAKE_FLIGHT_BYTES)
        return TPS_CRYPTO_ERR_BUFFER;
    randombytes_buf(contribution, sizeof contribution);
    result = tps_initiator_start_core(
        state, out, out_capacity, out_len, contribution);
    sodium_memzero(contribution, sizeof contribution);
    return result;
}

static int32_t tps_initiator_flight_2(
    tps_crypto_state *state,
    const uint8_t *input,
    size_t input_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    uint8_t finish[TPS_FINISH_WIRE_BYTES];
    NoiseBuffer finish_buffer;
    int noise_error;
    int32_t result;

    if (input_len != TPS_HANDSHAKE_FLIGHT_BYTES)
        return tps_fail(state, TPS_CRYPTO_ERR_PROTOCOL);
    if (!out || out_capacity < TPS_FINISH_WIRE_BYTES)
        return TPS_CRYPTO_ERR_BUFFER;
    result = tps_read_noise_payload(
        state, input, input_len, state->responder_contribution);
    if (result != TPS_CRYPTO_OK)
        return tps_fail(state, result);
    result = tps_finish_noise_handshake(state);
    if (result != TPS_CRYPTO_OK)
        return tps_fail(state, result);

    memcpy(finish, tps_finish_domain, sizeof tps_finish_domain - 1u);
    memcpy(finish + sizeof tps_finish_domain - 1u,
           state->handshake_hash, sizeof state->handshake_hash);
    noise_buffer_set_inout(
        finish_buffer, finish, TPS_FINISH_PLAINTEXT_BYTES, sizeof finish);
    noise_error = noise_cipherstate_encrypt(state->finish_send, &finish_buffer);
    if (noise_error != NOISE_ERROR_NONE) {
        sodium_memzero(finish, sizeof finish);
        return tps_fail(state, tps_noise_error(noise_error));
    }
    if (finish_buffer.size != TPS_FINISH_WIRE_BYTES) {
        sodium_memzero(finish, sizeof finish);
        return tps_fail(state, TPS_CRYPTO_ERR_PROTOCOL);
    }
    memcpy(out, finish, finish_buffer.size);
    *out_len = finish_buffer.size;
    sodium_memzero(finish, sizeof finish);
    noise_cipherstate_free(state->finish_send);
    state->finish_send = NULL;
    noise_handshakestate_free(state->handshake);
    state->handshake = NULL;
    sodium_memzero(state->initiator_contribution,
                   sizeof state->initiator_contribution);
    sodium_memzero(state->responder_contribution,
                   sizeof state->responder_contribution);
    state->phase = TPS_PHASE_INITIATOR_WAIT_ACK;
    return TPS_CRYPTO_OK;
}

static int32_t tps_responder_flight_1_core(
    tps_crypto_state *state,
    const uint8_t *input,
    size_t input_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len,
    const uint8_t contribution[32])
{
    uint8_t generated_contribution[32] = {0};
    const uint8_t *selected_contribution = contribution;
    int32_t result;
    if (input_len != TPS_HANDSHAKE_FLIGHT_BYTES)
        return tps_fail(state, TPS_CRYPTO_ERR_PROTOCOL);
    if (!out || out_capacity < TPS_HANDSHAKE_FLIGHT_BYTES)
        return TPS_CRYPTO_ERR_BUFFER;
    result = tps_read_noise_payload(
        state, input, input_len, state->initiator_contribution);
    if (result != TPS_CRYPTO_OK)
        return tps_fail(state, result);
    if (!selected_contribution) {
        randombytes_buf(generated_contribution,
                        sizeof generated_contribution);
        selected_contribution = generated_contribution;
    }
    memcpy(state->responder_contribution, selected_contribution,
           sizeof state->responder_contribution);
    result = tps_write_noise_payload(
        state, state->responder_contribution, out, out_capacity, out_len);
    sodium_memzero(generated_contribution, sizeof generated_contribution);
    if (result != TPS_CRYPTO_OK)
        return tps_fail(state, result);
    result = tps_finish_noise_handshake(state);
    if (result != TPS_CRYPTO_OK) {
        *out_len = 0;
        return tps_fail(state, result);
    }
    noise_handshakestate_free(state->handshake);
    state->handshake = NULL;
    state->phase = TPS_PHASE_RESPONDER_WAIT_FINISH;
    return TPS_CRYPTO_OK;
}

static int32_t tps_responder_flight_1(
    tps_crypto_state *state,
    const uint8_t *input,
    size_t input_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    return tps_responder_flight_1_core(
        state, input, input_len, out, out_capacity, out_len, NULL);
}

static int32_t tps_responder_finish(
    tps_crypto_state *state,
    const uint8_t *input,
    size_t input_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    uint8_t finish[TPS_FINISH_WIRE_BYTES];
    uint8_t ack[TPS_ACK_WIRE_BYTES];
    NoiseBuffer finish_buffer;
    NoiseBuffer ack_buffer;
    int error;
    if (input_len != sizeof finish)
        return tps_fail(state, TPS_CRYPTO_ERR_PROTOCOL);
    if (!out || out_capacity < TPS_ACK_WIRE_BYTES)
        return TPS_CRYPTO_ERR_BUFFER;
    memcpy(finish, input, sizeof finish);
    noise_buffer_set_inout(finish_buffer, finish, sizeof finish, sizeof finish);
    error = noise_cipherstate_decrypt(state->finish_receive, &finish_buffer);
    if (error != NOISE_ERROR_NONE ||
            finish_buffer.size != TPS_FINISH_PLAINTEXT_BYTES ||
            sodium_memcmp(finish, tps_finish_domain,
                          sizeof tps_finish_domain - 1u) != 0 ||
            sodium_memcmp(finish + sizeof tps_finish_domain - 1u,
                          state->handshake_hash,
                          sizeof state->handshake_hash) != 0) {
        sodium_memzero(finish, sizeof finish);
        return tps_fail(state, error == NOISE_ERROR_NONE
            ? TPS_CRYPTO_ERR_AUTH : tps_noise_error(error));
    }
    sodium_memzero(finish, sizeof finish);

    memcpy(ack, tps_ack_domain, sizeof tps_ack_domain - 1u);
    memcpy(ack + sizeof tps_ack_domain - 1u,
           state->handshake_hash, sizeof state->handshake_hash);
    noise_buffer_set_inout(
        ack_buffer, ack, TPS_ACK_PLAINTEXT_BYTES, sizeof ack);
    error = noise_cipherstate_encrypt(state->finish_send, &ack_buffer);
    if (error != NOISE_ERROR_NONE) {
        sodium_memzero(ack, sizeof ack);
        return tps_fail(state, tps_noise_error(error));
    }
    if (ack_buffer.size != TPS_ACK_WIRE_BYTES) {
        sodium_memzero(ack, sizeof ack);
        return tps_fail(state, TPS_CRYPTO_ERR_PROTOCOL);
    }
    memcpy(out, ack, ack_buffer.size);
    *out_len = ack_buffer.size;
    sodium_memzero(ack, sizeof ack);
    tps_mark_ready(state);
    return TPS_CRYPTO_OK;
}

static int32_t tps_initiator_ack(
    tps_crypto_state *state,
    const uint8_t *input,
    size_t input_len)
{
    uint8_t ack[TPS_ACK_WIRE_BYTES];
    NoiseBuffer ack_buffer;
    int error;
    if (input_len != sizeof ack)
        return tps_fail(state, TPS_CRYPTO_ERR_PROTOCOL);
    memcpy(ack, input, sizeof ack);
    noise_buffer_set_inout(ack_buffer, ack, sizeof ack, sizeof ack);
    error = noise_cipherstate_decrypt(state->finish_receive, &ack_buffer);
    if (error != NOISE_ERROR_NONE ||
            ack_buffer.size != TPS_ACK_PLAINTEXT_BYTES ||
            sodium_memcmp(ack, tps_ack_domain,
                          sizeof tps_ack_domain - 1u) != 0 ||
            sodium_memcmp(ack + sizeof tps_ack_domain - 1u,
                          state->handshake_hash,
                          sizeof state->handshake_hash) != 0) {
        sodium_memzero(ack, sizeof ack);
        return tps_fail(state, error == NOISE_ERROR_NONE
            ? TPS_CRYPTO_ERR_AUTH : tps_noise_error(error));
    }
    sodium_memzero(ack, sizeof ack);
    tps_mark_ready(state);
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_state_handshake(
    tps_crypto_state *state,
    const uint8_t *input,
    size_t input_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    if (!state || !input || !input_len || !out_len)
        return TPS_CRYPTO_ERR_ARGUMENT;
    *out_len = 0;
    if (state->phase == TPS_PHASE_INITIATOR_WAIT_FLIGHT_2)
        return tps_initiator_flight_2(
            state, input, input_len, out, out_capacity, out_len);
    if (state->phase == TPS_PHASE_INITIATOR_WAIT_ACK)
        return tps_initiator_ack(state, input, input_len);
    if (state->phase == TPS_PHASE_RESPONDER_WAIT_FLIGHT_1)
        return tps_responder_flight_1(
            state, input, input_len, out, out_capacity, out_len);
    if (state->phase == TPS_PHASE_RESPONDER_WAIT_FINISH)
        return tps_responder_finish(
            state, input, input_len, out, out_capacity, out_len);
    return TPS_CRYPTO_ERR_STATE;
}

TPS_CRYPTO_API int32_t tps_crypto_state_is_ready(
    const tps_crypto_state *state)
{
    if (!state)
        return TPS_CRYPTO_ERR_ARGUMENT;
    return state->phase == TPS_PHASE_READY ? 1 : 0;
}

TPS_CRYPTO_API int32_t tps_crypto_state_seal(
    tps_crypto_state *state,
    uint8_t channel,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *plaintext,
    size_t plaintext_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    tps_channel_state *channel_state;
    uint8_t nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    uint8_t full_aad[TPS_CRYPTO_MAX_AAD_BYTES + 8u];
    uint8_t direction;
    uint64_t sequence;
    unsigned long long ciphertext_len = 0;
    int32_t result;

    if (!state || !out_len || (!aad && aad_len) ||
            (!plaintext && plaintext_len) || !out)
        return TPS_CRYPTO_ERR_ARGUMENT;
    *out_len = 0;
    if (state->phase != TPS_PHASE_READY)
        return TPS_CRYPTO_ERR_STATE;
    if (aad_len > TPS_CRYPTO_MAX_AAD_BYTES ||
            plaintext_len > crypto_aead_xchacha20poly1305_ietf_messagebytes_max() ||
            plaintext_len > SIZE_MAX - TPS_CRYPTO_DATA_OVERHEAD_BYTES ||
            out_capacity < plaintext_len + TPS_CRYPTO_DATA_OVERHEAD_BYTES)
        return TPS_CRYPTO_ERR_BUFFER;

    direction = state->role == TPS_CRYPTO_ROLE_INITIATOR ? 0u : 1u;
    channel_state = &state->send_channels[channel];
    result = tps_derive_channel(state, channel_state, direction, channel);
    if (result != TPS_CRYPTO_OK)
        return result;
    sequence = channel_state->next_sequence;
    if (sequence == UINT64_MAX)
        return TPS_CRYPTO_ERR_EXHAUSTED;

    tps_store_be64(out, sequence);
    memcpy(nonce, channel_state->nonce_prefix, 16);
    memcpy(nonce + 16, out, 8);
    if (aad_len)
        memcpy(full_aad, aad, aad_len);
    memcpy(full_aad + aad_len, out, 8);
    if (crypto_aead_xchacha20poly1305_ietf_encrypt(
            out + 8, &ciphertext_len,
            plaintext, (unsigned long long) plaintext_len,
            full_aad, (unsigned long long) (aad_len + 8u),
            NULL, nonce, channel_state->key) != 0 ||
            ciphertext_len != plaintext_len +
                crypto_aead_xchacha20poly1305_ietf_ABYTES) {
        sodium_memzero(nonce, sizeof nonce);
        sodium_memzero(full_aad, sizeof full_aad);
        return TPS_CRYPTO_ERR_INTERNAL;
    }
    ++channel_state->next_sequence;
    *out_len = (size_t) ciphertext_len + 8u;
    sodium_memzero(nonce, sizeof nonce);
    sodium_memzero(full_aad, sizeof full_aad);
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API int32_t tps_crypto_state_open(
    tps_crypto_state *state,
    uint8_t channel,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    tps_channel_state *channel_state;
    uint8_t nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    uint8_t full_aad[TPS_CRYPTO_MAX_AAD_BYTES + 8u];
    uint8_t direction;
    uint64_t sequence;
    size_t plaintext_capacity;
    unsigned long long plaintext_len = 0;
    int32_t result;

    if (!state || !out_len || (!aad && aad_len) || !ciphertext || !out)
        return TPS_CRYPTO_ERR_ARGUMENT;
    *out_len = 0;
    if (state->phase != TPS_PHASE_READY)
        return TPS_CRYPTO_ERR_STATE;
    if (aad_len > TPS_CRYPTO_MAX_AAD_BYTES ||
            ciphertext_len < TPS_CRYPTO_DATA_OVERHEAD_BYTES)
        return TPS_CRYPTO_ERR_PROTOCOL;
    plaintext_capacity = ciphertext_len - TPS_CRYPTO_DATA_OVERHEAD_BYTES;
    if (out_capacity < plaintext_capacity)
        return TPS_CRYPTO_ERR_BUFFER;

    direction = state->role == TPS_CRYPTO_ROLE_INITIATOR ? 1u : 0u;
    channel_state = &state->receive_channels[channel];
    result = tps_derive_channel(state, channel_state, direction, channel);
    if (result != TPS_CRYPTO_OK)
        return result;
    sequence = tps_load_be64(ciphertext);
    if (sequence == UINT64_MAX)
        return TPS_CRYPTO_ERR_EXHAUSTED;
    if (!tps_replay_allowed(channel_state, sequence))
        return TPS_CRYPTO_ERR_REPLAY;

    memcpy(nonce, channel_state->nonce_prefix, 16);
    memcpy(nonce + 16, ciphertext, 8);
    if (aad_len)
        memcpy(full_aad, aad, aad_len);
    memcpy(full_aad + aad_len, ciphertext, 8);
    if (crypto_aead_xchacha20poly1305_ietf_decrypt(
            out, &plaintext_len, NULL,
            ciphertext + 8,
            (unsigned long long) (ciphertext_len - 8u),
            full_aad, (unsigned long long) (aad_len + 8u),
            nonce, channel_state->key) != 0) {
        sodium_memzero(nonce, sizeof nonce);
        sodium_memzero(full_aad, sizeof full_aad);
        if (plaintext_capacity)
            sodium_memzero(out, plaintext_capacity);
        return TPS_CRYPTO_ERR_AUTH;
    }
    tps_replay_commit(channel_state, sequence);
    *out_len = (size_t) plaintext_len;
    sodium_memzero(nonce, sizeof nonce);
    sodium_memzero(full_aad, sizeof full_aad);
    return TPS_CRYPTO_OK;
}

TPS_CRYPTO_API void tps_crypto_state_free(tps_crypto_state *state)
{
    if (!state)
        return;
    tps_free_noise(state);
    sodium_memzero(state, sizeof *state);
    free(state);
}

static int tps_hex_decode(uint8_t *out, size_t out_len, const char *hex)
{
    size_t index;
    unsigned int high;
    unsigned int low;
    for (index = 0; index < out_len; ++index) {
        char a = hex[index * 2u];
        char b = hex[index * 2u + 1u];
        high = a >= '0' && a <= '9' ? (unsigned int) (a - '0')
             : a >= 'a' && a <= 'f' ? (unsigned int) (a - 'a' + 10) : 99u;
        low = b >= '0' && b <= '9' ? (unsigned int) (b - '0')
            : b >= 'a' && b <= 'f' ? (unsigned int) (b - 'a' + 10) : 99u;
        if (high > 15u || low > 15u)
            return 0;
        out[index] = (uint8_t) ((high << 4) | low);
    }
    return hex[out_len * 2u] == '\0';
}

static int tps_self_test_response(void)
{
    uint8_t key[TPS_CRYPTO_KEY_BYTES] = {0};
    uint8_t transcript[TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES] = {0};
    uint8_t expected[TPS_CRYPTO_RESPONSE_TAG_BYTES] = {0};
    uint8_t actual[TPS_CRYPTO_RESPONSE_TAG_BYTES] = {0};
    size_t index;
    int ok = 0;

    for (index = 0; index < sizeof key; ++index)
        key[index] = (uint8_t) (0x20u + index);
    if (!tps_hex_decode(transcript, sizeof transcript,
            "545053322d524553504f4e53452d7631"
            "02010600650102030258566a26064700470000000000000000001111"
            "000102030405060708090a0b0c0d0e0f"
            "02020600650102030258700e20014860486000000000000000008888"
            "000102030405060708090a0b0c0d0e0f"
            "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf") ||
        !tps_hex_decode(expected, sizeof expected,
            "0124c94b1be6f885a41dd40f699ce4e03d7f69c9df73c595e028656016995bdd") ||
        tps_crypto_response_tag(key, transcript, actual) != TPS_CRYPTO_OK ||
        sodium_memcmp(actual, expected, sizeof actual) != 0 ||
        tps_crypto_response_verify(key, transcript, expected) !=
            TPS_CRYPTO_OK)
        goto cleanup;
    actual[0] ^= 1u;
    if (tps_crypto_response_verify(key, transcript, actual) !=
            TPS_CRYPTO_ERR_AUTH)
        goto cleanup;
    ok = 1;

cleanup:
    sodium_memzero(key, sizeof key);
    sodium_memzero(transcript, sizeof transcript);
    sodium_memzero(expected, sizeof expected);
    sodium_memzero(actual, sizeof actual);
    return ok;
}

static int tps_self_test_opening(void)
{
    tps_crypto_opening_state *host = NULL;
    tps_crypto_opening_state *guest = NULL;
    uint8_t key[TPS_CRYPTO_KEY_BYTES] = {0};
    uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES] = {0};
    uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES] = {0};
    uint8_t packet[TPS_CRYPTO_OPENING_PACKET_BYTES] = {0};
    uint8_t captured[TPS_CRYPTO_OPENING_PACKET_BYTES] = {0};
    uint8_t bogus_echo[TPS_CRYPTO_OPENING_PACKET_BYTES] = {0};
    size_t index;
    int ok = 0;

    for (index = 0; index < sizeof key; ++index)
        key[index] = (uint8_t) (0x40u + index);
    for (index = 0; index < sizeof invitation_id; ++index) {
        invitation_id[index] = (uint8_t) index;
        guest_nonce[index] = (uint8_t) (0xf0u - index);
    }
    if (tps_crypto_opening_state_new(
            TPS_CRYPTO_OPENING_ROLE_HOST, key,
            invitation_id, guest_nonce, &host) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_new(
            TPS_CRYPTO_OPENING_ROLE_GUEST, key,
            invitation_id, guest_nonce, &guest) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_next(host, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(guest, packet, sizeof packet) !=
            TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(guest, packet, sizeof packet) !=
            TPS_CRYPTO_ERR_REPLAY ||
        tps_crypto_opening_state_next(guest, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(host, packet, sizeof packet) !=
            TPS_CRYPTO_OK ||
        tps_crypto_opening_state_is_ready(host) != 0 ||
        tps_crypto_opening_state_is_ready(guest) != 0 ||
        tps_crypto_opening_state_next(host, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(guest, packet, sizeof packet) !=
            TPS_CRYPTO_OK ||
        tps_crypto_opening_state_is_ready(host) != 0 ||
        tps_crypto_opening_state_is_ready(guest) != 1 ||
        tps_crypto_opening_state_next(guest, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(host, packet, sizeof packet) !=
            TPS_CRYPTO_OK ||
        tps_crypto_opening_state_is_ready(host) != 1 ||
        tps_crypto_opening_state_is_ready(guest) != 1)
        goto cleanup;
    if (tps_crypto_opening_state_receive(host, packet, sizeof packet) !=
            TPS_CRYPTO_ERR_REPLAY)
        goto cleanup;
    host->next_counter = UINT32_MAX;
    if (tps_crypto_opening_state_next(host, packet) != TPS_CRYPTO_OK ||
        tps_load_be32(packet + TPS_OPENING_COUNTER_OFFSET) != UINT32_MAX)
        goto cleanup;
    memset(packet, 0xa5, sizeof packet);
    if (tps_crypto_opening_state_next(host, packet) !=
            TPS_CRYPTO_ERR_EXHAUSTED ||
        !sodium_is_zero(packet, sizeof packet))
        goto cleanup;

    tps_crypto_opening_state_free(host);
    tps_crypto_opening_state_free(guest);
    host = NULL;
    guest = NULL;
    if (tps_crypto_opening_state_new(
            TPS_CRYPTO_OPENING_ROLE_HOST, key,
            invitation_id, guest_nonce, &host) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_next(host, captured) != TPS_CRYPTO_OK)
        goto cleanup;
    tps_crypto_opening_state_free(host);
    host = NULL;
    if (tps_crypto_opening_state_new(
            TPS_CRYPTO_OPENING_ROLE_HOST, key,
            invitation_id, guest_nonce, &host) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_new(
            TPS_CRYPTO_OPENING_ROLE_GUEST, key,
            invitation_id, guest_nonce, &guest) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(guest, captured, sizeof captured) !=
            TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(guest, captured, sizeof captured) !=
            TPS_CRYPTO_ERR_REPLAY ||
        tps_crypto_opening_state_next(guest, bogus_echo) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(host, bogus_echo,
                                         sizeof bogus_echo) !=
            TPS_CRYPTO_ERR_PROTOCOL ||
        tps_crypto_opening_state_next(host, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(guest, packet, sizeof packet) !=
            TPS_CRYPTO_OK ||
        tps_crypto_opening_state_next(guest, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(host, packet, sizeof packet) !=
            TPS_CRYPTO_OK ||
        tps_crypto_opening_state_next(host, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(guest, packet, sizeof packet) !=
            TPS_CRYPTO_OK ||
        tps_crypto_opening_state_is_ready(guest) != 1 ||
        tps_crypto_opening_state_next(guest, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(host, packet, sizeof packet) !=
            TPS_CRYPTO_OK ||
        tps_crypto_opening_state_is_ready(host) != 1)
        goto cleanup;
    ok = 1;

cleanup:
    tps_crypto_opening_state_free(host);
    tps_crypto_opening_state_free(guest);
    sodium_memzero(key, sizeof key);
    sodium_memzero(invitation_id, sizeof invitation_id);
    sodium_memzero(guest_nonce, sizeof guest_nonce);
    sodium_memzero(packet, sizeof packet);
    sodium_memzero(captured, sizeof captured);
    sodium_memzero(bogus_echo, sizeof bogus_echo);
    return ok;
}

static int tps_self_test_bridge(void)
{
    static const uint8_t aad[32] = {
        'T','P','S','B', 1, 1, TPS_CRYPTO_BRIDGE_ROLE_GUEST, 0,
        0, 1, 2, 3, 4, 5, 6, 7,
        8, 9, 10, 11, 12, 13, 14, 15,
        0, 0, 0, 1, 0, 1, 0, 13
    };
    static const uint8_t plaintext[] = "bridge-kat-v3";
    static const uint8_t reply[] = "bridge-reply";
    tps_crypto_bridge_state *host = NULL;
    tps_crypto_bridge_state *guest = NULL;
    tps_crypto_bridge_state *wrong = NULL;
    uint8_t key[TPS_CRYPTO_KEY_BYTES] = {0};
    uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES] = {0};
    uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES] = {0};
    uint8_t wrong_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES] = {0};
    uint8_t wire[TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES +
                 TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES] = {0};
    uint8_t opened[TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES] = {0};
    uint8_t tampered[TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES +
                     TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES] = {0};
    uint8_t changed_aad[sizeof aad] = {0};
    uint8_t expected_wire[37] = {0};
    size_t wire_len = 0;
    size_t opened_len = 0;
    size_t index;
    int ok = 0;

    for (index = 0; index < sizeof key; ++index)
        key[index] = (uint8_t) (0x60u + index);
    for (index = 0; index < sizeof invitation_id; ++index) {
        invitation_id[index] = (uint8_t) index;
        guest_nonce[index] = (uint8_t) (0xa0u + index);
        wrong_nonce[index] = guest_nonce[index];
    }
    wrong_nonce[0] ^= 1u;
    if (!tps_hex_decode(
            expected_wire, sizeof expected_wire,
            "0000000000000000e5b053860c716527eefd08b96ffc94aa2059a4fed69ba34f"
            "17a7569a08") ||
        tps_crypto_bridge_state_new(
            TPS_CRYPTO_BRIDGE_ROLE_HOST, key,
            invitation_id, guest_nonce, &host) != TPS_CRYPTO_OK ||
        tps_crypto_bridge_state_new(
            TPS_CRYPTO_BRIDGE_ROLE_GUEST, key,
            invitation_id, guest_nonce, &guest) != TPS_CRYPTO_OK ||
        tps_crypto_bridge_state_new(
            TPS_CRYPTO_BRIDGE_ROLE_HOST, key,
            invitation_id, wrong_nonce, &wrong) != TPS_CRYPTO_OK)
        goto cleanup;

    if (tps_crypto_bridge_state_seal(
            guest, aad, sizeof aad,
            plaintext, sizeof plaintext - 1u,
            wire, sizeof wire, &wire_len) != TPS_CRYPTO_OK ||
        wire_len != sizeof plaintext - 1u +
            TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES ||
        wire_len != sizeof expected_wire ||
        sodium_memcmp(wire, expected_wire, sizeof expected_wire) != 0)
        goto cleanup;
    memcpy(tampered, wire, wire_len);
    tampered[wire_len - 1u] ^= 1u;
    if (tps_crypto_bridge_state_open(
            host, aad, sizeof aad, tampered, wire_len,
            opened, sizeof opened, &opened_len) != TPS_CRYPTO_ERR_AUTH ||
        opened_len != 0u ||
        tps_crypto_bridge_state_open(
            host, aad, sizeof aad, wire, wire_len,
            opened, sizeof opened, &opened_len) != TPS_CRYPTO_OK ||
        opened_len != sizeof plaintext - 1u ||
        sodium_memcmp(opened, plaintext, opened_len) != 0 ||
        tps_crypto_bridge_state_open(
            host, aad, sizeof aad, wire, wire_len,
            opened, sizeof opened, &opened_len) != TPS_CRYPTO_ERR_REPLAY ||
        tps_crypto_bridge_state_open(
            wrong, aad, sizeof aad, wire, wire_len,
            opened, sizeof opened, &opened_len) != TPS_CRYPTO_ERR_AUTH)
        goto cleanup;

    memcpy(changed_aad, aad, sizeof changed_aad);
    changed_aad[27] ^= 1u;
    if (tps_crypto_bridge_state_seal(
            host, aad, sizeof aad,
            reply, sizeof reply - 1u,
            wire, sizeof wire, &wire_len) != TPS_CRYPTO_OK ||
        tps_crypto_bridge_state_open(
            guest, changed_aad, sizeof changed_aad,
            wire, wire_len, opened, sizeof opened,
            &opened_len) != TPS_CRYPTO_ERR_AUTH ||
        tps_crypto_bridge_state_open(
            guest, aad, sizeof aad,
            wire, wire_len, opened, sizeof opened,
            &opened_len) != TPS_CRYPTO_OK ||
        opened_len != sizeof reply - 1u ||
        sodium_memcmp(opened, reply, opened_len) != 0)
        goto cleanup;
    ok = 1;

cleanup:
    tps_crypto_bridge_state_free(host);
    tps_crypto_bridge_state_free(guest);
    tps_crypto_bridge_state_free(wrong);
    sodium_memzero(key, sizeof key);
    sodium_memzero(invitation_id, sizeof invitation_id);
    sodium_memzero(guest_nonce, sizeof guest_nonce);
    sodium_memzero(wrong_nonce, sizeof wrong_nonce);
    sodium_memzero(wire, sizeof wire);
    sodium_memzero(opened, sizeof opened);
    sodium_memzero(tampered, sizeof tampered);
    sodium_memzero(changed_aad, sizeof changed_aad);
    sodium_memzero(expected_wire, sizeof expected_wire);
    return ok;
}

static int tps_self_test_kdf(void)
{
    uint8_t master[crypto_kdf_KEYBYTES];
    uint8_t actual[crypto_kdf_BYTES_MAX];
    uint8_t expected[crypto_kdf_BYTES_MAX];
    size_t index;
    for (index = 0; index < sizeof master; ++index)
        master[index] = (uint8_t) index;
    if (!tps_hex_decode(expected, sizeof expected,
            "a0c724404728c8bb95e5433eb6a9716171144d61efb23e74b873fcbeda51d807"
            "1b5d70aae12066dfc94ce943f145aa176c055040c3dd73b0a15e36254d450614") ||
        crypto_kdf_derive_from_key(
            actual, sizeof actual, 0, "KDF test", master) != 0 ||
        sodium_memcmp(actual, expected, sizeof actual) != 0) {
        sodium_memzero(master, sizeof master);
        sodium_memzero(actual, sizeof actual);
        return 0;
    }
    sodium_memzero(master, sizeof master);
    sodium_memzero(actual, sizeof actual);
    return 1;
}

static int tps_self_test_xchacha(void)
{
    static const uint8_t message[] =
        "Ladies and Gentlemen of the class of '99: If I could offer you "
        "only one tip for the future, sunscreen would be it.";
    static const uint8_t nonce[24] = {
        0x07, 0x00, 0x00, 0x00, 0x40, 0x41, 0x42, 0x43,
        0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b,
        0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53
    };
    static const uint8_t aad[12] = {
        0x50, 0x51, 0x52, 0x53, 0xc0, 0xc1,
        0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7
    };
    uint8_t key[32];
    uint8_t actual[130];
    uint8_t expected[130];
    unsigned long long actual_len = 0;
    size_t index;
    for (index = 0; index < sizeof key; ++index)
        key[index] = (uint8_t) (0x80u + index);
    if (sizeof message - 1u != 114u ||
        !tps_hex_decode(expected, sizeof expected,
            "f8ebea4875044066fc162a0604e171feecfb3d20425248563bcfd5a155dcc47b"
            "bda70b86e5ab9b55002bd1274c02db35321acd7af8b2e2d25015e136b7679458"
            "e9f43243bf719d639badb5feac03f80a19a96ef10cb1d15333a837b90946ba38"
            "54ee74da3f2585efc7e1e170e17e15e563e77601f4f85cafa8e5877614e143e6"
            "8420") ||
        crypto_aead_xchacha20poly1305_ietf_encrypt(
            actual, &actual_len, message, sizeof message - 1u,
            aad, sizeof aad, NULL, nonce, key) != 0 ||
        actual_len != sizeof actual ||
        sodium_memcmp(actual, expected, sizeof actual) != 0) {
        sodium_memzero(key, sizeof key);
        sodium_memzero(actual, sizeof actual);
        return 0;
    }
    sodium_memzero(key, sizeof key);
    sodium_memzero(actual, sizeof actual);
    return 1;
}

static int tps_noise_vector_new(
    NoiseHandshakeState **out,
    int role,
    const uint8_t psk[32],
    const uint8_t ephemeral[32])
{
    NoiseHandshakeState *state = NULL;
    NoiseDHState *fixed;
    int error;
    error = noise_handshakestate_new_by_name(
        &state, TPS_NOISE_PROTOCOL, role);
    if (error == NOISE_ERROR_NONE)
        error = noise_handshakestate_set_pre_shared_key(state, psk, 32);
    if (error == NOISE_ERROR_NONE)
        error = noise_handshakestate_set_prologue(
            state, "John Galt", sizeof "John Galt" - 1u);
    fixed = error == NOISE_ERROR_NONE
        ? noise_handshakestate_get_fixed_ephemeral_dh(state) : NULL;
    if (!fixed)
        error = NOISE_ERROR_NO_MEMORY;
    if (error == NOISE_ERROR_NONE)
        error = noise_dhstate_set_keypair_private(fixed, ephemeral, 32);
    if (error == NOISE_ERROR_NONE)
        error = noise_handshakestate_start(state);
    if (error != NOISE_ERROR_NONE) {
        if (state)
            noise_handshakestate_free(state);
        return 0;
    }
    *out = state;
    return 1;
}

static int tps_self_test_noise(void)
{
    NoiseHandshakeState *initiator = NULL;
    NoiseHandshakeState *responder = NULL;
    NoiseCipherState *init_send = NULL;
    NoiseCipherState *init_receive = NULL;
    NoiseCipherState *resp_send = NULL;
    NoiseCipherState *resp_receive = NULL;
    NoiseBuffer message;
    NoiseBuffer payload;
    uint8_t psk[32], init_e[32], resp_e[32], expected_hash[32];
    uint8_t expected_1[64], expected_2[63];
    uint8_t expected_3[27], expected_4[27];
    uint8_t expected_5[33], expected_6[37];
    uint8_t payload_1[16], payload_2[15], received[16];
    uint8_t payload_3[11], payload_4[11], payload_5[17], payload_6[21];
    uint8_t wire[80], mutable_wire[80], hash_i[32], hash_r[32];
    int ok = 0;
    int vector_error;

    if (!tps_hex_decode(psk, sizeof psk,
            "54686973206973206d7920417573747269616e20706572737065637469766521") ||
        !tps_hex_decode(init_e, sizeof init_e,
            "893e28b9dc6ca8d611ab664754b8ceb7bac5117349a4439a6b0569da977c464a") ||
        !tps_hex_decode(resp_e, sizeof resp_e,
            "bbdb4cdbd309f1a1f2e1456967fe288cadd6f712d65dc7b7793d5e63da6b375b") ||
        !tps_hex_decode(expected_hash, sizeof expected_hash,
            "b3e9c846d264120a4211e18307da91157a21e92e69b639c50f027f101db3e1a6") ||
        !tps_hex_decode(payload_1, sizeof payload_1,
            "4c756477696720766f6e204d69736573") ||
        !tps_hex_decode(payload_2, sizeof payload_2,
            "4d757272617920526f746862617264") ||
        !tps_hex_decode(expected_1, sizeof expected_1,
            "ca35def5ae56cec33dc2036731ab14896bc4c75dbb07a61f879f8e3afa4c7944"
            "fda936bec35a8adfdff198386f7d5475880897edaaf7495314c99095a2e4d66a") ||
        !tps_hex_decode(expected_2, sizeof expected_2,
            "95ebc60d2b1fa672c1f46a8aa265ef51bfe38e7ccb39ec5be34069f144808843"
            "4cd2a371993ba41ea11448024fca32766b169183c9e691a7a433279da7e729") ||
        !tps_hex_decode(payload_3, sizeof payload_3,
            "462e20412e20486179656b") ||
        !tps_hex_decode(expected_3, sizeof expected_3,
            "bc44da303ae0beb08075fc4eb4e58235c67c2d1f53a4f2fff0bca7") ||
        !tps_hex_decode(payload_4, sizeof payload_4,
            "4361726c204d656e676572") ||
        !tps_hex_decode(expected_4, sizeof expected_4,
            "416d1af83e9fa6966ce4e871156b131aa9bd7e9a1d6f8794f4872a") ||
        !tps_hex_decode(payload_5, sizeof payload_5,
            "4a65616e2d426170746973746520536179") ||
        !tps_hex_decode(expected_5, sizeof expected_5,
            "8a7d81b77bcc6c072f2b807da066efba6b5fab9edf71a7faceb2c8454b0cfef608") ||
        !tps_hex_decode(payload_6, sizeof payload_6,
            "457567656e2042f6686d20766f6e2042617765726b") ||
        !tps_hex_decode(expected_6, sizeof expected_6,
            "1e2ee010f72894824a25a867664ff298f2548a145dc4e9d27b1cad83f32fa7c54d69dc3279"))
        goto cleanup;
    if (!tps_noise_vector_new(
            &initiator, NOISE_ROLE_INITIATOR, psk, init_e) ||
        !tps_noise_vector_new(
            &responder, NOISE_ROLE_RESPONDER, psk, resp_e))
        goto cleanup;

    noise_buffer_set_output(message, wire, sizeof wire);
    noise_buffer_set_input(payload, payload_1, sizeof payload_1);
    vector_error = noise_handshakestate_write_message(
            initiator, &message, &payload);
    if (vector_error != NOISE_ERROR_NONE ||
        message.size != sizeof expected_1 ||
        sodium_memcmp(wire, expected_1, sizeof expected_1) != 0)
        goto cleanup;

    memcpy(mutable_wire, wire, message.size);
    noise_buffer_set_input(message, mutable_wire, message.size);
    noise_buffer_set_output(payload, received, sizeof received);
    if (noise_handshakestate_read_message(
            responder, &message, &payload) != NOISE_ERROR_NONE ||
        payload.size != sizeof payload_1 ||
        sodium_memcmp(received, payload_1, sizeof payload_1) != 0)
        goto cleanup;

    noise_buffer_set_output(message, wire, sizeof wire);
    noise_buffer_set_input(payload, payload_2, sizeof payload_2);
    if (noise_handshakestate_write_message(
            responder, &message, &payload) != NOISE_ERROR_NONE ||
        message.size != sizeof expected_2 ||
        sodium_memcmp(wire, expected_2, sizeof expected_2) != 0)
        goto cleanup;
    memcpy(mutable_wire, wire, message.size);
    noise_buffer_set_input(message, mutable_wire, message.size);
    noise_buffer_set_output(payload, received, sizeof received);
    if (noise_handshakestate_read_message(
            initiator, &message, &payload) != NOISE_ERROR_NONE ||
        payload.size != sizeof payload_2 ||
        sodium_memcmp(received, payload_2, sizeof payload_2) != 0)
        goto cleanup;
    if (noise_handshakestate_get_handshake_hash(
            initiator, hash_i, sizeof hash_i) != NOISE_ERROR_NONE ||
        noise_handshakestate_get_handshake_hash(
            responder, hash_r, sizeof hash_r) != NOISE_ERROR_NONE ||
        sodium_memcmp(hash_i, expected_hash, sizeof hash_i) != 0 ||
        sodium_memcmp(hash_r, expected_hash, sizeof hash_r) != 0)
        goto cleanup;

    if (noise_handshakestate_split(
            initiator, &init_send, &init_receive) != NOISE_ERROR_NONE ||
        noise_handshakestate_split(
            responder, &resp_send, &resp_receive) != NOISE_ERROR_NONE)
        goto cleanup;

    memcpy(wire, payload_3, sizeof payload_3);
    noise_buffer_set_inout(message, wire, sizeof payload_3, sizeof wire);
    if (noise_cipherstate_encrypt(init_send, &message) != NOISE_ERROR_NONE ||
        message.size != sizeof expected_3 ||
        sodium_memcmp(wire, expected_3, sizeof expected_3) != 0)
        goto cleanup;
    memcpy(mutable_wire, expected_3, sizeof expected_3);
    mutable_wire[sizeof expected_3 - 1u] ^= 1u;
    noise_buffer_set_inout(message, mutable_wire,
                           sizeof expected_3, sizeof expected_3);
    if (noise_cipherstate_decrypt(resp_receive, &message) !=
            NOISE_ERROR_MAC_FAILURE)
        goto cleanup;
    memcpy(mutable_wire, expected_3, sizeof expected_3);
    noise_buffer_set_inout(message, mutable_wire,
                           sizeof expected_3, sizeof expected_3);
    if (noise_cipherstate_decrypt(resp_receive, &message) != NOISE_ERROR_NONE ||
        message.size != sizeof payload_3 ||
        sodium_memcmp(mutable_wire, payload_3, sizeof payload_3) != 0)
        goto cleanup;

    memcpy(wire, payload_4, sizeof payload_4);
    noise_buffer_set_inout(message, wire, sizeof payload_4, sizeof wire);
    if (noise_cipherstate_encrypt(resp_send, &message) != NOISE_ERROR_NONE ||
        message.size != sizeof expected_4 ||
        sodium_memcmp(wire, expected_4, sizeof expected_4) != 0)
        goto cleanup;
    memcpy(mutable_wire, expected_4, sizeof expected_4);
    noise_buffer_set_inout(message, mutable_wire,
                           sizeof expected_4, sizeof expected_4);
    if (noise_cipherstate_decrypt(init_receive, &message) != NOISE_ERROR_NONE ||
        message.size != sizeof payload_4 ||
        sodium_memcmp(mutable_wire, payload_4, sizeof payload_4) != 0)
        goto cleanup;

    memcpy(wire, payload_5, sizeof payload_5);
    noise_buffer_set_inout(message, wire, sizeof payload_5, sizeof wire);
    if (noise_cipherstate_encrypt(init_send, &message) != NOISE_ERROR_NONE ||
        message.size != sizeof expected_5 ||
        sodium_memcmp(wire, expected_5, sizeof expected_5) != 0)
        goto cleanup;
    memcpy(mutable_wire, expected_5, sizeof expected_5);
    noise_buffer_set_inout(message, mutable_wire,
                           sizeof expected_5, sizeof expected_5);
    if (noise_cipherstate_decrypt(resp_receive, &message) != NOISE_ERROR_NONE ||
        message.size != sizeof payload_5 ||
        sodium_memcmp(mutable_wire, payload_5, sizeof payload_5) != 0)
        goto cleanup;

    memcpy(wire, payload_6, sizeof payload_6);
    noise_buffer_set_inout(message, wire, sizeof payload_6, sizeof wire);
    if (noise_cipherstate_encrypt(resp_send, &message) != NOISE_ERROR_NONE ||
        message.size != sizeof expected_6 ||
        sodium_memcmp(wire, expected_6, sizeof expected_6) != 0)
        goto cleanup;
    memcpy(mutable_wire, expected_6, sizeof expected_6);
    noise_buffer_set_inout(message, mutable_wire,
                           sizeof expected_6, sizeof expected_6);
    if (noise_cipherstate_decrypt(init_receive, &message) != NOISE_ERROR_NONE ||
        message.size != sizeof payload_6 ||
        sodium_memcmp(mutable_wire, payload_6, sizeof payload_6) != 0)
        goto cleanup;
    ok = 1;

cleanup:
    if (init_send)
        noise_cipherstate_free(init_send);
    if (init_receive)
        noise_cipherstate_free(init_receive);
    if (resp_send)
        noise_cipherstate_free(resp_send);
    if (resp_receive)
        noise_cipherstate_free(resp_receive);
    if (initiator)
        noise_handshakestate_free(initiator);
    if (responder)
        noise_handshakestate_free(responder);
    sodium_memzero(psk, sizeof psk);
    sodium_memzero(init_e, sizeof init_e);
    sodium_memzero(resp_e, sizeof resp_e);
    sodium_memzero(wire, sizeof wire);
    sodium_memzero(mutable_wire, sizeof mutable_wire);
    sodium_memzero(received, sizeof received);
    sodium_memzero(hash_i, sizeof hash_i);
    sodium_memzero(hash_r, sizeof hash_r);
    return ok;
}

/*
 * These literal provider-v2 expectations were derived independently of
 * Noise-C and libsodium using standard BLAKE2/HMAC plus standalone X25519,
 * IETF ChaCha20-Poly1305, and HChaCha20 implementations.  That derivation
 * also reproduced the pinned Cacophony NNpsk0, libsodium KDF, and XChaCha
 * anchors tested above.  The reference generator is deliberately not part
 * of this runtime test so this KAT cannot regenerate its own expectations.
 */
static int tps_self_test_provider(void)
{
    static const uint8_t aad[] = {
        0x54, 0x50, 0x53, 0x44, 0x01, 0x02, 0x07
    };
    static const uint8_t c2h_plaintext[] = "KAT-C2H-v2";
    static const uint8_t h2c_plaintext[] = "KAT-H2C-v2";
    tps_crypto_state *initiator = NULL;
    tps_crypto_state *responder = NULL;
    tps_channel_state *channel_state;
    uint8_t master[32] = {0};
    uint8_t initiator_ephemeral[32] = {0};
    uint8_t responder_ephemeral[32] = {0};
    uint8_t initiator_contribution[32] = {0};
    uint8_t responder_contribution[32] = {0};
    uint8_t actual_noise_psk[32] = {0};
    uint8_t expected_noise_psk[32] = {0};
    uint8_t expected_flight_1[TPS_HANDSHAKE_FLIGHT_BYTES] = {0};
    uint8_t expected_flight_2[TPS_HANDSHAKE_FLIGHT_BYTES] = {0};
    uint8_t expected_handshake_hash[32] = {0};
    uint8_t expected_root[32] = {0};
    uint8_t expected_finish[TPS_FINISH_WIRE_BYTES] = {0};
    uint8_t expected_ack[TPS_ACK_WIRE_BYTES] = {0};
    uint8_t expected_direction_0_key[32] = {0};
    uint8_t expected_direction_0_nonce[16] = {0};
    uint8_t expected_direction_0_wire[34] = {0};
    uint8_t expected_direction_1_key[32] = {0};
    uint8_t expected_direction_1_nonce[16] = {0};
    uint8_t expected_direction_1_wire[34] = {0};
    uint8_t flight_1[TPS_HANDSHAKE_FLIGHT_BYTES] = {0};
    uint8_t flight_2[TPS_HANDSHAKE_FLIGHT_BYTES] = {0};
    uint8_t finish[TPS_FINISH_WIRE_BYTES] = {0};
    uint8_t ack[TPS_ACK_WIRE_BYTES] = {0};
    uint8_t wire[34] = {0};
    uint8_t opened[sizeof c2h_plaintext - 1u] = {0};
    size_t flight_1_len = 0;
    size_t flight_2_len = 0;
    size_t finish_len = 0;
    size_t ack_len = 0;
    size_t wire_len = 0;
    size_t opened_len = 0;
    int ok = 0;

    if (!tps_hex_decode(master, sizeof master,
            "4242424242424242424242424242424242424242424242424242424242424242") ||
        !tps_hex_decode(initiator_ephemeral, sizeof initiator_ephemeral,
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f") ||
        !tps_hex_decode(responder_ephemeral, sizeof responder_ephemeral,
            "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f") ||
        !tps_hex_decode(initiator_contribution,
            sizeof initiator_contribution,
            "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f") ||
        !tps_hex_decode(responder_contribution,
            sizeof responder_contribution,
            "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf") ||
        !tps_hex_decode(expected_noise_psk, sizeof expected_noise_psk,
            "e6836ac518901ad047b75e9022054e09b25846f00f45cb0c47ed8c0ae61604e1") ||
        !tps_hex_decode(expected_flight_1, sizeof expected_flight_1,
            "8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f"
            "89900a750fa09f8d96fcdf8a6a764b406dab379829961d15c0528dc1b9fe2fb8"
            "d95416c6eb7bc700cfdffa5e55f1003a") ||
        !tps_hex_decode(expected_flight_2, sizeof expected_flight_2,
            "358072d6365880d1aeea329adf9121383851ed21a28e3b75e965d0d2cd1662544"
            "7084b274c3a7c32377f308e17a0546e1e66e2ee958e578beabfb87f0b46a5360"
            "6f5f00311f84d02b54a020ace56c172") ||
        !tps_hex_decode(expected_handshake_hash,
            sizeof expected_handshake_hash,
            "51934045e1e2af3b1b257a348bc2ef06c1a70eb341f04f75bf4a17b00aede172") ||
        !tps_hex_decode(expected_root, sizeof expected_root,
            "a0a3a2eda1310f8017af23ef8ad305bb448f8610e908dc3a18734cb2202e675e") ||
        !tps_hex_decode(expected_finish, sizeof expected_finish,
            "08a0a88f2d2a6bb377100a2fd9cd2adcafd4104a9e4211a2b5b074858527e4af"
            "284afba47c8789e9b54b2a74aaf2cd81d6d1386f8d5bf1df") ||
        !tps_hex_decode(expected_ack, sizeof expected_ack,
            "b46e03f4ad8eaa626383ac5bae622f515e7f844730ae1a7e7a8d67dcdcd03938"
            "99e738ae0624eb9610d1b81851880d796f48c7162f48b41d") ||
        !tps_hex_decode(expected_direction_0_key,
            sizeof expected_direction_0_key,
            "03deae48abb8bc1bca73a44263f43903a074fa68dee0e0e01ebb2ec3c7624e36") ||
        !tps_hex_decode(expected_direction_0_nonce,
            sizeof expected_direction_0_nonce,
            "b8f45292df1825089b22669d9c2e294d") ||
        !tps_hex_decode(expected_direction_0_wire,
            sizeof expected_direction_0_wire,
            "000000000000000068d01d4e43cc1070e69307ab0a6975cb03fb00c3e1d4ffedd5d7") ||
        !tps_hex_decode(expected_direction_1_key,
            sizeof expected_direction_1_key,
            "e0d8a9b5e6463c662da6a8cfdf575da4e2a447375a6684b750fdcfc4ddac73a0") ||
        !tps_hex_decode(expected_direction_1_nonce,
            sizeof expected_direction_1_nonce,
            "120f335f858dc1dd431d2ba026f2c88f") ||
        !tps_hex_decode(expected_direction_1_wire,
            sizeof expected_direction_1_wire,
            "0000000000000000c549192ef2e6adbecadf66f1eb7df3b0653c12e826e2be4d45f4"))
        goto cleanup;

    if (tps_derive_noise_psk(actual_noise_psk, master) != TPS_CRYPTO_OK ||
        sodium_memcmp(actual_noise_psk, expected_noise_psk,
                      sizeof actual_noise_psk) != 0 ||
        tps_state_new_core(
            TPS_CRYPTO_ROLE_INITIATOR, master, initiator_ephemeral,
            &initiator) != TPS_CRYPTO_OK ||
        tps_state_new_core(
            TPS_CRYPTO_ROLE_RESPONDER, master, responder_ephemeral,
            &responder) != TPS_CRYPTO_OK)
        goto cleanup;

    if (tps_crypto_state_start(responder, NULL, 0, &flight_2_len) !=
            TPS_CRYPTO_OK || flight_2_len != 0 ||
        tps_initiator_start_core(
            initiator, flight_1, sizeof flight_1, &flight_1_len,
            initiator_contribution) != TPS_CRYPTO_OK ||
        flight_1_len != sizeof expected_flight_1 ||
        sodium_memcmp(flight_1, expected_flight_1,
                      sizeof expected_flight_1) != 0)
        goto cleanup;

    if (tps_responder_flight_1_core(
            responder, flight_1, flight_1_len,
            flight_2, sizeof flight_2, &flight_2_len,
            responder_contribution) != TPS_CRYPTO_OK ||
        flight_2_len != sizeof expected_flight_2 ||
        sodium_memcmp(flight_2, expected_flight_2,
                      sizeof expected_flight_2) != 0)
        goto cleanup;

    if (tps_crypto_state_handshake(
            initiator, flight_2, flight_2_len,
            finish, sizeof finish, &finish_len) != TPS_CRYPTO_OK ||
        finish_len != sizeof expected_finish ||
        sodium_memcmp(finish, expected_finish, sizeof expected_finish) != 0 ||
        !initiator->root_ready || !responder->root_ready ||
        sodium_memcmp(initiator->handshake_hash,
                      expected_handshake_hash,
                      sizeof expected_handshake_hash) != 0 ||
        sodium_memcmp(responder->handshake_hash,
                      expected_handshake_hash,
                      sizeof expected_handshake_hash) != 0 ||
        sodium_memcmp(initiator->root, expected_root,
                      sizeof expected_root) != 0 ||
        sodium_memcmp(responder->root, expected_root,
                      sizeof expected_root) != 0)
        goto cleanup;

    if (tps_crypto_state_handshake(
            responder, finish, finish_len,
            ack, sizeof ack, &ack_len) != TPS_CRYPTO_OK ||
        ack_len != sizeof expected_ack ||
        sodium_memcmp(ack, expected_ack, sizeof expected_ack) != 0 ||
        tps_crypto_state_handshake(
            initiator, ack, ack_len, NULL, 0, &finish_len) !=
                TPS_CRYPTO_OK ||
        finish_len != 0 ||
        tps_crypto_state_is_ready(initiator) != 1 ||
        tps_crypto_state_is_ready(responder) != 1)
        goto cleanup;

    if (tps_crypto_state_seal(
            initiator, 7, aad, sizeof aad,
            c2h_plaintext, sizeof c2h_plaintext - 1u,
            wire, sizeof wire, &wire_len) != TPS_CRYPTO_OK ||
        wire_len != sizeof expected_direction_0_wire ||
        sodium_memcmp(wire, expected_direction_0_wire,
                      sizeof expected_direction_0_wire) != 0)
        goto cleanup;
    channel_state = &initiator->send_channels[7];
    if (!channel_state->derived ||
        channel_state->next_sequence != UINT64_C(1) ||
        sodium_memcmp(channel_state->key, expected_direction_0_key,
                      sizeof expected_direction_0_key) != 0 ||
        sodium_memcmp(channel_state->nonce_prefix,
                      expected_direction_0_nonce,
                      sizeof expected_direction_0_nonce) != 0)
        goto cleanup;
    if (tps_crypto_state_open(
            responder, 7, aad, sizeof aad, wire, wire_len,
            opened, sizeof opened, &opened_len) != TPS_CRYPTO_OK ||
        opened_len != sizeof c2h_plaintext - 1u ||
        sodium_memcmp(opened, c2h_plaintext, opened_len) != 0)
        goto cleanup;
    channel_state = &responder->receive_channels[7];
    if (!channel_state->derived ||
        !channel_state->replay_started ||
        channel_state->replay_highest != UINT64_C(0) ||
        channel_state->replay_bitmap != UINT64_C(1) ||
        sodium_memcmp(channel_state->key, expected_direction_0_key,
                      sizeof expected_direction_0_key) != 0 ||
        sodium_memcmp(channel_state->nonce_prefix,
                      expected_direction_0_nonce,
                      sizeof expected_direction_0_nonce) != 0)
        goto cleanup;

    sodium_memzero(wire, sizeof wire);
    sodium_memzero(opened, sizeof opened);
    wire_len = 0;
    opened_len = 0;
    if (tps_crypto_state_seal(
            responder, 7, aad, sizeof aad,
            h2c_plaintext, sizeof h2c_plaintext - 1u,
            wire, sizeof wire, &wire_len) != TPS_CRYPTO_OK ||
        wire_len != sizeof expected_direction_1_wire ||
        sodium_memcmp(wire, expected_direction_1_wire,
                      sizeof expected_direction_1_wire) != 0)
        goto cleanup;
    channel_state = &responder->send_channels[7];
    if (!channel_state->derived ||
        channel_state->next_sequence != UINT64_C(1) ||
        sodium_memcmp(channel_state->key, expected_direction_1_key,
                      sizeof expected_direction_1_key) != 0 ||
        sodium_memcmp(channel_state->nonce_prefix,
                      expected_direction_1_nonce,
                      sizeof expected_direction_1_nonce) != 0)
        goto cleanup;
    if (tps_crypto_state_open(
            initiator, 7, aad, sizeof aad, wire, wire_len,
            opened, sizeof opened, &opened_len) != TPS_CRYPTO_OK ||
        opened_len != sizeof h2c_plaintext - 1u ||
        sodium_memcmp(opened, h2c_plaintext, opened_len) != 0)
        goto cleanup;
    channel_state = &initiator->receive_channels[7];
    if (!channel_state->derived ||
        !channel_state->replay_started ||
        channel_state->replay_highest != UINT64_C(0) ||
        channel_state->replay_bitmap != UINT64_C(1) ||
        sodium_memcmp(channel_state->key, expected_direction_1_key,
                      sizeof expected_direction_1_key) != 0 ||
        sodium_memcmp(channel_state->nonce_prefix,
                      expected_direction_1_nonce,
                      sizeof expected_direction_1_nonce) != 0)
        goto cleanup;
    ok = 1;

cleanup:
    tps_crypto_state_free(initiator);
    tps_crypto_state_free(responder);
    sodium_memzero(master, sizeof master);
    sodium_memzero(initiator_ephemeral, sizeof initiator_ephemeral);
    sodium_memzero(responder_ephemeral, sizeof responder_ephemeral);
    sodium_memzero(initiator_contribution, sizeof initiator_contribution);
    sodium_memzero(responder_contribution, sizeof responder_contribution);
    sodium_memzero(actual_noise_psk, sizeof actual_noise_psk);
    sodium_memzero(expected_noise_psk, sizeof expected_noise_psk);
    sodium_memzero(expected_flight_1, sizeof expected_flight_1);
    sodium_memzero(expected_flight_2, sizeof expected_flight_2);
    sodium_memzero(expected_handshake_hash, sizeof expected_handshake_hash);
    sodium_memzero(expected_root, sizeof expected_root);
    sodium_memzero(expected_finish, sizeof expected_finish);
    sodium_memzero(expected_ack, sizeof expected_ack);
    sodium_memzero(expected_direction_0_key,
                   sizeof expected_direction_0_key);
    sodium_memzero(expected_direction_0_nonce,
                   sizeof expected_direction_0_nonce);
    sodium_memzero(expected_direction_0_wire,
                   sizeof expected_direction_0_wire);
    sodium_memzero(expected_direction_1_key,
                   sizeof expected_direction_1_key);
    sodium_memzero(expected_direction_1_nonce,
                   sizeof expected_direction_1_nonce);
    sodium_memzero(expected_direction_1_wire,
                   sizeof expected_direction_1_wire);
    sodium_memzero(flight_1, sizeof flight_1);
    sodium_memzero(flight_2, sizeof flight_2);
    sodium_memzero(finish, sizeof finish);
    sodium_memzero(ack, sizeof ack);
    sodium_memzero(wire, sizeof wire);
    sodium_memzero(opened, sizeof opened);
    return ok;
}

TPS_CRYPTO_API int32_t tps_crypto_self_test(void)
{
    if (tps_crypto_init() != TPS_CRYPTO_OK)
        return TPS_CRYPTO_ERR_INTERNAL;
    if (!tps_self_test_kdf() || !tps_self_test_xchacha() ||
            !tps_self_test_response() || !tps_self_test_opening() ||
            !tps_self_test_bridge() ||
            tps_self_test_noise() != 1 || tps_self_test_provider() != 1)
        return TPS_CRYPTO_ERR_INTERNAL;
    return TPS_CRYPTO_OK;
}
