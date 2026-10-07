-- Direct transport cryptographic and lifecycle regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.preAuthPeer = Context.preAuthClient.base.peer
    Context.preAuthHost:service(8)
    Context.openBeforePreAuth = Context.countCalls(Context.preAuthHostCrypto, "open")
    Context.preAuthNetwork:injectHost(Context.preAuthPeer,
        Context.directFrame(Context.DirectTransport.TYPE_DATA,
            string.rep("x", Context.DirectTransport.DEFAULT_MAX_HANDSHAKE_BYTES + 1)),
        2, false)
    Context.preAuthHost:service(8)
    Context.check("direct_transport_rejects_large_pre_auth_data_before_crypto_open",
        Context.countCalls(Context.preAuthHostCrypto, "open") == Context.openBeforePreAuth
        and Context.preAuthHost._peerStates[Context.preAuthPeer] == nil)
    Context.preAuthClient:close()
    Context.preAuthHost:close()

    Context.inboundCap = Context.establishSingle()
    Context.openBeforeInboundCap = Context.countCalls(Context.inboundCap.hostCrypto, "open")
    Context.inboundCap.network:injectHost(Context.inboundCap.peer,
        Context.directFrame(Context.DirectTransport.TYPE_DATA,
            string.rep("x", Context.DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES
                + Context.DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES + 1)),
        2, false)
    Context.inboundCapEvents = Context.inboundCap.host:service(8)
    Context.check("direct_transport_caps_guest_wire_data_before_host_crypto_open",
        Context.countCalls(Context.inboundCap.hostCrypto, "open") == Context.openBeforeInboundCap
        and Context.containsEvent(Context.inboundCapEvents, "disconnect") ~= nil)
    Context.inboundCap.client:close()
    Context.inboundCap.host:close()

    Context.secretError = "provider-error-" .. Context.hexEncode(Context.SHARED_KEY)
    Context.errorProvider = {
        productionReady = true,
        admissionToken = Context.fakeAdmissionToken,
        newInitiator = function() error(Context.secretError) end,
        newResponder = function() error(Context.secretError) end,
    }
    Context.errorNetwork = Context.fakeNetwork()
    Context.errorHostFactory = Context.DirectTransport.newFactory({
        baseFactory = Context.errorNetwork.factory,
        cryptoProvider = Context.errorProvider,
        key = Context.SHARED_KEY,
    })
    Context.errorClientFactory = Context.newSecureFactory(Context.errorNetwork)
    Context.errorHost = Context.errorHostFactory.createHost({ channels = 3 })
    Context.errorClient = Context.errorClientFactory.createClient(
        "direct.example:22122", { channels = 3 })
    Context.errorHost:service(8)
    Context.check("direct_transport_crypto_exceptions_never_echo_shared_key_material",
        type(Context.errorHost.lastError) == "string"
        and Context.errorHost.lastError:find(Context.secretError, 1, true) == nil
        and Context.errorHost.lastError:find(Context.hexEncode(Context.SHARED_KEY), 1, true) == nil)
    Context.errorClient:close()
    Context.errorHost:close()

    Context.frameLimitNetwork = Context.fakeNetwork()
    Context.frameLimitLog = { handshakes = 0, bytes = 0 }
    Context.frameLimitFactory = Context.DirectTransport.newFactory({
        baseFactory = Context.frameLimitNetwork.factory,
        cryptoProvider = Context.stallingCryptoProvider(Context.frameLimitLog),
        key = Context.SHARED_KEY,
        maxHandshakeFrames = 2,
        maxHandshakeTotalBytes = 100,
    })
    Context.frameLimitHost = Context.frameLimitFactory.createHost({ channels = 3 })
    Context.frameLimitClient = Context.frameLimitNetwork.factory.createClient(
        "direct.example:22122", {
            channels = 3,
            connectData = Context.fakeAdmissionToken(Context.SHARED_KEY),
        })
    Context.frameLimitPeer = Context.frameLimitClient.peer
    Context.frameLimitHost:service(8)
    for _ = 1, 3 do
        Context.frameLimitNetwork:injectHost(Context.frameLimitPeer,
            Context.directFrame(Context.DirectTransport.TYPE_HANDSHAKE, "aa"), 0, true)
    end
    Context.frameLimitHost:service(8)
    Context.check("direct_transport_caps_pre_auth_handshake_frame_count",
        Context.frameLimitLog.handshakes == 2
        and Context.frameLimitHost._peerStates[Context.frameLimitPeer] == nil)
    Context.frameLimitClient:close()
    Context.frameLimitHost:close()

    Context.byteLimitNetwork = Context.fakeNetwork()
    Context.byteLimitLog = { handshakes = 0, bytes = 0 }
    Context.byteLimitFactory = Context.DirectTransport.newFactory({
        baseFactory = Context.byteLimitNetwork.factory,
        cryptoProvider = Context.stallingCryptoProvider(Context.byteLimitLog),
        key = Context.SHARED_KEY,
        maxHandshakeFrames = 4,
        maxHandshakeTotalBytes = 4,
    })
    Context.byteLimitHost = Context.byteLimitFactory.createHost({ channels = 3 })
    Context.byteLimitClient = Context.byteLimitNetwork.factory.createClient(
        "direct.example:22122", {
            channels = 3,
            connectData = Context.fakeAdmissionToken(Context.SHARED_KEY),
        })
    Context.byteLimitPeer = Context.byteLimitClient.peer
    Context.byteLimitHost:service(8)
    Context.byteLimitNetwork:injectHost(Context.byteLimitPeer,
        Context.directFrame(Context.DirectTransport.TYPE_HANDSHAKE, "abc"), 0, true)
    Context.byteLimitNetwork:injectHost(Context.byteLimitPeer,
        Context.directFrame(Context.DirectTransport.TYPE_HANDSHAKE, "de"), 0, true)
    Context.byteLimitHost:service(8)
    Context.check("direct_transport_caps_aggregate_pre_auth_handshake_bytes",
        Context.byteLimitLog.handshakes == 1 and Context.byteLimitLog.bytes == 3
        and Context.byteLimitHost._peerStates[Context.byteLimitPeer] == nil)
    Context.byteLimitClient:close()
    Context.byteLimitHost:close()

    Context.budgetNetwork = Context.fakeNetwork()
    Context.budgetFactory = Context.newSecureFactory(Context.budgetNetwork)
    Context.budgetHost = Context.budgetFactory.createHost({ channels = 3 })
    for index = 1, 100 do
        Context.budgetNetwork.host.inbound[#Context.budgetNetwork.host.inbound + 1] = {
            type = "receive",
            peer = { id = "raw-budget-" .. tostring(index) },
            data = "not-a-direct-frame",
            channel = 0,
        }
    end
    Context.budgetHost:service(64)
    Context.check("direct_transport_service_shares_one_bounded_raw_event_budget",
        #Context.budgetNetwork.host.inbound == 100 - Context.DirectTransport.MAX_EVENTS_PER_SERVICE)
    Context.budgetHost:close()

    Context.disposedNetwork = Context.fakeNetwork()
    Context.disposedFactory = Context.newSecureFactory(Context.disposedNetwork)
    Context.disposed, Context.disposeError = Context.disposedFactory.close()
    Context.disposedAgain, Context.disposeAgainError = Context.disposedFactory.close()
    Context.createAfterDispose = Context.disposedFactory.createHost({ channels = 3 })
    Context.check("direct_transport_factory_dispose_is_idempotent_and_one_session_scoped",
        Context.disposed and not Context.disposeError and Context.disposedAgain and not Context.disposeAgainError
        and Context.createAfterDispose == nil)

    Context.stickyNetwork = Context.fakeNetwork()
    Context.stickyFactory = Context.newSecureFactory(Context.stickyNetwork)
    Context.stickyHost = Context.stickyFactory.createHost({ channels = 3 })
    Context.stickyHost.base.close = function() return false, "injected close failure" end
    Context.stickyClosed, Context.stickyError = Context.stickyHost:close()
    Context.stickyClosedAgain, Context.stickyErrorAgain = Context.stickyHost:close()
    Context.check("direct_transport_repeated_close_never_upgrades_unverified_cleanup",
        Context.stickyClosed == false and type(Context.stickyError) == "string"
        and Context.stickyClosedAgain == false and Context.stickyErrorAgain == Context.stickyError)
end

return Component
