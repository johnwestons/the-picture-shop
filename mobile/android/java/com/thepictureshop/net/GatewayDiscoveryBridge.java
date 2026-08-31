package com.thepictureshop.net;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.RouteInfo;
import android.os.Build;

import androidx.annotation.Keep;
import androidx.annotation.RequiresApi;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.util.List;

/**
 * Publishes a bounded snapshot of the app's local IPv4 default route to a
 * small native library. No socket is opened and no packet is sent here.
 *
 * <p>The Android networking classes are isolated behind the API-26 entry
 * check so loading this outer class remains safe for the application's older
 * minSdk. The opaque Network handle is retained with the addresses so future
 * traffic can be bound to the exact Android network that was inspected.</p>
 */
@Keep
public final class GatewayDiscoveryBridge {
    private static final Object LIFECYCLE_LOCK = new Object();
    private static final String NATIVE_LIBRARY = "tps_android_gateway";

    private static boolean nativeLoadAttempted;
    private static boolean nativeReady;
    private static Api26State activeState;

    private GatewayDiscoveryBridge() {
    }

    @Keep
    private static native boolean nativePublishDefaultIpv4(
            String sourceAddress,
            String gatewayAddress,
            long networkHandle);

    @Keep
    private static native void nativeClearDefaultIpv4();

    /** Starts one fail-closed listener for the application's default network. */
    @Keep
    public static void start(Context context) {
        if (context == null || Build.VERSION.SDK_INT < 26) {
            return;
        }

        synchronized (LIFECYCLE_LOCK) {
            if (activeState != null) {
                return;
            }

            Api26State state = null;
            try {
                if (!loadNativeLibraryLocked()) {
                    return;
                }

                Context applicationContext = context.getApplicationContext();
                if (applicationContext == null) {
                    applicationContext = context;
                }
                state = new Api26State(applicationContext);
                activeState = state;
                if (!state.startLocked()) {
                    state.stopLocked();
                    activeState = null;
                }
            } catch (Throwable ignored) {
                if (state != null && activeState == state) {
                    state.stopLocked();
                    activeState = null;
                } else if (activeState == null) {
                    clearNativeSnapshotLocked();
                }
            }
        }
    }

    /** Stops the listener and invalidates any route snapshot it published. */
    @Keep
    public static void stop() {
        synchronized (LIFECYCLE_LOCK) {
            Api26State state = activeState;
            if (state == null) {
                clearNativeSnapshotLocked();
                return;
            }
            try {
                state.stopLocked();
            } catch (Throwable ignored) {
                clearNativeSnapshotLocked();
            } finally {
                if (activeState == state) {
                    activeState = null;
                }
            }
        }
    }

    private static boolean loadNativeLibraryLocked() {
        if (nativeReady) {
            return true;
        }
        if (nativeLoadAttempted) {
            return false;
        }
        nativeLoadAttempted = true;
        try {
            System.loadLibrary(NATIVE_LIBRARY);
            nativeReady = true;
            nativeClearDefaultIpv4();
            return true;
        } catch (Throwable ignored) {
            if (nativeReady) {
                try {
                    nativeClearDefaultIpv4();
                } catch (Throwable clearIgnored) {
                    // The bridge is disabled immediately below.
                }
            }
            nativeReady = false;
            return false;
        }
    }

    private static boolean publishNativeSnapshotLocked(Candidate candidate) {
        if (!nativeReady || candidate == null) {
            return false;
        }
        try {
            boolean published = nativePublishDefaultIpv4(
                    candidate.sourceAddress,
                    candidate.gatewayAddress,
                    candidate.networkHandle);
            if (published) {
                return true;
            }
        } catch (Throwable ignored) {
            // Clear and disable below.
        }
        disableNativeAfterClearLocked();
        return false;
    }

    private static void disableNativeAfterClearLocked() {
        if (nativeReady) {
            try {
                nativeClearDefaultIpv4();
            } catch (Throwable ignored) {
                // The bridge is disabled immediately below.
            }
        }
        nativeReady = false;
    }

    private static void clearNativeSnapshotLocked() {
        if (!nativeReady) {
            return;
        }
        try {
            nativeClearDefaultIpv4();
        } catch (Throwable ignored) {
            // Clearing was attempted before disabling the faulty bridge.
            nativeReady = false;
        }
    }

