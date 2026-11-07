-- Versioned frozen town terrain. v2 worlds never consult the generator on load.
local M=require('src.commute.vendor.mathx')
local V2={MODE='inland-town-v2',COARSE=8};local Plan={};Plan.__index=Plan
local function copy(v)if type(v)~='table' then return v end;local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out end
function V2.random(seed,salt)
    local state=(seed+(salt or 0)*104729)%2147483647
    if state==0 then state=1 end
    for _=1,9 do state=state*16807%2147483647 end
    return function(lo,hi)state=state*16807%2147483647;return (lo or 0)+((hi or 1)-(lo or 0))*(state-1)/2147483646 end
end
local function q(v)return math.floor(v*1000+.5)/1000 end
local function ellipse(p,x,z)
    local dx,dz=x-p.x,z-p.z;local c,s=math.cos(p.angle or 0),math.sin(p.angle or 0)
    return M.length((dx*c+dz*s)/p.rx,(-dx*s+dz*c)/p.rz)
end
local function array(a,max)
    if type(a)~='table' or #a>max then return false end
    local n=0;for k in pairs(a)do if type(k)~='number' or k%1~=0 or k<1 or k>#a then return false end;n=n+1 end
    return n==#a
end
local function number(n,a,b)return M.finite(n) and n>=a and n<=b end
local function region(p)
    return type(p)=='table' and number(p.x,-128,640) and number(p.z,-128,640)
        and number(p.rx,4,220) and number(p.rz,4,220) and number(p.angle,-math.pi*2,math.pi*2)
end
function V2.valid(t)
    if type(t)~='table' or t.mode~=V2.MODE or t.size~=512 or not number(t.seed,1,2147483646)
        or t.seed%1~=0 or not array(t.heights,4225) or #t.heights~=4225
        or not array(t.rivers,3) or #t.rivers<1 or not array(t.lakes,3)
        or not array(t.ridges,5) or not array(t.forestRegions,6)
        or type(t.family)~='string' or #t.family>32 then return false end
    for _,h in ipairs(t.heights)do if not number(h,.3,84) then return false end end
    local waterIds={}
    for _,r in ipairs(t.rivers)do
        if type(r)~='table' or type(r.id)~='string' or #r.id>48 or not array(r.points,40) or #r.points<2
            or waterIds[r.id] or not number(r.waterWidth,2,12) or not number(r.valleyWidth,12,48)
            or r.valleyWidth<r.waterWidth+5 or not number(r.depth,.1,1.5) then return false end
        waterIds[r.id]=true
        for index,p in ipairs(r.points)do
            if type(p)~='table' or not number(p.x,-128,640) or not number(p.z,-128,640) then return false end
            local before=r.points[index-1]
            if before and (p.x-before.x)^2+(p.z-before.z)^2<.01 then return false end
        end
    end
    for _,p in ipairs(t.lakes)do if not region(p) or not number(p.depth,.2,1.2)
        or type(p.id)~='string' or #p.id>48 or waterIds[p.id] then return false end;waterIds[p.id]=true end
    for _,p in ipairs(t.ridges)do if not region(p) or not number(p.height,0,30) then return false end end
    for _,p in ipairs(t.forestRegions)do if not region(p) or type(p.open)~='boolean' then return false end end
    return true
