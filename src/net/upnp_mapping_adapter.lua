-- Exact-network-bound UPnP IGD2/IGD1 mapping adapter for Reachability.
-- Discovery is restricted to the selected default gateway. Description and
-- SOAP HTTP requests are connected directly to that same numeric IPv4 origin.
local GatewayDiscovery = require("src.net.gateway_discovery")
local IpScope = require("src.net.ip_scope")
local UpnpIgd = require("src.net.upnp_igd")
local WindowsTransport = require("src.net.upnp_transport_windows")

local UpnpMappingAdapter = {}

local DISCOVERY_SECONDS = 5
local DISCOVERY_RETRY_SECONDS = 2.5
local IGD1_GRACE_SECONDS = 0.5
local HTTP_TIMEOUT_SECONDS = 8
local MAX_DISCOVERY_READS = 32
local DESCRIPTION_RESPONSE_BYTES = UpnpIgd.MAX_DESCRIPTION_BYTES
    + UpnpIgd.MAX_HTTP_HEADER_BYTES + 65536
local SOAP_RESPONSE_BYTES = UpnpIgd.MAX_SOAP_BODY_BYTES
    + UpnpIgd.MAX_HTTP_HEADER_BYTES + 16384

local OWNED = setmetatable({}, { __mode = "k" })

local function finite(value)
    return type(value) == "number" and value >= 0 and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function whole(value, minimum, maximum)
    return finite(value) and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function copied(value)
    local result = {}
    for key, item in pairs(value or {}) do result[key] = item end
    return result
end

local function localAddress(value)
    local classification = IpScope.classify(value)
    return classification.reason == "private_use"
        or classification.reason == "link_local"
end

local function validRoute(route)
    return type(route) == "table" and route.platform == "Windows"
        and route.family == 4 and localAddress(route.internalAddress)
        and localAddress(route.gatewayAddress)
        and route.internalAddress ~= route.gatewayAddress
        and whole(route.interfaceIndex, 1, 4294967295)
        and type(route.networkGeneration) == "string"
        and route.networkGeneration ~= "" and #route.networkGeneration <= 128
        and type(route.routeFingerprint) == "string"
        and route.routeFingerprint ~= ""
end

local function exactRoute(left, right)
    return validRoute(left) and validRoute(right)
        and left.platform == right.platform
        and left.internalAddress == right.internalAddress
        and left.gatewayAddress == right.gatewayAddress
        and left.interfaceIndex == right.interfaceIndex
        and left.networkGeneration == right.networkGeneration
        and left.routeFingerprint == right.routeFingerprint
end

local function validRequest(request, route)
    return type(request) == "table"
        and request.internalAddress == route.internalAddress
        and request.gatewayAddress == route.gatewayAddress
        and whole(request.internalPort, UpnpIgd.MIN_UNPRIVILEGED_PORT, 65535)
        and whole(request.suggestedExternalPort, 0, 65535)
        and whole(request.requestedLifetime, 1, UpnpIgd.MAX_LEASE_SECONDS)
end

local function exactProof(proof, route)
    return type(proof) == "table" and proof.exactNetworkBinding == true
        and proof.family == 4 and proof.internalAddress == route.internalAddress
        and proof.gatewayAddress == route.gatewayAddress
        and proof.interfaceIndex == route.interfaceIndex
        and proof.networkGeneration == route.networkGeneration
        and proof.routeFingerprint == route.routeFingerprint
        and whole(proof.localPort, 1, 65535)
end

local function discoveryShape(socket)
    return type(socket) == "table" and type(socket.sendto) == "function"
        and type(socket.receivefrom) == "function"
        and type(socket.bindingProof) == "function"
        and type(socket.close) == "function"
end

local function httpShape(handle)
    return type(handle) == "table" and type(handle.update) == "function"
        and type(handle.requestSent) == "function"
        and type(handle.bindingProof) == "function"
        and type(handle.close) == "function"
