local WorkshopAuthority = require("src.workshop_authority")

local Test = {}

local function exactArgs(args, fields)
    if type(args) ~= "table" then return nil end
    local allowed = {}
    for _, field in ipairs(fields) do allowed[field] = true end
    for key in pairs(args) do if not allowed[key] then return nil end end
    for _, field in ipairs(fields) do if args[field] == nil then return nil end end
    local result = {}
    for _, field in ipairs(fields) do result[field] = args[field] end
    return result
end

local function specs(calls)
    local function canAcquire(player, context, request)
        calls.range[request.resourceId] = (calls.range[request.resourceId] or 0) + 1
        local target = context.targets[request.resourceId]
        local dx, dy = player.x - target.x, player.y - target.y
        if dx * dx + dy * dy > target.radius * target.radius then
            return false, "out_of_range", "Move closer to that workshop resource."
        end
        return true
    end

    local function released(lease, _, reason)
        calls.release[lease.resourceId] = (calls.release[lease.resourceId] or 0) + 1
        calls.lastRelease = { resourceId = lease.resourceId, reason = reason,
            private = lease.private }
        return true
    end

    return {
        reception_customer = {
            canAcquire = canAcquire,
            onAcquire = function(_, _, _, request)
                calls.acquire.reception_customer = calls.acquire.reception_customer + 1
                return true, "acquired", "Review the customer's quote.",
                    { offerId = "JOB-0001", recommendedPrice = 125 },
                    { offerId = "JOB-0001", authoritativeOffer = true,
                        acquiredFrom = request.resourceId }
            end,
            onRelease = released,
            commands = {
                submit_quote = {
                    normalize = function(args)
                        local normalized = exactArgs(args, { "amount" })
                        if not normalized or type(normalized.amount) ~= "number"
                            or normalized.amount ~= math.floor(normalized.amount)
                            or normalized.amount < 1 or normalized.amount > 100000000
                        then
                            return nil, "invalid_arguments", "Quote amount is invalid."
                        end
                        return normalized
                    end,
                    perform = function(lease, _, args)
                        calls.command.submit_quote = calls.command.submit_quote + 1
                        if not lease.private or not lease.private.authoritativeOffer then
                            return false, "offer_missing", "The host offer is missing."
                        end
                        calls.lastQuote = { offerId = lease.private.offerId, amount = args.amount }
                        return true, "quote_submitted", "The quote was submitted.",
                            { offerId = lease.private.offerId, amount = args.amount }
                    end,
                },
                decline = {
                    normalize = function(args)
                        return exactArgs(args, {}) or nil, "invalid_arguments",
                            "Decline does not accept arguments."
                    end,
                    perform = function()
                        calls.command.decline = calls.command.decline + 1
                        return true, "declined", "The customer offer was declined."
                    end,
                },
            },
        },
        office_computer = {
            canAcquire = canAcquire,
            onRelease = released,
            commands = {
                request_pickup = {
                    normalize = function(args)
                        local normalized = exactArgs(args, { "jobId" })
                        if not normalized or type(normalized.jobId) ~= "string"
                            or not normalized.jobId:match("^[A-Za-z0-9_.%-]+$")
                        then
                            return nil, "invalid_arguments", "Job ID is invalid."
                        end
                        return normalized
                    end,
                    perform = function(_, _, args)
                        calls.command.request_pickup = calls.command.request_pickup + 1
                        return true, "pickup_requested", "Pickup was requested.",
                            { jobId = args.jobId }
                    end,
                },
            },
        },
        skid_wrapper = {
            canAcquire = canAcquire,
            onRelease = released,
            commands = {
                select_pallet = {
                    normalize = function(args)
                        local normalized = exactArgs(args, { "palletId" })
                        if not normalized or type(normalized.palletId) ~= "string"
                            or not normalized.palletId:match("^[A-Za-z0-9_.%-]+$")
                        then
                            return nil, "invalid_arguments", "Pallet ID is invalid."
                        end
                        return normalized
                    end,
                    perform = function(_, _, args)
                        calls.command.select_pallet = calls.command.select_pallet + 1
                        return true, "pallet_selected", "Pallet selected.",
                            { palletId = args.palletId }
                    end,
                },
                start_cycle = {
                    normalize = function(args)
                        local normalized = exactArgs(args, { "palletId" })
                        if not normalized or type(normalized.palletId) ~= "string"
                            or not normalized.palletId:match("^[A-Za-z0-9_.%-]+$")
                        then
                            return nil, "invalid_arguments", "Pallet ID is invalid."
                        end
                        return normalized
                    end,
                    perform = function(_, _, args)
                        calls.command.start_cycle = calls.command.start_cycle + 1
                        return true, "cycle_started", "Wrapper cycle started.",
                            { palletId = args.palletId }
                    end,
                },
            },
        },
        pallet_jack = {
            canAcquire = canAcquire,
            onRelease = released,
            commands = {
                lift_pallet = {
                    normalize = function(args)
                        local normalized = exactArgs(args, { "palletId" })
                        if not normalized or type(normalized.palletId) ~= "string"
                            or not normalized.palletId:match("^[A-Za-z0-9_.%-]+$")
                        then
                            return nil, "invalid_arguments", "Pallet ID is invalid."
                        end
                        return normalized
                    end,
                    perform = function(_, _, args)
                        calls.command.lift_pallet = calls.command.lift_pallet + 1
                        return true, "pallet_lifted", "Pallet lifted.",
                            { palletId = args.palletId }
                    end,
                },
                lower_pallet = {
                    normalize = function(args)
                        local normalized = exactArgs(args, { "palletId" })
                        if not normalized or type(normalized.palletId) ~= "string"
                            or not normalized.palletId:match("^[A-Za-z0-9_.%-]+$")
                        then
                            return nil, "invalid_arguments", "Pallet ID is invalid."
                        end
                        return normalized
                    end,
                    perform = function(_, _, args)
                        calls.command.lower_pallet = calls.command.lower_pallet + 1
                        return true, "pallet_lowered", "Pallet lowered.",
                            { palletId = args.palletId }
                    end,
                },
                park_jack = {
                    normalize = function(args)
                        return exactArgs(args, {}) or nil, "invalid_arguments",
                            "Park jack does not accept arguments."
                    end,
                    perform = function()
                        calls.command.park_jack = calls.command.park_jack + 1
                        return true, "jack_parked", "Pallet jack parked."
                    end,
                },
            },
        },
    }
