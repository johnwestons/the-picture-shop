local DirectComposite = {
    MAX_GUESTS = 3,
    MAX_PEERS = 3,
    MIN_CHANNELS = 3,
    DEFAULT_CHANNELS = 3,
    MAX_EVENTS_PER_SERVICE = 64,
    FIRST_CONNECT_TIMEOUT_SECONDS = 30,
}

local Instance = {}
Instance.__index = Instance

local Controller = {}
Controller.__index = Controller

local ERROR_OPTIONS = "Direct host transport options are invalid."
local ERROR_ATTACH = "The Direct guest link could not be attached."
local ERROR_FULL = "This Direct host already has three guest links."
local ERROR_CLOSED = "The Direct host transport is closed."
local ERROR_PEER = "That Direct guest is no longer connected."
local ERROR_SEND = "The Direct guest link could not send."
local ERROR_DISCONNECT = "The Direct guest link could not disconnect cleanly."
local ERROR_CLOSE = "Direct guest link cleanup failed."
local ERROR_FACTORY = "A Direct host transport factory creates only one session."
local ERROR_CLOCK = "Direct guest link timing failed."

local Peer = {}
Peer.__index = Peer

local LinkHandle = {}
LinkHandle.__index = LinkHandle

local function wholeNumber(value, minimum, maximum)
    value = tonumber(value)
    return value and value == value and value == math.floor(value)
        and value >= minimum and value <= maximum and value or nil
end

local function finiteNumber(value, minimum, maximum)
    return type(value) == "number" and value == value
        and value >= minimum and value <= maximum and value or nil
end

local function defaultClock()
    if love and love.timer and love.timer.getTime then return love.timer.getTime() end
    return os.clock()
end

local function methodFor(target, method)
    if target == nil then return nil end
    local ok, callable = pcall(function() return target[method] end)
    return ok and type(callable) == "function" and callable or nil
end

local function callMethod(target, method, ...)
    local callable = methodFor(target, method)
    if not callable then return false, nil end
    return pcall(callable, target, ...)
end

local function successful(value)
    if value == false or value == nil then return false end
    return type(value) ~= "number" or value >= 0
end

local function copyTable(value)
    local result = {}
    for key, item in pairs(type(value) == "table" and value or {}) do
        result[key] = item
    end
    return result
end

local function closeUnownedLink(link)
    local close = methodFor(link, "close")
    if not close then return false end
    local ok, result = pcall(close, link, 0, true)
    return ok and successful(result)
end

local function closeUnownedFactory(factory)
    local close = methodFor(factory, "close")
    if not close then return false end
    local ok, result = pcall(close, factory)
    return ok and successful(result)
end

local function linkShape(link, channels)
    if type(link) ~= "table" or link.mode ~= "host"
        or wholeNumber(link.channels, 1, 255) ~= channels
        or wholeNumber(link.maxGuests, 1, 1) ~= 1
        or wholeNumber(link.peerCapacity, 1, 1) ~= 1 then
        return false
    end
    for _, method in ipairs({ "poll", "send", "disconnect", "close" }) do
        if not methodFor(link, method) then return false end
    end
    return true
end

local function publicPeer()
    -- Session keys peers by table identity.  An empty wrapper is stable while
    -- revealing neither the underlying transport peer nor invitation metadata.
    return setmetatable({}, Peer)
end

local function linkHandle()
    return setmetatable({}, LinkHandle)
end

local function sanitizedCode(value)
    return wholeNumber(value, 0, 2147483647)
end

local function publicEvent(eventType, peer, event)
    local result = { type = eventType, peer = peer }
    if eventType == "receive" then
        local payload = event.data
        if payload == nil then payload = event.payload end
        result.data = payload
        result.payload = payload
        result.channel = event.channel
        result.reliable = event.reliable == true
    else
        local code = sanitizedCode(event.code or event.data)
        if code ~= nil then result.code = code end
    end
    return result
end

function Instance:_removeRecord(record)
    if not record or not record.active then return false end
    record.active = false
    self._links[record.handle] = nil
    for index, handle in ipairs(self._order) do
        if handle == record.handle then
            table.remove(self._order, index)
            if self._cursor > #self._order then self._cursor = 1 end
            break
        end
    end
    if record.peer then self._routes[record.peer] = nil end
    return true
