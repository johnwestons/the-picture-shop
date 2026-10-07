-- Base transport wrapping and direct factory configuration.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.wrapBase(base, mode, config, createOptions)
        if type(base) ~= "table" then return nil, "The base transport did not create an instance." end
        for _, method in ipairs({ "poll", "send", "disconnect", "close" }) do
            if type(base[method]) ~= "function" then
                return nil, "The base transport instance must implement " .. method .. "."
            end
        end
        local channels = Runtime.wholeNumber(base.channels or (createOptions and createOptions.channels)
            or Runtime.DirectTransport.DEFAULT_CHANNELS, 1, 255)
        if not channels then return nil, "Direct transport channel count must be between 1 and 255." end
        local baseMaxGuests = Runtime.wholeNumber(base.maxGuests, 1,
            Runtime.DirectTransport.DEFAULT_MAX_READY_PEERS)
        local maxReadyPeers = math.min(config.maxReadyPeers,
            baseMaxGuests or config.maxReadyPeers)
        return setmetatable({
            mode = mode,
            endpoint = base.endpoint,
            channels = channels,
            maxGuests = base.maxGuests,
            peerCapacity = base.peerCapacity,
            base = base,
            cryptoProvider = config.cryptoProvider,
            _key = config.key,
            admissionToken = config.admissionToken,
            clock = config.clock,
            handshakeTimeout = config.handshakeTimeout,
            maxHandshakeBytes = config.maxHandshakeBytes,
            maxHandshakeFrames = config.maxHandshakeFrames,
            maxHandshakeTotalBytes = config.maxHandshakeTotalBytes,
            maxPreReadyDataFrames = config.maxPreReadyDataFrames,
            maxPreReadyDataBytes = config.maxPreReadyDataBytes,
            maxPendingPeers = config.maxPendingPeers,
            admissionBurst = config.admissionBurst,
            admissionRefillSeconds = config.admissionRefillSeconds,
            maxReadyPeers = maxReadyPeers,
            maxRealtimePlaintextBytes = config.maxRealtimePlaintextBytes,
            maxPlaintextBytes = config.maxPlaintextBytes,
            maxCiphertextOverheadBytes = config.maxCiphertextOverheadBytes,
            maxWireBytes = config.maxWireBytes,
            peer = nil,
            closed = false,
            _serverPeer = mode == "client" and base.peer or nil,
            _peerStates = {},
            _readyPeers = {},
            _events = {},
            _admissionTokens = config.admissionBurst,
            _admissionLastRefill = nil,
            _lastClock = nil,
            _clockFailed = false,
        }, Runtime.Instance)
    end

    function Runtime.DirectTransport.newFactory(options)
        options = options or {}
        if type(options.baseFactory) ~= "table"
            or type(options.baseFactory.createHost) ~= "function"
            or type(options.baseFactory.createClient) ~= "function"
        then
            return nil, "Direct Internet Play requires a base transport factory."
        end
        local baseFactory = options.baseFactory
        local provider, providerError = Runtime.validateProvider(options.cryptoProvider)
        if not provider then return nil, providerError end
        if type(options.key) ~= "string" or #options.key ~= Runtime.DirectTransport.KEY_BYTES then
            return nil, "Direct Internet Play requires a 32-byte shared key."
        end
        local admissionToken, admissionTokenError = Runtime.DirectTransport.admissionToken(
            provider, options.key)
        if admissionToken == nil then return nil, admissionTokenError end
        local clock = options.clock or Runtime.defaultClock
        if type(clock) ~= "function" then return nil, "Direct transport clock must be a function." end
        local handshakeTimeout = Runtime.finiteNumber(options.handshakeTimeout
            or Runtime.DirectTransport.DEFAULT_HANDSHAKE_TIMEOUT, 0, 120)
        if not handshakeTimeout or handshakeTimeout <= 0 then
            return nil, "Direct handshake timeout must be greater than zero and at most 120 seconds."
        end
        local maxHandshakeBytes = Runtime.wholeNumber(options.maxHandshakeBytes
            or Runtime.DirectTransport.DEFAULT_MAX_HANDSHAKE_BYTES, 1, 65535)
        local maxHandshakeFrames = Runtime.wholeNumber(options.maxHandshakeFrames
            or Runtime.DirectTransport.DEFAULT_MAX_HANDSHAKE_FRAMES, 1, 16)
        local maxHandshakeTotalBytes = Runtime.wholeNumber(options.maxHandshakeTotalBytes
            or Runtime.DirectTransport.DEFAULT_MAX_HANDSHAKE_TOTAL_BYTES, 1, 65535)
        local maxPreReadyDataFrames = Runtime.wholeNumber(options.maxPreReadyDataFrames
            or Runtime.DirectTransport.DEFAULT_MAX_PRE_READY_DATA_FRAMES, 1, 16)
        local maxPlaintextBytes = Runtime.wholeNumber(options.maxPlaintextBytes
            or Runtime.DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES, 1, 1024 * 1024)
        local maxRealtimePlaintextBytes = Runtime.wholeNumber(options.maxRealtimePlaintextBytes
            or math.min(Runtime.DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES,
                maxPlaintextBytes or Runtime.DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES),
            1, maxPlaintextBytes or Runtime.DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES)
        local maxCiphertextOverheadBytes = Runtime.wholeNumber(options.maxCiphertextOverheadBytes
            or Runtime.DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES, 16, 4096)
        local peerCapacity = Runtime.wholeNumber(options.peerCapacity
            or Runtime.DirectTransport.DEFAULT_PEER_CAPACITY, 4, 16)
        local maxReadyPeers = Runtime.wholeNumber(options.maxReadyPeers
            or Runtime.DirectTransport.DEFAULT_MAX_READY_PEERS, 1,
            Runtime.DirectTransport.DEFAULT_MAX_READY_PEERS)
        local maxPendingPeers = peerCapacity and Runtime.wholeNumber(options.maxPendingPeers
            or Runtime.DirectTransport.DEFAULT_MAX_PENDING_PEERS, 1,
            peerCapacity - (maxReadyPeers or Runtime.DirectTransport.DEFAULT_MAX_READY_PEERS)) or nil
        local admissionBurst = peerCapacity and Runtime.wholeNumber(options.admissionBurst
            or Runtime.DirectTransport.DEFAULT_ADMISSION_BURST, 1, peerCapacity) or nil
        local admissionRefillSeconds = Runtime.finiteNumber(options.admissionRefillSeconds
            or Runtime.DirectTransport.DEFAULT_ADMISSION_REFILL_SECONDS, 0.001, 3600)
        local maxWireBytes = Runtime.wholeNumber(options.maxWireBytes
            or Runtime.DirectTransport.DEFAULT_MAX_WIRE_BYTES,
            Runtime.DirectTransport.HEADER_BYTES + 1, 2 * 1024 * 1024)
        local defaultPreReadyBytes = maxWireBytes and maxPreReadyDataFrames
            and math.min(4 * 1024 * 1024,
                maxWireBytes * maxPreReadyDataFrames,
                Runtime.DirectTransport.DEFAULT_MAX_PRE_READY_DATA_BYTES)
            or Runtime.DirectTransport.DEFAULT_MAX_PRE_READY_DATA_BYTES
        local maxPreReadyDataBytes = Runtime.wholeNumber(options.maxPreReadyDataBytes
            or defaultPreReadyBytes, 1, 4 * 1024 * 1024)
        if not maxHandshakeBytes then return nil, "Direct handshake byte limit is invalid." end
        if not maxHandshakeFrames then return nil, "Direct handshake frame limit is invalid." end
        if not maxHandshakeTotalBytes then return nil, "Direct handshake total-byte limit is invalid." end
        if not maxPreReadyDataFrames or not maxPreReadyDataBytes then
            return nil, "Direct pre-ready data limits are invalid."
        end
        if not maxPlaintextBytes then return nil, "Direct plaintext byte limit is invalid." end
        if not maxRealtimePlaintextBytes then
            return nil, "Direct realtime plaintext byte limit is invalid."
        end
        if not maxCiphertextOverheadBytes then
            return nil, "Direct ciphertext overhead limit is invalid."
        end
        if not peerCapacity or not maxReadyPeers or not maxPendingPeers then
            return nil, "Direct peer capacity must reserve room for authenticated guests."
        end
        if not admissionBurst or not admissionRefillSeconds then
            return nil, "Direct admission rate limits are invalid."
        end
        if not maxWireBytes then return nil, "Direct wire byte limit is invalid." end
        if maxWireBytes < Runtime.DirectTransport.HEADER_BYTES + maxHandshakeBytes then
            return nil, "Direct wire byte limit cannot contain the configured handshake limit."
        end
        if maxWireBytes < Runtime.DirectTransport.HEADER_BYTES + maxPlaintextBytes then
            return nil, "Direct wire byte limit cannot contain the configured plaintext limit."
        end

        local config = {
            cryptoProvider = provider,
            key = options.key,
            admissionToken = admissionToken,
            clock = clock,
            handshakeTimeout = handshakeTimeout,
            maxHandshakeBytes = maxHandshakeBytes,
            maxHandshakeFrames = maxHandshakeFrames,
            maxHandshakeTotalBytes = maxHandshakeTotalBytes,
            maxPreReadyDataFrames = maxPreReadyDataFrames,
            maxPreReadyDataBytes = maxPreReadyDataBytes,
            maxPendingPeers = maxPendingPeers,
            admissionBurst = admissionBurst,
            admissionRefillSeconds = admissionRefillSeconds,
            maxReadyPeers = maxReadyPeers,
            maxRealtimePlaintextBytes = maxRealtimePlaintextBytes,
            maxPlaintextBytes = maxPlaintextBytes,
            maxCiphertextOverheadBytes = maxCiphertextOverheadBytes,
            maxWireBytes = maxWireBytes,
            peerCapacity = peerCapacity,
        }
        local factory = {
            DEFAULT_PORT = baseFactory.DEFAULT_PORT,
            MAX_GUESTS = baseFactory.MAX_GUESTS,
            MAX_PEERS = baseFactory.MAX_PEERS,
            MIN_CHANNELS = baseFactory.MIN_CHANNELS,
            DEFAULT_CHANNELS = baseFactory.DEFAULT_CHANNELS,
        }
        local created = false

        local function disposeFactory()
            if created then return true end
            created = true
            config.key = nil
            config.admissionToken = nil
            config.cryptoProvider = nil
            return true
        end

        function factory.close()
            return disposeFactory()
        end

        factory.dispose = factory.close

        function factory.createHost(createOptions)
            if created then return nil, "A Direct transport factory creates only one session." end
            createOptions = createOptions or {}
            local forwarded = {}
            for name, value in pairs(createOptions) do forwarded[name] = value end
            forwarded.peerCapacity = config.peerCapacity
            local ok, base, errorMessage = Runtime.callFactory(baseFactory, "createHost", forwarded)
            if not ok then
                disposeFactory()
                return nil, "Base host creation failed: " .. tostring(base)
            end
            if not base then disposeFactory(); return nil, errorMessage end
            local wrapped, wrapError = Runtime.wrapBase(base, "host", config, forwarded)
            if not wrapped then
                Runtime.callMethod(base, "close", Runtime.DirectTransport.DISCONNECT_INTERNAL, true)
                disposeFactory()
                return nil, wrapError
            end
            created = true
            config.key = nil
            return wrapped
        end

        function factory.createClient(address, createOptions)
            if created then return nil, "A Direct transport factory creates only one session." end
            createOptions = createOptions or {}
            local forwarded = {}
            for name, value in pairs(createOptions) do forwarded[name] = value end
            forwarded.connectData = config.admissionToken
            local ok, base, errorMessage = Runtime.callFactory(baseFactory,
                "createClient", address, forwarded)
            if not ok then
                disposeFactory()
                return nil, "Base client creation failed: " .. tostring(base)
            end
            if not base then disposeFactory(); return nil, errorMessage end
            local wrapped, wrapError = Runtime.wrapBase(base, "client", config, forwarded)
            if not wrapped then
                Runtime.callMethod(base, "close", Runtime.DirectTransport.DISCONNECT_INTERNAL, true)
                disposeFactory()
                return nil, wrapError
            end
            created = true
            config.key = nil
            return wrapped
        end

        return factory
    end

    Runtime.DirectTransport.Instance = Runtime.Instance
end

return Component
