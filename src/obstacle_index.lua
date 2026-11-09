-- Spatial broad phase for one immutable collision snapshot. Rebuild after the
-- world changes; never reuse cells for moved pallets, vehicles, or employees.
local Index = {}
local CELL = 64
local EMPTY = {}

function Index.new(obstacles,scratch)
    if obstacles and obstacles.cells then return obstacles end
    -- Small scenes are cheaper to scan directly.
    if not obstacles or #obstacles < 16 then return obstacles end
    local cells,pool,poolCount
    if scratch then
        -- Navigation snapshots are consumed synchronously; recycle their cell
        -- lists only after the previous move has returned.
        cells=scratch.cells or {};pool=scratch.pool or {};poolCount=scratch.poolCount or 0
        for _,column in pairs(cells) do
            for y,entries in pairs(column) do
                for index=#entries,1,-1 do entries[index]=nil end
                poolCount=poolCount+1;pool[poolCount]=entries;column[y]=nil
            end
        end
        scratch.cells,scratch.pool,scratch.poolCount=cells,pool,poolCount
    else
        cells={}
    end
    local result = {cells=cells}
    for _, obstacle in ipairs(obstacles) do
        local w,h=obstacle.halfWidth or obstacle.radius,obstacle.halfHeight or obstacle.radius
        for x=math.floor((obstacle.x-w)/CELL),math.floor((obstacle.x+w)/CELL) do
            local column=result.cells[x] or {};result.cells[x]=column
            for y=math.floor((obstacle.y-h)/CELL),math.floor((obstacle.y+h)/CELL) do
                local cell=column[y]
                if not cell then
                    if scratch and scratch.poolCount>0 then
                        local count=scratch.poolCount
                        cell=scratch.pool[count];scratch.pool[count]=nil;scratch.poolCount=count-1
                    else
                        cell={}
                    end
                    column[y]=cell
                end
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

-- Reused scratch arrays may have unused tail entries; callers should use the
-- returned count as the valid prefix length.
function Index.segment(obstacles,x,y,nx,ny,scratch)
    if not obstacles then return EMPTY,0 end
    if not obstacles.cells then return obstacles,#obstacles end
    local left,right=math.floor(math.min(x,nx)/CELL),math.floor(math.max(x,nx)/CELL)
    local top,bottom=math.floor(math.min(y,ny)/CELL),math.floor(math.max(y,ny)/CELL)
    if left==right and top==bottom then
        local point=Index.point(obstacles,x,y)
        return point,#point
    end
    local result,seen,stamp
    if scratch then
        result,seen=scratch.items or {},scratch.seen or {}
        scratch.items,scratch.seen=result,seen
        scratch.generation=(scratch.generation or 0)+1
        if scratch.generation>=2147483647 then
            scratch.seen={};scratch.generation=1
        end
        stamp=scratch.generation
    else
        result,seen,stamp={},{},true
    end
    -- The second return value is the valid prefix length for a reused list;
    -- old tail entries can stay in the scratch array until the search ends.
    local count=0
    for cx=left,right do
        local column=obstacles.cells[cx]
        if column then
            for cy=top,bottom do
                for _,obstacle in ipairs(column[cy] or EMPTY) do
                    if seen[obstacle]~=stamp then
                        seen[obstacle]=stamp;count=count+1;result[count]=obstacle
                    end
                end
            end
        end
    end
    return result,count
end

return Index
