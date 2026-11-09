-- Solid warehouse fixtures, measured against the original canvas. No facade imagery.
local G=require('src.warehouse_perspective_geometry')
local S={}
function S.build(texture)
    local vertices,solids={},{}
    local steel={.19,.25,.27}; local wall={.55,.51,.43}; local wood={.64,.42,.19}
    local function box(x,z,length,depth,bottom,height,color,angle,collide)
        angle=angle or 0
        local c,s=math.cos(angle),math.sin(angle)
        local points={}
        for _,h in ipairs({bottom,bottom+height}) do
            for _,p in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
                local u,v=p[1]*length/2,p[2]*depth/2
                points[#points+1]={x+c*u-s*v,z+s*u+c*v,h}
            end
        end
        for i,face in ipairs({{1,2,3,4},{5,8,7,6},{1,5,6,2},{2,6,7,3},{3,7,8,4},{4,8,5,1}}) do
            local shade=({.55,1,.78,.67,.88,.72})[i]
            for _,j in ipairs({1,2,3,1,3,4}) do
                local p=points[face[j]]
                vertices[#vertices+1]={p[1],p[2],p[3],0,0,color[1]*shade,color[2]*shade,color[3]*shade,1}
            end
        end
        if collide then solids[#solids+1]={x=x,z=z,l=length/2,d=depth/2,c=c,s=s} end
    end
    local function line(ax,ay,bx,by,depth,bottom,height,color,collide)
        local x,z=G.floorPoint(ax,ay);local xx,zz=G.floorPoint(bx,by)
        box((x+xx)/2,(z+zz)/2,math.sqrt((xx-x)^2+(zz-z)^2),depth,bottom,height,color,math.atan2(zz-z,xx-x),collide)
    end
    local function prop(sx,sy,l,d,b,h,col,angle,collide)
        local x,z=G.floorPoint(sx,sy);box(x,z,l,d,b,h,col,angle or -.42,collide)
    end
    local function brace(x,z,u0,h0,u1,h1,angle)
        local c,s=math.cos(angle),math.sin(angle)
        local du,dh=u1-u0,h1-h0;local len=math.sqrt(du*du+dh*dh)
        local pts={}
        for _,endPoint in ipairs({{u0,h0},{u1,h1}}) do
            for _,sign in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
                local u=endPoint[1]+sign[2]*dh/len*.025
                local h=endPoint[2]-sign[2]*du/len*.025
                pts[#pts+1]={x+c*u-s*sign[1]*.018,z+s*u+c*sign[1]*.018,h}
            end
        end
        for i,face in ipairs({{1,2,3,4},{5,8,7,6},{1,5,6,2},{2,6,7,3},{3,7,8,4},{4,8,5,1}}) do
            for _,k in ipairs({1,2,3,1,3,4}) do local p=pts[face[k]]
                vertices[#vertices+1]={p[1],p[2],p[3],0,0,.24,.29,.29,1}
            end
        end
    end
    -- Rear envelope has real door openings, with lintels above them.
    line(0,266,40,247,.18,0,4.7,wall,true)
    line(40,247,170,187,.18,3.1,1.6,wall)
    line(170,187,182,181,.18,0,4.7,wall,true)
    line(182,181,210,169,.18,2.5,2.2,wall)
    line(210,169,220,164,.18,0,4.7,wall,true)
    line(183,181,209,170,.12,0,2.45,{.19,.29,.27},true)
    prop(205,174,.09,.12,1,.10,{.80,.72,.44})
    line(220,164,594,250,.18,0,4.7,wall,true)
    line(594,250,625,231,.18,0,4.7,wall,true)
    line(625,231,674,201,.18,2.8,1.9,wall)
    line(674,201,684,180,.18,0,4.7,wall,true)
    line(684,180,705,186,.18,0,4.7,wall,true)
    line(705,186,739,196,.18,2.5,2.2,wall)
    line(739,196,960,221,.18,0,4.7,wall,true)
    -- Dock roller door: individual metal slats and guide rails.
    for h=.10,3.05,.17 do line(43,245,167,188,.09,h,.145,{.38,.41,.40},true) end
    for _,p in ipairs({{40,247},{170,187},{220,164},{594,250},{684,180},{960,221}}) do
        prop(p[1],p[2],.20,.22,0,4.7,steel,0,true)
    end
    line(0,266,220,164,.24,3.3,.22,steel)
    line(220,164,594,250,.24,3.3,.22,steel)
    line(684,180,960,221,.24,3.3,.22,steel)
    -- Rack: five bays, three separate decks, posts and orange crossbeams.
    local ax,az=G.floorPoint(242,188);local bx,bz=G.floorPoint(562,262)
    local length=math.sqrt((bx-ax)^2+(bz-az)^2);local angle=math.atan2(bz-az,bx-ax)
    local c,s=math.cos(angle),math.sin(angle)
    for i=0,5 do
        local x,z=ax+(bx-ax)*i/5,az+(bz-az)*i/5
        for _,offset in ipairs({-.39,.39}) do
            box(x-s*offset,z+c*offset,.09,.09,0,3.45,steel,angle,true)
        end
    end
    for i=0,4 do
        local x,z=ax+(bx-ax)*(i+.5)/5,az+(bz-az)*(i+.5)/5
        for _,h in ipairs({.25,1.55,2.85}) do
            box(x,z,length/5-.06,.83,h,.09,wood,angle)
            for _,offset in ipairs({-.43,.43}) do
                box(x-s*offset,z+c*offset,length/5,.06,h-.05,.12,{.87,.32,.06},angle)
            end
        end
    end
    -- Back-room extension: opening, concrete floor and three enclosing walls.
    line(625,231,590,180,.15,0,3.5,wall,true)
    line(674,201,639,150,.15,0,3.5,wall,true)
    line(590,180,639,150,.15,0,3.5,wall,true)
    line(605,205,654,175,1.8,-.04,.04,{.48,.47,.43})
    prop(618,177,1.1,.45,0,1.15,wood,0,true)
    -- Parking-lot pedestrian door, frame, glass and handle.
    line(705,186,739,196,.12,0,2.48,{.20,.29,.29},true)
    line(711,188,733,194,.14,1.05,1.15,{.36,.56,.60})
    prop(733,197,.08,.12,1,.10,{.80,.72,.44})
    -- Office partition, entry posts, and lounge furniture.
    line(828,219,837,201,.16,0,3.5,wall,true)
    local function sofa(sx,sy,width)
        local x,z=G.floorPoint(sx,sy);local a=-.42;local c,s=math.cos(a),math.sin(a)
        local function part(u,v,l,d,b,h,color)
            box(x+c*u-s*v,z+s*u+c*v,l,d,b,h,color,a)
        end
        box(x,z,width,.72,.12,.23,{.32,.105,.035},a,true)
        part(0,-.30,width,.17,.35,.65,{.56,.18,.045})
        for _,u in ipairs({-width/2+.10,width/2-.10}) do
            part(u,0,.20,.75,.34,.32,{.62,.22,.065})
            for _,v in ipairs({-.25,.25}) do part(u,v,.07,.07,0,.15,wood) end
        end
        local count=width>1 and 3 or 1
        for i=1,count do
            local u=(i-(count+1)/2)*(width-.44)/count
            part(u,.04,(width-.46)/count-.025,.50,.35,.17,{.71,.28,.09})
            part(u,-.19,(width-.46)/count-.025,.12,.54,.36,{.66,.24,.065})
        end
    end
    sofa(773,222,1.8);sofa(811,245,.78)
    prop(922,225,1.25,.65,.80,.10,wood,nil,true)
    for _,x in ipairs({905,937}) do prop(x,225,.12,.50,0,.80,steel) end
    prop(913,214,.50,.09,.98,.38,{.07,.10,.12})
    prop(914,216,.40,.04,1.02,.28,{.23,.55,.76})
    prop(899,247,.45,.45,.4,.10,steel,nil,true)
    prop(899,254,.45,.10,.50,.50,steel)
    prop(862,211,.46,.50,0,1.1,{.43,.43,.37},nil,true)
    for h=.22,1,.25 do prop(862,219,.35,.03,h,.02,{.70,.69,.62}) end
    -- Picture frame, vent, notice board, clock and wall lamps are separate solids.
    prop(774,204,.92,.08,1.40,.65,wood)
    prop(774,206,.79,.06,1.46,.52,{.29,.47,.51})
    prop(871,235,.70,.08,2.7,.40,steel)
    for h=2.75,3.05,.06 do prop(871,237,.60,.04,h,.018,{.06,.08,.09}) end
    prop(923,250,.55,.08,1.7,.42,wood)
    for _,p in ipairs({{30,253},{193,180},{700,185},{934,254}}) do
        prop(p[1],p[2],.11,.18,3.4,.3,steel)
        prop(p[1],p[2]+5,.29,.25,3.25,.12,{.94,.77,.39})
    end
    -- Blockwork mortar, sill courses and steel column base plates.
    for h=.35,4.5,.36 do
        line(223,168,590,252,.018,h,.012,{.42,.40,.35})
        line(742,199,956,224,.018,h,.012,{.42,.40,.35})
    end
    for _,p in ipairs({{40,247},{170,187},{220,164},{594,250},{684,180},{960,221}}) do
        prop(p[1],p[2],.36,.36,0,.055,{.28,.29,.26},0)
        for _,dx in ipairs({-.12,.12}) do
            local x,z=G.floorPoint(p[1],p[2]);box(x+dx,z+.13,.035,.035,.055,.025,{.65,.65,.56})
        end
    end
    -- Rack feet, bolt heads, deck planks, labels and rear cross bracing.
    for i=0,5 do
        local x,z=ax+(bx-ax)*i/5,az+(bz-az)*i/5
        for _,offset in ipairs({-.39,.39}) do
            box(x-s*offset,z+c*offset,.22,.20,0,.035,steel,angle)
            for h=.30,3.1,.20 do box(x-s*(offset+.055),z+c*(offset+.055),.027,.025,h,.027,{.57,.61,.59},angle) end
        end
    end
    for i=0,4 do
        local x,z=ax+(bx-ax)*(i+.5)/5,az+(bz-az)*(i+.5)/5
        for _,h in ipairs({.25,1.55,2.85}) do
            for plank=0,6 do
                local u=(plank/6-.5)*(length/5-.09)
                box(x+c*u,z+s*u,.012,.80,h+.091,.008,{.38,.25,.12},angle)
            end
            box(x-s*.466,z+c*.466,.16,.012,h-.02,.06,{.92,.88,.67},angle)
        end
        brace(x+s*.39,z-c*.39,-length/10,.3,length/10,2.85,angle)
        brace(x+s*.39,z-c*.39,length/10,.3,-length/10,2.85,angle)
    end
    -- Desk keyboard, monitor stand, drawers, chair pedestal and feet.
    prop(913,216,.09,.12,.89,.13,steel)
    prop(921,235,.46,.18,.91,.025,{.15,.18,.19})
    for key=0,7 do prop(914+key*2,235,.015,.13,.937,.005,{.55,.57,.52}) end
    prop(899,247,.08,.08,.08,.33,steel)
    prop(899,247,.65,.07,.06,.055,steel)
    prop(899,247,.07,.65,.06,.055,steel)
    for h=.16,.68,.23 do prop(936,224,.30,.48,h,.19,{.49,.31,.13}) end
    -- Potted plants with stalks and layered leaves.
    for _,p in ipairs({{861,211,1.1},{942,225,.9}}) do
        prop(p[1],p[2],.20,.20,p[3],.21,{.48,.27,.13})
        prop(p[1],p[2],.24,.24,p[3]+.18,.045,{.61,.37,.20})
        prop(p[1],p[2],.025,.025,p[3]+.2,.35,{.25,.34,.12})
        for leaf=1,5 do prop(p[1],p[2],.30,.075,p[3]+.23+leaf*.047,.055,{.25+leaf*.015,.39+leaf*.018,.10},leaf*1.7) end
    end
    -- Door jambs, threshold plates and roller housing.
    for _,p in ipairs({{182,181},{210,169},{705,186},{739,196},{625,231},{674,201}}) do
        prop(p[1],p[2],.09,.18,0,2.65,steel)
    end
    line(705,186,739,196,.25,.006,.025,{.57,.57,.49})
    line(40,247,170,187,.34,3.1,.30,steel)
    -- Electrical cabinets, conduit and dock safety bollards.
    for _,p in ipairs({{25,254},{217,176}}) do
        prop(p[1],p[2],.23,.13,1.1,.39,{.37,.39,.35})
        prop(p[1],p[2],.025,.025,1.49,1.75,steel)
        prop(p[1],p[2]+3,.04,.02,1.28,.06,{.86,.44,.10})
    end
    for _,p in ipairs({{46,260},{178,198}}) do
        prop(p[1],p[2],.17,.17,0,.71,{.96,.66,.06},0,true)
        prop(p[1],p[2],.25,.25,0,.045,steel,0)
    end
    -- Continuous extension floor, including the doorway threshold.
    local corners={{625,235},{674,205},{639,150},{590,180}}
    for _,i in ipairs({1,2,3,1,3,4}) do
        local x,z=G.floorPoint(corners[i][1],corners[i][2])
        vertices[#vertices+1]={x,z,.002,0,0,.48,.47,.43,1}
    end
    local m=love.graphics.newMesh({{'VertexPosition','float',2},{'WorldHeight','float',1},{'VertexTexCoord','float',2},{'VertexColor','float',4}},vertices,'triangles','static')
    m:setTexture(texture)
    return {mesh=m,solids=solids}
end
function S.insideExtension(x,z)
    local sx,sy=G.sourcePoint(x,z,0)
    local p={{625,235},{674,205},{639,150},{590,180}}
    local sign
    for i=1,4 do
        local a,b=p[i],p[i%4+1]
        local cross=(b[1]-a[1])*(sy-a[2])-(b[2]-a[2])*(sx-a[1])
        if sign and cross*sign<0 then return false end
        if cross~=0 then sign=cross end
    end
    return true
end
function S.blocked(scene,x,z)
    for _,b in ipairs(scene.solids) do
        local dx,dz=x-b.x,z-b.z
        if math.abs(dx*b.c+dz*b.s)<b.l+.18 and math.abs(-dx*b.s+dz*b.c)<b.d+.18 then return true end
    end
    return false
end
return S
