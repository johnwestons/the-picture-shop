local Address = require("src.net.address")
local DirectOpening = require("src.net.direct_opening")
local DirectOpeningCode = require("src.net.direct_opening_code")
local DirectTransport = require("src.net.transport_direct")
local EnetTransport = require("src.net.transport_enet")
local Ipv6Address = require("src.net.ipv6_address")
local BridgeTransport = require("src.net.transport_ipv6_bridge")

local DirectConnection = {
    DEFAULT_OUTER_PORT = 22123,
    DEFAULT_LIFETIME_SECONDS = DirectOpeningCode.DEFAULT_LIFETIME,
}

local Connection = {}
Connection.__index = Connection

local ERROR_UNAVAILABLE = "Direct Internet Play is not available in this build."
local ERROR_OPTIONS = "Direct Internet Play could not be initialized."
local ERROR_ADDRESS = "Enter this device's global IPv6 address."
local ERROR_SOCKET = "The Direct Internet socket could not be opened."
local ERROR_HOST_CODE = "The host code is invalid or expired."
local ERROR_RESPONSE_CODE = "The reply code is invalid or does not match."
local ERROR_OPENING = "The authenticated Direct Internet opening failed."
local ERROR_TRANSPORT = "The encrypted Direct Internet transport could not start."
local ERROR_STATE = "That Direct Internet action is not available now."

local function wholeNumber(value, minimum, maximum)
    return type(value) == "number" and value == value
        and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function closeSocket(socket)
    if not socket then return true end
    local ok, result = pcall(socket.close, socket)
    return ok and result ~= nil and result ~= false
end

local function closeOpening(opening)
    if not opening then return true end
    local ok, result = pcall(opening.close, opening)
    return ok and result == true
end

local function closeFactory(factory)
    if not factory or type(factory.close) ~= "function" then return factory == nil end
    local ok, result = pcall(factory.close, factory)
    return ok and result == true
end

local function providerShape(provider)
    return type(provider) == "table"
        and provider.productionReady == true
        and type(provider.randomBytes) == "function"
        and type(provider.responseTag) == "function"
        and type(provider.verifyResponseTag) == "function"
        and type(provider.newOpeningHost) == "function"
        and type(provider.newOpeningGuest) == "function"
        and type(provider.newBridgeHost) == "function"
        and type(provider.newBridgeGuest) == "function"
        and type(provider.newInitiator) == "function"
        and type(provider.newResponder) == "function"
end

local function socketModuleShape(socketModule)
    return type(socketModule) == "table"
        and type(socketModule.udp6) == "function"
        and type(socketModule.udp) == "function"
end

local function socketShape(socket)
    local kind = type(socket)
    return (kind == "table" or kind == "userdata")
        and type(socket.settimeout) == "function"
        and type(socket.setsockname) == "function"
        and type(socket.getsockname) == "function"
        and type(socket.sendto) == "function"
        and type(socket.receivefrom) == "function"
        and type(socket.close) == "function"
end

local function successful(value)
    return value ~= nil and value ~= false
end

local function publicAddress(value)
    local parsed = Ipv6Address.parse(value)
    if not parsed or parsed.isGlobal ~= true then return nil end
    return parsed.address
end

local function createSocket(socketModule, port)
    local ok, socket = pcall(socketModule.udp6)
    if not ok or not socketShape(socket) then
        if socket then closeSocket(socket) end
        return nil
    end
    local timeoutOk, timeoutResult = pcall(socket.settimeout, socket, 0)
    local bindOk, bindResult = pcall(socket.setsockname, socket, "::", port)
    local nameOk, _, reportedPort = pcall(socket.getsockname, socket)
    -- Android's bundled LuaSocket reports the bound UDP port as a numeric
    -- string, while desktop LuaSocket reports a number.  Normalize the
    -- transport-owned value before validating it; never accept a fractional,
    -- out-of-range, or mismatched port.
    local boundPort = tonumber(reportedPort)
    if not timeoutOk or not successful(timeoutResult)
        or not bindOk or not successful(bindResult)
        or not nameOk or not wholeNumber(boundPort, 1, 65535)
        or (port ~= 0 and boundPort ~= port)
    then
        closeSocket(socket)
        return nil
    end
    return socket, boundPort
end

local function randomBytes(provider, count)
    local ok, value = pcall(provider.randomBytes, count)
    if not ok or type(value) ~= "string" or #value ~= count then return nil end
    return value
