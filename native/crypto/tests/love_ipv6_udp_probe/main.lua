local ROLE_HOST = "host"
local ROLE_CLIENT = "client"
local MIN_PORT = 20000
local MAX_PORT = 60999
local RETRY_SECONDS = 0.25
local TIMEOUT_SECONDS = 35
local SUCCESS_GRACE_SECONDS = 3

local runtime = {
    socket = nil,
    config = nil,
    startedAt = 0,
    nextSendAt = 0,
    successAt = nil,
    sentLogged = false,
    finished = false,
    quitRequested = false,
}

local function requestQuit(code)
    if runtime.quitRequested then return end
    runtime.quitRequested = true
    if love and love.event and type(love.event.quit) == "function" then
        pcall(love.event.quit, code)
    end
end

local function closeSocket()
    local udp = runtime.socket
    runtime.socket = nil
    if udp and type(udp.close) == "function" then pcall(udp.close, udp) end
end

local function fail(code)
    if runtime.finished then return end
    runtime.finished = true
    closeSocket()
    -- Never print socket errors: lower layers may include either player's
    -- globally routable address. Fixed stage codes are enough for diagnosis.
    print("TPS_IPV6_UDP_FAIL run=" .. tostring(runtime.config and runtime.config.runId)
        .. " role=" .. tostring(runtime.config and runtime.config.role)
        .. " stage=" .. tostring(code))
    requestQuit(1)
end

local function succeed()
    if runtime.successAt then return end
    runtime.successAt = love.timer.getTime()
    print("TPS_IPV6_UDP_OK run=" .. runtime.config.runId
        .. " role=" .. runtime.config.role)
end

local function validConfig(config)
    if type(config) ~= "table" then return false end
    if config.role ~= ROLE_HOST and config.role ~= ROLE_CLIENT then return false end
    if type(config.port) ~= "number" or config.port ~= math.floor(config.port)
        or config.port < MIN_PORT or config.port > MAX_PORT
    then
        return false
    end
    if type(config.runId) ~= "string" or #config.runId ~= 32
        or not config.runId:match("^[0-9a-f]+$")
    then
        return false
    end
    if type(config.token) ~= "string" or #config.token ~= 64
        or not config.token:match("^[0-9a-f]+$")
    then
        return false
    end
    if config.role == ROLE_CLIENT
        and (type(config.hostAddress) ~= "string"
            or not config.hostAddress:find(":", 1, true))
    then
        return false
    end
    return true
end

local function probePayload()
    return "TPS6/P/" .. runtime.config.runId .. "/" .. runtime.config.token
end

local function ackPayload()
    return "TPS6/A/" .. runtime.config.runId .. "/" .. runtime.config.token
end

local function loadProbe()
    local configOk, config = pcall(require, "probe_config")
    if not configOk or not validConfig(config) then
        runtime.config = { role = "unknown" }
        return fail("config")
    end
    runtime.config = config

    local socketOk, socket = pcall(require, "socket")
    if not socketOk or type(socket) ~= "table" or type(socket.udp6) ~= "function" then
        return fail("udp6_unavailable")
    end
    local udp, createError = socket.udp6()
    if not udp then return fail("udp6_create") end
    runtime.socket = udp

    local timeoutOk = udp:settimeout(0)
    if timeoutOk ~= 1 then return fail("nonblocking") end

    if config.role == ROLE_HOST then
        local bound = udp:setsockname("::", config.port)
        if bound ~= 1 then return fail("bind") end
        print("TPS_IPV6_UDP_READY run=" .. config.runId .. " role=host")
    else
        local connected = udp:setpeername(config.hostAddress, config.port)
        if connected ~= 1 then return fail("connect") end
        runtime.nextSendAt = 0
        print("TPS_IPV6_UDP_READY run=" .. config.runId .. " role=client")
    end
    runtime.startedAt = love.timer.getTime()
end

function love.load()
    local ok = pcall(loadProbe)
    if not ok and not runtime.finished then fail("load") end
end

local function updateHost()
    for _ = 1, 32 do
        local data, address, port = runtime.socket:receivefrom()
        if not data then break end
        if data == probePayload() and type(address) == "string"
            and type(port) == "number"
        then
            local sent = runtime.socket:sendto(ackPayload(), address, port)
            if not sent then return fail("reply") end
            succeed()
        end
    end
end

local function updateClient(now)
    if not runtime.successAt and now >= runtime.nextSendAt then
        local sent = runtime.socket:send(probePayload())
        if not sent then return fail("send") end
        if not runtime.sentLogged then
            runtime.sentLogged = true
            print("TPS_IPV6_UDP_SENT run=" .. runtime.config.runId .. " role=client")
        end
        runtime.nextSendAt = now + RETRY_SECONDS
    end
    for _ = 1, 32 do
        local data = runtime.socket:receive()
        if not data then break end
        if data == ackPayload() then succeed() end
    end
end

function love.update()
    if runtime.finished or not runtime.socket then return end
    local now = love.timer.getTime()
    local ok
    if runtime.config.role == ROLE_HOST then
        ok = pcall(updateHost)
    else
        ok = pcall(updateClient, now)
    end
    if not ok then return fail("network") end

    if runtime.successAt and now - runtime.successAt >= SUCCESS_GRACE_SECONDS then
        runtime.finished = true
        closeSocket()
        return requestQuit(0)
    end
    if now - runtime.startedAt >= TIMEOUT_SECONDS then return fail("timeout") end
end

function love.quit()
    closeSocket()
end
