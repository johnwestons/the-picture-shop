#include "tps_android_gateway.h"
#include "tps_android_gateway_internal.h"

#include <stdint.h>
#include <string.h>

#if defined(TPS_ANDROID_GATEWAY_TEST_SINGLE_THREAD)
#define STATE_LOCK() ((void)0)
#define STATE_UNLOCK() ((void)0)
#elif defined(TPS_ANDROID_GATEWAY_TEST_WINDOWS_THREADS)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
static SRWLOCK state_mutex = SRWLOCK_INIT;
#define STATE_LOCK() ((void)AcquireSRWLockExclusive(&state_mutex))
#define STATE_UNLOCK() ((void)ReleaseSRWLockExclusive(&state_mutex))
#elif defined(__ANDROID__)
#include <pthread.h>
static pthread_mutex_t state_mutex = PTHREAD_MUTEX_INITIALIZER;
#define STATE_LOCK() ((void)pthread_mutex_lock(&state_mutex))
#define STATE_UNLOCK() ((void)pthread_mutex_unlock(&state_mutex))
#else
#error "The production state implementation is Android-only."
#endif

struct route_snapshot {
    char source[TPS_ANDROID_GATEWAY_ADDRESS_BYTES];
    char gateway[TPS_ANDROID_GATEWAY_ADDRESS_BYTES];
    uint64_t network_handle;
    uint32_t network_revision;
    int valid;
};

static struct route_snapshot state;

static void clear_outputs(
    char *source,
    char *gateway,
    uint32_t *network_handle_high,
    uint32_t *network_handle_low,
    uint32_t *network_revision)
{
    if (source != NULL) {
        memset(source, 0, TPS_ANDROID_GATEWAY_ADDRESS_BYTES);
    }
    if (gateway != NULL) {
        memset(gateway, 0, TPS_ANDROID_GATEWAY_ADDRESS_BYTES);
    }
    if (network_handle_high != NULL) {
        *network_handle_high = 0u;
    }
    if (network_handle_low != NULL) {
        *network_handle_low = 0u;
    }
    if (network_revision != NULL) {
        *network_revision = 0u;
    }
}

static uint32_t next_revision(uint32_t current)
{
    current++;
    return current == 0u ? 1u : current;
}

static int parse_canonical_ipv4(const char *text, uint8_t octets[4])
{
    uint32_t value = 0u;
    unsigned int octet = 0u;
    unsigned int digits = 0u;
    size_t index;

    if (text == NULL || octets == NULL) {
        return 0;
    }
    for (index = 0u; index < TPS_ANDROID_GATEWAY_ADDRESS_BYTES; index++) {
        unsigned char character = (unsigned char)text[index];
        if (character >= (unsigned char)'0' && character <= (unsigned char)'9') {
            if (digits == 0u) {
                value = 0u;
            } else if (digits == 1u && value == 0u) {
                return 0;
            }
            digits++;
            if (digits > 3u) {
                return 0;
            }
            value = value * 10u + (uint32_t)(character - (unsigned char)'0');
            if (value > 255u) {
                return 0;
            }
        } else if (character == (unsigned char)'.') {
            if (digits == 0u || octet >= 3u) {
                return 0;
            }
            octets[octet++] = (uint8_t)value;
            digits = 0u;
            value = 0u;
        } else if (character == 0u) {
            if (digits == 0u || octet != 3u) {
                return 0;
            }
            octets[octet] = (uint8_t)value;
            return 1;
        } else {
            return 0;
        }
    }
    return 0;
}

static int usable_unicast(const uint8_t octets[4])
{
    if (octets[0] == 0u || octets[0] == 127u || octets[0] >= 224u) {
        return 0;
    }
    if ((octets[0] == 192u && octets[1] == 0u && octets[2] == 2u) ||
        (octets[0] == 198u && octets[1] == 51u && octets[2] == 100u) ||
        (octets[0] == 203u && octets[1] == 0u && octets[2] == 113u)) {
        return 0;
    }
    return 1;
}

