local Games = {}

local function clamp(value, low, high)
    return math.max(low, math.min(high, tonumber(value) or low))
end

local function feederTarget(job)
    local spec = job and job.stockSpec or {}
    local weight = tonumber(spec.weight) or 80
    local grade = tostring(spec.grade or spec.description or ""):lower()
    if weight <= 60 or grade:find("text", 1, true) then
        return { pile = 3, suction = 1, blast = 3, hint = "LIGHT STOCK: HIGHER PILE + AIR, LOWER SUCTION" }
    end
    if weight >= 100 or grade:find("board", 1, true) or grade:find("cover", 1, true) then
        return { pile = 2, suction = 3, blast = 1, hint = "HEAVY STOCK: LOWER PILE + AIR, FIRMER SUCTION" }
    end
    return { pile = 2, suction = 2, blast = 2, hint = "MEDIUM STOCK: BALANCE PILE, SUCTION, AND AIR" }
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
        game.pile, game.suction, game.blast, game.tests = 0, 0, 0, 0
        game.target = feederTarget(job)
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
        if action == "pile" then game.pile = (game.pile + 1) % 5
        elseif action == "suction" then game.suction = (game.suction + 1) % 5
        elseif action == "blast" then game.blast = (game.blast + 1) % 5
        elseif action == "test" then
            local target = game.target
            if game.pile == target.pile and game.suction == target.suction and game.blast == target.blast then
                game.tests = game.tests + 1
            else
                game.tests, game.faults = 0, game.faults + 1
            end
        end
        if game.tests >= 3 then return finish(game) end
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
        return string.format("PILE %d  •  SUCTION %d  •  AIR %d  •  SINGLE SHEETS %d / 3",
            game.pile, game.suction, game.blast, game.tests)
    end
    return string.format("REGISTER X %+d  •  Y %+d  •  TEST %d / 1", game.xOffset, game.yOffset, game.tests)
end

function Games.controls(task)
    if task == "chase" then return { {"align","ALIGN FORM"}, {"square","SQUARE FORM"}, {"tighten","TIGHTEN QUOINS"} }
    elseif task == "packing" then return { {"layer","ADD / REMOVE PACK"}, {"smooth","SMOOTH TYMPAN"}, {"clamp","TOGGLE CLAMP"} }
    elseif task == "rollers" then return { {"left_down","LEFT −"}, {"left_up","LEFT +"}, {"right_down","RIGHT −"}, {"right_up","RIGHT +"} }
    elseif task == "ink" then return { {"key_1","KEY 1"}, {"key_2","KEY 2"}, {"key_3","KEY 3"}, {"ductor","DUCTOR"} }
    elseif task == "feeder" then return { {"pile","PILE HEIGHT"}, {"suction","SUCTION"}, {"blast","AIR BLAST"}, {"test","TEST 3 SHEETS"} }
    end
    return { {"left","GUIDE LEFT"}, {"right","GUIDE RIGHT"}, {"up","GUIDE UP"}, {"down","GUIDE DOWN"}, {"test","PULL REGISTER TEST"} }
end

return Games
