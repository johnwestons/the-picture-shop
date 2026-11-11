-- Read-only weekly budget panel inside Payroll.
local Budget = {}
local ink = {0.91, 0.95, 0.93}
local muted = {0.69, 0.80, 0.81}
local aqua = {0.40, 0.84, 0.81}
local amber = {0.96, 0.77, 0.47}
local green = {0.59, 0.89, 0.67}
local red = {1, 0.59, 0.50}
local Chart = require("src.screens.finance_charts")
local Fonts = require("src.screens.computer.fonts")
local valueFont

local function money(value)
    local whole, fraction = string.format("%.2f", math.abs(value)):match("^(%d+)%.(%d+)$")
    whole = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (value < 0 and "−$" or "$") .. whole .. "." .. fraction
end

local function label(value, x, y, width, color, alignment, typewriter)
    local original = love.graphics.getFont()
    if typewriter then love.graphics.setFont(Fonts.get("typewriter", 14)) end
    love.graphics.setColor(color)
    love.graphics.printf(value, x, y, width, alignment or "left")
    if typewriter then love.graphics.setFont(original) end
end

local function card(x, width, name, value, color)
    love.graphics.setColor(0.08, 0.14, 0.16)
    love.graphics.rectangle("fill", x, 271, width, 56, 3)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, 271, 3, 56)
    label(name, x+12, 277, width-20, muted)
    local original = love.graphics.getFont()
    valueFont = valueFont or love.graphics.newFont(19)
    love.graphics.setFont(valueFont)
    label(money(value), x+12, 295, width-20, color)
    love.graphics.setFont(original)
end

local function row(x, y, width, name, value, color)
    label(name, x, y, width*0.66, muted, nil, true)
    label(value, x, y, width, color or ink, "right", true)
end
local function compact(value)
    local amount=math.abs(value or 0)
    local sign=(value or 0)<0 and "−" or ""
    if amount>=1000000 then return string.format("%s$%.1fm",sign,amount/1000000) end
    if amount>=10000 then return string.format("%s$%.0fk",sign,amount/1000) end
    if amount>=1000 then return string.format("%s$%.1fk",sign,amount/1000) end
    return money(value or 0)
end

function Budget.draw(cash, f, plan)
    love.graphics.push("all")
    -- Fit the existing finance layout inside the CRT browser window without
    -- scaling its type down or changing any of its money/chart colors.
    love.graphics.translate(14, 0)
    love.graphics.scale(0.98, 1)
    label("SHOP CASH FLOW", 100, 249, 720, amber)
    card(98, 234, "Available cash today", f.freeCash, f.freeCash < 0 and red or aqua)
    card(339, 242, "Expected income this week", plan.revenue, ink)
    card(588, 250, plan.profit < 0 and "Forecast weekly shortfall" or "Forecast weekly surplus",
        plan.profit, plan.profit < 0 and red or green)

    label("TODAY  /  CASH ON HAND", 100, 339, 220, aqua)
    row(100, 363, 212, "Bank balance", money(cash))
    row(100, 385, 212, "Less unpaid wages", money(f.earnedUnpaid), amber)
    row(100, 407, 212, "Bills + loans", money(f.billsDue), red)
    love.graphics.setColor(0.22, 0.34, 0.36)
    love.graphics.line(100, 430, 310, 430)
    row(100, 438, 212, "Free cash", money(f.freeCash), green)
    row(100, 459, 212, "Payroll reserve", money(f.cycleReserve), aqua)
    Chart.donut(365, 410, 43, {
        {label="Free cash",value=math.max(0,f.freeCash),color=green},
        {label="Unpaid wages",value=f.earnedUnpaid,color=amber},
        {label="Bills + loans",value=f.billsDue,color=red},
    }, "ON HAND", compact(cash))

    local costs = {
        {"Staff wages", f.weeklyWages,green}, {"Shop bills", f.weeklyOperating,aqua},
        {"Loan payments", f.weeklyLoans,amber}, {"Machine reserve", plan.machineReserve,{.77,.63,.94,1}},
    }
    local total = f.weeklyFixed + plan.machineReserve
    label("THIS WEEK  /  FORECAST COSTS", 455, 339, 377, amber)
    for i, cost in ipairs(costs) do
        local y = 362 + (i-1)*21
        label(cost[1], 455, y, 102, muted)
        Chart.bar(559,y+5,66,7,cost[2],total,cost[3])
        label(money(cost[2]), 630, y, 82, ink, "right")
    end
    row(455, 453, 257, "Total weekly costs", money(total), amber)
    Chart.donut(772, 407, 47, costs, "WEEKLY", compact(total))

    love.graphics.setColor(0.09, 0.14, 0.16)
    love.graphics.rectangle("fill", 98, 480, 740, 67, 3)
    label("ORDER FORECAST", 109, 485, 336, aqua)
    label(string.format("%d delivered jobs  ·  %d work units left", f.inHouseJobs, f.inHouseWorkUnits),109,506,335,ink,nil,true)
    label(string.format("%d work units forecast this week", plan.forecastUnits),109,526,335,muted,nil,true)
    label("CUTTING CAPACITY", 455, 485, 375, amber)
    label(string.format("%d lifts to break even  /  %d lifts available", f.breakEvenLifts, f.capacity),455,506,375,ink,nil,true)
    label(money(f.pricePerLift).." budgeted charge per lift",455,526,375,muted,nil,true)
    label("Forecast includes delivered, unpaid orders. Jobs ready for pickup count at full value.",100,561,735,muted,nil,true)
    love.graphics.pop()
end

return Budget
