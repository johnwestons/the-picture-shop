local Reputation = {}

local MAX_REVIEWS = 20
local REVIEW_TEXT = {
    [1] = {
        "The print was off-spec and unusable. We need this corrected.",
        "Major quality problems made this order a loss for us.",
        "We had to reject the material because it missed the approved specs.",
        "This run had serious defects and delayed our own work.",
        "The order was badly spoiled. We cannot use what was delivered.",
    },
    [2] = {
        "Too much of the order needed rework before we could use it.",
        "We had to spend extra time sorting out quality problems.",
        "The replacement sheets helped, but this job still caused a headache.",
        "The run was rough and arrived with more defects than we can accept.",
        "We expected better. Several parts of the order needed fixing.",
    },
    [3] = {
        "The order met our needs. Nothing special, but no major issues.",
        "A decent job overall. There are a few things that could be sharper.",
        "It turned out fine, though the finishing could use more care.",
        "Good enough for this order. We'll see how the next one goes.",
        "The job got done as expected, with some room to improve.",
    },
    [4] = {
        "Nice work overall. We'd be happy to order from the shop again.",
        "Everything arrived in good shape. Thanks for taking care with it.",
        "A solid run and an easy pickup. We appreciate the good work.",
        "The order came out well, and the shop was helpful throughout.",
        "Good quality on this job. We'll keep the shop in mind for next time.",
    },
    [5] = {
        "Excellent quality from start to finish. We'll definitely be back!",
        "Perfect run! The finished order looks great.",
        "Fantastic work and a smooth pickup. Highly recommended.",
        "The print looks terrific. This is exactly why we order here.",
        "Fast, careful, and beautifully done. We couldn't be happier.",
        "Another excellent order from the shop. Five paws from us!",
    },
}

local LEGACY_REVIEW_TEXT = {
    [1] = "The order had serious quality problems. We will not order again yet.",
    [2] = "Several issues needed follow-up. We expected a smoother job.",
    [3] = "The order met our needs, though there was room to improve.",
    [4] = "Good quality work and helpful service. We would order again.",
    [5] = "Excellent quality and a smooth pickup. Highly recommended!",
}

local QUALITY_LABELS = {
    [1] = "Poor",
    [2] = "Weak",
    [3] = "Fair",
    [4] = "Good",
    [5] = "Excellent",
}


local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function stableHash(key)
    key = tostring(key or "job")
    local hash = 0
    for index = 1, #key do hash = (hash * 31 + key:byte(index)) % 2147483647 end
    return hash
end

local function reviewTextFor(jobId, rating)
    local variants = REVIEW_TEXT[rating]
    return variants[(math.floor(stableHash(jobId) / 100) % #variants) + 1]
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
            local text = review.text
            if text == LEGACY_REVIEW_TEXT[review.rating] then
                text = reviewTextFor(review.jobId, review.rating)
            end
            reviews[#reviews + 1] = {
                jobId = review.jobId, customer = review.customer, rating = review.rating,
                text = text, gameHours = review.gameHours,
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

local function stableJobHash(job)
    return stableHash(job.id or job.company or "job")
end

local function qualityRating(job)
    local totalSheets = math.max(1, tonumber(job.quote and job.quote.totalSheets) or 1)
    local spoiledSheets = math.max(0, tonumber(job.replacementSheets) or 0,
        tonumber(job.spoiledSheets) or 0)
    local offSpec = false
    local edgeQuality = 1
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.paper then
            if pallet.paper.offSpec then offSpec = true end
            edgeQuality = math.min(edgeQuality, tonumber(pallet.paper.cutQuality) or 1)
        end
    end
    local spoilRate = spoiledSheets / totalSheets
    local rating
    if offSpec or spoiledSheets > 0 then
        -- A spoiled or off-spec order always draws a negative review.
        rating = (offSpec or spoilRate >= 0.20) and 1 or 2
    elseif edgeQuality < 0.73 then
        rating = 1
    elseif edgeQuality < 0.80 then
        rating = 2
    else
        rating = 3 + stableJobHash(job) % 3
    end
    return rating, {
        edgeQuality = edgeQuality,
        offSpec = offSpec,
        spoiledSheets = spoiledSheets,
        spoilRate = spoilRate,
    }
end

function Reputation.qualityPreview(job)
    if type(job) ~= "table" then return nil end
    local rating, details = qualityRating(job)
    local factor
    if details.offSpec and details.spoiledSheets > 0 then
        factor = string.format("Off-spec • %d%% spoilage", math.floor(details.spoilRate * 100 + 0.5))
    elseif details.offSpec then
        factor = "Off-spec cut"
    elseif details.spoiledSheets > 0 then
        factor = string.format("%d%% spoilage", math.floor(details.spoilRate * 100 + 0.5))
    elseif details.edgeQuality < 0.999 then
        factor = string.format("Cut edge %d%%", math.floor(details.edgeQuality * 100 + 0.5))
    else
        factor = "Clean cuts • no spoilage"
    end
    return {
        rating = rating,
        label = QUALITY_LABELS[rating],
        factor = factor,
        edgeQuality = details.edgeQuality,
        offSpec = details.offSpec,
        spoiledSheets = details.spoiledSheets,
        spoilRate = details.spoilRate,
    }
end

local function customerReview(job)
    local rating = qualityRating(job)
    local text = reviewTextFor(job.id or job.company or "job", rating)
    return rating, text
end

function Reputation.recordReview(state, job, gameHours)
    local reputation = Reputation.ensure(state)
    local jobId = tostring(job.id or "JOB")
    for _, existing in ipairs(reputation.reviews) do
        if existing.jobId == jobId then return existing, Reputation.averageRating(reputation) end
    end
    local rating, text = customerReview(job)
    if not rating then return nil, Reputation.averageRating(reputation) end
    local review = {
        jobId = jobId,
        customer = tostring(job.company or "Customer"),
        rating = rating,
        text = text,
        gameHours = math.max(0, tonumber(gameHours) or 0),
    }
    reputation.ratingCount = reputation.ratingCount + 1
    reputation.ratingTotal = reputation.ratingTotal + rating
    reputation.reviews[#reputation.reviews + 1] = review
    while #reputation.reviews > MAX_REVIEWS do table.remove(reputation.reviews, 1) end
    return review, Reputation.averageRating(reputation)
end

function Reputation.backfillCompleted(state)
    local reputation=Reputation.ensure(state)
    if reputation.ratingCount>0 or #reputation.reviews>0 then return false end
    local completed=state.jobs and state.jobs.completed or {}
    local changed=false
    for index=math.max(1,#completed-MAX_REVIEWS+1),#completed do
        local job=completed[index]
        if type(job)=="table" then
            local review=Reputation.recordReview(state,job,job.completedAtHours or 0)
            changed=review~=nil or changed
        end
    end
    return changed
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
    return 1 + reputation.score * (reputation.score >= 0 and 0.005 or 0.002)
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
