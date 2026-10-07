-- Read-only local IPv4 interface enumeration for Local Play. This module does
-- not open sockets or send traffic; it only reads addresses already assigned
-- by the operating system (including USB tether/Ethernet adapters).
local InterfaceAddresses = {}

local ffi
local ffiAttempted = false

local function loadFfi()
    if ffiAttempted then return ffi end
    ffiAttempted = true
    local ok, module = pcall(require, "ffi")
    if ok and type(module) == "table" then ffi = module end
    return ffi
end

local function platform()
    if love and love.system and type(love.system.getOS) == "function" then
        local ok, value = pcall(love.system.getOS)
        if ok and type(value) == "string" then return value end
    end
    return jit and jit.os or nil
end

local function prefixFromOctets(octets)
    local prefix, sawZero = 0, false
    for _, byte in ipairs(octets) do
        for bit = 7, 0, -1 do
            local set = math.floor(byte / (2 ^ bit)) % 2 == 1
            if set and sawZero then return nil end
            if set then prefix = prefix + 1 else sawZero = true end
        end
    end
    return prefix
end

local function broadcastFor(address, prefixLength)
    if type(address) ~= "string" or type(prefixLength) ~= "number"
        or prefixLength < 1 or prefixLength >= 31
    then
        return nil
    end
    local a, b, c, d = address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    local octets = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
    local remaining = 32 - prefixLength
    for index = 4, 1, -1 do
        local hostBits = math.min(8, remaining)
        local hostMask = (2 ^ hostBits) - 1
        local networkPart = math.floor(octets[index] / (2 ^ hostBits)) * (2 ^ hostBits)
        octets[index] = networkPart + hostMask
        remaining = remaining - hostBits
    end
    return table.concat(octets, ".")
end

local function isUsbName(name)
    name = tostring(name or ""):lower()
    return name:find("usb", 1, true) ~= nil
        or name:find("rndis", 1, true) ~= nil
        or name:find("ncm", 1, true) ~= nil
        or name:find("remote nd", 1, true) ~= nil
end

local function appendAddress(target, address, prefixLength, name)
    if type(address) ~= "string" then return end
    target[#target + 1] = {
        address = address,
        prefixLength = prefixLength,
        broadcast = broadcastFor(address, prefixLength),
        interfaceName = tostring(name or ""),
        isUsb = isUsbName(name),
    }
end

local function enumeratePosix(ffiModule)
    local declarations = [[
        typedef unsigned short tps_sa_family_t;
        struct tps_sockaddr {
            tps_sa_family_t sa_family;
            char sa_data[14];
        };
        struct tps_sockaddr_in {
            tps_sa_family_t sin_family;
            unsigned short sin_port;
            unsigned char sin_addr_bytes[4];
            unsigned char sin_zero[8];
        };
        struct tps_ifaddrs {
            struct tps_ifaddrs *ifa_next;
            char *ifa_name;
            unsigned int ifa_flags;
            struct tps_sockaddr *ifa_addr;
            struct tps_sockaddr *ifa_netmask;
            struct tps_sockaddr *ifa_ifu;
            void *ifa_data;
        };
        int getifaddrs(struct tps_ifaddrs **);
        void freeifaddrs(struct tps_ifaddrs *);
    ]]
    local declared = pcall(ffiModule.cdef, declarations)
    if not declared then return nil end
    local head = ffiModule.new("struct tps_ifaddrs *[1]")
    local ok, result = pcall(ffiModule.C.getifaddrs, head)
    if not ok or result ~= 0 or head[0] == nil then return nil end

    local addresses = {}
    local current = head[0]
    while current ~= nil do
        local flags = tonumber(current.ifa_flags)
        local address = current.ifa_addr
        if address ~= nil and tonumber(address.sa_family) == 2
            and flags and flags % 2 == 1 and math.floor(flags / 8) % 2 == 0
        then
            local sockaddr = ffiModule.cast("struct tps_sockaddr_in *", address)
            local text = string.format("%d.%d.%d.%d",
                tonumber(sockaddr.sin_addr_bytes[0]),
                tonumber(sockaddr.sin_addr_bytes[1]),
                tonumber(sockaddr.sin_addr_bytes[2]),
                tonumber(sockaddr.sin_addr_bytes[3]))
            local prefix
            if current.ifa_netmask ~= nil
                and tonumber(current.ifa_netmask.sa_family) == 2
            then
                local mask = ffiModule.cast("struct tps_sockaddr_in *", current.ifa_netmask)
                local maskText = string.format("%d.%d.%d.%d",
                    tonumber(mask.sin_addr_bytes[0]), tonumber(mask.sin_addr_bytes[1]),
                    tonumber(mask.sin_addr_bytes[2]), tonumber(mask.sin_addr_bytes[3]))
                local m1, m2, m3, m4 = maskText:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
                prefix = prefixFromOctets({
                    tonumber(m1), tonumber(m2), tonumber(m3), tonumber(m4),
                })
            end
            local name = current.ifa_name ~= nil and ffiModule.string(current.ifa_name) or ""
            appendAddress(addresses, text, prefix, name)
        end
        current = current.ifa_next
    end
    pcall(ffiModule.C.freeifaddrs, head[0])
    return addresses
