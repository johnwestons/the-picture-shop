local ROLE_HOST = "host"
local ROLE_CLIENT = "client"
local MIN_PROBE_PORT = 20000
local MAX_PROBE_PORT = 60999
local CHANNEL_CONTROL = 0
local CHANNEL_REALTIME = 1
local CHANNEL_DURABLE = 2
local DEFAULT_OVERALL_TIMEOUT_SECONDS = 45
local PROTOCOL_TIMEOUT_SECONDS = 25

local runtime = {
    stage = "load",
    transport = nil,
    peer = nil,
    startedAt = 0,
    protocolDeadline = nil,
    successAt = nil,
    finished = false,
    hostControlReceived = false,
    hostRealtimeReceived = {},
    hostDurableSent = false,
    clientCompletionSent = false,
    quitRequested = false,
    failureLogged = false,
    redactNetworkDetails = false,
    markerQuitAt = nil,
}

local function sanitize(value)
    value = tostring(value or "unknown")
    value = value:gsub("[%z\1-\31\127]+", "_")
    value = value:gsub("%s+", "_")
    value = value:gsub("[^%w%._:%-]", "_")
    if #value > 160 then value = value:sub(1, 160) end
    if value == "" then return "unknown" end
    return value
end

local function escapePattern(value)
    return (value:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function redactForLog(value)
    value = tostring(value or "unknown")
    if not runtime.redactNetworkDetails then return value end

    local config = runtime.config
    local configuredAddress = config and config.hostAddress
    if type(configuredAddress) == "string" and configuredAddress ~= ""
        and configuredAddress ~= "redacted"
    then
        value = value:gsub(escapePattern(configuredAddress),
            "public_address_redacted")
    end

    -- Defense in depth for lower networking layers: their error strings are
    -- outside this probe's control and may include a local or remote endpoint.
    value = value:gsub("%d+%.%d+%.%d+%.%d+", "ipv4_address_redacted")
    return value
end

local function safeLogValue(value)
    return sanitize(redactForLog(value))
end

local function errorDetail(code, detail)
    if runtime.redactNetworkDetails then return code end
    return detail or code
end

local function closeTransport()
    if not runtime.transport then return true end
    local transport = runtime.transport
    runtime.transport = nil
    local called, result, errorMessage = pcall(transport.close, transport, 0, false)
    if not called then return false, result end
    if result ~= true then return false, errorMessage or "transport_close_failed" end
    return true
end

local function requestQuit(exitCode)
    if runtime.quitRequested then return true end
    local quit = love and love.event and love.event.quit
    if type(quit) ~= "function" then return false end
    runtime.quitRequested = true
    local ok = pcall(quit, exitCode)
    if not ok then runtime.quitRequested = false end
    return ok
end

local function logFailure(stage, message)
    if runtime.failureLogged then return end
    runtime.failureLogged = true
    local config = runtime.config or { runId = "unknown", role = "unknown" }
    local line = "TPS_DIRECT_PROBE_FAIL run=" .. safeLogValue(config.runId)
        .. " role=" .. safeLogValue(config.role)
        .. " stage=" .. safeLogValue(stage)
        .. " error=" .. safeLogValue(message)
    pcall(print, line)
end

local function fail(stage, message)
    if not runtime.finished then
        runtime.finished = true
        logFailure(stage, message)
    end
    closeTransport()
    requestQuit(1)
end

local function send(peer, payload, channel, reliable)
    local ok, errorMessage = runtime.transport:send(peer, payload, channel, reliable)
    if not ok then
        fail("send_channel_" .. tostring(channel),
            errorDetail("transport_send_failed", errorMessage))
        return false
    end
    return true
end

local function sendToServer(payload, channel, reliable)
    local ok, errorMessage = runtime.transport:sendToServer(payload, channel, reliable)
    if not ok then
        fail("send_channel_" .. tostring(channel),
            errorDetail("transport_send_to_server_failed", errorMessage))
        return false
    end
    return true
end

local function flush()
    local ok, errorMessage = runtime.transport:flush()
    if not ok then
        fail("flush", errorDetail("transport_flush_failed", errorMessage))
        return false
    end
    return true
end

local function payload(label)
    return "TPS-DIRECT-PROBE/" .. runtime.config.runId .. "/" .. label
end

local function secureConnected(event)
    if runtime.peer and runtime.peer ~= event.peer then
        return fail("secure_connect", "unexpected_second_peer")
    end
    runtime.peer = event.peer
    runtime.protocolDeadline = love.timer.getTime() + PROTOCOL_TIMEOUT_SECONDS
    print("TPS_DIRECT_PROBE_SECURE_CONNECTED run=" .. runtime.config.runId
        .. " role=" .. runtime.config.role)

    if runtime.config.role == ROLE_CLIENT then
        runtime.stage = "client_send_sentinels"
        if not sendToServer(payload("control"), CHANNEL_CONTROL, true) then return end
        if not sendToServer(payload("realtime-1"), CHANNEL_REALTIME, true) then return end
        if not sendToServer(payload("realtime-2"), CHANNEL_REALTIME, true) then return end
        if not flush() then return end
        runtime.stage = "client_wait_durable"
    else
        runtime.stage = "host_wait_sentinels"
    end
end

local function hostReceive(event)
    if event.peer ~= runtime.peer then
        return fail("host_receive", "payload_from_unexpected_peer")
    end
    if event.channel == CHANNEL_CONTROL and event.data == payload("control")
        and not runtime.hostControlReceived and not runtime.hostDurableSent
    then
        runtime.hostControlReceived = true
    elseif event.channel == CHANNEL_REALTIME
        and (event.data == payload("realtime-1")
            or event.data == payload("realtime-2"))
        and not runtime.hostDurableSent
    then
        local realtimeIndex = event.data == payload("realtime-1") and 1 or 2
        if runtime.hostRealtimeReceived[realtimeIndex] then
            return fail("host_receive", "duplicate_realtime_sentinel")
        end
        runtime.hostRealtimeReceived[realtimeIndex] = true
    elseif event.channel == CHANNEL_CONTROL and event.data == payload("completion")
        and runtime.hostDurableSent
    then
        runtime.stage = "host_acknowledge_completion"
        if not send(runtime.peer, payload("ack"), CHANNEL_CONTROL, true) then return end
        if not flush() then return end
        -- Keep servicing briefly after ENet accepted and flushed the reliable
        -- acknowledgement so the client can receive it before this probe exits.
        runtime.successAt = love.timer.getTime() + 1.0
        runtime.stage = "host_acknowledged"
        return
    else
        return fail("host_receive", "unexpected_payload_or_channel")
    end

    if runtime.hostControlReceived and runtime.hostRealtimeReceived[1]
        and runtime.hostRealtimeReceived[2]
        and not runtime.hostDurableSent
    then
        runtime.stage = "host_send_durable"
        if not send(runtime.peer, payload("durable"), CHANNEL_DURABLE, true) then return end
        if not flush() then return end
        runtime.hostDurableSent = true
        runtime.stage = "host_wait_completion"
    end
end

local function clientReceive(event)
    if event.peer ~= runtime.peer then
        return fail("client_receive", "payload_from_unexpected_peer")
    end
    if event.channel == CHANNEL_DURABLE and event.data == payload("durable")
        and not runtime.clientCompletionSent
    then
        runtime.stage = "client_send_completion"
        if not sendToServer(payload("completion"), CHANNEL_CONTROL, true) then return end
        if not flush() then return end
        runtime.clientCompletionSent = true
        runtime.stage = "client_wait_ack"
        return
    end
    if event.channel == CHANNEL_CONTROL and event.data == payload("ack")
        and runtime.clientCompletionSent
    then
        runtime.successAt = love.timer.getTime() + 1.25
        runtime.stage = "client_acknowledged"
        return
    end
    fail("client_receive", "unexpected_payload_or_channel")
end

local function handleEvent(event)
    if event.type == "connect" then
        if runtime.peer then return fail("secure_connect", "duplicate_connect") end
        return secureConnected(event)
    end
    if event.type == "disconnect" then
        -- Once the reliable acknowledgement has completed the protocol, the
        -- other role may finish its own grace period first.
        if runtime.successAt then return end
        return fail("disconnect", errorDetail("peer_disconnected",
            event.error or event.code or "peer_disconnected"))
    end
    if event.type ~= "receive" then
        return fail("event", "unexpected_event_type")
    end
    if not runtime.peer then return fail("receive", "data_before_secure_connect") end
    if runtime.config.role == ROLE_HOST then return hostReceive(event) end
    return clientReceive(event)
end

local function finishSuccess()
    if runtime.finished then return end
    if not runtime.nativeProvider
        or runtime.nativeProvider.productionReady ~= false
    then
        return fail("production_gate_recheck", "production_gate_changed")
    end
    local closed, closeError = closeTransport()
    if not closed then
        return fail("teardown", errorDetail("transport_close_failed", closeError))
    end
    runtime.finished = true
    print("TPS_DIRECT_PROBE_OK run=" .. runtime.config.runId
        .. " role=" .. runtime.config.role .. " channels=0,1,2")
    -- The Internet orchestrator reads only this process's log buffer and then
    -- force-stops/uninstalls both probes.  Keep the marker process alive until
    -- collection cannot race process exit, but still self-terminate after a
    -- short bounded grace period if the PC-side completion step disappears.
    if runtime.config.internetProbe then
        runtime.markerQuitAt = love.timer.getTime() + 20
        return
    end
    requestQuit(0)
end

local function run()
    runtime.config = require("probe_config")
    local config = runtime.config
    runtime.redactNetworkDetails = type(config) == "table"
        and config.internetProbe == true
    assert(type(config) == "table", "probe_config_not_table")
    assert(config.role == ROLE_HOST or config.role == ROLE_CLIENT, "invalid_role")
    assert(type(config.hostAddress) == "string" and config.hostAddress ~= "",
        "invalid_host_address")
    assert(type(config.internetProbe) == "boolean", "invalid_probe_mode")
    assert(type(config.overallTimeoutSeconds) == "number"
        and config.overallTimeoutSeconds == math.floor(config.overallTimeoutSeconds)
        and config.overallTimeoutSeconds >= DEFAULT_OVERALL_TIMEOUT_SECONDS
        and config.overallTimeoutSeconds <= 900, "invalid_overall_timeout")
    assert(type(config.port) == "number"
        and config.port == math.floor(config.port)
        and config.port >= MIN_PROBE_PORT and config.port <= MAX_PROBE_PORT,
        "invalid_probe_port")
    assert(type(config.runId) == "string" and config.runId:match("^[0-9a-f]+$")
        and #config.runId >= 16 and #config.runId <= 64, "invalid_run_id")
    assert(type(config.key) == "string" and #config.key == 32, "invalid_probe_key")

    if config.role == ROLE_CLIENT and config.internetProbe then
        local IpScope = require("src.net.ip_scope")
        local isGlobal = IpScope.isGlobal(config.hostAddress)
        assert(isGlobal == true, "internet_probe_address_not_global")
    end

    local NativeProvider = require("src.net.crypto_native")
    local DirectTransport = require("src.net.transport_direct")
    local EnetTransport = require("src.net.transport_enet")

    assert(NativeProvider.available == true,
        NativeProvider.loadError or "native_provider_unavailable")
    assert(NativeProvider.engineeringReady == true, "provider_not_engineering_ready")
    assert(NativeProvider.engineeringOnly == true, "provider_not_engineering_only")
    assert(NativeProvider.productionReady == false, "production_gate_unexpectedly_open")
    runtime.nativeProvider = NativeProvider

    print("TPS_DIRECT_PROBE_INFO run=" .. config.runId .. " role=" .. config.role
        .. " productionReady=false")

    local closedFactory, closedError = DirectTransport.newFactory({
        baseFactory = EnetTransport,
        cryptoProvider = NativeProvider,
        key = config.key,
    })
    assert(closedFactory == nil and closedError
        == "Direct Internet Play requires a production cryptographic provider.",
        "unmodified_provider_did_not_fail_closed")
    assert(NativeProvider.productionReady == false, "production_gate_mutated")
    print("TPS_DIRECT_PROBE_GATE_CLOSED_OK run=" .. config.runId
        .. " role=" .. config.role)

    -- This shallow proxy opens the API guard only inside this diagnostic
    -- process. The audited module and the shipping game remain unchanged.
    local EngineeringProxy = {}
    for key, value in pairs(NativeProvider) do EngineeringProxy[key] = value end
    EngineeringProxy.productionReady = true

    local factory, factoryError = DirectTransport.newFactory({
        baseFactory = EnetTransport,
        cryptoProvider = EngineeringProxy,
        key = config.key,
        handshakeTimeout = 20,
    })
    assert(factory, factoryError or "factory_creation_failed")
    assert(NativeProvider.productionReady == false, "production_gate_mutated_by_proxy")

    if config.role == ROLE_HOST then
        runtime.stage = "host_create"
        runtime.transport, factoryError = factory.createHost({
            bind = "*",
            port = config.port,
            channels = 3,
            maxGuests = 1,
        })
        assert(runtime.transport, factoryError or "host_creation_failed")
        -- The host does not need the advertised address in order to bind.
        -- Keep it out of adb logs because an Internet probe may carry the
        -- player's public address in this otherwise shared configuration.
        print("TPS_DIRECT_PROBE_HOST_READY run=" .. config.runId
            .. " port=" .. tostring(config.port) .. " address=redacted")
        runtime.stage = "host_wait_secure_connect"
    else
        runtime.stage = "client_create"
        runtime.transport, factoryError = factory.createClient(config.hostAddress, {
            port = config.port,
            channels = 3,
        })
        -- Lower ENet errors may include the remote endpoint. Do not place a
        -- player's public address in adb logs.
        assert(runtime.transport, "client_creation_failed_redacted")
        runtime.stage = "client_wait_secure_connect"
    end
end

function love.load()
    runtime.startedAt = love.timer.getTime()
    local ok, message = pcall(run)
    if not ok then
        fail(runtime.stage, errorDetail("runtime_initialization_failed", message))
    end
end

function love.update()
    if runtime.markerQuitAt then
        if love.timer.getTime() >= runtime.markerQuitAt then requestQuit(0) end
        return
    end
    if runtime.finished then return end
    local now = love.timer.getTime()
    if runtime.successAt and now >= runtime.successAt then return finishSuccess() end
    if now - runtime.startedAt > runtime.config.overallTimeoutSeconds then
        return fail(runtime.stage, "overall_timeout")
    end
    if runtime.protocolDeadline and now > runtime.protocolDeadline then
        return fail(runtime.stage, "protocol_timeout")
    end

    local events, errorMessage = runtime.transport:service(64)
    if errorMessage then
        return fail(runtime.stage,
            errorDetail("transport_service_failed", errorMessage))
    end
    for _, event in ipairs(events or {}) do
        if runtime.finished then break end
        handleEvent(event)
    end
end

local function failOnLifecycleLoss(stage)
    if runtime.redactNetworkDetails and not runtime.finished then
        fail(stage, "internet_probe_left_foreground")
    end
end

-- On Android, Activity focus is lost before SDL pauses its event pump. Closing
-- here prevents the UDP listener from surviving a suspended diagnostic app.
function love.focus(focused)
    if focused == false then failOnLifecycleLoss("focus_lost") end
end

function love.visible(visible)
    if visible == false then failOnLifecycleLoss("visibility_lost") end
end

function love.lowmemory()
    failOnLifecycleLoss("android_low_memory")
end

function love.threaderror(_, errorMessage)
    fail("thread_error", errorDetail("thread_runtime_error", errorMessage))
end

function love.errorhandler(errorMessage)
    runtime.finished = true
    closeTransport()
    logFailure("unhandled_runtime_error",
        errorDetail("unhandled_runtime_error", errorMessage))
    return function() return 1 end
end

function love.quit()
    runtime.finished = true
    closeTransport()
end
