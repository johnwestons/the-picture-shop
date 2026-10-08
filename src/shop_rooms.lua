-- Scene identity is per player; the shop and its pallet owners remain shared.
local Config = require("src.config")
local Storage = require("src.pallet_storage")
local Rooms = { IDS = { warehouse=true, front_left=true, front_right=true } }
-- Reuse the scene mask: navigation caches are keyed by assets/mask identity.
-- Weak values let transient preview assets and their adapters be collected.
local adapters=setmetatable({}, {__mode="k"})
Rooms.entrance = { x=688, y=232, radius=56 }
Rooms.exit = { x=102, y=232, radius=62 }
Rooms.shelves = { x=530, y=285, radius=160 }
Rooms.rest = { x=775, y=260, radius=80 }
Rooms.seats={{x=745,y=190},{x=785,y=195},{x=643,y=202},{x=850,y=225}}
Rooms.paths = {
    storage="assets/generated/shop-storage-room-v1.png",
    breakroom="assets/generated/shop-breakroom-v1.png",
    floor="assets/generated/shop-utility-room-v1.png",
}
local function near(player,point)
    return type(player)=="table" and type(player.x)=="number" and type(player.y)=="number"
        and (player.x-point.x)^2+(player.y-point.y)^2<=point.radius^2
end
function Rooms.scene(player) return player and player.sceneId or "warehouse" end
function Rooms.sameScene(a,b) return Rooms.scene(a)==Rooms.scene(b) end
function Rooms.employeeScene(entry)
    local actor=entry.actor
    return actor.phase=="break" and actor.seatBay or "warehouse"
end
function Rooms.definition(state,id)
    local bay=state and state.warehouse and state.warehouse.bays[id]
    return bay and bay.status=="complete" and bay.optionId or nil
end
function Rooms.name(state,id)
    if id=="warehouse" then return "Warehouse" end
    local kind=Rooms.definition(state,id)
    return (kind=="storage" and "Storage room" or kind=="breakroom" and "Break room" or "Utility room")
        .. (id=="front_left" and " A" or " B")
end
function Rooms.walkable(x,y,sceneId)
    if x<8 or x>952 or y>670 then return false end
    if sceneId and sceneId~="warehouse" then
        -- Door floor joins the main open floor; furniture sits along the rear wall.
        return y>=math.max(178,175+(x-180)*0.13)
    end
    -- Authored wall/floor seams, including the open lobby and computer office.
    if x<220 then return y>=264-x*0.30 end
    if x<594 then return y>=175+(x-220)*0.225 end
    if x<660 then return y>=260 end
    if x<828 then return y>=196 end
    return y>=248
end
function Rooms.assets(assets,sceneId)
    if not assets then return nil end
    sceneId=sceneId or "warehouse"
    if rawget(assets,"_shopRoomScene")==sceneId then return assets end
    assets=rawget(assets,"_shopRoomSource") or assets
    local scenes=adapters[assets]
    if not scenes then scenes=setmetatable({}, {__mode="v"});adapters[assets]=scenes end
    if scenes[sceneId] then return scenes[sceneId] end
    local mask={}
    function mask:getDimensions() return 1536,1024 end
    function mask:getPixel(px,py)
        local value=Rooms.walkable(px*960/1536,py*678/1024,sceneId) and 1 or 0
        return value,value,value,1
    end
    local adapted=setmetatable({_shopRoomSource=assets,_shopRoomScene=sceneId,getData=function(name)
        if name=="walkmask" then return mask end
        return assets.getData and assets.getData(name)
    end},{__index=assets})
    scenes[sceneId]=adapted
    return adapted
end
function Rooms.obstacles(state,sceneId)
    if Rooms.definition(state,sceneId)=="breakroom" then
        return {{x=730,y=210,halfWidth=62,halfHeight=20},{x=852,y=218,halfWidth=26,halfHeight=18}}
    end
    return {}
