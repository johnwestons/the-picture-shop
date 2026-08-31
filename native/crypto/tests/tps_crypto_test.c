#include "tps_crypto.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition, label)                                                \
    do {                                                                        \
        if (!(condition)) {                                                      \
            fprintf(stderr, "FAIL: %s (line %d)\n", label, __LINE__);          \
            goto cleanup;                                                       \
        }                                                                       \
    } while (0)

typedef struct test_pair {
    tps_crypto_state *initiator;
    tps_crypto_state *responder;
} test_pair;

typedef struct handshake_fixture {
    test_pair pair;
    uint8_t flight_1[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    uint8_t flight_2[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    uint8_t finish[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    uint8_t ack[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    size_t flight_1_len;
    size_t flight_2_len;
    size_t finish_len;
    size_t ack_len;
} handshake_fixture;

typedef struct opening_pair {
    tps_crypto_opening_state *host;
    tps_crypto_opening_state *guest;
} opening_pair;

static void free_pair(test_pair *pair)
{
    tps_crypto_state_free(pair->initiator);
    tps_crypto_state_free(pair->responder);
    pair->initiator = NULL;
    pair->responder = NULL;
}

static void free_fixture(handshake_fixture *fixture)
{
    if (!fixture)
        return;
    free_pair(&fixture->pair);
    memset(fixture, 0, sizeof *fixture);
}

static void free_opening_pair(opening_pair *pair)
{
    if (!pair)
        return;
    tps_crypto_opening_state_free(pair->host);
    tps_crypto_opening_state_free(pair->guest);
    pair->host = NULL;
    pair->guest = NULL;
}

static int new_opening_pair(
    opening_pair *pair,
    const uint8_t key[TPS_CRYPTO_KEY_BYTES],
    const uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES],
    const uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES])
{
    if (!pair || pair->host || pair->guest)
        return 0;
    if (tps_crypto_opening_state_new(
            TPS_CRYPTO_OPENING_ROLE_HOST, key,
            invitation_id, guest_nonce, &pair->host) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_new(
            TPS_CRYPTO_OPENING_ROLE_GUEST, key,
            invitation_id, guest_nonce, &pair->guest) != TPS_CRYPTO_OK) {
        free_opening_pair(pair);
        return 0;
    }
    return 1;
}

static int complete_opening(opening_pair *pair)
{
    uint8_t packet[TPS_CRYPTO_OPENING_PACKET_BYTES] = {0};
    int ok = 0;

    if (!pair || !pair->host || !pair->guest)
        return 0;
    if (tps_crypto_opening_state_next(pair->host, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(
            pair->guest, packet, sizeof packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_next(pair->guest, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(
            pair->host, packet, sizeof packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_is_ready(pair->host) != 0 ||
        tps_crypto_opening_state_is_ready(pair->guest) != 0 ||
        tps_crypto_opening_state_next(pair->host, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(
            pair->guest, packet, sizeof packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_is_ready(pair->host) != 0 ||
        tps_crypto_opening_state_is_ready(pair->guest) != 1 ||
        tps_crypto_opening_state_next(pair->guest, packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_receive(
            pair->host, packet, sizeof packet) != TPS_CRYPTO_OK ||
        tps_crypto_opening_state_is_ready(pair->host) != 1 ||
        tps_crypto_opening_state_is_ready(pair->guest) != 1 ||
        tps_crypto_opening_state_receive(
            pair->host, packet, sizeof packet) != TPS_CRYPTO_ERR_REPLAY)
        goto cleanup;
    ok = 1;

cleanup:
    memset(packet, 0, sizeof packet);
    return ok;
}

static int decode_hex(uint8_t *out, size_t out_len, const char *hex)
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

static int fixture_to_flight_2(
    handshake_fixture *fixture,
    const uint8_t initiator_key[32],
    const uint8_t responder_key[32])
{
    size_t empty_len = 99;

    if (!fixture || fixture->pair.initiator || fixture->pair.responder)
        return 0;
    memset(fixture, 0, sizeof *fixture);
    if (tps_crypto_state_new(TPS_CRYPTO_ROLE_INITIATOR,
            initiator_key, &fixture->pair.initiator) != TPS_CRYPTO_OK ||
        tps_crypto_state_new(TPS_CRYPTO_ROLE_RESPONDER,
            responder_key, &fixture->pair.responder) != TPS_CRYPTO_OK ||
        tps_crypto_state_start(fixture->pair.responder,
            NULL, 0, &empty_len) != TPS_CRYPTO_OK ||
        empty_len != 0 ||
        tps_crypto_state_start(fixture->pair.initiator,
            fixture->flight_1, sizeof fixture->flight_1,
            &fixture->flight_1_len) != TPS_CRYPTO_OK ||
        fixture->flight_1_len != 80)
        return 0;

    if (tps_crypto_state_handshake(fixture->pair.responder,
            fixture->flight_1, fixture->flight_1_len,
            fixture->flight_2, sizeof fixture->flight_2,
            &fixture->flight_2_len) != TPS_CRYPTO_OK ||
        fixture->flight_2_len != 80 ||
        tps_crypto_state_is_ready(fixture->pair.initiator) != 0 ||
        tps_crypto_state_is_ready(fixture->pair.responder) != 0)
        return 0;
    return 1;
}

static int fixture_to_finish(
    handshake_fixture *fixture,
    const uint8_t initiator_key[32],
    const uint8_t responder_key[32])
{
    if (!fixture_to_flight_2(fixture, initiator_key, responder_key))
        return 0;
    if (tps_crypto_state_handshake(fixture->pair.initiator,
            fixture->flight_2, fixture->flight_2_len,
            fixture->finish, sizeof fixture->finish,
            &fixture->finish_len) != TPS_CRYPTO_OK ||
        fixture->finish_len != 56 ||
        tps_crypto_state_is_ready(fixture->pair.initiator) != 0 ||
        tps_crypto_state_is_ready(fixture->pair.responder) != 0)
        return 0;
    return 1;
}

static int fixture_accept_finish(handshake_fixture *fixture)
{
    fixture->ack_len = 99;
    if (tps_crypto_state_handshake(fixture->pair.responder,
            fixture->finish, fixture->finish_len,
            fixture->ack, sizeof fixture->ack,
            &fixture->ack_len) != TPS_CRYPTO_OK ||
        fixture->ack_len != 56 ||
        tps_crypto_state_is_ready(fixture->pair.responder) != 1 ||
        tps_crypto_state_is_ready(fixture->pair.initiator) != 0)
        return 0;
    return 1;
}

static int fixture_accept_ack(handshake_fixture *fixture)
{
    size_t empty_len = 99;
    if (tps_crypto_state_handshake(fixture->pair.initiator,
            fixture->ack, fixture->ack_len,
            NULL, 0, &empty_len) != TPS_CRYPTO_OK ||
        empty_len != 0 ||
        tps_crypto_state_is_ready(fixture->pair.initiator) != 1 ||
        tps_crypto_state_is_ready(fixture->pair.responder) != 1)
        return 0;
    return 1;
}

static int complete_handshake(
    test_pair *pair,
    const uint8_t initiator_key[32],
    const uint8_t responder_key[32])
{
    uint8_t flight_1[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    uint8_t flight_2[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    uint8_t finish[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    uint8_t ack[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    size_t flight_1_len = 0;
    size_t flight_2_len = 0;
    size_t finish_len = 0;
    size_t ack_len = 0;
    size_t empty_len = 99;

    if (tps_crypto_state_new(TPS_CRYPTO_ROLE_INITIATOR,
            initiator_key, &pair->initiator) != TPS_CRYPTO_OK ||
        tps_crypto_state_new(TPS_CRYPTO_ROLE_RESPONDER,
            responder_key, &pair->responder) != TPS_CRYPTO_OK ||
        tps_crypto_state_start(pair->responder,
            NULL, 0, &empty_len) != TPS_CRYPTO_OK ||
        empty_len != 0 ||
        tps_crypto_state_start(pair->initiator,
            flight_1, sizeof flight_1, &flight_1_len) != TPS_CRYPTO_OK ||
        flight_1_len != 80)
        return 0;

    if (tps_crypto_state_handshake(pair->responder,
            flight_1, flight_1_len,
            flight_2, sizeof flight_2, &flight_2_len) != TPS_CRYPTO_OK)
        return 0;
    if (flight_2_len != 80 || tps_crypto_state_is_ready(pair->responder) != 0)
        return 0;

    if (tps_crypto_state_handshake(pair->initiator,
            flight_2, flight_2_len,
            finish, sizeof finish, &finish_len) != TPS_CRYPTO_OK)
        return 0;
    if (finish_len != 56 || tps_crypto_state_is_ready(pair->initiator) != 0 ||
            tps_crypto_state_is_ready(pair->responder) != 0)
        return 0;

    if (tps_crypto_state_handshake(pair->responder,
            finish, finish_len, ack, sizeof ack, &ack_len) != TPS_CRYPTO_OK)
        return 0;
    if (ack_len != 56 || tps_crypto_state_is_ready(pair->responder) != 1 ||
            tps_crypto_state_is_ready(pair->initiator) != 0)
        return 0;

    empty_len = 99;
    if (tps_crypto_state_handshake(pair->initiator,
            ack, ack_len, NULL, 0, &empty_len) != TPS_CRYPTO_OK)
        return 0;
    return empty_len == 0 && tps_crypto_state_is_ready(pair->initiator) == 1;
}

static int seal_message(
    tps_crypto_state *state,
    uint8_t channel,
    const uint8_t *aad,
    size_t aad_len,
    const char *message,
    uint8_t *out,
    size_t out_capacity,
    size_t *out_len)
{
    return tps_crypto_state_seal(state, channel, aad, aad_len,
        (const uint8_t *) message, strlen(message),
        out, out_capacity, out_len) == TPS_CRYPTO_OK;
}

static int open_message(
    tps_crypto_state *state,
    uint8_t channel,
    const uint8_t *aad,
    size_t aad_len,
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    const char *expected)
{
    uint8_t plaintext[512];
    size_t plaintext_len = 0;
    size_t expected_len = strlen(expected);
    return tps_crypto_state_open(state, channel, aad, aad_len,
               ciphertext, ciphertext_len,
               plaintext, sizeof plaintext, &plaintext_len) == TPS_CRYPTO_OK &&
           plaintext_len == expected_len &&
           memcmp(plaintext, expected, expected_len) == 0;
}

int main(void)
{
    static const uint8_t aad_channel_1[] = {'T','P','S','D',1,2,1};
    static const uint8_t aad_channel_2[] = {'T','P','S','D',1,2,2};
    static const uint8_t aad_channel_3[] = {'T','P','S','D',1,2,3};
    /*
     * Valid NNpsk0 flight one for master key 0x42*32, the TPS prologue,
     * initiator contribution 00..1f, and the non-zero low-order X25519
     * public input u=1.  The derivation was cross-checked against the pinned
     * independent Cacophony first-flight vector before changing its inputs.
     */
    static const uint8_t low_order_flight_1[80] = {
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x95, 0x23, 0x7e, 0xcc, 0xfc, 0x91, 0x33, 0xf6,
        0x7c, 0xc9, 0x25, 0x16, 0x34, 0xd3, 0xb2, 0x74,
        0x83, 0x71, 0xb2, 0x37, 0xf3, 0x7c, 0xa1, 0x69,
        0x90, 0x6f, 0xd1, 0xe9, 0xb1, 0xab, 0x09, 0xc3,
        0x23, 0x9a, 0xfe, 0x9a, 0x0b, 0x01, 0xd5, 0x00,
        0x76, 0x29, 0xef, 0xc4, 0x6c, 0x72, 0x4d, 0xb7
    };
    uint8_t key[32];
    uint8_t wrong_key[32];
    uint8_t random_bytes[32];
    uint8_t ciphertext[8][512];
    uint8_t tampered[512];
    uint8_t negative_output[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    uint8_t replay_flight_2[TPS_CRYPTO_HANDSHAKE_MAX_BYTES];
    uint8_t response_key[TPS_CRYPTO_KEY_BYTES] = {0};
    uint8_t response_transcript[TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES] = {0};
    uint8_t response_tag[TPS_CRYPTO_RESPONSE_TAG_BYTES] = {0};
    uint8_t expected_response_tag[TPS_CRYPTO_RESPONSE_TAG_BYTES] = {0};
    uint8_t altered_response_tag[TPS_CRYPTO_RESPONSE_TAG_BYTES] = {0};
    uint8_t opening_key[TPS_CRYPTO_KEY_BYTES] = {0};
    uint8_t wrong_opening_key[TPS_CRYPTO_KEY_BYTES] = {0};
    uint8_t invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES] = {0};
    uint8_t other_invitation_id[TPS_CRYPTO_INVITATION_ID_BYTES] = {0};
    uint8_t guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES] = {0};
    uint8_t other_guest_nonce[TPS_CRYPTO_GUEST_NONCE_BYTES] = {0};
    uint8_t opening_packet[TPS_CRYPTO_OPENING_PACKET_BYTES] = {0};
    uint8_t original_opening_packet[TPS_CRYPTO_OPENING_PACKET_BYTES] = {0};
    uint8_t mutated_opening_packet[TPS_CRYPTO_OPENING_PACKET_BYTES] = {0};
    uint8_t opening_packets[3][TPS_CRYPTO_OPENING_PACKET_BYTES] = {{0}};
    uint8_t bridge_aad[32] = {0};
    uint8_t changed_bridge_aad[32] = {0};
    uint8_t bridge_plaintext[TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES] = {0};
    uint8_t bridge_wire[TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES +
                        TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES] = {0};
    uint8_t bridge_opened[TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES] = {0};
    uint8_t bridge_tampered[TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES +
                            TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES] = {0};
    size_t ciphertext_len[8] = {0};
    size_t negative_output_len = 0;
    size_t replay_flight_2_len = 0;
    size_t bridge_wire_len = 0;
    size_t bridge_opened_len = 0;
    uint32_t token_1 = 0;
    uint32_t token_2 = 0;
    uint32_t wrong_token = 0;
    test_pair pair = {0};
    test_pair wrong_pair = {0};
    test_pair replay_pair = {0};
    handshake_fixture fixture = {0};
    opening_pair opening = {0};
    opening_pair opening_aux = {0};
    tps_crypto_opening_state *invalid_opening_state = NULL;
    tps_crypto_bridge_state *bridge_host = NULL;
    tps_crypto_bridge_state *bridge_guest = NULL;
    tps_crypto_bridge_state *bridge_wrong = NULL;
    size_t index;
    size_t mutation_index;
    uint32_t counter_index;
    int all_zero = 1;
    int32_t self_test_result;
    int32_t negative_result;
    int32_t wrong_channel_result;
    int result = EXIT_FAILURE;

    memset(key, 0x42, sizeof key);
    memset(wrong_key, 0x24, sizeof wrong_key);
    for (index = 0; index < sizeof response_key; ++index)
        response_key[index] = (uint8_t) (0x20u + index);
    for (index = 0; index < sizeof opening_key; ++index) {
        opening_key[index] = (uint8_t) (0x40u + index);
        wrong_opening_key[index] = (uint8_t) (0x80u + index);
    }
    for (index = 0; index < sizeof invitation_id; ++index) {
        invitation_id[index] = (uint8_t) index;
        other_invitation_id[index] = (uint8_t) index;
        guest_nonce[index] = (uint8_t) (0xf0u - index);
        other_guest_nonce[index] = (uint8_t) (0xf0u - index);
    }
    other_invitation_id[0] ^= 1u;
    other_guest_nonce[0] ^= 1u;

    CHECK(tps_crypto_abi_version() == TPS_CRYPTO_ABI_VERSION, "ABI version");
    CHECK(strcmp(tps_crypto_suite(),
        "TPS-Direct-v3/Noise_NNpsk0_25519_ChaChaPoly_BLAKE2s/"
        "XChaCha20-Poly1305") == 0, "suite pin");
    CHECK(tps_crypto_init() == TPS_CRYPTO_OK, "initialization");
    self_test_result = tps_crypto_self_test();
    if (self_test_result != TPS_CRYPTO_OK)
        fprintf(stderr, "self-test status: %d\n", (int) self_test_result);
    CHECK(self_test_result == TPS_CRYPTO_OK,
          "libsodium, pinned Cacophony, and deterministic TPS-provider vectors");
    CHECK(tps_crypto_random(random_bytes, sizeof random_bytes) == TPS_CRYPTO_OK,
          "operating-system randomness");
    for (index = 0; index < sizeof random_bytes; ++index)
        all_zero &= random_bytes[index] == 0;
    CHECK(!all_zero, "random output is not all zero");

    CHECK(tps_crypto_admission_token(key, &token_1) == TPS_CRYPTO_OK &&
          tps_crypto_admission_token(key, &token_2) == TPS_CRYPTO_OK &&
          tps_crypto_admission_token(wrong_key, &wrong_token) == TPS_CRYPTO_OK,
          "admission-token derivation");
    CHECK(token_1 == token_2 && token_1 == UINT32_C(119185594) &&
              token_1 <= 2147483647u,
          "domain-separated admission-token known answer is stable and 31-bit");
    CHECK(token_1 != wrong_token, "different invitation keys separate tokens");

    CHECK(TPS_CRYPTO_RESPONSE_TRANSCRIPT_BYTES == 120u &&
          TPS_CRYPTO_RESPONSE_TAG_BYTES == 32u &&
          TPS_CRYPTO_INVITATION_ID_BYTES == 16u &&
          TPS_CRYPTO_GUEST_NONCE_BYTES == 16u &&
          TPS_CRYPTO_OPENING_CHALLENGE_BYTES == 16u &&
          TPS_CRYPTO_OPENING_PACKET_BYTES == 92u &&
          TPS_CRYPTO_OPENING_TAG_BYTES == 16u,
          "response and simultaneous-opening ABI sizes are pinned");
    CHECK(decode_hex(response_transcript, sizeof response_transcript,
              "545053322d524553504f4e53452d7631"
              "02010600650102030258566a26064700470000000000000000001111"
              "000102030405060708090a0b0c0d0e0f"
              "02020600650102030258700e20014860486000000000000000008888"
              "000102030405060708090a0b0c0d0e0f"
              "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf") &&
          decode_hex(expected_response_tag, sizeof expected_response_tag,
              "0124c94b1be6f885a41dd40f699ce4e03d7f69c9df73c595e028656016995bdd"),
          "independent response-authentication vector fixtures are exact");
    CHECK(tps_crypto_response_tag(
              response_key, response_transcript, response_tag) ==
              TPS_CRYPTO_OK &&
          memcmp(response_tag, expected_response_tag,
                 sizeof response_tag) == 0 &&
          tps_crypto_response_verify(
              response_key, response_transcript, response_tag) ==
              TPS_CRYPTO_OK,
          "domain-separated response authentication matches hardcoded KAT");
    memcpy(altered_response_tag, response_tag, sizeof altered_response_tag);
    altered_response_tag[sizeof altered_response_tag - 1u] ^= 1u;
    CHECK(tps_crypto_response_verify(
              response_key, response_transcript, altered_response_tag) ==
              TPS_CRYPTO_ERR_AUTH &&
          tps_crypto_response_verify(
              wrong_opening_key, response_transcript, response_tag) ==
              TPS_CRYPTO_ERR_AUTH,
          "response tag and wrong-key failures are constant-time auth errors");
    response_transcript[sizeof response_transcript - 1u] ^= 1u;
    CHECK(tps_crypto_response_verify(
              response_key, response_transcript, response_tag) ==
              TPS_CRYPTO_ERR_AUTH,
          "response transcript is authenticated byte-for-byte");
    response_transcript[sizeof response_transcript - 1u] ^= 1u;
    CHECK(tps_crypto_response_tag(NULL, response_transcript, response_tag) ==
              TPS_CRYPTO_ERR_ARGUMENT &&
          tps_crypto_response_tag(response_key, NULL, response_tag) ==
              TPS_CRYPTO_ERR_ARGUMENT &&
          tps_crypto_response_tag(response_key, response_transcript, NULL) ==
              TPS_CRYPTO_ERR_ARGUMENT &&
          tps_crypto_response_verify(NULL, response_transcript, response_tag) ==
              TPS_CRYPTO_ERR_ARGUMENT &&
          tps_crypto_response_verify(response_key, NULL, response_tag) ==
              TPS_CRYPTO_ERR_ARGUMENT &&
          tps_crypto_response_verify(
              response_key, response_transcript, NULL) ==
              TPS_CRYPTO_ERR_ARGUMENT,
          "response-authentication arguments fail closed");

    CHECK(tps_crypto_opening_state_new(
              0u, opening_key, invitation_id, guest_nonce,
              &invalid_opening_state) == TPS_CRYPTO_ERR_ARGUMENT &&
          invalid_opening_state == NULL &&
          tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_HOST, NULL,
              invitation_id, guest_nonce,
              &invalid_opening_state) == TPS_CRYPTO_ERR_ARGUMENT &&
          invalid_opening_state == NULL &&
          tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_HOST, opening_key,
              NULL, guest_nonce,
              &invalid_opening_state) == TPS_CRYPTO_ERR_ARGUMENT &&
          invalid_opening_state == NULL &&
          tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_HOST, opening_key,
              invitation_id, NULL,
              &invalid_opening_state) == TPS_CRYPTO_ERR_ARGUMENT &&
          invalid_opening_state == NULL &&
          tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_HOST, opening_key,
              invitation_id, guest_nonce, NULL) ==
              TPS_CRYPTO_ERR_ARGUMENT &&
          tps_crypto_opening_state_is_ready(NULL) ==
              TPS_CRYPTO_ERR_ARGUMENT &&
          tps_crypto_opening_state_next(NULL, opening_packet) ==
              TPS_CRYPTO_ERR_ARGUMENT &&
          tps_crypto_opening_state_receive(
              NULL, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_ERR_ARGUMENT,
          "simultaneous-opening constructor and state arguments fail closed");

    CHECK(new_opening_pair(
              &opening, opening_key, invitation_id, guest_nonce) &&
          complete_opening(&opening),
          "authenticated simultaneous-opening states converge in four packets");
    free_opening_pair(&opening);

    CHECK(new_opening_pair(
              &opening, opening_key, invitation_id, guest_nonce) &&
          tps_crypto_opening_state_next(
              opening.host, original_opening_packet) == TPS_CRYPTO_OK &&
          memcmp(original_opening_packet, "TPSO", 4u) == 0 &&
          original_opening_packet[4] == 1u &&
          original_opening_packet[5] == 1u &&
          original_opening_packet[6] == TPS_CRYPTO_OPENING_ROLE_HOST &&
          original_opening_packet[7] == 0u &&
          memcmp(original_opening_packet + 8,
                 invitation_id, sizeof invitation_id) == 0 &&
          memcmp(original_opening_packet + 24,
                 guest_nonce, sizeof guest_nonce) == 0 &&
          original_opening_packet[72] == 0u &&
          original_opening_packet[73] == 0u &&
          original_opening_packet[74] == 0u &&
          original_opening_packet[75] == 1u,
          "opening packet has exact v1 header, identifiers, role, flags, and counter");
    all_zero = 1;
    for (index = 40u; index < 56u; ++index)
        all_zero &= original_opening_packet[index] == 0u;
    CHECK(!all_zero, "opening challenge comes from the operating-system CSPRNG");
    all_zero = 1;
    for (index = 56u; index < 72u; ++index)
        all_zero &= original_opening_packet[index] == 0u;
    CHECK(all_zero, "first opening packet has no challenge echo");
    for (mutation_index = 0;
            mutation_index < TPS_CRYPTO_OPENING_PACKET_BYTES;
            ++mutation_index) {
        CHECK(tps_crypto_opening_state_receive(
                  opening.guest, original_opening_packet, mutation_index) ==
                  TPS_CRYPTO_ERR_PROTOCOL,
              "every truncated opening packet is rejected without state change");
    }
    CHECK(tps_crypto_opening_state_receive(
              opening.guest, NULL, sizeof original_opening_packet) ==
              TPS_CRYPTO_ERR_ARGUMENT &&
          tps_crypto_opening_state_next(opening.host, NULL) ==
              TPS_CRYPTO_ERR_ARGUMENT,
          "opening packet pointers are required");
    for (mutation_index = 0;
            mutation_index < TPS_CRYPTO_OPENING_PACKET_BYTES;
            ++mutation_index) {
        memcpy(mutated_opening_packet, original_opening_packet,
               sizeof mutated_opening_packet);
        mutated_opening_packet[mutation_index] ^= 1u;
        CHECK(tps_crypto_opening_state_receive(
                  opening.guest, mutated_opening_packet,
                  sizeof mutated_opening_packet) != TPS_CRYPTO_OK,
              "every opening header, role, flag, id, nonce, challenge, echo, counter, and tag byte is authenticated");
    }
    CHECK(tps_crypto_opening_state_receive(
              opening.guest, original_opening_packet,
              sizeof original_opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, original_opening_packet,
              sizeof original_opening_packet) == TPS_CRYPTO_ERR_REPLAY &&
          tps_crypto_opening_state_is_ready(opening.guest) == 0,
          "failed mutations are immutable and exact replay is rejected");
    free_opening_pair(&opening);

    CHECK(new_opening_pair(
              &opening, opening_key, invitation_id, guest_nonce) &&
          tps_crypto_opening_state_next(
              opening.host, original_opening_packet) == TPS_CRYPTO_OK,
          "tag-failed provisional-state fixture creates a current packet");
    memcpy(mutated_opening_packet, original_opening_packet,
           sizeof mutated_opening_packet);
    mutated_opening_packet[TPS_CRYPTO_OPENING_PACKET_BYTES - 1u] ^= 1u;
    CHECK(tps_crypto_opening_state_receive(
              opening.guest, mutated_opening_packet,
              sizeof mutated_opening_packet) == TPS_CRYPTO_ERR_AUTH &&
          tps_crypto_opening_state_next(
              opening.guest, opening_packet) == TPS_CRYPTO_OK &&
          opening_packet[7] == 0u,
          "tag-failed packet cannot install a provisional echo candidate");
    free_opening_pair(&opening);

    CHECK(tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_HOST, opening_key,
              invitation_id, guest_nonce, &opening.host) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, original_opening_packet) == TPS_CRYPTO_OK,
          "cross-state replay fixture captures pair-A host counter one");
    tps_crypto_opening_state_free(opening.host);
    opening.host = NULL;
    CHECK(new_opening_pair(
              &opening, opening_key, invitation_id, guest_nonce) &&
          tps_crypto_opening_state_receive(
              opening.guest, original_opening_packet,
              sizeof original_opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, original_opening_packet,
              sizeof original_opening_packet) == TPS_CRYPTO_ERR_REPLAY &&
          tps_crypto_opening_state_next(
              opening.guest, opening_packets[0]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.host, opening_packets[0],
              sizeof opening_packets[0]) == TPS_CRYPTO_ERR_PROTOCOL &&
          tps_crypto_opening_state_next(
              opening.host, opening_packets[1]) == TPS_CRYPTO_OK &&
          opening_packets[1][72] == original_opening_packet[72] &&
          opening_packets[1][73] == original_opening_packet[73] &&
          opening_packets[1][74] == original_opening_packet[74] &&
          opening_packets[1][75] == original_opening_packet[75] &&
          memcmp(opening_packets[1] + 40,
                 original_opening_packet + 40,
                 TPS_CRYPTO_OPENING_CHALLENGE_BYTES) != 0 &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packets[1],
              sizeof opening_packets[1]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packets[1],
              sizeof opening_packets[1]) == TPS_CRYPTO_ERR_REPLAY &&
          tps_crypto_opening_state_next(
              opening.guest, opening_packets[2]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.host, opening_packets[2],
              sizeof opening_packets[2]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_is_ready(opening.guest) == 1 &&
          tps_crypto_opening_state_next(
              opening.guest, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.host, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_is_ready(opening.host) == 1,
          "pair-A replay stays provisional, pair-B same-counter challenge replaces it, and pair B converges");
    free_opening_pair(&opening);

    CHECK(tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_HOST, opening_key,
              invitation_id, guest_nonce, &opening.host) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_GUEST, wrong_opening_key,
              invitation_id, guest_nonce, &opening.guest) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_ERR_AUTH,
          "wrong opening key fails packet authentication");
    free_opening_pair(&opening);

    CHECK(tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_HOST, opening_key,
              invitation_id, guest_nonce, &opening.host) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_GUEST, opening_key,
              other_invitation_id, guest_nonce, &opening.guest) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_ERR_PROTOCOL,
          "opening invitation id is bound before state mutation");
    free_opening_pair(&opening);
    CHECK(tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_HOST, opening_key,
              invitation_id, guest_nonce, &opening.host) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_GUEST, opening_key,
              invitation_id, other_guest_nonce, &opening.guest) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_ERR_PROTOCOL,
          "opening guest nonce is bound before state mutation");
    free_opening_pair(&opening);

    CHECK(new_opening_pair(
              &opening, opening_key, invitation_id, guest_nonce) &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.guest, opening_packets[0]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.host, opening_packets[0],
              sizeof opening_packets[0]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packets[1]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packets[1],
              sizeof opening_packets[1]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_new(
              TPS_CRYPTO_OPENING_ROLE_HOST, opening_key,
              invitation_id, guest_nonce, &opening_aux.host) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening_aux.host, mutated_opening_packet) == TPS_CRYPTO_OK &&
          memcmp(opening_packet + 40, mutated_opening_packet + 40,
                 TPS_CRYPTO_OPENING_CHALLENGE_BYTES) != 0 &&
          tps_crypto_opening_state_receive(
              opening.guest, mutated_opening_packet,
              sizeof mutated_opening_packet) == TPS_CRYPTO_ERR_PROTOCOL,
          "freshness-proven peer challenge is pinned against replacement");
    free_opening_pair(&opening);
    free_opening_pair(&opening_aux);

    CHECK(new_opening_pair(
              &opening, opening_key, invitation_id, guest_nonce) &&
          new_opening_pair(
              &opening_aux, opening_key, invitation_id, guest_nonce) &&
          tps_crypto_opening_state_next(
              opening.host, original_opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, original_opening_packet,
              sizeof original_opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.guest, opening_packets[0]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening_aux.guest, opening_packets[1]) == TPS_CRYPTO_OK &&
          memcmp(opening_packets[0] + 40, opening_packets[1] + 40,
                 TPS_CRYPTO_OPENING_CHALLENGE_BYTES) != 0 &&
          tps_crypto_opening_state_receive(
              opening.host, opening_packets[1],
              sizeof opening_packets[1]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, mutated_opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, mutated_opening_packet,
              sizeof mutated_opening_packet) == TPS_CRYPTO_ERR_PROTOCOL &&
          tps_crypto_opening_state_is_ready(opening.guest) == 0,
          "authenticated but incorrect challenge echo cannot verify a peer");
    free_opening_pair(&opening);
    free_opening_pair(&opening_aux);

    CHECK(new_opening_pair(
              &opening, opening_key, invitation_id, guest_nonce) &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.guest, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.host, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packets[0]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packets[1]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packets[2]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packets[2],
              sizeof opening_packets[2]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packets[0],
              sizeof opening_packets[0]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packets[1],
              sizeof opening_packets[1]) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packets[0],
              sizeof opening_packets[0]) == TPS_CRYPTO_ERR_REPLAY,
          "opening replay window accepts authenticated bounded reordering once");
    free_opening_pair(&opening);

    CHECK(new_opening_pair(
              &opening, opening_key, invitation_id, guest_nonce) &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.guest, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.host, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK &&
          tps_crypto_opening_state_next(
              opening.host, original_opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, original_opening_packet,
              sizeof original_opening_packet) == TPS_CRYPTO_OK,
          "opening old-window fixture pins freshness before counter three");
    for (counter_index = 4u; counter_index <= 68u; ++counter_index) {
        CHECK(tps_crypto_opening_state_next(
                  opening.host, opening_packet) == TPS_CRYPTO_OK &&
              tps_crypto_opening_state_receive(
                  opening.guest, opening_packet, sizeof opening_packet) ==
                  TPS_CRYPTO_OK,
              "opening replay window advances over authenticated counters");
    }
    CHECK(tps_crypto_opening_state_receive(
              opening.guest, original_opening_packet,
              sizeof original_opening_packet) == TPS_CRYPTO_ERR_REPLAY &&
          tps_crypto_opening_state_next(
              opening.host, opening_packet) == TPS_CRYPTO_OK &&
          tps_crypto_opening_state_receive(
              opening.guest, opening_packet, sizeof opening_packet) ==
              TPS_CRYPTO_OK,
          "opening packet older than the 64-counter window is rejected without poisoning new traffic");
    free_opening_pair(&opening);

    memcpy(bridge_aad, "TPSB", 4u);
    bridge_aad[4] = 1u;
    bridge_aad[5] = 1u;
    bridge_aad[6] = TPS_CRYPTO_BRIDGE_ROLE_GUEST;
    memcpy(bridge_aad + 8u, invitation_id, sizeof invitation_id);
    bridge_aad[27] = 1u;
    bridge_aad[29] = 1u;
    bridge_aad[30] = 4u;
    bridge_aad[31] = 0x98u;
    memcpy(changed_bridge_aad, bridge_aad, sizeof bridge_aad);
    changed_bridge_aad[27] ^= 1u;
    for (index = 0; index < sizeof bridge_plaintext; ++index)
        bridge_plaintext[index] = (uint8_t) (index & 0xffu);

    CHECK(TPS_CRYPTO_BRIDGE_MAX_AAD_BYTES == 64u &&
          TPS_CRYPTO_BRIDGE_MAX_PLAINTEXT_BYTES == 1176u &&
          TPS_CRYPTO_BRIDGE_OVERHEAD_BYTES == 24u,
          "bridge ABI limits are pinned to the IPv6 minimum-MTU budget");
    CHECK(tps_crypto_bridge_state_new(
              0u, opening_key, invitation_id, guest_nonce,
              &bridge_host) == TPS_CRYPTO_ERR_ARGUMENT &&
          bridge_host == NULL &&
          tps_crypto_bridge_state_new(
              TPS_CRYPTO_BRIDGE_ROLE_HOST, NULL,
              invitation_id, guest_nonce,
              &bridge_host) == TPS_CRYPTO_ERR_ARGUMENT &&
          bridge_host == NULL,
          "bridge constructor arguments fail closed");
    CHECK(tps_crypto_bridge_state_new(
              TPS_CRYPTO_BRIDGE_ROLE_HOST, opening_key,
              invitation_id, guest_nonce, &bridge_host) == TPS_CRYPTO_OK &&
          tps_crypto_bridge_state_new(
              TPS_CRYPTO_BRIDGE_ROLE_GUEST, opening_key,
              invitation_id, guest_nonce, &bridge_guest) == TPS_CRYPTO_OK &&
          tps_crypto_bridge_state_new(
              TPS_CRYPTO_BRIDGE_ROLE_HOST, wrong_opening_key,
              invitation_id, guest_nonce, &bridge_wrong) == TPS_CRYPTO_OK,
          "direction-separated bridge states are created");
    CHECK(tps_crypto_bridge_state_seal(
              bridge_guest, bridge_aad, sizeof bridge_aad,
              bridge_plaintext, sizeof bridge_plaintext,
              bridge_wire, sizeof bridge_wire,
              &bridge_wire_len) == TPS_CRYPTO_OK &&
          bridge_wire_len == sizeof bridge_wire,
          "maximum bridge fragment fits one 1200-byte authenticated body");
    memcpy(bridge_tampered, bridge_wire, bridge_wire_len);
    bridge_tampered[bridge_wire_len - 1u] ^= 1u;
    bridge_opened_len = 99u;
    CHECK(tps_crypto_bridge_state_open(
              bridge_host, bridge_aad, sizeof bridge_aad,
              bridge_tampered, bridge_wire_len,
              bridge_opened, sizeof bridge_opened,
              &bridge_opened_len) == TPS_CRYPTO_ERR_AUTH &&
          bridge_opened_len == 0u,
          "bridge fragment tampering is rejected without plaintext");
    bridge_opened_len = 99u;
    CHECK(tps_crypto_bridge_state_open(
              bridge_host, changed_bridge_aad, sizeof changed_bridge_aad,
              bridge_wire, bridge_wire_len,
              bridge_opened, sizeof bridge_opened,
              &bridge_opened_len) == TPS_CRYPTO_ERR_AUTH &&
          bridge_opened_len == 0u &&
          tps_crypto_bridge_state_open(
              bridge_wrong, bridge_aad, sizeof bridge_aad,
              bridge_wire, bridge_wire_len,
              bridge_opened, sizeof bridge_opened,
              &bridge_opened_len) == TPS_CRYPTO_ERR_AUTH,
          "bridge metadata and session key are authenticated");
    CHECK(tps_crypto_bridge_state_open(
              bridge_host, bridge_aad, sizeof bridge_aad,
              bridge_wire, bridge_wire_len,
              bridge_opened, sizeof bridge_opened,
              &bridge_opened_len) == TPS_CRYPTO_OK &&
          bridge_opened_len == sizeof bridge_plaintext &&
          memcmp(bridge_opened, bridge_plaintext,
                 sizeof bridge_plaintext) == 0 &&
          tps_crypto_bridge_state_open(
              bridge_host, bridge_aad, sizeof bridge_aad,
              bridge_wire, bridge_wire_len,
              bridge_opened, sizeof bridge_opened,
              &bridge_opened_len) == TPS_CRYPTO_ERR_REPLAY,
          "bridge authentication failures do not consume valid traffic and replay is rejected");
    tps_crypto_bridge_state_free(bridge_host);
    tps_crypto_bridge_state_free(bridge_guest);
    tps_crypto_bridge_state_free(bridge_wrong);
    bridge_host = NULL;
    bridge_guest = NULL;
    bridge_wrong = NULL;

    CHECK(complete_handshake(&pair, key, key),
          "four-flight mutually confirmed authenticated handshake");
    CHECK(tps_crypto_state_start(pair.initiator,
              ciphertext[0], sizeof ciphertext[0], &ciphertext_len[0]) ==
              TPS_CRYPTO_ERR_STATE,
          "handshake cannot restart");

    CHECK(seal_message(pair.initiator, 1,
              aad_channel_1, sizeof aad_channel_1, "client-to-host",
              ciphertext[0], sizeof ciphertext[0], &ciphertext_len[0]),
          "seal client-to-host");
    CHECK(ciphertext_len[0] == strlen("client-to-host") +
              TPS_CRYPTO_DATA_OVERHEAD_BYTES,
          "data frame overhead");
    CHECK(open_message(pair.responder, 1,
              aad_channel_1, sizeof aad_channel_1,
              ciphertext[0], ciphertext_len[0], "client-to-host"),
          "open client-to-host");
    CHECK(tps_crypto_state_open(pair.responder, 1,
              aad_channel_1, sizeof aad_channel_1,
              ciphertext[0], ciphertext_len[0],
              tampered, sizeof tampered, &ciphertext_len[7]) ==
              TPS_CRYPTO_ERR_REPLAY,
          "exact replay rejected");

    CHECK(seal_message(pair.responder, 2,
              aad_channel_2, sizeof aad_channel_2, "host-to-client",
              ciphertext[0], sizeof ciphertext[0], &ciphertext_len[0]) &&
          open_message(pair.initiator, 2,
              aad_channel_2, sizeof aad_channel_2,
              ciphertext[0], ciphertext_len[0], "host-to-client"),
          "direction-separated reverse traffic");

    CHECK(seal_message(pair.initiator, 2,
              aad_channel_2, sizeof aad_channel_2, "zero",
              ciphertext[0], sizeof ciphertext[0], &ciphertext_len[0]) &&
          seal_message(pair.initiator, 2,
              aad_channel_2, sizeof aad_channel_2, "one",
              ciphertext[1], sizeof ciphertext[1], &ciphertext_len[1]) &&
          seal_message(pair.initiator, 2,
              aad_channel_2, sizeof aad_channel_2, "two",
              ciphertext[2], sizeof ciphertext[2], &ciphertext_len[2]),
          "seal out-of-order replay-window fixtures");
    CHECK(open_message(pair.responder, 2,
              aad_channel_2, sizeof aad_channel_2,
              ciphertext[2], ciphertext_len[2], "two") &&
          open_message(pair.responder, 2,
              aad_channel_2, sizeof aad_channel_2,
              ciphertext[0], ciphertext_len[0], "zero") &&
          open_message(pair.responder, 2,
              aad_channel_2, sizeof aad_channel_2,
              ciphertext[1], ciphertext_len[1], "one"),
          "authenticated out-of-order packets inside window accepted");

    CHECK(seal_message(pair.initiator, 1,
              aad_channel_1, sizeof aad_channel_1, "tamper-retry",
              ciphertext[3], sizeof ciphertext[3], &ciphertext_len[3]),
          "seal tamper fixture");
    memcpy(tampered, ciphertext[3], ciphertext_len[3]);
    tampered[ciphertext_len[3] - 1] ^= 1;
    ciphertext_len[7] = 99;
    CHECK(tps_crypto_state_open(pair.responder, 1,
              aad_channel_1, sizeof aad_channel_1,
              tampered, ciphertext_len[3],
              ciphertext[4], sizeof ciphertext[4], &ciphertext_len[7]) ==
              TPS_CRYPTO_ERR_AUTH && ciphertext_len[7] == 0,
          "tamper rejected without plaintext");
    CHECK(open_message(pair.responder, 1,
              aad_channel_1, sizeof aad_channel_1,
              ciphertext[3], ciphertext_len[3], "tamper-retry"),
          "failed authentication does not consume replay sequence");

    CHECK(seal_message(pair.initiator, 1,
              aad_channel_1, sizeof aad_channel_1, "channel-bound",
              ciphertext[4], sizeof ciphertext[4], &ciphertext_len[4]),
          "seal channel-bound fixture");
    wrong_channel_result = tps_crypto_state_open(pair.responder, 3,
        aad_channel_3, sizeof aad_channel_3,
        ciphertext[4], ciphertext_len[4],
        tampered, sizeof tampered, &ciphertext_len[7]);
    CHECK(wrong_channel_result == TPS_CRYPTO_ERR_AUTH,
          "fresh wrong channel and AAD fail authentication");
    CHECK(open_message(pair.responder, 1,
              aad_channel_1, sizeof aad_channel_1,
              ciphertext[4], ciphertext_len[4], "channel-bound"),
          "wrong-channel failure does not consume correct-channel sequence");

    CHECK(seal_message(pair.initiator, 1,
              aad_channel_1, sizeof aad_channel_1, "reserved-sequence",
              ciphertext[5], sizeof ciphertext[5], &ciphertext_len[5]),
          "seal reserved-sequence rejection fixture");
    memcpy(tampered, ciphertext[5], ciphertext_len[5]);
    memset(tampered, 0xff, 8);
    ciphertext_len[7] = 99;
    CHECK(tps_crypto_state_open(pair.responder, 1,
              aad_channel_1, sizeof aad_channel_1,
              tampered, ciphertext_len[5],
              ciphertext[6], sizeof ciphertext[6], &ciphertext_len[7]) ==
              TPS_CRYPTO_ERR_EXHAUSTED && ciphertext_len[7] == 0,
          "reserved maximum receive sequence rejected before authentication");

    CHECK(tps_crypto_state_new(TPS_CRYPTO_ROLE_INITIATOR,
              key, &wrong_pair.initiator) == TPS_CRYPTO_OK &&
          tps_crypto_state_new(TPS_CRYPTO_ROLE_RESPONDER,
              wrong_key, &wrong_pair.responder) == TPS_CRYPTO_OK,
          "wrong-key fixture state creation");
    ciphertext_len[0] = ciphertext_len[1] = 0;
    CHECK(tps_crypto_state_start(wrong_pair.responder,
              NULL, 0, &ciphertext_len[1]) == TPS_CRYPTO_OK &&
          tps_crypto_state_start(wrong_pair.initiator,
              ciphertext[0], sizeof ciphertext[0], &ciphertext_len[0]) ==
              TPS_CRYPTO_OK,
          "wrong-key fixture first flight");
    CHECK(tps_crypto_state_handshake(wrong_pair.responder,
              ciphertext[0], ciphertext_len[0],
              ciphertext[1], sizeof ciphertext[1], &ciphertext_len[1]) ==
              TPS_CRYPTO_ERR_AUTH,
          "wrong invitation key rejected");

    CHECK(fixture_to_finish(&fixture, key, key),
          "tampered-finish fixture reaches confirmation flight");
    memcpy(tampered, fixture.finish, fixture.finish_len);
    tampered[fixture.finish_len - 1u] ^= 1u;
    negative_output_len = 99;
    negative_result = tps_crypto_state_handshake(fixture.pair.responder,
        tampered, fixture.finish_len,
        negative_output, sizeof negative_output, &negative_output_len);
    CHECK(negative_result == TPS_CRYPTO_ERR_AUTH && negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.responder) == 0 &&
              tps_crypto_state_is_ready(fixture.pair.initiator) == 0,
          "tampered finish fails closed without acknowledgement output");
    negative_output_len = 99;
    CHECK(tps_crypto_state_handshake(fixture.pair.responder,
              fixture.finish, fixture.finish_len,
              negative_output, sizeof negative_output, &negative_output_len) ==
              TPS_CRYPTO_ERR_STATE && negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.responder) == 0,
          "tampered finish permanently fails the responder state");
    free_fixture(&fixture);

    CHECK(fixture_to_finish(&fixture, key, key),
          "truncated-finish fixture reaches confirmation flight");
    negative_output_len = 99;
    negative_result = tps_crypto_state_handshake(fixture.pair.responder,
        fixture.finish, fixture.finish_len - 1u,
        negative_output, sizeof negative_output, &negative_output_len);
    CHECK(negative_result == TPS_CRYPTO_ERR_PROTOCOL && negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.responder) == 0 &&
              tps_crypto_state_is_ready(fixture.pair.initiator) == 0,
          "truncated finish fails closed without acknowledgement output");
    negative_output_len = 99;
    CHECK(tps_crypto_state_handshake(fixture.pair.responder,
              fixture.finish, fixture.finish_len,
              negative_output, sizeof negative_output, &negative_output_len) ==
              TPS_CRYPTO_ERR_STATE && negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.responder) == 0,
          "truncated finish permanently fails the responder state");
    free_fixture(&fixture);

    CHECK(fixture_to_finish(&fixture, key, key),
          "duplicate-first-flight fixture reaches confirmation flight");
    negative_output_len = 99;
    negative_result = tps_crypto_state_handshake(fixture.pair.responder,
        fixture.flight_1, fixture.flight_1_len,
        negative_output, sizeof negative_output, &negative_output_len);
    CHECK(negative_result == TPS_CRYPTO_ERR_PROTOCOL && negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.responder) == 0 &&
              tps_crypto_state_is_ready(fixture.pair.initiator) == 0,
          "same-state first-flight replay fails closed");
    negative_output_len = 99;
    CHECK(tps_crypto_state_handshake(fixture.pair.responder,
              fixture.finish, fixture.finish_len,
              negative_output, sizeof negative_output, &negative_output_len) ==
              TPS_CRYPTO_ERR_STATE && negative_output_len == 0,
          "same-state first-flight replay cannot continue with the finish");
    free_fixture(&fixture);

    CHECK(fixture_to_finish(&fixture, key, key) &&
              fixture_accept_finish(&fixture),
          "duplicate-finish fixture accepts its first finish");
    negative_output_len = 99;
    negative_result = tps_crypto_state_handshake(fixture.pair.responder,
        fixture.finish, fixture.finish_len,
        negative_output, sizeof negative_output, &negative_output_len);
    CHECK(negative_result == TPS_CRYPTO_ERR_STATE && negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.responder) == 1 &&
              tps_crypto_state_is_ready(fixture.pair.initiator) == 0,
          "duplicate finish is rejected without a second acknowledgement");
    free_fixture(&fixture);

    CHECK(fixture_to_finish(&fixture, key, key) &&
              fixture_accept_finish(&fixture),
          "tampered-ack fixture reaches acknowledgement flight");
    memcpy(tampered, fixture.ack, fixture.ack_len);
    tampered[fixture.ack_len - 1u] ^= 1u;
    negative_output_len = 99;
    negative_result = tps_crypto_state_handshake(fixture.pair.initiator,
        tampered, fixture.ack_len,
        NULL, 0, &negative_output_len);
    CHECK(negative_result == TPS_CRYPTO_ERR_AUTH && negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.initiator) == 0 &&
              tps_crypto_state_is_ready(fixture.pair.responder) == 1,
          "tampered acknowledgement fails the initiator closed");
    negative_output_len = 99;
    CHECK(tps_crypto_state_handshake(fixture.pair.initiator,
              fixture.ack, fixture.ack_len,
              NULL, 0, &negative_output_len) == TPS_CRYPTO_ERR_STATE &&
              negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.initiator) == 0,
          "tampered acknowledgement permanently fails the initiator state");
    free_fixture(&fixture);

    CHECK(fixture_to_finish(&fixture, key, key) &&
              fixture_accept_finish(&fixture),
          "truncated-ack fixture reaches acknowledgement flight");
    negative_output_len = 99;
    negative_result = tps_crypto_state_handshake(fixture.pair.initiator,
        fixture.ack, fixture.ack_len - 1u,
        NULL, 0, &negative_output_len);
    CHECK(negative_result == TPS_CRYPTO_ERR_PROTOCOL && negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.initiator) == 0 &&
              tps_crypto_state_is_ready(fixture.pair.responder) == 1,
          "truncated acknowledgement fails the initiator closed");
    negative_output_len = 99;
    CHECK(tps_crypto_state_handshake(fixture.pair.initiator,
              fixture.ack, fixture.ack_len,
              NULL, 0, &negative_output_len) == TPS_CRYPTO_ERR_STATE &&
              negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.initiator) == 0,
          "truncated acknowledgement permanently fails the initiator state");
    free_fixture(&fixture);

    CHECK(fixture_to_finish(&fixture, key, key) &&
              fixture_accept_finish(&fixture) && fixture_accept_ack(&fixture),
          "duplicate-ack fixture completes mutual confirmation");
    negative_output_len = 99;
    negative_result = tps_crypto_state_handshake(fixture.pair.initiator,
        fixture.ack, fixture.ack_len,
        NULL, 0, &negative_output_len);
    CHECK(negative_result == TPS_CRYPTO_ERR_STATE && negative_output_len == 0 &&
              tps_crypto_state_is_ready(fixture.pair.initiator) == 1 &&
              tps_crypto_state_is_ready(fixture.pair.responder) == 1,
          "duplicate acknowledgement is rejected without changing ready state");
    free_fixture(&fixture);

    CHECK(fixture_to_finish(&fixture, key, key),
          "cross-session finish-replay fixture reaches confirmation flight");
    negative_output_len = 99;
    CHECK(tps_crypto_state_new(TPS_CRYPTO_ROLE_RESPONDER,
              key, &replay_pair.responder) == TPS_CRYPTO_OK &&
          tps_crypto_state_start(replay_pair.responder,
              NULL, 0, &negative_output_len) == TPS_CRYPTO_OK &&
          negative_output_len == 0,
          "fresh responder accepts a replay-test connection");
    replay_flight_2_len = 99;
    CHECK(tps_crypto_state_handshake(replay_pair.responder,
              fixture.flight_1, fixture.flight_1_len,
              replay_flight_2, sizeof replay_flight_2,
              &replay_flight_2_len) == TPS_CRYPTO_OK &&
          replay_flight_2_len == 80 &&
          tps_crypto_state_is_ready(replay_pair.responder) == 0 &&
          memcmp(replay_flight_2, fixture.flight_2, replay_flight_2_len) != 0,
          "fresh responder accepts captured flight one but emits a fresh flight two");
    negative_output_len = 99;
    negative_result = tps_crypto_state_handshake(replay_pair.responder,
        fixture.finish, fixture.finish_len,
        negative_output, sizeof negative_output, &negative_output_len);
    CHECK(negative_result == TPS_CRYPTO_ERR_AUTH && negative_output_len == 0 &&
              tps_crypto_state_is_ready(replay_pair.responder) == 0,
          "old finish cannot authenticate a fresh responder transcript");
    negative_output_len = 99;
    CHECK(tps_crypto_state_handshake(replay_pair.responder,
              fixture.finish, fixture.finish_len,
              negative_output, sizeof negative_output, &negative_output_len) ==
              TPS_CRYPTO_ERR_STATE && negative_output_len == 0 &&
              tps_crypto_state_is_ready(replay_pair.responder) == 0,
          "old finish replay permanently fails the fresh responder state");
    free_pair(&replay_pair);
    free_fixture(&fixture);
    free_opening_pair(&opening);
    free_opening_pair(&opening_aux);
    tps_crypto_opening_state_free(invalid_opening_state);
    tps_crypto_bridge_state_free(bridge_host);
    tps_crypto_bridge_state_free(bridge_guest);
    tps_crypto_bridge_state_free(bridge_wrong);
    invalid_opening_state = NULL;

    negative_output_len = 99;
    CHECK(tps_crypto_state_new(TPS_CRYPTO_ROLE_RESPONDER,
              key, &replay_pair.responder) == TPS_CRYPTO_OK &&
          tps_crypto_state_start(replay_pair.responder,
              NULL, 0, &negative_output_len) == TPS_CRYPTO_OK &&
          negative_output_len == 0,
          "low-order public-input fixture creates a fresh responder");
    negative_output_len = 99;
    negative_result = tps_crypto_state_handshake(replay_pair.responder,
        low_order_flight_1, sizeof low_order_flight_1,
        negative_output, sizeof negative_output, &negative_output_len);
    CHECK(negative_result == TPS_CRYPTO_ERR_AUTH && negative_output_len == 0 &&
              tps_crypto_state_is_ready(replay_pair.responder) == 0,
          "non-zero low-order X25519 input is rejected without flight-two output");
    negative_output_len = 99;
    CHECK(tps_crypto_state_handshake(replay_pair.responder,
              low_order_flight_1, sizeof low_order_flight_1,
              negative_output, sizeof negative_output, &negative_output_len) ==
              TPS_CRYPTO_ERR_STATE && negative_output_len == 0 &&
              tps_crypto_state_is_ready(replay_pair.responder) == 0,
          "low-order X25519 rejection permanently fails responder state");
    free_pair(&replay_pair);

    result = EXIT_SUCCESS;
    puts("TPS_NATIVE_CRYPTO_OK");

