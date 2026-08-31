-- LuaJIT FFI adapter for the native Direct Internet Play cryptographic
-- candidate.  Loading this module is always safe: a missing FFI runtime or
-- native library leaves a fail-closed provider table instead of raising.
--
-- This adapter deliberately remains an engineering candidate.  Promoting it
-- to productionReady requires independent review of the native implementation,
-- its pinned dependencies, and its release binaries.
local Provider = {
    name = "TPS native crypto",
    expectedAbiVersion = 3,
    expectedSuite = "TPS-Direct-v3/Noise_NNpsk0_25519_ChaChaPoly_BLAKE2s/"
        .. "XChaCha20-Poly1305",
    available = false,
    engineeringReady = false,
    candidateReady = false,
    engineeringOnly = true,
    productionReady = false,
    readiness = "unavailable",
    loadError = "Native cryptographic provider is unavailable.",
}

local ABI_VERSION = 3
local KEY_BYTES = 32
local RESPONSE_TRANSCRIPT_BYTES = 120
local RESPONSE_TAG_BYTES = 32
local INVITATION_ID_BYTES = 16
local GUEST_NONCE_BYTES = 16
local OPENING_PACKET_BYTES = 92
local BRIDGE_MAX_AAD_BYTES = 64
local BRIDGE_MAX_PLAINTEXT_BYTES = 1176
local BRIDGE_OVERHEAD_BYTES = 24
local HANDSHAKE_MAX_BYTES = 256
local DATA_OVERHEAD_BYTES = 24
-- Match DirectTransport's configurable upper bound; the default is lower.
local MAX_DATA_BYTES = 1024 * 1024
local ROLE_INITIATOR = 1
local ROLE_RESPONDER = 2
local OPENING_ROLE_HOST = 1
local OPENING_ROLE_GUEST = 2
local BRIDGE_ROLE_HOST = 1
local BRIDGE_ROLE_GUEST = 2
local OK = 0
local ERR_AUTH = -3
local ERR_REPLAY = -5
local ERR_PROTOCOL = -6
local DATA_AAD_PREFIX = "TPSD" .. string.char(1, 2)
local DATA_AAD_BYTES = #DATA_AAD_PREFIX + 1

local EXPECTED_SUITE = Provider.expectedSuite

local ffi
local nativeLibrary
local stateFinalizer
local openingStateFinalizer
local bridgeStateFinalizer
local State = {}
State.__index = State
local OpeningState = {}
OpeningState.__index = OpeningState
local BridgeState = {}
BridgeState.__index = BridgeState

local function unavailable()
    return nil, "Native cryptographic provider is unavailable."
end

local function failLoad(message)
    Provider.available = false
    Provider.engineeringReady = false
    Provider.candidateReady = false
    Provider.productionReady = false
    Provider.readiness = "unavailable"
    Provider.loadError = message or "Native cryptographic provider is unavailable."
    return false
end

local function addUnique(values, seen, value)
    if type(value) ~= "string" or value == "" or seen[value] then return end
    seen[value] = true
    values[#values + 1] = value
end

local function directoryName(path)
    if type(path) ~= "string" then return nil end
    return path:match("^(.*)[/\\][^/\\]+$")
end

local function joinPath(root, relative)
    if type(root) ~= "string" or root == "" then return relative end
    local separator = package.config:sub(1, 1)
    relative = relative:gsub("[/\\]", separator)
    if root:sub(-1) == "/" or root:sub(-1) == "\\" then
        return root .. relative
    end
    return root .. separator .. relative
end

local function sourceRoots()
    local roots, seen = {}, {}

    if love and love.filesystem then
        local filesystem = love.filesystem
        if type(filesystem.getSource) == "function" then
            local ok, source = pcall(filesystem.getSource)
            if ok and type(source) == "string" then
                if source:lower():sub(-5) == ".love" then
                    source = directoryName(source)
                end
                addUnique(roots, seen, source)
            end
        end
        if type(filesystem.getSourceBaseDirectory) == "function" then
            local ok, base = pcall(filesystem.getSourceBaseDirectory)
            if ok then addUnique(roots, seen, base) end
        end
    end

    if debug and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, 1, "S")
        local source = ok and info and info.source or nil
        if type(source) == "string" and source:sub(1, 1) == "@" then
            source = source:sub(2)
            local root = source:match("^(.*)[/\\]src[/\\]net[/\\]crypto_native%.lua$")
            if not root and source:match("^src[/\\]net[/\\]crypto_native%.lua$") then
                root = "."
            end
            addUnique(roots, seen, root)
        end
    end

    return roots
