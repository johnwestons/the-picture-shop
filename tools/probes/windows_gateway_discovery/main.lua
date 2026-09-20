local function finish(success, reason)
    if success then
        print("TPS_GATEWAY_DISCOVERY=PASS")
        print("DEFAULT_IPV4_ROUTE=VERIFIED")
        print("ROUTE_SNAPSHOT_ALLOWLISTED=True")
        print("NETWORK_GENERATION_PRESENT=True")
        print("NETWORK_TRAFFIC_SENT=False")
        love.event.quit(0)
    else
        print("TPS_GATEWAY_DISCOVERY=FAIL")
        print("REASON=" .. reason)
        love.event.quit(1)
    end
end

function love.load()
    local root = os.getenv("TPS_GATEWAY_PROBE_ROOT")
    if type(root) ~= "string" or root == "" or root:find(";", 1, true) then
        finish(false, "invalid_probe_root")
        return
    end
    package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

    local moduleOk, discovery = pcall(require, "src.net.gateway_discovery")
    if not moduleOk or type(discovery) ~= "table" then
        finish(false, "module_unavailable")
        return
    end
    local snapshot, discoveryError = discovery.discover()
    if not snapshot then
        local safeReasons = {
            unsupported_platform = true,
            platform_bridge_unavailable = true,
            gateway_discovery_unavailable = true,
            invalid_default_route = true,
        }
        finish(false, safeReasons[discoveryError] and discoveryError
            or "discovery_failed")
        return
    end
    if snapshot.family ~= 4 or snapshot.routePrefixLength ~= 0 or
        type(snapshot.internalAddress) ~= "string" or
        type(snapshot.gatewayAddress) ~= "string" or
        type(snapshot.interfaceIndex) ~= "number" or
        type(snapshot.networkGeneration) ~= "string" or
        type(snapshot.routeFingerprint) ~= "string" or
        snapshot.platform ~= "Windows" then
        finish(false, "invalid_snapshot")
        return
    end

    local current, revalidateError = discovery.revalidate(snapshot)
    if not current then
        finish(false, revalidateError == "network_changed" and
            "network_changed" or "revalidation_failed")
        return
    end
    finish(true)
end
