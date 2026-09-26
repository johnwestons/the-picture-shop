local Resource = {}

local modelByBase = {
    cutter = "polar_115",
    skid_wrapper = "skid_wrapper",
    windmill = "heidelberg_10x15",
}

function Resource.parse(resourceId)
    if type(resourceId) ~= "string" then return nil end
    if modelByBase[resourceId] then return resourceId, nil end
    local base, machineId = resourceId:match("^([a-z_]+):(MCH%-%d+)$")
    if modelByBase[base] and #resourceId <= 64 then return base, machineId end
end

function Resource.model(base)
    return modelByBase[base]
end

function Resource.forUnit(base, machineId)
    if not modelByBase[base] then return nil end
    if type(machineId) ~= "string" or not machineId:match("^MCH%-%d+$") then
        return base
    end
    return base .. ":" .. machineId
end

return Resource
