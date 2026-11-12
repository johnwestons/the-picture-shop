local PaperWork = {}
local BladeProfiles = require("src.machine.cutter.blade_profiles")

function PaperWork.createStockPaper()
    local job = { id = "STOCK", sourceSize = { width = 13, height = 10 },
        finishedSize = { width = 12, height = 9 } }
    local pallet = { id = "STOCK-P01" }
    return PaperWork.create(job, pallet, "easy", 1), pallet, job
end

local function round(value)
    return math.floor(value * 100 + 0.5) / 100
end

local function splitMargin(total, difficulty, seed)
    if total <= 0 then return 0, 0 end
    local ratio = 0.5
    if difficulty == "medium" then
        ratio = seed % 2 == 0 and 0.4 or 0.6
    elseif difficulty == "hard" then
        local ratios = { 0.25, 0.35, 0.65, 0.75 }
        ratio = ratios[seed % #ratios + 1]
    end
    local first = round(total * ratio)
    return first, round(total - first)
end

function PaperWork.create(job, pallet, difficulty, seed)
    local source = job.sourceSize
    local finished = job.finishedSize
    local horizontal = round(source.width - finished.width)
    local vertical = round(source.height - finished.height)
    local left, right = splitMargin(horizontal, difficulty, seed * 3 + 1)
    local top, bottom = splitMargin(vertical, difficulty, seed * 5 + 2)
    local afterRight = round(source.width - right)
    local afterBottom = round(source.height - bottom)
    local cuts = {
        -- The active margin is always placed on the operator-facing edge
        -- nearest the screen. In the bed renderer, these orientations map
        -- right, bottom, left, and top to the front edge respectively.
        { number = 1, edge = "right", margin = right, gauge = afterRight, orientation = 90 },
        { number = 2, edge = "bottom", margin = bottom, gauge = afterBottom, orientation = 0 },
        { number = 3, edge = "left", margin = left, gauge = finished.width, orientation = 270 },
        { number = 4, edge = "top", margin = top, gauge = finished.height, orientation = 180 },
    }
    return {
        id = pallet.id .. "-PAPER",
        jobId = job.id,
        palletId = pallet.id,
        artworkId = "ART-" .. job.id,
        artworkKey = job.artworkKey or "flower",
        difficulty = difficulty,
        sourceSize = { width = source.width, height = source.height },
        finishedSize = { width = finished.width, height = finished.height },
        currentSize = { width = source.width, height = source.height },
        margins = { left = left, right = right, top = top, bottom = bottom },
        orientation = cuts[1].orientation or 0,
        activeCut = 1,
        cuts = cuts,
        status = "uncut",
        cutQuality = 1,
        history = {},
    }
end

function PaperWork.currentCut(paper)
    return paper and paper.cuts and paper.cuts[paper.activeCut]
end

function PaperWork.prepareFirstCut(paper)
    if not paper or type(paper.cuts) ~= "table" or (paper.activeCut or 1) ~= 1
        or #(paper.history or {}) > 0 or not paper.cuts[1]
    then return false end
    paper.orientation = paper.cuts[1].orientation or 0
    return true
end

-- Positive rotation is clockwise in the cutter's screen-space presentation.
-- Follow the same quarter-turn direction as the programmed cut sequence so a
-- single click after each cut presents the next edge to the blade.
function PaperWork.rotationDirection(paper)
    local cuts = paper and paper.cuts
    if type(cuts) ~= "table" or #cuts < 2 then return -1 end
    local active = math.max(1, math.floor(tonumber(paper.activeCut) or 1))
    local fromIndex, toIndex
    if active > 1 and cuts[active - 1] and cuts[active] then
        fromIndex, toIndex = active - 1, active
    elseif cuts[active] and cuts[active + 1] then
        fromIndex, toIndex = active, active + 1
    else
        return -1
    end
    local from = tonumber(cuts[fromIndex].orientation) or 0
    local to = tonumber(cuts[toIndex].orientation) or from
    local delta = (to - from + 540) % 360 - 180
    if math.abs(delta) < 0.001 then return -1 end
    return delta > 0 and 1 or -1
end

function PaperWork.rotate(paper, direction)
    if not paper or paper.status == "complete" then return false end
    if direction ~= nil and direction ~= 1 and direction ~= -1 then return false end
    paper.orientation = ((tonumber(paper.orientation) or 0) + 90 * (direction or PaperWork.rotationDirection(paper))) % 360
    return true
end

function PaperWork.normalizeOrientations(paper)
    if not paper or type(paper.cuts) ~= "table" then return end
    local orientations = { right = 90, bottom = 0, left = 270, top = 180 }
    for _, cut in ipairs(paper.cuts) do
        if orientations[cut.edge] then cut.orientation = orientations[cut.edge] end
    end
end

function PaperWork.gaugeMatches(paper, gauge)
    local cut = PaperWork.currentCut(paper)
    return cut ~= nil and math.abs((gauge or 0) - cut.gauge) < 0.011
end

function PaperWork.applyCut(paper, gauge, programIndex, bladeSharpness, operatorSkill, bladeGrade)
    local cut = PaperWork.currentCut(paper)
    if not cut then return false, "No remaining programmed cut." end
    gauge = round(tonumber(gauge) or 0)
    local correctProgram = programIndex == nil or programIndex == paper.activeCut
    local expectedProgram = paper.activeCut
    local correctRotation = paper.orientation == cut.orientation
    local correctGauge = PaperWork.gaugeMatches(paper, gauge)
    local offSpec = not correctProgram or not correctRotation or not correctGauge
    local sharpness = math.max(0, math.min(100, tonumber(bladeSharpness) or 100))
    local blade = BladeProfiles.get(bladeGrade) or BladeProfiles.get("standard")
    local bladeQuality = blade.qualityFloor + (1 - blade.qualityFloor) * sharpness / 100
    local skillQuality = operatorSkill == nil and 1
        or 0.82 + 0.18 * math.max(0, math.min(100, tonumber(operatorSkill) or 0)) / 100
    local edgeQuality = math.min(bladeQuality, skillQuality)
    paper.cutQuality = math.min(tonumber(paper.cutQuality) or 1, edgeQuality)
    local horizontal = correctRotation and (cut.edge == "left" or cut.edge == "right")
        or paper.orientation == 90 or paper.orientation == 270
    if horizontal then
        local original = paper.currentSize.width
        paper.currentSize.width = math.max(0.01, math.min(original, gauge))
    else
        local original = paper.currentSize.height
        paper.currentSize.height = math.max(0.01, math.min(original, gauge))
    end
    paper.history[#paper.history + 1] = {
        number = cut.number,
        edge = cut.edge,
        margin = horizontal
            and round(math.max(0, paper.sourceSize.width - paper.currentSize.width))
            or round(math.max(0, paper.sourceSize.height - paper.currentSize.height)),
        gauge = gauge,
        resultingSize = { width = paper.currentSize.width, height = paper.currentSize.height },
        edgeQuality = edgeQuality,
        offSpec = offSpec,
        expectedGauge = cut.gauge,
        selectedProgram = programIndex,
    }
    if offSpec then
        paper.offSpec = true
        paper.status = "complete"
        paper.activeCut = #paper.cuts + 1
        return true, {
            offSpec = true,
            expectedGauge = cut.gauge,
            actualGauge = gauge,
            expectedOrientation = cut.orientation,
            actualOrientation = paper.orientation,
            expectedProgram = expectedProgram,
            selectedProgram = programIndex,
        }
    end
    paper.activeCut = paper.activeCut + 1
    if paper.activeCut > #paper.cuts then
        paper.status = "complete"
        paper.currentSize.width = paper.finishedSize.width
        paper.currentSize.height = paper.finishedSize.height
    else
        paper.status = "in_process"
    end
    return true, cut
end

function PaperWork.resetForNextLift(paper)
    if not paper or type(paper.sourceSize) ~= "table" then return false end
    paper.currentSize = {
        width = paper.sourceSize.width,
        height = paper.sourceSize.height,
    }
    paper.orientation = paper.cuts and paper.cuts[1] and paper.cuts[1].orientation or 0
    paper.activeCut = 1
    paper.status = "uncut"
    paper.offSpec = nil
    paper.history = {}
    return true
end

function PaperWork.tooltip(paper)
    if not paper then return "No paper selected" end
    local nextCut = PaperWork.currentCut(paper)
    local text = string.format(
        "%s | %s | %.2f x %.2f in | %d degrees",
        paper.id,
        paper.artworkId,
        paper.currentSize.width,
        paper.currentSize.height,
        paper.orientation
    )
    if nextCut then
        text = text .. string.format(" | next: %s %.2f in @ gauge %.2f", nextCut.edge, nextCut.margin, nextCut.gauge)
    else
        text = text .. " | COMPLETE"
    end
    return text
end

return PaperWork