end

local function detectedOS()
    if love and love.system and type(love.system.getOS) == "function" then
        local ok, operatingSystem = pcall(love.system.getOS)
        if ok and type(operatingSystem) == "string" then return operatingSystem end
    end
    return ffi and ffi.os or nil
end

local function libraryCandidates()
    local candidates, seen = {}, {}
    local override
    if os and type(os.getenv) == "function" then
        local ok, configured = pcall(os.getenv, "TPS_CRYPTO_LIBRARY")
        if ok and type(configured) == "string" then
            configured = configured:match("^%s*(.-)%s*$")
            if configured ~= "" then override = configured end
        end
    end

    -- An explicit override is authoritative so a typo cannot silently select a
    -- different binary from the process search path.
    if override then
        addUnique(candidates, seen, override)
        return candidates
    end

    local operatingSystem = detectedOS()
    if operatingSystem == "Windows" then
        for _, root in ipairs(sourceRoots()) do
            addUnique(candidates, seen, joinPath(root, "tps_crypto.dll"))
            addUnique(candidates, seen, joinPath(root, "native/crypto/tps_crypto.dll"))
            addUnique(candidates, seen,
                joinPath(root, "output/native-crypto/tps_crypto.dll"))
            addUnique(candidates, seen,
                joinPath(root, "output/native-crypto/windows-x64/tps_crypto.dll"))
            addUnique(candidates, seen,
                joinPath(root, "output/native-crypto/build/windows-x64/tps_crypto.dll"))
            addUnique(candidates, seen,
                joinPath(root,
                    "output/native-crypto/build/windows-x64/Release/tps_crypto.dll"))
            addUnique(candidates, seen,
                joinPath(root,
                    "output/native-crypto/build/windows-x64/Debug/tps_crypto.dll"))
        end
    elseif operatingSystem == "Android" then
        addUnique(candidates, seen, "tps_crypto")
    else
        addUnique(candidates, seen, "tps_crypto")
    end
    return candidates
end

