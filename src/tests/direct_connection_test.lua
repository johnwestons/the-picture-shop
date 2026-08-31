local DirectConnection = require("src.net.direct_connection")
local DirectOpeningCode = require("src.net.direct_opening_code")
local Session = require("src.net.session")

local Test = {}

local HOST_ADDRESS = "2606:4700:4700::1111"
local GUEST_ADDRESS = "2001:4860:4860::8888"

local function digest(value)
    local a, b = 2166136261, 2246822519
    for index = 1, #value do
        local byte = value:byte(index)
        a = (a * 16777619 + byte) % 4294967296
        b = (b * 3266489917 + byte + index) % 4294967296
    end
    local word = string.char(
        math.floor(a / 16777216) % 256,
        math.floor(a / 65536) % 256,
        math.floor(a / 256) % 256,
        a % 256,
        math.floor(b / 16777216) % 256,
        math.floor(b / 65536) % 256,
        math.floor(b / 256) % 256,
        b % 256)
    return word .. word .. word .. word
end

local function fakeProvider(productionReady)
    local provider = { productionReady = productionReady == true, randomCalls = 0 }
    function provider.randomBytes(count)
        provider.randomCalls = provider.randomCalls + 1
        return string.rep(string.char(64 + provider.randomCalls), count)
    end
    function provider.responseTag(masterKey, transcript)
        return digest(masterKey .. transcript)
    end
    function provider.verifyResponseTag(masterKey, transcript, tag)
        return tag == provider.responseTag(masterKey, transcript)
    end
    function provider.newOpeningHost() return {} end
    function provider.newOpeningGuest() return {} end
    function provider.newBridgeHost() return {} end
    function provider.newBridgeGuest() return {} end
    function provider.newInitiator() return {} end
    function provider.newResponder() return {} end
    return provider
end

