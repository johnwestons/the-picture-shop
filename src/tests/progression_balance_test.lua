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
    local pressOffers,pressOfferError={},nil
    if pressBought then
        for index=1,5 do
            local offer,errors=context.jobService.createNextOffer(pressState,1000+index)
            if not offer then pressOfferError=table.concat(errors or {},"; ") end
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
        and Schedule.skillAllows(expert,pressOffers[3],"press"),
        string.format("bought=%s prints=%d jobs=%s skills=%s/%s fleet=%d/%d next=%s",
            tostring(pressBought), #pressOffers,
            table.concat({ pressOffers[1] and pressOffers[1].id or "-",
                pressOffers[1] and pressOffers[1].difficulty or "-",
                pressOffers[2] and pressOffers[2].id or "-",
                pressOffers[2] and pressOffers[2].difficulty or "-",
                pressOffers[3] and pressOffers[3].id or "-",
                pressOffers[3] and pressOffers[3].difficulty or "-" }, "/"),
            tostring(pressOffers[1] and Schedule.skillAllows(intermediate,pressOffers[1],"press")),
            tostring(pressOffers[3] and Schedule.skillAllows(expert,pressOffers[3],"press")),
            #context.machineFleet.installedUnits(pressState,"polar_115"),
            #context.machineFleet.installedUnits(pressState,"heidelberg_10x15"),
            tostring(pressState.nextJobId) .. " error=" .. tostring(pressOfferError)))

    local mixedFleet=context.State.new()
    mixedFleet.money=100000
    mixedFleet.reputation.score=20
    local secondCutter=context.machineFleet.buy(mixedFleet,"dealer",1)
    local onePress=context.machineFleet.buy(mixedFleet,"dealer",3)
    local mixedPrint,mixedCut=0,0
    local doubledCutVolume=false
    for index=1,9 do
        local offer=context.jobService.createNextOffer(mixedFleet,3000+index)
        if offer then
            if offer.press then mixedPrint=mixedPrint+1
            else
                mixedCut=mixedCut+1
                if index==2 then doubledCutVolume=#offer.pallets==4 end
            end
            context.jobService.declineOffer(mixedFleet,offer,4000+index)
        end
    end
    check("job_mix_tracks_one_press_to_two_cutter_capacity",
        secondCutter and onePress and mixedPrint==3 and mixedCut==6 and doubledCutVolume)

    local pressCapacity=context.State.new()
    pressCapacity.money=100000
    pressCapacity.reputation.score=0
    local pressOne=context.machineFleet.buy(pressCapacity,"dealer",3)
    local pressTwo=context.machineFleet.buy(pressCapacity,"dealer",3)
    local firstExpandedPrint=context.jobService.createNextOffer(pressCapacity,5000)
    local printShare,cutShare=firstExpandedPrint and firstExpandedPrint.press and 1 or 0,0
    if firstExpandedPrint then context.jobService.declineOffer(pressCapacity,firstExpandedPrint,6000) end
    for index=2,9 do
        local offer=context.jobService.createNextOffer(pressCapacity,5000+index)
        if offer then
            if offer.press then printShare=printShare+1 else cutShare=cutShare+1 end
            context.jobService.declineOffer(pressCapacity,offer,6000+index)
        end
    end
    check("job_mix_and_volume_scale_with_two_printing_presses",
        pressOne and pressTwo and firstExpandedPrint and firstExpandedPrint.press
        and #firstExpandedPrint.pallets==2 and printShare==6 and cutShare==3)

    local pressStarter=context.State.new()
    pressStarter.money=20000
    local starterPressBought=context.machineFleet.buy(pressStarter,"dealer",3)
    local starterPrint=starterPressBought
        and context.jobService.createNextOffer(pressStarter,7000)
    check("installed_press_receives_easy_print_work_before_reputation_unlocks",
        starterPrint and starterPrint.press and starterPrint.difficulty=="easy")

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