    private static final class Candidate {
        final String sourceAddress;
        final String gatewayAddress;
        final long networkHandle;

        Candidate(String sourceAddress, String gatewayAddress, long networkHandle) {
            this.sourceAddress = sourceAddress;
            this.gatewayAddress = gatewayAddress;
            this.networkHandle = networkHandle;
        }

        boolean sameRoute(Candidate other) {
            return other != null
                    && networkHandle == other.networkHandle
                    && sourceAddress.equals(other.sourceAddress)
                    && gatewayAddress.equals(other.gatewayAddress);
        }
    }

    @RequiresApi(26)
    private static final class Api26State {
        private final Context context;
        private final ConnectivityManager connectivityManager;
        private final ConnectivityManager.NetworkCallback callback;

        private boolean running;
        private boolean registered;
        private Network currentNetwork;
        private NetworkCapabilities currentCapabilities;
        private LinkProperties currentLinkProperties;
        private boolean blockedStatusKnown;
        private boolean currentBlocked;
        private Candidate publishedCandidate;

        Api26State(Context context) {
            this.context = context;
            Object service = context.getSystemService(Context.CONNECTIVITY_SERVICE);
            this.connectivityManager = service instanceof ConnectivityManager
                    ? (ConnectivityManager) service : null;
            this.callback = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onAvailable(Network network) {
                    callbackAvailable(network);
                }

                @Override
                public void onCapabilitiesChanged(
                        Network network, NetworkCapabilities capabilities) {
                    callbackCapabilitiesChanged(network, capabilities);
                }

                @Override
                public void onLinkPropertiesChanged(
                        Network network, LinkProperties linkProperties) {
                    callbackLinkPropertiesChanged(network, linkProperties);
                }

                @Override
                public void onLost(Network network) {
                    callbackLost(network);
                }

                @Override
                public void onBlockedStatusChanged(Network network, boolean blocked) {
                    callbackBlockedStatusChanged(network, blocked);
                }

                @Override
                public void onUnavailable() {
                    callbackUnavailable();
                }
            };
        }

        boolean startLocked() {
            if (connectivityManager == null
                    || context.checkSelfPermission(
                    Manifest.permission.ACCESS_NETWORK_STATE)
                    != PackageManager.PERMISSION_GRANTED) {
                clearNativeSnapshotLocked();
                return false;
            }
            if (running) {
                return true;
            }

            running = true;
            try {
                connectivityManager.registerDefaultNetworkCallback(callback);
                registered = true;
                return true;
            } catch (Throwable ignored) {
                running = false;
                registered = false;
                invalidateCurrentLocked();
                try {
                    // The framework may throw after partially accepting the
                    // callback, so cleanup is attempted even without a normal
                    // registration return.
                    connectivityManager.unregisterNetworkCallback(callback);
                } catch (Throwable unregisterIgnored) {
                    // Snapshot state is already invalid.
                }
                return false;
            }
        }

        void stopLocked() {
            boolean shouldUnregister = registered;
            running = false;
            registered = false;
            invalidateCurrentLocked();

            if (shouldUnregister && connectivityManager != null) {
                try {
                    connectivityManager.unregisterNetworkCallback(callback);
                } catch (Throwable ignored) {
                    // State is already invalid and queued callbacks cannot
                    // publish after running is cleared.
                }
            }
        }

        private boolean ownsLifecycleLocked() {
            return activeState == this && running;
        }

        private void callbackAvailable(Network network) {
            synchronized (LIFECYCLE_LOCK) {
                if (!ownsLifecycleLocked()) {
                    return;
                }
                try {
                    if (network == null) {
                        invalidateCurrentLocked();
                        return;
                    }
                    if (network.equals(currentNetwork)) {
                        reevaluateLocked();
                        return;
                    }
                    currentNetwork = network;
                    currentCapabilities = null;
                    currentLinkProperties = null;
                    // Android did not expose blocked-status callbacks before
                    // API 29. On API 26-28 this marks the unavailable signal
                    // as not applicable; it does not claim it was observed.
                    blockedStatusKnown = Build.VERSION.SDK_INT < 29;
                    currentBlocked = false;
                    publishedCandidate = null;
                    clearNativeSnapshotLocked();
                } catch (Throwable ignored) {
                    invalidateCurrentLocked();
                }
            }
        }

