local Address = {}

Address.DEFAULT_PORT = 22122
Address.MAX_INPUT_LENGTH = 260

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function validPort(value)
    if type(value) == "string" and not value:match("^%d+$") then return nil end
    local port = tonumber(value)
    return port and port == math.floor(port) and port >= 1 and port <= 65535
        and port or nil
end

local function ipv4Octets(value)
    if type(value) ~= "string" then return nil end
    local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    local octets = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
    for _, octet in ipairs(octets) do
        if not octet or octet < 0 or octet > 255 then return nil end
    end
    return octets
end

local function normalizedIPv4(value)
    local octets = ipv4Octets(value)
    if not octets then return nil end
    return table.concat(octets, "."), octets
end

local function validDestinationIPv4(octets)
    if not octets then return false end
    if octets[1] == 0 or octets[1] >= 224 then return false end
    if octets[1] == 255 and octets[2] == 255
        and octets[3] == 255 and octets[4] == 255
    then return false end
    return true
end

local function normalizedHostname(value)
    if #value < 1 or #value > 253 then return nil end
    if value:find("[^%w%.%-]") then return nil end
    if value:find("..", 1, true) then return nil end
    if value:sub(1, 1) == "." or value:sub(-1) == "." then return nil end
    for label in value:gmatch("[^.]+") do
        if #label > 63 or label:sub(1, 1) == "-" or label:sub(-1) == "-" then
            return nil
        end
    end
    return value:lower()
end

function Address.validPort(value)
    return validPort(value) ~= nil
end

function Address.isIPv4(value)
    return normalizedIPv4(value) ~= nil
end

function Address.isLoopbackIPv4(value)
    local _, octets = normalizedIPv4(value)
    return octets ~= nil and octets[1] == 127
end

function Address.isPrivateIPv4(value)
    local _, octets = normalizedIPv4(value)
    if not octets then return false end
    return octets[1] == 10
        or (octets[1] == 172 and octets[2] >= 16 and octets[2] <= 31)
        or (octets[1] == 192 and octets[2] == 168)
end

function Address.isHamachiIPv4(value)
    local _, octets = normalizedIPv4(value)
    return octets ~= nil and octets[1] == 25
end

function Address.parse(value, defaultPort)
    if type(value) ~= "string" then return nil, "Host address must be text." end
    if #value > Address.MAX_INPUT_LENGTH then return nil, "Host address is too long." end
    value = trim(value)
    if value == "" then return nil, "Host address is required." end
    if value:find("[%z\1-\31\127]") then return nil, "Host address contains control characters." end
    if value:find("://", 1, true) or value:find("[/\\@%?#%[%]]") then
        return nil, "Enter only a host name or IPv4 address, not a URL."
    end

    local fallbackPort = defaultPort == nil and Address.DEFAULT_PORT or validPort(defaultPort)
    if not fallbackPort then return nil, "Default port must be between 1 and 65535." end

    local host, portText = value, nil
    local colon = value:find(":", 1, true)
    if colon then
        if value:find(":", colon + 1, true) then
            return nil, "IPv6 addresses are not supported by this LAN screen."
        end
        host, portText = value:sub(1, colon - 1), value:sub(colon + 1)
        if host == "" or portText == "" then return nil, "Host and port are both required." end
    end

    local port = fallbackPort
    if portText then port = validPort(portText) end
    if not port then return nil, "Port must be a whole number between 1 and 65535." end

    local normalized, octets = normalizedIPv4(host)
    if octets then
        if not validDestinationIPv4(octets) then return nil, "That IPv4 address cannot be a game host." end
        host = normalized
    else
        if host:match("^[%d%.]+$") then return nil, "IPv4 address is invalid." end
        host = normalizedHostname(host)
        if not host then return nil, "Host name is invalid." end
    end

    return {
        host = host,
        port = port,
        endpoint = host .. ":" .. tostring(port),
        isIPv4 = octets ~= nil,
        isLoopback = octets ~= nil and octets[1] == 127,
        isPrivate = octets ~= nil and Address.isPrivateIPv4(host),
    }
end

function Address.format(host, port)
    local parsed, errorMessage = Address.parse(tostring(host or ""), port)
    return parsed and parsed.endpoint or nil, errorMessage
end

