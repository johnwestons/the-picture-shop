-- Procedural fixture models, batched into static neighbourhood meshes for both cameras.
local G=require('src.commute.structure_geometry')
local Geo={}
local metal={.20,.25,.25}
local iron={.12,.19,.18}
local zinc={.57,.62,.62}
local white={1,.98,.88}
local cedar={.49,.33,.18}
local planks={.65,.47,.28}
local function box(m,x,z,y,w,d,h,c)
    G.box(m,x-w/2,z-d/2,y,x+w/2,z+d/2,y+h,c)
end
local function panel(m,n,radius,height,z,color,rotation)
    local points={}
    for i=1,n do
        local a=(i-1)*math.pi*2/n+rotation
        points[i]={math.cos(a)*radius,z,height+math.sin(a)*radius}
    end
    for i=2,n-1 do G.triangle(m,points[1],points[i],points[i+1],color,{0,0,1}) end
end
local stopGlyphs={S={'111','100','111','001','111'},T={'111','010','010','010','010'},
    O={'111','101','101','101','111'},P={'110','101','110','100','100'}}
local function stop(m)
    box(m,0,-.04,0,.065,.065,2.3,zinc)
    panel(m,8,.50,2.17,-.073,zinc,math.pi/8)
    panel(m,8,.50,2.17,.018,white,math.pi/8)
    panel(m,8,.465,2.17,.022,{.84,.08,.075},math.pi/8)
    local cell=.047
    for i,letter in ipairs({'S','T','O','P'}) do
        for row,bits in ipairs(stopGlyphs[letter]) do
            for col=1,3 do if bits:sub(col,col)=='1' then
                local x=(-7.5+(i-1)*4+col-1)*cell
                local y=2.17+(2.5-row)*cell
                G.quad(m,{x,.029,y},{x+cell,.029,y},{x+cell,.029,y+cell},{x,.029,y+cell},white,{0,0,1})
            end end
        end
    end
end
local function curve(m,side)
    box(m,0,-.055,0,.065,.065,2.3,zinc)
    panel(m,4,.59,2.18,-.08,zinc,0)
    panel(m,4,.59,2.18,.01,{.23,.22,.16},0)
    panel(m,4,.55,2.18,.015,{1,.76,.10},0)
    local c={.10,.105,.09};local z=.025
    local function p(x,y)return {x*side,z,2.18+y}end
    G.quad(m,p(-.085,-.30),p(.005,-.30),p(.005,-.06),p(-.085,-.06),c,{0,0,1})
    G.quad(m,p(-.085,-.06),p(.005,-.06),p(.14,.12),p(.055,.14),c,{0,0,1})
    G.triangle(m,p(-.005,.155),p(.19,.215),p(.147,.005),c,{0,0,1})
end
local function lamp(m)
    G.cylinder(m,0,0,0,.22,.14,metal,8)
    G.cylinder(m,0,0,.14,.14,.33,iron,8)
    G.cylinder(m,0,0,.47,.075,2.53,iron,8)
    G.cylinder(m,0,0,2.92,.14,.14,metal,8)
    box(m,0,0,3.05,.42,.42,.07,iron)
    box(m,0,0,3.12,.33,.33,.38,{1,.87,.52,.99})
    for _,x in ipairs({-.175,.175}) do for _,z in ipairs({-.175,.175}) do
        box(m,x,z,3.11,.04,.04,.40,iron)
    end end
    box(m,0,0,3.49,.48,.48,.075,iron)
    local top={0,0,3.77}
    local corners={{-.25,-.25,3.565},{.25,-.25,3.565},{.25,.25,3.565},{-.25,.25,3.565}}
    for i=1,4 do G.triangle(m,corners[i],corners[i%4+1],top,metal) end
    G.cylinder(m,0,0,3.76,.055,.09,iron,6)
end
local function mailbox(m)
    box(m,0,0,0,.13,.13,.92,cedar)
    box(m,0,0,.84,.32,.55,.075,cedar)
    local blue={.20,.34,.37};local dark={.12,.22,.24}
    box(m,0,0,.92,.35,.53,.18,blue)
    local ridge=1.10
    for i=0,7 do
        local a,b=i*math.pi/8,(i+1)*math.pi/8
        local x1,y1=.175*math.cos(a),ridge+.175*math.sin(a)
        local x2,y2=.175*math.cos(b),ridge+.175*math.sin(b)
        G.quad(m,{x1,-.265,y1},{x2,-.265,y2},{x2,.265,y2},{x1,.265,y1},blue)
        G.triangle(m,{0,.268,ridge},{x1,.268,y1},{x2,.268,y2},dark,{0,0,1})
        G.triangle(m,{0,-.265,ridge},{x2,-.265,y2},{x1,-.265,y1},blue,{0,0,-1})
    end
    box(m,0,.271,1.04,.09,.025,.035,zinc)
    box(m,.19,0,1.04,.025,.025,.24,{.81,.16,.11})
    box(m,.19,.044,1.22,.025,.115,.065,{.81,.16,.11})
