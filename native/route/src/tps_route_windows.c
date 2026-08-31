#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>

#include <stdint.h>
#include <string.h>

#include "tps_route.h"

static void clear_outputs(
    char *source, char *gateway, uint32_t *interface_index)
{
    if (source != NULL) {
        memset(source, 0, TPS_ROUTE_ADDRESS_BYTES);
    }
    if (gateway != NULL) {
        memset(gateway, 0, TPS_ROUTE_ADDRESS_BYTES);
    }
    if (interface_index != NULL) {
        *interface_index = 0u;
    }
}

static int legacy_is_default(const MIB_IPFORWARDROW *route)
{
    return route != NULL && route->dwForwardDest == 0u &&
        route->dwForwardMask == 0u && route->dwForwardIfIndex != 0u &&
        route->dwForwardType == MIB_IPROUTE_TYPE_INDIRECT;
}

static int same_legacy_route(
    const MIB_IPFORWARDROW *left, const MIB_IPFORWARDROW *right)
{
    return legacy_is_default(left) && legacy_is_default(right) &&
        left->dwForwardIfIndex == right->dwForwardIfIndex &&
        left->dwForwardNextHop == right->dwForwardNextHop;
}

uint32_t tps_route_abi_version(void)
{
    return TPS_ROUTE_ABI_VERSION;
}

int32_t tps_route_default_ipv4(
    char source[TPS_ROUTE_ADDRESS_BYTES],
    char gateway[TPS_ROUTE_ADDRESS_BYTES],
    uint32_t *interface_index)
{
    IN_ADDR destination;
    SOCKADDR_INET destination_socket;
    SOCKADDR_INET best_source;
    MIB_IPFORWARDROW first_route;
    MIB_IPFORWARDROW confirmed_route;
    MIB_IPFORWARD_ROW2 route;
    ULONG result;

    clear_outputs(source, gateway, interface_index);
    if (source == NULL || gateway == NULL || interface_index == NULL) {
        return TPS_ROUTE_ERR_ARGUMENT;
    }

    memset(&destination, 0, sizeof(destination));
    if (InetPtonA(AF_INET, "192.0.0.9", &destination) != 1) {
        return TPS_ROUTE_ERR_UNAVAILABLE;
    }

    memset(&first_route, 0, sizeof(first_route));
    result = GetBestRoute(destination.s_addr, 0u, &first_route);
    if (result != NO_ERROR) {
        return TPS_ROUTE_ERR_UNAVAILABLE;
    }
    if (!legacy_is_default(&first_route)) {
        return TPS_ROUTE_ERR_NOT_DEFAULT;
    }
    if (first_route.dwForwardNextHop == 0u) {
        return TPS_ROUTE_ERR_NO_GATEWAY;
    }

    memset(&destination_socket, 0, sizeof(destination_socket));
    destination_socket.Ipv4.sin_family = AF_INET;
    destination_socket.Ipv4.sin_addr = destination;
    memset(&best_source, 0, sizeof(best_source));
    memset(&route, 0, sizeof(route));
    result = GetBestRoute2(
        NULL,
        first_route.dwForwardIfIndex,
        NULL,
        &destination_socket,
        0u,
        &route,
        &best_source);
    if (result != NO_ERROR) {
        return TPS_ROUTE_ERR_UNAVAILABLE;
    }

    if (route.InterfaceIndex != first_route.dwForwardIfIndex ||
        route.DestinationPrefix.PrefixLength != 0u ||
        route.DestinationPrefix.Prefix.si_family != AF_INET ||
        route.DestinationPrefix.Prefix.Ipv4.sin_addr.s_addr != 0u ||
        route.NextHop.si_family != AF_INET ||
        best_source.si_family != AF_INET) {
        return TPS_ROUTE_ERR_NOT_DEFAULT;
    }
    if (route.NextHop.Ipv4.sin_addr.s_addr == 0u) {
        return TPS_ROUTE_ERR_NO_GATEWAY;
    }
    if (route.NextHop.Ipv4.sin_addr.s_addr != first_route.dwForwardNextHop ||
        best_source.Ipv4.sin_addr.s_addr == 0u ||
        best_source.Ipv4.sin_addr.s_addr == route.NextHop.Ipv4.sin_addr.s_addr) {
        return TPS_ROUTE_ERR_CHANGED;
    }

    memset(&confirmed_route, 0, sizeof(confirmed_route));
    result = GetBestRoute(
        destination.s_addr,
        best_source.Ipv4.sin_addr.s_addr,
        &confirmed_route);
    if (result != NO_ERROR ||
        !same_legacy_route(&first_route, &confirmed_route)) {
        return TPS_ROUTE_ERR_CHANGED;
    }

    if (InetNtopA(
            AF_INET,
            &best_source.Ipv4.sin_addr,
            source,
            TPS_ROUTE_ADDRESS_BYTES) == NULL ||
        InetNtopA(
            AF_INET,
            &route.NextHop.Ipv4.sin_addr,
            gateway,
            TPS_ROUTE_ADDRESS_BYTES) == NULL ||
        source[0] == '\0' || gateway[0] == '\0' ||
        strcmp(source, gateway) == 0) {
        clear_outputs(source, gateway, interface_index);
        return TPS_ROUTE_ERR_FORMAT;
    }

    *interface_index = route.InterfaceIndex;
    return TPS_ROUTE_OK;
}
