-- Shared physical warehouse decisions. World supplies its current collision
-- obstacles; no client menu coordinates or inventory copies are trusted here.
local Config=require("src.config")
local Layout=require("src.warehouse_layout")
local Forklift=require("src.forklift")
local Cargo=require("src.forklift_cargo")
local Storage=require("src.pallet_storage")
local Pallets=require("src.pallet_state")
local Navigation=require("src.navigation")
local Intent=require("src.warehouse_intent")
local Construction=require("src.warehouse_construction")
local Gameplay={}
local FLOOR={warehouse=true,cutter_output=true,press_output=true}
local VECTORS={northwest={-1,-1},north={0,-1},northeast={1,-1},east={1,0},southeast={1,1},south={0,1},southwest={-1,1},west={-1,0}}
local MESSAGES={mounted="Operating forklift. Stop, then lower forks to pick up a skid; raise to travel before driving.",
    parked="Forklift parked.",parked_loaded="Forklift parked with its load safely lowered.",
    lifting="Forks moving to the selected height.",already_targeted="Forks are already at that height.",
    attached="Pallet picked up. Raise forks to travel height before driving.",detached="Pallet placed on the warehouse floor.",
    store="Pallet stored on the shelf.",retrieve="Pallet retrieved. Set travel height before driving.",replayed="This transfer was already completed.",
    stack="Pallet stacked two high. The lower skid must stay in place until the top is removed.",
    unstack="Top pallet retrieved. Set travel height before driving.",
    not_stackable="Only customer paper skids can be stacked; other supplies need their own floor space.",
    incompatible_footprint="These skids have different footprints. Stack matching-size skids only.",
    supporting_pallet="Take the top pallet off before moving the lower skid.",
    support_occupied="That skid already has a pallet on top. Floor stacks are limited to two high.",
    invalid_support="Choose another floor skid as the base of the stack.",wrong_stack="The selected upper pallet no longer belongs to that stack.",
    vehicle_not_stationary="Stop the forklift before transferring a pallet.",lift_in_progress="Wait for the forks to finish moving.",
    lower_forks_first="Lower the forks fully before this action.",raise_to_travel_height="Raise the load to travel height first.",
    wrong_fork_height="Set forks to ground for the lower shelf, or full height for the upper shelf / floor stack.",
    not_stationary="Stop driving and wait for the forks to finish moving.",moving="Stop the forklift first.",
    not_aligned="Face the rack or pallet with the forks before transferring it.",out_of_range="Move closer to the forklift or rack loading position.",
    blocked="That space is blocked. Clear the loading area first.",no_exit="There is no clear place to step out. Move to an open area first.",
    not_owner="Only the worker operating this forklift can use its controls.",busy="Another worker is operating this forklift.",
    not_owned="Buy the forklift from CritterNet first.",delivery_blocked="Clear the forklift delivery area in the center-front of the warehouse.",
    forklift_required="A forklift is required to use the upper row.",not_operator="Operate a pallet jack or forklift before transferring stock.",
    no_pallet="Move the lowered forks up to a floor pallet.",slot_occupied="That shelf already contains a pallet.",
    stale_revision="The shelves changed. Select the space again.",already_operating_vehicle="Park the pallet jack before operating the forklift.",
    wrong_vehicle="The requested vehicle is not the one you are operating.",rack_unavailable="That storage upgrade is not complete yet."}
local function message(code) return MESSAGES[code] or ("Warehouse action unavailable: "..tostring(code)..".") end
local function enabled() return not Config.warehouse or Config.warehouse.enabled~=false end
local function id(player)
    local value=type(player)=="table" and player.id
    if type(value)=="number" and value==math.floor(value) and value>=1 and value<=4 then return value end
end
local function near(x,y,tx,ty,r) return (x-tx)^2+(y-ty)^2<=r*r end
local function config(key,fallback) return Config.forklift and Config.forklift[key] or fallback end
local function forkPosition(state)
    -- Forklift.dropPosition normalizes its input. Targeting/validation must not
    -- rewrite the live moving or lifting flags before the domain checks them.
    local detached={}
    for key,value in pairs(state.forklift or {}) do detached[key]=value end
    return Forklift.dropPosition({forklift=detached},Config.forklift)
