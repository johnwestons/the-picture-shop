local Projection = {}

function Projection.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        if type(item) ~= "function" then result[key] = Projection.copy(item) end
    end
    return result
end

return Projection