local function fakeSockets()
    local module = { sockets = {}, nextPort = 24000 }
    function module.udp() return {} end
    function module.udp6()
        local socket = {
            timeout = nil,
            address = nil,
            port = nil,
            closeCalls = 0,
        }
        function socket:settimeout(value) self.timeout = value; return 1 end
        function socket:setsockname(address, port)
            self.address = address
            self.port = port == 0 and module.nextPort or port
            module.nextPort = module.nextPort + 1
            return 1
        end
        function socket:getsockname()
            return self.address, module.stringPorts and tostring(self.port) or self.port
        end
        function socket:sendto() return 1 end
        function socket:receivefrom() return nil, "timeout" end
        function socket:close()
            self.closeCalls = self.closeCalls + 1
            if module.failClose then return false end
            return 1
        end
        module.sockets[#module.sockets + 1] = socket
        return socket
    end
    return module
end

local function fakeOpeningModule(log)
    local module = {}
    function module.create(options)
        log[#log + 1] = options
        local opening = {
            options = options,
            ready = false,
            closeCalls = 0,
        }
        function opening:update() self.ready = true; return "ready" end
        function opening:isReady() return self.ready end
        function opening:takeSocket()
            local socket = self.options.socket
            self.options.socket = nil
            return socket
        end
        function opening:close()
            self.closeCalls = self.closeCalls + 1
            if self.options.socket then
                self.options.socket:close()
                self.options.socket = nil
            end
            return true
        end
        log.lastOpening = opening
        return opening
    end
    return module
end

local function fakeTransportModules(log)
    local direct, bridge = {}, {}
    function direct.newFactory(options)
        log.direct = options
        return {
            createHost = function() return {} end,
            createClient = function() return {} end,
            close = function()
                log.directCloseCalls = (log.directCloseCalls or 0) + 1
                return true
            end,
        }
    end
    function bridge.newFactory(options)
        log.bridge = options
        local disposed = false
        return {
            marker = "direct-bridge-factory",
            createHost = function() return {} end,
            createClient = function() return {} end,
            close = function()
                if disposed then return true end
                disposed = true
                log.bridgeCloseCalls = (log.bridgeCloseCalls or 0) + 1
                local openingOk = options.opening:close()
                local baseOk = options.baseFactory.close()
                return openingOk == true and baseOk == true
            end,
        }
    end
    return direct, bridge
end

local function connectionOptions(now, provider, sockets, openingLog, transportLog)
    local direct, bridge = fakeTransportModules(transportLog)
    return {
        provider = provider,
        socketModule = sockets,
        openingModule = fakeOpeningModule(openingLog),
        directTransportModule = direct,
        bridgeTransportModule = bridge,
        baseFactory = {
            createHost = function() return {} end,
            createClient = function() return {} end,
        },
        wallClock = function() return now.value end,
        clock = function() return now.monotonic end,
        lifetimeSeconds = 120,
    }
end

local function responseCode(hostCode, provider, guestAddress)
    local host = assert(DirectOpeningCode.parseHost(hostCode, 1000, {
        futureSkew = 0, expiryGrace = 0,
    }))
    local response = {
        kind = "response",
        version = 2,
        issuedAt = host.issuedAt,
        lifetime = host.lifetime,
        address = guestAddress,
        port = host.port,
        invitationId = host.invitationId,
        guestNonce = string.rep("G", 16),
    }
    response.responseTag = provider.responseTag(host.masterKey,
        assert(DirectOpeningCode.responseTranscript(host, response)))
    return assert(DirectOpeningCode.encodeResponse(response))
end

function Test.run(_, check)
    local now = { value = 1000, monotonic = 10 }
    local provider = fakeProvider(true)
    local sockets, openingLog, transportLog = fakeSockets(), {}, {}
    local host = assert(DirectConnection.new(connectionOptions(
        now, provider, sockets, openingLog, transportLog)))
    local hostStarted, hostCode = host:startHost(HOST_ADDRESS)
    local parsedHost = hostCode and DirectOpeningCode.parseHost(hostCode, now.value, {
        futureSkew = 0, expiryGrace = 0,
    })
    check("direct_connection_host_binds_before_creating_an_expiring_secret_code",
        hostStarted and parsedHost and host.state == "awaiting_response"
        and parsedHost.address == HOST_ADDRESS
        and parsedHost.port == DirectConnection.DEFAULT_OUTER_PORT
        and #parsedHost.masterKey == 32 and #parsedHost.invitationId == 16
        and sockets.sockets[1].address == "::" and sockets.sockets[1].timeout == 0)

    local androidSockets = fakeSockets()
    androidSockets.stringPorts = true
    local androidHost = assert(DirectConnection.new(connectionOptions(
        now, fakeProvider(true), androidSockets, {}, {})))
    local androidStarted, androidCode = androidHost:startHost(HOST_ADDRESS, 57842)
    local androidParsed = androidCode and DirectOpeningCode.parseHost(
        androidCode, now.value, { futureSkew = 0, expiryGrace = 0 })
    check("direct_connection_accepts_android_luasocket_numeric_string_bound_port",
        androidStarted and androidParsed and androidParsed.port == 57842
        and type(androidParsed.port) == "number")
    androidHost:close()

    local badResponse = responseCode(hostCode, provider, GUEST_ADDRESS)
    badResponse = badResponse:sub(1, -2) .. (badResponse:sub(-1) == "A" and "B" or "A")
    local badAccepted, badError = host:submitResponse(badResponse)
    check("direct_connection_rejects_a_bad_reply_without_losing_the_host_invitation",
        badAccepted == false and badError == DirectConnection.ERROR_RESPONSE_CODE
        and host.state == "awaiting_response" and host:code() == hostCode
        and sockets.sockets[1].closeCalls == 0
        and not badError:find(hostCode, 1, true))

    local replyCode = responseCode(hostCode, provider, GUEST_ADDRESS)
    local replyAccepted = host:submitResponse(replyCode)
    local hostState = host:update()
    local hostFactory, hostRole = host:takeTransportFactory()
    local secondFactory = host:takeTransportFactory()
    check("direct_connection_host_authenticates_then_hands_the_bridge_factory_off_once",
        replyAccepted and hostState == "ready"
        and hostFactory and hostFactory.marker == "direct-bridge-factory"
        and hostRole == "host" and secondFactory == nil
        and host.state == "handed_off" and host:code() == nil
        and #openingLog == 1 and openingLog[1].role == "host"
        and transportLog.bridge.role == "host"
        and transportLog.bridge.peerAddress == GUEST_ADDRESS
        and transportLog.bridge.peerPort == DirectConnection.DEFAULT_OUTER_PORT
        and transportLog.direct.key == parsedHost.masterKey)
    check("direct_connection_handoff_does_not_close_the_socket_owned_by_the_factory",
        sockets.sockets[1].closeCalls == 0 and host:close()
        and sockets.sockets[1].closeCalls == 0)

    local guestNow = { value = 1000, monotonic = 20 }
    local guestProvider = fakeProvider(true)
    local guestSockets, guestOpeningLog, guestTransportLog = fakeSockets(), {}, {}
    local guest = assert(DirectConnection.new(connectionOptions(
        guestNow, guestProvider, guestSockets, guestOpeningLog, guestTransportLog)))
    local guestStarted, guestCode = guest:startGuest(hostCode, GUEST_ADDRESS)
    local parsedResponse = guestCode and DirectOpeningCode.parseResponse(guestCode)
    local matched = parsedResponse and DirectOpeningCode.verifyResponse(
        parsedHost, parsedResponse, guestProvider.verifyResponseTag)
    local guestState = guest:update()
    local guestFactory, guestRole = guest:takeTransportFactory()
    check("direct_connection_guest_generates_an_authenticated_reply_and_starts_opening",
        guestStarted and matched and guestState == "ready"
        and guestFactory and guestRole == "guest"
        and parsedResponse.address == GUEST_ADDRESS
        and parsedResponse.port == parsedHost.port
        and guestOpeningLog[1].role == "guest"
        and guestTransportLog.bridge.role == "guest"
        and guestTransportLog.bridge.peerAddress == HOST_ADDRESS)

    local cancelSockets = fakeSockets()
    local cancel = assert(DirectConnection.new(connectionOptions(
        { value = 2000, monotonic = 1 }, fakeProvider(true), cancelSockets, {}, {})))
    cancel:startHost(HOST_ADDRESS)
    local cancelCode = cancel:code()
    local cancelClosed = cancel:close()
    check("direct_connection_cancel_closes_the_bound_socket_and_clears_codes",
        cancelClosed and cancel.state == "closed" and cancel:code() == nil
        and cancelSockets.sockets[1].closeCalls == 1
        and cancelCode:sub(1, #DirectOpeningCode.HOST_PREFIX)
            == DirectOpeningCode.HOST_PREFIX)

    local readyCancelNow = { value = 1000, monotonic = 1 }
    local readyCancelLog, readyOpeningLog = {}, {}
    local readyCancel = assert(DirectConnection.new(connectionOptions(
        readyCancelNow, fakeProvider(true), fakeSockets(),
        readyOpeningLog, readyCancelLog)))
    local readyStarted, readyHostCode = readyCancel:startHost(HOST_ADDRESS)
    local readyParsedHost = readyHostCode and DirectOpeningCode.parseHost(
        readyHostCode, readyCancelNow.value, { futureSkew = 0, expiryGrace = 0 })
    local readyResponse = readyParsedHost and responseCode(
        readyHostCode, readyCancel.provider, GUEST_ADDRESS)
    local readySubmitted = readyResponse and readyCancel:submitResponse(readyResponse)
    local readyState = readySubmitted and readyCancel:update()
    local readyClosed, readyCloseError = readyCancel:close()
    check("direct_connection_ready_cancel_disposes_the_unclaimed_bridge_factory_once",
        readyStarted and readyState == "ready" and readyClosed
        and readyCloseError == nil and readyCancelLog.bridgeCloseCalls == 1
        and readyCancelLog.directCloseCalls == 1
        and readyOpeningLog.lastOpening.closeCalls == 1)

    local failedCleanupSockets = fakeSockets()
    failedCleanupSockets.failClose = true
    local failedCleanup = assert(DirectConnection.new(connectionOptions(
        { value = 2100, monotonic = 1 }, fakeProvider(true),
        failedCleanupSockets, {}, {})))
    failedCleanup:startHost(HOST_ADDRESS)
    local failedClose, failedCloseError = failedCleanup:close()
    local failedCloseAgain, failedCloseAgainError = failedCleanup:close()
    check("direct_connection_repeated_close_never_upgrades_unverified_socket_cleanup",
        failedClose == false and failedCloseError ~= nil
        and failedCloseAgain == false and failedCloseAgainError == failedCloseError
        and failedCleanupSockets.sockets[1].closeCalls == 1)

    local expiryNow = { value = 3000, monotonic = 1 }
    local expirySockets = fakeSockets()
    local expiring = assert(DirectConnection.new(connectionOptions(
        expiryNow, fakeProvider(true), expirySockets, {}, {})))
    expiring:startHost(HOST_ADDRESS)
    expiryNow.value = 3121
    local expiredState, expiredError = expiring:update()
    check("direct_connection_expiry_fails_closed_and_releases_the_waiting_socket",
        expiredState == "failed" and expiredError == DirectConnection.ERROR_HOST_CODE
        and expirySockets.sockets[1].closeCalls == 1 and expiring:code() == nil)

    local unavailableSockets = fakeSockets()
    local unavailable, unavailableError = DirectConnection.new(connectionOptions(
        now, fakeProvider(false), unavailableSockets, {}, {}))
    check("direct_connection_production_gate_blocks_before_socket_or_entropy_activity",
        unavailable == nil and unavailableError == DirectConnection.ERROR_UNAVAILABLE
        and #unavailableSockets.sockets == 0)

    local invalidSockets = fakeSockets()
    local invalid = assert(DirectConnection.new(connectionOptions(
        now, fakeProvider(true), invalidSockets, {}, {})))
    local invalidStarted, invalidError = invalid:startHost("fe80::1")
    check("direct_connection_rejects_non_global_addresses_before_binding",
        invalidStarted == false and invalidError == DirectConnection.ERROR_ADDRESS
        and #invalidSockets.sockets == 0)

    local faultNow = { value = 1000, monotonic = 30 }
    local faultProvider, faultSockets = fakeProvider(true), fakeSockets()
    local faultOptions = connectionOptions(
        faultNow, faultProvider, faultSockets, {}, {})
    faultOptions.directTransportModule = {
        newFactory = function() error("injected factory failure containing no user data") end,
    }
    local faulted = assert(DirectConnection.new(faultOptions))
    local faultStarted = faulted:startGuest(hostCode, GUEST_ADDRESS)
    local faultState, faultError = faulted:update()
    check("direct_connection_factory_exception_fails_closed_and_redacts_invitation_data",
        faultStarted and faultState == "failed"
        and faultError == "The encrypted Direct Internet transport could not start."
        and faulted:code() == nil and faultSockets.sockets[1].closeCalls == 1
        and not faultError:find(hostCode, 1, true))

    local factoryCalls = { default = 0, host = 0, client = 0 }
    local function transport()
        return {
            close = function() return true end,
            flush = function() return true end,
            broadcast = function() return true end,
            send = function() return true end,
            sendToServer = function() return true end,
            disconnect = function() return true end,
            service = function() return {} end,
        }
    end
    local defaultFactory = {
        createHost = function() factoryCalls.default = factoryCalls.default + 1; return transport() end,
        createClient = function() factoryCalls.default = factoryCalls.default + 1; return transport() end,
    }
    local overrideFactory = {
        createHost = function() factoryCalls.host = factoryCalls.host + 1; return transport() end,
        createClient = function() factoryCalls.client = factoryCalls.client + 1; return transport() end,
    }
    local directHostSession = Session.new({
        transportFactory = defaultFactory,
        clock = function() return 50 end,
    })
    local directClientSession = Session.new({
        transportFactory = defaultFactory,
        clock = function() return 51 end,
    })
    local sessionHostStarted = directHostSession:startHost({
        transportFactory = overrideFactory,
        networkKind = "direct",
        port = 22122,
        name = "Direct Host",
    })
    local sessionClientStarted = directClientSession:startClient("127.0.0.1:22122", {
        transportFactory = overrideFactory,
        networkKind = "direct",
        name = "Direct Worker",
    })
    check("multiplayer_session_accepts_one_session_direct_factories_without_replacing_lan_default",
        sessionHostStarted and sessionClientStarted
        and factoryCalls.default == 0 and factoryCalls.host == 1 and factoryCalls.client == 1
        and directHostSession:hudInfo().networkKind == "direct"
        and directClientSession:hudInfo().networkKind == "direct"
        and directHostSession.localAddress == nil
        and directHostSession.status == "Hosting a Direct Internet shop"
        and directClientSession.status == "Connecting to the Direct Internet host")
end

return Test