        private void callbackCapabilitiesChanged(
                Network network, NetworkCapabilities capabilities) {
            synchronized (LIFECYCLE_LOCK) {
                if (!ownsLifecycleLocked()) {
                    return;
                }
                try {
                    if (network == null || capabilities == null) {
                        invalidateCurrentLocked();
                    } else if (network.equals(currentNetwork)) {
                        currentCapabilities = capabilities;
                        reevaluateLocked();
                    }
                } catch (Throwable ignored) {
                    invalidateCurrentLocked();
                }
            }
        }

        private void callbackLinkPropertiesChanged(
                Network network, LinkProperties linkProperties) {
            synchronized (LIFECYCLE_LOCK) {
                if (!ownsLifecycleLocked()) {
                    return;
                }
                try {
                    if (network == null || linkProperties == null) {
                        invalidateCurrentLocked();
                    } else if (network.equals(currentNetwork)) {
                        currentLinkProperties = linkProperties;
                        reevaluateLocked();
                    }
                } catch (Throwable ignored) {
                    invalidateCurrentLocked();
                }
            }
        }

        private void callbackLost(Network network) {
            synchronized (LIFECYCLE_LOCK) {
                if (!ownsLifecycleLocked()) {
                    return;
                }
                try {
                    if (network == null || network.equals(currentNetwork)) {
                        invalidateCurrentLocked();
                    }
                } catch (Throwable ignored) {
                    invalidateCurrentLocked();
                }
            }
        }

        private void callbackBlockedStatusChanged(Network network, boolean blocked) {
            synchronized (LIFECYCLE_LOCK) {
                if (!ownsLifecycleLocked()) {
                    return;
                }
                try {
                    if (network == null) {
                        invalidateCurrentLocked();
                    } else if (network.equals(currentNetwork)) {
                        blockedStatusKnown = true;
                        currentBlocked = blocked;
                        reevaluateLocked();
                    }
                } catch (Throwable ignored) {
                    invalidateCurrentLocked();
                }
            }
        }

        private void callbackUnavailable() {
            synchronized (LIFECYCLE_LOCK) {
                if (ownsLifecycleLocked()) {
                    invalidateCurrentLocked();
                }
            }
        }

        private void invalidateCurrentLocked() {
            currentNetwork = null;
            currentCapabilities = null;
            currentLinkProperties = null;
            blockedStatusKnown = false;
            currentBlocked = true;
            publishedCandidate = null;
            clearNativeSnapshotLocked();
        }

        private void invalidatePublishedLocked() {
            publishedCandidate = null;
            clearNativeSnapshotLocked();
        }

        private void reevaluateLocked() {
            if (!ownsLifecycleLocked() || !blockedStatusKnown || currentBlocked
                    || currentNetwork == null
                    || currentCapabilities == null
                    || currentLinkProperties == null) {
                invalidatePublishedLocked();
                return;
            }

            Candidate candidate = selectCandidate(
                    currentNetwork, currentCapabilities, currentLinkProperties);
            if (candidate == null) {
                invalidatePublishedLocked();
                return;
            }
            if (candidate.sameRoute(publishedCandidate)) {
                return;
            }

            if (publishNativeSnapshotLocked(candidate)) {
                publishedCandidate = candidate;
            } else {
                invalidatePublishedLocked();
            }
        }

        private static Candidate selectCandidate(
                Network network,
                NetworkCapabilities capabilities,
                LinkProperties properties) {
            if (network == null || !usableCapabilities(capabilities)
                    || properties == null) {
                return null;
            }

            long networkHandle = network.getNetworkHandle();
            if (networkHandle == 0L) {
                return null;
            }

            String interfaceName = properties.getInterfaceName();
            if (interfaceName == null || interfaceName.length() == 0) {
                return null;
            }

            Inet4Address gateway = uniqueIpv4Gateway(
                    properties.getRoutes(), interfaceName);
            Inet4Address source = uniqueIpv4Source(properties.getLinkAddresses());
            if (gateway == null || source == null || gateway.equals(source)) {
                return null;
            }

            String sourceText = source.getHostAddress();
            String gatewayText = gateway.getHostAddress();
            if (!boundedIpv4Text(sourceText) || !boundedIpv4Text(gatewayText)
                    || sourceText.equals(gatewayText)) {
                return null;
            }
            return new Candidate(sourceText, gatewayText, networkHandle);
        }

