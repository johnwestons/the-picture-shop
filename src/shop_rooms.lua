-- Scene identity is per player; the shop and its pallet owners remain shared.
local Config = require("src.config")
local Storage = require("src.pallet_storage")
local Registration=require("src.warehouse_registration")
local Layout=require("src.warehouse_layout")
local Games=require("src.breakroom_games")
local Rooms = { IDS = { warehouse=true, front_left=true, front_right=true } }
-- Reuse the scene mask: navigation caches are keyed by assets/mask identity.
-- Weak values let transient preview assets and their adapters be collected.
local adapters=setmetatable({}, {__mode="k"})
Rooms.entrance,Rooms.roomEntrance,Rooms.exit=Registration.entrance,Registration.roomEntrance,Registration.exit
Rooms.shelves,Rooms.rest,Rooms.seats=Registration.shelves,Registration.rest,Registration.roomSeats
Rooms.paths = {
    storage="assets/generated/shop-storage-room-v1.png",
    breakroom="assets/generated/shop-breakroom-games-v1.png",
    floor="assets/generated/shop-utility-room-v1.png",
}
Rooms.constructionPaths = {
    storage={
        "assets/generated/shop-storage-construction-stage-1.png",
        "assets/generated/shop-storage-construction-stage-2.png",
        "assets/generated/shop-storage-construction-stage-3.png",
        "assets/generated/shop-storage-construction-stage-4.png",
    },
    breakroom={
        "assets/generated/shop-breakroom-construction-stage-1.png",
        "assets/generated/shop-breakroom-construction-stage-2.png",
        "assets/generated/shop-breakroom-construction-stage-3.png",
        "assets/generated/shop-breakroom-construction-stage-4.png",
    },
    floor={
        "assets/generated/shop-floor-construction-stage-1.png",
        "assets/generated/shop-floor-construction-stage-2.png",
        "assets/generated/shop-floor-construction-stage-3.png",
        "assets/generated/shop-floor-construction-stage-4.png",
    },
}
local function near(player,point)
    return type(player)=="table" and type(player.x)=="number" and type(player.y)=="number"
        and (player.x-point.x)^2+(player.y-point.y)^2<=point.radius^2
end
local function ballTargets(targets,player,state)
    for _,ball in ipairs(require("src.basketball").renderRecords(state)) do
        if ball.mode=="placed" and ball.sceneId==Rooms.scene(player) then
            targets["roomBall:"..ball.bayId]={kind="roomGame",fixtureId="basketball",ball=true,
                x=ball.x,y=ball.y,radius=59,hoverX=ball.x,hoverY=ball.y-10,
                hoverRadius=30,prompt="E: pick up basketball"}
        end
    end
end
function Rooms.scene(player) return player and player.sceneId or "warehouse" end
function Rooms.sameScene(a,b) return Rooms.scene(a)==Rooms.scene(b) end
function Rooms.employeeScene(entry)
    local actor=entry.actor
    return actor.phase=="break" and actor.seatBay or "warehouse"
end
function Rooms.bayStatus(state,id)
    local warehouse=state and state.warehouse
    return warehouse and warehouse.bays and warehouse.bays[id]
end
function Rooms.isComplete(state,id)
    local bay=Rooms.bayStatus(state,id)
    return bay and bay.status=="complete" or false
end
function Rooms.isBuilding(state,id)
    local bay=Rooms.bayStatus(state,id)
    return bay and bay.status=="building" or false
end
function Rooms.constructionStage(state,id)
    if not Rooms.isBuilding(state,id) then return nil end
    local project=Layout.project(state,id)
    local stage=project and tonumber(project.stage) or 1
    return math.max(1,math.min(4,math.floor(stage)))
end
function Rooms.definition(state,id)
    local bay=state and state.warehouse and state.warehouse.bays[id]
    return bay and (bay.status=="building" or bay.status=="complete") and bay.optionId or nil
end
function Rooms.name(state,id)
    if id=="warehouse" then return "Warehouse" end
    local kind=Rooms.definition(state,id)
    local name=(kind=="storage" and "Storage room" or kind=="breakroom" and "Break room" or "Utility room")
        .. (id=="front_left" and " A" or " B")
    return name..(Rooms.isBuilding(state,id) and " - Under construction" or "")
