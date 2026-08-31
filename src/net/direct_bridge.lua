local Ipv6Address = require("src.net.ipv6_address")

local DirectBridge = {
    MAGIC = "TPSB",
    VERSION = 1,
    TYPE_DATA = 1,
    HEADER_BYTES = 32,
    CRYPTO_OVERHEAD_BYTES = 24,
    MAX_OUTER_BYTES = 1232,
    MAX_FRAGMENT_BYTES = 1176,
    MAX_INNER_BYTES = 1400,
    MAX_FRAGMENTS = 2,
    MAX_RECEIVES_PER_UPDATE = 32,
    DEFAULT_MAX_PENDING_DATAGRAMS = 32,
    DEFAULT_MAX_PENDING_BYTES = 32 * 1400,
    DEFAULT_REASSEMBLY_TIMEOUT_SECONDS = 2,
    COMPLETED_CACHE_SIZE = 128,
}

local Controller = {}
Controller.__index = Controller

local ERROR_OPTIONS = "Direct bridge options are invalid."
local ERROR_SOCKET = "Direct bridge socket failed."
local ERROR_PROVIDER = "Direct bridge authentication failed."
local ERROR_PROTOCOL = "Direct bridge protocol failed."
local ERROR_CLOCK = "Direct bridge clock failed."
local ERROR_CLEANUP = "Direct bridge cleanup failed."

local function finiteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function wholeNumber(value, minimum, maximum)
    return finiteNumber(value)
        and value == math.floor(value)
        and value >= minimum
        and value <= maximum
        and value or nil
end

local function defaultClock()
    if love and love.timer and type(love.timer.getTime) == "function" then
        return love.timer.getTime()
    end
    return os.clock()
end

local function closeValue(value)
    return value ~= nil and value ~= false
end

local function socketShape(socket, requireName)
    local valueType = type(socket)
    return (valueType == "table" or valueType == "userdata")
        and type(socket.settimeout) == "function"
        and type(socket.sendto) == "function"
        and type(socket.receivefrom) == "function"
        and type(socket.close) == "function"
        and (not requireName or type(socket.getsockname) == "function")
end

local function stateShape(state)
    return type(state) == "table"
        and type(state.seal) == "function"
        and type(state.open) == "function"
        and type(state.close) == "function"
end

local function be16(value)
    return string.char(math.floor(value / 256) % 256, value % 256)
end

local function be32(value)
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256)
end

local function read16(value, offset)
    local a, b = value:byte(offset, offset + 1)
    if not a or not b then return nil end
    return a * 256 + b
end

local function read32(value, offset)
    local a, b, c, d = value:byte(offset, offset + 3)
    if not a or not b or not c or not d then return nil end
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function expectedFragmentBytes(totalLength, fragmentIndex, fragmentCount)
    if not wholeNumber(totalLength, 1, DirectBridge.MAX_INNER_BYTES)
        or not wholeNumber(fragmentCount, 1, DirectBridge.MAX_FRAGMENTS)
        or not wholeNumber(fragmentIndex, 0, fragmentCount - 1) then
        return nil
    end
    local expectedCount = totalLength <= DirectBridge.MAX_FRAGMENT_BYTES and 1 or 2
    if fragmentCount ~= expectedCount then return nil end
    if fragmentIndex == 0 then
        return math.min(totalLength, DirectBridge.MAX_FRAGMENT_BYTES)
    end
    return totalLength - DirectBridge.MAX_FRAGMENT_BYTES
end

local function encodeHeader(roleByte, invitationId, datagramId,
    fragmentIndex, fragmentCount, totalLength)
    if not wholeNumber(roleByte, 1, 2)
        or type(invitationId) ~= "string" or #invitationId ~= 16
        or not wholeNumber(datagramId, 1, 0xffffffff)
        or not expectedFragmentBytes(totalLength, fragmentIndex, fragmentCount) then
        return nil
    end
    return DirectBridge.MAGIC
        .. string.char(DirectBridge.VERSION, DirectBridge.TYPE_DATA, roleByte, 0)
        .. invitationId
        .. be32(datagramId)
        .. string.char(fragmentIndex, fragmentCount)
        .. be16(totalLength)