end
local function completeRack(state,rackId)
    local rack=state.storage and state.storage.racks and state.storage.racks[rackId]
    local bay=rack and Layout.bayState(state,rack.bayId)
    return rack and bay and bay.status=="complete" and bay.optionId=="storage"
end
local function footprint(loaded)
    return loaded and config("loadedCollisionHalfWidth",48) or config("collisionHalfWidth",40),
        loaded and config("loadedCollisionHalfHeight",24) or config("collisionHalfHeight",18)
end

-- Keep original core pixels and registration. Only completed extension polygons
-- are added; locked black upgrade spaces stay non-walkable even in maskless tests.
function Gameplay.assets(assets,state)
    if not assets then return nil end
    if assets._warehouseNavigationState==state then return assets end
    if assets._warehouseSource then assets=assets._warehouseSource end
    local original=assets.getData and assets.getData("walkmask")
    local width,height=Config.baseWidth,Config.baseHeight
    if original then width,height=original:getDimensions() end
    local mask={}
    function mask:getDimensions() return width,height end
    function mask:getPixel(px,py)
        local x,y=px/width*Config.baseWidth,py/height*Config.baseHeight
        -- Expansion seams deliberately overlap the old rim. Preserve every
        -- already-walkable core pixel before considering those polygons, or
        -- a locked bay would clip existing machine spawn/recovery space.
        if original then
            local r,g,b,a=original:getPixel(px,py)
            if r>0.9 and g>0.9 and b>0.9 then return r,g,b,a end
            if Layout.containsUnlocked(state,x,y) then return 1,1,1,1 end
            return r,g,b,a
        end
        if Layout.containsUnlocked(state,x,y) then return 1,1,1,1 end
        if Layout.isReserved(state,x,y) then return 0,0,0,1 end
        local okay=x>55 and x<Config.baseWidth-55 and y>90 and y<Config.baseHeight-45
        local value=okay and 1 or 0;return value,value,value,1
    end
    return setmetatable({_warehouseNavigationState=state,_warehouseSource=assets,
        getData=function(name) if name=="walkmask" then return mask end
            return assets.getData and assets.getData(name) end},{__index=assets})
end

local function obstacles(context,state,halfWidth,halfHeight,excludedPallet,excludeLift,excludeJack)
    return context.obstacles(state,excludeJack==true,{x=halfWidth or 0,y=halfHeight or 0},
        false,false,excludedPallet,false,excludeLift==true)
end
local function clear(context,state,x,y,halfWidth,halfHeight,excludedPallet,excludeLift,excludeJack)
    local assets=Gameplay.assets(context.assets,state)
    return assets and Navigation.isAreaWalkable(assets,x,y,halfWidth,halfHeight)
        and Navigation.isWalkable(assets,x,y,obstacles(context,state,halfWidth,halfHeight,excludedPallet,excludeLift,excludeJack))
end
local function facing(vehicle,x,y)
    local vector=VECTORS[vehicle.direction]
    if not vector then return false end
    local dx,dy=x-vehicle.x,y-vehicle.y
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance<1 then return false end
    return (vector[1]*dx+vector[2]*dy)/math.sqrt(vector[1]^2+vector[2]^2)/distance>=0.5
end

function Gameplay.nearRack(player,state)
    if not id(player) then return nil end
    local nearest,best
    for _,bayId in ipairs(Layout.BAY_IDS) do
        local rackId=bayId.."-rack"
        local point=Layout.rackApproach(rackId)
        local distance=(player.x-point.x)^2+(player.y-point.y)^2
        if completeRack(state,rackId) and distance<=130*130 and (not best or distance<best) then nearest,best=rackId,distance end
    end
    return nearest
end

