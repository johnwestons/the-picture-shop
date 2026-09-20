local Protocol = require("src.net.public_ipv4_probe_protocol")

local Test = {}

function Test.run(_, check)
    local nonce = string.rep("n", Protocol.NONCE_BYTES)
    local challenge = Protocol.challenge(1, 0, nonce)
    local ack = Protocol.ack(2, 2, nonce)
    local parsedChallenge = Protocol.parse(challenge)
    local parsedAck = Protocol.parse(ack)
    check("public_ipv4_probe_protocol_round_trips_bounded_encrypted_messages",
        parsedChallenge and parsedChallenge.kind == "challenge"
        and parsedChallenge.phase == 1 and parsedChallenge.channel == 0
        and parsedChallenge.nonce == nonce
        and parsedAck and parsedAck.kind == "ack"
        and parsedAck.phase == 2 and parsedAck.channel == 2
        and parsedAck.nonce == nonce)

    local invalid = {
        false, "", challenge .. "x", challenge:sub(1, -2),
        "FAIL" .. challenge:sub(5),
        challenge:sub(1, 4) .. string.char(2) .. challenge:sub(6),
        challenge:sub(1, 5) .. string.char(9) .. challenge:sub(7),
        challenge:sub(1, 6) .. string.char(0) .. challenge:sub(8),
        challenge:sub(1, 7) .. string.char(3) .. challenge:sub(9),
    }
    local rejected = Protocol.parse(nil) == nil
    for _, packet in ipairs(invalid) do
        rejected = rejected and Protocol.parse(packet) == nil
    end
    check("public_ipv4_probe_protocol_rejects_wrong_size_type_phase_and_channel",
        rejected
        and Protocol.challenge(0, 0, nonce) == nil
        and Protocol.challenge(1, 3, nonce) == nil
        and Protocol.ack(1, 0, nonce .. "x") == nil)
end

return Test
