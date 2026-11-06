-- Short-lived tire marks for hard braking, wheel slip and fast acceleration.
local Bike=require('src.commute.motorcycle')
local FP=require('src.commute.first_person_camera')
local M=require('src.commute.vendor.mathx')
local Tracks={TTL=26,MAX_CHUNKS=64,CHUNK_SECONDS=.45,CHUNK_POINTS=24,MIN_STEP=.01}
Tracks.__index=Tracks

local function point(x,z,world)
    return {x=x,z=z,h=world:supportHeight(x,z)+.012}
end

local function wheels(bike,world)
    local c,s=math.cos(bike.heading or 0),math.sin(bike.heading or 0)
    local half=Bike.WHEELBASE*.5
    return point(bike.x+c*half,bike.z+s*half,world),
        point(bike.x-c*half,bike.z-s*half,world)
end

local function surfaceAt(bike,world)
    if bike.surface=='road' or bike.surface=='dirt' then return bike.surface end
    local distance,segment=world.roads:nearest(bike.x,bike.z,true)
    local roadAmount=segment and segment.surface~='dirt'
        and 1-M.smooth(distance-segment.width*.5) or 0
    return roadAmount>=.5 and 'road' or 'dirt'
end

function Tracks.new()
    return setmetatable({time=0,chunks={},history={},current={}},Tracks)
end

function Tracks:update(id,bike,world,dt,visual)
    self.time=self.time+math.max(0,dt or 0)
    if type(bike)~='table' or not M.finite(bike.x) or not M.finite(bike.z) then
        self.current[id]=nil;self.history[id]=nil;return false
    end

    local front,rear=wheels(bike,world)
    local previous=self.history[id]
    local speed=math.max(0,visual and visual.speed or bike.speed or 0)
    local throttle=M.clamp(visual and visual.throttle or bike.throttle or 0,0,1)
    local brake=M.clamp(visual and visual.brake or bike.brake or 0,0,1)
    local slip=math.max(visual and visual.slip or bike.slip or 0,
        visual and visual.tireSlip or bike.tireSlip or 0)
    local acceleration=M.finite(bike.acceleration) and bike.acceleration
        or previous and dt>0 and (speed-previous.speed)/dt or 0
    local grounded=(visual and visual.grounded)~=false and bike.grounded~=false
    local sliding=slip>=.14
    local braking=brake>=.7 and speed>=2.2
    local accelerating=throttle>=.72 and acceleration>=1.8 and speed>=.8
    local active=grounded and speed>=.8 and (sliding or braking or accelerating)
    local intensity=math.max(
        M.clamp((slip-.1)/.75,0,1),
        braking and M.clamp(.35+.65*brake*speed/7,0,1) or 0,
        accelerating and (.35+.65*M.clamp((acceleration-1.8)/4,0,1))*throttle or 0)
    if active then intensity=math.max(.35,intensity) end
    local surface=surfaceAt(bike,world)

    if active and previous then
        local moved=math.max(M.length(front.x-previous.front.x,front.z-previous.front.z),
            M.length(rear.x-previous.rear.x,rear.z-previous.rear.z))
        local jumpLimit=math.max(1.8,speed*math.max(dt or 0,1/60)*3+.5)
        if moved>=Tracks.MIN_STEP and moved<=jumpLimit then
            local chunk=self.current[id]
            if chunk and (chunk.surface~=surface or self.time-chunk.started>=Tracks.CHUNK_SECONDS
                or #chunk.front>=Tracks.CHUNK_POINTS) then chunk=nil end
            if not chunk then
                chunk={surface=surface,intensity=intensity,started=self.time,front={previous.front},rear={previous.rear}}
                self.chunks[#self.chunks+1]=chunk;self.current[id]=chunk
            else
                chunk.intensity=math.max(chunk.intensity,intensity)
            end
            chunk.front[#chunk.front+1]=front;chunk.rear[#chunk.rear+1]=rear
            while #self.chunks>Tracks.MAX_CHUNKS do table.remove(self.chunks,1) end
        else self.current[id]=nil end
    else self.current[id]=nil end

    self.history[id]={front=front,rear=rear,speed=speed}
    while self.chunks[1] and self.time-self.chunks[1].started>Tracks.TTL do table.remove(self.chunks,1) end
    return active
end

local function screenLine(points,camera,firstPerson,depthSpan)
    local lines,runs={},{}
    local sumDepth,depthCount=0,0
    local function flush()
        if #runs>=4 then lines[#lines+1]={points=runs,depth=depthCount>0 and sumDepth/depthCount or nil} end
        runs={};sumDepth,depthCount=0,0
    end
    for _,p in ipairs(points) do
        local x,y,viewDepth=camera:screen(p.x,p.z,p.h)
        local depth=firstPerson and viewDepth or camera:depth(p.x,p.z,p.h)
        local visible=not firstPerson or viewDepth>=FP.NEAR and viewDepth<=FP.FAR
        if M.finite(x) and M.finite(y) and M.finite(depth) and visible then
            local value=firstPerson and FP.depthValue(depth) or -depth/math.max(1,depthSpan or 1)
            runs[#runs+1]=x;runs[#runs+1]=y
            sumDepth=sumDepth+value;depthCount=depthCount+1
        else flush() end
    end
    flush()
    return lines
end

function Tracks:draw(camera,depthShader,depthSpan)
    if #self.chunks==0 then return end
    local g=love.graphics;local firstPerson=camera.firstPerson==true
    g.push('all');g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
    g.setDepthMode(depthShader and 'lequal' or 'always',false)
    if depthShader then g.setShader(depthShader) end
    for _,chunk in ipairs(self.chunks) do
        local age=self.time-chunk.started
        local fade=M.clamp(1-age/Tracks.TTL,0,1)
        if fade>0 then
            if chunk.surface=='road' then g.setColor(.025,.027,.025,.78*fade*chunk.intensity)
            else g.setColor(.25,.18,.105,.72*fade*chunk.intensity) end
            local front=screenLine(chunk.front,camera,firstPerson,depthSpan)
            local rear=screenLine(chunk.rear,camera,firstPerson,depthSpan)
            local width
            if firstPerson then
                local depth=(front[1] and front[1].depth) or (rear[1] and rear[1].depth) or FP.FAR
                width=M.clamp(camera.focal*.12/depth,1.25,10)
            else width=M.clamp(48*camera.zoom*.12,1.5,7) end
            g.setLineWidth(width*(.85+.3*chunk.intensity))
            for _,line in ipairs(front) do
                if depthShader and line.depth then depthShader:send('spriteDepth',line.depth) end
                g.line(line.points)
            end
            for _,line in ipairs(rear) do
                if depthShader and line.depth then depthShader:send('spriteDepth',line.depth) end
                g.line(line.points)
            end
        end
    end
    g.setDepthMode('lequal',true);g.setLineWidth(1);g.setColor(1,1,1);g.pop()
end

return Tracks
