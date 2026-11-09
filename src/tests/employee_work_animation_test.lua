local WorkAnimation = require("src.employee_work_animation")
local Test = {}

local function sample(record, count)
    local action, frame = WorkAnimation.sample(record, count)
    return action, frame
end

local function input(mode, taskKey, action, extra)
    local value = { mode = mode, taskKey = taskKey, action = action }
    for key, item in pairs(extra or {}) do value[key] = item end
    return value
end

function Test.run(_, check)
    local clip = {
        action = "work_press",
        frameCount = 8,
        approachFrames = { 2, 3, 4 },
        contactFrame = 5,
        operationFrame = 6,
        recoveryFrames = { 7, 8 },
        secondsPerFrame = .1,
    }
    local entryClip = {
        action = "work_press", frameCount = 8,
        approachFrames = { 2, 3, 4 }, contactFrame = 5, operationEntryFrame = 3,
        operationFrame = 6, recoveryFrames = { 7, 8 }, secondsPerFrame = .1,
    }
    local record = WorkAnimation.newRecord()
    local _, initial = sample(record, 8)
    check("employee_work_animation_starts_ready", record.phase == "ready" and initial == 1)

    WorkAnimation.update(record, input("start", "job-a:press", "work_press"), 0, clip)
    check("employee_work_animation_task_start_plays_approach", record.phase == "approach"
        and sample(record, 8) == "work_press" and select(2, sample(record, 8)) == 2)
    WorkAnimation.update(record, input("contact", "job-a:press", "work_press"), .3, clip)
    check("employee_work_animation_approach_ends_at_contact", record.phase == "contact"
        and select(2, sample(record, 8)) == 5)

    local inFlight = WorkAnimation.newRecord()
    WorkAnimation.update(inFlight, input("start", "job-active:press", "work_press"), 0, clip)
    WorkAnimation.update(inFlight, input("operate", "job-active:press", "work_press"), 0, clip)
    check("employee_work_animation_operation_overrides_in_flight_approach", inFlight.phase == "operate"
        and select(2, sample(inFlight, 8)) == 6)

    local entryFromApproach = WorkAnimation.newRecord()
    WorkAnimation.update(entryFromApproach, input("start", "entry:approach", "work_press"), 0, entryClip)
    WorkAnimation.update(entryFromApproach, input("operate", "entry:approach", "work_press"), 0, entryClip)
    check("employee_work_animation_operation_entry_overrides_approach_immediately",
        entryFromApproach.phase == "operate" and entryFromApproach.operationEntryPending
            and select(2, sample(entryFromApproach, 8)) == 3)
    WorkAnimation.update(entryFromApproach, input("operate", "entry:approach", "work_press"), .04, entryClip)
    check("employee_work_animation_operation_entry_accumulates_fractional_time",
        entryFromApproach.operationEntryPending and math.abs(entryFromApproach.operationEntryElapsed-.04)<1e-8
            and select(2, sample(entryFromApproach, 8)) == 3)
    WorkAnimation.update(entryFromApproach, input("operate", "entry:approach", "work_press"), .06, entryClip)
    check("employee_work_animation_operation_entry_changes_to_hold_at_duration",
        not entryFromApproach.operationEntryPending and select(2, sample(entryFromApproach, 8)) == 6)
    WorkAnimation.update(entryFromApproach, input("operate", "entry:approach", "work_press"), 4, entryClip)
    check("employee_work_animation_operation_entry_never_restarts_during_same_hold",
        not entryFromApproach.operationEntryPending and select(2, sample(entryFromApproach, 8)) == 6)

    local entryFromContact = WorkAnimation.newRecord()
    WorkAnimation.update(entryFromContact, input("start", "entry:contact", "work_press"), 0, entryClip)
    WorkAnimation.update(entryFromContact, input("contact", "entry:contact", "work_press"), .3, entryClip)
    WorkAnimation.update(entryFromContact, input("operate", "entry:contact", "work_press"), 0, entryClip)
    check("employee_work_animation_operation_entry_runs_from_contact",
        entryFromContact.phase == "operate" and entryFromContact.operationEntryPending
            and select(2, sample(entryFromContact, 8)) == 3)

    local firstObservedActive = WorkAnimation.newRecord()
    WorkAnimation.update(firstObservedActive, input("operate", "already-active", "work_press"), 0, entryClip)
    check("employee_work_animation_new_record_active_starts_on_operation_hold",
        firstObservedActive.phase == "operate" and not firstObservedActive.operationEntryPending
            and select(2, sample(firstObservedActive, 8)) == 6)

    local explicitOperationEdge = WorkAnimation.newRecord()
    WorkAnimation.update(explicitOperationEdge,
        input("operate", "edge-active", "work_press", { operationStarted = true }), 0, entryClip)
    check("employee_work_animation_explicit_operation_edge_uses_entry_pose",
        explicitOperationEdge.operationEntryPending and select(2, sample(explicitOperationEdge, 8)) == 3)
    WorkAnimation.update(explicitOperationEdge,
        input("operate", "edge-active", "work_press", { operationStarted = true }), .04, entryClip)
    check("employee_work_animation_repeated_operation_edge_does_not_restart_entry",
        explicitOperationEdge.operationEntryPending and math.abs(explicitOperationEdge.operationEntryElapsed-.04)<1e-8)

    local changedWhileActive = WorkAnimation.newRecord()
    WorkAnimation.update(changedWhileActive,
        input("operate", "old-active", "work_press", { operationStarted = true }), 0, entryClip)
    WorkAnimation.update(changedWhileActive, input("operate", "new-active", "work_press"), 0, entryClip)
    check("employee_work_animation_new_active_task_does_not_inherit_old_entry",
        changedWhileActive.taskKey == "new-active" and changedWhileActive.phase == "operate"
            and not changedWhileActive.operationEntryPending and select(2, sample(changedWhileActive, 8)) == 6)

    local stoppedDuringEntry = WorkAnimation.newRecord()
    WorkAnimation.update(stoppedDuringEntry,
        input("operate", "stop-entry", "work_press", { operationStarted = true }), 0, entryClip)
    WorkAnimation.update(stoppedDuringEntry, input("contact", "stop-entry", "work_press"), 0, entryClip)
    check("employee_work_animation_operation_stop_during_entry_starts_recovery",
        stoppedDuringEntry.phase == "recovery" and not stoppedDuringEntry.operationEntryPending
            and select(2, sample(stoppedDuringEntry, 8)) == 7)

    local resetDuringEntry = WorkAnimation.newRecord()
    WorkAnimation.update(resetDuringEntry,
        input("operate", "reset-entry", "work_press", { operationStarted = true }), 0, entryClip)
    WorkAnimation.reset(resetDuringEntry)
    check("employee_work_animation_reset_clears_operation_entry",
        resetDuringEntry.phase == "ready" and not resetDuringEntry.operationEntryPending
            and resetDuringEntry.operationEntryElapsed == 0 and resetDuringEntry.taskKey == nil)

    local defaultEntryDuration = WorkAnimation.newRecord()
    local defaultEntryClip = { action = "work_press", frameCount = 8, operationEntryFrame = 5,
        operationFrame = 6, approachFrames = { 2, 3, 4 }, recoveryFrames = { 7, 8 } }
    WorkAnimation.update(defaultEntryDuration,
        input("operate", "default-entry", "work_press", { operationStarted = true }), 0, defaultEntryClip)
    check("employee_work_animation_operation_entry_duration_defaults_to_point_one",
        defaultEntryDuration.clip.operationEntryDuration == .10 and defaultEntryDuration.operationEntryPending)

    local fractionalEntry, wholeEntry, hitchEntry =
        WorkAnimation.newRecord(), WorkAnimation.newRecord(), WorkAnimation.newRecord()
    for _, candidate in ipairs({ fractionalEntry, wholeEntry, hitchEntry }) do
        WorkAnimation.update(candidate,
            input("operate", "entry-dt", "work_press", { operationStarted = true }), 0, entryClip)
    end
    WorkAnimation.update(fractionalEntry, input("operate", "entry-dt", "work_press"), .025, entryClip)
    WorkAnimation.update(fractionalEntry, input("operate", "entry-dt", "work_press"), .025, entryClip)
    WorkAnimation.update(fractionalEntry, input("operate", "entry-dt", "work_press"), .05, entryClip)
    WorkAnimation.update(wholeEntry, input("operate", "entry-dt", "work_press"), .1, entryClip)
    check("employee_work_animation_operation_entry_fractional_dt_matches_whole_dt",
        fractionalEntry.phase == wholeEntry.phase and fractionalEntry.frame == wholeEntry.frame
            and not fractionalEntry.operationEntryPending and not wholeEntry.operationEntryPending
            and math.abs(fractionalEntry.operationEntryElapsed-wholeEntry.operationEntryElapsed)<1e-8)
    WorkAnimation.update(hitchEntry, input("operate", "entry-dt", "work_press"), .5, entryClip)
    check("employee_work_animation_operation_entry_hitch_finishes_into_static_hold",
        hitchEntry.phase == "operate" and not hitchEntry.operationEntryPending
            and select(2, sample(hitchEntry, 8)) == 6)

    WorkAnimation.update(record, input("contact", "job-a:press", "work_press"), 3, clip)
    check("employee_work_animation_contact_is_held_without_looping", record.phase == "contact"
        and select(2, sample(record, 8)) == 5)
    WorkAnimation.update(record, input("contact", "job-a:press", "work_press"), 0, clip)
    local changedContactClip = {
        action = "work_press", frameCount = 8, contactFrame = 4,
        operationFrame = 6, approachFrames = { 2, 3, 4 }, recoveryFrames = { 7, 8 },
        secondsPerFrame = .1,
    }
    WorkAnimation.update(record, input("contact", "job-a:press", "work_press"), 0, changedContactClip)
    check("employee_work_animation_contact_tracks_current_machine_substate", record.phase == "contact"
        and select(2, sample(record, 8)) == 4)

    WorkAnimation.update(record, input("operate", "job-a:press", "work_press"), 0, clip)
    WorkAnimation.update(record, input("operate", "job-a:press", "work_press"), 9, clip)
    check("employee_work_animation_operation_is_a_static_hold", record.phase == "operate"
        and select(2, sample(record, 8)) == 6)
    WorkAnimation.update(record, input("contact", "job-a:press", "work_press"), 0, clip)
    check("employee_work_animation_active_stop_starts_release", record.phase == "recovery"
        and select(2, sample(record, 8)) == 7)
    WorkAnimation.update(record, input("contact", "job-a:press", "work_press"), .1, clip)
    check("employee_work_animation_recovery_plays_second_frame", record.phase == "recovery"
        and select(2, sample(record, 8)) == 8)
    WorkAnimation.update(record, input("contact", "job-a:press", "work_press"), .1, clip)
    check("employee_work_animation_recovery_returns_through_approach", record.phase == "approach"
        and select(2, sample(record, 8)) == 2)
    WorkAnimation.update(record, input("contact", "job-a:press", "work_press"), .3, clip)
    check("employee_work_animation_reapproach_finishes_at_contact", record.phase == "contact"
        and select(2, sample(record, 8)) == 5)

    WorkAnimation.update(record, input("operate", "job-a:press", "work_press"), 0, clip)
    WorkAnimation.update(record, input("release", "job-a:press", "work_press",
        { safeToRecover = false }), 1, clip)
    check("employee_work_animation_interruption_waits_for_machine_safety", record.phase == "operate"
        and select(2, sample(record, 8)) == 6)
    WorkAnimation.update(record, input("release", "job-a:press", "work_press",
        { safeToRecover = true }), 0, clip)
    WorkAnimation.update(record, input("release", "job-a:press", "work_press",
        { safeToRecover = true }), .2, clip)
    check("employee_work_animation_safe_interruption_recovers_to_ready", record.phase == "ready"
        and record.taskKey == nil and select(2, sample(record, 8)) == 1)

    WorkAnimation.update(record, input("start", "old:press", "work_press"), 0, clip)
    WorkAnimation.update(record, input("start", "new:press", "work_press"), 0, clip)
    check("employee_work_animation_task_change_runs_old_recovery", record.taskKey == "old:press"
        and record.phase == "recovery")
    WorkAnimation.update(record, input("start", "new:press", "work_press"), .2, clip)
    check("employee_work_animation_task_change_starts_new_approach", record.taskKey == "new:press"
        and record.phase == "approach" and select(2, sample(record, 8)) == 2)

    local wrapperClip = {
        action = "work_wrapping", frameCount = 8, operationFrame = 5, contactFrame = 4,
        approachFrames = { 2, 3 }, recoveryFrames = { 6, 7, 8 }, secondsPerFrame = .1,
    }
    WorkAnimation.update(record, input("operate", "active:wrapper", "work_wrapping"), 0, wrapperClip)
    check("employee_work_animation_active_new_task_overrides_old_recovery", record.taskKey == "active:wrapper"
        and record.action == "work_wrapping" and record.phase == "operate"
        and select(2, sample(record, 8)) == 5)
    WorkAnimation.update(record, input("operate", "active:wrapper", "work_wrapping"), 0, wrapperClip)
    WorkAnimation.update(record, input("start", "pending:press", "work_press"), 0, clip)
    check("employee_work_animation_reset_fixture_has_pending_recovery", record.phase == "recovery"
        and record.pending ~= nil and record.action == "work_wrapping"
        and select(2, sample(record, 8)) == 6)
    WorkAnimation.reset(record)
    WorkAnimation.update(record, input("release", nil, nil), 10, clip)
    check("employee_work_animation_cancel_clears_old_task_immediately", record.phase == "ready"
        and record.taskKey == nil and record.action == nil and record.pending == nil
        and select(2, sample(record, 8)) == 1)
    WorkAnimation.update(record, input("operate", "active:press", "work_press"), 0, clip)
    WorkAnimation.update(record, { reset = true }, 0, clip)
    WorkAnimation.update(record, input("release", nil, nil), 10, clip)
    check("employee_work_animation_reset_input_does_not_resurface_cancelled_pose", record.phase == "ready"
        and record.taskKey == nil and record.action == nil)

    local legacy = WorkAnimation.newRecord()
    local legacyClip = { action = "work_wrapping", frameCount = 4, secondsPerFrame = .1 }
    WorkAnimation.update(legacy, input("start", "job:wrap", "work_wrapping"), 0, legacyClip)
    WorkAnimation.update(legacy, input("contact", "job:wrap", "work_wrapping"), .2, legacyClip)
    WorkAnimation.update(legacy, input("operate", "job:wrap", "work_wrapping"), 0, legacyClip)
    check("employee_work_animation_four_frame_fallback_stays_in_range", legacy.phase == "operate"
        and select(2, sample(legacy, 4)) == 4)
    WorkAnimation.update(legacy, input("release", "job:wrap", "work_wrapping"), 0, legacyClip)
    for index, dt in ipairs({ .1, .1, .1 }) do
        WorkAnimation.update(legacy, input("release", "job:wrap", "work_wrapping"), dt, legacyClip)
        local _, frame = sample(legacy, 4)
        check("employee_work_animation_fallback_never_exceeds_clip_" .. index, frame <= 4)
    end

    local fractionalA, fractionalB = WorkAnimation.newRecord(), WorkAnimation.newRecord()
    for _, candidate in ipairs({ fractionalA, fractionalB }) do
        WorkAnimation.update(candidate, input("start", "fractional", "work_press"), 0, clip)
    end
    WorkAnimation.update(fractionalA, input("contact", "fractional", "work_press"), .05, clip)
    WorkAnimation.update(fractionalA, input("contact", "fractional", "work_press"), .05, clip)
    WorkAnimation.update(fractionalB, input("contact", "fractional", "work_press"), .1, clip)
    check("employee_work_animation_fractional_dt_accumulates_stably", fractionalA.phase == fractionalB.phase
        and fractionalA.frame == fractionalB.frame and math.abs(fractionalA.elapsed-fractionalB.elapsed) < 1e-8)

    local hitch, stepped = WorkAnimation.newRecord(), WorkAnimation.newRecord()
    for _, candidate in ipairs({ hitch, stepped }) do
        WorkAnimation.update(candidate, input("operate", "hitch", "work_press"), 0, clip)
    end
    WorkAnimation.update(hitch, input("contact", "hitch", "work_press"), .5, clip)
    for _ = 1, 10 do
        WorkAnimation.update(stepped, input("contact", "hitch", "work_press"), .05, clip)
    end
    check("employee_work_animation_hitch_dt_matches_fractional_recovery_and_reapproach", hitch.phase == stepped.phase
        and hitch.frame == stepped.frame and hitch.phase == "contact"
        and math.abs(hitch.elapsed-stepped.elapsed) < 1e-8)

    local before = { hitch.action, hitch.taskKey, hitch.phase, hitch.frame,
        hitch.sequenceIndex, hitch.elapsed, hitch.recoveryTarget }
    for _ = 1, 5 do sample(hitch, 8) end
    local after = { hitch.action, hitch.taskKey, hitch.phase, hitch.frame,
        hitch.sequenceIndex, hitch.elapsed, hitch.recoveryTarget }
    local unchanged = true
    for index, value in ipairs(before) do
        if after[index] ~= value then unchanged = false end
    end
    check("employee_work_animation_render_sample_does_not_mutate_state", unchanged)
end

return Test
