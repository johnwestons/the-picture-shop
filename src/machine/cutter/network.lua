-- Applying bounded cutter replicas and updating live control fields.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    function Context.Machine.applyNetworkView(view)
        if type(view) ~= "table" then return false end
        local revision = tonumber(view.runtimeRevision)
        if not revision or revision < (tonumber(Context.Machine.runtimeRevision) or 0) then return false end
        Context.Machine.runtimeRevision = revision
        Context.Machine.step = tostring(view.step)
        Context.Machine.loaded = view.loaded == true
        Context.Machine.clamp = view.clamp == true
        Context.Machine.clampProgress = (tonumber(view.clampPermille) or 0) / 1000
        Context.Machine.bladeProgress = (tonumber(view.bladePermille) or 0) / 1000
        Context.Machine.barrierClear = view.barrierClear == true
        Context.Machine.emergencyStopped = view.emergencyStopped == true
        Context.Machine.gauge = (tonumber(view.gaugeCentiInch) or 0) / 100
        Context.Machine.programIndex = math.max(1, math.min(4, math.floor(view.programIndex or 1)))
        return true
    end

    function Context.Machine.resetNetworkReplica()
        Context.Machine.runtimeRevision = -1
        Context.Machine.step, Context.Machine.progress, Context.Machine.loaded = "idle", 0, false
        Context.Machine.clamp, Context.Machine.clampProgress, Context.Machine.bladeProgress = false, 0, 0
        Context.Machine.barrierClear, Context.Machine.emergencyStopped = true, false
        Context.Machine.leftDown, Context.Machine.rightDown = false, false
        Context.Machine.paper, Context.Machine.pallet, Context.Machine.job = nil, nil, nil
        Context.Machine._resetResume, Context.Machine._blockedResume = nil, nil
        return true
    end

    function Context.Machine.hasActiveBatch()
        return Context.Machine.paper ~= nil
    end

    function Context.Machine.validateSale(item, cutterLeaseActive)
        if type(item) ~= "table" or item.modelId ~= "polar_115" or item.status ~= "installed" then
            return true
        end
        if cutterLeaseActive == true then
            return false, "Close the active cutter console before listing the cutter for sale."
        end
        if Context.Machine.hasActiveBatch() then
            return false, "Finish or safely unload the cutter batch before listing the cutter for sale."
        end
        return true
    end

    function Context.Machine.paperTooltip() return Context.PaperWork.tooltip(Context.Machine.paper) end
end

return Component
