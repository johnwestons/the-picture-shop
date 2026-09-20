local Protocol = require("src.net.public_ipv4_probe_protocol")
local Watchdog = require("src.net.public_ipv4_probe_watchdog")

local PORT = 59281
local LEASE_SECONDS = 120
local CHANNELS = 3
-- PCP may need to wait for its last possible finite lease to expire before
-- NAT-PMP, and NAT-PMP completes its own RFC retry schedule before UPnP. This
-- bound gives all three serialized methods time without overlapping mappings.
local MAPPING_TIMEOUT_SECONDS = 360
local GUEST_WAIT_SECONDS = 10 * 60
local CLEANUP_TIMEOUT_SECONDS = LEASE_SECONDS + 45
local INVITATION_MAX_BYTES = 180
local phaseWatchdog = assert(Watchdog.new(LEASE_SECONDS))

local role = os.getenv("TPS_PUBLIC_IPV4_PROBE_ROLE")
local trafficOnly = role == "traffic"
local armed = os.getenv("TPS_PUBLIC_IPV4_PROBE_ARMED") ==
    "ALLOW_TEMPORARY_ROUTER_MAPPING"
local resultPath = os.getenv("TPS_PUBLIC_IPV4_PROBE_RESULT")

local screen = {
    title = "Starting acceptance test",
    lines = {},
    tone = "normal",
}
local finalWritten = false
local finalSuccess = false
local allowQuit = false
local finishAt
local titleFont
local bodyFont
local footFont

local crypto
local provider
local route
local ipv4Host
local transport
local invitation
local invitationCopied = false
local peer
local nonce
local phaseAcks = { {}, {} }
local phaseStarted = { false, false }
local initialProof = false
local renewedProof = false
local renewalBaseline = 0
local mappingStartedAt
local guestDeadline
local cleanupDeadline
local desiredSuccess = false
local failureReason
local state = "starting"

local guestInput = ""
local guestSeen = { {}, {} }
local guestNonce
local guestConnected = false
local guestDeadlineAt
local guestCompleteAt

local SAFE_FAILURES = {
    cancelled = true,
    crypto_unavailable = true,
    route_unavailable = true,
    exact_socket_unavailable = true,
    listener_unavailable = true,
    mapping_unavailable = true,
    mapping_timeout = true,
    mapped_endpoint_changed = true,
    transport_unavailable = true,
    guest_timeout = true,
    transport_failed = true,
    authentication_failed = true,
    challenge_failed = true,
    renewal_failed = true,
    cleanup_timeout = true,
    deletion_not_acknowledged = true,
    invalid_invitation = true,
    guest_connection_failed = true,
    guest_disconnected_early = true,
    invalid_role = true,
    preflight_failed = true,
}

local function setScreen(title, lines, tone)
    screen.title = title
    screen.lines = lines or {}
    screen.tone = tone or "normal"
end

local function writeResult(lines)
    if finalWritten then return end
    finalWritten = true
    if type(resultPath) == "string" and resultPath ~= ""
        and #resultPath <= 1024 and not resultPath:find("[\r\n]") then
        local file = io.open(resultPath, "wb")
        if file then
            file:write(table.concat(lines, "\n"), "\n")
            file:close()
        end
    end
    for _, line in ipairs(lines) do print(line) end
end

local function clearInvitation()
    invitation = nil
    guestInput = ""
    if invitationCopied and love.system and love.system.setClipboardText then
        pcall(love.system.setClipboardText, "")
    end
    invitationCopied = false
end

