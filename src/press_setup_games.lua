local Games = {}

local function clamp(value, low, high)
    return math.max(low, math.min(high, tonumber(value) or low))
end

local function feederTarget(job)
    local spec = job and job.stockSpec or {}
    local weight = tonumber(spec.weight) or 80
    local grade = tostring(spec.grade or spec.description or ""):lower()
    if weight <= 60 or grade:find("text", 1, true) then
        return { pile = 3, suction = 1, air = 3, profile = "LIGHT STOCK" }
    end
    if weight >= 100 or grade:find("board", 1, true) or grade:find("cover", 1, true) then
        return { pile = 2, suction = 3, air = 1, profile = "HEAVY STOCK" }
    end
    return { pile = 2, suction = 2, air = 2, profile = "MEDIUM STOCK" }
end

function Games.new(task, job)
    local game = { task = task, faults = 0, actions = 0, complete = false }
    if task == "chase" then
        game.offset, game.angle, game.locks = 2, 2, 0
    elseif task == "packing" then
        game.layers, game.wrinkles, game.clamped = 0, 2, false
    elseif task == "rollers" then
        game.leftStripe, game.rightStripe = 6, 16
    elseif task == "ink" then
        game.keys, game.ductor = { 0, 3, 1 }, false
    elseif task == "feeder" then
        game.prepared, game.suction, game.air, game.cleanFeeds = false, 2, 2, 0
        game.target = feederTarget(job)
        game.feederFeedback = "Fan the stock and load it squarely against the feeder standards."
    elseif task == "register" then
        game.xOffset, game.yOffset, game.tests = 3, -2, 0
    end
    return game
end

local function finish(game)
    game.complete = true
    game.score = clamp(1 - game.faults * 0.08, 0.55, 1)
    return true, game.score
end

local FEEDER_LEVELS = { "LOW", "STANDARD", "HIGH" }

local function feederLevel(value)
    return FEEDER_LEVELS[math.max(1, math.min(3, math.floor(tonumber(value) or 2)))]
end

local function feederDiagnostic(game)
    if game.suction < game.target.suction then
        return false, "NO PICKUP — INCREASE SUCTION"
    elseif game.suction > game.target.suction then
        return false, "HARD PICKUP — REDUCE SUCTION"
    elseif game.air < game.target.air then
        return false, "DOUBLE FEED — INCREASE SEPARATING AIR"
    elseif game.air > game.target.air then
        return false, "SHEET FLUTTER — REDUCE SEPARATING AIR"
    end
    return true, "CLEAN SINGLE-SHEET FEED"
end

local function feederAdjusted(game, field, delta)
    if not game.prepared then
        game.feederFeedback = "FAN + LOAD the stock before adjusting the feeder."
        return
    end
    game[field] = math.max(1, math.min(3, game[field] + delta))
    game.cleanFeeds = 0
    game.feederFeedback = "Adjustment changed. Test one sheet and follow the feed result."
end

