-- Arcade loadouts live only in the session; no campaign inventory or save API.
local Items={}
function Items.enabled() return false end
function Items.condition(data,name) return (data.weaponDurability or {})[name] or 100 end
function Items.setCondition(data,name,value)
    data.weaponDurability=data.weaponDurability or {};data.weaponDurability[name]=value
end
function Items.weapons(data,catalog)
    local result={}
    for _,name in ipairs(catalog.weaponProgression) do
        result[#result+1]={name=name,key=name,id=name,durability=Items.condition(data,name)}
    end
    return result
end
function Items.selection(data,name,catalog)
    for _,item in ipairs(Items.weapons(data,catalog)) do if item.name==name then return item end end
end
return Items
