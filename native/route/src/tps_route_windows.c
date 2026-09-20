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

static INIT_ONCE notification_once = INIT_ONCE_STATIC_INIT;
static volatile LONG64 network_generation = 1;
static HANDLE route_notification = NULL;
static HANDLE interface_notification = NULL;
static HANDLE address_notification = NULL;

static void clear_outputs(
    char *source,
    char *gateway,
    uint32_t *interface_index,
    uint32_t *network_generation_high,
    uint32_t *network_generation_low)
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
    if (network_generation_high != NULL) {
        *network_generation_high = 0u;
    }
    if (network_generation_low != NULL) {
        *network_generation_low = 0u;
    }
}

static void advance_network_generation(MIB_NOTIFICATION_TYPE notification_type)
{
    if (notification_type != MibInitialNotification) {
        (void)InterlockedIncrement64(&network_generation);
    }
}

static VOID CALLBACK route_changed(
    PVOID context,
    PMIB_IPFORWARD_ROW2 row,
    MIB_NOTIFICATION_TYPE notification_type)
{
    (void)context;
    (void)row;
    advance_network_generation(notification_type);
}

static VOID CALLBACK interface_changed(
    PVOID context,
    PMIB_IPINTERFACE_ROW row,
    MIB_NOTIFICATION_TYPE notification_type)
{
    (void)context;
    (void)row;
    advance_network_generation(notification_type);
}

static VOID CALLBACK address_changed(
    PVOID context,
    PMIB_UNICASTIPADDRESS_ROW row,
    MIB_NOTIFICATION_TYPE notification_type)
{
    (void)context;
    (void)row;
    advance_network_generation(notification_type);
}

static void cancel_notification(HANDLE *handle)
{
    if (handle != NULL && *handle != NULL) {
        (void)CancelMibChangeNotify2(*handle);
        *handle = NULL;
    }
}

static BOOL CALLBACK initialize_notifications(
    PINIT_ONCE once,
    PVOID parameter,
    PVOID *context)
{
    ULONG result;

    (void)once;
    (void)parameter;
    (void)context;
    result = NotifyRouteChange2(
        AF_INET, route_changed, NULL, FALSE, &route_notification);
    if (result == NO_ERROR) {
        result = NotifyIpInterfaceChange(
            AF_INET, interface_changed, NULL, FALSE,
            &interface_notification);
    }
    if (result == NO_ERROR) {
        result = NotifyUnicastIpAddressChange(
            AF_INET, address_changed, NULL, FALSE, &address_notification);
    }
    if (result != NO_ERROR) {
        cancel_notification(&address_notification);
        cancel_notification(&interface_notification);
        cancel_notification(&route_notification);
        return FALSE;
    }
    return TRUE;
}

static int notifications_available(void)
{
    return InitOnceExecuteOnce(
        &notification_once, initialize_notifications, NULL, NULL) != FALSE;
}

static uint64_t read_network_generation(void)
{
    return (uint64_t)InterlockedCompareExchange64(
        &network_generation, 0, 0);
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

static int source_is_unique_on_interface(
    const SOCKADDR_INET *source, uint32_t interface_index)
{
    PMIB_UNICASTIPADDRESS_TABLE table = NULL;
    ULONG result;
    ULONG index;
    uint32_t matches = 0u;
    int selected_match = 0;

    if (source == NULL || source->si_family != AF_INET ||
        source->Ipv4.sin_addr.s_addr == 0u || interface_index == 0u) {
        return 0;
    }
    result = GetUnicastIpAddressTable(AF_INET, &table);
    if (result != NO_ERROR || table == NULL) {
        return 0;
    }
    for (index = 0u; index < table->NumEntries; ++index) {
        const MIB_UNICASTIPADDRESS_ROW *row = &table->Table[index];
        if (row->Address.si_family == AF_INET &&
            row->Address.Ipv4.sin_addr.s_addr ==
                source->Ipv4.sin_addr.s_addr) {
            ++matches;
            if (row->InterfaceIndex == interface_index) {
                selected_match = 1;
            }
        }
    }
    FreeMibTable(table);
    return matches == 1u && selected_match;
}

uint32_t tps_route_abi_version(void)
{
    return TPS_ROUTE_ABI_VERSION;
}

int32_t tps_route_default_ipv4(
    char source[TPS_ROUTE_ADDRESS_BYTES],
    char gateway[TPS_ROUTE_ADDRESS_BYTES],
    uint32_t *interface_index,
    uint32_t *network_generation_high,
    uint32_t *network_generation_low)
{
    IN_ADDR destination;
    SOCKADDR_INET destination_socket;
    SOCKADDR_INET best_source;
    MIB_IPFORWARDROW first_route;
    MIB_IPFORWARDROW confirmed_route;
    MIB_IPFORWARD_ROW2 route;
    uint64_t generation_before;
    uint64_t generation_after;
    ULONG result;

    clear_outputs(
        source,
        gateway,
        interface_index,
        network_generation_high,
        network_generation_low);
    if (source == NULL || gateway == NULL || interface_index == NULL ||
        network_generation_high == NULL || network_generation_low == NULL) {
        return TPS_ROUTE_ERR_ARGUMENT;
    }
    if (!notifications_available()) {
        return TPS_ROUTE_ERR_UNAVAILABLE;
    }
    generation_before = read_network_generation();

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
    /*
     * ENet can bind the selected source address but cannot set
     * IP_UNICAST_IF through its Lua API.  Requiring that address to belong
     * to exactly one local interface makes the exact source bind an
     * unambiguous interface bind; duplicate-address multihoming fails closed.
     */
    if (!source_is_unique_on_interface(
            &best_source, route.InterfaceIndex)) {
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
        clear_outputs(
            source,
            gateway,
            interface_index,
            network_generation_high,
            network_generation_low);
        return TPS_ROUTE_ERR_FORMAT;
    }

    generation_after = read_network_generation();
    if (generation_before == 0u || generation_after != generation_before) {
        clear_outputs(
            source,
            gateway,
            interface_index,
            network_generation_high,
            network_generation_low);
        return TPS_ROUTE_ERR_CHANGED;
    }
    *interface_index = route.InterfaceIndex;
    *network_generation_high = (uint32_t)(generation_after >> 32u);
    *network_generation_low = (uint32_t)generation_after;
    return TPS_ROUTE_OK;
}
