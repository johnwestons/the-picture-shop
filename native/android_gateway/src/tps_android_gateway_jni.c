#include "tps_android_gateway.h"
#include "tps_android_gateway_internal.h"

#include <jni.h>
#include <stdint.h>

JNIEXPORT jboolean JNICALL
Java_com_thepictureshop_net_GatewayDiscoveryBridge_nativePublishDefaultIpv4(
    JNIEnv *environment,
    jclass bridge_class,
    jstring source,
    jstring gateway,
    jlong network_handle)
{
    const char *source_text = NULL;
    const char *gateway_text = NULL;
    jsize source_length;
    jsize gateway_length;
    int32_t result;

    (void)bridge_class;
    if (environment == NULL || source == NULL || gateway == NULL ||
        network_handle == (jlong)0) {
        tps_android_gateway_clear_for_bridge();
        return JNI_FALSE;
    }

    source_length = (*environment)->GetStringUTFLength(environment, source);
    gateway_length = (*environment)->GetStringUTFLength(environment, gateway);
    if ((*environment)->ExceptionCheck(environment) || source_length <= 0 ||
        gateway_length <= 0 ||
        source_length >= (jsize)TPS_ANDROID_GATEWAY_ADDRESS_BYTES ||
        gateway_length >= (jsize)TPS_ANDROID_GATEWAY_ADDRESS_BYTES) {
        tps_android_gateway_clear_for_bridge();
        return JNI_FALSE;
    }

    source_text = (*environment)->GetStringUTFChars(environment, source, NULL);
    if (source_text == NULL) {
        tps_android_gateway_clear_for_bridge();
        return JNI_FALSE;
    }
    if ((*environment)->ExceptionCheck(environment)) {
        (*environment)->ReleaseStringUTFChars(environment, source, source_text);
        tps_android_gateway_clear_for_bridge();
        return JNI_FALSE;
    }
    gateway_text = (*environment)->GetStringUTFChars(environment, gateway, NULL);
    if (gateway_text == NULL) {
        (*environment)->ReleaseStringUTFChars(environment, source, source_text);
        tps_android_gateway_clear_for_bridge();
        return JNI_FALSE;
    }
    if ((*environment)->ExceptionCheck(environment)) {
        (*environment)->ReleaseStringUTFChars(environment, gateway, gateway_text);
        (*environment)->ReleaseStringUTFChars(environment, source, source_text);
        tps_android_gateway_clear_for_bridge();
        return JNI_FALSE;
    }

    result = tps_android_gateway_publish_for_bridge(
        source_text, gateway_text, (uint64_t)network_handle);
    (*environment)->ReleaseStringUTFChars(environment, gateway, gateway_text);
    (*environment)->ReleaseStringUTFChars(environment, source, source_text);
    return result == TPS_ANDROID_GATEWAY_OK ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_thepictureshop_net_GatewayDiscoveryBridge_nativeClearDefaultIpv4(
    JNIEnv *environment,
    jclass bridge_class)
{
    (void)environment;
    (void)bridge_class;
    tps_android_gateway_clear_for_bridge();
}
