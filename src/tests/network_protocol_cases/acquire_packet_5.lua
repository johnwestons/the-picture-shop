-- Network wire validation and codec regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.acquirePacket = Context.Protocol.encode("workshop_acquire", {
        sessionId = "session-001", requestId = 19,
        resourceId = "skid_wrapper", expectedRevision = 10,
    })
    Context.windmillAcquirePacket = Context.Protocol.encode("workshop_acquire", {
        sessionId = "session-001", requestId = 20,
        resourceId = "windmill", expectedRevision = 6,
    })
    Context.invalidAcquireResource = Context.Protocol.encode("workshop_acquire", {
        sessionId = "session-001", requestId = 19,
        resourceId = "press", expectedRevision = 10,
    })
    Context.spoofedAcquire = Context.Protocol.encode("workshop_acquire", {
        sessionId = "session-001", requestId = 19,
        resourceId = "skid_wrapper", expectedRevision = 10, playerId = 2,
    })
    Context.releasePacket = Context.Protocol.encode("workshop_release", {
        sessionId = "session-001", requestId = 20, leaseId = "lease-wrapper-2",
        resourceId = "skid_wrapper", reason = "cancelled",
    })
    Context.windmillReleasePacket = Context.Protocol.encode("workshop_release", {
        sessionId = "session-001", requestId = 21, leaseId = "lease-windmill-2",
        resourceId = "windmill", reason = "closed",
    })
    Context.invalidReleaseReason = Context.Protocol.encode("workshop_release", {
        sessionId = "session-001", requestId = 20, leaseId = "lease-wrapper-2",
        resourceId = "skid_wrapper", reason = "disconnect_everyone",
    })
    Context.spoofedRelease = Context.Protocol.encode("workshop_release", {
        sessionId = "session-001", requestId = 20, leaseId = "lease-wrapper-2",
        resourceId = "skid_wrapper", reason = "closed", ownerPlayerId = 2,
    })
    Context.wrongResultAction = Context.Protocol.encode("workshop_result", {
        sessionId = "session-001", commandId = 21, resourceId = "office_computer",
        action = "start_cycle", accepted = false, code = "rejected",
        message = "Rejected.", revision = 10,
    })
    Context.check("network_protocol_workshop_lifecycle_messages_are_correlated_and_unspoofable",
        Context.acquirePacket ~= nil and Context.windmillAcquirePacket ~= nil
        and Context.releasePacket ~= nil and Context.windmillReleasePacket ~= nil
        and Context.invalidAcquireResource == nil and Context.spoofedAcquire == nil
        and Context.invalidReleaseReason == nil and Context.spoofedRelease == nil and Context.wrongResultAction == nil)

    Context.workshopSnapshotPacket = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = Context.workshopResources(),
        wrapper = {
            step = "wrapping", progress = 1.5, cycleTime = 3,
            selectedPalletId = "JOB-0001-P01", palletId = "JOB-0001-P01",
            pallets = Context.wrapperView("idle").pallets,
        },
    })
    Context.workshopSnapshot = Context.workshopSnapshotPacket and Context.Protocol.decode(Context.workshopSnapshotPacket)
    Context.duplicateResources = Context.workshopResources()
    Context.duplicateResources[3].resourceId = "reception_customer"
    Context.duplicateWorkshopSnapshot = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = Context.duplicateResources,
        wrapper = Context.wrapperSnapshot("idle", {}),
    })
    Context.incompleteWorkshopSnapshot = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11,
        resources = Context.Codec.array({
            { resourceId = "reception_customer", revision = 4, occupied = false },
            { resourceId = "work_phone", revision = 0, occupied = false },
            { resourceId = "office_computer", revision = 1, occupied = false },
            { resourceId = "skid_wrapper", revision = 2, occupied = false },
        }),
        wrapper = Context.wrapperSnapshot("idle", {}),
    })
    Context.vacantOwnerSnapshot = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11,
        resources = Context.Codec.array({
            { resourceId = "reception_customer", revision = 4,
                occupied = false, ownerPlayerId = 2 },
            { resourceId = "office_computer", revision = 1, occupied = false },
            { resourceId = "skid_wrapper", revision = 2, occupied = false },
            { resourceId = "pallet_jack", revision = 3, occupied = false },
            { resourceId = "cutter", revision = 5, occupied = false },
            { resourceId = "windmill", revision = 6, occupied = false },
        }),
        wrapper = Context.wrapperSnapshot("idle", {}),
    })
    Context.invalidRuntimeSnapshot = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = Context.workshopResources(),
        wrapper = { step = "finished", progress = 2.9, cycleTime = 3,
            selectedPalletId = "JOB-0001-P01", palletId = "JOB-0001-P01",
            pallets = Context.Codec.array({}) },
    })
    Context.arbitraryRuntime = Context.wrapperSnapshot("idle", {})
    Context.arbitraryRuntime.sound = "start"
    Context.arbitraryRuntimeSnapshot = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = Context.workshopResources(),
        wrapper = Context.arbitraryRuntime,
    })
    Context.fractionalResourceRevision = Context.workshopResources()
    Context.fractionalResourceRevision[1].revision = 1.5
    Context.invalidResourceRevisionSnapshot = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = Context.fractionalResourceRevision,
        wrapper = Context.wrapperSnapshot("idle", {}),
    })
    Context.missingPalletListSnapshot = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = Context.workshopResources(),
        wrapper = { step = "idle", progress = 0, cycleTime = 3 },
    })
    Context.sixPallets = {}
    for index = 1, 6 do
        Context.sixPallets[index] = {
            palletId = "JOB-000" .. index .. "-P01",
            jobLabel = "Client " .. index,
            packaging = index % 2 == 0 and "boxed" or "flat",
            distance = index * 10,
        }
    end
    Context.oversizedPalletListSnapshot = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = Context.workshopResources(),
        wrapper = Context.wrapperSnapshot("idle", Context.sixPallets),
    })
    Context.spoofedPalletListSnapshot = Context.Protocol.encode("workshop_snapshot", {
        sessionId = "session-001", revision = 11, resources = Context.workshopResources(),
        wrapper = Context.wrapperSnapshot("idle", {
            { palletId = "JOB-0001-P01", jobLabel = "Client 1", packaging = "flat",
                distance = 10, hostX = 326, hostY = 338 },
        }),
    })
    Context.check("network_protocol_workshop_snapshot_repairs_occupancy_runtime_and_live_pallets",
        Context.workshopSnapshot and Context.workshopSnapshot.payload.revision == 11
        and #Context.workshopSnapshot.payload.resources == 10
        and Context.workshopSnapshot.payload.resources[1].resourceId == "cutter"
        and Context.workshopSnapshot.payload.resources[2].resourceId == "office_computer"
        and Context.workshopSnapshot.payload.resources[2].revision == 1
        and Context.workshopSnapshot.payload.resources[3].resourceId == "pallet_jack"
        and Context.workshopSnapshot.payload.resources[4].ownerPlayerId == 2
        and Context.workshopSnapshot.payload.resources[5].resourceId == "skid_wrapper"
        and Context.workshopSnapshot.payload.resources[6].resourceId == "truck"
        and Context.workshopSnapshot.payload.resources[7].resourceId == "vendor"
        and Context.workshopSnapshot.payload.resources[8].resourceId == "warehouse"
        and Context.workshopSnapshot.payload.resources[9].resourceId == "windmill"
        and Context.workshopSnapshot.payload.resources[9].revision == 6
        and Context.workshopSnapshot.payload.wrapper.step == "wrapping"
        and Context.workshopSnapshot.payload.wrapper.progress == 1.5
        and #Context.workshopSnapshot.payload.wrapper.pallets == 2
        and Context.workshopSnapshot.payload.wrapper.pallets[1].palletId == "JOB-0001-P01"
        and #Context.workshopSnapshotPacket <= Context.Protocol.MAX_PACKET_BYTES
        and Context.duplicateWorkshopSnapshot == nil and Context.incompleteWorkshopSnapshot == nil
        and Context.vacantOwnerSnapshot == nil and Context.invalidRuntimeSnapshot == nil
        and Context.arbitraryRuntimeSnapshot == nil and Context.invalidResourceRevisionSnapshot == nil
        and Context.missingPalletListSnapshot == nil and Context.oversizedPalletListSnapshot == nil
        and Context.spoofedPalletListSnapshot == nil)

    do
        local packets = {}
        packets.valid = Context.Protocol.encode("cutter_snapshot", {
            sessionId = "session-001", serverTick = 42, resourceRevision = 11,
            view = Context.loadedCutterView(),
        })
        packets.maximum = Context.Protocol.encode("cutter_snapshot", {
            sessionId = string.rep("S", 64), serverTick = 4294967295,
            resourceRevision = 4294967295, view = Context.maximumCutterView,
        })
        packets.decoded = packets.valid and Context.Protocol.decode(packets.valid)
        packets.invalidStep = Context.Protocol.encode("cutter_snapshot", {
            sessionId = "session-001", serverTick = 42, resourceRevision = 11,
            view = Context.cutterView({ step = "maintenance" }),
        })
        packets.invalidTick = Context.Protocol.encode("cutter_snapshot", {
            sessionId = "session-001", serverTick = 42.5, resourceRevision = 11,
            view = Context.cutterView(),
        })
        packets.extraField = Context.Protocol.encode("cutter_snapshot", {
            sessionId = "session-001", serverTick = 42, resourceRevision = 11,
            view = Context.cutterView(), operatorPlayerId = 2,
        })
        Context.check("network_protocol_cutter_snapshot_is_strict_bounded_and_revisioned",
            packets.decoded and packets.decoded.payload.serverTick == 42
            and packets.decoded.payload.resourceRevision == 11
            and packets.decoded.payload.view.paper.orientation == 90
            and #packets.valid <= Context.Protocol.MAX_PACKET_BYTES
            and packets.maximum ~= nil
            and #packets.maximum <= Context.Protocol.MAX_PACKET_BYTES
            and packets.invalidStep == nil and packets.invalidTick == nil
                and packets.extraField == nil)
    end

    do
        local maximumView = Context.windmillView({
            runtimeRevision = 4294967295,
            status = "pass_complete",
            speed = 5500,
            counter = 4294967295,
            goodSheets = 4294967295,
            spoilage = 4294967295,
            targetSheets = 4294967295,
            feedStart = 4294967295,
            feedRemaining = 4294967295,
            setupPermille = Context.Codec.array({ 1000, 1000, 1000, 1000, 1000, 1000 }),
            candidates = Context.Codec.array({
                { palletId = "JOB-MAX-1", colorIndex = 1 },
                { palletId = "JOB-MAX-2", colorIndex = 2 },
                { palletId = "JOB-MAX-3", colorIndex = 4 },
            }),
            serviceStep = "task",
            servicePermille = 1000,
            plateMarkerPermille = 1000,
        })
        local packets = {}
        packets.valid = Context.Protocol.encode("windmill_snapshot", {
            sessionId = "session-001", serverTick = 43, resourceRevision = 12,
            view = Context.runningWindmillView(),
        })
        packets.maximum = Context.Protocol.encode("windmill_snapshot", {
            sessionId = string.rep("S", 64), serverTick = 4294967295,
            resourceRevision = 4294967295, view = maximumView,
        })
        packets.decoded = packets.valid and Context.Protocol.decode(packets.valid)
        packets.invalidStatus = Context.Protocol.encode("windmill_snapshot", {
            sessionId = "session-001", serverTick = 43, resourceRevision = 12,
            view = Context.windmillView({ status = "running" }),
        })
        packets.invalidTick = Context.Protocol.encode("windmill_snapshot", {
            sessionId = "session-001", serverTick = 43.5, resourceRevision = 12,
            view = Context.windmillView(),
        })
        packets.invalidRevision = Context.Protocol.encode("windmill_snapshot", {
            sessionId = "session-001", serverTick = 43, resourceRevision = -1,
            view = Context.windmillView(),
        })
        packets.extraField = Context.Protocol.encode("windmill_snapshot", {
            sessionId = "session-001", serverTick = 43, resourceRevision = 12,
            view = Context.windmillView(), operatorPlayerId = 2,
        })
        Context.check("network_protocol_windmill_snapshot_is_strict_bounded_and_revisioned",
            packets.decoded and packets.decoded.payload.serverTick == 43
            and packets.decoded.payload.resourceRevision == 12
            and packets.decoded.payload.view.status == "production"
            and packets.decoded.payload.view.counter == 125
            and #packets.valid <= Context.Protocol.MAX_PACKET_BYTES
            and packets.maximum ~= nil
            and #packets.maximum <= Context.Protocol.MAX_PACKET_BYTES
            and packets.invalidStatus == nil and packets.invalidTick == nil
            and packets.invalidRevision == nil and packets.extraField == nil)
    end
end

return Component
