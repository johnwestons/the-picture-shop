-- Surface poses are derived from the supporting object, never separately saved.
-- Parent zero is the permanent kitchen counter; no surface can support a surface.
local Catalog=require("src.home_furniture_catalog")
local Layout=require("src.home_layouts")
local Surface={}
function Surface.find(state,id)
    for _,item in ipairs(state.home.furniture and state.home.furniture.items or {}) do if item.id==id then return item end end
end
function Surface.slots(state,parentId)
    if parentId==0 then return {{0,0},{24,4},{-24,-4}} end
    local p=Surface.find(state,parentId);local entry=p and Catalog.ITEMS[p.kind]
    return p and p.location=="floor" and entry.surface and entry.surface.slots
end
function Surface.children(state,id)
    local result={}
    for _,item in ipairs(state.home.furniture and state.home.furniture.items or {}) do
        if item.location=="surface" and item.parentId==id then result[#result+1]=item end
    end
    table.sort(result,function(a,b) return a.slot<b.slot end);return result
end
function Surface.pose(state,item)
    if item.location~="surface" then return item end
    local slots=Surface.slots(state,item.parentId);local offset=slots and slots[item.slot]
    if not offset then return nil end
    local x,y,direction
    if item.parentId==0 then
        local anchor=Layout.get(state).laptop;x,y=Layout.toWorld(anchor.x,anchor.y)
        x,y=x+offset[1],y+offset[2];direction=Catalog.rotate("southeast",Catalog.angle(item.direction)/(math.pi/4))
    else
        local p=Surface.find(state,item.parentId);local a=Catalog.angle(p.direction)
        x=p.x+offset[1]*math.cos(a)-offset[2]*math.sin(a)
        y=p.y+(offset[1]*math.sin(a)+offset[2]*math.cos(a))*.5-Catalog.ITEMS[p.kind].surface.height
        direction=Catalog.rotate(p.direction,Catalog.angle(item.direction)/(math.pi/4))
    end
    return {id=item.id,kind=item.kind,x=x,y=y,direction=direction,location="surface",contents=item.contents,lit=item.lit,powered=item.powered}
end
function Surface.valid(data)
    local occupied={};local map={};for _,item in ipairs(data.items) do map[item.id]=item end
    for _,item in ipairs(data.items) do
        if item.location=="surface" then
            local p=map[item.parentId];local entry=p and Catalog.ITEMS[p.kind]
            if not Catalog.ITEMS[item.kind].small or type(item.parentId)~="number" or item.parentId<0 or item.parentId~=math.floor(item.parentId)
                or type(item.slot)~="number" or item.slot~=math.floor(item.slot) or item.slot<1
                or item.parentId~=0 and (not p or p.location~="floor" or not entry.surface)
                or item.slot>(item.parentId==0 and 3 or #entry.surface.slots) or item.x~=0 or item.y~=0 then return false end
            local key=item.parentId..":"..item.slot;if occupied[key] then return false end;occupied[key]=true
        elseif item.parentId~=nil or item.slot~=nil then return false end
    end
    return true
end
function Surface.canAttach(state,item,parentId,slot,player)
    if not Catalog.ITEMS[item.kind].small then return false,"Only small objects fit on a surface." end
    local slots=Surface.slots(state,parentId)
    if not slots or not slots[slot] then return false,"Choose an available desk, table or counter slot." end
    local parent=Surface.find(state,parentId)
    if parent and parent.editor then return false,"Finish arranging that surface first." end
    for _,other in ipairs(Surface.children(state,parentId)) do
        if other.id~=item.id and other.slot==slot then return false,"That surface slot is occupied." end
    end
    if require("src.home_dining").occupied(state,parentId,slot) then return false,"That slot holds a served meal or a meal being eaten." end
    local x,y
    if parentId==0 then x,y=Layout.toWorld(unpack(Layout.get(state).laptop.approach)) else x,y=parent.x,parent.y end
    if (x-player.x)^2+(y-player.y)^2>120^2 then return false,"Walk closer to that surface." end
    return true
end
function Surface.packChildren(state,parentId)
    for _,child in ipairs(Surface.children(state,parentId)) do
        child.location="storage";child.parentId=nil;child.slot=nil;child.x=0;child.y=0;child.revision=child.revision+1
    end
end
function Surface.editConflict(state,item)
    if item.location=="surface" then local p=Surface.find(state,item.parentId);if p and p.editor then return true end end
    for _,child in ipairs(Surface.children(state,item.id)) do if child.editor then return true end end
    return false
end
function Surface.approaches(state,item)
    if item.location=="surface" then
        if item.parentId==0 then local x,y=Layout.toWorld(unpack(Layout.get(state).laptop.approach));return {{x=x,y=y}} end
        item=Surface.find(state,item.parentId)
    end
    return item and item.location=="floor" and require("src.home_furniture").approaches(item) or {}
end
function Surface.computer(state,player)
    local best,distance;local Furniture=require("src.home_furniture")
    local obstacles=Furniture.obstacles(state);local Navigation=require("src.navigation")
    local assets={getData=function() return Layout.mask(state.home.apartmentId) end}
    for _,item in ipairs(state.home.furniture and state.home.furniture.items or {}) do
        if item.kind=="laptop" and item.location~="storage" and not item.editor and not Surface.editConflict(state,item) then
            for _,p in ipairs(Surface.approaches(state,item)) do
                local d=(player.x-p.x)^2+(player.y-p.y)^2
                if (not distance or d<distance) and Navigation.isWalkable(assets,p.x,p.y,obstacles) then
                    local pose=Surface.pose(state,item);distance=d
                    best={kind="computer",x=p.x,y=p.y,radius=48,hoverX=pose.x,hoverY=pose.y-10,hoverRadius=24,
                        furnitureId=item.id,prompt="E: use your laptop / CritterNet"}
                end
            end
        end
    end
    return best
end
return Surface
