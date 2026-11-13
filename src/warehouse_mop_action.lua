-- The worker keeps walking while the authored mop pose loops. Each step
-- removes a saved patch from the spill beneath the mop rather than completing
-- a timed, stationary animation.
local Condition=require("src.warehouse_condition")
local Animation=require("src.character_animation")
local Mop=require("src.home_mop_art")
local Motion=require("src.warehouse_mop_motion")
local Action={DURATION=Mop.duration}

local function selectedDirection(player)
    local x=tonumber(player.intentX) or tonumber(player.facing) or 1
    local y=tonumber(player.intentY) or 0
    if x*x+y*y<.0001 then x=tonumber(player.facing) or 1;y=0 end
    return Animation.authoredDirection(x,y)
end

function Action.active(player)
    return type(player)=="table" and type(player._warehouseMopAction)=="table"
end

function Action.begin(Runtime,command)
    local player=Runtime.World.player
    if Action.active(player) then return false,"Stop mopping before starting another spill." end
    local name=type(command)=="string" and command:match("^clean_(puddle%d+)$")
    local c=Condition.of(Runtime.state)
    local point=name and Condition.anchors[name]
    if not point or not Condition.valid(c) or c.mode~="story" or c.cleanedPuddles[name] then
        return false,"This floor spill is already clean or unavailable."
    end
    if player.sceneId~="warehouse"
        or not Condition.spillFootprint(name,player.x,player.y) then
        return false,"Stand in the oily puddle before starting to mop."
    end
    if player.character~="rabbit-worker" then
        return false,"This mop animation is authored for the rabbit worker."
    end
    local jack=Runtime.state.palletJack
    if jack and jack.operating and jack.operatorPlayerId==(tonumber(player.id) or 1) then
        return false,"Park the pallet jack before mopping."
    end
    if Runtime.Forklift and Runtime.Forklift.isOperator
        and Runtime.Forklift.isOperator(Runtime.state,Runtime.Config.forklift,tonumber(player.id) or 1) then
        return false,"Park the forklift before mopping."
    end
    player._warehouseMopAction={puddle=name,direction=selectedDirection(player),elapsed=0,
        lastX=player.x,lastY=player.y,stampsSinceSave=0,runtime=Runtime}
    Runtime.World.selectedInteraction=nil
    Runtime.state.screen="world"
    Runtime.state.message="Move the mop across the spill. Repeated passes fade the water away."
    return true
end

function Action.pose(player)
    local task=player and player._warehouseMopAction
    if not task then return nil end
    return {routine="mop",direction=task.direction,frame=Mop.frame(task.elapsed),
        elapsed=task.elapsed,duration=Mop.duration,puddle=task.puddle}
end

function Action.draw(player)
    local pose=Action.pose(player)
    if not pose or player.character~="rabbit-worker" then return false end
    return Mop.draw(pose.direction,pose.frame,player.x,player.y,player)~=false
end

function Action.stop(Runtime,finished,state)
    local player=Runtime.World.player
    if not Action.active(player) then return false end
    local task=player._warehouseMopAction
    local app=task.runtime or Runtime
    state=state or app.state
    local name=task.puddle
    player._warehouseMopAction=nil
    app.World.selectedInteraction=nil
    state.message=finished and "Floor spill cleaned."
        or "Mopping paused. The faded water stays where you wiped it; return to finish the spill."
    if app.saveCurrent and not (app.multiplayer and app.multiplayer:isClient()) then
        app.saveCurrent(true)
    end
    Mop.release()
    return true
end

function Action.update(Runtime,dt,state)
    local player=Runtime.World.player
    local task=player and player._warehouseMopAction
    if not task then return false end
    local app=task.runtime or Runtime
    local condition=Condition.of(state or app.state)
    if condition and condition.cleanedPuddles[task.puddle] then
        Action.stop(Runtime,true,state)
        return true
    end
    local guest=app.multiplayer and app.multiplayer:isClient()
    if player.moving then task.direction=selectedDirection(player) end
    local startX,startY=task.lastX,task.lastY
    local changed,done=Motion.advance(state or app.state,task,player,dt,startX,startY,
        player.x,player.y,guest)
    task.stampsSinceSave=task.stampsSinceSave+changed
    if done then Action.stop(Runtime,true,state);return true end
    task.lastX,task.lastY=player.x,player.y
    if task.stampsSinceSave>=8 then
        task.stampsSinceSave=0
        local app=task.runtime or Runtime
        if app.saveCurrent and not (app.multiplayer and app.multiplayer:isClient()) then
            app.saveCurrent()
        end
    end
    Runtime.World.selectedInteraction=nil
    return true
end

return Action
