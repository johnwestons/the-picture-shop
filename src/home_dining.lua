local Food=require("src.home_food_catalog")
local Catalog=require("src.home_furniture_catalog")
local Surface=require("src.home_surfaces")
local Layout=require("src.home_layouts")
local Dining={LIMIT=48}
local function integer(n,a,b) return type(n)=="number" and n==n and n>=a and n<=b and n==math.floor(n) end
function Dining.new() return {version=1,revision=0,nextId=1,items={}} end
function Dining.ensure(state) state.home.dining=state.home.dining or Dining.new();return state.home.dining end
local function edible(food) return Food.ITEMS[food] and Food.ITEMS[food].action~=nil end
local function changed(state) local d=Dining.ensure(state);d.revision=d.revision+1;state.home.revision=state.home.revision+1 end
function Dining.parent(state,id)
    if id==0 then return true end
    local p=Surface.find(state,id);return p and p.location=="floor" and Catalog.ITEMS[p.kind].surface and p
end
function Dining.children(state,parentId)
    local rows={}
    for _,meal in ipairs(state.home.dining and state.home.dining.items or {}) do if meal.parentId==parentId then rows[#rows+1]=meal end end
    for _,r in pairs(state.home.residents or {}) do
        local a=r.activity
        if a and a.diningParentId==parentId then
            rows[#rows+1]={parentId=parentId,slot=a.diningSlot,food=require("src.home_residents").ACTIONS[a.kind].item,eating=true}
        end
    end
    table.sort(rows,function(a,b) return a.slot<b.slot end);return rows
end
function Dining.occupied(state,parentId,slot)
    for _,meal in ipairs(Dining.children(state,parentId)) do if meal.slot==slot then return true end end
    return false
end
function Dining.validActivity(a)
    if a.diningParentId==nil then return a.diningSlot==nil end
    return integer(a.diningParentId,0,1e9-1) and integer(a.diningSlot,1,3) and require("src.home_residents").ACTIONS[a.kind].item~=nil
end
function Dining.valid(state)
    local d=state.home.dining
    if d==nil then
        for _,r in pairs(state.home.residents or {}) do if r.activity and r.activity.diningParentId~=nil then return false end end
        return true
    end
    if type(d)~="table" or d.version~=1 or not integer(d.revision,0,1e12) or not integer(d.nextId,1,1e9) or type(d.items)~="table" or #d.items>Dining.LIMIT then return false end
    local ids,slots,count={},{},0
    for _,item in ipairs(state.home.furniture and state.home.furniture.items or {}) do
        if item.location=="surface" then slots[item.parentId..":"..item.slot]=true end
    end
    local function slot(parentId,index)
        if not integer(parentId,0,1e9-1) or not integer(index,1,3) then return false end
        local list=Surface.slots(state,parentId);local key=parentId..":"..index
        if not list or not list[index] or slots[key] then return false end
        slots[key]=true;return true
    end
    for index,meal in pairs(d.items) do
        count=count+1
        if not integer(index,1,#d.items) or type(meal)~="table" or not integer(meal.id,1,d.nextId-1) or ids[meal.id]
            or not edible(meal.food) or not slot(meal.parentId,meal.slot) then return false end
        ids[meal.id]=true
    end
    for _,r in pairs(state.home.residents or {}) do
        local a=r.activity;if a and a.diningParentId~=nil and not slot(a.diningParentId,a.diningSlot) then return false end
    end
    return count==#d.items
end
function Dining.pose(state,meal)
    return Surface.pose(state,{location="surface",parentId=meal.parentId,slot=meal.slot,direction="east",kind="meal"})
end
function Dining.canPack(state,parentId)
    local totals={}
    for _,meal in ipairs(Dining.children(state,parentId)) do
        if meal.eating then return false,"Finish eating from this surface before arranging it." end
        totals[meal.food]=(totals[meal.food] or 0)+1
    end
    for food,n in pairs(totals) do
        if not require("src.home_cooking").hasRoom(state,food,n) then return false,"Make room in household supplies before packing these served meals." end
    end
    return true
end
function Dining.pack(state,parentId)
    local d=Dining.ensure(state);local any=false
    for i=#d.items,1,-1 do
        local meal=d.items[i]
        if meal.parentId==parentId then state.home.inventory[meal.food]=(state.home.inventory[meal.food] or 0)+1;table.remove(d.items,i);any=true end
    end
    if any then changed(state) end
end
local function approach(state,player,parentId)
    local parent=Dining.parent(state,parentId);if not parent or parentId~=0 and parent.editor then return false end
    local Navigation=require("src.navigation");local obstacles=require("src.home_furniture").obstacles(state)
    local assets={getData=function() return Layout.mask(state.home.apartmentId) end}
    for _,p in ipairs(Surface.approaches(state,{location="surface",parentId=parentId})) do
        if (p.x-player.x)^2+(p.y-player.y)^2<=48^2 and Navigation.isWalkable(assets,p.x,p.y,obstacles)
            and Navigation.canTraverse(assets,player.x,player.y,p.x,p.y,obstacles) then return true end
    end
    return false
end
function Dining.seatReaches(state,seat,parentId,slot)
    if not seat or seat.location~="floor" or seat.editor or not (seat.kind=="chair" or seat.kind=="couch") then return false end
    local parent=Dining.parent(state,parentId);if not parent or parentId~=0 and parent.editor then return false end
    local x,y
    if parentId==0 then x,y=Layout.toWorld(unpack(Layout.get(state).laptop.approach)) else x,y=parent.x,parent.y end
    local dx,dy=x-seat.x,(y-seat.y)*2;local distance=math.sqrt(dx*dx+dy*dy)
    local entry=parentId~=0 and Catalog.ITEMS[parent.kind]
    local reach=entry and math.sqrt(entry.length^2+entry.width^2)/2+45 or 48
    if distance<1 or distance>reach then return false end
    local angle=Catalog.angle(seat.direction)
    if (dx*math.cos(angle)+dy*math.sin(angle))/distance<.70 then return false end
    local pose=Dining.pose(state,{parentId=parentId,slot=slot});if not pose then return false end
    local height=entry and entry.surface.height or 0
    local px,py=pose.x,pose.y+height
    if parentId==0 then px,py=x,y end
    if (px-seat.x)^2+((py-seat.y)*2)^2>85^2 then return false end
    local mask=Layout.mask(state.home.apartmentId);local steps=math.max(1,math.ceil(math.sqrt((x-seat.x)^2+(y-seat.y)^2)/4))
    local Footprint=require("src.floor_footprint")
    for _,item in ipairs(state.home.furniture.items) do
        if item.location=="floor" and item.id~=seat.id and item.id~=parentId
            and Footprint.segmentPenetrates(require("src.home_furniture").footprint(item),seat.x,seat.y,x,y) then return false end
    end
    for i=1,steps-1 do if mask:getPixel(math.floor(seat.x+(x-seat.x)*i/steps),math.floor(seat.y+(y-seat.y)*i/steps))~=1 then return false end end
    return true
end
function Dining.decode(command)
    if type(command)~="string" or #command>80 then return end
    local parent,slot,food,revision=command:match("^dine:serve:(%d+):(%d+):([a-z_]+):(%d+)$")
    local action,id,seat
    if parent then action="serve"
    else id,seat,revision=command:match("^dine:eat:(%d+):(%d+):(%d+)$");if id then action="eat"
        else id,revision=command:match("^dine:return:(%d+):(%d+)$");if id then action="return" end end
    end
    if not action then return end
    for _,v in pairs({parent,slot,id,seat,revision}) do if tostring(tonumber(v))~=v then return end end
    local c={action=action,parentId=tonumber(parent),slot=tonumber(slot),food=food,id=tonumber(id),seatId=tonumber(seat),revision=tonumber(revision)}
    if not integer(c.revision,0,1e12) then return end
    if action=="serve" then if not integer(c.parentId,0,1e9-1) or not integer(c.slot,1,3) or not edible(food) then return end
    elseif not integer(c.id,1,1e9-1) or action=="eat" and not integer(c.seatId,0,1e9-1) then return end
    return c
end
function Dining.command(state,player,command)
    local c=Dining.decode(command);local Residents=require("src.home_residents");local r=Residents.get(state,player)
    if not c then return false,"invalid_action","Choose a meal action." end
    if not r or player.sceneId~="home" or not require("src.weekend_flow").atHome(state) then return false,"wrong_scene","Serve and eat meals at home." end
    if r.activity then return false,"busy","Finish or stop your current activity first." end
    local d=Dining.ensure(state);if d.revision~=c.revision then return false,"changed","The served meals changed. Review them and try again." end
    if c.action=="serve" then
        if #d.items>=Dining.LIMIT or d.nextId>=1e9 then return false,"full","Clear a served portion before serving more." end
        if not approach(state,player,c.parentId) then return false,"out_of_range","Walk beside that surface and finish arranging it first." end
        local okay,reason=Surface.canAttach(state,{kind="cup",id=-1},c.parentId,c.slot,player)
        if not okay then return false,"unavailable",reason end
        if (state.home.inventory[c.food] or 0)<1 then return false,"empty","Take a portion out of storage or receive groceries first." end
        state.home.inventory[c.food]=state.home.inventory[c.food]-1
        d.items[#d.items+1]={id=d.nextId,parentId=c.parentId,slot=c.slot,food=c.food};d.nextId=d.nextId+1;changed(state)
        return true,"served","One portion served. Eat here or from an aligned nearby chair/couch."
    end
    local meal,index
    for i,item in ipairs(d.items) do if item.id==c.id then meal,index=item,i;break end end
    if not meal then return false,"changed","That served portion is no longer available." end
    if c.action=="return" then
        if not approach(state,player,meal.parentId) then return false,"out_of_range","Walk beside the serving surface first." end
        if not require("src.home_cooking").hasRoom(state,meal.food,1) then return false,"full","Household supplies are full or reserved for cooking." end
        state.home.inventory[meal.food]=(state.home.inventory[meal.food] or 0)+1
    else
        local target
        if c.seatId==0 then
            if not approach(state,player,meal.parentId) then return false,"out_of_range","Walk beside the serving surface first." end
            target=meal.parentId==0 and "floor" or "furniture"..meal.parentId
        else
            local seat=Surface.find(state,c.seatId)
            if not Dining.seatReaches(state,seat,meal.parentId,meal.slot) then return false,"unavailable","Place and face the chair/couch toward the table, close enough to reach the meal." end
            target="furniture"..seat.id
        end
        local okay,code,message=Residents.command(state,player,Food.ITEMS[meal.food].action..":"..target,meal)
        if not okay then return false,code,message end
    end
    table.remove(d.items,index);changed(state)
    return true,c.action=="eat" and "started" or "returned",c.action=="eat" and "Eating the served portion. Moving or stopping does not return eaten food." or "Uneaten portion returned to household supplies."
end
function Dining.rows(state,player,target)
    local rows={};local id=target:match("^furniture(%d+)$");local item=id and Surface.find(state,tonumber(id))
    local parentId=target=="sink" and 0 or item and Catalog.ITEMS[item.kind].surface and item.id
    local seat=item and (item.kind=="chair" or item.kind=="couch") and item
    local d=Dining.ensure(state)
    for _,meal in ipairs(d.items) do
        if meal.parentId==parentId or seat and Dining.seatReaches(state,seat,meal.parentId,meal.slot) then
            rows[#rows+1]={label="EAT SERVED "..Food.ITEMS[meal.food].name,command="dine:eat:"..meal.id..":"..(seat and seat.id or 0)..":"..d.revision}
            if parentId then rows[#rows+1]={label="RETURN "..Food.ITEMS[meal.food].name.." TO SUPPLIES",command="dine:return:"..meal.id..":"..d.revision} end
        end
    end
    if parentId then
        local free
        for slot=1,#(Surface.slots(state,parentId) or {}) do
            if Surface.canAttach(state,{kind="cup",id=-1},parentId,slot,player) then free=slot;break end
        end
        if free then for _,food in ipairs(require("src.home_objects").FOODS) do
            if edible(food) and (state.home.inventory[food] or 0)>0 then
                rows[#rows+1]={label="SERVE "..Food.ITEMS[food].name.." / SLOT "..free,command="dine:serve:"..parentId..":"..free..":"..food..":"..d.revision}
            end
        end end
    end
    return rows
end
function Dining.draw(state,parentId)
    for _,meal in ipairs(Dining.children(state,parentId)) do
        local pose=Dining.pose(state,meal);local food=Food.ITEMS[meal.food]
        require("src.home_food_art").draw(food.eatingSprite or food.sprite,pose.x,pose.y-4,28)
    end
end
return Dining
