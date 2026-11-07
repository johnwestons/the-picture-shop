-- Message dispatch, canonical encoding, decoding, and packet routing.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizePing(payload, kind)
        local valid, shapeError = Runtime.shape(payload, kind .. " payload", { "sessionId", "nonce" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(payload.sessionId, Runtime.MAX_TOKEN_BYTES, kind .. ".sessionId")
        if not sessionId then return nil, fieldError end
        local nonce
        nonce, fieldError = Runtime.integerInRange(payload.nonce, 0, Runtime.UINT32_MAX, kind .. ".nonce")
        if not nonce then return nil, fieldError end
        return { sessionId = sessionId, nonce = nonce }
    end

    function Runtime.normalizeLeave(payload)
        local valid, shapeError = Runtime.shape(payload, "leave payload",
            { "sessionId", "playerId", "reason" }, { "serverTick" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(payload.sessionId, Runtime.MAX_TOKEN_BYTES, "leave.sessionId")
        if not sessionId then return nil, fieldError end
        local playerId
        playerId, fieldError = Runtime.integerInRange(
            payload.playerId, 1, Runtime.Protocol.MAX_PLAYERS, "leave.playerId")
        if not playerId then return nil, fieldError end
        local reason
        reason, fieldError = Runtime.printableString(payload.reason, 1, Runtime.MAX_REASON_BYTES, "leave.reason")
        if not reason then return nil, fieldError end
        local normalized = { sessionId = sessionId, playerId = playerId, reason = reason }
        if payload.serverTick ~= nil then
            normalized.serverTick, fieldError = Runtime.integerInRange(
                payload.serverTick, 0, Runtime.UINT32_MAX, "leave.serverTick")
            if not normalized.serverTick then return nil, fieldError end
        end
        return normalized
    end

    function Runtime.normalizeError(payload)
        local valid, shapeError = Runtime.shape(payload, "error payload",
            { "code", "message" }, { "sessionId" })
        if not valid then return nil, shapeError end
        local code, fieldError = Runtime.token(payload.code, Runtime.MAX_ERROR_CODE_BYTES, "error.code")
        if not code then return nil, fieldError end
        local message
        message, fieldError = Runtime.printableString(
            payload.message, 1, Runtime.MAX_ERROR_MESSAGE_BYTES, "error.message")
        if not message then return nil, fieldError end
        local normalized = { code = code, message = message }
        if payload.sessionId ~= nil then
            normalized.sessionId, fieldError = Runtime.token(
                payload.sessionId, Runtime.MAX_TOKEN_BYTES, "error.sessionId")
            if not normalized.sessionId then return nil, fieldError end
        end
        return normalized
    end

    Runtime.PAYLOAD_NORMALIZERS = {
        hello = Runtime.normalizeHello,
        welcome = Runtime.normalizeWelcome,
        shop_snapshot = Runtime.normalizeShopSnapshot,
        shop_state = Runtime.normalizeShopState,
        radio_state = Runtime.normalizeRadioState,
        interaction_request = Runtime.normalizeInteractionRequest,
        interaction_result = Runtime.normalizeInteractionResult,
        highfive_request = Runtime.normalizeHighFiveRequest,
        highfive_offer = Runtime.normalizeHighFiveOffer,
        highfive_response = Runtime.normalizeHighFiveResponse,
        highfive_request_result = Runtime.normalizeHighFiveRequestResult,
        highfive_result = Runtime.normalizeHighFiveResult,
        highfive_start = Runtime.normalizeHighFiveStart,
        workshop_acquire = Runtime.normalizeWorkshopAcquire,
        workshop_grant = Runtime.normalizeWorkshopGrant,
        workshop_command = Runtime.normalizeWorkshopCommand,
        workshop_result = Runtime.normalizeWorkshopResult,
        workshop_release = Runtime.normalizeWorkshopRelease,
        workshop_snapshot = Runtime.normalizeWorkshopSnapshot,
        fight_snapshot = Runtime.normalizeFightSnapshot,
        crisis_snapshot = Runtime.normalizeCrisisSnapshot,
        crisis_frame = Runtime.normalizeCrisisFrame,
        cutter_snapshot = Runtime.normalizeCutterSnapshot,
        wrapper_snapshot = Runtime.normalizeWrapperSnapshot,
        windmill_snapshot = Runtime.normalizeWindmillSnapshot,
        pallet_jack_snapshot = Runtime.normalizePalletJackSnapshot,
        extra_pallet_jack_snapshot = Runtime.normalizeExtraPalletJackSnapshot,
        forklift_snapshot = Runtime.normalizeForkliftSnapshot,
        input = Runtime.normalizeInput,
        snapshot = Runtime.normalizeSnapshot,
        visitor_snapshot = Runtime.normalizeVisitorSnapshot,
        environment_snapshot = Runtime.normalizeEnvironmentSnapshot,
        employee_snapshot = Runtime.normalizeEmployeeSnapshot,
        ping = function(payload) return Runtime.normalizePing(payload, "ping") end,
        pong = function(payload) return Runtime.normalizePing(payload, "pong") end,
        leave = Runtime.normalizeLeave,
        error = Runtime.normalizeError,
    }

    function Runtime.normalizeEnvelope(envelope)
        local valid, shapeError = Runtime.shape(envelope, "envelope", { "version", "type", "payload" })
        if not valid then return nil, shapeError end
        if envelope.version ~= Runtime.Protocol.VERSION then return nil, "unsupported protocol version" end
        if type(envelope.type) ~= "string" or not Runtime.PAYLOAD_NORMALIZERS[envelope.type] then
            return nil, "unsupported message type"
        end
        local payload, payloadError = Runtime.PAYLOAD_NORMALIZERS[envelope.type](envelope.payload)
        if not payload then return nil, payloadError end
        return { version = Runtime.Protocol.VERSION, type = envelope.type, payload = payload }
    end

    function Runtime.limitsFor(kind)
        return (kind == "shop_snapshot" or kind == "shop_state")
            and Runtime.SHOP_CODEC_LIMITS or Runtime.REALTIME_CODEC_LIMITS
    end

    local function wireEnvelope(normalized)
        if normalized.type~="workshop_snapshot" then return normalized end
        local resources={}
        for index,record in ipairs(normalized.payload.resources) do
            local tuple={record.resourceId,record.revision,record.occupied}
            if record.ownerPlayerId~=nil then tuple[4]=record.ownerPlayerId end
            resources[index]=Runtime.Codec.array(tuple)
        end
        return {version=normalized.version,type=normalized.type,payload={
            sessionId=normalized.payload.sessionId,revision=normalized.payload.revision,
            resources=Runtime.Codec.array(resources),wrapper=normalized.payload.wrapper,
        }}
    end

    local function encodeCanonical(normalized)
        return Runtime.Codec.encode(wireEnvelope(normalized),Runtime.limitsFor(normalized.type))
    end

    local function compressShopPacket(kind, packet)
        if (kind ~= "shop_snapshot" and kind ~= "shop_state")
            or #packet < Runtime.Protocol.SHOP_COMPRESSION_MIN_BYTES
        then
            return packet
        end
        local data = type(love) == "table" and love.data or nil
        if type(data) ~= "table" or type(data.compress) ~= "function" then return packet end
        local okay, compressed = pcall(data.compress, "string", "lz4", packet)
        if not okay or type(compressed) ~= "string" then return packet end
        if #compressed + #Runtime.Protocol.SHOP_COMPRESSION_MAGIC
            + Runtime.Protocol.SHOP_COMPRESSION_MIN_SAVING_BYTES > #packet
        then
            return packet
        end
        return Runtime.Protocol.SHOP_COMPRESSION_MAGIC .. compressed
    end

    local function decompressShopPacket(packet)
        local magic = Runtime.Protocol.SHOP_COMPRESSION_MAGIC
        if packet:sub(1, #magic) ~= magic then return packet end
        local compressed = packet:sub(#magic + 1)
        if #compressed < 4 then return nil, "compressed packet header is truncated" end
        -- LÖVE's LZ4 string format begins with its little-endian raw byte count.
        -- Validate that count before asking the decompressor to allocate output.
        local b1, b2, b3, b4 = compressed:byte(1, 4)
        local rawBytes = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        if rawBytes < 1 or rawBytes > Runtime.Protocol.MAX_SHOP_SNAPSHOT_BYTES then
            return nil, "compressed packet exceeds maximum decoded size"
        end
        local data = type(love) == "table" and love.data or nil
        if type(data) ~= "table" or type(data.decompress) ~= "function" then
            return nil, "compressed packets are unavailable"
        end
        -- Keep the compressed input as a string. LÖVE's string overload uses
        -- bounded LZ4 decoding; its CompressedData overload can select the
        -- fast decoder when given a claimed decompressed size.
        local okay, decoded = pcall(data.decompress, "string", "lz4", compressed)
        if not okay or type(decoded) ~= "string" or #decoded ~= rawBytes then
            return nil, "compressed packet is invalid"
        end
        return decoded
    end

    -- Codec.decode already rejects noncanonical scalar encodings, map order,
    -- duplicate keys, and trailing bytes. Compare the validated wire shape to
    -- the decoded value instead of encoding a second full copy of large shop
    -- snapshots solely to prove canonicality.
    local function sameCanonicalValue(left,right)
        local leftType,rightType=type(left),type(right)
        if leftType~=rightType then return false end
        if leftType~="table" then return left==right end
        if Runtime.Codec.isArray(left)~=Runtime.Codec.isArray(right) then return false end
        local leftCount,rightCount=0,0
        for key,value in next,left do
            leftCount=leftCount+1
            local other=right[key]
            if other==nil or not sameCanonicalValue(value,other) then return false end
        end
        for _ in next,right do rightCount=rightCount+1 end
        return leftCount==rightCount
    end

    function Runtime.Protocol.packetLimitFor(kindOrEnvelope)
        local kind = type(kindOrEnvelope) == "table" and kindOrEnvelope.type or kindOrEnvelope
        if type(kind) ~= "string" or not Runtime.PAYLOAD_NORMALIZERS[kind] then
            return Runtime.protocolError("unsupported message type")
        end
        return (kind == "shop_snapshot" or kind == "shop_state")
            and Runtime.Protocol.MAX_SHOP_SNAPSHOT_BYTES
            or Runtime.Protocol.MAX_PACKET_BYTES
    end

    function Runtime.Protocol.route(kindOrEnvelope)
        local kind = type(kindOrEnvelope) == "table" and kindOrEnvelope.type or kindOrEnvelope
        local route = type(kind) == "string" and Runtime.ROUTES[kind] or nil
        if not route then return Runtime.protocolError("unsupported message type") end
        return route.channel, route.delivery
    end

    function Runtime.Protocol.validate(envelope)
        local normalized, validationError = Runtime.normalizeEnvelope(envelope)
        if not normalized then return Runtime.protocolError(validationError) end
        local _, codecError = encodeCanonical(normalized)
        if codecError then return Runtime.protocolError("codec validation failed: " .. tostring(codecError)) end
        return normalized
    end

    function Runtime.Protocol.make(kind, payload)
        return Runtime.Protocol.validate({ version = Runtime.Protocol.VERSION, type = kind, payload = payload })
    end

    function Runtime.Protocol.encode(envelopeOrKind, payload)
        local envelope
        if type(envelopeOrKind) == "string" then
            envelope = { version = Runtime.Protocol.VERSION, type = envelopeOrKind, payload = payload }
        elseif type(envelopeOrKind) == "table" and payload == nil then
            envelope = envelopeOrKind
        else
            return Runtime.protocolError("encode expects an envelope or a message type and payload")
        end
        local normalized, validationError = Runtime.normalizeEnvelope(envelope)
        if not normalized then return Runtime.protocolError(validationError) end
        local encoded, codecError = encodeCanonical(normalized)
        if not encoded then return Runtime.protocolError("codec encode failed: " .. tostring(codecError)) end
        return compressShopPacket(normalized.type, encoded)
    end

    function Runtime.Protocol.decode(packet)
        if type(packet) ~= "string" then return Runtime.protocolError("packet must be a string") end
        if #packet > Runtime.Protocol.MAX_SHOP_SNAPSHOT_BYTES then
            return Runtime.protocolError("packet exceeds maximum size")
        end
        local codecPacket, decompressError = decompressShopPacket(packet)
        if not codecPacket then
            return Runtime.protocolError("compressed packet decode failed: " .. tostring(decompressError))
        end
        local decoded, codecError = Runtime.Codec.decode(codecPacket, Runtime.SHOP_CODEC_LIMITS)
        if not decoded then return Runtime.protocolError("codec decode failed: " .. tostring(codecError)) end
        local normalized, validationError = Runtime.normalizeEnvelope(decoded)
        if not normalized then return Runtime.protocolError(validationError) end
        local limit = (normalized.type == "shop_snapshot" or normalized.type == "shop_state")
            and Runtime.Protocol.MAX_SHOP_SNAPSHOT_BYTES or Runtime.Protocol.MAX_PACKET_BYTES
        if #codecPacket > limit then return Runtime.protocolError("packet exceeds limit for " .. normalized.type) end
        if not sameCanonicalValue(decoded,wireEnvelope(normalized)) then
            return Runtime.protocolError("packet is not canonical")
        end
        return normalized
    end
end

return Component
