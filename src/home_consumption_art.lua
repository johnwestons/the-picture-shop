-- Food presentation follows the same replicated activity clock as the need
-- action. Inventory and need rewards remain owned by home_residents/dining.
local Calendar=require("src.business_calendar")
local Food=require("src.home_food_catalog")
local Catalog=require("src.home_furniture_catalog")
local Held=require("src.home_held_art")
local Art={}

local function elapsed(state,activity)
    return math.max(0,Calendar.absoluteHours(state)-activity.startedAt)
        *Calendar.secondsPerDay(state)/24
end

local function direction(actor,pose)
    if pose and pose.direction then return pose.direction end
    return (actor.facing or 1)<0 and "west" or "east"
end

local function heldFamily(item)
    if item=="sandwich" or item=="good_sandwich" or item=="rough_sandwich" then
        return "sandwich"
    end
    if item=="bottled_drink" then return "bottle" end
    if item=="basic_meal" or item=="cereal" or item=="pizza_slice" or item=="chinese_meal"
        or item=="meal" or item=="good_meal" or item=="plain_meal" then
        return "meal"
    end
end

local function drawFood(state,activity,actor,pose,kind)
    local action= require("src.home_residents").ACTIONS[kind]
    local meal=action and action.item and Food.ITEMS[action.item]
    local sprite=meal and (meal.eatingSprite or meal.sprite)
    local family=action and heldFamily(action.item)
    local dir=direction(actor,pose)
    local angle=Catalog.angle(dir) or 0
    local baseX,baseY=pose and pose.x or actor.x,pose and pose.y or actor.y
    local mouthX,mouthY=baseX+math.cos(angle)*5,baseY-34+math.sin(angle)*2
    local fromX,fromY
    if activity.diningParentId~=nil then
        local serving=require("src.home_dining").pose(state,{parentId=activity.diningParentId,slot=activity.diningSlot})
        if serving then fromX,fromY=serving.x,serving.y-4 end
    end
    if not fromX then
        fromX=baseX+math.cos(angle)*12
        fromY=baseY-(pose and 9 or 16)+math.sin(angle)*3
    end

    local duration=math.max(.001,(action.minutes/60)*Calendar.secondsPerDay(state)/24)
    local t=math.min(1,elapsed(state,activity)/duration)
    local cycle=elapsed(state,activity)%2.35
    local u=cycle/2.35
    if u>=.72 and u<.84 then return true end -- chewing between bites
    if u>=.84 then u=(1-u)/.16 end
    local travel=math.max(0,math.min(1,(u-.12)/.48))
    travel=travel*travel*(3-2*travel)
    local x=fromX+(mouthX-fromX)*travel
    local y=fromY+(mouthY-fromY)*travel-math.sin(travel*math.pi)*3
    local size=family=="meal" and 34 or family=="sandwich" and 32 or 17
    if not (family and Held.draw(family,dir,x,y,size)) then
        require("src.home_food_art").draw(sprite or 14,x,y,17-(t*.8))
    end
    return true
end

function Art.draw(state,activity,actor,pose)
    local kind=activity.kind
    local residents=require("src.home_residents")
    local definition=residents.ACTIONS[kind]
    if definition and definition.item and Food.ITEMS[definition.item] then
        return drawFood(state,activity,actor,pose,kind)
    end
    if kind~="drink" and kind~="cupdrink" then return false end

    local dir=direction(actor,pose);local angle=Catalog.angle(dir) or 0
    local baseX,baseY=pose and pose.x or actor.x,pose and pose.y or actor.y
    local fromX=baseX+math.cos(angle)*12
    local fromY=baseY-(pose and 9 or 16)+math.sin(angle)*3
    local mouthX,mouthY=baseX+math.cos(angle)*5,baseY-34+math.sin(angle)*2
    local seconds=elapsed(state,activity)
    local duration=math.max(.001,((definition and definition.minutes or 2)/60)*Calendar.secondsPerDay(state)/24)
    local t=math.min(1,seconds/duration)
    local cycle=seconds%1.65;local u=cycle/1.65
    local lift=math.max(0,math.min(1,(u-.08)/.34))
    if u>=.58 then lift=math.max(0,1-(u-.58)/.30) end
    lift=lift*lift*(3-2*lift)
    local x=fromX+(mouthX-fromX)*lift
    local y=fromY+(mouthY-fromY)*lift
    local sprite=kind=="cupdrink" and 15 or kind=="drink" and 14 or 16
    local tilt=(u>.31 and u<.65) and math.sin(math.pi*(u-.31)/.34)*.22 or 0
    -- Tap water is an interaction with the sink rather than a bottled item;
    -- keep its existing catalog presentation. Bottled drinks route through
    -- drawFood above and use the directional bottle atlas.
    local family=nil
    local size=(kind=="cupdrink" and 16 or 17)*(1-t*.12)
    if not (family and Held.draw(family,dir,x,y,31,tilt)) then
        require("src.home_food_art").draw(sprite,x,y,size,tilt)
    end
    return true
end

return Art
