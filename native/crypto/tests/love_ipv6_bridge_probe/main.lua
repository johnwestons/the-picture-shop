local ROLE_HOST = "host"
local ROLE_CLIENT = "client"
local CHANNEL_CONTROL = 0
local CHANNEL_REALTIME = 1
local CHANNEL_DURABLE = 2
local PROTOCOL_TIMEOUT_SECONDS = 30
local CLIENT_DURABLE_BYTES = 1200
local HOST_DURABLE_BYTES = 8192

local runtime = {
    config = nil,
    stage = "load",
    opening = nil,
    transport = nil,
    peer = nil,
    startedAt = 0,
    protocolDeadline = nil,
    successAt = nil,
    finished = false,
    quitRequested = false,
    failureLogged = false,
    hostControlReceived = false,
    hostRealtimeReceived = {},
    hostClientDurableReceived = false,
    hostReplySent = false,
    clientReplyReceived = false,
    clientCompletionSent = false,
}

local function marker(name, suffix)
    local config = runtime.config or { runId = "invalid", role = "unknown" }
    local line = name .. " run=" .. tostring(config.runId or "invalid")
        .. " role=" .. tostring(config.role or "unknown")
    if suffix then line = line .. " " .. suffix end
    pcall(print, line)
end

local function requestQuit(code)
    if runtime.quitRequested then return end
    runtime.quitRequested = true
    if love and love.event and type(love.event.quit) == "function" then
        pcall(love.event.quit, code)
    end
end

local function closeOpening()
    local opening = runtime.opening
    runtime.opening = nil
    if not opening then return true end
    local ok, result = pcall(opening.close, opening)
    return ok and result == true
end

local function closeTransport()
    local transport = runtime.transport
    runtime.transport = nil
    if not transport then return true end
    local ok, result = pcall(transport.close, transport, 0, false)
    return ok and result == true
end

local function fail(stage)
    if not runtime.failureLogged then
        runtime.failureLogged = true
        marker("TPS_IPV6_BRIDGE_FAIL", "stage=" .. tostring(stage or "unknown"))
    end
    runtime.finished = true
    closeOpening()
    closeTransport()
    requestQuit(1)
end

local function validInteger(value, minimum, maximum)
    return type(value) == "number" and value == value
        and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function validConfig(config)
    return type(config) == "table"
        and (config.role == ROLE_HOST or config.role == ROLE_CLIENT)
        and type(config.runId) == "string" and #config.runId == 32
        and config.runId:match("^[0-9a-f]+$") ~= nil
        and type(config.peerAddress) == "string"
        and #config.peerAddress >= 2 and #config.peerAddress <= 64
        and config.peerAddress:match("^[0-9A-Fa-f:]+$") ~= nil
        and validInteger(config.outerPort, 20000, 60999)
        and validInteger(config.loopbackPort, 20000, 60999)
        and validInteger(config.issuedAt, 0, 0xffffffff)
        and validInteger(config.lifetime, 30, 120)
        and validInteger(config.overallTimeoutSeconds, 45, 180)
        and type(config.localAddress) == "string"
        and #config.localAddress >= 2 and #config.localAddress <= 64
        and config.localAddress:match("^[0-9A-Fa-f:]+$") ~= nil
        and type(config.masterKey) == "string" and #config.masterKey == 32
        and type(config.invitationId) == "string" and #config.invitationId == 16
        and type(config.guestNonce) == "string" and #config.guestNonce == 16
end

local function payload(label)
    return "TPS-IPV6-BRIDGE/" .. runtime.config.runId .. "/" .. label
end

