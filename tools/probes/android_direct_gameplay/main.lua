-- Engineering-only full-game Direct Internet Play acceptance driver.
--
-- This file is never used as the normal game's entry point.  The Android
-- runner copies it over main.lua inside two isolated engineering packages.
-- The native provider remains productionReady=false in the shipped source;
-- this process-local opt-in exists only so the complete player flow can be
-- exercised before the independent production crypto review is complete.
local Config = require("direct_gameplay_probe_config")

assert(Config.role == "host" or Config.role == "guest",
    "engineering Direct gameplay role is invalid")
assert(type(Config.playerName) == "string" and #Config.playerName >= 16
    and #Config.playerName <= 24
    and Config.playerName:match("^[A-Za-z0-9]+$"),
    "engineering Direct gameplay player canary is invalid")

local multiGuest = Config.multiGuest == true
local guestOrdinal = tonumber(Config.guestOrdinal) or 1
local directPorts = type(Config.directPorts) == "table"
    and Config.directPorts or { 57842 }
local expectedGuestNames = type(Config.expectedGuestNames) == "table"
    and Config.expectedGuestNames or {}

if multiGuest then
    assert(#directPorts == 2 and directPorts[1] == 57842
        and directPorts[2] == 57844,
        "engineering multi-guest Direct ports are invalid")
    if Config.role == "guest" then
        assert(guestOrdinal == 1 or guestOrdinal == 2,
            "engineering Direct guest ordinal is invalid")
    else
        assert(#expectedGuestNames == 2,
            "engineering Direct expected guest list is invalid")
        for index = 1, 2 do
            local name = expectedGuestNames[index]
            assert(type(name) == "string" and #name >= 16 and #name <= 24
                and name:match("^[A-Za-z0-9]+$"),
                "engineering Direct expected guest canary is invalid")
        end
        assert(expectedGuestNames[1] ~= expectedGuestNames[2],
            "engineering Direct expected guest canaries must differ")
    end
end

local function indexedName(name, ordinal)
    if not multiGuest then return name end
    return name .. "-" .. tostring(ordinal)
end

local function guestName(name)
    return indexedName(name, guestOrdinal)
end

local Probe = {
    session = nil,
    elapsed = 0,
    inputX = 0,
    inputY = 0,
    movementElapsed = 0,
    remoteStartX = nil,
    remoteStartY = nil,
    remoteStarts = {},
    hostInvitationOrdinal = 1,
    hostOpeningOrdinal = 0,
    approvalCount = 0,
    approvalRequestIds = {},
    pendingApproval = nil,
    flags = {},
    pendingMarkers = {},
}

local function socketPreflightPort(port)
    local loaded, socketModule = pcall(require, "socket")
    if not loaded or type(socketModule) ~= "table"
        or type(socketModule.udp6) ~= "function"
    then
        return false, "module"
    end
    local created, udp = pcall(socketModule.udp6)
    if not created or not udp then return false, "create" end
    local socketType = type(udp)
    if (socketType ~= "table" and socketType ~= "userdata")
        or type(udp.settimeout) ~= "function"
        or type(udp.setsockname) ~= "function"
        or type(udp.getsockname) ~= "function"
        or type(udp.close) ~= "function"
    then
        pcall(udp.close, udp)
        return false, "shape"
    end
    local timeoutOk, timeoutResult = pcall(udp.settimeout, udp, 0)
    if not timeoutOk or timeoutResult == nil or timeoutResult == false then
        pcall(udp.close, udp)
        return false, "nonblocking"
    end
    local bindOk, bindResult, bindError = pcall(udp.setsockname, udp, "::", port)
    if not bindOk or bindResult == nil or bindResult == false then
        pcall(udp.close, udp)
        local message = tostring(bindError or bindResult or "")
        local category = message:find("use", 1, true) and "bind-in-use"
            or (message:find("permission", 1, true) and "bind-permission")
            or (message:find("argument", 1, true) and "bind-argument")
            or "bind"
        return false, category
    end
    local nameOk, _, boundPort = pcall(udp.getsockname, udp)
    pcall(udp.close, udp)
    if not nameOk then return false, "getsockname-call" end
    boundPort = tonumber(boundPort)
    if type(boundPort) ~= "number" then return false, "getsockname-port-type" end
    if boundPort ~= port then return false, "getsockname-port-value" end
    return true, "ready"
end

local function socketPreflight()
    local ports = Config.role == "host" and directPorts
        or { directPorts[guestOrdinal] or directPorts[1] }
    for _, port in ipairs(ports) do
        local ready, stage = socketPreflightPort(port)
        if not ready then return false, stage end
    end
    return true, "ready"
