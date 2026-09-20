-- Exact-route live PCP/NAT-PMP adapters for Reachability.
--
-- The constructor is side-effect-free.  The first update revalidates the
-- captured route, opens one exact-network-bound nonblocking socket, and only
-- then sends control traffic to that route's gateway.  The same socket,
-- mapping nonce/ownership state, and route identity remain in force for
-- creation, renewal, and deletion.
local GatewayDiscovery = require("src.net.gateway_discovery")
local IpScope = require("src.net.ip_scope")
local NatPmp = require("src.net.nat_pmp")
local Pcp = require("src.net.pcp")
local UpnpMappingAdapter = require("src.net.upnp_mapping_adapter")
local WindowsSocket = require("src.net.mapping_socket_windows")

local RouterMappingAdapter = {}

local UINT16_MAX = 65535
local MAX_RECEIVES_PER_UPDATE = 16
local OWNER_TOKEN_BYTES = 16
local PCP_MAX_ATTEMPTS = 5
local NAT_PMP_MAX_ATTEMPTS = 9

local OWNED = setmetatable({}, { __mode = "k" })

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function wholeNumber(value, minimum, maximum)
    return finite(value) and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function copied(value)
    local result = {}
    for key, item in pairs(value or {}) do result[key] = item end
    return result
end

local function exactRoute(left, right)
    return type(left) == "table" and type(right) == "table"
        and left.family == 4 and right.family == 4
        and left.platform == right.platform
        and left.internalAddress == right.internalAddress
        and left.gatewayAddress == right.gatewayAddress
        and left.interfaceIndex == right.interfaceIndex
        and left.networkGeneration == right.networkGeneration
        and left.routeFingerprint == right.routeFingerprint
end

local function validRoute(route)
    if type(route) ~= "table" or route.family ~= 4
        or (route.platform ~= "Windows" and route.platform ~= "Android")
        or not IpScope.parse(route.internalAddress)
        or not IpScope.parse(route.gatewayAddress)
        or route.internalAddress == route.gatewayAddress
        or type(route.routeFingerprint) ~= "string" then
        return false
    end
    if route.platform == "Windows" then
        return wholeNumber(route.interfaceIndex, 1, 4294967295)
            and type(route.networkGeneration) == "string"
            and route.networkGeneration ~= ""
    end
    return route.interfaceIndex == nil
        and type(route.networkGeneration) == "string"
        and route.networkGeneration ~= ""
end

local function validRequest(request, route)
    return type(request) == "table"
        and request.internalAddress == route.internalAddress
        and request.gatewayAddress == route.gatewayAddress
        and wholeNumber(request.internalPort, 1, UINT16_MAX)
        and wholeNumber(request.suggestedExternalPort, 0, UINT16_MAX)
        and wholeNumber(request.requestedLifetime, 1, 24 * 60 * 60)
end

local function socketShape(socket)
    local kind = type(socket)
    return (kind == "table" or kind == "userdata")
        and type(socket.sendto) == "function"
        and type(socket.receivefrom) == "function"
        and type(socket.bindingProof) == "function"
        and type(socket.close) == "function"
end

local function validProof(proof, route)
    return type(proof) == "table" and proof.exactNetworkBinding == true
        and proof.family == 4
        and proof.internalAddress == route.internalAddress
        and proof.gatewayAddress == route.gatewayAddress
        and proof.interfaceIndex == route.interfaceIndex
        and proof.networkGeneration == route.networkGeneration
        and proof.routeFingerprint == route.routeFingerprint
end

local function defaultRevalidate(route)
    return GatewayDiscovery.revalidate(route)
end

local function revalidate(state)
    local ok, current = pcall(state.revalidate, copied(state.route))
    return ok and exactRoute(current, state.route)
end

local function randomExact(randomBytes, count)
    local ok, value = pcall(randomBytes, count)
    if not ok or type(value) ~= "string" or #value ~= count then return nil end
    return value
end

local function jittered(state, value)
    local ok, unit = pcall(state.randomUnit)
    if not ok or not finite(unit) or unit < 0 or unit > 1 then unit = 0.5 end
    return value * (0.9 + unit * 0.2)
end

local function closeSocket(state)
    if not state.socket then return true end
    local socket = state.socket
    state.socket = nil
    local ok, result = pcall(socket.close, socket)
    return ok and result == true
end

