local Jobs = require("src.jobs")
local PaperWork = require("src.paper_work")
local Guide = require("src.cutter_cut_guide")
local Test = {}

local function spec(width, height, difficulty)
    return { company = "Trim Margin Co.", sourceSize = { width = width, height = height },
        finishedSize = { width = 24, height = 24 }, sheetCounts = { 500, 500, 500, 500, 500 },
        difficulty = difficulty or "hard" }
end

local function hasTrim(job)
    if not job or job.sourceSize.width + 0.000001 < job.finishedSize.width + Jobs.MIN_STOCK_EXCESS
        or job.sourceSize.height + 0.000001 < job.finishedSize.height + Jobs.MIN_STOCK_EXCESS then
        return false
    end
    for _, pallet in ipairs(job.pallets) do
        for _, cut in ipairs(pallet.paper.cuts) do
            if cut.margin < 0.25 then return false end
        end
    end
    return true
end

local function validation(check)
    for index, size in ipairs({ { 24, 25 }, { 25, 24 }, { 24.99, 25 }, { 25, 24.99 },
        { 24.01, 24.01 }, { 26, 25 }, { 25, 26 }, { 0 / 0, 25 }, { 25, math.huge } }) do
        local invalid = spec(size[1], size[2])
        check("cut_stock_rejects_missing_or_invalid_trim_" .. index,
            not Jobs.validateSpec(invalid) and Jobs.createOffer(invalid) == nil)
    end
    for _, difficulty in ipairs({ "easy", "medium", "hard" }) do
        local offer = assert(Jobs.createOffer(spec(25, 25, difficulty)))
        check("cut_stock_minimum_accepted_" .. difficulty, hasTrim(offer))
        for index, pallet in ipairs(offer.pallets) do
            local paper = pallet.paper
            local trimmed = true
            for number = 1, 4 do
                local cut = PaperWork.currentCut(paper)
                local width, height = paper.currentSize.width, paper.currentSize.height
                PaperWork.rotate(paper)
                local ok, result = PaperWork.applyCut(paper, cut.gauge, number)
                trimmed = trimmed and ok and not result.offSpec
                    and (paper.currentSize.width < width or paper.currentSize.height < height)
            end
            check("cut_stock_four_real_cuts_finish_exactly_" .. difficulty .. "_" .. index,
                trimmed and paper.status == "complete" and #paper.history == 4
                and paper.currentSize.width == 24 and paper.currentSize.height == 24)
            PaperWork.resetForNextLift(paper)
            check("cut_stock_next_lift_restores_trim_" .. difficulty .. "_" .. index,
                paper.currentSize.width == 25 and paper.currentSize.height == 25
                and paper.status == "uncut" and #paper.history == 0)
        end
    end
end

local function offers(context, check)
    local starter
    for _, score in ipairs({ 0, 5, 20, 50, 80 }) do
        local state = context.State.new()
        state.reputation.score = score
        for sequence = 1, 9 do
            state.nextJobId = sequence
            local offer = context.jobService.createNextOffer(state, sequence)
            check("cut_stock_generated_offer_has_trim_" .. score .. "_" .. sequence, hasTrim(offer))
            if score == 0 and sequence == 1 then starter = offer end
        end
    end
    check("cut_stock_starter_has_top_and_bottom_trim",
        starter.sourceSize.width == 17 and starter.sourceSize.height == 12
        and starter.finishedSize.width == 8.5 and starter.finishedSize.height == 11
        and starter.pallets[1].paper.margins.top == 0.5
        and starter.pallets[1].paper.margins.bottom == 0.5)
    -- Simulate the old starter ticket, including its flush-height stock.
    starter.sourceSize.height, starter.status = 11, "completed"
    for email = 1, 2 do
        local state = context.State.new()
        state.reputation.score, state.clientEmails.nextEmailId = 80, email
        local scheduled = context.jobService.scheduleRepeatEmail(state, starter)
        local repeatJob = scheduled and state.clientEmails.pending[1].job
        check("cut_stock_legacy_repeat_gets_trim_" .. email,
            hasTrim(repeatJob) and starter.sourceSize.height == 11)
        check("cut_stock_repeat_keeps_requested_dimensions_" .. email,
            repeatJob and repeatJob.finishedSize.width == (email == 1 and 8.5 or 11)
            and repeatJob.finishedSize.height == (email == 1 and 11 or 8.5))
    end
    starter.sourceSize.height = 12
    return starter
end

local function renderedMargins(check)
    local runtime = { Screen = {}, CutGuide = Guide }
    require("src.screens.machine.paper").install(runtime)
    local offer = assert(Jobs.createOffer(spec(25, 25)))
    local paper = offer.pallets[1].paper
    local canvas = love.graphics.newCanvas(960, 680)
    -- Inspect the real stock/artwork draw calls, including every cut and rotation.
    -- The first fills are shadow, stock, then artwork; later fills are decoration.
    local rectangle, fills = love.graphics.rectangle, {}
    love.graphics.rectangle = function(mode, x, y, width, height, ...)
        if mode == "fill" then fills[#fills + 1] = { x = x, y = y, w = width, h = height } end
        return rectangle(mode, x, y, width, height, ...)
    end
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    local ok, failure = xpcall(function()
        for completed = 0, 4 do
            for turns = 0, 3 do
                paper.orientation, fills = turns * 90, {}
                love.graphics.clear(0, 0, 0, 1)
                runtime.drawPaper(nil, { loaded = true, step = "loaded", paper = paper, programIndex = completed + 1 })
                local stock, artwork = fills[2], fills[3]
                local borders = { artwork.y - stock.y, stock.x + stock.w - artwork.x - artwork.w,
                    stock.y + stock.h - artwork.y - artwork.h, artwork.x - stock.x }
                local visible, flush = true, true
                local originalEdges = { top = 1, right = 2, bottom = 3, left = 4 }
                local cutEdges = {}
                for _, cut in ipairs(paper.history) do
                    cutEdges[(originalEdges[cut.edge] - 1 + turns) % 4 + 1] = true
                end
                for edge, pixels in ipairs(borders) do
                    if cutEdges[edge] then flush = flush and math.abs(pixels) < 0.001
                    else visible = visible and pixels >= Guide.MIN_VISIBLE_MARGIN - 0.001 end
                end
                check("cut_stock_rendered_uncut_borders_visible_" .. completed .. "_" .. turns, visible)
                check("cut_stock_rendered_cut_edges_are_flush_" .. completed .. "_" .. turns, flush)
            end
            if completed < 4 then
                PaperWork.rotate(paper)
                assert(PaperWork.applyCut(paper, PaperWork.currentCut(paper).gauge, completed + 1))
            end
        end
    end, debug.traceback)
    love.graphics.rectangle = rectangle
    love.graphics.pop()
    canvas:release()
    if not ok then error(failure) end
    check("cut_stock_no_fake_trim_for_flush_edge",
        Guide.marginPixels(0, 100, 25) == 0
        and Guide.band({ screenEdge = "bottom", margin = 0 }, 0, 0, 100, 50, 25, 25) == nil)
end

local function captures(context, starter)
    local directory = os.getenv("PICTURE_SHOP_CUT_STOCK_CAPTURE_DIR")
    if not directory then return end
    local screen = require("src.screens.machine_screen")
    local pack = context.assets.activePack
    context.assets.activatePack("cutter")
    local hard = assert(Jobs.createOffer(spec(25, 25)))
    for _, item in ipairs({ { "starter", starter }, { "minimum-hard", hard } }) do
        for _, viewport in ipairs({ { "desktop", 960, 640 }, { "mobile", 480, 320 } }) do
            local canvas = love.graphics.newCanvas(viewport[2], viewport[3])
            love.graphics.push("all")
            love.graphics.setCanvas(canvas)
            love.graphics.clear(0.05, 0.08, 0.10, 1)
            local paper = item[2].pallets[1].paper
            paper.orientation = 90
            screen.drawCutterScene(context.assets, { loaded = true, step = "loaded", paper = paper,
                progress = 0, transferTime = 1, cycleTime = 1, clampProgress = 0, programIndex = 1 },
                { x = 0, y = 0, width = viewport[2], height = viewport[3] })
            love.graphics.pop()
            local pixels = canvas:newImageData()
            local encoded = pixels:encode("png")
            local file = assert(io.open(directory .. "/" .. item[1] .. "-" .. viewport[1] .. ".png", "wb"))
            file:write(encoded:getString())
            file:close()
            encoded:release()
            pixels:release()
            canvas:release()
        end
    end
    context.assets.activatePack(pack)
end

function Test.run(context, check)
    validation(check)
    local starter = offers(context, check)
    renderedMargins(check)
    captures(context, starter)
end

return Test
