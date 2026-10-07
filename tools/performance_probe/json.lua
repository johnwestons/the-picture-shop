-- The probe report contains only finite numbers, strings and plain tables.
local function encode(value)
    local kind=type(value)
    if kind=="number" or kind=="boolean" then return tostring(value) end
    if kind=="string" then
        return '"'..value:gsub('[%z\1-\31\\"]',function(character)
            return string.format("\\u%04x",character:byte())
        end)..'"'
    end
    local parts={}
    if #value>0 then
        for _,entry in ipairs(value) do parts[#parts+1]=encode(entry) end
        return "["..table.concat(parts,",").."]"
    end
    for key,entry in pairs(value) do parts[#parts+1]=encode(key)..":"..encode(entry) end
    return "{"..table.concat(parts,",").."}"
end
return encode