local function largePayload(label, byteCount)
    local prefix = payload(label) .. "/"
    local repetitions = math.ceil(byteCount / #prefix)
    return string.rep(prefix, repetitions):sub(1, byteCount)
end

local function send(peer, data, channel, reliable)
    local ok = runtime.transport:send(peer, data, channel, reliable)
    if ok ~= true then fail("send_channel_" .. tostring(channel)) end
    return ok == true
end

local function sendToServer(data, channel, reliable)
    local ok = runtime.transport:sendToServer(data, channel, reliable)
    if ok ~= true then fail("send_channel_" .. tostring(channel)) end
    return ok == true
end

local function flush()
    local ok = runtime.transport:flush()
    if ok ~= true then fail("flush") end
    return ok == true
end

local function secureConnected(event)
    if runtime.peer then return fail("duplicate_secure_connect") end
    runtime.peer = event.peer
    runtime.protocolDeadline = love.timer.getTime() + PROTOCOL_TIMEOUT_SECONDS
    runtime.stage = runtime.config.role == ROLE_HOST
        and "host_wait_payloads" or "client_send_payloads"
    marker("TPS_IPV6_BRIDGE_SECURE_CONNECTED")

    if runtime.config.role == ROLE_CLIENT then
        if not sendToServer(payload("control"), CHANNEL_CONTROL, true) then return end
        if not sendToServer(payload("realtime-1"), CHANNEL_REALTIME, false) then return end
        if not sendToServer(payload("realtime-2"), CHANNEL_REALTIME, false) then return end
        if not sendToServer(largePayload("client-durable", CLIENT_DURABLE_BYTES),
                CHANNEL_DURABLE, true) then return end
        if not flush() then return end
        runtime.stage = "client_wait_host_durable"
    end
end

local function hostReceive(event)
    if event.peer ~= runtime.peer then return fail("host_unexpected_peer") end
    if event.channel == CHANNEL_CONTROL and event.data == payload("control") then
        runtime.hostControlReceived = true
    elseif event.channel == CHANNEL_REALTIME
        and (event.data == payload("realtime-1")
            or event.data == payload("realtime-2")) then
        local index = event.data == payload("realtime-1") and 1 or 2
        runtime.hostRealtimeReceived[index] = true
    elseif event.channel == CHANNEL_DURABLE
        and event.data == largePayload("client-durable", CLIENT_DURABLE_BYTES) then
        runtime.hostClientDurableReceived = true
    elseif event.channel == CHANNEL_CONTROL and event.data == payload("completion")
        and runtime.hostReplySent then
        if not send(runtime.peer, payload("ack"), CHANNEL_CONTROL, true) then return end
        if not flush() then return end
        runtime.successAt = love.timer.getTime() + 1.0
        runtime.stage = "host_acknowledged"
        return
    else
        return fail("host_unexpected_payload")
    end

    if runtime.hostControlReceived and runtime.hostRealtimeReceived[1]
        and runtime.hostRealtimeReceived[2]
        and runtime.hostClientDurableReceived and not runtime.hostReplySent then
        if not send(runtime.peer, largePayload("host-durable", HOST_DURABLE_BYTES),
                CHANNEL_DURABLE, true) then return end
        if not flush() then return end
        runtime.hostReplySent = true
        runtime.stage = "host_wait_completion"
    end
end

local function clientReceive(event)
    if event.peer ~= runtime.peer then return fail("client_unexpected_peer") end
    if event.channel == CHANNEL_DURABLE
        and event.data == largePayload("host-durable", HOST_DURABLE_BYTES)
        and not runtime.clientReplyReceived then
        runtime.clientReplyReceived = true
        if not sendToServer(payload("completion"), CHANNEL_CONTROL, true) then return end
        if not flush() then return end
        runtime.clientCompletionSent = true
        runtime.stage = "client_wait_ack"
        return
    end
    if event.channel == CHANNEL_CONTROL and event.data == payload("ack")
        and runtime.clientCompletionSent then
        runtime.successAt = love.timer.getTime() + 1.25
        runtime.stage = "client_acknowledged"
        return
    end
    fail("client_unexpected_payload")
end

local function handleEvent(event)
    if event.type == "connect" then return secureConnected(event) end
    if event.type == "disconnect" then
        if runtime.successAt then return end
        return fail("disconnect")
    end
    if event.type ~= "receive" or not runtime.peer then
        return fail("unexpected_event")
    end
    if runtime.config.role == ROLE_HOST then return hostReceive(event) end
    return clientReceive(event)
end

local function bridgeFragmented()
    local bridge = runtime.transport and runtime.transport.bridge
    return type(bridge) == "table"
        and type(bridge.sentFragments) == "number"
        and type(bridge.sentDatagrams) == "number"
        and type(bridge.receivedFragments) == "number"
        and type(bridge.receivedDatagrams) == "number"
        and bridge.sentFragments > bridge.sentDatagrams
        and bridge.receivedFragments > bridge.receivedDatagrams
end

local function finishSuccess()
    if runtime.finished then return end
    if not runtime.nativeProvider
        or runtime.nativeProvider.productionReady ~= false then
        return fail("production_gate_recheck")
    end
    if not bridgeFragmented() then return fail("fragmentation_not_observed") end
    marker("TPS_IPV6_BRIDGE_FRAGMENTED")
    if not closeTransport() then return fail("teardown") end
    runtime.finished = true
    marker("TPS_IPV6_BRIDGE_OK", "channels=0,1,2 fragmented=true")
    requestQuit(0)
end

local function startTransport()
    local config = runtime.config
    local socketModule = runtime.socketModule
    local NativeProvider = runtime.nativeProvider
    local DirectTransport = require("src.net.transport_direct")
    local EnetTransport = require("src.net.transport_enet")
    local BridgeTransport = require("src.net.transport_ipv6_bridge")

    local closedDirect = DirectTransport.newFactory({
        baseFactory = EnetTransport,
        cryptoProvider = NativeProvider,
        key = config.masterKey,
    })
    assert(closedDirect == nil, "direct_production_gate_open")
    local closedBridge = BridgeTransport.newFactory({
        role = config.role == ROLE_HOST and "host" or "guest",
        baseFactory = EnetTransport,
        socketModule = socketModule,
        opening = runtime.opening,
        provider = NativeProvider,
        masterKey = config.masterKey,
        invitationId = config.invitationId,
        guestNonce = config.guestNonce,
        peerAddress = config.peerAddress,
        peerPort = config.outerPort,
        loopbackHostPort = config.loopbackPort,
    })
    assert(closedBridge == nil, "bridge_production_gate_open")

    local EngineeringProxy = {}
    for key, value in pairs(NativeProvider) do EngineeringProxy[key] = value end
    EngineeringProxy.productionReady = true

    local secureFactory, factoryError = DirectTransport.newFactory({
        baseFactory = EnetTransport,
        cryptoProvider = EngineeringProxy,
        key = config.masterKey,
        handshakeTimeout = 20,
    })
    assert(secureFactory, factoryError or "secure_factory_failed")
    local bridgeFactory
    bridgeFactory, factoryError = BridgeTransport.newFactory({
        role = config.role == ROLE_HOST and "host" or "guest",
        baseFactory = secureFactory,
        socketModule = socketModule,
        opening = runtime.opening,
        provider = EngineeringProxy,
        masterKey = config.masterKey,
        invitationId = config.invitationId,
        guestNonce = config.guestNonce,
        peerAddress = config.peerAddress,
        peerPort = config.outerPort,
        loopbackHostPort = config.loopbackPort,
    })
    assert(bridgeFactory, factoryError or "bridge_factory_failed")

    if config.role == ROLE_HOST then
        runtime.transport, factoryError = bridgeFactory.createHost({
            channels = 3,
            maxGuests = 1,
        })
    else
        runtime.transport, factoryError = bridgeFactory.createClient(nil, {
            channels = 3,
        })
    end
    assert(runtime.transport, factoryError or "bridge_transport_failed")
    runtime.opening = nil
    config.masterKey = nil
    config.invitationId = nil
    config.guestNonce = nil
    runtime.stage = config.role == ROLE_HOST
        and "host_wait_secure_connect" or "client_wait_secure_connect"
end

local function run()
    local config = require("probe_config")
    runtime.config = config
    assert(validConfig(config), "invalid_config")

    local socketModule = require("socket")
    local NativeProvider = require("src.net.crypto_native")
    local DirectOpeningCode = require("src.net.direct_opening_code")
    local DirectOpening = require("src.net.direct_opening")
    assert(type(socketModule) == "table" and type(socketModule.udp6) == "function",
        "udp6_unavailable")
    assert(NativeProvider.available == true, "native_provider_unavailable")
    assert(NativeProvider.engineeringReady == true, "provider_not_ready")
    assert(NativeProvider.engineeringOnly == true, "provider_not_engineering")
    assert(NativeProvider.productionReady == false, "production_gate_open")
    runtime.socketModule = socketModule
    runtime.nativeProvider = NativeProvider

    local host = {
        kind = "host",
        version = 2,
        issuedAt = config.issuedAt,
        lifetime = config.lifetime,
        address = config.role == ROLE_HOST and config.localAddress
            or config.peerAddress,
        port = config.outerPort,
        invitationId = config.invitationId,
        masterKey = config.masterKey,
    }
    local response = {
        kind = "response",
        version = 2,
        issuedAt = config.issuedAt,
        lifetime = config.lifetime,
        address = config.role == ROLE_CLIENT and config.localAddress
            or config.peerAddress,
        port = config.outerPort,
        invitationId = config.invitationId,
        guestNonce = config.guestNonce,
    }
    local transcript = assert(DirectOpeningCode.responseTranscript(host, response))
    response.responseTag = assert(NativeProvider.responseTag(
        config.masterKey, transcript))

    local udp = assert(socketModule.udp6())
    assert(udp:settimeout(0) == 1, "nonblocking_failed")
    assert(udp:setsockname("::", config.outerPort) == 1, "bind_failed")
    runtime.opening = assert(DirectOpening.create({
        role = config.role == ROLE_HOST and "host" or "guest",
        socket = udp,
        ownsSocket = true,
        provider = NativeProvider,
        host = host,
        response = response,
        timeoutSeconds = config.lifetime,
    }))
    runtime.stage = "authenticated_opening"
    marker("TPS_IPV6_BRIDGE_READY")
end

function love.load()
    runtime.startedAt = love.timer.getTime()
    local ok = pcall(run)
    if not ok then fail(runtime.stage) end
end

function love.update()
    if runtime.finished then return end
    local now = love.timer.getTime()
    if not runtime.config
        or now - runtime.startedAt > runtime.config.overallTimeoutSeconds then
        return fail("overall_timeout")
    end
    if runtime.successAt and now >= runtime.successAt then return finishSuccess() end
    if runtime.protocolDeadline and now > runtime.protocolDeadline then
        return fail("protocol_timeout")
    end

    if runtime.opening then
        local status, errorMessage = runtime.opening:update()
        if errorMessage or status == "failed" then return fail("authenticated_opening") end
        if status == "ready" then
            marker("TPS_IPV6_BRIDGE_OPEN_READY")
            local ok = pcall(startTransport)
            if not ok then return fail("bridge_start") end
        end
        return
    end

    local events, errorMessage = runtime.transport:service(64)
    if errorMessage then return fail("bridge_service") end
    for _, event in ipairs(events or {}) do
        if runtime.finished then break end
        handleEvent(event)
    end
end

local function lifecycleLoss(stage)
    if not runtime.finished then fail(stage) end
end

function love.focus(focused)
    if focused == false then lifecycleLoss("focus_lost") end
end

function love.visible(visible)
    if visible == false then lifecycleLoss("visibility_lost") end
end

function love.lowmemory()
    lifecycleLoss("android_low_memory")
end

function love.threaderror()
    fail("thread_error")
end

function love.errorhandler()
    fail("unhandled_runtime_error")
    return function() return 1 end
end

function love.quit()
    runtime.finished = true
    closeOpening()
    closeTransport()
end
