local Codec = require("src.net.codec")
local Protocol = require("src.net.protocol")
local SaveSchema = require("src.save_schema")

local Test = {}

local function player(id, name, x, y)
    return {
        id = id,
        name = name,
        x = x,
        y = y,
        velocityX = id * 2,
        velocityY = -id,
        intentX = id % 2 == 0 and -1 or 1,
        intentY = 0,
        moving = true,
        facing = id % 2 == 0 and -1 or 1,
        animationDistance = id * 20,
        character = "rabbit-worker",
        inputSequence = id * 10,
    }
end

local function roster()
    return Codec.array({
        player(1, "Host", 420, 520),
        player(2, "Phone One", 445, 520),
        player(3, "Phone Two", 470, 520),
        player(4, "Guest", 495, 520),
    })
end

-- Runtime movement accumulates binary floating-point values rather than the
-- compact integers used by most protocol fixtures. These records model the
-- wire cost that exposed the four-device v6 roster overflow.
local function fullPrecisionPlayer(id)
    return {
        id = id,
        name = id == 1 and "LAN Host" or ("LAN Worker " .. tostring(id)),
        x = 420.12345678901235 + id * 0.9876543210987654,
        y = 520.98765432109872 - id * 0.12345678901234567,
        velocityX = 123.45678901234567,
        velocityY = -98.765432109876543,
        intentX = 0.70710678118654757,
        intentY = -0.70710678118654757,
        moving = true,
        facing = id % 2 == 0 and -1 or 1,
        animationDistance = 123456789.12345679 + id * 0.00000011920928955,
        character = "rabbit-worker",
        inputSequence = 4000000000 + id,
    }
end

local function fullPrecisionRoster()
    return Codec.array({
        fullPrecisionPlayer(1),
        fullPrecisionPlayer(2),
        fullPrecisionPlayer(3),
        fullPrecisionPlayer(4),
    })
end

local function visitor(state, visible, x, y)
    return {
        state = state,
        visible = visible,
        x = x,
        y = y,
        waypoint = visible and 3 or 1,
        seatIndex = visible and 1 or 0,
        character = "business-cat",
        facing = 1,
        intentX = 0,
        intentY = 1,
        motionX = 0,
        motionY = 0,
        currentSpeed = 0,
        animationDistance = 12,
        animationClock = 1,
        idleClock = 2,
        waitTimer = visible and 22 or 0,
        arrivalTimer = visible and 0 or 7,
        inMotion = state == "entering" or state == "exiting",
    }
end

local function receptionView(printJob)
    local quoteRows
    if printJob then
        quoteRows = Codec.array({
            { number = 1, sheetCount = 525, requiredLifts = 2,
                requestedCopies = 500, spoilageAllowance = 25 },
            { number = 2, sheetCount = 260, requiredLifts = 1,
                requestedCopies = 250, spoilageAllowance = 10 },
        })
    else
        quoteRows = Codec.array({
            { number = 1, sheetCount = 525, requiredLifts = 2, price = 180 },
            { number = 2, sheetCount = 260, requiredLifts = 1, price = 90 },
        })
    end
    return {
        jobId = "JOB-0001",
        company = "Riverside Books",
        difficulty = printJob and "medium" or "easy",
        sourceSize = { width = 12, height = 18 },
        finishedSize = { width = 6, height = 9 },
        stock = "80 lb uncoated text",
        packaging = "boxed",
        delivery = "Customer stock arrives Tuesday",
        artworkKey = "ad-delivery",
        artworkName = "Delivery postcard",
        printJob = printJob,
        quoteRows = quoteRows,
        recommendedTotal = printJob and 1275 or 270,
    }
end

local function wrapperView(step)
    step = step or "idle"
    local wrapping = step == "wrapping"
    local finished = step == "finished"
    return {
        step = step,
        progress = wrapping and 1.25 or (finished and 3 or 0),
        cycleTime = 3,
        selectedPalletId = step ~= "idle" and "JOB-0001-P01" or nil,
        palletId = step ~= "idle" and "JOB-0001-P01" or nil,
        plasticWrapRolls = 2,
        plasticWrapUses = 8,
        pallets = Codec.array({
            { palletId = "JOB-0001-P01", jobLabel = "Riverside Books",
                packaging = "boxed", distance = 32 },
            { palletId = "JOB-0002-P01", jobLabel = "Museum postcards",
                packaging = "flat", distance = 48 },
        }),
    }
