-- Bounded encrypted acceptance messages used only by the public-IPv4 probe.
-- These frames travel inside DirectTransport encryption and contain no
-- endpoint, invitation, player name, or router metadata.
local Protocol = {}

Protocol.MAGIC = "TPSA"
Protocol.VERSION = 1
Protocol.TYPE_CHALLENGE = 1
Protocol.TYPE_ACK = 2
Protocol.NONCE_BYTES = 16
Protocol.CHANNELS = 3
Protocol.PHASES = 2
Protocol.PACKET_BYTES = #Protocol.MAGIC + 4 + Protocol.NONCE_BYTES

local function wholeNumber(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function encode(kind, phase, channel, nonce)
    local packetType = kind == "challenge" and Protocol.TYPE_CHALLENGE
        or kind == "ack" and Protocol.TYPE_ACK or nil
    if not packetType or not wholeNumber(phase, 1, Protocol.PHASES)
        or not wholeNumber(channel, 0, Protocol.CHANNELS - 1)
        or type(nonce) ~= "string" or #nonce ~= Protocol.NONCE_BYTES then
        return nil, "invalid_probe_message"
    end
    return Protocol.MAGIC .. string.char(
        Protocol.VERSION, packetType, phase, channel) .. nonce
end

function Protocol.challenge(phase, channel, nonce)
    return encode("challenge", phase, channel, nonce)
end

function Protocol.ack(phase, channel, nonce)
    return encode("ack", phase, channel, nonce)
end

function Protocol.parse(packet)
    if type(packet) ~= "string" or #packet ~= Protocol.PACKET_BYTES
        or packet:sub(1, #Protocol.MAGIC) ~= Protocol.MAGIC then
        return nil, "invalid_probe_message"
    end
    local version, packetType, phase, channel = packet:byte(5, 8)
    if version ~= Protocol.VERSION
        or (packetType ~= Protocol.TYPE_CHALLENGE
            and packetType ~= Protocol.TYPE_ACK)
        or not wholeNumber(phase, 1, Protocol.PHASES)
        or not wholeNumber(channel, 0, Protocol.CHANNELS - 1) then
        return nil, "invalid_probe_message"
    end
    return {
        kind = packetType == Protocol.TYPE_CHALLENGE and "challenge" or "ack",
        phase = phase,
        channel = channel,
        nonce = packet:sub(9, 8 + Protocol.NONCE_BYTES),
    }
end

return Protocol
