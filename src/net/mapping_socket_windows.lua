-- Windows-only exact-interface UDP socket for PCP/NAT-PMP control traffic.
--
-- LuaSocket can bind an IPv4 source address, but it cannot also pin the
-- Windows interface index.  This narrow LuaJIT FFI boundary does both with
-- IP_UNICAST_IF, then exposes only the nonblocking datagram operations used by
-- the router-mapping adapter.  It never discovers a route or chooses a
-- wildcard address.
local IpScope = require("src.net.ip_scope")

local MappingSocketWindows = {
    exactNetworkBinding = true,
}

local AF_INET = 2
local SOCK_DGRAM = 2
local IPPROTO_IP = 0
local IPPROTO_UDP = 17
local IP_UNICAST_IF = 31
local FIONBIO = -2147195266 -- 0x8004667e as a signed Win32 long
local WSAEWOULDBLOCK = 10035
local SOCKET_ERROR = -1
local MAX_PACKET_BYTES = 1100

local ffi
local winsock
local initialized = false

local function wholeNumber(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function loadWinsock()
    if winsock then return winsock, ffi end
    if initialized then return nil end
    initialized = true
    if not jit or jit.os ~= "Windows" or jit.arch ~= "x64" then return nil end

    local ok, ffiModule = pcall(require, "ffi")
    if not ok or type(ffiModule) ~= "table" then return nil end
    local cdefOk = pcall(ffiModule.cdef, [[
        typedef unsigned short tps_sa_family_t;
        typedef unsigned long long tps_socket_t;
        struct tps_in_addr { unsigned long s_addr; };
        struct tps_sockaddr {
            tps_sa_family_t sa_family;
            char sa_data[14];
        };
        struct tps_sockaddr_in {
            short sin_family;
            unsigned short sin_port;
            struct tps_in_addr sin_addr;
            char sin_zero[8];
        };
        int WSAStartup(unsigned short version, void *data);
        int WSAGetLastError(void);
        tps_socket_t socket(int af, int type, int protocol);
        int ioctlsocket(tps_socket_t socket, long command, unsigned long *value);
        int setsockopt(tps_socket_t socket, int level, int name,
            const char *value, int length);
        int bind(tps_socket_t socket, const struct tps_sockaddr *address,
            int length);
        int getsockname(tps_socket_t socket, struct tps_sockaddr *address,
            int *length);
        int sendto(tps_socket_t socket, const char *buffer, int length,
            int flags, const struct tps_sockaddr *address, int address_length);
        int recvfrom(tps_socket_t socket, char *buffer, int length,
            int flags, struct tps_sockaddr *address, int *address_length);
        int closesocket(tps_socket_t socket);
        unsigned short htons(unsigned short value);
        unsigned short ntohs(unsigned short value);
        unsigned long htonl(unsigned long value);
        int inet_pton(int family, const char *text, void *address);
        const char *inet_ntop(int family, const void *address,
            char *text, size_t length);
    ]])
    if not cdefOk then return nil end

    local loadOk, library = pcall(ffiModule.load, "ws2_32")
    if not loadOk or not library then return nil end
    local startupData = ffiModule.new("uint64_t[64]")
    if library.WSAStartup(0x0202, startupData) ~= 0 then return nil end
    ffi, winsock = ffiModule, library
    return winsock, ffi
end

local function invalidSocket(ffiModule, value)
    local maximum = ffiModule.cast("tps_socket_t", -1)
    return value == maximum
end

local function socketAddress(library, ffiModule, address, port)
    local parsed = IpScope.parse(address)
    if not parsed or not wholeNumber(port, 0, 65535) then return nil end
    local result = ffiModule.new("struct tps_sockaddr_in")
    result.sin_family = AF_INET
    result.sin_port = library.htons(port)
    if library.inet_pton(AF_INET, parsed.address, result.sin_addr) ~= 1 then
        return nil
    end
    return result
end

local function decodeAddress(library, ffiModule, address)
    if tonumber(address.sin_family) ~= AF_INET then return nil end
    local text = ffiModule.new("char[16]")
    if library.inet_ntop(AF_INET, address.sin_addr, text, 16) == nil then
        return nil
    end
    local value = ffiModule.string(text)
    return IpScope.parse(value) and value or nil
end

local Socket = {}
Socket.__index = Socket

function Socket:sendto(packet, address, port)
    if self.closed or type(packet) ~= "string" or #packet < 1
        or #packet > MAX_PACKET_BYTES then
        return nil, "socket_error"
    end
    local target = socketAddress(self.library, self.ffi, address, port)
    if not target then return nil, "socket_error" end
    local sent = self.library.sendto(self.handle, packet, #packet, 0,
        self.ffi.cast("const struct tps_sockaddr *", target),
        self.ffi.sizeof(target))
    if sent == SOCKET_ERROR or sent ~= #packet then return nil, "socket_error" end
    return sent
end

function Socket:receivefrom()
    if self.closed then return nil, "socket_error" end
    local buffer = self.ffi.new("char[?]", MAX_PACKET_BYTES)
    local source = self.ffi.new("struct tps_sockaddr_in")
    local sourceLength = self.ffi.new("int[1]", self.ffi.sizeof(source))
    local received = self.library.recvfrom(self.handle, buffer,
        MAX_PACKET_BYTES, 0,
        self.ffi.cast("struct tps_sockaddr *", source), sourceLength)
    if received == SOCKET_ERROR then
        if self.library.WSAGetLastError() == WSAEWOULDBLOCK then
            return nil, "timeout"
        end
        return nil, "socket_error"
    end
    if received < 1 or received > MAX_PACKET_BYTES
        or sourceLength[0] ~= self.ffi.sizeof(source) then
        return nil, "socket_error"
    end
    local address = decodeAddress(self.library, self.ffi, source)
    local port = tonumber(self.library.ntohs(source.sin_port))
    if not address or not wholeNumber(port, 1, 65535) then
        return nil, "socket_error"
    end
    return self.ffi.string(buffer, received), address, port
end

function Socket:bindingProof()
    if self.closed then return nil end
    local proof = {}
    for key, value in pairs(self.proof) do proof[key] = value end
    return proof
end

function Socket:close()
    if self.closed then return self.closeOk == true end
    local result = self.library.closesocket(self.handle)
    self.closed = true
    self.handle = nil
    self.closeOk = result == 0
    return self.closeOk
end

function MappingSocketWindows.open(route)
    if type(route) ~= "table" or route.platform ~= "Windows"
        or route.family ~= 4 or not IpScope.parse(route.internalAddress)
        or not IpScope.parse(route.gatewayAddress)
        or not wholeNumber(route.interfaceIndex, 1, 4294967295)
        or type(route.networkGeneration) ~= "string"
        or route.networkGeneration == ""
        or type(route.routeFingerprint) ~= "string" then
        return nil, "invalid_route"
    end
    local library, ffiModule = loadWinsock()
    if not library or not ffiModule then return nil, "unavailable" end

    local handle = library.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if invalidSocket(ffiModule, handle) then return nil, "unavailable" end
    local function fail()
        library.closesocket(handle)
        return nil, "bind_failed"
    end

    -- Windows requires IP_UNICAST_IF's interface index in network byte order.
    local interface = ffiModule.new("unsigned long[1]",
        library.htonl(route.interfaceIndex))
    if library.setsockopt(handle, IPPROTO_IP, IP_UNICAST_IF,
            ffiModule.cast("const char *", interface),
            ffiModule.sizeof(interface)) ~= 0 then
        return fail()
    end
    local nonblocking = ffiModule.new("unsigned long[1]", 1)
    if library.ioctlsocket(handle, FIONBIO, nonblocking) ~= 0 then
        return fail()
    end
    local localAddress = socketAddress(library, ffiModule,
        route.internalAddress, 0)
    if not localAddress or library.bind(handle,
            ffiModule.cast("const struct tps_sockaddr *", localAddress),
            ffiModule.sizeof(localAddress)) ~= 0 then
        return fail()
    end

    local reported = ffiModule.new("struct tps_sockaddr_in")
    local reportedLength = ffiModule.new("int[1]", ffiModule.sizeof(reported))
    if library.getsockname(handle,
            ffiModule.cast("struct tps_sockaddr *", reported),
            reportedLength) ~= 0
        or reportedLength[0] ~= ffiModule.sizeof(reported)
        or decodeAddress(library, ffiModule, reported) ~= route.internalAddress
        or not wholeNumber(tonumber(library.ntohs(reported.sin_port)), 1, 65535)
    then
        return fail()
    end

    return setmetatable({
        library = library,
        ffi = ffiModule,
        handle = handle,
        closed = false,
        proof = {
            family = 4,
            internalAddress = route.internalAddress,
            gatewayAddress = route.gatewayAddress,
            interfaceIndex = route.interfaceIndex,
            networkGeneration = route.networkGeneration,
            routeFingerprint = route.routeFingerprint,
            exactNetworkBinding = true,
        },
    }, Socket)
end

-- Shared only by the sibling exact-route UPnP transport. Keeping the base
-- declarations in one LuaJIT FFI boundary prevents incompatible duplicate
-- Winsock declarations when the protocols run sequentially.
function MappingSocketWindows.runtimeForExactTransports()
    return loadWinsock()
end

return MappingSocketWindows
