-- World-plane shoe marks for players walking through the streamed town.
-- Terrain and road materials decide whether a step leaves a visible trace.
local Math=require('src.commute.vendor.mathx')
local Terrain=require('src.commute.vendor.terrain')
local FirstPerson=require('src.commute.first_person_camera')
local Tracks={TTL=18,STEP=.62,MAX_PER_PLAYER=48}
Tracks.__index=Tracks

local styles={
    dirt={alpha=.46,color={.20,.13,.085},size=1},
    shore={alpha=.38,color={.34,.27,.17},size=.92},
    meadow={alpha=.19,color={.13,.18,.105},size=.82},
    litter={alpha=.27,color={.24,.17,.105},size=.9},
    moss={alpha=.17,color={.13,.18,.12},size=.83},
    sidewalk={alpha=.045,color={.16,.16,.15},size=.9},
}

function Tracks.new()
    return setmetatable({time=0,players={}},Tracks)
end

local function materialAt(world,x,z)
    local height,support=world:supportHeight(x,z)
    if support=='road' or support=='bridge' or support=='water' then return nil end
    if support=='trail' then return 'dirt',height end
    if support=='sidewalk' then return 'sidewalk',height end
    local _,_,_,kind=Terrain.surface(world,x,z)
    if kind=='water' or kind=='stone' then return nil end
    if kind=='shore' or kind=='dirt' or kind=='meadow' or kind=='litter' or kind=='moss' then
        return kind,height
    end
end

function Tracks:update(id,actor,world,active,now)
    now=now or love.timer.getTime()
    self.time=now
    local track=self.players[id]
    if not track then track={marks={},side=1,carry=0};self.players[id]=track end
    if not active or type(actor)~='table' or not Math.finite(actor.x) or not Math.finite(actor.z) then
        track.x,track.z,track.carry=nil,nil,0
    elseif not track.x or not track.z then
        track.x,track.z=actor.x,actor.z
    else
        local dx,dz=actor.x-track.x,actor.z-track.z
        local distance=Math.length(dx,dz)
        if distance>3.2 then
            -- A relocation, doorway transition, or network snap is not a walk.
            track.x,track.z,track.carry=actor.x,actor.z,0
        elseif distance>1e-4 then
            local angle=math.atan2(dz,dx)
            local nextStep=Tracks.STEP-(track.carry or 0)
            while nextStep<=distance do
                local f=nextStep/distance
                local x,z=track.x+dx*f,track.z+dz*f
                local side=track.side
                track.side=-track.side
                local material,height=materialAt(world,x,z)
                if material then
                    track.marks[#track.marks+1]={x=x,z=z,angle=angle,side=side,
                        material=material,h=height,at=now}
                    while #track.marks>Tracks.MAX_PER_PLAYER do table.remove(track.marks,1) end
                end
                nextStep=nextStep+Tracks.STEP
            end
            track.carry=(track.carry+distance)%Tracks.STEP
            track.x,track.z=actor.x,actor.z
        end
    end
    for i=#track.marks,1,-1 do
        if now-track.marks[i].at>=Tracks.TTL then table.remove(track.marks,i) end
    end
end

local function drawMark(mark,camera,world,depthShader,depthSpan)
    local style=styles[mark.material]
    if not style then return end
    local c,s=math.cos(mark.angle),math.sin(mark.angle)
    local shoe={
        { .145,.04},{ .115,.065},{ .035,.06},{-.075,.05},
        {-.125,.035},{-.125,-.035},{-.075,-.05},{ .035,-.06},
        { .115,-.065},{ .145,-.04},
    }
    local points={};local depthTotal,depthCount=0,0
    for _,vertex in ipairs(shoe) do
        local along,across=vertex[1]*style.size,vertex[2]*style.size+mark.side*.11
        local x=mark.x+c*along-s*across
        local z=mark.z+s*along+c*across
        local h=(mark.h or world:supportHeight(mark.x,mark.z))+.014
        local sx,sy,viewDepth=camera:screen(x,z,h)
        local depth
        if camera.firstPerson then
            if not viewDepth or viewDepth<FirstPerson.NEAR or viewDepth>FirstPerson.FAR then return end
            depth=FirstPerson.depthValue(viewDepth)
        else depth=-camera:depth(x,z,h)/math.max(1,depthSpan or 1) end
        if not Math.finite(sx) or not Math.finite(sy) or not Math.finite(depth) then return end
        points[#points+1]=sx;points[#points+1]=sy
        depthTotal=depthTotal+depth;depthCount=depthCount+1
    end
    local fade=Math.clamp(1-(love.timer.getTime()-mark.at)/Tracks.TTL,0,1)
    if fade<=0 then return end
    depthShader:send('spriteDepth',depthTotal/math.max(1,depthCount))
    love.graphics.setColor(style.color[1],style.color[2],style.color[3],style.alpha*fade)
    love.graphics.polygon('fill',points)
end

function Tracks:draw(camera,depthShader,depthSpan,world,radius)
    if not camera or not depthShader then return end
    local g=love.graphics
    local centerX,centerZ=camera.centerX or 0,camera.centerZ or 0
    local reach=radius or 56
    g.push('all');g.origin();g.setScissor();g.setBlendMode('alpha')
    g.setDepthMode('lequal',false);g.setShader(depthShader)
    for _,track in pairs(self.players) do
        for _,mark in ipairs(track.marks) do
            if (mark.x-centerX)^2+(mark.z-centerZ)^2<=reach*reach then
                drawMark(mark,camera,world,depthShader,depthSpan)
            end
        end
    end
    g.setShader();g.setDepthMode('lequal',true);g.setColor(1,1,1);g.pop()
end

function Tracks:count(id)
    local track=self.players[id]
    return track and #track.marks or 0
end

return Tracks
