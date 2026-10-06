local Catalog={}
Catalog.profiles={
    {name="Radio Cat",character="cat-worker",cutterSkill=65,attention=75,reliability=90,requestedWage=2200,minimumWage=2000},
    {name="Tinker Fox",character="tinker-fox-worker",cutterSkill=76,attention=80,reliability=86,requestedWage=2300,minimumWage=2100},
    {name="Ferret Engineer",character="ferret-engineer-worker",cutterSkill=84,attention=88,reliability=92,requestedWage=2400,minimumWage=2200},
}
function Catalog.valid(character)
    for _,p in ipairs(Catalog.profiles) do if p.character==character then return true end end
    return false
end
function Catalog.character(entry)
    local record=type(entry.worker)=="table" and entry.worker or type(entry.application)=="table" and entry.application or nil
    return record and record.character or "cat-worker"
end
function Catalog.action(character,prefix,x,y)
    local animation=require("src.character_animation")
    if character=="ferret-engineer-worker" then
        if prefix=="walk" then return animation.directionalWalkAction(x,y) end
        return animation.directionalIdleAction(x,y)
    end
    return animation.authoredAction(prefix,x,y),1
end
return Catalog