end

function Test.run(_, check)
    local now = 100
    local calls = {
        range = {},
        acquire = { reception_customer = 0 },
        command = {
            submit_quote = 0, decline = 0, request_pickup = 0,
            select_pallet = 0, start_cycle = 0,
            lift_pallet = 0, lower_pallet = 0, park_jack = 0,
        },
        release = {},
    }
    local context = { targets = {
        reception_customer = { x = 10, y = 10, radius = 20 },
        office_computer = { x = 100, y = 10, radius = 20 },
        skid_wrapper = { x = 200, y = 10, radius = 20 },
        pallet_jack = { x = 300, y = 10, radius = 20 },
    } }
    local authority = WorkshopAuthority.new({
        clock = function() return now end,
        leaseTimeout = 10,
        replayLimit = 8,
        tokenGenerator = function(serial, resourceId, playerId)
            return string.format("test-%d-%s-%d", serial, resourceId, playerId)
        end,
        resources = specs(calls),
    })

    local initial = authority:snapshot()
    check("workshop_authority_snapshot_has_four_vacant_resources",
        #initial == 4
        and initial[1].resourceId == "reception_customer" and not initial[1].occupied
        and initial[1].ownerPlayerId == nil and initial[1].revision == 0
        and initial[2].resourceId == "office_computer" and not initial[2].occupied
        and initial[2].revision == 0
        and initial[3].resourceId == "skid_wrapper" and not initial[3].occupied
        and initial[3].revision == 0
        and initial[4].resourceId == "pallet_jack" and not initial[4].occupied
        and initial[4].revision == 0)

    local farWorker = { id = 1, x = 200, y = 200 }
    local far = authority:acquire(farWorker,
        { requestId = 1, resourceId = "reception_customer" }, context)
    farWorker.x, farWorker.y = 10, 10
    local farReplay = authority:acquire(farWorker,
        { requestId = 1, resourceId = "reception_customer" }, context)
    check("workshop_authority_range_rejection_is_replay_safe",
        not far.accepted and far.code == "out_of_range"
        and not farReplay.accepted and farReplay.code == "out_of_range"
        and calls.range.reception_customer == 1)

    local reused = authority:acquire(farWorker,
        { requestId = 1, resourceId = "office_computer" }, context)
    check("workshop_authority_request_id_cannot_change_fingerprint",
        not reused.accepted and reused.code == "request_id_reused")

    local injectedIdentity = authority:acquire(farWorker,
        { requestId = 2, resourceId = "reception_customer", playerId = 4 }, context)
    check("workshop_authority_rejects_client_identity_fields",
        not injectedIdentity.accepted and injectedIdentity.code == "invalid_request")

    local acquired = authority:acquire(farWorker,
        { requestId = 2, resourceId = "reception_customer" }, context)
    local acquiredReplay = authority:acquire(farWorker,
        { requestId = 2, resourceId = "reception_customer" }, context)
    check("workshop_authority_acquire_is_exactly_once",
        acquired.accepted and acquired.code == "acquired"
        and acquired.leaseId == "test-1-reception_customer-1"
        and acquired.data.offerId == "JOB-0001" and acquired.revision == 1
        and acquiredReplay.accepted and acquiredReplay.leaseId == acquired.leaseId
        and calls.acquire.reception_customer == 1)

    local secondWorker = { id = 2, x = 10, y = 10 }
    local busyResource = authority:acquire(secondWorker,
        { requestId = 1, resourceId = "reception_customer" }, context)
    local busyPlayer = authority:acquire(farWorker,
        { requestId = 3, resourceId = "office_computer" }, context)
    check("workshop_authority_enforces_resource_and_player_exclusivity",
        not busyResource.accepted and busyResource.code == "resource_busy"
        and not busyPlayer.accepted and busyPlayer.code == "player_busy")

    local malformedCommand = authority:command(farWorker, {
        requestId = 4, resourceId = "reception_customer", leaseId = acquired.leaseId,
        action = "submit_quote", args = { amount = 125, claimedJobId = "FAKE" },
    }, context)
    check("workshop_authority_action_normalizer_rejects_extra_arguments",
        not malformedCommand.accepted and malformedCommand.code == "invalid_arguments"
        and calls.command.submit_quote == 0)

    local staleRevision = authority:command(farWorker, {
        requestId = 5, resourceId = "reception_customer", leaseId = acquired.leaseId,
        action = "submit_quote", args = { amount = 125 }, expectedRevision = 0,
    }, context)
    check("workshop_authority_rejects_stale_resource_revision",
        not staleRevision.accepted and staleRevision.code == "revision_conflict"
        and calls.command.submit_quote == 0)

    local wrongOwner = authority:command(secondWorker, {
        requestId = 2, resourceId = "reception_customer", leaseId = acquired.leaseId,
        action = "submit_quote", args = { amount = 125 }, expectedRevision = 1,
    }, context)
    check("workshop_authority_binds_lease_to_authoritative_player",
        not wrongOwner.accepted and wrongOwner.code == "not_owner"
        and calls.command.submit_quote == 0)

    local quoted = authority:command(farWorker, {
        requestId = 6, resourceId = "reception_customer", leaseId = acquired.leaseId,
        action = "submit_quote", args = { amount = 125 }, expectedRevision = 1,
    }, context)
    local quotedReplay = authority:command(farWorker, {
        requestId = 6, resourceId = "reception_customer", leaseId = acquired.leaseId,
        action = "submit_quote", args = { amount = 125 }, expectedRevision = 1,
    }, context)
    local quoteIdReuse = authority:command(farWorker, {
        requestId = 6, resourceId = "reception_customer", leaseId = acquired.leaseId,
        action = "submit_quote", args = { amount = 126 }, expectedRevision = 1,
    }, context)
    check("workshop_authority_command_is_exactly_once",
        quoted.accepted and quoted.code == "quote_submitted" and quoted.revision == 2
        and quoted.data.offerId == "JOB-0001" and quoted.data.amount == 125
        and quotedReplay.accepted and quotedReplay.revision == 2
        and not quoteIdReuse.accepted and quoteIdReuse.code == "request_id_reused"
        and calls.command.submit_quote == 1
        and calls.lastQuote.offerId == "JOB-0001" and calls.lastQuote.amount == 125)

    local wrongRelease = authority:release(secondWorker, {
        requestId = 3, resourceId = "reception_customer", leaseId = acquired.leaseId,
        reason = "closed",
    }, context)
    local released = authority:release(farWorker, {
        requestId = 7, resourceId = "reception_customer", leaseId = acquired.leaseId,
        reason = "cancelled",
    }, context)
    local releaseReplay = authority:release(farWorker, {
        requestId = 7, resourceId = "reception_customer", leaseId = acquired.leaseId,
        reason = "cancelled",
    }, context)
    check("workshop_authority_release_is_owned_and_exactly_once",
        not wrongRelease.accepted and wrongRelease.code == "not_owner"
        and released.accepted and released.code == "released" and released.revision == 3
        and releaseReplay.accepted and releaseReplay.code == "released"
        and authority:leaseForResource("reception_customer") == nil
        and calls.release.reception_customer == 1
        and calls.lastRelease.reason == "cancelled"
        and calls.lastRelease.private.authoritativeOffer)

    secondWorker.x, secondWorker.y = 100, 10
    local computer = authority:acquire(secondWorker,
        { requestId = 4, resourceId = "office_computer" }, context)
    local thirdWorker = { id = 3, x = 200, y = 10 }
    local wrapper = authority:acquire(thirdWorker,
        { requestId = 1, resourceId = "skid_wrapper" }, context)
    local fourthWorker = { id = 4, x = 300, y = 10 }
    local palletJack = authority:acquire(fourthWorker,
        { requestId = 1, resourceId = "pallet_jack" }, context)
    local occupied = authority:snapshot()
    check("workshop_authority_allows_different_resources_concurrently",
        computer.accepted and wrapper.accepted and palletJack.accepted
        and not occupied[1].occupied
        and occupied[1].revision == 3
        and occupied[2].occupied and occupied[2].ownerPlayerId == 2
        and occupied[2].revision == 1
        and occupied[3].occupied and occupied[3].ownerPlayerId == 3
        and occupied[3].revision == 1
        and occupied[4].occupied and occupied[4].ownerPlayerId == 4
        and occupied[4].revision == 1)

    farWorker.x, farWorker.y = 300, 10
    local busyPalletJack = authority:acquire(farWorker,
        { requestId = 8, resourceId = "pallet_jack" }, context)
    check("workshop_authority_pallet_jack_is_exclusive",
        not busyPalletJack.accepted and busyPalletJack.code == "resource_busy")

    local crossResourceAction = authority:command(fourthWorker, {
        requestId = 2, resourceId = "pallet_jack", leaseId = palletJack.leaseId,
        action = "start_cycle", args = {}, expectedRevision = 1,
    }, context)
    check("workshop_authority_pallet_jack_rejects_cross_resource_actions",
        not crossResourceAction.accepted and crossResourceAction.code == "action_not_allowed")

    local lifted = authority:command(fourthWorker, {
        requestId = 3, resourceId = "pallet_jack", leaseId = palletJack.leaseId,
        action = "lift_pallet", args = { palletId = "JOB-0001-P01" },
        expectedRevision = 1,
    }, context)
    local liftedReplay = authority:command(fourthWorker, {
        requestId = 3, resourceId = "pallet_jack", leaseId = palletJack.leaseId,
        action = "lift_pallet", args = { palletId = "JOB-0001-P01" },
        expectedRevision = 1,
    }, context)
    local lowered = authority:command(fourthWorker, {
        requestId = 4, resourceId = "pallet_jack", leaseId = palletJack.leaseId,
        action = "lower_pallet", args = { palletId = "JOB-0001-P01" },
        expectedRevision = 2,
    }, context)
    local parked = authority:command(fourthWorker, {
        requestId = 5, resourceId = "pallet_jack", leaseId = palletJack.leaseId,
        action = "park_jack", args = {}, expectedRevision = 3,
    }, context)
    check("workshop_authority_pallet_jack_actions_are_allowlisted_and_replay_safe",
        lifted.accepted and lifted.code == "pallet_lifted" and lifted.revision == 2
        and lifted.data.palletId == "JOB-0001-P01"
        and liftedReplay.accepted and liftedReplay.revision == 2
        and lowered.accepted and lowered.code == "pallet_lowered" and lowered.revision == 3
        and lowered.data.palletId == "JOB-0001-P01"
        and parked.accepted and parked.code == "jack_parked" and parked.revision == 4
        and calls.command.lift_pallet == 1
        and calls.command.lower_pallet == 1 and calls.command.park_jack == 1)

    local secondResource = authority:acquire(secondWorker,
        { requestId = 5, resourceId = "skid_wrapper" }, context)
    check("workshop_authority_allows_only_one_lease_per_player",
        not secondResource.accepted and secondResource.code == "player_busy")

    now = 106
    check("workshop_authority_touch_renews_active_lease",
        authority:touchPlayer(thirdWorker) and authority:touchPlayer(secondWorker)
        and authority:touchPlayer(fourthWorker))
    now = 115
    check("workshop_authority_does_not_expire_before_timeout",
        #authority:update(context) == 0 and authority:leaseForPlayer(thirdWorker) ~= nil)
    now = 116
    authority:touchPlayer(secondWorker)
    local timeoutEvents = authority:update(context)
    check("workshop_authority_timeout_releases_all_expired_resources_with_cleanup",
        #timeoutEvents == 2 and timeoutEvents[1].reason == "timeout"
        and timeoutEvents[1].resourceId == "skid_wrapper"
        and timeoutEvents[1].cleanupAccepted
        and timeoutEvents[2].reason == "timeout"
        and timeoutEvents[2].resourceId == "pallet_jack"
        and timeoutEvents[2].cleanupAccepted
        and authority:leaseForPlayer(thirdWorker) == nil
        and authority:leaseForPlayer(fourthWorker) == nil
        and calls.release.skid_wrapper == 1 and calls.release.pallet_jack == 1)

    local cleanupEvents = authority:cleanupPlayer(secondWorker, "disconnected", context)
    secondWorker.x, secondWorker.y = 100, 10
    local reusedAfterDisconnect = authority:acquire(secondWorker,
        { requestId = 1, resourceId = "office_computer" }, context)
    check("workshop_authority_disconnect_cleanup_clears_lease_and_replay_identity",
        #cleanupEvents == 1 and cleanupEvents[1].reason == "disconnected"
        and calls.release.office_computer == 1
        and reusedAfterDisconnect.accepted)
    authority:cleanupPlayer(secondWorker, "test_complete", context)

    local replayNow = 0
    local replayCalls = { range = 0 }
    local limited = WorkshopAuthority.new({
        clock = function() return replayNow end,
        replayLimit = 2,
        resources = {
            reception_customer = {
                canAcquire = function()
                    replayCalls.range = replayCalls.range + 1
                    return false, "out_of_range", "Too far away."
                end,
            },
        },
    })
    local limitedPlayer = { id = 4, x = 0, y = 0 }
    for requestId = 1, 3 do
        limited:acquire(limitedPlayer,
            { requestId = requestId, resourceId = "reception_customer" }, {})
    end
    local evictedReplay = limited:acquire(limitedPlayer,
        { requestId = 1, resourceId = "reception_customer" }, {})
    check("workshop_authority_evicted_request_cannot_execute_again",
        not evictedReplay.accepted and evictedReplay.code == "stale_request"
        and replayCalls.range == 3)
end

return Test
