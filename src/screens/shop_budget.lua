-- Read-only weekly budget panel inside Payroll.
local Budget = {}
local ink = {0.91, 0.95, 0.93}
local muted = {0.69, 0.80, 0.81}
local aqua = {0.40, 0.84, 0.81}
local amber = {0.96, 0.77, 0.47}
local green = {0.59, 0.89, 0.67}
local red = {1, 0.59, 0.50}
local valueFont

local function money(value)
    local whole, fraction = string.format("%.2f", math.abs(value)):match("^(%d+)%.(%d+)$")
    whole = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (value < 0 and "−$" or "$") .. whole .. "." .. fraction
end

local function label(value, x, y, width, color, alignment)
    love.graphics.setColor(color)
    love.graphics.printf(value, x, y, width, alignment or "left")
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
    label(name, x, y, width*0.66, muted)
    label(value, x, y, width, color or ink, "right")
end

function Budget.draw(cash, f, plan)
    love.graphics.push("all")
    label("SHOP CASH FLOW", 100, 249, 720, amber)
    card(98, 234, "Available cash today", f.freeCash, f.freeCash < 0 and red or aqua)
    card(339, 242, "Expected income this week", plan.revenue, ink)
    card(588, 250, plan.profit < 0 and "Forecast weekly shortfall" or "Forecast weekly surplus",
        plan.profit, plan.profit < 0 and red or green)

    label("TODAY  /  CASH ON HAND", 100, 339, 330, aqua)
    row(100, 363, 328, "Bank balance", money(cash))
    row(100, 385, 328, "Less unpaid wages", money(f.earnedUnpaid))
    row(100, 407, 328, "Less bills and loans due", money(f.billsDue))
    love.graphics.setColor(0.22, 0.34, 0.36)
    love.graphics.line(100, 430, 428, 430)
    row(100, 438, 328, "Payroll reserve target", money(f.cycleReserve))
    label("Covers one full pay cycle.", 100, 458, 328, muted)

    local costs = {
        {"Staff wages", f.weeklyWages}, {"Shop bills", f.weeklyOperating},
        {"Loan payments", f.weeklyLoans}, {"Machine reserve", plan.machineReserve},
    }
    local total = f.weeklyFixed + plan.machineReserve
    label("THIS WEEK  /  FORECAST COSTS", 455, 339, 377, amber)
    for i, cost in ipairs(costs) do
        local y = 362 + (i-1)*21
        label(cost[1], 455, y, 130, muted)
        love.graphics.setColor(0.13, 0.20, 0.22)
        love.graphics.rectangle("fill", 586, y+5, 108, 7)
        love.graphics.setColor(amber)
        love.graphics.rectangle("fill", 586, y+5, total > 0 and 108*cost[2]/total or 0, 7)
        label(money(cost[2]), 697, y, 139, ink, "right")
    end
    row(455, 453, 381, "Total forecast costs", money(total), amber)

    love.graphics.setColor(0.09, 0.14, 0.16)
    love.graphics.rectangle("fill", 98, 480, 740, 67, 3)
    label("ORDER FORECAST", 109, 485, 336, aqua)
    label(string.format("%d delivered jobs  ·  %d work units left", f.inHouseJobs, f.inHouseWorkUnits),109,506,335,ink)
    label(string.format("%d work units forecast this week", plan.forecastUnits),109,526,335,muted)
    label("CUTTING CAPACITY", 455, 485, 375, amber)
    label(string.format("%d lifts to break even  /  %d lifts available", f.breakEvenLifts, f.capacity),455,506,375,ink)
    label(money(f.pricePerLift).." budgeted charge per lift",455,526,375,muted)
    label("Forecast includes delivered, unpaid orders. Jobs ready for pickup count at full value.",100,605,735,muted)
    love.graphics.pop()
end

return Budget
