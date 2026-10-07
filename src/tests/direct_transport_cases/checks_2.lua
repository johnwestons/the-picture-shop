-- Direct transport cryptographic and lifecycle regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.wrongKey.client:close()
    Context.wrongKey.host:close()

    Context.plaintext = Context.establishSingle()
    Context.plaintext.network:injectHost(Context.plaintext.peer, "hello from plaintext", 0, true)
    Context.plaintextEvents = Context.plaintext.host:service(8)
    Context.plaintextDisconnect = Context.containsEvent(Context.plaintextEvents, "disconnect")
    Context.check("direct_transport_rejects_plaintext_after_authentication_without_fallback",
        Context.plaintextDisconnect
        and Context.plaintextDisconnect.code == Context.DirectTransport.DISCONNECT_AUTHENTICATION
        and not Context.containsEvent(Context.plaintextEvents, "receive"))
    Context.plaintext.client:close()
    Context.plaintext.host:close()

    Context.tampered = Context.establishSingle()
    Context.tampered.client:sendToServer("protected", 2, false)
    Context.tamperedRaw = Context.tampered.network.host.inbound[#Context.tampered.network.host.inbound]
    Context.tamperedRaw.data = Context.tamperedRaw.data:sub(1, -2)
        .. string.char((Context.tamperedRaw.data:byte(-1) + 1) % 255)
    Context.tamperedRaw.payload = Context.tamperedRaw.data
    Context.tamperedEvents = Context.tampered.host:service(8)
    Context.check("direct_transport_rejects_tampered_ciphertext",
        Context.containsEvent(Context.tamperedEvents, "disconnect") ~= nil
        and not Context.containsEvent(Context.tamperedEvents, "receive"))
    Context.tampered.client:close()
    Context.tampered.host:close()

    Context.movedChannel = Context.establishSingle()
    Context.movedChannel.client:sendToServer("channel-bound", 2, false)
    Context.movedRaw = Context.movedChannel.network.host.inbound[#Context.movedChannel.network.host.inbound]
    Context.movedRaw.channel = 1
    Context.movedEvents = Context.movedChannel.host:service(8)
    Context.check("direct_transport_authenticates_the_observed_channel_as_aad",
        Context.containsEvent(Context.movedEvents, "disconnect") ~= nil
        and not Context.containsEvent(Context.movedEvents, "receive"))
    Context.movedChannel.client:close()
    Context.movedChannel.host:close()

    Context.unreliableNetwork = Context.fakeNetwork()
    Context.unreliableHostFactory = Context.newSecureFactory(Context.unreliableNetwork)
    Context.unreliableClientFactory = Context.newSecureFactory(Context.unreliableNetwork)
    Context.unreliableHost = Context.unreliableHostFactory.createHost({ channels = 3 })
    Context.unreliableClient = Context.unreliableClientFactory.createClient("direct.example:22122",
        { channels = 3 })
    Context.unreliablePeer = Context.unreliableClient.base.peer
    Context.unreliableHost:service(8)
    Context.unreliableClient:service(8)
    Context.handshakeRaw = Context.unreliableNetwork.host.inbound[#Context.unreliableNetwork.host.inbound]
    Context.handshakeRaw.reliable = false
    Context.handshakeRaw.channel = 1
    Context.unreliableEvents = Context.unreliableHost:service(8)
    Context.check("direct_transport_rejects_handshakes_outside_reliable_channel_zero",
        Context.unreliableEvents and #Context.unreliableEvents == 0
        and Context.unreliableNetwork.disconnects[#Context.unreliableNetwork.disconnects].code
            == Context.DirectTransport.DISCONNECT_AUTHENTICATION)
    Context.unreliableClient:close()
    Context.unreliableHost:close()

    Context.now = 0
    Context.timeoutNetwork = Context.fakeNetwork()
    Context.timeoutFactory, Context.timeoutCrypto = Context.newSecureFactory(Context.timeoutNetwork,
        Context.SHARED_KEY, function() return Context.now end, 3)
    Context.timeoutClientFactory = Context.newSecureFactory(Context.timeoutNetwork,
        Context.SHARED_KEY, function() return Context.now end, 3)
    Context.timeoutHost = Context.timeoutFactory.createHost({ channels = 3 })
    Context.timeoutClient = Context.timeoutClientFactory.createClient(
        "direct.example:22122", { channels = 3 })
    Context.timeoutHost:service(8)
    Context.now = 3.1
    Context.timeoutEvents = Context.timeoutHost:service(8)
    Context.timeoutDisconnect = Context.timeoutNetwork.disconnects[#Context.timeoutNetwork.disconnects]
    Context.check("direct_transport_expires_and_cleans_up_incomplete_handshakes",
        Context.timeoutEvents and #Context.timeoutEvents == 0
        and Context.timeoutDisconnect
        and Context.timeoutDisconnect.code == Context.DirectTransport.DISCONNECT_HANDSHAKE_TIMEOUT
        and next(Context.timeoutHost._peerStates) == nil
        and Context.countCalls(Context.timeoutCrypto, "close") == 1)
    Context.timeoutClient:close()
    Context.timeoutHost:close()

    Context.broadcastNetwork = Context.fakeNetwork()
    Context.broadcastFactory, Context.broadcastCrypto = Context.newSecureFactory(Context.broadcastNetwork)
    Context.broadcastClientFactoryOne = Context.newSecureFactory(Context.broadcastNetwork)
    Context.broadcastClientFactoryTwo = Context.newSecureFactory(Context.broadcastNetwork)
    Context.broadcastHost = Context.broadcastFactory.createHost({ channels = 3 })
    Context.clientOne, Context.peerOne, Context._, Context._, Context.hostOne, Context.readyOne =
        Context.connectClient(Context.broadcastHost, Context.broadcastClientFactoryOne, Context.broadcastNetwork)
    Context.clientTwo, Context.peerTwo, Context._, Context._, Context.hostTwo, Context.readyTwo =
        Context.connectClient(Context.broadcastHost, Context.broadcastClientFactoryTwo, Context.broadcastNetwork)
    Context.sealBefore = Context.countCalls(Context.broadcastCrypto, "seal")
    Context.sendsBefore = #Context.broadcastNetwork.sends
    Context.didBroadcast = Context.broadcastHost:broadcast("snapshot", 2, false)
    Context.broadcastSends = {}
    for index = Context.sendsBefore + 1, #Context.broadcastNetwork.sends do
        Context.broadcastSends[#Context.broadcastSends + 1] = Context.broadcastNetwork.sends[index]
    end
    Context.oneEvents = Context.clientOne:service(8)
    Context.twoEvents = Context.clientTwo:service(8)
    Context.check("direct_transport_broadcast_seals_once_per_authenticated_peer",
        Context.containsEvent(Context.hostOne, "connect") and Context.containsEvent(Context.readyOne, "connect")
        and Context.containsEvent(Context.hostTwo, "connect") and Context.containsEvent(Context.readyTwo, "connect")
        and Context.didBroadcast and #Context.broadcastSends == 2
        and Context.broadcastSends[1].peer ~= Context.broadcastSends[2].peer
        and Context.broadcastSends[1].channel == 2 and not Context.broadcastSends[1].reliable
        and Context.broadcastSends[2].channel == 2 and not Context.broadcastSends[2].reliable
        and Context.broadcastNetwork.broadcastCalls == 0
        and Context.countCalls(Context.broadcastCrypto, "seal") == Context.sealBefore + 2
        and Context.containsEvent(Context.oneEvents, "receive", "snapshot")
        and Context.containsEvent(Context.twoEvents, "receive", "snapshot"))

    Context.responderIds = {}
    for _, state in ipairs(Context.broadcastCrypto.states) do
        if state.role == "responder" then Context.responderIds[state.id] = true end
    end
    Context.responderCloseBefore = Context.countCalls(Context.broadcastCrypto, "close", Context.responderIds)
    Context.hostClosed = Context.broadcastHost:close(0, true)
    Context.responderCloseAfter = Context.countCalls(Context.broadcastCrypto, "close", Context.responderIds)
    Context.check("direct_transport_close_cleans_every_per_peer_crypto_state",
        Context.hostClosed and Context.broadcastHost.closed and Context.broadcastHost.base.closed
        and next(Context.broadcastHost._peerStates) == nil
        and Context.responderCloseBefore == 0 and Context.responderCloseAfter == 2
        and Context.peerOne ~= Context.peerTwo)
    Context.clientOne:close(0, true)
    Context.clientTwo:close(0, true)

    Context.boundedNetwork = Context.fakeNetwork()
    Context.boundedFactory = Context.newSecureFactory(Context.boundedNetwork, Context.SHARED_KEY, nil, nil, {
        maxHandshakeBytes = 64,
        maxPlaintextBytes = 8,
        maxWireBytes = 128,
    })
    Context.boundedClientFactory = Context.newSecureFactory(Context.boundedNetwork, Context.SHARED_KEY, nil, nil, {
        maxHandshakeBytes = 64,
        maxPlaintextBytes = 8,
        maxWireBytes = 128,
    })
    Context.boundedHost = Context.boundedFactory.createHost({ channels = 3 })
    Context.boundedClient, Context.boundedPeer, Context._, Context._, Context.boundedHostReady, Context.boundedClientReady =
        Context.connectClient(Context.boundedHost, Context.boundedClientFactory, Context.boundedNetwork)
    Context.oversizedSend = Context.boundedClient:sendToServer("123456789", 2, false)
    Context.boundedNetwork:injectHost(Context.boundedPeer, string.rep("x", 129), 2, false)
    Context.oversizedEvents = Context.boundedHost:service(8)
    Context.check("direct_transport_enforces_plaintext_and_wire_byte_caps",
        Context.containsEvent(Context.boundedHostReady, "connect")
        and Context.containsEvent(Context.boundedClientReady, "connect")
        and Context.oversizedSend == false
        and Context.containsEvent(Context.oversizedEvents, "disconnect") ~= nil
        and not Context.containsEvent(Context.oversizedEvents, "receive"))
    Context.boundedClient:close()
    Context.boundedHost:close()

    Context.prefilterNetwork = Context.fakeNetwork()
    Context.prefilterHostFactory, Context.prefilterHostCrypto = Context.newSecureFactory(Context.prefilterNetwork)
    Context.prefilterClientFactory = Context.newSecureFactory(Context.prefilterNetwork)
    Context.prefilterHost = Context.prefilterHostFactory.createHost({ channels = 3 })
    for index = 1, 3 do
        Context.prefilterNetwork.host.inbound[#Context.prefilterNetwork.host.inbound + 1] = {
            type = "connect",
            peer = { id = "scanner-" .. tostring(index) },
            data = index,
            code = index,
        }
    end
    Context.prefilterHost:service(16)
    Context.prefilterClient, Context._, Context._, Context._, Context.prefilterHostReady, Context.prefilterClientReady =
        Context.connectClient(Context.prefilterHost, Context.prefilterClientFactory, Context.prefilterNetwork)
    Context.secondHost = Context.prefilterHostFactory.createHost({ channels = 3 })
    Context.check("direct_transport_prefilter_releases_scanners_before_noise_state_allocation",
        #Context.prefilterNetwork.disconnects >= 3
        and #Context.prefilterHostCrypto.states == 1
        and Context.containsEvent(Context.prefilterHostReady, "connect") ~= nil
        and Context.containsEvent(Context.prefilterClientReady, "connect") ~= nil
        and Context.secondHost == nil)
    Context.check("direct_transport_factory_and_shared_key_are_session_scoped",
        Context.prefilterHost._key == Context.SHARED_KEY and Context.prefilterClient._key == nil)
    Context.prefilterClient:close()
    Context.prefilterHost:close()
    Context.check("direct_transport_close_releases_the_host_shared_key",
        Context.prefilterHost._key == nil)

    do
    local burstNow = 0
    local burstNetwork = Context.fakeNetwork()
    local burstFactory, burstCrypto = Context.newSecureFactory(burstNetwork, Context.SHARED_KEY,
        function() return burstNow end, nil, { maxPendingPeers = 8 })
    local burstHost = burstFactory.createHost({ channels = 3 })
    for index = 1, 10 do
        Context.injectHostConnect(burstNetwork, { id = "burst-" .. tostring(index) },
            Context.fakeAdmissionToken(Context.SHARED_KEY))
    end
    burstHost:service(64)
    Context.check("direct_transport_bounds_same_tick_valid_admissions_before_crypto_allocation",
        Context.DirectTransport.DEFAULT_ADMISSION_BURST == 4
        and #burstCrypto.states == Context.DirectTransport.DEFAULT_ADMISSION_BURST
        and Context.tableCount(burstHost._peerStates) == Context.DirectTransport.DEFAULT_ADMISSION_BURST
        and #burstNetwork.disconnects == 10 - Context.DirectTransport.DEFAULT_ADMISSION_BURST
        and burstHost._admissionTokens == 0)
    burstHost:close()
    end
end

return Component
