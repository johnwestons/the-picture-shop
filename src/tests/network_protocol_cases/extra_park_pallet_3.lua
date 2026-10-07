-- Network wire validation and codec regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.extraParkPallet = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "pallet_jack", action = "park_jack", expectedRevision = 0,
        palletId = "JOB-0001-P01",
    })
    Context.jackActionOnWrapper = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "skid_wrapper", action = "lift_pallet", expectedRevision = 0,
        palletId = "JOB-0001-P01",
    })
    Context.extraDeclineArgument = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "reception_customer", action = "decline", expectedRevision = 0,
        amount = 200,
    })
    Context.arbitraryArguments = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "skid_wrapper", action = "start_cycle", expectedRevision = 0,
        palletId = "JOB-0001-P01", args = { force = true },
    })
    Context.spoofedWorkshopCommand = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "skid_wrapper", action = "start_cycle", expectedRevision = 0,
        palletId = "JOB-0001-P01", playerId = 2, x = 326, y = 338,
    })
    Context.invalidQuoteAmount = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "reception_customer", action = "submit_quote", expectedRevision = 0,
        amount = 100000001,
    })
    Context.fractionalWorkshopRevision = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "reception_customer", action = "decline", expectedRevision = 0.5,
    })
    Context.invalidCutterCommands.missingProgramIndex = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "cutter", action = "select_program", expectedRevision = 0,
    })
    Context.invalidCutterCommands.fractionalProgramIndex = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "cutter", action = "select_program", expectedRevision = 0,
        programIndex = 2.5,
    })
    Context.invalidCutterCommands.invalidGauge = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "cutter", action = "set_gauge", expectedRevision = 0,
        gaugeCentiInch = 2501,
    })
    Context.invalidCutterCommands.invalidClamp = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "cutter", action = "set_clamp", expectedRevision = 0,
        clamp = 1,
    })
    Context.invalidCutterCommands.extraGuardedCutArgument = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "cutter", action = "guarded_cut", expectedRevision = 0,
        clamp = true,
    })
    Context.invalidWindmillCommands = {}
    Context.invalidWindmillCommands.missingPallet = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "windmill", action = "load_pallet", expectedRevision = 0,
    })
    Context.invalidWindmillCommands.missingSetupTask = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "windmill", action = "begin_setup", expectedRevision = 0,
    })
    Context.invalidWindmillCommands.unknownSetupTask = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "windmill", action = "begin_setup", expectedRevision = 0,
        setupTask = "guarding",
    })
    Context.invalidWindmillCommands.missingSetupAction = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "windmill", action = "setup_action", expectedRevision = 0,
    })
    Context.invalidWindmillCommands.unknownSetupAction = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "windmill", action = "setup_action", expectedRevision = 0,
        setupAction = "perfect_score",
    })
    Context.invalidWindmillCommands.clientScoredSetup = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "windmill", action = "setup_action", expectedRevision = 0,
        setupAction = "align", score = 1,
    })
    Context.invalidWindmillCommands.missingPlate = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "windmill", action = "process_plate", expectedRevision = 0,
    })
    Context.invalidWindmillCommands.clientPlateAccuracy = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "windmill", action = "process_plate", expectedRevision = 0,
        plateId = "PLATE-0001-C01", accuracy = 1,
    })
    Context.invalidWindmillCommands.extraNoArgument = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "windmill", action = "emergency_stop", expectedRevision = 0,
        palletId = "JOB-0001-P01",
    })
    Context.invalidWindmillCommands.crossResource = Context.Protocol.encode("workshop_command", {
        sessionId = "session-001", commandId = 1, leaseId = "lease-1",
        resourceId = "cutter", action = "toggle_motor", expectedRevision = 0,
    })
    Context.check("network_protocol_workshop_commands_use_closed_resource_action_scalar_unions",
        Context.workshopCommandsValid and Context.wrongResourceAction == nil and Context.missingActionArgument == nil
        and Context.invalidCutterCommands.missingVendorItem == nil
        and Context.invalidCutterCommands.clientVendorPrice == nil
        and Context.missingLiftPallet == nil and Context.missingLowerPallet == nil
        and Context.extraParkPallet == nil and Context.jackActionOnWrapper == nil
        and Context.extraDeclineArgument == nil and Context.arbitraryArguments == nil
        and Context.spoofedWorkshopCommand == nil and Context.invalidQuoteAmount == nil
        and Context.fractionalWorkshopRevision == nil
        and Context.invalidCutterCommands.missingProgramIndex == nil
        and Context.invalidCutterCommands.fractionalProgramIndex == nil
        and Context.invalidCutterCommands.invalidGauge == nil
        and Context.invalidCutterCommands.invalidClamp == nil
        and Context.invalidCutterCommands.extraGuardedCutArgument == nil
        and Context.invalidWindmillCommands.missingPallet == nil
        and Context.invalidWindmillCommands.missingSetupTask == nil
        and Context.invalidWindmillCommands.unknownSetupTask == nil
        and Context.invalidWindmillCommands.missingSetupAction == nil
        and Context.invalidWindmillCommands.unknownSetupAction == nil
        and Context.invalidWindmillCommands.clientScoredSetup == nil
        and Context.invalidWindmillCommands.missingPlate == nil
        and Context.invalidWindmillCommands.clientPlateAccuracy == nil
        and Context.invalidWindmillCommands.extraNoArgument == nil
        and Context.invalidWindmillCommands.crossResource == nil)

    Context.customerGrantPacket = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 12, resourceId = "reception_customer",
        granted = true, leaseId = "lease-customer-2", code = "granted",
        message = "Customer counter acquired.", revision = 8, view = Context.receptionView(false),
    })
    Context.customerGrant = Context.customerGrantPacket and Context.Protocol.decode(Context.customerGrantPacket)
    Context.printResultPacket = Context.Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 13, resourceId = "reception_customer",
        action = "submit_quote", accepted = false, code = "offer_changed",
        message = "The customer offer changed.", revision = 9, view = Context.receptionView(true),
    })
    Context.printResult = Context.printResultPacket and Context.Protocol.decode(Context.printResultPacket)
    Context.wrapperResultPacket = Context.Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 14, resourceId = "skid_wrapper",
        action = "start_cycle", accepted = true, code = "accepted",
        message = "Wrapping started.", revision = 10, view = Context.wrapperView("wrapping"),
    })
    Context.wrapperResult = Context.wrapperResultPacket and Context.Protocol.decode(Context.wrapperResultPacket)
    Context.officeGrantPacket = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 15, resourceId = "office_computer",
        granted = true, leaseId = "lease-office-2", code = "granted",
        message = "Office computer acquired.", revision = 10, view = {},
    })
    Context.cutterViews = { loaded = Context.loadedCutterView() }
    Context.cutterViews.vendorGrantPacket = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "vendor",
        granted = true, leaseId = "lease-vendor-2", code = "granted",
        message = "Vendor catalog acquired.", revision = 10, view = Context.vendorView(),
    })
    Context.cutterViews.vendorGrant = Context.cutterViews.vendorGrantPacket
        and Context.Protocol.decode(Context.cutterViews.vendorGrantPacket)
    Context.cutterViews.vendorMachinePacket = Context.Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 19, resourceId = "vendor",
        action = "purchase_machine", accepted = true, code = "machine_purchased",
        message = "Machine purchased.", revision = 11, view = Context.vendorView("machines"),
    })
    Context.cutterViews.invalidVendorView = Context.vendorView()
    Context.cutterViews.invalidVendorView.items[1].condition = 62
    Context.cutterViews.invalidVendorPacket = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "vendor",
        granted = true, leaseId = "lease-vendor-2", code = "granted",
        message = "Vendor catalog acquired.", revision = 10,
        view = Context.cutterViews.invalidVendorView,
    })
    Context.jackGrantPacket = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "pallet_jack",
        granted = true, leaseId = "lease-jack-2", code = "granted",
        message = "Pallet jack acquired.", revision = 10, view = {},
    })
    Context.cutterViews.grantPacket = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 17, resourceId = "cutter",
        granted = true, leaseId = "lease-cutter-2", code = "granted",
        message = "Cutter console acquired.", revision = 11, view = Context.cutterViews.loaded,
    })
    Context.cutterViews.grant = Context.cutterViews.grantPacket and Context.Protocol.decode(Context.cutterViews.grantPacket)
    Context.maximumCutterCandidates = {}
    for index = 1, 3 do
        Context.maximumCutterCandidates[index] = {
            palletId = string.rep("P", 63) .. tostring(index),
            distancePixels = 100000,
        }
    end
    Context.maximumCutterView = Context.cutterView({
        runtimeRevision = 4294967295,
        memoryCentiInch = Context.Codec.array({ 2500, 2500, 2500 }),
        candidates = Context.Codec.array(Context.maximumCutterCandidates),
        genericSheets = 100000,
    })
    Context.maximumCutterGrantPacket = Context.Protocol.encode("workshop_grant", {
        sessionId = string.rep("S", 64), requestId = 4294967295,
        resourceId = "cutter", granted = true, leaseId = string.rep("L", 64),
        code = string.rep("C", 32), message = string.rep("M", 160),
        revision = 4294967295, view = Context.maximumCutterView,
    })
end

return Component
