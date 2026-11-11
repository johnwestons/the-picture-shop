local Bubble={}
function Bubble.layout(message,font)
    local width=math.min(176,math.max(52,font:getWidth(message)+16))
    local _,lines=font:getWrap(message,width-12)
    return width,math.max(22,math.ceil(#lines*font:getHeight()*font:getLineHeight())+10)
end
function Bubble.draw(message,font,originX,headY,screenWidth,layoutMessage)
    local width,height=Bubble.layout(layoutMessage or message,font)
    local x=math.max(4,math.min(screenWidth-width-4,originX-width/2))
    local y=math.max(4,headY-height-9)
    local tailX=math.max(x+8,math.min(x+width-8,originX))
    love.graphics.push('all')
    love.graphics.setFont(font);love.graphics.setLineWidth(1)
    love.graphics.setColor(.035,.06,.075,.94)
    love.graphics.polygon('fill',tailX-4,y+height-1,tailX+4,y+height-1,tailX,y+height+6)
    love.graphics.rectangle('fill',x,y,width,height,5,5)
    love.graphics.setColor(.55,.82,.79,.9)
    love.graphics.rectangle('line',x,y,width,height,5,5)
    love.graphics.setColor(.96,.97,.91,1)
    love.graphics.printf(message,x+6,y+5,width-12,'center')
    love.graphics.pop()
end
return Bubble
