-- Fixed town geography. All coordinates and elevations are metres.
-- Curve samples drive rendering, grading, collision and route measurements.
local M=require('src.commute.vendor.mathx')
local Sites=require('src.commute.sites')
local Roads={VERSION=2};Roads.__index=Roads
Roads.destinations={
    warehouse={x=100,z=380,h=4.5,label='The Picture Shop'},
    ['brick-walkup']={x=225,z=330,h=4.5,label='Brick walk-up'},
    garden={x=425,z=208,h=6,label='East Bank garden apartment'},
    courtyard={x=187,z=226,h=9,label='Woodland courtyard'},
    corner={x=110,z=130,h=12,label='Ridge corner apartment'},
}
local definitions={
    {id='shop-lane',width=5,points={{100,380,4.5},{112,372,4.8},{130,360,5}}},
    {id='valley-road',width=6.4,points={{130,360,5},{165,327,5},{205,306,4.5},{250,290,4}}},
    {id='ridge-loop',width=5.6,points={{250,290,4},{250,235,5.5},{220,190,7},{190,155,8},{140,160,10},{112,215,12},{108,280,9},{130,360,5}}},
    {id='east-bank',width=5,points={{250,290,4},{280,270,3.6},{290,270,3.6},{308,270,3.6},{352,270,3.6},{380,270,3.6},{402,240,4.5},{425,208,6}}},
    {id='brick-lane',width=4.2,points={{205,306,4.5},{213,320,4.5},{225,330,4.5}}},
    {id='courtyard-lane',width=4.2,points={{112,215,12},{155,220,10},{187,226,9}}},
    {id='corner-lane',width=4.2,points={{140,160,10},{124,143,11},{110,130,12}}},
}
local function cat(a,b,c,d,t)
    return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
end
function Roads.new()
    local self=setmetatable({segments={},paths={},bins={},binSize=16},Roads)
    for _,def in ipairs(definitions) do
        local path={id=def.id,width=def.width,points={},length=0};self.paths[#self.paths+1]=path
        for i=1,#def.points-1 do
            local a,b,c,d=def.points[math.max(1,i-1)],def.points[i],def.points[i+1],def.points[math.min(#def.points,i+2)]
            local steps=math.max(1,math.ceil(M.length(c[1]-b[1],c[2]-b[2])/1.5))
            for j=0,steps-1 do
                local t=j/steps
                path.points[#path.points+1]={x=cat(a[1],b[1],c[1],d[1],t),z=cat(a[2],b[2],c[2],d[2],t),h=M.lerp(b[3],c[3],M.smooth(t))}
            end
        end
        local p=def.points[#def.points];path.points[#path.points+1]={x=p[1],z=p[2],h=p[3]}
        for i,v in ipairs(path.points) do
            local a,b=path.points[math.max(1,i-1)],path.points[math.min(#path.points,i+1)]
            local dx,dz=b.x-a.x,b.z-a.z;local length=M.length(dx,dz)
            v.nx,v.nz=-dz/length,dx/length
        end
        for i=1,#path.points-1 do
            local a,b=path.points[i],path.points[i+1];local dx,dz=b.x-a.x,b.z-a.z;local len=M.length(dx,dz)
            local s={a=a,b=b,dx=dx,dz=dz,len=len,length2=len*len,width=def.width,id=def.id,distance=path.length}
            s.bridge=def.id=='east-bank' and (a.x+b.x)*.5>=302 and (a.x+b.x)*.5<=360
            s.nx,s.nz=-dz/len,dx/len;path.length=path.length+len
            self.segments[#self.segments+1]=s
            local reach=def.width*.5+7
            for bx=math.floor((math.min(a.x,b.x)-reach)/16),math.floor((math.max(a.x,b.x)+reach)/16) do
                for bz=math.floor((math.min(a.z,b.z)-reach)/16),math.floor((math.max(a.z,b.z)+reach)/16) do
                    local key=bx..':'..bz;self.bins[key]=self.bins[key] or {};table.insert(self.bins[key],s)
                end
            end
        end
    end
    return self
end
function Roads:nearest(x,z)
    local list=self.bins[math.floor(x/16)..':'..math.floor(z/16)] or {}
    local best,segment,u=math.huge,nil,0
    for _,s in ipairs(list) do
        local t=M.clamp(((x-s.a.x)*s.dx+(z-s.a.z)*s.dz)/s.length2,0,1)
        local d=M.length(x-s.a.x-t*s.dx,z-s.a.z-t*s.dz)
        if d<best then best,segment,u=d,s,t end
    end
    return best,segment,u
end
function Roads:sample(x,z)
    local d,s,u=self:nearest(x,z)
    if s then return d,s,M.lerp(s.a.h,s.b.h,u) end
    return d,nil,nil
end
function Roads:padAt(x,z)
    for id,p in pairs(self.destinations) do
        local d=M.length(x-p.x,z-p.z)
        if d<9 then return p,d,id end
    end
end
function Roads:grade(base,x,z)
    local distance,s,h=self:sample(x,z)
    local graded=base
    if s and not s.bridge then
        local blend=1-M.smooth((distance-s.width*.5)/5)
        graded=M.lerp(base,h,blend)
    end
    local pad,d=self:padAt(x,z)
    if pad then graded=M.lerp(pad.h,graded,M.smooth((d-5)/4)) end
    return Sites.grade(graded,x,z)
end
function Roads:supportHeight(world,x,z)
    local d,s,h=self:sample(x,z)
    if s and s.bridge and d<=s.width*.5 then return h,'bridge' end
    return world:height(x,z),s and d<=s.width*.5 and 'road' or 'terrain'
end
function Roads:blocked(world,x,z)
    if x<56 or z<56 or x>458 or z>458 then return true end
    if Sites.blocked(x,z) then return true end
    local h,kind=self:supportHeight(world,x,z)
    if kind=='bridge' then return false end
    local d,s=self:sample(x,z)
    if s and s.bridge and d<s.width*.5+1.2 then return true end -- bridge rails
    return h<.25
end
function Roads:vegetationAllowed(x,z)
    if not Sites.vegetationAllowed(x,z) then return false end
    if self:padAt(x,z) then return false end
    local d,s=self:nearest(x,z)
    return not s or d>s.width*.5+2.2
end
function Roads:attach(world)
    local terrainHeight=world.height
    world.ungradedHeight=terrainHeight;world.roads=self
    function world:height(x,z) return self.roads:grade(terrainHeight(self,x,z),x,z) end
    function world:supportHeight(x,z) return self.roads:supportHeight(self,x,z) end
    return world
end
return Roads
