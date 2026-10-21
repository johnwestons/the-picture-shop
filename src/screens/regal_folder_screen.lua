local Game = require("src.regal_folder_game")
local Screen = { run = nil }

local controls = {
    { "fold_down", "FOLD -5", 30, 432, 130, 42, "Q" },
    { "fold_up", "FOLD +5", 170, 432, 130, 42, "W" },
    { "guide_down", "GUIDE -5", 30, 480, 130, 42, "A" },
    { "guide_up", "GUIDE +5", 170, 480, 130, 42, "S" },
    { "air", "AIR SETTING", 30, 528, 270, 42, "E" },
    { "speed_down", "SPEED -", 324, 432, 126, 42, "1" },
    { "speed_up", "SPEED +", 460, 432, 126, 42, "2" },
    { "proof", "RUN TEST SHEET", 324, 480, 262, 42, "R" },
    { "start_stop", "START / STOP", 324, 528, 262, 42, "F" },
    { "refill", "LOAD FEEDER", 324, 576, 262, 42, "G" },
    { "catch", "CATCH PIECE", 614, 432, 316, 42, "SPACE" },
    { "box", "BOX & LABEL", 614, 480, 316, 42, "B" },
    { "clear_jam", "CLEAR STOPPED JAM", 614, 528, 316, 42, "C" },
    { "reset", "NEW PRACTICE BATCH", 614, 576, 316, 42, "N" },
    { "rotate_view", "NEXT VIEW", 324, 364, 262, 36, "V" },
}

local keys = {
    q = "fold_down", w = "fold_up", a = "guide_down", s = "guide_up",
    e = "air", r = "proof", f = "start_stop", g = "refill",
    ["1"] = "speed_down", ["2"] = "speed_up", space = "catch",
    b = "box", c = "clear_jam", n = "reset", v = "rotate_view",
}

local function inside(x, y, bx, by, width, height)
    return x >= bx and x <= bx + width and y >= by and y <= by + height
end

local function panel(x, y, width, height)
    love.graphics.setColor(0.09, 0.12, 0.15, 0.94)
    love.graphics.rectangle("fill", x, y, width, height, 9, 9)
    love.graphics.setColor(0.39, 0.47, 0.51)
    love.graphics.rectangle("line", x, y, width, height, 9, 9)
end

local function label(text, x, y, width, color)
    love.graphics.setColor(color or { 0.94, 0.95, 0.93 })
    love.graphics.printf(text, x, y, width, "left")
end

local function button(item, active, pointerX, pointerY)
    local action, caption, x, y, width, height, key = unpack(item)
    local hover = inside(pointerX or -1, pointerY or -1, x, y, width, height)
    if active then
        love.graphics.setColor(hover and 0.37 or 0.26, hover and 0.49 or 0.36,
            hover and 0.43 or 0.32)
    else
        love.graphics.setColor(0.19, 0.23, 0.25)
    end
    love.graphics.rectangle("fill", x, y, width, height, 5, 5)
    love.graphics.setColor(0.85, 0.88, 0.85)
    love.graphics.printf(caption, x + 7, y + 8, width - 14, "center")
    love.graphics.setColor(0.71, 0.79, 0.78)
    love.graphics.printf(key, x + 7, y + 27, width - 14, "center")
end

