#ifndef TPS_ROUTE_H
#define TPS_ROUTE_H

#include <stdint.h>

#if defined(_WIN32)
#define TPS_ROUTE_API __declspec(dllexport)
#else
#define TPS_ROUTE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define TPS_ROUTE_ABI_VERSION 2u
#define TPS_ROUTE_ADDRESS_BYTES 16u

#define TPS_ROUTE_OK 0
#define TPS_ROUTE_ERR_ARGUMENT -1
#define TPS_ROUTE_ERR_UNAVAILABLE -2
#define TPS_ROUTE_ERR_NOT_DEFAULT -3
#define TPS_ROUTE_ERR_NO_GATEWAY -4
#define TPS_ROUTE_ERR_CHANGED -5
#define TPS_ROUTE_ERR_FORMAT -6

/*
 * This ABI is intentionally smaller than the Windows route structures it
 * wraps.  On success it returns one atomic IPv4 source/default-gateway pair
 * plus an opaque, process-local generation driven by Windows IPv4 route,
 * interface, and unicast-address notifications.  Outputs are cleared before
 * every failure and never contain system errors.
 */
TPS_ROUTE_API uint32_t tps_route_abi_version(void);
TPS_ROUTE_API int32_t tps_route_default_ipv4(
    char source[TPS_ROUTE_ADDRESS_BYTES],
    char gateway[TPS_ROUTE_ADDRESS_BYTES],
    uint32_t *interface_index,
    uint32_t *network_generation_high,
    uint32_t *network_generation_low);

#ifdef __cplusplus
}
#endif

#endif
