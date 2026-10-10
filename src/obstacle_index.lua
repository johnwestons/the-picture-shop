-- Spatial broad phase for one immutable collision snapshot. Rebuild after the
-- world changes; never reuse cells for moved pallets, vehicles, or employees.
local Index = {}
local CELL = 64
local EMPTY = {}

function Index.new(obstacles)
    if obstacles and obstacles.cells then return obstacles end
    -- Small scenes are cheaper to scan directly.
    if not obstacles or #obstacles < 16 then return obstacles end
    local result = {cells={}}
    for _, obstacle in ipairs(obstacles) do
        local w,h=obstacle.halfWidth or obstacle.radius,obstacle.halfHeight or obstacle.radius
        for x=math.floor((obstacle.x-w)/CELL),math.floor((obstacle.x+w)/CELL) do
            local column=result.cells[x] or {};result.cells[x]=column
            for y=math.floor((obstacle.y-h)/CELL),math.floor((obstacle.y+h)/CELL) do
                local cell=column[y] or {};column[y]=cell
                cell[#cell+1]=obstacle
            end
        end
    end
    return result
end

function Index.point(obstacles,x,y)
    if not obstacles then return EMPTY end
    if not obstacles.cells then return obstacles end
    local column=obstacles.cells[math.floor(x/CELL)]
    return column and column[math.floor(y/CELL)] or EMPTY
end

function Index.segment(obstacles,x,y,nx,ny)
    if not obstacles then return EMPTY end
    if not obstacles.cells then return obstacles end
    local left,right=math.floor(math.min(x,nx)/CELL),math.floor(math.max(x,nx)/CELL)
    local top,bottom=math.floor(math.min(y,ny)/CELL),math.floor(math.max(y,ny)/CELL)
    if left==right and top==bottom then return Index.point(obstacles,x,y) end
    local result,seen={},{}
    for cx=left,right do
        local column=obstacles.cells[cx]
        if column then
            for cy=top,bottom do
                for _,obstacle in ipairs(column[cy] or EMPTY) do
                    if not seen[obstacle] then seen[obstacle]=true;result[#result+1]=obstacle end
                end
            end
        end
    end
    return result
end

return Index