local function candidateAddress(candidate)
    if type(candidate) == "string" then return candidate end
    if type(candidate) ~= "table" then return nil end
    return candidate.addr or candidate.address or candidate.host or candidate.ip
end

local function lanScore(value)
    local _, octets = normalizedIPv4(value)
    if not validDestinationIPv4(octets) or octets[1] == 127 then return nil end
    if octets[1] == 192 and octets[2] == 168 then return 500 end
    if octets[1] == 10 then return 490 end
    if octets[1] == 172 and octets[2] >= 16 and octets[2] <= 31 then return 480 end
    if octets[1] == 169 and octets[2] == 254 then return 250 end
    if octets[1] == 100 and octets[2] >= 64 and octets[2] <= 127 then return 150 end
    if octets[1] == 25 then return 20 end
    return 100
end

function Address.chooseLanAddress(candidates)
    local best, bestScore
    local seen = {}
    for _, candidate in ipairs(candidates or {}) do
        local raw = candidateAddress(candidate)
        local parsed = raw and Address.parse(raw)
        local value = parsed and parsed.isIPv4 and parsed.host or nil
        if value and not seen[value] then
            seen[value] = true
            local score = lanScore(value)
            if score and (not bestScore or score > bestScore
                or (score == bestScore and value < best))
            then
                best, bestScore = value, score
            end
        end
    end
    return best
end

local function appendCandidates(target, value)
    if type(value) == "string" then
        target[#target + 1] = value
    elseif type(value) == "table" then
        local direct = candidateAddress(value)
        if direct then target[#target + 1] = direct end
        for _, item in ipairs(value) do appendCandidates(target, item) end
    end
end

-- Android commonly reports only localhost for its process hostname even while
-- Wi-Fi is active. Connecting a UDP socket chooses an outbound route without
-- sending a packet; getsockname can then reveal the address on that route.
-- Keep this as a fallback so desktop DNS enumeration can still consider every
-- adapter and prefer the best private address.
local function routedLocalAddress(socketModule, options)
    if type(socketModule) ~= "table" or type(socketModule.udp) ~= "function" then
        return nil
    end
    local created, udp = pcall(socketModule.udp)
    if not created or (type(udp) ~= "table" and type(udp) ~= "userdata") then
        return nil
    end

    local selected
    local connected, result = pcall(udp.setpeername, udp,
        tostring(options.routeProbeHost or "192.0.2.1"),
        tonumber(options.routeProbePort) or 9)
    if connected and result ~= nil and result ~= false then
        local inspected, address = pcall(udp.getsockname, udp)
        if inspected then selected = Address.chooseLanAddress({ address }) end
    end
    if type(udp.close) == "function" then pcall(udp.close, udp) end
    return selected
end

function Address.detectLanAddress(options)
    options = options or {}
    if type(options.candidates) == "table" then
        local selected = Address.chooseLanAddress(options.candidates)
        return selected or nil, selected and nil or "No usable non-loopback IPv4 address was found."
    end

    local socketModule = options.socket
    if socketModule == nil then
        local ok, loaded = pcall(require, "socket")
        if ok then socketModule = loaded end
    end
    if type(socketModule) ~= "table" then return nil, "LuaSocket address lookup is unavailable." end

    local candidates = {}
    if type(socketModule.dns) == "table" and type(socketModule.dns.gethostname) == "function" then
        local okHost, hostname = pcall(socketModule.dns.gethostname)
        if okHost and type(hostname) == "string" and hostname ~= "" then
            if type(socketModule.dns.getaddrinfo) == "function" then
                local okInfo, info = pcall(socketModule.dns.getaddrinfo, hostname)
                if okInfo then appendCandidates(candidates, info) end
            end
            if type(socketModule.dns.toip) == "function" then
                local okIp, primary, resolved = pcall(socketModule.dns.toip, hostname)
                if okIp then
                    appendCandidates(candidates, primary)
                    appendCandidates(candidates, resolved)
                end
            end
        end
    end
    appendCandidates(candidates, options.extraCandidates)
    local selected = Address.chooseLanAddress(candidates)
    if not selected then selected = routedLocalAddress(socketModule, options) end
    return selected or nil, selected and nil or "No usable non-loopback IPv4 address was found."
end

Address.localAddress = Address.detectLanAddress
return Address
