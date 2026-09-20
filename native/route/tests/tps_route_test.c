#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif

#include <winsock2.h>
#include <ws2tcpip.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "tps_route.h"

static int fail(const char *name)
{
    fprintf(stderr, "TPS_ROUTE_TEST_FAILURE=%s\n", name);
    return 1;
}

static int is_canonical_ipv4(const char *value)
{
    IN_ADDR parsed;
    char canonical[TPS_ROUTE_ADDRESS_BYTES];

    if (value == NULL || value[0] == '\0' ||
        strnlen(value, TPS_ROUTE_ADDRESS_BYTES) >= TPS_ROUTE_ADDRESS_BYTES) {
        return 0;
    }
    memset(&parsed, 0, sizeof(parsed));
    memset(canonical, 0, sizeof(canonical));
    if (InetPtonA(AF_INET, value, &parsed) != 1 ||
        InetNtopA(AF_INET, &parsed, canonical, sizeof(canonical)) == NULL) {
        return 0;
    }
    return strcmp(value, canonical) == 0;
}

static int known_result(int32_t result)
{
    return result == TPS_ROUTE_ERR_UNAVAILABLE ||
        result == TPS_ROUTE_ERR_NOT_DEFAULT ||
        result == TPS_ROUTE_ERR_NO_GATEWAY ||
        result == TPS_ROUTE_ERR_CHANGED ||
        result == TPS_ROUTE_ERR_FORMAT;
}

int main(int argc, char **argv)
{
    int require_live = 0;
    char source[TPS_ROUTE_ADDRESS_BYTES];
    char gateway[TPS_ROUTE_ADDRESS_BYTES];
    uint32_t interface_index = 99u;
    uint32_t generation_high = 99u;
    uint32_t generation_low = 99u;
    int32_t result;

    if (argc == 2 && strcmp(argv[1], "--require-live") == 0) {
        require_live = 1;
    } else if (argc != 1) {
        return fail("arguments");
    }
    if (tps_route_abi_version() != TPS_ROUTE_ABI_VERSION) {
        return fail("abi_version");
    }

    memset(source, 'x', sizeof(source));
    memset(gateway, 'y', sizeof(gateway));
    result = tps_route_default_ipv4(
        source, gateway, NULL, &generation_high, &generation_low);
    if (result != TPS_ROUTE_ERR_ARGUMENT ||
        source[0] != '\0' || gateway[0] != '\0' ||
        generation_high != 0u || generation_low != 0u) {
        return fail("null_output_contract");
    }

    memset(gateway, 'y', sizeof(gateway));
    interface_index = 99u;
    generation_high = 99u;
    generation_low = 99u;
    result = tps_route_default_ipv4(
        NULL, gateway, &interface_index, &generation_high, &generation_low);
    if (result != TPS_ROUTE_ERR_ARGUMENT || gateway[0] != '\0' ||
        interface_index != 0u || generation_high != 0u ||
        generation_low != 0u) {
        return fail("null_source_clears_other_outputs");
    }

    memset(source, 'x', sizeof(source));
    interface_index = 99u;
    generation_high = 99u;
    generation_low = 99u;
    result = tps_route_default_ipv4(
        source, NULL, &interface_index, &generation_high, &generation_low);
    if (result != TPS_ROUTE_ERR_ARGUMENT || source[0] != '\0' ||
        interface_index != 0u || generation_high != 0u ||
        generation_low != 0u) {
        return fail("null_gateway_clears_other_outputs");
    }

    memset(source, 'x', sizeof(source));
    memset(gateway, 'y', sizeof(gateway));
    interface_index = 99u;
    generation_low = 99u;
    result = tps_route_default_ipv4(
        source, gateway, &interface_index, NULL, &generation_low);
    if (result != TPS_ROUTE_ERR_ARGUMENT || source[0] != '\0' ||
        gateway[0] != '\0' || interface_index != 0u ||
        generation_low != 0u) {
        return fail("null_generation_clears_other_outputs");
    }

    memset(source, 'x', sizeof(source));
    memset(gateway, 'y', sizeof(gateway));
    interface_index = 99u;
    generation_high = 99u;
    generation_low = 99u;
    result = tps_route_default_ipv4(
        source, gateway, &interface_index, &generation_high, &generation_low);
    if (result != TPS_ROUTE_OK) {
        if (!known_result(result)) {
            return fail("bounded_error_contract");
        }
        if (source[0] != '\0' || gateway[0] != '\0' ||
            interface_index != 0u || generation_high != 0u ||
            generation_low != 0u) {
            return fail("failure_did_not_clear_outputs");
        }
        puts("TPS_ROUTE_NATIVE=UNAVAILABLE");
        if (require_live) {
            return fail("live_default_route_required");
        }
        return 0;
    }

    if (interface_index == 0u ||
        (generation_high == 0u && generation_low == 0u) ||
        !is_canonical_ipv4(source) ||
        !is_canonical_ipv4(gateway) ||
        strcmp(source, gateway) == 0) {
        return fail("live_result_contract");
    }

    puts("TPS_ROUTE_NATIVE=PASS");
    puts("TPS_ROUTE_LIVE=PASS");
    puts("SOURCE_CANONICAL=True");
    puts("GATEWAY_CANONICAL=True");
    puts("INTERFACE_INDEX_PRESENT=True");
    puts("NETWORK_GENERATION_PRESENT=True");
    puts("NETWORK_TRAFFIC_SENT=False");
    return 0;
}
