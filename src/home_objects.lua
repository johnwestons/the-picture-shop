-- Host-authoritative household object actions. Commands carry object revisions,
-- never client quantities, prices, contents or player coordinates.
local Catalog=require("src.home_furniture_catalog")
local Food=require("src.home_food_catalog")
local Layout=require("src.home_layouts")
local Surface=require("src.home_surfaces")
local Utilities=require("src.home_utilities")
local Objects={FOODS={"basic_meal","sandwich","cereal","pizza_slice","chinese_meal","bottled_drink","bread","vegetables","cooked_meal","good_meal","plain_meal","good_sandwich","rough_sandwich"}}
local function integer(n,a,b) return type(n)=="number" and n==n and n>=a and n<=b and n==math.floor(n) end
function Objects.capacity(item) return Catalog.ITEMS[item.kind].capacity or 0 end
function Objects.count(item)
    local n=0;for _,v in pairs(item.contents) do if type(v)=="number" then n=n+v end end;return n
end
function Objects.valid(item)
    local capacity=Objects.capacity(item)
    local storage=Catalog.ITEMS[item.kind].storage
    for k,v in pairs(item.contents) do
        if item.kind=="cup" then
            if not (k=="water" and integer(v,0,1) or k=="dirty" and type(v)=="boolean") then return false end
        elseif storage then
            if k~=storage.key or not integer(v,0,storage.capacity) then return false end
        elseif capacity>0 then
            if not Food.isFood(k) or not integer(v,0,capacity) then return false end
        else return false end
    end
    if capacity>0 and Objects.count(item)>capacity then return false end
    if item.lit~=nil and (not Catalog.ITEMS[item.kind].light or type(item.lit)~="boolean") then return false end
    if item.powered~=nil and (not Catalog.ITEMS[item.kind].television or type(item.powered)~="boolean") then return false end
    if item.location=="carried" then
        local Residents=require("src.home_residents")
        if item.kind~="cup" or item.x~=0 or item.y~=0 or item.editor~=nil
            or not (item.holderId=="owner" or Residents.validId(item.holderId)) then return false end
    elseif item.holderId~=nil then return false end
    return true
end
function Objects.interactive(item) local entry=Catalog.ITEMS[item.kind];return item.kind=="cup" or entry.light~=nil or entry.television or entry.storage~=nil or Objects.capacity(item)>0 end
function Objects.held(state,player)
    local id=require("src.home_residents").key(player)
    for _,item in ipairs(state.home.furniture.items) do if item.location=="carried" and item.holderId==id then return item end end
end
function Objects.changed(state,item)
    item.revision=item.revision+1;state.home.furniture.revision=state.home.furniture.revision+1;state.home.revision=state.home.revision+1
end
function Objects.decode(command)
    if type(command)~="string" or #command>80 then return nil end
    local action,id,revision,food=command:match("^object:([a-z]+):(%d+):(%d+):([a-z_]+)$")
    if not action then action,id,revision=command:match("^object:([a-z]+):(%d+):(%d+)$") end
    if not action or tostring(tonumber(id))~=id or tostring(tonumber(revision))~=revision
        or not integer(tonumber(id),1,1e9) or not integer(tonumber(revision),0,1e12) then return nil end
    if action=="put" or action=="take" then if not Food.isFood(food) then return nil end
    elseif action~="on" and action~="off" and action~="pickup" and action~="away" and action~="setdown" and not Utilities.ACTIONS[action] or food then return nil end
    return {action=action,id=tonumber(id),revision=tonumber(revision),food=food}
