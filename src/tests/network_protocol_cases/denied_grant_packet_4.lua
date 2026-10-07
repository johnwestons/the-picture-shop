-- Network wire validation and codec regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.deniedGrantPacket = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "office_computer",
        granted = false, code = "occupied", message = "Computer is in use.", revision = 10,
    })
    Context.fivePalletView = Context.receptionView(true)
    Context.fiveRows = {}
    for number = 1, 5 do
        Context.fiveRows[number] = { number = number, sheetCount = 525, requiredLifts = 2,
            requestedCopies = 500, spoilageAllowance = 25 }
    end
    Context.fivePalletView.quoteRows = Context.Codec.array(Context.fiveRows)
    Context.fivePalletGrantPacket = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "reception_customer",
        granted = true, leaseId = "lease-customer-2", code = "granted",
        message = "Customer counter acquired.", revision = 10, view = Context.fivePalletView,
    })
    Context.missingGrantedLease = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "office_computer",
        granted = true, code = "granted", message = "Granted.", revision = 10,
    })
    Context.deniedWithLease = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "office_computer",
        granted = false, leaseId = "forged-lease", code = "occupied",
        message = "Computer is in use.", revision = 10,
    })
    Context.invalidOfficeView = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "office_computer",
        granted = true, leaseId = "lease-office-2", code = "granted",
        message = "Granted.", revision = 10, view = { state = {} },
    })
    Context.invalidJackView = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 16, resourceId = "pallet_jack",
        granted = true, leaseId = "lease-jack-2", code = "granted",
        message = "Granted.", revision = 10, view = { x = 560, y = 520 },
    })
    Context.invalidQuoteView = Context.receptionView(true)
    Context.invalidQuoteView.quoteRows[1].spoilageAllowance = 24
    Context.inconsistentQuoteView = Context.Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 17, resourceId = "reception_customer",
        action = "submit_quote", accepted = false, code = "changed",
        message = "Changed.", revision = 10, view = Context.invalidQuoteView,
    })
    Context.invalidWrapperView = Context.wrapperView("wrapping")
    Context.invalidWrapperView.progress = Context.invalidWrapperView.cycleTime
    Context.inconsistentWrapperView = Context.Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 18, resourceId = "skid_wrapper",
        action = "start_cycle", accepted = false, code = "busy",
        message = "Busy.", revision = 10, view = Context.invalidWrapperView,
    })
    Context.arbitraryResultState = Context.Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 18, resourceId = "skid_wrapper",
        action = "start_cycle", accepted = false, code = "busy",
        message = "Busy.", revision = 10, state = { inventory = {} },
    })
    Context.cutterViews.conflicting = Context.cutterView({ paper = Context.cutterViews.loaded.paper })
    Context.cutterViews.conflictingGrant = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 17, resourceId = "cutter",
        granted = true, leaseId = "lease-cutter-2", code = "granted",
        message = "Granted.", revision = 11, view = Context.cutterViews.conflicting,
    })
    Context.cutterViews.invalidMemory = Context.cutterView()
    Context.cutterViews.invalidMemory.memoryCentiInch = Context.Codec.array({ 100, 200, 300, 400 })
    Context.cutterViews.invalidMemoryGrant = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 17, resourceId = "cutter",
        granted = true, leaseId = "lease-cutter-2", code = "granted",
        message = "Granted.", revision = 11, view = Context.cutterViews.invalidMemory,
    })
    Context.cutterViews.tooManyCandidates = Context.cutterView({
        candidates = Context.Codec.array({
            { palletId = "JOB-1-P01", distancePixels = 1 },
            { palletId = "JOB-2-P01", distancePixels = 2 },
            { palletId = "JOB-3-P01", distancePixels = 3 },
            { palletId = "JOB-4-P01", distancePixels = 4 },
        }),
    })
    Context.cutterViews.tooManyCandidatesGrant = Context.Protocol.encode("workshop_grant", {
        sessionId = "session-001", requestId = 17, resourceId = "cutter",
        granted = true, leaseId = "lease-cutter-2", code = "granted",
        message = "Granted.", revision = 11, view = Context.cutterViews.tooManyCandidates,
    })
    Context.check("network_protocol_workshop_views_are_host_authored_strict_and_resource_specific",
        Context.customerGrant and Context.customerGrant.payload.view.jobId == "JOB-0001"
        and Context.customerGrant.payload.view.difficulty == "easy"
        and Context.customerGrant.payload.view.quoteRows[2].price == 90
        and Context.printResult and Context.printResult.payload.view.printJob == true
        and Context.printResult.payload.view.difficulty == "medium"
        and Context.printResult.payload.view.quoteRows[1].requestedCopies == 500
        and Context.wrapperResult and Context.wrapperResult.payload.view.step == "wrapping"
        and Context.wrapperResult.payload.view.pallets[2].palletId == "JOB-0002-P01"
        and Context.officeGrantPacket ~= nil and Context.jackGrantPacket ~= nil
        and Context.cutterViews.vendorGrant
        and Context.cutterViews.vendorGrant.payload.view.items[1].name
            == "House paper, 1,000 sheets"
        and Context.cutterViews.vendorMachinePacket ~= nil
        and Context.cutterViews.invalidVendorPacket == nil
        and #Context.cutterViews.vendorGrantPacket <= Context.Protocol.MAX_PACKET_BYTES
        and Context.cutterViews.grant
        and Context.cutterViews.grant.payload.view.paper.selectedCut.edge == "bottom"
        and Context.cutterViews.grant.payload.view.memoryCentiInch[2] == 900
        and Context.deniedGrantPacket ~= nil and Context.fivePalletGrantPacket ~= nil
        and #Context.customerGrantPacket <= Context.Protocol.MAX_PACKET_BYTES
        and #Context.printResultPacket <= Context.Protocol.MAX_PACKET_BYTES
        and #Context.wrapperResultPacket <= Context.Protocol.MAX_PACKET_BYTES
        and #Context.cutterViews.grantPacket <= Context.Protocol.MAX_PACKET_BYTES
        and Context.maximumCutterGrantPacket ~= nil
        and #Context.maximumCutterGrantPacket <= Context.Protocol.MAX_PACKET_BYTES
        and #Context.fivePalletGrantPacket <= Context.Protocol.MAX_PACKET_BYTES
        and Context.missingGrantedLease == nil and Context.deniedWithLease == nil
        and Context.invalidOfficeView == nil and Context.invalidJackView == nil
        and Context.inconsistentQuoteView == nil
        and Context.inconsistentWrapperView == nil and Context.arbitraryResultState == nil
        and Context.cutterViews.conflictingGrant == nil
        and Context.cutterViews.invalidMemoryGrant == nil
        and Context.cutterViews.tooManyCandidatesGrant == nil)

    do
        local function packet(paper)
            local view = Context.loadedCutterView()
            view.paper = paper
            return Context.Protocol.encode("cutter_snapshot", {
                sessionId = "session-001", serverTick = 300,
                resourceRevision = 12, view = view,
            })
        end
        local paper = Context.loadedCutterView().paper
        paper.widthCentiInch, paper.heightCentiInch, paper.offSpec = 1, 100000, true
        local encoded = packet(paper)
        local decoded = encoded and Context.Protocol.decode(encoded)
        Context.check("network_protocol_cutter_actual_geometry_and_spoil_are_bounded",
            decoded and decoded.payload.view.paper.widthCentiInch == 1
            and decoded.payload.view.paper.heightCentiInch == 100000
            and decoded.payload.view.paper.offSpec and #encoded <= Context.Protocol.MAX_PACKET_BYTES)
        paper.widthCentiInch = 0
        local zero = packet(paper)
        paper.widthCentiInch = 1.5
        local fractional = packet(paper)
        paper.widthCentiInch = 100001
        local excessive = packet(paper)
        paper.widthCentiInch, paper.offSpec = 1, "true"
        local flag = packet(paper)
        paper.offSpec, paper.heightCentiInch = true, nil
        local partial = packet(paper)
        Context.check("network_protocol_cutter_rejects_invalid_or_partial_geometry",
            not zero and not fractional and not excessive and not flag and not partial)
    end

    do
        local function grant(view, resourceId)
            return Context.Protocol.encode("workshop_grant", {
                sessionId = "session-001", requestId = 18,
                resourceId = resourceId or "windmill", granted = true,
                leaseId = "lease-windmill-2", code = "granted",
                message = "Windmill console acquired.", revision = 12, view = view,
            })
        end

        local validGrantPacket = grant(Context.runningWindmillView())
        local validGrant = validGrantPacket and Context.Protocol.decode(validGrantPacket)
        local validResultPacket = Context.Protocol.encode("workshop_result", {
            sessionId = "session-001", commandId = 19, resourceId = "windmill",
            action = "setup_action", accepted = true, code = "accepted",
            message = "Setup input accepted.", revision = 13,
            view = Context.windmillView({
                status = "setup", setupTask = "chase",
                setupPermille = Context.Codec.array({ 250, 0, 0, 0, 0, 0 }),
            }),
        })
        local validResult = validResultPacket and Context.Protocol.decode(validResultPacket)
        local maximumView = Context.windmillView({
            runtimeRevision = 4294967295,
            status = "stock_shortage",
            speed = 5500,
            counter = 4294967295,
            goodSheets = 4294967295,
            spoilage = 4294967295,
            targetSheets = 4294967295,
            feedStart = 4294967295,
            feedRemaining = 4294967295,
            setupPermille = Context.Codec.array({ 1000, 1000, 1000, 1000, 1000, 1000 }),
            candidates = Context.Codec.array({
                { palletId = "JOB-MAX-01", colorIndex = 1 },
                { palletId = "JOB-MAX-02", colorIndex = 2 },
                { palletId = "JOB-MAX-03", colorIndex = 4 },
            }),
            serviceStep = "task",
            servicePermille = 1000,
            plateMarkerPermille = 1000,
            colorIndex = 4,
            colorCount = 4,
            proofPermille = 1000,
            setupTask = "register",
            setupSummary = "Maximum safe setup",
            serviceTask = "Lubrication",
        })
        local maximumGrantPacket = grant(maximumView)

        local invalid = {}
        invalid.missingRequired = Context.windmillView()
        invalid.missingRequired.motor = nil
        invalid.missingRequired = grant(invalid.missingRequired)
        invalid.extraField = Context.windmillView({ operatorPlayerId = 2 })
        invalid.extraField = grant(invalid.extraField)
        invalid.status = grant(Context.windmillView({ status = "maintenance" }))
        invalid.lowSpeed = grant(Context.windmillView({ speed = 999 }))
        invalid.highSpeed = grant(Context.windmillView({ speed = 5501 }))
        invalid.fractionalSpeed = grant(Context.windmillView({ speed = 2800.5 }))
        invalid.boolean = grant(Context.windmillView({ motor = 1 }))
        invalid.negativeCounter = grant(Context.windmillView({ counter = -1 }))
        invalid.overflowCounter = grant(Context.windmillView({ counter = 4294967296 }))
        invalid.fractionalCounter = grant(Context.windmillView({ counter = 1.5 }))
        invalid.shortSetup = grant(Context.windmillView({
            setupPermille = Context.Codec.array({ 0, 0, 0, 0, 0 }),
        }))
        invalid.fractionalSetup = grant(Context.windmillView({
            setupPermille = Context.Codec.array({ 0, 0, 0, 0, 0, 1.5 }),
        }))
        invalid.tooManyCandidates = grant(Context.windmillView({
            candidates = Context.Codec.array({
                { palletId = "JOB-1", colorIndex = 1 },
                { palletId = "JOB-2", colorIndex = 2 },
                { palletId = "JOB-3", colorIndex = 3 },
                { palletId = "JOB-4", colorIndex = 4 },
            }),
        }))
        invalid.duplicateCandidate = grant(Context.windmillView({
            candidates = Context.Codec.array({
                { palletId = "JOB-DUP", colorIndex = 1 },
                { palletId = "JOB-DUP", colorIndex = 2 },
            }),
        }))
        invalid.candidateColor = grant(Context.windmillView({
            candidates = Context.Codec.array({ { palletId = "JOB-1", colorIndex = 5 } }),
        }))
        invalid.optionalColor = grant(Context.windmillView({ colorIndex = 5 }))
        invalid.serviceStep = grant(Context.windmillView({ serviceStep = "running" }))
        invalid.servicePermille = grant(Context.windmillView({ servicePermille = 1001 }))
        invalid.platePermille = grant(Context.windmillView({ plateMarkerPermille = -1 }))
        invalid.setupTask = grant(Context.windmillView({ setupTask = "guarding" }))
        invalid.resourceSpecific = grant(Context.windmillView(), "office_computer")

        local allInvalid = true
        for _, packet in pairs(invalid) do allInvalid = allInvalid and packet == nil end
        Context.check("network_protocol_windmill_views_are_strict_bounded_and_resource_specific",
            validGrant and validGrant.payload.view.status == "production"
            and validGrant.payload.view.counter == 125
            and validGrant.payload.view.colorCount == 4
            and Context.Codec.isArray(validGrant.payload.view.setupPermille)
            and Context.Codec.isArray(validGrant.payload.view.candidates)
            and validResult and validResult.payload.view.setupTask == "chase"
            and validResult.payload.view.setupPermille[1] == 250
            and #validGrantPacket <= Context.Protocol.MAX_PACKET_BYTES
            and #validResultPacket <= Context.Protocol.MAX_PACKET_BYTES
            and maximumGrantPacket ~= nil
            and #maximumGrantPacket <= Context.Protocol.MAX_PACKET_BYTES
            and allInvalid)
    end
end

return Component
