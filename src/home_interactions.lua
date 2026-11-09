-- Classifies home interactions as direct actions or focused appliance screens.
local Interaction={}

local furniture={
    bed={category="action",prompt="lie down",actionLabel="LIE DOWN"},
    chair={category="action",prompt="sit / watch TV",actionLabel="SIT"},
    couch={category="action",prompt="sit / watch TV",actionLabel="SIT"},
    old_tv={category="action",prompt="switch TV on / off",actionLabel="TV"},
    refrigerator={category="inventory",appliance="fridge",prompt="open food storage",actionLabel="OPEN"},
    mini_fridge={category="inventory",appliance="fridge",prompt="open food storage",actionLabel="OPEN"},
    bikeCargo={category="inventory",appliance="bike",prompt="open bike cargo",actionLabel="BIKE"},
    stove={category="minigame",appliance="stove",prompt="open cooking",actionLabel="COOK"},
}

local fixtures={
    sink={category="menu",prompt="choose sink task",actionLabel="USE"},
    bath={category="menu",prompt="choose bathroom task",actionLabel="USE"},
    toilet={category="menu",prompt="choose bathroom task",actionLabel="USE"},
    laundry={category="minigame",appliance="laundry",prompt="open washer",actionLabel="WASHER"},
}

function Interaction.describe(kind,fixture)
    local result=(fixture and fixtures[fixture]) or furniture[kind]
    if result then return result end
    local subject=kind or fixture
    return {category="menu",prompt=(subject and "open "..subject or "view activities"),actionLabel="USE"}
end

function Interaction.appliance(kind,fixture)
    return Interaction.describe(kind,fixture).appliance
end

function Interaction.directCommand(state,player,item)
    if not item or item.location=="storage" or item.location=="carried" then return nil end
    local target="furniture"..item.id
    local resident=require("src.home_residents").get(state,player)
    local activity=resident and resident.activity
    if activity and activity.furnitureId==item.id then
        if item.kind=="bed" and (activity.kind=="nap" or activity.kind=="sleepbed" or activity.kind=="workbed")
            or (item.kind=="chair" or item.kind=="couch")
                and (activity.kind=="sit" or activity.kind=="watch" or activity.kind=="couchrest"
                    or activity.kind=="sleepcouch" or activity.kind=="workcouch") then
            return "cancel"
        end
    end

    if item.kind=="bed" then return "nap:"..target end
    if item.kind=="chair" or item.kind=="couch" then
        for _,row in ipairs(require("src.home_dining").rows(state,player,target)) do
            if row.command:find("^dine:eat:") then return nil end
        end
        local tv=require("src.home_utilities").findTV(state,player,item)
        return (tv and "watch:" or "sit:")..target
    end
    if item.kind=="old_tv" then
        return "object:"..(item.powered and "off" or "on")..":"..item.id..":"..item.revision
    end
end

return Interaction
