-- Shared offer progression rules. Reputation sets the opportunity ceiling;
-- production staff skills and weekly capacity determine what the shop can
-- comfortably take on as its workforce develops.
local Reputation = require("src.reputation")
local StaffFinances = require("src.staff_finances")
local Jobs = require("src.jobs")

local Progression = {}
local DIFFICULTY = { easy = 1, medium = 2, hard = 3 }
local DIFFICULTY_NAME = { [1] = "easy", [2] = "medium", [3] = "hard" }
local REPUTATION_LIFT_BUDGET = { [0] = 1, [1] = 4, [2] = 8, [3] = 14, [4] = 20 }

local function productionTeam(state)
    local team = {}
    for _, worker in ipairs(state and state.employment and state.employment.staff or {}) do
        local role = worker.contract and worker.contract.role
        if worker.status == "employed" and not worker.terminationRequested and role ~= "driver" then
            team[#team + 1] = worker
        end
    end
    return team
end

function Progression.hasProductionTeam(state)
    return #productionTeam(state) > 0
end

function Progression.difficultyRank(difficulty)
    return DIFFICULTY[difficulty] or 1
end

function Progression.capDifficulty(state, difficulty, kind)
    local wanted = Progression.difficultyRank(difficulty)
    local team = productionTeam(state)
    -- With no production employees, the player can still take the job and the
    -- reputation progression remains available. Once staff are hired, their
    -- relevant skill becomes the ceiling for the work offered to the shop.
    if #team == 0 then return DIFFICULTY_NAME[wanted] end

    local field = kind == "press" and "pressSkill" or "cutterSkill"
    local best = 0
    for _, worker in ipairs(team) do best = math.max(best, tonumber(worker[field]) or 0) end
    local skillCeiling
    if kind == "press" then
        skillCeiling = best >= 80 and 3 or best >= 60 and 2 or 1
    else
        skillCeiling = best >= 80 and 3 or best >= 50 and 2 or 1
    end
    return DIFFICULTY_NAME[math.min(wanted, skillCeiling)]
end

function Progression.liftBudget(state)
    local _, tier = Reputation.tier(Reputation.ensure(state))
    tier = math.max(0, tier)
    local reputationBudget = REPUTATION_LIFT_BUDGET[tier] or REPUTATION_LIFT_BUDGET[4]
    local team = productionTeam(state)
    local outputBudget
    if #team == 0 then
        -- The player can cover production without hired staff, so reputation
        -- still unlocks larger opportunities on its own.
        outputBudget = Jobs.MAX_PALLETS * (Jobs.MAX_SHEETS / Jobs.LIFT_CAPACITY)
    else
        -- Keep room for the player to help while letting an experienced crew
        -- raise the total scope as their modeled weekly output improves.
        outputBudget = math.max(4, StaffFinances.summary(state).capacity)
    end
    return math.min(Jobs.MAX_PALLETS * (Jobs.MAX_SHEETS / Jobs.LIFT_CAPACITY),
        reputationBudget, outputBudget)
end

function Progression.scaleSheetCounts(counts, requestedCopies, machineCount, liftBudget, maxPallets,
        allowReduction)
    if type(counts) ~= "table" or #counts == 0 then return counts, requestedCopies end
    maxPallets = math.max(1, math.floor(tonumber(maxPallets) or Jobs.MAX_PALLETS))
    local repeatCount = math.max(1, math.floor(tonumber(machineCount) or 1))
    local sourceCount = #counts
    local rows, totalLifts = {}, 0
    for _ = 1, repeatCount do
        for index, sheets in ipairs(counts) do
            if #rows >= maxPallets then break end
            local amount = math.max(Jobs.MIN_SHEETS, math.min(Jobs.MAX_SHEETS,
                math.floor(tonumber(sheets) or Jobs.MIN_SHEETS)))
            local units = math.max(1, math.min(Jobs.MAX_SHEETS / Jobs.LIFT_CAPACITY,
                math.ceil(amount / Jobs.LIFT_CAPACITY)))
            rows[#rows + 1] = { sheets = amount, lifts = units, source = index }
            totalLifts = totalLifts + units
        end
        if #rows >= maxPallets then break end
    end

    local target = math.min(maxPallets * (Jobs.MAX_SHEETS / Jobs.LIFT_CAPACITY),
        math.max(totalLifts, math.floor(tonumber(liftBudget) or totalLifts)))
    if allowReduction then
        target = math.min(totalLifts, math.max(1, math.floor(tonumber(liftBudget) or totalLifts)))
        while totalLifts > target do
            local selected
            for index, row in ipairs(rows) do
                if row.lifts > 1 and (not selected or row.lifts > rows[selected].lifts) then
                    selected = index
                end
            end
            if selected then
                rows[selected].lifts = rows[selected].lifts - 1
                rows[selected].sheets = math.max(Jobs.MIN_SHEETS,
                    rows[selected].sheets - Jobs.LIFT_CAPACITY)
                totalLifts = totalLifts - 1
            elseif #rows > 1 then
                totalLifts = totalLifts - rows[#rows].lifts
                table.remove(rows)
            else
                break
            end
        end
    end
    while totalLifts < target do
        local selected
        for index, row in ipairs(rows) do
            if row.lifts < Jobs.MAX_SHEETS / Jobs.LIFT_CAPACITY
                and (not selected or row.lifts < rows[selected].lifts) then
                selected = index
            end
        end
        if selected then
            rows[selected].lifts = rows[selected].lifts + 1
            rows[selected].sheets = math.min(Jobs.MAX_SHEETS,
                rows[selected].sheets + Jobs.LIFT_CAPACITY)
            totalLifts = totalLifts + 1
        elseif #rows < maxPallets then
            local source = (#rows % sourceCount) + 1
            rows[#rows + 1] = { sheets = Jobs.LIFT_CAPACITY, lifts = 1, source = source }
            totalLifts = totalLifts + 1
        else
            break
        end
    end

    local scaledCounts, scaledCopies = {}, {}
    for index, row in ipairs(rows) do
        local sheets = row.sheets
        scaledCounts[index] = sheets
        if requestedCopies then
            local originalSheets = math.max(1, tonumber(counts[row.source]) or sheets)
            local originalCopies = math.max(1, tonumber(requestedCopies[row.source]) or originalSheets)
            scaledCopies[index] = math.min(sheets,
                math.max(1, math.floor(originalCopies * sheets / originalSheets + 0.5)))
        end
    end
    return scaledCounts, requestedCopies and scaledCopies or nil
end

function Progression.volumeDiscount(lifts)
    local volume = math.max(0, math.floor(tonumber(lifts) or 0))
    return math.min(0.15, math.max(0, volume - 4) * 0.0125)
end

function Progression.qualityStandard(tier)
    if tier >= 4 then return 0.95 end
    if tier >= 3 then return 0.93 end
    if tier >= 2 then return 0.88 end
    if tier >= 1 then return 0.80 end
    return 0.73
end

return Progression