end
local function tableModel(m)
    for _,x in ipairs({-.72,.72}) do
        box(m,x,0,.06,.12,1.56,.1,iron)
        for _,z in ipairs({-.28,.28}) do box(m,x,z,.08,.14,.14,.64,cedar) end
        box(m,x,0,.34,.14,1.73,.12,cedar)
    end
    for i=-2,2 do box(m,0,i*.162,.73,2.05,.151,.07,planks) end
    for _,z in ipairs({-.72,.72}) do box(m,0,z,.44,2.08,.28,.075,planks) end
end
local function bench(m)
    for _,x in ipairs({-.67,.67}) do
        box(m,x,0,.02,.12,.52,.08,iron)
        box(m,x,-.18,.06,.085,.085,.84,iron)
        box(m,x,.19,.06,.085,.085,.39,iron)
    end
    for i=-1,1 do box(m,0,i*.155,.42,1.8,.14,.065,planks) end
    for i=0,1 do box(m,0,-.17,.64+i*.16,1.8,.085,.13,planks) end
end
local function tent(m)
    local canvas={.46,.49,.27};local trim={.30,.36,.21}
    box(m,0,0,.02,2.14,2.65,.07,trim)
    for _,side in ipairs({1,-1}) do
        G.quad(m,{side*1.04,-1.28,.09},{side*1.04,1.28,.09},{0,1.28,1.46},{0,-1.28,1.46},canvas)
    end
    G.triangle(m,{-1.04,-1.28,.09},{1.04,-1.28,.09},{0,-1.28,1.46},trim)
    G.triangle(m,{-1.04,1.28,.09},{1.04,1.28,.09},{0,1.28,1.46},{.11,.16,.12})
    G.triangle(m,{-1.04,1.29,.09},{-.56,1.29,.09},{0,1.29,1.46},canvas)
    G.triangle(m,{1.04,1.29,.09},{.56,1.29,.09},{0,1.29,1.46},canvas)
end
local function fireRing(m)
    G.cylinder(m,0,0,.01,.64,.025,{.21,.19,.16},10)
    for i=1,9 do
        local a=i*2*math.pi/9
        G.cylinder(m,math.cos(a)*.57,math.sin(a)*.57,0,.18,.22+i%2*.03,{.45,.44,.39},5)
    end
    box(m,-.10,0,.05,.17,.60,.14,{.27,.21,.16})
    box(m,.12,.03,.05,.15,.53,.13,{.30,.23,.16})
end
local function trailSign(m)
    box(m,0,0,0,.15,.15,1.50,cedar)
    box(m,0,.02,1.00,.79,.11,.54,{.20,.30,.21})
    G.triangle(m,{-.22,.09,1.12},{-.02,.09,1.42},{.18,.09,1.12},white,{0,0,1})
    G.triangle(m,{.015,.091,1.12},{.14,.091,1.32},{.29,.091,1.12},{.78,.78,.62},{0,0,1})
end
local function townSign(m)
    for _,x in ipairs({-1.78,1.78}) do
        box(m,x,0,0,.14,.17,2.55,cedar)
        box(m,x,0,.02,.20,.22,.12,planks)
    end
    box(m,0,0,1.52,4.28,.22,1.24,cedar)
    box(m,0,.116,1.62,4.02,.025,1.04,{.13,.25,.20})
    box(m,0,.132,1.59,4.04,.028,.055,planks)
    box(m,0,.132,2.65,4.04,.028,.055,planks)
end
local templates={}
local recreation=require('src.commute.recreation_geometry')
local constructors={stop=stop,lamp=lamp,mailbox=mailbox,table=tableModel,bench=bench,tent=tent,fireRing=fireRing,
    trailSign=trailSign,townSign=townSign,curveR=function(m)curve(m,1)end,curveL=function(m)curve(m,-1)end,
    pond=recreation.pond,stage=recreation.stage,logSeat=recreation.logSeat,
    rangerHut=recreation.rangerHut,outhouse=recreation.outhouse,
    parkSign=function(m)recreation.parkSign(m,'PARK')end,campSign=function(m)recreation.parkSign(m,'CAMP')end}
