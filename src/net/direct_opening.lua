local Ipv6Address = require("src.net.ipv6_address")
local DirectOpeningCode = require("src.net.direct_opening_code")

local DirectOpening = {
    RETRY_SECONDS = 0.250,
    DEFAULT_TIMEOUT_SECONDS = 60,
    MAX_TIMEOUT_SECONDS = 15 * 60,
    MAX_RECEIVES_PER_UPDATE = 32,
    PACKET_BYTES = 92,
    READY_LINGER_SECONDS = 3,
}

local Controller = {}
Controller.__index = Controller

local ERROR_INVALID_OPTIONS = "Direct opening options are invalid."
local ERROR_INVALID_RECORDS = "Direct opening records are invalid."
local ERROR_INVALID_ENDPOINT = "Direct opening endpoint is invalid."
local ERROR_INVALID_SOCKET = "Direct opening socket is invalid."
local ERROR_PROVIDER_UNAVAILABLE = "Direct opening provider is unavailable."
local ERROR_RESPONSE_AUTHENTICATION =
    "Direct opening response authentication failed."
local ERROR_INITIALIZATION = "Direct opening initialization failed."
local ERROR_PROVIDER = "Direct opening authentication failed."
local ERROR_SOCKET = "Direct opening socket failed."
local ERROR_CLOCK = "Direct opening clock failed."
local ERROR_TIMEOUT = "Direct opening timed out."
local ERROR_CLEANUP = "Direct opening cleanup failed."

local function finiteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function integerInRange(value, minimum, maximum)
    return finiteNumber(value)
        and value == math.floor(value)
        and value >= minimum
        and value <= maximum
end

local function fixedBytes(value, length)
    return type(value) == "string" and #value == length
end

local function defaultClock()
    if love and love.timer and type(love.timer.getTime) == "function" then
        return love.timer.getTime()
    end
    return os.clock()
end

local function addressField(record, primary, alias)
    if type(record) ~= "table" then return nil end
    local primaryValue, aliasValue = record[primary], record[alias]
    if primaryValue == nil then primaryValue = aliasValue end
    if type(primaryValue) ~= "string" then return nil end

    local parsed = Ipv6Address.parse(primaryValue)
    if not parsed or parsed.isGlobal ~= true then return nil end
    if aliasValue ~= nil then
        if type(aliasValue) ~= "string" then return nil end
        local parsedAlias = Ipv6Address.parse(aliasValue)
        if not parsedAlias or parsedAlias.isGlobal ~= true
            or parsedAlias.bytes ~= parsed.bytes
        then
            return nil
        end
    end
    return parsed
end

local function portField(record, primary, alias)
    if type(record) ~= "table" then return nil end
    local primaryValue, aliasValue = record[primary], record[alias]
    if primaryValue == nil then primaryValue = aliasValue end
    if not integerInRange(primaryValue, 1, 65535) then return nil end
    if aliasValue ~= nil and aliasValue ~= primaryValue then return nil end
    return primaryValue
end

