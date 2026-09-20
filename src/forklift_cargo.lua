-- Trusted host adapter only. World clearance is mandatory; wire authorization,
-- purchase/spawn, input, persistence and rendering remain caller responsibilities.
local Forklift = require("src.forklift")
local PalletState = require("src.pallet_state")
local Storage = require("src.pallet_storage")
local Upgrades = require("src.warehouse_upgrades")
local Cargo = {}
local FLOOR = {warehouse=true,cutter_output=true,press_output=true}
local ROTATIONS = {northwest=1,north=1,northeast=2,east=2,southeast=4,south=4,southwest=3,west=3}
local MAX_COORDINATE, GROUND_EPSILON = 1000000, 0.000001
local VIEW_FIELDS = {"owned","x","y","direction","operating","operatorPlayerId","carriedPalletId",
    "moving","animationDistance","forkHeight","targetForkHeight","lifting"}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end
local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function coordinate(value) return finite(value) and math.abs(value)<=MAX_COORDINATE end
local function playerId(value) return finite(value) and value==math.floor(value) and value>=1 and value<=4 end
local function radius(config,name)
    local value=type(config)=="table" and config[name]
    if value==nil then return 24 end
    if finite(value) and value>=0 and value<=128 then return value end
end
local function near(x,y,anchorX,anchorY,distance)
    return (x-anchorX)^2+(y-anchorY)^2<=distance^2
end
local function validState(state,config)
    if type(state)~="table" or not Forklift.validState(state.forklift,config)
        or not Upgrades.validate(state.warehouse) then return false end
    local okay,valid=pcall(PalletState.validate,state)
    return okay and valid==true
end
local function sameVehicle(left,right)
    if type(right)~="table" then return false end
    for _,field in ipairs(VIEW_FIELDS) do if left[field]~=right[field] then return false end end
    return true
end
local function worldAt(pallet,lift,x,y)
    local world=copy(pallet.world or {})
    world.x,world.y,world.fromX,world.fromY=x,y,x,y
    world.direction,world.rotation,world.spawnProgress=lift.direction,ROTATIONS[lift.direction],1
    return world
end

-- Produces (palletId, "attach"/"detach", detachedVehicleView) -> boolean, code
-- for Forklift.attachCargo/detachCargo. Callbacks below must be synchronous and
-- read-only. They receive detached data, never the mutable pallet/vehicle.
function Cargo.callback(state,config,operator,options)
    options=type(options)=="table" and options or {}
    local validateWorld,dropPosition=options.validateWorld,options.dropPosition
    return function(id,action,vehicleView)
        if action~="attach" and action~="detach" then return false,"invalid_action" end
        if type(id)~="string" or id=="" or #id>128 or id:find("%c") then
            return false,"invalid_pallet"
        end
        if not playerId(operator) then return false,"invalid_operator" end
        if type(validateWorld)~="function" then return false,"world_validator_required" end
        if dropPosition~=nil and type(dropPosition)~="function" then return false,"invalid_drop_resolver" end
        local pickupRadius,dropRadius=radius(config,"floorPickupRadius"),radius(config,"floorDropRadius")
        if not pickupRadius or not dropRadius then return false,"invalid_transfer_config" end
        if not validState(state,config) then return false,"invalid_state" end
        local lift=state.forklift
        if not lift.owned or not state.warehouse.forkliftOwned then return false,"not_owned" end
        if not lift.operating or lift.operatorPlayerId~=operator then return false,"not_owner" end
        if not sameVehicle(lift,vehicleView) then return false,"stale_vehicle" end
        if lift.moving or lift.lifting then return false,"not_stationary" end
        if lift.forkHeight>GROUND_EPSILON or lift.targetForkHeight>GROUND_EPSILON then
            return false,"lower_forks_first"
        end
        local item=PalletState.find(state,id)
        if not item then return false,"missing_pallet" end
        local pallet=item.pallet
        if Storage.isSupporting(state,id) then return false,"supporting_pallet" end
        if action=="attach" then
            if lift.carriedPalletId then return false,"cargo_occupied" end
            if not FLOOR[pallet.location] or item.vendor and pallet.location~="warehouse" then
                return false,"not_floor_stock"
            end
        elseif lift.carriedPalletId~=id or pallet.location~="on_forklift" then
            return false,"wrong_pallet"
        end
        if type(pallet.world)~="table" or not coordinate(pallet.world.x) or not coordinate(pallet.world.y) then
            return false,"invalid_pallet_position"
        end
        if action=="attach" and pallet.world.spawnProgress~=nil and pallet.world.spawnProgress~=1 then
            return false,"pallet_in_motion"
        end
        -- dropPosition normalizes its argument; use a detached vehicle so even
        -- an invalid/refused request cannot normalize the authoritative object.
        local forkX,forkY=Forklift.dropPosition({forklift=copy(lift)},config)
        if not coordinate(forkX) or not coordinate(forkY) then return false,"invalid_fork_position" end
        local x,y=pallet.world.x,pallet.world.y
        if action=="detach" then
            x,y=forkX,forkY
            if dropPosition then
                local okay,nextX,nextY=pcall(dropPosition,forkX,forkY,copy(lift))
                if not okay then return false,"drop_resolution_failed" end
                x,y=nextX,nextY
            end
        end
        if not coordinate(x) or not coordinate(y) then return false,"invalid_target" end
        if not near(x,y,forkX,forkY,action=="attach" and pickupRadius or dropRadius) then
            return false,"out_of_range"
        end
        local query={action=action,palletId=id,playerId=operator,x=x,y=y,forkX=forkX,forkY=forkY,
            vehicle=copy(lift),pallet=copy(pallet),vendor=item.vendor==true}
        local called,allowed,reason=pcall(validateWorld,query)
        if not called then return false,"world_validation_failed" end
        if allowed~=true then return false,type(reason)=="string" and reason or "blocked" end
        -- All trusted world checks are complete. PalletState owns both ends of
        -- this single transition and rolls back any canonical validation refusal.
        local previousWorld=pallet.world
        local target=action=="attach" and "on_forklift" or "warehouse"
        local world=worldAt(pallet,lift,action=="attach" and lift.x or x,action=="attach" and lift.y or y)
        local moved,transitionError=PalletState.transition(state,pallet,target,{world=world})
        if not moved then
            pallet.world=previousWorld -- preserve the exact pre-transfer reference too
            return false,transitionError
        end
        return true,action=="attach" and "attached" or "detached"
    end
end

-- Invoke after authoritative movement and before broadcasting its resulting
-- pose. The vehicle's height drives visual lift; pallet.world stores the same
-- ground-plane vehicle anchor as other canonical on-vehicle placements.
function Cargo.sync(state,config)
    if not validState(state,config) then return false,"invalid_state" end
    local lift=state.forklift
    if not lift.carriedPalletId then return false,"empty" end
    if not lift.owned or not state.warehouse.forkliftOwned then return false,"not_owned" end
    local item=PalletState.find(state,lift.carriedPalletId)
    if not item or item.pallet.location~="on_forklift" then return false,"wrong_pallet" end
    local world=item.pallet.world
    local fields={x=lift.x,y=lift.y,fromX=lift.x,fromY=lift.y,direction=lift.direction,
        rotation=ROTATIONS[lift.direction],spawnProgress=1}
    local changed=false
    for key,value in pairs(fields) do if world[key]~=value then changed=true end end
    if not changed then return false,"unchanged" end
    for key,value in pairs(fields) do world[key]=value end
    return true,"synced"
end

return Cargo
