local Game = require("src.chandler_price_game")
local Fleet = require("src.machine_fleet")
local Screen = { runs = {}, machineId = nil, image = nil, imageView = nil, helpPage = 0 }

local controls = {
    { "die", "LOCK / RELEASE DIE", "D" },
    { "gauge_down", "GAUGE -", "Q" },
    { "gauge_up", "GAUGE +", "W" },
    { "grippers", "CHECK GRIPPERS", "G" },
    { "packing_down", "PACKING -", "A" },
    { "packing_up", "PACKING +", "S" },
    { "impression", "THROW-OFF / ON", "I" },
    { "proof", "PULL PROOF", "R" },
    { "start_stop", "START / STOP", "F" },
    { "collect", "COLLECT BLANK", "C" },
    { "box", "BOX FLAT BLANKS", "B" },
    { "restock", "RESTOCK", "L" },
    { "clear_delivery", "CLEAR STOPPED JAM", "J" },
    { "view", "NEXT ANGLE", "V" },
    { "new_run", "NEW RUN", "N" },
}

local keyActions = {}
for _, item in ipairs(controls) do keyActions[item[3]:lower()] = item[1] end

local function hit(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.width
        and y >= rect.y and y <= rect.y + rect.height
end

local function button(rect, text, enabled, pointerX, pointerY, accent)
    local hover = enabled and hit(pointerX or -1, pointerY or -1, rect)
    local color = enabled and (hover and {0.23,0.49,0.43} or {0.15,0.34,0.32})
        or {0.16,0.20,0.22}
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setColor(accent or (enabled and {0.55,0.86,0.76} or {0.35,0.43,0.44}))
    love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setColor(enabled and {0.94,0.96,0.93} or {0.55,0.61,0.61})
    love.graphics.printf(text, rect.x + 3, rect.y + rect.height / 2 - 7, rect.width - 6, "center")
end

local function label(text, x, y, width, color)
    love.graphics.setColor(color or {0.84,0.88,0.86})
    love.graphics.printf(text, x, y, width, "left")
end

local function panel(rect)
    love.graphics.setColor(0.075,0.10,0.12)
    love.graphics.rectangle("fill",rect.x,rect.y,rect.width,rect.height,7,7)
    love.graphics.setColor(0.27,0.40,0.42)
    love.graphics.rectangle("line",rect.x,rect.y,rect.width,rect.height,7,7)
end

local function controlRect(index)
    local col = (index - 1) % 4
    local row = math.floor((index - 1) / 4)
    return {x = 24 + col * 231, y = 416 + row * 47, width = 219, height = 42}
end

local previousJob = {x=37,y=113,width=102,height=39}
local nextJob = {x=155,y=113,width=102,height=39}
local helpRect = {x=704,y=17,width=108,height=42}
local exitRect = {x=826,y=17,width=108,height=42}
local helpPrevious = {x=117,y=524,width=168,height=44}
local helpNext = {x=674,y=524,width=168,height=44}
local helpClose = {x=389,y=524,width=182,height=44}

local helpPages = {
    {
        title = "1  |  READ THE JOB TICKET",
        intro = "This is a hand-fed platen die cutter. Each job produces flat cut-and-scored blanks for later folding.",
        steps = {
            {"CHOOSE THE SAMPLE", "Use PREVIOUS / NEXT JOB before feeding any sheets. The folder and box use different die settings."},
            {"MATCH THE TICKET", "Read the blank, dieline, gauge and packing targets in the left panel."},
            {"KNOW THE ROLES", "One operator starts and monitors the press. A second operator can collect, inspect and box the blanks."},
            {"KEEP CLEAR", "Feed only when status says OPEN / FEED. Never reach into the press during the closing stroke."},
        },
    },
    {
        title = "2  |  SET UP AND PROOF",
        intro = "Complete setup while the press is stopped. Changing a setting cancels the approved proof.",
        steps = {
            {"LOCK THE DIE  [D]", "Fit the job's cutting-and-creasing die in the chase, then lock it."},
            {"SET GAUGE  [Q / W]", "Move the sheet position to the exact number shown on the job ticket."},
            {"SET PACKING  [A / S]", "Adjust impression packing to the ticket number; check the grippers [G]."},
            {"PROOF  [I, R]", "Turn impression on [I], then pull a proof [R]. A bad proof uses one sheet; correct setup and proof again."},
        },
    },
    {
        title = "3  |  FEED THE RUN",
        intro = "An approved proof unlocks START / STOP [F]. Watch the platen status throughout the run.",
        steps = {
            {"START  [F]", "Start the press. The platen alternates between open feeding and closing impression."},
            {"AUTOMATIC FEED", "Once started, the game feeds one sheet every time the platen opens. Watch stock and delivery."},
            {"RESTOCK  [L]", "If the feed board empties, the press pauses. Load fresh sheets, then start again."},
            {"STOP SAFELY  [F]", "Stop between sheets when possible. Stopping with a sheet held mid-cycle spoils that sheet."},
        },
    },
    {
        title = "4  |  COLLECT, BOX AND RECOVER",
        intro = "Do not let delivery pile up. Flat blanks need inspection and boxing to finish the run.",
        steps = {
            {"COLLECT  [C]", "Take each blank from delivery, inspect it and clear loose waste."},
            {"BOX  [B]", "Box six collected blanks at a time. Box the final partial bundle after the last sheet."},
            {"CLEAR A JAM  [J]", "Eight uncollected blanks jam delivery and spoil them. Clear the stopped jam, then pull a new proof."},
            {"START OVER  [N]", "NEW RUN resets this sample. NEXT ANGLE [V] rotates the machine view."},
        },
    },
}

local function available(run, action)
    if action == "view" or action == "new_run" then return true end
    if run.phase == "complete" then return false end
    if action == "collect" then return run.delivery > 0 and run.held < Game.job(run).bundle end
    if action == "box" then return run.held > 0 and (run.held >= Game.job(run).bundle
        or run.fed >= Game.job(run).target and run.pending == 0 and run.delivery == 0) end
    if action == "restock" then return run.phase ~= "running" and run.phase ~= "jammed"
        and run.stock == 0 and run.fed < Game.job(run).target end
    if action == "clear_delivery" then return run.phase == "jammed" end
    if action == "start_stop" then return run.phase == "running" or run.proof end
    if action == "proof" then return run.phase ~= "running" and run.phase ~= "jammed"
        and run.pending == 0 and run.stock > 0 end
    return run.phase ~= "running" and run.phase ~= "jammed" and run.pending == 0
end

local function ownedUnit()
    local unit = Screen.state and Screen.machineId
        and Fleet.byId(Screen.state,Screen.machineId)
    return unit and unit.modelId == "chandler_price_platen" and unit or nil
end

function Screen.enter(machineId,state)
    Screen.machineId = machineId or "sample"
    Screen.state = state
    local unit = ownedUnit()
    if unit then
        unit.platenRun = type(unit.platenRun) == "table" and unit.platenRun or Game.new()
        Screen.runs[Screen.machineId] = unit.platenRun
    else
        Screen.runs[Screen.machineId] = Screen.runs[Screen.machineId] or Game.new()
    end
    Screen.image, Screen.imageView = nil, nil
    Screen.helpPage = 0
end

function Screen.helpOpen() return Screen.helpPage > 0 end
function Screen.closeHelp()
    if Screen.helpPage == 0 then return false end
    Screen.helpPage = 0
    return true
end

function Screen.run()
    if not Screen.machineId then Screen.enter() end
    return Screen.runs[Screen.machineId]
end

function Screen.update(dt,state)
    if not Screen.machineId then return false end
    if Screen.helpOpen() then return false end
    local run = Screen.run()
    local pending = run.pending
    local changed = Game.update(run,dt)
    if changed and pending > 0 then
        local unit = ownedUnit()
        if unit and state then Fleet.recordUse(state,"chandler_price_platen",pending,unit.id) end
    end
    return changed
end

function Screen.act(action)
    if Screen.helpOpen() then return false end
    local run = Screen.run()
    if not available(run,action) then return false end
    if action == "start_stop" and run.phase ~= "running" and Screen.state then
        local unit = ownedUnit()
        if unit then
            local ready,reason = Fleet.canOperate(Screen.state,"chandler_price_platen",unit.id)
            if not ready then run.message = reason; return false end
        end
    end
    local changed, accepted = Game.dispatch(run,action)
    Screen.runs[Screen.machineId] = changed
    local unit = ownedUnit()
    if unit then unit.platenRun = changed end
    return accepted
end

function Screen.keypressed(key)
    if key == "h" then
        Screen.helpPage = Screen.helpOpen() and 0 or 1
        return true
    end
    if Screen.helpOpen() then
        if key == "escape" then return Screen.closeHelp() end
        if key == "left" then Screen.helpPage = math.max(1,Screen.helpPage-1) end
        if key == "right" then Screen.helpPage = math.min(#helpPages,Screen.helpPage+1) end
        return true
    end
    local action = keyActions[key]
    return action and Screen.act(action) or false
end

function Screen.mousepressed(x,y,mouseButton)
    if mouseButton ~= 1 then return false end
    if Screen.helpOpen() then
        if hit(x,y,helpClose) then return Screen.closeHelp() end
        if hit(x,y,helpPrevious) then Screen.helpPage = math.max(1,Screen.helpPage-1) end
        if hit(x,y,helpNext) then Screen.helpPage = math.min(#helpPages,Screen.helpPage+1) end
        return true
    end
    if hit(x,y,helpRect) then Screen.helpPage = 1; return true end
    if hit(x,y,exitRect) then return {action="exit"} end
    local run = Screen.run()
    if hit(x,y,previousJob) and run.phase ~= "running" then return Screen.act("job_previous") end
    if hit(x,y,nextJob) and run.phase ~= "running" then return Screen.act("job_next") end
    for index,item in ipairs(controls) do
        if hit(x,y,controlRect(index)) then return Screen.act(item[1]) end
    end
    return false
end

local viewNames = {"FRONT LEFT","FRONT","FRONT RIGHT","RIGHT",
    "BACK RIGHT","BACK","BACK LEFT","LEFT"}
local viewFiles = {
    "01-front-left.png","02-front.png","03-front-right.png","04-right.png",
    "05-back-right.png","06-back.png","07-back-left.png","08-left.png",
}

local function drawMachine(run,assets)
    if Screen.imageView ~= run.view then
        Screen.imageView = run.view
        Screen.image = run.view == 1 and assets.get("chandlerPriceFrontLeft")
            or love.graphics.newImage(
                "assets/generated/chandler-price-angles-v1/" .. viewFiles[run.view])
        Screen.image:setFilter("linear","linear")
    end
    local image = Screen.image
    local width,height = image:getDimensions()
    local scale = math.min(294/width,188/height)
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,466,302,0,scale,scale,width/2,height)
    label("VIEW "..run.view.." / 8  |  "..viewNames[run.view],328,307,295,{0.67,0.80,0.79})
end

local function drawDieline(run)
    local cut = {0.91,0.93,0.91}
    local score = {0.95,0.39,0.35}
    love.graphics.setLineWidth(2)
    if Game.job(run).id == "two_pocket_folder" then
        love.graphics.setColor(cut)
        love.graphics.rectangle("line",355,334,224,48)
        love.graphics.line(355,363,460,363)
        love.graphics.line(474,363,579,363)
        love.graphics.line(460,363,467,381,474,363)
        love.graphics.setColor(score)
        love.graphics.line(467,334,467,361)
        love.graphics.line(355,363,579,363)
    else
        love.graphics.setColor(cut)
        love.graphics.rectangle("line",354,342,224,32)
        love.graphics.rectangle("line",383,329,75,13)
        love.graphics.rectangle("line",383,374,75,13)
        love.graphics.rectangle("line",503,329,44,13)
        love.graphics.rectangle("line",503,374,44,13)
        love.graphics.setColor(score)
        for _,x in ipairs({383,458,473,503,547}) do
            love.graphics.line(x,342,x,374)
        end
        love.graphics.line(383,342,458,342)
        love.graphics.line(383,374,458,374)
    end
    love.graphics.setLineWidth(1)
end

local function drawHelp(pointerX,pointerY)
    love.graphics.setColor(0,0,0,0.82)
    love.graphics.rectangle("fill",0,0,960,640)
    panel({x=80,y=75,width=800,height=510})
    local page = helpPages[Screen.helpPage]
    label("PRESS OPERATOR HELP",111,98,740,{0.98,0.82,0.53})
    label("PAGE "..Screen.helpPage.." / "..#helpPages,760,98,90,{0.63,0.75,0.74})
    label(page.title,111,133,740,{0.96,0.95,0.90})
    label("RUN PAUSED",730,133,120,{0.63,0.75,0.74})
    label(page.intro,111,173,736,{0.72,0.85,0.82})
    for index,step in ipairs(page.steps) do
        local y = 224 + (index-1)*72
        love.graphics.setColor(0.12,0.18,0.19)
        love.graphics.rectangle("fill",109,y-7,742,64,4,4)
        label(step[1],125,y,714,{0.98,0.82,0.53})
        label(step[2],125,y+23,714)
    end
    button(helpPrevious,"PREVIOUS",Screen.helpPage>1,pointerX,pointerY)
    button(helpClose,"BACK TO PRESS",true,pointerX,pointerY)
    button(helpNext,"NEXT PAGE",Screen.helpPage<#helpPages,pointerX,pointerY)
end

function Screen.draw(state,assets,pointerX,pointerY)
    local run = Screen.run()
    local job = Game.job(run)
    love.graphics.setColor(0.035,0.052,0.063)
    love.graphics.rectangle("fill",0,0,960,640)
    love.graphics.setColor(0.20,0.10,0.09)
    love.graphics.rectangle("fill",0,0,960,73)
    label("CHANDLER & PRICE  |  PLATEN DIE CUTTER",24,18,720,{0.98,0.85,0.70})
    label("Hand-fed cut + crease sample jobs  |  keep hands clear during impression",24,46,660)
    button(helpRect,"HELP  [H]",true,pointerX,pointerY)
    button(exitRect,"BACK",true,pointerX,pointerY)

    panel({x=24,y=84,width=277,height=316})
    label("JOB TICKET  "..run.jobIndex.." / "..#Game.jobs,39,91,244,{0.98,0.82,0.53})
    button(previousJob,"PREVIOUS",run.phase~="running" and run.fed==0,pointerX,pointerY)
    button(nextJob,"NEXT JOB",run.phase~="running" and run.fed==0,pointerX,pointerY)
    label(job.name,39,166,247,{0.96,0.95,0.90})
    label(job.blank,39,191,247)
    label(job.detail,39,216,247)
    label("Output: "..job.output,39,265,247)
    label("Target: "..job.target.." blanks  |  "..job.bundle.." per box",39,316,247)
    label("Gauges "..job.gauge.."  |  Packing "..job.packing,39,347,247,
        {0.98,0.82,0.53})

    panel({x=312,y=84,width=319,height=316})
    label("PLATEN / DIE VIEW",328,94,290,{0.98,0.82,0.53})
    drawMachine(run,assets)
    drawDieline(run)

    panel({x=642,y=84,width=294,height=316})
    label("RUN STATUS",657,94,265,{0.98,0.82,0.53})
    label("Phase: "..run.phase:upper(),657,124,265)
    label("Die: "..(run.dieLocked and "LOCKED" or "NOT LOCKED"),657,149,265)
    label("Gauge "..run.gauge.."  |  Packing "..run.packing,657,174,265)
    label("Grippers: "..(run.grippersChecked and "CHECKED" or "UNCHECKED"),657,199,265)
    label("Impression: "..(run.impression and "ON" or "THROWN OFF"),657,224,265)
    label("Proof: "..(run.proof and "APPROVED" or "NEEDED"),657,249,265,
        run.proof and {0.48,0.91,0.65} or {0.96,0.62,0.42})
    label("Platen: "..(Game.platenOpen(run) and "OPEN / FEED" or "CLOSING / CLEAR"),
        657,274,265,Game.platenOpen(run) and {0.48,0.91,0.65} or {0.96,0.62,0.42})
    label("Feed "..run.stock.."  |  Cut "..run.fed.." / "..job.target,
        657,300,265)
    label("Delivery "..run.delivery.."  |  Held "..run.held.."  |  Boxed "..run.boxed,
        657,326,265)
    label("Boxes "..run.boxes.."  |  Spoiled "..run.spoiled,
        657,352,265)

    for index,item in ipairs(controls) do
        button(controlRect(index),item[2].."  ["..item[3].."]",
            available(run,item[1]),pointerX,pointerY)
    end
    label(run.message,24,609,912,{0.98,0.86,0.69})
    if Screen.helpOpen() then drawHelp(pointerX,pointerY) end
end

return Screen
