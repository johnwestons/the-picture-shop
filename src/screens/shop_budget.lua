-- Read-only weekly budget panel inside Payroll.
local Budget = {}
local ink = {0.91, 0.95, 0.93}
local muted = {0.69, 0.80, 0.81}
local aqua = {0.40, 0.84, 0.81}
local amber = {0.96, 0.77, 0.47}
local green = {0.59, 0.89, 0.67}
local red = {1, 0.59, 0.50}
local Chart = require("src.screens.finance_charts")
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
    valueFont = valueFont or require('src.screens.typography').get(19)
    love.graphics.setFont(valueFont)
    label(money(value), x+12, 295, width-20, color)
    love.graphics.setFont(original)
end

local function row(x, y, width, name, value, color)
    label(name, x, y, width*0.66, muted)
    label(value, x, y, width, color or ink, "right")
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
    local g=love.graphics;local Text=require('src.screens.typography')
    g.push('all');g.setFont(Text.get(16))
    label('SHOP CASH FLOW',100,242,730,amber)
    card(98,234,'Cash available',f.freeCash,f.freeCash<0 and red or aqua)
    card(339,242,'Income this week',plan.revenue,ink)
    card(588,250,plan.profit<0 and 'Weekly shortfall' or 'Weekly surplus',plan.profit,plan.profit<0 and red or green)
    g.setFont(Text.get(16,'bold'))
    label('TODAY / CASH ON HAND',100,341,350,aqua)
    label('THIS WEEK / COSTS',490,341,340,amber)
    g.setFont(Text.get(16))
    local today={{'Bank balance',cash,ink},{'Unpaid wages',f.earnedUnpaid,amber},
        {'Bills + loans',f.billsDue,red},{'Free cash',f.freeCash,green},{'Payroll reserve',f.cycleReserve,aqua}}
    local costs={{'Staff wages',f.weeklyWages,green},{'Shop bills',f.weeklyOperating,aqua},
        {'Loan payments',f.weeklyLoans,amber},{'Machine reserve',plan.machineReserve,ink},
        {'Total weekly',f.weeklyFixed+plan.machineReserve,amber}}
    for i,item in ipairs(today) do row(100,369+(i-1)*25,340,item[1],money(item[2]),item[3]) end
    for i,item in ipairs(costs) do row(490,369+(i-1)*25,340,item[1],money(item[2]),item[3]) end
    g.setColor(.09,.14,.16);g.rectangle('fill',98,506,740,88,3)
    g.setFont(Text.get(14,'bold'));label('ORDER FORECAST',109,513,350,aqua);label('CUTTING CAPACITY',490,513,330,amber)
    g.setFont(Text.get(14))
    label(('%d jobs / %d units left'):format(f.inHouseJobs,f.inHouseWorkUnits),109,538,350,ink)
    label(('%d units forecast this week'):format(plan.forecastUnits),109,565,350,muted)
    label(('%d lifts to break even'):format(f.breakEvenLifts),490,538,330,ink)
    label(('%d available / %s per lift'):format(f.capacity,money(f.pricePerLift)),490,565,330,muted)
    g.setFont(Text.get(12));label('Includes unpaid orders and completed jobs awaiting pickup.',100,608,735,muted)
    g.pop()
end
return Budget