end

local function parseHeader(packet)
    if type(packet) ~= "string"
        or #packet < DirectBridge.HEADER_BYTES + DirectBridge.CRYPTO_OVERHEAD_BYTES
        or #packet > DirectBridge.MAX_OUTER_BYTES
        or packet:sub(1, 4) ~= DirectBridge.MAGIC
        or packet:byte(5) ~= DirectBridge.VERSION
        or packet:byte(6) ~= DirectBridge.TYPE_DATA
        or packet:byte(8) ~= 0 then
        return nil
    end
    local roleByte = packet:byte(7)
    local datagramId = read32(packet, 25)
    local fragmentIndex = packet:byte(29)
    local fragmentCount = packet:byte(30)
    local totalLength = read16(packet, 31)
    local fragmentBytes = expectedFragmentBytes(
        totalLength, fragmentIndex, fragmentCount)
    if not wholeNumber(roleByte, 1, 2)
        or not wholeNumber(datagramId, 1, 0xffffffff)
        or not fragmentBytes
        or #packet ~= DirectBridge.HEADER_BYTES
            + DirectBridge.CRYPTO_OVERHEAD_BYTES + fragmentBytes then
        return nil
    end
    return {
        roleByte = roleByte,
        invitationId = packet:sub(9, 24),
        datagramId = datagramId,
        fragmentIndex = fragmentIndex,
        fragmentCount = fragmentCount,
        totalLength = totalLength,
        fragmentBytes = fragmentBytes,
        header = packet:sub(1, DirectBridge.HEADER_BYTES),
        ciphertext = packet:sub(DirectBridge.HEADER_BYTES + 1),
    }
end

local function sendSucceeded(result, byteCount)
    return result == 1 or result == byteCount
end

local function isLoopback(address)
    return address == "127.0.0.1"
end

function Controller:_now()
    local ok, now = pcall(self._clock)
    if not ok or not finiteNumber(now) or now < 0
        or (self._lastNow ~= nil and now < self._lastNow) then
        return nil
    end
    self._lastNow = now
    return now
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

    local inner = self._innerSocket
    self._innerSocket = nil
    if inner and self.ownsInnerSocket then
        local ok, result = pcall(inner.close, inner)
        if not ok or not closeValue(result) then cleaned = false end
    end

    local outer = self._outerSocket
    self._outerSocket = nil
    if outer and self.ownsOuterSocket then
        local ok, result = pcall(outer.close, outer)
        if not ok or not closeValue(result) then cleaned = false end
    end

    self._pending = {}
    self._pendingCount = 0
    self._pendingBytes = 0
    self._completed = {}
    self._completedOrder = {}
    self._cleanupOk = cleaned
    return cleaned
end

function Controller:_fail(message)
    if self.status == "running" then
        self.status = "failed"
        self.lastError = message
        self:_cleanup()
    end
    return false, self.lastError
end

function Controller:_removePending(datagramId)
    local entry = self._pending[datagramId]
    if not entry then return nil end
    self._pending[datagramId] = nil
    self._pendingCount = self._pendingCount - 1
    self._pendingBytes = self._pendingBytes - entry.bytes
    return entry
end

function Controller:_evictOldest()
    local oldestId, oldestAt
    for datagramId, entry in pairs(self._pending) do
        if oldestAt == nil or entry.createdAt < oldestAt
            or (entry.createdAt == oldestAt and datagramId < oldestId) then
            oldestId, oldestAt = datagramId, entry.createdAt
        end
    end
    if oldestId then
        self:_removePending(oldestId)
        self.droppedDatagrams = self.droppedDatagrams + 1
        return true
    end
    return false
end

