-- Five authored views and three intentional mirrors match the rabbit walk rig.
local Animation=require("src.character_animation")
local Ball=require("src.basketball")
local Renderer={}
local images,quads={},{}
local mirrors={west="east",northwest="northeast",southwest="southeast"}
local CELL=362
local function atlas(direction)
    local authored=mirrors[direction] or direction
    if not images[authored] then
        local path="assets/generated/breakroom-games-v1/basketball-actions-"..authored..".png"
        if not love.filesystem.getInfo(path) then return nil end
        images[authored]=love.graphics.newImage(path)
        images[authored]:setFilter("linear","linear")
    end
    return images[authored],authored
end
local function quad(direction,row,col)
    local key=direction..":"..row..":"..col
    if not quads[key] then
        quads[key]=love.graphics.newQuad((col-1)*CELL,(row-1)*CELL,CELL,CELL,
            CELL*4,CELL*3)
    end
    return quads[key]
end
function Renderer.draw(player,state)
    if player.character~="rabbit-worker" then return false end
    local id=tonumber(player.id) or 1
    local held=Ball.heldBy(state,id)
    local shot
    for _,record in ipairs(Ball.renderRecords(state)) do
        if record.shooterId==id then shot=record;break end
    end
    if not held and not shot then return false end
    local x=tonumber(player.intentX) or tonumber(player.velocityX) or 1
    local y=tonumber(player.intentY) or tonumber(player.velocityY) or 0
    local direction=Animation.authoredDirection(x,y)
    local image,authored=atlas(direction)
    if not image then return false end
    local row,col
    if shot then
        row=3
        if shot.shotPhase=="charge" then col=shot.shotElapsed<.17 and 1 or 2
        else col=shot.shotElapsed<.16 and 3 or 4 end
    elseif player.moving then
        row,col=2,math.floor((player.animationDistance or 0)/20)%4+1
    else
        row,col=1,math.floor((player.idleClock or 0)*5)%4+1
    end
    love.graphics.setColor(.03,.04,.05,.22)
    love.graphics.ellipse("fill",player.x,player.y+1,13,5)
    love.graphics.setColor(1,1,1,1)
    local scale=.23
    love.graphics.draw(image,quad(authored,row,col),player.x,player.y,0,
        mirrors[direction] and -scale or scale,scale,CELL/2,CELL-14)
    return true
end
function Renderer.clear()
    for key,image in pairs(images) do if image.release then image:release() end;images[key]=nil end
    quads={}
end
return Renderer
