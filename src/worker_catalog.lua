local Catalog={}
Catalog.motion={speed=72,acceleration=600,walkPixelsPerFrame=13,
    gaitSpeedMultipliers={.96,.94,1.04,1.06,.96,.94,1.04,1.06},
    gaitAccelerationMultipliers={.92,.90,1.08,1.10,.92,.90,1.08,1.10}}
local WORK_ACTIONS={
    polar_115="work_cutter",
    heidelberg_10x15="work_press",
    skid_wrapper="work_wrapping",
}
Catalog.profiles={
    {character="cat-worker",cutterSkill=65,pressSkill=0,wrappingSkill=25,attention=75,reliability=90,requestedWage=2200,minimumWage=2000,shiftPreference="day"},
    {character="tinker-fox-worker",cutterSkill=76,pressSkill=45,wrappingSkill=65,attention=80,reliability=86,requestedWage=2300,minimumWage=2100,shiftPreference="night"},
    {character="ferret-engineer-worker",cutterSkill=84,pressSkill=80,wrappingSkill=80,attention=88,reliability=92,requestedWage=2400,minimumWage=2200,shiftPreference="flexible"},
}
local firstNames={
    "Alder","Ansel","Beryl","Bram","Briony","Cal","Calla","Clover","Corin","Cricket",
    "Della","Ellery","Fern","Fennel","Gale","Hazel","Hollis","Ida","Jasper","Juniper",
    "Kestrel","Kit","Lark","Mabel","Marlow","Moss","Nettle","Nori","Olive","Orla",
    "Otis","Pippa","Pip","Quincy","Remy","Rue","Silas","Tansy","Tilda","Wren",
}
local familyNames={
    "Bellwether","Brasswhisk","Brightpaper","Brushwell","Cardwell","Chatterwick","Coppercoil","Copperspool",
    "Crinkletail","Cutler","Dovetail","Dryden","Everpress","Fairpage","Feltwhistle","Folden",
    "Foxglove","Gearhart","Goldenleaf","Goodpaper","Granger","Inkblot","Inkwell","Labelle",
    "Lockwood","Millwright","Paperfield","Quickquill","Reamwell","Rivetpaw","Sable","Shears",
    "Spindle","Staple","Swiftpaw","Tapeley","Thimble","Tuckwell","Underleaf","Whetstone",
}
local legacyNames={ ["radio cat"]=true,["tinker fox"]=true,["ferret engineer"]=true }
function Catalog.isLegacyName(name)
    return type(name)=="string" and legacyNames[name:lower()]==true
end
function Catalog.generatedName(identity,usedNames)
    local sequence=tonumber(tostring(identity or ""):match("(%d+)$")) or 1
    sequence=math.max(1,math.floor(sequence))
    local combinations=#firstNames*#familyNames
    local start=((sequence-1)*173)%combinations
    for offset=0,combinations-1 do
        local slot=(start+offset)%combinations
        local first=firstNames[math.floor(slot/#familyNames)+1]
        local family=familyNames[slot%#familyNames+1]
        local name=first.." "..family
        if not usedNames or not usedNames[name:lower()] then return name end
    end
    return firstNames[(sequence-1)%#firstNames+1].." "
        ..familyNames[(sequence-1)%#familyNames+1].." "..sequence
end
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
function Catalog.workAction(entry)
    local worker=type(entry) == "table" and entry.worker or nil
    local assignment=type(worker) == "table" and worker.assignment or nil
    local actor=entry and entry.actor
    local liveActions={[4]="work_cutter",[5]="work_wrapping",[6]="work_press",
        [24]="work_press",[25]="work_press",[26]="work_wrapping"}
    if actor and liveActions[actor.speechCode] then return liveActions[actor.speechCode] end
    if worker and worker.training then
        return ({cutter="work_cutter",press="work_press",wrapping="work_wrapping"})[worker.training.skill]
    end
    return type(assignment) == "table" and WORK_ACTIONS[assignment.machineModel] or nil
end
function Catalog.pushAction(character,x,y)
    if not Catalog.valid(character) then return nil end
    return require("src.character_animation").directionalPalletJackPushAction(x,y)
end
return Catalog
