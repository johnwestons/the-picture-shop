local PaperWork = require("src.paper_work")

local Presentation = {}
Presentation.__index = Presentation

local function fraction(value)
    return math.max(0, math.min(1, (tonumber(value) or 0) / 1000))
end

function Presentation.new()
    return setmetatable({ elapsed = 0, phase = 0, clamp = 0 }, Presentation)
end

function Presentation:accept(view)
    view = view or {}
    local revision = tonumber(view.runtimeRevision) or -1
    if self.revision and revision < self.revision then return false end
    local phase, clamp = fraction(view.phasePermille), fraction(view.clampPermille)
    local paper = type(view.paper) == "table" and view.paper or {}
    local paperKey = table.concat({ tostring(paper.palletId), tostring(paper.activeLift),
        tostring(paper.activeCut), tostring(paper.orientation) }, ":")
    -- The host increments runtimeRevision every simulation frame, not merely
    -- on commands. Smooth across newer revisions within the same physical phase.
    local continuous = self.step == view.step and self.revision ~= nil
        and revision >= self.revision and phase >= self.phase and self.paperKey == paperKey
        and self.loaded == view.loaded and self.emergency == view.emergencyStopped
    self.fromPhase = continuous and self.phase or phase
    self.fromClamp = continuous and self.clamp or clamp
    self.targetPhase, self.targetClamp = phase, clamp
    self.phase, self.clamp = self.fromPhase, self.fromClamp
    self.step, self.revision = view.step, revision
    self.paperKey = paperKey
    self.loaded, self.emergency = view.loaded, view.emergencyStopped
    self.elapsed = 0
    return true
end

function Presentation:update(dt)
    self.elapsed = math.min(0.1, self.elapsed + math.max(0, tonumber(dt) or 0))
    local t = self.elapsed / 0.1
    self.phase = (self.fromPhase or 0) + ((self.targetPhase or 0) - (self.fromPhase or 0)) * t
    self.clamp = (self.fromClamp or 0) + ((self.targetClamp or 0) - (self.fromClamp or 0)) * t
end

local function findPaper(state, id)
    if id == "STOCK-P01" then return PaperWork.createStockPaper() end
    for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.id == id then return pallet.paper end
        end
    end
end

function Presentation:model(state, view)
    view = view or {}
    local model = {
        step = view.step or "idle", loaded = view.loaded == true,
        transferTime = 1, cycleTime = 1, progress = self.phase,
        clampProgress = self.clamp,
    }
    local record = view.paper
    local source = record and findPaper(state, record.palletId)
    if not source or not source.sourceSize or not source.margins then return model end
    -- The ticket comes from the host's durable shop snapshot. Reconstruct only
    -- completed, host-confirmed cuts so realtime rotation/lift changes do not
    -- wait for the next full save snapshot. Never mutate that mirrored ticket.
    local size = { width = source.sourceSize.width, height = source.sourceSize.height }
    local history = {}
    for index, cut in ipairs(source.cuts or {}) do
        if index < (record.activeCut or 1) then
            history[#history + 1] = { edge = cut.edge }
            if cut.edge == "left" or cut.edge == "right" then size.width = cut.gauge
            else size.height = cut.gauge end
        end
    end
    if record.widthCentiInch and record.heightCentiInch then
        size = { width = record.widthCentiInch / 100, height = record.heightCentiInch / 100 }
        if record.offSpec then history = source.offSpec and source.history or {} end
    elseif source.offSpec then
        size = { width = source.currentSize.width, height = source.currentSize.height }
        history = source.history
    end
    model.paper = {
        orientation = record.orientation or 0, currentSize = size,
        margins = source.margins, history = history,
        artworkId = source.artworkId, artworkKey = source.artworkKey,
        offSpec = record.offSpec == true,
    }
    for key, value in pairs(source) do if model.paper[key] == nil then model.paper[key] = value end end
    model.paper.activeCut, model.paper.status = record.activeCut, record.status
    return model
end

return Presentation
