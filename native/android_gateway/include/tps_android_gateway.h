#ifndef TPS_ANDROID_GATEWAY_H
#define TPS_ANDROID_GATEWAY_H

#include <stdint.h>

#if defined(_WIN32)
#define TPS_ANDROID_GATEWAY_API __declspec(dllexport)
#else
#define TPS_ANDROID_GATEWAY_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define TPS_ANDROID_GATEWAY_ABI_VERSION 2u
#define TPS_ANDROID_GATEWAY_ADDRESS_BYTES 16u

#define TPS_ANDROID_GATEWAY_OK 0
#define TPS_ANDROID_GATEWAY_ERR_ARGUMENT -1
#define TPS_ANDROID_GATEWAY_ERR_UNAVAILABLE -2
#define TPS_ANDROID_GATEWAY_ERR_FORMAT -3

/*
 * Returns one atomic, process-local snapshot published by Android's default
 * network callback. Every output is cleared on failure. The two handle words
 * preserve Android's opaque 64-bit Network handle without requiring callers
 * to perform a potentially lossy numeric conversion. network_revision is
 * nonzero on success and changes whenever the published route or exact
 * Network identity is invalidated or replaced; zero is never valid.
 */
TPS_ANDROID_GATEWAY_API uint32_t tps_android_gateway_abi_version(void);
TPS_ANDROID_GATEWAY_API int32_t tps_android_gateway_default_ipv4(
    char source[TPS_ANDROID_GATEWAY_ADDRESS_BYTES],
    char gateway[TPS_ANDROID_GATEWAY_ADDRESS_BYTES],
    uint32_t *network_handle_high,
    uint32_t *network_handle_low,
    uint32_t *network_revision);

#ifdef __cplusplus
}
#endif

#endif
