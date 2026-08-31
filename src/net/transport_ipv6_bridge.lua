local DirectBridge = require("src.net.direct_bridge")

local BridgeTransport = {
    DEFAULT_PORT = 22122,
    MAX_GUESTS = 1,
    MAX_PEERS = 1,
    MIN_CHANNELS = 3,
    DEFAULT_CHANNELS = 3,
    MAX_EVENTS_PER_SERVICE = 64,
}

local Instance = {}
Instance.__index = Instance

local ERROR_FACTORY = "IPv6 bridge transport options are invalid."
local ERROR_OPENING = "IPv6 bridge requires an authenticated opening."
local ERROR_SOCKET = "IPv6 loopback bridge socket failed."
local ERROR_NETWORK = "IPv6 bridge network failed."
local ERROR_CLOSE = "IPv6 bridge cleanup failed."

local function wholeNumber(value, minimum, maximum)
    value = tonumber(value)
    return value and value == value and value == math.floor(value)
        and value >= minimum and value <= maximum and value or nil
end

local function methodFor(target, method)
    if target == nil then return nil end
    local ok, callable = pcall(function() return target[method] end)
    return ok and type(callable) == "function" and callable or nil
end

local function callMethod(target, method, ...)
    local callable = methodFor(target, method)
    if not callable then return false, "missing " .. tostring(method) end
    return pcall(callable, target, ...)
end

local function callFactory(factory, method, ...)
    if type(factory) ~= "table" or type(factory[method]) ~= "function" then
        return false, "missing " .. tostring(method)
    end
    return pcall(factory[method], ...)
end

local function sendSucceeded(result)
    if result == false or result == nil then return false end
    if type(result) == "number" and result < 0 then return false end
    return true
end

local function closeSocket(socket)
    if not socket then return true end
    local ok, result = pcall(socket.close, socket)
    return ok and result ~= false and result ~= nil
end

local function createLoopbackSocket(socketModule)
    if type(socketModule) ~= "table" or type(socketModule.udp) ~= "function" then
        return nil, ERROR_SOCKET
    end
    local ok, socket = pcall(socketModule.udp)
    if not ok or not socket
        or type(socket.settimeout) ~= "function"
        or type(socket.setsockname) ~= "function"
        or type(socket.getsockname) ~= "function"
        or type(socket.sendto) ~= "function"
        or type(socket.receivefrom) ~= "function"
        or type(socket.close) ~= "function" then
        if socket then closeSocket(socket) end
        return nil, ERROR_SOCKET
    end
    local timeoutOk, timeoutResult = pcall(socket.settimeout, socket, 0)
    local bindOk, bindResult = pcall(
        socket.setsockname, socket, "127.0.0.1", 0)
    local nameOk, address, port = pcall(socket.getsockname, socket)
    if not timeoutOk or timeoutResult == false or timeoutResult == nil
        or not bindOk or bindResult == false or bindResult == nil
        or not nameOk or address ~= "127.0.0.1"
        or not wholeNumber(port, 1, 65535) then
        closeSocket(socket)
        return nil, ERROR_SOCKET
    end
    return socket, address, port
end

function Instance:_updateBridge()
    if self.closed then return false, ERROR_NETWORK end
    local ok, status, errorMessage = pcall(self.bridge.update, self.bridge)
    if not ok or status ~= "running" or errorMessage ~= nil then
        self.lastError = ERROR_NETWORK
        return false, ERROR_NETWORK
    end
    return true
end

function Instance:poll()
    if self.closed then return nil end
    local bridgeOk, bridgeError = self:_updateBridge()
    if not bridgeOk then return nil, bridgeError end
    local ok, event, errorMessage = callMethod(self.base, "poll")
    if not ok then return nil, ERROR_NETWORK end
    if errorMessage ~= nil then return nil, ERROR_NETWORK end
    bridgeOk, bridgeError = self:_updateBridge()
    if not bridgeOk then return nil, bridgeError end
    if type(event) == "table" then
        if event.type == "connect" and self.mode == "client" then
            self.peer = event.peer
        elseif event.type == "disconnect" and event.peer == self.peer then
            self.peer = nil
        end
    end
    return event
