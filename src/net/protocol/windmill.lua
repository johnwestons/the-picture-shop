-- Windmill runtime, setup, and plate validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizeWindmillSetupPermille(value, label)
        if not Runtime.Codec.isArray(value) then return nil, label .. " must be an array" end
        if #value ~= 6 then return nil, label .. " must contain exactly 6 setup values" end
        local setup = {}
        for index = 1, 6 do
            local progress, fieldError = Runtime.integerInRange(
                value[index], 0, 1000, label .. "[" .. index .. "]")
            if progress == nil then return nil, fieldError end
            setup[index] = progress
        end
        return Runtime.Codec.array(setup)
    end

    function Runtime.normalizeWindmillCandidates(value, label)
        if not Runtime.Codec.isArray(value) then return nil, label .. " must be an array" end
        if #value > 3 then return nil, label .. " must contain at most 3 pallets" end
        local candidates, seen = {}, {}
        for index = 1, #value do
            local candidateLabel = label .. "[" .. index .. "]"
            local valid, shapeError = Runtime.shape(
                value[index], candidateLabel, { "palletId", "colorIndex" })
            if not valid then return nil, shapeError end
            local palletId, fieldError = Runtime.token(
                value[index].palletId, Runtime.MAX_WINDMILL_ID_BYTES, candidateLabel .. ".palletId")
            if not palletId then return nil, fieldError end
            if seen[palletId] then return nil, label .. " contains a duplicate palletId" end
            seen[palletId] = true
            local colorIndex
            colorIndex, fieldError = Runtime.integerInRange(
                value[index].colorIndex, 1, 4, candidateLabel .. ".colorIndex")
            if not colorIndex then return nil, fieldError end
            candidates[#candidates + 1] = {
                palletId = palletId,
                colorIndex = colorIndex,
            }
        end
        return Runtime.Codec.array(candidates)
    end

    function Runtime.normalizeWindmillWorkshopView(value, label)
        local valid, shapeError = Runtime.shape(value, label, {
            "runtimeRevision", "status", "speed", "motor", "feeder", "impression",
            "emergency", "counter", "goodSheets", "spoilage", "targetSheets", "feedStart",
            "feedRemaining", "proofApproved", "artworkVerified", "setupPermille", "candidates",
            "serviceStep", "servicePermille", "plateMarkerPermille",
        }, {
            "jobId", "palletId", "colorIndex", "colorCount", "proofPermille", "warning",
            "setupTask", "setupSummary", "serviceTask", "setupVisual",
        })
        if not valid then return nil, shapeError end
        local normalized, fieldError = {}
        normalized.runtimeRevision, fieldError = Runtime.integerInRange(
            value.runtimeRevision, 0, Runtime.UINT32_MAX, label .. ".runtimeRevision")
        if normalized.runtimeRevision == nil then return nil, fieldError end
        if type(value.status) ~= "string" or not Runtime.WORKSHOP_WINDMILL_STATUSES[value.status] then
            return nil, label .. ".status is invalid"
        end
        normalized.status = value.status
        normalized.speed, fieldError = Runtime.integerInRange(value.speed, 1000, 5500, label .. ".speed")
        if normalized.speed == nil then return nil, fieldError end
        for _, field in ipairs({
            "motor", "feeder", "impression", "emergency", "proofApproved", "artworkVerified",
        }) do
            if type(value[field]) ~= "boolean" then
                return nil, label .. "." .. field .. " must be boolean"
            end
            normalized[field] = value[field]
        end
        for _, field in ipairs({
            "counter", "goodSheets", "spoilage", "targetSheets", "feedStart", "feedRemaining",
        }) do
            normalized[field], fieldError = Runtime.integerInRange(
                value[field], 0, Runtime.UINT32_MAX, label .. "." .. field)
            if normalized[field] == nil then return nil, fieldError end
        end
        normalized.setupPermille, fieldError = Runtime.normalizeWindmillSetupPermille(
            value.setupPermille, label .. ".setupPermille")
        if not normalized.setupPermille then return nil, fieldError end
        normalized.candidates, fieldError = Runtime.normalizeWindmillCandidates(
            value.candidates, label .. ".candidates")
        if not normalized.candidates then return nil, fieldError end
        if type(value.serviceStep) ~= "string"
            or not Runtime.WORKSHOP_WINDMILL_SERVICE_STEPS[value.serviceStep]
        then
            return nil, label .. ".serviceStep is invalid"
        end
        normalized.serviceStep = value.serviceStep
        normalized.servicePermille, fieldError = Runtime.integerInRange(
            value.servicePermille, 0, 1000, label .. ".servicePermille")
        if normalized.servicePermille == nil then return nil, fieldError end
        normalized.plateMarkerPermille, fieldError = Runtime.integerInRange(
            value.plateMarkerPermille, 0, 1000, label .. ".plateMarkerPermille")
        if normalized.plateMarkerPermille == nil then return nil, fieldError end

        for _, field in ipairs({ "jobId", "palletId" }) do
            if value[field] ~= nil then
                normalized[field], fieldError = Runtime.token(
                    value[field], Runtime.MAX_WINDMILL_ID_BYTES, label .. "." .. field)
                if not normalized[field] then return nil, fieldError end
            end
        end
        for _, field in ipairs({ "colorIndex", "colorCount" }) do
            if value[field] ~= nil then
                normalized[field], fieldError = Runtime.integerInRange(
                    value[field], 1, 4, label .. "." .. field)
                if not normalized[field] then return nil, fieldError end
            end
        end
        if value.proofPermille ~= nil then
            normalized.proofPermille, fieldError = Runtime.integerInRange(
                value.proofPermille, 0, 1000, label .. ".proofPermille")
            if normalized.proofPermille == nil then return nil, fieldError end
        end
        local viewTextBytes = 0
        for _, field in ipairs({ "warning", "setupSummary", "serviceTask" }) do
            if value[field] ~= nil then
                normalized[field], fieldError = Runtime.printableString(
                    value[field], 1, Runtime.MAX_WINDMILL_VIEW_TEXT_TOTAL_BYTES,
                    label .. "." .. field)
                if not normalized[field] then return nil, fieldError end
                viewTextBytes = viewTextBytes + #normalized[field]
            end
        end
        if viewTextBytes > Runtime.MAX_WINDMILL_VIEW_TEXT_TOTAL_BYTES then
            return nil, label .. " optional display text exceeds "
                .. Runtime.MAX_WINDMILL_VIEW_TEXT_TOTAL_BYTES .. " bytes"
        end
        if value.setupTask ~= nil then
            if type(value.setupTask) ~= "string"
                or not Runtime.WORKSHOP_WINDMILL_SETUP_TASKS[value.setupTask]
            then
                return nil, label .. ".setupTask is invalid"
            end
            normalized.setupTask = value.setupTask
        end
        if value.setupVisual ~= nil then
            normalized.setupVisual, fieldError = require("src.press_setup_view").normalize(value.setupTask, value.setupVisual)
            if not normalized.setupVisual then return nil, fieldError end
        end
        return normalized
    end
end

return Component
