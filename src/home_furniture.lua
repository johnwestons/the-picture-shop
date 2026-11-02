local Catalog=require("src.home_furniture_catalog")
local Layout=require("src.home_layouts")
local Footprint=require("src.floor_footprint")
local Grid=require("src.placement_grid")
local Residents=require("src.home_residents")
local Surface=require("src.home_surfaces")
local Objects=require("src.home_objects")
local Furniture={GRID={cellWidth=8,cellHeight=6,originX=0,originY=0,previewRadius=8,selectionRadius=80}}
local function clock() return love and love.timer and love.timer.getTime() or os.clock() end
local function integer(n,a,b) return type(n)=="number" and n==n and n>=a and n<=b and n==math.floor(n) end
function Furniture.new() return {version=3,nextId=1,nextEdit=1,revision=0,items={},permissions={move=false,purchase=false,sell=false}} end
function Furniture.valid(data)
    if data==nil then return true end
    if type(data)~="table" or not integer(data.version,1,3) or not integer(data.nextId,1,1e9) or not integer(data.nextEdit,1,1e12)
        or not integer(data.revision,0,1e12) or type(data.items)~="table" or #data.items>128 or type(data.permissions)~="table" then return false end
    for _,key in ipairs({"move","purchase","sell"}) do if type(data.permissions[key])~="boolean" then return false end end
    local ids,count,floorCount,holders={},0,0,{}
    for index,item in pairs(data.items) do
        if not integer(index,1,#data.items) or type(item)~="table" or not integer(item.id,1,data.nextId-1) or ids[item.id]
            or not Catalog.ITEMS[item.kind] or not Catalog.angle(item.direction) or item.sceneId~="home"
            or (item.location~="floor" and item.location~="storage" and item.location~="surface" and item.location~="carried") or not integer(item.condition,0,100)
            or not integer(item.revision,0,1e12) or not integer(item.x,0,960) or not integer(item.y,0,678)
            or item.x%8~=0 or item.y%6~=0 or type(item.contents)~="table" or not Objects.valid(item) then return false end
        if item.holderId then if holders[item.holderId] then return false end;holders[item.holderId]=true end
        if item.editor~=nil and (not (item.editor=="owner" or Residents.validId(item.editor)) or not integer(item.editToken,1,data.nextEdit-1)
            or type(item.editExpiresAt)~="number" or item.editExpiresAt~=item.editExpiresAt or item.editExpiresAt<0 or item.editExpiresAt>1e12) then return false end
        if item.editor==nil and (item.editToken~=nil or item.editExpiresAt~=nil) then return false end
        count=count+1;ids[item.id]=true;if item.location=="floor" then floorCount=floorCount+1 end
    end
    return count==#data.items and floorCount<=48 and Surface.valid(data)
end
local function changed(state)
    state.home.furniture.revision=state.home.furniture.revision+1;state.home.revision=state.home.revision+1
end
function Furniture.materialize(state,starter)
    local home=state.home;home.furniture=home.furniture or Furniture.new();local data=home.furniture
    for _,kind in ipairs(Catalog.ORDER) do
        local count=home.inventory[kind] or 0
        for i=1,count do
            if #data.items>=128 then break end
            local item={id=data.nextId,kind=kind,sceneId="home",location="storage",x=0,y=0,
                direction=Catalog.ITEMS[kind].defaultDirection or "southeast",condition=100,contents={},revision=0}
            if starter and i==1 then require("src.home_starter_layouts").place(state,item) end
            data.nextId=data.nextId+1;data.items[#data.items+1]=item;home.inventory[kind]=home.inventory[kind]-1
        end
    end
    return data
end
function Furniture.ensure(state)
    local fresh=not state.home.furniture;local legacy=not fresh and state.home.furniture.version==1
    if fresh or legacy then
        Furniture.materialize(state,fresh)
        local desk
        for _,item in ipairs(state.home.furniture.items) do if item.kind=="small_desk" and item.location=="floor" then desk=item end end
        for _,item in ipairs(state.home.furniture.items) do
            if item.location=="storage" and Catalog.ITEMS[item.kind].small and (fresh or item.kind=="laptop") then
                local parentId=desk and desk.id or 0
                local slot=item.kind=="laptop" and 1 or item.kind=="clock" and 2 or 3
                local taken=false;for _,child in ipairs(Surface.children(state,parentId)) do if child.slot==slot then taken=true end end
                if not taken then item.location="surface";item.parentId=parentId;item.slot=slot;item.direction="east" end
            end
        end
        state.home.furniture.version=3
    end
    if state.home.furniture.version==2 then state.home.furniture.version=3 end
    return state.home.furniture
end
function Furniture.find(state,id)
    for _,item in ipairs(state.home.furniture and state.home.furniture.items or {}) do if item.id==id then return item end end
end
function Furniture.allowed(state,player,action)
    return Residents.get(state,player)~=nil and ((player.id or 1)==1 or Furniture.ensure(state).permissions[action]==true)
end
function Furniture.footprint(item)
    local entry=Catalog.ITEMS[item.kind]
    return Footprint.orientedBox(item.x,item.y,entry.length,entry.width,Catalog.angle(item.direction),.5)
end
function Furniture.obstacles(state,exclude,candidate)
    local result={}
    for _,item in ipairs(state.home.furniture and state.home.furniture.items or {}) do
        if item.id~=exclude and item.location=="floor" then result[#result+1]=Furniture.footprint(item) end
    end
    if candidate then result[#result+1]=Furniture.footprint(candidate) end
    return result
end
local function essential(state)
    local result={};local entry=Layout.get(state)
    for i=1,4 do local x,y=Layout.spawn(state,i);result[#result+1]={x=x,y=y} end
    for _,fixture in pairs(entry.fixtures) do local x,y=Layout.toWorld(unpack(fixture.approach));result[#result+1]={x=x,y=y} end
    local x,y=Layout.toWorld(unpack(entry.laptop.approach));result[#result+1]={x=x,y=y}
    return result
end
Furniture.essential=essential
function Furniture.approaches(item)
    local shape=Furniture.footprint(item);local result={}
    local offsets={{-shape.halfWidth-16,0},{shape.halfWidth+16,0},{0,shape.halfHeight+12},{0,-shape.halfHeight-12}}
    if item.kind=="stove" then
        local x,y=shape.halfWidth+12,shape.halfHeight+12
        offsets[#offsets+1]={-x,-y};offsets[#offsets+1]={x,-y}
        offsets[#offsets+1]={-x,y};offsets[#offsets+1]={x,y}
    end
    for _,offset in ipairs(offsets) do
        result[#result+1]={x=item.x+offset[1],y=item.y+offset[2]}
    end
    return result
end
function Furniture.targets(state,player)
    local targets={};local obstacles=Furniture.obstacles(state)
    local assets={getData=function() return Layout.mask(state.home.apartmentId) end}
    local Navigation=require("src.navigation")
    for _,item in ipairs(state.home.furniture and state.home.furniture.items or {}) do
        local usable=false
        for _,action in pairs(Residents.ACTIONS) do if Residents.furnitureAvailable(state,action,item) then usable=true;break end end
        if (usable or Objects.interactive(item) or Catalog.ITEMS[item.kind].surface or Catalog.ITEMS[item.kind].hookup)
            and item.location~="storage" and item.location~="carried" then
            local best,distance
            for _,point in ipairs(Surface.approaches(state,item)) do
                local d=(point.x-player.x)^2+(point.y-player.y)^2
                if (not distance or d<distance) and Navigation.isWalkable(assets,point.x,point.y,obstacles) then best,distance=point,d end
            end
            local pose=Surface.pose(state,item)
            if best then targets["furniture"..item.id]={kind="homeActivity",fixtureId="furniture"..item.id,
                x=best.x,y=best.y,radius=42,hoverX=pose.x,hoverY=pose.y-20,hoverRadius=26,
                prompt="E: "..Catalog.ITEMS[item.kind].name.." / activities",actionLabel="USE"} end
        end
    end
    return targets
end
function Furniture.hookupPoint(state,item)
    local entry=Catalog.ITEMS[item and item.kind]
    return entry and entry.hookup and Layout.applianceHookup(state,entry.hookup) or nil
end
function Furniture.hookedUp(state,item)
    local entry=Catalog.ITEMS[item and item.kind]
    if not entry or not entry.hookup then return true end
    local point=Furniture.hookupPoint(state,item)
    return point~=nil and item.location=="floor" and item.x==point.x and item.y==point.y
        and item.direction==point.direction
end
function Furniture.hookupHint(state,item)
    local entry=Catalog.ITEMS[item and item.kind]
    if not entry or not entry.hookup then return nil end
    local point=Furniture.hookupPoint(state,item)
    if not point then return "This apartment has no hookup spot for this appliance." end
    local direction=entry.hookupDirection=="west" and "face left" or "face south"
    if Furniture.hookedUp(state,item) then return "Connected at the kitchen hookup." end
    return string.format("Move to the kitchen hookup at %d, %d and %s to connect.",point.x,point.y,direction)
end
function Furniture.canPlace(state,candidate,players,quick)
    local entry=Catalog.ITEMS[candidate.kind]
    if not entry or not Catalog.angle(candidate.direction) then return false,"Unknown furniture or direction." end
    if entry.hookup then
        local point=Furniture.hookupPoint(state,candidate)
        if not point or candidate.x~=point.x or candidate.y~=point.y then
            return false,"Install this appliance at its kitchen hookup."
        end
    end
    local shape=Furniture.footprint(candidate);local polygon=Footprint.vertices(shape)
    local mask=Layout.mask(state.home.apartmentId)
    local function onFloor(x,y) return mask:getPixel(math.floor(x),math.floor(y))==1 end
    local count=1;for _,item in ipairs(state.home.furniture.items) do if item.id~=candidate.id and item.location=="floor" then count=count+1 end end
    if count>48 then return false,"Store an object before placing more furniture." end
    -- Sample the whole contact patch, including the interior, against fixture
    -- bases and registered walls. Testing corners alone can straddle a wall.
    for y=candidate.y-shape.halfHeight,candidate.y+shape.halfHeight,4 do
        for x=candidate.x-shape.halfWidth,candidate.x+shape.halfWidth,4 do
            if Footprint.penetration(shape,x,y)>=0 and not onFloor(x,y) then return false,"Keep furniture on clear apartment floor." end
        end
    end
    for i=1,#polygon,2 do if not onFloor(polygon[i],polygon[i+1]) then return false,"Keep the whole footprint on the floor." end end
    for _,other in ipairs(Furniture.obstacles(state,candidate.id)) do if Footprint.overlaps(shape,other,3) then return false,"Furniture would overlap another object." end end
    local padded=Footprint.expand(shape,{x=10,y=5})
    for _,point in ipairs(essential(state)) do if Footprint.penetration(padded,point.x,point.y)>0 then return false,"Keep entrances and fixture approaches clear." end end
    for _,p in ipairs(players or {}) do if p.sceneId=="home" and Footprint.penetration(padded,p.x,p.y)>0 then return false,"Move away from the placement first." end end
    if quick then return true end
    return require("src.home_furniture_routes").validate(state,candidate,players)
end
function Furniture.stageDeliveries(state,firstId,players)
    local center=Layout.get(state).rooms.living
    local cx,cy=Layout.toWorld(center[1],center[2])
    local staged=0
    for _,item in ipairs(state.home.furniture.items) do
        if item.id>=firstId and item.location=="storage" then
            local found
            local hookup=Furniture.hookupPoint(state,item)
            if hookup then
                local candidate={id=item.id,kind=item.kind,x=hookup.x,y=hookup.y,
                    direction=hookup.direction or Catalog.ITEMS[item.kind].defaultDirection or item.direction,location="floor"}
                local okay=Furniture.canPlace(state,candidate,players,true)
                if okay then okay=Furniture.canPlace(state,candidate,players) end
                if okay then found=candidate end
            end
            for radius=0,288,24 do
                if found then break end
                local offsets={}
                if radius==0 then offsets[1]={0,0}
                else
                    for dx=-radius,radius,24 do
                        offsets[#offsets+1]={dx,-radius};offsets[#offsets+1]={dx,radius}
                    end
                    for dy=-radius+24,radius-24,24 do
                        offsets[#offsets+1]={-radius,dy};offsets[#offsets+1]={radius,dy}
                    end
                end
                for _,offset in ipairs(offsets) do
                    local x,y=Grid.snap(cx+offset[1],cy+offset[2],Furniture.GRID)
                    local candidate={id=item.id,kind=item.kind,x=x,y=y,
                        direction=Catalog.ITEMS[item.kind].defaultDirection or item.direction,location="floor"}
                    local okay=Furniture.canPlace(state,candidate,players,true)
                    if okay then
                        okay=Furniture.canPlace(state,candidate,players)
                        if okay then found=candidate;break end
                    end
                end
                if found then break end
            end
            if found then
                item.x,item.y,item.direction=found.x,found.y,found.direction
                item.location="floor";item.revision=item.revision+1;staged=staged+1
            end
        end
    end
    return staged
end
function Furniture.recover(state,players)
    local present={}
    for _,p in ipairs(players or {}) do local id=Residents.key(p);if id and p.sceneId=="home" and state.home.weekend.phase=="home" then present[id]=true end end
    local released=false
    for _,item in ipairs(Furniture.ensure(state).items) do
        if item.location=="carried" and not present[item.holderId] then
            item.location="storage";item.holderId=nil;item.revision=item.revision+1;released=true
        end
        if item.editor and (not present[item.editor] or clock()>item.editExpiresAt) then item.editor=nil;item.editToken=nil;item.editExpiresAt=nil;released=true end
    end
    if released then changed(state) end
    return released
end
function Furniture.decode(command)
    if type(command)~="string" or #command>80 then return nil end
    local ai,at,ap,as,ad=command:match("^attach:(%d+):(%d+):(%d+):(%d+):([a-z]+)$")
    if ai then
        for _,v in ipairs({ai,at,ap,as}) do if tostring(tonumber(v))~=v then return nil end end
        if integer(tonumber(ai),1,1e9) and integer(tonumber(at),1,1e12) and integer(tonumber(ap),0,1e9)
            and integer(tonumber(as),1,3) and Catalog.angle(ad) then
            return {action="attach",id=tonumber(ai),token=tonumber(at),parentId=tonumber(ap),slot=tonumber(as),direction=ad}
        end
        return nil
    end
    local action,id,token,cell,direction=command:match("^(place):(%d+):(%d+):(c%d+r%d+):([a-z]+)$")
    if action then
        if not Catalog.angle(direction) or not Grid.decode(cell,Furniture.GRID) then return nil end
    else action,id,token=command:match("^([a-z]+):(%d+):(%d+)$") end
    if action=="place" or action=="store" or action=="sell" or action=="cancel" then
        if not id or not token or tostring(tonumber(id))~=id or tostring(tonumber(token))~=token or not integer(tonumber(id),1,1e9) or not integer(tonumber(token),1,1e12) then return nil end
        return {action=action,id=tonumber(id),token=tonumber(token),cell=cell,direction=direction}
    end
    action,id=command:match("^(begin):(%d+)$")
    if action and tostring(tonumber(id))==id and integer(tonumber(id),1,1e9) then return {action=action,id=tonumber(id)} end
    local permission,enabled=command:match("^permission:([a-z]+):([01])$")
    if permission=="move" or permission=="purchase" or permission=="sell" then return {action="permission",permission=permission,enabled=enabled=="1"} end
end
function Furniture.command(state,player,command,players)
    local c=Furniture.decode(command);if not c then return false,"Choose a valid furniture action." end
    local allowed,reason=require('src.commute.outfit').allowed(state,player,'household')
    if not allowed and c.action~='cancel' then return false,reason end
    if player.sceneId~="home" or state.home.weekend.phase~="home" then return false,"Furnish your apartment while at home." end
    if not Residents.get(state,player) then return false,"Join this household before furnishing." end
    local data=Furniture.ensure(state);local resident=Residents.key(player)
    if c.action=="permission" then
        if (player.id or 1)~=1 then return false,"Only the host grants furniture permissions." end
        if data.permissions[c.permission]==c.enabled then return false,"That permission is already set." end
        data.permissions[c.permission]=c.enabled;changed(state);return true,"Guest furniture permission saved."
    end
    local item=Furniture.find(state,c.id);if not item then return false,"That furniture is no longer available." end
    if item.location=="carried" then return false,"Put the carried cup in storage through Home [H] before arranging it." end
    if c.action=="cancel" and item.editor==resident and c.token==item.editToken then
        item.editor=nil;item.editToken=nil;item.editExpiresAt=nil;changed(state);return true,"Furniture move cancelled; its original position is kept."
    end
    if not Furniture.allowed(state,player,c.action=="sell" and "sell" or "move")
        and not (c.action=="begin" and Furniture.allowed(state,player,"sell")) then return false,"The host has not granted this furniture permission." end
    if item.location=="floor" and (player.x-item.x)^2+(player.y-item.y)^2>120^2 then return false,"Walk closer to that furniture." end
    if c.action=="begin" then
        if item.editor then return false,"Someone is already arranging this object." end
        if Surface.editConflict(state,item) then return false,"Finish arranging the supporting desk or its contents first." end
        if item.location=="surface" then
            local near=false;for _,p in ipairs(Surface.approaches(state,item)) do if (p.x-player.x)^2+(p.y-player.y)^2<=120^2 then near=true end end
            if not near then return false,"Walk closer to that object." end
        end
        for _,other in ipairs(data.items) do if other.editor==resident then return false,"Finish your current furniture move first." end end
        for _,r in pairs(state.home.residents) do if r.activity and (r.activity.furnitureId==item.id or r.activity.tvId==item.id or r.activity.diningParentId==item.id) then return false,"Finish using this furniture before moving it." end end
        for _,child in ipairs(Surface.children(state,item.id)) do
            for _,r in pairs(state.home.residents) do if r.activity and (r.activity.furnitureId==child.id or r.activity.tvId==child.id) then return false,"Finish using objects on this desk before moving it." end end
        end
        item.editor=resident;item.editToken=data.nextEdit;item.editExpiresAt=clock()+120;data.nextEdit=data.nextEdit+1;changed(state)
        return true,"Choose a green grid space. Q rotates, Enter places, Escape cancels."
    end
    if item.editor~=resident or item.editToken~=c.token then return false,"That furniture editing session has ended." end
    if c.action=="attach" then
        local okay,message=Surface.canAttach(state,item,c.parentId,c.slot,player);if not okay then return false,message end
        item.x,item.y=0,0;item.location="surface";item.parentId=c.parentId;item.slot=c.slot;item.direction=c.direction
    elseif c.action=="place" then
        local x,y=Grid.decode(c.cell,Furniture.GRID)
        if not Catalog.ITEMS[item.kind].hookup and (x-player.x)^2+(y-player.y)^2>160^2 then
            return false,"Choose a space near your character."
        end
        local candidate={id=item.id,kind=item.kind,x=x,y=y,direction=c.direction,location="floor"}
        local okay,message=Furniture.canPlace(state,candidate,players or {player})
        if not okay then return false,message end
        item.x,item.y,item.direction,item.location=x,y,c.direction,"floor"
        item.parentId=nil;item.slot=nil
    elseif c.action=="store" then
        local Dining=require("src.home_dining");local okay,message=Dining.canPack(state,item.id);if not okay then return false,message end
        Dining.pack(state,item.id);Surface.packChildren(state,item.id);item.location="storage";item.parentId=nil;item.slot=nil
    elseif c.action=="sell" then
        local price=math.floor(Catalog.ITEMS[item.kind].priceCents*.4*item.condition/100)
        if state.home.balanceCents+price>1e12 then return false,"The household account cannot receive this sale." end
        local okay,message=Objects.canSell(state,item);if not okay then return false,message end
        local Dining=require("src.home_dining");okay,message=Dining.canPack(state,item.id);if not okay then return false,message end
        Dining.pack(state,item.id)
        Objects.emptyForSale(state,item)
        Surface.packChildren(state,item.id)
        state.home.balanceCents=state.home.balanceCents+price
        for i,row in ipairs(data.items) do if row==item then table.remove(data.items,i);break end end
    else return false,"Choose a furniture action." end
    item.editor=nil;item.editToken=nil;item.editExpiresAt=nil;item.revision=item.revision+1;changed(state)
    return true,(c.action=="place" or c.action=="attach") and "Furniture placed." or c.action=="store" and "Furniture and supported objects stored. Unpack them with Furnish [M]." or "Furniture sold; supported objects kept in storage."
end
return Furniture