end

local function enumerateWindows(ffiModule)
    local declarations = [[
        typedef unsigned long tps_win_ulong;
        typedef unsigned int tps_win_uint;
        typedef unsigned char tps_win_uchar;
        typedef struct tps_win_sockaddr {
            unsigned short sa_family;
            char sa_data[14];
        } tps_win_sockaddr;
        typedef struct tps_win_sockaddr_in {
            unsigned short sin_family;
            unsigned short sin_port;
            unsigned char sin_addr_bytes[4];
            unsigned char sin_zero[8];
        } tps_win_sockaddr_in;
        typedef struct tps_win_socket_address {
            tps_win_sockaddr *lpSockaddr;
            int iSockaddrLength;
        } tps_win_socket_address;
        typedef struct tps_win_unicast {
            union {
                unsigned long long alignment;
                struct { tps_win_ulong length; tps_win_ulong flags; } fields;
            } header;
            struct tps_win_unicast *next;
            tps_win_socket_address address;
            int prefixOrigin;
            int suffixOrigin;
            int dadState;
            tps_win_ulong validLifetime;
            tps_win_ulong preferredLifetime;
            tps_win_ulong leaseLifetime;
            tps_win_uchar onLinkPrefixLength;
        } tps_win_unicast;
        typedef struct tps_win_adapter {
            tps_win_ulong length;
            tps_win_ulong ifIndex;
            struct tps_win_adapter *next;
            char *adapterName;
            tps_win_unicast *firstUnicastAddress;
            void *firstAnycastAddress;
            void *firstMulticastAddress;
            void *firstDnsServerAddress;
            unsigned short *dnsSuffix;
            unsigned short *description;
            unsigned short *friendlyName;
            tps_win_uchar physicalAddress[32];
            tps_win_ulong physicalAddressLength;
            tps_win_ulong flags;
            tps_win_ulong mtu;
            tps_win_ulong ifType;
            int operStatus;
            tps_win_ulong ipv6IfIndex;
            tps_win_ulong zoneIndices[16];
        } tps_win_adapter;
        int __stdcall GetAdaptersAddresses(
            tps_win_ulong, tps_win_ulong, void *, tps_win_adapter *, tps_win_ulong *);
    ]]
    local declared = pcall(ffiModule.cdef, declarations)
    if not declared then return nil end
    local loaded, library = pcall(ffiModule.load, "iphlpapi")
    if not loaded or not library then return nil end
    local size = ffiModule.new("tps_win_ulong[1]", 0)
    local status = tonumber(library.GetAdaptersAddresses(2, 0x10 + 0x04 + 0x08,
        nil, nil, size))
    if status ~= 111 or size[0] == 0 then return nil end
    local storage = ffiModule.new("tps_win_uchar[?]", tonumber(size[0]))
    local adapters = ffiModule.cast("tps_win_adapter *", storage)
    status = tonumber(library.GetAdaptersAddresses(2, 0x10 + 0x04 + 0x08,
        nil, adapters, size))
    if status ~= 0 then return nil end

    local addresses = {}
    local adapter = adapters
    while adapter ~= nil do
        -- IF_OPER_STATUS.Up is 1; software loopback and tunnel adapters cannot
        -- provide a direct Ethernet broadcast path for cable play.
        if tonumber(adapter.operStatus) == 1
            and tonumber(adapter.ifType) ~= 24 and tonumber(adapter.ifType) ~= 131
        then
            local description = ""
            local wide = adapter.friendlyName or adapter.description
            if wide ~= nil then
                local chars = ffiModule.cast("const unsigned short *", wide)
                local parts = {}
                for index = 0, 255 do
                    local code = tonumber(chars[index])
                    if code == 0 then break end
                    if code < 128 then parts[#parts + 1] = string.char(code) end
                end
                description = table.concat(parts):lower()
            end
            local unicast = adapter.firstUnicastAddress
            while unicast ~= nil do
                local socketAddress = unicast.address.lpSockaddr
                if socketAddress ~= nil and tonumber(socketAddress.sa_family) == 2 then
                    local sockaddr = ffiModule.cast("tps_win_sockaddr_in *", socketAddress)
                    local text = string.format("%d.%d.%d.%d",
                        tonumber(sockaddr.sin_addr_bytes[0]), tonumber(sockaddr.sin_addr_bytes[1]),
                        tonumber(sockaddr.sin_addr_bytes[2]), tonumber(sockaddr.sin_addr_bytes[3]))
                    local usb = isUsbName(description)
                    appendAddress(addresses, text,
                        tonumber(unicast.onLinkPrefixLength), usb and "USB network" or description)
                end
                unicast = unicast.next
            end
        end
        adapter = adapter.next
    end
    return addresses
end

function InterfaceAddresses.enumerate(options)
    options = type(options) == "table" and options or {}
    local ffiModule = loadFfi()
    if not ffiModule then return nil, "ffi_unavailable" end
    local osName = options.os or platform()
    if osName == "Windows" then return enumerateWindows(ffiModule) end
    if osName == "Android" or osName == "Linux" or osName == "OS X" or osName == "macOS" then
        return enumeratePosix(ffiModule)
    end
    return nil, "platform_unavailable"
end

return InterfaceAddresses
