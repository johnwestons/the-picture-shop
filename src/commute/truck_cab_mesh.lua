-- Cross-sections of the cab from its roof lip down to the bumper. The side
-- and front artwork meet at the same vertices, including the windshield rake.
local Cab={}
local sections={
    -- side top Y, leading X, half width (metres), front art Y, left/right X
    {1,68,.82,58,90,331},
    {9,83,.87,67,72,349},
    {27,96,.92,94,60,361},
    {100,119,.98,217,49,373},
    {152,127,1,283,45,377},
    {212,127,1,390,36,387},
}
local format={{'VertexPosition','float',3},{'VertexTexCoord','float',2}}

function Cab.new(image)
    local iw,ih=image:getDimensions()
    local function vertex(sideX,sideY,width,u,v)
        return {1.47+1.29*sideX/128,width,2.5*(270-sideY)/270,u/iw,v/ih}
    end
    local function mesh(side)
        local vertices={}
        local function quad(a,b,c,d)
            for _,p in ipairs({a,b,c,a,c,d}) do vertices[#vertices+1]=p end
        end
        local function sideVertex(row,x)
            -- Keep the top seam on opaque cab paint and the tires at their original UV.
            return vertex(x,row[1],row[3]*side,447+x*.985,548+row[1]*258/270)
        end
        local function frontVertex(row,edge)
            return vertex(row[2],row[1],row[3]*edge,860+(edge==1 and row[5] or row[6]),536+row[4])
        end
        -- The head-on tread and axle sit underneath the cab, behind the bumper.
        local function under(y,edge,v)
            return vertex(75,y,.94*edge,860+(edge==1 and 39 or 383),536+v)
        end
        quad(under(209,1,391),under(209,-1,391),under(270,-1,477),under(270,1,477))
        local last=sections[#sections]
        local bottom={270,127,1}
        quad(sideVertex(last,0),sideVertex(last,127),sideVertex(bottom,127),sideVertex(bottom,0))
        for i=1,#sections-1 do
            local a,b=sections[i],sections[i+1]
            quad(sideVertex(a,0),sideVertex(a,a[2]),sideVertex(b,b[2]),sideVertex(b,0))
        end
        local sideCount=#vertices
        for i=1,#sections-1 do
            local a,b=sections[i],sections[i+1]
            quad(frontVertex(a,1),frontVertex(a,-1),frontVertex(b,-1),frontVertex(b,1))
        end
        -- The top-down source also shows glass. Only sample the painted roof.
        local top=sections[1]
        local function roof(x,edge,u)
            return vertex(x,top[1],edge*top[3],u,edge==1 and 478 or 16)
        end
        quad(roof(0,-1,1554),roof(top[2],-1,1811),roof(top[2],1,1811),roof(0,1,1554))
        local result=love.graphics.newMesh(format,vertices,'triangles','static')
        result:setTexture(image)
        return result,sideCount
    end
    local right,n=mesh(1)
    local left=mesh(-1)
    return {right=right,left=left,sideCount=n}
end

function Cab.draw(cab,transform,x,y,horizontal,depth,vertical,s,c)
    local mesh=s>=0 and cab.right or cab.left
    transform:setMatrix('row',
        horizontal*s,horizontal*c,0,x, -depth*c,depth*s,-vertical,y,
        0,0,0,0, 0,0,0,1)
    if c<0 then
        mesh:setDrawRange()
        love.graphics.draw(mesh,transform)
    else
        -- The front fascia is hidden when seen from behind.
        mesh:setDrawRange(1,cab.sideCount)
        love.graphics.draw(mesh,transform)
        mesh:setDrawRange(mesh:getVertexCount()-5,mesh:getVertexCount())
        love.graphics.draw(mesh,transform)
    end
end

return Cab
