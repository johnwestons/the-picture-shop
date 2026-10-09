-- Legacy bay IDs now identify separate rooms A and B; source contacts are
-- registered to the actual platform pixels in each full-floor background.
local Layout={VERSION=3,BAY_IDS={"front_left","front_right"}}
local function room(id)
    return {id=id,rackId=id.."-rack",polygon={{x=8,y=180},{x=952,y=285},{x=952,y=670},{x=8,y=670}},
        walkPolygon={{x=8,y=285},{x=952,y=285},{x=952,y=670},{x=8,y=670}},seam={{x=8,y=285},{x=952,y=285}},
        workPoint={x=642,y=314},approach={x=668,y=310},
        rackApproachPoint={x=530,y=285},restPoint={x=775,y=260},
        rackStart={x=222,y=118},rackEnd={x=881,y=208},upperDeckOffset=99*678/1024,rackHeight=120,
        rackGroundPosts={{x=221,y=175},{x=330,y=195},{x=439,y=215},{x=548,y=235},{x=657,y=255},{x=766,y=275}}}
end
function Layout.bay(id)
    if id=="warehouse" then
        local b=room(id);b.rackApproachPoint={x=374,y=218};b.upperDeckOffset=85*678/1024;return b
    end
    if id=="front_left" or id=="front_right" then return room(id) end
end
function Layout.forkliftSpawn() return {x=460,y=515,direction="northwest"} end
function Layout.containsPolygon(polygon,x,y)
    local inside=false
    if type(x)~="number" or type(y)~="number" then return false end
    local previous=#(polygon or {})
    for i,p in ipairs(polygon or {}) do
        local q=polygon[previous]
        if (p.y>y)~=(q.y>y) and x<(q.x-p.x)*(y-p.y)/(q.y-p.y)+p.x then inside=not inside end
        previous=i
    end
    return inside
end
function Layout.bayState(state,id) return state and state.warehouse and state.warehouse.bays[id] end
function Layout.containsUnlocked() return false end
function Layout.isReserved() return false end
local function idForRack(id) return id and id:gsub("%-rack$","") end
function Layout.rackApproach(id) local b=Layout.bay(idForRack(id));return b and b.rackApproachPoint end
function Layout.rackPoint(id,row,column)
    local bayId=idForRack(id)
    if not Layout.bay(bayId) or (row~=1 and row~=2) or type(column)~="number"
        or column<1 or column>5 or column~=math.floor(column) then return nil end
    local x,y,groundY
    if bayId=="warehouse" then
        x=(432+(column-1)*104)*960/1536
        y=(162+(column-1)*26-(row-1)*85)*678/1024
        groundY=(268+(column-1)*25)*678/1024
    else
        -- Five of the six visible bays are registered as stock slots.
        x=(431+(column-1)*174)*960/1536
        y=(188+(column-1)*29-(row-1)*99)*678/1024
        groundY=(257+(column-1)*30)*678/1024
    end
    return {x=x,y=y,groundY=groundY,row=row,column=column}
end
function Layout.obstacles() return require("src.warehouse_registration").obstacles("warehouse") end
function Layout.project(state,id)
    local bay=Layout.bayState(state,id)
    if bay then for _,p in ipairs(state.warehouse.projects or {}) do if p.id==bay.projectId then return p end end end
end
return Layout