end

local function defaultRevalidate(snapshot)
    local current = GatewayDiscovery.revalidate(snapshot)
    if exactRoute(snapshot, current) then return current end
    return nil
end

local function revalidate(state)
    local ok, current = pcall(state.revalidate, copied(state.route))
    return ok and exactRoute(state.route, current)
end

local function closeDiscovery(state)
    if not state.discovery then return true end
    local ok, result = pcall(state.discovery.close, state.discovery)
    state.discovery = nil
    return ok and result ~= false
end

local function closeHttp(state)
    if not state.http then return true end
    local ok, result = pcall(state.http.close, state.http)
    state.http = nil
    state.httpRequest = nil
    state.httpKind = nil
    state.httpStartedAt = nil
    return ok and result ~= false
end

local function beginHttp(state, request, kind, now, maxResponseBytes)
    if not revalidate(state) or state.http then return false end
    local ok, handle = pcall(state.transport.openHttp,
        state.route, request, maxResponseBytes)
    if not ok or not httpShape(handle) then
        if type(handle) == "table" and type(handle.close) == "function" then
            pcall(handle.close, handle)
        end
        return false
    end
    local proofOk, proof = pcall(handle.bindingProof, handle)
    if not proofOk or not exactProof(proof, state.route) then
        pcall(handle.close, handle)
        return false
    end
    state.http, state.httpRequest = handle, request
    state.httpKind, state.httpStartedAt = kind, now
    return true
end

local function trustedResponse(state, transportResponse, maximumBodyBytes)
    if type(transportResponse) ~= "table" or type(transportResponse.raw) ~= "string"
        or transportResponse.peerAddress ~= state.route.gatewayAddress
        or transportResponse.peerPort ~= state.httpRequest.port then
        return nil
    end
    local parsed = UpnpIgd.parseHttpResponse(transportResponse.raw, maximumBodyBytes)
    if not parsed then return nil end
    parsed.finalUrl = state.httpRequest.url
    parsed.peerAddress = transportResponse.peerAddress
    parsed.peerPort = transportResponse.peerPort
    parsed.redirectCount = 0
    return parsed
end

local function mappingOptions(state, externalPort)
    return {
        internalPort = state.request.internalPort,
        externalPort = externalPort,
        internalClient = state.route.internalAddress,
        controlPointAddress = state.route.internalAddress,
        leaseSeconds = state.request.requestedLifetime,
        description = "The Picture Shop co-op",
    }
end

local function initialExternalPort(state)
    local suggested = state.request.suggestedExternalPort
    if suggested < UpnpIgd.MIN_UNPRIVILEGED_PORT then
        return state.request.internalPort
    end
    return suggested
end

local function beginMapping(state, now, renewal)
    local request, requestError
    if renewal then
        request, requestError = UpnpIgd.buildAddPortMapping(
            state.service, mappingOptions(state, state.externalPort))
    elseif state.service.supportsAddAnyPortMapping and not state.addAnyRejected then
        request, requestError = UpnpIgd.buildAddAnyPortMapping(
            state.service, mappingOptions(state, initialExternalPort(state)))
    else
        request, requestError = UpnpIgd.buildAddPortMapping(
            state.service, mappingOptions(state, initialExternalPort(state)))
    end
    if not request then return false, requestError end
    state.phase = renewal and "renew" or "add"
    return beginHttp(state, request, state.phase, now, SOAP_RESPONSE_BYTES)
end

local function updatePossibleLease(state, now)
    if not state.http or (state.httpKind ~= "add" and state.httpKind ~= "renew") then return end
    local ok, sent = pcall(state.http.requestSent, state.http)
    if ok and sent == true and not state.httpTransmissionRecorded then
        state.httpTransmissionRecorded = true
        local possible = now + state.request.requestedLifetime
        state.possibleExpiresAt = math.max(state.possibleExpiresAt or 0, possible)
    end
