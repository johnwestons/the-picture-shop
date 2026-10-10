-- Seasonal client demand and the shop's early-business ramp.
local Demand = {}

local MONTHS = {
    { name = "Post-holiday slowdown", demand = 0.72 },
    { name = "Post-holiday slowdown", demand = 0.72 },
    { name = "Spring ramp-up", demand = 0.92 },
    { name = "Spring ramp-up", demand = 0.92 },
    { name = "Graduation and wedding season", demand = 1.12 },
    { name = "Graduation and wedding season", demand = 1.12 },
    { name = "Summer slowdown", demand = 0.82 },
    { name = "Summer slowdown", demand = 0.82 },
    { name = "Fall and holiday preparation", demand = 1.14 },
    { name = "Fall and holiday preparation", demand = 1.14 },
    { name = "Holiday print rush", demand = 1.30 },
    { name = "Year-end slowdown", demand = 0.84 },
}

function Demand.seasonForMonth(month)
    month = math.max(1, math.min(12, math.floor(tonumber(month) or 1)))
    local season = MONTHS[month]
    return { name = season.name, demand = season.demand }
end

function Demand.delayMultiplier(state)
    local month = state and state.calendar and state.calendar.month or 1
    local season = Demand.seasonForMonth(month)
    local reputation = tonumber(state and state.reputation and state.reputation.score) or 0
    reputation = math.max(0, math.min(80, reputation))

    -- A new shop starts with fewer inbound leads. Higher reputation gradually
    -- brings the visitor cadence back up, while the month adjusts it for season.
    local earlyShopDelay = 1.35 - reputation / 80 * 0.35
    return earlyShopDelay / season.demand
end

return Demand
