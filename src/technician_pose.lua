-- Compact presentation-only service visit state. Routes and service authority
-- stay in the durable host shop; this array carries only visible motion.
local Codec=require("src.net.codec")
local Animation=require("src.character_animation")
local Config=require("src.config")
local Pose={CYCLE_DISTANCE=Config.technician.walkPixelsPerFrame*8}
local directions={"east","southeast","south","southwest","west","northwest","north","northeast"}
local vectors={{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}
local statuses={"entering","servicing","exiting"}
local function index(values,value)
    for i,v in ipairs(values) do if v==value then return i end end
end
local function integer(value,lo,hi)
    return type(value)=="number" and value==math.floor(value) and value>=lo and value<=hi
end
function Pose.normalize(row)
    if not Codec.isArray(row) or (#row~=0 and #row~=9) then return nil end
    local entries=0
    for key in pairs(row) do if not integer(key,1,#row) then return nil end;entries=entries+1 end
    if entries~=#row then return nil end
    if #row==0 then return Codec.array() end
    local ranges={{1,2},{1,3},{-1000000,1000000},{-1000000,1000000},{1,8},
        {0,Pose.CYCLE_DISTANCE*100-1},{0,3076},{0,15999},{0,1}}
    local result=Codec.array()
    for i,bounds in ipairs(ranges) do
        if not integer(row[i],bounds[1],bounds[2]) then return nil end
        result[i]=row[i]
    end
    if row[2]==2 and row[9]~=0 then return nil end
    return result
end
function Pose.capture(visit)
    if not visit or not visit.visible or visit.status=="scheduled" then return Codec.array() end
    local function q(value) return math.floor(value*100+.5) end
    local legacy=({{-1,0},{0,-1},{0,1},{1,0}})[visit.directionFrame or 4] or {1,0}
    return Pose.normalize(Codec.array({visit.species=="lizard" and 2 or 1,index(statuses,visit.status),
        q(visit.x),q(visit.y),index(directions,Animation.authoredDirection(visit.intentX or legacy[1],visit.intentY or legacy[2])),
        math.floor(((visit.animationDistance or 0)%Pose.CYCLE_DISTANCE)*100),
        math.floor(((visit.idleClock or 0)%(2/.65))*1000),
        math.floor(((visit.animationClock or 0)%16)*1000),visit.inMotion and 1 or 0}))
end
function Pose.actor(row)
    row=Pose.normalize(row)
    if not row then return nil end
    if #row==0 then return false end
    local v=vectors[row[5]]
    return {visible=true,species=row[1]==2 and "lizard" or "mouse",kind=row[1]==2 and "windmill" or "cutter",
        status=statuses[row[2]],x=row[3]/100,y=row[4]/100,intentX=v[1],intentY=v[2],
        directionFrame=math.abs(v[1])>=math.abs(v[2]) and (v[1]<0 and 1 or 4) or (v[2]<0 and 2 or 3),
        facing=v[1]<0 and -1 or 1,animationDistance=row[6]/100,idleClock=row[7]/1000,
        animationClock=row[8]/1000,inMotion=row[9]==1}
end
return Pose
