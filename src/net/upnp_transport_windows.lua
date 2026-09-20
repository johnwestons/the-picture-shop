-- Windows-only transport for exact-route UPnP IGD discovery and control.
-- UDP discovery and every TCP control connection are pinned to both the
-- selected IPv4 source address and Windows interface index. No wildcard bind,
-- hostname lookup, redirect, or route choice occurs in this module.
local IpScope = require("src.net.ip_scope")
local MappingSocketWindows = require("src.net.mapping_socket_windows")
local UpnpIgd = require("src.net.upnp_igd")

local Transport = { exactNetworkBinding = true }

local AF_INET = 2
local SOCK_STREAM, SOCK_DGRAM = 1, 2
local IPPROTO_IP, IPPROTO_TCP, IPPROTO_UDP = 0, 6, 17
local SOL_SOCKET, SO_ERROR = 0xffff, 0x1007
local IP_MULTICAST_IF, IP_MULTICAST_TTL, IP_MULTICAST_LOOP = 9, 10, 11
local IP_UNICAST_IF = 31
local FIONBIO = -2147195266
local WSAEWOULDBLOCK, WSAEINPROGRESS = 10035, 10036
local SOCKET_ERROR = -1
local MAX_REQUEST_BYTES = UpnpIgd.MAX_SOAP_BODY_BYTES + UpnpIgd.MAX_HTTP_HEADER_BYTES
local MAX_RECEIVES_PER_UPDATE = 16

local ffi, winsock
local initialized = false

