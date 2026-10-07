-- Network wire validation and codec regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.check("network_protocol_routes_match_three_channel_contract", Context.routesCorrect,
        string.format("version=%s channels=%s/%s/%s count=%s durable=%s/%s",
            tostring(Context.Protocol.VERSION), tostring(Context.Protocol.CHANNEL_CONTROL),
            tostring(Context.Protocol.CHANNEL_STATE), tostring(Context.Protocol.CHANNEL_DURABLE),
            tostring(Context.Protocol.CHANNEL_COUNT), tostring(Context.durableChannel),
            tostring(Context.durableDelivery)) .. " join=" .. tostring(Context.joinStateChannel)
            .. "/" .. tostring(Context.joinStateDelivery)
            .. " routes=" .. table.concat(Context.routeSummary, ","))
    Context.checkRadioProtocol(Context.check)

    Context.visitorPacket = Context.Protocol.encode("visitor_snapshot", {
        sessionId = "session-001",
        serverTick = 42,
        customer = Context.visitor("reviewing", true, 612, 318),
        vendor = Context.visitor("scheduled", false, 500, 300),
    })
    Context.visitorEnvelope = Context.visitorPacket and Context.Protocol.decode(Context.visitorPacket)
    Context.invalidVisitorTick = Context.Protocol.encode("visitor_snapshot", {
        sessionId = "session-001", serverTick = -1, customer = {}, vendor = {},
    })
    Context.unsafeVisitor = Context.Protocol.encode("visitor_snapshot", {
        sessionId = "session-001", serverTick = 42,
        customer = { callback = function() end }, vendor = {},
    })
    Context.check("network_protocol_visitor_snapshot_round_trips_as_bounded_realtime_data",
        Context.visitorEnvelope and Context.visitorEnvelope.payload.serverTick == 42
        and Context.visitorEnvelope.payload.customer.state == "reviewing"
        and Context.visitorEnvelope.payload.vendor.visible == false
        and #Context.visitorPacket <= Context.Protocol.MAX_PACKET_BYTES
        and Context.invalidVisitorTick == nil and Context.unsafeVisitor == nil)

    Context.pingPacket = Context.Protocol.encode("ping", { sessionId = "session-001", nonce = 3 })
    Context.malformed = Context.Protocol.decode("return {payload={}}")
    Context.trailingPacket = Context.pingPacket and Context.Protocol.decode(Context.pingPacket .. "x")
    Context.wrongVersionPacket = Context.Codec.encode({
        version = Context.Protocol.VERSION + 1,
        type = "ping",
        payload = { sessionId = "session-001", nonce = 3 },
    })
    Context.decodedWrongVersion = Context.wrongVersionPacket and Context.Protocol.decode(Context.wrongVersionPacket)
    Context.hugePacket = Context.Protocol.decode(string.rep("x", Context.Protocol.MAX_SHOP_SNAPSHOT_BYTES + 1))
    Context.check("network_protocol_decode_rejects_malformed_trailing_wrong_version_and_huge_packets",
        Context.malformed == nil and Context.trailingPacket == nil and Context.decodedWrongVersion == nil and Context.hugePacket == nil)
end

return Component