end
function Rooms.walkable(x,y,sceneId,kind)
    return Registration.walkable(x,y,(not sceneId or sceneId=="warehouse") and "warehouse" or kind or "floor")
end
function Rooms.assets(assets,sceneId,state)
    if not assets then return nil end
    sceneId=sceneId or "warehouse"
    local kind=sceneId=="warehouse" and "warehouse" or Rooms.definition(state,sceneId) or "floor"
    if rawget(assets,"_shopRoomScene")==sceneId and rawget(assets,"_shopRoomKind")==kind then return assets end
    assets=rawget(assets,"_shopRoomSource") or assets
    local scenes=adapters[assets]
    if not scenes then scenes=setmetatable({}, {__mode="v"});adapters[assets]=scenes end
    local key=sceneId..":"..kind
    if scenes[key] then return scenes[key] end
    local mask={}
    function mask:getDimensions() return 1536,1024 end
    function mask:getPixel(px,py)
        local value=Rooms.walkable(px*960/1536,py*678/1024,sceneId,kind) and 1 or 0
        return value,value,value,1
    end
    local adapted=setmetatable({_shopRoomSource=assets,_shopRoomScene=sceneId,_shopRoomKind=kind,getData=function(name)
        if name=="walkmask" then return mask end
        return assets.getData and assets.getData(name)
    end},{__index=assets})
    scenes[key]=adapted
    return adapted
end
function Rooms.obstacles(state,sceneId)
    if Rooms.isComplete(state,sceneId) and Rooms.definition(state,sceneId)=="breakroom" then
        local result=Registration.obstacles("breakroom")
        for _,id in ipairs(Games.ORDER) do
            if Games.owns(state,sceneId,id) then
                local fixture=Games.CATALOG[id]
                result[#result+1]={x=fixture.x,y=fixture.y,halfWidth=fixture.width/2,
                    halfHeight=fixture.depth/2,kind="breakroom_game"}
            end
        end
        return result
    end
    return {}
end
function Rooms.targets(player,state)
    if Rooms.scene(player)=="warehouse" then
        local jack=state and state.palletJack
        local mounted=jack and jack.operating and jack.operatorPlayerId==(tonumber(player and player.id) or 1)
        local targets={shopEntrance={kind="shopEntrance",x=Rooms.roomEntrance.x,y=Rooms.roomEntrance.y,
            radius=mounted and 82 or Rooms.roomEntrance.radius,hoverX=Rooms.roomEntrance.hoverX,
            hoverY=Rooms.roomEntrance.hoverY,hoverRadius=Rooms.roomEntrance.hoverRadius,
            prompt="E: choose an expansion room"}}
        ballTargets(targets,player,state)
        return targets
    end
    local jack=state and state.palletJack
    local mounted=jack and jack.operating and jack.operatorPlayerId==(tonumber(player and player.id) or 1)
    local targets={shopEntrance={kind="shopEntrance",x=Rooms.exit.x,y=Rooms.exit.y,
        radius=mounted and 82 or Rooms.exit.radius,hoverX=Rooms.exit.hoverX,hoverY=Rooms.exit.hoverY,
        hoverRadius=Rooms.exit.hoverRadius,prompt="E: return to the warehouse"}}
    local kind=Rooms.definition(state,Rooms.scene(player))
    if Rooms.isComplete(state,Rooms.scene(player)) and kind=="storage" then targets.roomStock={kind="roomStock",x=Rooms.shelves.x,y=Rooms.shelves.y,
        radius=Rooms.shelves.radius,hoverX=Rooms.shelves.hoverX,hoverY=Rooms.shelves.hoverY,
        hoverRadius=Rooms.shelves.hoverRadius,prompt="E: manage stored shop stock"} end
    if Rooms.isComplete(state,Rooms.scene(player)) and kind=="breakroom" then
        for _,id in ipairs(Games.ORDER) do
            if Games.owns(state,Rooms.scene(player),id) then
                local fixture=Games.CATALOG[id]
                targets["roomGame:"..id]={kind="roomGame",fixtureId=id,
                    x=fixture.interactionX,y=fixture.interactionY,radius=65,
                    hoverX=fixture.x,hoverY=fixture.y-45,hoverRadius=52,
                    prompt=id=="basketball" and "E: start or join a basketball contest"
                        or ("E: play "..fixture.name)}
            end
        end
        targets.roomRest={kind="roomRest",x=player.resting and player.x or Rooms.rest.x,y=player.resting and player.y or Rooms.rest.y,
        radius=Rooms.rest.radius,hoverX=player.resting and player.x or Rooms.rest.hoverX,
        hoverY=player.resting and player.y-28 or Rooms.rest.hoverY,
        hoverRadius=Rooms.rest.hoverRadius,prompt=player.resting and "E: stand up" or "E: take a break"}
    end
    ballTargets(targets,player,state)
    return targets
