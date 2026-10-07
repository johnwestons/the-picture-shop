-- Multiplayer session regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.hostContext.getWorkshopSnapshot = function()
        return {
            resources = {
                { resourceId = "reception_customer", revision = 0, occupied = false },
                { resourceId = "vendor", revision = 0, occupied = false },
                { resourceId = "truck", revision = 0, occupied = false },
                { resourceId = "work_phone", revision = 0, occupied = false },
                { resourceId = "warehouse", revision = 0, occupied = false },
                { resourceId = "office_computer", revision = Context.workshopRevision,
                    occupied = Context.workshopLease ~= nil and Context.workshopResource == "office_computer",
                    ownerPlayerId = Context.workshopLease and Context.workshopResource == "office_computer"
                        and 2 or nil },
                { resourceId = "skid_wrapper", revision = Context.workshopRevision,
                    occupied = Context.workshopLease ~= nil and Context.workshopResource == "skid_wrapper",
                    ownerPlayerId = Context.workshopLease and Context.workshopResource == "skid_wrapper"
                        and 2 or nil },
                { resourceId = "pallet_jack", revision = Context.workshopRevision,
                    occupied = Context.workshopLease ~= nil and Context.workshopResource == "pallet_jack",
                    ownerPlayerId = Context.workshopLease and Context.workshopResource == "pallet_jack"
                        and 2 or nil },
                { resourceId = "cutter", revision = Context.workshopRevision,
                    occupied = Context.workshopLease ~= nil and Context.workshopResource == "cutter",
                    ownerPlayerId = Context.workshopLease and Context.workshopResource == "cutter"
                        and 2 or nil },
                { resourceId = "windmill", revision = Context.workshopRevision,
                    occupied = Context.workshopLease ~= nil and Context.workshopResource == "windmill",
                    ownerPlayerId = Context.workshopLease and Context.workshopResource == "windmill"
                        and 2 or nil },
            },
            wrapper = {
                step = "idle", progress = 0, cycleTime = 3,
                pallets = Context.workshopPallets,
            },
        }
    end

    Context.workshopRequested = Context.client:requestWorkshopAcquire("office_computer")
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.workshopGrant = Context.eventNamed(Context.client:drainEvents(), "workshop_grant")
    Context.acquireWire = Context.decodedPayload(
        Context.network:messages("client_to_host", "workshop_acquire")[1])
    Context.grantMessage = Context.network:messages("host_to_client", "workshop_grant")[1]
    Context.check("multiplayer_session_worker_acquires_host_owned_office_without_spoofable_identity",
        Context.workshopRequested and Context.workshopGrant and Context.workshopGrant.granted
        and Context.workshopGrant.leaseId == Context.workshopLease
        and Context.acquireWire and Context.acquireWire.resourceId == "office_computer"
        and Context.acquireWire.expectedRevision == 0
        and Context.acquireWire.playerId == nil and Context.acquireWire.x == nil and Context.acquireWire.y == nil
        and Context.workshopCalls[1] and Context.workshopCalls[1].player == Context.host.players[2]
        and Context.grantMessage and Context.grantMessage.channel == Context.Protocol.CHANNEL_CONTROL
        and Context.grantMessage.reliable and Context.client:workshopInfo().revision == 1)

    Context.workshopCommanded = Context.client:requestWorkshopCommand(
        "request_pickup", { jobId = "JOB-0001" })
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.workshopResult = Context.eventNamed(Context.client:drainEvents(), "workshop_result")
    Context.commandMessage = Context.network:messages("client_to_host", "workshop_command")[1]
    Context.commandWire = Context.decodedPayload(Context.commandMessage)
    Context.check("multiplayer_session_worker_command_is_semantic_reliable_and_updates_revision_once",
        Context.workshopCommanded and Context.workshopResult and Context.workshopResult.accepted
        and Context.workshopResult.action == "request_pickup" and Context.workshopMutation == 1
        and Context.commandWire and Context.commandWire.jobId == "JOB-0001"
        and Context.commandWire.expectedRevision == 1 and Context.commandWire.state == nil
        and Context.commandMessage.channel == Context.Protocol.CHANNEL_CONTROL and Context.commandMessage.reliable
        and Context.client:workshopInfo().revision == 2 and Context.workshopTouches > 0)

    Context.workshopReleased = Context.client:releaseWorkshop("closed")
    Context.host:update(0, Context.hostContext)
    Context.check("multiplayer_session_worker_release_clears_client_and_host_resource_ownership",
        Context.workshopReleased and Context.client:workshopInfo() == nil and Context.workshopLease == nil
        and Context.workshopRevision == 3 and Context.workshopCalls[#Context.workshopCalls].operation == "workshop_release")

    Context.workshopPallets = {}
    Context.wrapperRequested = Context.client:requestWorkshopAcquire("skid_wrapper")
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.wrapperGrant = Context.eventNamed(Context.client:drainEvents(), "workshop_grant")
    Context.host:update(0.09, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.emptyWrapperSnapshot = Context.eventNamed(Context.client:drainEvents(), "workshop_snapshot")

    Context.workshopPallets = {
        { palletId = "JOB-LIVE-P01", jobLabel = "Live Client · JOB-LIVE",
            packaging = "boxed", distance = 28 },
    }
    Context.host:update(0.09, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.liveWrapperSnapshot = Context.eventNamed(Context.client:drainEvents(), "workshop_snapshot")
    Context.workshopPackets = Context.network:messages("host_to_client", "workshop_snapshot")
    Context.liveWorkshopWire = Context.decodedPayload(Context.workshopPackets[#Context.workshopPackets])
    Context.check("multiplayer_session_open_wrapper_receives_empty_to_eligible_live_pallet_update",
        Context.wrapperRequested and Context.wrapperGrant and Context.wrapperGrant.granted
        and Context.wrapperGrant.resourceId == "skid_wrapper"
        and Context.wrapperGrant.view and #Context.wrapperGrant.view.pallets == 0
        and Context.emptyWrapperSnapshot and #Context.emptyWrapperSnapshot.wrapper.pallets == 0
        and Context.liveWrapperSnapshot and #Context.liveWrapperSnapshot.wrapper.pallets == 1
        and Context.liveWrapperSnapshot.wrapper.pallets[1].palletId == "JOB-LIVE-P01"
        and Context.liveWrapperSnapshot.wrapper.pallets[1].packaging == "boxed"
        and Context.liveWorkshopWire and #Context.liveWorkshopWire.wrapper.pallets == 1
        and #Context.workshopPackets[#Context.workshopPackets].payload <= Context.Protocol.MAX_PACKET_BYTES
        and Context.client:workshopInfo() and Context.client:workshopInfo().resourceId == "skid_wrapper")
    Context.client:releaseWorkshop("closed")
    Context.host:update(0, Context.hostContext)

    Context.jackRequested = Context.client:requestWorkshopAcquire("pallet_jack")
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.jackGrant = Context.eventNamed(Context.client:drainEvents(), "workshop_grant")
    Context.jackInfo = Context.client:workshopInfo()
    Context.check("multiplayer_session_worker_acquires_host_owned_pallet_jack_control",
        Context.jackRequested and Context.jackGrant and Context.jackGrant.granted
        and Context.jackGrant.resourceId == "pallet_jack"
        and Context.jackGrant.leaseId == "lease-jack-test"
        and Context.jackGrant.view and next(Context.jackGrant.view) == nil
        and Context.jackInfo and Context.jackInfo.resourceId == "pallet_jack"
        and Context.jackInfo.leaseId == "lease-jack-test")

    Context.commandsBeforeJack = #Context.network:messages("client_to_host", "workshop_command")
    Context.liftRequested = Context.client:requestWorkshopCommand(
        "lift_pallet", { palletId = "JOB-LIFT-P01" })
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.liftResult = Context.eventNamed(Context.client:drainEvents(), "workshop_result")
    Context.commandPackets = Context.network:messages("client_to_host", "workshop_command")
    Context.liftPacket = Context.commandPackets[Context.commandsBeforeJack + 1]
    Context.liftWire = Context.decodedPayload(Context.liftPacket)
    Context.liftRevision = Context.liftResult and Context.liftResult.revision

    Context.lowerRequested = Context.client:requestWorkshopCommand(
        "lower_pallet", { palletId = "JOB-LIFT-P01" })
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.lowerResult = Context.eventNamed(Context.client:drainEvents(), "workshop_result")
    Context.commandPackets = Context.network:messages("client_to_host", "workshop_command")
    Context.lowerPacket = Context.commandPackets[Context.commandsBeforeJack + 2]
    Context.lowerWire = Context.decodedPayload(Context.lowerPacket)
    Context.lowerRevision = Context.lowerResult and Context.lowerResult.revision

    -- Even if a caller accidentally supplies an argument, the session emits
    -- the closed park command shape: no coordinates and no pallet identity.
    Context.parkRequested = Context.client:requestWorkshopCommand(
        "park_jack", { palletId = "MUST-NOT-REACH-HOST", x = 999, y = 999 })
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.parkResult = Context.eventNamed(Context.client:drainEvents(), "workshop_result")
    Context.commandPackets = Context.network:messages("client_to_host", "workshop_command")
    Context.parkPacket = Context.commandPackets[Context.commandsBeforeJack + 3]
    Context.parkWire = Context.decodedPayload(Context.parkPacket)

    Context.jackCalls = {
        Context.workshopCalls[#Context.workshopCalls - 2],
        Context.workshopCalls[#Context.workshopCalls - 1],
        Context.workshopCalls[#Context.workshopCalls],
    }
    Context.check("multiplayer_session_pallet_jack_commands_serialize_exact_lift_lower_and_park_intent",
        Context.liftRequested and Context.lowerRequested and Context.parkRequested
        and Context.liftResult and Context.liftResult.accepted and Context.liftResult.action == "lift_pallet"
        and Context.lowerResult and Context.lowerResult.accepted and Context.lowerResult.action == "lower_pallet"
        and Context.parkResult and Context.parkResult.accepted and Context.parkResult.action == "park_jack"
        and Context.liftPacket and Context.liftPacket.channel == Context.Protocol.CHANNEL_CONTROL and Context.liftPacket.reliable
        and Context.lowerPacket and Context.lowerPacket.channel == Context.Protocol.CHANNEL_CONTROL and Context.lowerPacket.reliable
        and Context.parkPacket and Context.parkPacket.channel == Context.Protocol.CHANNEL_CONTROL and Context.parkPacket.reliable
        and Context.liftWire and Context.liftWire.resourceId == "pallet_jack"
        and Context.liftWire.leaseId == "lease-jack-test"
        and Context.liftWire.action == "lift_pallet" and Context.liftWire.palletId == "JOB-LIFT-P01"
        and Context.lowerWire and Context.lowerWire.resourceId == "pallet_jack"
        and Context.lowerWire.leaseId == "lease-jack-test"
        and Context.lowerWire.action == "lower_pallet" and Context.lowerWire.palletId == "JOB-LIFT-P01"
        and Context.lowerWire.expectedRevision == Context.liftRevision
        and Context.parkWire and Context.parkWire.resourceId == "pallet_jack"
        and Context.parkWire.leaseId == "lease-jack-test"
        and Context.parkWire.action == "park_jack" and Context.parkWire.palletId == nil
        and Context.parkWire.x == nil and Context.parkWire.y == nil
        and Context.parkWire.expectedRevision == Context.lowerRevision
        and Context.liftWire.commandId < Context.lowerWire.commandId
        and Context.lowerWire.commandId < Context.parkWire.commandId
        and Context.jackCalls[1] and Context.jackCalls[1].payload.action == "lift_pallet"
        and Context.jackCalls[1].payload.palletId == "JOB-LIFT-P01"
        and Context.jackCalls[2] and Context.jackCalls[2].payload.action == "lower_pallet"
        and Context.jackCalls[2].payload.palletId == "JOB-LIFT-P01"
        and Context.jackCalls[3] and Context.jackCalls[3].payload.action == "park_jack"
        and Context.jackCalls[3].payload.palletId == nil)

    Context.jackReleased = Context.client:releaseWorkshop("closed")
    Context.host:update(0, Context.hostContext)
    Context.check("multiplayer_session_worker_releases_pallet_jack_after_parking",
        Context.jackReleased and Context.client:workshopInfo() == nil
        and Context.workshopLease == nil and Context.workshopResource == nil)

    Context.authoritativeCutter = Context.cutterState()
    Context.hostContext.getCutterSnapshot = function()
        return {
            resourceRevision = Context.workshopRevision,
            view = Context.authoritativeCutter,
        }
    end
    Context.cutterRequested = Context.client:requestWorkshopAcquire("cutter")
    Context.host:update(0, Context.hostContext)
end

return Component