end
function Rooms.targets(player,state)
    if Rooms.scene(player)=="warehouse" then
        return {shopEntrance={kind="shopEntrance",x=Rooms.entrance.x,y=Rooms.entrance.y,
            radius=Rooms.entrance.radius,prompt="E: choose a shop room at the front entrance"}}
    end
    local targets={shopEntrance={kind="shopEntrance",x=Rooms.exit.x,y=Rooms.exit.y,
        radius=Rooms.exit.radius,prompt="E: return to the warehouse"}}
    local kind=Rooms.definition(state,Rooms.scene(player))
    if kind=="storage" then targets.roomStock={kind="roomStock",x=Rooms.shelves.x,y=Rooms.shelves.y,
        radius=Rooms.shelves.radius,prompt="E: manage stored shop stock"} end
    if kind=="breakroom" then targets.roomRest={kind="roomRest",x=player.resting and player.x or Rooms.rest.x,y=player.resting and player.y or Rooms.rest.y,
        radius=Rooms.rest.radius,prompt=player.resting and "E: stand up" or "E: take a break"} end
    return targets
end
local function operating(player,state)
    for _,key in ipairs({"palletJack","forklift"}) do
        local vehicle=state[key]
        if vehicle and vehicle.operating and vehicle.operatorPlayerId==(player.id or 1) then return true end
    end
    return false
end
local function availableSeat(player,state,context)
    local occupied={}
    for _,other in ipairs(context and context.players and context.players() or {}) do
        if other~=player and Rooms.sameScene(player,other) and other.resting then
            for i,seat in ipairs(Rooms.seats) do if (other.x-seat.x)^2+(other.y-seat.y)^2<20^2 then occupied[i]=true end end
        end
    end
    for _,worker in ipairs(state.employment and state.employment.staff or {}) do
        if worker.visible and worker.phase=="break" and worker.seatBay==Rooms.scene(player) then occupied[3]=true end
    end
    local start=player.id or 1
    for offset=0,#Rooms.seats-1 do
        local index=(start-1+offset)%#Rooms.seats+1
        if not occupied[index] then return Rooms.seats[index],index end
    end
end
function Rooms.transition(player,state,destination)
    if not Rooms.IDS[destination] then return false,"not_allowed","Unknown shop room." end
    local current=Rooms.scene(player)
    if current==destination then return true,"already_applied","You are already in this room." end
    if operating(player,state) then return false,"park_first","Park the pallet jack or forklift before entering a room." end
    if current=="warehouse" then
        if not near(player,Rooms.entrance) then return false,"out_of_range","Use the front entrance to enter another room." end
        if not Rooms.definition(state,destination) then return false,"room_locked","Finish this room's construction first." end
    elseif destination~="warehouse" or not near(player,Rooms.exit) then
        return false,"out_of_range","Use the room's exit to return to the warehouse."
    end
    player.sceneId=destination
    local point=destination=="warehouse" and {x=Rooms.entrance.x,y=Rooms.entrance.y+48} or {x=Rooms.exit.x,y=Rooms.exit.y+38}
    player.x,player.y=point.x,point.y
    player.velocityX,player.velocityY,player.moving,player.resting=0,0,false,false
    player._restOrigin=nil
    player.animationDistance,player.idleClock=0,0
    return true,"accepted","Entered "..Rooms.name(state,destination).."."