end
local function operating(player,state)
    for _,key in ipairs({"palletJack","forklift"}) do
        local vehicle=state[key]
        if vehicle and vehicle.operating and vehicle.operatorPlayerId==(player.id or 1) then return true end
    end
    return false
end
local function movingAttachedMachine(state)
    return require("src.machine_transport").active(state) ~= nil
end
local function moveJackBetweenScenes(state,dx,dy,destination)
    local jack=state and state.palletJack
    if not jack then return end
    jack.x,jack.y=jack.x+dx,jack.y+dy
    jack.sceneId=destination
    if jack.carriedPalletId then
        local item=require("src.pallet_state").find(state,jack.carriedPalletId)
        local world=item and item.pallet.world
        if world then
            world.x,world.y=world.x+dx,world.y+dy
            world.fromX,world.fromY=world.x,world.y
            world.sceneId=destination
            world.spawnProgress=1
        end
    end
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
    local jack=state and state.palletJack
    local playerId=tonumber(player.id) or 1
    local ownsJack=jack and jack.operating and jack.operatorPlayerId==playerId
    local ownsForklift=state and state.forklift and state.forklift.operating
        and state.forklift.operatorPlayerId==playerId
    if ownsForklift or operating(player,state) and not ownsJack or movingAttachedMachine(state) then
        return false,"park_first","Place the moving equipment before entering a room."
    end
    if ownsJack and jack.moving then return false,"stop_first","Stop the pallet jack at the doorway first." end
    local doorway=current=="warehouse" and Rooms.roomEntrance or Rooms.exit
    if current=="warehouse" then
        if not near(player,doorway) and not (ownsJack and near(jack,doorway)) then
            return false,"out_of_range","Use the wide expansion doorway to enter another room."
        end
        if ownsJack and not near(jack,{x=doorway.x,y=doorway.y,radius=doorway.radius+34}) then
            return false,"out_of_range","Bring the pallet jack to the expansion doorway first."
        end
        if not Rooms.definition(state,destination) then return false,"room_locked","Wait until construction starts before entering this room." end
    elseif destination~="warehouse" or not near(player,doorway) and not (ownsJack and near(jack,doorway)) then
        return false,"out_of_range","Use the room's exit to return to the warehouse."
    elseif ownsJack and not near(jack,{x=doorway.x,y=doorway.y,radius=doorway.radius+34}) then
        return false,"out_of_range","Bring the pallet jack to the room exit first."
    end
    local point=destination=="warehouse"
        and {x=Rooms.roomEntrance.x,y=Rooms.roomEntrance.y+46}
        or {x=Rooms.exit.x,y=Rooms.exit.y+38}
    local dx,dy=point.x-player.x,point.y-player.y
    if ownsJack then moveJackBetweenScenes(state,dx,dy,destination) end
    player.sceneId=destination
    player.x,player.y=point.x,point.y
    require("src.basketball").onTransition(state,player,destination)
    player.velocityX,player.velocityY,player.moving,player.resting=0,0,false,false
    player._restOrigin=nil
    player.animationDistance,player.idleClock=0,0
    return true,"accepted","Entered "..Rooms.name(state,destination).."."
end
function Rooms.stockItems(state,sceneId)
    if not Rooms.isComplete(state,sceneId) or Rooms.definition(state,sceneId)~="storage" then return {} end
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
    if not Rooms.isComplete(state,sceneId) or Rooms.definition(state,sceneId)~="storage" or not near(player,Rooms.shelves) then
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
        if not Rooms.isComplete(state,Rooms.scene(player)) or Rooms.definition(state,Rooms.scene(player))~="breakroom"
            or not player.resting and not near(player,Rooms.rest) then
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
