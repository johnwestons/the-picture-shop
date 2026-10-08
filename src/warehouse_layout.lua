-- Additive expansion geometry in the existing 960x678 world. No existing
-- character, machine or core-floor coordinates are rescaled by this layout.
if require("src.config").warehouse.roomScenes then return require("src.warehouse_room_layout") end
local Layout = { VERSION = 1, BAY_IDS = { "front_left", "front_right" } }

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local left = {
    id = "front_left", rackId = "front_left-rack",
    polygon = { {x=8,y=386}, {x=379,y=647}, {x=8,y=647} },
    -- Overlap only the old raised concrete rim so the two masks join cleanly.
    walkPolygon = { {x=8,y=376}, {x=389,y=647}, {x=8,y=647} },
    seam = { {x=8,y=386}, {x=379,y=647} },
    workPoint = {x=260,y=505}, approach = {x=315,y=515},
    rackApproachPoint = {x=220,y=495},
    -- Registered against the authored world-space 5×2 rack sprite. The
    -- lower deck contact line follows the actual front beam, and the upper
    -- shelf's displayed deck height matches the source art.
    -- The rack is inset parallel to the bay's diagonal seam. Its rear row
    -- sits just inside that seam and its front row remains in walkable bay
    -- space; this keeps all shelf supports on the expansion footprint.
    rackStart = {x=25,y=427}, rackEnd = {x=297,y=618.35},
    rackHeight = 112, upperDeckOffset = 70,
    -- Floor-contact centres of the six visible base plates in the selected
    -- rack art. The shelf contact line above is raised off this ground line.
    rackGroundPosts = {
        {x=25,y=442}, {x=78.9524,y=480.1708},
        {x=133.4725,y=517.3509}, {x=188.3614,y=556.403},
        {x=242.0584,y=595.1803}, {x=297,y=633.35},
    },
    restPoint = {x=95,y=639},
}
local right = copy(left)
right.id, right.rackId = "front_right", "front_right-rack"
for _, key in ipairs({"polygon", "walkPolygon", "seam"}) do
    for _, point in ipairs(right[key]) do point.x = 960 - point.x end
end
for _, key in ipairs({"workPoint", "approach", "rackApproachPoint", "rackStart", "rackEnd", "restPoint"}) do
    right[key].x = 960 - right[key].x
end
for _,point in ipairs(right.rackGroundPosts) do point.x=960-point.x end
local bays = { front_left=left, front_right=right }

function Layout.bay(id) return copy(bays[id]) end
function Layout.forkliftSpawn() return {x=460,y=515,direction="northwest"} end
function Layout.containsPolygon(polygon, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    local positive, negative = false, false
    for index, point in ipairs(polygon or {}) do
        local nextPoint = polygon[index % #polygon + 1]
        local cross = (nextPoint.x-point.x)*(y-point.y)-(nextPoint.y-point.y)*(x-point.x)
        if cross > 0.0001 then positive=true elseif cross < -0.0001 then negative=true end
        if positive and negative then return false end
    end
    return type(polygon) == "table" and #polygon >= 3
end
function Layout.bayState(state, id)
    local warehouse = type(state) == "table" and state.warehouse
    return warehouse and warehouse.bays and warehouse.bays[id]
end
function Layout.containsUnlocked(state, x, y)
    for _, id in ipairs(Layout.BAY_IDS) do
        local status = Layout.bayState(state,id)
        if status and status.status == "complete"
            and Layout.containsPolygon(bays[id].walkPolygon,x,y) then return true,id end
    end
    return false
end
function Layout.isReserved(state, x, y)
    for _, id in ipairs(Layout.BAY_IDS) do
        local status = Layout.bayState(state,id)
        if (not status or status.status ~= "complete")
            and Layout.containsPolygon(bays[id].polygon,x,y) then return true,id end
    end
    return false
end
local function forRack(id)
    if bays[id] then return bays[id] end
    for _, bay in pairs(bays) do if bay.rackId == id then return bay end end
end
function Layout.rackApproach(id)
    local bay = forRack(id)
    return bay and copy(bay.rackApproachPoint)
end
function Layout.rackPoint(id,row,column)
    local bay = forRack(id)
    if not bay or (row ~= 1 and row ~= 2) or type(column) ~= "number"
        or column < 1 or column > 5 or column ~= math.floor(column) then return nil end
    local fraction = (column-0.5)/5
    local x = bay.rackStart.x+(bay.rackEnd.x-bay.rackStart.x)*fraction
    local groundY = bay.rackStart.y+(bay.rackEnd.y-bay.rackStart.y)*fraction
    return {x=x,y=groundY-7-(row-1)*bay.upperDeckOffset,groundY=groundY,row=row,column=column}
end
function Layout.obstacles(state)
    local result = {}
    for _, id in ipairs(Layout.BAY_IDS) do
        local status = Layout.bayState(state,id)
        if status and status.status == "complete" and status.optionId == "storage" then
            local bay=bays[id]
            -- Block the visible floor feet, where a worker or vehicle can
            -- collide with a post, rather than the raised lower shelf beam.
            for _,point in ipairs(bay.rackGroundPosts) do
                result[#result+1]={x=point.x,y=point.y,halfWidth=2,halfHeight=3,
                    kind="pallet_rack_post",rackId=bay.rackId}
            end
        elseif status and status.status=="complete" and status.optionId=="breakroom" then
            local mirror=id=="front_right"
            local function x(value) return mirror and 960-value or value end
            result[#result+1]={x=x(96),y=613,halfWidth=49,halfHeight=16,kind="breakroom_table",bayId=id}
            result[#result+1]={x=x(85),y=515,halfWidth=66,halfHeight=23,kind="breakroom_kitchenette",bayId=id}
            result[#result+1]={x=x(203),y=618,halfWidth=25,halfHeight=12,kind="breakroom_vending",bayId=id}
        end
    end
    return result
end
function Layout.project(state,id)
    local status=Layout.bayState(state,id)
    if not status then return nil end
    for _, project in ipairs(state.warehouse.projects or {}) do
        if project.id==status.projectId then return project end
    end
end

return Layout
