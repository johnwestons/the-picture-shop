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

local function wrapperSnapshot(step, pallets)
    local view = wrapperView(step)
    view.plasticWrapRolls = nil
    view.plasticWrapUses = nil
    if pallets ~= nil then view.pallets = Codec.array(pallets) end
    return view
end

local function workshopResources()
    return Codec.array({
        { resourceId = "skid_wrapper", revision = 2, occupied = false },
        { resourceId = "reception_customer", revision = 4,
            occupied = true, ownerPlayerId = 2 },
        { resourceId = "office_computer", revision = 1, occupied = false },
    })
end

function Test.run(context, check)
    local first = {
        zeta = 12.5,
        alpha = "wire-safe",
        flags = Codec.array({ true, false }),
        nested = { right = 2, left = 1 },
        empty = Codec.array({}),
    }
    local second = {}
    second.empty = Codec.array({})
    second.nested = { left = 1, right = 2 }
    second.flags = Codec.array({ true, false })
    second.alpha = "wire-safe"
    second.zeta = 12.5
    local firstBytes = Codec.encode(first)
    local secondBytes = Codec.encode(second)
    local decoded = firstBytes and Codec.decode(firstBytes)
    local reencoded = decoded and Codec.encode(decoded)
    check("network_protocol_codec_deterministic_round_trip",
        firstBytes and firstBytes == secondBytes and reencoded == firstBytes
        and decoded.alpha == "wire-safe" and decoded.flags[1] == true
        and decoded.flags[2] == false and Codec.isArray(decoded.empty))

    local cyclic = {}
    cyclic.self = cyclic
    local executable = Codec.encode({ callback = function() return true end })
    local cyclicBytes = Codec.encode(cyclic)
    local oversized = Codec.encode({ text = string.rep("x", 9) }, {
        maxBytes = 100,
        maxDepth = 4,
        maxEntries = 4,
        maxStringBytes = 8,
        maxNumberBytes = 32,
    })
    local trailing = firstBytes and Codec.decode(firstBytes .. "x")
    local sourceText = Codec.decode("return {version=1}")
    check("network_protocol_codec_rejects_executable_cyclic_and_unbounded_data",
        executable == nil and cyclicBytes == nil and oversized == nil
        and trailing == nil and sourceText == nil)

    local players = roster()
    local messages = {
        { "hello", {
            clientNonce = "phone-001", name = "Phone One", character = "rabbit-worker",
        } },
        { "welcome", {
            sessionId = "session-001", playerId = 2, serverTick = 30, players = players,
        } },
        { "shop_snapshot", {
            sessionId = "session-001",
            revision = 0,
            state = {
                money = 1500,
                screen = "world",
                jobs = { active = Codec.array({}), completed = Codec.array({}) },
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
                jobs = { active = Codec.array({}), completed = Codec.array({}) },
                clientEmails = { inbox = Codec.array({}) },
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
            view = receptionView(false),
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
            sessionId = "session-001", revision = 5, resources = workshopResources(),
            wrapper = wrapperSnapshot("wrapping"),
        } },
        { "input", {
            sessionId = "session-001", sequence = 17, moveX = 1, moveY = -1,
        } },
        { "snapshot", {
            sessionId = "session-001", serverTick = 31, players = players,
        } },
        { "visitor_snapshot", {
            sessionId = "session-001",
            serverTick = 31,
            customer = visitor("waiting", true, 612, 318),
            vendor = visitor("scheduled", false, 500, 300),
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
    local roundTrips = true
    for _, message in ipairs(messages) do
        local packet = Protocol.encode(message[1], message[2])
        local envelope = packet and Protocol.decode(packet)
        local packetLimit = Protocol.packetLimitFor(message[1])
        roundTrips = roundTrips and packet ~= nil and envelope ~= nil
            and envelope.version == Protocol.VERSION and envelope.type == message[1]
            and #packet <= packetLimit
    end
    check("network_protocol_all_v4_envelopes_round_trip", roundTrips)

    local orderedPacket = Protocol.encode("snapshot", {
        sessionId = "session-001", serverTick = 40, players = roster(),
    })
    local reversePlayers = roster()
    local reversedPacket = Protocol.encode("snapshot", {
        sessionId = "session-001",
        serverTick = 40,
        players = Codec.array({ reversePlayers[4], reversePlayers[3], reversePlayers[2], reversePlayers[1] }),
    })
    local welcomePacket = Protocol.encode("welcome", {
        sessionId = "session-001", playerId = 4, serverTick = 40, players = roster(),
    })
    local normalizedRoster = reversedPacket and Protocol.decode(reversedPacket)
    check("network_protocol_player_rosters_are_canonical_and_bounded",
        orderedPacket and reversedPacket == orderedPacket and welcomePacket
        and #orderedPacket <= Protocol.MAX_PACKET_BYTES
        and #welcomePacket <= Protocol.MAX_PACKET_BYTES
        and normalizedRoster.payload.players[1].id == 1
        and normalizedRoster.payload.players[4].id == 4
        and normalizedRoster.payload.players[3].name == "Phone Two")

    local wrongVersion = Protocol.validate({
        version = Protocol.VERSION + 1,
        type = "ping",
        payload = { sessionId = "session-001", nonce = 1 },
    })
    local extraField = Protocol.encode("input", {
        sessionId = "session-001", sequence = 1, moveX = 0, moveY = 0, x = 900,
    })
    local invalidAxis = Protocol.encode("input", {
        sessionId = "session-001", sequence = 1, moveX = 1.01, moveY = 0,
    })
    local duplicatePlayers = roster()
    duplicatePlayers[4].id = 3
    local duplicateRoster = Protocol.encode("snapshot", {
        sessionId = "session-001", serverTick = 1, players = duplicatePlayers,
    })
    local tooManyPlayers = roster()
    tooManyPlayers[5] = player(4, "Duplicate", 500, 500)
    local fullRoster = Protocol.encode("snapshot", {
        sessionId = "session-001", serverTick = 1, players = tooManyPlayers,
    })
    local missingAssignedPlayer = Protocol.encode("welcome", {
        sessionId = "session-001",
        playerId = 4,
        serverTick = 1,
        players = Codec.array({ player(1, "Host", 1, 1), player(2, "Guest", 2, 2) }),
    })
    local badNamePlayers = roster()
    badNamePlayers[2].name = "bad\nname"
    local badName = Protocol.encode("snapshot", {
        sessionId = "session-001", serverTick = 1, players = badNamePlayers,
    })
    check("network_protocol_rejects_invalid_envelopes_and_player_records",
        wrongVersion == nil and extraField == nil and invalidAxis == nil
        and duplicateRoster == nil and fullRoster == nil
        and missingAssignedPlayer == nil and badName == nil)

    local safeInteractionRequest = Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    local decodedInteractionRequest = safeInteractionRequest
        and Protocol.decode(safeInteractionRequest)
    local safeInteractionResult = Protocol.encode("interaction_result", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        accepted = false, code = "out_of_range",
        message = "Move closer to the loading-bay wall switch.",
    })
    local decodedInteractionResult = safeInteractionResult
        and Protocol.decode(safeInteractionResult)
    local zeroRequestId = Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 0, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    local fractionalRequestId = Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 1.5, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    local overflowingRequestId = Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 4294967296, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    local unsupportedInteraction = Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "computer",
        desiredState = "open",
    })
    local claimedIdentity = Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "loadingBayDoor",
        desiredState = "open", playerId = 2,
    })
    local claimedPosition = Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "loadingBayDoor",
        desiredState = "open", x = 300, y = 285,
    })
    local missingDesiredState = Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "loadingBayDoor",
    })
    local invalidDesiredState = Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "loadingBayDoor",
        desiredState = "opening",
    })
    local nonBooleanResult = Protocol.encode("interaction_result", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        accepted = 1, code = "accepted", message = "Opening.",
    })
    local malformedResultCode = Protocol.encode("interaction_result", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        accepted = false, code = "bad\ncode", message = "Rejected.",
    })
    local extraResultField = Protocol.encode("interaction_result", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        accepted = false, code = "rejected", message = "Rejected.", retry = true,
    })
    check("network_protocol_interaction_messages_are_strict_bounded_and_positionless",
        decodedInteractionRequest
        and decodedInteractionRequest.payload.requestId == 8
        and decodedInteractionRequest.payload.targetKind == "loadingBayDoor"
        and decodedInteractionRequest.payload.desiredState == "open"
        and decodedInteractionResult
        and decodedInteractionResult.payload.accepted == false
        and decodedInteractionResult.payload.code == "out_of_range"
        and #safeInteractionRequest <= Protocol.MAX_PACKET_BYTES
        and #safeInteractionResult <= Protocol.MAX_PACKET_BYTES
        and zeroRequestId == nil and fractionalRequestId == nil
        and overflowingRequestId == nil and unsupportedInteraction == nil
        and claimedIdentity == nil and claimedPosition == nil
        and missingDesiredState == nil and invalidDesiredState == nil
        and nonBooleanResult == nil and malformedResultCode == nil
        and extraResultField == nil)

    local validWorkshopCommands = {
        { resourceId = "reception_customer", action = "submit_quote", amount = 285 },
        { resourceId = "reception_customer", action = "decline" },
        { resourceId = "office_computer", action = "request_pickup", jobId = "JOB-0001" },
        { resourceId = "skid_wrapper", action = "select_pallet", palletId = "JOB-0001-P01" },
        { resourceId = "skid_wrapper", action = "start_cycle", palletId = "JOB-0001-P01" },
    }
    local workshopCommandsValid = true
    for index, command in ipairs(validWorkshopCommands) do
        local payload = {
            sessionId = "session-001",
            commandId = 100 + index,
            leaseId = "lease-guest-2",
            resourceId = command.resourceId,
            action = command.action,
            expectedRevision = 7,
            amount = command.amount,
            jobId = command.jobId,
            palletId = command.palletId,
        }
        local packet = Protocol.encode("workshop_command", payload)
        local envelope = packet and Protocol.decode(packet)
        workshopCommandsValid = workshopCommandsValid and packet ~= nil and envelope ~= nil
            and envelope.payload.resourceId == command.resourceId
            and envelope.payload.action == command.action
            and envelope.payload.amount == command.amount
            and envelope.payload.jobId == command.jobId
            and envelope.payload.palletId == command.palletId
            and #packet <= Protocol.MAX_PACKET_BYTES
    end
    local wrongResourceAction = Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "office_computer", action = "submit_quote",
        expectedRevision = 0, amount = 200,
    })
    local missingActionArgument = Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "skid_wrapper", action = "start_cycle", expectedRevision = 0,
    })
    local extraDeclineArgument = Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "reception_customer", action = "decline", expectedRevision = 0,
        amount = 200,
    })
    local arbitraryArguments = Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "skid_wrapper", action = "start_cycle", expectedRevision = 0,
        palletId = "JOB-0001-P01", args = { force = true },
    })
    local spoofedWorkshopCommand = Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "skid_wrapper", action = "start_cycle", expectedRevision = 0,
        palletId = "JOB-0001-P01", playerId = 2, x = 326, y = 338,
    })
    local invalidQuoteAmount = Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "reception_customer", action = "submit_quote", expectedRevision = 0,
        amount = 100000001,
    })
    local fractionalWorkshopRevision = Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "reception_customer", action = "decline", expectedRevision = 0.5,
    })
    check("network_protocol_workshop_commands_use_closed_resource_action_scalar_unions",
        workshopCommandsValid and wrongResourceAction == nil and missingActionArgument == nil
        and extraDeclineArgument == nil and arbitraryArguments == nil
        and spoofedWorkshopCommand == nil and invalidQuoteAmount == nil
        and fractionalWorkshopRevision == nil)

    local customerGrantPacket = Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 12, resourceId = "reception_customer",
        granted = true, leaseId = "lease-customer-2", code = "granted",
        message = "Customer counter acquired.", revision = 8, view = receptionView(false),
    })
    local customerGrant = customerGrantPacket and Protocol.decode(customerGrantPacket)
    local printResultPacket = Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 13, resourceId = "reception_customer",
        action = "submit_quote", accepted = false, code = "offer_changed",
        message = "The customer offer changed.", revision = 9, view = receptionView(true),
    })
    local printResult = printResultPacket and Protocol.decode(printResultPacket)
    local wrapperResultPacket = Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 14, resourceId = "skid_wrapper",
        action = "start_cycle", accepted = true, code = "accepted",
        message = "Wrapping started.", revision = 10, view = wrapperView("wrapping"),
    })
    local wrapperResult = wrapperResultPacket and Protocol.decode(wrapperResultPacket)
    local officeGrantPacket = Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 15, resourceId = "office_computer",
        granted = true, leaseId = "lease-office-2", code = "granted",
        message = "Office computer acquired.", revision = 10, view = {},
    })
    local deniedGrantPacket = Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "office_computer",
        granted = false, code = "occupied", message = "Computer is in use.", revision = 10,
    })
    local fivePalletView = receptionView(true)
    local fiveRows = {}
    for number = 1, 5 do
        fiveRows[number] = { number = number, sheetCount = 525, requiredLifts = 2,
            requestedCopies = 500, spoilageAllowance = 25 }
    end
    fivePalletView.quoteRows = Codec.array(fiveRows)
    local fivePalletGrantPacket = Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "reception_customer",
        granted = true, leaseId = "lease-customer-2", code = "granted",
        message = "Customer counter acquired.", revision = 10, view = fivePalletView,
    })
    local missingGrantedLease = Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "office_computer",
        granted = true, code = "granted", message = "Granted.", revision = 10,
    })
    local deniedWithLease = Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "office_computer",
        granted = false, leaseId = "forged-lease", code = "occupied",
        message = "Computer is in use.", revision = 10,
    })
    local invalidOfficeView = Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "office_computer",
        granted = true, leaseId = "lease-office-2", code = "granted",
        message = "Granted.", revision = 10, view = { state = {} },
    })
    local invalidQuoteView = receptionView(true)
    invalidQuoteView.quoteRows[1].spoilageAllowance = 24
    local inconsistentQuoteView = Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 17, resourceId = "reception_customer",
        action = "submit_quote", accepted = false, code = "changed",
        message = "Changed.", revision = 10, view = invalidQuoteView,
    })
    local invalidWrapperView = wrapperView("wrapping")
    invalidWrapperView.progress = invalidWrapperView.cycleTime
    local inconsistentWrapperView = Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 18, resourceId = "skid_wrapper",
        action = "start_cycle", accepted = false, code = "busy",
        message = "Busy.", revision = 10, view = invalidWrapperView,
    })
    local arbitraryResultState = Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 18, resourceId = "skid_wrapper",
        action = "start_cycle", accepted = false, code = "busy",
        message = "Busy.", revision = 10, state = { inventory = {} },
    })
    check("network_protocol_workshop_views_are_host_authored_strict_and_resource_specific",
        customerGrant and customerGrant.payload.view.jobId == "JOB-0001"
        and customerGrant.payload.view.quoteRows[2].price == 90
        and printResult and printResult.payload.view.printJob == true
        and printResult.payload.view.quoteRows[1].requestedCopies == 500
        and wrapperResult and wrapperResult.payload.view.step == "wrapping"
        and wrapperResult.payload.view.pallets[2].palletId == "JOB-0002-P01"
        and officeGrantPacket ~= nil and deniedGrantPacket ~= nil and fivePalletGrantPacket ~= nil
        and #customerGrantPacket <= Protocol.MAX_PACKET_BYTES
        and #printResultPacket <= Protocol.MAX_PACKET_BYTES
        and #wrapperResultPacket <= Protocol.MAX_PACKET_BYTES
        and #fivePalletGrantPacket <= Protocol.MAX_PACKET_BYTES
        and missingGrantedLease == nil and deniedWithLease == nil
        and invalidOfficeView == nil and inconsistentQuoteView == nil
        and inconsistentWrapperView == nil and arbitraryResultState == nil)

    local acquirePacket = Protocol.encode("workshop_acquire", {
        sessionId = "session-001", requestId = 19,
        resourceId = "skid_wrapper", expectedRevision = 10,
    })
    local invalidAcquireResource = Protocol.encode("workshop_acquire", {
        sessionId = "session-001", requestId = 19,
        resourceId = "press", expectedRevision = 10,
    })
    local spoofedAcquire = Protocol.encode("workshop_acquire", {
        sessionId = "session-001", requestId = 19,
        resourceId = "skid_wrapper", expectedRevision = 10, playerId = 2,
    })
    local releasePacket = Protocol.encode("workshop_release", {
        sessionId = "session-001", requestId = 20, leaseId = "lease-wrapper-2",
        resourceId = "skid_wrapper", reason = "cancelled",
    })
    local invalidReleaseReason = Protocol.encode("workshop_release", {
        sessionId = "session-001", requestId = 20, leaseId = "lease-wrapper-2",
        resourceId = "skid_wrapper", reason = "disconnect_everyone",
    })
    local spoofedRelease = Protocol.encode("workshop_release", {
        sessionId = "session-001", requestId = 20, leaseId = "lease-wrapper-2",
        resourceId = "skid_wrapper", reason = "closed", ownerPlayerId = 2,
    })
    local wrongResultAction = Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 21, resourceId = "office_computer",
        action = "start_cycle", accepted = false, code = "rejected",
        message = "Rejected.", revision = 10,
    })
    check("network_protocol_workshop_lifecycle_messages_are_correlated_and_unspoofable",
        acquirePacket ~= nil and releasePacket ~= nil
        and invalidAcquireResource == nil and spoofedAcquire == nil
        and invalidReleaseReason == nil and spoofedRelease == nil and wrongResultAction == nil)

    local workshopSnapshotPacket = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = workshopResources(),
        wrapper = {
            step = "wrapping", progress = 1.5, cycleTime = 3,
            selectedPalletId = "JOB-0001-P01", palletId = "JOB-0001-P01",
            pallets = wrapperView("idle").pallets,
        },
    })
    local workshopSnapshot = workshopSnapshotPacket and Protocol.decode(workshopSnapshotPacket)
    local duplicateResources = workshopResources()
    duplicateResources[3].resourceId = "reception_customer"
    local duplicateWorkshopSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = duplicateResources,
        wrapper = wrapperSnapshot("idle", {}),
    })
    local incompleteWorkshopSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11,
        resources = Codec.array({
            { resourceId = "reception_customer", revision = 4, occupied = false },
            { resourceId = "office_computer", revision = 1, occupied = false },
        }),
        wrapper = wrapperSnapshot("idle", {}),
    })
    local vacantOwnerSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11,
        resources = Codec.array({
            { resourceId = "reception_customer", revision = 4,
                occupied = false, ownerPlayerId = 2 },
            { resourceId = "office_computer", revision = 1, occupied = false },
            { resourceId = "skid_wrapper", revision = 2, occupied = false },
        }),
        wrapper = wrapperSnapshot("idle", {}),
    })
    local invalidRuntimeSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = workshopResources(),
        wrapper = { step = "finished", progress = 2.9, cycleTime = 3,
            selectedPalletId = "JOB-0001-P01", palletId = "JOB-0001-P01",
            pallets = Codec.array({}) },
    })
    local arbitraryRuntime = wrapperSnapshot("idle", {})
    arbitraryRuntime.sound = "start"
    local arbitraryRuntimeSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = workshopResources(),
        wrapper = arbitraryRuntime,
    })
    local fractionalResourceRevision = workshopResources()
    fractionalResourceRevision[1].revision = 1.5
    local invalidResourceRevisionSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = fractionalResourceRevision,
        wrapper = wrapperSnapshot("idle", {}),
    })
    local missingPalletListSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = workshopResources(),
        wrapper = { step = "idle", progress = 0, cycleTime = 3 },
    })
    local sixPallets = {}
    for index = 1, 6 do
        sixPallets[index] = {
            palletId = "JOB-000" .. index .. "-P01",
            jobLabel = "Client " .. index,
            packaging = index % 2 == 0 and "boxed" or "flat",
            distance = index * 10,
        }
    end
    local oversizedPalletListSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = workshopResources(),
        wrapper = wrapperSnapshot("idle", sixPallets),
    })
    local spoofedPalletListSnapshot = Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = workshopResources(),
        wrapper = wrapperSnapshot("idle", {
            { palletId = "JOB-0001-P01", jobLabel = "Client 1", packaging = "flat",
                distance = 10, hostX = 326, hostY = 338 },
        }),
    })
    check("network_protocol_workshop_snapshot_repairs_occupancy_runtime_and_live_pallets",
        workshopSnapshot and workshopSnapshot.payload.revision == 11
        and workshopSnapshot.payload.resources[1].resourceId == "office_computer"
        and workshopSnapshot.payload.resources[1].revision == 1
        and workshopSnapshot.payload.resources[2].ownerPlayerId == 2
        and workshopSnapshot.payload.wrapper.step == "wrapping"
        and workshopSnapshot.payload.wrapper.progress == 1.5
        and #workshopSnapshot.payload.wrapper.pallets == 2
        and workshopSnapshot.payload.wrapper.pallets[1].palletId == "JOB-0001-P01"
        and #workshopSnapshotPacket <= Protocol.MAX_PACKET_BYTES
        and duplicateWorkshopSnapshot == nil and incompleteWorkshopSnapshot == nil
        and vacantOwnerSnapshot == nil and invalidRuntimeSnapshot == nil
        and arbitraryRuntimeSnapshot == nil and invalidResourceRevisionSnapshot == nil
        and missingPalletListSnapshot == nil and oversizedPalletListSnapshot == nil
        and spoofedPalletListSnapshot == nil)

    local environmentPacket = Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "opening", progress = 0.4 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    })
    local environmentEnvelope = environmentPacket and Protocol.decode(environmentPacket)
    local invalidClosedDoor = Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "closed", progress = 0.1 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    })
    local invalidAbsentTruck = Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "closed", progress = 0 },
        truck = {
            state = "absent", jobId = "JOB-0001", mode = "delivery",
            backingProgress = 0, cargoProgress = 0,
        },
    })
    local invalidTruckProgress = Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "closed", progress = 0 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 1.1 },
    })
    local extraEnvironmentField = Protocol.encode("environment_snapshot", {
        sessionId = "session-001", serverTick = 42,
        bayDoor = { state = "closed", progress = 0, frame = 1 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    })
    check("network_protocol_environment_snapshot_is_strict_and_semantically_bounded",
        environmentEnvelope and environmentEnvelope.payload.serverTick == 42
        and environmentEnvelope.payload.bayDoor.state == "opening"
        and environmentEnvelope.payload.bayDoor.progress == 0.4
        and environmentEnvelope.payload.truck.state == "absent"
        and #environmentPacket <= Protocol.MAX_PACKET_BYTES
        and invalidClosedDoor == nil and invalidAbsentTruck == nil
        and invalidTruckProgress == nil and extraEnvironmentField == nil)

    local safeShopPacket = Protocol.encode("shop_snapshot", {
        sessionId = "session-001",
        revision = 0,
        state = {
            inventory = { paper = 2500, stock = { shipping_cartons = 2 } },
            jobs = Codec.array({ { id = "JOB-0001", status = "in_production" } }),
        },
        player = { x = 420, y = 520, character = "rabbit-worker" },
    })
    local safeShop = safeShopPacket and Protocol.decode(safeShopPacket)
    local unsafeShopPacket = Protocol.encode("shop_snapshot", {
        sessionId = "session-001",
        revision = 0,
        state = { callback = function() return "not data" end },
        player = { x = 1, y = 2 },
    })
    local unsafeShopEnvelope = Protocol.make("shop_snapshot", {
        sessionId = "session-001",
        revision = 0,
        state = { callback = function() return "not data" end },
        player = { x = 1, y = 2 },
    })
    local chunk = string.rep("x", 110000)
    local oversizedShopPacket = Protocol.encode("shop_snapshot", {
        sessionId = "session-001",
        revision = 0,
        state = { chunks = Codec.array({ chunk, chunk, chunk, chunk, chunk }) },
        player = { x = 1, y = 2 },
    })
    local unrevisionedShopPacket = Protocol.encode("shop_snapshot", {
        sessionId = "session-001", state = {}, player = { x = 1, y = 2 },
    })
    check("network_protocol_shop_snapshot_is_safe_and_separately_bounded",
        safeShop and safeShop.payload.state.inventory.paper == 2500
        and safeShop.payload.revision == 0
        and safeShop.payload.player.character == "rabbit-worker"
        and Protocol.packetLimitFor("shop_snapshot") == Protocol.MAX_SHOP_SNAPSHOT_BYTES
        and unsafeShopPacket == nil and unsafeShopEnvelope == nil
        and oversizedShopPacket == nil and unrevisionedShopPacket == nil)

    local safeStatePacket = Protocol.encode("shop_state", {
        sessionId = "session-001",
        revision = 8,
        state = {
            inventory = { paper = 2250, stock = { shipping_cartons = 5 } },
            calendar = { year = 1, month = 1, day = 5, hour = 10, minute = 30 },
            jobs = { active = Codec.array({ { id = "JOB-0002", status = "accepted" } }) },
        },
    })
    local safeState = safeStatePacket and Protocol.decode(safeStatePacket)
    local invalidRevision = Protocol.encode("shop_state", {
        sessionId = "session-001", revision = -1, state = {},
    })
    local extraStateField = Protocol.encode("shop_state", {
        sessionId = "session-001", revision = 8, state = {}, player = {},
    })
    local unsafeStatePacket = Protocol.encode("shop_state", {
        sessionId = "session-001", revision = 8,
        state = { callback = function() return "not data" end },
    })
    local oversizedStatePacket = Protocol.encode("shop_state", {
        sessionId = "session-001", revision = 8,
        state = { chunks = Codec.array({ chunk, chunk, chunk, chunk, chunk }) },
    })
    check("network_protocol_shop_state_is_revisioned_safe_and_snapshot_bounded",
        safeState and safeState.payload.revision == 8
        and safeState.payload.state.inventory.paper == 2250
        and Protocol.packetLimitFor("shop_state") == Protocol.MAX_SHOP_SNAPSHOT_BYTES
        and invalidRevision == nil and extraStateField == nil
        and unsafeStatePacket == nil and oversizedStatePacket == nil)

    local liveState = SaveSchema.snapshot(context.state)
    local livePacket, liveEncodeError = Protocol.encode("shop_snapshot", {
        sessionId = "live-save-contract",
        revision = 0,
        state = liveState,
        player = context.world.snapshot(),
    })
    local liveEnvelope, liveDecodeError
    if livePacket then liveEnvelope, liveDecodeError = Protocol.decode(livePacket) end
    check("network_protocol_current_save_schema_round_trips_as_shop_snapshot",
        livePacket ~= nil and #livePacket <= Protocol.MAX_SHOP_SNAPSHOT_BYTES
        and liveEnvelope ~= nil and liveEnvelope.payload.state.money == liveState.money
        and type(liveEnvelope.payload.state.inventory) == "table"
        and liveEnvelope.payload.player.character == context.world.player.character,
        tostring(liveEncodeError or liveDecodeError or (livePacket and #livePacket) or "unknown failure"))

    local spawnX, spawnY = context.world.resolveNetworkSpawn(
        context.world.player.x, context.world.player.y, 2,
        context.assets, context.state, { context.world.player })
    check("network_guest_spawn_resolver_returns_walkable_shop_position",
        type(spawnX) == "number" and type(spawnY) == "number"
        and context.Navigation.isWalkable(context.assets, spawnX, spawnY, {}))

    local routesCorrect = Protocol.VERSION == 4 and Protocol.CHANNEL_COUNT == 3
        and Protocol.CHANNEL_CONTROL == 0 and Protocol.CHANNEL_STATE == 1
        and Protocol.CHANNEL_DURABLE == 2 and Protocol.MAX_PLAYERS == 4
    local routeSummary = {}
    for _, kind in ipairs({
        "hello", "welcome", "interaction_request", "interaction_result",
        "workshop_acquire", "workshop_grant", "workshop_command", "workshop_result",
        "workshop_release", "leave", "error",
    }) do
        local channel, delivery = Protocol.route(kind)
        routeSummary[#routeSummary + 1] = kind .. "=" .. tostring(channel) .. "/" .. tostring(delivery)
        routesCorrect = routesCorrect
            and channel == Protocol.CHANNEL_CONTROL and delivery == "reliable"
    end
    for _, kind in ipairs({
        "input", "snapshot", "visitor_snapshot", "environment_snapshot", "workshop_snapshot",
        "ping", "pong",
    }) do
        local channel, delivery = Protocol.route(kind)
        routeSummary[#routeSummary + 1] = kind .. "=" .. tostring(channel) .. "/" .. tostring(delivery)
        routesCorrect = routesCorrect
            and channel == Protocol.CHANNEL_STATE and delivery == "unreliable"
    end
    local durableChannel, durableDelivery = Protocol.route("shop_state")
    local joinStateChannel, joinStateDelivery = Protocol.route("shop_snapshot")
    routesCorrect = routesCorrect
        and durableChannel == Protocol.CHANNEL_DURABLE and durableDelivery == "reliable"
        and joinStateChannel == Protocol.CHANNEL_DURABLE and joinStateDelivery == "reliable"
    for _, kind in ipairs({
        "workshop_acquire", "workshop_grant", "workshop_command", "workshop_result",
        "workshop_release", "workshop_snapshot",
    }) do
        routesCorrect = routesCorrect
            and Protocol.packetLimitFor(kind) == Protocol.MAX_PACKET_BYTES
    end
    check("network_protocol_routes_match_three_channel_contract", routesCorrect,
        string.format("version=%s channels=%s/%s/%s count=%s durable=%s/%s",
            tostring(Protocol.VERSION), tostring(Protocol.CHANNEL_CONTROL),
            tostring(Protocol.CHANNEL_STATE), tostring(Protocol.CHANNEL_DURABLE),
            tostring(Protocol.CHANNEL_COUNT), tostring(durableChannel),
            tostring(durableDelivery)) .. " join=" .. tostring(joinStateChannel)
            .. "/" .. tostring(joinStateDelivery)
            .. " routes=" .. table.concat(routeSummary, ","))

    local visitorPacket = Protocol.encode("visitor_snapshot", {
        sessionId = "session-001",
        serverTick = 42,
        customer = visitor("reviewing", true, 612, 318),
        vendor = visitor("scheduled", false, 500, 300),
    })
    local visitorEnvelope = visitorPacket and Protocol.decode(visitorPacket)
    local invalidVisitorTick = Protocol.encode("visitor_snapshot", {
        sessionId = "session-001", serverTick = -1, customer = {}, vendor = {},
    })
    local unsafeVisitor = Protocol.encode("visitor_snapshot", {
        sessionId = "session-001", serverTick = 42,
        customer = { callback = function() end }, vendor = {},
    })
    check("network_protocol_visitor_snapshot_round_trips_as_bounded_realtime_data",
        visitorEnvelope and visitorEnvelope.payload.serverTick == 42
        and visitorEnvelope.payload.customer.state == "reviewing"
        and visitorEnvelope.payload.vendor.visible == false
        and #visitorPacket <= Protocol.MAX_PACKET_BYTES
        and invalidVisitorTick == nil and unsafeVisitor == nil)

    local pingPacket = Protocol.encode("ping", { sessionId = "session-001", nonce = 3 })
    local malformed = Protocol.decode("return {payload={}}")
    local trailingPacket = pingPacket and Protocol.decode(pingPacket .. "x")
    local wrongVersionPacket = Codec.encode({
        version = Protocol.VERSION + 1,
        type = "ping",
        payload = { sessionId = "session-001", nonce = 3 },
    })
    local decodedWrongVersion = wrongVersionPacket and Protocol.decode(wrongVersionPacket)
    local hugePacket = Protocol.decode(string.rep("x", Protocol.MAX_SHOP_SNAPSHOT_BYTES + 1))
    check("network_protocol_decode_rejects_malformed_trailing_wrong_version_and_huge_packets",
        malformed == nil and trailingPacket == nil and decodedWrongVersion == nil and hugePacket == nil)
end

return Test
