-- Installed-machine resource registration.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.withWorkshopUnit(base, machineId, resourceId, callback)
        local previousResource = Runtime.state._activeWorkshopResourceId
        Runtime.state._activeWorkshopResourceId = resourceId
        if base == "cutter" then Runtime.Machine.select(machineId, Runtime.state)
        elseif base == "skid_wrapper" then Runtime.Wrapper.select(machineId, Runtime.state) end
        local results = { pcall(function()
            return Runtime.MachineFleet.withUnit(Runtime.state, machineId, callback)
        end) }
        Runtime.state._activeWorkshopResourceId = previousResource
        if base == "cutter" then Runtime.Machine.select(Runtime.state._localWorkshopMachineId, Runtime.state)
        elseif base == "skid_wrapper" then Runtime.Wrapper.select(Runtime.state._localWorkshopMachineId, Runtime.state) end
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2)
    end

    function Runtime.registerInstalledMachineResources(authority)
        if not authority then return end
        for _, base in ipairs({ "cutter", "skid_wrapper", "windmill" }) do
            for _, unit in ipairs(Runtime.MachineFleet.installedUnits(Runtime.state, Runtime.MachineResource.model(base))) do
                local machineId = unit.id
                local resourceId = Runtime.MachineResource.forUnit(base, machineId)
                if not authority.resources[resourceId] then
                    local source = authority.resources[base]
                    local spec = {}
                    for key, value in pairs(source) do spec[key] = value end
                    for _, callbackName in ipairs({ "canAcquire", "onAcquire", "onRelease" }) do
                        local callback = source[callbackName]
                        if callback then
                            spec[callbackName] = function(...)
                                local arguments = { ... }
                                local count = select("#", ...)
                                return Runtime.withWorkshopUnit(base, machineId, resourceId, function()
                                    return callback(unpack(arguments, 1, count))
                                end)
                            end
                        end
                    end
                    spec.commands = {}
                    for action, command in pairs(source.commands or {}) do
                        local perform = command.perform
                        local wrapped = {}
                        for key, value in pairs(command) do wrapped[key] = value end
                        wrapped.perform = function(...)
                            local arguments = { ... }
                            local count = select("#", ...)
                            return Runtime.withWorkshopUnit(base, machineId, resourceId, function()
                                return perform(unpack(arguments, 1, count))
                            end)
                        end
                        spec.commands[action] = wrapped
                    end
                    assert(authority:registerResource(resourceId, spec))
                end
            end
        end
    end
end

return Component
