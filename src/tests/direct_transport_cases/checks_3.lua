-- Direct transport cryptographic and lifecycle regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    do
    local scannerNetwork = Context.fakeNetwork()
    local scannerFactory, scannerCrypto = Context.newSecureFactory(scannerNetwork,
        Context.SHARED_KEY, nil, nil, { admissionBurst = 3 })
    local scannerHost = scannerFactory.createHost({ channels = 3 })
    for index = 1, 8 do
        Context.injectHostConnect(scannerNetwork, { id = "wrong-token-" .. tostring(index) },
            index)
    end
    for index = 1, 3 do
        Context.injectHostConnect(scannerNetwork, { id = "valid-after-scan-" .. tostring(index) },
            Context.fakeAdmissionToken(Context.SHARED_KEY))
    end
    scannerHost:service(64)
    Context.check("direct_transport_wrong_tokens_do_not_consume_admission_permits",
        #scannerCrypto.states == 3
        and Context.tableCount(scannerHost._peerStates) == 3
        and #scannerNetwork.disconnects == 8
        and scannerHost._admissionTokens == 0)
    scannerHost:close()
    end

    do
    local pendingNetwork = Context.fakeNetwork()
    local pendingFactory, pendingCrypto = Context.newSecureFactory(pendingNetwork,
        Context.SHARED_KEY, nil, nil, { admissionBurst = 8 })
    local pendingHost = pendingFactory.createHost({ channels = 3 })
    for index = 1, 8 do
        Context.injectHostConnect(pendingNetwork, { id = "pending-" .. tostring(index) },
            Context.fakeAdmissionToken(Context.SHARED_KEY))
    end
    pendingHost:service(64)
    Context.check("direct_transport_keeps_a_hard_four_state_pending_admission_cap",
        Context.DirectTransport.DEFAULT_MAX_PENDING_PEERS == 4
        and pendingHost.maxPendingPeers == Context.DirectTransport.DEFAULT_MAX_PENDING_PEERS
        and #pendingCrypto.states == Context.DirectTransport.DEFAULT_MAX_PENDING_PEERS
        and Context.tableCount(pendingHost._peerStates)
            == Context.DirectTransport.DEFAULT_MAX_PENDING_PEERS
        and pendingHost._admissionTokens == 4
        and #pendingNetwork.disconnects == 4)
    pendingHost:close()
    end

    do
    local refillNow = 0
    local refillNetwork = Context.fakeNetwork()
    local refillFactory, refillCrypto = Context.newSecureFactory(refillNetwork,
        Context.SHARED_KEY, function() return refillNow end, nil, {
            admissionBurst = 1,
            admissionRefillSeconds = 1,
        })
    local refillHost = refillFactory.createHost({ channels = 3 })
    local refillFirst = { id = "refill-first" }
    Context.injectHostConnect(refillNetwork, refillFirst, Context.fakeAdmissionToken(Context.SHARED_KEY))
    refillHost:service(8)
    refillHost:disconnect(refillFirst, 0, true)
    refillNow = 0.999
    local refillEarly = { id = "refill-early" }
    Context.injectHostConnect(refillNetwork, refillEarly, Context.fakeAdmissionToken(Context.SHARED_KEY))
    refillHost:service(8)
    refillNow = 1
    local refillExact = { id = "refill-exact" }
    Context.injectHostConnect(refillNetwork, refillExact, Context.fakeAdmissionToken(Context.SHARED_KEY))
    refillHost:service(8)
    Context.check("direct_transport_refills_one_admission_permit_per_second",
        #refillCrypto.states == 2
        and refillHost._peerStates[refillEarly] == nil
        and refillHost._peerStates[refillExact] ~= nil
        and refillHost._admissionTokens == 0)
    refillHost:close()
    end

    do
    local noRefundCalls = 0
    local noRefundSecret = "constructor-secret-" .. Context.hexEncode(Context.SHARED_KEY)
    local noRefundProvider = Context.fakeCryptoProvider({ states = {}, calls = {} })
    function noRefundProvider.newResponder()
        noRefundCalls = noRefundCalls + 1
        error(noRefundSecret)
    end
    local noRefundNetwork = Context.fakeNetwork()
    local noRefundFactory = Context.DirectTransport.newFactory({
        baseFactory = noRefundNetwork.factory,
        cryptoProvider = noRefundProvider,
        key = Context.SHARED_KEY,
        clock = function() return 0 end,
        admissionBurst = 1,
    })
    local noRefundHost = noRefundFactory.createHost({ channels = 3 })
    Context.injectHostConnect(noRefundNetwork, { id = "constructor-failure" },
        Context.fakeAdmissionToken(Context.SHARED_KEY))
    Context.injectHostConnect(noRefundNetwork, { id = "constructor-retry" },
        Context.fakeAdmissionToken(Context.SHARED_KEY))
    noRefundHost:service(8)
    Context.check("direct_transport_does_not_refund_failed_crypto_state_admissions",
        noRefundCalls == 1
        and Context.tableCount(noRefundHost._peerStates) == 0
        and #noRefundNetwork.disconnects == 2
        and type(noRefundHost.lastError) == "string"
        and noRefundHost.lastError:find(noRefundSecret, 1, true) == nil
        and noRefundHost.lastError:find(Context.hexEncode(Context.SHARED_KEY), 1, true) == nil)
    noRefundHost:close()
    end

    do
    local invalidClockSecret = "clock-secret-" .. Context.hexEncode(Context.SHARED_KEY)
    local invalidClockNetwork = Context.fakeNetwork()
    local invalidClockFactory, invalidClockCrypto = Context.newSecureFactory(
        invalidClockNetwork, Context.SHARED_KEY, function() error(invalidClockSecret) end)
    local invalidClockHost = invalidClockFactory.createHost({ channels = 3 })
    Context.injectHostConnect(invalidClockNetwork, { id = "invalid-clock" },
        Context.fakeAdmissionToken(Context.SHARED_KEY))
    invalidClockHost:service(8)
    Context.check("direct_transport_invalid_clock_fails_closed_without_allocating_or_leaking",
        #invalidClockCrypto.states == 0
        and Context.tableCount(invalidClockHost._peerStates) == 0
        and invalidClockHost._clockFailed == true
        and #invalidClockNetwork.disconnects == 1
        and type(invalidClockHost.lastError) == "string"
        and invalidClockHost.lastError:find(invalidClockSecret, 1, true) == nil
        and invalidClockHost.lastError:find(Context.hexEncode(Context.SHARED_KEY), 1, true) == nil)
    invalidClockHost:close()
    end

    do
    local backwardNow = 10
    local backwardNetwork = Context.fakeNetwork()
    local backwardFactory, backwardCrypto = Context.newSecureFactory(backwardNetwork,
        Context.SHARED_KEY, function() return backwardNow end)
    local backwardClientFactory = Context.newSecureFactory(backwardNetwork,
        Context.SHARED_KEY, function() return backwardNow end)
    local backwardHost = backwardFactory.createHost({ channels = 3 })
    local backwardClient, backwardPeer, _, _, backwardHostReady,
        backwardClientReady = Context.connectClient(
            backwardHost, backwardClientFactory, backwardNetwork)
    backwardNow = 9
    Context.injectHostConnect(backwardNetwork, { id = "after-clock-rollback" },
        Context.fakeAdmissionToken(Context.SHARED_KEY))
    backwardHost:service(8)
    Context.check("direct_transport_backward_clock_fails_closed_before_another_allocation",
        #backwardCrypto.states == 1
        and Context.containsEvent(backwardHostReady, "connect") ~= nil
        and Context.containsEvent(backwardClientReady, "connect") ~= nil
        and backwardHost._peerStates[backwardPeer] ~= nil
        and Context.tableCount(backwardHost._peerStates) == 1
        and Context.tableCount(backwardHost._readyPeers) == 1
        and backwardHost._clockFailed == true
        and type(backwardHost.lastError) == "string"
        and backwardHost.lastError:find(Context.hexEncode(Context.SHARED_KEY), 1, true) == nil)
    backwardClient:close()
    backwardHost:close()
    end

    do
    local readyNetwork = Context.fakeNetwork()
    local readyHostFactory, readyHostCrypto = Context.newSecureFactory(readyNetwork)
    local readyHost = readyHostFactory.createHost({ channels = 3 })
    local readyClients, readyPeers = {}, {}
    local firstThreeReady = true
    for index = 1, 3 do
        local readyClientFactory = Context.newSecureFactory(readyNetwork)
        local client, peer, _, _, hostEvents, clientEvents =
            Context.connectClient(readyHost, readyClientFactory, readyNetwork)
        readyClients[#readyClients + 1] = client
        readyPeers[#readyPeers + 1] = peer
        firstThreeReady = firstThreeReady
            and Context.containsEvent(hostEvents, "connect") ~= nil
            and Context.containsEvent(clientEvents, "connect") ~= nil
    end
    local fourthClientFactory = Context.newSecureFactory(readyNetwork)
    local fourthClient, fourthPeer, _, _, fourthHostEvents, fourthClientEvents =
        Context.connectClient(readyHost, fourthClientFactory, readyNetwork)
    local fourthRejected = Context.containsEvent(fourthHostEvents, "connect") == nil
        and Context.containsEvent(fourthClientEvents, "connect") == nil
        and readyHost._peerStates[fourthPeer] == nil
    readyHost:disconnect(readyPeers[1], 0, true)
    local replacementFactory = Context.newSecureFactory(readyNetwork)
    local replacementClient, replacementPeer, _, _, replacementHostEvents,
        replacementClientEvents = Context.connectClient(
            readyHost, replacementFactory, readyNetwork)
    Context.check("direct_transport_caps_ready_guests_at_three_and_allows_replacement",
        Context.DirectTransport.DEFAULT_MAX_READY_PEERS == 3
        and firstThreeReady and fourthRejected
        and Context.containsEvent(replacementHostEvents, "connect") ~= nil
        and Context.containsEvent(replacementClientEvents, "connect") ~= nil
        and readyHost._peerStates[replacementPeer] ~= nil
        and Context.tableCount(readyHost._readyPeers) == 3
        and #readyHostCrypto.states == 4)
    fourthClient:close()
    replacementClient:close()
    for _, client in ipairs(readyClients) do client:close() end
    readyHost:close()
    end

    Context.preAuthNetwork = Context.fakeNetwork()
    Context.preAuthHostFactory, Context.preAuthHostCrypto = Context.newSecureFactory(Context.preAuthNetwork)
    Context.preAuthClientFactory = Context.newSecureFactory(Context.preAuthNetwork)
    Context.preAuthHost = Context.preAuthHostFactory.createHost({ channels = 3 })
    Context.preAuthClient = Context.preAuthClientFactory.createClient(
        "direct.example:22122", { channels = 3 })
end

return Component
