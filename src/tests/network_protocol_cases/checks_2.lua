-- Network wire validation and codec regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.runLeaveTickProtocolRegression(Context.check)

    Context.safeInteractionRequest = Context.Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    Context.decodedInteractionRequest = Context.safeInteractionRequest
        and Context.Protocol.decode(Context.safeInteractionRequest)
    Context.safeInteractionResult = Context.Protocol.encode("interaction_result", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        accepted = false, code = "out_of_range",
        message = "Move closer to the loading-bay wall switch.",
    })
    Context.decodedInteractionResult = Context.safeInteractionResult
        and Context.Protocol.decode(Context.safeInteractionResult)
    Context.zeroRequestId = Context.Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 0, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    Context.fractionalRequestId = Context.Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 1.5, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    Context.overflowingRequestId = Context.Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 4294967296, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    Context.unsupportedInteraction = Context.Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "computer",
        desiredState = "open",
    })
    Context.claimedIdentity = Context.Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "loadingBayDoor",
        desiredState = "open", playerId = 2,
    })
    Context.claimedPosition = Context.Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "loadingBayDoor",
        desiredState = "open", x = 300, y = 285,
    })
    Context.missingDesiredState = Context.Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "loadingBayDoor",
    })
    Context.invalidDesiredState = Context.Protocol.encode("interaction_request", {
        sessionId = "session-001", requestId = 9, targetKind = "loadingBayDoor",
        desiredState = "opening",
    })
    Context.nonBooleanResult = Context.Protocol.encode("interaction_result", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        accepted = 1, code = "accepted", message = "Opening.",
    })
    Context.malformedResultCode = Context.Protocol.encode("interaction_result", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        accepted = false, code = "bad\ncode", message = "Rejected.",
    })
    Context.extraResultField = Context.Protocol.encode("interaction_result", {
        sessionId = "session-001", requestId = 8, targetKind = "loadingBayDoor",
        accepted = false, code = "rejected", message = "Rejected.", retry = true,
    })
    Context.check("network_protocol_interaction_messages_are_strict_bounded_and_positionless",
        Context.decodedInteractionRequest
        and Context.decodedInteractionRequest.payload.requestId == 8
        and Context.decodedInteractionRequest.payload.targetKind == "loadingBayDoor"
        and Context.decodedInteractionRequest.payload.desiredState == "open"
        and Context.decodedInteractionResult
        and Context.decodedInteractionResult.payload.accepted == false
        and Context.decodedInteractionResult.payload.code == "out_of_range"
        and #Context.safeInteractionRequest <= Context.Protocol.MAX_PACKET_BYTES
        and #Context.safeInteractionResult <= Context.Protocol.MAX_PACKET_BYTES
        and Context.zeroRequestId == nil and Context.fractionalRequestId == nil
        and Context.overflowingRequestId == nil and Context.unsupportedInteraction == nil
        and Context.claimedIdentity == nil and Context.claimedPosition == nil
        and Context.missingDesiredState == nil and Context.invalidDesiredState == nil
        and Context.nonBooleanResult == nil and Context.malformedResultCode == nil
        and Context.extraResultField == nil)

    Context.validWorkshopCommands = {
        { resourceId = "reception_customer", action = "submit_quote", amount = 285 },
        { resourceId = "reception_customer", action = "decline" },
        { resourceId = "vendor", action = "purchase_stock", itemIndex = 2 },
        { resourceId = "vendor", action = "purchase_machine", itemIndex = 1 },
        { resourceId = "vendor", action = "dismiss" },
        { resourceId = "office_computer", action = "request_pickup", jobId = "JOB-0001" },
        { resourceId = "skid_wrapper", action = "select_pallet", palletId = "JOB-0001-P01" },
        { resourceId = "skid_wrapper", action = "start_cycle", palletId = "JOB-0001-P01" },
        { resourceId = "pallet_jack", action = "lift_pallet", palletId = "JOB-0001-P01" },
        { resourceId = "pallet_jack", action = "lower_pallet", palletId = "JOB-0001-P01" },
        { resourceId = "pallet_jack", action = "park_jack" },
        { resourceId = "cutter", action = "load_pallet", palletId = "JOB-0001-P01" },
        { resourceId = "cutter", action = "load_stock" },
        { resourceId = "cutter", action = "select_program", programIndex = 4 },
        { resourceId = "cutter", action = "set_gauge", gaugeCentiInch = 625 },
        { resourceId = "cutter", action = "auto_gauge" },
        { resourceId = "cutter", action = "save_gauge" },
        { resourceId = "cutter", action = "recall_gauge" },
        { resourceId = "cutter", action = "rotate_paper" },
        { resourceId = "cutter", action = "position_paper" },
        { resourceId = "cutter", action = "set_clamp", clamp = true },
        { resourceId = "cutter", action = "set_barrier", barrierClear = false },
        { resourceId = "cutter", action = "guarded_cut" },
        { resourceId = "cutter", action = "emergency_stop" },
        { resourceId = "cutter", action = "reset_safety" },
        { resourceId = "cutter", action = "return_to_pallet" },
        { resourceId = "cutter", action = "run_next_lift" },
        { resourceId = "windmill", action = "load_pallet", palletId = "JOB-0001-P01" },
        { resourceId = "windmill", action = "toggle_motor" },
        { resourceId = "windmill", action = "toggle_feeder" },
        { resourceId = "windmill", action = "toggle_impression" },
        { resourceId = "windmill", action = "speed_up" },
        { resourceId = "windmill", action = "speed_down" },
        { resourceId = "windmill", action = "emergency_stop" },
        { resourceId = "windmill", action = "reset_safety" },
        { resourceId = "windmill", action = "take_proof" },
        { resourceId = "windmill", action = "verify_artwork" },
        { resourceId = "windmill", action = "approve_proof" },
        { resourceId = "windmill", action = "start_run" },
        { resourceId = "windmill", action = "stop_run" },
        { resourceId = "windmill", action = "clean_unload" },
        { resourceId = "windmill", action = "order_plate", plateId = "PLATE-0001-C01" },
        { resourceId = "windmill", action = "begin_plate", plateId = "PLATE-0001-C01" },
        { resourceId = "windmill", action = "process_plate", plateId = "PLATE-0001-C01" },
        { resourceId = "windmill", action = "begin_setup", setupTask = "chase" },
        { resourceId = "windmill", action = "setup_action", setupAction = "align" },
        { resourceId = "windmill", action = "cancel_setup" },
        { resourceId = "windmill", action = "begin_service" },
        { resourceId = "windmill", action = "service_lockout" },
        { resourceId = "windmill", action = "service_task" },
        { resourceId = "windmill", action = "book_technician" },
    }
    -- Every visible setup control must survive the wire, not just the chase's
    -- first button. Keep the protocol allowlist independently validated.
    for _, task in ipairs(require("src.windmill").setupTasks()) do
        for _, control in ipairs(require("src.press_setup_games").controls(task)) do
            Context.validWorkshopCommands[#Context.validWorkshopCommands+1] = {
                resourceId="windmill", action="setup_action", setupAction=control[1],
            }
        end
    end
    Context.workshopCommandsValid = true
    for index, command in ipairs(Context.validWorkshopCommands) do
        local payload = {
            sessionId = "session-001",
            commandId = 100 + index,
            leaseId = "lease-guest-2",
            resourceId = command.resourceId,
            action = command.action,
            expectedRevision = 7,
            amount = command.amount,
            itemIndex = command.itemIndex,
            jobId = command.jobId,
            palletId = command.palletId,
            programIndex = command.programIndex,
            gaugeCentiInch = command.gaugeCentiInch,
            clamp = command.clamp,
            barrierClear = command.barrierClear,
            plateId = command.plateId,
            setupTask = command.setupTask,
            setupAction = command.setupAction,
        }
        local packet = Context.Protocol.encode("workshop_command", payload)
        local envelope = packet and Context.Protocol.decode(packet)
        Context.workshopCommandsValid = Context.workshopCommandsValid and packet ~= nil and envelope ~= nil
            and envelope.payload.resourceId == command.resourceId
            and envelope.payload.action == command.action
            and envelope.payload.amount == command.amount
            and envelope.payload.itemIndex == command.itemIndex
            and envelope.payload.jobId == command.jobId
            and envelope.payload.palletId == command.palletId
            and envelope.payload.programIndex == command.programIndex
            and envelope.payload.gaugeCentiInch == command.gaugeCentiInch
            and envelope.payload.clamp == command.clamp
            and envelope.payload.barrierClear == command.barrierClear
            and envelope.payload.plateId == command.plateId
            and envelope.payload.setupTask == command.setupTask
            and envelope.payload.setupAction == command.setupAction
            and #packet <= Context.Protocol.MAX_PACKET_BYTES
    end
    Context.wrongResourceAction = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "office_computer", action = "submit_quote",
        expectedRevision = 0, amount = 200,
    })
    Context.invalidCutterCommands = {}
    Context.invalidCutterCommands.missingVendorItem = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "vendor", action = "purchase_stock", expectedRevision = 0,
    })
    Context.invalidCutterCommands.clientVendorPrice = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "vendor", action = "purchase_stock", expectedRevision = 0,
        itemIndex = 1, amount = 1,
    })
    Context.missingActionArgument = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "skid_wrapper", action = "start_cycle", expectedRevision = 0,
    })
    Context.missingLiftPallet = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "pallet_jack", action = "lift_pallet", expectedRevision = 0,
    })
    Context.missingLowerPallet = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "pallet_jack", action = "lower_pallet", expectedRevision = 0,
    })
end

return Component