end
function V2.generate(seed,frame,naturalRivers,progress,isCancelled)
    local rng=V2.random(seed,2)
    local t={mode=V2.MODE,seed=seed,size=512,heights={},rivers={},lakes={},ridges={},forestRegions={}}
    local function transform(x,z)return frame.x+x*frame.c-z*frame.s,frame.z+x*frame.s+z*frame.c end
    local axis=math.floor(rng(0,2));local gap=math.floor(rng(1,4));local offset=(gap-2)*90
    local family=math.floor(rng(1,5));t.family=({'river-valley','tributary-town','twin-waterways','lake-district'})[family]
    local function river(id,along,at,start,finish,width,endAt)
        local r={id=id,waterWidth=width,valleyWidth=width+rng(13,19),depth=rng(.55,.95),points={}}
        local phase=rng(0,math.pi*2)
        local phase2,phase3=phase,phase
        local amplitude,secondary,small
        if naturalRivers then
            -- Several broad bends give the channel a recognizable natural
            -- course instead of reading as a straight divider.
            phase2,phase3=rng(0,math.pi*2),rng(0,math.pi*2)
            amplitude,secondary,small=rng(18,30),rng(7,14),rng(2,6)
        else
            amplitude,secondary,small=rng(5,12),3,0
        end
        for i=0,24 do
            local u=i/24;local v=M.lerp(start,finish,u)
            local bend=math.sin(u*math.pi*2+phase)*amplitude
                +math.sin(u*math.pi*4+phase2)*secondary
                +math.sin(u*math.pi*6+phase3)*small
            local center=at+((endAt or at)-at)*M.smooth((v+75)/150)
            local x,z=center+bend,v;if along==1 then x,z=z,x end
            x,z=transform(x,z);r.points[#r.points+1]={x=q(x),z=q(z)}
        end
        t.rivers[#t.rivers+1]=r;return r
    end
    local endAt=offset
    if family~=3 and rng()<.75 then endAt=offset==0 and (rng()<.5 and -90 or 90) or 0 end
    local main=river('main-river',axis,offset,-300,300,rng(4.5,8),endAt)
    if family==2 then
        -- A tributary reaches the main waterway through a different block gap.
        local cross=(math.floor(rng(1,4))-2)*90
        local branch=river('tributary',1-axis,cross,-300,offset,rng(3,5))
        local sample=(cross+300)/600*24;local index=math.floor(sample)+1;local u=sample-math.floor(sample)
        local a,b=main.points[index],main.points[index+1]
        branch.points[#branch.points]={x=q(M.lerp(a.x,b.x,u)),z=q(M.lerp(a.z,b.z,u))}
    elseif family==3 then
        local other=offset<=0 and 90 or -90
        river('second-creek',axis,other,-300,300,rng(3,5.5))
    end
    local lakeCount=family==4 and 3 or math.floor(rng(0,3))
    for i=1,lakeCount do
        local gx=(math.floor(rng(1,4))-2)*90;local gz=(math.floor(rng(1,4))-2)*90
        local x,z=transform(gx+rng(-8,8),gz+rng(-8,8))
        t.lakes[#t.lakes+1]={id='lake-'..i,x=q(x),z=q(z),rx=rng(17,30),rz=rng(14,25),angle=rng(-math.pi,math.pi),depth=rng(.55,1.1)}
    end
    local base=rng(3.6,6.4);local amplitude=rng(1.5,4)
    local ridgeCount=math.floor(rng(2,5))
    for i=1,ridgeCount do
        local x,z=transform(rng(-185,185),rng(-185,185))
        t.ridges[#t.ridges+1]={x=q(x),z=q(z),rx=rng(65,135),rz=rng(40,90),angle=rng(-math.pi,math.pi),height=rng(3,12)}
    end
    for i=1,5 do
        local x,z=transform(rng(-190,190),rng(-190,190))
        t.forestRegions[#t.forestRegions+1]={x=q(x),z=q(z),rx=rng(45,110),rz=rng(45,100),angle=rng(-math.pi,math.pi),open=i%3==0}
    end
    for x=0,64 do
        if isCancelled and isCancelled() then error('Town generation cancelled.',0) end
        if progress and x%4==0 then progress(x/64,'Shaping island terrain') end
        for z=0,64 do
            local wx,wz=x*8,z*8
            local h=base+(M.noise(seed+15053,wx*.009,wz*.009)-.5)*amplitude
                +(M.noise(seed+15067,wx*.028,wz*.028)-.5)*.65
            for _,ridge in ipairs(t.ridges)do h=h+ridge.height*(1-M.smooth(ellipse(ridge,wx,wz))) end
            t.heights[#t.heights+1]=q(math.max(.5,h))
        end
    end
    return t
end
function V2.new(t,config,progress,isCancelled)
    assert(V2.valid(t),'Invalid frozen v2 town terrain')
    local self=setmetatable({seed=t.seed,config=config,town=true,townPreset=V2.MODE,grid={},rivers=copy(t.rivers),
        lakes=copy(t.lakes),ridges=copy(t.ridges),forestRegions=copy(t.forestRegions),mountains={},marshes={},routes={},
        riverBins={},playableBounds={x0=56,z0=56,x1=458,z1=458}},Plan)
    local index=0
    for x=0,64 do
        if isCancelled and isCancelled() then error('Town generation cancelled.',0) end
        if progress and x%8==0 then progress(x/64,'Preparing terrain grid') end
        self.grid[x]={}
        for z=0,64 do index=index+1;self.grid[x][z]=t.heights[index] end
    end
    for _,r in ipairs(self.rivers)do
        r.segments={}
        for i=1,#r.points-1 do
            local a,b=r.points[i],r.points[i+1];local dx,dz=b.x-a.x,b.z-a.z
            local segment={a=a,dx=dx,dz=dz,length2=dx*dx+dz*dz,id=r.id,waterWidth=r.waterWidth,
                valleyWidth=r.valleyWidth,depth=r.depth,progress=(i-.5)/(#r.points-1)}
            if segment.length2>1e-8 then
                r.segments[#r.segments+1]=segment
                local reach=r.valleyWidth+48
                for bx=math.floor((math.min(a.x,b.x)-reach)/32),math.floor((math.max(a.x,b.x)+reach)/32)do
                    for bz=math.floor((math.min(a.z,b.z)-reach)/32),math.floor((math.max(a.z,b.z)+reach)/32)do
                        local key=bx..':'..bz;local bin=self.riverBins[key] or {};self.riverBins[key]=bin;bin[#bin+1]=segment
                    end
                end
            end
        end
    end
    return self
end
function Plan:riverDistance(x,z)
    local best,nearest=math.huge,nil
    for _,s in ipairs(self.riverBins[math.floor(x/32)..':'..math.floor(z/32)] or {})do
        local u=M.clamp(((x-s.a.x)*s.dx+(z-s.a.z)*s.dz)/s.length2,0,1)
        local dx,dz=x-s.a.x-u*s.dx,z-s.a.z-u*s.dz;local d=dx*dx+dz*dz
        if d<best then best,nearest=d,s end
    end
    return math.sqrt(best),nearest and nearest.progress,nearest and nearest.id,nearest
end
function Plan:landHeight(x,z)
    x,z=M.clamp(x,0,511.999999),M.clamp(z,0,511.999999)
    local gx,gz=x/8,z/8;local ix,iz=math.floor(gx),math.floor(gz)
    return M.lerp(M.lerp(self.grid[ix][iz],self.grid[ix+1][iz],gx-ix),
        M.lerp(self.grid[ix][iz+1],self.grid[ix+1][iz+1],gx-ix),gz-iz)
end
function Plan:rawHeight(x,z)
    if x<0 or z<0 or x>=512 or z>=512 then return -1.2 end
    local base=self:landHeight(x,z);local h=base
    -- Combine intersecting channels continuously. Choosing only the closest
    -- centerline would create a seam where differently sized tributaries join.
    for _,r in ipairs(self.riverBins[math.floor(x/32)..':'..math.floor(z/32)]or {})do
        local u=M.clamp(((x-r.a.x)*r.dx+(z-r.a.z)*r.dz)/r.length2,0,1)
        local dx,dz=x-r.a.x-u*r.dx,z-r.a.z-u*r.dz;local distance2=dx*dx+dz*dz
        if distance2<r.valleyWidth*r.valleyWidth then
            local distance=math.sqrt(distance2)
            local bank=M.smooth((distance-r.waterWidth)/math.max(1,r.valleyWidth-r.waterWidth))
            local channel=-r.depth+r.depth*.72*distance2/(r.waterWidth*r.waterWidth)
            h=math.min(h,M.lerp(math.min(base,channel),base,bank))
        end
    end
    for _,lake in ipairs(self.lakes)do
        local d=ellipse(lake,x,z)
        if d<1.45 then h=math.min(h,M.lerp(-lake.depth,self:landHeight(x,z),M.smooth((d-.72)/.73))) end
    end
    return math.max(-1.2,h)
end
function Plan:height(x,z)return self:rawHeight(x,z)end
function Plan:riverCenterX(z)
    for _,s in ipairs(self.rivers[1].segments)do
        local a,b=s.a,{x=s.a.x+s.dx,z=s.a.z+s.dz}
        if z>=math.min(a.z,b.z) and z<=math.max(a.z,b.z) and math.abs(s.dz)>1e-8 then return a.x+s.dx*(z-a.z)/s.dz end
    end
end
function Plan:lakeAt(x,z)for _,lake in ipairs(self.lakes)do if ellipse(lake,x,z)<1.05 then return lake end end end
function Plan:marshAt()return 0,nil end
function Plan:shoreDistance()return math.huge end
function Plan:isRiverAt(x,z)local _,_,_,r=self:riverDistance(x,z);return r~=nil and self:height(x,z)<.04 end
function Plan:waterIdAt(x,z)
    if self:height(x,z)>=.04 then return nil end
    local lake=self:lakeAt(x,z);if lake then return lake.id end
    local _,_,id=self:riverDistance(x,z);return id
end
function Plan:habitat(x,z)
    local moisture=M.noise(self.seed+137,x*.004,z*.004)*.62+M.noise(self.seed+139,x*.018,z*.018)*.38
    local d,_,_,river=self:riverDistance(x,z)
    if river then moisture=M.clamp(moisture+(1-M.smooth((d-river.valleyWidth)/44))*.22,0,1) end
    local canopy=M.smooth((M.noise(self.seed+461,x*.008,z*.008)-.32)/.48)*.72+M.smooth((moisture-.28)/.62)*.28
    local open,dense,rock=0,0,0
    for _,region in ipairs(self.forestRegions)do
        local influence=1-M.smooth((ellipse(region,x,z)-.72)/.42)
        if region.open then open=math.max(open,influence) else dense=math.max(dense,influence) end
    end
    for _,ridge in ipairs(self.ridges)do rock=math.max(rock,(1-M.smooth(ellipse(ridge,x,z)))*ridge.height/16) end
    canopy=math.max(canopy,.78*dense)*(1-.88*open)*(1-.5*rock)
    return M.clamp(canopy,0,1),M.smooth((moisture-.47)/.28),M.clamp(rock,0,1)
end
function Plan:plantCommunity(x,z)
    local canopy,moisture,rock=self:habitat(x,z)
    if self:riverDistance(x,z)<55 and moisture>.36 then return 'river-margin' end
    if canopy>.56 then return 'woodland-understory' end
    if canopy<.34 and rock<.58 then return 'sunny-opening' end
    return 'shrub-edge'
end
return V2