end

local function vendorView(kind)
    if kind == "machines" then
        return {
            categoryIndex = 5, categoryName = "USED MACHINERY",
            salesman = "Rufus Gearbox", kind = "machines", cash = 75000,
            items = Codec.array({
                { itemIndex = 1, name = "Polar 115",
                    price = 32000, available = true,
                    detail = "serviceable used dealer unit" },
            }),
        }
    end
    return {
        categoryIndex = 1, categoryName = "PAPER & BOARD",
        salesman = "Milo Stockwell", kind = "products", cash = 1200,
        items = Codec.array({
            { itemIndex = 1, name = "House paper, 1,000 sheets",
                price = 90, available = true,
                detail = "1000 sheets · dock delivery" },
            { itemIndex = 2, name = "Cover stock, 500 sheets",
                price = 125, available = true,
                detail = "500 sheets · dock delivery" },
        }),
    }
end

local function wrapperSnapshot(step, pallets)
    local view = wrapperView(step)
    view.plasticWrapRolls = nil
    view.plasticWrapUses = nil
    if pallets ~= nil then view.pallets = Codec.array(pallets) end
    return view
end

local function checkRadioProtocol(check)
    local packet = Protocol.encode("radio_state", {
        sessionId = "session-001", revision = 7, trackIndex = 9,
        active = true, paused = false, muted = true, positionMs = 145000,
    })
    local envelope = packet and Protocol.decode(packet)
    local invalid = Protocol.encode("radio_state", {
        sessionId = "session-001", revision = 8, trackIndex = 10,
        active = true, paused = false, muted = false, positionMs = 0,
    })
    check("network_protocol_validates_host_radio_playback_state",
        envelope and envelope.payload.trackIndex == 9
        and envelope.payload.positionMs == 145000 and invalid == nil)
end

local function cutterView(overrides)
    local view = {
        runtimeRevision = 12,
        step = "idle",
        phasePermille = 0,
        loaded = false,
        clamp = false,
        clampPermille = 0,
        bladePermille = 0,
        barrierClear = true,
        emergencyStopped = false,
        gaugeCentiInch = 0,
        programIndex = 1,
        memoryCentiInch = Codec.array({ 625, 900 }),
        candidates = Codec.array({
            { palletId = "JOB-0001-P01", distancePixels = 32 },
        }),
        genericSheets = 2500,
    }
    for key, value in pairs(overrides or {}) do view[key] = value end
    return view
end

local function loadedCutterView()
    local view = cutterView({
        runtimeRevision = 13,
        step = "clamped",
        loaded = true,
        clamp = true,
        clampPermille = 1000,
        gaugeCentiInch = 625,
        programIndex = 2,
        paper = {
            palletId = "JOB-0001-P01",
            orientation = 90,
            status = "in_process",
            activeCut = 2,
            cutCount = 4,
            activeLift = 1,
            requiredLifts = 2,
            remainingSheets = 525,
            widthCentiInch = 1250,
            heightCentiInch = 1000,
            offSpec = false,
            selectedCut = {
                number = 2,
                edge = "bottom",
                marginCentiInch = 625,
                gaugeCentiInch = 625,
                orientation = 90,
                active = true,
            },
        },
    })
    view.candidates, view.genericSheets = nil, nil
    return view
end

local function windmillView(overrides)
    local view = {
        runtimeRevision = 21,
        status = "idle",
        speed = 2800,
        motor = false,
        feeder = false,
        impression = false,
        emergency = false,
        counter = 0,
        goodSheets = 0,
        spoilage = 0,
        targetSheets = 525,
        feedStart = 525,
        feedRemaining = 525,
        proofApproved = false,
        artworkVerified = false,
        setupPermille = Codec.array({ 0, 0, 0, 0, 0, 0 }),
        candidates = Codec.array({
            { palletId = "JOB-0001-P01", colorIndex = 1 },
        }),
        serviceStep = "idle",
        servicePermille = 0,
        plateMarkerPermille = 0,
    }
    for key, value in pairs(overrides or {}) do view[key] = value end
    return view
