-- A short two-station folder run. This is a practice batch, separate from paid jobs.
local Game = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Game.new()
    return {
        phase = "setup", fold = 40, guide = 45, air = 0, speed = 2,
        targetFold = 55, targetGuide = 50, proof = false,
        stock = 8, fed = 0, target = 24, inTransit = {}, delivery = 0,
        held = 0, boxed = 0, boxes = 0, spoiled = 0, jams = 0,
        feedClock = 0, time = 0, view = 1,
        message = "Operator: set the fold stop, guides and air, then inspect a proof.",
    }
end

local function ready(run)
    return math.abs(run.fold - run.targetFold) <= 2
        and math.abs(run.guide - run.targetGuide) <= 2 and run.air == 2
end

function Game.dispatch(run, action)
    if action == "reset" then return Game.new(), true end
    if action == "rotate_view" then
        run.view = run.view % 8 + 1
        return run, true
    end
    if run.phase == "complete" then return run, false end
    if action == "fold_down" or action == "fold_up" then
        if run.phase == "running" then return run, false end
        run.fold = clamp(run.fold + (action == "fold_up" and 5 or -5), 20, 80)
        run.proof = false
    elseif action == "guide_down" or action == "guide_up" then
        if run.phase == "running" then return run, false end
        run.guide = clamp(run.guide + (action == "guide_up" and 5 or -5), 30, 70)
        run.proof = false
    elseif action == "air" then
        if run.phase == "running" then return run, false end
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
            run.message = "Proof rejected. Match fold stop and guides to the job card; set air to 2."
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
        if run.delivery <= 0 or run.held >= 6 then return run, false end
        run.delivery = run.delivery - 1
        run.held = run.held + 1
        run.message = "Catcher collected a folded piece. Box six at a time."
    elseif action == "box" then
        if run.held <= 0 or (run.held < 6 and (run.fed < run.target
            or #run.inTransit > 0 or run.delivery > 0)) then return run, false end
        run.boxed = run.boxed + run.held
        run.boxes = run.boxes + 1
        run.held = 0
        run.message = "Catcher packed and labeled a box."
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
    for index = #run.inTransit, 1, -1 do
        local remaining = run.inTransit[index] - dt
        if remaining <= 0 then
            table.remove(run.inTransit, index)
            run.delivery = run.delivery + 1
            changed = true
        else
            run.inTransit[index] = remaining
        end
    end
    if run.phase == "running" and run.fed < run.target then
        run.feedClock = run.feedClock + dt
        local interval = 1.4 - run.speed * 0.25
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
    if run.delivery > 8 and run.phase ~= "jammed" then
        run.phase = "jammed"
        run.spoiled = run.spoiled + run.delivery + #run.inTransit
        run.delivery, run.inTransit = 0, {}
        run.jams = run.jams + 1
        run.message = "Delivery backed up. Stop and clear the jam; then proof again."
        changed = true
    end
    if run.fed >= run.target and #run.inTransit == 0 and run.delivery == 0
        and run.held == 0 and run.boxed + run.spoiled >= run.target
    then
        run.phase = "complete"
        run.message = string.format("Batch complete: %d good pieces in %d boxes; %d spoiled.",
            run.boxed, run.boxes, run.spoiled)
        changed = true
    end
    return changed
end

return Game