cleanup:
    free_pair(&pair);
    free_pair(&wrong_pair);
    free_pair(&replay_pair);
    free_fixture(&fixture);
    free_opening_pair(&opening);
    free_opening_pair(&opening_aux);
    tps_crypto_opening_state_free(invalid_opening_state);
    tps_crypto_bridge_state_free(bridge_host);
    tps_crypto_bridge_state_free(bridge_guest);
    tps_crypto_bridge_state_free(bridge_wrong);
    memset(key, 0, sizeof key);
    memset(wrong_key, 0, sizeof wrong_key);
    memset(random_bytes, 0, sizeof random_bytes);
    memset(ciphertext, 0, sizeof ciphertext);
    memset(tampered, 0, sizeof tampered);
    memset(negative_output, 0, sizeof negative_output);
    memset(replay_flight_2, 0, sizeof replay_flight_2);
    memset(response_key, 0, sizeof response_key);
    memset(response_transcript, 0, sizeof response_transcript);
    memset(response_tag, 0, sizeof response_tag);
    memset(expected_response_tag, 0, sizeof expected_response_tag);
    memset(altered_response_tag, 0, sizeof altered_response_tag);
    memset(opening_key, 0, sizeof opening_key);
    memset(wrong_opening_key, 0, sizeof wrong_opening_key);
    memset(invitation_id, 0, sizeof invitation_id);
    memset(other_invitation_id, 0, sizeof other_invitation_id);
    memset(guest_nonce, 0, sizeof guest_nonce);
    memset(other_guest_nonce, 0, sizeof other_guest_nonce);
    memset(opening_packet, 0, sizeof opening_packet);
    memset(original_opening_packet, 0, sizeof original_opening_packet);
    memset(mutated_opening_packet, 0, sizeof mutated_opening_packet);
    memset(opening_packets, 0, sizeof opening_packets);
    memset(bridge_aad, 0, sizeof bridge_aad);
    memset(changed_bridge_aad, 0, sizeof changed_bridge_aad);
    memset(bridge_plaintext, 0, sizeof bridge_plaintext);
    memset(bridge_wire, 0, sizeof bridge_wire);
    memset(bridge_opened, 0, sizeof bridge_opened);
    memset(bridge_tampered, 0, sizeof bridge_tampered);
    return result;
}