end

local function runningWindmillView(overrides)
    local view = windmillView({
        runtimeRevision = 22,
        status = "production",
        speed = 3600,
        motor = true,
        feeder = true,
        impression = true,
        counter = 125,
        goodSheets = 120,
        spoilage = 5,
        targetSheets = 525,
        feedStart = 550,
        feedRemaining = 425,
        proofApproved = true,
        artworkVerified = true,
        setupPermille = Codec.array({ 1000, 1000, 1000, 1000, 1000, 1000 }),
        candidates = Codec.array({}),
        jobId = "JOB-0001",
        palletId = "JOB-0001-P01",
        colorIndex = 1,
        colorCount = 4,
        proofPermille = 940,
        warning = "Keep hands clear",
        setupSummary = "Setup complete",
    })
    for key, value in pairs(overrides or {}) do view[key] = value end
    return view
end

local function workshopResources()
    return Codec.array({
        { resourceId = "skid_wrapper", revision = 2, occupied = false },
        { resourceId = "reception_customer", revision = 4,
            occupied = true, ownerPlayerId = 2 },
        { resourceId = "vendor", revision = 0, occupied = false },
        { resourceId = "truck", revision = 0, occupied = false },
        { resourceId = "work_phone", revision = 0, occupied = false },
        { resourceId = "office_computer", revision = 1, occupied = false },
        { resourceId = "pallet_jack", revision = 3, occupied = false },
        { resourceId = "cutter", revision = 5, occupied = false },
        { resourceId = "windmill", revision = 6, occupied = false },
        { resourceId = "warehouse", revision = 0, occupied = false },
    })
end

local function palletJackSnapshot(overrides)
    local snapshot = {
        x = 560,
        y = 520,
        direction = "northwest",
        operating = true,
        moving = false,
        operatorPlayerId = 2,
        candidatePalletId = "JOB-0001-P01",
    }
    for key, value in pairs(overrides or {}) do snapshot[key] = value end
    if overrides and overrides.clearCandidate then
        snapshot.clearCandidate, snapshot.candidatePalletId = nil, nil
    end
    if overrides and overrides.clearOwner then
        snapshot.clearOwner, snapshot.operatorPlayerId = nil, nil
    end
    return snapshot
end

local function machinePoses(overrides)
    local poses = {
        cutter = {
            x = 700, y = 420, direction = "northwest",
            moving = false, inMotion = false,
        },
        wrapper = {
            x = 820, y = 360, direction = "northwest",
            moving = false, inMotion = false,
        },
        windmill = {
            x = 850, y = 450, direction = "northwest",
            moving = false, inMotion = false,
        },
    }
    for machine, fields in pairs(overrides or {}) do
        poses[machine] = poses[machine] or {}
        for key, value in pairs(fields) do poses[machine][key] = value end
    end
    return poses
end