local function bindLibrary()
    local ffiOk, ffiModule = pcall(require, "ffi")
    if not ffiOk or type(ffiModule) ~= "table" then
        return failLoad("LuaJIT FFI is unavailable.")
    end
    ffi = ffiModule

    local cdefOk = pcall(ffi.cdef, [[
        struct tps_crypto_state;
        struct tps_crypto_opening_state;
        struct tps_crypto_bridge_state;

        uint32_t tps_crypto_abi_version(void);
        const char *tps_crypto_suite(void);
        int32_t tps_crypto_init(void);
        int32_t tps_crypto_self_test(void);
        int32_t tps_crypto_random(uint8_t *out, size_t out_len);
        int32_t tps_crypto_admission_token(
            const uint8_t key[32], uint32_t *out_token);
        int32_t tps_crypto_response_tag(
            const uint8_t key[32],
            const uint8_t transcript[120],
            uint8_t out_tag[32]);
        int32_t tps_crypto_response_verify(
            const uint8_t key[32],
            const uint8_t transcript[120],
            const uint8_t tag[32]);

        int32_t tps_crypto_opening_state_new(
            uint32_t role,
            const uint8_t key[32],
            const uint8_t invitation_id[16],
            const uint8_t guest_nonce[16],
            struct tps_crypto_opening_state **out_state);
        int32_t tps_crypto_opening_state_next(
            struct tps_crypto_opening_state *state,
            uint8_t out_packet[92]);
        int32_t tps_crypto_opening_state_receive(
            struct tps_crypto_opening_state *state,
            const uint8_t *input,
            size_t input_len);
        int32_t tps_crypto_opening_state_is_ready(
            const struct tps_crypto_opening_state *state);
        void tps_crypto_opening_state_free(
            struct tps_crypto_opening_state *state);

        int32_t tps_crypto_bridge_state_new(
            uint32_t role,
            const uint8_t key[32],
            const uint8_t invitation_id[16],
            const uint8_t guest_nonce[16],
            struct tps_crypto_bridge_state **out_state);
        int32_t tps_crypto_bridge_state_seal(
            struct tps_crypto_bridge_state *state,
            const uint8_t *aad,
            size_t aad_len,
            const uint8_t *plaintext,
            size_t plaintext_len,
            uint8_t *out,
            size_t out_capacity,
            size_t *out_len);
        int32_t tps_crypto_bridge_state_open(
            struct tps_crypto_bridge_state *state,
            const uint8_t *aad,
            size_t aad_len,
            const uint8_t *ciphertext,
            size_t ciphertext_len,
            uint8_t *out,
            size_t out_capacity,
            size_t *out_len);
        void tps_crypto_bridge_state_free(
            struct tps_crypto_bridge_state *state);

        int32_t tps_crypto_state_new(
            uint32_t role,
            const uint8_t key[32],
            struct tps_crypto_state **out_state);
        int32_t tps_crypto_state_start(
            struct tps_crypto_state *state,
            uint8_t *out,
            size_t out_capacity,
            size_t *out_len);
        int32_t tps_crypto_state_handshake(
            struct tps_crypto_state *state,
            const uint8_t *input,
            size_t input_len,
            uint8_t *out,
            size_t out_capacity,
            size_t *out_len);
        int32_t tps_crypto_state_is_ready(
            const struct tps_crypto_state *state);
        int32_t tps_crypto_state_seal(
            struct tps_crypto_state *state,
            uint8_t channel,
            const uint8_t *aad,
            size_t aad_len,
            const uint8_t *plaintext,
            size_t plaintext_len,
            uint8_t *out,
            size_t out_capacity,
            size_t *out_len);
        int32_t tps_crypto_state_open(
            struct tps_crypto_state *state,
            uint8_t channel,
            const uint8_t *aad,
            size_t aad_len,
            const uint8_t *ciphertext,
            size_t ciphertext_len,
            uint8_t *out,
            size_t out_capacity,
            size_t *out_len);
        void tps_crypto_state_free(struct tps_crypto_state *state);
    ]])
    if not cdefOk then return failLoad("Native cryptographic ABI binding failed.") end

    local library
    for _, candidate in ipairs(libraryCandidates()) do
        local loadOk, loaded = pcall(ffi.load, candidate)
        if loadOk and loaded ~= nil then
            library = loaded
            break
        end
    end
    if not library then return failLoad("Native cryptographic library is unavailable.") end

    local requiredSymbols = {
        "tps_crypto_abi_version",
        "tps_crypto_suite",
        "tps_crypto_init",
        "tps_crypto_self_test",
        "tps_crypto_random",
        "tps_crypto_admission_token",
        "tps_crypto_response_tag",
        "tps_crypto_response_verify",
        "tps_crypto_opening_state_new",
        "tps_crypto_opening_state_next",
        "tps_crypto_opening_state_receive",
        "tps_crypto_opening_state_is_ready",
        "tps_crypto_opening_state_free",
        "tps_crypto_bridge_state_new",
        "tps_crypto_bridge_state_seal",
        "tps_crypto_bridge_state_open",
        "tps_crypto_bridge_state_free",
        "tps_crypto_state_new",
        "tps_crypto_state_start",
        "tps_crypto_state_handshake",
        "tps_crypto_state_is_ready",
        "tps_crypto_state_seal",
        "tps_crypto_state_open",
        "tps_crypto_state_free",
    }
    for _, symbol in ipairs(requiredSymbols) do
        local symbolOk, value = pcall(function() return library[symbol] end)
        if not symbolOk or value == nil then
            return failLoad("Native cryptographic ABI is incomplete.")
        end
    end

    local verifyOk, abiVersion, suite, initResult, selfTestResult = pcall(function()
        local version = tonumber(library.tps_crypto_abi_version())
        local suitePointer = library.tps_crypto_suite()
        local suiteName = suitePointer ~= nil and ffi.string(suitePointer) or nil
        local initialized = tonumber(library.tps_crypto_init())
        local selfTested = initialized == OK
            and tonumber(library.tps_crypto_self_test()) or nil
        return version, suiteName, initialized, selfTested
    end)
    if not verifyOk then return failLoad("Native cryptographic verification failed.") end
    if abiVersion ~= ABI_VERSION then
        return failLoad("Native cryptographic ABI version is unsupported.")
    end
    if suite ~= EXPECTED_SUITE then
        return failLoad("Native cryptographic suite is unsupported.")
    end
    if initResult ~= OK then
        return failLoad("Native cryptographic initialization failed.")
    end
    if selfTestResult ~= OK then
        return failLoad("Native cryptographic self-test failed.")
    end

    nativeLibrary = library
    -- Capture this exact verified library handle.  State finalizers must not
    -- depend on a later global lookup or on process DLL search state.
    stateFinalizer = function(pointer)
        library.tps_crypto_state_free(pointer)
    end
    openingStateFinalizer = function(pointer)
        library.tps_crypto_opening_state_free(pointer)
    end
    bridgeStateFinalizer = function(pointer)
        library.tps_crypto_bridge_state_free(pointer)
    end
    Provider.abiVersion = abiVersion
    Provider.suite = suite
    Provider.available = true
    Provider.engineeringReady = true
    Provider.candidateReady = true
    Provider.productionReady = false
    Provider.readiness = "engineering-candidate"
    Provider.loadError = nil
    return true