end

local function beginDelete(state, now)
    if not state.mappingHandle then
        if state.possibleExpiresAt then
            state.phase = "delete_wait"
            return nil
        end
        state.phase, state.deleted = "deleted", true
        return true
    end
    if now >= state.mappingHandle.expiresAt then
        state.mappingHandle = nil
        if state.possibleExpiresAt and now < state.possibleExpiresAt then
            state.phase = "delete_wait"
            return nil
        end
        state.possibleExpiresAt = nil
        state.phase, state.deleted = "deleted", true
        return true
    end
    local request = UpnpIgd.buildDeletePortMapping(state.service, state.mappingHandle, {
        nowSeconds = now,
        networkEpoch = state.route.networkGeneration,
    })
    if not request then
        state.phase = "delete_wait"
        return nil
    end
    state.phase = "delete"
    if not beginHttp(state, request, "delete", now, SOAP_RESPONSE_BYTES) then
        state.phase = "delete_wait"
    end
    return nil
end

local function finishHttpFailure(state, now)
    updatePossibleLease(state, now)
    closeHttp(state)
    state.httpTransmissionRecorded = false
    if state.deleting then
        state.phase = "delete_wait"
        return nil
    end
    return { kind = "failed" }
end

local function processDescription(state, response, now)
    local parsed = trustedResponse(state, response, UpnpIgd.MAX_DESCRIPTION_BYTES)
    closeHttp(state)
    if not parsed then return { kind = "failed" } end
    local description = UpnpIgd.parseDeviceDescription(parsed, state.discoveryResult)
    if not description then return { kind = "failed" } end
    state.service = description.service
    local request = UpnpIgd.buildGetExternalIPAddress(state.service)
    if not request or not beginHttp(state, request, "external", now, SOAP_RESPONSE_BYTES) then
        return { kind = "failed" }
    end
    state.phase = "external"
end

local function processExternal(state, response, now)
    local parsed = trustedResponse(state, response, UpnpIgd.MAX_SOAP_BODY_BYTES)
    local request = state.httpRequest
    closeHttp(state)
    if not parsed then return { kind = "failed" } end
    local result = UpnpIgd.parseSoapResponse(parsed, request)
    if not result or result.success ~= true or result.addressIsGlobal ~= true then
        return { kind = "failed" }
    end
    state.externalAddress = result.externalAddress
    if not beginMapping(state, now, false) then return { kind = "failed" } end
end

local function processMapping(state, response, now, renewal)
    updatePossibleLease(state, now)
    local parsed = trustedResponse(state, response, UpnpIgd.MAX_SOAP_BODY_BYTES)
    local request = state.httpRequest
    closeHttp(state)
    state.httpTransmissionRecorded = false
    if not parsed then return { kind = "failed" } end
    local result = UpnpIgd.parseSoapResponse(parsed, request, {
        nowSeconds = now,
        networkEpoch = state.route.networkGeneration,
    })
    if not result or result.success ~= true or not result.mappingHandle then
        -- A validated SOAP fault is proof the requested mapping was rejected.
        if result and result.success == false then
            state.possibleExpiresAt = renewal and state.mappingHandle
                and state.mappingHandle.expiresAt or nil
            if not renewal and request.context.action == "AddAnyPortMapping" then
                state.addAnyRejected = true
                if beginMapping(state, now, false) then return nil end
            end
        end
        return { kind = "failed" }
    end
    state.mappingHandle = result.mappingHandle
    state.externalPort = result.externalPort
    state.possibleExpiresAt = now + state.request.requestedLifetime
    state.phase = "mapped"
    return { kind = "mapped", externalAddress = state.externalAddress,
        externalPort = state.externalPort,
        lifetime = state.request.requestedLifetime }
end

