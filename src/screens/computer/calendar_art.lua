local Sponsors=require("src.calendar_sponsors")
local Art={}
local cache={}

function Art.image(month)
    local sponsor=Sponsors[month] or Sponsors[1]
    if cache[month]~=nil then return cache[month] or nil end
    local okay,image=pcall(love.graphics.newImage,
        "assets/generated/critternet-calendar-v1/"..sponsor.image)
    if not okay then cache[month]=false;return nil end
    image:setFilter("linear","linear")
    cache[month]=image
    return image
end

function Art.draw(month,rect)
    local image=Art.image(month)
    if not image then return false end
    local width,height=image:getDimensions()
    local scale=math.max(rect.width/width,rect.height/height)
    local drawWidth,drawHeight=width*scale,height*scale
    local x=rect.x+(rect.width-drawWidth)*.5
    local y=rect.y+(rect.height-drawHeight)*.5
    love.graphics.push("all")
    love.graphics.setScissor(rect.x,rect.y,rect.width,rect.height)
    love.graphics.setColor(1,1,1,.45)
    love.graphics.draw(image,x,y,0,scale,scale)
    love.graphics.setScissor()
    love.graphics.setColor(.018,.035,.045,.42)
    love.graphics.rectangle("fill",rect.x,rect.y,rect.width,rect.height)
    love.graphics.pop()
    return true
end

function Art.release()
    for month,image in pairs(cache) do
        if image and image.release then image:release() end
        cache[month]=nil
    end
end

return Art
