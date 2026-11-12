-- A short, transient story restoration task. The saved floor state changes
-- only after the registered mop animation finishes.
local Condition=require("src.warehouse_condition")
local Animation=require("src.character_animation")
local Mop=require("src.home_mop_art")
local Action={DURATION=6}

local function selectedDirection(player)
    local x=tonumber(player.intentX) or tonumber(player.facing) or 1
    local y=tonumber(player.intentY) or 0
    if x*x+y*y<.0001 then x=tonumber(player.facing) or 1;y=0 end
    return Animation.authoredDirection(x,y)
end

local function reasonFor(state,player,command)
    local region=type(command)=="string" and command:match("^clean_(%a+)$")
    local c=Condition.of(state)
    if not region or not Condition.valid(c) or c.mode~="story" then
        return nil,"This floor cannot be mopped right now."
    end
    if c.cleaned[region] then return nil,"This floor region is already clean." end
    if region=="center" and not c.cleaned.west then return nil,"Clean the west area first." end
    if region=="east" and not c.cleaned.center then return nil,"Clean the center area first." end
    local point=Condition.anchors[region]
    if not point or player.sceneId~="warehouse"
        or (player.x-point.x)^2+(player.y-point.y)^2>point.radius^2 then
        return nil,"Move into this floor area before mopping."
    end
    return region
end

function Action.active(player)
    return type(player)=="table" and type(player._warehouseMopAction)=="table"
end

function Action.begin(Runtime,command)
    local player=Runtime.World.player
    if Action.active(player) then return false,"Finish mopping this floor area first." end
    local region,reason=reasonFor(Runtime.state,player,command)
    if not region then return false,reason end
    if player.character~="rabbit-worker" then
        return false,"This mop animation is authored for the rabbit worker."
    end
    local jack=Runtime.state.palletJack
    if jack and jack.operating and jack.operatorPlayerId==(tonumber(player.id) or 1) then
        return false,"Park the pallet jack before cleaning the floor."
    end
    if Runtime.Forklift and Runtime.Forklift.isOperator
        and Runtime.Forklift.isOperator(Runtime.state,Runtime.Config.forklift,tonumber(player.id) or 1) then
        return false,"Park the forklift before cleaning the floor."
    end
    player._warehouseMopAction={command=command,region=region,direction=selectedDirection(player),elapsed=0,
        runtime=Runtime}
    player.moving=false;player.velocityX=0;player.velocityY=0
    Runtime.World.selectedInteraction=nil
    Runtime.state.screen="world"
    Runtime.state.message="Mopping the "..region.." floor..."
    return true
end

function Action.pose(player)
    local task=player and player._warehouseMopAction
    if not task then return nil end
    return {routine="mop",direction=task.direction,frame=Mop.frame(task.elapsed),
        elapsed=task.elapsed,duration=Action.DURATION,region=task.region}
end

function Action.draw(player)
    local pose=Action.pose(player)
    if not pose or player.character~="rabbit-worker" then return false end
    return Mop.draw(pose.direction,pose.frame,player.x,player.y,player)~=false
end

local function finish(Runtime,task,state)
    Runtime=task.runtime or Runtime
    state=state or Runtime.state
    if state and not Runtime.state then Runtime.state=state end
    local player=Runtime.World.player
    local okay,code,message
    local multiplayer=Runtime.multiplayer
    if multiplayer and multiplayer:isClient() then
        okay,message=multiplayer:requestInteraction("restoration",task.command)
    else
        okay,code,message=Runtime.World.performNetworkInteraction(player,Runtime.state,
            "restoration",task.command)
    end
    local Controls=require("src.shop_room_controls")
    Controls.open(Runtime,"restoration",task.command)
    Runtime.state.message=message or (okay and "Floor cleaned: "..task.region.."." or "The floor could not be cleaned.")
    Runtime.World.selectedInteraction=nil
    if okay and not (multiplayer and multiplayer:isClient()) then Runtime.saveCurrent() end
    Mop.release()
    return okay,code
end

function Action.update(Runtime,dt,state)
    local player=Runtime.World.player
    local task=player and player._warehouseMopAction
    if not task then return false end
    task.elapsed=math.min(Action.DURATION,task.elapsed+math.max(0,tonumber(dt) or 0))
    player.moving=false;player.velocityX=0;player.velocityY=0
    Runtime.World.selectedInteraction=nil
    if task.elapsed>=Action.DURATION then
        player._warehouseMopAction=nil
        finish(Runtime,task,state)
    end
    return true
end

return Action
