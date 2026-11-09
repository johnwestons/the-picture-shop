local State = require("src.state")
local Jobs = require("src.jobs")
local Schema = require("src.save_schema")
local Calendar = require("src.business_calendar")
local PalletState = require("src.pallet_state")
local Feedback = require("src.job_feedback")
local WorkPhone = require("src.work_phone")

local Test = {}

local function validSavedState(state)
    local snapshot = Schema.snapshot(state)
    return snapshot ~= nil and Schema.validState(snapshot)
end

local function newJob(state, id, dueDate)
    local job = assert(Jobs.createOffer({
        id = id,
        company = "Feedback Test Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 },
        packaging = "flat",
        details = { dueDate = dueDate or "Five business days" },
    }))
    assert(state and state.jobs)
    assert(require("src.job_service").acceptOffer(state, job, 100))
    job.status = "in_production"
    job.delivery.status = "received"
    job.delivery.acceptedGameHours = 0
    job.acceptedGameHours = 0
    return job
end

local function finishPallet(state, pallet, offSpec)
    pallet.location = "warehouse"
    pallet.world = {
        x = 620, y = 500, fromX = 620, fromY = 500,
        direction = "northwest", rotation = 1, spawnProgress = 1, sceneId = "warehouse",
    }
    pallet.status, pallet.remainingSheets, pallet.finishedSheets = "wrapped", 0, 500
    pallet.wrapped = true
    pallet.paper.status = "complete"
    pallet.paper.offSpec = offSpec == true
    pallet.paper.cutQuality = offSpec and 0.70 or 1
    state.inventory.finishedPallets = (state.inventory.finishedPallets or 0) + 1
end

function Test.run(context, check)
    local clean = State.new()
    local cleanJob = newJob(clean, "JOB-FEEDBACK-PASS")
    finishPallet(clean, cleanJob.pallets[1], false)
    local inspectionReady = Feedback.progress(clean, cleanJob)
    Feedback.sync(clean)
    check("feedback_wrapped_job_is_ready_for_inspection_before_qc",
        inspectionReady.stage == "READY FOR INSPECTION"
            and inspectionReady.nextAction == "Inspect the finished job on the computer"
            and cleanJob.feedback.stage == "READY FOR INSPECTION")
    local inspected, result = context.jobService.inspectJob(clean, cleanJob.id)
    local pickup = inspected and context.jobService.requestPickup(clean, cleanJob, 101)
    check("feedback_clean_job_passes_sample_check_and_releases_pickup",
        inspected and result.status == "passed" and pickup == true
            and cleanJob.inspection.firstPass == true and cleanJob.status == "ready_for_pickup")
    check("feedback_clean_job_record_passes_save_validation", validSavedState(clean))

    local rework = State.new()
    local badJob = newJob(rework, "JOB-FEEDBACK-REWORK")
    finishPallet(rework, badJob.pallets[1], true)
    local held, holdResult = context.jobService.inspectJob(rework, badJob.id)
    check("feedback_known_offsize_output_is_held_for_rework",
        held and holdResult.status == "held" and #holdResult.findings > 0)
    local reworked, reworkResult = context.jobService.requestQualityRework(rework, badJob.id)
    local replacement = reworked and reworkResult.pallets[1]
    check("feedback_rework_reenters_normal_stock_and_machine_flow",
        reworked and replacement and replacement.location == "awaiting_delivery"
            and replacement.status == "replacement_in_transit"
            and badJob.delivery.status == "replacement_pending"
            and badJob.inspection.status == "rework_in_progress"
            and rework.bills.balance > 0 and rework.inventory.finishedPallets == 0)
    check("feedback_rework_job_record_passes_save_validation", validSavedState(rework))

    local alertState = State.new()
    local alertJob = newJob(alertState, "JOB-FEEDBACK-ALERT")
    alertState.employment.staff[1] = {
        id = "WORKER-FEEDBACK", name = "Casey", activity = "Cutter safety needs attention",
        assignment = { jobId = alertJob.id, palletId = alertJob.pallets[1].id },
    }
    Feedback.sync(alertState)
    local eventCount = #alertJob.feedback.events
    Feedback.sync(alertState)
    local alertCount = 0
    for _, event in ipairs(alertJob.feedback.events) do
        if event.stage == "employee_alert" then alertCount = alertCount + 1 end
    end
    check("feedback_employee_blocker_is_recorded_once_until_it_changes",
        alertCount == 1 and #alertJob.feedback.events == eventCount)

    local late = State.new()
    local lateJob = newJob(late, "JOB-FEEDBACK-LATE")
    finishPallet(late, lateJob.pallets[1], false)
    late.calendar = Calendar.dateFromTotalDay(8)
    late.calendar.secondsPerDay = Calendar.defaultCalendar().secondsPerDay
    late.calendar.elapsed = late.calendar.secondsPerDay / 24
    local lateInspection = context.jobService.inspectJob(late, lateJob.id)
    local ready = lateInspection and context.jobService.requestPickup(late, lateJob, 102)
    local scheduled = ready and context.jobService.schedulePickup(lateJob, 103)
    local loaded = scheduled and PalletState.transition(late, lateJob.pallets[1], "outbound_truck",
        { status = "loaded_for_pickup" })
    local closed = loaded and context.jobService.completePickup(late, lateJob.id, 104)
    local reviewBefore = late.reputation.reviews[1] and late.reputation.reviews[1].rating
    local complaintCall = late.workPhone.incoming
    if complaintCall then
        WorkPhone.answer(late)
        WorkPhone.respond(late)
    end
    local caseEmail
    for _, email in ipairs(late.clientEmails.inbox) do
        if email.id == "CASE-" .. lateJob.id then caseEmail = email end
    end
    check("feedback_late_pickup_creates_one_actionable_email_and_urgent_call",
        closed and lateJob.customerCase and lateJob.customerCase.status == "open"
            and caseEmail and caseEmail.noticeKind == "customer_case"
            and complaintCall and complaintCall.kind == "customer_complaint"
            and reviewBefore ~= nil)
    local resolved, case = context.jobService.resolveCustomerCase(late, lateJob.id, "credit")
    local reviewAfter = late.reputation.reviews[1] and late.reputation.reviews[1].rating
    check("feedback_customer_credit_updates_bills_and_review",
        resolved and lateJob.customerCase.status == "resolved"
            and lateJob.customerCase.resolution == "credit"
            and lateJob.customerCase.creditAmount > 0
            and lateJob.feedback.deliveredSheets == 500
            and late.bills.balance >= lateJob.customerCase.creditAmount
            and reviewAfter == math.min(5, reviewBefore + 1))

    check("feedback_case_passes_save_validation", validSavedState(late))
end

return Test