local function runShardedPlayerProtocolRegression(check)
    local precisionRoster = fullPrecisionRoster()
    local combinedRosterBytes = Codec.encode({
        version = Protocol.VERSION,
        type = "snapshot",
        payload = {
            sessionId = "session-full-precision",
            serverTick = 4000000000,
            players = precisionRoster,
        },
    }, {
        maxBytes = 64 * 1024,
        maxDepth = 8,
        maxEntries = 128,
        maxStringBytes = 160,
        maxNumberBytes = 32,
    })
    local welcomePacket = Protocol.encode("welcome", {
        sessionId = "session-full-precision",
        playerId = 4,
        serverTick = 4000000000,
        players = Codec.array({ precisionRoster[4], precisionRoster[1] }),
    })
    local welcomeEnvelope = welcomePacket and Protocol.decode(welcomePacket)
    local shardPackets, shardsBounded = {}, true
    for id = 1, 4 do
        shardPackets[id] = Protocol.encode("snapshot", {
            sessionId = "session-full-precision",
            serverTick = 4000000000,
            players = Codec.array({ precisionRoster[id] }),
        })
        shardsBounded = shardsBounded and shardPackets[id] ~= nil
            and #shardPackets[id] <= Protocol.MAX_PACKET_BYTES
    end
    local combinedSnapshot = Protocol.encode("snapshot", {
        sessionId = "session-full-precision",
        serverTick = 4000000000,
        players = Codec.array({ precisionRoster[1], precisionRoster[2] }),
    })
    check("network_protocol_v7_player_updates_are_mtu_safe_shards",
        combinedRosterBytes and #combinedRosterBytes > 1200
        and Protocol.MAX_PACKET_BYTES == 1200
        and welcomeEnvelope and welcomeEnvelope.payload.playerId == 4
        and #welcomeEnvelope.payload.players == 2
        and welcomeEnvelope.payload.players[1].id == 1
        and welcomeEnvelope.payload.players[2].id == 4
        and #welcomePacket <= Protocol.MAX_PACKET_BYTES
        and shardsBounded
        and combinedSnapshot == nil,
        string.format("combined=%s welcome=%s shards=%s/%s/%s/%s limit=%s",
            tostring(combinedRosterBytes and #combinedRosterBytes),
            tostring(welcomePacket and #welcomePacket),
            tostring(shardPackets[1] and #shardPackets[1]),
            tostring(shardPackets[2] and #shardPackets[2]),
            tostring(shardPackets[3] and #shardPackets[3]),
            tostring(shardPackets[4] and #shardPackets[4]),
            tostring(Protocol.MAX_PACKET_BYTES)))
end

local function runLeaveTickProtocolRegression(check)
    local legacyLeavePacket = Protocol.encode("leave", {
        sessionId = "session-001", playerId = 3, reason = "Connection lost",
    })
    local timedLeavePacket = Protocol.encode("leave", {
        sessionId = "session-001", playerId = 3, reason = "Connection lost",
        serverTick = 4294967295,
    })
    local timedLeave = timedLeavePacket and Protocol.decode(timedLeavePacket)
    local fractionalLeaveTick = Protocol.encode("leave", {
        sessionId = "session-001", playerId = 3, reason = "Connection lost",
        serverTick = 4.5,
    })
    local overflowingLeaveTick = Protocol.encode("leave", {
        sessionId = "session-001", playerId = 3, reason = "Connection lost",
        serverTick = 4294967296,
    })
    check("network_protocol_leave_accepts_optional_bounded_server_tick",
        legacyLeavePacket and timedLeavePacket and timedLeave
        and #legacyLeavePacket <= Protocol.MAX_PACKET_BYTES
        and #timedLeavePacket <= Protocol.MAX_PACKET_BYTES
        and timedLeave.payload.serverTick == 4294967295
        and fractionalLeaveTick == nil and overflowingLeaveTick == nil)
end

function Test.run(context, check)
    local Context = {
        context = context,
        check = check,
        Codec = Codec,
        Protocol = Protocol,
        SaveSchema = SaveSchema,
        player = player,
        roster = roster,
        visitor = visitor,
        receptionView = receptionView,
        wrapperView = wrapperView,
        vendorView = vendorView,
        wrapperSnapshot = wrapperSnapshot,
        checkRadioProtocol = checkRadioProtocol,
        cutterView = cutterView,
        loadedCutterView = loadedCutterView,
        windmillView = windmillView,
        runningWindmillView = runningWindmillView,
        workshopResources = workshopResources,
        palletJackSnapshot = palletJackSnapshot,
        machinePoses = machinePoses,
        runShardedPlayerProtocolRegression = runShardedPlayerProtocolRegression,
        runLeaveTickProtocolRegression = runLeaveTickProtocolRegression,
    }
    require("src.tests.network_protocol_cases.first_1").run(Context)
    require("src.tests.network_protocol_cases.checks_2").run(Context)
    require("src.tests.network_protocol_cases.extra_park_pallet_3").run(Context)
    require("src.tests.network_protocol_cases.denied_grant_packet_4").run(Context)
    require("src.tests.network_protocol_cases.acquire_packet_5").run(Context)
    require("src.tests.network_protocol_cases.environment_packet_6").run(Context)
    require("src.tests.network_protocol_cases.mismatched_machine_x_7").run(Context)
    require("src.tests.network_protocol_cases.checks_8").run(Context)

end

return Test
