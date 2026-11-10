-- Low-poly woodland amenities, shared by the first- and third-person renderer.
local G=require('src.commute.structure_geometry')
local Geo={}
local wood={.40,.26,.14};local planks={.63,.46,.28};local cream={.91,.84,.64}
local green={.20,.33,.24};local dark={.13,.18,.16};local stone={.48,.47,.40}
local function box(m,x,z,h,w,d,height,color)
    G.box(m,x-w/2,z-d/2,h,x+w/2,z+d/2,h+height,color)
end
local function letters(m,text,x,z,h,w,height)
    local first=#m.vertices+1
    G.lettering(m,text,x,z,h,w,height)
    for i=first,#m.vertices do
        local v=m.vertices[i];v[9],v[10],v[11]=cream[1],cream[2],cream[3]
    end
end
local function roof(m,w,d,h,rise)
    for _,side in ipairs({-1,1}) do
        G.quad(m,{side*w/2,-d/2,h},{side*w/2,d/2,h},{0,d/2,h+rise},{0,-d/2,h+rise},green)
    end
    G.triangle(m,{-w/2,d/2,h},{w/2,d/2,h},{0,d/2,h+rise},wood)
    G.triangle(m,{w/2,-d/2,h},{-w/2,-d/2,h},{0,-d/2,h+rise},wood)
end
function Geo.stage(m)
    box(m,0,0,.02,5.2,3,.42,wood)
    for i=0,14 do box(m,0,-1.4+i*.2,.44,5.2,.185,.07,planks) end
    -- Low open platform with broad, visibly shallow steps at the front.
    box(m,0,1.65,.01,2.6,.45,.17,wood)
    box(m,0,1.5,.17,2.6,.30,.17,planks)
    for _,x in ipairs({-2.45,2.45}) do box(m,x,-1.3,.51,.13,.13,2.05,wood) end
    box(m,0,-1.3,2.3,5,.14,.32,green)
    letters(m,'WOODLAND',0,-1.215,2.46,3.8,.24)
end
function Geo.logSeat(m)
    -- Rotate an actual faceted log onto its side, including visible end grain.
    local log=G.new();G.cylinder(log,0,0,0,.24,2.4,wood,8)
    for _,v in ipairs(log.vertices) do
        local x,z,h=v[1],v[2],v[3]
        local nx,ny,nz=v[4],v[5],v[6]
        v[1],v[2],v[3]=h-1.2,z,x+.26
        v[4],v[5],v[6]=ny,nx,nz
        m.vertices[#m.vertices+1]=v
    end
    for _,side in ipairs({-1,1}) do
        local x=side*1.205
        for i=1,10 do
            local a,b=(i-1)*math.pi/5,i*math.pi/5
            G.triangle(m,{x,0,.26},{x,math.sin(a)*.19,.26+math.cos(a)*.19},
                {x,math.sin(b)*.19,.26+math.cos(b)*.19},planks,{side,0,0})
        end
    end
end
function Geo.pond(m)
    -- A shallow stone-edged pool sits just above the graded lawn. The raised
    -- bank prevents the coarse terrain mesh from poking through the water.
    local n=32
    for i=0,n-1 do
        local a,b=i*2*math.pi/n,(i+1)*2*math.pi/n
        local ax,az=math.cos(a)*3.7,math.sin(a)*2.6
        local bx,bz=math.cos(b)*3.7,math.sin(b)*2.6
        G.triangle(m,{0,0,.13},{ax,az,.13},{bx,bz,.13},{.18,.44,.43},{0,1,0})
        G.cylinder(m,ax,az,.01,.27,.23+(i%3)*.025,stone,5)
    end
    -- Reeds and lily pads break up the outline without adding texture assets.
    for i=1,7 do
        local x,z=-2.9+i*.14,-1.7+i%2*.18
        box(m,x,z,.16,.035,.035,.42+i%3*.12,{.38,.43,.19})
        box(m,x,z,.55+i%3*.12,.065,.065,.13,{.34,.25,.13})
    end
    for _,p in ipairs({{1.7,.6},{2.1,.3},{1.8,.1},{-1,-1}}) do
        G.cylinder(m,p[1],p[2],.14,.24,.012,{.32,.48,.24},7)
    end
    for _,p in ipairs({{-.8,.7,.9},{.7,-.9,.55},{-1.7,.1,.5}}) do
        box(m,p[1],p[2],.141,p[3],.035,.008,{.47,.65,.59})
    end
end
function Geo.rangerHut(m)
    box(m,0,0,.01,3.6,2.8,.18,wood)
    box(m,0,-1.3,.19,3.6,.16,2.35,planks)
    for _,x in ipairs({-1.7,1.7}) do
        box(m,x,0,.19,.16,2.8,2.35,planks)
        box(m,x,1.3,.19,.15,.15,2.35,wood)
    end
    box(m,0,1.3,.19,3.5,.16,.8,planks)
    box(m,0,1.4,.99,3.7,.48,.12,wood)
    roof(m,4.15,3.5,2.55,.8)
    box(m,0,1.79,2.15,3.25,.10,.39,green)
    letters(m,'RANGER INFO',0,1.85,2.35,2.95,.27)
    -- Noticeboard/map behind the counter, readable as an information point.
    box(m,0,-1.19,1.22,2.25,.04,.97,green)
    box(m,-.45,-1.16,1.32,.95,.035,.72,cream)
    box(m,.56,-1.15,1.65,.62,.035,.32,cream)
    box(m,.56,-1.15,1.3,.62,.035,.22,cream)
    for i=0,4 do box(m,-.75+i*.14,-1.13,1.4+i%3*.13,.12,.02,.07,green) end
end
function Geo.outhouse(m)
    box(m,0,0,.01,1.8,1.8,2.22,planks)
    box(m,0,.91,.06,.94,.045,1.9,green)
    box(m,.31,.95,.92,.055,.04,.12,cream)
    for i=0,7 do
        box(m,-.8+i*.23,0,.1,.025,1.82,2.1,wood)
    end
    roof(m,2.15,2.2,2.25,.48)
    box(m,0,1.12,2.14,1.64,.07,.24,green)
    letters(m,'RESTROOM',0,1.17,2.26,1.5,.17)
    -- A simple person symbol on the door.
    box(m,0,.95,1.54,.13,.035,.13,cream)
    box(m,0,.95,1.3,.23,.035,.19,cream)
    for _,x in ipairs({-.065,.065}) do box(m,x,.95,1.1,.065,.035,.21,cream) end
end
function Geo.parkSign(m,label)
    box(m,0,0,0,.15,.15,1.95,wood)
    box(m,0,.04,1.3,1.6,.14,.66,green)
    letters(m,label,0,.12,1.73,1.35,.29)
    letters(m,'WELCOME',0,.12,1.43,1.4,.12)
end
return Geo
