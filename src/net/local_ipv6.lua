local Ipv6Address = require("src.net.ipv6_address")

local LocalIpv6 = {}

-- UDP connect selects a local route without sending a datagram. The host uses
-- a numeric documentation address only as a route selector; a guest should
-- supply the validated host address so the OS selects that peer's route.
local DEFAULT_ROUTE_ADDRESS = "2001:db8::1"

local MESSAGES = {
    ipv6_unavailable = "IPv6 sockets are unavailable on this device.",
    invalid_ipv6_peer = "Paste a valid, unexpired IPv6 host code first.",
    no_ipv6_route = "This network has no usable IPv6 route. Try another Wi-Fi network or mobile data, then retry.",
    no_global_ipv6 = "This network has no public IPv6 address for Direct Play. Try another Wi-Fi network or mobile data, then retry.",
    ipv6_bind_failed = "This device's IPv6 address changed or cannot be used. Check the network and retry.",
    ipv6_cleanup_failed = "IPv6 socket cleanup could not be verified. Restart the test app before retrying.",
}

local function successful(value)
    return value ~= nil and value ~= false
end

local function isSocket(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function close(socket)
    if not isSocket(socket) or type(socket.close) ~= "function" then return false end
    local called, result = pcall(socket.close, socket)
    return called and successful(result)
end

local function finish(socket, value, reason)
    if not close(socket) then return nil, "ipv6_cleanup_failed" end
    return value, reason
end

local function create(socketModule)
    local called, socket = pcall(socketModule.udp6)
    if not called or not isSocket(socket) then return nil, "ipv6_unavailable" end
    if type(socket.settimeout) ~= "function"
        or type(socket.getsockname) ~= "function"
        or type(socket.close) ~= "function" then
        return finish(socket, nil, "ipv6_unavailable")
    end
    local configured, result = pcall(socket.settimeout, socket, 0)
    if not configured or not successful(result) then
        return finish(socket, nil, "ipv6_unavailable")
    end
    return socket
end

local function selectedAddress(socketModule, peerAddress)
    local socket, reason = create(socketModule)
    if not socket then return nil, reason end
    if type(socket.setpeername) ~= "function" then
        return finish(socket, nil, "ipv6_unavailable")
    end
    local connected, result = pcall(socket.setpeername, socket, peerAddress, 9)
    if not connected or not successful(result) then
        return finish(socket, nil, "no_ipv6_route")
    end
    local inspected, address = pcall(socket.getsockname, socket)
    local parsed = inspected and Ipv6Address.parse(address) or nil
    if not parsed or parsed.isGlobal ~= true then
        return finish(socket, nil, "no_global_ipv6")
    end
    return finish(socket, parsed.address)
end

local function verifyExactBind(socketModule, address)
    local socket, reason = create(socketModule)
    if not socket then return nil, reason end
    if type(socket.setsockname) ~= "function" then
        return finish(socket, nil, "ipv6_unavailable")
    end
    local bound, result = pcall(socket.setsockname, socket, address, 0)
    if not bound or not successful(result) then
        return finish(socket, nil, "ipv6_bind_failed")
    end
    local inspected, boundAddress, boundPort = pcall(socket.getsockname, socket)
    local parsed = inspected and Ipv6Address.parse(boundAddress) or nil
    -- Android LuaSocket may return the bound port as a numeric string.
    local port = tonumber(boundPort)
    if not parsed or parsed.address ~= address or not port
        or port ~= math.floor(port) or port < 1 or port > 65535 then
        return finish(socket, nil, "ipv6_bind_failed")
    end
    return finish(socket, address)
end

-- No DNS, address service, send/receive, invite creation, or persistent socket
-- is used here. This is local address selection, not a reachability test.
function LocalIpv6.detect(options)
    options = options or {}
    local peerAddress = DEFAULT_ROUTE_ADDRESS
    if options.peerAddress ~= nil then
        local parsed = Ipv6Address.parse(options.peerAddress)
        if not parsed or parsed.isGlobal ~= true then return nil, "invalid_ipv6_peer" end
        peerAddress = parsed.address
    end
    local socketModule = options.socketModule
    if socketModule == nil then
        local loaded, value = pcall(require, "socket")
        if loaded then socketModule = value end
    end
    if type(socketModule) ~= "table" or type(socketModule.udp6) ~= "function" then
        return nil, "ipv6_unavailable"
    end
    local address, reason = selectedAddress(socketModule, peerAddress)
    if not address then return nil, reason end
    return verifyExactBind(socketModule, address)
end

function LocalIpv6.messageFor(reason)
    return MESSAGES[reason] or MESSAGES.no_global_ipv6
end

return LocalIpv6
