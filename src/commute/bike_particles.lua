-- Local presentation only: distance-spaced road dust and small exhaust puffs.
-- No saved state, shared RNG, generated textures, or emission while paused.
local M=require('src.commute.vendor.mathx')
local Bike=require('src.commute.motorcycle')
local FP=require('src.commute.first_person_camera')
local Particles={MAX_PARTICLES=192,MAX_EMITTERS=8}
Particles.__index=Particles
local shaderSource=[[
#ifdef VERTEX
extern float particleDepth;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec4 clip=transform_projection*vertex_position;
    clip.z=particleDepth*clip.w;
    return clip;
}
#endif
#ifdef PIXEL
extern float particlePhase;
extern float particleFog;
vec4 effect(vec4 color,Image texture,vec2 uv,vec2 pixel) {
    vec2 p=uv*2.0-1.0;
    float radius=dot(p,p);
    float soft=max(0.0,exp(-3.4*radius)-exp(-3.4));
    float lobes=.88+.12*sin(p.x*7.0+particlePhase)*sin(p.y*6.0-particlePhase*.6);
    float alpha=color.a*soft*lobes;
    if(alpha<.002) discard;
    return vec4(mix(color.rgb,vec3(.57,.68,.70),particleFog),alpha);
}
#endif
]]
local function value(bike,visual,key,fallback)
    local v=visual and visual[key]
    if v==nil then v=bike[key] end
    return v==nil and fallback or v
end
function Particles.new()
    return setmetatable({time=0,particles={},emitters={},seed=173,totalDust=0,totalExhaust=0},Particles)
end
function Particles:random()
    self.seed=self.seed*48271%2147483647
    return self.seed/2147483647
end
function Particles:prewarm()
    if self.shader then return end
    self.shader=love.graphics.newShader(shaderSource)
    self.quad=love.graphics.newMesh({{-.5,-.5,0,0},{.5,-.5,1,0},{.5,.5,1,1},{-.5,.5,0,1}},'fan','static')
end
function Particles:advance(dt)
    dt=math.max(0,dt or 0);self.time=self.time+dt
    for i=#self.particles,1,-1 do
        local p=self.particles[i];p.age=p.age+dt
        if p.age>=p.life then table.remove(self.particles,i)
        else
            p.x=p.x+p.vx*dt;p.z=p.z+p.vz*dt;p.h=p.h+p.vh*dt
        end
    end
    for id,e in pairs(self.emitters) do if self.time-e.seen>1.5 then self.emitters[id]=nil end end