function Games.apply(game, action)
    if not game or game.complete then return false end
    game.actions = game.actions + 1
    if game.task == "chase" then
        if action == "align" then game.offset = math.max(0, game.offset - 1)
        elseif action == "square" then game.angle = math.max(0, game.angle - 1)
        elseif action == "tighten" then
            if game.offset == 0 and game.angle == 0 then game.locks = math.min(2, game.locks + 1)
            else game.faults = game.faults + 1 end
        end
        if game.offset == 0 and game.angle == 0 and game.locks == 2 then return finish(game) end
    elseif game.task == "packing" then
        if action == "layer" then game.layers = (game.layers + 1) % 5
        elseif action == "smooth" then game.wrinkles = math.max(0, game.wrinkles - 1)
        elseif action == "clamp" then game.clamped = not game.clamped end
        if game.clamped and game.layers == 3 and game.wrinkles == 0 then return finish(game) end
    elseif game.task == "rollers" then
        if action == "left_down" then game.leftStripe = math.max(2, game.leftStripe - 2)
        elseif action == "left_up" then game.leftStripe = math.min(20, game.leftStripe + 2)
        elseif action == "right_down" then game.rightStripe = math.max(2, game.rightStripe - 2)
        elseif action == "right_up" then game.rightStripe = math.min(20, game.rightStripe + 2) end
        if game.leftStripe >= 10 and game.leftStripe <= 12
            and game.rightStripe >= 10 and game.rightStripe <= 12 then return finish(game) end
    elseif game.task == "ink" then
        local index = tonumber(tostring(action):match("key_(%d)"))
        if index then game.keys[index] = (game.keys[index] + 1) % 5
        elseif action == "ductor" then game.ductor = not game.ductor end
        local minimum = math.min(game.keys[1], game.keys[2], game.keys[3])
        local maximum = math.max(game.keys[1], game.keys[2], game.keys[3])
        local average = (game.keys[1] + game.keys[2] + game.keys[3]) / 3
        if game.ductor and maximum - minimum <= 1 and average >= 2 and average <= 3 then return finish(game) end
    elseif game.task == "feeder" then
        if action == "prepare" then
            game.prepared = true
            game.cleanFeeds = 0
            game.feederFeedback = string.format(
                "%s loaded. Test one sheet, then adjust from the result.",
                game.target.profile)
        elseif action == "suction_down" then feederAdjusted(game, "suction", -1)
        elseif action == "suction_up" then feederAdjusted(game, "suction", 1)
        elseif action == "air_down" then feederAdjusted(game, "air", -1)
        elseif action == "air_up" then feederAdjusted(game, "air", 1)
        elseif action == "test" then
            if not game.prepared then
                game.cleanFeeds, game.faults = 0, game.faults + 1
                game.feederFeedback = "NO FEED — fan and load the stock before testing."
            else
                local clean, result = feederDiagnostic(game)
                if clean then
                    game.cleanFeeds = game.cleanFeeds + 1
                    game.feederFeedback = string.format("%s — %d / 3 confirmed.",
                        result, game.cleanFeeds)
                else
                    game.cleanFeeds, game.faults = 0, game.faults + 1
                    game.feederFeedback = result
                end
            end
        end
        if game.cleanFeeds >= 3 then return finish(game) end
    elseif game.task == "register" then
        if action == "left" then game.xOffset = math.max(-4, game.xOffset - 1)
        elseif action == "right" then game.xOffset = math.min(4, game.xOffset + 1)
        elseif action == "up" then game.yOffset = math.max(-4, game.yOffset - 1)
        elseif action == "down" then game.yOffset = math.min(4, game.yOffset + 1)
        elseif action == "test" then
            if game.xOffset == 0 and game.yOffset == 0 then game.tests = game.tests + 1
            else game.tests, game.faults = 0, game.faults + 1 end
        end
        if game.tests >= 1 then return finish(game) end
    end
    return false
end

function Games.summary(game)
    if game.task == "chase" then
        return string.format("FORM OFFSET %d  •  ROTATION %d  •  QUOINS %d / 2", game.offset, game.angle, game.locks)
    elseif game.task == "packing" then
        return string.format("PACKING %d / 3  •  WRINKLES %d  •  CLAMP %s", game.layers, game.wrinkles,
            game.clamped and "CLOSED" or "OPEN")
    elseif game.task == "rollers" then
        return string.format("LEFT STRIPE %d PT  •  RIGHT STRIPE %d PT  •  TARGET 10–12 PT",
            game.leftStripe, game.rightStripe)
    elseif game.task == "ink" then
        return string.format("FOUNTAIN KEYS %d / %d / %d  •  DUCTOR %s", game.keys[1], game.keys[2],
            game.keys[3], game.ductor and "ENGAGED" or "OFF")
    elseif game.task == "feeder" then
        return Games.feederStatus(game) .. "  •  " .. game.feederFeedback
    end
    return string.format("REGISTER X %+d  •  Y %+d  •  TEST %d / 1", game.xOffset, game.yOffset, game.tests)
end

function Games.feederStatus(game)
    if not game or game.task ~= "feeder" then return "" end
    if not game.prepared then return "STEP 1 / 3  •  STOCK NOT LOADED" end
    return string.format("SUCTION %s  •  AIR %s  •  CLEAN FEEDS %d / 3",
        feederLevel(game.suction), feederLevel(game.air), game.cleanFeeds)
end

function Games.instruction(game)
    if not game or game.task ~= "feeder" then return "" end
    return game.feederFeedback
end

function Games.controls(task)
    if task == "chase" then return { {"align","ALIGN FORM"}, {"square","SQUARE FORM"}, {"tighten","TIGHTEN QUOINS"} }
    elseif task == "packing" then return { {"layer","ADD / REMOVE PACK"}, {"smooth","SMOOTH TYMPAN"}, {"clamp","TOGGLE CLAMP"} }
    elseif task == "rollers" then return { {"left_down","LEFT −"}, {"left_up","LEFT +"}, {"right_down","RIGHT −"}, {"right_up","RIGHT +"} }
    elseif task == "ink" then return { {"key_1","KEY 1"}, {"key_2","KEY 2"}, {"key_3","KEY 3"}, {"ductor","DUCTOR"} }
    elseif task == "feeder" then return {
        {"prepare","FAN + LOAD"}, {"suction_down","SUCTION −"},
        {"suction_up","SUCTION +"}, {"air_down","AIR −"},
        {"air_up","AIR +"}, {"test","TEST 1 SHEET"},
    }
    end
    return { {"left","GUIDE LEFT"}, {"right","GUIDE RIGHT"}, {"up","GUIDE UP"}, {"down","GUIDE DOWN"}, {"test","PULL REGISTER TEST"} }
end

return Games
