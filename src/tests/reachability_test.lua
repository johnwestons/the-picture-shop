local Reachability = require("src.net.reachability")

local Test = {}

local function fakeMethod(name, options, log)
    options = options or {}
    local method = {
        name = name,
        starts = 0,
        requests = {},
        handles = {},
        attemptTimeoutSeconds = options.attemptTimeoutSeconds,
    }

    function method:start(request)
        self.starts = self.starts + 1
        self.requests[#self.requests + 1] = request
        log[#log + 1] = name .. ":start"
        if options.throwOnStart then error(options.throwOnStart) end
        if options.startFails then return nil, options.startFails end

        local handle = {
            events = {},
            renews = 0,
            deletes = 0,
            closes = 0,
        }
        function handle:update(now)
            log[#log + 1] = name .. ":update:" .. tostring(now)
            if options.throwOnUpdate then error(options.throwOnUpdate) end
            if #self.events == 0 then return nil end
            return table.remove(self.events, 1)
        end
        function handle:renew(now)
            self.renews = self.renews + 1
            log[#log + 1] = name .. ":renew:" .. tostring(now)
            if options.throwOnRenew then error(options.throwOnRenew) end
            return options.renewResult
        end
        function handle:delete()
            self.deletes = self.deletes + 1
            log[#log + 1] = name .. ":delete"
            if options.throwOnDelete then error(options.throwOnDelete) end
            if options.returnNilOnDelete then return nil end
            if options.deleteResult == nil then return true end
            return options.deleteResult
        end
        function handle:close()
            self.closes = self.closes + 1
            log[#log + 1] = name .. ":close"
            if options.throwOnClose then error(options.throwOnClose) end
            return options.closeResult
        end
        method.handles[#method.handles + 1] = handle
        if options.invalidHandle then handle[options.invalidHandle] = nil end
        return handle
    end
    return method
end

local function request(overrides)
    local value = {
        internalAddress = "192.168.1.134",
        internalPort = 22122,
        gatewayAddress = "192.168.1.1",
        suggestedExternalPort = 22122,
        requestedLifetime = 7200,
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end

local function containsInOrder(values, expected)
    local nextExpected = 1
    for _, value in ipairs(values) do
        if value == expected[nextExpected] then nextExpected = nextExpected + 1 end
    end
    return nextExpected > #expected
end

local function eventNamed(events, kind)
    for _, event in ipairs(events) do
        if event.kind == kind then return event end
    end
    return nil
end

local function flatten(value, output, seen)
    output, seen = output or {}, seen or {}
    if type(value) == "table" and not seen[value] then
        seen[value] = true
        for key, item in pairs(value) do
            flatten(key, output, seen)
            flatten(item, output, seen)
        end
    elseif type(value) ~= "function" then
        output[#output + 1] = tostring(value)
    end
    return table.concat(output, "|")
end

function Test.run(_, check)
    local now, fallbackLog = 100, {}
    local pcp = fakeMethod("pcp", {}, fallbackLog)
    local natPmp = fakeMethod("nat_pmp", {}, fallbackLog)
    local coordinator = Reachability.new({
        methods = { pcp, natPmp },
        clock = function() return now end,
    })
    local secret = "invite-key-must-never-reach-an-adapter"
    local started = coordinator:start(request({
        psk = secret,
        invitationKey = secret,
        rawResponse = secret,
    }))
    local firstRequest = pcp.requests[1]
    local beforeFallback = natPmp.starts == 0
        and firstRequest.internalAddress == "192.168.1.134"
        and firstRequest.internalPort == 22122
        and firstRequest.psk == nil and firstRequest.invitationKey == nil
        and firstRequest.rawResponse == nil
    pcp.handles[1].events[1] = { kind = "failed", rawResponse = secret }
    coordinator:update(now)
    local fallbackSerialized = natPmp.starts == 1
        and containsInOrder(fallbackLog, {
            "pcp:start", "pcp:update:100", "pcp:delete", "pcp:close",
            "nat_pmp:start",
        })
    natPmp.handles[1].events[1] = {
        kind = "mapped", externalAddress = "8.8.4.4",
        externalPort = 40000, lifetime = 120,
        rawResponse = secret,
    }
    coordinator:update(now)
    local candidate = coordinator:candidate()
    check("reachability_serializes_fallback_cleans_owned_attempt_and_allowlists_requests",
        started and beforeFallback and fallbackSerialized
        and candidate and candidate.endpoint == "8.8.4.4:40000"
        and candidate.method == "nat_pmp" and not candidate.cleanupRequired
        and flatten(coordinator:snapshot()):find(secret, 1, true) == nil
        and flatten(coordinator:drainEvents()):find(secret, 1, true) == nil)

    local strictLog = {}
    local invalidPublic = fakeMethod("pcp", {}, strictLog)
    local validPublic = fakeMethod("nat_pmp", {}, strictLog)
    local strict = Reachability.new({
        methods = { invalidPublic, validPublic }, clock = function() return 0 end,
    })
    strict:start(request({ now = 0 }))
    invalidPublic.handles[1].events[1] = {
        kind = "mapped", externalAddress = "192.168.1.9",
        externalPort = 22122, lifetime = 30,
    }
    strict:update(0)
    validPublic.handles[1].events[1] = {
        kind = "mapped", externalAddress = "008.8.8.8",
        externalPort = 22122, lifetime = 30,
    }
    strict:update(0)
    check("reachability_rejects_private_and_noncanonical_external_candidates",
        strict:candidate() == nil and strict:status() == "unavailable"
        and invalidPublic.handles[1].deletes == 1
        and validPublic.handles[1].deletes == 1
        and containsInOrder(strictLog, {
            "pcp:delete", "pcp:close", "nat_pmp:start",
            "nat_pmp:delete", "nat_pmp:close",
        }))

    local leaseLog = {}
    local leaseMethod = fakeMethod("pcp", {}, leaseLog)
    local lease = Reachability.new({
        methods = { leaseMethod }, clock = function() return now end,
        maxLeaseSeconds = 1000, renewFraction = 0.5,
    })
    now = 10
    lease:start(request({ now = now, requestedLifetime = 100 }))
    leaseMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "1.1.1.1",
        externalPort = 22122, lifetime = 100,
    }
    lease:update(now)
    local initialLease = lease:candidate()
    lease:update(59)
    lease:update(60)
    lease:update(61)
    local renewedOnlyOnce = leaseMethod.handles[1].renews == 1
    leaseMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "1.1.1.1",
        externalPort = 22122, lifetime = 80,
    }
    lease:update(70)
    local renewedLease = lease:candidate()
    lease:update(110)
    lease:update(150)
    check("reachability_uses_finite_lease_renews_once_and_expires_without_acknowledgement",
        initialLease.createdAt == 10 and initialLease.renewAt == 60
        and initialLease.expiresAt == 110 and renewedOnlyOnce
        and renewedLease.createdAt == 70 and renewedLease.renewAt == 110
        and renewedLease.expiresAt == 150
        and lease:candidate() == nil and lease:status() == "unavailable"
        and leaseMethod.handles[1].deletes == 1)

    local epochLog = {}
    local epochMethod = fakeMethod("pcp", {}, epochLog)
    local epochFallback = fakeMethod("nat_pmp", {}, epochLog)
    local epoch = Reachability.new({
        methods = { epochMethod, epochFallback }, clock = function() return 0 end,
    })
    epoch:start(request({ now = 0 }))
    epochMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "9.9.9.9",
        externalPort = 22122, lifetime = 60,
    }
    epoch:update(0)
    epochMethod.handles[1].events[1] = {
        kind = "epoch_reset", epoch = 0, rawResponse = secret,
    }
    epoch:update(1)
    local epochEvents = epoch:drainEvents()
    check("reachability_epoch_event_invalidates_candidate_before_clean_fallback",
        epoch:candidate() == nil and epochFallback.starts == 1
        and eventNamed(epochEvents, "candidate_invalidated").reason == "epoch_reset"
        and containsInOrder(epochLog, {
            "pcp:update:1", "pcp:delete", "pcp:close", "nat_pmp:start",
        }) and flatten(epochEvents):find(secret, 1, true) == nil)

    local cleanupLog = {}
    local dirty = fakeMethod("pcp", { deleteResult = false }, cleanupLog)
    local mustNotStart = fakeMethod("nat_pmp", {}, cleanupLog)
    local cleanup = Reachability.new({
        methods = { dirty, mustNotStart }, clock = function() return 0 end,
    })
    cleanup:start(request({ now = 0 }))
    dirty.handles[1].events[1] = { kind = "failed" }
    cleanup:update(0)
    local automaticAcknowledged, automaticAcknowledgeError =
        cleanup:acknowledgeCleanup()
    check("reachability_failed_automatic_cleanup_cannot_be_acknowledged_or_bypassed",
        cleanup:status() == "cleanup_required" and mustNotStart.starts == 0
        and cleanup:snapshot().cleanupRequired
        and cleanup:snapshot().cleanupKind == "automatic"
        and dirty.handles[1].deletes == 1 and dirty.handles[1].closes == 0
        and cleanup:start(request({ now = 0 })) == false
        and not automaticAcknowledged
        and automaticAcknowledgeError == "automatic_cleanup_cannot_be_acknowledged"
        and cleanup:snapshot().cleanupRequired and mustNotStart.starts == 0)

    local pendingDeleteLog = {}
    local pendingDelete = fakeMethod("pcp", {
        returnNilOnDelete = true,
    }, pendingDeleteLog)
    local pendingFallback = fakeMethod("nat_pmp", {}, pendingDeleteLog)
    local pendingCleanup = Reachability.new({
        methods = { pendingDelete, pendingFallback },
        clock = function() return 0 end,
    })
    pendingCleanup:start(request({ now = 0 }))
    pendingDelete.handles[1].events[1] = { kind = "failed" }
    pendingCleanup:update(0)
    local pendingBeforeAck = pendingCleanup:status() == "cleaning"
        and pendingCleanup:snapshot().cleanupRequired
        and pendingFallback.starts == 0
        and pendingDelete.handles[1].deletes == 1
        and pendingDelete.handles[1].closes == 0
    pendingDelete.handles[1].events[1] = { kind = "deleted" }
    pendingCleanup:update(1)
    check("reachability_waits_for_exact_async_delete_ack_before_fallback",
        pendingBeforeAck and pendingFallback.starts == 1
        and pendingDelete.handles[1].closes == 1
        and containsInOrder(pendingDeleteLog, {
            "pcp:delete", "pcp:update:1", "pcp:close", "nat_pmp:start",
        }))

    local expiryCleanupLog = {}
    local expiryCleanupMethod = fakeMethod("pcp", {
        deleteResult = false,
    }, expiryCleanupLog)
    local expiryFallback = fakeMethod("nat_pmp", {}, expiryCleanupLog)
    local expiryCleanup = Reachability.new({
        methods = { expiryCleanupMethod, expiryFallback },
        clock = function() return 0 end,
    })
    expiryCleanup:start(request({ now = 0 }))
    expiryCleanupMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "8.8.8.8",
        externalPort = 22122, lifetime = 5,
    }
    expiryCleanup:update(0)
    expiryCleanupMethod.handles[1].events[1] = { kind = "failed" }
    expiryCleanup:update(1)
    local heldUntilExpiry = expiryCleanup:status() == "cleanup_required"
        and expiryFallback.starts == 0
        and expiryCleanupMethod.handles[1].closes == 0
        and expiryCleanup:snapshot().cleanupExpiresAt == 5
    expiryCleanup:update(4.99)
    local stillHeld = expiryFallback.starts == 0
    expiryCleanup:update(5)
    check("reachability_allows_fallback_only_after_the_known_old_lease_expires",
        heldUntilExpiry and stillHeld and expiryFallback.starts == 1
        and expiryCleanupMethod.handles[1].deletes == 1
        and expiryCleanupMethod.handles[1].closes == 1)

    local lateMappingLog = {}
    local lateMappingMethod = fakeMethod("pcp", {
        returnNilOnDelete = true,
    }, lateMappingLog)
    local lateFallback = fakeMethod("nat_pmp", {}, lateMappingLog)
    local lateMapping = Reachability.new({
        methods = { lateMappingMethod, lateFallback },
        clock = function() return 0 end,
    })
    lateMapping:start(request({ now = 0 }))
    lateMappingMethod.handles[1].events[1] = { kind = "failed" }
    lateMapping:update(0)
    lateMappingMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "8.8.4.4",
        externalPort = 40000, lifetime = 5,
    }
    lateMapping:update(1)
    local lateMappingHeld = lateFallback.starts == 0
        and lateMapping:candidate() == nil
        and lateMappingMethod.handles[1].deletes == 2
        and lateMapping:snapshot().cleanupExpiresAt == 6
    lateMapping:update(6)
    check("reachability_late_creation_is_never_advertised_and_is_deleted_again_before_fallback",
        lateMappingHeld and lateFallback.starts == 1
        and lateMappingMethod.handles[1].closes == 1)

    local manual = Reachability.new({
        methods = {}, clock = function() return 20 end,
        manualCandidateSeconds = 30,
    })
    local manualStarted = manual:start(request({
        now = 20,
        manualCandidate = {
            externalAddress = "4.4.4.4", externalPort = 30000,
        },
    }))
    local manualCandidate = manual:candidate()
    local earlyManualAck, earlyManualAckError = manual:acknowledgeManualCleanup()
    manual:update(50)
    local expiredManualEvents = manual:drainEvents()
    local manualResidualBeforeAck = manual:snapshot().cleanupRequired
        and manual:snapshot().cleanupKind == "manual"
    local genericManualAck, genericManualAckError = manual:acknowledgeCleanup()
    local explicitManualAck = manual:acknowledgeManualCleanup()
    local invalidManual = Reachability.new({ methods = {} })
    local invalidManualStarted, invalidManualError = invalidManual:start(request({
        now = 0,
        manualCandidate = {
            externalAddress = "100.64.0.1", externalPort = 30000,
        },
    }))
    check("reachability_manual_candidate_is_unverified_finite_and_requires_cleanup",
        manualStarted and manualCandidate.method == "manual"
        and manualCandidate.verified == false
        and manualCandidate.cleanupRequired == true
        and manualCandidate.renewAt == nil and manualCandidate.expiresAt == 50
        and not earlyManualAck and earlyManualAckError == "still_active"
        and manual:candidate() == nil and manualResidualBeforeAck
        and not genericManualAck
        and genericManualAckError == "use_acknowledge_manual_cleanup"
        and explicitManualAck and not manual:snapshot().cleanupRequired
        and eventNamed(expiredManualEvents, "unavailable").cleanupRequired
        and not invalidManualStarted and invalidManualError == "invalid_manual_candidate")

    local verifyLog = {}
    local verifyMethod = fakeMethod("pcp", {}, verifyLog)
    local verify = Reachability.new({
        methods = { verifyMethod }, clock = function() return 0 end,
    })
    verify:start(request({ now = 0 }))
    verifyMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "8.8.8.8",
        externalPort = 32000, lifetime = 60, verified = true,
    }
    verify:update(0)
    local mapperCouldNotVerify = verify:candidate().verified == false
    local wrongVerification, wrongVerificationError = verify:markVerified(
        "8.8.4.4", 32000)
    local verified = verify:markVerified("8.8.8.8", 32000)
    local verificationEvents = verify:drainEvents()
    verifyMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "8.8.8.8",
        externalPort = 32000, lifetime = 60,
    }
    verify:update(1)
    local unchangedRenewalPreservedProof = verify:candidate().verified == true
    verify:drainEvents()
    verifyMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "8.8.4.4",
        externalPort = 32001, lifetime = 60, verified = true,
    }
    verify:update(2)
    local changedEvents = verify:drainEvents()
    check("reachability_verification_requires_exact_probe_and_endpoint_changes_withdraw_proof",
        mapperCouldNotVerify
        and not wrongVerification and wrongVerificationError == "candidate_mismatch"
        and verified and eventNamed(verificationEvents, "candidate_verified") ~= nil
        and unchangedRenewalPreservedProof
        and verify:candidate().verified == false
        and verify:candidate().endpoint == "8.8.4.4:32001"
        and changedEvents[1].kind == "candidate_invalidated"
        and changedEvents[1].reason == "endpoint_changed"
        and changedEvents[2].kind == "candidate_ready")

    local expiredVerifyNow, expiredVerifyLog = 0, {}
    local expiredVerifyMethod = fakeMethod("pcp", {}, expiredVerifyLog)
    local expiredVerify = Reachability.new({
        methods = { expiredVerifyMethod },
        clock = function() return expiredVerifyNow end,
    })
    expiredVerify:start(request({ now = 0 }))
    expiredVerifyMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "8.8.8.8",
        externalPort = 33000, lifetime = 1,
    }
    expiredVerify:update(0)
    expiredVerify:drainEvents()
    expiredVerifyNow = 1
    local expiredVerified, expiredVerifyError = expiredVerify:markVerified(
        "8.8.8.8", 33000)
    check("reachability_never_verifies_a_candidate_at_or_after_lease_expiry",
        not expiredVerified and expiredVerifyError == "candidate_expired"
        and expiredVerify:candidate().verified == false
        and eventNamed(expiredVerify:drainEvents(), "candidate_verified") == nil)

    local stopLog = {}
    local stopMethod = fakeMethod("pcp", {}, stopLog)
    local stopping = Reachability.new({
        methods = { stopMethod }, clock = function() return 0 end,
    })
    stopping:start(request({ now = 0 }))
    stopMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "1.0.0.1",
        externalPort = 22122, lifetime = 60,
    }
    stopping:update(0)
    local firstStop, firstCleanup = stopping:stop()
    local secondStop, secondCleanup = stopping:stop()
    check("reachability_stop_is_idempotent_and_deletes_only_its_owned_mapping_once",
        firstStop and secondStop and not firstCleanup and not secondCleanup
        and stopMethod.handles[1].deletes == 1
        and stopMethod.handles[1].closes == 1
        and stopping:status() == "stopped" and stopping:candidate() == nil)

    local pendingStopLog = {}
    local pendingStopMethod = fakeMethod("pcp", {
        returnNilOnDelete = true,
    }, pendingStopLog)
    local pendingStop = Reachability.new({
        methods = { pendingStopMethod }, clock = function() return 0 end,
    })
    pendingStop:start(request({ now = 0 }))
    pendingStopMethod.handles[1].events[1] = {
        kind = "mapped", externalAddress = "1.1.1.1",
        externalPort = 22122, lifetime = 60,
    }
    pendingStop:update(0)
    local pendingFirstStop, pendingFirstCleanup = pendingStop:stop()
    local pendingSecondStop, pendingSecondCleanup = pendingStop:stop()
    local heldOpenForAck = not pendingFirstStop and pendingFirstCleanup
        and not pendingSecondStop and pendingSecondCleanup
        and pendingStop:status() == "cleaning"
        and pendingStopMethod.handles[1].closes == 0
    pendingStopMethod.handles[1].events[1] = { kind = "deleted" }
    pendingStop:update(1)
    local completedStop, completedCleanup = pendingStop:stop()
    check("reachability_stop_stays_incomplete_until_async_mapping_cleanup_finishes",
        heldOpenForAck and completedStop and not completedCleanup
        and pendingStop:status() == "stopped"
        and pendingStopMethod.handles[1].deletes == 1
        and pendingStopMethod.handles[1].closes == 1)

    local manualStop = Reachability.new({
        methods = {}, clock = function() return 0 end,
    })
    manualStop:start(request({
        now = 0,
        manualCandidate = {
            externalAddress = "4.4.4.4", externalPort = 33001,
        },
    }))
    local manualStopOk, manualStopCleanup = manualStop:stop()
    local genericStopAck, genericStopAckError = manualStop:acknowledgeCleanup()
    local explicitStopAck = manualStop:acknowledgeManualCleanup()
    local acknowledgedStopOk, acknowledgedStopCleanup = manualStop:stop()
    check("reachability_stop_cannot_report_success_while_manual_rule_cleanup_remains",
        not manualStopOk and manualStopCleanup
        and not genericStopAck
        and genericStopAckError == "use_acknowledge_manual_cleanup"
        and explicitStopAck and acknowledgedStopOk and not acknowledgedStopCleanup)

    local errorLog = {}
    local throwing = fakeMethod("pcp", { throwOnUpdate = secret }, errorLog)
    local errorCoordinator = Reachability.new({
        methods = { throwing }, clock = function() return 0 end,
    })
    errorCoordinator:start(request({ now = 0 }))
    errorCoordinator:update(0)
    local errorSurface = flatten(errorCoordinator:drainEvents())
        .. flatten(errorCoordinator:snapshot())
    check("reachability_never_surfaces_adapter_errors_raw_packets_or_invitation_secrets",
        errorSurface:find(secret, 1, true) == nil
        and errorCoordinator:status() == "unavailable")

    local timeoutLog = {}
    local silent = fakeMethod("pcp", {}, timeoutLog)
    local timeoutFallback = fakeMethod("nat_pmp", {}, timeoutLog)
    local timeout = Reachability.new({
        methods = { silent, timeoutFallback },
        clock = function() return 0 end,
        attemptTimeoutSeconds = 2,
    })
    timeout:start(request({ now = 0 }))
    timeout:update(1.99)
    timeout:update(2)
    local backwards, backwardsError = timeout:update(1)
    check("reachability_times_out_silent_methods_and_rejects_backward_or_nonfinite_time",
        timeoutFallback.starts == 1 and not backwards
        and backwardsError == "time_went_backwards"
        and timeout:update(0 / 0) == false)

    local adapterTimedLog = {}
    local adapterTimed = fakeMethod("pcp", {
        attemptTimeoutSeconds = false,
    }, adapterTimedLog)
    local adapterTimedFallback = fakeMethod("nat_pmp", {}, adapterTimedLog)
    local adapterTimedCoordinator = Reachability.new({
        methods = { adapterTimed, adapterTimedFallback },
        clock = function() return 0 end,
        attemptTimeoutSeconds = 2,
    })
    adapterTimedCoordinator:start(request({ now = 0 }))
    adapterTimedCoordinator:update(100)
    local adapterOwnsDeadline = adapterTimedFallback.starts == 0
        and adapterTimedCoordinator:status() == "probing"
    adapterTimed.handles[1].events[1] = { kind = "exhausted" }
    adapterTimedCoordinator:update(101)
    check("reachability_allows_adapter_rfc_schedule_to_control_exhaustion_safely",
        adapterOwnsDeadline and adapterTimedFallback.starts == 1
        and adapterTimed.handles[1].deletes == 1
        and adapterTimed.handles[1].closes == 1)

    local customTimedLog = {}
    local customTimed = fakeMethod("pcp", {
        attemptTimeoutSeconds = 10,
    }, customTimedLog)
    local customTimedFallback = fakeMethod("nat_pmp", {}, customTimedLog)
    local customTimedCoordinator = Reachability.new({
        methods = { customTimed, customTimedFallback },
        clock = function() return 0 end,
        attemptTimeoutSeconds = 2,
    })
    customTimedCoordinator:start(request({ now = 0 }))
    customTimedCoordinator:update(2)
    local customHeld = customTimedFallback.starts == 0
    customTimedCoordinator:update(10)
    check("reachability_method_specific_timeout_overrides_the_short_global_default",
        customHeld and customTimedFallback.starts == 1
        and customTimed.handles[1].deletes == 1)

    local rejectedLocalInputs = true
    for _, address in ipairs({
        "0.0.0.0", "127.0.0.1", "224.0.0.1", "255.255.255.255",
    }) do
        local invalidInternal = Reachability.new({ methods = {} })
        local accepted, errorCode = invalidInternal:start(request({
            now = 0, internalAddress = address,
        }))
        rejectedLocalInputs = rejectedLocalInputs
            and not accepted and errorCode == "invalid_internal_address"

        local invalidGateway = Reachability.new({ methods = {} })
        accepted, errorCode = invalidGateway:start(request({
            now = 0, gatewayAddress = address,
        }))
        rejectedLocalInputs = rejectedLocalInputs
            and not accepted and errorCode == "invalid_gateway_address"
    end
    local publicGateway = Reachability.new({ methods = {} })
    check("reachability_local_inputs_reject_nonunicast_but_allow_public_gateways",
        rejectedLocalInputs and publicGateway:start(request({
            now = 0, gatewayAddress = "1.1.1.1",
        })))
end

return Test
