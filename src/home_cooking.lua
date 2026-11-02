-- Recipes consume ingredients once when work starts. A resident's bounded
-- activity reserves room for its output; cancelling wastes the prepared batch.
local Food=require("src.home_food_catalog")
local Calendar=require("src.business_calendar")
local Cooking={}
Cooking.RECIPES={
    cook={label="Cook vegetables and toast",minutes=20,targets={},furnitureKind="stove",gain={},
        ingredients={bread=1,vegetables=2},outputs={"plain_meal","cooked_meal","good_meal"},portions=2},
    prepare={label="Prepare two sandwiches",minutes=10,targets={sink=true},furnitureKinds={countertop=true,kitchen_table=true},gain={},
        ingredients={bread=1,vegetables=1},outputs={"rough_sandwich","sandwich","good_sandwich"},portions=2},
}
Cooking.FOODS={
    hotmeal={label="Eat a home-cooked meal",minutes=15,targets={floor=true},gain={hunger=60},item="cooked_meal"},
    goodmeal={label="Eat a well-seasoned meal",minutes=15,targets={floor=true},gain={hunger=75},item="good_meal"},
    plainmeal={label="Eat an overdone meal",minutes=15,targets={floor=true},gain={hunger=35},item="plain_meal"},
    goodsandwich={label="Eat a carefully prepared sandwich",minutes=10,targets={floor=true},gain={hunger=50},item="good_sandwich"},
    roughsandwich={label="Eat a roughly prepared sandwich",minutes=10,targets={floor=true},gain={hunger=25},item="rough_sandwich"},
}
function Cooking.reserved(state,food)
    local n=0
    for _,r in pairs(state.home.residents or {}) do
        local a=r.activity;local recipe=a and Cooking.RECIPES[a.kind]
        if recipe then for _,output in ipairs(recipe.outputs) do if output==food then n=n+recipe.portions end end end
    end
    return n
end
function Cooking.hasRoom(state,food,count) return (state.home.inventory[food] or 0)+Cooking.reserved(state,food)+count<=10000 end
function Cooking.validActivity(a)
    if not Cooking.RECIPES[a.kind] then return a.cookQuality==nil and a.cookTended==nil end
    return type(a.cookQuality)=="number" and a.cookQuality>=1 and a.cookQuality<=3 and a.cookQuality==math.floor(a.cookQuality)
        and type(a.cookTended)=="boolean" and (a.cookTended or a.cookQuality==1)
end
function Cooking.valid(state)
    for _,recipe in pairs(Cooking.RECIPES) do for _,food in ipairs(recipe.outputs) do if not Cooking.hasRoom(state,food,0) then return false end end end
    return true
end
function Cooking.prepare(state,kind)
    local recipe=Cooking.RECIPES[kind];if not recipe then return true end
    for food,n in pairs(recipe.ingredients) do if (state.home.inventory[food] or 0)<n then return false,"Need "..n.." "..Food.ITEMS[food].name.." in household storage. Take ingredients out of the fridge first." end end
    for _,food in ipairs(recipe.outputs) do if not Cooking.hasRoom(state,food,recipe.portions) then return false,"Make room for the prepared portions in household storage first." end end
    return true
end
function Cooking.start(state,a)
    local recipe=Cooking.RECIPES[a.kind];if not recipe then return end
    for food,n in pairs(recipe.ingredients) do state.home.inventory[food]=state.home.inventory[food]-n end
    a.cookQuality=1;a.cookTended=false;state.home.revision=state.home.revision+1
end
function Cooking.finish(state,a)
    local recipe=Cooking.RECIPES[a.kind];if not recipe then return end
    local food=recipe.outputs[a.cookQuality]
    state.home.inventory[food]=(state.home.inventory[food] or 0)+recipe.portions
    state.home.revision=state.home.revision+1
    return recipe.portions.." portions ready: "..Food.ITEMS[food].name..". Home [H] serves them."
end
function Cooking.decode(command)
    local n=type(command)=="string" and #command<=24 and command:match("^season:(%d+)$")
    return n and tostring(tonumber(n))==n and tonumber(n)<=1e12 and tonumber(n) or nil
end
function Cooking.command(state,player,command)
    local revision=Cooking.decode(command);local r=require("src.home_residents").get(state,player)
    local a=r and r.activity
    if not revision or not a or not Cooking.RECIPES[a.kind] or r.revision~=revision then return false,"changed","That cooking step is no longer available." end
    if player.sceneId~="home" or state.home.weekend.phase~="home" or (player.x-a.x)^2+(player.y-a.y)^2>12^2 then return false,"out_of_range","Stay at your cooking station to finish preparing this batch." end
    local now=Calendar.absoluteHours(state)
    if a.cookTended or now<a.startedAt or now>=a.endsAt then return false,"unavailable","This batch has already been tended, or its preparation time has ended." end
    local fraction=(now-a.startedAt)/(a.endsAt-a.startedAt)
    a.cookQuality=fraction>=.4 and fraction<=.7 and 3 or fraction>=.25 and fraction<=.85 and 2 or 1
    a.cookTended=true;r.revision=r.revision+1
    return true,"changed",({"Too early or too late; the meal will still be edible.","Good timing. Finish the preparation to collect your portions.","Great timing! Finish the preparation for better portions."})[a.cookQuality]
end
function Cooking.rows(state,player)
    local r=require("src.home_residents").get(state,player);local a=r and r.activity
    if a and Cooking.RECIPES[a.kind] and not a.cookTended then return {{label="TEND BATCH NOW — aim for the green timing band",command="season:"..r.revision}} end
    return {}
end
function Cooking.description(state,player,target)
    local r=require("src.home_residents").get(state,player);local a=r and r.activity
    if a and Cooking.RECIPES[a.kind] then return "Tend once in the green band for better food. Moving, stopping or leaving wastes this batch." end
    local id=target:match("^furniture(%d+)$");local item=id and require("src.home_surfaces").find(state,tonumber(id))
    if item and require("src.home_furniture_catalog").ITEMS[item.kind].hookup
        and not require("src.home_furniture").hookedUp(state,item) then
        return require("src.home_furniture").hookupHint(state,item)
    end
    if target=="sink" or item and (item.kind=="stove" or item.kind=="countertop" or item.kind=="kitchen_table") then
        return "2 portions: sandwiches use 1 bread + 1 veg; stove meal 1 bread + 2 veg. In storage: bread "..(state.home.inventory.bread or 0)..", veg "..(state.home.inventory.vegetables or 0)..". Ingredients are used when you start."
    end
end
return Cooking