end

function Instance:_rememberUnclean(record)
    if not record or record.cleanupPending then return end
    record.cleanupPending = true
    self._unclean[#self._unclean + 1] = record
end

function Instance:_retryUnclean()
    local hadUnverifiedCleanup = #self._unclean > 0
    for _, record in ipairs(self._unclean) do
        -- A later close call may help a transport release resources, but it
        -- cannot retroactively prove that an earlier failed close succeeded.
        -- Retain the owner and the sticky failure until process shutdown.
        callMethod(record.transport, "close", 0, true)
    end
    return not hadUnverifiedCleanup
end

function Instance:_closeRecord(record, queueDisconnect)
    if not record or not record.active then return true end
    local peer = record.peer
    self:_removeRecord(record)
    local ok, result = callMethod(record.transport, "close", 0, true)
    record.rawPeer = nil
    record.peer = nil
    local cleaned = ok and successful(result)
    if cleaned then
        record.transport = nil
    else
        self:_rememberUnclean(record)
    end
    if queueDisconnect and peer then
        self._events[#self._events + 1] = { type = "disconnect", peer = peer }
    end
    if not cleaned then
        self.cleanupFailures = self.cleanupFailures + 1
        self.lastError = ERROR_CLOSE
        self._fatalError = ERROR_CLOSE
    end
    return cleaned
end

function Instance:_failRecord(record)
    if not record or not record.active then return false end
    self.failedLinks = self.failedLinks + 1
    self.lastError = "A Direct guest link ended safely."
    self:_closeRecord(record, record.peer ~= nil)
    return true
end

function Instance:_dequeue()
    if #self._events == 0 then return nil end
    return table.remove(self._events, 1)
end

function Instance:_attach(link)
    if self.closed or self._fatalError then
        local cleaned = closeUnownedLink(link)
        if not cleaned and type(link) == "table" then
            self:_rememberUnclean({ transport = link })
            self._fatalError = ERROR_CLOSE
        end
        return nil, self.closed and ERROR_CLOSED or ERROR_CLOSE
    end
    if #self._order >= self.maxGuests then
        local cleaned = closeUnownedLink(link)
        if not cleaned and type(link) == "table" then
            self:_rememberUnclean({ transport = link })
            self._fatalError = ERROR_CLOSE
        end
        return nil, ERROR_FULL
    end
    if not linkShape(link, self.channels) then
        local cleaned = closeUnownedLink(link)
        if not cleaned and type(link) == "table" then
            self:_rememberUnclean({ transport = link })
            self._fatalError = ERROR_CLOSE
        end
        return nil, ERROR_ATTACH
    end
    local handle = linkHandle()
    local record = {
        handle = handle,
        transport = link,
        rawPeer = nil,
        peer = nil,
        active = true,
        attachedAt = self:_now(),
    }
    if not record.attachedAt then
        local cleaned = closeUnownedLink(link)
        if not cleaned then self:_rememberUnclean(record) end
        self._fatalError = cleaned and ERROR_CLOCK or ERROR_CLOSE
        return nil, self._fatalError
    end
    self._links[handle] = record
    self._order[#self._order + 1] = handle
    return handle
end

function Instance:attachInstance(link)
    return self:_attach(link)
end

Instance.attachLink = Instance.attachInstance

function Instance:attachFactory(factory, createOptions)
    local factoryValid = type(factory) == "table"
        and type(factory.createHost) == "function"
        and type(factory.close) == "function"
    if self.closed or self._fatalError or #self._order >= self.maxGuests then
        local cleaned = factoryValid and closeUnownedFactory(factory) or false
        if factoryValid and not cleaned then self._fatalError = ERROR_CLOSE end
        if self._fatalError then return nil, ERROR_CLOSE end
        return nil, self.closed and ERROR_CLOSED or ERROR_FULL
    end
    if not factoryValid then
        return nil, ERROR_ATTACH
    end
    local forwarded = copyTable(createOptions)
    forwarded.channels = self.channels
    forwarded.maxGuests = 1
    forwarded.peerCapacity = 1
    local ok, link = pcall(factory.createHost, forwarded)
    if not ok or not link then
        if not closeUnownedFactory(factory) then
            self._fatalError = ERROR_CLOSE
            return nil, ERROR_CLOSE
        end
        return nil, ERROR_ATTACH
    end
    return self:_attach(link)
end

function Instance:_now()
    local ok, now = pcall(self._clock)
    now = ok and finiteNumber(now, 0, 1e15) or nil
    if not now or (self._lastClock ~= nil and now < self._lastClock) then return nil end
    self._lastClock = now
    return now
end

function Instance:_expireUnconnected(now)
    local snapshot = {}
    for _, handle in ipairs(self._order) do snapshot[#snapshot + 1] = handle end
    for _, handle in ipairs(snapshot) do
        local record = self._links[handle]
        if record and record.active and record.rawPeer == nil
            and now - record.attachedAt >= self.firstConnectTimeoutSeconds
        then
            self:_failRecord(record)
            if self._fatalError then return false end
        end
    end
    return true
end

function Instance:linkCount()
    return #self._order
end

function Instance:capacity()
    return self.maxGuests
end

function Instance:remainingCapacity()
    return self.maxGuests - #self._order
end

function Instance:peerCount()
    local count = 0
    for _ in pairs(self._routes) do count = count + 1 end
    return count
end

function Instance:_disconnectUnexpected(record, rawPeer)
    local ok, result = callMethod(record.transport,
        "disconnect", rawPeer, 7, true)
    if not ok or not successful(result) then self:_failRecord(record) end
end

function Instance:_translate(record, event)
    if type(event) ~= "table" or type(event.type) ~= "string" then
        self:_failRecord(record)
        return nil
    end
    if event.type == "connect" then
        if event.peer == nil then self:_failRecord(record); return nil end
        if record.rawPeer ~= nil then
            -- Every underlying transport is a one-use, one-guest link.  A
            -- second connect signal is a protocol violation even when the raw
            -- peer object is repeated; retire the complete link.
            self:_failRecord(record)
            return nil
        end
        local peer = publicPeer()
        record.rawPeer = event.peer
        record.peer = peer
        self._routes[peer] = record
        return publicEvent("connect", peer, event)
    end
    if event.type ~= "receive" and event.type ~= "disconnect" then
        self:_failRecord(record)
        return nil
    end
    if event.peer == nil or event.peer ~= record.rawPeer or not record.peer then
        if event.peer ~= nil then self:_disconnectUnexpected(record, event.peer) end
        if record.active then self:_failRecord(record) end
        return nil
    end
    local translated = publicEvent(event.type, record.peer, event)
    if event.type == "disconnect" then self:_closeRecord(record, false) end
    return translated
end

function Instance:poll()
    if self.closed then return nil end
    if self._fatalError then return nil, self._fatalError end
    local now = self:_now()
    if not now then
        self._fatalError = ERROR_CLOCK
        return nil, self._fatalError
    end
    if not self:_expireUnconnected(now) then return nil, self._fatalError end
    local queued = self:_dequeue()
    if queued then return queued end
    local count = #self._order
    if count == 0 then return nil end
    if self._cursor > count then self._cursor = 1 end
    local snapshot = {}
    for offset = 0, count - 1 do
        local index = ((self._cursor + offset - 1) % count) + 1
        snapshot[#snapshot + 1] = self._order[index]
    end
    self._cursor = (self._cursor % count) + 1
    for _, handle in ipairs(snapshot) do
        local record = self._links[handle]
        if record and record.active then
            local ok, event, errorMessage = callMethod(record.transport, "poll")
            if not ok or errorMessage ~= nil then
                self:_failRecord(record)
                if self._fatalError then return nil, self._fatalError end
                queued = self:_dequeue()
                if queued then return queued end
            elseif event ~= nil then
                local translated = self:_translate(record, event)
                if self._fatalError then return nil, self._fatalError end
                if translated then return translated end
                queued = self:_dequeue()
                if queued then return queued end
            end
        end
    end
    return self:_dequeue()
end

function Instance:service(maxEvents)
    maxEvents = wholeNumber(maxEvents or DirectComposite.MAX_EVENTS_PER_SERVICE,
        1, 1024)
    if not maxEvents then return nil, "Event limit must be between 1 and 1024." end
    if self.closed then return {} end
    if self._fatalError then return {}, self._fatalError end
    local events = {}
    for _ = 1, maxEvents do
        local event, errorMessage = self:poll()
        if errorMessage then return events, errorMessage end
        if not event then break end
        events[#events + 1] = event
    end
    -- Ordinary link failures become per-peer disconnect events. Cleanup or
    -- clock-integrity failures remain fatal because ownership cannot be proven.
    return events
end

function Instance:send(peer, payload, channelOrOptions, reliable)
    if self.closed then return false, ERROR_CLOSED end
    if self._fatalError then return false, self._fatalError end
    local record = self._routes[peer]
    if not record or not record.active or not record.rawPeer then
        return false, ERROR_PEER
    end
    local ok, result = callMethod(record.transport, "send",
        record.rawPeer, payload, channelOrOptions, reliable)
    if not ok or not successful(result) then
        self:_failRecord(record)
        return false, ERROR_SEND
    end
    return true
end

function Instance:broadcast(payload, channelOrOptions, reliable)
    if self.closed then return false, ERROR_CLOSED end
    if self._fatalError then return false, self._fatalError end
    local peers = {}
    for peer in pairs(self._routes) do peers[#peers + 1] = peer end
    for _, peer in ipairs(peers) do
        local record = self._routes[peer]
        if record and record.active then
            local ok, result = callMethod(record.transport, "send",
                record.rawPeer, payload, channelOrOptions, reliable)
            if not ok or not successful(result) then self:_failRecord(record) end
        end
    end
    return true
end

function Instance:flush()
    if self.closed then return true end
    if self._fatalError then return false, self._fatalError end
    local snapshot = {}
    for _, handle in ipairs(self._order) do snapshot[#snapshot + 1] = handle end
    for _, handle in ipairs(snapshot) do
        local record = self._links[handle]
        if record and record.active and methodFor(record.transport, "flush") then
            local ok, result = callMethod(record.transport, "flush")
            if not ok or not successful(result) then self:_failRecord(record) end
        end
    end
    return true
end

function Instance:disconnect(peer, code, immediate)
    if self.closed then return false, ERROR_CLOSED end
    if self._fatalError then return false, self._fatalError end
    local record = self._routes[peer]
    if not record or not record.active or not record.rawPeer then
        return false, ERROR_PEER
    end
    code = wholeNumber(code or 0, 0, 2147483647)
    if not code then return false, ERROR_DISCONNECT end
    local ok, result = callMethod(record.transport, "disconnect",
        record.rawPeer, code, immediate == true)
    local disconnected = ok and successful(result)
    local cleaned = self:_closeRecord(record, false)
    if not disconnected or not cleaned then return false, ERROR_DISCONNECT end
    return true
end

function Instance:retireLink(handle, code, immediate)
    if self.closed then return false, ERROR_CLOSED end
    if self._fatalError then return false, self._fatalError end
    local record = self._links[handle]
    if not record or not record.active then return false, ERROR_PEER end
    code = wholeNumber(code or 0, 0, 2147483647)
    if not code then return false, ERROR_DISCONNECT end
    local disconnected = true
    if record.rawPeer then
        local ok, result = callMethod(record.transport, "disconnect",
            record.rawPeer, code, immediate == true)
        disconnected = ok and successful(result)
    end
    local cleaned = self:_closeRecord(record, false)
    if not disconnected or not cleaned then return false, ERROR_DISCONNECT end
    return true
end

function Instance:close(code, immediate)
    if self.closed then
        if not self._closeOk and #self._unclean > 0 then
            self._closeOk = self:_retryUnclean()
        end
        if self._closeOk then return true end
        return false, ERROR_CLOSE
    end
    code = wholeNumber(code or 0, 0, 2147483647)
    if not code then return false, ERROR_CLOSE end
    local snapshot = {}
    for _, handle in ipairs(self._order) do snapshot[#snapshot + 1] = handle end
    local cleaned = true
    for _, handle in ipairs(snapshot) do
        local record = self._links[handle]
        if record and record.active then
            if record.rawPeer then
                local ok, result = callMethod(record.transport, "disconnect",
                    record.rawPeer, code, immediate == true)
                if not ok or not successful(result) then cleaned = false end
            end
            if not self:_closeRecord(record, false) then cleaned = false end
        end
    end
    local cleanupOk = self:_retryUnclean()
    if not cleanupOk then cleaned = false end
    self._events = {}
    self._routes = {}
    self.closed = true
    self._closeOk = cleaned
    self.lastError = nil
    if not cleaned then self.lastError = ERROR_CLOSE end
    if cleaned then
        self.lastError = nil
        return true
    end
    return false, ERROR_CLOSE
end

Instance.destroy = Instance.close

local function createInstance(options)
    options = options or {}
    local channels = wholeNumber(options.channels
        or DirectComposite.DEFAULT_CHANNELS, DirectComposite.MIN_CHANNELS, 255)
    local maxGuests = wholeNumber(options.maxGuests
        or DirectComposite.MAX_GUESTS, 1, DirectComposite.MAX_GUESTS)
    local clock = options.clock or defaultClock
    local firstConnectTimeoutSeconds = finiteNumber(
        options.firstConnectTimeoutSeconds
            or DirectComposite.FIRST_CONNECT_TIMEOUT_SECONDS, 1, 120)
    if not channels or not maxGuests or type(clock) ~= "function"
        or not firstConnectTimeoutSeconds then return nil, ERROR_OPTIONS end
    local clockOk, initialNow = pcall(clock)
    initialNow = clockOk and finiteNumber(initialNow, 0, 1e15) or nil
    if not initialNow then return nil, ERROR_OPTIONS end
    return setmetatable({
        mode = "host",
        endpoint = "direct-composite",
        channels = channels,
        maxGuests = maxGuests,
        peerCapacity = maxGuests,
        closed = false,
        lastError = nil,
        failedLinks = 0,
        cleanupFailures = 0,
        _links = {},
        _order = {},
        _routes = {},
        _events = {},
        _unclean = {},
        _cursor = 1,
        _closeOk = true,
        _fatalError = nil,
        _clock = clock,
        _lastClock = initialNow,
        firstConnectTimeoutSeconds = firstConnectTimeoutSeconds,
    }, Instance)
end

function DirectComposite.newFactory(options)
    local instance, errorMessage = createInstance(options)
    if not instance then return nil, nil, errorMessage end
    local handedOff = false
    local factory = {
        DEFAULT_PORT = nil,
        MAX_GUESTS = instance.maxGuests,
        MAX_PEERS = instance.maxGuests,
        MIN_CHANNELS = instance.channels,
        DEFAULT_CHANNELS = instance.channels,
    }
    function factory.createHost(createOptions)
        if handedOff or instance.closed then return nil, ERROR_FACTORY end
        if instance._fatalError then return nil, ERROR_CLOSE end
        createOptions = createOptions or {}
        local requestedChannels = wholeNumber(createOptions.channels
            or instance.channels, DirectComposite.MIN_CHANNELS, 255)
        local requestedGuests = wholeNumber(createOptions.maxGuests
            or instance.maxGuests, 1, DirectComposite.MAX_GUESTS)
        if requestedChannels ~= instance.channels
            or not requestedGuests or requestedGuests > instance.maxGuests then
            return nil, ERROR_OPTIONS
        end
        handedOff = true
        return instance
    end

    local controller = setmetatable({ _instance = instance }, Controller)
    return factory, controller
end

function Controller:attachFactory(factory, createOptions)
    return self._instance:attachFactory(factory, createOptions)
end

function Controller:attachInstance(link)
    return self._instance:attachInstance(link)
end

Controller.attachLink = Controller.attachInstance

function Controller:retireLink(handle, code, immediate)
    return self._instance:retireLink(handle, code, immediate)
end

function Controller:linkCount()
    return self._instance:linkCount()
end

function Controller:capacity()
    return self._instance:capacity()
end

function Controller:remainingCapacity()
    return self._instance:remainingCapacity()
end

function Controller:peerCount()
    return self._instance:peerCount()
end

function Controller:close(code, immediate)
    return self._instance:close(code, immediate)
end

DirectComposite.Instance = Instance
DirectComposite.Controller = Controller
DirectComposite.ERROR_ATTACH = ERROR_ATTACH
DirectComposite.ERROR_FULL = ERROR_FULL

return DirectComposite