end
function Particles:add(kind,x,z,h,vx,vz,strength,baseH)
    local r=self:random();local dust=kind=='dust'
    local p={kind=kind,x=x,z=z,h=h,baseH=baseH or h,age=0,life=(dust and 1.25 or 1.1)+r*.5,
        radius=(dust and .075 or .055)+r*.045,growth=dust and .38 or .26,
        vx=vx+(self:random()-.5)*(dust and .65 or .2),
        vz=vz+(self:random()-.5)*(dust and .65 or .2),
        vh=(dust and .18 or .43)+self:random()*.17,
        phase=self:random()*math.pi*2,strength=strength}
    if #self.particles>=Particles.MAX_PARTICLES then table.remove(self.particles,1) end
    self.particles[#self.particles+1]=p
    if dust then self.totalDust=self.totalDust+1 else self.totalExhaust=self.totalExhaust+1 end
end
local function surface(world,x,z)
    if world.roads and world.roads.nearest then
        local d,s=world.roads:nearest(x,z,true)
        if s and s.surface~='dirt' and d<=s.width*.5+.25 then return 'road' end
    end
    return 'dirt'
end
function Particles:emit(id,bike,world,dt,visual,engine,mounted)
    dt=math.min(.1,math.max(0,dt or 0))
    if not bike or not M.finite(bike.x) or not M.finite(bike.z) or dt==0 then return end
    local e=self.emitters[id]
    if not e then
        local count=0;for _ in pairs(self.emitters) do count=count+1 end
        if count>=Particles.MAX_EMITTERS then return end
        e={x=bike.x,z=bike.z,dustDistance=0,exhaustTime=0};self.emitters[id]=e
    end
    e.seen=self.time
    local dx,dz=bike.x-e.x,bike.z-e.z;local moved=M.length(dx,dz)
    local speed=math.max(0,value(bike,visual,'speed',0))
    local heading=bike.heading or 0;local c,s=math.cos(heading),math.sin(heading)
    local support=world:supportHeight(bike.x,bike.z)
    local h=value(bike,visual,'h',support)
    local contact=value(bike,visual,'grounded',true) and math.abs(h-support)<.4
    local continuous=moved<=math.max(1.8,speed*dt*3+.5)
    local slip=math.max(value(bike,visual,'slip',0),value(bike,visual,'tireSlip',0))
    local loose=surface(world,bike.x,bike.z)=='dirt'
    local active=mounted~=false and contact and speed>.7 and moved>.0001 and continuous
    if active then
        local step=loose and .32 or (slip>.18 and .85 or 2.6)
        local strength=loose and .62 or (slip>.18 and .25 or .12)
        if e.dustStep~=step then e.dustDistance=0;e.dustStep=step end
        local old=e.dustDistance;local total=old+moved
        local count=math.min(8,math.floor(total/step))
        for n=1,count do
            local along=M.clamp((n*step-old)/moved,0,1)
            local x,z=e.x+dx*along-c*Bike.WHEELBASE*.5,e.z+dz*along-s*Bike.WHEELBASE*.5
            local ground=world:supportHeight(x,z)
            self:add('dust',x,z,ground+.055,dx/dt*.10,dz/dt*.10,strength,ground)
        end
        e.dustDistance=total%step
    else e.dustDistance=0 end
    if engine then
        local throttle=M.clamp(value(bike,visual,'throttle',0),0,1)
        e.exhaustTime=e.exhaustTime+dt*(6+8*throttle)
        local count=math.min(2,math.floor(e.exhaustTime));e.exhaustTime=e.exhaustTime-count
        local back,side=-.80,.27 -- Physical right tailpipe; never mirrored with the view.
        local x,z=bike.x+c*back-s*side,bike.z+s*back+c*side
        local height=h+.83+math.sin(value(bike,visual,'pitch',0))*back
        local vx,vz=continuous and dx/dt*.12 or 0,continuous and dz/dt*.12 or 0
        local sick=require('src.commute.bike_service').rough(bike)
        local kind=sick>.12 and 'soot' or 'exhaust'
        for _=1,count do self:add(kind,x,z,height,vx-c*.30,vz-s*.30,.40+.10*throttle+.25*sick,h) end
    else e.exhaustTime=0 end
    e.x,e.z=bike.x,bike.z
end
function Particles:stats()
    local dust,exhaust=0,0
    for _,p in ipairs(self.particles) do if p.kind=='dust' then dust=dust+1 else exhaust=exhaust+1 end end
    return {active=#self.particles,dust=dust,exhaust=exhaust,totalDust=self.totalDust,totalExhaust=self.totalExhaust}
end
function Particles:draw(camera,radius,depthSpan)
    if #self.particles==0 then return end
    self:prewarm()
    local g=love.graphics;local first=camera.firstPerson==true;local visible={}
    for _,p in ipairs(self.particles) do
        local distance=M.length(p.x-camera.centerX,p.z-camera.centerZ)
        -- Sprite billboards use 48 pixels/metre; the outside ground projection
        -- compresses height to 22. Match the pipe's authored vertical scale.
        local height=first and p.h or p.baseH+(p.h-p.baseH)*48/22
        local x,y,depth=camera:screen(p.x,p.z,height)
        if distance<radius and M.finite(x) and M.finite(y) and (not first or depth>=FP.NEAR and depth<=FP.FAR) then
            visible[#visible+1]={p=p,x=x,y=y,depth=depth,distance=distance,sort=camera:depth(p.x,p.z,height)}
        end
    end
    table.sort(visible,function(a,b)return a.sort<b.sort end)
    g.push('all');g.setShader(self.shader);g.setBlendMode('alpha');g.setDepthMode('lequal',false)
    for _,v in ipairs(visible) do
        local p=v.p;local t=p.age/p.life
        local alpha=p.strength*M.smooth(p.age/.07)*(1-t)^1.6
        local scale=first and camera.focal/v.depth or 48*camera.zoom
        local size=(p.radius+p.growth*p.age)*2*scale
        self.shader:send('particleDepth',first and FP.depthValue(v.depth) or -v.sort/depthSpan)
        self.shader:send('particlePhase',p.phase+p.age*.45)
        self.shader:send('particleFog',first and M.smooth((v.distance-radius*.74)/(radius*.26)) or 0)
        if p.kind=='dust' then g.setColor(.77,.66,.46,alpha) elseif p.kind=='soot' then g.setColor(.09,.08,.075,alpha) else g.setColor(.76,.79,.78,alpha) end
        g.draw(self.quad,v.x,v.y,first and camera.roll or 0,size,size*.82)
    end
    g.pop()
end
function Particles:release()
    if self.shader then self.shader:release();self.quad:release() end
    self.shader,self.quad=nil,nil;self.particles={};self.emitters={}
end
return Particles
