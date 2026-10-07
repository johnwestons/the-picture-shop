-- Direct transport constants, provider contracts, and wire framing.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    -- Fail-closed security boundary for Direct Internet Play. This module does not
    -- implement cryptography. A production native provider must return Lua tables
    -- or userdata exposing start, handshake, isReady, seal, open, and close. The
    -- provider owns Noise transcript validation, direction-separated traffic keys,
    -- per-channel nonces/replay windows, and native key zeroization. `productionReady`
    -- is an API guard, not a substitute for provider conformance tests.
    Runtime.DirectTransport = {}
    Runtime.Instance = {}
    Runtime.Instance.__index = Runtime.Instance

    Runtime.DirectTransport.MAGIC = "TPSD"
    Runtime.DirectTransport.VERSION = 1
    Runtime.DirectTransport.TYPE_HANDSHAKE = 1
    Runtime.DirectTransport.TYPE_DATA = 2
    Runtime.DirectTransport.HEADER_BYTES = #Runtime.DirectTransport.MAGIC + 2
    Runtime.DirectTransport.HANDSHAKE_CHANNEL = 0
    Runtime.DirectTransport.DURABLE_CHANNEL = 2
    Runtime.DirectTransport.KEY_BYTES = 32

    Runtime.DirectTransport.DEFAULT_CHANNELS = 3
    Runtime.DirectTransport.DEFAULT_HANDSHAKE_TIMEOUT = 5
    Runtime.DirectTransport.DEFAULT_PEER_CAPACITY = 12
    Runtime.DirectTransport.DEFAULT_MAX_PENDING_PEERS = 4
    Runtime.DirectTransport.DEFAULT_ADMISSION_BURST = 4
    Runtime.DirectTransport.DEFAULT_ADMISSION_REFILL_SECONDS = 1
    Runtime.DirectTransport.DEFAULT_MAX_READY_PEERS = 3
    Runtime.DirectTransport.DEFAULT_MAX_HANDSHAKE_BYTES = 1024
    Runtime.DirectTransport.DEFAULT_MAX_HANDSHAKE_FRAMES = 4
    Runtime.DirectTransport.DEFAULT_MAX_HANDSHAKE_TOTAL_BYTES = 4096
    Runtime.DirectTransport.DEFAULT_MAX_PRE_READY_DATA_FRAMES = 8
    Runtime.DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES = 1200
    Runtime.DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES = 512 * 1024
    Runtime.DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES = 256
    Runtime.DirectTransport.DEFAULT_MAX_WIRE_BYTES = Runtime.DirectTransport.HEADER_BYTES
        + Runtime.DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES
        + Runtime.DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES
    Runtime.DirectTransport.DEFAULT_MAX_PRE_READY_DATA_BYTES =
        Runtime.DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES
        + Runtime.DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES
        + (Runtime.DirectTransport.DEFAULT_MAX_PRE_READY_DATA_FRAMES - 1)
            * (Runtime.DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES
                + Runtime.DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES)
    Runtime.DirectTransport.MAX_EVENTS_PER_SERVICE = 64

    Runtime.DirectTransport.DISCONNECT_AUTHENTICATION = 4201
    Runtime.DirectTransport.DISCONNECT_HANDSHAKE_TIMEOUT = 4202
    Runtime.DirectTransport.DISCONNECT_INTERNAL = 4203

    Runtime.HANDSHAKE_PREFIX = Runtime.DirectTransport.MAGIC
        .. string.char(Runtime.DirectTransport.VERSION, Runtime.DirectTransport.TYPE_HANDSHAKE)
    Runtime.DATA_PREFIX = Runtime.DirectTransport.MAGIC
        .. string.char(Runtime.DirectTransport.VERSION, Runtime.DirectTransport.TYPE_DATA)

    Runtime.REQUIRED_STATE_METHODS = {
        "start", "handshake", "isReady", "seal", "open", "close",
    }

    function Runtime.wholeNumber(value, minimum, maximum)
        value = tonumber(value)
        return value and value == math.floor(value) and value >= minimum and value <= maximum
            and value or nil
    end

    function Runtime.finiteNumber(value, minimum, maximum)
        value = tonumber(value)
        return value and value == value and value > -math.huge and value < math.huge
            and value >= minimum and value <= maximum and value or nil
    end

    function Runtime.defaultClock()
        if love and love.timer and type(love.timer.getTime) == "function" then
            return love.timer.getTime()
        end
        return os.clock()
    end

    function Runtime.copyEvent(event, eventType)
        local result = {}
        if type(event) == "table" then
            for key, value in pairs(event) do result[key] = value end
        end
        result.type = eventType or result.type
        return result
    end

    function Runtime.methodFor(target, method)
        if target == nil then return nil end
        local ok, callable = pcall(function() return target[method] end)
        if not ok or type(callable) ~= "function" then return nil end
        return callable
    end

    function Runtime.callMethod(target, method, ...)
        local callable = Runtime.methodFor(target, method)
        if not callable then return false, "missing " .. tostring(method) end
        return pcall(callable, target, ...)
    end

    function Runtime.callFactory(factory, method, ...)
        if type(factory) ~= "table" or type(factory[method]) ~= "function" then
            return false, "missing " .. tostring(method)
        end
        return pcall(factory[method], ...)
    end

    function Runtime.sendSucceeded(result)
        if result == false then return false end
        if type(result) == "number" and result < 0 then return false end
        return true
    end

    function Runtime.sendOptions(channelOrOptions, reliable)
        if type(channelOrOptions) == "table" then
            return channelOrOptions.channel or 0, channelOrOptions.reliable == true
        end
        return channelOrOptions or 0, reliable == true
    end

    function Runtime.validateProvider(provider)
        if type(provider) ~= "table" then
            return nil, "Direct Internet Play requires a cryptographic provider."
        end
        if type(provider.newInitiator) ~= "function"
            or type(provider.newResponder) ~= "function"
        then
            return nil, "The cryptographic provider must implement newInitiator and newResponder."
        end
        if type(provider.admissionToken) ~= "function" then
            return nil, "The cryptographic provider must implement admissionToken."
        end
        if provider.productionReady ~= true then
            return nil, "Direct Internet Play requires a production cryptographic provider."
        end
        return provider
    end

    function Runtime.validateState(state)
        if state == nil then
            return nil, "The cryptographic provider did not create a state object."
        end
        for _, method in ipairs(Runtime.REQUIRED_STATE_METHODS) do
            if not Runtime.methodFor(state, method) then
                return nil, "The cryptographic state must implement " .. method .. "."
            end
        end
        return state
    end

    function Runtime.closeState(entry)
        if not entry or entry.closed then return true end
        entry.closed = true
        local ok, result, errorMessage = Runtime.callMethod(entry.state, "close")
        if not ok or result == false then return false, "Cryptographic state cleanup failed." end
        return true
    end

    function Runtime.frame(packetType, payload)
        local prefix = packetType == Runtime.DirectTransport.TYPE_HANDSHAKE
            and Runtime.HANDSHAKE_PREFIX or Runtime.DATA_PREFIX
        return prefix .. payload
    end

    function Runtime.parseFrame(payload, maxHandshakeBytes, maxWireBytes)
        if type(payload) ~= "string" then return nil, nil, "Direct packet is not a string." end
        if #payload < Runtime.DirectTransport.HEADER_BYTES + 1 then
            return nil, nil, "Direct packet is missing its authenticated frame."
        end
        if #payload > maxWireBytes then return nil, nil, "Direct packet exceeds the wire limit." end
        if payload:sub(1, #Runtime.DirectTransport.MAGIC) ~= Runtime.DirectTransport.MAGIC then
            return nil, nil, "Direct packet has the wrong magic."
        end
        local version = payload:byte(#Runtime.DirectTransport.MAGIC + 1)
        if version ~= Runtime.DirectTransport.VERSION then
            return nil, nil, "Direct packet has an unsupported version."
        end
        local packetType = payload:byte(#Runtime.DirectTransport.MAGIC + 2)
        if packetType ~= Runtime.DirectTransport.TYPE_HANDSHAKE
            and packetType ~= Runtime.DirectTransport.TYPE_DATA
        then
            return nil, nil, "Direct packet has an invalid type."
        end
        local body = payload:sub(Runtime.DirectTransport.HEADER_BYTES + 1)
        if #body == 0 then return nil, nil, "Direct packet has an empty body." end
        if packetType == Runtime.DirectTransport.TYPE_HANDSHAKE and #body > maxHandshakeBytes then
            return nil, nil, "Direct handshake exceeds the handshake limit."
        end
        return packetType, body
    end

    function Runtime.DirectTransport.aadForChannel(channel)
        channel = Runtime.wholeNumber(channel, 0, 255)
        if not channel then return nil, "Direct packet channel must be between 0 and 255." end
        return Runtime.DATA_PREFIX .. string.char(channel)
    end

    function Runtime.DirectTransport.admissionToken(provider, key)
        if type(provider) ~= "table" or type(provider.admissionToken) ~= "function" then
            return nil, "Direct admission tokens require a cryptographic provider."
        end
        if type(key) ~= "string" or #key ~= Runtime.DirectTransport.KEY_BYTES then
            return nil, "Direct admission tokens require a 32-byte shared key."
        end
        local ok, token, errorMessage = pcall(provider.admissionToken, key)
        if not ok or errorMessage ~= nil then
            return nil, "Cryptographic admission token derivation failed."
        end
        if type(token) ~= "number" or token ~= token or token ~= math.floor(token)
            or token < 0 or token > 2147483647
        then
            return nil, "The cryptographic provider returned an invalid admission token."
        end
        return token
    end
end

return Component
