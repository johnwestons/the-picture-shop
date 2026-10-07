-- Cutter runtime and maintenance validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizeCutterMemory(value, label)
        if not Runtime.Codec.isArray(value) then return nil, label .. " must be an array" end
        if #value > 3 then return nil, label .. " must contain at most 3 measurements" end
        local memory = {}
        for index = 1, #value do
            local measurement, fieldError = Runtime.integerInRange(
                value[index], 0, 2500, label .. "[" .. index .. "]")
            if measurement == nil then return nil, fieldError end
            memory[#memory + 1] = measurement
        end
        return Runtime.Codec.array(memory)
    end

    function Runtime.normalizeCutterSelectedCut(value, label)
        local valid, shapeError = Runtime.shape(value, label, {
            "number", "edge", "marginCentiInch", "gaugeCentiInch", "orientation", "active",
        })
        if not valid then return nil, shapeError end
        local number, fieldError = Runtime.integerInRange(value.number, 1, 4, label .. ".number")
        if not number then return nil, fieldError end
        if type(value.edge) ~= "string" or not Runtime.WORKSHOP_CUTTER_EDGES[value.edge] then
            return nil, label .. ".edge is invalid"
        end
        local marginCentiInch
        marginCentiInch, fieldError = Runtime.integerInRange(
            value.marginCentiInch, 0, 100000, label .. ".marginCentiInch")
        if marginCentiInch == nil then return nil, fieldError end
        local gaugeCentiInch
        gaugeCentiInch, fieldError = Runtime.integerInRange(
            value.gaugeCentiInch, 0, 2500, label .. ".gaugeCentiInch")
        if gaugeCentiInch == nil then return nil, fieldError end
        local orientation
        orientation, fieldError = Runtime.integerInRange(
            value.orientation, 0, 270, label .. ".orientation")
        if orientation == nil then return nil, fieldError end
        if not Runtime.WORKSHOP_CUTTER_ORIENTATIONS[orientation] then
            return nil, label .. ".orientation is invalid"
        end
        if type(value.active) ~= "boolean" then return nil, label .. ".active must be boolean" end
        return {
            number = number,
            edge = value.edge,
            marginCentiInch = marginCentiInch,
            gaugeCentiInch = gaugeCentiInch,
            orientation = orientation,
            active = value.active,
        }
    end

    function Runtime.normalizeCutterPaper(value, label)
        local valid, shapeError = Runtime.shape(value, label, {
            "palletId", "orientation", "status", "activeCut", "cutCount", "activeLift",
            "requiredLifts", "remainingSheets",
        }, { "selectedCut", "widthCentiInch", "heightCentiInch", "offSpec" })
        if not valid then return nil, shapeError end
        local palletId, fieldError = Runtime.token(value.palletId, Runtime.MAX_TOKEN_BYTES, label .. ".palletId")
        if not palletId then return nil, fieldError end
        local orientation
        orientation, fieldError = Runtime.integerInRange(value.orientation, 0, 270, label .. ".orientation")
        if orientation == nil then return nil, fieldError end
        if not Runtime.WORKSHOP_CUTTER_ORIENTATIONS[orientation] then
            return nil, label .. ".orientation is invalid"
        end
        if type(value.status) ~= "string" or not Runtime.WORKSHOP_CUTTER_PAPER_STATUSES[value.status] then
            return nil, label .. ".status is invalid"
        end
        local activeCut
        activeCut, fieldError = Runtime.integerInRange(value.activeCut, 1, 5, label .. ".activeCut")
        if not activeCut then return nil, fieldError end
        local cutCount
        cutCount, fieldError = Runtime.integerInRange(value.cutCount, 1, 4, label .. ".cutCount")
        if not cutCount then return nil, fieldError end
        local activeLift
        activeLift, fieldError = Runtime.integerInRange(value.activeLift, 1, 1000, label .. ".activeLift")
        if not activeLift then return nil, fieldError end
        local requiredLifts
        requiredLifts, fieldError = Runtime.integerInRange(
            value.requiredLifts, 1, 1000, label .. ".requiredLifts")
        if not requiredLifts then return nil, fieldError end
        local remainingSheets
        remainingSheets, fieldError = Runtime.integerInRange(
            value.remainingSheets, 0, 100000, label .. ".remainingSheets")
        if remainingSheets == nil then return nil, fieldError end
        local paper = {
            palletId = palletId,
            orientation = orientation,
            status = value.status,
            activeCut = activeCut,
            cutCount = cutCount,
            activeLift = activeLift,
            requiredLifts = requiredLifts,
            remainingSheets = remainingSheets,
        }
        if value.selectedCut ~= nil then
            paper.selectedCut, fieldError = Runtime.normalizeCutterSelectedCut(
                value.selectedCut, label .. ".selectedCut")
            if not paper.selectedCut then return nil, fieldError end
        end
        if value.widthCentiInch ~= nil or value.heightCentiInch ~= nil or value.offSpec ~= nil then
            paper.widthCentiInch, fieldError = Runtime.integerInRange(value.widthCentiInch, 1, 100000,
                label .. ".widthCentiInch")
            if not paper.widthCentiInch then return nil, fieldError end
            paper.heightCentiInch, fieldError = Runtime.integerInRange(value.heightCentiInch, 1, 100000,
                label .. ".heightCentiInch")
            if not paper.heightCentiInch then return nil, fieldError end
            if type(value.offSpec) ~= "boolean" then return nil, label .. ".offSpec must be boolean" end
            paper.offSpec = value.offSpec
        end
        return paper
    end

    function Runtime.normalizeCutterCandidates(value, label)
        if not Runtime.Codec.isArray(value) then return nil, label .. " must be an array" end
        if #value > 3 then return nil, label .. " must contain at most 3 pallets" end
        local candidates, seen = {}, {}
        for index = 1, #value do
            local candidateLabel = label .. "[" .. index .. "]"
            local valid, shapeError = Runtime.shape(
                value[index], candidateLabel, { "palletId", "distancePixels" })
            if not valid then return nil, shapeError end
            local palletId, fieldError = Runtime.token(
                value[index].palletId, Runtime.MAX_TOKEN_BYTES, candidateLabel .. ".palletId")
            if not palletId then return nil, fieldError end
            if seen[palletId] then return nil, label .. " contains a duplicate palletId" end
            seen[palletId] = true
            local distancePixels
            distancePixels, fieldError = Runtime.integerInRange(
                value[index].distancePixels, 0, 100000, candidateLabel .. ".distancePixels")
            if distancePixels == nil then return nil, fieldError end
            candidates[#candidates + 1] = {
                palletId = palletId,
                distancePixels = distancePixels,
            }
        end
        return Runtime.Codec.array(candidates)
    end

    function Runtime.normalizeCutterServiceItems(value, label)
        if not Runtime.Codec.isArray(value) then return nil, label .. " must be an array" end
        if #value > 2 then return nil, label .. " must contain at most 2 visible points" end
        local items, seen = {}, {}
        for index = 1, #value do
            local itemLabel = label .. "[" .. index .. "]"
            local valid, shapeError = Runtime.shape(value[index], itemLabel, {
                "itemIndex", "label", "cleaned", "coupled", "strokes", "complete",
            })
            if not valid then return nil, shapeError end
            local itemIndex, fieldError = Runtime.integerInRange(
                value[index].itemIndex, 1, 7, itemLabel .. ".itemIndex")
            if not itemIndex then return nil, fieldError end
            if seen[itemIndex] then return nil, label .. " contains a duplicate itemIndex" end
            seen[itemIndex] = true
            local displayLabel
            displayLabel, fieldError = Runtime.printableString(
                value[index].label, 1, 48, itemLabel .. ".label")
            if not displayLabel then return nil, fieldError end
            for _, field in ipairs({ "cleaned", "coupled", "complete" }) do
                if type(value[index][field]) ~= "boolean" then
                    return nil, itemLabel .. "." .. field .. " must be boolean"
                end
            end
            local strokes
            strokes, fieldError = Runtime.integerInRange(
                value[index].strokes, 0, 99, itemLabel .. ".strokes")
            if strokes == nil then return nil, fieldError end
            items[#items + 1] = {
                itemIndex = itemIndex,
                label = displayLabel,
                cleaned = value[index].cleaned,
                coupled = value[index].coupled,
                strokes = strokes,
                complete = value[index].complete,
            }
        end
        return Runtime.Codec.array(items)
    end

    function Runtime.normalizeCutterWorkshopView(value, label)
        local valid, shapeError = Runtime.shape(value, label, {
            "runtimeRevision", "step", "phasePermille", "loaded", "clamp", "clampPermille",
            "bladePermille", "barrierClear", "emergencyStopped", "gaugeCentiInch",
            "programIndex", "memoryCentiInch",
        }, {
            "paper", "candidates", "genericSheets", "serviceStep", "servicePermille",
            "serviceView", "serviceTool", "serviceItems", "centralInstalled",
            "gearInspected", "gearLevelPermille", "bladeBoltsDone", "bladeBoltMask",
        })
        if not valid then return nil, shapeError end
        local runtimeRevision, fieldError = Runtime.integerInRange(
            value.runtimeRevision, 0, Runtime.UINT32_MAX, label .. ".runtimeRevision")
        if runtimeRevision == nil then return nil, fieldError end
        if type(value.step) ~= "string" or not Runtime.WORKSHOP_CUTTER_STEPS[value.step] then
            return nil, label .. ".step is invalid"
        end
        local phasePermille
        phasePermille, fieldError = Runtime.integerInRange(
            value.phasePermille, 0, 1000, label .. ".phasePermille")
        if phasePermille == nil then return nil, fieldError end
        if type(value.loaded) ~= "boolean" then return nil, label .. ".loaded must be boolean" end
        if type(value.clamp) ~= "boolean" then return nil, label .. ".clamp must be boolean" end
        local clampPermille
        clampPermille, fieldError = Runtime.integerInRange(
            value.clampPermille, 0, 1000, label .. ".clampPermille")
        if clampPermille == nil then return nil, fieldError end
        local bladePermille
        bladePermille, fieldError = Runtime.integerInRange(
            value.bladePermille, 0, 1000, label .. ".bladePermille")
        if bladePermille == nil then return nil, fieldError end
        if type(value.barrierClear) ~= "boolean" then
            return nil, label .. ".barrierClear must be boolean"
        end
        if type(value.emergencyStopped) ~= "boolean" then
            return nil, label .. ".emergencyStopped must be boolean"
        end
        local gaugeCentiInch
        gaugeCentiInch, fieldError = Runtime.integerInRange(
            value.gaugeCentiInch, 0, 2500, label .. ".gaugeCentiInch")
        if gaugeCentiInch == nil then return nil, fieldError end
        local programIndex
        programIndex, fieldError = Runtime.integerInRange(
            value.programIndex, 1, 4, label .. ".programIndex")
        if not programIndex then return nil, fieldError end
        local memoryCentiInch
        memoryCentiInch, fieldError = Runtime.normalizeCutterMemory(
            value.memoryCentiInch, label .. ".memoryCentiInch")
        if not memoryCentiInch then return nil, fieldError end
        local serviceStep, servicePermille
        if value.serviceStep ~= nil then
            if type(value.serviceStep) ~= "string"
                or not Runtime.WORKSHOP_CUTTER_SERVICE_STEPS[value.serviceStep]
                or value.serviceStep == "idle"
            then
                return nil, label .. ".serviceStep is invalid"
            end
            serviceStep = value.serviceStep
            servicePermille, fieldError = Runtime.integerInRange(
                value.servicePermille, 0, 1000, label .. ".servicePermille")
            if servicePermille == nil then return nil, fieldError end
        elseif value.servicePermille ~= nil then
            return nil, label .. ".servicePermille requires an active serviceStep"
        end
        if value.paper ~= nil and (value.candidates ~= nil or value.genericSheets ~= nil) then
            return nil, label .. " cannot include load candidates while paper is present"
        end
        if serviceStep and value.paper ~= nil then
            return nil, label .. " cannot service the cutter while paper is present"
        end
        if serviceStep and (value.loaded ~= false or value.step ~= "idle"
            or value.candidates ~= nil or value.genericSheets ~= nil)
        then
            return nil, label .. " active service requires an idle unloaded cutter without load candidates"
        end
        local normalized = {
            runtimeRevision = runtimeRevision,
            step = value.step,
            phasePermille = phasePermille,
            loaded = value.loaded,
            clamp = value.clamp,
            clampPermille = clampPermille,
            bladePermille = bladePermille,
            barrierClear = value.barrierClear,
            emergencyStopped = value.emergencyStopped,
            gaugeCentiInch = gaugeCentiInch,
            programIndex = programIndex,
            memoryCentiInch = memoryCentiInch,
        }
        if serviceStep then
            normalized.serviceStep = serviceStep
            normalized.servicePermille = servicePermille
        end
        if value.paper ~= nil then
            normalized.paper, fieldError = Runtime.normalizeCutterPaper(value.paper, label .. ".paper")
            if not normalized.paper then return nil, fieldError end
        end
        if value.candidates ~= nil then
            normalized.candidates, fieldError = Runtime.normalizeCutterCandidates(
                value.candidates, label .. ".candidates")
            if not normalized.candidates then return nil, fieldError end
        end
        if value.genericSheets ~= nil then
            normalized.genericSheets, fieldError = Runtime.integerInRange(
                value.genericSheets, 0, 100000, label .. ".genericSheets")
            if normalized.genericSheets == nil then return nil, fieldError end
        end
        local serviceFields = {
            "serviceView", "serviceTool", "serviceItems", "centralInstalled",
            "gearInspected", "gearLevelPermille",
        }
        if serviceStep == "lubricate" then
            for _, field in ipairs(serviceFields) do
                if value[field] == nil then return nil, label .. "." .. field .. " is required" end
            end
            normalized.serviceView, fieldError = Runtime.integerInRange(
                value.serviceView, 1, 5, label .. ".serviceView")
            if not normalized.serviceView then return nil, fieldError end
            normalized.serviceTool, fieldError = Runtime.integerInRange(
                value.serviceTool, 1, 4, label .. ".serviceTool")
            if not normalized.serviceTool then return nil, fieldError end
            normalized.serviceItems, fieldError = Runtime.normalizeCutterServiceItems(
                value.serviceItems, label .. ".serviceItems")
            if not normalized.serviceItems then return nil, fieldError end
            for _, item in ipairs(normalized.serviceItems) do
                local matchesView = (normalized.serviceView == 1 and item.itemIndex <= 2)
                    or (normalized.serviceView == 2 and item.itemIndex >= 3 and item.itemIndex <= 4)
                    or (normalized.serviceView == 3 and item.itemIndex >= 5 and item.itemIndex <= 6)
                    or (normalized.serviceView == 5 and item.itemIndex == 7)
                if not matchesView then
                    return nil, label .. ".serviceItems contains a point outside serviceView"
                end
            end
            if type(value.centralInstalled) ~= "boolean" then
                return nil, label .. ".centralInstalled must be boolean"
            end
            if type(value.gearInspected) ~= "boolean" then
                return nil, label .. ".gearInspected must be boolean"
            end
            normalized.centralInstalled = value.centralInstalled
            normalized.gearInspected = value.gearInspected
            normalized.gearLevelPermille, fieldError = Runtime.integerInRange(
                value.gearLevelPermille, 0, 1000, label .. ".gearLevelPermille")
            if normalized.gearLevelPermille == nil then return nil, fieldError end
        else
            for _, field in ipairs(serviceFields) do
                if value[field] ~= nil then
                    return nil, label .. "." .. field .. " is only valid during lubrication"
                end
            end
        end
        local bladeActive = serviceStep == "blade_bolts"
            or serviceStep == "blade_lift" or serviceStep == "blade_sleeve"
        if bladeActive then
            normalized.bladeBoltsDone, fieldError = Runtime.integerInRange(
                value.bladeBoltsDone, 0, 4, label .. ".bladeBoltsDone")
            if normalized.bladeBoltsDone == nil then return nil, fieldError end
            if (serviceStep == "blade_lift" or serviceStep == "blade_sleeve")
                and normalized.bladeBoltsDone ~= 4
            then
                return nil, label .. ".bladeBoltsDone must be 4 after bolt removal"
            elseif serviceStep == "blade_bolts" and normalized.bladeBoltsDone >= 4 then
                return nil, label .. ".blade_bolts must advance after the fourth bolt"
            end
        elseif value.bladeBoltsDone ~= nil then
            return nil, label .. ".bladeBoltsDone is only valid during blade service"
        end
        if value.bladeBoltMask ~= nil then
            if not bladeActive then return nil, "Blade display requires blade service." end
            normalized.bladeBoltMask, fieldError = Runtime.integerInRange(value.bladeBoltMask,0,15,label..".bladeBoltMask")
            if normalized.bladeBoltMask == nil then return nil,fieldError end
            local count=0
            for index=0,3 do count=count+math.floor(normalized.bladeBoltMask/2^index)%2 end
            if count~=normalized.bladeBoltsDone then return nil,"Blade display count mismatch." end
        end
        return normalized
    end
end

return Component
