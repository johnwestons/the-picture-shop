-- Sectional steel door in the registered wall plane. The existing warehouse
-- artwork supplies the worn metal material; geometry, ribs and hardware move
-- independently. No generated images, texture uploads or animation frames.
local Shutter={SECTIONS=14}
local cache=setmetatable({}, {__mode='k'})
local function clamp(n)return math.max(0,math.min(1,tonumber(n) or 0))end
function Shutter.point(a,u,v)
    local leftX=a[1].x+(a[4].x-a[1].x)*v
    local leftY=a[1].y+(a[4].y-a[1].y)*v
    local rightX=a[2].x+(a[3].x-a[2].x)*v
    local rightY=a[2].y+(a[3].y-a[2].y)*v
    return leftX+(rightX-leftX)*u,leftY+(rightY-leftY)*u
end
function Shutter.opening(a,progress)
    local top=1-clamp(progress)
    local points={}
    for _,uv in ipairs({{0,top},{1,top},{1,1},{0,1}})do
        local x,y=Shutter.point(a,uv[1],uv[2]);points[#points+1]=x;points[#points+1]=y
    end
    return points
end
local function quad(vertices,a,u0,v0,u1,v1,color,sourceV0,sourceV1)
    local positions={{u0,v0},{u1,v0},{u1,v1},{u0,v1}}
    local source={sourceV0 or v0,sourceV0 or v0,sourceV1 or v1,sourceV1 or v1}
    for _,index in ipairs({1,2,3,1,3,4})do
        local uv=positions[index];local x,y=Shutter.point(a,uv[1],uv[2])
        local sx,sy=Shutter.point(a,uv[1],source[index])
        vertices[#vertices+1]={x,y,sx/960,sy/678,color[1],color[2],color[3],color[4] or 1}
    end
end
local function polygon(a,u0,v0,u1,v1)
    local points={}
    for _,uv in ipairs({{u0,v0},{u1,v0},{u1,v1},{u0,v1}})do
        local x,y=Shutter.point(a,uv[1],uv[2]);points[#points+1]=x;points[#points+1]=y
    end
    return points
end
local function line(g,a,u0,v0,u1,v1,color,width)
    local x,y=Shutter.point(a,u0,v0);local xx,yy=Shutter.point(a,u1,v1)
    g.setColor(unpack(color));g.setLineWidth(width or 1);g.line(x,y,xx,yy)
end
function Shutter.draw(assets,door,a,source)
    local g=love.graphics;local progress=clamp(door and door.progress)
    local image=assets.get('warehouse')
    source=source or a
    local record=cache[a]
    if not record then record={};cache[a]=record end
    g.push('all');g.setShader();g.setColor(1,1,1,1)
    -- Shutter contents are clipped to the frame, so panels disappear into the
    -- header rather than dragging painted masonry or floor into the opening.
    local outline=polygon(a,0,0,1,1)
    g.stencil(function()g.polygon('fill',unpack(outline))end,'replace',1)
    g.setStencilTest('greater',0)
    if progress<1 then
        if record.progress~=progress or record.image~=image then
            local vertices={};local shift=progress
            for section=0,Shutter.SECTIONS-1 do
                local original0,original1=section/Shutter.SECTIONS,(section+1)/Shutter.SECTIONS
                local bottom=original1-shift
                if bottom>0 then
                    local top=math.max(0,original0-shift)
                    local sampleTop=original0+math.max(0,shift-original0)
                    local height=bottom-top
                    local function panel(lo,hi,tint)
                        local before=#vertices
                        quad(vertices,a,.012,top+height*lo,.988,top+height*hi,tint)
                        -- Sample the corresponding portion of the original
                        -- material, including the clipped top of a raised rib.
                        for index=before+1,#vertices do
                            local vertex=vertices[index]
                            local fraction=(index-before==1 or index-before==2 or index-before==4) and lo or hi
                            local u=(index-before==1 or index-before==4 or index-before==6) and .012 or .988
                            local sx,sy=Shutter.point(source,u,sampleTop+(original1-sampleTop)*fraction)
                            vertex[3],vertex[4]=sx/960,sy/678
                        end
                    end
                    panel(0,.12,{1.23,1.17,1.03,1})
                    panel(.12,.77,{.94,.96,.96,1})
                    panel(.77,.92,{.62,.68,.70,1})
                    panel(.92,1,{.24,.28,.29,1})
                end
            end
            if #vertices>0 then
                while #vertices<Shutter.SECTIONS*24 do vertices[#vertices+1]={0,0,0,0,0,0,0,0}end
                if record.mesh then record.mesh:setVertices(vertices)
                else record.mesh=g.newMesh(vertices,'triangles','dynamic')end
                record.mesh:setTexture(image)
            end
            record.progress,record.image=progress,image
        end
        if record.mesh and image then g.setColor(1,1,1,1);g.draw(record.mesh)end
        -- Repeated fasteners, hinge plates and scored steel are deterministic,
        -- so moving a panel does not make its wear pattern crawl or shimmer.
        for row=0,Shutter.SECTIONS-1 do
            local v=(row+.48)/Shutter.SECTIONS-progress
            if v>.012 and v<1 then
                for _,u in ipairs({.075,.925})do
                    local x,y=Shutter.point(a,u,v)
                    g.setColor(.08,.10,.11,1);g.circle('fill',x,y,.9)
                    g.setColor(.68,.66,.57,1);g.circle('fill',x-.25,y-.25,.4)
                end
                if row%3==1 then
                    for _,u in ipairs({.29,.71})do
                        g.setColor(.23,.25,.24,1);g.polygon('fill',unpack(polygon(a,u-.024,v-.017,u+.024,v+.017)))
                        line(g,a,u-.017,v-.013,u+.017,v-.013,{.62,.61,.53,1},.55)
                    end
                end
                local u=.15+(row*37%53)/100
                line(g,a,u,v+.012,math.min(.87,u+.12),v+.012,{.74,.70,.59,.30},.55)
            end
        end
        local seal=1-progress
        g.setColor(.025,.035,.035,1);g.polygon('fill',unpack(polygon(a,0,math.max(0,seal-.021),1,seal)))
        line(g,a,.02,seal-.025,.98,seal-.025,{.53,.48,.34,1},1)
        if seal>.16 then
            g.setColor(.10,.12,.12,1);g.polygon('fill',unpack(polygon(a,.43,seal-.075,.58,seal-.042)))
            line(g,a,.45,seal-.067,.56,seal-.067,{.64,.61,.50,1},1.25)
        end
    end
    g.setStencilTest()
    -- Stationary channels, inset shadows and mounting bolts stay attached to
    -- the masonry. The warm upper edge echoes the painted dock lamp.
    for _,u in ipairs({-.022,1.022})do
        line(g,a,u,-.005,u,1.025,{.055,.075,.08,1},4)
        line(g,a,u-.007,0,u-.007,1.01,{.35,.36,.32,1},1)
        for i=0,4 do
            local x,y=Shutter.point(a,u,.055+i*.225)
            g.setColor(.54,.53,.45,1);g.circle('fill',x,y,.85)
            g.setColor(.08,.10,.11,1);g.circle('fill',x+.2,y+.2,.35)
        end
    end
    g.setColor(.10,.12,.12,1);g.polygon('fill',unpack(polygon(a,-.045,-.105,1.045,-.012)))
    line(g,a,-.035,-.10,1.035,-.10,{.52,.49,.39,1},1.1)
    line(g,a,-.025,-.023,1.025,-.023,{.04,.05,.05,1},2)
    line(g,a,.02,-.086,.98,-.086,{.68,.59,.39,.7},.7)
    line(g,a,0,1.008,1,1.008,{.035,.04,.035,1},2)
    g.pop()
end
function Shutter.clear()
    for key,record in pairs(cache)do if record.mesh then record.mesh:release()end;cache[key]=nil end
end
return Shutter
