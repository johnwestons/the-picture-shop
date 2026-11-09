local Rooms=require("src.shop_rooms")
local Fleet=require("src.pallet_jack_fleet")
local Jack=require("src.pallet_jack")
local Config=require("src.config")
local Navigator=require("src.npc_navigation")
local Travel={}
function Travel.step(state,worker,destination,dt,context)
    local scene=worker.sceneId or "warehouse"
    if scene==destination then return true,false end
    local nextScene=scene=="warehouse" and destination or "warehouse"
    if nextScene~="warehouse" and (not Rooms.isComplete(state,nextScene)
        or (Rooms.definition(state,nextScene)~="storage" and Rooms.definition(state,nextScene)~="floor")) then
        worker.activity="Waiting for room access";return false,false
    end
    local jack=Fleet.owned(state,worker.id)
    local doorway=scene=="warehouse" and Rooms.roomEntrance or Rooms.exit
    local goal={x=doorway.x,y=doorway.y+64}
    local reached,blocked
    if jack then reached,blocked=require("src.employee_pallet_jack").move(state,worker,goal,dt,context)
    else reached,blocked=context.move(worker,goal,dt) end
    worker.activity=blocked and "Clear the room doorway" or "Taking pallet jack through room doorway"
    if not reached then return false,false end
    local landing=context.sceneLanding(worker,jack,nextScene)
    if not landing then worker.activity="Clear the far side of the room doorway";return false,false end
    if jack then
        local dx,dy=landing.x-jack.x,landing.y-jack.y
        jack.x,jack.y,jack.sceneId=landing.x,landing.y,nextScene
        local view=Fleet.view(state,jack)
        Jack.stop(view,Config.palletJack)
        if jack.carriedPalletId then
            local p=require("src.pallet_state").find(state,jack.carriedPalletId).pallet
            p.world.x,p.world.y=p.world.x+dx,p.world.y+dy
            p.world.fromX,p.world.fromY,p.world.sceneId=p.world.x,p.world.y,nextScene
        end
        worker.x,worker.y=Jack.operatorPosition(view,Config.palletJack)
    else worker.x,worker.y=landing.x,landing.y end
    worker.sceneId=nextScene
    Navigator.reset(worker)
    if worker._jackNavigator then Navigator.reset(worker._jackNavigator) end
    worker._jackTarget,worker._jackParkingTarget=nil,nil
    worker.moving=false
    return nextScene==destination,true
end
return Travel