function Controller:_expirePending(now)
    local expired = {}
    for datagramId, entry in pairs(self._pending) do
        if now - entry.createdAt >= self.reassemblyTimeoutSeconds then
            expired[#expired + 1] = datagramId
        end
    end
    for _, datagramId in ipairs(expired) do
        self:_removePending(datagramId)
        self.droppedDatagrams = self.droppedDatagrams + 1
    end
end

function Controller:_markCompleted(datagramId)
    self._completed[datagramId] = true
    self._completedOrder[#self._completedOrder + 1] = datagramId
    if #self._completedOrder > DirectBridge.COMPLETED_CACHE_SIZE then
        local expired = table.remove(self._completedOrder, 1)
        self._completed[expired] = nil
    end
end

function Controller:_deliver(datagramId, entry)
    if not self._localTargetPort then return true, false end
    local datagram
    if entry.fragmentCount == 1 then
        datagram = entry.fragments[1]
    else
        datagram = entry.fragments[1] and entry.fragments[2]
            and (entry.fragments[1] .. entry.fragments[2]) or nil
    end
    if not datagram then return true, false end
    if #datagram ~= entry.totalLength then return self:_fail(ERROR_PROTOCOL) end

    local ok, sent = pcall(self._innerSocket.sendto, self._innerSocket,
        datagram, self._localTargetAddress, self._localTargetPort)
    if not ok or not sendSucceeded(sent, #datagram) then
        return self:_fail(ERROR_SOCKET)
    end
    self:_removePending(datagramId)
    self:_markCompleted(datagramId)
    self.receivedDatagrams = self.receivedDatagrams + 1
    return true, true
end

function Controller:_deliverCompleted()
    if not self._localTargetPort then return true end
    local ready = {}
    for datagramId, entry in pairs(self._pending) do
        if entry.complete then
            ready[#ready + 1] = { id = datagramId, at = entry.createdAt }
        end
    end
    table.sort(ready, function(a, b)
        return a.at < b.at or (a.at == b.at and a.id < b.id)
    end)
    for _, item in ipairs(ready) do
        local ok = self:_deliver(item.id, self._pending[item.id])
        if not ok then return false end
    end
    return true
end

function Controller:_sendDatagram(datagram)
    if self._nextDatagramId > 0xffffffff then
        return self:_fail(ERROR_PROTOCOL)
    end
    local datagramId = self._nextDatagramId
    local fragmentCount = #datagram <= DirectBridge.MAX_FRAGMENT_BYTES and 1 or 2

    for fragmentIndex = 0, fragmentCount - 1 do
        local first = fragmentIndex * DirectBridge.MAX_FRAGMENT_BYTES + 1
        local last = math.min(#datagram,
            first + DirectBridge.MAX_FRAGMENT_BYTES - 1)
        local plaintext = datagram:sub(first, last)
        local header = encodeHeader(self._localRoleByte, self._invitationId,
            datagramId, fragmentIndex, fragmentCount, #datagram)
        if not header or #plaintext == 0 then return self:_fail(ERROR_PROTOCOL) end

        local ok, ciphertext, errorMessage = pcall(
            self._state.seal, self._state, plaintext, header)
        if not ok or errorMessage ~= nil
            or type(ciphertext) ~= "string"
            or #ciphertext ~= #plaintext + DirectBridge.CRYPTO_OVERHEAD_BYTES then
            return self:_fail(ERROR_PROVIDER)
        end
        local packet = header .. ciphertext
        if #packet > DirectBridge.MAX_OUTER_BYTES then
            return self:_fail(ERROR_PROTOCOL)
        end
        local sentOk, sent = pcall(self._outerSocket.sendto,
            self._outerSocket, packet, self._peerAddress, self._peerPort)
        if not sentOk or not sendSucceeded(sent, #packet) then
            return self:_fail(ERROR_SOCKET)
        end
        self.sentFragments = self.sentFragments + 1
    end

    self._nextDatagramId = datagramId + 1
    self.sentDatagrams = self.sentDatagrams + 1
    return true
end

function Controller:_acceptLocal(packet, address, port)
    if type(packet) ~= "string" or #packet < 1
        or #packet > DirectBridge.MAX_INNER_BYTES
        or not isLoopback(address)
        or not wholeNumber(port, 1, 65535) then
        return false
    end
    if self._localTargetPort then
        return address == self._localTargetAddress
            and port == self._localTargetPort
    end
    if self.role ~= "guest" then return false end
    self._localTargetAddress = address
    self._localTargetPort = port
    return true
end

function Controller:_drainInner()
    for _ = 1, DirectBridge.MAX_RECEIVES_PER_UPDATE do
        local ok, packet, address, port = pcall(
            self._innerSocket.receivefrom, self._innerSocket)
        if not ok then return self:_fail(ERROR_SOCKET) end
        if packet == nil then
            if address == "timeout" then return true end
            return self:_fail(ERROR_SOCKET)
        end
        if self:_acceptLocal(packet, address, port) then
            if not self:_sendDatagram(packet) then return false end
        end
    end
    return true
end

function Controller:_acceptOuterSource(address, port)
    if port ~= self._peerPort or type(address) ~= "string" then return false end
    local parsed = Ipv6Address.parse(address)
    return parsed ~= nil and parsed.isGlobal == true
        and parsed.bytes == self._peerAddressBytes
end

function Controller:_storeFragment(parsed, plaintext, now)
    if self._completed[parsed.datagramId] then return true end
    local entry = self._pending[parsed.datagramId]
    if entry then
        if entry.fragmentCount ~= parsed.fragmentCount
            or entry.totalLength ~= parsed.totalLength then
            return self:_fail(ERROR_PROTOCOL)
        end
        local existing = entry.fragments[parsed.fragmentIndex + 1]
        if existing then
            if existing ~= plaintext then return self:_fail(ERROR_PROTOCOL) end
            return true
        end
    else
        while self._pendingCount >= self.maxPendingDatagrams do
            if not self:_evictOldest() then return self:_fail(ERROR_PROTOCOL) end
        end
        entry = {
            createdAt = now,
            fragmentCount = parsed.fragmentCount,
            totalLength = parsed.totalLength,
            fragments = {},
            bytes = 0,
            complete = false,
        }
        self._pending[parsed.datagramId] = entry
        self._pendingCount = self._pendingCount + 1
    end

    while self._pendingBytes + #plaintext > self.maxPendingBytes do
        if self._pendingCount == 1 and self._pending[parsed.datagramId] then
            return self:_fail(ERROR_PROTOCOL)
        end
        if not self:_evictOldest() then return self:_fail(ERROR_PROTOCOL) end
        entry = self._pending[parsed.datagramId]
        if not entry then
            entry = {
                createdAt = now,
                fragmentCount = parsed.fragmentCount,
                totalLength = parsed.totalLength,
                fragments = {},
                bytes = 0,
                complete = false,
            }
            self._pending[parsed.datagramId] = entry
            self._pendingCount = self._pendingCount + 1
        end
    end

    entry.fragments[parsed.fragmentIndex + 1] = plaintext
    entry.bytes = entry.bytes + #plaintext
    self._pendingBytes = self._pendingBytes + #plaintext
    entry.complete = entry.bytes == entry.totalLength
        and entry.fragments[1] ~= nil
        and (entry.fragmentCount == 1 or entry.fragments[2] ~= nil)
    if entry.complete then
        return self:_deliver(parsed.datagramId, entry)
    end
    return true
end

function Controller:_processOuter(packet, address, port, now)
    if not self:_acceptOuterSource(address, port) then return true end
    local parsed = parseHeader(packet)
    if not parsed
        or parsed.roleByte ~= self._peerRoleByte
        or parsed.invitationId ~= self._invitationId then
        return true
    end
    local ok, plaintext, errorMessage = pcall(
        self._state.open, self._state, parsed.ciphertext, parsed.header)
    if not ok or errorMessage ~= nil then return self:_fail(ERROR_PROVIDER) end
    if plaintext == false then
        self.rejectedFragments = self.rejectedFragments + 1
        return true
    end
    if type(plaintext) ~= "string" or #plaintext ~= parsed.fragmentBytes then
        return self:_fail(ERROR_PROVIDER)
    end
    self.receivedFragments = self.receivedFragments + 1
    return self:_storeFragment(parsed, plaintext, now)
end

function Controller:_drainOuter(now)
    for _ = 1, DirectBridge.MAX_RECEIVES_PER_UPDATE do
        local ok, packet, address, port = pcall(
            self._outerSocket.receivefrom, self._outerSocket)
        if not ok then return self:_fail(ERROR_SOCKET) end
        if packet == nil then
            if address == "timeout" then return true end
            return self:_fail(ERROR_SOCKET)
        end
        if not self:_processOuter(packet, address, port, now) then return false end
    end
    return true
end

function Controller:update()
    if self.status ~= "running" then return self.status, self.lastError end
    local now = self:_now()
    if not now then
        self:_fail(ERROR_CLOCK)
        return self.status, self.lastError
    end
    self:_expirePending(now)
    if not self:_drainInner()
        or not self:_deliverCompleted()
        or not self:_drainOuter(now)
        or not self:_deliverCompleted() then
        return self.status, self.lastError
    end
    return self.status, nil
end

Controller.poll = Controller.update

function Controller:localEndpoint()
    if self.status ~= "running" or not self._innerSocket then
        return nil, ERROR_SOCKET
    end
    local ok, address, port = pcall(
        self._innerSocket.getsockname, self._innerSocket)
    if not ok or not isLoopback(address)
        or not wholeNumber(port, 1, 65535) then
        return nil, ERROR_SOCKET
    end
    return address, port
end

function Controller:close()
    if self.status == "closed" then
        if self._cleanupOk then return true end
        return false, ERROR_CLEANUP
    end
    local cleaned = self:_cleanup()
    self.status = "closed"
    self.lastError = nil
    if not cleaned then
        self.lastError = ERROR_CLEANUP
        return false, ERROR_CLEANUP
    end
    return true
end

function DirectBridge.create(options)
    if type(options) ~= "table"
        or (options.role ~= "host" and options.role ~= "guest")
        or not socketShape(options.outerSocket)
        or not socketShape(options.innerSocket, true)
        or type(options.masterKey) ~= "string" or #options.masterKey ~= 32
        or type(options.invitationId) ~= "string" or #options.invitationId ~= 16
        or type(options.guestNonce) ~= "string" or #options.guestNonce ~= 16
        or (options.ownsOuterSocket ~= nil
            and type(options.ownsOuterSocket) ~= "boolean")
        or (options.ownsInnerSocket ~= nil
            and type(options.ownsInnerSocket) ~= "boolean") then
        return nil, ERROR_OPTIONS
    end

    -- After the structural boundary succeeds, owned sockets transfer to this
    -- constructor even when a later semantic or provider check fails.
    local ownsOuter = options.ownsOuterSocket ~= false
    local ownsInner = options.ownsInnerSocket ~= false
    local function closeInjected()
        if ownsInner then pcall(options.innerSocket.close, options.innerSocket) end
        if ownsOuter then pcall(options.outerSocket.close, options.outerSocket) end
    end

    local peerAddress = Ipv6Address.parse(options.peerAddress)
    local peerPort = wholeNumber(options.peerPort, 1, 65535)
    local localTargetPort = options.localTargetPort
    if localTargetPort ~= nil then
        localTargetPort = wholeNumber(localTargetPort, 1, 65535)
    end
    local localTargetAddress = options.localTargetAddress or "127.0.0.1"
    if not peerAddress or peerAddress.isGlobal ~= true or not peerPort
        or not isLoopback(localTargetAddress)
        or (options.localTargetPort ~= nil and not localTargetPort)
        or (options.role == "host" and not localTargetPort) then
        closeInjected()
        return nil, ERROR_OPTIONS
    end

    local provider = options.provider
    local constructorName = options.role == "host"
        and "newBridgeHost" or "newBridgeGuest"
    if type(provider) ~= "table" or type(provider[constructorName]) ~= "function" then
        closeInjected()
        return nil, ERROR_OPTIONS
    end
    local clock = options.clock or defaultClock
    local reassemblyTimeout = options.reassemblyTimeoutSeconds
        or DirectBridge.DEFAULT_REASSEMBLY_TIMEOUT_SECONDS
    local maxPendingDatagrams = wholeNumber(options.maxPendingDatagrams
        or DirectBridge.DEFAULT_MAX_PENDING_DATAGRAMS, 1, 256)
    local maxPendingBytes = wholeNumber(options.maxPendingBytes
        or DirectBridge.DEFAULT_MAX_PENDING_BYTES,
        DirectBridge.MAX_INNER_BYTES, 256 * DirectBridge.MAX_INNER_BYTES)
    if type(clock) ~= "function"
        or not finiteNumber(reassemblyTimeout) or reassemblyTimeout <= 0
        or reassemblyTimeout > 30
        or not maxPendingDatagrams or not maxPendingBytes then
        closeInjected()
        return nil, ERROR_OPTIONS
    end
    local outerOk, outerResult = pcall(
        options.outerSocket.settimeout, options.outerSocket, 0)
    local innerOk, innerResult = pcall(
        options.innerSocket.settimeout, options.innerSocket, 0)
    if not outerOk or not closeValue(outerResult)
        or not innerOk or not closeValue(innerResult) then
        closeInjected()
        return nil, ERROR_SOCKET
    end

    local constructor = provider[constructorName]
    local stateOk, state = pcall(constructor,
        options.masterKey, options.invitationId, options.guestNonce)
    if not stateOk or not stateShape(state) then
        if type(state) == "table" and type(state.close) == "function" then
            pcall(state.close, state)
        end
        closeInjected()
        return nil, ERROR_PROVIDER
    end

    local localRoleByte = options.role == "host" and 1 or 2
    local controller = setmetatable({
        status = "running",
        lastError = nil,
        role = options.role,
        ownsOuterSocket = ownsOuter,
        ownsInnerSocket = ownsInner,
        reassemblyTimeoutSeconds = reassemblyTimeout,
        maxPendingDatagrams = maxPendingDatagrams,
        maxPendingBytes = maxPendingBytes,
        sentDatagrams = 0,
        sentFragments = 0,
        receivedDatagrams = 0,
        receivedFragments = 0,
        rejectedFragments = 0,
        droppedDatagrams = 0,
        _outerSocket = options.outerSocket,
        _innerSocket = options.innerSocket,
        _state = state,
        _clock = clock,
        _peerAddress = peerAddress.address,
        _peerAddressBytes = peerAddress.bytes,
        _peerPort = peerPort,
        _localTargetAddress = localTargetAddress,
        _localTargetPort = localTargetPort,
        _invitationId = options.invitationId,
        _localRoleByte = localRoleByte,
        _peerRoleByte = localRoleByte == 1 and 2 or 1,
        _nextDatagramId = 1,
        _pending = {},
        _pendingCount = 0,
        _pendingBytes = 0,
        _completed = {},
        _completedOrder = {},
        _cleaned = false,
        _cleanupOk = true,
    }, Controller)
    local now = controller:_now()
    if not now then
        controller:_fail(ERROR_CLOCK)
        return nil, ERROR_CLOCK
    end
    return controller
end

DirectBridge.encodeHeader = encodeHeader
DirectBridge.parseHeader = parseHeader
DirectBridge.Controller = Controller

return DirectBridge
