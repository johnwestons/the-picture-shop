-- Hand-fed Chandler & Price platen die-cutting/creasing sample runs.
-- The artwork examples define the two layouts; dimensions are press-sized.
local Game = {}

Game.jobs = {
    {
        id = "two_pocket_folder", name = "TWO-POCKET FOLDER",
        blank = "10 x 9 in scaled blank", output = "flat cut and scored folder blanks",
        detail = "Two panels, two lower pockets, center fold and pocket scores",
        gauge = 3, packing = 2, target = 12, bundle = 6,
    },
    {
        id = "box_layout", name = "BOX LAYOUT",
        blank = "compact carton net", output = "flat cut and scored carton blanks",
        detail = "Front/back panels, side glue tab and top/bottom flaps",
        gauge = 1, packing = 3, target = 12, bundle = 6,
    },
}

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function Game.new(jobIndex)
    local index = clamp(math.floor(tonumber(jobIndex) or 1), 1, #Game.jobs)
    return {
        jobIndex = index, phase = "setup", dieLocked = false,
        gauge = 0, packing = 1, impression = false, grippersChecked = false,
        proof = false, speed = 1, cycle = 0, view = 1,
        stock = 12, fed = 0, pending = 0, delivery = 0, held = 0,
        boxed = 0, boxes = 0, spoiled = 0, missedFeeds = 0,
        message = "Lock the correct die in the chase, then set gauges, packing and grippers.",
    }
end

function Game.job(run) return Game.jobs[run.jobIndex] end

function Game.platenOpen(run)
    return (run.cycle or 0) < 1.2
end

function Game.setupReady(run)
    local job = Game.job(run)
    return run.dieLocked and run.grippersChecked and run.gauge == job.gauge
        and run.packing == job.packing and run.impression
end

local function invalidateProof(run)
    run.proof = false
    if run.phase == "paused" then run.phase = "setup" end
end

local function complete(run)
    if run.fed >= Game.job(run).target and run.pending == 0 and run.delivery == 0
        and run.held == 0 and run.boxed + run.spoiled >= run.fed then
        run.phase = "complete"
        run.impression = false
        run.message = string.format("Run complete: %d flat blanks boxed; %d spoiled.", run.boxed, run.spoiled)
    end
end

function Game.dispatch(run, action)
    if action == "view" then run.view = run.view % 8 + 1; return run, true end
    if action == "new_run" then return Game.new(run.jobIndex), true end
    if action == "job_previous" or action == "job_next" then
        if run.phase == "running" or run.fed > 0 then return run, false end
        return Game.new(action == "job_previous"
            and (run.jobIndex - 2) % #Game.jobs + 1 or run.jobIndex % #Game.jobs + 1), true
    end
    if run.phase == "complete" then return run, false end
    local setting = action == "die" or action == "gauge_down" or action == "gauge_up"
        or action == "packing_down" or action == "packing_up"
        or action == "grippers" or action == "impression"
    if setting and (run.phase == "running" or run.phase == "jammed" or run.pending > 0) then return run, false end
    if action == "die" then
        run.dieLocked = not run.dieLocked; invalidateProof(run)
    elseif action == "gauge_down" or action == "gauge_up" then
        run.gauge = clamp(run.gauge + (action == "gauge_up" and 1 or -1), 0, 4)
        invalidateProof(run)
    elseif action == "packing_down" or action == "packing_up" then
        run.packing = clamp(run.packing + (action == "packing_up" and 1 or -1), 1, 4)
        invalidateProof(run)
    elseif action == "grippers" then
        run.grippersChecked = not run.grippersChecked; invalidateProof(run)
    elseif action == "impression" then
        run.impression = not run.impression; invalidateProof(run)
    elseif action == "proof" then
        if run.phase == "running" or run.phase == "jammed"
            or run.pending > 0 or run.stock <= 0 then return run, false end
        run.stock = run.stock - 1
        run.spoiled = run.spoiled + 1
        run.proof = Game.setupReady(run)
        run.message = run.proof and "Proof approved: cut and scores align. Start for automatic feeding."
            or "Proof rejected: check die, grippers, gauge, packing and impression."
    elseif action == "start_stop" then
        if run.phase == "running" then
            run.phase = "paused"
            if run.pending > 0 then
                run.spoiled = run.spoiled + run.pending
                run.pending = 0
                run.message = "Press stopped mid-cycle; the held sheet was spoiled. Collect the delivery."
            else
                run.message = "Press stopped. Collect and box delivered blanks."
            end
        elseif (run.phase == "setup" or run.phase == "paused") and run.proof
            and Game.setupReady(run) and run.fed < Game.job(run).target then
            run.phase = "running"; run.cycle = 0
            run.message = "Press running. Sheets feed automatically at each open platen."
        else
            run.message = "Approve a correctly set proof before starting."
        end
    elseif action == "feed" then
        if run.phase ~= "running" or not Game.platenOpen(run)
            or run.pending > 0 or run.stock <= 0
            or run.fed >= Game.job(run).target then return run, false end
        run.stock = run.stock - 1; run.fed = run.fed + 1; run.pending = 1
        run.message = "Sheet placed at the open platen; stand clear for the impression."
    elseif action == "collect" then
        if run.delivery <= 0 or run.held >= Game.job(run).bundle then return run, false end
        run.delivery = run.delivery - 1; run.held = run.held + 1
        run.message = "Blank inspected; strip loose waste and stack it flat."
    elseif action == "box" then
        if run.held == 0 or (run.held < Game.job(run).bundle
            and (run.fed < Game.job(run).target or run.pending > 0 or run.delivery > 0))
        then return run, false end
        run.boxed = run.boxed + run.held; run.boxes = run.boxes + 1; run.held = 0
        run.message = "Flat blanks boxed and labeled."
        complete(run)
    elseif action == "restock" then
        if run.phase == "running" or run.phase == "jammed"
            or run.stock > 0 or run.fed + run.stock >= Game.job(run).target then return run, false end
        run.stock = Game.job(run).target - run.fed
        run.message = "Fresh sheets loaded on the feed board."
    elseif action == "clear_delivery" then
        if run.phase ~= "jammed" then return run, false end
        run.phase = "paused"; run.proof = false
        run.message = "Stopped delivery cleared. Recheck setup and pull a new proof."
    else
        return run, false
    end
    return run, true
end

function Game.update(run, dt)
    if run.phase ~= "running" then return false end
    dt = clamp(tonumber(dt) or 0, 0, 0.1)
    if dt <= 0 then return false end
    if Game.platenOpen(run) and run.pending == 0 and run.stock > 0
        and run.fed < Game.job(run).target then
        Game.dispatch(run,"feed")
    end
    local cycleLength = 2.5 - (run.speed - 1) * 0.3
    local before = run.cycle
    run.cycle = run.cycle + dt
    if before < 1.2 and run.cycle >= 1.2 and run.pending == 0 then
        run.missedFeeds = run.missedFeeds + 1
    end
    if run.cycle >= cycleLength then
        run.cycle = run.cycle - cycleLength
        if run.pending > 0 then
            run.delivery = run.delivery + run.pending
            run.pending = 0
        end
        if run.delivery >= 8 then
            run.phase = "jammed"; run.proof = false
            run.spoiled = run.spoiled + run.delivery; run.delivery = 0
            run.message = "Delivery backed up. Stop, clear it, and proof again."
        elseif run.fed >= Game.job(run).target then
            run.phase = "paused"
            run.message = "Last sheet delivered. Collect and box all flat blanks."
        elseif run.stock == 0 then
            run.phase = "paused"
            run.message = "Feed board empty. Restock before continuing."
        end
        return true
    end
    return false
end

return Game