        private static boolean usableCapabilities(
                NetworkCapabilities capabilities) {
            // NET_CAPABILITY_NOT_SUSPENDED is only observable from API 28.
            // API 26-27 validation therefore uses only signals those releases
            // actually expose.
            return capabilities != null
                    && !capabilities.hasTransport(
                    NetworkCapabilities.TRANSPORT_VPN)
                    && !capabilities.hasTransport(
                    NetworkCapabilities.TRANSPORT_CELLULAR)
                    && capabilities.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                    && capabilities.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    && capabilities.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                    && (Build.VERSION.SDK_INT < 28
                    || Api28.isNotSuspended(capabilities))
                    && (capabilities.hasTransport(
                    NetworkCapabilities.TRANSPORT_WIFI)
                    || capabilities.hasTransport(
                    NetworkCapabilities.TRANSPORT_ETHERNET));
        }

        private static Inet4Address uniqueIpv4Gateway(
                List<RouteInfo> routes, String interfaceName) {
            if (routes == null || interfaceName == null) {
                return null;
            }

            Inet4Address selected = null;
            int matchingRouteCount = 0;
            for (RouteInfo route : routes) {
                if (route == null || route.getDestination() == null) {
                    return null;
                }
                InetAddress destination = route.getDestination().getAddress();
                if (!(destination instanceof Inet4Address)
                        || !route.isDefaultRoute()) {
                    continue;
                }
                if (Build.VERSION.SDK_INT >= 33 && !Api33.isUnicast(route)) {
                    return null;
                }
                if (!interfaceName.equals(route.getInterface())) {
                    return null;
                }

                InetAddress address = route.getGateway();
                if (!(address instanceof Inet4Address)
                        || !usableIpv4Gateway((Inet4Address) address)) {
                    return null;
                }
                matchingRouteCount++;
                if (matchingRouteCount != 1) {
                    return null;
                }
                selected = (Inet4Address) address;
            }
            return matchingRouteCount == 1 ? selected : null;
        }

        private static Inet4Address uniqueIpv4Source(List<LinkAddress> addresses) {
            if (addresses == null) {
                return null;
            }
            Inet4Address selected = null;
            for (LinkAddress linkAddress : addresses) {
                if (linkAddress == null) {
                    return null;
                }
                InetAddress address = linkAddress.getAddress();
                if (!(address instanceof Inet4Address)
                        || !usableIpv4Source((Inet4Address) address)) {
                    continue;
                }
                Inet4Address candidate = (Inet4Address) address;
                if (selected != null && !selected.equals(candidate)) {
                    return null;
                }
                selected = candidate;
            }
            return selected;
        }

        private static boolean usableIpv4Gateway(Inet4Address address) {
            return !address.isAnyLocalAddress()
                    && !address.isLoopbackAddress()
                    && !address.isMulticastAddress();
        }

        private static boolean usableIpv4Source(Inet4Address address) {
            return usableIpv4Gateway(address) && !address.isLinkLocalAddress();
        }

        private static boolean boundedIpv4Text(String value) {
            if (value == null || value.length() < 7 || value.length() > 15) {
                return false;
            }
            for (int index = 0; index < value.length(); index++) {
                char character = value.charAt(index);
                if ((character < '0' || character > '9') && character != '.') {
                    return false;
                }
            }
            return true;
        }
    }

    @RequiresApi(28)
    private static final class Api28 {
        private Api28() {
        }

        static boolean isNotSuspended(NetworkCapabilities capabilities) {
            return capabilities.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED);
        }
    }

    @RequiresApi(33)
    private static final class Api33 {
        private Api33() {
        }

        static boolean isUnicast(RouteInfo route) {
            return route.getType() == RouteInfo.RTN_UNICAST;
        }
    }
}
