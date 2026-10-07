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
Discovery.MAX_REPLIES_PER_SECOND = 128
Discovery.FALLBACK_SCAN_DELAY = 0.8
Discovery.UNICAST_PROBES_PER_SECOND = 128
Discovery.MAX_UNICAST_PROBES_PER_UPDATE = 6
Discovery.MAX_UNICAST_SCAN_TARGETS = 1024

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

local function directedBroadcast(address, prefixLength)
    local a, b, c
    if type(address) == "string" then
        a, b, c = address:match("^(%d+)%.(%d+)%.(%d+)%.%d+$")
    end
    if not a then return nil end
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if a > 255 or b > 255 or c > 255 then return nil end
    prefixLength = tonumber(prefixLength)
    if not prefixLength or prefixLength ~= math.floor(prefixLength)
        or prefixLength < 1 or prefixLength >= 31
    then
        -- Android USB tethering and most phone hotspots use /24. Only infer a
        -- broadcast for private addresses; never turn public DNS addresses
        -- into directed broadcast destinations.
        if not Address.isPrivateIPv4(address) then return nil end
        prefixLength = 24
    end
    local values = {}
    for value in address:gmatch("%d+") do values[#values + 1] = tonumber(value) end
    local remaining = 32 - prefixLength
    for index = 4, 1, -1 do
        local hostBits = math.min(8, remaining)
        local block = 2 ^ hostBits
        values[index] = math.floor(values[index] / block) * block + block - 1
        remaining = remaining - hostBits
    end
    return table.concat(values, ".")
end

local function isLocalBroadcastInterface(address)
    if Address.isPrivateIPv4(address) then return true end
    local a, b
    if type(address) == "string" then a, b = address:match("^(%d+)%.(%d+)%.") end
    a, b = tonumber(a), tonumber(b)
    return (a == 169 and b == 254)
        or (a == 100 and b and b >= 64 and b <= 127)
end

local function ipv4Number(address)
    if type(address) ~= "string" then return nil end
    local a, b, c, d = address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    local octets = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
    for _, octet in ipairs(octets) do
        if not octet or octet < 0 or octet > 255 or octet ~= math.floor(octet) then
            return nil
        end
    end
    return ((octets[1] * 256 + octets[2]) * 256 + octets[3]) * 256 + octets[4]
end

local function ipv4Text(value)
    local d = value % 256
    value = math.floor(value / 256)
    local c = value % 256
    value = math.floor(value / 256)
    local b = value % 256
    local a = math.floor(value / 256) % 256
    return string.format("%d.%d.%d.%d", a, b, c, d)
end

local function buildUnicastScanTargets(interfaces)
    local perInterface, seen, total = {}, {}, 0
    for _, interface in ipairs(interfaces or {}) do
        local address = type(interface) == "table" and interface.address or interface
        local addressNumber = ipv4Number(address)
        if addressNumber and isLocalBroadcastInterface(address) then
            local prefix = type(interface) == "table" and tonumber(interface.prefixLength) or nil
            if not prefix or prefix ~= math.floor(prefix) or prefix < 1 or prefix > 30 then
                prefix = 24
            end
            local subnetSize = 2 ^ (32 - prefix)
            local network = math.floor(addressNumber / subnetSize) * subnetSize
            local broadcast = network + subnetSize - 1
            local first, last = network + 1, broadcast - 1
            -- Avoid scanning huge carrier or enterprise subnets. Probe the
            -- interface's /24 neighborhood instead, which covers home Wi-Fi
            -- and Android hotspots even when the assigned mask is unusually
            -- wide. Ordinary /23 networks still get their full address range.
            if last - first + 1 > 512 then
                local local24 = math.floor(addressNumber / 256) * 256
                first, last = math.max(network + 1, local24 + 1), math.min(broadcast - 1, local24 + 254)
            end
            local limit = math.min(last - first + 1, 512)
            local targets = {}
            if limit > 0 then
                -- Start near the common gateway address, then walk the local
                -- range. Skip this device so its own discovery socket does
                -- not receive a pointless query.
                for candidate = first, first + limit - 1 do
                    if candidate ~= addressNumber then
                        targets[#targets + 1] = ipv4Text(candidate)
                    end
                end
            end
            if #targets > 0 then perInterface[#perInterface + 1] = targets end
        end
    end

    local targets, round = {}, 1
    while total < Discovery.MAX_UNICAST_SCAN_TARGETS do
        local added = false
        for _, addresses in ipairs(perInterface) do
            local address = addresses[round]
            if address and not seen[address] then
                seen[address] = true
                targets[#targets + 1] = address
                total = total + 1
                added = true
                if total >= Discovery.MAX_UNICAST_SCAN_TARGETS then break end
            end
        end
        if not added then break end
        round = round + 1
    end
    return targets
end

function Discovery.new(options)
    options = options or {}
    local clock = options.clock or defaultClock
    return setmetatable({
        socketModule = loadSocket(options.socket),
        addressDetector = options.addressDetector or Address.detectLanInterfaces,
        socketInjected = options.socket ~= nil,
        clock = clock,
        nonceFactory = options.nonceFactory or function() return defaultNonce(clock) end,
        discoveryPort = tonumber(options.port) or Discovery.PORT,
        mode = "idle",
        udp = nil,
        nonce = nil,
        gamePort = nil,
        hostName = nil,
        localAddress = nil,
        localInterfaces = {},
        unicastScanTargets = {},
        unicastScanIndex = 1,
        nextUnicastProbeAt = math.huge,
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
    self.localInterfaces = {}
    self.unicastScanTargets = {}
    self.unicastScanIndex = 1
    self.nextUnicastProbeAt = math.huge
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
    self.localInterfaces = type(options.localInterfaces) == "table"
        and options.localInterfaces or {}
    if #self.localInterfaces == 0 and type(self.addressDetector) == "function" then
        local detectorOptions = { native = not self.socketInjected }
        if self.socketInjected then detectorOptions.socket = self.socketModule end
        local detected, value = pcall(self.addressDetector, detectorOptions)
        if detected then
            if type(value) == "table" then
                self.localInterfaces = value
            elseif type(value) == "string" then
                self.localInterfaces = { { address = value } }
            end
        end
    end
    if #self.localInterfaces == 0 and self.localAddress then
        self.localInterfaces = { { address = self.localAddress } }
    end
    if not self.localAddress and self.localInterfaces[1] then
        local first = self.localInterfaces[1]
        self.localAddress = type(first) == "table" and first.address or first
    end
    self.unicastScanTargets = buildUnicastScanTargets(self.localInterfaces)
    self.unicastScanIndex = 1
    self.nextUnicastProbeAt = self.clock() + Discovery.FALLBACK_SCAN_DELAY
    self.lastQueryAt = -math.huge
    self.message = "Searching local adapters, including USB Ethernet..."
    return true
end

function Discovery:_sendFallbackProbes(now)
    if #self.unicastScanTargets == 0 or now < self.nextUnicastProbeAt then return end
    local sent = 0
    while sent < Discovery.MAX_UNICAST_PROBES_PER_UPDATE
        and now >= self.nextUnicastProbeAt
    do
        local target = self.unicastScanTargets[self.unicastScanIndex]
        if not target then
            self.unicastScanIndex = 1
            target = self.unicastScanTargets[self.unicastScanIndex]
        end
        if not target then return end
        safeCall(self.udp, "sendto", queryPacket(self.nonce), target, self.discoveryPort)
        self.unicastScanIndex = self.unicastScanIndex + 1
        self.nextUnicastProbeAt = self.nextUnicastProbeAt
            + 1 / Discovery.UNICAST_PROBES_PER_SECOND
        sent = sent + 1
    end
end

function Discovery:_sendQuery(now)
    if now - self.lastQueryAt < Discovery.QUERY_INTERVAL then return end
    self.lastQueryAt = now
    local packet = queryPacket(self.nonce)
    safeCall(self.udp, "sendto", packet, "255.255.255.255", self.discoveryPort)
    local sent = {}
    for _, interface in ipairs(self.localInterfaces or {}) do
        local address = type(interface) == "table" and interface.address or interface
        local directed = type(interface) == "table" and interface.broadcast or nil
        if type(directed) ~= "string" then
            directed = directedBroadcast(address,
                type(interface) == "table" and interface.prefixLength or nil)
        end
        if directed and isLocalBroadcastInterface(address)
            and directed ~= "255.255.255.255" and not sent[directed]
        then
            sent[directed] = true
            safeCall(self.udp, "sendto", packet, directed, self.discoveryPort)
        end
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
        or (self.unicastScanIndex > 1
            and "Checking nearby addresses on this local network..."
            or "Searching local adapters, including USB Ethernet...")
end

function Discovery:update(_)
    if not self.udp then return end
    local now = self.clock()
    if self.mode == "host" then
        self:_receiveHostQueries(now)
    elseif self.mode == "search" then
        self:_sendQuery(now)
        self:_sendFallbackProbes(now)
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

function Discovery:interfaces()
    local interfaces = {}
    for _, interface in ipairs(self.localInterfaces or {}) do
        if type(interface) == "table" then
            interfaces[#interfaces + 1] = {
                address = interface.address,
                prefixLength = interface.prefixLength,
                broadcast = interface.broadcast,
                interfaceName = interface.interfaceName,
                isUsb = interface.isUsb == true,
            }
        elseif type(interface) == "string" then
            interfaces[#interfaces + 1] = { address = interface }
        end
    end
    return interfaces
end

function Discovery:status()
    return self.mode, self.message
end

return Discovery
