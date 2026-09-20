-- Best-effort LAN host discovery. Discovery replies are deliberately only
-- address hints: joining still uses Session's versioned hello and the host's
-- authoritative snapshot before any shop data is accepted.
local Address = require("src.net.address")
local Protocol = require("src.net.protocol")

local Discovery = {}
Discovery.__index = Discovery

Discovery.PORT = 22123
Discovery.QUERY_INTERVAL = 1
Discovery.RESULT_TTL = 5
Discovery.MAX_RESULTS = 8
Discovery.MAX_PACKET_BYTES = 160
Discovery.MAX_REPLIES_PER_SECOND = 16

local PREFIX = "TPSLAN1"

local function defaultClock()
    if love and love.timer and love.timer.getTime then return love.timer.getTime() end
    return os.clock()
end

local function loadSocket(provided)
    if provided ~= nil then return provided end
    local ok, socketModule = pcall(require, "socket")
    return ok and socketModule or nil
end

local function safeCall(target, method, ...)
    if not target or type(target[method]) ~= "function" then return false, "unavailable" end
    local ok, first, second = pcall(target[method], target, ...)
    if not ok then return false, tostring(first) end
    if first == nil or first == false then return false, tostring(second or "failed") end
    return true, first, second
end

local function displayName(value)
    value = tostring(value or "Local shop")
        :gsub("[%z\1-\31\127|]", "?")
        :gsub("[^%w %._%-?]", "?")
    value = value:match("^%s*(.-)%s*$") or value
    if value == "" then value = "Local shop" end
    return value:sub(1, 32)
end

local function validNonce(value)
    return type(value) == "string" and #value == 16
        and value:match("^[0-9a-f]+$") ~= nil
end

local nonceSerial = 0
local function defaultNonce(clock)
    nonceSerial = (nonceSerial + 1) % 0x100000000
    local micros = math.floor(math.max(0, clock()) * 1000000) % 0x100000000
    return string.format("%08x%08x", micros, nonceSerial)
end

local function queryPacket(nonce)
    return table.concat({ PREFIX, "Q", nonce, tostring(Protocol.VERSION) }, "|")
end

local function hostPacket(nonce, port, name)
    return table.concat({
        PREFIX, "H", nonce, tostring(Protocol.VERSION), tostring(port), displayName(name),
    }, "|")
end

local function parseQuery(packet)
    if type(packet) ~= "string" or #packet > Discovery.MAX_PACKET_BYTES then return nil end
    local nonce, version = packet:match("^" .. PREFIX .. "|Q|([0-9a-f]+)|(%d+)$")
    version = tonumber(version)
    if not validNonce(nonce) or version ~= Protocol.VERSION then return nil end
    return nonce
end

local function parseHost(packet, expectedNonce)
    if type(packet) ~= "string" or #packet > Discovery.MAX_PACKET_BYTES then return nil end
    local nonce, version, port, name = packet:match(
        "^" .. PREFIX .. "|H|([0-9a-f]+)|(%d+)|(%d+)|([^|]+)$")
    version, port = tonumber(version), tonumber(port)
    if not validNonce(nonce) or nonce ~= expectedNonce or version ~= Protocol.VERSION
        or not port or port ~= math.floor(port) or port < 1 or port > 65535
    then
        return nil
    end
    return port, displayName(name)
end

local function directedBroadcast(address)
    local a, b, c
    if type(address) == "string" then
        a, b, c = address:match("^(%d+)%.(%d+)%.(%d+)%.%d+$")
    end
    if not a then return nil end
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if a > 255 or b > 255 or c > 255 then return nil end
    return string.format("%d.%d.%d.255", a, b, c)
end

function Discovery.new(options)
    options = options or {}
    local clock = options.clock or defaultClock
    return setmetatable({
        socketModule = loadSocket(options.socket),
        addressDetector = options.addressDetector or Address.detectLanAddress,
        clock = clock,
        nonceFactory = options.nonceFactory or function() return defaultNonce(clock) end,
        discoveryPort = tonumber(options.port) or Discovery.PORT,
        mode = "idle",
        udp = nil,
        nonce = nil,
        gamePort = nil,
        hostName = nil,
        localAddress = nil,
        lastQueryAt = -math.huge,
        resultsByAddress = {},
        resultOrder = {},
        replyWindow = -1,
        repliesInWindow = 0,
        message = "Discovery is idle.",
    }, Discovery)
end

function Discovery:_open(bindPort, broadcast)
    if type(self.socketModule) ~= "table" or type(self.socketModule.udp) ~= "function" then
        return nil, "LAN discovery sockets are unavailable; enter the address manually."
    end
    local created, udp = pcall(self.socketModule.udp)
    if not created or not udp then
        return nil, "LAN discovery could not open a UDP socket; enter the address manually."
    end
    safeCall(udp, "setoption", "reuseaddr", true)
    if broadcast then safeCall(udp, "setoption", "broadcast", true) end
    safeCall(udp, "settimeout", 0)
    -- LuaSocket's wildcard may select an IPv6 socket on Android. Discovery
    -- sends IPv4 limited/directed broadcasts and must therefore bind an
    -- explicit IPv4 wildcard just like the ENet Local Play listener.
    local bound, bindError = safeCall(udp, "setsockname", "0.0.0.0", bindPort)
    if not bound then
        if type(udp.close) == "function" then pcall(udp.close, udp) end
        return nil, "LAN discovery could not bind: " .. tostring(bindError)
    end
    return udp
