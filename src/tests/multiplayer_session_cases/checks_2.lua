-- Multiplayer session regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.network:sendRawToHost(Context.firstInteractionRequest.payload,
        Context.Protocol.CHANNEL_CONTROL, true)
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.duplicateEvents = Context.client:drainEvents()
    Context.interactionResults = Context.network:messages("host_to_client", "interaction_result")
    Context.duplicateWireResult = Context.decodedPayload(Context.interactionResults[#Context.interactionResults])
    Context.check("multiplayer_session_duplicate_use_replays_result_without_reexecution",
        #Context.interactionCalls == 1 and Context.interactionMutations == 1
        and #Context.interactionResults == 2
        and Context.duplicateWireResult and Context.firstWireResult
        and Context.duplicateWireResult.requestId == Context.firstWireResult.requestId
        and Context.duplicateWireResult.accepted == Context.firstWireResult.accepted
        and Context.duplicateWireResult.code == Context.firstWireResult.code
        and Context.eventNamed(Context.duplicateEvents, "interaction_result") == nil)

    -- A new request inside the host cooldown consumes its id and returns a
    -- stable rejection without entering the world callback.
    Context.rateRequest = Context.client:requestInteraction("loadingBayDoor", "open")
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.rateResult = Context.eventNamed(Context.client:drainEvents(), "interaction_result")
    Context.check("multiplayer_session_unique_use_spam_is_rate_limited",
        Context.rateRequest and Context.rateResult and not Context.rateResult.accepted
        and Context.rateResult.requestId == 2 and Context.rateResult.code == "rate_limited"
        and #Context.interactionCalls == 1 and Context.interactionMutations == 1
        and Context.host.players[2].lastInteractionRequestId == 2)

    -- The phone now predicts itself at the switch while the host's player is
    -- far away. Only the latter is passed to performInteraction.
    Context.now = Context.now + 0.21
    Context.host.players[2].x, Context.host.players[2].y = 700, 600
    Context.guestPlayer.x, Context.guestPlayer.y = Context.interactionX, Context.interactionY
    Context.outOfRangeRequest = Context.client:requestInteraction("loadingBayDoor", "open")
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.outOfRangeResult = Context.eventNamed(Context.client:drainEvents(), "interaction_result")
    Context.check("multiplayer_session_out_of_range_use_uses_host_position",
        Context.outOfRangeRequest and Context.outOfRangeResult and not Context.outOfRangeResult.accepted
        and Context.outOfRangeResult.requestId == 3 and Context.outOfRangeResult.code == "out_of_range"
        and #Context.interactionCalls == 2
        and Context.interactionCalls[2].player == Context.host.players[2]
        and Context.interactionCalls[2].x == 700 and Context.interactionCalls[2].y == 600
        and Context.interactionCalls[2].x ~= Context.guestPlayer.x and Context.interactionCalls[2].y ~= Context.guestPlayer.y
        and Context.interactionMutations == 1)

    Context.staleInteractionPacket = Context.Protocol.encode("interaction_request", {
        sessionId = Context.host.sessionId, requestId = 2, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    Context.network:sendRawToHost(Context.staleInteractionPacket, Context.Protocol.CHANNEL_CONTROL, true)
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.staleInteractionEvents = Context.client:drainEvents()
    Context.interactionResults = Context.network:messages("host_to_client", "interaction_result")
    Context.staleWireResult = Context.decodedPayload(Context.interactionResults[#Context.interactionResults])
    Context.check("multiplayer_session_stale_use_is_rejected_without_reexecution",
        Context.staleWireResult and Context.staleWireResult.requestId == 2
        and not Context.staleWireResult.accepted and Context.staleWireResult.code == "stale_request"
        and Context.host.players[2].lastInteractionRequestId == 3
        and #Context.interactionCalls == 2 and Context.interactionMutations == 1
        and Context.eventNamed(Context.staleInteractionEvents, "interaction_result") == nil)

    Context.resultCountBeforeWrongSession = #Context.interactionResults
    Context.wrongSessionInteraction = Context.Protocol.encode("interaction_request", {
        sessionId = "spoofed-session", requestId = 4, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    Context.network:sendRawToHost(Context.wrongSessionInteraction, Context.Protocol.CHANNEL_CONTROL, true)
    Context.host:update(0, Context.hostContext)
    Context.check("multiplayer_session_wrong_session_use_is_ignored_without_consuming_id",
        #Context.network:messages("host_to_client", "interaction_result")
            == Context.resultCountBeforeWrongSession
        and Context.host.players[2].lastInteractionRequestId == 3
        and #Context.interactionCalls == 2 and Context.interactionMutations == 1)

    Context.now = Context.now + 0.21
    Context.host.players[2].x, Context.host.players[2].y = Context.interactionX, Context.interactionY
    Context.guestPlayer.x, Context.guestPlayer.y = 900, 620
    Context.validAfterSpoof = Context.client:requestInteraction("loadingBayDoor", "open")
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.validAfterSpoofResult = Context.eventNamed(Context.client:drainEvents(), "interaction_result")
    Context.check("multiplayer_session_valid_use_after_spoof_keeps_monotonic_sequence",
        Context.validAfterSpoof and Context.validAfterSpoofResult and Context.validAfterSpoofResult.accepted
        and Context.validAfterSpoofResult.requestId == 4
        and Context.host.players[2].lastInteractionRequestId == 4
        and #Context.interactionCalls == 3 and Context.interactionMutations == 2)

    Context.duplicateAcceptedResult = Context.Protocol.encode("interaction_result", {
        sessionId = Context.host.sessionId, requestId = 4, targetKind = "loadingBayDoor",
        accepted = true, code = "accepted", message = "Opening the loading bay door...",
    })
    Context.wrongSessionResult = Context.Protocol.encode("interaction_result", {
        sessionId = "spoofed-session", requestId = 5, targetKind = "loadingBayDoor",
        accepted = true, code = "accepted", message = "Opening the loading bay door...",
    })
    Context.now = Context.now + 0.21
    Context.pendingFifthRequest = Context.client:requestInteraction("loadingBayDoor", "open")
    Context.network.host:send(Context.network.peer, Context.duplicateAcceptedResult,
        Context.Protocol.CHANNEL_CONTROL, true)
    Context.network.host:send(Context.network.peer, Context.wrongSessionResult,
        Context.Protocol.CHANNEL_CONTROL, true)
    Context.client:update(0, Context.clientContext)
    Context.ignoredResultEvents = Context.client:drainEvents()
    Context.check("multiplayer_session_guest_ignores_stale_and_wrong_session_results",
        Context.pendingFifthRequest
        and Context.eventNamed(Context.ignoredResultEvents, "interaction_result") == nil
        and Context.client.pendingInteraction and Context.client.pendingInteraction.requestId == 5)
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.fifthResult = Context.eventNamed(Context.client:drainEvents(), "interaction_result")
    Context.check("multiplayer_session_matching_result_clears_only_its_pending_request",
        Context.fifthResult and Context.fifthResult.requestId == 5 and Context.fifthResult.accepted
        and Context.client.pendingInteraction == nil
        and Context.host.players[2].lastInteractionRequestId == 5
        and #Context.interactionCalls == 4 and Context.interactionMutations == 3)

    Context.malformedInteraction = Context.Codec.encode({
        version = Context.Protocol.VERSION,
        type = "interaction_request",
        payload = {
            sessionId = Context.host.sessionId, requestId = 5, targetKind = "loadingBayDoor",
            desiredState = "open", playerId = 2, x = Context.interactionX, y = Context.interactionY,
        },
    })
    Context.now = Context.now + 1.01
    Context.errorsBeforeSpoof = #Context.network:messages("host_to_client", "error")
    Context.network:sendRawToHost(Context.malformedInteraction, Context.Protocol.CHANNEL_CONTROL, true)
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.malformedInteractionError = Context.eventNamed(Context.client:drainEvents(), "error")
    Context.check("multiplayer_session_position_and_identity_spoof_returns_bad_packet",
        Context.malformedInteractionError and Context.malformedInteractionError.code == "bad_packet"
        and #Context.network:messages("host_to_client", "error") == Context.errorsBeforeSpoof + 1
        and Context.host.players[2].lastInteractionRequestId == 5
        and #Context.interactionCalls == 4 and Context.interactionMutations == 3)

    Context.now = Context.now + 1.01
    Context.errorCountBeforeInvalid = #Context.network:messages("host_to_client", "error")
    Context.network:sendRawToHost("this-is-not-a-protocol-packet")
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.invalidEvents = Context.client:drainEvents()
    Context.invalidError = Context.eventNamed(Context.invalidEvents, "error")
    Context.errorPackets = Context.network:messages("host_to_client", "error")
    Context.check("multiplayer_session_invalid_packet_returns_bad_packet_error",
        Context.invalidError and Context.invalidError.code == "bad_packet"
        and #Context.errorPackets == Context.errorCountBeforeInvalid + 1
        and #Context.errorPackets[#Context.errorPackets].payload <= Context.Protocol.MAX_PACKET_BYTES
        and Context.errorPackets[#Context.errorPackets].channel == Context.Protocol.CHANNEL_CONTROL
        and Context.errorPackets[#Context.errorPackets].reliable)

    Context.now = Context.now + 1.01
    Context.wrongChannelCount = #Context.errorPackets
    Context.wrongChannelInteraction = Context.Protocol.encode("interaction_request", {
        sessionId = Context.host.sessionId, requestId = 6, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    Context.network:sendRawToHost(Context.wrongChannelInteraction, Context.Protocol.CHANNEL_STATE, true)
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.wrongChannelError = Context.eventNamed(Context.client:drainEvents(), "error")
    Context.check("multiplayer_session_guest_command_on_wrong_channel_is_rejected_before_execution",
        Context.wrongChannelError and Context.wrongChannelError.code == "bad_packet"
        and #Context.network:messages("host_to_client", "error") == Context.wrongChannelCount + 1
        and Context.host.players[2].lastInteractionRequestId == 5
        and #Context.interactionCalls == 4 and Context.interactionMutations == 3)

    Context.now = Context.now + 1.01
    Context.oversizedCount = #Context.network:messages("host_to_client", "error")
    Context.network:sendRawToHost(string.rep("x", Context.Protocol.MAX_PACKET_BYTES + 1),
        Context.Protocol.CHANNEL_DURABLE, true)
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.oversizedGuestError = Context.eventNamed(Context.client:drainEvents(), "error")
    Context.check("multiplayer_session_guest_packets_are_capped_before_large_codec_decode",
        Context.Protocol.MAX_PACKET_BYTES == 1200
        and Context.oversizedGuestError and Context.oversizedGuestError.code == "bad_packet"
        and #Context.network:messages("host_to_client", "error") == Context.oversizedCount + 1
        and Context.host.players[2].lastInteractionRequestId == 5
        and #Context.interactionCalls == 4 and Context.interactionMutations == 3)

    Context.workshopRevision, Context.workshopLease, Context.workshopResource, Context.workshopMutation = 0, nil, nil, 0
    Context.authoritativeCutter = nil
    Context.workshopPallets = {}
    Context.workshopCalls, Context.workshopTouches = {}, 0
    Context.hostContext.touchWorkshop = function(player)
        if player and player.id == 2 then Context.workshopTouches = Context.workshopTouches + 1 end
    end
    Context.hostContext.performWorkshop = function(player, operation, payload)
        Context.workshopCalls[#Context.workshopCalls + 1] = {
            player = player, operation = operation, payload = payload,
        }
        if operation == "workshop_acquire" then
            Context.workshopRevision = Context.workshopRevision + 1
            Context.workshopResource = payload.resourceId
            local leases = {
                office_computer = "lease-office-test",
                skid_wrapper = "lease-wrapper-test",
                pallet_jack = "lease-jack-test",
                cutter = "lease-cutter-test",
                windmill = "lease-windmill-test",
            }
            Context.workshopLease = leases[Context.workshopResource] or "lease-workshop-test"
            local data = {}
            if Context.workshopResource == "skid_wrapper" then
                data = {
                    step = "idle", progress = 0, cycleTime = 3,
                    plasticWrapRolls = 2, plasticWrapUses = 8,
                    pallets = Context.workshopPallets,
                }
            elseif Context.workshopResource == "cutter" then
                data = Context.authoritativeCutter or Context.cutterState()
            elseif Context.workshopResource == "windmill" then
                data = Context.hostContext.windmillTestView or Context.windmillState()
            end
            return {
                accepted = true, code = "acquired", message = "Workshop console connected.",
                revision = Context.workshopRevision, leaseId = Context.workshopLease, data = data,
            }
        elseif operation == "workshop_command" then
            if payload.leaseId ~= Context.workshopLease then
                return { accepted = false, code = "lease_not_found", message = "Lease missing.",
                    revision = Context.workshopRevision }
            end
            Context.workshopRevision, Context.workshopMutation = Context.workshopRevision + 1, Context.workshopMutation + 1
            if Context.workshopResource == "windmill" then
                local windmill = Context.hostContext.windmillTestView or Context.windmillState()
                Context.hostContext.windmillTestView = windmill
                windmill.runtimeRevision = windmill.runtimeRevision + 1
                if payload.action == "load_pallet" then
                    windmill.jobId = "JOB-PRESS"
                    windmill.palletId = payload.palletId
                    windmill.colorIndex = 1
                    windmill.colorCount = 4
                    windmill.candidates = {}
                elseif payload.action == "begin_setup" then
                    windmill.status = "setup"
                    windmill.setupTask = payload.setupTask
                elseif payload.action == "setup_action" then
                    windmill.setupPermille[1] = 250
                elseif payload.action == "toggle_motor" then
                    windmill.motor = not windmill.motor
                elseif payload.action == "speed_up" then
                    windmill.speed = windmill.speed + 100
                elseif payload.action == "emergency_stop" then
                    windmill.status = "stopped"
                    windmill.motor = false
                    windmill.feeder = false
                    windmill.impression = false
                    windmill.emergency = true
                end
            end
            local data = Context.workshopResource == "cutter"
                and (Context.authoritativeCutter or Context.cutterState())
                or Context.workshopResource == "windmill"
                    and (Context.hostContext.windmillTestView or Context.windmillState()) or {}
            return {
                accepted = true, code = "pickup_requested", message = "Pickup requested.",
                revision = Context.workshopRevision, data = data,
            }
        elseif operation == "workshop_release" then
            Context.workshopRevision, Context.workshopLease, Context.workshopResource = Context.workshopRevision + 1, nil, nil
            return { accepted = true, code = "released", message = "Released.",
                revision = Context.workshopRevision }
        end
    end
end

return Component