-- The controller accepts the parsed records returned by direct_opening_code.
-- It copies only their explicitly checked fields into fresh canonical records;
-- this prevents an injected `bytes` member from authenticating different
-- endpoint fields than the controller will actually use.
local function openingRecords(options)
    local host, response = options.host, options.response
    if type(host) ~= "table" or type(response) ~= "table"
        or host.kind ~= "host" or response.kind ~= "response"
        or host.version ~= 2 or response.version ~= 2
        or not integerInRange(host.issuedAt, 0, 0xffffffff)
        or response.issuedAt ~= host.issuedAt
        or not integerInRange(host.lifetime, 1, DirectOpening.MAX_TIMEOUT_SECONDS)
        or response.lifetime ~= host.lifetime
        or not fixedBytes(host.invitationId, 16)
        or response.invitationId ~= host.invitationId
        or not fixedBytes(host.masterKey, 32)
        or not fixedBytes(response.guestNonce, 16)
        or not fixedBytes(response.responseTag, 32)
    then
        return nil
    end

    local hostAddress = addressField(host, "address", "hostAddress")
    local guestAddress = addressField(response, "address", "guestAddress")
    local hostPort = portField(host, "port", "hostPort")
    local guestPort = portField(response, "port", "guestPort")
    if not hostAddress or not guestAddress or not hostPort or not guestPort then
        return nil
    end

    local canonicalHost = {
        kind = "host",
        version = 2,
        issuedAt = host.issuedAt,
        lifetime = host.lifetime,
        address = hostAddress.address,
        port = hostPort,
        invitationId = host.invitationId,
        masterKey = host.masterKey,
    }
    local canonicalResponse = {
        kind = "response",
        version = 2,
        issuedAt = response.issuedAt,
        lifetime = response.lifetime,
        address = guestAddress.address,
        port = guestPort,
        invitationId = response.invitationId,
        guestNonce = response.guestNonce,
        responseTag = response.responseTag,
    }
    return {
        host = canonicalHost,
        response = canonicalResponse,
        hostAddress = hostAddress,
        guestAddress = guestAddress,
        hostPort = hostPort,
        guestPort = guestPort,
    }
end

local function socketShape(socket)
    local valueType = type(socket)
    return (valueType == "table" or valueType == "userdata")
        and type(socket.settimeout) == "function"
        and type(socket.sendto) == "function"
        and type(socket.receivefrom) == "function"
        and type(socket.close) == "function"
end

local function stateShape(state)
    return type(state) == "table"
        and type(state.next) == "function"
        and type(state.receive) == "function"
        and type(state.isReady) == "function"
        and type(state.close) == "function"
end

local function stateCanClose(state)
    return type(state) == "table" and type(state.close) == "function"
end

local function closeValue(value)
    return value ~= nil and value ~= false
end

function Controller:_cleanup()
    if self._cleaned then return self._cleanupOk end
    self._cleaned = true

    local cleaned = true
    local state = self._state
    self._state = nil
    if state then
        local ok, result = pcall(state.close, state)
        if not ok or not closeValue(result) then cleaned = false end
    end

    local socket = self._socket
    if socket and self.ownsSocket then
        local ok, result = pcall(socket.close, socket)
        if not ok or not closeValue(result) then cleaned = false end
    end
    self._cleanupOk = cleaned
    return cleaned
end

function Controller:_fail(message)
    if self.status == "opening" or self.status == "confirming"
        or self.status == "ready" then
        self.status = "failed"
        self.lastError = message
        self:_cleanup()
    end
    return self.status, self.lastError
end

function Controller:_now()
    local ok, now = pcall(self._clock)
    if not ok or not finiteNumber(now) or now < 0
        or (self._lastNow ~= nil and now < self._lastNow)
    then
        return nil
    end
    self._lastNow = now
    return now
end