static int same_address(const uint8_t left[4], const uint8_t right[4])
{
    return memcmp(left, right, 4u) == 0;
}

uint32_t tps_android_gateway_abi_version(void)
{
    return TPS_ANDROID_GATEWAY_ABI_VERSION;
}

int32_t tps_android_gateway_default_ipv4(
    char source[TPS_ANDROID_GATEWAY_ADDRESS_BYTES],
    char gateway[TPS_ANDROID_GATEWAY_ADDRESS_BYTES],
    uint32_t *network_handle_high,
    uint32_t *network_handle_low,
    uint32_t *network_revision)
{
    clear_outputs(
        source,
        gateway,
        network_handle_high,
        network_handle_low,
        network_revision);
    if (source == NULL || gateway == NULL || network_handle_high == NULL ||
        network_handle_low == NULL || network_revision == NULL) {
        return TPS_ANDROID_GATEWAY_ERR_ARGUMENT;
    }

    STATE_LOCK();
    if (!state.valid) {
        STATE_UNLOCK();
        return TPS_ANDROID_GATEWAY_ERR_UNAVAILABLE;
    }
    memcpy(source, state.source, TPS_ANDROID_GATEWAY_ADDRESS_BYTES);
    memcpy(gateway, state.gateway, TPS_ANDROID_GATEWAY_ADDRESS_BYTES);
    *network_handle_high = (uint32_t)(state.network_handle >> 32u);
    *network_handle_low = (uint32_t)(state.network_handle & UINT32_MAX);
    *network_revision = state.network_revision;
    STATE_UNLOCK();
    return TPS_ANDROID_GATEWAY_OK;
}

int32_t tps_android_gateway_publish_for_bridge(
    const char *source,
    const char *gateway,
    uint64_t network_handle)
{
    uint8_t source_octets[4];
    uint8_t gateway_octets[4];
    char source_copy[TPS_ANDROID_GATEWAY_ADDRESS_BYTES];
    char gateway_copy[TPS_ANDROID_GATEWAY_ADDRESS_BYTES];

    memset(source_copy, 0, sizeof(source_copy));
    memset(gateway_copy, 0, sizeof(gateway_copy));
    if (network_handle == 0u ||
        !parse_canonical_ipv4(source, source_octets) ||
        !parse_canonical_ipv4(gateway, gateway_octets) ||
        !usable_unicast(source_octets) || !usable_unicast(gateway_octets) ||
        same_address(source_octets, gateway_octets)) {
        tps_android_gateway_clear_for_bridge();
        return TPS_ANDROID_GATEWAY_ERR_FORMAT;
    }
    memcpy(source_copy, source, strlen(source) + 1u);
    memcpy(gateway_copy, gateway, strlen(gateway) + 1u);

    STATE_LOCK();
    if (state.valid && state.network_handle == network_handle &&
        memcmp(state.source, source_copy, sizeof(source_copy)) == 0 &&
        memcmp(state.gateway, gateway_copy, sizeof(gateway_copy)) == 0) {
        STATE_UNLOCK();
        return TPS_ANDROID_GATEWAY_OK;
    }
    memset(state.source, 0, sizeof(state.source));
    memset(state.gateway, 0, sizeof(state.gateway));
    memcpy(state.source, source_copy, sizeof(state.source));
    memcpy(state.gateway, gateway_copy, sizeof(state.gateway));
    state.network_handle = network_handle;
    state.network_revision = next_revision(state.network_revision);
    state.valid = 1;
    STATE_UNLOCK();
    return TPS_ANDROID_GATEWAY_OK;
}

void tps_android_gateway_clear_for_bridge(void)
{
    STATE_LOCK();
    if (state.valid) {
        memset(state.source, 0, sizeof(state.source));
        memset(state.gateway, 0, sizeof(state.gateway));
        state.network_handle = 0u;
        state.network_revision = next_revision(state.network_revision);
        state.valid = 0;
    }
    STATE_UNLOCK();
}
