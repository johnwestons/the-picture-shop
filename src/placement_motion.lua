local Motion = {}

-- Keep analog stick magnitude for slow positioning. Check short steps along
-- the route so a delayed frame cannot push equipment through an obstruction.
function Motion.move(item, dx, dy, dt, speed, canMove)
    local length = math.sqrt(dx*dx + dy*dy)
    if length == 0 or dt <= 0 then return false end
    local distance = speed * math.min(1,length) * dt
    local stepX,stepY = dx/length*distance,dy/length*distance
    local count = math.max(1,math.ceil(distance/4))
    local moved = false
    for _=1,count do
        local x,y = item.x+stepX/count,item.y+stepY/count
        if not canMove(x,y) then break end
        item.x,item.y,moved = x,y,true
    end
    return moved
end

return Motion
