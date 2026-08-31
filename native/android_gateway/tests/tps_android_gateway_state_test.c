#include "tps_android_gateway.h"
#include "tps_android_gateway_internal.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(TPS_ANDROID_GATEWAY_TEST_WINDOWS_THREADS)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

static int failures;

static void expect(int condition, const char *name)
{
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", name);
        failures++;
    }
}

static int snapshot(
    char source[16],
    char gateway[16],
    uint32_t *handle_high,
    uint32_t *handle_low,
    uint32_t *revision)
{
    return tps_android_gateway_default_ipv4(
        source, gateway, handle_high, handle_low, revision);
}

#if defined(TPS_ANDROID_GATEWAY_TEST_WINDOWS_THREADS)
static volatile LONG concurrent_failures;

static int valid_concurrent_snapshot(
    const char *source,
    const char *gateway,
    uint32_t handle_high,
    uint32_t handle_low,
    uint32_t revision)
{
    int first = strcmp(source, "10.20.30.40") == 0 &&
        strcmp(gateway, "10.20.30.1") == 0 &&
        handle_high == UINT32_C(0x11223344) &&
        handle_low == UINT32_C(0x55667788);
    int second = strcmp(source, "172.20.30.40") == 0 &&
        strcmp(gateway, "172.20.30.1") == 0 &&
        handle_high == UINT32_C(0xaabbccdd) &&
        handle_low == UINT32_C(0xeeff0011);
    return revision != 0u && (first || second);
}

static DWORD WINAPI publish_worker(LPVOID context)
{
    unsigned int index;
    (void)context;
    for (index = 0u; index < 20000u; index++) {
        if (tps_android_gateway_publish_for_bridge(
                "10.20.30.40", "10.20.30.1",
                UINT64_C(0x1122334455667788)) != 0 ||
            tps_android_gateway_publish_for_bridge(
                "172.20.30.40", "172.20.30.1",
                UINT64_C(0xaabbccddeeff0011)) != 0) {
            InterlockedIncrement(&concurrent_failures);
            break;
        }
    }
    return 0u;
}

static DWORD WINAPI clear_worker(LPVOID context)
{
    unsigned int index;
    (void)context;
    for (index = 0u; index < 10000u; index++) {
        tps_android_gateway_clear_for_bridge();
        if (tps_android_gateway_publish_for_bridge(
                "10.20.30.40", "10.20.30.1",
                UINT64_C(0x1122334455667788)) != 0) {
            InterlockedIncrement(&concurrent_failures);
            break;
        }
    }
    return 0u;
}

static DWORD WINAPI read_worker(LPVOID context)
{
    char source[16];
    char gateway[16];
    uint32_t handle_high;
    uint32_t handle_low;
    uint32_t revision;
    unsigned int index;
    (void)context;
    for (index = 0u; index < 50000u; index++) {
        int result;
        memset(source, 'x', sizeof(source));
        memset(gateway, 'x', sizeof(gateway));
        handle_high = 1u;
        handle_low = 1u;
        revision = 1u;
        result = snapshot(
            source, gateway, &handle_high, &handle_low, &revision);
        if (result == TPS_ANDROID_GATEWAY_OK) {
            if (!valid_concurrent_snapshot(
                    source, gateway, handle_high, handle_low, revision)) {
                InterlockedIncrement(&concurrent_failures);
                break;
            }
        } else if (result == TPS_ANDROID_GATEWAY_ERR_UNAVAILABLE) {
            if (source[0] != 0 || gateway[0] != 0 || handle_high != 0u ||
                handle_low != 0u || revision != 0u) {
                InterlockedIncrement(&concurrent_failures);
                break;
            }
        } else {
            InterlockedIncrement(&concurrent_failures);
            break;
        }
    }
    return 0u;
}

static int run_concurrency_stress(void)
{
    HANDLE threads[4];
    DWORD wait_result;

    concurrent_failures = 0;
    tps_android_gateway_clear_for_bridge();
    if (tps_android_gateway_publish_for_bridge(
            "10.20.30.40", "10.20.30.1",
            UINT64_C(0x1122334455667788)) != 0) {
        return 0;
    }

    threads[0] = CreateThread(NULL, 0u, publish_worker, NULL, 0u, NULL);
    threads[1] = CreateThread(NULL, 0u, clear_worker, NULL, 0u, NULL);
    threads[2] = CreateThread(NULL, 0u, read_worker, NULL, 0u, NULL);
    threads[3] = CreateThread(NULL, 0u, read_worker, NULL, 0u, NULL);
    if (threads[0] == NULL || threads[1] == NULL ||
        threads[2] == NULL || threads[3] == NULL) {
        unsigned int index;
        for (index = 0u; index < 4u; index++) {
            if (threads[index] != NULL) {
                CloseHandle(threads[index]);
            }
        }
        return 0;
    }

    wait_result = WaitForMultipleObjects(4u, threads, TRUE, 30000u);
    CloseHandle(threads[0]);
    CloseHandle(threads[1]);
    CloseHandle(threads[2]);
    CloseHandle(threads[3]);
    return wait_result == WAIT_OBJECT_0 && concurrent_failures == 0;
}
#endif