end

function DirectConnection.new(options)
    options = options or {}
    if not providerShape(options.provider) then return nil, ERROR_UNAVAILABLE end
    if not socketModuleShape(options.socketModule) then return nil, ERROR_OPTIONS end

    local wallClock = options.wallClock or os.time
    local monotonicClock = options.clock
    local lifetime = options.lifetimeSeconds or DirectConnection.DEFAULT_LIFETIME_SECONDS
    local loopbackPort = options.loopbackHostPort or Address.DEFAULT_PORT
    if type(wallClock) ~= "function"
        or (monotonicClock ~= nil and type(monotonicClock) ~= "function")
        or not wholeNumber(lifetime, DirectOpening.READY_LINGER_SECONDS + 2,
            DirectOpeningCode.MAX_LIFETIME)
        or not wholeNumber(loopbackPort, 1, 65535)
    then
        return nil, ERROR_OPTIONS
    end

    return setmetatable({
        state = "idle",
        role = nil,
        lastError = nil,
        provider = options.provider,
        socketModule = options.socketModule,
        baseFactory = options.baseFactory or EnetTransport,
        openingModule = options.openingModule or DirectOpening,
        codeModule = options.codeModule or DirectOpeningCode,
        directTransportModule = options.directTransportModule or DirectTransport,
        bridgeTransportModule = options.bridgeTransportModule or BridgeTransport,
        wallClock = wallClock,
        clock = monotonicClock,
        lifetimeSeconds = lifetime,
        loopbackHostPort = loopbackPort,
        opening = nil,
        socket = nil,
        host = nil,
        response = nil,
        hostCode = nil,
        responseCode = nil,
        transportFactory = nil,
        handedOff = false,
        lastWallTime = nil,
        resourcesReleased = false,
        cleanupOk = nil,
        cleanupOpening = nil,
        cleanupSocket = nil,
        cleanupFactory = nil,
        closeOk = nil,
        closeError = nil,
    }, Connection)
end

function Connection:_now()
    local ok, value = pcall(self.wallClock)
    if not ok or not wholeNumber(value, 0, 0xffffffff)
        or (self.lastWallTime ~= nil and value < self.lastWallTime)
    then
        return nil
    end
    self.lastWallTime = value
    return value
end

function Connection:_clearSecrets()
    self.host = nil
    self.response = nil
    self.hostCode = nil
    self.responseCode = nil
end

function Connection:_releaseResources()
    if self.resourcesReleased then return self.cleanupOk == true end
    self.resourcesReleased = true
    local opening, socket, factory = self.opening, self.socket, self.transportFactory
    self.opening, self.socket, self.transportFactory = nil, nil, nil
    local factoryOk = closeFactory(factory)
    local openingOk = closeOpening(opening)
    local socketOk = closeSocket(socket)
    if not factoryOk then self.cleanupFactory = factory end
    if not openingOk then self.cleanupOpening = opening end
    if not socketOk then self.cleanupSocket = socket end
    self:_clearSecrets()
    self.cleanupOk = factoryOk and openingOk and socketOk
    return self.cleanupOk
end

function Connection:_fail(message)
    if self.state == "handed_off" or self.state == "closed" then
        return false, ERROR_STATE
    end
    self:_releaseResources()
    self.state = "failed"
    self.lastError = message
    return false, message
end

function Connection:_remainingLifetime(now)
    if not self.host then return nil end
    local remaining = self.host.issuedAt + self.host.lifetime - now
    if not wholeNumber(remaining, DirectOpening.READY_LINGER_SECONDS + 1,
        DirectOpeningCode.MAX_LIFETIME) then
        return nil
    end
    return remaining
end

function Connection:_beginOpening(role, now)
    local remaining = self:_remainingLifetime(now)
    if not remaining then return self:_fail(ERROR_HOST_CODE) end
    local createOk, opening, openingError = pcall(self.openingModule.create, {
        role = role,
        socket = self.socket,
        ownsSocket = true,
        provider = self.provider,
        host = self.host,
        response = self.response,
        timeoutSeconds = remaining,
        clock = self.clock,
    })
    if not createOk or not opening then
        closeSocket(self.socket)
        self.socket = nil
        return self:_fail(openingError and ERROR_OPENING or ERROR_OPENING)
    end
    self.opening = opening
    self.socket = nil
    self.state = "opening"
    self.lastError = nil
    return true