local function openSocket(state)
    if state.socket then return true end
    if not revalidate(state) then return false end
    local ok, socket = pcall(state.socketFactory.open, copied(state.route))
    if not ok or not socketShape(socket) then
        if socket and type(socket.close) == "function" then pcall(socket.close, socket) end
        return false
    end
    local proofOk, proof = pcall(socket.bindingProof, socket)
    if not proofOk or not validProof(proof, state.route) then
        pcall(socket.close, socket)
        return false
    end
    state.socket = socket
    return true
end

local function pcpPacket(state, kind)
    local request = state.request
    local lifetime = kind == "delete" and 0 or request.requestedLifetime
    local suggestedPort = 0
    local suggestedAddress = "0.0.0.0"
    if kind == "renew" and state.mapping then
        suggestedPort = state.mapping.externalPort
        suggestedAddress = state.mapping.externalAddress
    end
    return Pcp.encodeMapRequest({
        clientAddress = request.internalAddress,
        nonce = state.nonce,
        protocol = Pcp.PROTOCOL_UDP,
        internalPort = request.internalPort,
        suggestedExternalPort = kind == "create"
            and request.suggestedExternalPort or suggestedPort,
        suggestedExternalAddress = suggestedAddress,
        lifetime = lifetime,
    })
end

local function natPmpPacket(state, kind)
    if kind == "external" then return NatPmp.encodeExternalAddressRequest() end
    local suggestedPort = 0
    if kind == "create" then
        suggestedPort = state.request.suggestedExternalPort
    elseif kind == "renew" and state.mapping then
        suggestedPort = state.mapping.externalPort
    end
    return NatPmp.encodeUdpMappingRequest({
        internalPort = state.request.internalPort,
        suggestedExternalPort = suggestedPort,
        lifetime = kind == "delete" and 0 or state.request.requestedLifetime,
    })
end

local function buildOperation(state, kind)
    local packet, expected
    if state.protocol == "pcp" then
        packet, expected = pcpPacket(state, kind)
    else
        packet, expected = natPmpPacket(state, kind)
    end
    if not packet then return false end
    state.operation = {
        kind = kind,
        packet = packet,
        expected = expected,
        attempts = 0,
        nextAt = nil,
    }
    return true
end

local function maximumAttempts(state)
    return state.protocol == "pcp" and PCP_MAX_ATTEMPTS
        or NAT_PMP_MAX_ATTEMPTS
end

local function retryDelay(state, attempt)
    if state.protocol == "pcp" then
        return jittered(state, math.min(3 * 2 ^ (attempt - 1), 1024))
    end
    return 0.25 * 2 ^ (attempt - 1)
end

local function transmit(state, now)
    local operation = state.operation
    if not operation or not openSocket(state) or not revalidate(state) then
        return false
    end
    local ok, sent = pcall(state.socket.sendto, state.socket,
        operation.packet, state.route.gatewayAddress, Pcp.SERVER_PORT)
    if not ok or sent ~= #operation.packet then return false end
    operation.attempts = operation.attempts + 1
    operation.nextAt = now + retryDelay(state, operation.attempts)
    if operation.kind == "create" then
        state.creationTransmitted = true
        local possibleExpiry = now + state.request.requestedLifetime
        state.possibleExpiresAt = math.max(state.possibleExpiresAt or 0,
            possibleExpiry)
    elseif operation.kind == "renew" then
        local possibleExpiry = now + state.request.requestedLifetime
        state.possibleExpiresAt = math.max(state.possibleExpiresAt or 0,
            possibleExpiry)
    end
    return true
end

local function checkEpoch(state, epoch, now)
    local checker = state.protocol == "pcp" and Pcp.checkEpoch
        or NatPmp.checkEpoch
    local checked = checker(state.epoch, epoch, now)
    if not checked then return false, true end
    state.epoch = checked.state
    return checked.valid == true, checked.resetSuspected == true
end

local function mappedEvent(state, response, now, externalAddress)
    local address = externalAddress or response.externalAddress
    state.mapping = {
        externalAddress = address,
        externalPort = response.externalPort,
        lifetime = response.lifetime,
        expiresAt = now + response.lifetime,
    }
    state.possibleExpiresAt = state.mapping.expiresAt
    state.operation = nil
    return {
        kind = "mapped",
        externalAddress = address,
        externalPort = response.externalPort,
        lifetime = response.lifetime,
    }
end