end

local socketPreflightReady, socketPreflightStage = socketPreflight()

local function fixedName(value)
    return type(value) == "string" and value:match("^[a-z0-9%-]+$") ~= nil
end

local function probePath(name)
    assert(fixedName(name), "invalid engineering marker name")
    return "probe/" .. name .. ".txt"
end

local function remove(name)
    local path = probePath(name)
    if love.filesystem.getInfo(path) then love.filesystem.remove(path) end
end

local function writePrivate(name, value)
    assert(type(value) == "string", "engineering private value must be text")
    love.filesystem.createDirectory("probe")
    return love.filesystem.write(probePath(name), value)
end

local function mark(name)
    if Probe.flags[name] then return true end
    local wrote = writePrivate(name, "ok\n")
    -- Private milestone storage can be briefly unavailable while Android is
    -- settling app data after a launch.  Commit the one-shot flag only after
    -- the file exists so the next update can retry instead of losing evidence.
    if not wrote then
        Probe.pendingMarkers[name] = true
        return false
    end
    Probe.pendingMarkers[name] = nil
    Probe.flags[name] = true
    print("[TPS DIRECT GAMEPLAY] " .. name .. " role=" .. Config.role)
    io.flush()
    return true
end

local function flushPendingMarkers()
    local names = {}
    for name in pairs(Probe.pendingMarkers) do names[#names + 1] = name end
    for _, name in ipairs(names) do mark(name) end
end

local function readInbox(name)
    local path = probePath(name)
    if not love.filesystem.getInfo(path) then return nil end
    local value = love.filesystem.read(path)
    love.filesystem.remove(path)
    if type(value) ~= "string" then return false end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" or #value > 160 or value:find("[^A-Za-z0-9_.%-]") then
        return false
    end
    return value
end

local function readAddressInbox(name)
    local path = probePath(name or "inbox-local-address")
    if not love.filesystem.getInfo(path) then return nil end
    local value = love.filesystem.read(path)
    love.filesystem.remove(path)
    if type(value) ~= "string" then return false end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" or #value > 39 or value:find("[^0-9A-Fa-f:]") then
        return false
    end
    return value
end

local CryptoNative = require("src.net.crypto_native")
assert(CryptoNative.productionReady == false,
    "engineering package expected the production provider gate to be closed")
assert(CryptoNative.engineeringOnly == true and CryptoNative.engineeringReady == true,
    "engineering native provider is not ready")
CryptoNative.productionReady = true

-- Report only bounded state facts from the authenticated opening.  This
-- engineering adapter deliberately never records endpoints, packets, codes,
-- nonces, or keys.
local function openingName(name, ordinal)
    return multiGuest and ("opening-" .. tostring(ordinal) .. "-" .. name)
        or ("opening-" .. name)
end

local function instrumentOpeningState(state, ordinal)
    if type(state) ~= "table" then return state end
    local proxy = {}
    function proxy:next()
        local packet, errorMessage = state:next()
        if type(packet) == "string" then mark(openingName("native-next", ordinal)) end
        return packet, errorMessage
    end
    function proxy:receive(packet)
        mark(openingName("native-receive", ordinal))
        local accepted, errorMessage = state:receive(packet)
        if accepted == true then
            mark(openingName("native-accepted", ordinal))
        else
            mark(openingName("native-rejected", ordinal))
        end
        return accepted, errorMessage
    end
    function proxy:isReady()
        local ready, errorMessage = state:isReady()
        if ready == true then mark(openingName("native-ready", ordinal)) end
        return ready, errorMessage
    end
    function proxy:close()
        return state:close()
    end
    return proxy
end

local originalOpeningHost = CryptoNative.newOpeningHost
local originalOpeningGuest = CryptoNative.newOpeningGuest
CryptoNative.newOpeningHost = function(...)
    Probe.hostOpeningOrdinal = Probe.hostOpeningOrdinal + 1
    return instrumentOpeningState(originalOpeningHost(...), Probe.hostOpeningOrdinal)
end
CryptoNative.newOpeningGuest = function(...)
    return instrumentOpeningState(originalOpeningGuest(...), guestOrdinal)
end

local Ipv6Address = require("src.net.ipv6_address")
local DirectOpening = require("src.net.direct_opening")
local originalOpeningCreate = DirectOpening.create
local directOpeningHostOrdinal = 0
DirectOpening.create = function(options)
    local rawSocket = options and options.socket
    local peerRecord = options and options.role == "host"
        and options.response or options and options.host
    local expectedAddress = peerRecord and Ipv6Address.parse(peerRecord.address)
    local expectedPort = peerRecord and tonumber(peerRecord.port)
    local openingOrdinal
    if options and options.role == "host" then
        directOpeningHostOrdinal = directOpeningHostOrdinal + 1
        openingOrdinal = directOpeningHostOrdinal
    else
        openingOrdinal = guestOrdinal
    end
    if rawSocket and expectedAddress and expectedPort then
        local proxy = {}
        function proxy:settimeout(value)
            return rawSocket:settimeout(value)
        end
        function proxy:sendto(packet, address, port)
            local sent, errorMessage = rawSocket:sendto(packet, address, port)
            if sent ~= nil and sent ~= false then
                mark(openingName("datagram-sent", openingOrdinal))
            end
            return sent, errorMessage
        end
        function proxy:receivefrom()
            local packet, address, port = rawSocket:receivefrom()
            if packet ~= nil then
                mark(openingName("datagram-received", openingOrdinal))
                if type(packet) == "string" and #packet == 92 then
                    mark(openingName("framing-matched", openingOrdinal))
                end
                local parsed = type(address) == "string"
                    and Ipv6Address.parse(address) or nil
                if parsed and parsed.bytes == expectedAddress.bytes then
                    mark(openingName("address-matched", openingOrdinal))
                end
                if tonumber(port) == expectedPort then
                    mark(openingName("port-numeric-matched", openingOrdinal))
                end
                if type(port) == "string" then
                    mark(openingName("port-was-string", openingOrdinal))
                elseif type(port) == "number" then
                    mark(openingName("port-was-number", openingOrdinal))
                end
            end
            return packet, address, port
        end
        function proxy:close()
            return rawSocket:close()
        end
        options.socket = proxy
    end
    return originalOpeningCreate(options)
end

local DirectConnection = require("src.net.direct_connection")
local originalDirectNew = DirectConnection.new
local hostPortOrdinal = 0
DirectConnection.new = function(options)
    options = options or {}
    options.lifetimeSeconds = 120
    local connection, errorMessage = originalDirectNew(options)
    if connection then
        local originalStartHost = connection.startHost
        connection.startHost = function(self, localAddress)
            -- The engineering run uses a known-free outer port previously
            -- proven by the encrypted two-phone bridge.  The chosen port is
            -- carried inside the host code; it is not a game-session port.
            hostPortOrdinal = hostPortOrdinal + 1
            local port = directPorts[hostPortOrdinal]
            assert(type(port) == "number",
                "engineering Direct host created too many invitations")
            return originalStartHost(self, localAddress, port)
        end
    end
    return connection, errorMessage
end

local Save = require("src.save")
local originalNewGame = Save.newGame
Save.newGame = function(slot, timestamp)
    local payload = originalNewGame(slot, timestamp)
    if Config.role == "host" then
        -- Put the authoritative host and first guest within the allowlisted
        -- loading-bay and cutter ranges in this disposable engineering save.
        payload.player.x, payload.player.y = 320, 285
        payload.state.cutter.x, payload.state.cutter.y = 430, 285
        payload.state.cutter.direction = "northwest"
        payload.state.cutter.moving = false
        payload.state.cutter.inMotion = false
    end
    return payload
end

local Input = require("src.input")
Input.movement = function()
    return Probe.inputX, Probe.inputY
end

local Session = require("src.net.session")
local originalSessionNew = Session.new
Session.new = function(options)
    local session = originalSessionNew(options)
    -- Use a private, per-run player name so packet-capture validation can
    -- prove the real protocol encoded it before the Direct transport encrypted
    -- it. Session construction does not consume a name; the start calls do.
    local function named(startOptions)
        local result = {}
        for key, value in pairs(startOptions or {}) do result[key] = value end
        result.name = Config.playerName
        return result
    end
    local originalStartHost = session.startHost
    session.startHost = function(self, startOptions)
        return originalStartHost(self, named(startOptions))
    end
    local originalStartClient = session.startClient
    session.startClient = function(self, address, startOptions)
        return originalStartClient(self, address, named(startOptions))
    end
    Probe.session = session
    return session
end

local Protocol = require("src.net.protocol")
local originalProtocolEncode = Protocol.encode
Protocol.encode = function(envelopeOrKind, payload)
    local encoded, encodeError = originalProtocolEncode(envelopeOrKind, payload)
    if type(encoded) == "string" then
        if encoded:find(Config.playerName, 1, true) then
            mark("encoded-player-canary")
        end
        if encoded:find("loadingBayDoor", 1, true) then
            mark("encoded-loading-bay-plaintext")
        end
        if encoded:find("emergency_stop", 1, true) then
            mark("encoded-cutter-plaintext")
        end
    end
    return encoded, encodeError
end

local originalQueue = Session._queue
Session._queue = function(self, eventType, values)
    if self == Probe.session then
        if eventType == "ready" then
            Probe.flags.snapshotReceived = true
        elseif eventType == "player_joined" then
            Probe.flags.playerJoined = true
        elseif eventType == "player_left" then
            Probe.flags.playerLeft = true
            if multiGuest and Config.role == "host" and values
                and values.name == expectedGuestNames[2]
                and values.reason == "Application closed"
            then
                Probe.flags.gracefulSurvivorLeft = true
            end
        elseif eventType == "direct_closed" then
            Probe.flags.directClosed = true
        elseif eventType == "interaction_result" and values and values.accepted == true
            and values.targetKind == "loadingBayDoor"
        then
            Probe.flags.bayInteraction = true
        elseif eventType == "workshop_grant" and values and values.granted == true
            and values.resourceId == "cutter"
        then
            Probe.flags.cutterGranted = true
        elseif eventType == "workshop_result" and values and values.accepted == true
            and values.resourceId == "cutter" and values.action == "emergency_stop"
        then
            Probe.flags.cutterAction = true
        elseif eventType == "disconnected" then
            Probe.flags.disconnected = true
        elseif eventType == "error" then
            Probe.flags.sessionError = true
        end
    end
    return originalQueue(self, eventType, values)
end

local originalSessionStop = Session.stop
Session.stop = function(self, reason)
    local verifyGraceful = self == Probe.session
        and Probe.flags.gracefulQuitRequested == true
    local wasActive = verifyGraceful and self.mode == "client"
        and self.ready == true and self.transport ~= nil
        and not Probe.flags.sessionError and not Probe.flags.disconnected
    local cleaned, cleanupError = originalSessionStop(self, reason)
    if verifyGraceful then
        assert(wasActive, "graceful exit did not begin from an active Direct client")
        assert(cleaned == true and self.mode == "offline" and self.transport == nil,
            "graceful Direct client stop could not be verified")
        Probe.flags.gracefulSessionStopObserved = true
        assert(mark(guestName("session-stop-confirmed")),
            "graceful session-stop marker could not be committed")
    end
    return cleaned, cleanupError
end

local DirectScreen = require("src.screens.direct_screen")
local MultiplayerHud = require("src.screens.multiplayer_hud")
local Viewport = require("src.viewport")
local GameConfig = require("src.config")
local App = require("src.app")
local originalAppQuit = App.quit
App.quit = function(...)
    local verifyGraceful = Probe.flags.gracefulQuitRequested == true
    if verifyGraceful then
        local session = Probe.session
        assert(session and session.mode == "client" and session.ready == true
                and session.transport ~= nil and not Probe.flags.sessionError
                and not Probe.flags.disconnected,
            "graceful exit was no longer attached before App.quit")
        Probe.flags.gracefulAppQuitObserved = true
    end
    local result = originalAppQuit(...)
    if verifyGraceful then
        assert(Probe.flags.gracefulSessionStopObserved == true,
            "App.quit did not stop the active Direct client")
        assert(mark(guestName("app-quit-confirmed")),
            "graceful App.quit marker could not be committed")
        assert(mark(guestName("client-graceful-exit")),
            "graceful exit marker could not be committed")
    end
    return result
end

local function resetProbeFiles()
    local names = {
        "host-code", "response-code", "inbox-host-code", "inbox-response-code",
        "inbox-local-address", "inbox-disconnect", "app-loaded",
        "host-code-ready", "response-code-ready", "response-accepted",
        "response-rejected", "host-approved", "session-ready", "snapshot-applied", "hud-direct-two",
        "bay-interaction", "cutter-action", "movement", "client-complete",
        "host-complete", "host-disconnect", "failure", "opening-native-next",
        "opening-native-receive", "opening-native-accepted",
        "opening-native-rejected", "opening-native-ready",
        "opening-datagram-sent", "opening-datagram-received",
        "opening-framing-matched", "opening-address-matched",
        "opening-port-numeric-matched", "opening-port-was-string",
        "opening-port-was-number", "client-graceful-exit",
        "session-stop-confirmed", "app-quit-confirmed", "inbox-kick",
        "host-kick", "guest-kicked", "encoded-player-canary",
        "encoded-loading-bay-plaintext", "encoded-cutter-plaintext",
    }
    if multiGuest then
        for ordinal = 1, 2 do
            for _, base in ipairs({
                "host-code", "host-code-ready", "response-code",
                "response-code-ready", "response-accepted", "response-rejected",
                "inbox-host-code", "inbox-response-code",
                "approval-waiting", "approval-pending",
                "inbox-approve", "host-approved", "session-ready",
                "snapshot-applied", "hud-direct-two", "hud-direct-three",
                "bay-interaction", "cutter-action", "movement",
                "client-complete", "host-observed-movement", "host-complete",
                "opening-native-next", "opening-native-receive",
                "opening-native-accepted", "opening-native-rejected",
                "opening-native-ready", "opening-datagram-sent",
                "opening-datagram-received", "opening-framing-matched",
                "opening-address-matched", "opening-port-numeric-matched",
                "opening-port-was-string", "opening-port-was-number",
                "guest-kicked", "client-graceful-exit",
                "session-stop-confirmed", "app-quit-confirmed",
            }) do
                names[#names + 1] = indexedName(base, ordinal)
            end
        end
        for _, name in ipairs({
            "inbox-invite-2", "inbox-local-address-2", "host-hud-three",
            "inbox-kick-1", "host-kick-1", "host-survivor-two",
            "guest-survivor-two", "host-final-one",
        }) do
            names[#names + 1] = name
        end
    end
    for _, name in ipairs(names) do
        remove(name)
    end
end

local function enterPlayerFlow()
    App.keypressed("i")
    if Config.role == "host" then
        App.keypressed("h")
        App.textinput(Config.localAddress)
        App.keypressed("return")
        if DirectScreen.mode ~= "host_reply"
            or type(DirectScreen.displayCode) ~= "string"
        then
            local message = tostring(DirectScreen.message or "")
            local category = message:find("save", 1, true) and "host-save"
                or (message:find("socket", 1, true) and "socket")
                or (message:find("address", 1, true) and "address")
                or (message:find("unavailable", 1, true) and "unavailable")
                or "unknown"
            error("host player flow failure category=" .. category)
        end
        local hostCodeName = indexedName("host-code", 1)
        assert(writePrivate(hostCodeName, DirectScreen.displayCode),
            "host code could not be placed in private app storage")
        mark(indexedName("host-code-ready", 1))
    else
        App.keypressed("j")
        assert(DirectScreen.mode == "guest_setup",
            "guest player flow did not open")
    end
end

local function serviceCodeExchange()
    if Config.role == "guest" and DirectScreen.mode == "guest_setup" then
        local code = readInbox(guestName("inbox-host-code"))
        if code == false then error("invalid private host-code exchange") end
        if code then
            App.textinput(code)
            App.keypressed("tab")
            App.textinput(Config.localAddress)
            App.keypressed("return")
            assert(DirectScreen.mode == "opening_guest"
                and type(DirectScreen.displayCode) == "string",
                "guest player flow did not produce a reply")
            assert(writePrivate(guestName("response-code"), DirectScreen.displayCode),
                "reply code could not be placed in private app storage")
            mark(guestName("response-code-ready"))
        end
    elseif Config.role == "host" and DirectScreen.mode == "host_reply" then
        local ordinal = multiGuest and Probe.hostInvitationOrdinal or 1
        local response = readInbox(indexedName("inbox-response-code", ordinal))
        if response == false then error("invalid private response-code exchange") end
        if response then
            App.textinput(response)
            App.keypressed("return")
            if DirectScreen.mode == "host_reply" then
                mark(indexedName("response-rejected", ordinal))
                -- A real player replaces the rejected reply before pasting a
                -- fresh one.  The engineering driver types directly into the
                -- focused field, so clear the rejected text explicitly.
                DirectScreen.responseInput = ""
            else
                mark(indexedName("response-accepted", ordinal))
            end
        end
    end
end

local function directPlayerHud(playerCount)
    local session = Probe.session
    if not session then return false end
    local info = session:hudInfo()
    return info.networkKind == "direct" and info.playerCount == playerCount
        and ((Config.role == "host" and info.mode == "host")
            or (Config.role == "guest" and info.mode == "client"))
end

local function clickHudButton(kind, identifier, info, twice)
    if not MultiplayerHud.isOpen() then App.keypressed("p") end
    local gameX, gameY = MultiplayerHud.buttonCenter(kind, identifier, info)
    assert(gameX and gameY, "host player control was not available")
    local offsetX, offsetY, scale = Viewport.transform(
        GameConfig.baseWidth, GameConfig.baseHeight)
    local screenX, screenY = offsetX + gameX * scale, offsetY + gameY * scale
    App.mousepressed(screenX, screenY, 1, false)
    App.mousereleased(screenX, screenY, 1, false)
    if twice then
        App.mousepressed(screenX, screenY, 1, false)
        App.mousereleased(screenX, screenY, 1, false)
    end
end

local function serviceHostMovement(session)
    for ordinal, expectedName in ipairs(expectedGuestNames) do
        local remote
        for _, candidate in ipairs(session:remotePlayers()) do
            if candidate.name == expectedName then remote = candidate; break end
        end
        if remote then
            local start = Probe.remoteStarts[ordinal]
            if not start then
                Probe.remoteStarts[ordinal] = { x = remote.x, y = remote.y }
            else
                local dx, dy = remote.x - start.x, remote.y - start.y
                if dx * dx + dy * dy >= 25 then
                    mark(indexedName("host-observed-movement", ordinal))
                    mark(indexedName("host-complete", ordinal))
                end
            end
        end
    end
end

local function serviceMultiHostAcceptance(session, info)
    if info.pendingJoinCount == 1 and info.pendingJoins and info.pendingJoins[1] then
        local pendingInfo = info.pendingJoins[1]
        local ordinal = Probe.approvalCount + 1
        assert(ordinal <= 2 and pendingInfo.name == expectedGuestNames[ordinal],
            "unexpected Direct guest requested approval")
        assert(info.playerCount == ordinal,
            "Direct guest received session state before approval")
        if not Probe.pendingApproval then
            assert(not Probe.approvalRequestIds[pendingInfo.requestId],
                "Direct approval request identifier was reused")
            Probe.pendingApproval = {
                ordinal = ordinal,
                requestId = pendingInfo.requestId,
            }
            mark(indexedName("approval-pending", ordinal))
        end
    end

    local pending = Probe.pendingApproval
    if pending then
        local command = readInbox(indexedName("inbox-approve", pending.ordinal))
        if command == false then error("invalid private approval command") end
        if command then
            assert(command == "approve", "unknown private approval command")
            assert(info.pendingJoinCount == 1
                    and info.pendingJoins[1].requestId == pending.requestId,
                "Direct approval request changed before host confirmation")
            clickHudButton("approve", pending.requestId, info, false)
            local accepted = session.approvalRequests[pending.requestId]
            assert(accepted and accepted.decision == "approved",
                "host approval control rejected the authenticated player")
            Probe.approvalRequestIds[pending.requestId] = true
            Probe.approvalCount = pending.ordinal
            Probe.pendingApproval = nil
            mark(indexedName("host-approved", pending.ordinal))
            return
        end
    end

    if directPlayerHud(2) and Probe.approvalCount >= 1 then
        mark(indexedName("session-ready", 1))
        mark(indexedName("hud-direct-two", 1))
    elseif directPlayerHud(3) and Probe.approvalCount == 2 then
        mark(indexedName("session-ready", 2))
        mark("host-hud-three")
    end
    serviceHostMovement(session)
end

local function serviceHostAcceptance()
    local session = Probe.session
    if not session then return end
    local info = session:hudInfo()
    if multiGuest then
        serviceMultiHostAcceptance(session, info)
        return
    end
    if not Probe.flags["host-approved"] and info.pendingJoinCount == 1
        and info.pendingJoins and info.pendingJoins[1]
    then
        local requestId = info.pendingJoins[1].requestId
        clickHudButton("approve", requestId, info, false)
        local pending = session.approvalRequests[requestId]
        assert(pending and pending.decision == "approved",
            "host approval control rejected the authenticated player")
        mark("host-approved")
        return
    end
    if not directPlayerHud(2) then return end
    mark("session-ready")
    mark("hud-direct-two")

    local remote = session:remotePlayers()[1]
    if remote and Probe.remoteStartX == nil then
        Probe.remoteStartX, Probe.remoteStartY = remote.x, remote.y
    elseif remote and Probe.remoteStartX ~= nil then
        local dx, dy = remote.x - Probe.remoteStartX, remote.y - Probe.remoteStartY
        if dx * dx + dy * dy >= 25 then mark("movement") end
    end
    if Probe.flags.movement then mark("host-complete") end
end

local function serviceAdditionalHostInvite()
    if not multiGuest or Config.role ~= "host"
        or Probe.hostInvitationOrdinal ~= 1 or Probe.approvalCount ~= 1
    then
        return
    end
    local command = readInbox("inbox-invite-2")
    if command == false then error("invalid private invitation command") end
    if not command then return end
    assert(command == "invite", "unknown private invitation command")
    local address = readAddressInbox("inbox-local-address-2")
    assert(type(address) == "string", "second private host address was unavailable")
    local session = Probe.session
    local info = session and session:hudInfo() or nil
    assert(info and info.networkKind == "direct" and info.mode == "host"
            and info.playerCount == 2 and info.pendingJoinCount == 0,
        "second Direct invitation was not sequential")
    info.canInvite = true
    clickHudButton("invite", nil, info, false)
    assert(DirectScreen.mode == "host_setup",
        "additional Direct invitation player flow did not open")
    Probe.hostInvitationOrdinal = 2
    App.textinput(address)
    App.keypressed("return")
    assert(DirectScreen.mode == "host_reply"
            and type(DirectScreen.displayCode) == "string",
        "second Direct host code could not be created")
    assert(writePrivate(indexedName("host-code", 2), DirectScreen.displayCode),
        "second host code could not be placed in private app storage")
    mark(indexedName("host-code-ready", 2))
end

local function serviceGuestAcceptance(dt)
    local session = Probe.session
    if not session then return end
    if multiGuest and not session.ready then
        if DirectScreen.mode == "connecting" and not Probe.flags.snapshotReceived then
            mark(guestName("approval-waiting"))
        end
        return
    end
    local expectedCount = multiGuest and (guestOrdinal == 1 and 2 or 3) or 2
    local info = session:hudInfo()
    if multiGuest and guestOrdinal == 2 and session.ready
        and Probe.flags[guestName("hud-direct-three")]
        and info.networkKind == "direct" and info.mode == "client"
        and info.playerCount == 2 and not Probe.flags.disconnected
    then
        mark("guest-survivor-two")
    end
    if not session.ready or info.networkKind ~= "direct"
        or info.mode ~= "client" or info.playerCount < expectedCount
    then
        return
    end
    mark(guestName("session-ready"))
    if info.playerCount == 2 then mark(guestName("hud-direct-two")) end
    if multiGuest and info.playerCount == 3 then
        mark(guestName("hud-direct-three"))
    end
    if Probe.flags.snapshotReceived and DirectScreen.callbacks == nil then
        mark(guestName("snapshot-applied"))
    else
        return
    end

    if not multiGuest or guestOrdinal == 1 then
        if not Probe.flags.bayRequested then
            local requested = session:requestInteraction("loadingBayDoor", "open")
            if requested then Probe.flags.bayRequested = true end
            return
        end
        if not Probe.flags.bayInteraction then return end
        mark(guestName("bay-interaction"))

        if not Probe.flags.cutterRequested then
            local requested = session:requestWorkshopAcquire("cutter")
            if requested then Probe.flags.cutterRequested = true end
            return
        end
        if not Probe.flags.cutterGranted then return end
        if not Probe.flags.cutterCommandRequested then
            local requested = session:requestWorkshopCommand("emergency_stop", {})
            if requested then Probe.flags.cutterCommandRequested = true end
            return
        end
        if not Probe.flags.cutterAction then return end
        mark(guestName("cutter-action"))
        if not Probe.flags.cutterReleased then
            App.keypressed("escape")
            Probe.flags.cutterReleased = true
            Probe.inputX, Probe.inputY = 0, 1
        end
    elseif not Probe.flags.secondGuestMovementStarted then
        Probe.flags.secondGuestMovementStarted = true
        Probe.inputX, Probe.inputY = 1, 0
    end

    Probe.movementElapsed = Probe.movementElapsed + math.max(0, tonumber(dt) or 0)
    if Probe.movementElapsed >= 1.5 then
        Probe.inputX, Probe.inputY = 0, 0
        mark(guestName("movement"))
        mark(guestName("client-complete"))
    end
end

local function serviceDisconnect()
    if Config.role ~= "host" or not Probe.flags.playerLeft then return end
    local session = Probe.session
    local info = session and session:hudInfo() or nil
    if multiGuest and info and info.mode == "host"
        and info.networkKind == "direct"
    then
        if Probe.flags["host-kick-1"] and Probe.approvalCount == 2
            and info.playerCount == 2
        then
            mark("host-survivor-two")
        elseif Probe.flags["host-survivor-two"]
            and Probe.flags.gracefulSurvivorLeft and info.playerCount == 1
        then
            mark("host-final-one")
        end
        return
    end
    if info and ((info.mode == "host" and info.networkKind == "direct"
        and info.playerCount == 1) or (info.mode == "offline" and Probe.flags.directClosed))
    then
        mark("host-disconnect")
    end
end

local function serviceDisconnectCommand()
    if Config.role ~= "guest"
        or not Probe.flags[guestName("client-complete")]
    then
        return
    end
    local command = readInbox("inbox-disconnect")
    if command == false then error("invalid private disconnect command") end
    if not command then return end
    assert(command == "quit", "unknown private disconnect command")
    local session = Probe.session
    assert(session ~= nil and not Probe.flags.sessionError
            and not Probe.flags.disconnected
            and session.mode == "client" and session.ready == true
            and session.transport ~= nil,
        "graceful exit command arrived after the Direct client disconnected")
    Probe.flags.gracefulQuitRequested = true
    love.event.quit(0)
end

local function serviceKickCommand()
    if Config.role == "guest" then
        local command = readInbox("inbox-kick")
        if command == false then error("invalid private kick command") end
        if command then
            assert(command == "kick", "unknown private kick command")
            Probe.flags.expectKick = true
        end
        if Probe.flags.expectKick and (Probe.flags.sessionError or Probe.flags.disconnected) then
            mark(guestName("guest-kicked"))
        end
        return
    end
    if multiGuest then
        if Probe.flags["host-kick-1"] then return end
        local command = readInbox("inbox-kick-1")
        if command == false then error("invalid private kick command") end
        if not command then return end
        assert(command == "kick", "unknown private kick command")
        local session = Probe.session
        local info = session and session:hudInfo() or nil
        assert(info and info.playerCount == 3 and info.connectedGuests,
            "host kick control did not have three connected players")
        local playerId
        for _, guest in ipairs(info.connectedGuests) do
            if guest.name == expectedGuestNames[1] then
                playerId = guest.playerId
                break
            end
        end
        assert(playerId, "host kick control could not identify the first guest")
        clickHudButton("remove", playerId, info, true)
        local after = session:hudInfo()
        assert(session.terminal ~= true and session.transport ~= nil
                and session.players[playerId] == nil and after.playerCount == 2,
            "host remove confirmation did not preserve the surviving Direct link")
        mark("host-kick-1")
        mark("host-survivor-two")
        return
    end
    if Probe.flags["host-kick"] then return end
    local command = readInbox("inbox-kick")
    if command == false then error("invalid private kick command") end
    if not command then return end
    assert(command == "kick", "unknown private kick command")
    local session = Probe.session
    local info = session and session:hudInfo() or nil
    assert(info and info.connectedGuests and info.connectedGuests[1],
        "host kick control had no connected guest")
    local playerId = info.connectedGuests[1].playerId
    clickHudButton("remove", playerId, info, true)
    assert(session.terminal ~= true and session.transport ~= nil
        and session.players[playerId] == nil,
        "host remove confirmation did not isolate the Direct guest link")
    mark("host-kick")
end

function love.load()
    resetProbeFiles()
    App.load()
    print("[TPS DIRECT GAMEPLAY] socket-preflight-" .. socketPreflightStage
        .. " role=" .. Config.role)
    io.flush()
    if not socketPreflightReady then
        error("engineering socket preflight failure category=" .. socketPreflightStage)
    end
    mark("app-loaded")
end

function love.update(dt)
    flushPendingMarkers()
    Probe.elapsed = Probe.elapsed + math.max(0, tonumber(dt) or 0)
    if not Probe.flags.playerFlowEntered then
        local address = readAddressInbox()
        if address == false then error("invalid private local-address exchange") end
        if address then
            Config.localAddress = address
            Probe.flags.playerFlowEntered = true
            enterPlayerFlow()
        end
    end
    serviceCodeExchange()
    App.update(dt)
    if Config.role == "host" then
        serviceHostAcceptance()
        serviceAdditionalHostInvite()
    else
        serviceGuestAcceptance(dt)
    end
    serviceDisconnect()
    serviceDisconnectCommand()
    serviceKickCommand()
    local lifetime = multiGuest and 300 or 180
    if Probe.elapsed > lifetime and not Probe.flags.failure then
        mark("failure")
    end
end

function love.draw() App.draw() end
function love.keypressed(key) App.keypressed(key) end
function love.keyreleased(key) App.keyreleased(key) end
function love.textinput(text) App.textinput(text) end
function love.mousepressed(x, y, button, istouch) App.mousepressed(x, y, button, istouch) end
function love.mousereleased(x, y, button, istouch) App.mousereleased(x, y, button, istouch) end
function love.mousemoved(x, y, dx, dy, istouch) App.mousemoved(x, y, dx, dy, istouch) end
function love.wheelmoved(x, y) App.wheelmoved(x, y) end
function love.touchpressed(id, x, y) App.touchpressed(id, x, y) end
function love.touchmoved(id, x, y, dx, dy) App.touchmoved(id, x, y, dx, dy) end
function love.touchreleased(id, x, y) App.touchreleased(id, x, y) end
function love.gamepadpressed(joystick, button) App.gamepadpressed(joystick, button) end
function love.gamepadreleased(joystick, button) App.gamepadreleased(joystick, button) end
function love.focus(focused) App.focus(focused) end
function love.quit() App.quit() end
