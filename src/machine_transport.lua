-- Resolve the exact owned machine without replacing the original machine's pose.
local Fleet = require("src.machine_fleet")
local Transport = {}
Transport.models = { cutter = "polar_115", wrapper = "skid_wrapper", windmill = "heidelberg_10x15" }
Transport.order = { "cutter", "wrapper", "windmill" }

function Transport.resolve(state, kind, machineId)
    local model = Transport.models[kind]
    if not model then return nil end
    local unit
    if machineId then
        for _, owned in ipairs(state.machines and state.machines.items or {}) do
            if owned.id == machineId then unit = owned; break end
        end
    else unit = Fleet.installedUnits(state, model)[1] end
    if not unit or unit.modelId ~= model or unit.status ~= "installed" then return nil end
    return unit, unit.world or state[kind]
end

function Transport.view(state, kind, unit)
    if not unit or not unit.world then return state end
    return setmetatable({ [kind] = unit.world, _operatingMachineId = unit.id }, { __index = state })
end

function Transport.active(state)
    if type(state) ~= "table" then return nil end
    for _, kind in ipairs(Transport.order) do
        if state[kind] and state[kind].moving then return kind, state[kind] end
    end
    for _, unit in ipairs(state.machines and state.machines.items or {}) do
        if unit.status == "installed" and unit.world and unit.world.moving then
            for kind, model in pairs(Transport.models) do
                if unit.modelId == model then return kind, unit.world, unit end
            end
        end
    end
end

function Transport.remember(state, kind, unit)
    state._machinePoseUnits = state._machinePoseUnits or {}
    state._machinePoseUnits[kind] = unit.world and unit.id or nil
end

return Transport