end

function Discovery:stop()
    if self.udp and type(self.udp.close) == "function" then pcall(self.udp.close, self.udp) end
    self.udp = nil
    self.mode = "idle"
    self.nonce = nil
    self.gamePort = nil
    self.hostName = nil
    self.localAddress = nil
    self.resultsByAddress = {}
    self.resultOrder = {}
    self.message = "Discovery is idle."
    return true
end

function Discovery:startHost(options)
    options = options or {}
    self:stop()
    local gamePort = tonumber(options.gamePort)
    if not gamePort or gamePort ~= math.floor(gamePort) or gamePort < 1 or gamePort > 65535 then
        return false, "LAN discovery needs a valid game port."
    end
    local udp, openError = self:_open(self.discoveryPort, false)
    if not udp then return false, openError end
    self.udp = udp
    self.mode = "host"
    self.gamePort = gamePort
    self.hostName = displayName(options.name)
    self.message = "Advertising this shop on the local network."
    return true
end

function Discovery:startSearch(options)
    options = options or {}
    self:stop()
    local udp, openError = self:_open(0, true)
    if not udp then return false, openError end
    local nonce = tostring(self.nonceFactory() or ""):lower()
    if not validNonce(nonce) then
        if type(udp.close) == "function" then pcall(udp.close, udp) end
        return false, "LAN discovery could not create a search token."
    end
    self.udp = udp
    self.mode = "search"
    self.nonce = nonce
    self.localAddress = options.localAddress
    if not self.localAddress and type(self.addressDetector) == "function" then
        local detected, address = pcall(self.addressDetector, {
            socket = self.socketModule,
        })
        if detected then self.localAddress = address end
    end
    self.lastQueryAt = -math.huge
    self.message = "Searching for shops on this network..."
    return true
end

function Discovery:_sendQuery(now)
    if now - self.lastQueryAt < Discovery.QUERY_INTERVAL then return end
    self.lastQueryAt = now
    local packet = queryPacket(self.nonce)
    safeCall(self.udp, "sendto", packet, "255.255.255.255", self.discoveryPort)
    local directed = directedBroadcast(self.localAddress)
    if directed and directed ~= "255.255.255.255" then
        safeCall(self.udp, "sendto", packet, directed, self.discoveryPort)
    end
end

function Discovery:_receiveHostQueries(now)
    local window = math.floor(now)
    if window ~= self.replyWindow then
        self.replyWindow, self.repliesInWindow = window, 0
    end
    for _ = 1, 24 do
        local ok, packet, address, port = pcall(self.udp.receivefrom, self.udp)
        if not ok or not packet then break end
        local nonce = parseQuery(packet)
        if nonce and type(address) == "string" and type(port) == "number"
            and self.repliesInWindow < Discovery.MAX_REPLIES_PER_SECOND
        then
            local reply = hostPacket(nonce, self.gamePort, self.hostName)
            local sent = safeCall(self.udp, "sendto", reply, address, port)
            if sent then self.repliesInWindow = self.repliesInWindow + 1 end
        end
    end
end

function Discovery:_receiveHostReplies(now)
    for _ = 1, 24 do
        local ok, packet, address = pcall(self.udp.receivefrom, self.udp)
        if not ok or not packet then break end
        local port, name = parseHost(packet, self.nonce)
        if port and type(address) == "string" and #address <= 64 then
            local key = address .. ":" .. tostring(port)
            if not self.resultsByAddress[key] and #self.resultOrder < Discovery.MAX_RESULTS then
                self.resultOrder[#self.resultOrder + 1] = key
            end
            if self.resultsByAddress[key] or #self.resultOrder <= Discovery.MAX_RESULTS then
                self.resultsByAddress[key] = {
                    address = address,
                    port = port,
                    name = name,
                    seenAt = now,
                }
            end
        end
    end
    local retained = {}
    for _, key in ipairs(self.resultOrder) do
        local result = self.resultsByAddress[key]
        if result and now - result.seenAt <= Discovery.RESULT_TTL then
            retained[#retained + 1] = key
        else
            self.resultsByAddress[key] = nil
        end
    end
    self.resultOrder = retained
    self.message = #retained > 0
        and (tostring(#retained) .. (#retained == 1 and " shop found." or " shops found."))
        or "Searching for shops on this network..."
end

function Discovery:update(_)
    if not self.udp then return end
    local now = self.clock()
    if self.mode == "host" then
        self:_receiveHostQueries(now)
    elseif self.mode == "search" then
        self:_sendQuery(now)
        self:_receiveHostReplies(now)
    end
end

function Discovery:results()
    local results = {}
    for _, key in ipairs(self.resultOrder) do
        local result = self.resultsByAddress[key]
        if result then
            results[#results + 1] = {
                address = result.address,
                port = result.port,
                name = result.name,
            }
        end
    end
    return results
end

function Discovery:status()
    return self.mode, self.message
end

return Discovery
