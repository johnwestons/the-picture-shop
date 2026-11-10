-- Guidance along the actual road route. Distances are world metres, not pixels.
local Gps={}
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2)end
local function angle(a,b)return math.atan2(b.z-a.z,b.x-a.x)end
local function delta(a,b)return math.atan2(math.sin(b-a),math.cos(b-a))end
function Gps.distance(metres)
    if metres>=1000 then return ('%.1f km'):format(metres/1000) end
    return ('%d m'):format(math.max(0,math.floor(metres+.5)))
end
function Gps.prepare(route)
    local path={points={},at={},length=0,turns={},joinDistance=route and route.joinDistance or 0}
    for _,p in ipairs(route and route.points or {}) do
        local last=path.points[#path.points]
        if not last or distance(last,p)>.01 then
            path.length=path.length+(last and distance(last,p) or 0)
            path.points[#path.points+1]=p;path.at[#path.points]=path.length
        end
    end
    local function sample(at)
        at=math.max(0,math.min(path.length,at))
        local low,high=2,#path.points
        while low<high do
            local middle=math.floor((low+high)/2)
            if path.at[middle]<at then low=middle+1 else high=middle end
        end
        local a,b=path.points[low-1],path.points[low]
        local t=(at-path.at[low-1])/(path.at[low]-path.at[low-1])
        return {x=a.x+(b.x-a.x)*t,z=a.z+(b.z-a.z)*t}
    end
    -- Sample across short road tessellation segments so a curved corner still
    -- produces one instruction rather than dozens of tiny direction changes.
    for i=2,#path.points-1 do
        local at=path.at[i];local p=path.points[i]
        local turn=delta(angle(sample(at-12),p),angle(p,sample(at+12)))
        if math.abs(turn)>=math.rad(35) then
            local previous=path.turns[#path.turns]
            if previous and at-previous.lastAt<18 and turn*previous.angle>0 then
                previous.lastAt=at
                if math.abs(turn)>math.abs(previous.angle) then previous.at,previous.angle,previous.point=at,turn,p end
            else path.turns[#path.turns+1]={at=at,lastAt=at,angle=turn,point=p} end
        end
    end
    return path
end
function Gps.guidance(path,actor)
    local points=path.points
    if #points==0 then return {kind='unavailable',text='No road route',remaining=0,distance=0} end
    local nearest,progress,segment=math.huge,0,2
    for i=2,#points do
        local a,b=points[i-1],points[i];local dx,dz=b.x-a.x,b.z-a.z
        local t=math.max(0,math.min(1,((actor.x-a.x)*dx+(actor.z-a.z)*dz)/(dx*dx+dz*dz)))
        local d=distance(actor,{x=a.x+dx*t,z=a.z+dz*t})
        if d<nearest then nearest,progress,segment=d,path.at[i-1]+t*(path.at[i]-path.at[i-1]),i end
    end
    local remaining=math.max(0,path.length-progress)
    local result={kind='straight',text='Continue',distance=remaining,remaining=remaining,progress=progress}
    if distance(actor,points[#points])<8 and remaining<8 then
        result.kind,result.text,result.distance='arrive','Destination reached',0
    elseif path.joinDistance>8 and progress<path.joinDistance-2 then
        result.kind,result.text,result.distance='rejoin','Join the road',path.joinDistance-progress
    elseif #points<2 or nearest>22 then
        result.kind,result.text,result.distance='rejoin','Join the route',nearest<math.huge and nearest or distance(actor,points[1])
    elseif math.abs(delta(actor.heading or 0,angle(points[segment-1],points[segment])))>math.rad(135)
        and remaining>16 then
        result.kind,result.text,result.distance='uturn','Turn around safely',0
    else
        for _,turn in ipairs(path.turns) do
            if turn.at-progress>=2 then
                result.kind=turn.angle>0 and 'right' or 'left'
                result.text='Turn '..result.kind
                if math.abs(turn.angle)>math.rad(145) then result.kind,result.text='uturn','Turn around safely' end
                result.distance=turn.at-progress;result.turn=turn.point
                break
            end
        end
        if not result.turn and remaining<45 then result.text='Destination ahead' end
    end
    return result
end
return Gps
