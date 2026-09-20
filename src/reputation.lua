local Reputation = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Reputation.defaultState()
    return {
        score = 0,
        completedJobs = 0,
        spoiledSheets = 0,
        spoilClaims = 0,
    }
end

function Reputation.ensure(state)
    state.reputation = type(state.reputation) == "table" and state.reputation or Reputation.defaultState()
    local reputation = state.reputation
    reputation.score = clamp(math.floor(tonumber(reputation.score) or 0), -100, 100)
    reputation.completedJobs = math.max(0, math.floor(tonumber(reputation.completedJobs) or 0))
    reputation.spoiledSheets = math.max(0, math.floor(tonumber(reputation.spoiledSheets) or 0))
    reputation.spoilClaims = math.max(0, math.floor(tonumber(reputation.spoilClaims) or 0))
    return reputation
end

function Reputation.valid(value)
    return type(value) == "table"
        and type(value.score) == "number" and value.score >= -100 and value.score <= 100
        and value.score == math.floor(value.score)
        and type(value.completedJobs) == "number" and value.completedJobs >= 0
        and value.completedJobs == math.floor(value.completedJobs)
        and type(value.spoiledSheets) == "number" and value.spoiledSheets >= 0
        and value.spoiledSheets == math.floor(value.spoiledSheets)
        and type(value.spoilClaims) == "number" and value.spoilClaims >= 0
        and value.spoilClaims == math.floor(value.spoilClaims)
end

function Reputation.tier(value)
    local score = type(value) == "table" and tonumber(value.score) or tonumber(value) or 0
    if score < 0 then return "Poor", -1 end
    if score >= 80 then return "Premier", 4 end
    if score >= 50 then return "Established", 3 end
    if score >= 20 then return "Reliable", 2 end
    if score >= 5 then return "New Shop", 1 end
    return "Unrated", 0
end

function Reputation.priceMultiplier(state)
    local reputation = Reputation.ensure(state)
    return 1 + reputation.score * (reputation.score >= 0 and 0.004 or 0.002)
end

function Reputation.completeJob(state, job)
    local reputation = Reputation.ensure(state)
    local price = job and job.quote and tonumber(job.quote.totalPrice) or 0
    local gain = clamp(5 + math.floor(price / 1000), 5, 12)
    if job and job.clientTemperament == "demanding" then gain = gain + 2 end
    reputation.score = clamp(reputation.score + gain, -100, 100)
    reputation.completedJobs = reputation.completedJobs + 1
    return gain, reputation.score
end

function Reputation.spoilLift(state, sheets, cost, demanding)
    local reputation = Reputation.ensure(state)
    sheets = math.max(1, math.floor(tonumber(sheets) or 1))
    local loss = 4 + math.ceil(sheets / 250)
    if demanding then loss = loss + 2 end
    reputation.score = clamp(reputation.score - loss, -100, 100)
    reputation.spoiledSheets = reputation.spoiledSheets + sheets
    reputation.spoilClaims = reputation.spoilClaims + math.max(0, math.floor(tonumber(cost) or 0))
    return loss, reputation.score
end

return Reputation