end

function Connection:startHost(localAddress, port)
    if self.state ~= "idle" then return false, ERROR_STATE end
    local address = publicAddress(localAddress)
    port = port == nil and DirectConnection.DEFAULT_OUTER_PORT or tonumber(port)
    if not address then return false, ERROR_ADDRESS end
    if not wholeNumber(port, 1, 65535) or port == self.loopbackHostPort then
        return false, ERROR_SOCKET
    end

    local now = self:_now()
    if not now then return self:_fail(ERROR_OPTIONS) end
    local socket, boundPort = createSocket(self.socketModule, port)
    if not socket then return self:_fail(ERROR_SOCKET) end
    self.socket = socket

    local invitationId = randomBytes(self.provider,
        self.codeModule.INVITATION_ID_BYTES or 16)
    local masterKey = randomBytes(self.provider,
        self.codeModule.MASTER_KEY_BYTES or 32)
    if not invitationId or not masterKey then return self:_fail(ERROR_OPTIONS) end

    local host = {
        kind = "host",
        version = 2,
        issuedAt = now,
        lifetime = self.lifetimeSeconds,
        address = address,
        port = boundPort,
        invitationId = invitationId,
        masterKey = masterKey,
    }
    local hostCode = self.codeModule.encodeHost(host)
    if not hostCode then return self:_fail(ERROR_OPTIONS) end
    local parsedHost = self.codeModule.parseHost(hostCode, now, {
        futureSkew = 0,
        expiryGrace = 0,
    })
    if not parsedHost then return self:_fail(ERROR_OPTIONS) end

    self.role = "host"
    self.host = parsedHost
    self.hostCode = hostCode
    self.state = "awaiting_response"
    self.lastError = nil
    return true, hostCode
end

function Connection:submitResponse(responseCode)
    if self.state ~= "awaiting_response" or self.role ~= "host" then
        return false, ERROR_STATE
    end
    local now = self:_now()
    if not now or not self:_remainingLifetime(now) then
        return self:_fail(ERROR_HOST_CODE)
    end
    local parseOk, response = pcall(self.codeModule.parseResponse, responseCode)
    if not parseOk or not response then return false, ERROR_RESPONSE_CODE end
    local verifyOk, verified = pcall(self.codeModule.verifyResponse,
        self.host, response, self.provider.verifyResponseTag)
    if not verifyOk or not verified then return false, ERROR_RESPONSE_CODE end
    self.response = verified
    self.responseCode = nil
    return self:_beginOpening("host", now)
end

function Connection:startGuest(hostCode, localAddress)
    if self.state ~= "idle" then return false, ERROR_STATE end
    local now = self:_now()
    if not now then return self:_fail(ERROR_OPTIONS) end
    local host = self.codeModule.parseHost(hostCode, now, {
        futureSkew = self.codeModule.DEFAULT_CLOCK_SKEW or 300,
        expiryGrace = 0,
    })
    local address = publicAddress(localAddress)
    if not host then return false, ERROR_HOST_CODE end
    if not address then return false, ERROR_ADDRESS end
    if host.port == self.loopbackHostPort then return false, ERROR_HOST_CODE end

    local socket, boundPort = createSocket(self.socketModule, host.port)
    if not socket then return self:_fail(ERROR_SOCKET) end
    self.socket = socket
    self.host = host

    local guestNonce = randomBytes(self.provider,
        self.codeModule.GUEST_NONCE_BYTES or 16)
    if not guestNonce then return self:_fail(ERROR_OPTIONS) end
    local response = {
        kind = "response",
        version = 2,
        issuedAt = host.issuedAt,
        lifetime = host.lifetime,
        address = address,
        port = boundPort,
        invitationId = host.invitationId,
        guestNonce = guestNonce,
    }
    local transcript = self.codeModule.responseTranscript(host, response)
    if not transcript then return self:_fail(ERROR_OPTIONS) end
    local tagOk, responseTag = pcall(
        self.provider.responseTag, host.masterKey, transcript)
    if not tagOk or type(responseTag) ~= "string"
        or #responseTag ~= (self.codeModule.RESPONSE_TAG_BYTES or 32)
    then
        return self:_fail(ERROR_OPTIONS)
    end
    response.responseTag = responseTag
    local responseCode = self.codeModule.encodeResponse(response)
    local parsedResponse = responseCode and self.codeModule.parseResponse(responseCode)
    if not parsedResponse then return self:_fail(ERROR_OPTIONS) end

    self.role = "guest"
    self.response = parsedResponse
    self.responseCode = responseCode
    local opened, openingError = self:_beginOpening("guest", now)
    if not opened then return false, openingError end
    return true, responseCode