end
function Rooms.stockItems(state,sceneId)
    local items={}
    for _,item in ipairs(require("src.pallet_state").items(state)) do
        local p=item.pallet
        if p.location=="rack" and p.storage and p.storage.rackId==sceneId.."-rack" then
            items[#items+1]={item=item,stored=true}
        elseif item.vendor and p.location=="warehouse" and p.world
            and near(p.world,{x=Rooms.entrance.x,y=Rooms.entrance.y+70,radius=105})
            and not Storage.isSupporting(state,p.id) then
            items[#items+1]={item=item,stored=false}
        end
    end
    table.sort(items,function(a,b) return a.item.pallet.id<b.item.pallet.id end)
    return items
end
function Rooms.transfer(player,state,action,palletId,context)
    local sceneId=Rooms.scene(player)
    if Rooms.definition(state,sceneId)~="storage" or not near(player,Rooms.shelves) then
        return false,"out_of_range","Use the shelving inside your storage room."
    end
    if operating(player,state) then return false,"park_first","Park your vehicle first." end
    local item=Storage.find(state,palletId)
    if not item or not item.vendor and action~="retrieve" then return false,"stock_only","Storage rooms accept delivered shop stock." end
    local pallet=item.pallet
    local rackId=sceneId.."-rack"
    local registry=state.storage
    if not registry or not registry.racks[rackId] then return false,"room_locked","This storage room is not ready." end
    if not Storage.validate(state) then return false,"invalid_state","Stock records need to be valid before transferring." end
    if action=="store" and pallet.location=="rack" and pallet.storage and pallet.storage.rackId==rackId then
        return true,"already_applied","This stock is already stored here."
    end
    if registry.revision>=2147483647 then return false,"revision_exhausted","The stock transfer counter is full." end
    if action=="store" then
        if pallet.location~="warehouse" or not pallet.world
            or not near(pallet.world,{x=Rooms.entrance.x,y=Rooms.entrance.y+70,radius=105})
            or Storage.isSupporting(state,pallet.id) or (pallet.world.spawnProgress or 1)<1 then
            return false,"stage_stock","Bring the stock pallet to the front entrance and put it down first."
        end
        local slots=Storage.slots(state,rackId)
        local row,column
        for r=1,2 do for c=1,5 do if not row and not slots[r][c] then row,column=r,c end end end
        if not row then return false,"room_full","All ten stock spaces are occupied." end
        local point=require("src.warehouse_layout").rackPoint(rackId,row,column)
        pallet.location,pallet.storage,pallet.world="rack",{rackId=rackId,row=row,column=column},{x=point.x,y=point.y}
    elseif action=="retrieve" then
        if pallet.location~="rack" or not pallet.storage or pallet.storage.rackId~=rackId then
            return false,"stock_changed","This pallet is no longer stored in your room."
        end
        local drop
        for _,offset in ipairs({{0,75},{80,75},{-80,75},{0,140},{80,140},{-80,140}}) do
            local x,y=Rooms.entrance.x+offset[1],Rooms.entrance.y+offset[2]
            local blocked=false
            local obstacles=context and context.obstacles and context.obstacles(state,false) or {}
            for _,obstacle in ipairs(obstacles) do
                if math.abs(x-obstacle.x)<(obstacle.halfWidth or obstacle.radius or 25)+32
                    and math.abs(y-obstacle.y)<(obstacle.halfHeight or obstacle.radius or 18)+20 then blocked=true end
            end
            if Rooms.walkable(x,y) and not blocked then drop={x=x,y=y};break end
        end
        if not drop then return false,"blocked","Clear space at the warehouse entrance before retrieving stock." end
        pallet.location,pallet.storage,pallet.world="warehouse",nil,drop
    else return false,"not_allowed","Unknown stock action." end
    registry.revision=registry.revision+1
    registry.racks[rackId].revision=registry.revision
    return true,"accepted",action=="store" and "Shop stock stored in this room." or "Stock returned to the warehouse entrance."
end
function Rooms.perform(player,state,kind,command,context)
    if kind=="shopRoom" then return Rooms.transition(player,state,command) end
    if kind=="roomRest" then
        if command~="rest" and command~="stand" then return false,"not_allowed","Unknown break room action." end
        if Rooms.definition(state,Rooms.scene(player))~="breakroom" or not player.resting and not near(player,Rooms.rest) then
            return false,"out_of_range","Move closer to the break room seating."
        end
        if command=="rest" and not player.resting then
            local seat,index=availableSeat(player,state,context)
            if not seat then return false,"seats_full","The break room seats are in use." end
            player._restOrigin={x=player.x,y=player.y}
            player.x,player.y=seat.x,seat.y
            player.facing=index==4 and -1 or 1
        elseif command=="stand" then Rooms.stand(player) end
        player.resting=command=="rest"
        player.velocityX,player.velocityY,player.moving=0,0,false
        return true,"accepted",player.resting and "Taking a break. Move to stand up." or "Ready to work."
    end
    if kind~="roomStock" then return false,"not_allowed","Unknown room control." end
    local action,palletId
    if type(command)=="string" then action,palletId=command:match("^(%a+):([%w_.%-]+)$") end
    return Rooms.transfer(player,state,action,palletId,context)
end
function Rooms.stand(player)
    if not player.resting then return end
    local point=player._restOrigin or Rooms.rest
    player.x,player.y,player.resting,player._restOrigin=point.x,point.y,false,nil
end
return Rooms
