-- Wrapper runtime, pallets, and maintenance validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizeWorkshopWrapperRuntimeFields(value, label)
        if type(value.step) ~= "string" or not Runtime.WORKSHOP_WRAPPER_STEPS[value.step] then
            return nil, label .. ".step is invalid"
        end
        local cycleTime, fieldError = Runtime.numberInRange(
            value.cycleTime, 0.01, Runtime.MAX_WORKSHOP_CYCLE_TIME, label .. ".cycleTime")
        if not cycleTime then return nil, fieldError end
        local progress
        progress, fieldError = Runtime.numberInRange(
            value.progress, 0, Runtime.MAX_WORKSHOP_CYCLE_TIME, label .. ".progress")
        if progress == nil then return nil, fieldError end
        if progress > cycleTime then return nil, label .. ".progress exceeds cycleTime" end
        local selectedPalletId
        if value.selectedPalletId ~= nil then
            selectedPalletId, fieldError = Runtime.token(
                value.selectedPalletId, Runtime.MAX_TOKEN_BYTES, label .. ".selectedPalletId")
            if not selectedPalletId then return nil, fieldError end
        end
        local palletId
        if value.palletId ~= nil then
            palletId, fieldError = Runtime.token(value.palletId, Runtime.MAX_TOKEN_BYTES, label .. ".palletId")
            if not palletId then return nil, fieldError end
        end
        if value.step == "idle" then
            if progress ~= 0 or palletId ~= nil then
                return nil, label .. " idle runtime cannot carry progress or an active pallet"
            end
        elseif value.step == "wrapping" then
            if not palletId or selectedPalletId ~= palletId or progress >= cycleTime then
                return nil, label .. " wrapping runtime is inconsistent"
            end
        elseif not palletId or selectedPalletId ~= palletId or progress ~= cycleTime then
            return nil, label .. " finished runtime is inconsistent"
        end
        return {
            step = value.step,
            progress = progress,
            cycleTime = cycleTime,
            selectedPalletId = selectedPalletId,
            palletId = palletId,
        }
    end

    function Runtime.normalizeWorkshopPallets(value, label)
        if not Runtime.Codec.isArray(value) then return nil, label .. " must be an array" end
        if #value > 5 then return nil, label .. " must contain at most 5 pallets" end
        local pallets, seen = {}, {}
        for index = 1, #value do
            local palletLabel = label .. "[" .. index .. "]"
            local valid, shapeError = Runtime.shape(value[index], palletLabel,
                { "palletId", "jobLabel", "packaging", "distance" })
            if not valid then return nil, shapeError end
            local palletId, fieldError = Runtime.token(
                value[index].palletId, Runtime.MAX_TOKEN_BYTES, palletLabel .. ".palletId")
            if not palletId then return nil, fieldError end
            if seen[palletId] then return nil, label .. " contains a duplicate palletId" end
            seen[palletId] = true
            local jobLabel
            jobLabel, fieldError = Runtime.printableString(
                value[index].jobLabel, 1, Runtime.MAX_WORKSHOP_VIEW_TEXT_BYTES,
                palletLabel .. ".jobLabel")
            if not jobLabel then return nil, fieldError end
            local packaging
            packaging, fieldError = Runtime.workshopPackaging(
                value[index].packaging, palletLabel .. ".packaging")
            if not packaging then return nil, fieldError end
            local distance
            distance, fieldError = Runtime.numberInRange(
                value[index].distance, 0, Runtime.MAX_WORKSHOP_DISTANCE, palletLabel .. ".distance")
            if distance == nil then return nil, fieldError end
            pallets[#pallets + 1] = {
                palletId = palletId,
                jobLabel = jobLabel,
                packaging = packaging,
                distance = distance,
            }
        end
        return Runtime.Codec.array(pallets)
    end

    Runtime.WRAPPER_SERVICE_FIELDS = {
        "serviceStep", "serviceTaskId", "serviceTaskIndex", "serviceTaskCount",
        "servicePhase", "serviceTargetCount", "serviceAttempts", "serviceMisses",
        "servicePermille",
    }

    function Runtime.normalizeWrapperService(value, runtime, pallets, label)
        if value.serviceStep == nil then
            for _, field in ipairs(Runtime.WRAPPER_SERVICE_FIELDS) do
                if field ~= "serviceStep" and value[field] ~= nil then
                    return nil, label .. "." .. field .. " requires an active serviceStep"
                end
            end
            return runtime
        end
        if value.serviceStep ~= "task" then
            return nil, label .. ".serviceStep is invalid"
        end
        if runtime.step ~= "idle" or runtime.progress ~= 0
            or runtime.selectedPalletId ~= nil or runtime.palletId ~= nil or #pallets ~= 0
        then
            return nil, label .. " active service requires an idle wrapper with an empty turntable"
        end
        local targetCount = Runtime.WORKSHOP_WRAPPER_SERVICE_TASKS[value.serviceTaskId]
        if not targetCount then return nil, label .. ".serviceTaskId is invalid" end
        local fieldError
        runtime.serviceStep = "task"
        runtime.serviceTaskId = value.serviceTaskId
        runtime.serviceTaskIndex, fieldError = Runtime.integerInRange(
            value.serviceTaskIndex, 1, 4, label .. ".serviceTaskIndex")
        if not runtime.serviceTaskIndex then return nil, fieldError end
        runtime.serviceTaskCount, fieldError = Runtime.integerInRange(
            value.serviceTaskCount, 4, 4, label .. ".serviceTaskCount")
        if not runtime.serviceTaskCount then return nil, fieldError end
        runtime.servicePhase, fieldError = Runtime.integerInRange(
            value.servicePhase, 1, targetCount, label .. ".servicePhase")
        if not runtime.servicePhase then return nil, fieldError end
        runtime.serviceTargetCount, fieldError = Runtime.integerInRange(
            value.serviceTargetCount, targetCount, targetCount, label .. ".serviceTargetCount")
        if not runtime.serviceTargetCount then return nil, fieldError end
        runtime.serviceAttempts, fieldError = Runtime.integerInRange(
            value.serviceAttempts, 0, 9999, label .. ".serviceAttempts")
        if runtime.serviceAttempts == nil then return nil, fieldError end
        runtime.serviceMisses, fieldError = Runtime.integerInRange(
            value.serviceMisses, 0, runtime.serviceAttempts, label .. ".serviceMisses")
        if runtime.serviceMisses == nil then return nil, fieldError end
        if runtime.serviceAttempts < runtime.servicePhase - 1 then
            return nil, label .. ".serviceAttempts is inconsistent with servicePhase"
        end
        runtime.servicePermille, fieldError = Runtime.integerInRange(
            value.servicePermille, 0, 999, label .. ".servicePermille")
        if runtime.servicePermille == nil then return nil, fieldError end
        return runtime
    end

    function Runtime.normalizeWorkshopWrapperRuntime(value, label)
        local valid, shapeError = Runtime.shape(value, label,
            { "step", "progress", "cycleTime", "pallets" },
            { "selectedPalletId", "palletId", "serviceStep", "serviceTaskId",
                "serviceTaskIndex", "serviceTaskCount", "servicePhase",
                "serviceTargetCount", "serviceAttempts", "serviceMisses",
                "servicePermille" })
        if not valid then return nil, shapeError end
        local runtime, fieldError = Runtime.normalizeWorkshopWrapperRuntimeFields(value, label)
        if not runtime then return nil, fieldError end
        local pallets
        pallets, fieldError = Runtime.normalizeWorkshopPallets(value.pallets, label .. ".pallets")
        if not pallets then return nil, fieldError end
        runtime.pallets = pallets
        return Runtime.normalizeWrapperService(value, runtime, pallets, label)
    end

    function Runtime.normalizeWrapperWorkshopView(value, label)
        local valid, shapeError = Runtime.shape(value, label, {
            "step", "progress", "cycleTime", "plasticWrapRolls", "plasticWrapUses", "pallets",
        }, { "selectedPalletId", "palletId", "serviceStep", "serviceTaskId",
            "serviceTaskIndex", "serviceTaskCount", "servicePhase",
            "serviceTargetCount", "serviceAttempts", "serviceMisses",
            "servicePermille" })
        if not valid then return nil, shapeError end
        local runtime, fieldError = Runtime.normalizeWorkshopWrapperRuntimeFields(value, label)
        if not runtime then return nil, fieldError end
        local plasticWrapRolls
        plasticWrapRolls, fieldError = Runtime.integerInRange(
            value.plasticWrapRolls, 0, Runtime.MAX_WORKSHOP_INVENTORY, label .. ".plasticWrapRolls")
        if plasticWrapRolls == nil then return nil, fieldError end
        local plasticWrapUses
        plasticWrapUses, fieldError = Runtime.integerInRange(
            value.plasticWrapUses, 0, Runtime.MAX_WORKSHOP_INVENTORY, label .. ".plasticWrapUses")
        if plasticWrapUses == nil then return nil, fieldError end
        local pallets
        pallets, fieldError = Runtime.normalizeWorkshopPallets(value.pallets, label .. ".pallets")
        if not pallets then return nil, fieldError end
        runtime.plasticWrapRolls = plasticWrapRolls
        runtime.plasticWrapUses = plasticWrapUses
        runtime.pallets = pallets
        return Runtime.normalizeWrapperService(value, runtime, pallets, label)
    end
end

return Component