end

function Connection:_buildTransport()
    local host, response = self.host, self.response
    local readyOk, ready = false, false
    if self.opening and type(self.opening.isReady) == "function" then
        readyOk, ready = pcall(self.opening.isReady, self.opening)
    end
    if not host or not response or not self.opening or ready ~= true
    then
        return self:_fail(ERROR_OPENING)
    end

    local secureOk, secureFactory = pcall(self.directTransportModule.newFactory, {
        baseFactory = self.baseFactory,
        cryptoProvider = self.provider,
        key = host.masterKey,
        handshakeTimeout = 20,
    })
    if not secureOk or not secureFactory or type(secureFactory.close) ~= "function" then
        return self:_fail(ERROR_TRANSPORT)
    end
    self.transportFactory = secureFactory
    local peerAddress = self.role == "host" and response.address or host.address
    local peerPort = self.role == "host" and response.port or host.port
    local bridgeOk, bridgeFactory = pcall(self.bridgeTransportModule.newFactory, {
        role = self.role,
        baseFactory = secureFactory,
        socketModule = self.socketModule,
        opening = self.opening,
        provider = self.provider,
        masterKey = host.masterKey,
        invitationId = host.invitationId,
        guestNonce = response.guestNonce,
        peerAddress = peerAddress,
        peerPort = peerPort,
        loopbackHostPort = self.loopbackHostPort,
    })
    if not bridgeOk or not bridgeFactory or type(bridgeFactory.close) ~= "function" then
        return self:_fail(ERROR_TRANSPORT)
    end

    self.transportFactory = bridgeFactory
    -- The bridge factory now owns the authenticated opening and the secure
    -- base factory. Connection must not attempt to close either separately.
    self.opening = nil
    self.state = "ready"
    self.lastError = nil
    return true
end

function Connection:update()
    if self.state == "awaiting_response" then
        local now = self:_now()
        if not now or not self:_remainingLifetime(now) then
            self:_fail(ERROR_HOST_CODE)
        end
        return self.state, self.lastError
    end
    if self.state ~= "opening" then return self.state, self.lastError end

    local ok, status, errorMessage = pcall(self.opening.update, self.opening)
    if not ok or errorMessage or status == "failed" then
        self:_fail(ERROR_OPENING)
        return self.state, self.lastError
    end
    if status == "ready" then
        local buildOk = pcall(self._buildTransport, self)
        if not buildOk then self:_fail(ERROR_TRANSPORT) end
    end
    return self.state, self.lastError
end

Connection.poll = Connection.update

function Connection:code()
    if self.state == "awaiting_response" and self.role == "host" then
        return self.hostCode
    end
    if self.state == "opening" and self.role == "guest" then
        return self.responseCode
    end
    return nil
end

function Connection:takeTransportFactory()
    if self.state ~= "ready" or not self.transportFactory or self.handedOff then
        return nil, ERROR_STATE
    end
    local factory, role = self.transportFactory, self.role
    self.transportFactory = nil
    self.opening = nil
    self.handedOff = true
    self.resourcesReleased = true
    self.cleanupOk = true
    self.state = "handed_off"
    self.lastError = nil
    self:_clearSecrets()
    return factory, role
end

function Connection:close()
    if self.state == "closed" then
        if self.closeOk == true then return true end
        return false, self.closeError or ERROR_OPENING
    end
    if self.state == "handed_off" then
        self.state = "closed"
        self.lastError = nil
        self.closeOk = true
        self.closeError = nil
        return true
    end
    local cleaned = self:_releaseResources()
    self.state = "closed"
    self.lastError = nil
    if not cleaned then self.lastError = ERROR_OPENING end
    self.closeOk = cleaned
    self.closeError = self.lastError
    return self.closeOk, self.closeError
end

DirectConnection.ERROR_UNAVAILABLE = ERROR_UNAVAILABLE
DirectConnection.ERROR_ADDRESS = ERROR_ADDRESS
DirectConnection.ERROR_HOST_CODE = ERROR_HOST_CODE
DirectConnection.ERROR_RESPONSE_CODE = ERROR_RESPONSE_CODE

return DirectConnection
