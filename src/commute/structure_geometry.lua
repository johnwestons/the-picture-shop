-- Pure CPU architectural meshes. Designs are authored locally, then transformed
-- by a site placement; no map coordinates, graphics calls or texture dependency.
local Geometry={}
local mechanicSign=require('src.commute.sites').MECHANIC_NAME:upper()
local colors={wall={.53,.49,.44},brick={.49,.42,.37},metal={.48,.51,.52},
    trim={.70,.68,.62},roof={.26,.29,.30},glass={.23,.36,.40},recess={.12,.15,.16},
    door={.28,.30,.29},rail={.24,.27,.28},stone={.58,.59,.56},sign={.77,.75,.67},
    farmhouse={.72,.64,.49},barn={.58,.17,.13},barnDoor={.43,.10,.09},
    farmTrim={.88,.82,.68},soil={.28,.17,.095},corn={.24,.43,.15},cornLeaf={.34,.53,.18},
    tomatoLeaf={.25,.43,.17},tomato={.78,.16,.10},wood={.36,.25,.14},
    groceryWall={.71,.66,.51},marketGreen={.19,.39,.24},marketCream={.91,.83,.64},
    produceCrate={.31,.39,.22},produceRed={.79,.17,.10},produceOrange={.91,.43,.09},
    produceYellow={.91,.73,.16},gasWall={.74,.71,.61},gasRed={.75,.15,.10},
    gasYellow={.95,.75,.20},gasBlue={.12,.31,.38},gasGreen={.20,.48,.34},
    mechanicSteel={.40,.47,.48},postOfficeWall={.73,.69,.57},mailBlue={.10,.30,.54},
    mailRed={.78,.16,.12},policeWall={.68,.70,.67},policeBlue={.12,.25,.43},
    policeGold={.88,.68,.19},fireWall={.72,.70,.63},fireRed={.72,.14,.12},
    fireCream={.91,.85,.68},dinerWall={.80,.75,.61},dinerRed={.71,.13,.13},
    dinerCream={.94,.87,.69},coffeeWall={.48,.37,.29},coffeeBrown={.28,.17,.10},
    coffeeCream={.91,.83,.64},generalWall={.63,.62,.46},generalWood={.38,.27,.16},
    generalSage={.37,.43,.29}}
Geometry.colors=colors
function Geometry.new()
    return {vertices={},features={},counts={boxes=0,quads=0,cylinders=0},
        bounds={minX=math.huge,maxX=-math.huge,minZ=math.huge,maxZ=-math.huge,minH=math.huge,maxH=-math.huge}}