end

local function readyProvider()
    return ffi ~= nil and nativeLibrary ~= nil and Provider.engineeringReady == true
end

local function validLength(value, minimum, maximum)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function wipe(buffer, length)
    if ffi and buffer ~= nil and length > 0 then pcall(ffi.fill, buffer, length, 0) end
end

local function outputString(buffer, length, capacity)
    length = tonumber(length)
    if not validLength(length, 0, capacity) then
        wipe(buffer, capacity)
        return nil
    end
    local ok, value = pcall(ffi.string, buffer, length)
    wipe(buffer, capacity)
    if not ok then return nil end
    return value
end

local function nativeState(self)
    if type(self) ~= "table" or getmetatable(self) ~= State or self._state == nil then
        return nil
    end
    return self._state
end

local function nativeOpeningState(self)
    if type(self) ~= "table" or getmetatable(self) ~= OpeningState
        or self._state == nil then
        return nil
    end
    return self._state
end

function Provider.randomBytes(count)
    if not readyProvider() then return unavailable() end
    if not validLength(count, 1, MAX_DATA_BYTES) then
        return nil, "Native random byte request is invalid."
    end

    local output = ffi.new("uint8_t[?]", count)
    local ok, result = pcall(nativeLibrary.tps_crypto_random, output, count)
    if not ok or tonumber(result) ~= OK then
        wipe(output, count)
        return nil, "Native random byte generation failed."
    end
    local value = outputString(output, count, count)
    if value == nil then return nil, "Native random byte generation failed." end
    return value
end

function Provider.admissionToken(key)
    if not readyProvider() then return unavailable() end
    if type(key) ~= "string" or #key ~= KEY_BYTES then
        return nil, "Native admission token input is invalid."
    end

    local output = ffi.new("uint32_t[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_admission_token,
        ffi.cast("const uint8_t *", key), output)
    local token = ok and tonumber(output[0]) or nil
    wipe(output, ffi.sizeof(output))
    if not ok or tonumber(result) ~= OK
        or not validLength(token, 0, 2147483647)
    then
        return nil, "Native admission token derivation failed."
    end
    return token
end

function Provider.responseTag(masterKey, transcript)
    if not readyProvider() then return unavailable() end
    if type(masterKey) ~= "string" or #masterKey ~= KEY_BYTES
        or type(transcript) ~= "string"
        or #transcript ~= RESPONSE_TRANSCRIPT_BYTES then
        return nil, "Native response authentication failed."
    end

    local output = ffi.new("uint8_t[?]", RESPONSE_TAG_BYTES)
    local ok, result = pcall(nativeLibrary.tps_crypto_response_tag,
        ffi.cast("const uint8_t *", masterKey),
        ffi.cast("const uint8_t *", transcript), output)
    if not ok or tonumber(result) ~= OK then
        wipe(output, RESPONSE_TAG_BYTES)
        return nil, "Native response authentication failed."
    end
    local value = outputString(output, RESPONSE_TAG_BYTES, RESPONSE_TAG_BYTES)
    if value == nil then return nil, "Native response authentication failed." end
    return value
