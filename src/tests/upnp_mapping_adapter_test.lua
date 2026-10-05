local UpnpIgd = require("src.net.upnp_igd")
local UpnpMappingAdapter = require("src.net.upnp_mapping_adapter")
local Reachability = require("src.net.reachability")

local Test = {}
local UDN = "uuid:12345678-1234-4abc-8def-1234567890ab"

local function route()
    return {
        family = 4, platform = "Windows", internalAddress = "192.168.1.20",
        gatewayAddress = "192.168.1.1", interfaceIndex = 7,
        networkGeneration = "windows-route-v2-test-0001",
        routeFingerprint = "route-v1-aabbccdd",
    }
end

local function request()
    return {
        internalAddress = "192.168.1.20", gatewayAddress = "192.168.1.1",
        internalPort = 22122, suggestedExternalPort = 0,
        requestedLifetime = 120,
    }
end

local function http(body, status)
    status = status or "200 OK"
    return "HTTP/1.1 " .. status .. "\r\nContent-Length: "
        .. tostring(#body) .. "\r\nConnection: close\r\n\r\n" .. body
end

local function soap(serviceType, action, contents)
    local body = "<?xml version=\"1.0\"?>"
        .. "<s:Envelope xmlns:s=\"" .. UpnpIgd.SOAP_ENVELOPE .. "\">"
        .. "<s:Body><u:" .. action .. "Response xmlns:u=\"" .. serviceType .. "\">"
        .. (contents or "") .. "</u:" .. action .. "Response></s:Body></s:Envelope>"
    return http(body)
end

local function ssdp()
    return table.concat({
        "HTTP/1.1 200 OK", "CACHE-CONTROL: max-age=1800", "EXT:",
        "LOCATION: http://192.168.1.1:5000/root.xml",
        "ST: " .. UpnpIgd.IGD2_TARGET,
        "USN: " .. UDN .. "::" .. UpnpIgd.IGD2_TARGET,
        "SERVER: test/1 UPnP/1.1 gateway/1", "BOOTID.UPNP.ORG: 1", "", "",
    }, "\r\n")
end

local function description()
    return "<?xml version=\"1.0\"?>"
        .. "<root xmlns=\"" .. UpnpIgd.DEVICE_NAMESPACE .. "\">"
        .. "<specVersion><major>1</major><minor>1</minor></specVersion>"
        .. "<device><deviceType>" .. UpnpIgd.IGD2_TARGET .. "</deviceType>"
        .. "<UDN>" .. UDN .. "</UDN><friendlyName>Gateway</friendlyName>"
        .. "<deviceList><device><deviceType>" .. UpnpIgd.WAN_DEVICE_V2 .. "</deviceType>"
        .. "<deviceList><device><deviceType>" .. UpnpIgd.WAN_CONNECTION_DEVICE_V2 .. "</deviceType>"
        .. "<serviceList><service><serviceType>" .. UpnpIgd.WAN_IP_V2 .. "</serviceType>"
        .. "<serviceId>urn:upnp-org:serviceId:WANIPConn1</serviceId>"
        .. "<controlURL>/control</controlURL></service></serviceList>"
        .. "</device></deviceList></device></deviceList></device></root>"
end

local function proof(selected)
    return {
        family = 4, internalAddress = selected.internalAddress,
        gatewayAddress = selected.gatewayAddress,
        interfaceIndex = selected.interfaceIndex,
        networkGeneration = selected.networkGeneration,
        routeFingerprint = selected.routeFingerprint,
        localPort = 49152, exactNetworkBinding = true,
    }
end

local function fakeTransport(selected, log, pendingAdd, closeFailures)
    local factory = { exactNetworkBinding = true }
    function factory.openDiscovery(actual)
        log[#log + 1] = { kind = "open_discovery", route = actual }
        local socket = { inbound = { ssdp() }, closed = false }
        function socket:bindingProof() return proof(selected) end
        function socket:sendto(bytes, address, port)
            log[#log + 1] = { kind = "ssdp", bytes = bytes,
                address = address, port = port }
            return #bytes
        end
        function socket:receivefrom()
            local packet = table.remove(self.inbound, 1)
            if not packet then return nil, "timeout" end
            return packet, selected.gatewayAddress, UpnpIgd.SSDP_PORT
        end
        function socket:close()
            if closeFailures and (closeFailures.discovery or 0) > 0 then
                closeFailures.discovery = closeFailures.discovery - 1
                return false
            end
            self.closed = true
            return true
        end
        return socket
    end
    function factory.openHttp(actual, outbound)
        log[#log + 1] = { kind = "http", request = outbound, route = actual }
        local action = outbound.context and outbound.context.action
        local raw
        if outbound.context and outbound.context.kind == "description" then
            raw = http(description())
        elseif action == "GetExternalIPAddress" then
            raw = soap(UpnpIgd.WAN_IP_V2, action,
                "<NewExternalIPAddress>8.8.4.4</NewExternalIPAddress>")
        elseif action == "AddAnyPortMapping" then
            if pendingAdd == "fault" then
                local fault = "<s:Envelope xmlns:s=\"" .. UpnpIgd.SOAP_ENVELOPE .. "\">"
                    .. "<s:Body><s:Fault><faultcode>s:Client</faultcode>"
                    .. "<faultstring>UPnPError</faultstring><detail><UPnPError xmlns=\""
                    .. UpnpIgd.UPNP_CONTROL .. "\"><errorCode>401</errorCode>"
                    .. "<errorDescription>Invalid Action</errorDescription>"
                    .. "</UPnPError></detail></s:Fault></s:Body></s:Envelope>"
                raw = http(fault, "500 Internal Server Error")
            else
                raw = soap(UpnpIgd.WAN_IP_V2, action,
                    "<NewReservedPort>40000</NewReservedPort>")
            end
        elseif action == "AddPortMapping" then
            raw = soap(UpnpIgd.WAN_IP_V2, action, "")
        elseif action == "DeletePortMapping" then
            raw = soap(UpnpIgd.WAN_IP_V2, action, "")
        end
        local handle = { closed = false }
        function handle:bindingProof() return proof(selected) end
        function handle:requestSent() return true end
        function handle:update()
            if pendingAdd == true and (action == "AddAnyPortMapping"
                    or action == "AddPortMapping") then
                return nil, "pending"
            end
            if not raw then return nil, "socket_error" end
            local value, peer = raw, selected.gatewayAddress
            raw = nil
            return { raw = value, peerAddress = peer, peerPort = outbound.port }
        end
        function handle:close()
            if closeFailures and (closeFailures.http or 0) > 0 then
                closeFailures.http = closeFailures.http - 1
                return false
            end
            self.closed = true
            return true
        end
        return handle
    end
    return factory
end

local function newAdapter(selected, log, pendingAdd, changed, closeFailures)
    return UpnpMappingAdapter.new({
        route = selected,
        transportFactory = fakeTransport(selected, log, pendingAdd, closeFailures),
        revalidate = function(snapshot)
            if changed.value then return nil end
            return snapshot
        end,
    })
end

local function requestByAction(log, action)
    for _, item in ipairs(log) do
        if item.request and item.request.context
            and item.request.context.action == action then return item.request end
    end
end

function Test.run(_, check)
    local selected, log, changed = route(), {}, { value = false }
    local adapter = assert(newAdapter(selected, log, false, changed))
    local handle = assert(adapter:start(request()))
    check("upnp_mapping_adapter_constructor_and_start_are_side_effect_free",
        adapter.name == "upnp_igd" and adapter.attemptTimeoutSeconds == false
        and #log == 0)

    handle:update(0)
    handle:update(0.1)
    handle:update(0.2)
    local mapped = handle:update(0.3)
    local addRequest = requestByAction(log, "AddAnyPortMapping")
    check("upnp_mapping_adapter_discovers_queries_and_maps_only_the_exact_gateway",
        mapped and mapped.kind == "mapped" and mapped.externalAddress == "8.8.4.4"
        and mapped.externalPort == 40000 and mapped.lifetime == 120
        and log[1].kind == "open_discovery"
        and log[2].kind == "ssdp" and log[2].address == UpnpIgd.SSDP_ADDRESS
        and log[3].kind == "ssdp"
        and addRequest and addRequest.host == selected.gatewayAddress
        and addRequest.context.action == "AddAnyPortMapping"
        and addRequest.context.internalClient == selected.internalAddress
        and addRequest.context.leaseSeconds == 120)

    local failedCloseLog, closeFailures = {}, { http = 1 }
    local failedCloseHandle = assert((assert(newAdapter(route(), failedCloseLog,
        false, { value = false }, closeFailures))):start(request()))
    failedCloseHandle:update(0)
    failedCloseHandle:update(0.1)
    local failedDescriptionClose = failedCloseHandle:update(0.2)
    local retriedHttpClose = failedCloseHandle:close(0.2)
    check("upnp_mapping_adapter_retains_failed_http_close_and_never_advances_setup",
        failedDescriptionClose and failedDescriptionClose.kind == "failed"
        and requestByAction(failedCloseLog, "GetExternalIPAddress") == nil
        and closeFailures.http == 0 and retriedHttpClose == true)

    local failedDiscoveryLog, discoveryCloseFailures = {}, { discovery = 3 }
    local failedDiscoveryHandle = assert((assert(newAdapter(route(),
        failedDiscoveryLog, false, { value = false }, discoveryCloseFailures))):start(request()))
    local failedDiscoveryClose = failedDiscoveryHandle:update(0)
    local discoveryDelete = failedDiscoveryHandle:delete(0)
    local firstFinalClose = failedDiscoveryHandle:close(0)
    local discoveryRetryClose = failedDiscoveryHandle:close(0)
    check("upnp_mapping_adapter_retries_a_failed_final_close_without_losing_ownership",
        failedDiscoveryClose and failedDiscoveryClose.kind == "failed"
        and discoveryCloseFailures.discovery == 0
        and discoveryDelete == true and firstFinalClose == false
        and discoveryRetryClose == true)

    local wrongProofLog, wrongProofCloseFailures = {}, { discovery = 2 }
    local wrongProofTransport = fakeTransport(route(), wrongProofLog,
        false, wrongProofCloseFailures)
    local openWrongProofDiscovery = wrongProofTransport.openDiscovery
    function wrongProofTransport.openDiscovery(actualRoute)
        local socket = openWrongProofDiscovery(actualRoute)
        function socket:bindingProof()
            local wrongProof = proof(route())
            wrongProof.internalAddress = "192.168.1.99"
            return wrongProof
        end
        return socket
    end
    local wrongProofAdapter = assert(UpnpMappingAdapter.new({
        route = route(),
        transportFactory = wrongProofTransport,
        revalidate = function(snapshot) return snapshot end,
    }))
    local wrongProofHandle = assert(wrongProofAdapter:start(request()))
    local rejectedWrongProof = wrongProofHandle:update(0)
    local wrongProofDelete = wrongProofHandle:delete(0)
    local wrongProofFirstClose = wrongProofHandle:close(0)
    local wrongProofRetryClose = wrongProofHandle:close(0)
    local wrongProofSentPacket = false
    for _, item in ipairs(wrongProofLog) do
        if item.kind == "ssdp" then wrongProofSentPacket = true end
    end
    check("upnp_mapping_adapter_retains_unverified_socket_until_close_is_proven",
        rejectedWrongProof and rejectedWrongProof.kind == "failed"
        and wrongProofDelete == true and wrongProofFirstClose == false
        and wrongProofRetryClose == true
        and wrongProofCloseFailures.discovery == 0
        and not wrongProofSentPacket)

    local renewalStarted = handle:renew(0.4)
    local renewed = handle:update(0.5)
    local renewalRequest = requestByAction(log, "AddPortMapping")
    local deletionStarted = handle:delete(0.6)
    local deleted = handle:update(0.7)
    local deleteRequest = requestByAction(log, "DeletePortMapping")
    check("upnp_mapping_adapter_requires_owned_exact_delete_ack_before_close",
        renewalStarted and renewed and renewed.kind == "mapped"
        and renewed.externalPort == 40000
        and renewalRequest and renewalRequest.context.requestedPort == 40000
        and renewalRequest.context.internalPort == 22122
        and deletionStarted == nil and deleted and deleted.kind == "deleted"
        and deleteRequest and deleteRequest.context.action == "DeletePortMapping"
        and deleteRequest.context.externalPort == 40000
        and handle:close())

    local fallbackLog, fallbackChanged = {}, { value = false }
    local fallbackHandle = assert((assert(newAdapter(route(), fallbackLog,
        "fault", fallbackChanged))):start(request()))
    fallbackHandle:update(0)
    fallbackHandle:update(0.1)
    fallbackHandle:update(0.2)
    local faultHandled = fallbackHandle:update(0.3)
    local fixedMapped = fallbackHandle:update(0.4)
    check("upnp_mapping_adapter_falls_back_to_finite_addport_after_exact_addany_fault",
        faultHandled == nil and fixedMapped and fixedMapped.kind == "mapped"
        and fixedMapped.externalPort == 22122
        and requestByAction(fallbackLog, "AddAnyPortMapping") ~= nil
        and requestByAction(fallbackLog, "AddPortMapping") ~= nil
        and fallbackHandle:delete(0.5) == nil
        and fallbackHandle:update(0.6).kind == "deleted"
        and fallbackHandle:close())

    local pendingLog, pendingChanged = {}, { value = false }
    local pending = assert((assert(newAdapter(route(), pendingLog, true,
        pendingChanged))):start(request()))
    pending:update(0)
    pending:update(0.1)
    pending:update(0.2)
    pending:update(0.3)
    local timedOut = pending:update(8.3)
    local cleanupStarted = pending:delete(8.3)
    local expiry = pending:cleanupExpiresAt()
    local earlyClose = pending:close()
    local expiredClose = pending:close(expiry)
    check("upnp_mapping_adapter_waits_finite_lease_after_uncertain_http_mapping",
        timedOut and timedOut.kind == "failed" and cleanupStarted == nil
        and math.abs(expiry - 120.3) < 0.000001 and earlyClose == false
        and expiredClose == true and pending:cleanupExpiresAt() == nil)

    local routeLossLog, routeLoss = {}, { value = false }
    local routeLossAdapter = assert(newAdapter(route(), routeLossLog,
        false, routeLoss))
    local routeLossNow = 0
    local routeLossReachability = assert(Reachability.new({
        methods = { routeLossAdapter },
        clock = function() return routeLossNow end,
    }))
    local routeLossStarted = routeLossReachability:start(request({ now = 0 }))
    routeLossReachability:update(0)
    routeLossNow = 0.1
    routeLossReachability:update(routeLossNow)
    routeLossNow = 0.2
    routeLossReachability:update(routeLossNow)
    routeLossNow = 0.3
    routeLossReachability:update(routeLossNow)
    local routeLossCandidate = routeLossReachability:candidate()
    routeLoss.value = true
    routeLossNow = 0.4
    local routeLossStopped, routeLossCleanup = routeLossReachability:stop()
    local upnpCleanupExpiry = routeLossReachability:snapshot().cleanupExpiresAt
    routeLossNow = upnpCleanupExpiry or 0
    local upnpExpiryUpdate = routeLossReachability:update(routeLossNow)
    local upnpFinalStop, upnpFinalCleanup = routeLossReachability:stop()
    local upnpFinalSnapshot = routeLossReachability:snapshot()
    check("reachability_closes_upnp_local_sockets_after_route_lost_mapping_lease_expires",
        routeLossStarted and routeLossCandidate
        and routeLossCandidate.externalPort == 40000
        and not routeLossStopped and routeLossCleanup == true
        and math.abs((upnpCleanupExpiry or 0) - 120.3) < 0.000001
        and upnpExpiryUpdate == true
        and upnpFinalStop == true and upnpFinalCleanup == false
        and upnpFinalSnapshot.status == "stopped"
        and upnpFinalSnapshot.cleanupRequired == false)

    local changedLog, routeChanged = {}, { value = true }
    local changedHandle = assert((assert(newAdapter(route(), changedLog, false,
        routeChanged))):start(request()))
    local changedEvent = changedHandle:update(0)
    check("upnp_mapping_adapter_revalidates_network_before_first_packet",
        changedEvent and changedEvent.kind == "failed" and #changedLog == 0
        and changedHandle:delete(0) == true and changedHandle:close())
end

return Test