end
local function feature(m,kind,data)
    m.features[kind]=m.features[kind] or {};m.features[kind][#m.features[kind]+1]=data or {}
    m.counts[kind]=#m.features[kind]
end
local function normal(a,b,c)
    local ax,ay,az=b[1]-a[1],b[3]-a[3],b[2]-a[2]
    local bx,by,bz=c[1]-a[1],c[3]-a[3],c[2]-a[2]
    local x,y,z=ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx
    local length=math.sqrt(x*x+y*y+z*z)
    assert(length>1e-9,'Degenerate structure face')
    return {x/length,y/length,z/length}
end
local function vertex(m,p,n,c,u,v)
    m.vertices[#m.vertices+1]={p[1],p[2],p[3],n[1],n[2],n[3],u or 0,v or 0,c[1],c[2],c[3],c[4] or 1}
end
function Geometry.triangle(m,a,b,c,color,n)
    n=n or normal(a,b,c);color=color or colors.wall
    vertex(m,a,n,color,0,0);vertex(m,b,n,color,1,0);vertex(m,c,n,color,1,1)
end
function Geometry.quad(m,a,b,c,d,color,n)
    n=n or normal(a,b,c);color=color or colors.wall
    vertex(m,a,n,color,0,0);vertex(m,b,n,color,1,0);vertex(m,c,n,color,1,1)
    vertex(m,a,n,color,0,0);vertex(m,c,n,color,1,1);vertex(m,d,n,color,0,1)
    m.counts.quads=m.counts.quads+1
end
function Geometry.box(m,x0,z0,h0,x1,z1,h1,color)
    assert(x1>x0 and z1>z0 and h1>h0,'Structure boxes need positive dimensions')
    Geometry.quad(m,{x0,z1,h0},{x1,z1,h0},{x1,z1,h1},{x0,z1,h1},color,{0,0,1})
    Geometry.quad(m,{x1,z0,h0},{x0,z0,h0},{x0,z0,h1},{x1,z0,h1},color,{0,0,-1})
    Geometry.quad(m,{x1,z1,h0},{x1,z0,h0},{x1,z0,h1},{x1,z1,h1},color,{1,0,0})
    Geometry.quad(m,{x0,z0,h0},{x0,z1,h0},{x0,z1,h1},{x0,z0,h1},color,{-1,0,0})
    Geometry.quad(m,{x0,z0,h1},{x0,z1,h1},{x1,z1,h1},{x1,z0,h1},color,{0,1,0})
    Geometry.quad(m,{x0,z1,h0},{x0,z0,h0},{x1,z0,h0},{x1,z1,h0},color,{0,-1,0})
    m.counts.boxes=m.counts.boxes+1
end
function Geometry.cylinder(m,x,z,h,radius,height,color,segments)
    segments=segments or 12
    assert(radius>0 and height>0 and segments>=3,'Invalid structure cylinder')
    for i=0,segments-1 do
        local a,b=i*2*math.pi/segments,(i+1)*2*math.pi/segments
        local ax,az=x+math.cos(a)*radius,z+math.sin(a)*radius
        local bx,bz=x+math.cos(b)*radius,z+math.sin(b)*radius
        Geometry.quad(m,{ax,az,h},{bx,bz,h},{bx,bz,h+height},{ax,az,h+height},color,
            {math.cos((a+b)*.5),0,math.sin((a+b)*.5)})
        Geometry.triangle(m,{x,z,h+height},{ax,az,h+height},{bx,bz,h+height},color,{0,1,0})
        Geometry.triangle(m,{x,z,h},{bx,bz,h},{ax,az,h},color,{0,-1,0})
    end
    m.counts.cylinders=m.counts.cylinders+1
end
-- Raised sign letters use merged solid strokes, not a raster/font texture.
local glyphs={
    A='01110/10001/10001/11111/10001/10001/10001',B='11110/10001/10001/11110/10001/10001/11110',
    C='01111/10000/10000/10000/10000/10000/01111',D='11110/10001/10001/10001/10001/10001/11110',
    E='11111/10000/10000/11110/10000/10000/11111',F='11111/10000/10000/11110/10000/10000/10000',
    G='01111/10000/10000/10111/10001/10001/01111',H='10001/10001/10001/11111/10001/10001/10001',
    I='11111/00100/00100/00100/00100/00100/11111',J='00111/00010/00010/00010/10010/10010/01100',
    K='10001/10010/10100/11000/10100/10010/10001',L='10000/10000/10000/10000/10000/10000/11111',
    M='10001/11011/10101/10101/10001/10001/10001',N='10001/11001/11001/10101/10011/10011/10001',
    O='01110/10001/10001/10001/10001/10001/01110',P='11110/10001/10001/11110/10000/10000/10000',
    Q='01110/10001/10001/10001/10101/10010/01101',R='11110/10001/10001/11110/10100/10010/10001',
    S='01111/10000/10000/01110/00001/00001/11110',T='11111/00100/00100/00100/00100/00100/00100',
    U='10001/10001/10001/10001/10001/10001/01110',V='10001/10001/10001/10001/10001/01010/00100',
    W='10001/10001/10001/10101/10101/11011/10001',X='10001/10001/01010/00100/01010/10001/10001',
    Y='10001/10001/01010/00100/00100/00100/00100',Z='11111/00001/00010/00100/01000/10000/11111',
}
function Geometry.lettering(m,text,x,z,h,width,height)
    local cell=math.min(height/7,width/math.max(1,#text*6-1))
    local left=x-(#text*6-1)*cell*.5
    for index=1,#text do
        local glyph=glyphs[text:sub(index,index)]
        if glyph then
            local row=0
            for line in glyph:gmatch('[^/]+') do
                row=row+1;local column=1
                while column<=5 do
                    if line:sub(column,column)=='1' then
                        local first=column
                        repeat column=column+1 until column>5 or line:sub(column,column)~='1'
                        local x0=left+((index-1)*6+first-1)*cell
                        local y0=h+(3.5-row)*cell
                        Geometry.box(m,x0,z,y0,x0+(column-first)*cell,z+.027,y0+cell,colors.recess)
                    else column=column+1 end
                end
            end
        end
    end
    feature(m,'lettering',{text=text,x=x,z=z,h=h})
end
local function panel(m,axis,plane,sign,u0,u1,h0,h1,d0,d1,color)
    local a,b=plane+sign*d0,plane+sign*d1
    a,b=math.min(a,b),math.max(a,b)
    if axis=='z' then Geometry.box(m,u0,a,h0,u1,b,h1,color)
    else Geometry.box(m,a,u0,h0,b,u1,h1,color) end
end
local function opening(m,axis,plane,sign,o)
    local u0,u1,h0,h1=o.u0,o.u1,o.h0,o.h1
    local frame=o.kind=='door' and .11 or .09
    panel(m,axis,plane,sign,u0,u1,h0,h1,-.24,-.215,colors.recess)
    panel(m,axis,plane,sign,u0+frame,u1-frame,h0+frame,h1-frame,-.205,-.185,
        o.kind=='door' and colors.door or o.kind=='garage' and colors.metal or colors.glass)
    for _,r in ipairs({{u0,u0+frame,h0,h1},{u1-frame,u1,h0,h1},
        {u0+frame,u1-frame,h0,h0+frame},{u0+frame,u1-frame,h1-frame,h1}}) do
        panel(m,axis,plane,sign,r[1],r[2],r[3],r[4],-.22,.075,colors.trim)
    end
    if o.kind=='garage' then
        for i=1,7 do
            local h=h0+(h1-h0)*i/8
            panel(m,axis,plane,sign,u0+frame,u1-frame,h-.025,h+.025,-.18,-.11,colors.trim)
        end
        for i=1,3 do
            local center=u0+(u1-u0)*(i-.5)/3;local width=(u1-u0)*.21
            panel(m,axis,plane,sign,center-width*.5,center+width*.5,h1-.85,h1-.4,-.16,-.12,colors.glass)
        end
        panel(m,axis,plane,sign,u0-.12,u1+.12,h1+.03,h1+.24,-.10,.16,colors.trim)
        feature(m,'garageBays',{axis=axis,plane=plane,u=(u0+u1)*.5,width=u1-u0,height=h1-h0})
    elseif o.kind=='door' then
        panel(m,axis,plane,sign,u0+.23,u1-.23,h0+.95,h1-.22,-.175,-.155,colors.glass)
        panel(m,axis,plane,sign,u1-.25,u1-.20,h0+.84,h0+1.18,-.10,.04,colors.trim)
        panel(m,axis,plane,sign,u0+.15,u1-.15,h0+.19,h0+.80,-.17,-.14,colors.metal)
        feature(m,'doors',{axis=axis,plane=plane,u=(u0+u1)*.5,h=h0,width=u1-u0})
    else
        local mid=(u0+u1)*.5;local rail=h0+(h1-h0)*.55
        panel(m,axis,plane,sign,mid-.028,mid+.028,h0+frame,h1-frame,-.18,.04,colors.trim)
        panel(m,axis,plane,sign,u0+frame,u1-frame,rail-.028,rail+.028,-.18,.04,colors.trim)
        panel(m,axis,plane,sign,u0-.08,u1+.08,h0-.07,h0+.035,-.25,.18,colors.stone)
        panel(m,axis,plane,sign,u0-.05,u1+.05,h1,h1+.13,-.10,.12,colors.trim)
        feature(m,'windows',{axis=axis,plane=plane,u=mid,h=h0,recess=.185,panes=4})
    end
end
local function sortedCuts(values)
    table.sort(values);local out={}
    for _,v in ipairs(values) do if #out==0 or math.abs(v-out[#out])>1e-7 then out[#out+1]=v end end
    return out
end
local function facade(m,axis,plane,sign,u0,u1,height,floors,color,door,options)
    options=options or {};local openings={};local storey=height/floors
    for _,o in ipairs(options.openings or {}) do openings[#openings+1]=o end
    local bays=math.max(1,math.floor((u1-u0)/2.7));local step=(u1-u0)/bays
    local doorWidth=options.doorWidth or 1.4
    if door then openings[#openings+1]={u0=door-doorWidth*.5,u1=door+doorWidth*.5,h0=.10,
        h1=math.min(options.doorHeight or 2.65,height-.3),kind='door'} end
    for floor=0,floors-1 do
        for bay=1,bays do
            local center=u0+(bay-.5)*step;local width=math.min(options.windowWidth or 1.65,step*.66)
            if not options.noWindows and not (floor==0 and door and math.abs(center-door)<width*.5+doorWidth*.5+.22) then
                openings[#openings+1]={u0=center-width*.5,u1=center+width*.5,
                    h0=floor*storey+(options.windowBase or .78),
                    h1=floor*storey+math.min(storey-.4,options.windowTop or 2.45),kind='window'}
            end
        end
    end
    local us,hs={u0,u1},{0,height}
    for _,o in ipairs(openings) do us[#us+1]=o.u0;us[#us+1]=o.u1;hs[#hs+1]=o.h0;hs[#hs+1]=o.h1 end
    us,hs=sortedCuts(us),sortedCuts(hs)
    for i=1,#us-1 do for j=1,#hs-1 do
        local u,h=(us[i]+us[i+1])*.5,(hs[j]+hs[j+1])*.5;local hole=false
        for _,o in ipairs(openings) do if u>o.u0 and u<o.u1 and h>o.h0 and h<o.h1 then hole=true;break end end
        if not hole then panel(m,axis,plane,sign,us[i],us[i+1],hs[j],hs[j+1],-.28,0,color) end
    end end
    for _,o in ipairs(openings) do opening(m,axis,plane,sign,o) end
end
local function roofEdge(m,r,height,parapet)
    local b=Geometry.box
    b(m,r.minX-.12,r.minZ-.12,height-.16,r.maxX+.12,r.maxZ+.12,height+.08,colors.trim)
    b(m,r.minX,r.minZ,height+.08,r.maxX,r.maxZ,height+.13,colors.roof)
    if parapet then
        for _,p in ipairs({{r.minX,r.minZ,r.maxX,r.minZ+.18},{r.minX,r.maxZ-.18,r.maxX,r.maxZ},
            {r.minX,r.minZ+.18,r.minX+.18,r.maxZ-.18},{r.maxX-.18,r.minZ+.18,r.maxX,r.maxZ-.18}}) do
            b(m,p[1],p[2],height+.08,p[3],p[4],height+.46,colors.wall)
            b(m,p[1]-.035,p[2]-.035,height+.46,p[3]+.035,p[4]+.035,height+.55,colors.trim)
        end
    end
    feature(m,'roofs',{height=height,parapet=parapet==true})
end
local function block(m,r,height,floors,color,door,options)
    Geometry.box(m,r.minX,r.minZ,-.08,r.maxX,r.maxZ,.12,colors.stone)
    facade(m,'z',r.maxZ,1,r.minX,r.maxX,height,floors,color,door,options)
    facade(m,'z',r.minZ,-1,r.minX,r.maxX,height,floors,color,nil,options)
    facade(m,'x',r.minX,-1,r.minZ,r.maxZ,height,floors,color,nil,options)
    facade(m,'x',r.maxX,1,r.minZ,r.maxZ,height,floors,color,nil,options)
    for floor=1,floors-1 do
        local h=floor*height/floors
        Geometry.box(m,r.minX-.06,r.minZ-.06,h-.09,r.maxX+.06,r.maxZ+.06,h+.07,colors.trim)
    end
    roofEdge(m,r,height,not (options and options.pitched))
end
local function entry(m,x,z,wide)
    local width=wide or 2.5;local b=Geometry.box
    b(m,x-width*.5,z-.65,.02,x+width*.5,z-.32,.07,colors.stone)
    b(m,x-width*.5+.12,z-.32,.02,x+width*.5-.12,z,.13,colors.stone)
    b(m,x-width*.5-.15,z-.25,2.85,x+width*.5+.15,z+.65,3.02,colors.roof)
    b(m,x-width*.5-.15,z+.59,2.75,x+width*.5+.15,z+.69,3.02,colors.trim)
    for _,side in ipairs({-1,1}) do
        local px=x+side*(width*.5-.10)
        b(m,px-.065,z-.12,.12,px+.065,z+.015,2.85,colors.trim)
    end
    feature(m,'entries',{x=x,z=z,h=0,canopy=true,steps=2})
end
local function mechanical(m,x,z,height)
    local b=Geometry.box
    b(m,x-.78,z-.54,height+.13,x+.78,z+.54,height+.72,colors.metal)
    b(m,x-.87,z-.62,height+.72,x+.87,z+.62,height+.81,colors.roof)
    for i=1,5 do b(m,x-.62,z+.545,height+.20+i*.075,x+.62,z+.58,height+.23+i*.075,colors.recess) end
    Geometry.cylinder(m,x+2,z,height+.13,.23,.92,colors.metal,12)
    Geometry.cylinder(m,x+2,z,height+1.03,.36,.12,colors.trim,12)
    feature(m,'mechanical',{x=x,z=z,h=height+.13,vent=true})
end
local function balcony(m,axis,plane,sign,u0,u1,height)
    panel(m,axis,plane,sign,u0,u1,height-.10,height+.05,-.02,.8,colors.stone)
    panel(m,axis,plane,sign,u0,u1,height+.94,height+1.01,.72,.80,colors.rail)
    local count=math.max(2,math.floor((u1-u0)/.32))
    for i=0,count do
        local u=u0+(u1-u0)*i/count
        panel(m,axis,plane,sign,u-.025,u+.025,height+.05,height+.98,.73,.78,colors.rail)
    end
    for _,u in ipairs({u0,u1}) do panel(m,axis,plane,sign,u-.035,u+.035,height+.94,height+1.01,0,.8,colors.rail) end
    feature(m,'balconies',{axis=axis,plane=plane,u0=u0,u1=u1,h=height})
end
local function pitchedRoof(m,r,height,rise,palette)
    palette=palette or {}
    local roofColor,trimColor,gableColor=palette.roof or colors.roof,palette.trim or colors.trim,
        palette.gable or colors.wall
    local e=.30;local x0,x1,z0,z1=r.minX-e,r.maxX+e,r.minZ-e,r.maxZ+e;local mid=(z0+z1)*.5
    local slope=(rise-.12)/(mid-z0);local length=math.sqrt(1+slope*slope)
    Geometry.quad(m,{x0,z0,height+.12},{x1,z0,height+.12},{x1,mid,height+rise},{x0,mid,height+rise},roofColor,{0,1/length,-slope/length})
    Geometry.quad(m,{x0,mid,height+rise},{x1,mid,height+rise},{x1,z1,height+.12},{x0,z1,height+.12},roofColor,{0,1/length,slope/length})
    Geometry.triangle(m,{r.minX,r.minZ,height},{r.minX,r.maxZ,height},{r.minX,mid,height+rise-.10},gableColor,{-1,0,0})
    Geometry.triangle(m,{r.maxX,r.maxZ,height},{r.maxX,r.minZ,height},{r.maxX,mid,height+rise-.10},gableColor,{1,0,0})
    Geometry.box(m,x0,z0-.04,height+.02,x1,z0+.04,height+.22,trimColor)
    Geometry.box(m,x0,z1-.04,height+.02,x1,z1+.04,height+.22,trimColor)
    Geometry.box(m,x0,mid-.08,height+rise-.04,x1,mid+.08,height+rise+.08,trimColor)
    feature(m,'pitchedRoofs',{rise=rise})
end
local function warehouse(m,design,r)
    local height=design.height
    Geometry.box(m,r.minX,r.minZ,-.08,r.maxX,r.maxZ,.12,colors.stone)
    facade(m,'z',r.minZ,-1,r.minX,r.maxX,height,1,colors.metal)
    facade(m,'x',r.minX,-1,r.minZ,r.maxZ,height,1,colors.metal)
    facade(m,'x',r.maxX,1,r.minZ,r.maxZ,height,1,colors.metal,(r.minZ+r.maxZ)*.5,
        {doorWidth=design.depth-1.2,doorHeight=3.45,noWindows=true})
    roofEdge(m,r,height,true)
    -- A brick facade is modeled as large wall piers/bands, never one mesh per brick.
    facade(m,'z',r.maxZ,1,r.minX,r.maxX,height,1,colors.brick,design.threshold.x,{windowWidth=2.0})
    Geometry.box(m,r.minX+.3,r.maxZ+.03,3.30,r.maxX-.3,r.maxZ+.20,4.10,colors.trim)
    Geometry.box(m,r.minX+.46,r.maxZ+.20,3.43,r.maxX-.46,r.maxZ+.23,3.97,colors.sign)
    feature(m,'signs',{text='THE PICTURE SHOP',x=0,z=r.maxZ+.24,h=3.70,width=design.width-.92,height=.54})
    Geometry.lettering(m,'THE PICTURE SHOP',0,r.maxZ+.235,3.70,design.width-1.2,.44)
    -- Actual inset loading leaf, tracks and rib geometry on the east side.
    panel(m,'x',r.maxX+.02,1,r.minZ+.6,r.maxZ-.6,.12,3.45,-.03,.06,colors.recess)
    panel(m,'x',r.maxX+.02,1,r.minZ+.76,r.maxZ-.76,.20,3.31,.07,.10,colors.metal)
    for i=1,8 do panel(m,'x',r.maxX+.02,1,r.minZ+.76,r.maxZ-.76,.20+i*.34,.24+i*.34,.10,.13,colors.trim) end
    for _,z in ipairs({r.minZ+.62,r.maxZ-.72}) do panel(m,'x',r.maxX+.02,1,z,z+.10,.15,3.44,.06,.20,colors.trim) end
    feature(m,'loadingDoors',{axis='x',plane=r.maxX,h=0,width=design.depth-1.2})
    for _,x in ipairs({r.minX+.22,r.maxX-.22}) do Geometry.box(m,x-.04,r.minZ-.06,.1,x+.04,r.minZ+.03,height,colors.metal) end
    entry(m,design.threshold.x,design.threshold.z,2.1)
    mechanical(m,-1.4,-.2,height)
end
local function sign(m,d,r,text,height)
    local width=math.min(d.width-1.4,11);local h=height or d.height-.8
    Geometry.box(m,-width*.5,r.maxZ+.03,h-.28,width*.5,r.maxZ+.16,h+.28,colors.trim)
    Geometry.box(m,-width*.5+.10,r.maxZ+.16,h-.20,width*.5-.10,r.maxZ+.19,h+.20,colors.sign)
    feature(m,'signs',{text=text,x=0,z=r.maxZ+.20,h=h,width=width-.2,height=.4})
    Geometry.lettering(m,text,0,r.maxZ+.195,h,width-.4,.33)
end
local function corbels(m,r,height)
    local count=math.max(3,math.floor((r.maxX-r.minX)/.65))
    for i=0,count do
        local x=r.minX+.20+(r.maxX-r.minX-.40)*i/count
        Geometry.box(m,x-.07,r.maxZ-.03,height-.40,x+.07,r.maxZ+.12,height-.15,colors.trim)
    end
    feature(m,'corbelledCornices',{count=count+1})
end
local function portico(m,x,z,width,height)
    for _,side in ipairs({-1,1}) do
        local px=x+side*(width*.5-.28)
        Geometry.box(m,px-.21,z-.35,.06,px+.21,z+.07,.27,colors.stone)
        Geometry.cylinder(m,px,z-.14,.27,.14,height-.40,colors.trim,10)
        Geometry.box(m,px-.20,z-.34,height-.18,px+.20,z+.06,height+.02,colors.trim)
    end
    Geometry.box(m,x-width*.5,z-.46,height,x+width*.5,z+.85,height+.20,colors.trim)
    Geometry.triangle(m,{x-width*.5,z+.86,height+.20},{x+width*.5,z+.86,height+.20},
        {x,z+.86,height+.95},colors.stone,{0,0,1})
    Geometry.triangle(m,{x+width*.5,z-.46,height+.20},{x-width*.5,z-.46,height+.20},
        {x,z-.46,height+.95},colors.stone,{0,0,-1})
    local slope=1.5/width;local length=math.sqrt(1+slope*slope)
    Geometry.quad(m,{x-width*.5,z-.46,height+.20},{x-width*.5,z+.86,height+.20},
        {x,z+.86,height+.95},{x,z-.46,height+.95},colors.roof,{-slope/length,1/length,0})
    Geometry.quad(m,{x,z-.46,height+.95},{x,z+.86,height+.95},
        {x+width*.5,z+.86,height+.20},{x+width*.5,z-.46,height+.20},colors.roof,{slope/length,1/length,0})
    feature(m,'porticos',{x=x,z=z,width=width})
end
local function curvedCanopy(m,x,z,width,depth,height,palette)
    local segments=16;local thick=.16
    palette=palette or {roof=colors.roof,trim=colors.trim}
    for i=0,segments-1 do
        local a,b=i*math.pi/segments,(i+1)*math.pi/segments
        local ax,az=x+math.cos(a)*width*.5,z+math.sin(a)*depth
        local bx,bz=x+math.cos(b)*width*.5,z+math.sin(b)*depth
        local roofColor=palette.alternate and i%2==0 and palette.alternate or palette.roof
        Geometry.triangle(m,{x,z,height},{ax,az,height},{bx,bz,height},roofColor,{0,1,0})
        Geometry.triangle(m,{x,z,height-thick},{bx,bz,height-thick},{ax,az,height-thick},palette.trim,{0,-1,0})
        local nx,nz=math.cos((a+b)*.5)/(width*.5),math.sin((a+b)*.5)/depth;local length=math.sqrt(nx*nx+nz*nz)
        Geometry.quad(m,{ax,az,height-thick},{bx,bz,height-thick},{bx,bz,height},{ax,az,height},palette.trim,{nx/length,0,nz/length})
    end
    feature(m,'curvedCanopies',{x=x,z=z,width=width,depth=depth})
end
local function pergola(m,x,z,width,height)
    for _,side in ipairs({-1,1}) do
        local px=x+side*(width*.5-.15)
        Geometry.box(m,px-.075,z-.25,0,px+.075,z-.10,height,colors.door)
    end
    Geometry.box(m,x-width*.5,z-.3,height-.10,x+width*.5,z-.12,height+.08,colors.door)
    Geometry.box(m,x-width*.5,z+.9,height-.10,x+width*.5,z+1.08,height+.08,colors.door)
    for i=0,math.floor(width/.42) do
        local u=x-width*.5+width*i/math.floor(width/.42)
        Geometry.box(m,u-.045,z-.40,height,u+.045,z+1.2,height+.14,colors.trim)
    end
    feature(m,'pergolas',{x=x,z=z,width=width})
end
local function ruralHouse(m)
    local r={minX=7,maxX=18,minZ=-17,maxZ=-7};local height=4.15
    Geometry.box(m,r.minX,r.minZ,-.08,r.maxX,r.maxZ,.12,colors.stone)
    facade(m,'z',r.maxZ,1,r.minX,r.maxX,height,1,colors.farmhouse,12,
        {windowWidth=1.25,windowBase=.9,windowTop=2.55,doorWidth=1.2,doorHeight=2.55})
    facade(m,'z',r.minZ,-1,r.minX,r.maxX,height,1,colors.farmhouse)
    facade(m,'x',r.minX,-1,r.minZ,r.maxZ,height,1,colors.farmhouse)
    facade(m,'x',r.maxX,1,r.minZ,r.maxZ,height,1,colors.farmhouse)
    Geometry.box(m,11.46,r.maxZ+.035,.12,12.54,r.maxZ+.11,2.26,colors.wood)
    entry(m,12,r.maxZ,2.5)
    pitchedRoof(m,r,height,2.15,{roof={.28,.25,.20},trim=colors.farmTrim,gable=colors.farmhouse})
    for _,x in ipairs({r.minX+.22,r.maxX-.22}) do
        Geometry.box(m,x-.07,r.maxZ-.04,.1,x+.07,r.maxZ+.08,height,colors.farmTrim)
    end
    feature(m,'farmhouses',{bounds=r,doorX=12,doorZ=r.maxZ})
end
local function brace(m,x0,h0,x1,h1,z,width,color)
    local dx,dh=x1-x0,h1-h0;local length=math.sqrt(dx*dx+dh*dh)
    local ox,oh=-dh/length*width*.5,dx/length*width*.5
    Geometry.quad(m,{x0+ox,z,h0+oh},{x0-ox,z,h0-oh},{x1-ox,z,h1-oh},{x1+ox,z,h1+oh},color,{0,0,1})
end
local function ruralBarn(m)
    local r={minX=-18,maxX=-3,minZ=-16,maxZ=-1};local height=4.85
    Geometry.box(m,r.minX,r.minZ,-.08,r.maxX,r.maxZ,.15,colors.stone)
    facade(m,'z',r.maxZ,1,r.minX,r.maxX,height,1,colors.barn,nil,
        {noWindows=true,openings={{u0=-15.6,u1=-5.4,h0=.12,h1=3.55,kind='garage'}}})
    facade(m,'z',r.minZ,-1,r.minX,r.maxX,height,1,colors.barn)
    facade(m,'x',r.minX,-1,r.minZ,r.maxZ,height,1,colors.barn)
    facade(m,'x',r.maxX,1,r.minZ,r.maxZ,height,1,colors.barn)
    -- A red sliding barn door with pale timber framing and cross braces.
    Geometry.box(m,-15.45,r.maxZ+.045,.15,-5.55,r.maxZ+.12,3.45,colors.barnDoor)
    for _,x in ipairs({-15.65,-5.35}) do
        Geometry.box(m,x-.12,r.maxZ+.05,.08,x+.12,r.maxZ+.16,3.65,colors.farmTrim)
    end
    Geometry.box(m,-15.65,r.maxZ+.05,3.52,-5.35,r.maxZ+.16,3.72,colors.farmTrim)
    for _,x in ipairs({-14.8,-12.3,-9.7,-7.1,-6.2}) do
        Geometry.box(m,x-.045,r.maxZ+.13,.22,x+.045,r.maxZ+.17,3.40,colors.barn)
    end
    brace(m,-15.1,.34,-5.9,3.28,r.maxZ+.18,.20,colors.farmTrim)
    brace(m,-5.9,.34,-15.1,3.28,r.maxZ+.18,.20,colors.farmTrim)
    pitchedRoof(m,r,height,2.72,{roof={.22,.25,.20},trim=colors.farmTrim,gable=colors.barn})
    -- Narrow siding boards and a small loft vent make the barn read at a distance.
    for x=-17.5,-3.5,.7 do
        Geometry.box(m,x-.025,r.maxZ+.015,.20,x+.025,r.maxZ+.035,4.35,colors.farmTrim)
    end
    Geometry.box(m,-11.4,r.maxZ+.04,4.03,-9.6,r.maxZ+.12,4.37,colors.barnDoor)
    feature(m,'barns',{bounds=r,doorWidth=10,doorHeight=3.55})
end
local function cornPlant(m,x,z,height)
    Geometry.box(m,x-.045,z-.045,.12,x+.045,z+.045,height,colors.corn)
    for i=1,4 do
        local side=i%2==0 and 1 or -1
        local level=.28+i*.25
        local offset=side*(.24+(i%3)*.08)
        local leaf=colors.cornLeaf
        Geometry.triangle(m,{x,z,level},{x+offset,z+.05,level+.12},{x+side*.48,z+.08,level+.02},leaf,{0,0,1})
        Geometry.triangle(m,{x,z,level+.06},{x-.04,z+offset,level+.17},{x-.08,z+side*.43,level+.08},leaf,{1,0,0})
    end
    Geometry.triangle(m,{x-.12,z,height-.05},{x,z-.04,height+.28},{x+.12,z,height-.05},{.73,.66,.26},{0,0,1})
end
local function tomatoPlant(m,x,z)
    Geometry.box(m,x-.045,z-.045,.12,x+.045,z+.045,.82,colors.tomatoLeaf)
    for _,side in ipairs({-1,1}) do
        Geometry.box(m,x+side*.18-.20,z-.08,.39,x+side*.18+.20,z+.08,.51,colors.tomatoLeaf)
    end
    for _,fruit in ipairs({{-.20,.02,.39},{.20,.02,.50},{0,-.16,.61}}) do
        Geometry.cylinder(m,x+fruit[1],z+fruit[2],fruit[3],.105,.14,colors.tomato,6)
    end
end
local function fenceRun(m,x0,z0,x1,z1,spacing)
    local length=math.sqrt((x1-x0)^2+(z1-z0)^2);local count=math.max(1,math.ceil(length/spacing))
    for i=0,count do
        local t=i/count;local x,z=x0+(x1-x0)*t,z0+(z1-z0)*t
        Geometry.box(m,x-.08,z-.08,.08,x+.08,z+.08,1.34,colors.wood)
        if i<count then
            local nextT=(i+1)/count;local nx,nz=x0+(x1-x0)*nextT,z0+(z1-z0)*nextT
            local thick=.075
            if math.abs(x1-x0)>math.abs(z1-z0) then
                Geometry.box(m,math.min(x,nx),z-thick,.42,math.max(x,nx),z+thick,.54,colors.farmTrim)
                Geometry.box(m,math.min(x,nx),z-thick,.90,math.max(x,nx),z+thick,1.02,colors.farmTrim)
            else
                Geometry.box(m,x-thick,math.min(z,nz),.42,x+thick,math.max(z,nz),.54,colors.farmTrim)
                Geometry.box(m,x-thick,math.min(z,nz),.90,x+thick,math.max(z,nz),1.02,colors.farmTrim)
            end
        end
    end
end
local function farm(m,d)
    ruralBarn(m);ruralHouse(m)
    -- Cultivated beds are distinct plots: tall corn to the west and tomatoes
    -- on low trellised rows to the east, with a dirt lane between them.
    local corn={minX=-19,maxX=-1,minZ=1,maxZ=18}
    Geometry.box(m,corn.minX,corn.minZ,.025,corn.maxX,corn.maxZ,.11,colors.soil)
    local cornRows,cornCount=0,0
    for row=0,6 do
        local x=-17.65+row*2.38;cornRows=cornRows+1
        Geometry.box(m,x-.63,corn.minZ+.2,.11,x+.63,corn.maxZ-.2,.20,{.36,.23,.12})
        for column=0,7 do
            cornPlant(m,x,2.25+column*2.05,1.55+(column%3)*.09);cornCount=cornCount+1
        end
    end
    feature(m,'cornFields',{bounds=corn,rows=cornRows,plants=cornCount})
    local tomatoes={minX=2,maxX=18,minZ=1,maxZ=18}
    Geometry.box(m,tomatoes.minX,tomatoes.minZ,.025,tomatoes.maxX,tomatoes.maxZ,.11,colors.soil)
    local tomatoRows,tomatoCount=0,0
    for row=0,5 do
        local x=3.2+row*2.72;tomatoRows=tomatoRows+1
        Geometry.box(m,x-.50,tomatoes.minZ+.25,.11,x+.50,tomatoes.maxZ-.25,.18,{.39,.25,.13})
        for column=0,5 do
            tomatoPlant(m,x,2.35+column*2.72);tomatoCount=tomatoCount+1
        end
        Geometry.box(m,x-.54,tomatoes.minZ+.5,.95,x+.54,tomatoes.maxZ-.5,1.01,colors.wood)
    end
    feature(m,'tomatoFields',{bounds=tomatoes,rows=tomatoRows,plants=tomatoCount})
    -- The farm drive ends at a simple timber gate; no interaction is wired yet.
    for _,x in ipairs({-3,3}) do Geometry.box(m,x-.16,19.10,.08,x+.16,19.42,2.35,colors.wood) end
    Geometry.box(m,-3.05,19.06,2.20,3.05,19.46,2.47,colors.wood)
    Geometry.box(m,-2.35,19.47,2.23,2.35,19.51,3.22,colors.farmTrim)
    Geometry.lettering(m,'MILLER FARM',0,19.52,2.75,3.25,.48)
    fenceRun(m,-20,-19,-20,19,4.6);fenceRun(m,20,-19,20,19,4.6)
    fenceRun(m,-20,-19,20,-19,4.8)
    fenceRun(m,-20,19,-3.2,19,4.8);fenceRun(m,3.2,19,20,19,4.8)
    feature(m,'farmFences',{gateWidth=6.4})
    feature(m,'farmApproach',{threshold=d.threshold,parking=d.parking})
end
local services={['gas-station']=true,mechanic=true,grocery=true,['post-office']=true,police=true,['fire-station']=true,
    diner=true,['coffee-shop']=true,['general-store']=true}
local function commercial(m,d,r)
    local b=Geometry.box;local style=d.style;local height=d.height
    local front={windowWidth=2.1,windowBase=.55,windowTop=3.1}
    if style=='mechanic' or style=='fire-station' then
        front={noWindows=true,openings={}}
        local count=style=='mechanic' and 2 or 3
        local start=r.minX+4;local step=(r.maxX-.5-start)/count
        for i=1,count do
            local center=start+(i-.5)*step
            front.openings[#front.openings+1]={u0=center-step*.40,u1=center+step*.40,h0=.12,
                h1=height-(style=='mechanic' and 1.05 or 1.25),kind='garage'}
        end
    elseif style=='grocery' then
        front={windowWidth=2.55,windowBase=.45,windowTop=2.65,doorWidth=1.8,doorHeight=2.65}
    elseif style=='gas-station' then
        front={windowWidth=1.75,windowBase=.55,windowTop=2.7}
    elseif style=='coffee-shop' then front.windowTop=2.75
    elseif style=='diner' then front.windowWidth=2.65;front.windowBase=.65;front.windowTop=2.6
    elseif style=='police' or style=='general-store' then front={windowWidth=1.65} end
    local facadePalette={mechanic=colors.mechanicSteel,['gas-station']=colors.gasWall,
        grocery=colors.groceryWall,['post-office']=colors.postOfficeWall,
        police=colors.policeWall,['fire-station']=colors.fireWall,
        diner=colors.dinerWall,['coffee-shop']=colors.coffeeWall,
        ['general-store']=colors.generalWall}
    local facadeColor=facadePalette[style] or colors.brick
    local sideColor=facadePalette[style] or colors.wall
    b(m,r.minX,r.minZ,-.08,r.maxX,r.maxZ,.12,colors.stone)
    facade(m,'z',r.maxZ,1,r.minX,r.maxX,height,d.floors,facadeColor,d.threshold.x,front)
    facade(m,'z',r.minZ,-1,r.minX,r.maxX,height,d.floors,sideColor)
    facade(m,'x',r.minX,-1,r.minZ,r.maxZ,height,d.floors,sideColor)
    facade(m,'x',r.maxX,1,r.minZ,r.maxZ,height,d.floors,sideColor)
    roofEdge(m,r,height,style~='mechanic');corbels(m,r,height)
    entry(m,d.threshold.x,d.threshold.z,2.3)
    if style=='mechanic' then
        pitchedRoof(m,r,height,1.35)
        b(m,r.minX+.5,r.maxZ-.2,3.20,r.maxX-.5,r.maxZ+1.35,3.38,colors.metal)
        feature(m,'workCanopies',{width=d.width-1,depth=1.55})
        for index,x in ipairs({-3.7,6.55}) do
            for layer=0,2 do
                Geometry.cylinder(m,x,r.maxZ+.60,.08+layer*.25,.36,.20,colors.recess,12)
            end
            Geometry.cylinder(m,x,r.maxZ+.60,.68,.14,.08,colors.metal,10)
            feature(m,'tireStacks',{x=x,z=r.maxZ+.60,layers=3,side=index})
        end
        b(m,5.8,r.maxZ+.30,.08,7.0,r.maxZ+.74,1.02,colors.gasRed)
        for h=.30,.82,.26 do
            b(m,5.86,r.maxZ+.751,h,6.94,r.maxZ+.79,h+.08,colors.metal)
        end
        feature(m,'mechanicToolCabinets',{x=6.4,z=r.maxZ+.52})
        sign(m,d,r,mechanicSign,height-.48)
    elseif style=='gas-station' then
        local asphalt={.28,.30,.29};local stripe={.92,.82,.50}
        local pumpRed={.73,.16,.12};local pumpWhite={.82,.83,.78};local display={.10,.26,.24}
        -- A broad, level apron connects the building to clearly marked pump
        -- bays and a separate truck pull-through space.
        b(m,-5.5,4,-.08,5.5,13.5,.025,asphalt)
        for _,x in ipairs({-3.05,-1.35,1.35,3.05}) do
            b(m,x-.035,5.35,.03,x+.035,7.65,.047,stripe)
        end
        for _,z in ipairs({5.35,7.65}) do
            b(m,-3.085,z,.03,-1.315,z+.07,.047,stripe)
            b(m,1.315,z,.03,3.085,z+.07,.047,stripe)
        end
        -- Truck bay markings sit beyond the two motorcycle bays.
        for _,x in ipairs({-3.45,3.45}) do b(m,x-.045,9.35,.03,x+.045,13.15,.047,stripe) end
        for _,z in ipairs({9.35,13.1}) do b(m,-3.45,z,.03,3.45,z+.07,.047,stripe) end
        b(m,-4.55,3.75,3.15,4.55,9.1,3.42,colors.roof)
        for _,x in ipairs({-4.25,4.25}) do
            for _,z in ipairs({4.05,8.8}) do
                b(m,x-.11,z-.11,0,x+.11,z+.11,3.15,colors.metal)
                b(m,x-.16,z-.16,0,x+.16,z+.16,.18,colors.trim)
            end
        end
        for index,x in ipairs({-3,3}) do
            -- Raised island, cabinet, digital display, payment keypad and
            -- hose/nozzle make each dispenser readable at terrain scale.
            b(m,x-.57,4.22,.025,x+.57,5.38,.13,colors.stone)
            b(m,x-.39,4.38,.13,x+.39,5.12,1.42,pumpWhite)
            b(m,x-.43,4.36,1.39,x+.43,5.14,1.58,pumpRed)
            b(m,x-.31,5.125,.87,x+.31,5.155,1.25,display)
            b(m,x-.25,5.16,1.02,x+.25,5.18,1.12,colors.sign)
            for row=0,1 do
                for column=0,2 do
                    local bx=x-.18+column*.16;local bh=.69-row*.14
                    b(m,bx,5.13,bh,bx+.085,5.16,bh+.065,
                        (row+column)%2==0 and colors.sign or pumpRed)
                end
            end
            b(m,x+.40,4.78,.35,x+.49,4.94,.43,colors.metal)
            b(m,x+.42,4.82,.44,x+.46,4.90,1.13,colors.metal)
            b(m,x+.29,4.84,1.00,x+.47,4.91,1.07,colors.metal)
            b(m,x+.40,4.80,1.04,x+.52,4.94,1.17,pumpRed)
            feature(m,'fuelPumps',{x=x,z=4.8,side=index,screen=true,nozzle=true})
        end
        feature(m,'pumpBays',{centers={{x=-2.2,z=6.5},{x=2.2,z=6.5}},count=2})
        feature(m,'truckPumpBay',{x=0,z=11.1,width=6.9,depth=3.8})
        feature(m,'pumpCanopy',{width=9.1,depth=5.35,frontZ=9.1})
        -- A bright branded canopy edge is visible from the road before the
        -- player reaches the pumps.
        b(m,-4.55,8.98,3.10,4.55,9.19,3.49,colors.gasRed)
        b(m,-4.55,8.98,3.10,4.55,9.19,3.20,colors.gasYellow)
        Geometry.lettering(m,'FUEL',0,9.20,3.28,3.1,.28)
        sign(m,d,r,'GAS',3.21)
        -- Small roadside price/amenities pylon gives the forecourt its own
        -- landmark silhouette and advertises fuel and ice without relying on
        -- the building name sign.
        local pylonX,pylonZ=-4.82,10.15
        for _,dx in ipairs({-.50,.50}) do
            b(m,pylonX+dx-.065,pylonZ-.085,.02,pylonX+dx+.065,pylonZ+.085,2.75,colors.metal)
        end
        b(m,pylonX-.82,pylonZ-.16,2.68,pylonX+.82,pylonZ+.16,4.78,colors.gasRed)
        b(m,pylonX-.70,pylonZ+.161,3.40,pylonX+.70,pylonZ+.19,4.65,colors.gasYellow)
        Geometry.lettering(m,'FUEL',pylonX,pylonZ+.19,4.27,1.22,.30)
        Geometry.lettering(m,'ICE',pylonX,pylonZ+.19,3.69,.87,.27)
        feature(m,'gasAdvertising',{x=pylonX,z=pylonZ,items={'fuel','ice'},height=4.78})
    elseif style=='grocery' then
        b(m,r.minX+.3,r.maxZ-.1,3.22,r.maxX-.3,r.maxZ+1.20,3.40,colors.marketGreen)
        for i=0,5 do
            local x=r.minX+.5+(d.width-1)*i/5
            b(m,x-.055,r.maxZ-.03,2.92,x+.055,r.maxZ+.18,3.35,colors.trim)
        end
        -- Cream and green fabric stripes make this read as a neighborhood
        -- market awning instead of the same flat commercial cornice.
        for i=0,7 do
            local x0=r.minX+.32+(d.width-.64)*i/8
            local x1=r.minX+.32+(d.width-.64)*(i+1)/8
            b(m,x0,r.maxZ+1.16,3.03,x1,r.maxZ+1.24,3.37,
                i%2==0 and colors.marketCream or colors.marketGreen)
        end
        feature(m,'shelteredStorefronts',{width=d.width-.6})
        for _,center in ipairs({-6.2,6.2}) do
            local z=r.maxZ+.62
            b(m,center-.96,z-.34,.12,center+.96,z+.60,.65,colors.produceCrate)
            b(m,center-.90,z-.28,.65,center+.90,z+.54,.72,colors.marketGreen)
            local fruit={colors.produceRed,colors.produceOrange,colors.produceYellow}
            for row=0,1 do for column=0,2 do
                local x=center+(column-1)*.48
                local fz=z-.08+row*.42
                Geometry.cylinder(m,x,fz,.72,.15,.15,fruit[(column+row)%#fruit+1],8)
            end end
            feature(m,'groceryProduceDisplays',{x=center,z=z,crates=2})
        end
        sign(m,d,r,'TOWN GROCERY',4.18)
        mechanical(m,1,-1,height)
    elseif style=='post-office' or style=='police' then
        portico(m,d.threshold.x,r.maxZ,4.5,3.1)
        sign(m,d,r,style=='police' and 'POLICE' or 'POST OFFICE',height-.80)
        if style=='post-office' then
            -- Solid mail collection cabinet beside the public entrance.
            local x=r.minX+1.1;local z=r.maxZ-.10
            b(m,x-.32,z-.32,.10,x+.32,z+.24,1.32,colors.mailBlue)
            b(m,x-.38,z-.36,1.32,x+.38,z+.29,1.43,colors.mailBlue)
            b(m,x-.25,z+.245,.90,x+.25,z+.27,.98,colors.mailRed)
            b(m,x-.21,z+.245,1.04,x+.21,z+.265,1.10,colors.recess)
            b(m,x-.22,z+.245,1.12,x+.22,z+.27,1.30,colors.sign)
            Geometry.lettering(m,'MAIL',x,z+.27,1.21,.40,.12)
            b(m,r.minX+.35,r.maxZ+.07,3.18,r.maxX-.35,r.maxZ+.17,3.45,colors.mailBlue)
            b(m,r.minX+.35,r.maxZ+.07,3.18,r.maxX-.35,r.maxZ+.17,3.27,colors.mailRed)
            feature(m,'mailboxes',{x=x,z=z})
            feature(m,'postalServiceBand',{height=3.18})
        else
            b(m,r.minX+.35,r.maxZ+.03,height*.5-.11,r.maxX-.35,r.maxZ+.13,height*.5+.08,colors.trim)
            local band=height*.5
            b(m,r.minX+.2,r.maxZ+.08,band-.16,r.maxX-.2,r.maxZ+.20,band+.20,colors.policeBlue)
            b(m,-.72,r.maxZ+.21,band-.02,.72,r.maxZ+.24,band+.92,colors.policeBlue)
            Geometry.triangle(m,{-0.44,r.maxZ+.25,band+.69},{0,r.maxZ+.25,band+.18},
                {.44,r.maxZ+.25,band+.69},colors.policeGold,{0,0,1})
            b(m,-.10,r.maxZ+.26,band+.40,.10,r.maxZ+.29,band+.62,colors.policeGold)
            b(m,-.42,r.maxZ+.03,height+.66,.42,r.maxZ+.32,height+.80,colors.metal)
            b(m,-.38,r.maxZ+.33,height+.66,-.05,r.maxZ+.52,height+.98,colors.mailRed)
            b(m,.05,r.maxZ+.33,height+.66,.38,r.maxZ+.52,height+.98,colors.gasBlue)
            feature(m,'policeBadge',{x=0,z=r.maxZ+.24,height=band+.55})
            feature(m,'policeRoofBeacon',{height=height+.98})
            feature(m,'civicBuildings',{portico=true})
        end
        mechanical(m,1,-2,height)
    elseif style=='fire-station' then
        local tower={minX=r.minX,maxX=r.minX+3.3,minZ=r.minZ,maxZ=r.minZ+3.3}
        b(m,tower.minX,tower.minZ,height,tower.maxX,tower.maxZ,height+4.4,colors.brick)
        roofEdge(m,tower,height+4.4,true)
        for i=1,3 do
            local h=height+.55+i*.78
            panel(m,'z',tower.maxZ,1,tower.minX+.75,tower.maxX-.75,h,h+.38,.01,.04,colors.recess)
        end
        -- Red apparatus-bay lintel and a bell on the hose tower reinforce the
        -- station silhouette even when the lettering is too small to read.
        b(m,r.minX+.2,r.maxZ+.08,height-1.20,r.maxX-.2,r.maxZ+.20,height-1.00,colors.fireRed)
        b(m,r.minX+.2,r.maxZ+.08,height-1.28,r.maxX-.2,r.maxZ+.20,height-1.20,colors.fireCream)
        b(m,tower.minX+1.38,tower.maxZ+.10,height+4.38,tower.minX+1.92,tower.maxZ+.36,height+4.54,colors.metal)
        Geometry.cylinder(m,tower.minX+1.65,tower.maxZ+.23,height+4.54,.27,.34,colors.fireRed,12)
        feature(m,'fireApparatusBays',{count=3,lintelHeight=height-1.00})
        feature(m,'fireBell',{x=tower.minX+1.65,z=tower.maxZ+.23,height=height+4.88})
        feature(m,'hoseTowers',{x=tower.minX,z=tower.minZ,height=height+4.4})
        sign(m,d,r,'FIRE STATION',height-.62)
    elseif style=='diner' then
        curvedCanopy(m,0,r.maxZ+.02,d.width-.5,1.5,2.96,
            {roof=colors.dinerRed,trim=colors.dinerCream,alternate=colors.dinerCream})
        b(m,r.minX+1,r.minZ+1,height+.10,r.maxX-1,r.maxZ-1,height+.72,colors.metal)
        panel(m,'z',r.maxZ-1,1,r.minX+1.25,r.maxX-1.25,height+.22,height+.56,.01,.04,colors.glass)
        for i=1,6 do
            local x=r.minX+1+(d.width-2)*i/7
            panel(m,'z',r.maxZ-1,1,x-.04,x+.04,height+.16,height+.65,.04,.08,colors.trim)
        end
        feature(m,'clerestories',{height=height+.72})
        b(m,r.minX+.3,r.maxZ+.06,2.86,r.maxX-.3,r.maxZ+.16,3.03,colors.dinerRed)
        for _,x in ipairs({-5.1,5.1}) do
            local z=r.maxZ+1.05
            Geometry.cylinder(m,x,z,.68,.44,.10,colors.dinerRed,12)
            Geometry.cylinder(m,x,z,.18,.07,.50,colors.metal,10)
            for _,side in ipairs({-1,1}) do
                b(m,x+side*.66-.23,z-.18,.16,x+side*.66+.23,z+.18,.50,colors.dinerCream)
            end
            feature(m,'dinerOutdoorTables',{x=x,z=z,seats=2})
        end
        sign(m,d,r,'DINER',3.53)
    elseif style=='coffee-shop' then
        pergola(m,0,r.maxZ,d.width-1,2.95)
        local cupZ=r.maxZ+.24
        b(m,-.92,r.maxZ+.06,3.82,.92,r.maxZ+.20,5.04,colors.coffeeBrown)
        Geometry.quad(m,{-.43,cupZ,4.76},{-.30,cupZ,4.20},{.30,cupZ,4.20},
            {.43,cupZ,4.76},colors.coffeeCream,{0,0,1})
        b(m,.40,cupZ,4.52,.66,cupZ+.035,4.62,colors.coffeeCream)
        b(m,.52,cupZ,4.30,.66,cupZ+.035,4.53,colors.coffeeCream)
        b(m,.40,cupZ,4.22,.66,cupZ+.035,4.32,colors.coffeeCream)
        b(m,-.52,cupZ,4.10,.52,cupZ+.06,4.18,colors.trim)
        for _,x in ipairs({-.25,0,.25}) do
            b(m,x-.035,cupZ,4.82,x+.035,cupZ+.035,4.98,colors.coffeeCream)
        end
        feature(m,'coffeeCupLogo',{x=0,z=cupZ,height=4.4})
        for _,x in ipairs({-3.15,3.15}) do
            local z=r.maxZ+.82
            Geometry.cylinder(m,x,z,.72,.43,.10,colors.coffeeBrown,12)
            Geometry.cylinder(m,x,z,.12,.065,.60,colors.generalWood,10)
            for _,side in ipairs({-1,1}) do
                b(m,x+side*.65-.22,z-.17,.17,x+side*.65+.22,z+.17,.48,colors.generalWood)
            end
            feature(m,'coffeePatioSeating',{x=x,z=z,seats=2})
        end
        sign(m,d,r,'COFFEE',3.30)
        mechanical(m,-1,-1,height)
    elseif style=='general-store' then
        b(m,r.minX+.2,r.maxZ-.15,2.78,r.maxX-.2,r.maxZ+1.18,2.98,colors.generalSage)
        for _,x in ipairs({r.minX+.6,r.minX+3,r.maxX-3,r.maxX-.6}) do
            b(m,x-.09,r.maxZ-.14,0,x+.09,r.maxZ+.01,2.80,colors.generalWood)
        end
        feature(m,'coveredPorches',{width=d.width-.4,depth=1.33})
        for _,x in ipairs({-4.9,4.9}) do
            local z=r.maxZ+.72
            b(m,x-.52,z-.38,.08,x+.52,z+.38,.72,colors.generalWood)
            b(m,x-.45,z-.31,.72,x+.45,z+.31,.82,colors.generalSage)
            local barrelX=x+(x>0 and .95 or -.95)
            Geometry.cylinder(m,barrelX,z+.08,.12,.31,.82,colors.generalWood,10)
            Geometry.cylinder(m,barrelX,z+.08,.38,.34,.08,colors.trim,10)
            Geometry.cylinder(m,barrelX,z+.08,.65,.34,.08,colors.trim,10)
            feature(m,'generalStoreDisplays',{x=x,z=z,barrel=true,crate=true})
        end
        for i=0,9 do
            local x=r.minX+.25+(d.width-.5)*i/10
            b(m,x-.045,r.maxZ+1.12,2.80,x+.045,r.maxZ+1.18,2.98,
                i%2==0 and colors.generalWood or colors.generalSage)
        end
        sign(m,d,r,'GENERAL STORE',3.6)
        mechanical(m,1,-1,height)
    end
    feature(m,'services',{kind=style})
end
function Geometry.finish(m,site)
    local bounds=m.bounds
    for _,v in ipairs(m.vertices) do
        if site then
            v[1],v[2],v[3]=site:toWorld(v[1],v[2],v[3])
            v[4],v[5],v[6]=site:normalToWorld(v[4],v[5],v[6])
        end
        bounds.minX,bounds.maxX=math.min(bounds.minX,v[1]),math.max(bounds.maxX,v[1])
        bounds.minZ,bounds.maxZ=math.min(bounds.minZ,v[2]),math.max(bounds.maxZ,v[2])
        bounds.minH,bounds.maxH=math.min(bounds.minH,v[3]),math.max(bounds.maxH,v[3])
    end
    m.counts.vertices=#m.vertices;m.counts.triangles=#m.vertices/3
    if site then
        m.siteId=site.id;m.features.entrance={{x=site.threshold.x,z=site.threshold.z,h=site.threshold.h}}
        m.features.interaction={{x=site.door.x,z=site.door.z,h=site.door.h}}
    end
    return m
end
function Geometry.build(site)
    assert(site and site.design and site.toWorld,'Geometry needs a placed local structure design')
    local m=Geometry.new();local d=site.design;local r=site.localFoundation
    if d.style=='warehouse' then warehouse(m,d,r)
    elseif services[d.style] then commercial(m,d,r)
    elseif d.style=='farm' then farm(m,d)
    elseif d.style=='courtyard' then
        for _,piece in ipairs(site.localFootprints) do block(m,piece,d.height,d.floors,colors.wall) end
        -- Inward balconies overlook a genuinely open court; the entrance is a
        -- walk-through portal registered to the existing destination threshold.
        local left,right,back=site.localFootprints[1],site.localFootprints[2],site.localFootprints[3]
        balcony(m,'x',left.maxX,1,back.maxZ+.5,left.maxZ-1,d.height*.5)
        balcony(m,'x',right.minX,-1,back.maxZ+.5,right.maxZ-1,d.height*.5)
        balcony(m,'z',back.maxZ,1,left.maxX+1,right.minX-1,d.height*.5)
        for _,x in ipairs({d.threshold.x-1.65,d.threshold.x+1.65}) do
            Geometry.box(m,x-.13,d.threshold.z-.3,0,x+.13,d.threshold.z-.05,2.9,colors.trim)
        end
        Geometry.box(m,d.threshold.x-1.85,d.threshold.z-.4,2.80,d.threshold.x+1.85,d.threshold.z+.15,3.15,colors.stone)
        feature(m,'entries',{x=d.threshold.x,z=d.threshold.z,h=0,portal=true})
        feature(m,'courtyards',{open=true})
        mechanical(m,(left.minX+left.maxX)*.5,(left.minZ+left.maxZ)*.5-1,d.height)
    else
        block(m,r,d.height,d.floors,(d.style=='brick-walkup' or d.style=='residential') and colors.brick or colors.wall,d.threshold.x,
            {pitched=d.style=='garden'})
        entry(m,d.threshold.x,d.threshold.z,d.style=='garden' and 3.2 or 2.5)
        if d.style=='garden' then
            pitchedRoof(m,r,d.height,2.05)
            for _,x in ipairs({-5.8,5.8}) do balcony(m,'z',r.maxZ,1,x-1.2,x+1.2,d.height*.5) end
        else
            mechanical(m,-2,-1,d.height)
            corbels(m,r,d.height)
            if d.style=='corner' then
                -- Raised corner bay within the authoritative solid footprint.
                local bay={minX=r.maxX-2.35,maxX=r.maxX,minZ=r.maxZ-3.6,maxZ=r.maxZ}
                facade(m,'x',bay.maxX+.22,1,bay.minZ,bay.maxZ,d.height,d.floors,colors.trim)
                facade(m,'z',bay.maxZ+.22,1,bay.minX,bay.maxX,d.height,d.floors,colors.trim)
                roofEdge(m,{minX=bay.minX,maxX=bay.maxX+.22,minZ=bay.minZ,maxZ=bay.maxZ+.22},d.height+.12,true)
                feature(m,'cornerBays',{x=bay.maxX,z=bay.maxZ,floors=d.floors})
            end
        end
    end
    -- Exterior entrance fixture shares its anchor with local_lights.lua.
    local t=d.threshold
    Geometry.box(m,t.x-.25,t.z+.04,2.55,t.x+.25,t.z+.48,2.76,{.16,.19,.18})
    Geometry.box(m,t.x-.19,t.z+.15,2.53,t.x+.19,t.z+.50,2.63,{1,.87,.52,.99})
    if d.style=='farm' then
        Geometry.box(m,t.x-.06,t.z+.02,0,t.x+.06,t.z+.14,2.6,{.16,.19,.18})
    end
    return Geometry.finish(m,site)
end
return Geometry