function Controller:_send(packet, now)
    if type(packet) ~= "string" or #packet ~= DirectOpening.PACKET_BYTES then
        return self:_fail(ERROR_PROVIDER)
    end

    local ok, sent = pcall(self._socket.sendto, self._socket, packet,
        self._peerAddress, self._peerPort)
    -- LuaSocket UDP returns 1 on success.  Some injected adapters return the
    -- accepted byte count instead, so both strict success forms are allowed.
    if not ok or (sent ~= 1 and sent ~= #packet) then
        return self:_fail(ERROR_SOCKET)
    end
    self._outbound = packet
    self._lastSentAt = now
    return self.status
end

function Controller:_nextAndSend(now)
    local ok, packet = pcall(self._state.next, self._state)
    if not ok or type(packet) ~= "string"
        or #packet ~= DirectOpening.PACKET_BYTES
    then
        return self:_fail(ERROR_PROVIDER)
    end
    return self:_send(packet, now)
end

function Controller:_refreshReady(now)
    local ok, ready = pcall(self._state.isReady, self._state)
    if not ok or (ready ~= true and ready ~= false) then
        return self:_fail(ERROR_PROVIDER)
    end
    if ready then
        if self.status == "opening" then
            -- Native readiness is necessary but is not yet exposed to the
            -- gameplay bridge.  Keep this exact socket alive long enough to
            -- retransmit the final authenticated flight if UDP loses it.
            self.status = "confirming"
            self._readyLingerStartedAt = now
        end
    elseif self.status == "confirming" then
        -- Native readiness is required to be monotonic.  Never complete the
        -- grace phase after a provider reports that readiness was lost.
        return self:_fail(ERROR_PROVIDER)
    end
    return self.status
end

local function exactPeer(self, address, port)
    if port ~= self._peerPort or type(address) ~= "string" then return false end
    local parsed = Ipv6Address.parse(address)
    return parsed ~= nil and parsed.isGlobal == true
        and parsed.bytes == self._peerAddressBytes
end

function Controller:update()
    if self.status ~= "opening" and self.status ~= "confirming" then
        return self.status, self.lastError
    end

    local now = self:_now()
    if not now then return self:_fail(ERROR_CLOCK) end
    if now - self._startedAt >= self.timeoutSeconds then
        return self:_fail(ERROR_TIMEOUT)
    end

    for _ = 1, DirectOpening.MAX_RECEIVES_PER_UPDATE do
        local callOk, packet, address, port = pcall(
            self._socket.receivefrom, self._socket)
        if not callOk then return self:_fail(ERROR_SOCKET) end
        if packet == nil then
            if address == "timeout" then break end
            return self:_fail(ERROR_SOCKET)
        end

        -- Endpoint and framing prefilters run before native authentication.
        -- Wrong-source floods and malformed datagrams therefore consume only
        -- this update's fixed receive budget and never create peer state.
        if type(packet) == "string" and #packet == DirectOpening.PACKET_BYTES
            and exactPeer(self, address, port)
        then
            local receiveOk, accepted = pcall(
                self._state.receive, self._state, packet)
            if not receiveOk or (accepted ~= true and accepted ~= false) then
                return self:_fail(ERROR_PROVIDER)
            end
            if accepted then
                self:_nextAndSend(now)
                if self.status == "failed" then
                    return self.status, self.lastError
                end
                self:_refreshReady(now)
                if self.status == "failed" then
                    return self.status, self.lastError
                end
            end
        end
    end

    if now - self._lastSentAt >= DirectOpening.RETRY_SECONDS then
        self:_send(self._outbound, now)
    end
    if self.status == "failed" then return self.status, self.lastError end

    if self.status == "confirming"
        and now - self._readyLingerStartedAt >= DirectOpening.READY_LINGER_SECONDS
    then
        -- Re-check the native boundary immediately before exposing readiness.
        self:_refreshReady(now)
        if self.status == "confirming" then
            self.status = "ready"
            self.lastError = nil
        end
    end
    return self.status, self.lastError
end

Controller.poll = Controller.update

function Controller:isReady()
    return self.status == "ready"
end

-- Transfer the exact authenticated UDP6 socket to the gameplay bridge.  This
-- is deliberately one-way: the opening state is destroyed first, subsequent
-- opening packets are no longer processed, and close() will not reclaim the
-- transferred socket from its new owner.
function Controller:takeSocket()
    if self.status ~= "ready" or self._cleaned or not self._socket
        or not self._state then
        return nil, ERROR_INITIALIZATION
    end
    local state = self._state
    local ok, result = pcall(state.close, state)
    if not ok or not closeValue(result) then
        return nil, select(2, self:_fail(ERROR_CLEANUP))
    end
    local socket = self._socket
    self._state = nil
    self._socket = nil
    self._cleaned = true
    self._cleanupOk = true
    self.ownsSocket = false
    self.status = "handed_off"
    self.lastError = nil
    return socket
end

function Controller:close()
    if self.status == "closed" then
        if self._cleanupOk then return true end
        return false, ERROR_CLEANUP
    end

    local cleaned = self:_cleanup()
    self.status = "closed"
    self.lastError = nil
    if not cleaned then self.lastError = ERROR_CLEANUP end
    if not cleaned then return false, ERROR_CLEANUP end
    return true
end

function DirectOpening.create(options)
    if type(options) ~= "table"
        or (options.role ~= "host" and options.role ~= "guest")
        or (options.ownsSocket ~= nil and type(options.ownsSocket) ~= "boolean")
    then
        return nil, ERROR_INVALID_OPTIONS
    end

    local timeout = options.timeoutSeconds
    if timeout == nil then timeout = DirectOpening.DEFAULT_TIMEOUT_SECONDS end
    if not finiteNumber(timeout) or timeout <= 0
        or timeout > DirectOpening.MAX_TIMEOUT_SECONDS
    then
        return nil, ERROR_INVALID_OPTIONS
    end

    local records = openingRecords(options)
    if not records then return nil, ERROR_INVALID_RECORDS end

    -- `socket` must already be bound as a nonblocking UDP6 socket.  Ownership
    -- transfers after response authentication and defaults to the controller;
    -- pass ownsSocket=false when the caller will hand this same socket to the
    -- gameplay bridge after opening succeeds.
    local socket = options.socket
    if not socketShape(socket) then return nil, ERROR_INVALID_SOCKET end
    local ownsSocket = options.ownsSocket ~= false

    local provider = options.provider
    local constructorName = options.role == "host"
        and "newOpeningHost" or "newOpeningGuest"
    if type(provider) ~= "table" or type(provider[constructorName]) ~= "function"
        or type(provider.verifyResponseTag) ~= "function"
    then
        return nil, ERROR_PROVIDER_UNAVAILABLE
    end

    -- Authenticate the response before configuring, reading, or writing the
    -- injected socket and before allocating a native opening state.  The code
    -- module catches verifier exceptions; none of their details cross this API.
    local verifiedResponse = DirectOpeningCode.verifyResponse(
        records.host, records.response, provider.verifyResponseTag)
    if not verifiedResponse then return nil, ERROR_RESPONSE_AUTHENTICATION end

    local timeoutOk, timeoutResult = pcall(socket.settimeout, socket, 0)
    if not timeoutOk or not closeValue(timeoutResult) then
        if ownsSocket then pcall(socket.close, socket) end
        return nil, ERROR_INVALID_SOCKET
    end

    local peerAddress = options.role == "host"
        and records.guestAddress or records.hostAddress
    local peerPort = options.role == "host"
        and records.guestPort or records.hostPort
    if not peerAddress or not peerAddress.isGlobal then
        if ownsSocket then pcall(socket.close, socket) end
        return nil, ERROR_INVALID_ENDPOINT
    end

    local controller = setmetatable({
        status = "opening",
        lastError = nil,
        role = options.role,
        ownsSocket = ownsSocket,
        timeoutSeconds = timeout,
        _socket = socket,
        _clock = options.clock or defaultClock,
        _peerAddress = peerAddress.address,
        _peerAddressBytes = peerAddress.bytes,
        _peerPort = peerPort,
        _cleaned = false,
        _cleanupOk = true,
    }, Controller)
    if type(controller._clock) ~= "function" then
        controller:_fail(ERROR_CLOCK)
        return nil, ERROR_INITIALIZATION
    end

    local constructor = provider[constructorName]
    local callOk, state = pcall(constructor, records.host.masterKey,
        records.host.invitationId, records.response.guestNonce)
    if not callOk or not stateShape(state) then
        -- A partially constructed native adapter may still own a native
        -- handle.  Retain it solely long enough to invoke its close method.
        if stateCanClose(state) then controller._state = state end
        controller:_fail(ERROR_PROVIDER)
        return nil, ERROR_INITIALIZATION
    end
    controller._state = state

    local now = controller:_now()
    if not now then
        controller:_fail(ERROR_CLOCK)
        return nil, ERROR_INITIALIZATION
    end
    controller._startedAt = now
    controller:_nextAndSend(now)
    if controller.status ~= "opening" then return nil, ERROR_INITIALIZATION end
    controller:_refreshReady(now)
    if controller.status == "failed" then return nil, ERROR_INITIALIZATION end
    return controller
end

return DirectOpening
