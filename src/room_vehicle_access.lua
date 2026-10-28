local Config=require("src.config")
local Fleet=require("src.pallet_jack_fleet")
local Footprint=require("src.floor_footprint")
local Access={}
function Access.obstacles(state,scene,excludeJack,excludedPalletId,excludedForklift)
    local result=require("src.shop_rooms").obstacles(state,scene)
    for _,item in ipairs(require("src.pallet_logistics").physicalPallets(state)) do
        if item.pallet.id~=excludedPalletId and (item.pallet.world.sceneId or "warehouse")==scene then
            result[#result+1]={x=item.x,y=item.y-8,halfWidth=Config.palletLogistics.collisionHalfWidth,
                halfHeight=Config.palletLogistics.collisionHalfHeight,shape="diamond"}
        end
    end
    for _,jack in ipairs(Fleet.all(state)) do
        if jack~=excludeJack and (jack.sceneId or "warehouse")==scene then
            result[#result+1]={x=jack.x,y=jack.y-5,
                halfWidth=jack.carriedPalletId and Config.palletJack.loadedCollisionHalfWidth or Config.palletJack.collisionHalfWidth,
                halfHeight=jack.carriedPalletId and Config.palletJack.loadedCollisionHalfHeight or Config.palletJack.collisionHalfHeight,
                shape="diamond"}
        end
    end
    local lift=state.forklift
    if lift and lift~=excludedForklift and lift.owned and (lift.sceneId or "warehouse")==scene then
        result[#result+1]=Footprint.at(lift.x,lift.y,Config.forklift)
    end
    for _,entry in ipairs(require("src.employees").actors(state)) do
        if require("src.shop_rooms").employeeScene(entry)==scene then
            result[#result+1]={x=entry.actor.x,y=entry.actor.y,radius=14,actor=entry.actor}
        end
    end
    return result
end
function Access.landing(assets,scene,vehicle,obstacles)
    local Rooms=require("src.shop_rooms")
    local Navigation=require("src.navigation")
    local width,height=5,5
    if vehicle then
        local c=vehicle.owned and Config.forklift or Config.palletJack
        width=vehicle.carriedPalletId and c.loadedCollisionHalfWidth or c.collisionHalfWidth
        height=vehicle.carriedPalletId and c.loadedCollisionHalfHeight or c.collisionHalfHeight
    end
    local base=scene=="warehouse" and Rooms.roomEntrance or Rooms.exit
    local candidates={}
    -- Both sides are fully inside the walkable floor, beyond the door jamb.
    for _,dy in ipairs({72,96,120}) do
        for _,dx in ipairs({0,32,-32,64,-64}) do
            local x,y=base.x+dx,base.y+dy
            if Navigation.isAreaWalkable(assets,x,y,width,height) then
                local clear=true
                for _,o in ipairs(obstacles or {}) do
                    if Footprint.penetration(Footprint.expand(o,{x=width,y=height,shape="diamond"}),x,y)>0 then clear=false;break end
                end
                if clear then candidates[#candidates+1]={x=x,y=y} end
            end
        end
    end
    return candidates[1]
end
return Access