function Gameplay.rackContext(player,state,rackId,context)
    local playerId=id(player)
    local result={playerId=playerId,near=false,aligned=false,clear=false}
    if not playerId or not completeRack(state,rackId) then return result end
    local lift,jack=state.forklift,state.palletJack
    local vehicle
    if lift and lift.operating and lift.operatorPlayerId==playerId then result.vehicle,vehicle="forklift",lift
    elseif jack and jack.operating and jack.operatorPlayerId==playerId then result.vehicle,vehicle="pallet_jack",jack end
    local approach=Layout.rackApproach(rackId)
    local actor=vehicle or player
    result.near=near(actor.x,actor.y,approach.x,approach.y,130)
    if not vehicle then return result end
    local center=Layout.rackPoint(rackId,1,3)
    result.aligned=facing(vehicle,center.x,center.groundY)
    local w,h
    if result.vehicle=="forklift" then w,h=footprint(vehicle.carriedPalletId~=nil)
    else
        local jc=Config.palletJack
        w=vehicle.carriedPalletId and jc.loadedCollisionHalfWidth or jc.collisionHalfWidth
        h=vehicle.carriedPalletId and jc.loadedCollisionHalfHeight or jc.collisionHalfHeight
    end
    result.clear=clear(context,state,vehicle.x,vehicle.y,w,h,vehicle.carriedPalletId,
        result.vehicle=="forklift",result.vehicle=="pallet_jack")==true
    return result
end

function Gameplay.access(player,state,intent,context)
    if not enabled() then return false,"disabled","Warehouse upgrades are not enabled." end
    local playerId=id(player)
    if not playerId or type(state)~="table" then return false,"invalid_player","An authenticated worker is required." end
    local lift=state.forklift
    if intent and (intent.kind=="store" or intent.kind=="retrieve") then
        local access=Gameplay.rackContext(player,state,intent.rackId,context)
        if not access.near then return false,"out_of_range",message("out_of_range") end
        return true,"allowed"
    end
    if not intent then
        if Gameplay.nearRack(player,state) or lift and lift.owned
            and (lift.operatorPlayerId==playerId or near(player.x,player.y,lift.x,lift.y,config("interactionRadius",76))) then return true,"allowed" end
        return false,"out_of_range",message("out_of_range")
    end
    if not lift or not lift.owned then
        local code=state.warehouse and state.warehouse.forkliftOwned and "delivery_blocked" or "not_owned"
        return false,code,message(code)
    end
    if intent.kind=="operate" then
        if not near(player.x,player.y,lift.x,lift.y,config("interactionRadius",76)) then return false,"out_of_range",message("out_of_range") end
    elseif not lift.operating or lift.operatorPlayerId~=playerId then return false,"not_owner",message("not_owner") end
    return true,"allowed"
end

function Gameplay.candidate(state)
    local lift=state and state.forklift
    if not lift or not lift.owned or lift.carriedPalletId then return nil end
    local x,y=forkPosition(state)
    local closest,best
    for _,item in ipairs(Pallets.items(state)) do
        local pallet=item.pallet
        if FLOOR[pallet.location] and pallet.world and (pallet.world.spawnProgress==nil or pallet.world.spawnProgress==1)
            and not Storage.isSupporting(state,pallet.id) then
            local distance=(pallet.world.x-x)^2+(pallet.world.y-y)^2
            if distance<=config("floorPickupRadius",24)^2 and (not best or distance<best) then closest,best=pallet.id,distance end
        end
    end
    return closest
end

-- The support stays on the floor; both the target and all geometry are resolved
-- afresh on the host. This returns IDs for presentation, not trusted access flags.
function Gameplay.stackCandidate(state)
    local lift=state and state.forklift
    if not lift or not lift.owned then return nil end
    local x,y=forkPosition(state)
    local closest,best
    for _,item in ipairs(Pallets.items(state)) do
        local support=item.pallet
        if FLOOR[support.location] and support.world and support.id~=lift.carriedPalletId
            and (support.world.spawnProgress==nil or support.world.spawnProgress==1) then
            local supported,topId=Storage.isSupporting(state,support.id)
            local eligible=lift.carriedPalletId and not supported or not lift.carriedPalletId and supported
            local distance=(support.world.x-x)^2+(support.world.y-y)^2
            if eligible and facing(lift,support.world.x,support.world.y)
                and distance<=config("floorPickupRadius",40)^2 and (not best or distance<best) then
                closest={kind=lift.carriedPalletId and "stack" or "unstack",
                    palletId=lift.carriedPalletId or topId,supportPalletId=support.id}
                best=distance
            end
        end
    end
    return closest
