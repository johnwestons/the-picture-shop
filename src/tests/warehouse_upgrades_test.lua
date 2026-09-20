local State = require("src.state")
local Calendar = require("src.business_calendar")
local Config = require("src.config")
local Phone = require("src.work_phone")
local Upgrades = require("src.warehouse_upgrades")

local Test = {}
local function shop()
    local state = State.new()
    state.money = 30000
    return state
end
local function bought(state, bay, option, request, now)
    local ok, project = Upgrades.purchase(state, bay, option, request, now or 0)
    assert(ok, project)
    return project
end
local function start(state, request, now)
    now = now or 0
    local project = bought(state, "front_left", "floor", request, now)
    Upgrades.update(state, now)
    Upgrades.update(state, now, { noticeDeliveredProjectId = project.id, noticeCallId = "CALL-9001" })
    Upgrades.update(state, now + 2, { workerArrivedProjectId = project.id })
    return project.id
end
local function valid(state) return Upgrades.validate(state.warehouse) end

function Test.run(_, check)
    local legacy = shop()
    legacy.warehouse = nil
    local moneyBefore = legacy.money
    local defaults = Upgrades.ensure(legacy)
    check("warehouse_upgrades_legacy_defaults_are_locked_and_free",
        defaults and defaults.bays.front_left.status == "locked"
        and defaults.bays.front_right.status == "locked" and not defaults.forkliftOwned
        and #defaults.projects == 0 and legacy.money == moneyBefore and valid(legacy))
    local normalized = Upgrades.normalize(legacy.warehouse)
    normalized.bays.front_left.status = "complete"
    check("warehouse_upgrades_normalization_is_detached",
        legacy.warehouse.bays.front_left.status == "locked" and not Upgrades.validate(normalized)
        and Upgrades.validate(Upgrades.normalize(nil)))
    local catalog = Upgrades.catalog("storage")
    catalog.price = 1
    check("warehouse_upgrades_catalog_warns_about_upper_row_and_cannot_be_mutated",
        catalog.rows == 2 and catalog.columns == 5 and catalog.capacity == 10
        and catalog.upperRowRequiresForklift and catalog.warning:find("Upper 5: forklift required", 1, true)
        and Upgrades.catalog("storage").price == 4500)
    check("warehouse_upgrades_stage_tools_match_approved_sequence",
        Upgrades.stageInfo(1).tool == "concrete_float" and Upgrades.stageInfo(2).tool == "framing_hammer"
        and Upgrades.stageInfo(3).tool == "assembly_drill" and Upgrades.stageInfo(4).tool == "finishing_roller"
        and Upgrades.STAGE_HOURS == 24 and Upgrades.stageInfo(5) == nil)

    local poor = State.new()
    local poorMoney = poor.money
    local denied, _, deniedCode = Upgrades.purchase(poor, "front_left", "storage", "poor-buy", 0)
    check("warehouse_upgrades_insufficient_cash_does_not_reserve_or_debit",
        not denied and deniedCode == "insufficient_funds" and poor.money == poorMoney
        and #poor.warehouse.projects == 0 and poor.warehouse.bays.front_left.status == "locked")
    local bad = shop()
    local badBay = Upgrades.purchase(bad, "not-a-bay", "floor", "bad-1", 0)
    local badOption = Upgrades.purchase(bad, "front_left", "forklift", "bad-2", 0)
    local badRequest = Upgrades.purchase(bad, "front_left", "floor", "bad request", 0)
    local badTime = Upgrades.purchase(bad, "front_left", "floor", "bad-3", math.huge)
    check("warehouse_upgrades_invalid_purchase_inputs_leave_money_unchanged",
        not badBay and not badOption and not badRequest and not badTime and bad.money == 30000)

    local state = shop()
    local first = bought(state, "front_left", "storage", "left-storage")
    check("warehouse_upgrades_purchase_reserves_bay_and_debits_catalog_price",
        state.money == 25500 and first.id == "WUP-0001" and first.stage == 0
        and state.warehouse.bays.front_left.status == "reserved"
        and not Upgrades.isBayAccessible(state, "front_left") and valid(state))
    local replay, replayed, replayCode = Upgrades.purchase(state, "front_left", "storage", "left-storage", 400)
    check("warehouse_upgrades_same_request_replays_without_second_charge",
        replay and replayCode == "replayed" and replayed.id == first.id
        and state.money == 25500 and #state.warehouse.receipts == 1 and #state.warehouse.projects == 1)
    local conflict, _, conflictCode = Upgrades.purchase(state, "front_right", "floor", "left-storage", 0)
    local owned, _, ownedCode = Upgrades.purchase(state, "front_left", "floor", "another-buy", 0)
    check("warehouse_upgrades_reused_request_and_owned_bay_are_rejected",
        not conflict and conflictCode == "request_conflict" and not owned and ownedCode == "bay_owned"
        and state.money == 25500 and #state.warehouse.projects == 1)
    local second = bought(state, "front_right", "floor", "right-floor")
    local changed, events = Upgrades.update(state, 0)
    check("warehouse_upgrades_single_worker_dispatches_first_purchase",
        changed and #events == 1 and events[1].kind == "notice_requested"
        and state.warehouse.activeProjectId == first.id and state.warehouse.projects[2].phase == "queued"
        and Upgrades.pendingNotice(state).projectId == first.id and valid(state))

    assert(Phone.queueCall(state, { kind = "customer_status", caller = "Test customer", role = "CUSTOMER",
        subject = "CURRENT JOB", message = "Test fixture call." }))
    local currentCall = state.workPhone.incoming
    local idle = Upgrades.update(state, 24)
    check("warehouse_upgrades_busy_phone_notice_remains_pending_without_overwriting_call",
        not idle and state.workPhone.incoming == currentCall and Upgrades.pendingNotice(state).projectId == first.id
        and state.warehouse.projects[1].stage == 0 and not Upgrades.isBayAccessible(state, "front_left"))
    local badGate = Upgrades.update(state, 24, { noticeDeliveredProjectId = first.id })
    local malformedGate = Upgrades.update(state, 24, { clientElapsedHours = 999 })
    check("warehouse_upgrades_notice_requires_explicit_matched_call_gate",
        not badGate and not malformedGate and state.warehouse.projects[1].phase == "awaiting_notice")
    changed, events = Upgrades.update(state, 24,
        { noticeDeliveredProjectId = first.id, noticeCallId = "CALL-9000" })
    check("warehouse_upgrades_delivered_notice_sets_two_hour_lead_without_starting_work",
        changed and events[1].kind == "arrival_announced" and Upgrades.pendingNotice(state) == nil
        and state.warehouse.projects[1].arrivalDueAtHours == 26
        and state.warehouse.projects[1].phase == "awaiting_arrival" and valid(state))
    local early = Upgrades.update(state, 25, { workerArrivedProjectId = first.id })
    local noWorker = Upgrades.update(state, 100)
    check("warehouse_upgrades_no_progress_before_lead_or_actual_worker_arrival",
        not early and not noWorker and state.warehouse.projects[1].stage == 0
        and state.warehouse.projects[1].phase == "awaiting_arrival")
    changed, events = Upgrades.update(state, 26, { workerArrivedProjectId = first.id })
    check("warehouse_upgrades_actual_arrival_starts_full_first_day",
        changed and events[1].kind == "work_started" and state.warehouse.projects[1].stage == 1
        and state.warehouse.projects[1].stageDueAtHours == 50
        and state.warehouse.bays.front_left.status == "building" and valid(state))
    local unchanged = Upgrades.update(state, 49.999)
    check("warehouse_upgrades_first_stage_does_not_advance_early",
        not unchanged and state.warehouse.projects[1].stage == 1)
    for stage = 2, 4 do
        changed, events = Upgrades.update(state, 26 + (stage - 1) * 24)
        check("warehouse_upgrades_exact_stage_boundary_" .. stage,
            changed and #events == 1 and events[1].kind == "stage_changed" and events[1].stage == stage
            and state.warehouse.projects[1].stage == stage and not Upgrades.isBayAccessible(state, "front_left")
            and valid(state))
    end
    check("warehouse_upgrades_fourth_stage_stays_blocked_until_its_full_day_finishes",
        not Upgrades.update(state, 121.999) and not Upgrades.isBayAccessible(state, "front_left"))
    changed, events = Upgrades.update(state, 122)
    check("warehouse_upgrades_four_days_unlocks_once_without_extra_charge",
        changed and #events == 1 and events[1].kind == "construction_complete"
        and state.warehouse.projects[1].completedAtHours == 122
        and Upgrades.isBayAccessible(state, "front_left") and not Upgrades.isBayAccessible(state, "front_right")
        and state.money == 23000 and valid(state))
    unchanged, events = Upgrades.update(state, 150)
    check("warehouse_upgrades_completed_worker_must_exit_before_second_project_dispatch",
        not unchanged and #events == 0 and state.warehouse.activeProjectId == first.id
        and state.warehouse.projects[2].phase == "queued")
    changed, events = Upgrades.update(state, 150, { workerReleasedProjectId = first.id })
    check("warehouse_upgrades_worker_exit_releases_next_queued_notice",
        changed and #events == 2 and events[1].kind == "worker_released" and events[2].kind == "notice_requested"
        and state.warehouse.activeProjectId == second.id and Upgrades.pendingNotice(state).projectId == second.id
        and valid(state))
    unchanged = Upgrades.update(state, 150, { noticeDeliveredProjectId = first.id, noticeCallId = "CALL-9000",
        workerArrivedProjectId = first.id, workerReleasedProjectId = first.id })
    check("warehouse_upgrades_stale_lifecycle_gates_cannot_start_next_project",
        not unchanged and state.warehouse.projects[2].phase == "awaiting_notice")

    local reload = shop()
    reload.warehouse = assert(Upgrades.normalize(state.warehouse))
    reload.money = state.money
    replay, replayed, replayCode = Upgrades.purchase(reload, "front_left", "storage", "left-storage", 999)
    check("warehouse_upgrades_saved_receipts_replay_after_reload",
        replay and replayCode == "replayed" and replayed.phase == "complete"
        and reload.money == state.money and valid(reload))
    Upgrades.update(reload, 151, { noticeDeliveredProjectId = second.id, noticeCallId = "CALL-9002" })
    Upgrades.update(reload, 153, { workerArrivedProjectId = second.id })
    changed, events = Upgrades.update(reload, 500)
    check("warehouse_upgrades_long_update_processes_each_deadline_in_order",
        changed and #events == 4 and events[1].stage == 2 and events[2].stage == 3
        and events[3].stage == 4 and events[4].kind == "construction_complete"
        and reload.warehouse.projects[2].completedAtHours == 249
        and Upgrades.isBayAccessible(reload, "front_right") and valid(reload))
    unchanged, events = Upgrades.update(reload, 500)
    check("warehouse_upgrades_repeated_completion_has_no_events", not unchanged and #events == 0)

    local blocked = shop()
    local blockedId = start(blocked, "blocked-build")
    changed, events = Upgrades.update(blocked, 10, { blockedProjectId = blockedId })
    local serialized = assert(Upgrades.normalize(blocked.warehouse))
    blocked.warehouse = serialized
    unchanged = Upgrades.update(blocked, 100)
    check("warehouse_upgrades_blocked_work_survives_reload_without_progress",
        changed and events[1].kind == "work_blocked" and not unchanged
        and blocked.warehouse.projects[1].stage == 1 and blocked.warehouse.projects[1].pausedAtHours == 10
        and valid(blocked))
    changed, events = Upgrades.update(blocked, 100, { unblockedProjectId = blockedId })
    check("warehouse_upgrades_unblocked_work_preserves_remaining_hours",
        changed and events[1].kind == "work_resumed" and blocked.warehouse.projects[1].stageDueAtHours == 116
        and blocked.warehouse.projects[1].pausedAtHours == nil and valid(blocked))
    Upgrades.update(blocked, 116)
    check("warehouse_upgrades_resumed_stage_advances_at_shifted_deadline",
        blocked.warehouse.projects[1].stage == 2 and valid(blocked))
    local fractional = shop()
    local fractionalId = start(fractional, "fractional-build", 0.123456789)
    Upgrades.update(fractional, 10.45678, { blockedProjectId = fractionalId })
    Upgrades.update(fractional, 100.33333, { unblockedProjectId = fractionalId })
    check("warehouse_upgrades_fractional_hour_pause_has_stable_validation", valid(fractional))

    for stage = 2, 4 do
        local skipped = shop()
        start(skipped, "skip-stage-"..stage)
        skipped.warehouse.projects[1].stage = stage
        check("warehouse_upgrades_rejects_stage_"..stage.."_before_prior_full_days",
            not valid(skipped) and Upgrades.normalize(skipped.warehouse) == nil
            and not Upgrades.update(skipped, 200))
    end
    local forged = shop()
    start(forged, "forged-one-day-completion")
    local forgedProject = forged.warehouse.projects[1]
    forgedProject.stage, forgedProject.phase = 4, "complete"
    forgedProject.completedAtHours = forgedProject.stageDueAtHours
    forged.warehouse.bays.front_left.status = "complete"
    check("warehouse_upgrades_rejects_forged_fourth_stage_completion_after_one_day",
        not valid(forged) and Upgrades.normalize(forged.warehouse) == nil
        and not Upgrades.isBayAccessible(forged,"front_left"))
    Upgrades.update(blocked,120,{blockedProjectId=blockedId})
    Upgrades.update(blocked,130,{unblockedProjectId=blockedId})
    Upgrades.update(blocked,197.999)
    check("warehouse_upgrades_multiple_pauses_do_not_replace_required_work_days",
        valid(blocked) and blocked.warehouse.projects[1].phase == "building"
        and blocked.warehouse.projects[1].stage == 4
        and blocked.warehouse.projects[1].stageDueAtHours == 198)
    Upgrades.update(blocked,198)
    check("warehouse_upgrades_four_full_days_plus_all_pauses_can_complete",
        valid(blocked) and blocked.warehouse.projects[1].completedAtHours == 198
        and Upgrades.isBayAccessible(blocked,"front_left"))

    local corrupt = assert(Upgrades.normalize(state.warehouse))
    corrupt.projects[2].bayId = "front_left"
    check("warehouse_upgrades_duplicate_bay_project_is_rejected", not Upgrades.validate(corrupt))
    corrupt = assert(Upgrades.normalize(state.warehouse))
    corrupt.receipts[1].pricePaid = 0
    check("warehouse_upgrades_receipt_mismatch_is_rejected", not Upgrades.validate(corrupt))
    corrupt = assert(Upgrades.normalize(state.warehouse))
    corrupt.activeProjectId = first.id
    check("warehouse_upgrades_invalid_worker_owner_is_rejected", not Upgrades.validate(corrupt))
    local malformed = { money = 30000, warehouse = corrupt }
    local reset = Upgrades.ensure(malformed)
    local repaired = Upgrades.normalize(corrupt)
    check("warehouse_upgrades_malformed_paid_state_is_not_silently_reset",
        reset == nil and repaired == nil and malformed.warehouse == corrupt and malformed.money == 30000)

    local forklift = shop()
    local runtimeForklift = forklift.forklift
    local forkliftOk, forkliftReceipt, forkliftCode = Upgrades.purchaseForklift(forklift, "buy-forklift", 4)
    check("warehouse_upgrades_forklift_purchase_sets_entitlement_without_runtime_mutation",
        forkliftOk and forkliftCode == "purchased" and forkliftReceipt.pricePaid == 6500
        and forklift.money == 23500 and forklift.warehouse.forkliftOwned
        and forklift.forklift == runtimeForklift and valid(forklift))
    local forkliftAgain, _, forkliftReplay = Upgrades.purchaseForklift(forklift, "buy-forklift", 500)
    local forkliftDuplicate, _, forkliftDuplicateCode = Upgrades.purchaseForklift(forklift, "buy-another-forklift", 500)
    local crossPurchase, _, crossCode = Upgrades.purchase(forklift, "front_left", "floor", "buy-forklift", 500)
    check("warehouse_upgrades_forklift_replay_and_conflicts_cannot_double_debit",
        forkliftAgain and forkliftReplay == "replayed" and not forkliftDuplicate and forkliftDuplicateCode == "forklift_owned"
        and not crossPurchase and crossCode == "request_conflict" and forklift.money == 23500)
    local unaffordable, _, forkliftPoorCode = Upgrades.purchaseForklift(poor, "poor-forklift", 0)
    check("warehouse_upgrades_forklift_requires_cash", not unaffordable and forkliftPoorCode == "insufficient_funds"
        and poor.money == poorMoney and not poor.warehouse.forkliftOwned)

    local timed = shop()
    Calendar.update(timed, Config.businessCalendar.secondsPerDay / 2)
    local timedOk, timedProject = Upgrades.purchase(timed, "front_left", "breakroom", "calendar-clock")
    check("warehouse_upgrades_uses_real_business_calendar_when_time_omitted",
        timedOk and math.abs(timedProject.purchasedAtHours - 12) < 0.000001)
    local invalidUpdate, invalidError = Upgrades.update(timed, 0 / 0)
    check("warehouse_upgrades_nonfinite_update_time_rejected", not invalidUpdate and type(invalidError) == "string")
    local leaked = Upgrades.activeProject(state)
    leaked.phase = "complete"
    check("warehouse_upgrades_read_projections_cannot_mutate_authority",
        state.warehouse.projects[2].phase == "awaiting_notice" and not Upgrades.isBayAccessible(state, "unknown"))
end

return Test
