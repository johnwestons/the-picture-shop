-- Compact transient pose carried by realtime warehouse environment snapshots.
local Animation=require("src.character_animation")
local Pose={}
local DIRECTIONS={"east","southeast","south","southwest","west","northwest","north","northeast"}
local VECTORS={{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}

local function directionIndex(x,y)
    local direction=Animation.authoredDirection(x,y)
    for index,value in ipairs(DIRECTIONS) do if value==direction then return index end end
    return 1
end

function Pose.capture(actor,status,deliveryId)
    if type(actor)~="table" or actor.visible==false or type(actor.x)~="number" or type(actor.y)~="number" then
        return nil
    end
    local result={
        x=math.floor(actor.x*100+.5),y=math.floor(actor.y*100+.5),
        direction=directionIndex(actor.intentX,actor.intentY),
        distance=math.floor(((actor.animationDistance or actor.distance or 0)%1600)*100+.5),
        idleClock=math.floor(((actor.idleClock or 0)%13)*1000+.5),
        moving=actor.moving==true,
    }
    if status~=nil and deliveryId~=nil then
        result.status=status
        result.deliveryId=tostring(deliveryId)
    end
    return result
end

function Pose.normalize(value)
    if value==nil then return nil end
    if type(value)~="table" then return nil end
    for key in pairs(value) do
        if key~="x" and key~="y" and key~="direction" and key~="distance"
            and key~="idleClock" and key~="moving" and key~="status"
            and key~="deliveryId" then return nil end
    end
    local function integer(number,low,high)
        return type(number)=="number" and number==math.floor(number) and number>=low and number<=high
    end
    if not integer(value.x,0,96000) or not integer(value.y,0,67800)
        or not integer(value.direction,1,8) or not integer(value.distance,0,159999)
        or not integer(value.idleClock,0,12999) or type(value.moving)~="boolean" then return nil end
    local result={x=value.x,y=value.y,direction=value.direction,distance=value.distance,
        idleClock=value.idleClock,moving=value.moving}
    if value.status~=nil or value.deliveryId~=nil then
        if (value.status~="approaching" and value.status~="waiting"
            and value.status~="signed" and value.status~="missed")
            or type(value.deliveryId)~="string" or #value.deliveryId<1 or #value.deliveryId>64 then
            return nil
        end
        result.status=value.status
        result.deliveryId=value.deliveryId
    end
    return result
end

function Pose.actor(value)
    local pose=Pose.normalize(value)
    if not pose then return nil end
    local vector=VECTORS[pose.direction]
    return {visible=true,x=pose.x/100,y=pose.y/100,intentX=vector[1],intentY=vector[2],
        animationDistance=pose.distance/100,distance=pose.distance/100,
        idleClock=pose.idleClock/1000,moving=pose.moving,sceneId="warehouse",
        status=pose.status,deliveryId=pose.deliveryId}
end

return Pose