local function whole(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function validRoute(route)
    return type(route) == "table" and route.platform == "Windows"
        and route.family == 4 and IpScope.parse(route.internalAddress)
        and IpScope.parse(route.gatewayAddress)
        and whole(route.interfaceIndex, 1, 4294967295)
        and type(route.networkGeneration) == "string"
        and route.networkGeneration ~= ""
        and type(route.routeFingerprint) == "string"
end

local function loadWinsock()
    if winsock then return winsock, ffi end
    if initialized then return nil end
    initialized = true
    local library, ffiModule = MappingSocketWindows.runtimeForExactTransports()
    if not library or not ffiModule then return nil end
    local declared = pcall(ffiModule.cdef, [[
        struct tps_upnp_fd_set {
            unsigned int fd_count; tps_socket_t fd_array[64];
        };
        struct tps_upnp_timeval { long tv_sec; long tv_usec; };
        int getsockopt(tps_socket_t socket, int level, int name,
            char *value, int *length);
        int connect(tps_socket_t socket, const struct tps_sockaddr *address,
            int length);
        int getpeername(tps_socket_t socket, struct tps_sockaddr *address,
            int *length);
        int select(int ignored, struct tps_upnp_fd_set *readfds,
            struct tps_upnp_fd_set *writefds, struct tps_upnp_fd_set *exceptfds,
            const struct tps_upnp_timeval *timeout);
        int send(tps_socket_t socket, const char *buffer, int length, int flags);
        int recv(tps_socket_t socket, char *buffer, int length, int flags);
    ]])
    if not declared then return nil end
    ffi, winsock = ffiModule, library
    return winsock, ffi
end

local function invalidSocket(ffiModule, value)
    return value == ffiModule.cast("tps_socket_t", -1)
end

local function socketAddress(library, ffiModule, address, port)
    local parsed = IpScope.parse(address)
    if not parsed or not whole(port, 0, 65535) then return nil end
    local value = ffiModule.new("struct tps_sockaddr_in")
    value.sin_family = AF_INET
    value.sin_port = library.htons(port)
    if library.inet_pton(AF_INET, parsed.address, value.sin_addr) ~= 1 then return nil end
    return value
end

local function decodeAddress(library, ffiModule, address)
    if tonumber(address.sin_family) ~= AF_INET then return nil end
    local text = ffiModule.new("char[16]")
    if library.inet_ntop(AF_INET, address.sin_addr, text, 16) == nil then return nil end
    local value = ffiModule.string(text)
    return IpScope.parse(value) and value or nil
end

local function applyExactBinding(library, ffiModule, handle, route)
    local interface = ffiModule.new("unsigned long[1]", library.htonl(route.interfaceIndex))
    if library.setsockopt(handle, IPPROTO_IP, IP_UNICAST_IF,
            ffiModule.cast("const char *", interface), ffiModule.sizeof(interface)) ~= 0 then
        return false
    end
    local nonblocking = ffiModule.new("unsigned long[1]", 1)
    if library.ioctlsocket(handle, FIONBIO, nonblocking) ~= 0 then return false end
    local localAddress = socketAddress(library, ffiModule, route.internalAddress, 0)
    return localAddress and library.bind(handle,
        ffiModule.cast("const struct tps_sockaddr *", localAddress),
        ffiModule.sizeof(localAddress)) == 0
end

local function localBinding(library, ffiModule, handle, route)
    local reported = ffiModule.new("struct tps_sockaddr_in")
    local size = ffiModule.new("int[1]", ffiModule.sizeof(reported))
    if library.getsockname(handle,
            ffiModule.cast("struct tps_sockaddr *", reported), size) ~= 0
        or size[0] ~= ffiModule.sizeof(reported)
        or decodeAddress(library, ffiModule, reported) ~= route.internalAddress
    then
        return nil
    end
    local port = tonumber(library.ntohs(reported.sin_port))
    return whole(port, 1, 65535) and port or nil
end

local function proofFor(route, localPort)
    return {
        family = 4,
        internalAddress = route.internalAddress,
        gatewayAddress = route.gatewayAddress,
        interfaceIndex = route.interfaceIndex,
        networkGeneration = route.networkGeneration,
        routeFingerprint = route.routeFingerprint,
        localPort = localPort,
        exactNetworkBinding = true,
    }
end

local Discovery = {}
Discovery.__index = Discovery

function Discovery:sendto(packet, address, port)
    if self.closed or type(packet) ~= "string" or #packet < 1
        or #packet > UpnpIgd.MAX_SSDP_BYTES
        or address ~= UpnpIgd.SSDP_ADDRESS or port ~= UpnpIgd.SSDP_PORT then
        return nil, "socket_error"
    end
    local target = socketAddress(self.library, self.ffi, address, port)
    if not target then return nil, "socket_error" end
    local sent = self.library.sendto(self.handle, packet, #packet, 0,
        self.ffi.cast("const struct tps_sockaddr *", target), self.ffi.sizeof(target))
    if sent == SOCKET_ERROR or sent ~= #packet then return nil, "socket_error" end
    return sent
end

function Discovery:receivefrom()
    if self.closed then return nil, "socket_error" end
    local buffer = self.ffi.new("char[?]", UpnpIgd.MAX_SSDP_BYTES)
    local source = self.ffi.new("struct tps_sockaddr_in")
    local size = self.ffi.new("int[1]", self.ffi.sizeof(source))
    local received = self.library.recvfrom(self.handle, buffer, UpnpIgd.MAX_SSDP_BYTES,
        0, self.ffi.cast("struct tps_sockaddr *", source), size)
    if received == SOCKET_ERROR then
        if self.library.WSAGetLastError() == WSAEWOULDBLOCK then return nil, "timeout" end
        return nil, "socket_error"
    end
    local address = decodeAddress(self.library, self.ffi, source)
    local port = tonumber(self.library.ntohs(source.sin_port))
    if received < 1 or size[0] ~= self.ffi.sizeof(source)
        or not address or not whole(port, 1, 65535) then
        return nil, "socket_error"
    end
    return self.ffi.string(buffer, received), address, port
end

function Discovery:bindingProof()
    if self.closed then return nil end
    local result = {}
    for key, value in pairs(self.proof) do result[key] = value end
    return result
end

function Discovery:close()
    if self.closed then return self.closeOk == true end
    self.closeOk = self.library.closesocket(self.handle) == 0
    self.closed, self.handle = true, nil
    return self.closeOk
end

function Transport.openDiscovery(route)
    if not validRoute(route) then return nil, "invalid_route" end
    local library, ffiModule = loadWinsock()
    if not library then return nil, "unavailable" end
    local handle = library.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if invalidSocket(ffiModule, handle) then return nil, "unavailable" end
    local function fail()
        library.closesocket(handle)
        return nil, "bind_failed"
    end
    if not applyExactBinding(library, ffiModule, handle, route) then return fail() end
    local multicastAddress = ffiModule.new("struct tps_in_addr[1]")
    local ttl, loop = ffiModule.new("int[1]", 2), ffiModule.new("int[1]", 0)
    if library.inet_pton(AF_INET, route.internalAddress, multicastAddress) ~= 1
        or library.setsockopt(handle, IPPROTO_IP, IP_MULTICAST_IF,
            ffiModule.cast("const char *", multicastAddress),
            ffiModule.sizeof(multicastAddress[0])) ~= 0
        or library.setsockopt(handle, IPPROTO_IP, IP_MULTICAST_TTL,
            ffiModule.cast("const char *", ttl), ffiModule.sizeof(ttl)) ~= 0
        or library.setsockopt(handle, IPPROTO_IP, IP_MULTICAST_LOOP,
            ffiModule.cast("const char *", loop), ffiModule.sizeof(loop)) ~= 0 then
        return fail()
    end
    local localPort = localBinding(library, ffiModule, handle, route)
    if not localPort then return fail() end
    return setmetatable({ library = library, ffi = ffiModule, handle = handle,
        closed = false, proof = proofFor(route, localPort) }, Discovery)
end

local Http = {}
Http.__index = Http

local function responseIsComplete(raw)
    local separator = raw:find("\r\n\r\n", 1, true)
    if not separator then return false end
    local header = raw:sub(1, separator - 1):lower()
    local found, count = nil, 0
    for line in header:gmatch("[^\r\n]+") do
        local name, value = line:match("^([^:]+):[ \t]*(.-)[ \t]*$")
        if name == "content-length" then
            count = count + 1
            if not value:match("^%d+$") or #value > 10 then return false end
            found = tonumber(value)
        end
    end
    return count == 1 and found ~= nil and #raw >= separator + 3 + found
end

function Http:_peerProof()
    local peer = self.ffi.new("struct tps_sockaddr_in")
    local size = self.ffi.new("int[1]", self.ffi.sizeof(peer))
    if self.library.getpeername(self.handle,
            self.ffi.cast("struct tps_sockaddr *", peer), size) ~= 0
        or size[0] ~= self.ffi.sizeof(peer) then return nil end
    local address = decodeAddress(self.library, self.ffi, peer)
    local port = tonumber(self.library.ntohs(peer.sin_port))
    if address ~= self.route.gatewayAddress or port ~= self.request.port then return nil end
    return address, port
end

function Http:_finishConnect()
    if self.connected then return true end
    local writable = self.ffi.new("struct tps_upnp_fd_set")
    local exceptional = self.ffi.new("struct tps_upnp_fd_set")
    writable.fd_count, exceptional.fd_count = 1, 1
    writable.fd_array[0], exceptional.fd_array[0] = self.handle, self.handle
    local timeout = self.ffi.new("struct tps_upnp_timeval")
    local ready = self.library.select(0, nil, writable, exceptional, timeout)
    if ready == SOCKET_ERROR then return nil, "socket_error" end
    if ready == 0 then return nil, "pending" end
    local socketError, size = self.ffi.new("int[1]"), self.ffi.new("int[1]", 4)
    if self.library.getsockopt(self.handle, SOL_SOCKET, SO_ERROR,
            self.ffi.cast("char *", socketError), size) ~= 0
        or socketError[0] ~= 0 or exceptional.fd_count > 0 then
        return nil, "socket_error"
    end
    local address, port = self:_peerProof()
    if not address then return nil, "socket_error" end
    self.connected, self.peerAddress, self.peerPort = true, address, port
    return true
end

function Http:update()
    if self.closed or self.done then return nil, "socket_error" end
    local connected, connectError = self:_finishConnect()
    if not connected then return nil, connectError end
    if self.sent < #self.request.wire then
        local pointer = self.ffi.cast("const char *", self.request.wire) + self.sent
        local sent = self.library.send(self.handle, pointer, #self.request.wire - self.sent, 0)
        if sent == SOCKET_ERROR then
            if self.library.WSAGetLastError() == WSAEWOULDBLOCK then return nil, "pending" end
            return nil, "socket_error"
        end
        if sent < 1 then return nil, "socket_error" end
        self.sent = self.sent + sent
        if self.sent < #self.request.wire then return nil, "pending" end
    end
    for _ = 1, MAX_RECEIVES_PER_UPDATE do
        local buffer = self.ffi.new("char[8192]")
        local received = self.library.recv(self.handle, buffer, 8192, 0)
        if received == SOCKET_ERROR then
            if self.library.WSAGetLastError() == WSAEWOULDBLOCK then return nil, "pending" end
            return nil, "socket_error"
        end
        if received == 0 then
            if #self.raw == 0 then return nil, "socket_error" end
            self.done = true
            return { raw = self.raw, peerAddress = self.peerAddress,
                peerPort = self.peerPort }
        end
        self.raw = self.raw .. self.ffi.string(buffer, received)
        if #self.raw > self.maxResponseBytes then return nil, "response_too_large" end
        if responseIsComplete(self.raw) then
            self.done = true
            return { raw = self.raw, peerAddress = self.peerAddress,
                peerPort = self.peerPort }
        end
    end
    return nil, "pending"
end

function Http:requestSent()
    return self.sent == #self.request.wire
end

function Http:bindingProof()
    if self.closed then return nil end
    local result = {}
    for key, value in pairs(self.proof) do result[key] = value end
    return result
end

function Http:close()
    if self.closed then return self.closeOk == true end
    self.closeOk = self.library.closesocket(self.handle) == 0
    self.closed, self.handle = true, nil
    return self.closeOk
end

function Transport.openHttp(route, request, maxResponseBytes)
    if not validRoute(route) or type(request) ~= "table"
        or request.host ~= route.gatewayAddress or not whole(request.port, 1, 65535)
        or type(request.wire) ~= "string" or #request.wire < 1
        or #request.wire > MAX_REQUEST_BYTES
        or not whole(maxResponseBytes, 1, 2 * UpnpIgd.MAX_DESCRIPTION_BYTES)
    then
        return nil, "invalid_request"
    end
    local library, ffiModule = loadWinsock()
    if not library then return nil, "unavailable" end
    local handle = library.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if invalidSocket(ffiModule, handle) then return nil, "unavailable" end
    local function fail(reason)
        library.closesocket(handle)
        return nil, reason or "bind_failed"
    end
    if not applyExactBinding(library, ffiModule, handle, route) then return fail() end
    local localPort = localBinding(library, ffiModule, handle, route)
    if not localPort then return fail() end
    local target = socketAddress(library, ffiModule, route.gatewayAddress, request.port)
    if not target then return fail("invalid_request") end
    local result = library.connect(handle,
        ffiModule.cast("const struct tps_sockaddr *", target), ffiModule.sizeof(target))
    local connected = result == 0
    if result == SOCKET_ERROR then
        local code = library.WSAGetLastError()
        if code ~= WSAEWOULDBLOCK and code ~= WSAEINPROGRESS then
            return fail("connect_failed")
        end
    end
    local http = setmetatable({ library = library, ffi = ffiModule, handle = handle,
        route = route, request = request, maxResponseBytes = maxResponseBytes,
        connected = connected, sent = 0, raw = "", closed = false,
        proof = proofFor(route, localPort) }, Http)
    if connected then
        local address, port = http:_peerProof()
        if not address then return fail("connect_failed") end
        http.peerAddress, http.peerPort = address, port
    end
    return http
end

return Transport