end
function Objects.command(state,player,command)
    local c=Objects.decode(command);local Residents=require("src.home_residents")
    if not c then return false,"invalid_action","Choose a household object action." end
    local resident=Residents.get(state,player)
    if not resident or player.sceneId~="home" or state.home.weekend.phase~="home" then return false,"wrong_scene","Use household objects while at home." end
    if resident.activity and not (c.action=="off" and resident.activity.kind=="watch" and resident.activity.tvId==c.id) then
        return false,"busy","Finish or stop your current activity first."
    end
    local item=Surface.find(state,c.id)
    if not item or item.revision~=c.revision then return false,"changed","This object changed. Review it and try again." end
    if item.editor or Surface.editConflict(state,item) then return false,"being_moved","Finish arranging this object first." end
    if (c.action=="put" or c.action=="take") and not require("src.home_furniture").hookedUp(state,item) then
        return false,"not_connected",require("src.home_furniture").hookupHint(state,item)
    end
    if c.action=="away" or c.action=="setdown" then
        if item.location~="carried" or item.holderId~=Residents.key(player) then return false,"not_held","You are not carrying this cup." end
        if c.action=="setdown" then
            local parents={0};for _,p in ipairs(state.home.furniture.items) do if p.location=="floor" and Catalog.ITEMS[p.kind].surface then parents[#parents+1]=p.id end end
            local chosen,distance
            for _,id in ipairs(parents) do
                for slot=1,#Surface.slots(state,id) do
                    if Surface.canAttach(state,item,id,slot,player) then
                        for _,point in ipairs(Surface.approaches(state,{location="surface",parentId=id})) do
                            local d=(point.x-player.x)^2+(point.y-player.y)^2
                            if d<=48^2 and (not distance or d<distance) then chosen={id=id,slot=slot};distance=d end
                        end
                    end
                end
            end
            if not chosen then return false,"no_surface","Walk beside a desk or kitchen counter with a clear slot." end
            item.location="surface";item.holderId=nil;item.parentId=chosen.id;item.slot=chosen.slot;item.direction="east"
            Objects.changed(state,item);return true,"changed","Cup set down with its contents."
        end
        item.location="storage";item.holderId=nil;Objects.changed(state,item)
        return true,"changed","Cup put in storage with its contents. Furnish [M] places it again."
    end
    local target=require("src.home_furniture").targets(state,player)["furniture"..item.id]
    if not target or (target.x-player.x)^2+(target.y-player.y)^2>target.radius^2 then return false,"out_of_range","Walk closer to that object." end
    if Utilities.ACTIONS[c.action] then return Utilities.transfer(state,item,c.action)
    elseif c.action=="pickup" then
        if item.kind~="cup" or item.location=="carried" then return false,"not_available","Choose a placed cup." end
        if Objects.held(state,player) then return false,"hands_full","Put away your current cup first." end
        item.location="carried";item.holderId=Residents.key(player);item.parentId=nil;item.slot=nil;item.x=0;item.y=0
        Objects.changed(state,item);return true,"changed","Cup picked up. Carry it to a sink to fill or wash it; Home [H] drinks it."
    elseif c.action=="on" or c.action=="off" then
        if Catalog.ITEMS[item.kind].television then
            local on=c.action=="on";if (item.powered==true)==on then return false,"unchanged","The TV is already set that way." end
            item.powered=on;Objects.changed(state,item);return true,"changed",on and "TV switched on. Watch nearby or from a chair/couch in front of the screen." or "TV switched off."
        end
        if not Catalog.ITEMS[item.kind].light then return false,"not_available","This object has no light switch." end
        local lit=c.action=="on"
        if (item.lit==true)==lit then return false,"unchanged","The lamp is already set that way." end
        item.lit=lit;Objects.changed(state,item);return true,"changed",lit and "Lamp switched on." or "Lamp switched off."
    else
        local capacity=Objects.capacity(item);if capacity==0 then return false,"not_available","This object cannot store food." end
        local stored=item.contents[c.food] or 0;local pantry=state.home.inventory[c.food] or 0
        if c.action=="put" then
            if pantry<1 then return false,"empty","No portion of that food is in household storage." end
            if Objects.count(item)>=capacity then return false,"full","This food storage is full." end
            item.contents[c.food]=stored+1;state.home.inventory[c.food]=pantry-1
        else
            if stored<1 then return false,"empty","No portion of that food is stored here." end
            if not require("src.home_cooking").hasRoom(state,c.food,1) then return false,"full","Household storage is full or reserved for a batch being prepared." end
            item.contents[c.food]=stored-1;state.home.inventory[c.food]=pantry+1
        end
        Objects.changed(state,item)
        return true,"changed",c.action=="put" and "One portion moved into food storage." or "One portion moved to household storage, ready to eat or prepare."
    end
end
function Objects.canSell(state,item)
    local okay,reason=Utilities.canSell(state,item);if not okay then return false,reason end
    if Objects.capacity(item)>0 then
        for kind,n in pairs(item.contents) do if not require("src.home_cooking").hasRoom(state,kind,n) then return false,"Make room in household storage before selling this filled food container." end end
    end
    return true
end
function Objects.emptyForSale(state,item)
    Utilities.emptyForSale(state,item)
    if Objects.capacity(item)>0 then for kind,n in pairs(item.contents) do state.home.inventory[kind]=(state.home.inventory[kind] or 0)+n end;item.contents={} end
end
function Objects.activityTarget(state,player,kind,item)
    if not item or item.kind~="cup" or item.location~="carried" or item.holderId~=require("src.home_residents").key(player) then return nil,"Pick up a cup first." end
    if kind=="cupdrink" then
        if (item.contents.water or 0)<1 then return nil,"Fill your cup at a sink first." end
        return {x=player.x,y=player.y,radius=0}
    end
    if kind=="cupfill" and item.contents.dirty then return nil,"Wash your cup before refilling it." end
    if kind=="cupfill" and (item.contents.water or 0)>0 then return nil,"The cup is already full." end
    local best,distance
    for _,id in ipairs({"sink","basin"}) do
        local x,y=Layout.toWorld(unpack(Layout.get(state).fixtures[id].approach));local d=(x-player.x)^2+(y-player.y)^2
        if not distance or d<distance then best={x=x,y=y,radius=48,fixtureId=id};distance=d end
    end
    if distance>48^2 then return nil,"Carry the cup to the kitchen or bathroom sink." end
    return best
end
function Objects.startActivity(state,kind,item)
    if kind=="cupdrink" then item.contents.water=0;item.contents.dirty=true;Objects.changed(state,item) end
end
function Objects.finishActivity(state,activity)
    if activity.kind~="cupfill" and activity.kind~="cupwash" then return end
    local item=Surface.find(state,activity.furnitureId);if not item then return end
    item.contents.water=activity.kind=="cupfill" and 1 or 0;item.contents.dirty=false;Objects.changed(state,item)
end
function Objects.rows(state,player,target)
    local rows={};local id=target:match("^furniture(%d+)$");local item=id and Surface.find(state,tonumber(id))
    local function add(label,action,object,food)
        rows[#rows+1]={label=label,command="object:"..action..":"..object.id..":"..object.revision..(food and ":"..food or "")}
    end
    if item and item.location~="storage" and item.location~="carried" then
        if Catalog.ITEMS[item.kind].television then add(item.powered and "SWITCH TV OFF" or "SWITCH TV ON",item.powered and "off" or "on",item)
        elseif Catalog.ITEMS[item.kind].storage then
            local clothes=item.kind=="wardrobe"
            add(clothes and "STORE 1 CLEAN LAUNDRY BUNDLE" or "COLLECT UP TO 8 LOOSE TRASH", "stow",item)
            add(clothes and "RETURN 1 BUNDLE TO LAUNDRY" or "REMOVE UP TO 8 TRASH FOR ENTRANCE DISPOSAL", "retrieve",item)
        elseif Catalog.ITEMS[item.kind].light then add(item.lit and "SWITCH LAMP OFF" or "SWITCH LAMP ON",item.lit and "off" or "on",item)
        elseif item.kind=="cup" then add("PICK UP CUP — "..(item.contents.dirty and "needs washing" or (item.contents.water or 0)>0 and "full" or "empty"),"pickup",item)
        elseif Objects.capacity(item)>0 then
            local connected=require("src.home_furniture").hookedUp(state,item)
            for _,food in ipairs(Objects.FOODS) do
                local stored=item.contents[food] or 0;local pantry=state.home.inventory[food] or 0;local name=Food.ITEMS[food].name
                if connected and pantry>0 then add("STORE 1 "..name.." / "..pantry.." in household storage","put",item,food) end
                if connected and stored>0 then add("TAKE 1 "..name.." / "..stored.." stored here","take",item,food) end
            end
        end
    end
    local held=Objects.held(state,player)
    if held and (target=="floor" or target=="sink" or target=="basin") then
        for _,pair in ipairs({{"cupdrink","DRINK FROM CUP / 2 game min"},{"cupfill","FILL CUP AT SINK / 1 game min"},{"cupwash","WASH CUP AT SINK / 2 game min"}}) do
            rows[#rows+1]={label=pair[2],command=pair[1]..":furniture"..held.id}
        end
        add("SET CUP ON NEAREST CLEAR SURFACE","setdown",held)
        add("PUT CUP IN STORAGE","away",held)
    end
    return rows
end
function Objects.description(state,player,target)
    local id=target:match("^furniture(%d+)$");local item=id and Surface.find(state,tonumber(id))
    if item and Objects.capacity(item)>0 then
        if not require("src.home_furniture").hookedUp(state,item) then
            return require("src.home_furniture").hookupHint(state,item).." Food storage works after it is connected."
        end
        return "Food storage: "..Objects.count(item).." / "..Objects.capacity(item).." portions. Take a portion out before eating. Food stays fresh in storage."
    end
    if item and Catalog.ITEMS[item.kind].storage then
        local entry=Catalog.ITEMS[item.kind].storage
        return (item.kind=="wardrobe" and "Clean bundles: " or "Contained trash: ")..(item.contents[entry.key] or 0).." / "..entry.capacity
            ..(item.kind=="wardrobe" and ". Store unloaded laundry here, or put on fresh clothes from this wardrobe." or ". Collect loose waste here, then remove a bag and take it out beside the entrance.")
    end
    if item and item.kind=="old_tv" then return "TV "..(item.powered and "on" or "off")..". Watch from in front of the screen or a nearby chair/couch with a clear view. Awake viewers keep shared sleep at normal speed." end
    local held=Objects.held(state,player)
    if held then return "Carrying a cup: "..(held.contents.dirty and "needs washing" or (held.contents.water or 0)>0 and "full of water" or "empty")..". Fill/wash at a sink. Drink through Home [H]." end
end
return Objects
