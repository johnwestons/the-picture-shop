#ifndef TPS_CRYPTO_H
#define TPS_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define TPS_CRYPTO_API __declspec(dllexport)
#else
#define TPS_CRYPTO_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define TPS_CRYPTO_ABI_VERSION 3u
#define TPS_CRYPTO_KEY_BYTES 32u
#define TPS_CRYPTO_HANDSHAKE_MAX_BYTES 256u
#define TPS_CRYPTO_DATA_OVERHEAD_BYTES 24u
#define TPS_CRYPTO_MAX_AAD_BYTES 64u
#define TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES 120u
#define TPS_CRYPTO_RESPONSE_TAG_BYTES 32u
#define TPS_CRYPTO_INVITATION_ID_BYTES 16u
#define TPS_CRYPTO_GUEST_NONCE_BYTES 16u
#define TPS_CRYPTO_OPENING_CHALLENGE_BYTES 16u
#define TPS_CRYPTO_OPENING_PACKET_BYTES 92u
#define TPS_CRYPTO_OPENING_TAG_BYTES 16u
#define TPS_CRYPTO_BRIDGE_MAX_AAD_BYTES 64u
#define TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES 1176u
#define TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES 24u

#define TPS_CRYPTO_ROLE_INITIATOR 1u
#define TPS_CRYPTO_ROLE_RESPONDER 2u

#define TPS_CRYPTO_OPENING_ROLE_HOST 1u
#define TPS_CRYPTO_OPENING_ROLE_GUEST 2u

#define TPS_CRYPTO_BRIDGE_ROLE_HOST 1u
#define TPS_CRYPTO_BRIDGE_ROLE_GUEST 2u

#define TPS_CRYPTO_OK 0
#define TPS_CRYPTO_ERR_ARGUMENT -1
#define TPS_CRYPTO_ERR_STATE -2
#define TPS_CRYPTO_ERR_AUTH -3
#define TPS_CRYPTO_ERR_BUFFER -4
#define TPS_CRYPTO_ERR_REPLAY -5
#define TPS_CRYPTO_ERR_PROTOCOL -6
#define TPS_CRYPTO_ERR_INTERNAL -7
#define TPS_CRYPTO_ERR_EXHAUSTED -8

typedef struct tps_crypto_state tps_crypto_state;
typedef struct tps_crypto_opening_state tps_crypto_opening_state;
typedef struct tps_crypto_bridge_state tps_crypto_bridge_state;

/*
 * A state has one logical owner. Calls on the same state, including free,
 * must be serialized; concurrent use is outside this ABI contract. Input and
 * output byte ranges passed to seal/open must not overlap.
 */

TPS_CRYPTO_API uint32_t tps_crypto_abi_version(void);
TPS_CRYPTO_API const char *tps_crypto_suite(void);
TPS_CRYPTO_API int32_t tps_crypto_init(void);
TPS_CRYPTO_API int32_t tps_crypto_self_test(void);
TPS_CRYPTO_API int32_t tps_crypto_random(uint8_t *out, size_t out_len);
TPS_CRYPTO_API int32_t tps_crypto_admission_token(
    const uint8_t key[TPS_CRYPTO_KEY_BYTES], uint32_t *out_token);
TPS_CRYPTO_API int32_t tps_crypto_response_tag(
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t transcript[TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES],
    uint8_t out_tag[TPS_CRYPTO_RESPONSE_TAG_BYTES]);
TPS_CRYPTO_API int32_t tps_crypto_response_verify(
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t transcript[TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES],
    const uint8_t tag[TPS_CRYPTO_RESPONSE_TAG_BYTES]);

TPS_CRYPTO_API int32_t tps_crypto_opening_state_new(
    uint32_t role,
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES],
    const uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES],
    tps_crypto_opening_state **out_state);
TPS_CRYPTO_API int32_t tps_crypto_opening_state_next(
    tps_crypto_opening_state *state,
    uint8_t out_packet[TPS_CRYPTO_OPENING_PACKET_BYTES]);
TPS_CRYPTO_API int32_t tps_crypto_opening_state_receive(
    tps_crypto_opening_state *state,
    const uint8_t *input,
    size_t input_len);
TPS_CRYPTO_API int32_t tps_crypto_opening_state_is_ready(
    const tps_crypto_opening_state *state);
TPS_CRYPTO_API void tps_crypto_opening_state_free(
    tps_crypto_opening_state *state);

/*
 * Bridge states protect the raw loopback ENet datagrams that cross the
 * already-authenticated IPv6 path.  The caller authenticates its complete
 * fragment header as AAD.  Each ciphertext contains an eight-byte sequence,
 * a sixteen-byte XChaCha20-Poly1305 tag, and the encrypted fragment bytes.
 */
TPS_CRYPTO_API int32_t tps_crypto_bridge_state_new(
    uint32_t role,
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES],
    const uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES],
    tps_crypto_bridge_state **out_state);
TPS_CRYPTO_API int32_t tps_crypto_bridge_state_seal(
    tps_crypto_bridge_state *state,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *plaintext,
    size_t plaintext_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len);
TPS_CRYPTO_API int32_t tps_crypto_bridge_state_open(
    tps_crypto_bridge_state *state,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len);
TPS_CRYPTO_API void tps_crypto_bridge_state_free(
    tps_crypto_bridge_state *state);

TPS_CRYPTO_API int32_t tps_crypto_state_new(
    uint32_t role,
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    tps_crypto_state **out_state);
TPS_CRYPTO_API int32_t tps_crypto_state_start(
    tps_crypto_state *state,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len);
TPS_CRYPTO_API int32_t tps_crypto_state_handshake(
    tps_crypto_state *state,
    const uint8_t *input,
    size_t input_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len);
TPS_CRYPTO_API int32_t tps_crypto_state_is_ready(
    const tps_crypto_state *state);
TPS_CRYPTO_API int32_t tps_crypto_state_seal(
    tps_crypto_state *state,
    uint8_t channel,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *plaintext,
    size_t plaintext_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len);
TPS_CRYPTO_API int32_t tps_crypto_state_open(
    tps_crypto_state *state,
    uint8_t channel,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len);
TPS_CRYPTO_API void tps_crypto_state_free(tps_crypto_state *state);

#ifdef __cplusplus
}
#endif

#endif
