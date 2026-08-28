local Address = require("src.net.address")

local Transport = {}
local Instance = {}
Instance.__index = Instance

Transport.DEFAULT_PORT = Address.DEFAULT_PORT
Transport.MAX_GUESTS = 3
Transport.MIN_CHANNELS = 3
Transport.DEFAULT_CHANNELS = 3
Transport.MAX_EVENTS_PER_SERVICE = 64

local cachedEnet

local function loadEnet(provided)
    if provided ~= nil then
        if type(provided) ~= "table" or type(provided.host_create) ~= "function" then
            return nil, "Injected ENet module must provide host_create."
        end
        return provided
    end
    if cachedEnet then return cachedEnet end
    local ok, result = pcall(require, "enet")
    if not ok or type(result) ~= "table" or type(result.host_create) ~= "function" then
        return nil, "ENet networking is unavailable in this build."
    end
    cachedEnet = result
    return cachedEnet
end

local function wholeNumber(value, minimum, maximum)
    value = tonumber(value)
    return value and value == math.floor(value) and value >= minimum and value <= maximum
        and value or nil
end

local function channelCount(value)
    return wholeNumber(value or Transport.DEFAULT_CHANNELS, Transport.MIN_CHANNELS, 255)
end

local function protectedMethod(target, method, ...)
    if not target then return false, "missing target" end
    local callable = target[method]
    if type(callable) ~= "function" then return false, "missing " .. method end
    return pcall(callable, target, ...)
end

local function peerMetadata(peer)
    local metadata = {}
    local okId, connectionId = protectedMethod(peer, "connect_id")
    if okId then metadata.connectionId = connectionId end
    local okIndex, peerIndex = protectedMethod(peer, "index")
    if okIndex then metadata.peerIndex = peerIndex end
    local okState, state = protectedMethod(peer, "state")
    if okState then metadata.peerState = state end
    return metadata
end

local function normalizeEvent(raw)
    if type(raw) ~= "table" or raw.type == nil or raw.type == "none" then return nil end
    local event = {
        type = tostring(raw.type),
        peer = raw.peer,
        data = raw.data,
        channel = raw.channel,
    }
    if event.type == "receive" then
        event.payload = raw.data
        event.channel = tonumber(raw.channel) or 0
    else
        event.code = tonumber(raw.data) or 0
    end
    for key, value in pairs(peerMetadata(raw.peer)) do event[key] = value end
    return event
end

local function newInstance(mode, nativeHost, options)
    return setmetatable({
        mode = mode,
        endpoint = options.endpoint,
        channels = options.channels,
        maxGuests = options.maxGuests,
        peer = options.peer,
        nativeHost = nativeHost,
        closed = false,
        _peers = {},
    }, Instance)
end

local function createNativeHost(enet, ...)
    local ok, nativeHost, errorMessage = pcall(enet.host_create, ...)
    if not ok then return nil, "Could not create ENet host: " .. tostring(nativeHost) end
    if not nativeHost then return nil, tostring(errorMessage or "ENet host creation failed.") end
    return nativeHost
end

local function hostEndpoint(options)
    local port = wholeNumber(options.port or Address.DEFAULT_PORT, 1, 65535)
    if not port then return nil, "Host port must be between 1 and 65535." end
    local bind = options.bind or "*"
    if bind == "*" then return "*:" .. tostring(port) end
    local parsed, errorMessage = Address.parse(bind, port)
    return parsed and parsed.endpoint or nil, errorMessage
end

function Transport.createHost(options)
    options = options or {}
    local enet, loadError = loadEnet(options.enet)
    if not enet then return nil, loadError end
    local channels = channelCount(options.channels)
    if not channels then return nil, "ENet sessions require between 3 and 255 channels." end
    local maxGuests = wholeNumber(options.maxGuests or Transport.MAX_GUESTS, 1, Transport.MAX_GUESTS)
    if not maxGuests then return nil, "LAN hosting supports one to three guests." end
    local endpoint, endpointError = hostEndpoint(options)
    if not endpoint then return nil, endpointError end
    local nativeHost, createError = createNativeHost(enet, endpoint, maxGuests, channels,
        tonumber(options.incomingBandwidth) or 0, tonumber(options.outgoingBandwidth) or 0)
    if not nativeHost then return nil, createError end
    return newInstance("host", nativeHost, {
        endpoint = endpoint,
        channels = channels,
        maxGuests = maxGuests,
    })
end

function Transport.createClient(address, options)
    if type(address) == "table" and options == nil then
        options, address = address, address.address
    end
    options = options or {}
    local parsed, addressError = Address.parse(address or options.address or "", options.port)
    if not parsed then return nil, addressError end
    local enet, loadError = loadEnet(options.enet)
    if not enet then return nil, loadError end
    local channels = channelCount(options.channels)
    if not channels then return nil, "ENet sessions require between 3 and 255 channels." end
    local nativeHost, createError = createNativeHost(enet, nil, 1, channels,
        tonumber(options.incomingBandwidth) or 0, tonumber(options.outgoingBandwidth) or 0)
    if not nativeHost then return nil, createError end

    local connectData = wholeNumber(options.connectData or 0, 0, 2147483647)
    if not connectData then
        protectedMethod(nativeHost, "destroy")
        return nil, "Connection data must be a nonnegative whole number."
    end
    local okConnect, peer = protectedMethod(nativeHost, "connect", parsed.endpoint, channels, connectData)
    if not okConnect or not peer then
        protectedMethod(nativeHost, "destroy")
        return nil, "Could not connect to " .. parsed.endpoint .. ": " .. tostring(peer)
    end
    local instance = newInstance("client", nativeHost, {
        endpoint = parsed.endpoint,
        channels = channels,
        peer = peer,
    })
    instance._peers[peer] = true
    return instance
