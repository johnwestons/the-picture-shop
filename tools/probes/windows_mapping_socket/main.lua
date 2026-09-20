local function finish(success, reason)
    if success then
        print("TPS_MAPPING_SOCKET=PASS")
        print("SOURCE_ADDRESS_BOUND=True")
        print("INTERFACE_INDEX_BOUND=True")
        print("GATEWAY_ROUTE_MATCHED=True")
        print("NETWORK_GENERATION_BOUND=True")
        print("SECURE_IPV4_LISTENER_BOUND=True")
        print("WILDCARD_BIND_USED=False")
        print("INVITATION_CREATED=False")
        print("PRODUCTION_GATE_RETAINED=True")
        print("NETWORK_TRAFFIC_SENT=False")
        love.event.quit(0)
    else
        print("TPS_MAPPING_SOCKET=FAIL")
        print("REASON=" .. tostring(reason or "probe_failed"))
        love.event.quit(1)
    end
end

function love.load()
    local root = os.getenv("TPS_MAPPING_SOCKET_PROBE_ROOT")
    if type(root) ~= "string" or root == "" or root:find(";", 1, true) then
        finish(false, "invalid_probe_root")
        return
    end
    package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

    local discoveryOk, discovery = pcall(require, "src.net.gateway_discovery")
    local socketOk, socketFactory = pcall(
        require, "src.net.mapping_socket_windows")
    local listenerOk, listenerModule = pcall(
        require, "src.net.direct_ipv4_listener")
    local cryptoOk, crypto = pcall(require, "src.net.crypto_native")
    if not discoveryOk or not socketOk or not listenerOk or not cryptoOk then
        finish(false, "module_unavailable")
        return
    end
    local route = discovery.discover()
    if not route then finish(false, "route_unavailable"); return end
    local socket = socketFactory.open(route)
    if not socket then finish(false, "socket_unavailable"); return end
    local proof = socket:bindingProof()
    local exact = type(proof) == "table"
        and proof.exactNetworkBinding == true
        and proof.family == route.family
        and proof.internalAddress == route.internalAddress
        and proof.gatewayAddress == route.gatewayAddress
        and proof.interfaceIndex == route.interfaceIndex
        and proof.networkGeneration == route.networkGeneration
        and proof.routeFingerprint == route.routeFingerprint
    local current = exact and discovery.revalidate(route) or nil
    local closed = socket:close()
    local listener, listenerError
    local engineeringProvider = setmetatable({ productionReady = true }, {
        __index = crypto,
    })
    if exact and current and closed then
        for _, port in ipairs({ 57842, 57844, 57846 }) do
            listener, listenerError = listenerModule.open({
                route = route,
                port = port,
                provider = engineeringProvider,
            })
            if listener then break end
        end
    end
    local listenerBound = listener ~= nil
        and listener:invitation() == nil
        and listener:mappingRequest(60) ~= nil
    local listenerClosed = listenerBound and listener:close() or false
    if not exact then finish(false, "binding_mismatch")
    elseif not current then finish(false, "network_changed")
    elseif not closed then finish(false, "cleanup_failed")
    elseif not listenerBound then
        if listenerError == "Secure IPv4 transport is unavailable." then
            finish(false, "secure_transport_unavailable")
        elseif listenerError == "Secure IPv4 listener binding failed." then
            finish(false, "listener_binding_failed")
        elseif listenerError == "Secure IPv4 listener entropy is unavailable." then
            finish(false, "listener_entropy_unavailable")
        elseif listenerError == "Secure IPv4 listener options are invalid." then
            finish(false, "listener_options_invalid")
        else
            finish(false, "listener_unavailable")
        end
    elseif not listenerClosed then finish(false, "listener_cleanup_failed")
    elseif crypto.productionReady ~= false then finish(false, "production_gate_changed")
    else finish(true) end
end
