local Config=require("src.config")
local Staging={}
function Staging.slots()
    local c=Config.cutterStaging
    local slots={}
    for row=1,c.rows do for column=1,c.columns do
        slots[#slots+1]={number=#slots+1,x=c.firstX+(column-1)*c.columnSpacing,
            y=c.firstY+(row-1)*c.rowSpacing,direction=c.direction,rotation=1}
    end end
    return slots
end
function Staging.find(isClear)
    for _,slot in ipairs(Staging.slots()) do if isClear(slot.x,slot.y) then return slot end end
    return nil,"The marked cutter staging area is full or blocked. Move a finished pallet to make room."
end
function Staging.draw()
    local c=Config.cutterStaging
    love.graphics.push("all")
    love.graphics.setLineWidth(2)
    love.graphics.setColor(.96,.77,.18,.7)
    love.graphics.rectangle("line",c.x,c.y,c.width,c.height)
    local font=love.graphics.getFont()
    love.graphics.push()
    love.graphics.translate(c.x,c.y+3);love.graphics.scale(.7)
    love.graphics.printf("CUTTER OUTPUT",0,0,c.width/.7,"center")
    love.graphics.pop()
    for _,slot in ipairs(Staging.slots()) do
        love.graphics.setColor(.96,.77,.18,.4)
        local w,h=Config.palletLogistics.collisionHalfWidth,Config.palletLogistics.collisionHalfHeight
        local cy=slot.y+(Config.palletLogistics.collisionOffsetY or -8)
        love.graphics.polygon("line",slot.x,cy-h,slot.x+w,cy,slot.x,cy+h,slot.x-w,cy)
        love.graphics.printf(tostring(slot.number),slot.x-8,cy-font:getHeight()/2,16,"center")
    end
    love.graphics.pop()
end
return Staging