end

function Provider.verifyResponseTag(masterKey, transcript, tag)
    if not readyProvider() then return unavailable() end
    if type(masterKey) ~= "string" or #masterKey ~= KEY_BYTES
        or type(transcript) ~= "string"
        or #transcript ~= RESPONSE_TRANSCRIPT_BYTES
        or type(tag) ~= "string" or #tag ~= RESPONSE_TAG_BYTES then
        return nil, "Native response authentication failed."
    end

    local ok, result = pcall(nativeLibrary.tps_crypto_response_verify,
        ffi.cast("const uint8_t *", masterKey),
        ffi.cast("const uint8_t *", transcript),
        ffi.cast("const uint8_t *", tag))
    result = ok and tonumber(result) or nil
    if result == OK then return true end
    if result == ERR_AUTH then return false end
    return nil, "Native response authentication failed."
end

local function freeNativePointer(pointer)
    if pointer == nil then return true end
    if stateFinalizer == nil then return false end
    local ok = pcall(stateFinalizer, pointer)
    return ok
end

local function freeOpeningPointer(pointer)
    if pointer == nil then return true end
    if openingStateFinalizer == nil then return false end
    local ok = pcall(openingStateFinalizer, pointer)
    return ok
end

local function newOpeningState(role, masterKey, invitationId, guestNonce)
    if not readyProvider() then return unavailable() end
    if type(masterKey) ~= "string" or #masterKey ~= KEY_BYTES
        or type(invitationId) ~= "string"
        or #invitationId ~= INVITATION_ID_BYTES
        or type(guestNonce) ~= "string"
        or #guestNonce ~= GUEST_NONCE_BYTES then
        return nil, "Native opening state creation failed."
    end

    local output = ffi.new("struct tps_crypto_opening_state *[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_opening_state_new, role,
        ffi.cast("const uint8_t *", masterKey),
        ffi.cast("const uint8_t *", invitationId),
        ffi.cast("const uint8_t *", guestNonce), output)
    local pointer = output[0]
    if not ok or tonumber(result) ~= OK or pointer == nil then
        if pointer ~= nil then freeOpeningPointer(pointer) end
        return nil, "Native opening state creation failed."
    end

    local gcOk, managedPointer = pcall(ffi.gc, pointer, openingStateFinalizer)
    if not gcOk then
        freeOpeningPointer(pointer)
        return nil, "Native opening state creation failed."
    end
    return setmetatable({ _state = managedPointer }, OpeningState)
end

function Provider.newOpeningHost(masterKey, invitationId, guestNonce)
    return newOpeningState(
        OPENING_ROLE_HOST, masterKey, invitationId, guestNonce)
end

function Provider.newOpeningGuest(masterKey, invitationId, guestNonce)
    return newOpeningState(
        OPENING_ROLE_GUEST, masterKey, invitationId, guestNonce)
end

function OpeningState:next()
    local pointer = nativeOpeningState(self)
    if pointer == nil then return nil, "Native opening state is unavailable." end

    local output = ffi.new("uint8_t[?]", OPENING_PACKET_BYTES)
    local ok, result = pcall(
        nativeLibrary.tps_crypto_opening_state_next, pointer, output)
    if not ok or tonumber(result) ~= OK then
        wipe(output, OPENING_PACKET_BYTES)
        return nil, "Native opening packet generation failed."
    end
    local value = outputString(output, OPENING_PACKET_BYTES, OPENING_PACKET_BYTES)
    if value == nil then return nil, "Native opening packet generation failed." end
    return value
end

