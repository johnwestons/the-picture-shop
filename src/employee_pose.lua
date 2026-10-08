-- Compact host-owned NPC poses travel with realtime environment updates.
-- Contracts, assignments and money remain in the reliable shop snapshot.
local Codec=require("src.net.codec")
local Animation=require("src.character_animation")
local Speech=require("src.employee_speech")
local Pose={}
local directions={"east","southeast","south","southwest","west","northwest","north","northeast"}
local vectors={{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}
local phases={"hidden","entering","waiting","leaving","idle","walking","working","break_walk","break","pushing"}
local function index(values,value)
    for i,v in ipairs(values) do if v==value then return i end end
    return 1
end
local function int(n,low,high)
    return type(n)=="number" and n==math.floor(n) and n>=low and n<=high
end
local function dense(t,n)
    if type(t)~="table" or #t~=n then return false end
    local count=0
    for k in pairs(t) do if not int(k,1,n) then return false end;count=count+1 end
    return count==n
end
function Pose.normalize(rows)
    if type(rows)~="table" or #rows>11 or not dense(rows,#rows) then return nil end
    local out,ids=Codec.array(),{}
    local ranges={{0,96000},{0,67800},{1,8},{0,15999},{0,12999},{0,1},{1,10},{0,4},{0,2},{0,1000},{0,Speech.MAX_CODE}}
    for _,r in ipairs(rows) do
        if not dense(r,12) or type(r[1])~="string" or #r[1]>16
            or not (r[1]:match("^APP%-%d+$") or r[1]:match("^EMP%-%d+$")) or ids[r[1]] then return nil end
        for k,bounds in ipairs(ranges) do if not int(r[k+1],bounds[1],bounds[2]) then return nil end end
        ids[r[1]]=true
        local row=Codec.array();for i=1,12 do row[i]=r[i] end
        out[#out+1]=row
    end
    return out
end
function Pose.capture(entries)
    local rows=Codec.array()
    for _,entry in ipairs(entries) do
        local a=entry.actor
        local function q(n) return math.floor(n*100+.5) end
        rows[#rows+1]=Codec.array({(entry.application or entry.worker).id,q(a.x),q(a.y),
            index(directions,Animation.authoredDirection(a.intentX,a.intentY)),
            math.floor(((a.phase=="pushing" and a.jackDistance or a.distance or 0)%(a.phase=="pushing" and 160 or 104))*100),math.floor((a.idleClock%13)*1000),a.moving and 1 or 0,
            index(phases,a.phase),a.workFrame or 0,a.seatBay=="front_left" and 1 or a.seatBay=="front_right" and 2 or 0,
            math.floor((a.breakRemaining or 0)*1000+.5),Speech.code(entry)})
    end
    return Pose.normalize(rows)
end
function Pose.actors(rows)
    local normalized=Pose.normalize(rows)
    if not normalized then return nil end
    local result={}
    for _,r in ipairs(normalized) do
        local v=vectors[r[4]]
        result[r[1]]={visible=true,x=r[2]/100,y=r[3]/100,intentX=v[1],intentY=v[2],
            distance=r[5]/100,jackDistance=phases[r[8]]=="pushing" and r[5]/100 or nil,
            idleClock=r[6]/1000,moving=r[7]==1,phase=phases[r[8]],
            workFrame=r[9]>0 and r[9] or nil,seatBay=r[10]==1 and "front_left" or r[10]==2 and "front_right" or nil,
            breakRemaining=r[11]/1000,speechCode=r[12],
            greetingKind=r[12]>=1 and r[12]<=3 and r[12] or nil}
    end
    return result
end
return Pose
