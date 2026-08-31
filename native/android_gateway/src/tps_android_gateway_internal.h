#ifndef TPS_ANDROID_GATEWAY_INTERNAL_H
#define TPS_ANDROID_GATEWAY_INTERNAL_H

#include <stdint.h>

int32_t tps_android_gateway_publish_for_bridge(
    const char *source,
    const char *gateway,
    uint64_t network_handle);
void tps_android_gateway_clear_for_bridge(void);

#endif