local function processDelete(state, response)
    local parsed = trustedResponse(state, response, UpnpIgd.MAX_SOAP_BODY_BYTES)
    local request = state.httpRequest
    closeHttp(state)
    if not parsed then
        state.phase = "delete_wait"
        return nil
    end
    local result = UpnpIgd.parseSoapResponse(parsed, request)
    if not result or result.success ~= true or result.cleanupConfirmed ~= true then
        state.phase = "delete_wait"
        return nil
    end
    state.mappingHandle, state.possibleExpiresAt = nil, nil
    state.deleted, state.phase = true, "deleted"
    return { kind = "deleted" }
end

local function driveHttp(state, now)
    updatePossibleLease(state, now)
    if now - state.httpStartedAt >= HTTP_TIMEOUT_SECONDS then
        return finishHttpFailure(state, now)
    end
    local ok, response, reason = pcall(state.http.update, state.http)
    updatePossibleLease(state, now)
    if not ok or response == nil and reason ~= "pending" then
        return finishHttpFailure(state, now)
    end
    if not response then return nil end
    local kind = state.httpKind
    if kind == "description" then return processDescription(state, response, now) end
    if kind == "external" then return processExternal(state, response, now) end
    if kind == "add" then return processMapping(state, response, now, false) end
    if kind == "renew" then return processMapping(state, response, now, true) end
    if kind == "delete" then return processDelete(state, response) end
    return finishHttpFailure(state, now)
end

local function chooseDiscovery(state, discovery, now)
    if discovery.searchTarget == UpnpIgd.IGD2_TARGET then
        state.discoveryResult = discovery
    elseif not state.discoveryResult then
        state.igd1Result, state.igd1FoundAt = discovery, state.igd1FoundAt or now
    end
end

local function beginDescription(state, discovery, now)
    state.discoveryResult = discovery
    if not closeDiscovery(state) then return { kind = "failed" } end
    local request = UpnpIgd.buildDescriptionRequest(discovery)
    if not request or not beginHttp(state, request, "description", now,
            DESCRIPTION_RESPONSE_BYTES) then
        return { kind = "failed" }
    end
    state.phase = "description"
end

local function driveDiscovery(state, now)
    if not state.discovery then
        if not revalidate(state) then return { kind = "failed" } end
        local ok, socket = pcall(state.transport.openDiscovery, state.route)
        if not ok or not discoveryShape(socket) then return { kind = "failed" } end
        local proofOk, proof = pcall(socket.bindingProof, socket)
        if not proofOk or not exactProof(proof, state.route) then
            pcall(socket.close, socket)
            return { kind = "failed" }
        end
        state.discovery = socket
        state.discoveryStartedAt = now
        state.discoveryDeadline = now + DISCOVERY_SECONDS
        state.discoveryRetryAt = now + DISCOVERY_RETRY_SECONDS
        state.searches = UpnpIgd.buildSearchRequests(2)
    end
    if not state.discoverySent or not state.discoveryRetried
        and now >= state.discoveryRetryAt then
        for _, search in ipairs(state.searches) do
            local sent = state.discovery:sendto(search.bytes,
                search.context.destinationAddress, search.context.destinationPort)
            if sent ~= #search.bytes then return { kind = "failed" } end
        end
        if state.discoverySent then state.discoveryRetried = true
        else state.discoverySent = true end
    end
    for _ = 1, MAX_DISCOVERY_READS do
        local packet, address = state.discovery:receivefrom()
        if not packet then
            if address ~= "timeout" then return { kind = "failed" } end
            break
        end
        for _, search in ipairs(state.searches) do
            local discovery = UpnpIgd.parseSsdpResponse(packet, {
                sourceAddress = address,
                gatewayAddress = state.route.gatewayAddress,
                expectedTarget = search.context.expectedTarget,
            })
            if discovery then chooseDiscovery(state, discovery, now) end
        end
    end
    if state.discoveryResult then return beginDescription(state, state.discoveryResult, now) end
    if state.igd1Result and now - state.igd1FoundAt >= IGD1_GRACE_SECONDS then
        return beginDescription(state, state.igd1Result, now)
    end
    if now >= state.discoveryDeadline then
        closeDiscovery(state)
        return { kind = "exhausted" }
    end
