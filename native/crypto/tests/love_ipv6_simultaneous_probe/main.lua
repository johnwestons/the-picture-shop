local ROLE_HOST = "host"
local ROLE_CLIENT = "client"
local MIN_PORT = 20000
local MAX_PORT = 60999
local MIN_TIMEOUT_SECONDS = 5
local MAX_TIMEOUT_SECONDS = 120
local RETRY_SECONDS = 0.25
local SUCCESS_GRACE_SECONDS = 3
local MAX_RECEIVES_PER_UPDATE = 32

local runtime = {
    socket = nil,
    config = nil,
    markerRunId = "invalid",
    markerRole = "unknown",
    startedAt = 0,
    nextHelloAt = 0,
    nextAckAt = 0,
    peerHelloReceived = false,
    peerAckReceived = false,
    sentLogged = false,
    successAt = nil,
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

local function marker(name, suffix)
    local line = name .. " run=" .. runtime.markerRunId
        .. " role=" .. runtime.markerRole
    if suffix then line = line .. " " .. suffix end
    print(line)
end

local function fail(stage)
    if runtime.finished then return end
    runtime.finished = true
    closeSocket()
    -- Fixed stage names only: socket errors can contain globally routable
    -- addresses, so no lower-level error or packet content is ever printed.
    marker("TPS_IPV6_SIM_FAIL", "stage=" .. stage)
    requestQuit(1)
end

local function validHex(value, length)
    return type(value) == "string"
        and #value == length
        and value:match("^[0-9a-f]+$") ~= nil
end

local function validConfig(config)
    if type(config) ~= "table" then return false end
    if config.role ~= ROLE_HOST and config.role ~= ROLE_CLIENT then return false end
    if type(config.port) ~= "number" or config.port ~= math.floor(config.port)
        or config.port < MIN_PORT or config.port > MAX_PORT
    then
        return false
    end
    if not validHex(config.runId, 32) or not validHex(config.token, 64) then
        return false
    end
    if type(config.peerAddress) ~= "string"
        or #config.peerAddress < 2 or #config.peerAddress > 64
        or not config.peerAddress:find(":", 1, true)
        or not config.peerAddress:match("^[0-9A-Fa-f:]+$")
    then
        return false
    end
    if type(config.timeoutSeconds) ~= "number"
        or config.timeoutSeconds ~= config.timeoutSeconds
        or config.timeoutSeconds < MIN_TIMEOUT_SECONDS
        or config.timeoutSeconds > MAX_TIMEOUT_SECONDS
    then
        return false
    end
    return true
end

local function peerRole()
    if runtime.config.role == ROLE_HOST then return ROLE_CLIENT end
    return ROLE_HOST
end

local function helloPayload(role)
    return "TPS6/SIM/H/" .. role .. "/" .. runtime.config.runId
        .. "/" .. runtime.config.token
end

local function ackPayload(role)
    return "TPS6/SIM/A/" .. role .. "/" .. runtime.config.runId
        .. "/" .. runtime.config.token
end

local function sendHello(now)
    if now < runtime.nextHelloAt then return end
    runtime.nextHelloAt = now + RETRY_SECONDS
    local sent = runtime.socket:send(helloPayload(runtime.config.role))
    if sent and not runtime.sentLogged then
        runtime.sentLogged = true
        marker("TPS_IPV6_SIM_SENT")
    end
end

local function sendAck(now, immediate)
    if not runtime.peerHelloReceived then return end
    if not immediate and now < runtime.nextAckAt then return end
    runtime.nextAckAt = now + RETRY_SECONDS
    -- A transient UDP error is retried until the bounded overall timeout.
    runtime.socket:send(ackPayload(runtime.config.role))
end

local function markSuccess(now)
    if runtime.successAt
        or not runtime.peerHelloReceived
        or not runtime.peerAckReceived
    then
        return
    end
    runtime.successAt = now
    marker("TPS_IPV6_SIM_OK")
end

local function receivePackets(now)
    local expectedHello = helloPayload(peerRole())
    local expectedAck = ackPayload(peerRole())
    for _ = 1, MAX_RECEIVES_PER_UPDATE do
        local data = runtime.socket:receive()
        if not data then break end
        if data == expectedHello then
            if not runtime.peerHelloReceived then
                runtime.peerHelloReceived = true
                marker("TPS_IPV6_SIM_PEER_HELLO")
            end
            sendAck(now, true)
        elseif data == expectedAck then
            if not runtime.peerAckReceived then
                runtime.peerAckReceived = true
                marker("TPS_IPV6_SIM_PEER_ACK")
            end
        end
        -- Packets not authenticated by role, run id, and token are ignored.
    end
    markSuccess(now)
end

local function loadProbe()
    local configOk, config = pcall(require, "probe_config")
    if type(config) == "table" then
        if validHex(config.runId, 32) then runtime.markerRunId = config.runId end
        if config.role == ROLE_HOST or config.role == ROLE_CLIENT then
            runtime.markerRole = config.role
        end
    end
    if not configOk or not validConfig(config) then return fail("config") end
    runtime.config = config

    local socketOk, socket = pcall(require, "socket")
    if not socketOk or type(socket) ~= "table" or type(socket.udp6) ~= "function" then
        return fail("udp6_unavailable")
    end
    local udp = socket.udp6()
    if not udp then return fail("udp6_create") end
    runtime.socket = udp

    if udp:settimeout(0) ~= 1 then return fail("nonblocking") end
    if udp:setsockname("::", config.port) ~= 1 then return fail("bind") end
    if udp:setpeername(config.peerAddress, config.port) ~= 1 then
        return fail("connect")
    end

    runtime.startedAt = love.timer.getTime()
    runtime.nextHelloAt = 0
    runtime.nextAckAt = 0
    marker("TPS_IPV6_SIM_READY")
end

function love.load()
    local ok = pcall(loadProbe)
    if not ok and not runtime.finished then fail("load") end
end

function love.update()
    if runtime.finished or not runtime.socket then return end
    local now = love.timer.getTime()
    local ok = pcall(function()
        sendHello(now)
        sendAck(now, false)
        receivePackets(now)
    end)
    if not ok then return fail("network") end

    if runtime.successAt then
        if now - runtime.successAt >= SUCCESS_GRACE_SECONDS then
            runtime.finished = true
            closeSocket()
            requestQuit(0)
        end
    elseif now - runtime.startedAt >= runtime.config.timeoutSeconds then
        fail("timeout")
    end
end

function love.quit()
    closeSocket()
end