function OpeningState:receive(packet)
    local pointer = nativeOpeningState(self)
    if pointer == nil then return nil, "Native opening state is unavailable." end
    if type(packet) ~= "string" or #packet ~= OPENING_PACKET_BYTES then
        return false
    end

    local ok, result = pcall(nativeLibrary.tps_crypto_opening_state_receive,
        pointer, ffi.cast("const uint8_t *", packet), #packet)
    result = ok and tonumber(result) or nil
    if result == OK then return true end
    if result == ERR_AUTH or result == ERR_REPLAY or result == ERR_PROTOCOL then
        return false
    end
    return nil, "Native opening packet processing failed."
end

function OpeningState:isReady()
    local pointer = nativeOpeningState(self)
    if pointer == nil then return nil, "Native opening state is unavailable." end

    local ok, result = pcall(
        nativeLibrary.tps_crypto_opening_state_is_ready, pointer)
    result = ok and tonumber(result) or nil
    if result == 0 then return false end
    if result == 1 then return true end
    return nil, "Native opening readiness check failed."
end

function OpeningState:close()
    local pointer = nativeOpeningState(self)
    if pointer == nil then return true end

    local detachOk, detached = pcall(ffi.gc, pointer, nil)
    if not detachOk then return false, "Native opening state cleanup failed." end
    if not freeOpeningPointer(detached) then
        local attachOk, managed = pcall(
            ffi.gc, detached, openingStateFinalizer)
        self._state = attachOk and managed or detached
        return false, "Native opening state cleanup failed."
    end
    self._state = nil
    return true
end

OpeningState.free = OpeningState.close

local function nativeBridgeState(self)
    if type(self) ~= "table" or getmetatable(self) ~= BridgeState
        or self._state == nil then
        return nil
    end
    return self._state
end

local function freeBridgePointer(pointer)
    if pointer == nil then return true end
    if bridgeStateFinalizer == nil then return false end
    local ok = pcall(bridgeStateFinalizer, pointer)
    return ok
end

local function newBridgeState(role, masterKey, invitationId, guestNonce)
    if not readyProvider() then return unavailable() end
    if type(masterKey) ~= "string" or #masterKey ~= KEY_BYTES
        or type(invitationId) ~= "string"
        or #invitationId ~= INVITATION_ID_BYTES
        or type(guestNonce) ~= "string"
        or #guestNonce ~= GUEST_NONCE_BYTES then
        return nil, "Native bridge state creation failed."
    end

    local output = ffi.new("struct tps_crypto_bridge_state *[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_bridge_state_new, role,
        ffi.cast("const uint8_t *", masterKey),
        ffi.cast("const uint8_t *", invitationId),
        ffi.cast("const uint8_t *", guestNonce), output)
    local pointer = output[0]
    if not ok or tonumber(result) ~= OK or pointer == nil then
        if pointer ~= nil then freeBridgePointer(pointer) end
        return nil, "Native bridge state creation failed."
    end

    local gcOk, managedPointer = pcall(ffi.gc, pointer, bridgeStateFinalizer)
    if not gcOk then
        freeBridgePointer(pointer)
        return nil, "Native bridge state creation failed."
    end
    return setmetatable({ _state = managedPointer }, BridgeState)
end

function Provider.newBridgeHost(masterKey, invitationId, guestNonce)
    return newBridgeState(
        BRIDGE_ROLE_HOST, masterKey, invitationId, guestNonce)
end

function Provider.newBridgeGuest(masterKey, invitationId, guestNonce)
    return newBridgeState(
        BRIDGE_ROLE_GUEST, masterKey, invitationId, guestNonce)
end

local function validBridgeArguments(payload, aad, maximumPayload)
    return type(payload) == "string" and #payload <= maximumPayload
        and type(aad) == "string" and #aad >= 1
        and #aad <= BRIDGE_MAX_AAD_BYTES
end

function BridgeState:seal(plaintext, aad)
    local pointer = nativeBridgeState(self)
    if pointer == nil then return nil, "Native bridge state is closed." end
    if not validBridgeArguments(
        plaintext, aad, BRIDGE_MAX_PLAINTEXT_BYTES) then
        return nil, "Native bridge encryption input is invalid."
    end

    local capacity = #plaintext + BRIDGE_OVERHEAD_BYTES
    local output = ffi.new("uint8_t[?]", capacity)
    local outputLength = ffi.new("size_t[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_bridge_state_seal,
        pointer, ffi.cast("const uint8_t *", aad), #aad,
        ffi.cast("const uint8_t *", plaintext), #plaintext,
        output, capacity, outputLength)
    if not ok or tonumber(result) ~= OK then
        wipe(output, capacity)
        return nil, "Native bridge encryption failed."
    end
    local value = outputString(output, outputLength[0], capacity)
    if value == nil or #value ~= capacity then
        return nil, "Native bridge encryption failed."
    end
    return value
end

function BridgeState:open(ciphertext, aad)
    local pointer = nativeBridgeState(self)
    if pointer == nil then return nil, "Native bridge state is closed." end
    if not validBridgeArguments(ciphertext, aad,
        BRIDGE_MAX_PLAINTEXT_BYTES + BRIDGE_OVERHEAD_BYTES)
        or #ciphertext < BRIDGE_OVERHEAD_BYTES then
        return nil, "Native bridge authentication input is invalid."
    end

    local capacity = #ciphertext
    local output = ffi.new("uint8_t[?]", capacity)
    local outputLength = ffi.new("size_t[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_bridge_state_open,
        pointer, ffi.cast("const uint8_t *", aad), #aad,
        ffi.cast("const uint8_t *", ciphertext), #ciphertext,
        output, capacity, outputLength)
    result = ok and tonumber(result) or nil
    if result == ERR_AUTH or result == ERR_REPLAY or result == ERR_PROTOCOL then
        wipe(output, capacity)
        return false
    end
    if result ~= OK then
        wipe(output, capacity)
        return nil, "Native bridge authentication failed."
    end
    local value = outputString(output, outputLength[0], capacity)
    if value == nil
        or #value ~= #ciphertext - BRIDGE_OVERHEAD_BYTES then
        return nil, "Native bridge authentication failed."
    end
    return value
end

function BridgeState:close()
    local pointer = nativeBridgeState(self)
    if pointer == nil then return true end

    local detachOk, detached = pcall(ffi.gc, pointer, nil)
    if not detachOk then return false, "Native bridge state cleanup failed." end
    if not freeBridgePointer(detached) then
        local attachOk, managed = pcall(
            ffi.gc, detached, bridgeStateFinalizer)
        self._state = attachOk and managed or detached
        return false, "Native bridge state cleanup failed."
    end
    self._state = nil
    return true
end

BridgeState.free = BridgeState.close

local function newState(role, key)
    if not readyProvider() then return unavailable() end
    if type(key) ~= "string" or #key ~= KEY_BYTES then
        return nil, "Native cryptographic key is invalid."
    end

    local output = ffi.new("struct tps_crypto_state *[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_state_new, role,
        ffi.cast("const uint8_t *", key), output)
    local pointer = output[0]
    if not ok or tonumber(result) ~= OK or pointer == nil then
        if pointer ~= nil then freeNativePointer(pointer) end
        return nil, "Native cryptographic state creation failed."
    end

    local gcOk, managedPointer = pcall(ffi.gc, pointer, stateFinalizer)
    if not gcOk then
        freeNativePointer(pointer)
        return nil, "Native cryptographic state creation failed."
    end
    return setmetatable({ _state = managedPointer }, State)
end

function Provider.newInitiator(key)
    return newState(ROLE_INITIATOR, key)
end

function Provider.newResponder(key)
    return newState(ROLE_RESPONDER, key)
end

function State:start()
    local pointer = nativeState(self)
    if pointer == nil then return nil, "Native cryptographic state is closed." end

    local output = ffi.new("uint8_t[?]", HANDSHAKE_MAX_BYTES)
    local outputLength = ffi.new("size_t[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_state_start, pointer,
        output, HANDSHAKE_MAX_BYTES, outputLength)
    if not ok or tonumber(result) ~= OK then
        wipe(output, HANDSHAKE_MAX_BYTES)
        return nil, "Native cryptographic handshake failed."
    end
    local length = tonumber(outputLength[0])
    local value = outputString(output, length, HANDSHAKE_MAX_BYTES)
    if value == nil then return nil, "Native cryptographic handshake failed." end
    if #value == 0 then return nil end
    return value
end

function State:handshake(message)
    local pointer = nativeState(self)
    if pointer == nil then return nil, "Native cryptographic state is closed." end
    if type(message) ~= "string" or #message == 0
        or #message > HANDSHAKE_MAX_BYTES
    then
        return nil, "Native cryptographic handshake input is invalid."
    end

    local output = ffi.new("uint8_t[?]", HANDSHAKE_MAX_BYTES)
    local outputLength = ffi.new("size_t[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_state_handshake, pointer,
        ffi.cast("const uint8_t *", message), #message,
        output, HANDSHAKE_MAX_BYTES, outputLength)
    if not ok or tonumber(result) ~= OK then
        wipe(output, HANDSHAKE_MAX_BYTES)
        return nil, "Native cryptographic handshake failed."
    end
    local length = tonumber(outputLength[0])
    local value = outputString(output, length, HANDSHAKE_MAX_BYTES)
    if value == nil then return nil, "Native cryptographic handshake failed." end
    if #value == 0 then return nil end
    return value
end

function State:isReady()
    local pointer = nativeState(self)
    if pointer == nil then return nil, "Native cryptographic state is closed." end

    local ok, result = pcall(nativeLibrary.tps_crypto_state_is_ready, pointer)
    result = ok and tonumber(result) or nil
    if result == 0 then return false end
    if result == 1 then return true end
    return nil, "Native cryptographic readiness check failed."
end

local function validateDataArguments(payload, aad, maximumPayload)
    if type(payload) ~= "string" or #payload > maximumPayload then return nil end
    if type(aad) ~= "string" or #aad ~= DATA_AAD_BYTES
        or aad:sub(1, #DATA_AAD_PREFIX) ~= DATA_AAD_PREFIX
    then
        return nil
    end
    local channel = aad:byte(DATA_AAD_BYTES)
    if not channel then return nil end
    return channel
end

function State:seal(plaintext, aad)
    local pointer = nativeState(self)
    if pointer == nil then return nil, "Native cryptographic state is closed." end
    local channel = validateDataArguments(plaintext, aad, MAX_DATA_BYTES)
    if channel == nil then return nil, "Native cryptographic data input is invalid." end

    local capacity = #plaintext + DATA_OVERHEAD_BYTES
    local output = ffi.new("uint8_t[?]", capacity)
    local outputLength = ffi.new("size_t[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_state_seal, pointer, channel,
        ffi.cast("const uint8_t *", aad), #aad,
        ffi.cast("const uint8_t *", plaintext), #plaintext,
        output, capacity, outputLength)
    if not ok or tonumber(result) ~= OK then
        wipe(output, capacity)
        return nil, "Native cryptographic encryption failed."
    end
    local value = outputString(output, outputLength[0], capacity)
    if value == nil or #value ~= capacity then
        return nil, "Native cryptographic encryption failed."
    end
    return value
end

function State:open(ciphertext, aad)
    local pointer = nativeState(self)
    if pointer == nil then return nil, "Native cryptographic state is closed." end
    local channel = validateDataArguments(ciphertext, aad,
        MAX_DATA_BYTES + DATA_OVERHEAD_BYTES)
    if channel == nil or #ciphertext < DATA_OVERHEAD_BYTES then
        return nil, "Native cryptographic data input is invalid."
    end

    local capacity = #ciphertext
    local output = ffi.new("uint8_t[?]", capacity)
    local outputLength = ffi.new("size_t[1]")
    local ok, result = pcall(nativeLibrary.tps_crypto_state_open, pointer, channel,
        ffi.cast("const uint8_t *", aad), #aad,
        ffi.cast("const uint8_t *", ciphertext), #ciphertext,
        output, capacity, outputLength)
    if not ok or tonumber(result) ~= OK then
        wipe(output, capacity)
        return nil, "Native cryptographic authentication failed."
    end
    local value = outputString(output, outputLength[0], capacity)
    if value == nil or #value ~= #ciphertext - DATA_OVERHEAD_BYTES then
        return nil, "Native cryptographic authentication failed."
    end
    return value
end

function State:free()
    local pointer = nativeState(self)
    if pointer == nil then return true end

    local detachOk, detached = pcall(ffi.gc, pointer, nil)
    if not detachOk then return false, "Native cryptographic state cleanup failed." end
    if not freeNativePointer(detached) then
        -- Preserve ownership for a retry and, where possible, restore the GC
        -- fallback.  The C destructor is void, so a normal native call cannot
        -- report a partial cleanup.
        local attachOk, managed = pcall(ffi.gc, detached, stateFinalizer)
        self._state = attachOk and managed or detached
        return false, "Native cryptographic state cleanup failed."
    end
    self._state = nil
    return true
end

State.close = State.free

bindLibrary()

return Provider
