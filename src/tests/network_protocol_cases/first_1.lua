-- Network wire validation and codec regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.first = {
        zeta = 12.5,
        alpha = "wire-safe",
        flags = Context.Codec.array({ true, false }),
        nested = { right = 2, left = 1 },
        empty = Context.Codec.array({}),
    }
    Context.second = {}
    Context.second.empty = Context.Codec.array({})
    Context.second.nested = { left = 1, right = 2 }
    Context.second.flags = Context.Codec.array({ true, false })
    Context.second.alpha = "wire-safe"
    Context.second.zeta = 12.5
    Context.firstBytes = Context.Codec.encode(Context.first)
    Context.secondBytes = Context.Codec.encode(Context.second)
    Context.decoded = Context.firstBytes and Context.Codec.decode(Context.firstBytes)
    Context.reencoded = Context.decoded and Context.Codec.encode(Context.decoded)
    Context.check("network_protocol_codec_deterministic_round_trip",
        Context.firstBytes and Context.firstBytes == Context.secondBytes and Context.reencoded == Context.firstBytes
        and Context.decoded.alpha == "wire-safe" and Context.decoded.flags[1] == true
        and Context.decoded.flags[2] == false and Context.Codec.isArray(Context.decoded.empty))

    Context.cyclic = {}
    Context.cyclic.self = Context.cyclic
    Context.executable = Context.Codec.encode({ callback = function() return true end })
    Context.cyclicBytes = Context.Codec.encode(Context.cyclic)
    Context.oversized = Context.Codec.encode({ text = string.rep("x", 9) }, {
        maxBytes = 100,
        maxDepth = 4,
        maxEntries = 4,
        maxStringBytes = 8,
        maxNumberBytes = 32,
    })
    Context.trailing = Context.firstBytes and Context.Codec.decode(Context.firstBytes .. "x")
    Context.sourceText = Context.Codec.decode("return {version=1}")
    Context.check("network_protocol_codec_rejects_executable_cyclic_and_unbounded_data",
        Context.executable == nil and Context.cyclicBytes == nil and Context.oversized == nil
        and Context.trailing == nil and Context.sourceText == nil)

    Context.players = Context.roster()
    Context.messages = {
        { "hello", {
            clientNonce = "phone-001", name = "Phone One", character = "rabbit-worker",
        } },
        { "welcome", {
            sessionId = "session-001", playerId = 2, serverTick = 30,
            players = Context.Codec.array({ Context.players[1], Context.players[2] }),
        } },
        { "shop_snapshot", {
            sessionId = "session-001",
            revision = 0,
            state = {
                money = 1500,
                screen = "world",
                jobs = { active = Context.Codec.array({}), completed = Context.Codec.array({}) },
            },
            player = { x = 445, y = 520, character = "rabbit-worker" },
        } },
        { "shop_state", {
            sessionId = "session-001",
            revision = 7,
            state = {
                money = 1775,
                inventory = { paper = 2475, prints = 25 },
                calendar = { day = 5 },
                jobs = { active = Context.Codec.array({}), completed = Context.Codec.array({}) },
                clientEmails = { inbox = Context.Codec.array({}) },
            },
        } },
        { "interaction_request", {
            sessionId = "session-001", requestId = 7, targetKind = "loadingBayDoor",
            desiredState = "open",
        } },
        { "interaction_result", {
            sessionId = "session-001", requestId = 7, targetKind = "loadingBayDoor",
            accepted = true, code = "accepted", message = "Opening the loading bay door...",
        } },
        { "workshop_acquire", {
            sessionId = "session-001", requestId = 8,
            resourceId = "reception_customer", expectedRevision = 3,
        } },
        { "workshop_grant", {
            sessionId = "session-001", requestId = 8, resourceId = "reception_customer",
            granted = true, leaseId = "lease-guest-2-customer", code = "granted",
            message = "Customer counter acquired.", revision = 4,
            view = Context.receptionView(false),
        } },
        { "workshop_command", {
            sessionId = "session-001", commandId = 9, leaseId = "lease-guest-2-customer",
            resourceId = "reception_customer", action = "submit_quote",
            expectedRevision = 4, amount = 285,
        } },
        { "workshop_result", {
            sessionId = "session-001", commandId = 9, resourceId = "reception_customer",
            action = "submit_quote", accepted = true, code = "accepted",
            message = "Quote submitted.", revision = 5,
        } },
        { "workshop_release", {
            sessionId = "session-001", requestId = 10, leaseId = "lease-guest-2-customer",
            resourceId = "reception_customer", reason = "closed",
        } },
        { "workshop_snapshot", {
            sessionId = "session-001", revision = 5, resources = Context.workshopResources(),
            wrapper = Context.wrapperSnapshot("wrapping"),
        } },
        { "cutter_snapshot", {
            sessionId = "session-001", serverTick = 31, resourceRevision = 5,
            view = Context.cutterView(),
        } },
        { "windmill_snapshot", {
            sessionId = "session-001", serverTick = 31, resourceRevision = 6,
            view = Context.runningWindmillView(),
        } },
        { "pallet_jack_snapshot", {
            sessionId = "session-001", serverTick = 31,
            jack = Context.palletJackSnapshot(),
            machines = Context.machinePoses(),
        } },
        { "input", {
            sessionId = "session-001", sequence = 17, moveX = 1, moveY = -1,
        } },
        { "snapshot", {
            sessionId = "session-001", serverTick = 31,
            players = Context.Codec.array({ Context.players[2] }),
        } },
        { "visitor_snapshot", {
            sessionId = "session-001",
            serverTick = 31,
            customer = Context.visitor("waiting", true, 612, 318),
            vendor = Context.visitor("scheduled", false, 500, 300),
        } },
        { "environment_snapshot", {
            sessionId = "session-001",
            serverTick = 31,
            bayDoor = { state = "opening", progress = 0.5 },
            truck = {
                state = "parked_closed", jobId = "JOB-0001", mode = "delivery",
                backingProgress = 1, cargoProgress = 0,
            },
        } },
        { "ping", { sessionId = "session-001", nonce = 91 } },
        { "pong", { sessionId = "session-001", nonce = 91 } },
        { "leave", {
            sessionId = "session-001", playerId = 3, reason = "client disconnected",
        } },
        { "error", {
            sessionId = "session-001", code = "session_full", message = "The shop is full.",
        } },
    }
    Context.roundTrips = true
    for _, message in ipairs(Context.messages) do
        local packet = Context.Protocol.encode(message[1], message[2])
        local envelope = packet and Context.Protocol.decode(packet)
        local packetLimit = Context.Protocol.packetLimitFor(message[1])
        Context.roundTrips = Context.roundTrips and packet ~= nil and envelope ~= nil
            and envelope.version == Context.Protocol.VERSION and envelope.type == message[1]
            and #packet <= packetLimit
    end
    Context.check("network_protocol_all_v13_envelopes_round_trip", Context.roundTrips)

    Context.runShardedPlayerProtocolRegression(Context.check)

    Context.wrongVersion = Context.Protocol.validate({
        version = Context.Protocol.VERSION + 1,
        type = "ping",
        payload = { sessionId = "session-001", nonce = 1 },
    })
    Context.extraField = Context.Protocol.encode("input", {
        sessionId = "session-001", sequence = 1, moveX = 0, moveY = 0, x = 900,
    })
    Context.invalidAxis = Context.Protocol.encode("input", {
        sessionId = "session-001", sequence = 1, moveX = 1.01, moveY = 0,
    })
    Context.duplicatePlayers = Context.Codec.array({
        Context.player(1, "Host", 420, 520),
        Context.player(1, "Duplicate", 500, 500),
    })
    Context.duplicateRoster = Context.Protocol.encode("welcome", {
        sessionId = "session-001", playerId = 1, serverTick = 1,
        players = Context.duplicatePlayers,
    })
    Context.tooManyPlayers = Context.roster()
    Context.tooManyPlayers[5] = Context.player(4, "Duplicate", 500, 500)
    Context.fullRoster = Context.Protocol.encode("snapshot", {
        sessionId = "session-001", serverTick = 1, players = Context.tooManyPlayers,
    })
    Context.missingAssignedPlayer = Context.Protocol.encode("welcome", {
        sessionId = "session-001",
        playerId = 4,
        serverTick = 1,
        players = Context.Codec.array({ Context.player(1, "Host", 1, 1), Context.player(2, "Guest", 2, 2) }),
    })
    Context.badNamePlayers = Context.Codec.array({ Context.player(2, "bad\nname", 445, 520) })
    Context.badName = Context.Protocol.encode("snapshot", {
        sessionId = "session-001", serverTick = 1, players = Context.badNamePlayers,
    })
    Context.check("network_protocol_rejects_invalid_envelopes_and_player_records",
        Context.wrongVersion == nil and Context.extraField == nil and Context.invalidAxis == nil
        and Context.duplicateRoster == nil and Context.fullRoster == nil
        and Context.missingAssignedPlayer == nil and Context.badName == nil)
end

return Component
