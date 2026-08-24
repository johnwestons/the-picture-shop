local PaperWork = {}

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
        orientation = 0,
        activeCut = 1,
        cuts = cuts,
        status = "uncut",
        history = {},
    }
end

function PaperWork.currentCut(paper)
    return paper and paper.cuts and paper.cuts[paper.activeCut]
end

function PaperWork.rotate(paper)
    if not paper or paper.status == "complete" then return false end
    local cut = PaperWork.currentCut(paper)
    if not cut or paper.orientation == cut.orientation then return false end
    -- Move directly to the next programmed quarter-turn. This is one
    -- counter-clockwise handling turn for the operator, even though the
    -- stored screen orientation alternates across the four bed quadrants.
    paper.orientation = cut.orientation
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

function PaperWork.applyCut(paper, gauge)
    local cut = PaperWork.currentCut(paper)
    if not cut then return false, "No remaining programmed cut." end
    if paper.orientation ~= cut.orientation then
        return false, string.format("Rotate paper to %d degrees for the %s margin.", cut.orientation, cut.edge)
    end
    if not PaperWork.gaugeMatches(paper, gauge) then
        return false, string.format("Backgauge must be %.2f in for this cut.", cut.gauge)
    end
    if cut.edge == "left" or cut.edge == "right" then
        paper.currentSize.width = round(paper.currentSize.width - cut.margin)
    else
        paper.currentSize.height = round(paper.currentSize.height - cut.margin)
    end
    paper.history[#paper.history + 1] = {
        number = cut.number,
        edge = cut.edge,
        margin = cut.margin,
        gauge = gauge,
        resultingSize = { width = paper.currentSize.width, height = paper.currentSize.height },
    }
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
