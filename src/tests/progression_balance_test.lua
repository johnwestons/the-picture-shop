local Schedule=require("src.employee_schedule")
local Employees=require("src.employees")
local Workers=require("src.worker_catalog")
local Test={}

local function receptionOffer(context,score,sequence)
    local state=context.State.new()
    state.reputation.score=score
    state.nextJobId=sequence
    return context.jobService.createNextOffer(state,sequence),state
end

local function repeatOffer(context,source,score)
    local state=context.State.new()
    state.reputation.score=score
    state.clientEmails.nextEmailId=3
    local scheduled=context.jobService.scheduleRepeatEmail(state,source)
    return scheduled and state.clientEmails.pending[1] and state.clientEmails.pending[1].job
end

function Test.run(context,check)
    local starter=receptionOffer(context,0,1)
    local beginner,intermediate,expert=Workers.profiles[1],Workers.profiles[2],Workers.profiles[3]
    check("progression_starter_job_fits_first_applicant",
        starter and starter.difficulty=="easy" and starter.quote.totalLifts==1
        and Schedule.skillAllows(beginner,starter,"cutter")
        and Schedule.skillAllows(beginner,starter,"wrapping"))

    local early=receptionOffer(context,5,2)
    local medium=receptionOffer(context,20,6)
    local easyAtReliable=receptionOffer(context,20,5)
    local hard=receptionOffer(context,50,12)
    check("progression_cutting_jobs_advance_with_reputation",
        early and early.difficulty=="easy" and medium and medium.difficulty=="medium"
        and hard and hard.difficulty=="hard")
    check("progression_worker_skills_match_easy_medium_hard_work",
        Schedule.skillAllows(beginner,early,"wrapping")
        and Schedule.skillAllows(intermediate,medium,"cutter")
        and Schedule.skillAllows(intermediate,medium,"wrapping")
        and not Schedule.skillAllows(beginner,medium,"wrapping")
        and Schedule.skillAllows(expert,hard,"cutter")
        and Schedule.skillAllows(expert,hard,"wrapping")
        and not Schedule.skillAllows(intermediate,hard,"cutter"))
    check("progression_medium_job_pays_more_per_lift_than_easy_job",
        medium.quote.totalPrice/medium.quote.totalLifts
            > easyAtReliable.quote.totalPrice/easyAtReliable.quote.totalLifts)

    local noEarlyHard=true
    for _,score in ipairs({0,5,20}) do
        local state=context.State.new()
        state.reputation.score=score
        for sequence=1,15 do
            state.nextJobId=sequence
            local offer=context.jobService.createNextOffer(state,sequence)
            if not offer or offer.difficulty=="hard" then noEarlyHard=false end
        end
    end
    check("progression_early_reception_sequence_never_forces_hard_job",noEarlyHard)

    local pressState=context.State.new()
    pressState.money=20000
    pressState.reputation.score=50
    local pressBought=context.machineFleet.buy(pressState,"dealer",3)
    local pressOffers={}
    if pressBought then
        for index=1,5 do
            local offer=context.jobService.createNextOffer(pressState,1000+index)
            if offer then
                if offer.press then pressOffers[#pressOffers+1]=offer end
                context.jobService.declineOffer(pressState,offer,2000+index)
            end
        end
    end
    check("progression_print_jobs_step_from_easy_to_medium_to_hard",
        pressBought and #pressOffers==3
        and pressOffers[1].difficulty=="easy"
        and pressOffers[2].difficulty=="medium"
        and pressOffers[3].difficulty=="hard"
        and Schedule.skillAllows(intermediate,pressOffers[1],"press")
        and Schedule.skillAllows(expert,pressOffers[3],"press"))

    local pressTraining=Employees.trainingPlan(beginner,"press")
    local wrapTraining=Employees.trainingPlan(beginner,"wrapping")
    check("progression_training_reaches_next_available_stage",
        pressTraining and pressOffers[1]
        and pressTraining.target>=Schedule.minimumSkills(pressOffers[1]).press
        and wrapTraining and wrapTraining.target>=Schedule.minimumSkills(medium).wrapping)

    starter.status="completed"
    local earlyRepeat=repeatOffer(context,starter,5)
    local mediumRepeat=repeatOffer(context,starter,20)
    local hardRepeat=repeatOffer(context,starter,50)
    check("progression_followup_volume_and_difficulty_respect_shop_tier",
        earlyRepeat and earlyRepeat.difficulty=="easy" and #earlyRepeat.pallets==1
        and earlyRepeat.quote.totalSheets<=1000
        and mediumRepeat and mediumRepeat.difficulty=="medium" and #mediumRepeat.pallets<=2
        and mediumRepeat.quote.totalSheets<=4000
        and hardRepeat and hardRepeat.difficulty=="hard" and #hardRepeat.pallets==3)
end

return Test
