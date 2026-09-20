-- Secure, exact-address IPv4 listener used before PCP/NAT-PMP mapping.
--
-- ENet in this project is IPv4-only.  Dual-stack Direct Play therefore uses
-- this listener beside the existing authenticated IPv6 opening/bridge, never
-- a wildcard or IPv4-mapped dual-mode socket.
local DirectInvite = require("src.net.direct_invite")
local DirectTransport = require("src.net.transport_direct")
local EnetTransport = require("src.net.transport_enet")
local IpScope = require("src.net.ip_scope")

local DirectIpv4Listener = {
    IPV6_POLICY = "separate_authenticated_listener",
}

local Listener = {}
Listener.__index = Listener

local function wholeNumber(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
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
        if not wholeNumber(route.interfaceIndex, 1, 4294967295)
            or type(route.networkGeneration) ~= "string"
            or route.networkGeneration == "" then
            return false
        end
    elseif route.interfaceIndex ~= nil
        or type(route.networkGeneration) ~= "string"
        or route.networkGeneration == "" then
        return false
    end
    local internal = IpScope.classify(route.internalAddress)
    return internal.isGlobal == true or internal.reason == "private_use"
        or internal.reason == "carrier_grade_nat"
end

local function providerShape(provider)
    return type(provider) == "table"
        and provider.productionReady == true
        and type(provider.randomBytes) == "function"
end

local function closeTransport(transport)
    if not transport then return true end
    local ok, result = pcall(transport.close, transport, 0, true)
    return ok and result == true
end

local function oneUseFactory(listener)
    local factory = {}
    function factory.createHost(options)
        options = type(options) == "table" and options or {}
        if listener.closed or listener.taken or not listener.transport then
            return nil, "The secure IPv4 listener is unavailable."
        end
        if options.bind ~= listener.route.internalAddress
            or tonumber(options.port) ~= listener.port then
            return nil, "The secure IPv4 listener address changed."
        end
        local transport = listener.transport
        listener.transport = nil
        listener.handedTransport = transport
        listener.taken = true
        return transport
    end
    function factory.close()
        return listener:close()
    end
    factory.dispose = factory.close
    return factory
end

function DirectIpv4Listener.open(options)
    options = type(options) == "table" and options or {}
    local route = options.route
    local port = tonumber(options.port)
    local provider = options.provider
    if not validRoute(route) or not wholeNumber(port, 1, 65535)
        or not providerShape(provider) then
        return nil, "Secure IPv4 listener options are invalid."
    end

    local key = DirectInvite.generateKey(provider.randomBytes)
    if not key then return nil, "Secure IPv4 listener entropy is unavailable." end
    local secureFactory = DirectTransport.newFactory({
        baseFactory = options.baseFactory or EnetTransport,
        cryptoProvider = provider,
        key = key,
        clock = options.clock,
        handshakeTimeout = options.handshakeTimeout,
    })
    if not secureFactory then return nil, "Secure IPv4 transport is unavailable." end
    local transport = secureFactory.createHost({
        bind = route.internalAddress,
        port = port,
        maxGuests = options.maxGuests or 3,
        channels = options.channels or 3,
        enet = options.enet,
    })
    if not transport
        or transport.endpoint ~= route.internalAddress .. ":" .. tostring(port) then
        if transport then closeTransport(transport) end
        pcall(secureFactory.close)
        return nil, "Secure IPv4 listener binding failed."
    end

    local listener = setmetatable({
        state = "bound",
        route = {
            family = route.family,
            platform = route.platform,
            internalAddress = route.internalAddress,
            gatewayAddress = route.gatewayAddress,
            interfaceIndex = route.interfaceIndex,
            networkGeneration = route.networkGeneration,
            routeFingerprint = route.routeFingerprint,
        },
        port = port,
        provider = provider,
        key = key,
        transport = transport,
        secureFactory = secureFactory,
        invitationCode = nil,
        taken = false,
        closed = false,
    }, Listener)
    listener.factory = oneUseFactory(listener)
    return listener
end

function Listener:mappingRequest(requestedLifetime, suggestedExternalPort)
    if self.closed or self.state ~= "bound" then return nil, "Listener is not bound." end
    requestedLifetime = requestedLifetime or 2 * 60 * 60
    suggestedExternalPort = suggestedExternalPort == nil and self.port
        or suggestedExternalPort
    if not wholeNumber(requestedLifetime, 1, 24 * 60 * 60)
        or not wholeNumber(suggestedExternalPort, 0, 65535) then
        return nil, "Mapping request is invalid."
    end
    return {
        internalAddress = self.route.internalAddress,
        internalPort = self.port,
        gatewayAddress = self.route.gatewayAddress,
        suggestedExternalPort = suggestedExternalPort,
        requestedLifetime = requestedLifetime,
    }
end

function Listener:publish(candidate)
    if self.closed or self.state ~= "bound" or type(candidate) ~= "table"
        or not IpScope.isGlobal(candidate.externalAddress)
        or not wholeNumber(candidate.externalPort, 1, 65535)
        or (candidate.method ~= "pcp" and candidate.method ~= "nat_pmp"
            and candidate.method ~= "manual") then
        return nil, "Mapped IPv4 endpoint is invalid."
    end
    local code = DirectInvite.encode(candidate.externalAddress .. ":"
        .. tostring(candidate.externalPort), self.key)
    if not code then return nil, "Mapped IPv4 invitation could not be created." end
    self.invitationCode = code
    self.state = "published"
    return code
end

function Listener:invitation()
    return self.state == "published" and self.invitationCode or nil
end

function Listener:unpublish()
    if self.closed then return false end
    self.invitationCode = nil
    self.state = "bound"
    return true
end

function Listener:transportFactory()
    if self.closed then return nil end
    return self.factory
end

function Listener:close()
    if self.closed then return self.closeOk == true end
    local ownedTransportOk = closeTransport(self.transport)
    local handedTransportOk = closeTransport(self.handedTransport)
    local transportOk = ownedTransportOk and handedTransportOk
    self.transport = nil
    self.handedTransport = nil
    local factoryOk = true
    if self.secureFactory then
        local ok, result = pcall(self.secureFactory.close)
        factoryOk = ok and result == true
    end
    self.secureFactory = nil
    self.key = nil
    self.invitationCode = nil
    self.provider = nil
    self.state = "closed"
    self.closed = true
    self.closeOk = transportOk and factoryOk
    return self.closeOk
end

function DirectIpv4Listener.clientFactory(code, options)
    options = type(options) == "table" and options or {}
    local parsed = DirectInvite.parse(code)
    if not parsed or parsed.isIPv4 ~= true or not IpScope.isGlobal(parsed.host)
        or not providerShape(options.provider) then
        return nil, "Secure IPv4 invitation is invalid."
    end
    local factory = DirectTransport.newFactory({
        baseFactory = options.baseFactory or EnetTransport,
        cryptoProvider = options.provider,
        key = parsed.psk,
        clock = options.clock,
        handshakeTimeout = options.handshakeTimeout,
    })
    if not factory then return nil, "Secure IPv4 transport is unavailable." end
    return factory, parsed.endpoint
end

return DirectIpv4Listener