end

local function loadFootprint(item)
    local size=item and item.job and item.job.sourceSize
    if not size then size=item and item.pallet.paper and item.pallet.paper.sourceSize end
    if type(size)~="table" or type(size.width)~="number" or type(size.height)~="number"
        or size.width<=0 or size.height<=0 or size.width>=math.huge or size.height>=math.huge
        or size.width~=size.width or size.height~=size.height then return nil end
    return math.min(size.width,size.height),math.max(size.width,size.height)
end

function Gameplay.stackContext(player,state,intent,context)
    local result={playerId=id(player),near=false,aligned=false,clear=false,stackable=false,compatible=false}
    local lift=state.forklift
    if not result.playerId or not lift or not lift.operating or lift.operatorPlayerId~=result.playerId then return result end
    local supportItem=Storage.find(state,intent.supportPalletId)
    local item=Storage.find(state,intent.palletId)
    local support=supportItem and supportItem.pallet
    if not support or not FLOOR[support.location] or not support.world
        or (support.world.spawnProgress~=nil and support.world.spawnProgress~=1) then return result end
    local forkX,forkY=forkPosition(state)
    result.near=near(forkX,forkY,support.world.x,support.world.y,config("floorPickupRadius",40))
    result.aligned=facing(lift,support.world.x,support.world.y)
    local w,h=Config.palletLogistics.collisionHalfWidth,Config.palletLogistics.collisionHalfHeight
    -- Ignore only the selected support at the destination, but include it in
    -- the vehicle-body check so raised forks cannot authorize driving into it.
    local vw,vh=footprint(true)
    result.clear=clear(context,state,support.world.x,support.world.y,w,h,support.id,true,false)
        and clear(context,state,lift.x,lift.y,vw,vh,nil,true,false)==true
    result.stackable=item and not item.vendor and not supportItem.vendor
        and type(item.pallet.paper)=="table" and type(support.paper)=="table" or false
    local aw,ah=loadFootprint(item)
    local bw,bh=loadFootprint(supportItem)
    result.compatible=aw~=nil and bw~=nil and math.abs(aw-bw)<0.001 and math.abs(ah-bh)<0.001
    return result
end

function Gameplay.command(player,state,rawIntent,context)
    local intent,errorMessage=Intent.normalize(rawIntent)
    if not intent then return false,"invalid_warehouse_action",errorMessage end
    local allowed,code,text=Gameplay.access(player,state,intent,context)
    if not allowed then return false,code,text end
    local playerId=id(player)
    local okay
    if intent.kind=="operate" then
        okay,code=Forklift.acquire(state,Config.forklift,playerId)
        if okay then player.x,player.y=Forklift.operatorPosition(state,Config.forklift) end
    elseif intent.kind=="release" then
        local lift=state.forklift
        local exit
        for _,offset in ipairs({{0,48},{0,-48},{64,0},{-64,0},{64,48},{-64,48},{64,-48},{-64,-48}}) do
            local x,y=lift.x+offset[1],lift.y+offset[2]
            if clear(context,state,x,y,6,3,nil,false,false) then exit={x=x,y=y};break end
        end
        if not exit then return false,"no_exit",message("no_exit") end
        okay,code=Forklift.release(state,Config.forklift,playerId)
        if okay then player.x,player.y=exit.x,exit.y;player.moving=false;player.velocityX,player.velocityY=0,0 end
    elseif intent.kind=="set_height" then okay,code=Forklift.setForkHeight(state,Config.forklift,playerId,intent.height)
    elseif intent.kind=="pickup" or intent.kind=="drop" then
        local palletId=intent.kind=="pickup" and intent.palletId or state.forklift.carriedPalletId
        if not palletId then return false,"no_pallet",message("no_pallet") end
        local transfer=Cargo.callback(state,Config.forklift or {},playerId,{validateWorld=function(query)
            if not facing(query.vehicle,query.x,query.y) then return false,"not_aligned" end
            local w,h=Config.palletLogistics.collisionHalfWidth,Config.palletLogistics.collisionHalfHeight
            if not clear(context,state,query.x,query.y,w,h,query.palletId,true,false) then return false,"blocked" end
            local vw,vh=footprint(query.action=="attach")
            if not clear(context,state,query.vehicle.x,query.vehicle.y,vw,vh,query.palletId,true,false) then return false,"blocked" end
            return true
        end})
        if intent.kind=="pickup" then okay,code=Forklift.attachCargo(state,Config.forklift,playerId,palletId,transfer)
        else okay,code=Forklift.detachCargo(state,Config.forklift,playerId,palletId,transfer) end
    elseif intent.kind=="stack" or intent.kind=="unstack" then
        local access=Gameplay.stackContext(player,state,intent,context)
        local request={action=intent.kind}
        for key,value in pairs(intent) do if key~="kind" then request[key]=value end end
        okay,code=Storage.apply(state,request,access)
        if okay and code~="replayed" then Cargo.sync(state,Config.forklift) end
    else
        local access=Gameplay.rackContext(player,state,intent.rackId,context)
        if access.vehicle~=intent.vehicle then return false,"wrong_vehicle",message("wrong_vehicle") end
        local request={action=intent.kind}
        for key,value in pairs(intent) do if key~="kind" then request[key]=value end end
        okay,code=Storage.apply(state,request,access)
    end
    text=message(code)
    state.message=text
    return okay,code,text
