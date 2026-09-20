local SetupGames = require("src.press_setup_games")
local Test = {}
local sequences = {
    chase={"align","align","square","square","tighten","tighten"},
    packing={"layer","layer","layer","smooth","smooth","clamp"},
    rollers={"left_up","left_up","right_down","right_down"},
    ink={"key_1","key_1","key_2","key_2","key_2","key_2","key_3","ductor"},
    feeder={"prepare","suction_up","air_down","test","test","test"},
    register={"left","left","left","down","down","test"},
}

function Test.run(context, check, journey)
    local state, guest, job, pallet = journey.state, journey.guest, journey.job, journey.pallet
    local remote, click, key = journey.remote, journey.click, journey.key
    local confirmed, sync = journey.confirmed, journey.sync
    local function expect(label, passed, detail) check("guest_journey_"..label,passed,detail) end
    local function tab(index) click(95+(index-1)*136,139) end
    local function advance(dt) context.windmill.update(dt,state); sync(); remote.update(0.1) end
    journey.stage(pallet,state.windmill.x-60,state.windmill.y+30)
    journey.acquire("windmill"); tab(2)
    journey.render("plate_room")
    -- Deterministic timing fixture for the displayed plate marker, not a supplied
    -- score: the real host handler calculates every exposure/wash/dry/mount score.
    local previousClock=love.timer.getTime
    love.timer.getTime=function() return math.asin(0.34)/2.2 end
    sync()
    for color=1,2 do
        click(140+(color-1)*190,249)
        confirmed("plate_begin_"..color,function() click(430,519); click(430,519) end,true)
        for step=1,4 do
            confirmed("plate_process_"..color.."_"..step,function() click(730,519); click(730,519) end,true)
        end
        local plate=job.press.plates[color]
        expect("plate_ready_"..color,plate.mounted and plate.quality==1 and #plate.processScores==4)
    end
    love.timer.getTime=previousClock
    expect("plate_supplies_consumed_once",state.inventory.stock.raw_press_plates==2
        and state.inventory.stock.negative_film==2 and state.inventory.stock.plate_adhesive==2
        and state.inventory.stock.plate_chemistry==2 and job.press.actual.inHousePlates==2)
    for color=1,2 do
        tab(1)
        confirmed("press_load_"..color,function() click(480,545); click(480,545) end,true)
        local process=context.windmill.ensure(state)
        tab(3)
        for taskIndex,task in ipairs(context.windmill.setupTasks()) do
            local row,column=math.floor((taskIndex-1)/2),(taskIndex-1)%2
            confirmed("setup_open_"..color.."_"..task,function() click(256+column*426,235+row*112) end)
            journey.render("setup_"..color.."_"..task)
            local controls=SetupGames.controls(task)
            local width=math.floor((840-8*(#controls-1))/#controls)
            for step,action in ipairs(sequences[task]) do
                local index
                for i,control in ipairs(controls) do if control[1]==action then index=i; break end end
                assert(index,"Missing visible setup action")
                confirmed("setup_"..color.."_"..task.."_"..step,function()
                    click(60+(index-1)*(width+8)+width/2,598)
                end,true)
            end
            expect("setup_scored_"..color.."_"..task,process.setup[task]==1)
        end
        tab(1)
        confirmed("motor_"..color,function() key("m"); key("m") end,true)
        confirmed("feeder_"..color,function() key("f") end)
        confirmed("impression_"..color,function() key("i") end)
        local feedBefore=process.feedRemaining
        confirmed("proof_"..color,function() key("p"); key("p") end,true)
        expect("one_proof_sheet_"..color,process.feedRemaining==feedBefore-1 and process.counter==1)
        journey.render("proof_"..color)
        confirmed("verify_art_"..color,function() click(480,584) end)
        confirmed("approve_proof_"..color,function() click(746,584) end)
        tab(1)
        confirmed("start_run_"..color,function() click(647,439); click(647,439) end,true)
        if color==1 then
            advance(0.1)
            local count,good,lease=process.counter,process.goodSheets,remote.leaseId
            expect("production_began_before_disconnect",good>0 and good<process.targetSheets)
            journey.disconnect(); advance(1)
            expect("disconnected_press_stops_without_extra_sheets",process.counter==count and process.goodSheets==good
                and not process.motor and not process.feeder and not process.impression and process.status=="approved")
            journey.connect(); journey.acquire("windmill")
            journey.network:advanceSteps(8); journey.pump()
            expect("press_reconnect_restores_counts",remote.leaseId~=lease and remote.view.counter==count
                and remote.view.goodSheets==good and not remote.view.motor)
            confirmed("resume_motor",function() key("m") end)
            confirmed("resume_feeder",function() key("f") end)
            confirmed("resume_impression",function() key("i") end)
            confirmed("resume_run",function() click(647,439) end)
        end
        advance(10)
        expect("exact_pass_target_"..color,process.status=="pass_complete" and process.goodSheets==process.targetSheets
            and remote.view.goodSheets==process.goodSheets)
        local wash=state.inventory.stock.press_wash
        confirmed("clean_unload_"..color,function() click(822,439); click(822,439) end,true)
        expect("wash_and_pass_record_once_"..color,state.inventory.stock.press_wash==wash-1
            and #pallet.press.passHistory==color and pallet.press.completedColors==color)
        if color==1 then
            expect("wet_stock_not_loadable",pallet.press.status=="drying" and #remote.view.candidates==0)
            local hours=pallet.press.dryUntilHours-context.businessCalendar.absoluteHours(state)
            context.businessCalendar.update(state,hours/24*context.config.businessCalendar.secondsPerDay+0.01)
            sync()
            expect("dry_stock_reappears_for_second_color",#remote.view.candidates==1)
        end
    end
    expect("print_stock_and_guest_match",pallet.finishedSheets==450 and pallet.press.status=="complete"
        and guest.jobs.active[1].pallets[1].finishedSheets==450
        and guest.jobs.active[1].pallets[1].press.completedColors==2
        and state.inventory.stock.black_ink==3 and state.inventory.stock.color_ink==3
        and state.inventory.stock.tympan_sheets==2 and state.inventory.stock.press_wash==2)
    journey.release()
end
return Test
