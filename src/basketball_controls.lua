local Ball=require("src.basketball")
local Path=require("src.basketball_trajectory")
local Controls={}
local function id(Runtime) return tonumber(Runtime.World.player.id) or 1 end
local function send(Runtime,action,aim)
    if Runtime.multiplayer:isClient() then
        local okay,message=Runtime.multiplayer:requestInteraction("roomGame","basketball:"..action,aim)
        if message then Runtime.state.message=message end
        return okay
    end
    local okay,_,message=Ball.command(Runtime.state,Runtime.World.player,action,aim)
    Runtime.state.message=message
    return okay
end
local function worldPoint(Runtime,x,y)
    if Runtime.App and Runtime.App.cameraTransformsWorld and Runtime.App.cameraTransformsWorld()
        and Runtime.App.mobileCamera then return Runtime.App.mobileCamera:screenToWorld(x,y) end
    return x,y
end
function Controls.start(Runtime,pointer,x,y)
    if Runtime.state.screen~="world" or not Ball.heldBy(Runtime.state,id(Runtime)) then return false end
    if Runtime.basketballCharge then return true end
    if not send(Runtime,"shot_start") then return true end
    local player=Runtime.World.player
    local dx,dy=Path.rim.x-player.x,Path.rim.y-player.y
    local length=math.max(1,math.sqrt(dx*dx+dy*dy))
    player.intentX,player.intentY=dx/length,dy/length
    Runtime.basketballCharge={playerId=id(Runtime),elapsed=0,aimX=0,arcHeight=105,
        startX=player.x,startY=player.y,directionX=Path.rim.x-player.x,
        pointer=pointer,sceneId=player.sceneId or "warehouse"}
    Runtime.state._basketballAim=Runtime.basketballCharge
    if x then Controls.beginDrag(Runtime,x,y,pointer) end
    return true
end
function Controls.beginDrag(Runtime,x,y,pointer)
    local charge=Runtime.basketballCharge
    if not charge then return false end
    x,y=worldPoint(Runtime,x,y)
    charge.drag={x=x,y=y,aimX=charge.aimX,arcHeight=charge.arcHeight,pointer=pointer}
    return true
end
function Controls.drag(Runtime,x,y,pointer)
    local charge=Runtime.basketballCharge
    local drag=charge and charge.drag
    if not drag or drag.pointer~=pointer then return false end
    x,y=worldPoint(Runtime,x,y)
    charge.aimX=math.max(-100,math.min(100,drag.aimX+(x-drag.x)*.65))
    charge.arcHeight=math.max(45,math.min(190,drag.arcHeight-(y-drag.y)*.6))
    if not Runtime.multiplayer:isClient() then
        Ball.setAim(Runtime.state,id(Runtime),charge.aimX,charge.arcHeight)
    end
    return true
end
function Controls.release(Runtime,pointer)
    local charge=Runtime.basketballCharge
    if not charge then return false end
    if pointer and charge.pointer and pointer~=charge.pointer then return false end
    if pointer and not charge.pointer then charge.drag=nil;return true end
    charge.releasePending=charge.releasePending or {aimX=charge.aimX,arcHeight=charge.arcHeight,
        elapsed=math.min(Path.MAX_CHARGE,charge.elapsed)}
    local okay=send(Runtime,"shot_release",charge.releasePending)
    if okay then Controls.clear(Runtime) end
    return true
end
function Controls.clear(Runtime)
    Runtime.basketballCharge=nil
    Runtime.state._basketballAim=nil
    Runtime.basketballAimTouch=nil
end
function Controls.update(dt,Runtime)
    local charge=Runtime.basketballCharge
    if not charge then return end
    if Runtime.state.screen~="world" or charge.playerId~=id(Runtime)
        or charge.sceneId~=(Runtime.World.player.sceneId or "warehouse") then
        Controls.clear(Runtime);return
    end
    if charge.releasePending then Controls.release(Runtime)
    else
        charge.elapsed=math.min(Path.MAX_CHARGE,charge.elapsed+math.max(0,math.min(dt,.2)))
        if charge.elapsed>=Path.MAX_CHARGE then Controls.release(Runtime) end
    end
    if not Runtime.multiplayer:isClient() and not Ball.isCharging(id(Runtime)) then Controls.clear(Runtime) end
end
function Controls.mousepressed(x,y,button,Runtime)
    if Runtime.state.screen~="world" or button~=1 then return false end
    if Runtime.basketballCharge then return Controls.beginDrag(Runtime,x,y,"mouse") end
    local held=Ball.heldBy(Runtime.state,id(Runtime))
    if not held or held.bayId~=(Runtime.World.player.sceneId or "warehouse") then return false end
    -- Avoid claiming HUD buttons; hold/drag starts anywhere on the court.
    if y<145 or x<20 or x>940 then return false end
    return Controls.start(Runtime,"mouse",x,y)
end
function Controls.mousemoved(x,y,Runtime) return Controls.drag(Runtime,x,y,"mouse") end
function Controls.mousereleased(x,y,button,Runtime)
    if button~=1 then return false end
    Controls.drag(Runtime,x,y,"mouse")
    return Controls.release(Runtime,"mouse")
end
function Controls.touchpressed(touch,x,y,Runtime)
    if Runtime.state.screen~="world" then return false end
    if Runtime.basketballCharge then
        if Runtime.basketballAimTouch then return true end
        Runtime.basketballAimTouch=touch
        return Controls.beginDrag(Runtime,x,y,touch)
    end
    local held=Ball.heldBy(Runtime.state,id(Runtime))
    if not held or held.bayId~=(Runtime.World.player.sceneId or "warehouse") or not Runtime.mobileControls then return false end
    -- Keep movement and action buttons available. A court touch goes straight
    -- to aiming rather than the mobile camera's pending tap/pinch recognizer.
    local stick=Runtime.mobileControls.joystick
    if stick and x<=stick.x+stick.radius*1.65 and y>=stick.y-stick.radius*1.65 then return false end
    if Runtime.mobileControls:_buttonAt(x,y) or y<145 then return false end
    local started=Controls.start(Runtime,touch,x,y)
    if Runtime.basketballCharge then Runtime.basketballAimTouch=touch end
    return started
end
function Controls.touchmoved(touch,x,y,Runtime)
    if touch~=Runtime.basketballAimTouch then return false end
    Controls.drag(Runtime,x,y,touch);return true
end
function Controls.touchreleased(touch,x,y,Runtime)
    if touch~=Runtime.basketballAimTouch then return false end
    Controls.drag(Runtime,x,y,touch)
    Controls.release(Runtime,touch);Runtime.basketballAimTouch=nil
    return true
end
return Controls