end

function Gameplay.move(player,dt,dx,dy,state,context,readOnly)
    if not id(player) or not Forklift.isOperator(state,Config.forklift,player.id) then return false end
    local lift=state.forklift
    if not readOnly then
        local assets=Gameplay.assets(context.assets,state)
        Forklift.move(state,dx or 0,dy or 0,math.min(math.max(0,dt or 0),0.1),Config.forklift,function(x,y,loaded)
            local w,h=footprint(loaded)
            return assets and Navigation.canMoveAreaFrom(assets,lift.x,lift.y,x,y,w,h,
                obstacles(context,state,w,h,lift.carriedPalletId,true,false))
        end,player.id)
        Cargo.sync(state,Config.forklift)
    end
    player.x,player.y=Forklift.operatorPosition(state,Config.forklift)
    player.moving=lift.moving
    player.facing=(lift.direction=="northeast" or lift.direction=="east" or lift.direction=="southeast") and 1 or -1
    return true
end

function Gameplay.update(dt,state,context)
    if not enabled() then return false end
    local changed=false
    local lift=Forklift.ensure(state,Config.forklift)
    if state.warehouse and state.warehouse.forkliftOwned and not lift.owned then
        local spawn=Layout.forkliftSpawn()
        local w,h=footprint(false)
        if clear(context,state,spawn.x,spawn.y,w,h,nil,true,false) then
            lift.x,lift.y,lift.direction,lift.owned=spawn.x,spawn.y,spawn.direction,true
            changed=true
        end
    end
    changed=Forklift.update(state,math.max(0,dt or 0),Config.forklift) or changed
    local assets=Gameplay.assets(context.assets,state)
    if assets then
        local worker=Construction.worker(state)
        local constructionChanged,events=Construction.update(state,dt,{workPoint=function(bayId)
            local bay=Layout.bay(bayId);return bay and bay.workPoint.x,bay and bay.workPoint.y end,
            canMove=function(x,y,fromX,fromY)
                local all=obstacles(context,state,0,0,nil,false,false)
                -- The actor must not collide with its own durable visitor.
                for index=#all,1,-1 do if all[index].kind=="construction_worker" then table.remove(all,index) end end
                if fromX and fromY then return Navigation.canMoveFrom(assets,fromX,fromY,x,y,all) end
                return Navigation.isWalkable(assets,x,y,all)
            end})
        changed=constructionChanged or changed
        if type(events)=="table" then
            for _,event in ipairs(events) do
                if event.kind=="work_started" then state.message="The raccoon builder has reached the upgrade area and started the foundation."
                elseif event.kind=="stage_changed" then state.message="Warehouse construction advanced to stage "..event.stage.." of 4."
                elseif event.kind=="construction_complete" then state.message="Warehouse upgrade complete. The new space is ready to use." end
            end
        end
    end
    return changed
end
return Gameplay
