local Images=require("src.home_art_resources")
local Preload=require("src.home_art_preload")
local Art={PATH="assets/generated/home-furniture-v1/alarm-clock-animated-v1.png",
    frameSize=887,frameCount=2}
local texture,frames,digitalFont

local function load()
    if texture then return true end
    texture=Images.load("alarm_clock",Art.PATH)
    if not texture then return false end
    local width,height=texture:getDimensions()
    if width~=Art.frameSize*Art.frameCount or height~=Art.frameSize then
        Images.release("alarm_clock")
        texture=nil
        return false
    end
    texture:setFilter("linear","linear")
    frames={}
    for index=1,Art.frameCount do
        local x=(index-1)*Art.frameSize
        frames[index]=love.graphics.newQuad(x,0,Art.frameSize,Art.frameSize,width,height)
    end
    digitalFont=love.graphics.newFont(18)
    return true
end

function Art.prewarm() return load() end

function Art.draw(x,y,size,timeText,alarmActive)
    if not Preload.want("alarm_clock",Art.prewarm) or not load() then return false end
    local phase=math.floor(((love.timer and love.timer.getTime and love.timer.getTime()) or os.clock())*2)%2
    local frame=alarmActive and phase==1 and 2 or 1
    local scale=size/Art.frameSize
    love.graphics.push("all")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(texture,frames[frame],x,y,0,scale,scale)

    local display=timeText or "--:--"
    if phase==0 then display=display:gsub(":"," ") end
    love.graphics.setFont(digitalFont)
    love.graphics.setColor(.20,.10,.035,.9)
    love.graphics.printf(display,x+size*.16+1,y+size*.55-digitalFont:getHeight()/2+1,
        size*.68,"center")
    love.graphics.setColor(1,.72,.31,1)
    love.graphics.printf(display,x+size*.16,y+size*.55-digitalFont:getHeight()/2,
        size*.68,"center")
    love.graphics.pop()
    return true
end

function Art.release()
    Images.release("alarm_clock")
    if texture then texture:release() end
    if frames then for _,quad in ipairs(frames) do quad:release() end end
    texture,frames,digitalFont=nil,nil,nil
end

return Art
