-- Test-page balance experiment v2. Promote to the game only after user approval.
local Game = {}
local ORDERS = {
    {name="Gallery brochures", stock="Medium cover stock", fold=55, guide=50, air=2},
    {name="Cafe menus", stock="Light uncoated stock", fold=45, guide=55, air=1},
    {name="Invitation sleeves", stock="Heavy cover stock", fold=60, guide=45, air=3},
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Game.new(orderIndex)
    orderIndex = ((orderIndex or 1)-1) % #ORDERS + 1
    local order=ORDERS[orderIndex]
    return {
        phase = "setup", fold = 40, guide = 45, air = 0, speed = 2,
        targetFold = order.fold, targetGuide = order.guide, targetAir=order.air,
        orderIndex=orderIndex, orderName=order.name, stockName=order.stock,
        orderNumber=string.format("RF-%03d",orderIndex),proof = false,
        stock = 8, fed = 0, target = 24, inTransit = {}, delivery = 0,
        deliveryAges={}, deliveryLimit=6, oldestAge=0,
        held = 0, boxed = 0, boxes = 0, spoiled = 0, jams = 0,
        boxingRemaining=0, boxingDuration=1.2, score=0, combo=0, bestCombo=0,
        perfectCatches=0, lastCatch="", catchFlash=0, rating="", assisted=false,
        feedClock = 0, time = 0, view = 1,
        message = "Operator: set the fold stop, guides and air, then inspect a proof.",
    }
end

local function ready(run)
    return math.abs(run.fold - run.targetFold) <= 2
        and math.abs(run.guide - run.targetGuide) <= 2 and run.air == run.targetAir
end

function Game.dispatch(run, action)
    if action == "reset" then return Game.new(run.orderIndex+1), true end
    if action == "rotate_view" then
        run.view = run.view % 8 + 1
        return run, true
    end
    if run.phase == "complete" then return run, false end
    if action == "assist_setup" then
        if run.phase=="running" or run.phase=="jammed" then return run,false end
        run.fold,run.guide,run.air=run.targetFold,run.targetGuide,run.targetAir
        run.proof,run.assisted=true,true
        run.message="Practice setup applied. Start when ready; catch in the green window for a bonus."
        return run,true
    end
    if action == "fold_down" or action == "fold_up" then
        if run.phase == "running" or run.phase == "jammed" then return run, false end
        run.fold = clamp(run.fold + (action == "fold_up" and 5 or -5), 20, 80)
        run.proof = false
    elseif action == "guide_down" or action == "guide_up" then
        if run.phase == "running" or run.phase == "jammed" then return run, false end
        run.guide = clamp(run.guide + (action == "guide_up" and 5 or -5), 30, 70)
        run.proof = false
    elseif action == "air" then
        if run.phase == "running" or run.phase == "jammed" then return run, false end
        run.air = (run.air + 1) % 4
        run.proof = false
    elseif action == "speed_down" or action == "speed_up" then
        run.speed = clamp(run.speed + (action == "speed_up" and 1 or -1), 1, 3)
    elseif action == "proof" then
        if run.phase == "running" or run.phase == "jammed" then return run, false end
        run.proof = ready(run)
        if run.proof then
            run.message = "Proof is square and clean. Start the run; catcher, stand by."
        else
            run.spoiled = run.spoiled + 1
            run.message = "Proof rejected. Match the fold stop, guides and air to this work order."
        end
    elseif action == "start_stop" then
        if run.phase == "running" then
            run.phase = "paused"
            run.message = "Feed stopped. Catch and box the remaining sheets."
        elseif (run.phase == "setup" or run.phase == "paused") and run.proof then
            run.phase = "running"
            run.message = "Folder running. Feed stock and keep the delivery clear."
        else
            run.message = "Inspect an acceptable proof before starting."
        end
    elseif action == "refill" then
        if run.stock >= 8 or run.fed + run.stock >= run.target then return run, false end
        run.stock = math.min(8, run.target - run.fed)
        run.message = "Operator loaded the next pile at the feeder."
    elseif action == "catch" then
        if run.delivery <= 0 or run.held >= 6 or run.boxingRemaining>0 then return run, false end
        local age=table.remove(run.deliveryAges,1)
        local perfect=age>=.25 and age<=1.1
        if perfect then
            run.combo=run.combo+1
            run.bestCombo=math.max(run.bestCombo,run.combo)
            run.perfectCatches=run.perfectCatches+1
        else run.combo=0 end
        local points=10+(run.speed-1)+(perfect and (5+math.min(4,run.combo)*2) or 0)
        run.score=run.score+points
        run.lastCatch=(perfect and "PERFECT" or "CAUGHT").." +"..points
        run.catchFlash=1.1
        run.delivery = run.delivery - 1
        run.oldestAge=run.deliveryAges[1] or 0
        run.held = run.held + 1
        run.message = perfect and "Nice timing! Keep the rhythm for a streak bonus."
            or "Piece caught safely. Catch in the green window for bonus points."
    elseif action == "box" then
        if run.boxingRemaining>0 or run.held <= 0 or (run.held < 6 and (run.fed < run.target
            or #run.inTransit > 0 or run.delivery > 0)) then return run, false end
        run.boxingRemaining=run.boxingDuration
        run.message = "Packing for 1.2 seconds. Watch delivery; you can stop the feeder."
    elseif action == "clear_jam" then
        if run.phase ~= "jammed" then return run, false end
        run.phase = "paused"
        run.proof = false
        run.message = "Jam cleared with the feeder stopped. Reset setup and check another proof."
    else
        return run, false
    end
    return run, true
end

function Game.update(run, dt)
    dt = clamp(tonumber(dt) or 0, 0, 0.1)
    if run.phase == "complete" then return false end
    run.time = run.time + dt
    local changed = false
    run.catchFlash=math.max(0,run.catchFlash-dt)
    if run.boxingRemaining>0 then
        run.boxingRemaining=math.max(0,run.boxingRemaining-dt)
        if run.boxingRemaining==0 then
            run.boxed=run.boxed+run.held;run.held=0;run.boxes=run.boxes+1
            run.score=run.score+25
            run.message="Box packed! +25 points. Back to the delivery."
            changed=true
        end
    end
    for i=1,#run.deliveryAges do run.deliveryAges[i]=run.deliveryAges[i]+dt end
    for index = #run.inTransit, 1, -1 do
        local remaining = run.inTransit[index] - dt
        if remaining <= 0 then
            table.remove(run.inTransit, index)
            run.delivery = run.delivery + 1
            run.deliveryAges[#run.deliveryAges+1]=0
            changed = true
        else
            run.inTransit[index] = remaining
        end
    end
    run.oldestAge=run.deliveryAges[1] or 0
    if run.phase == "running" and run.fed < run.target then
        run.feedClock = run.feedClock + dt
        local interval = ({1.3,.95,.70})[run.speed]
        if run.feedClock >= interval then
            run.feedClock = run.feedClock - interval
            if run.stock > 0 then
                run.stock = run.stock - 1
                run.fed = run.fed + 1
                run.inTransit[#run.inTransit + 1] = 1.15
                changed = true
            else
                run.phase = "paused"
                run.message = "Feeder is empty. Operator: load the next pile."
                changed = true
            end
        end
    end
    if run.delivery > run.deliveryLimit and run.phase ~= "jammed" then
        run.phase = "jammed"
        run.spoiled = run.spoiled + run.delivery + #run.inTransit
        run.delivery, run.inTransit = 0, {}
        run.deliveryAges={};run.oldestAge=0;run.combo=0;run.score=math.max(0,run.score-20)
        run.jams = run.jams + 1
        run.message = "Delivery exceeded six pieces. Clear the jam, then proof again. Try a slower speed."
        changed = true
    end
    if run.fed >= run.target and #run.inTransit == 0 and run.delivery == 0
        and run.held == 0 and run.boxingRemaining==0
    then
        run.phase = "complete"
        run.rating=run.boxed==24 and run.jams==0 and run.perfectCatches>=12 and "GOLD RHYTHM"
            or run.boxed>=20 and "CLEAN FINISH" or "BATCH FINISHED"
        run.message = string.format("%s: %d good pieces, %d points, %d perfect catches. Best streak: %d.",
            run.rating,run.boxed,run.score,run.perfectCatches,run.bestCombo)
        changed = true
    end
    return changed
end

return Game