local function processPcp(state, packet, address, port, now)
    if not Pcp.validateResponseSource(address, port,
            state.route.gatewayAddress) then return nil end
    -- RFC 6886 version negotiation uses this exact eight-byte response to
    -- say that the selected gateway supports NAT-PMP (version 0), not PCP.
    -- No PCP mapping can have been created, so cleanup is already proven and
    -- the serialized coordinator may fall back immediately.
    if #packet == 8 and packet:byte(1) == 0 and packet:byte(2) == 0
        and packet:byte(3) == 0 and packet:byte(4) == 1 then
        state.creationTransmitted = false
        state.possibleExpiresAt = nil
        state.mapping = nil
        state.deleted = true
        state.operation = nil
        return { kind = "failed" }
    end
    local operation = state.operation
    local response = Pcp.decodeMapResponse(packet, operation.expected,
        state.request.requestedLifetime)
    if not response then return nil end
    local epochValid, reset = checkEpoch(state, response.epoch, now)
    if not epochValid then
        if reset and response.success and response.wireLifetime > 0 then
            state.possibleExpiresAt = now + response.lifetime
        end
        return { kind = "epoch_reset" }
    end
    if not response.success then
        if response.resultCode == 1 then
            state.creationTransmitted = false
            state.possibleExpiresAt = nil
            state.mapping = nil
            state.deleted = true
            state.operation = nil
        end
        return { kind = "failed" }
    end
    if operation.kind == "delete" then
        state.mapping = nil
        state.possibleExpiresAt = nil
        state.deleted = true
        state.operation = nil
        return { kind = "deleted" }
    end
    return mappedEvent(state, response, now)
end

local function processNatPmp(state, packet, address, port, now)
    if not NatPmp.validateResponseSource(address, port,
            state.route.gatewayAddress) then return nil end
    local operation = state.operation
    if operation.kind == "external" then
        local response = NatPmp.decodeExternalAddressResponse(packet)
        if not response then return nil end
        local epochValid, reset = checkEpoch(state, response.epoch, now)
        if not epochValid then return reset and { kind = "epoch_reset" }
            or { kind = "failed" } end
        if not response.success then return { kind = "failed" } end
        -- NAT-PMP cannot create a useful direct endpoint behind private or
        -- carrier-grade-NAT WAN space.  Stop before asking for a mapping.
        if not IpScope.isGlobal(response.externalAddress) then
            return { kind = "failed" }
        end
        state.externalAddress = response.externalAddress
        state.operation = nil
        if not buildOperation(state, "create") then return { kind = "failed" } end
        return nil
    end

    local response = NatPmp.decodeUdpMappingResponse(packet,
        operation.expected, state.request.requestedLifetime)
    if not response then return nil end
    local epochValid, reset = checkEpoch(state, response.epoch, now)
    if not epochValid then
        if reset and response.success and response.wireLifetime
            and response.wireLifetime > 0 then
            state.possibleExpiresAt = now + response.lifetime
        end
        return { kind = "epoch_reset" }
    end
    if not response.success then return { kind = "failed" } end
    if operation.kind == "delete" then
        state.mapping = nil
        state.possibleExpiresAt = nil
        state.deleted = true
        state.operation = nil
        return { kind = "deleted" }
    end
    return mappedEvent(state, response, now, state.externalAddress)
end

local Handle = {}
Handle.__index = Handle

local function ownedState(handle)
    local state = OWNED[handle]
    if not state or state.ownerToken == nil then return nil end
    return state
end

function Handle:update(now)
    local state = ownedState(self)
    if not state or state.closed or not finite(now) or now < 0
        or (state.lastNow ~= nil and now < state.lastNow) then
        return { kind = "failed" }
    end
    state.lastNow = now
    if state.possibleExpiresAt and now >= state.possibleExpiresAt then
        state.mapping = nil
        state.possibleExpiresAt = nil
        state.deleted = true
        state.operation = nil
        return state.deleting and { kind = "deleted" } or { kind = "expired" }
    end
    if not revalidate(state) then return { kind = "failed" } end
    if not state.operation then return nil end
    if not state.socket and not openSocket(state) then return { kind = "failed" } end

    local operation = state.operation
    if operation.attempts == 0 then
        if not transmit(state, now) then return { kind = "failed" } end
    elseif now >= operation.nextAt then
        if operation.attempts >= maximumAttempts(state) then
            if operation.kind == "delete" then return nil end
            return { kind = "exhausted" }
        end
        if not transmit(state, now) then return { kind = "failed" } end
    end

    for _ = 1, MAX_RECEIVES_PER_UPDATE do
        local ok, packet, address, port = pcall(
            state.socket.receivefrom, state.socket)
        if not ok then return { kind = "failed" } end
        if packet == nil then
            if address ~= "timeout" then return { kind = "failed" } end
            break
        end
        if type(packet) == "string" and #packet <= Pcp.MAX_PACKET_BYTES then
            local event = state.protocol == "pcp"
                and processPcp(state, packet, address, port, now)
                or processNatPmp(state, packet, address, port, now)
            if event then return event end
        end
    end
    return nil
