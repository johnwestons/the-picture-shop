-- Sale eligibility, loaded work, and active-control guards.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.machineOwnsCutterPallet(state, item)
        if item.modelId ~= "polar_115" then return false end
        for _, job in ipairs(state.jobs and state.jobs.active or {}) do
            for _, pallet in ipairs(job.pallets or {}) do
                if pallet.location == "at_cutter"
                    and (pallet.cutterMachineId or "MCH-0001") == item.id then return true end
            end
        end
        return false
    end

    function Runtime.installedWindmillIsLoaded(state, item)
        if item.modelId ~= "heidelberg_10x15" or item.status ~= "installed" then return false end
        local placement = item.world or (type(state.windmill) == "table" and state.windmill or {})
        local process = type(placement.process) == "table" and placement.process or {}
        return process.palletId ~= nil
    end

    function Runtime.printWorkNeedsWindmill(state)
        for _, job in ipairs(state.jobs and state.jobs.active or {}) do
            if type(job.press) == "table" then
                local pallets = type(job.pallets) == "table" and job.pallets or {}
                if #pallets == 0 then return true end
                for _, pallet in ipairs(pallets) do
                    if type(pallet.press) ~= "table" or pallet.press.status ~= "complete" then
                        return true
                    end
                end
            end
        end
        return false
    end

    function Runtime.hasStoredReplacement(fleet, item)
        for _, candidate in ipairs(fleet.items) do
            if candidate ~= item and candidate.modelId == item.modelId
                and (candidate.status == "stored" or candidate.status == "installed") then
                return true
            end
        end
        return false
    end

    function Runtime.Fleet.sell(state, machineId, channel)
        local fleet = Runtime.Fleet.ensure(state)
        local foundIndex, item
        for index, candidate in ipairs(fleet.items) do
            if candidate.id == machineId then foundIndex, item = index, candidate; break end
        end
        if not item then return false, "That machine is no longer owned by the shop." end
        local pose = item.world or state[Runtime.definition(item.modelId).placementKey]
        if pose and pose.moving then return false, "Place the moving machine before listing it for sale." end
        local hasLien, loan = require("src.credit").hasLien(state, item.id)
        if hasLien then
            return false, string.format("Pay off machine loan %s before selling this financed machine.", loan.id)
        end
        if Runtime.saleGuard then
            local allowed, reason = Runtime.saleGuard(state, item)
            if allowed == false then
                return false, tostring(reason or "That machine is currently in use.")
            end
        end
        if Runtime.machineOwnsCutterPallet(state, item) then
            return false, "Unload the cutter before listing it for sale."
        end
        if Runtime.installedWindmillIsLoaded(state, item) then
            return false, "Unload the Windmill before listing it for sale."
        end
        if item.modelId == "heidelberg_10x15" and item.status == "installed"
            and Runtime.printWorkNeedsWindmill(state) and not Runtime.hasStoredReplacement(fleet, item)
        then
            return false, "Finish the active print work or keep a replacement Windmill before selling this press."
        end
        local value = Runtime.Fleet.resaleValue(item, channel)
        local wasInstalled = item.status == "installed"
        table.remove(fleet.items, foundIndex)
        if wasInstalled then
            for _, candidate in ipairs(fleet.items) do
                if candidate.modelId == item.modelId and candidate.status == "stored" then
                    candidate.status = "installed"
                    break
                end
            end
        end
        state.money = (state.money or 0) + value
        return true, { machine = item, price = value, channel = channel == "dealer" and "dealer" or "online" }
    end

    function Runtime.Fleet.setSaleGuard(guard)
        local previous = Runtime.saleGuard
        Runtime.saleGuard = type(guard) == "function" and guard or nil
        return previous
    end
end

return Component