int main(void)
{
    char source[16];
    char gateway[16];
    uint32_t handle_high = 99u;
    uint32_t handle_low = 99u;
    uint32_t first_revision = 99u;
    uint32_t second_revision = 0u;

    expect(tps_android_gateway_abi_version() == 2u, "abi_version");
    memset(source, 'x', sizeof(source));
    memset(gateway, 'x', sizeof(gateway));
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &first_revision) == TPS_ANDROID_GATEWAY_ERR_UNAVAILABLE,
        "initial_unavailable");
    expect(source[0] == 0 && gateway[0] == 0 && handle_high == 0u &&
        handle_low == 0u && first_revision == 0u,
        "failure_clears_outputs");

    expect(tps_android_gateway_publish_for_bridge(
        "192.168.1.50", "192.168.1.1",
        UINT64_C(0x12345678abcdef01)) == 0, "publish_valid");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &first_revision) == 0, "snapshot_valid");
    expect(strcmp(source, "192.168.1.50") == 0 &&
        strcmp(gateway, "192.168.1.1") == 0 &&
        handle_high == UINT32_C(0x12345678) &&
        handle_low == UINT32_C(0xabcdef01) && first_revision != 0u,
        "snapshot_fields");

    expect(tps_android_gateway_publish_for_bridge(
        "192.168.1.50", "192.168.1.1",
        UINT64_C(0x12345678abcdef01)) == 0, "duplicate_publish_valid");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &second_revision) == 0 && second_revision == first_revision,
        "duplicate_preserves_revision");

    expect(tps_android_gateway_publish_for_bridge(
        "192.168.1.50", "192.168.1.1",
        UINT64_C(0x12345678abcdef02)) == 0, "new_handle_publish_valid");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &second_revision) == 0 && second_revision != first_revision &&
        handle_high == UINT32_C(0x12345678) &&
        handle_low == UINT32_C(0xabcdef02),
        "new_handle_changes_revision");
    first_revision = second_revision;

    expect(tps_android_gateway_publish_for_bridge(
        "192.168.1.51", "192.168.1.1",
        UINT64_C(0x12345678abcdef02)) == 0, "new_tuple_publish_valid");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &second_revision) == 0 && second_revision != first_revision &&
        strcmp(source, "192.168.1.51") == 0,
        "new_tuple_changes_revision");

    expect(tps_android_gateway_publish_for_bridge(
        "192.168.001.50", "192.168.1.1", 7u) ==
        TPS_ANDROID_GATEWAY_ERR_FORMAT, "leading_zero_rejected");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &second_revision) == TPS_ANDROID_GATEWAY_ERR_UNAVAILABLE,
        "invalid_publish_fails_closed");
    expect(tps_android_gateway_publish_for_bridge(
        "192.168.1.50", "192.168.1.1", 7u) == 0,
        "republish_after_invalid");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &first_revision) == 0, "republished_snapshot_valid");
    expect(tps_android_gateway_publish_for_bridge(
        "127.0.0.1", "192.168.1.1", 7u) ==
        TPS_ANDROID_GATEWAY_ERR_FORMAT, "loopback_rejected");
    expect(tps_android_gateway_publish_for_bridge(
        "192.0.2.10", "192.0.2.1", 7u) ==
        TPS_ANDROID_GATEWAY_ERR_FORMAT, "documentation_rejected");
    expect(tps_android_gateway_publish_for_bridge(
        "192.168.1.50", "192.168.1.50", 7u) ==
        TPS_ANDROID_GATEWAY_ERR_FORMAT, "same_pair_rejected");
    expect(tps_android_gateway_publish_for_bridge(
        "192.168.1.50", "192.168.1.1", 0u) ==
        TPS_ANDROID_GATEWAY_ERR_FORMAT, "zero_handle_rejected");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &second_revision) == TPS_ANDROID_GATEWAY_ERR_UNAVAILABLE,
        "rejected_publish_clears_snapshot");

    expect(tps_android_gateway_publish_for_bridge(
        "192.168.100.200", "192.168.100.1", UINT64_MAX) == 0,
        "maximum_handle_and_address_bound_accepted");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &second_revision) == 0 && handle_high == UINT32_MAX &&
        handle_low == UINT32_MAX &&
        strcmp(source, "192.168.100.200") == 0,
        "maximum_handle_split_exactly");
    expect(tps_android_gateway_publish_for_bridge(
        "192.168.100.2000", "192.168.100.1", UINT64_MAX) ==
        TPS_ANDROID_GATEWAY_ERR_FORMAT, "overlong_address_rejected");

    tps_android_gateway_clear_for_bridge();
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &second_revision) == TPS_ANDROID_GATEWAY_ERR_UNAVAILABLE,
        "clear_invalidates");
    expect(source[0] == 0 && gateway[0] == 0 && handle_high == 0u &&
        handle_low == 0u && second_revision == 0u,
        "clear_failure_outputs");

    expect(tps_android_gateway_publish_for_bridge(
        "10.0.0.25", "10.0.0.1", 12u) == 0, "republish_valid");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &second_revision) == 0 && second_revision != 0u &&
        second_revision != first_revision, "republish_changes_revision");

    expect(tps_android_gateway_publish_for_bridge(
        "10.0.0.25", "169.254.10.1", 12u) == 0,
        "link_local_gateway_allowed");
    expect(snapshot(source, gateway, &handle_high, &handle_low,
        &second_revision) == 0 && strcmp(source, "10.0.0.25") == 0 &&
        strcmp(gateway, "169.254.10.1") == 0,
        "link_local_gateway_snapshot");

    handle_high = 99u;
    handle_low = 99u;
    second_revision = 99u;
    expect(tps_android_gateway_default_ipv4(
        NULL, gateway, &handle_high, &handle_low, &second_revision) ==
        TPS_ANDROID_GATEWAY_ERR_ARGUMENT, "null_output_rejected");
    expect(gateway[0] == 0 && handle_high == 0u && handle_low == 0u &&
        second_revision == 0u, "null_output_clears_other_outputs");

#if defined(TPS_ANDROID_GATEWAY_TEST_WINDOWS_THREADS)
    expect(run_concurrency_stress(), "concurrency_stress");
#endif

    if (failures != 0) {
        return 1;
    }
    puts("TPS_ANDROID_GATEWAY_STATE=PASS");
    return 0;
}