end

function Instance:poll()
    if self.closed or not self.nativeHost then return nil end
    local ok, raw = protectedMethod(self.nativeHost, "service", 0)
    if not ok then return nil, "ENet service failed: " .. tostring(raw) end
    local event = normalizeEvent(raw)
    if not event then return nil end
    if event.type == "connect" and event.peer then
        self._peers[event.peer] = true
        if self.mode == "client" then self.peer = event.peer end
    elseif event.type == "disconnect" and event.peer then
        self._peers[event.peer] = nil
        if self.peer == event.peer then self.peer = nil end
    end
    return event
end

function Instance:service(maxEvents)
    maxEvents = wholeNumber(maxEvents or Transport.MAX_EVENTS_PER_SERVICE, 1, 1024)
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

local function sendOptions(channelOrOptions, reliable)
    if type(channelOrOptions) == "table" then
        return channelOrOptions.channel or 0, channelOrOptions.reliable == true
    end
    return channelOrOptions or 0, reliable == true
end

local function sendSucceeded(result)
    if result == false then return false end
    if type(result) == "number" and result < 0 then return false end
    return true
end

function Instance:send(peer, payload, channelOrOptions, reliable)
    if self.closed then return false, "Transport is closed." end
    if type(payload) ~= "string" then return false, "Network payload must be a string." end
    local channel, useReliable = sendOptions(channelOrOptions, reliable)
    channel = wholeNumber(channel, 0, self.channels - 1)
    if not channel then return false, "Network channel is outside this session's channel range." end
    local ok, result
    if useReliable then
        ok, result = protectedMethod(peer, "send", payload, channel, "reliable")
    else
        ok, result = protectedMethod(peer, "send", payload, channel, "unreliable")
    end
    if not ok then return false, "ENet send failed: " .. tostring(result) end
    local succeeded = sendSucceeded(result)
    return succeeded, not succeeded and "ENet rejected the packet." or nil
end

function Instance:sendToServer(payload, channelOrOptions, reliable)
    if not self.peer then return false, "Server connection is not available." end
    return self:send(self.peer, payload, channelOrOptions, reliable)
end

function Instance:broadcast(payload, channelOrOptions, reliable)
    if self.closed or not self.nativeHost then return false, "Transport is closed." end
    if type(payload) ~= "string" then return false, "Network payload must be a string." end
    local channel, useReliable = sendOptions(channelOrOptions, reliable)
    channel = wholeNumber(channel, 0, self.channels - 1)
    if not channel then return false, "Network channel is outside this session's channel range." end
    local ok, result
    if useReliable then
        ok, result = protectedMethod(self.nativeHost, "broadcast", payload, channel, "reliable")
    else
        ok, result = protectedMethod(self.nativeHost, "broadcast", payload, channel, "unreliable")
    end
    if not ok then return false, "ENet broadcast failed: " .. tostring(result) end
    local succeeded = sendSucceeded(result)
    return succeeded, not succeeded and "ENet rejected the broadcast." or nil
end

function Instance:flush()
    if self.closed or not self.nativeHost then return true end
    local ok, result = protectedMethod(self.nativeHost, "flush")
    return ok, ok and nil or "ENet flush failed: " .. tostring(result)
end

function Instance:disconnect(peer, code, immediate)
    if self.closed then return false, "Transport is closed." end
    code = wholeNumber(code or 0, 0, 2147483647)
    if not code then return false, "Disconnect code must be a nonnegative whole number." end
    local method = immediate == true and "disconnect_now" or "disconnect"
    local ok, result = protectedMethod(peer, method, code)
    if not ok then return false, "ENet disconnect failed: " .. tostring(result) end
    self._peers[peer] = nil
    if self.peer == peer then self.peer = nil end
    if not immediate then
        local flushed, flushError = self:flush()
        if not flushed then return false, flushError end
    end
    return true
end

function Instance:close(code, immediate)
    if self.closed then return true end
    code = wholeNumber(code or 0, 0, 2147483647)
    if not code then return false, "Disconnect code must be a nonnegative whole number." end
    local errors = {}
    local peers = {}
    for peer in pairs(self._peers) do peers[#peers + 1] = peer end
    if self.peer and not self._peers[self.peer] then peers[#peers + 1] = self.peer end
    for _, peer in ipairs(peers) do
        local method = immediate == true and "disconnect_now" or "disconnect"
        local ok, result = protectedMethod(peer, method, code)
        if not ok then errors[#errors + 1] = tostring(result) end
    end
    if not immediate and self.nativeHost then
        local ok, result = protectedMethod(self.nativeHost, "flush")
        if not ok then errors[#errors + 1] = tostring(result) end
    end
    if self.nativeHost then
        local ok, result = protectedMethod(self.nativeHost, "destroy")
        if not ok then errors[#errors + 1] = tostring(result) end
    end
    self._peers = {}
    self.peer = nil
    self.nativeHost = nil
    self.closed = true
    return #errors == 0, #errors > 0 and table.concat(errors, "; ") or nil
end

Instance.destroy = Instance.close
Transport.host = Transport.createHost
Transport.client = Transport.createClient
Transport.Instance = Instance
return Transport
