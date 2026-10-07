-- Direct transport cryptographic and lifecycle regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.baseFactory = {
        createHost = function() return {} end,
        createClient = function() return {} end,
    }
    Context.providerLog = { states = {}, calls = {} }
    Context.validProvider = Context.fakeCryptoProvider(Context.providerLog)
    Context.noProvider, Context.noProviderError = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, key = Context.SHARED_KEY,
    })
    Context.noKey, Context.noKeyError = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, cryptoProvider = Context.validProvider,
    })
    Context.shortKey = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, cryptoProvider = Context.validProvider, key = "too-short",
    })
    Context.longKey = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, cryptoProvider = Context.validProvider,
        key = string.rep("x", Context.DirectTransport.KEY_BYTES + 1),
    })
    Context.selfDeclaredTestProvider = Context.fakeCryptoProvider({ states = {}, calls = {} })
    Context.selfDeclaredTestProvider.productionReady = nil
    Context.nonProductionProvider = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, cryptoProvider = Context.selfDeclaredTestProvider, key = Context.SHARED_KEY,
    })
    Context.lowLevelOnly = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, cryptoProvider = { seal = function() end },
        key = Context.SHARED_KEY,
    })
    Context.missingAdmissionProvider = Context.fakeCryptoProvider({ states = {}, calls = {} })
    Context.missingAdmissionProvider.admissionToken = nil
    Context.missingAdmissionToken = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, cryptoProvider = Context.missingAdmissionProvider,
        key = Context.SHARED_KEY,
    })
    Context.check("direct_transport_fails_closed_without_high_level_crypto_and_key",
        Context.noProvider == nil and type(Context.noProviderError) == "string"
        and Context.noKey == nil and type(Context.noKeyError) == "string"
        and Context.shortKey == nil and Context.longKey == nil
        and Context.nonProductionProvider == nil and Context.lowLevelOnly == nil
        and Context.missingAdmissionToken == nil)

    Context.tokenKey = nil
    Context.maximumTokenProvider = Context.fakeCryptoProvider({ states = {}, calls = {} })
    function Context.maximumTokenProvider.admissionToken(key)
        Context.tokenKey = key
        return 2147483647
    end
    Context.maximumTokenFactory = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, cryptoProvider = Context.maximumTokenProvider,
        key = Context.SHARED_KEY,
    })
    Context.zeroTokenProvider = Context.fakeCryptoProvider({ states = {}, calls = {} })
    function Context.zeroTokenProvider.admissionToken() return 0 end
    Context.zeroTokenFactory = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, cryptoProvider = Context.zeroTokenProvider,
        key = Context.SHARED_KEY,
    })
    Context.check("direct_transport_uses_provider_owned_admission_token_with_inclusive_bounds",
        Context.maximumTokenFactory ~= nil and Context.zeroTokenFactory ~= nil and Context.tokenKey == Context.SHARED_KEY)

    Context.invalidTokenAccepted = false
    for _, invalidToken in ipairs({ -1, 0.5, 2147483648, "17", 0 / 0 }) do
        local invalidProvider = Context.fakeCryptoProvider({ states = {}, calls = {} })
        function invalidProvider.admissionToken() return invalidToken end
        local invalidFactory = Context.DirectTransport.newFactory({
            baseFactory = Context.baseFactory, cryptoProvider = invalidProvider,
            key = Context.SHARED_KEY,
        })
        if invalidFactory ~= nil then Context.invalidTokenAccepted = true end
    end
    Context.tokenSecretError = "token-provider-error-" .. Context.hexEncode(Context.SHARED_KEY)
    Context.throwingTokenProvider = Context.fakeCryptoProvider({ states = {}, calls = {} })
    function Context.throwingTokenProvider.admissionToken() error(Context.tokenSecretError) end
    Context.throwingTokenFactory, Context.throwingTokenError = Context.DirectTransport.newFactory({
        baseFactory = Context.baseFactory, cryptoProvider = Context.throwingTokenProvider,
        key = Context.SHARED_KEY,
    })
    Context.check("direct_transport_rejects_invalid_or_failing_provider_admission_tokens",
        not Context.invalidTokenAccepted and Context.throwingTokenFactory == nil
        and type(Context.throwingTokenError) == "string"
        and Context.throwingTokenError:find(Context.tokenSecretError, 1, true) == nil
        and Context.throwingTokenError:find(Context.hexEncode(Context.SHARED_KEY), 1, true) == nil)
    Context.check("direct_transport_rejects_invalid_admission_rate_and_ready_caps",
        Context.DirectTransport.newFactory({
            baseFactory = Context.baseFactory, cryptoProvider = Context.validProvider,
            key = Context.SHARED_KEY, admissionBurst = 0,
        }) == nil
        and Context.DirectTransport.newFactory({
            baseFactory = Context.baseFactory, cryptoProvider = Context.validProvider,
            key = Context.SHARED_KEY, admissionRefillSeconds = 0,
        }) == nil
        and Context.DirectTransport.newFactory({
            baseFactory = Context.baseFactory, cryptoProvider = Context.validProvider,
            key = Context.SHARED_KEY, maxReadyPeers = 4,
        }) == nil)

    Context.session = Context.establishSingle()
    Context.check("direct_transport_suppresses_physical_connect_until_mutual_authentication",
        Context.session.hostBefore and #Context.session.hostBefore == 0
        and Context.session.clientBefore and #Context.session.clientBefore == 0
        and Context.containsEvent(Context.session.hostReady, "connect") ~= nil
        and Context.containsEvent(Context.session.clientReady, "connect") ~= nil
        and Context.session.client.peer == Context.session.peer)
    Context.check("direct_transport_uses_invitation_prefilter_and_reserved_peer_capacity",
        Context.session.network.hostOptions.peerCapacity == Context.DirectTransport.DEFAULT_PEER_CAPACITY
        and Context.session.host.peerCapacity == Context.DirectTransport.DEFAULT_PEER_CAPACITY
        and Context.session.host.maxPendingPeers == Context.DirectTransport.DEFAULT_MAX_PENDING_PEERS
        and Context.session.host.admissionBurst == Context.DirectTransport.DEFAULT_ADMISSION_BURST
        and Context.session.host.admissionRefillSeconds
            == Context.DirectTransport.DEFAULT_ADMISSION_REFILL_SECONDS
        and Context.session.host.maxReadyPeers == Context.DirectTransport.DEFAULT_MAX_READY_PEERS
        and Context.session.network.lastClientOptions.connectData
            == Context.fakeAdmissionToken(Context.SHARED_KEY))

    Context.firstHandshake = Context.session.network.sends[1]
    Context.secondHandshake = Context.session.network.sends[2]
    Context.thirdHandshake = Context.session.network.sends[3]
    Context.fourthHandshake = Context.session.network.sends[4]
    Context.check("direct_transport_handshake_is_strictly_framed_on_reliable_channel_zero",
        Context.firstHandshake and Context.secondHandshake and Context.thirdHandshake and Context.fourthHandshake
        and Context.firstHandshake.channel == 0 and Context.firstHandshake.reliable
        and Context.secondHandshake.channel == 0 and Context.secondHandshake.reliable
        and Context.thirdHandshake.channel == 0 and Context.thirdHandshake.reliable
        and Context.fourthHandshake.channel == 0 and Context.fourthHandshake.reliable
        and Context.firstHandshake.payload:sub(1, 4) == Context.DirectTransport.MAGIC
        and Context.firstHandshake.payload:byte(5) == Context.DirectTransport.VERSION
        and Context.firstHandshake.payload:byte(6) == Context.DirectTransport.TYPE_HANDSHAKE)

    Context.reorderedNetwork = Context.fakeNetwork()
    Context.reorderedHostFactory = Context.newSecureFactory(Context.reorderedNetwork)
    Context.reorderedClientFactory, Context.reorderedClientCrypto =
        Context.newSecureFactory(Context.reorderedNetwork)
    Context.reorderedHost = Context.reorderedHostFactory.createHost({ channels = 3 })
    Context.reorderedClient = Context.reorderedClientFactory.createClient(
        "direct.example:22122", { channels = 3 })
    Context.reorderedPeer = Context.reorderedClient.base.peer
    Context.reorderedHost:service(8)
    Context.reorderedClient:service(8)
    Context.reorderedHost:service(8)
    Context.reorderedClient:service(8)
    Context.reorderedHostEvents = Context.reorderedHost:service(8)
    Context.earlySent = Context.reorderedHost:send(Context.reorderedPeer, "early-host-data", 2, true)
    Context.inbound = Context.reorderedClient.base.inbound
    Context.inbound[#Context.inbound - 1], Context.inbound[#Context.inbound] = Context.inbound[#Context.inbound], Context.inbound[#Context.inbound - 1]
    Context.reorderedClientEvents = Context.reorderedClient:service(8)
    Context.reorderedOpen = Context.lastCall(Context.reorderedClientCrypto, "open")
    Context.reorderedConnectIndex = Context.eventIndex(Context.reorderedClientEvents, "connect")
    Context.reorderedReceiveIndex = Context.eventIndex(
        Context.reorderedClientEvents, "receive", "early-host-data")
    Context.check("direct_transport_bounds_and_releases_data_that_overtakes_final_ack",
        Context.containsEvent(Context.reorderedHostEvents, "connect") ~= nil
        and Context.earlySent
        and Context.containsEvent(Context.reorderedClientEvents, "connect") ~= nil
        and Context.containsEvent(Context.reorderedClientEvents, "receive", "early-host-data") ~= nil
        and Context.reorderedConnectIndex and Context.reorderedReceiveIndex
        and Context.reorderedConnectIndex < Context.reorderedReceiveIndex
        and not Context.containsEvent(Context.reorderedClientEvents, "disconnect")
        and Context.reorderedOpen and Context.reorderedOpen.ready == true
        and #Context.reorderedClient._peerStates[Context.reorderedPeer].pendingData == 0)
    Context.reorderedClient:close()
    Context.reorderedHost:close()
    Context.checkClientHoldingAreaFailureModes(Context.check)

    Context.sentMotion, Context.motionError = Context.session.client:sendToServer("motion", 2, false)
    Context.motionWire = Context.session.network.sends[#Context.session.network.sends]
    Context.motionEvents = Context.session.host:service(8)
    Context.motionReceive = Context.containsEvent(Context.motionEvents, "receive", "motion")
    Context.expectedStateAad = Context.DirectTransport.aadForChannel(2)
    Context.lastSeal = Context.lastCall(Context.session.clientCrypto, "seal")
    Context.lastOpen = Context.lastCall(Context.session.hostCrypto, "open")
    Context.check("direct_transport_encrypts_data_and_preserves_channel_and_delivery",
        Context.sentMotion and Context.motionError == nil and Context.motionReceive
        and Context.motionReceive.channel == 2
        and Context.motionWire.channel == 2 and not Context.motionWire.reliable
        and Context.motionWire.payload ~= "motion"
        and Context.motionWire.payload:byte(6) == Context.DirectTransport.TYPE_DATA
        and Context.lastSeal and Context.lastSeal.aad == Context.expectedStateAad
        and Context.lastOpen and Context.lastOpen.aad == Context.expectedStateAad)

    Context.sentDurable = Context.session.host:send(Context.session.peer, "durable",
        { channel = 2, reliable = true })
    Context.durableWire = Context.session.network.sends[#Context.session.network.sends]
    Context.durableEvents = Context.session.client:service(8)
    Context.check("direct_transport_preserves_reliable_application_delivery_on_durable_channel_two",
        Context.DirectTransport.DURABLE_CHANNEL == 2
        and Context.sentDurable and Context.durableWire.channel == 2 and Context.durableWire.reliable
        and Context.containsEvent(Context.durableEvents, "receive", "durable") ~= nil)

    Context.session.network:injectHostDisconnect(Context.session.peer, 9)
    Context.disconnectEvents = Context.session.host:service(8)
    Context.check("direct_transport_emits_disconnect_only_for_an_authenticated_peer",
        Context.containsEvent(Context.disconnectEvents, "disconnect") ~= nil
        and Context.containsEvent(Context.disconnectEvents, "disconnect").code == 9
        and Context.session.host._peerStates[Context.session.peer] == nil)
    Context.session.client:close()
    Context.session.host:close()

    Context.wrongKey = Context.establishSingle(Context.SHARED_KEY, string.rep("w", Context.DirectTransport.KEY_BYTES))
    Context.check("direct_transport_rejects_a_peer_with_the_wrong_shared_key",
        Context.wrongKey.hostReady and #Context.wrongKey.hostReady == 0
        and Context.containsEvent(Context.wrongKey.clientBefore, "connect") == nil
        and Context.containsEvent(Context.wrongKey.clientReady, "connect") == nil
        and (Context.containsEvent(Context.wrongKey.clientBefore, "disconnect") ~= nil
            or Context.containsEvent(Context.wrongKey.clientReady, "disconnect") ~= nil)
        and #Context.wrongKey.network.disconnects >= 1
        and Context.wrongKey.network.disconnects[1].code == Context.DirectTransport.DISCONNECT_AUTHENTICATION
        and #Context.wrongKey.hostCrypto.states == 0
        and next(Context.wrongKey.host._readyPeers) == nil)
end

return Component