end

function Instance:service(maxEvents)
    maxEvents = wholeNumber(maxEvents or BridgeTransport.MAX_EVENTS_PER_SERVICE,
        1, 1024)
    if not maxEvents then return nil, "Event limit must be between 1 and 1024." end
    local events = {}
    for _ = 1, maxEvents do
        local event, errorMessage = self:poll()
        if errorMessage then return events, errorMessage end
        if not event then break end
        events[#events + 1] = event
    end
    return events
end

function Instance:send(peer, payload, channelOrOptions, reliable)
    if self.closed then return false, "Transport is closed." end
    local ok, result, errorMessage = callMethod(
        self.base, "send", peer, payload, channelOrOptions, reliable)
    if not ok or not sendSucceeded(result) then
        return false, tostring(errorMessage or ERROR_NETWORK)
    end
    local bridgeOk, bridgeError = self:_updateBridge()
    return bridgeOk, bridgeOk and nil or bridgeError
end

function Instance:sendToServer(payload, channelOrOptions, reliable)
    if self.closed then return false, "Transport is closed." end
    local ok, result, errorMessage = callMethod(
        self.base, "sendToServer", payload, channelOrOptions, reliable)
    if not ok or not sendSucceeded(result) then
        return false, tostring(errorMessage or ERROR_NETWORK)
    end
    local bridgeOk, bridgeError = self:_updateBridge()
    return bridgeOk, bridgeOk and nil or bridgeError
end

function Instance:broadcast(payload, channelOrOptions, reliable)
    if self.closed then return false, "Transport is closed." end
    local ok, result, errorMessage = callMethod(
        self.base, "broadcast", payload, channelOrOptions, reliable)
    if not ok or not sendSucceeded(result) then
        return false, tostring(errorMessage or ERROR_NETWORK)
    end
    local bridgeOk, bridgeError = self:_updateBridge()
    return bridgeOk, bridgeOk and nil or bridgeError
end

function Instance:flush()
    if self.closed then return true end
    local ok, result, errorMessage = callMethod(self.base, "flush")
    if not ok or result == false then
        return false, tostring(errorMessage or ERROR_NETWORK)
    end
    return self:_updateBridge()
end

function Instance:disconnect(peer, code, immediate)
    if self.closed then return false, "Transport is closed." end
    local ok, result, errorMessage = callMethod(
        self.base, "disconnect", peer, code, immediate)
    if not ok or result == false then
        return false, tostring(errorMessage or ERROR_NETWORK)
    end
    return self:_updateBridge()
end

function Instance:close(code, immediate)
    if self.closed then
        if self._closeOk == true then return true end
        return false, self._closeError or ERROR_CLOSE
    end
    local errors = {}
    local ok, result = callMethod(self.base, "close", code, immediate)
    if not ok or result == false then errors[#errors + 1] = ERROR_CLOSE end
    local bridgeUpdated = self:_updateBridge()
    if not bridgeUpdated then errors[#errors + 1] = ERROR_CLOSE end
    local bridgeCloseOk, bridgeClosed = pcall(self.bridge.close, self.bridge)
    if not bridgeCloseOk or bridgeClosed ~= true then
        errors[#errors + 1] = ERROR_CLOSE
    end
    self.peer = nil
    self.closed = true
    self.base = nil
    self.bridge = nil
    self._closeOk = #errors == 0
    self._closeError = nil
    if not self._closeOk then self._closeError = ERROR_CLOSE end
    return self._closeOk, self._closeError
end

Instance.destroy = Instance.close

local function wrap(base, bridge, mode)
    if type(base) ~= "table" or type(bridge) ~= "table" then
        return nil, ERROR_NETWORK
    end
    for _, method in ipairs({ "poll", "send", "disconnect", "close" }) do
        if not methodFor(base, method) then return nil, ERROR_NETWORK end
    end
    local channels = wholeNumber(base.channels or BridgeTransport.DEFAULT_CHANNELS,
        1, 255)
    if not channels then return nil, ERROR_NETWORK end
    return setmetatable({
        mode = mode,
        endpoint = "127.0.0.1",
        channels = channels,
        maxGuests = 1,
        peerCapacity = 1,
        peer = mode == "client" and base.peer or nil,
        base = base,
        bridge = bridge,
        closed = false,
        lastError = nil,
    }, Instance)
end

function BridgeTransport.newFactory(options)
    if type(options) ~= "table"
        or (options.role ~= "host" and options.role ~= "guest")
        or type(options.baseFactory) ~= "table"
        or type(options.baseFactory.createHost) ~= "function"
        or type(options.baseFactory.createClient) ~= "function"
        or type(options.socketModule) ~= "table"
        or type(options.socketModule.udp) ~= "function"
        or type(options.opening) ~= "table"
        or type(options.opening.isReady) ~= "function"
        or type(options.opening.takeSocket) ~= "function"
        or type(options.opening.close) ~= "function"
        or type(options.provider) ~= "table"
        or options.provider.productionReady ~= true
        or type(options.masterKey) ~= "string" or #options.masterKey ~= 32
        or type(options.invitationId) ~= "string" or #options.invitationId ~= 16
        or type(options.guestNonce) ~= "string" or #options.guestNonce ~= 16 then
        return nil, ERROR_FACTORY
    end
    local loopbackHostPort = options.loopbackHostPort
    if options.role == "host" then
        loopbackHostPort = wholeNumber(loopbackHostPort, 1, 65535)
        if not loopbackHostPort then return nil, ERROR_FACTORY end
    end

    local config = {
        role = options.role,
        baseFactory = options.baseFactory,
        socketModule = options.socketModule,
        opening = options.opening,
        provider = options.provider,
        masterKey = options.masterKey,
        invitationId = options.invitationId,
        guestNonce = options.guestNonce,
        peerAddress = options.peerAddress,
        peerPort = options.peerPort,
        loopbackHostPort = loopbackHostPort,
        clock = options.clock,
        reassemblyTimeoutSeconds = options.reassemblyTimeoutSeconds,
        maxPendingDatagrams = options.maxPendingDatagrams,
        maxPendingBytes = options.maxPendingBytes,
    }
    local factory = {
        DEFAULT_PORT = options.baseFactory.DEFAULT_PORT or BridgeTransport.DEFAULT_PORT,
        MAX_GUESTS = 1,
        MAX_PEERS = 1,
        MIN_CHANNELS = options.baseFactory.MIN_CHANNELS or 3,
        DEFAULT_CHANNELS = options.baseFactory.DEFAULT_CHANNELS or 3,
    }
    local created = false
    local disposed = false
    local disposeOk = nil

    local function clearSensitiveConfig()
        config.masterKey = nil
        config.invitationId = nil
        config.guestNonce = nil
        config.peerAddress = nil
        config.peerPort = nil
        config.provider = nil
    end

    local function disposeFactory()
        if created then return true end
        if disposed then return disposeOk == true end
        disposed = true
        local cleaned = true
        local pendingOpening = config.opening
        config.opening = nil
        if pendingOpening then
            local ok, result = callMethod(pendingOpening, "close")
            if not ok or result ~= true then cleaned = false end
        end
        if methodFor(config.baseFactory, "close") then
            local ok, result = callMethod(config.baseFactory, "close")
            if not ok or result ~= true then cleaned = false end
        end
        clearSensitiveConfig()
        disposeOk = cleaned
        return cleaned
    end

    local function failFactory(message)
        if not disposeFactory() then return nil, ERROR_CLOSE end
        return nil, message
    end

    function factory.close()
        local cleaned = disposeFactory()
        if cleaned then return true end
        return false, ERROR_CLOSE
    end

    factory.dispose = factory.close

    local function takeOuterSocket()
        local readyOk, ready = pcall(config.opening.isReady, config.opening)
        if not readyOk or ready ~= true then return nil, ERROR_OPENING end
        local takeOk, socket = pcall(config.opening.takeSocket, config.opening)
        if not takeOk or not socket then return nil, ERROR_OPENING end
        return socket
    end

    local function createBridge(innerSocket, outerSocket, localTargetPort)
        return DirectBridge.create({
            role = config.role,
            outerSocket = outerSocket,
            innerSocket = innerSocket,
            ownsOuterSocket = true,
            ownsInnerSocket = true,
            provider = config.provider,
            masterKey = config.masterKey,
            invitationId = config.invitationId,
            guestNonce = config.guestNonce,
            peerAddress = config.peerAddress,
            peerPort = config.peerPort,
            localTargetAddress = "127.0.0.1",
            localTargetPort = localTargetPort,
            clock = config.clock,
            reassemblyTimeoutSeconds = config.reassemblyTimeoutSeconds,
            maxPendingDatagrams = config.maxPendingDatagrams,
            maxPendingBytes = config.maxPendingBytes,
        })
    end

    function factory.createHost(createOptions)
        if created or disposed or config.role ~= "host" then return nil, ERROR_FACTORY end
        createOptions = createOptions or {}
        local forwarded = {}
        for key, value in pairs(createOptions) do forwarded[key] = value end
        forwarded.bind = "127.0.0.1"
        forwarded.port = config.loopbackHostPort
        forwarded.maxGuests = 1
        forwarded.peerCapacity = 1
        local baseOk, base, baseError = callFactory(
            config.baseFactory, "createHost", forwarded)
        if not baseOk or not base then return failFactory(baseError or ERROR_NETWORK) end

        local innerSocket = createLoopbackSocket(config.socketModule)
        if not innerSocket then
            callMethod(base, "close", 0, true)
            return failFactory(ERROR_SOCKET)
        end
        local outerSocket, openingError = takeOuterSocket()
        if not outerSocket then
            closeSocket(innerSocket)
            callMethod(base, "close", 0, true)
            return failFactory(openingError)
        end
        local bridge, bridgeError = createBridge(
            innerSocket, outerSocket, config.loopbackHostPort)
        if not bridge then
            callMethod(base, "close", 0, true)
            return failFactory(bridgeError or ERROR_NETWORK)
        end
        local instance, wrapError = wrap(base, bridge, "host")
        if not instance then
            bridge:close()
            callMethod(base, "close", 0, true)
            return failFactory(wrapError)
        end
        created = true
        config.opening = nil
        clearSensitiveConfig()
        return instance
    end

    function factory.createClient(_, createOptions)
        if created or disposed or config.role ~= "guest" then return nil, ERROR_FACTORY end
        createOptions = createOptions or {}
        local innerSocket, _, relayPort = createLoopbackSocket(config.socketModule)
        if not innerSocket then return failFactory(ERROR_SOCKET) end
        local outerSocket, openingError = takeOuterSocket()
        if not outerSocket then
            closeSocket(innerSocket)
            return failFactory(openingError)
        end
        local bridge, bridgeError = createBridge(innerSocket, outerSocket, nil)
        if not bridge then
            return failFactory(bridgeError or ERROR_NETWORK)
        end
        local endpoint = "127.0.0.1:" .. tostring(relayPort)
        local baseOk, base, baseError = callFactory(
            config.baseFactory, "createClient", endpoint, createOptions)
        if not baseOk or not base then
            bridge:close()
            return failFactory(baseError or ERROR_NETWORK)
        end
        local instance, wrapError = wrap(base, bridge, "client")
        if not instance then
            callMethod(base, "close", 0, true)
            bridge:close()
            return failFactory(wrapError)
        end
        created = true
        config.opening = nil
        clearSensitiveConfig()
        return instance
    end

    return factory
end

BridgeTransport.Instance = Instance

return BridgeTransport