local function model(kind)
    if not templates[kind] then
        local m=G.new()
        constructors[kind](m)
        templates[kind]=m.vertices
    end
    return templates[kind]
end
local function put(piece,v)
    piece.vertices[#piece.vertices+1]=v
    local b=piece.bounds
    b.minX,b.maxX=math.min(b.minX,v[1]),math.max(b.maxX,v[1])
    b.minZ,b.maxZ=math.min(b.minZ,v[2]),math.max(b.maxZ,v[2])
    b.minH,b.maxH=math.min(b.minH,v[3]),math.max(b.maxH,v[3])
end
local function fixture(piece,f)
    local kind=f.kind=='curve' and (f.turn>=0 and 'curveR' or 'curveL') or f.kind
    if kind=='parkSign' and f.label=='CAMP' then kind='campSign' end
    for _,v in ipairs(model(kind)) do
        put(piece,{f.x+v[1]*f.fz+v[2]*f.fx,f.z-v[1]*f.fx+v[2]*f.fz,f.h+v[3],
            v[4]*f.fz+v[6]*f.fx,v[5],-v[4]*f.fx+v[6]*f.fz,0,0,v[9],v[10],v[11],1})
    end
end
local function walk(piece,w)
    local p=w.corners
    local m=G.new()
    local concrete={.67,.65,.58}
    G.quad(m,p[1],p[2],p[3],p[4],concrete,{0,1,0})
    -- Adjacent sidewalk sections share their end vertices. Skip those end
    -- caps: drawing both coplanar caps creates depth-buffer seams in first
    -- person perspective. Keep only the two exposed long sides.
    for i=1,3,2 do
        local a,b=p[i],p[i%4+1]
        G.quad(m,a,b,{b[1],b[2],b[4]-.025},{a[1],a[2],a[4]-.025},concrete)
    end
    for _,v in ipairs(m.vertices) do put(piece,v) end
end
local function rail(piece,r)
    local dx,dz=r.bx-r.ax,r.bz-r.az
    local length=math.sqrt(dx*dx+dz*dz)
    local nx,nz=-dz/length,dx/length
    local m=G.new()
    box(m,r.ax,r.az,r.ha,.145,.145,.78,zinc)
    -- Folded galvanized beam: two ridges catch the light as the road turns.
    local profile={{-.07,.48},{.045,.56},{-.025,.64},{.045,.72},{-.07,.80}}
    for i=1,#profile-1 do
        local a,b=profile[i],profile[i+1]
        G.quad(m,{r.ax+nx*a[1],r.az+nz*a[1],r.ha+a[2]},
            {r.bx+nx*a[1],r.bz+nz*a[1],r.hb+a[2]},
            {r.bx+nx*b[1],r.bz+nz*b[1],r.hb+b[2]},
            {r.ax+nx*b[1],r.az+nz*b[1],r.ha+b[2]},zinc)
    end
    box(m,r.ax,r.az,r.ha+.71,.16,.16,.045,{.94,.83,.49})
    for _,v in ipairs(m.vertices) do put(piece,v) end
end
function Geo.build(plan)
    local tiles,pieces={},{}
    local function tile(item,kind)
        local size=kind=='sidewalk' and 32 or 16
        local id=kind..':'..math.floor(item.x/size)..':'..math.floor(item.z/size)
        if not tiles[id] then
            local piece=G.new()
            piece.kind=kind;piece.id=id
            tiles[id]=piece
            pieces[#pieces+1]=piece
        end
        return tiles[id]
    end
    for _,w in ipairs(plan.walks) do walk(tile(w,'sidewalk'),w) end
    for _,r in ipairs(plan.rails) do rail(tile(r,'streetFurniture'),r) end
    for _,f in ipairs(plan.fixtures) do fixture(tile(f,'streetFurniture'),f) end
    for _,surface in ipairs(plan.recreationSurfaces or {}) do
        local mesh=G.new();local corners=surface.corners
        for i=2,#corners-1 do
            G.triangle(mesh,corners[1],corners[i],corners[i+1],surface.color,{0,1,0})
        end
        local piece=tile(surface,'streetFurniture')
        for _,v in ipairs(mesh.vertices) do put(piece,v) end
    end
    for _,p in ipairs(pieces) do
        local b=p.bounds
        p.x,p.z,p.h=(b.minX+b.maxX)*.5,(b.minZ+b.maxZ)*.5,b.minH
    end
    return pieces
end
return Geo
