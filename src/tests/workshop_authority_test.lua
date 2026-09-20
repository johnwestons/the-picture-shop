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

    local function cutterNoArguments(args)
        return exactArgs(args, {}) or nil, "invalid_arguments",
            "This cutter action does not accept arguments."
    end

    local function performCutter(action, dataBuilder)
        return function(_, _, args)
            calls.command[action] = calls.command[action] + 1
            local data = dataBuilder and dataBuilder(args) or { action = action }
            return true, action .. "_accepted", "Cutter action accepted.", data
        end
    end

    local cutterCommands = {
        load_pallet = {
            normalize = function(args)
                local normalized = exactArgs(args, { "palletId" })
                if not normalized or type(normalized.palletId) ~= "string"
                    or #normalized.palletId < 1 or #normalized.palletId > 64
                    or not normalized.palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                then
                    return nil, "invalid_arguments", "Pallet ID is invalid."
                end
                return normalized
            end,
            perform = performCutter("load_pallet", function(args)
                return { palletId = args.palletId }
            end),
        },
        select_program = {
            normalize = function(args)
                local normalized = exactArgs(args, { "programIndex" })
                if not normalized or type(normalized.programIndex) ~= "number"
                    or normalized.programIndex ~= math.floor(normalized.programIndex)
                    or normalized.programIndex < 1 or normalized.programIndex > 4
                then
                    return nil, "invalid_arguments", "Program index is invalid."
                end
                return normalized
            end,
            perform = performCutter("select_program", function(args)
                return { programIndex = args.programIndex }
            end),
        },
        set_gauge = {
            normalize = function(args)
                local normalized = exactArgs(args, { "gaugeCentiInch" })
                if not normalized or type(normalized.gaugeCentiInch) ~= "number"
                    or normalized.gaugeCentiInch ~= math.floor(normalized.gaugeCentiInch)
                    or normalized.gaugeCentiInch < 0 or normalized.gaugeCentiInch > 2500
                then
                    return nil, "invalid_arguments", "Gauge value is invalid."
                end
                return normalized
            end,
            perform = performCutter("set_gauge", function(args)
                return { gaugeCentiInch = args.gaugeCentiInch }
            end),
        },
        set_clamp = {
            normalize = function(args)
                local normalized = exactArgs(args, { "clamp" })
                if not normalized or type(normalized.clamp) ~= "boolean" then
                    return nil, "invalid_arguments", "Clamp state is invalid."
                end
                return normalized
            end,
            perform = performCutter("set_clamp", function(args)
                return { clamp = args.clamp }
            end),
        },
        set_barrier = {
            normalize = function(args)
                local normalized = exactArgs(args, { "barrierClear" })
                if not normalized or type(normalized.barrierClear) ~= "boolean" then
                    return nil, "invalid_arguments", "Barrier state is invalid."
                end
                return normalized
            end,
            perform = performCutter("set_barrier", function(args)
                return { barrierClear = args.barrierClear }
            end),
        },
    }
    for _, action in ipairs({
        "load_stock", "auto_gauge", "save_gauge", "recall_gauge", "rotate_paper",
        "position_paper", "guarded_cut", "emergency_stop", "reset_safety",
        "return_to_pallet", "run_next_lift",
    }) do
        cutterCommands[action] = {
            normalize = cutterNoArguments,
            perform = performCutter(action),
        }
    end

    local windmillSetupTasks = {
        chase = true, packing = true, rollers = true,
        ink = true, feeder = true, register = true,
    }
    local windmillSetupActions = {
        align = true, square = true, tighten = true,
        layer = true, smooth = true, clamp = true,
        left_down = true, left_up = true, right_down = true, right_up = true,
        key_1 = true, key_2 = true, key_3 = true, ductor = true,
        pile = true, suction = true, blast = true, test = true,
        left = true, right = true, up = true, down = true,
    }
    local function windmillNoArguments(args)
        return exactArgs(args, {}) or nil, "invalid_arguments",
            "This Windmill action does not accept arguments."
    end
    local function performWindmill(action, dataBuilder)
        return function(_, _, args)
            calls.command[action] = (calls.command[action] or 0) + 1
            local state = calls.windmillState
            if action == "load_pallet" then
                state.jobId, state.palletId = "JOB-0001", args.palletId
            elseif action == "toggle_motor" then
                state.motor = not state.motor
            elseif action == "toggle_feeder" then
                state.feeder = not state.feeder
            elseif action == "toggle_impression" then
                state.impression = not state.impression
            elseif action == "start_run" then
                state.running, state.motor, state.feeder, state.impression = true, true, true, true
            elseif action == "stop_run" or action == "emergency_stop" then
                state.running, state.motor, state.feeder, state.impression = false, false, false, false
                state.emergency = action == "emergency_stop"
            elseif action == "reset_safety" then
                state.emergency = false
            elseif action == "begin_setup" then
                state.setupTask = args.setupTask
            elseif action == "setup_action" then
                state.lastSetupAction = args.setupAction
            end
            local data = dataBuilder and dataBuilder(args) or { action = action }
            return true, action .. "_accepted", "Windmill action accepted.", data
        end
    end
    local windmillCommands = {
        load_pallet = {
            normalize = function(args)
                local normalized = exactArgs(args, { "palletId" })
                if not normalized or type(normalized.palletId) ~= "string"
                    or #normalized.palletId < 1 or #normalized.palletId > 64
                    or not normalized.palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                then
                    return nil, "invalid_arguments", "Pallet ID is invalid."
                end
                return normalized
            end,
            perform = performWindmill("load_pallet", function(args)
                return { palletId = args.palletId }
            end),
        },
        begin_setup = {
            normalize = function(args)
                local normalized = exactArgs(args, { "setupTask" })
                if not normalized or not windmillSetupTasks[normalized.setupTask] then
                    return nil, "invalid_arguments", "Setup task is invalid."
                end
                return normalized
            end,
            perform = performWindmill("begin_setup", function(args)
                return { setupTask = args.setupTask }
            end),
        },
        setup_action = {
            normalize = function(args)
                local normalized = exactArgs(args, { "setupAction" })
                if not normalized or not windmillSetupActions[normalized.setupAction] then
                    return nil, "invalid_arguments", "Setup action is invalid."
                end
                return normalized
            end,
            perform = performWindmill("setup_action", function(args)
                return { setupAction = args.setupAction }
            end),
        },
    }
    for _, action in ipairs({
        "toggle_motor", "toggle_feeder", "toggle_impression", "speed_up", "speed_down",
        "emergency_stop", "reset_safety", "take_proof", "verify_artwork",
        "approve_proof", "start_run", "stop_run", "clean_unload", "cancel_setup",
        "begin_service", "service_lockout", "service_task", "book_technician",
    }) do
        windmillCommands[action] = {
            normalize = windmillNoArguments,
            perform = performWindmill(action),
        }
    end
    for _, action in ipairs({ "order_plate", "begin_plate", "process_plate" }) do
        windmillCommands[action] = {
            normalize = function(args)
                local normalized = exactArgs(args, { "plateId" })
                if not normalized or type(normalized.plateId) ~= "string"
                    or not normalized.plateId:match("^[A-Za-z0-9_.%-]+$")
                then
                    return nil, "invalid_arguments", "Plate ID is invalid."
                end
                return normalized
            end,
            perform = performWindmill(action, function(args)
                return { plateId = args.plateId }
            end),
        }
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
        cutter = {
            canAcquire = canAcquire,
            onAcquire = function()
                calls.acquire.cutter = calls.acquire.cutter + 1
                return true, "acquired", "Cutter console connected.",
                    { step = "idle", barrierClear = true }
            end,
            onRelease = released,
            commands = cutterCommands,
        },
        windmill = {
            canAcquire = canAcquire,
            onAcquire = function()
                calls.acquire.windmill = calls.acquire.windmill + 1
                return true, "acquired", "Windmill console connected.", {
                    status = calls.windmillState.running and "production" or "idle",
                    jobId = calls.windmillState.jobId,
                    palletId = calls.windmillState.palletId,
                }
            end,
            onRelease = function(lease, player, reason)
                local accepted, code, message = released(lease, player, reason)
                local state = calls.windmillState
                state.running, state.motor, state.feeder, state.impression =
                    false, false, false, false
                return accepted, code, message
            end,
            commands = windmillCommands,
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
        acquire = { reception_customer = 0, cutter = 0, windmill = 0 },
        command = {
            submit_quote = 0, decline = 0, request_pickup = 0,
            load_pallet = 0, load_stock = 0, select_program = 0, set_gauge = 0,
            auto_gauge = 0, save_gauge = 0, recall_gauge = 0, rotate_paper = 0,
            position_paper = 0, set_clamp = 0, set_barrier = 0, guarded_cut = 0,
            emergency_stop = 0, reset_safety = 0, return_to_pallet = 0,
            run_next_lift = 0,
            select_pallet = 0, start_cycle = 0,
            lift_pallet = 0, lower_pallet = 0, park_jack = 0,
        },
        windmillState = {
            jobId = "JOB-0001", palletId = "JOB-0001-P01",
            running = false, motor = false, feeder = false, impression = false,
            emergency = false, setupTask = nil, lastSetupAction = nil,
        },
        release = {},
    }
    local context = { targets = {
        reception_customer = { x = 10, y = 10, radius = 20 },
        office_computer = { x = 100, y = 10, radius = 20 },
        cutter = { x = 150, y = 10, radius = 20 },
        windmill = { x = 175, y = 10, radius = 20 },
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
    check("workshop_authority_snapshot_has_ten_vacant_resources",
        #initial == 10 and initial[10].resourceId == "warehouse" and not initial[10].occupied
        and initial[9].resourceId == "work_phone" and not initial[9].occupied
        and initial[1].resourceId == "reception_customer" and not initial[1].occupied
        and initial[1].ownerPlayerId == nil and initial[1].revision == 0
        and initial[2].resourceId == "vendor" and not initial[2].occupied
        and initial[2].revision == 0
        and initial[3].resourceId == "truck" and not initial[3].occupied
        and initial[3].revision == 0
        and initial[4].resourceId == "office_computer" and not initial[4].occupied
        and initial[4].revision == 0
        and initial[5].resourceId == "cutter" and not initial[5].occupied
        and initial[5].revision == 0
        and initial[6].resourceId == "windmill" and not initial[6].occupied
        and initial[6].revision == 0
        and initial[7].resourceId == "skid_wrapper" and not initial[7].occupied
        and initial[7].revision == 0
        and initial[8].resourceId == "pallet_jack" and not initial[8].occupied
        and initial[8].revision == 0)

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

    farWorker.x, farWorker.y = 150, 10
    local cutter = authority:acquire(farWorker,
        { requestId = 8, resourceId = "cutter" }, context)
    local thirdWorker = { id = 3, x = 150, y = 10 }
    local busyCutter = authority:acquire(thirdWorker,
        { requestId = 1, resourceId = "cutter" }, context)
    local wrongCutterOwner = authority:command(secondWorker, {
        requestId = 4, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "set_barrier", args = { barrierClear = false }, expectedRevision = 1,
    }, context)
    check("workshop_authority_cutter_lease_is_exclusive_and_owner_bound",
        cutter.accepted and cutter.revision == 1 and cutter.data.step == "idle"
        and calls.acquire.cutter == 1
        and not busyCutter.accepted and busyCutter.code == "resource_busy"
        and not wrongCutterOwner.accepted and wrongCutterOwner.code == "not_owner"
        and calls.command.set_barrier == 0)

    local malformedCutterLoad = authority:command(farWorker, {
        requestId = 9, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "load_pallet", args = { palletId = "JOB-0001-P01", force = true },
        expectedRevision = 1,
    }, context)
    local malformedCutterGauge = authority:command(farWorker, {
        requestId = 10, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "set_gauge", args = { gaugeCentiInch = 125.5 }, expectedRevision = 1,
    }, context)
    local malformedCutterBarrier = authority:command(farWorker, {
        requestId = 11, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "set_barrier", args = { barrierClear = true, override = true },
        expectedRevision = 1,
    }, context)
    local malformedGuardedCut = authority:command(farWorker, {
        requestId = 12, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "guarded_cut", args = { bypass = true }, expectedRevision = 1,
    }, context)
    local malformedSafetyReset = authority:command(farWorker, {
        requestId = 13, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "reset_safety", args = { force = true }, expectedRevision = 1,
    }, context)
    check("workshop_authority_cutter_normalizers_reject_malformed_or_extra_arguments",
        not malformedCutterLoad.accepted and malformedCutterLoad.code == "invalid_arguments"
        and not malformedCutterGauge.accepted and malformedCutterGauge.code == "invalid_arguments"
        and not malformedCutterBarrier.accepted
        and malformedCutterBarrier.code == "invalid_arguments"
        and not malformedGuardedCut.accepted and malformedGuardedCut.code == "invalid_arguments"
        and not malformedSafetyReset.accepted
        and malformedSafetyReset.code == "invalid_arguments"
        and calls.command.load_pallet == 0 and calls.command.set_gauge == 0
        and calls.command.set_barrier == 0 and calls.command.guarded_cut == 0
        and calls.command.reset_safety == 0)

    local staleCutterRevision = authority:command(farWorker, {
        requestId = 14, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "set_gauge", args = { gaugeCentiInch = 1250 }, expectedRevision = 0,
    }, context)
    check("workshop_authority_cutter_rejects_stale_resource_revision",
        not staleCutterRevision.accepted and staleCutterRevision.code == "revision_conflict"
        and calls.command.set_gauge == 0)

    local loadedCutter = authority:command(farWorker, {
        requestId = 15, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "load_pallet", args = { palletId = "JOB-0001-P01" },
        expectedRevision = 1,
    }, context)
    local loadedCutterReplay = authority:command(farWorker, {
        requestId = 15, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "load_pallet", args = { palletId = "JOB-0001-P01" },
        expectedRevision = 1,
    }, context)
    local gaugedCutter = authority:command(farWorker, {
        requestId = 16, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "set_gauge", args = { gaugeCentiInch = 1250 }, expectedRevision = 2,
    }, context)
    local barrierCutter = authority:command(farWorker, {
        requestId = 17, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "set_barrier", args = { barrierClear = true }, expectedRevision = 3,
    }, context)
    local cutCutter = authority:command(farWorker, {
        requestId = 18, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "guarded_cut", args = {}, expectedRevision = 4,
    }, context)
    local cutCutterReplay = authority:command(farWorker, {
        requestId = 18, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "guarded_cut", args = {}, expectedRevision = 4,
    }, context)
    local resetCutter = authority:command(farWorker, {
        requestId = 19, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "reset_safety", args = {}, expectedRevision = 5,
    }, context)
    check("workshop_authority_cutter_actions_are_revisioned_and_replay_safe",
        loadedCutter.accepted and loadedCutter.revision == 2
        and loadedCutter.data.palletId == "JOB-0001-P01"
        and loadedCutterReplay.accepted and loadedCutterReplay.revision == 2
        and gaugedCutter.accepted and gaugedCutter.revision == 3
        and gaugedCutter.data.gaugeCentiInch == 1250
        and barrierCutter.accepted and barrierCutter.revision == 4
        and barrierCutter.data.barrierClear
        and cutCutter.accepted and cutCutter.revision == 5
        and cutCutterReplay.accepted and cutCutterReplay.revision == 5
        and resetCutter.accepted and resetCutter.revision == 6
        and calls.command.load_pallet == 1 and calls.command.set_gauge == 1
        and calls.command.set_barrier == 1 and calls.command.guarded_cut == 1
        and calls.command.reset_safety == 1)

    local cutterCrossResourceAction = authority:command(farWorker, {
        requestId = 20, resourceId = "cutter", leaseId = cutter.leaseId,
        action = "start_cycle", args = {}, expectedRevision = 6,
    }, context)
    check("workshop_authority_cutter_rejects_cross_resource_actions",
        not cutterCrossResourceAction.accepted
        and cutterCrossResourceAction.code == "action_not_allowed")

    local cutterCleanup = authority:cleanupPlayer(farWorker, "disconnected", context)
    local cutterAfterDisconnect = authority:acquire(farWorker,
        { requestId = 1, resourceId = "cutter" }, context)
    check("workshop_authority_cutter_disconnect_cleanup_releases_and_resets_replay_identity",
        #cutterCleanup == 1 and cutterCleanup[1].resourceId == "cutter"
        and cutterCleanup[1].reason == "disconnected" and cutterCleanup[1].revision == 7
        and cutterCleanup[1].cleanupAccepted and calls.release.cutter == 1
        and cutterAfterDisconnect.accepted and cutterAfterDisconnect.revision == 8
        and calls.acquire.cutter == 2)

    secondWorker.x, secondWorker.y = 100, 10
    local computer = authority:acquire(secondWorker,
        { requestId = 5, resourceId = "office_computer" }, context)
    thirdWorker.x, thirdWorker.y = 200, 10
    local wrapper = authority:acquire(thirdWorker,
        { requestId = 2, resourceId = "skid_wrapper" }, context)
    local fourthWorker = { id = 4, x = 300, y = 10 }
    local palletJack = authority:acquire(fourthWorker,
        { requestId = 1, resourceId = "pallet_jack" }, context)
    local occupied = authority:snapshot()
    check("workshop_authority_allows_different_resources_concurrently",
        computer.accepted and cutterAfterDisconnect.accepted
        and wrapper.accepted and palletJack.accepted
        and not occupied[1].occupied
        and occupied[1].revision == 3
        and not occupied[2].occupied and occupied[2].revision == 0
        and not occupied[3].occupied and occupied[3].revision == 0
        and occupied[4].occupied and occupied[4].ownerPlayerId == 2
        and occupied[4].revision == 1
        and occupied[5].occupied and occupied[5].ownerPlayerId == 1
        and occupied[5].revision == 8
        and not occupied[6].occupied and occupied[6].revision == 0
        and occupied[7].occupied and occupied[7].ownerPlayerId == 3
        and occupied[7].revision == 1
        and occupied[8].occupied and occupied[8].ownerPlayerId == 4
        and occupied[8].revision == 1)

    local cutterReleasedForContention = authority:release(farWorker, {
        requestId = 2, resourceId = "cutter", leaseId = cutterAfterDisconnect.leaseId,
        reason = "closed",
    }, context)

    farWorker.x, farWorker.y = 300, 10
    local busyPalletJack = authority:acquire(farWorker,
        { requestId = 3, resourceId = "pallet_jack" }, context)
    check("workshop_authority_pallet_jack_is_exclusive",
        cutterReleasedForContention.accepted
        and not busyPalletJack.accepted and busyPalletJack.code == "resource_busy")

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
        { requestId = 6, resourceId = "skid_wrapper" }, context)
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

    local urgentAuthority = WorkshopAuthority.new({
        tokenGenerator = function() return "urgent-cutter-lease" end,
        resources = specs(calls),
    })
    local urgentPlayer = { id = 1, x = 150, y = 10 }
    local urgentLease = urgentAuthority:acquire(urgentPlayer,
        { requestId = 1, resourceId = "cutter" }, context)
    local revisionAdvance = urgentAuthority:command(urgentPlayer, {
        requestId = 2, resourceId = "cutter", leaseId = urgentLease.leaseId,
        action = "set_gauge", args = { gaugeCentiInch = 625 }, expectedRevision = 1,
    }, context)
    local staleEmergency = urgentAuthority:command(urgentPlayer, {
        requestId = 3, resourceId = "cutter", leaseId = urgentLease.leaseId,
        action = "emergency_stop", args = {}, expectedRevision = 1,
    }, context)
    local staleBarrierBlock = urgentAuthority:command(urgentPlayer, {
        requestId = 4, resourceId = "cutter", leaseId = urgentLease.leaseId,
        action = "set_barrier", args = { barrierClear = false }, expectedRevision = 1,
    }, context)
    local staleBarrierClear = urgentAuthority:command(urgentPlayer, {
        requestId = 5, resourceId = "cutter", leaseId = urgentLease.leaseId,
        action = "set_barrier", args = { barrierClear = true }, expectedRevision = 1,
    }, context)
    check("workshop_authority_stale_owner_safety_commands_preempt_but_clear_does_not",
        urgentLease.accepted and revisionAdvance.accepted and revisionAdvance.revision == 2
        and staleEmergency.accepted and staleEmergency.revision == 3
        and staleBarrierBlock.accepted and staleBarrierBlock.revision == 4
        and not staleBarrierClear.accepted and staleBarrierClear.code == "revision_conflict")

    local windmillAuthority = WorkshopAuthority.new({
        tokenGenerator = function() return "urgent-windmill-lease" end,
        resources = specs(calls),
    })
    local windmillWorker = { id = 1, x = 175, y = 10 }
    local competingWorker = { id = 2, x = 175, y = 10 }
    local windmillLease = windmillAuthority:acquire(windmillWorker,
        { requestId = 1, resourceId = "windmill" }, context)
    local windmillLeaseReplay = windmillAuthority:acquire(windmillWorker,
        { requestId = 1, resourceId = "windmill" }, context)
    local busyWindmill = windmillAuthority:acquire(competingWorker,
        { requestId = 1, resourceId = "windmill" }, context)
    local wrongWindmillOwner = windmillAuthority:command(competingWorker, {
        requestId = 2, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "toggle_motor", args = {}, expectedRevision = 1,
    }, context)
    check("workshop_authority_windmill_lease_is_exclusive_owner_bound_and_replay_safe",
        windmillLease.accepted and windmillLease.revision == 1
        and windmillLease.leaseId == "urgent-windmill-lease"
        and windmillLeaseReplay.accepted
        and windmillLeaseReplay.leaseId == windmillLease.leaseId
        and calls.acquire.windmill == 1
        and not busyWindmill.accepted and busyWindmill.code == "resource_busy"
        and not wrongWindmillOwner.accepted and wrongWindmillOwner.code == "not_owner")

    local clientScoredSetup = windmillAuthority:command(windmillWorker, {
        requestId = 2, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "setup_action", args = { setupAction = "align", score = 1 },
        expectedRevision = 1,
    }, context)
    local clientPlateAccuracy = windmillAuthority:command(windmillWorker, {
        requestId = 3, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "process_plate", args = { plateId = "PLATE-0001", accuracy = 1 },
        expectedRevision = 1,
    }, context)
    local unknownSetupTask = windmillAuthority:command(windmillWorker, {
        requestId = 4, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "begin_setup", args = { setupTask = "guarding" }, expectedRevision = 1,
    }, context)
    check("workshop_authority_windmill_rejects_client_scored_and_malformed_actions",
        not clientScoredSetup.accepted and clientScoredSetup.code == "invalid_arguments"
        and not clientPlateAccuracy.accepted
        and clientPlateAccuracy.code == "invalid_arguments"
        and not unknownSetupTask.accepted and unknownSetupTask.code == "invalid_arguments"
        and (calls.command.setup_action or 0) == 0
        and (calls.command.process_plate or 0) == 0
        and (calls.command.begin_setup or 0) == 0)

    local staleWindmillLoad = windmillAuthority:command(windmillWorker, {
        requestId = 5, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "load_pallet", args = { palletId = "JOB-0001-P01" },
        expectedRevision = 0,
    }, context)
    local loadedWindmill = windmillAuthority:command(windmillWorker, {
        requestId = 6, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "load_pallet", args = { palletId = "JOB-0001-P01" },
        expectedRevision = 1,
    }, context)
    local loadedWindmillReplay = windmillAuthority:command(windmillWorker, {
        requestId = 6, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "load_pallet", args = { palletId = "JOB-0001-P01" },
        expectedRevision = 1,
    }, context)
    local reusedWindmillCommand = windmillAuthority:command(windmillWorker, {
        requestId = 6, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "load_pallet", args = { palletId = "JOB-0002-P01" },
        expectedRevision = 1,
    }, context)
    local beganSetup = windmillAuthority:command(windmillWorker, {
        requestId = 7, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "begin_setup", args = { setupTask = "chase" }, expectedRevision = 2,
    }, context)
    local setupInput = windmillAuthority:command(windmillWorker, {
        requestId = 8, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "setup_action", args = { setupAction = "align" }, expectedRevision = 3,
    }, context)
    check("workshop_authority_windmill_commands_are_revisioned_and_exactly_once",
        not staleWindmillLoad.accepted and staleWindmillLoad.code == "revision_conflict"
        and loadedWindmill.accepted and loadedWindmill.revision == 2
        and loadedWindmill.data.palletId == "JOB-0001-P01"
        and loadedWindmillReplay.accepted and loadedWindmillReplay.revision == 2
        and not reusedWindmillCommand.accepted
        and reusedWindmillCommand.code == "request_id_reused"
        and beganSetup.accepted and beganSetup.revision == 3
        and beganSetup.data.setupTask == "chase"
        and setupInput.accepted and setupInput.revision == 4
        and setupInput.data.setupAction == "align"
        and calls.command.load_pallet == 2
        and calls.command.begin_setup == 1 and calls.command.setup_action == 1)

    local windmillMotor = windmillAuthority:command(windmillWorker, {
        requestId = 9, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "toggle_motor", args = {}, expectedRevision = 4,
    }, context)
    local staleWindmillEmergency = windmillAuthority:command(windmillWorker, {
        requestId = 10, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "emergency_stop", args = {}, expectedRevision = 4,
    }, context)
    local staleWindmillReset = windmillAuthority:command(windmillWorker, {
        requestId = 11, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "reset_safety", args = {}, expectedRevision = 4,
    }, context)
    check("workshop_authority_windmill_stale_emergency_preempts_but_reset_does_not",
        windmillMotor.accepted and windmillMotor.revision == 5
        and staleWindmillEmergency.accepted and staleWindmillEmergency.revision == 6
        and not staleWindmillReset.accepted and staleWindmillReset.code == "revision_conflict"
        and calls.windmillState.emergency and not calls.windmillState.motor
        and not calls.windmillState.feeder and not calls.windmillState.impression)

    local resetWindmill = windmillAuthority:command(windmillWorker, {
        requestId = 12, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "reset_safety", args = {}, expectedRevision = 6,
    }, context)
    local startedWindmill = windmillAuthority:command(windmillWorker, {
        requestId = 13, resourceId = "windmill", leaseId = windmillLease.leaseId,
        action = "start_run", args = {}, expectedRevision = 7,
    }, context)
    local disconnectedWindmill = windmillAuthority:cleanupPlayer(
        windmillWorker, "disconnected", context)
    local windmillAfterDisconnect = windmillAuthority:acquire(windmillWorker,
        { requestId = 1, resourceId = "windmill" }, context)
    check("workshop_authority_windmill_disconnect_stops_run_preserves_batch_and_resets_replay",
        resetWindmill.accepted and resetWindmill.revision == 7
        and startedWindmill.accepted and startedWindmill.revision == 8
        and #disconnectedWindmill == 1
        and disconnectedWindmill[1].resourceId == "windmill"
        and disconnectedWindmill[1].reason == "disconnected"
        and disconnectedWindmill[1].revision == 9
        and disconnectedWindmill[1].cleanupAccepted
        and calls.release.windmill == 1
        and not calls.windmillState.running and not calls.windmillState.motor
        and not calls.windmillState.feeder and not calls.windmillState.impression
        and calls.windmillState.jobId == "JOB-0001"
        and calls.windmillState.palletId == "JOB-0001-P01"
        and calls.windmillState.setupTask == "chase"
        and windmillAfterDisconnect.accepted and windmillAfterDisconnect.revision == 10)
    windmillAuthority:cleanupPlayer(windmillWorker, "test_complete", context)

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
