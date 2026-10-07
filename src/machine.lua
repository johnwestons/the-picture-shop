local PaperWork = require("src.paper_work")
local Config = require("src.config")
local Jobs = require("src.jobs")
local PalletState = require("src.pallet_state")
local Procurement = require("src.procurement")
local MachineFleet = require("src.machine_fleet")
local BusinessCalendar = require("src.business_calendar")
local Reputation = require("src.reputation")

local function createMachine(machineId)
    local Context = {
        machineId = machineId,
        PaperWork = PaperWork,
        Config = Config,
        Jobs = Jobs,
        PalletState = PalletState,
        Procurement = Procurement,
        MachineFleet = MachineFleet,
        BusinessCalendar = BusinessCalendar,
        Reputation = Reputation,
    }
    require("src.machine.cutter.state").run(Context)
    require("src.machine.cutter.gauge").run(Context)
    require("src.machine.cutter.handling").run(Context)
    require("src.machine.cutter.cutting").run(Context)
    require("src.machine.cutter.network").run(Context)
    return Context.Machine

end

local primary = createMachine(nil)
local instances = {}
local selectedId
local primaryId = "MCH-0001"
local exported = {}

local function instance(machineId)
    if not machineId or machineId == primaryId then return primary end
    if not instances[machineId] then
        instances[machineId] = createMachine(machineId)
        instances[machineId].outputResolver = primary.outputResolver
        instances[machineId].multiplayerSingleControl = primary.multiplayerSingleControl
    end
    return instances[machineId]
end

function exported.select(machineId, state)
    selectedId = machineId
    return instance(machineId)
end

function exported.forId(machineId) return instance(machineId) end

function exported.updateAll(dt, state)
    local units = MachineFleet.installedUnits(state, "polar_115")
    local durable = false
    for _, unit in ipairs(units) do
        MachineFleet.withUnit(state, unit.id, function()
            if instance(unit.id).update(dt, state) then durable = true end
        end)
    end
    return durable
end

function exported.setOutputResolver(resolver)
    primary.setOutputResolver(resolver)
    for _, unit in pairs(instances) do unit.setOutputResolver(resolver) end
end

function exported.setMultiplayerSingleControl(enabled)
    primary.setMultiplayerSingleControl(enabled)
    for _, unit in pairs(instances) do unit.setMultiplayerSingleControl(enabled) end
end

function exported.reset(state)
    primary.reset(state)
    instances = {}
    selectedId = nil
end

function exported.validateSale(item, cutterLeaseActive)
    return instance(item and item.id).validateSale(item, cutterLeaseActive)
end

return setmetatable(exported, {
    __index = function(_, key) return instance(selectedId)[key] end,
    __newindex = function(_, key, value) instance(selectedId)[key] = value end,
})
