-- Image-backed sprites for the fueling interface. Each asset is a four-frame
-- 2x2 atlas with alpha so the artwork animates cleanly over the station panel.
local Sprite={}
local pumpImage,dropImage,pumpFrames,dropFrames

local function atlas(path)
    local image=love.graphics.newImage(path)
    image:setFilter('linear','linear')
    local width,height=image:getDimensions()
    local cellWidth,cellHeight=math.floor(width/2),math.floor(height/2)
    local frames={}
    for index=0,3 do
        frames[index+1]=love.graphics.newQuad(index%2*cellWidth,
            math.floor(index/2)*cellHeight,cellWidth,cellHeight,width,height)
    end
    return image,frames,cellWidth,cellHeight
end

local function load()
    if pumpImage then return end
    pumpImage,pumpFrames=atlas('assets/commute/ui/gas-pump-fuel-loop-v1.png')
    dropImage,dropFrames=atlas('assets/commute/ui/fuel-drop-loop-v1.png')
end

function Sprite.draw(g,x,y,w,h,fuel,time,filling)
    load()
    time=time or 0
    local frame
    if filling then frame=({3,4})[math.floor(time*7)%2+1]
    else frame=math.floor(time*2.5)%3+1 end
    local cellWidth,cellHeight=pumpImage:getDimensions()
    cellWidth,cellHeight=cellWidth/2,cellHeight/2
    g.setColor(1,1,1,1)
    g.draw(pumpImage,pumpFrames[frame],x,y,0,w/cellWidth,h/cellHeight)
    if filling then
        local dropFrame=math.floor(time*8)%4+1
        local dropWidth,dropHeight=dropImage:getDimensions()
        dropWidth,dropHeight=dropWidth/2,dropHeight/2
        local size=math.min(w,h)*.17
        g.draw(dropImage,dropFrames[dropFrame],x+w*.69,y+h*.62,0,
            size/dropWidth,size/dropHeight)
    end
end

return Sprite
