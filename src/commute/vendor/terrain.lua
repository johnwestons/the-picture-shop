-- Seeded landforms and material fields. Noise is evaluated during generation /
-- mesh construction only, never in the movement hot path.
local M=require('src.commute.vendor.mathx')
local Materials=require('src.commute.vendor.ground_materials')
local Config=require('src.commute.vendor.world_config')
local Terrain={}
function Terrain.configure(seed)
    local rng=M.random(seed+307)
    local t={hills={},routes={},angle=M.hash(seed+307,11,17)*math.pi*2,stretch=.9+rng()*.2}
    for i=1,3 do
        local a=t.angle+(i-1)*math.pi*2/3+(rng()-.5)*.5
        local distance=16+rng()*7
        local hill={x=42+math.cos(a)*distance,z=42+math.sin(a)*distance,
            radius=8+rng()*5,height=11+rng()*21}
        t.hills[i]=hill
        local mx,mz=(42+hill.x)*.5,(42+hill.z)*.5
        mx=mx+math.sin(a)*2;mz=mz-math.cos(a)*2
        t.routes[#t.routes+1]={42,42,mx,mz}
        t.routes[#t.routes+1]={mx,mz,hill.x,hill.z}
    end
    local a=t.angle+math.pi/3
    t.pond={x=42+math.cos(a)*20,z=42+math.sin(a)*19,rx=5+rng()*3,rz=3.5+rng()*2}
    t.routes[#t.routes+1]={42,42,t.pond.x-math.cos(a)*(t.pond.rx+1.5),t.pond.z-math.sin(a)*(t.pond.rz+1.5)}
    return t
end
function Terrain.height(seed,t,x,z)
    local wx=(M.noise(seed+11,x*.055,z*.055)-.5)*3
    local wz=(M.noise(seed+29,x*.055,z*.055)-.5)*3
    local dx,dz=(x-42+wx)/(33*t.stretch),(z-42+wz)/(31/t.stretch)
    local radial=M.length(dx,dz)
    local coast=.99+(M.noise(seed+41,x*.12,z*.12)-.5)*.14
    local shore=(coast-radial)*14
    local broad=M.noise(seed+53,(x+wx)*.065,(z+wz)*.065)
    local folds=M.noise(seed+67,x*.17,z*.17)-.5
    local fine=M.noise(seed+83,x*.48,z*.48)-.5
    local h=.8+broad*1.4+folds*.65+fine*.18
    for _,hill in ipairs(t.hills) do
        local d=M.length(x-hill.x,z-hill.z)/hill.radius
        h=h+hill.height*(1-M.smooth(d))
    end
    -- Shallow drainage swales create saddles without water-separated regions.
    local valley=math.abs((x-42)*math.cos(t.angle)+(z-42)*math.sin(t.angle)+wx*2)
    h=math.max(.38,h-(1-M.smooth(valley/4))*1.1)
    h=math.min(shore,h)
    local p=t.pond
    local pond=M.length((x-p.x)/p.rx,(z-p.z)/p.rz)
    if pond<1.35 then h=math.min(h,(pond-1)*2.2) end
    local blend=M.smooth((M.length(x-42,z-42)-4.2)/5)
    return M.clamp(M.lerp(.8,h,blend),-1.2,Config.HEIGHT_LIMIT)
end
function Terrain.routeDistance(t,x,z)
    local best=math.huge
    for _,r in ipairs(t.routes) do
        local dx,dz=r[3]-r[1],r[4]-r[2]
        local u=M.clamp(((x-r[1])*dx+(z-r[2])*dz)/(dx*dx+dz*dz),0,1)
        best=math.min(best,M.length(x-r[1]-dx*u,z-r[2]-dz*u))
    end
    return best
end
-- Static visual habitat field, prepared once from the seeded tree placement.
-- Plant growth/death remains simulation-owned; sampling does not mutate it.
function Terrain.prepareMaterials(world)
    if world.streamed then return end
    if world.groundHabitat then return end
    local grid={}
    for x=0,world.size do grid[x]={};for z=0,world.size do
        local oak,pine=0,0
        world:eachProp(x-3.4,z-3.4,x+3.4,z+3.4,function(p)
            if (p.kind=='oak' or p.kind=='pine' or p.kind=='redbud' or p.kind=='dogwood' or p.kind=='persimmon')
                and p.lifePhase~='vacant' then
                local d=M.length(x-p.x,z-p.z)
                local weight=math.max(0,1-d/3.4)^2*p.scale
                if p.kind=='pine' then pine=pine+weight else oak=oak+weight end
            end
        end)
        grid[x][z]={M.clamp((oak+pine)*1.5,0,1),pine/(oak+pine+.08)}
    end end
    world.groundHabitat=grid
end
function Terrain.habitat(world,x,z)
    if world.streamed then return world.plan:habitat(x,z) end
    Terrain.prepareMaterials(world)
    x=M.clamp(x,0,world.size-.000001);z=M.clamp(z,0,world.size-.000001)
    local ix,iz=math.floor(x),math.floor(z);local u,v=x-ix,z-iz
    local a,b,c,d=world.groundHabitat[ix][iz],world.groundHabitat[ix+1][iz],world.groundHabitat[ix][iz+1],world.groundHabitat[ix+1][iz+1]
    return M.lerp(M.lerp(a[1],b[1],u),M.lerp(c[1],d[1],u),v),M.lerp(M.lerp(a[2],b[2],u),M.lerp(c[2],d[2],u),v)
end
function Terrain.surface(world,x,z)
    local h=world:height(x,z)
    local wetland=world.streamed and world.plan and world.plan.marshAt and world.plan:marshAt(x,z) or 0
    local hx,hz=world:height(x+.3,z)-world:height(x-.3,z),world:height(x,z+.3)-world:height(x,z-.3)
    local slope=M.length(hx,hz)/.6
    local moisture=M.noise(world.seed+137,x*.105,z*.105)
    local grain=M.noise(world.seed+193,x*.62,z*.62)
    local patch=M.noise(world.seed+227,x*.24,z*.24)
    local trail=1-M.smooth(Terrain.routeDistance(world.terrain,x,z)/.8)
    local canopy,conifer,rockiness=Terrain.habitat(world,x,z)
    rockiness=rockiness or 0
    local climate=M.noise(world.seed+461,x*.06,z*.06)
    local grassVariant=M.clamp((moisture-.18)*4.6+(climate-.5)*.65+canopy*.35,0,3)
    local soilVariant=0
    local litterVariant=M.clamp(2-conifer*2-M.smooth((moisture-.55)/.3)*.6
        +(M.noise(world.seed+677,x*.41,z*.41)-.5)*.32,0,2)
    local r,g,b,kind;local grassWeight,dirtWeight,leafWeight,coverage=0,0,0,0
    if h<.04 then
        local shallows=M.smooth((h+.7)/.78)
        r,g,b=.075+shallows*.10,.20+shallows*.14,.24+shallows*.10
        local marshTint=M.clamp(wetland*.68,0,.68)
        r,g,b=M.lerp(r,.14,marshTint),M.lerp(g,.21,marshTint),M.lerp(b,.15,marshTint)
        kind='water'
    elseif h<.38 then
        local blend=M.smooth((h-.04)/.34)
        r,g,b=M.lerp(.53,.34,blend),M.lerp(.51,.43,blend),M.lerp(.33,.23,blend)
        kind='shore'
        dirtWeight=1;coverage=M.smooth((h-.04)/.18)
        soilVariant=M.smooth((h-.08)/.8)*3
    else
        local rock=math.max(M.smooth((slope-.22)/.48)*M.smooth((h-1.0)/1.8),
            M.smooth((rockiness-.16)/.72)*M.smooth((h-.45)/1.2)*.86)
        local meadow=M.smooth((patch-.32)/.38)
        dirtWeight=M.clamp(trail*.80+(1-moisture)*.12+(1-meadow)*.13,0,.9)
        leafWeight=M.clamp(M.smooth((moisture-.44)/.27)*(.38+.62*(1-meadow))*.45+canopy*.85,0,.96)*(1-dirtWeight)
        grassWeight=1-dirtWeight-leafWeight;coverage=1
        grassWeight=grassWeight*(1-rock);leafWeight=leafWeight*(1-rock);dirtWeight=1-grassWeight-leafWeight
        soilVariant=M.clamp(1.5+M.smooth((moisture-.40)/.35)*1.5+rock*3.3,1,5)
        kind=rock>.45 and 'stone' or dirtWeight>.6 and 'dirt' or moisture>.62 and 'moss' or meadow>.55 and 'meadow' or 'litter'
    end
    if h>=.04 then r,g,b=Materials.tint(grassVariant,soilVariant,litterVariant,grassWeight,dirtWeight,leafWeight) end
    if h>=.04 and wetland>.05 then
        local marshTint=wetland*.30
        r,g,b=M.lerp(r,.34,marshTint),M.lerp(g,.40,marshTint),M.lerp(b,.28,marshTint)
    end
    if h>=.38 then
        -- Keep ordinary meadows green while exposing altitude bands on slopes
        -- and ridgelines, where geometric displacement alone is easy to miss.
        local foothill=M.smooth((h-3)/15)*.24
        local alpine=M.smooth((h-17)/27)*.52
        r=M.lerp(r,.62,foothill);g=M.lerp(g,.48,foothill);b=M.lerp(b,.32,foothill)
        r=M.lerp(r,.78,alpine);g=M.lerp(g,.76,alpine);b=M.lerp(b,.69,alpine)
    end
    local variation=(1-M.smooth((slope-.28)/.8)*.16)*(.94+grain*.12)
    return r*variation,g*variation,b*variation,kind,grassWeight,dirtWeight,leafWeight,coverage,grassVariant,soilVariant,litterVariant
end
return Terrain