local function available(run, action)
    if action == "reset" then return true end
    if action == "rotate_view" then return true end
    if run.phase == "complete" then return false end
    if action == "catch" then return run.delivery > 0 and run.held < 6 end
    if action == "box" then return run.held > 0 and (run.held == 6
        or (run.fed == run.target and #run.inTransit == 0 and run.delivery == 0)) end
    if action == "clear_jam" then return run.phase == "jammed" end
    if action == "refill" then return run.stock < 8 and run.fed + run.stock < run.target end
    if action == "start_stop" then return run.phase == "running" or run.proof end
    if action == "fold_down" or action == "fold_up" or action == "guide_down"
        or action == "guide_up" or action == "air" or action == "proof"
    then return run.phase ~= "running" and run.phase ~= "jammed" end
    return true
end

function Screen.enter()
    Screen.run = Game.new()
end

function Screen.update(dt)
    if Screen.run then Game.update(Screen.run, dt) end
end

function Screen.act(action)
    if not Screen.run then Screen.enter() end
    if not available(Screen.run, action) then return false end
    local updated, accepted = Game.dispatch(Screen.run, action)
    Screen.run = updated
    return accepted
end

function Screen.keypressed(key)
    local action = keys[key]
    return action and Screen.act(action) or false
end

function Screen.mousepressed(x, y, mouseButton)
    if mouseButton ~= 1 then return false end
    if inside(x, y, 824, 22, 106, 42) then return { action = "exit" } end
    for _, item in ipairs(controls) do
        if inside(x, y, item[3], item[4], item[5], item[6]) then
            return Screen.act(item[1])
        end
    end
    return false
end

function Screen.draw(state, assets, pointerX, pointerY)
    local run = Screen.run
    if not run then Screen.enter(); run = Screen.run end
    love.graphics.setColor(0.055, 0.075, 0.09)
    love.graphics.rectangle("fill", 0, 0, 960, 640)
    love.graphics.setColor(0.38, 0.11, 0.16)
    love.graphics.rectangle("fill", 0, 0, 960, 76)
    label("REGAL MOLL  |  FOLDER RUN", 30, 20, 570)
    label("Two stations: machine operator + catcher", 30, 47, 650,
        { 0.92, 0.82, 0.77 })
    button({ "exit", "EXIT", 824, 22, 106, 42, "ESC" }, true, pointerX, pointerY)

    panel(30, 92, 272, 312)
    label("WORK ORDER", 48, 108, 238, { 0.98, 0.84, 0.67 })
    label("24 cover-stock sheets  |  6 per box", 48, 138, 238)
    label("Fold stop: " .. run.targetFold .. "  |  Guides: " .. run.targetGuide,
        48, 168, 238)
    label("Air target: 2  |  Test before running", 48, 196, 238)
    label("OPERATOR SETUP", 48, 230, 238, { 0.98, 0.84, 0.67 })
    label("Fold " .. run.fold .. "   Guides " .. run.guide .. "   Air " .. run.air,
        48, 258, 238)
    label("Speed " .. run.speed .. " / 3   Feed pile " .. run.stock .. " / 8",
        48, 286, 238)
    label("Proof: " .. (run.proof and "APPROVED" or "NEEDED"), 48, 314, 238,
        run.proof and { 0.42, 0.89, 0.59 } or { 0.95, 0.65, 0.43 })
    label("Phase: " .. string.upper(run.phase), 48, 344, 238)

    panel(314, 92, 326, 312)
    local image = assets and assets.get and assets.get("regalFolderDirections")
    if image then
        local width, height = image:getDimensions()
        local edges = { 0, 444, 887, 1331, 1774 }
        local frame = run.view or 1
        local column, row = (frame - 1) % 4 + 1, math.floor((frame - 1) / 4)
        local cellWidth = edges[column + 1] - edges[column]
        local cellHeight = row == 0 and 444 or 443
        local quad = love.graphics.newQuad(edges[column], row == 0 and 0 or 444,
            cellWidth, cellHeight, width, height)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, quad, 477, 326, 0, 0.50, 0.50,
            cellWidth / 2, cellHeight)
    end
    label("Feed  >  fold gate  >  delivery", 338, 336, 278, { 0.8, 0.87, 0.85 })

    panel(652, 92, 278, 312)
    label("CATCHER / BOXING", 670, 108, 242, { 0.98, 0.84, 0.67 })
    label("At delivery: " .. run.delivery, 670, 145, 242)
    label("In hand: " .. run.held .. " / 6", 670, 173, 242)
    label("Boxed: " .. run.boxed .. " / " .. run.target, 670, 201, 242)
    label("Boxes: " .. run.boxes .. "   Spoiled: " .. run.spoiled,
        670, 229, 242)
    label("Jams: " .. run.jams, 670, 257, 242)
    label("Catch each piece; box when six", 670, 306, 242)
    label("are stacked. Backups cause jams.", 670, 330, 242)

    panel(30, 412, 900, 213)
    for _, item in ipairs(controls) do
        button(item, available(run, item[1]), pointerX, pointerY)
    end
    love.graphics.setColor(0.96, 0.89, 0.75)
    love.graphics.printf(run.message, 30, 628, 900, "center")
end

return Screen
