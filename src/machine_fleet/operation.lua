-- Machine selection, installation, use, and maintenance.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Fleet.byId(state, machineId)
        for _, item in ipairs(Runtime.Fleet.ensure(state).items) do
            if item.id == machineId then return item end
        end
    end

    function Runtime.Fleet.installed(state, modelId, machineId)
        local first
        local activeId = machineId or state._operatingMachineId
            or ((state.screen == "machine" or state.screen == "press") and state.machineId)
        for _, item in ipairs(Runtime.Fleet.ensure(state).items) do
            if item.modelId == modelId and item.status == "installed" then
                if activeId == item.id then return item end
                first = first or item
            end
        end
        return machineId == nil and first or nil
    end

    function Runtime.Fleet.withUnit(state, machineId, callback)
        local previous = state._operatingMachineId
        state._operatingMachineId = machineId
        local result = { pcall(callback) }
        state._operatingMachineId = previous
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2)
    end

    function Runtime.Fleet.installedUnits(state, modelId)
        local units = {}
        for _, item in ipairs(Runtime.Fleet.ensure(state).items) do
            if item.status == "installed" and (modelId == nil or item.modelId == modelId) then
                units[#units + 1] = item
            end
        end
        return units
    end

    function Runtime.Fleet.isInstalled(state, modelId)
        return Runtime.Fleet.installed(state, modelId) ~= nil
    end

    function Runtime.Fleet.canOperate(state, modelId, machineId)
        local item = Runtime.Fleet.installed(state, modelId, machineId)
        if not item then return false, "This machine is not installed in the shop." end
        if modelId == "polar_115" and item.maintenance.cutter.bladeRemoved then
            return false, "The cutter blade is removed for sharpening. Reinstall it before production."
        end
        if modelId == "heidelberg_10x15" and item.variables.safetyCircuit < 20 then
            return false, "The Windmill safety circuit must be serviced before production."
        end
        local condition = Runtime.Fleet.condition(item)
        if condition < 15 then
            return false, item.name .. " is in critical condition and must be maintained before it can run."
        end
        return true, item
    end

    function Runtime.Fleet.recordUse(state, modelId, cycles, machineId)
        local item = Runtime.Fleet.installed(state, modelId, machineId)
        local model = item and Runtime.definition(item.modelId)
        if not item or not model then return false, "No installed machine can receive wear." end
        cycles = math.max(0, tonumber(cycles) or 1)
        for componentId, component in pairs(model.components) do
            item.variables[componentId] = Runtime.clamp(item.variables[componentId] - component.wear * cycles, 0, 100)
        end
        item.cycles = item.cycles + cycles
        item.operatingMinutes = item.operatingMinutes + cycles * (modelId == "heidelberg_10x15" and 20 or 0.25)
        if modelId == "polar_115" and item.maintenance.cutter then
            local cutter = item.maintenance.cutter
            cutter.backgaugeLubrication = Runtime.clamp(cutter.backgaugeLubrication - cycles * 0.30, 0, 100)
            cutter.guideLubrication = Runtime.clamp(cutter.guideLubrication - cycles * 0.24, 0, 100)
            cutter.crankLubrication = Runtime.clamp(cutter.crankLubrication - cycles * 0.20, 0, 100)
            cutter.gearOilLevel = Runtime.clamp(cutter.gearOilLevel - cycles * 0.00035, 0, 1)
        end
        item.condition = Runtime.calculateCondition(item)
        return true, item
    end

    function Runtime.Fleet.maintenancePlan(state, machineId)
        local item = Runtime.Fleet.byId(state, machineId)
        local model = item and Runtime.definition(item.modelId)
        if not item or not model then return nil, "Machine not found." end
        local tasks = {}
        for componentId, component in pairs(model.components) do
            tasks[#tasks + 1] = {
                id = componentId,
                label = component.serviceTask,
                componentLabel = component.label,
                health = item.variables[componentId],
                -- Future sprite minigames can bind a moving/interactive scene to
                -- this stable component id without changing the save contract.
                sceneId = item.modelId .. ":" .. componentId,
            }
        end
        table.sort(tasks, function(a, b) return a.health < b.health end)
        return { machineId = item.id, modelId = item.modelId, tasks = tasks }
    end

    function Runtime.Fleet.completeMaintenance(state, machineId, taskScores)
        local item = Runtime.Fleet.byId(state, machineId)
        local model = item and Runtime.definition(item.modelId)
        if not item or not model then return false, "Machine not found." end
        local stock = state.inventory and state.inventory.stock or {}
        if (stock.maintenance_kit or 0) < 1 then return false, "A machine maintenance kit is required." end
        local consumed, consumptionError = Runtime.Procurement.consumePhysicalProduct(state, "maintenance_kit", 1, {allowAbstract=true})
        if not consumed then return false, consumptionError end
        local total, count = 0, 0
        for componentId in pairs(model.components) do
            local score = type(taskScores) == "table" and tonumber(taskScores[componentId]) or nil
            score = Runtime.clamp(score or 0, 0, 1)
            total, count = total + score, count + 1
            item.variables[componentId] = Runtime.clamp(item.variables[componentId] + 25 + score * 45, 0, 100)
        end
        local quality = count > 0 and total / count or 0
        stock.maintenance_kit = stock.maintenance_kit - 1
        item.maintenance.serviceCount = item.maintenance.serviceCount + 1
        item.maintenance.lastServiceAt = os.time()
        item.maintenance.lastServiceQuality = Runtime.rounded(quality * 100) / 100
        item.condition = Runtime.calculateCondition(item)
        return true, item
    end
end

return Component
