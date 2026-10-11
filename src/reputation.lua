local Reputation = {}

local MAX_REVIEWS = 20
local REVIEW_TEXT = {
    [1] = "The order had serious quality problems. We will not order again yet.",
    [2] = "Several issues needed follow-up. We expected a smoother job.",
    [3] = "The order met our needs, though there was room to improve.",
    [4] = "Good quality work and helpful service. We would order again.",
    [5] = "Excellent quality and a smooth pickup. Highly recommended!",
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function validReview(value)
    return type(value) == "table"
        and type(value.jobId) == "string" and #value.jobId > 0 and #value.jobId <= 256
        and type(value.customer) == "string" and #value.customer > 0 and #value.customer <= 256
        and integer(value.rating, 1, 5)
        and type(value.text) == "string" and #value.text > 0 and #value.text <= 300
        and type(value.gameHours) == "number" and value.gameHours >= 0 and value.gameHours < 1e12
end

local function validReviews(reviews)
    if reviews == nil then return true end
    if type(reviews) ~= "table" then return false end
    local count, highest = 0, 0
    for key, review in pairs(reviews) do
        if not integer(key, 1, MAX_REVIEWS) or not validReview(review) then return false end
        count, highest = count + 1, math.max(highest, key)
    end
    return count == highest
end

function Reputation.defaultState()
    return {
        score = 0,
        completedJobs = 0,
        spoiledSheets = 0,
        spoilClaims = 0,
        ratingCount = 0,
        ratingTotal = 0,
        reviews = {},
    }
end

function Reputation.ensure(state)
    state.reputation = type(state.reputation) == "table" and state.reputation or Reputation.defaultState()
    local reputation = state.reputation
    reputation.score = clamp(math.floor(tonumber(reputation.score) or 0), -100, 100)
    reputation.completedJobs = math.max(0, math.floor(tonumber(reputation.completedJobs) or 0))
    reputation.spoiledSheets = math.max(0, math.floor(tonumber(reputation.spoiledSheets) or 0))
    reputation.spoilClaims = math.max(0, math.floor(tonumber(reputation.spoilClaims) or 0))
    local reviews = {}
    for _, review in ipairs(type(reputation.reviews) == "table" and reputation.reviews or {}) do
        if validReview(review) then
            reviews[#reviews + 1] = {
                jobId = review.jobId, customer = review.customer, rating = review.rating,
                text = review.text, gameHours = review.gameHours,
            }
        end
    end
    while #reviews > MAX_REVIEWS do table.remove(reviews, 1) end
    reputation.reviews = reviews
    local recentTotal = 0
    for _, review in ipairs(reviews) do recentTotal = recentTotal + review.rating end
    reputation.ratingCount = math.max(#reviews,
        math.max(0, math.floor(tonumber(reputation.ratingCount) or #reviews)))
    reputation.ratingTotal = math.max(recentTotal,
        math.max(0, math.floor(tonumber(reputation.ratingTotal) or recentTotal)))
    reputation.ratingTotal = math.min(reputation.ratingTotal, reputation.ratingCount * 5)
    return reputation
end

function Reputation.valid(value)
    local hasRatingCount, hasRatingTotal = value and value.ratingCount ~= nil, value and value.ratingTotal ~= nil
    return type(value) == "table"
        and type(value.score) == "number" and value.score >= -100 and value.score <= 100
        and value.score == math.floor(value.score)
        and type(value.completedJobs) == "number" and value.completedJobs >= 0
        and value.completedJobs == math.floor(value.completedJobs)
        and type(value.spoiledSheets) == "number" and value.spoiledSheets >= 0
        and value.spoiledSheets == math.floor(value.spoiledSheets)
        and type(value.spoilClaims) == "number" and value.spoilClaims >= 0
        and value.spoilClaims == math.floor(value.spoilClaims)
        and (hasRatingCount == hasRatingTotal)
        and (not hasRatingCount or integer(value.ratingCount, 0, 1e12)
            and integer(value.ratingTotal, 0, value.ratingCount * 5)
            and (value.ratingCount > 0 or value.ratingTotal == 0))
        and validReviews(value.reviews)
end

function Reputation.averageRating(value)
    local reputation = type(value) == "table" and value.reputation or value
    local count = type(reputation) == "table" and tonumber(reputation.ratingCount) or 0
    local total = type(reputation) == "table" and tonumber(reputation.ratingTotal) or 0
    if not count or count <= 0 then return nil end
    return total / count
end

function Reputation.demandMultiplier(state)
    local average = Reputation.averageRating(state)
    if not average then return 1 end
    return clamp(1 + (average - 3) * 0.08, 0.84, 1.16)
end

local function customerRating(job)
    local totalSheets = math.max(1, tonumber(job.quote and job.quote.totalSheets) or 1)
    local spoiledSheets = math.max(0, tonumber(job.replacementSheets) or 0)
    local offSpec = false
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.paper and pallet.paper.offSpec then offSpec = true; break end
    end
    local spoilRate = spoiledSheets / totalSheets
    if offSpec or spoilRate >= 0.20 then return 1 end
    if spoilRate >= 0.10 then return 2 end
    if spoilRate >= 0.02 then return 3 end
    if spoilRate > 0 then return 4 end
    local key = tostring(job.id or job.company or "job")
    local hash = 0
    for index = 1, #key do hash = (hash * 31 + key:byte(index)) % 2147483647 end
    return hash % 3 == 0 and 4 or 5
end

function Reputation.recordReview(state, job, gameHours)
    local reputation = Reputation.ensure(state)
    local rating = customerRating(job)
    local review = {
        jobId = tostring(job.id or "JOB"),
        customer = tostring(job.company or "Customer"),
        rating = rating,
        text = REVIEW_TEXT[rating],
        gameHours = math.max(0, tonumber(gameHours) or 0),
    }
    reputation.ratingCount = reputation.ratingCount + 1
    reputation.ratingTotal = reputation.ratingTotal + rating
    reputation.reviews[#reputation.reviews + 1] = review
    while #reputation.reviews > MAX_REVIEWS do table.remove(reputation.reviews, 1) end
    return review, Reputation.averageRating(reputation)
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
    local gain = clamp(2 + math.floor(price / 2500), 2, 5)
    if job and job.clientTemperament == "demanding" then gain = math.min(6, gain + 1) end
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