end

function Handle:renew(now)
    local state = ownedState(self)
    if not state or state.closed or state.deleting or not state.mapping
        or state.operation or not finite(now) or now < (state.lastNow or 0)
        or not revalidate(state) then
        return false
    end
    state.lastNow = now
    return buildOperation(state, "renew")
end

function Handle:delete(now)
    local state = ownedState(self)
    if not state or state.closed or not finite(now) or now < (state.lastNow or 0) then
        return false
    end
    state.lastNow = now
    if state.deleted then return true end
    if not state.creationTransmitted and not state.mapping then
        state.deleted = true
        state.operation = nil
        return true
    end
    if state.deleting then return nil end
    if not revalidate(state) then return false end
    state.deleting = true
    if not buildOperation(state, "delete") then return false end
    return nil
end

function Handle:close()
    local state = ownedState(self)
    if not state then return false end
    if state.closed then return state.closeOk == true end
    local expired = state.possibleExpiresAt and state.lastNow
        and state.lastNow >= state.possibleExpiresAt
    if (state.creationTransmitted or state.mapping)
        and not state.deleted and not expired then
        return false
    end
    state.ownerToken = nil
    state.nonce = nil
    state.operation = nil
    state.mapping = nil
    state.closed = true
    state.closeOk = closeSocket(state)
    return state.closeOk
end

local Adapter = {}
Adapter.__index = Adapter

function Adapter:start(request)
    if not validRequest(request, self.route) then return nil end
    if self.protocol == "nat_pmp"
        and IpScope.classify(request.internalAddress).reason ~= "private_use" then
        return nil
    end
    local ownerToken = randomExact(self.randomBytes, OWNER_TOKEN_BYTES)
    local nonce = self.protocol == "pcp"
        and randomExact(self.randomBytes, Pcp.NONCE_BYTES) or nil
    if not ownerToken or (self.protocol == "pcp" and not nonce) then return nil end
    local state = {
        protocol = self.protocol,
        route = copied(self.route),
        request = copied(request),
        socketFactory = self.socketFactory,
        revalidate = self.revalidate,
        randomUnit = self.randomUnit,
        ownerToken = ownerToken,
        nonce = nonce,
        lastNow = nil,
        closed = false,
        deleted = false,
        deleting = false,
    }
    local initial = self.protocol == "pcp" and "create" or "external"
    if not buildOperation(state, initial) then return nil end
    local handle = setmetatable({}, Handle)
    OWNED[handle] = state
    return handle
end

function RouterMappingAdapter.new(options)
    options = type(options) == "table" and options or {}
    local route = copied(options.route)
    if not validRoute(route) then return nil, "invalid_route" end
    local socketFactory = options.socketFactory
    if socketFactory == nil and route.platform == "Windows" then
        socketFactory = WindowsSocket
    end
    if type(socketFactory) ~= "table" or socketFactory.exactNetworkBinding ~= true
        or type(socketFactory.open) ~= "function" then
        return nil, "exact_socket_unavailable"
    end
    local randomBytes = options.randomBytes
    local randomUnit = options.randomUnit or function() return 0.5 end
    local revalidator = options.revalidate or defaultRevalidate
    if type(randomBytes) ~= "function" or type(randomUnit) ~= "function"
        or type(revalidator) ~= "function" then
        return nil, "invalid_options"
    end

    local common = {
        route = route,
        socketFactory = socketFactory,
        randomBytes = randomBytes,
        randomUnit = randomUnit,
        revalidate = revalidator,
        attemptTimeoutSeconds = false,
    }
    local pcp = setmetatable(copied(common), Adapter)
    pcp.name, pcp.protocol = "pcp", "pcp"
    local natPmp = setmetatable(copied(common), Adapter)
    natPmp.name, natPmp.protocol = "nat_pmp", "nat_pmp"
    local methods = { pcp, natPmp }
    if route.platform == "Windows" then
        local upnp = UpnpMappingAdapter.new({
            route = route,
            transportFactory = options.upnpTransportFactory,
            revalidate = revalidator,
        })
        if upnp then methods[#methods + 1] = upnp end
    end
    return methods
end

return RouterMappingAdapter