end

local Handle = {}
Handle.__index = Handle

function Handle:update(now)
    local state = OWNED[self]
    if not state or state.closed or not finite(now)
        or state.lastNow and now < state.lastNow then
        return { kind = "failed" }
    end
    state.lastNow = now
    if state.deleted then return { kind = "deleted" } end
    if state.deleting then
        if state.possibleExpiresAt and now >= state.possibleExpiresAt then
            closeHttp(state)
            state.mappingHandle, state.possibleExpiresAt = nil, nil
            state.deleted, state.phase = true, "deleted"
            return { kind = "deleted" }
        end
        if not revalidate(state) then
            closeHttp(state)
            state.phase = "delete_wait"
            return nil
        end
        if state.phase == "delete_wait" then return nil end
        if state.http then return driveHttp(state, now) end
        return beginDelete(state, now) and { kind = "deleted" } or nil
    end
    if not revalidate(state) then return { kind = "failed" } end
    if state.phase == "discovery" then return driveDiscovery(state, now) end
    if state.http then return driveHttp(state, now) end
    if state.phase == "mapped" then return nil end
    return { kind = "failed" }
end

function Handle:renew(now)
    local state = OWNED[self]
    if not state or state.closed or state.deleting or state.phase ~= "mapped"
        or not finite(now) or state.lastNow and now < state.lastNow
        or not revalidate(state) then return false end
    state.lastNow = now
    return beginMapping(state, now, true) == true
end

function Handle:delete(now)
    local state = OWNED[self]
    if not state or state.closed or not finite(now)
        or state.lastNow and now < state.lastNow then return false end
    state.lastNow, state.deleting = now, true
    updatePossibleLease(state, now)
    closeDiscovery(state)
    closeHttp(state)
    state.httpTransmissionRecorded = false
    if state.deleted then return true end
    return beginDelete(state, now)
end

function Handle:cleanupExpiresAt()
    local state = OWNED[self]
    return state and state.possibleExpiresAt or nil
end

function Handle:close()
    local state = OWNED[self]
    if not state then return true end
    if state.closed then return state.closeOk == true end
    if not state.deleted and (state.mappingHandle or state.possibleExpiresAt) then return false end
    local discoveryOk, httpOk = closeDiscovery(state), closeHttp(state)
    state.closed, state.closeOk = true, discoveryOk and httpOk
    state.service, state.mappingHandle = nil, nil
    return state.closeOk
end

local Adapter = {}
Adapter.__index = Adapter

function Adapter:start(request)
    if not validRequest(request, self.route) then return nil end
    local state = {
        route = copied(self.route), request = copied(request),
        transport = self.transport, revalidate = self.revalidate,
        phase = "discovery", closed = false, deleted = false,
        deleting = false,
    }
    local handle = setmetatable({}, Handle)
    OWNED[handle] = state
    return handle
end

function UpnpMappingAdapter.new(options)
    options = type(options) == "table" and options or {}
    local route = copied(options.route)
    if not validRoute(route) then return nil, "invalid_route" end
    local transport = options.transportFactory or WindowsTransport
    local revalidator = options.revalidate or defaultRevalidate
    if type(transport) ~= "table" or transport.exactNetworkBinding ~= true
        or type(transport.openDiscovery) ~= "function"
        or type(transport.openHttp) ~= "function"
        or type(revalidator) ~= "function" then
        return nil, "exact_upnp_transport_unavailable"
    end
    return setmetatable({ name = "upnp_igd", route = route,
        transport = transport, revalidate = revalidator,
        attemptTimeoutSeconds = false }, Adapter)
end

return UpnpMappingAdapter