local function finish(success, reason, markers)
    phaseWatchdog:clear()
    clearInvitation()
    local prefix = role == "guest" and "TPS_PUBLIC_IPV4_GUEST"
        or role == "preflight" and "TPS_PUBLIC_IPV4_PREFLIGHT"
        or role == "traffic" and "TPS_PUBLIC_IPV4_TRAFFIC"
        or "TPS_PUBLIC_IPV4_HOST"
    local lines = { prefix .. "=" .. (success and "PASS" or "FAIL") }
    if not success then
        reason = SAFE_FAILURES[reason] and reason or "preflight_failed"
        lines[#lines + 1] = "REASON=" .. reason
    end
    for _, marker in ipairs(markers or {}) do lines[#lines + 1] = marker end
    lines[#lines + 1] = "NETWORK_DETAILS_RETAINED=False"
    writeResult(lines)
    finalSuccess = success == true
    state = "finished"
    finishAt = love.timer.getTime() + 4
    setScreen(success and "Test complete" or "Test stopped safely", {
        success and "The required checks passed."
            or "The test did not pass. No address or invitation was retained.",
        "This window will close automatically.",
    }, success and "pass" or "fail")
end

local function loadProvider()
    local ok, loaded = pcall(require, "src.net.crypto_native")
    if not ok or type(loaded) ~= "table"
        or loaded.engineeringReady ~= true
        or loaded.candidateReady ~= true
        or type(loaded.randomBytes) ~= "function" then
        return false
    end
    crypto = loaded
    provider = setmetatable({ productionReady = true }, { __index = crypto })
    return true
end

local function allChannels(values)
    for channel = 0, CHANNELS - 1 do
        if values[channel] ~= true then return false end
    end
    return true
end

local function sendHostPhase(phase)
    if not transport or not peer or type(nonce) ~= "string" then return false end
    for channel = 0, CHANNELS - 1 do
        local payload = Protocol.challenge(phase, channel, nonce)
        local sent = payload and transport:send(peer, payload, channel, true)
        if sent ~= true then return false end
    end
    if transport:flush() ~= true then return false end
    phaseStarted[phase] = true
    return true
end

local function safeHostStatus()
    if not ipv4Host or type(ipv4Host.status) ~= "function" then return nil end
    local ok, value = pcall(ipv4Host.status, ipv4Host)
    return ok and type(value) == "table" and value or nil
end

local function booleanMarker(value)
    return value == true and "True" or "False"
end

local function completeHostCleanup()
    local status = safeHostStatus() or {}
    local deletionAcknowledged = status.cleanupReason ==
        "deletion_acknowledged"
    local cleanupMarkers = {
        "FINITE_LEASE_SECONDS=" .. tostring(LEASE_SECONDS),
        "LISTENER_CLOSED_BEFORE_DELETE=" ..
            booleanMarker(status.listenerClosedBeforeCleanup == true),
        "DELETION_ACKNOWLEDGED=" .. booleanMarker(deletionAcknowledged),
    }
    if trafficOnly and desiredSuccess and deletionAcknowledged
        and status.listenerClosedBeforeCleanup == true then
        finish(true, nil, {
            "MAPPING_CREATED=True",
            unpack(cleanupMarkers),
        })
    elseif desiredSuccess and deletionAcknowledged
        and status.listenerClosedBeforeCleanup == true then
        finish(true, nil, {
            "MAPPING_CREATED=True",
            "REMOTE_AUTHENTICATED=True",
            "THREE_CHANNELS_BEFORE_RENEW=True",
            "LEASE_RENEWED=True",
            "THREE_CHANNELS_AFTER_RENEW=True",
            unpack(cleanupMarkers),
        })
    else
        finish(false, desiredSuccess and "deletion_not_acknowledged"
            or failureReason or "preflight_failed", cleanupMarkers)
    end
end

local function beginHostCleanup(success, reason)
    if state == "cleaning" or state == "finished" then return end
    phaseWatchdog:clear()
    desiredSuccess = success == true
    failureReason = reason
    clearInvitation()
    state = "cleaning"
    setScreen("Closing listener and removing mapping", {
        "Keep this window open while the router confirms cleanup.",
        "The listener has been closed before the deletion request.",
    })
    if not ipv4Host then
        finish(false, reason or "preflight_failed", {
            "FINITE_LEASE_SECONDS=" .. tostring(LEASE_SECONDS),
            "LISTENER_CLOSED_BEFORE_DELETE=False",
            "DELETION_ACKNOWLEDGED=False",
        })
        return
    end
    pcall(ipv4Host.stop, ipv4Host)
    cleanupDeadline = love.timer.getTime() + CLEANUP_TIMEOUT_SECONDS
    local status = safeHostStatus()
    if status and status.state == "stopped" then completeHostCleanup() end
end

local function transitionHostWatchdog(nextState, now, fallbackReason)
    if phaseWatchdog:transition(nextState, now) then return true end
    beginHostCleanup(false, phaseWatchdog:timeout(now) or fallbackReason)
    return false
end

local function runPreflight()
    if not loadProvider() then
        finish(false, "crypto_unavailable", { "NETWORK_TRAFFIC_SENT=False" })
        return
    end
    local GatewayDiscovery = require("src.net.gateway_discovery")
    local MappingSocket = require("src.net.mapping_socket_windows")
    local UpnpTransport = require("src.net.upnp_transport_windows")
    local DirectIpv4Host = require("src.net.direct_ipv4_host")
    route = GatewayDiscovery.discover()
    if not route then
        finish(false, "route_unavailable", { "NETWORK_TRAFFIC_SENT=False" })
        return
    end
    local socket = MappingSocket.open(route)
    if not socket then
        finish(false, "exact_socket_unavailable", {
            "NETWORK_TRAFFIC_SENT=False",
        })
        return
    end
    local proof = socket:bindingProof()
    local exact = proof and proof.exactNetworkBinding == true
        and proof.networkGeneration == route.networkGeneration
        and proof.routeFingerprint == route.routeFingerprint
    local socketClosed = socket:close()
    if not exact or not socketClosed then
        finish(false, "exact_socket_unavailable", {
            "NETWORK_TRAFFIC_SENT=False",
        })
        return
    end
    local upnpSocket = UpnpTransport.openDiscovery(route)
    if not upnpSocket then
        finish(false, "exact_socket_unavailable", {
            "NETWORK_TRAFFIC_SENT=False",
        })
        return
    end
    local upnpProof = upnpSocket:bindingProof()
    local upnpExact = upnpProof and upnpProof.exactNetworkBinding == true
        and upnpProof.internalAddress == route.internalAddress
        and upnpProof.gatewayAddress == route.gatewayAddress
        and upnpProof.interfaceIndex == route.interfaceIndex
        and upnpProof.networkGeneration == route.networkGeneration
        and upnpProof.routeFingerprint == route.routeFingerprint
    local upnpClosed = upnpSocket:close()
    if not upnpExact or not upnpClosed then
        finish(false, "exact_socket_unavailable", {
            "NETWORK_TRAFFIC_SENT=False",
        })
        return
    end
    ipv4Host = DirectIpv4Host.new({
        engineeringEnabled = true,
        provider = provider,
        discoverRoute = function() return route end,
        requestedLeaseSeconds = LEASE_SECONDS,
        maxLeaseSeconds = LEASE_SECONDS,
        renewFraction = 0.5,
        maxGuests = 1,
        channels = CHANNELS,
    })
    if not ipv4Host or not ipv4Host:start(PORT, {
            requestedLifetime = LEASE_SECONDS,
            suggestedExternalPort = 0,
        }) then
        finish(false, "listener_unavailable", {
            "NETWORK_TRAFFIC_SENT=False",
        })
        return
    end
    local stopped, cleanupRequired = ipv4Host:stop()
    local status = safeHostStatus() or {}
    if stopped ~= true or cleanupRequired == true
        or status.listenerClosedBeforeCleanup ~= true then
        finish(false, "preflight_failed", {
            "NETWORK_TRAFFIC_SENT=False",
        })
        return
    end
    finish(true, nil, {
        "NATIVE_CRYPTO_READY=True",
        "DEFAULT_ROUTE_READY=True",
        "NETWORK_GENERATION_READY=True",
        "EXACT_SOCKET_READY=True",
        "UPNP_TRANSPORT_READY=True",
        "SECURE_LISTENER_READY=True",
        "PRODUCTION_GATE_RETAINED=True",
        "NETWORK_TRAFFIC_SENT=False",
    })
end

local function startArmedHost()
    if not armed then
        finish(false, "preflight_failed", {
            "FINITE_LEASE_SECONDS=" .. tostring(LEASE_SECONDS),
        })
        return
    end
    if not loadProvider() then
        finish(false, "crypto_unavailable", {
            "FINITE_LEASE_SECONDS=" .. tostring(LEASE_SECONDS),
        })
        return
    end
    local GatewayDiscovery = require("src.net.gateway_discovery")
    local DirectIpv4Host = require("src.net.direct_ipv4_host")
    route = GatewayDiscovery.discover()
    if not route then
        finish(false, "route_unavailable", {
            "FINITE_LEASE_SECONDS=" .. tostring(LEASE_SECONDS),
        })
        return
    end
    ipv4Host = DirectIpv4Host.new({
        engineeringEnabled = true,
        provider = provider,
        discoverRoute = function() return route end,
        revalidateRoute = function(snapshot)
            return GatewayDiscovery.revalidate(snapshot)
        end,
        requestedLeaseSeconds = LEASE_SECONDS,
        maxLeaseSeconds = LEASE_SECONDS,
        renewFraction = 0.5,
        maxGuests = 1,
        channels = CHANNELS,
        handshakeTimeout = 10,
    })
    if not ipv4Host then
        finish(false, "listener_unavailable", {
            "FINITE_LEASE_SECONDS=" .. tostring(LEASE_SECONDS),
        })
        return
    end
    local now = love.timer.getTime()
    local started = ipv4Host:start(PORT, {
        now = now,
        requestedLifetime = LEASE_SECONDS,
        suggestedExternalPort = 0,
    })
    if not started then
        beginHostCleanup(false, "listener_unavailable")
        return
    end
    nonce = provider.randomBytes(Protocol.NONCE_BYTES)
    if type(nonce) ~= "string" or #nonce ~= Protocol.NONCE_BYTES then
        beginHostCleanup(false, "crypto_unavailable")
        return
    end
    mappingStartedAt = now
    state = "mapping"
    setScreen("Requesting a short router mapping", {
        "The secure listener is active on one fixed UDP port.",
        "The mapping lease is limited to two minutes.",
        "Keep this window open.",
    })
end

local function createHostTransport()
    invitation = ipv4Host:invitation()
    local factory = ipv4Host:transportFactory()
    if type(invitation) ~= "string" or type(factory) ~= "table" then
        return false
    end
    transport = factory.createHost({
        bind = route.internalAddress,
        port = PORT,
        maxGuests = 1,
        channels = CHANNELS,
    })
    if not transport then return false end
    guestDeadline = love.timer.getTime() + GUEST_WAIT_SECONDS
    state = "waiting_guest"
    setScreen("Mapping ready - send the invitation", {
        "Press C to copy the invitation shown below.",
        "Send it privately to the guest, then keep this window open.",
        "Invitation:",
    }, "ready")
    return true
end

local function processHostEvent(event, now)
    if event.type == "connect" then
        if peer then
            if peer ~= event.peer then
                beginHostCleanup(false, "authentication_failed")
            end
            return
        end
        peer = event.peer
        if not phaseStarted[1] and not sendHostPhase(1) then
            beginHostCleanup(false, "challenge_failed")
            return
        end
        state = "initial_exchange"
        if not transitionHostWatchdog(
                "host_initial_exchange", now, "challenge_failed") then
            return
        end
        setScreen("Remote guest authenticated", {
            "Checking encrypted traffic on all three game channels.",
        }, "ready")
    elseif event.type == "receive" then
        local parsed = Protocol.parse(event.payload or event.data)
        if not parsed or parsed.kind ~= "ack" or parsed.nonce ~= nonce
            or not peer or event.peer ~= peer
            or parsed.channel ~= event.channel or parsed.phase < 1
            or parsed.phase > 2
            or (parsed.phase == 1 and phaseStarted[1] ~= true)
            or (parsed.phase == 2 and (phaseStarted[2] ~= true
                or state ~= "renewed_exchange")) then
            beginHostCleanup(false, "challenge_failed")
            return
        end
        phaseAcks[parsed.phase][parsed.channel] = true
        if parsed.phase == 1 and not initialProof
            and allChannels(phaseAcks[1]) then
            initialProof = ipv4Host:markVerified(now)
            if not initialProof then
                beginHostCleanup(false, "challenge_failed")
                return
            end
            local status = safeHostStatus() or {}
            renewalBaseline = status.renewalCount or 0
            state = "waiting_renewal"
            if not transitionHostWatchdog(
                    "host_waiting_renewal", now, "renewal_failed") then
                return
            end
            setScreen("Initial outside connection passed", {
                "Encrypted traffic passed on all three channels.",
                "Waiting for the two-minute lease to renew once.",
                "Keep both test windows open.",
            }, "ready")
        elseif parsed.phase == 2 and allChannels(phaseAcks[2])
            and not renewedProof then
            renewedProof = true
            beginHostCleanup(true)
        end
    elseif event.type == "disconnect" and not renewedProof then
        beginHostCleanup(false, "authentication_failed")
    end
end

local function updateArmedHost(now)
    if state == "cleaning" then
        local ok = pcall(ipv4Host.update, ipv4Host, now)
        local status = safeHostStatus()
        if not ok then
            finish(false, "deletion_not_acknowledged", {
                "FINITE_LEASE_SECONDS=" .. tostring(LEASE_SECONDS),
                "DELETION_ACKNOWLEDGED=False",
            })
        elseif status and status.state == "stopped" then
            completeHostCleanup()
        elseif cleanupDeadline and now >= cleanupDeadline then
            finish(false, "cleanup_timeout", {
                "FINITE_LEASE_SECONDS=" .. tostring(LEASE_SECONDS),
                "DELETION_ACKNOWLEDGED=False",
            })
        end
        return
    end
    if state == "finished" then return end

    local ok, hostState = pcall(ipv4Host.update, ipv4Host, now)
    if not ok then beginHostCleanup(false, "mapping_unavailable"); return end
    if hostState == "unavailable" or hostState == "failed"
        or hostState == "cleanup_required" then
        beginHostCleanup(false, "mapping_unavailable")
        return
    end
    if state == "mapping" then
        if hostState == "ready" then
            if trafficOnly then
                beginHostCleanup(true)
            elseif not createHostTransport() then
                beginHostCleanup(false, "transport_unavailable")
            end
        elseif now - mappingStartedAt >= MAPPING_TIMEOUT_SECONDS then
            beginHostCleanup(false, "mapping_timeout")
        end
        return
    end

    if invitation and ipv4Host:invitation() ~= invitation then
        beginHostCleanup(false, "mapped_endpoint_changed")
        return
    end
    if guestDeadline and now >= guestDeadline and not peer then
        beginHostCleanup(false, "guest_timeout")
        return
    end
    local timeoutReason = phaseWatchdog:timeout(now)
    if timeoutReason then
        beginHostCleanup(false, timeoutReason)
        return
    end
    if transport then
        for _ = 1, 64 do
            local event, pollError = transport:poll()
            if pollError then
                beginHostCleanup(false, "transport_failed")
                return
            end
            if not event then break end
            processHostEvent(event, now)
            if state == "cleaning" then return end
        end
    end
    if state == "waiting_renewal" then
        local status = safeHostStatus() or {}
        if status.state ~= "ready" then
            beginHostCleanup(false, "renewal_failed")
        elseif (status.renewalCount or 0) > renewalBaseline then
            if not sendHostPhase(2) then
                beginHostCleanup(false, "challenge_failed")
            else
                state = "renewed_exchange"
                if not transitionHostWatchdog(
                        "host_renewed_exchange", now,
                        "challenge_failed") then
                    return
                end
                setScreen("Lease renewed", {
                    "Repeating the encrypted three-channel check.",
                }, "ready")
            end
        end
    end
    if state == "cleaning" then return end
    timeoutReason = phaseWatchdog:timeout(now)
    if timeoutReason then beginHostCleanup(false, timeoutReason) end
end

local function startGuestConnection()
    local code = guestInput:match("^%s*(.-)%s*$")
    guestInput = ""
    if love.system and love.system.setClipboardText then
        pcall(love.system.setClipboardText, "")
    end
    if code == "" or #code > INVITATION_MAX_BYTES then
        setScreen("Invitation rejected", {
            "Paste the complete invitation and press Enter.",
        }, "fail")
        return
    end
    if not provider and not loadProvider() then
        finish(false, "crypto_unavailable")
        return
    end
    local DirectIpv4Listener = require("src.net.direct_ipv4_listener")
    local factory, endpoint = DirectIpv4Listener.clientFactory(code, {
        provider = provider,
        handshakeTimeout = 10,
    })
    code = nil
    if not factory or type(endpoint) ~= "string" then
        setScreen("Invitation rejected", {
            "The invitation is invalid or the secure transport is unavailable.",
        }, "fail")
        return
    end
    transport = factory.createClient(endpoint, { channels = CHANNELS })
    endpoint = nil
    if not transport then
        finish(false, "guest_connection_failed")
        return
    end
    state = "guest_connecting"
    guestDeadlineAt = love.timer.getTime() + 30
    setScreen("Connecting to the remote host", {
        "The invitation has been cleared from this test window.",
        "Keep this window open.",
    })
end

local function transitionGuestWatchdog(nextState, now)
    if phaseWatchdog:transition(nextState, now) then return true end
    local reason = phaseWatchdog:timeout(now) or "challenge_failed"
    if transport then pcall(transport.close, transport, 0, true) end
    transport = nil
    finish(false, reason)
    return false
end

local function processGuestEvent(event, now)
    if event.type == "connect" then
        if guestConnected then return end
        guestConnected = true
        state = "guest_connected"
        if not transitionGuestWatchdog("guest_connected", now) then return end
        setScreen("Secure connection established", {
            "Waiting for the host's encrypted channel checks.",
        }, "ready")
    elseif event.type == "receive" then
        local parsed = Protocol.parse(event.payload or event.data)
        if not parsed or parsed.kind ~= "challenge" or not guestConnected
            or parsed.channel ~= event.channel
            or (guestNonce and parsed.nonce ~= guestNonce)
            or (parsed.phase == 2 and not allChannels(guestSeen[1])) then
            finish(false, "challenge_failed")
            return
        end
        guestNonce = guestNonce or parsed.nonce
        guestSeen[parsed.phase][parsed.channel] = true
        local ack = Protocol.ack(parsed.phase, parsed.channel, parsed.nonce)
        if not ack or transport:sendToServer(
                ack, parsed.channel, true) ~= true
            or transport:flush() ~= true then
            finish(false, "challenge_failed")
            return
        end
        if parsed.phase == 1 and allChannels(guestSeen[1])
            and state == "guest_connected" then
            state = "guest_waiting_renewal"
            if not transitionGuestWatchdog(
                    "guest_waiting_renewal", now) then return end
        elseif parsed.phase == 2 and state == "guest_waiting_renewal" then
            state = "guest_renewed_exchange"
            if not transitionGuestWatchdog(
                    "guest_renewed_exchange", now) then return end
        end
        if allChannels(guestSeen[2]) and state ~= "guest_waiting_close" then
            state = "guest_waiting_close"
            phaseWatchdog:clear()
            guestCompleteAt = now + 2
            setScreen("Remote exchange passed", {
                "Both encrypted three-channel checks completed.",
                "Giving the final reliable acknowledgements time to arrive.",
            }, "pass")
        end
    elseif event.type == "disconnect" then
        if allChannels(guestSeen[1]) and allChannels(guestSeen[2]) then
            if transport then pcall(transport.close, transport, 0, true) end
            transport = nil
            finish(true, nil, {
                "REMOTE_AUTHENTICATED=True",
                "THREE_CHANNELS_BEFORE_RENEW=True",
                "THREE_CHANNELS_AFTER_RENEW=True",
            })
        else
            finish(false, "guest_disconnected_early")
        end
    end
end

local function updateGuest(now)
    if state == "finished" or state == "guest_input" then return end
    if guestDeadlineAt and now >= guestDeadlineAt and not guestConnected then
        if transport then pcall(transport.close, transport, 0, true) end
        transport = nil
        finish(false, "guest_connection_failed")
        return
    end
    if not transport then return end
    local timeoutReason = phaseWatchdog:timeout(now)
    if timeoutReason then
        if transport then pcall(transport.close, transport, 0, true) end
        transport = nil
        finish(false, timeoutReason)
        return
    end
    for _ = 1, 64 do
        local event, pollError = transport:poll()
        if pollError then finish(false, "transport_failed"); return end
        if not event then break end
        processGuestEvent(event, now)
        if state == "finished" then return end
    end
    if state == "guest_waiting_close" and guestCompleteAt
        and now >= guestCompleteAt then
        if transport then pcall(transport.close, transport, 0, false) end
        transport = nil
        finish(true, nil, {
            "REMOTE_AUTHENTICATED=True",
            "THREE_CHANNELS_BEFORE_RENEW=True",
            "THREE_CHANNELS_AFTER_RENEW=True",
        })
        return
    end
    timeoutReason = phaseWatchdog:timeout(now)
    if timeoutReason then
        if transport then pcall(transport.close, transport, 0, true) end
        transport = nil
        finish(false, timeoutReason)
    end
end

function love.load()
    love.keyboard.setKeyRepeat(true)
    titleFont = love.graphics.newFont(24)
    bodyFont = love.graphics.newFont(17)
    footFont = love.graphics.newFont(14)
    if role == "preflight" then
        state = "preflight"
        setScreen("Running local preflight", {
            "No router packet will be sent and no mapping will be created.",
        })
        runPreflight()
    elseif role == "host" or role == "traffic" then
        startArmedHost()
    elseif role == "guest" then
        state = "guest_input"
        setScreen("Join the public IPv4 acceptance test", {
            "Paste the private invitation below and press Enter.",
            "The invitation will be cleared after it is parsed.",
        })
    else
        finish(false, "invalid_role")
    end
end

function love.update()
    local now = love.timer.getTime()
    if state == "finished" then
        if finishAt and now >= finishAt then
            allowQuit = true
            love.event.quit(finalSuccess and 0 or 1)
        end
    elseif role == "host" or role == "traffic" then
        updateArmedHost(now)
    elseif role == "guest" then
        updateGuest(now)
    end
end

local function drawWrapped(text, x, y, width, color)
    love.graphics.setColor(color or { 0.86, 0.89, 0.94 })
    love.graphics.printf(text, x, y, width, "left")
    local _, wrapped = love.graphics.getFont():getWrap(text, width)
    return y + math.max(1, #wrapped) * love.graphics.getFont():getHeight() + 10
end

function love.draw()
    love.graphics.clear(0.055, 0.065, 0.085)
    local accent = screen.tone == "pass" and { 0.35, 0.9, 0.55 }
        or screen.tone == "fail" and { 1.0, 0.45, 0.4 }
        or screen.tone == "ready" and { 0.35, 0.7, 1.0 }
        or { 0.85, 0.88, 0.96 }
    love.graphics.setColor(accent)
    love.graphics.setFont(titleFont)
    love.graphics.print(screen.title, 48, 42)
    love.graphics.setFont(bodyFont)
    local y = 100
    for _, line in ipairs(screen.lines) do
        y = drawWrapped(line, 48, y, 844)
    end
    if role == "host" and invitation and state == "waiting_guest" then
        love.graphics.setColor(0.12, 0.15, 0.2)
        love.graphics.rectangle("fill", 48, y + 4, 844, 116, 8, 8)
        love.graphics.setColor(0.95, 0.97, 1)
        love.graphics.printf(invitation, 62, y + 18, 816, "left")
        love.graphics.setColor(0.4, 0.75, 1)
        love.graphics.print(invitationCopied and
            "Copied. Send it privately to the guest." or
            "Press C to copy", 62, y + 86)
    elseif role == "guest" and state == "guest_input" then
        love.graphics.setColor(0.12, 0.15, 0.2)
        love.graphics.rectangle("fill", 48, y + 4, 844, 82, 8, 8)
        love.graphics.setColor(0.95, 0.97, 1)
        local display = #guestInput > 0 and string.rep("•",
            math.min(#guestInput, 72)) or "Ctrl+V to paste invitation"
        love.graphics.printf(display, 62, y + 30, 816, "left")
    end
    love.graphics.setFont(footFont)
    love.graphics.setColor(0.58, 0.64, 0.72)
    love.graphics.printf(
        "Engineering acceptance probe • no relay, matchmaking, telemetry, or retained network details",
        48, 580, 844, "center")
end

function love.textinput(text)
    if role ~= "guest" or state ~= "guest_input"
        or type(text) ~= "string" then return end
    if not text:find("[%z\1-\31\127]")
        and #guestInput + #text <= INVITATION_MAX_BYTES then
        guestInput = guestInput .. text
    end
end

function love.keypressed(key)
    local control = love.keyboard.isDown("lctrl", "rctrl")
    if role == "host" and invitation and state == "waiting_guest"
        and key == "c" then
        if love.system and love.system.setClipboardText then
            love.system.setClipboardText(invitation)
            invitationCopied = true
        end
    elseif role == "guest" and state == "guest_input" then
        if control and key == "v" and love.system
            and love.system.getClipboardText then
            local pasted = (love.system.getClipboardText() or "")
                :match("^%s*(.-)%s*$")
            if #pasted <= INVITATION_MAX_BYTES
                and not pasted:find("[%z\1-\31\127]") then
                guestInput = pasted
            end
        elseif key == "backspace" then
            guestInput = guestInput:sub(1, math.max(0, #guestInput - 1))
        elseif key == "return" or key == "kpenter" then
            startGuestConnection()
        end
    end
    if key == "escape" then
        if role == "host" or role == "traffic" then
            beginHostCleanup(false, "cancelled")
        else
            if transport then pcall(transport.close, transport, 0, true) end
            transport = nil
            finish(false, "cancelled")
        end
    end
end

function love.quit()
    if allowQuit or state == "finished" then return false end
    if (role == "host" or role == "traffic") and ipv4Host then
        beginHostCleanup(false, "cancelled")
        return true
    end
    if transport then pcall(transport.close, transport, 0, true) end
    transport = nil
    clearInvitation()
    if role == "guest" then
        finish(false, "cancelled")
        return true
    end
    return false
end
