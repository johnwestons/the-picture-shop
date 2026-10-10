local Ball=require("src.basketball")
local Path=require("src.basketball_trajectory")
local Art=require("src.basketball_art")
local Colorways=require("src.rabbit_colorways")
local Renderer={}
local images,quads={},{}
local function atlas(direction)
    local authored=Art.mirrors[direction] or direction
    if not images[authored] then
        local path="assets/generated/basketball-actions-v2/"..authored..".png"
        if not love.filesystem.getInfo(path) then return nil end
        images[authored]=love.graphics.newImage(path)
        images[authored]:setFilter("linear","linear")
    end
    return images[authored],authored
end
local function quad(frame)
    if not quads[frame] then
        quads[frame]=love.graphics.newQuad((frame-1)%4*Art.CELL,math.floor((frame-1)/4)*Art.CELL,
            Art.CELL,Art.CELL,Art.CELL*4,Art.CELL*6)
    end
    return quads[frame]
end
function Renderer.draw(player,state)
    if player.character~="rabbit-worker" then return false end
    local id=tonumber(player.id) or 1
    local held=Ball.heldBy(state,id)
    local shot
    for _,record in ipairs(Ball.renderRecords(state)) do
        if record.shooterId==id and (record.shotPhase=="charge"
            or (record.releaseElapsed or 1)<Path.RECOVERY) then shot=record;break end
    end
    if not held and not shot then return false end
    local direction=Art.direction(player)
    local image=atlas(direction)
    if not image then return false end
    local frame,jump=1,0
    if shot then
        if shot.shotPhase=="charge" then
            frame=8+Art.chargeFrame(shot.shotElapsed or 0)
            jump=Path.jumpHeight(shot.shotElapsed or 0)
        else
            local progress=math.min(1,(shot.releaseElapsed or 0)/Path.RECOVERY)
            frame=21+math.min(3,math.floor(progress*4))
            jump=Path.jumpHeight(shot.releaseTime or Path.APEX)*(1-progress)
        end
    elseif player.moving then frame=5+math.floor((player.animationDistance or 0)/20)%4
    else frame=1+math.floor((player.idleClock or 0)*6)%4 end
    love.graphics.push("all")
    love.graphics.setColor(.03,.04,.05,.22)
    love.graphics.ellipse("fill",player.x,player.y+1,13,5)
    if held then
        local x,y=Art.ballPoint(player,frame,jump)
        if x then require("src.shop_room_renderer").drawBall(x,y) end
    end
    love.graphics.setColor(1,1,1,1)
    local scale=Art.scale()
    Colorways.draw(image,quad(frame),player.x,player.y-jump,0,
        Art.mirrors[direction] and -scale or scale,scale,Art.ANCHOR_X,Art.ANCHOR_Y,
        0,0,player.furColorway,player.overallsColorway)
    love.graphics.pop()
    return true
end
function Renderer.drawArc(state,player)
    for _,record in ipairs(Ball.renderRecords(state)) do
        if record.shotPhase=="charge" and record.shooterId==(tonumber(player.id) or 1) then
            local x,y=Art.releasePoint(player,record.shotElapsed or 0)
            local path=Path.path(x,y,record.aimX,record.arcHeight,record.shotElapsed or 0)
            love.graphics.push("all")
            love.graphics.setColor(1,.86,.15,.75)
            love.graphics.setLineWidth(2)
            local previousX,previousY=x,y
            local blocked=false
            for i=1,48 do
                local nx,ny=Path.point(path,path.duration*i/48)
                local hx,hy=Path.sweepFlight(previousX,previousY,nx,ny)
                if hx then
                    love.graphics.circle("line",hx,hy,9)
                    blocked=true;break
                end
                love.graphics.line(previousX,previousY,nx,ny)
                if i%4==0 then love.graphics.circle("fill",nx,ny,2.5) end
                previousX,previousY=nx,ny
            end
            if not blocked then love.graphics.circle("line",path.endX,path.endY,9) end
            love.graphics.pop()
            return true
        end
    end
end
function Renderer.clear()
    for key,image in pairs(images) do if image.release then image:release() end;images[key]=nil end
    quads={}
end
return Renderer
