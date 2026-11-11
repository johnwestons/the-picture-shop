local Config=require("src.config")
local Ui=require("src.screens.ui")

local Screen={item=nil,pending=false,fonts={}}
local PAPER={x=30,y=25,width=900,height=600}
local CANCEL={x=510,y=548,width=150,height=42}
local SIGN={x=686,y=548,width=180,height=42}
local CLEAR={x=103,y=548,width=150,height=42}
local PAD={x=337,y=410,width=520,height=82}
local INK={0.18,0.16,0.13,1}
local MUTED={0.36,0.31,0.25,1}
local STAMP={0.40,0.16,0.12,1}

local function font(size)
    if Screen.fonts[size] then return Screen.fonts[size] end
    local ok,value=pcall(love.graphics.newFont,Config.paths.workOrderFont,size)
    if not ok or not value then value=love.graphics.newFont(size) end
    Screen.fonts[size]=value
    return value
end

local function text(value,x,y,width,align)
    love.graphics.printf(tostring(value or "--"),x,y,width or 300,align or "left")
end

local function labelValue(label,value,x,y,width)
    love.graphics.setFont(font(12));love.graphics.setColor(MUTED)
    text(string.upper(label),x,y,width)
    love.graphics.setFont(font(16));love.graphics.setColor(INK)
    text(value,x,y+14,width)
end

local function drawButton(rect,label,hovered,disabled)
    local isHovered=hovered and Ui.contains(rect,hovered.x,hovered.y)
    local down=isHovered and love.mouse and love.mouse.isDown and love.mouse.isDown(1)
    local inset=down and 2 or 0
    local x,y=rect.x+inset,rect.y+inset
    if disabled then
        love.graphics.setColor(0.65,0.61,0.53,0.35)
    elseif down then
        love.graphics.setColor(0.40,0.16,0.12,0.20)
    elseif isHovered then
        love.graphics.setColor(0.62,0.42,0.22,0.18)
    else
        love.graphics.setColor(0.94,0.89,0.76,0.34)
    end
    love.graphics.rectangle("fill",x,y,rect.width,rect.height,2,2)
    love.graphics.setColor(isHovered and STAMP or MUTED)
    love.graphics.setLineWidth(down and 3 or 2)
    love.graphics.rectangle("line",x,y,rect.width,rect.height,2,2)
    love.graphics.setFont(font(15))
    text(label,x,y+12,rect.width,"center")
end

function Screen.enter(item)
    Screen.item=item
    Screen.pending=false
    Screen.clearInk()
end

function Screen.clear()
    Screen.item=nil
    Screen.pending=false
    Screen.clearInk()
end

function Screen.clearInk()
    Screen.strokes={};Screen.pointer=nil;Screen.stroke=nil;Screen.inkLength=0;Screen.pointCount=0
end

function Screen.canSign()
    return Screen.item~=nil and not Screen.pending and Screen.pointer==nil and (Screen.inkLength or 0)>=3
end

function Screen.pointerpressed(id,x,y)
    if Screen.pending or Screen.pointer~=nil then return nil end
    if Ui.contains(PAD,x,y) and Screen.pointCount<4096
        and #Screen.strokes<require('src.receipt_signature').MAX_STROKES then
        x=math.max(PAD.x+2,math.min(PAD.x+PAD.width-2,x))
        y=math.max(PAD.y+2,math.min(PAD.y+PAD.height-2,y))
        Screen.pointer=id;Screen.stroke={x,y}
        Screen.strokes[#Screen.strokes+1]=Screen.stroke
        Screen.pointCount=Screen.pointCount+1
        return {action='drawing'}
    end
    local action=Screen.hitTest(x,y)
    if action=='clear' then Screen.clearInk();return {action='clear'} end
    return action and {action=action} or nil
end

function Screen.pointermoved(id,x,y)
    if id~=Screen.pointer or not Screen.stroke or Screen.pending then return false end
    x=math.max(PAD.x+2,math.min(PAD.x+PAD.width-2,x))
    y=math.max(PAD.y+2,math.min(PAD.y+PAD.height-2,y))
    local stroke=Screen.stroke
    local distance=math.sqrt((x-stroke[#stroke-1])^2+(y-stroke[#stroke])^2)
    if distance>=1 and Screen.pointCount<4096 then
        stroke[#stroke+1]=x;stroke[#stroke+1]=y
        Screen.inkLength=Screen.inkLength+distance;Screen.pointCount=Screen.pointCount+1
    end
    return true
end

function Screen.pointerreleased(id,x,y)
    if id~=Screen.pointer then return false end
    Screen.pointermoved(id,x,y)
    Screen.pointer=nil;Screen.stroke=nil
    return true
end

function Screen.deliveryId()
    return Screen.item and Screen.item.deliveryId
end
function Screen.signature()
    return require('src.receipt_signature').encode(Screen.strokes,PAD)
end

function Screen.setPending(value)
    Screen.pending=value==true
    if Screen.pending then Screen.pointer=nil;Screen.stroke=nil end
end

function Screen.hitTest(x,y)
    if Screen.pointer~=nil then return nil end
    if not Screen.pending and Ui.contains(CANCEL,x,y) then return "cancel" end
    if not Screen.pending and Ui.contains(CLEAR,x,y) then return "clear" end
    if Screen.canSign() and Ui.contains(SIGN,x,y) then return "sign" end
end

function Screen.mousepressed(x,y,button)
    if button~=1 then return nil end
    return Screen.pointerpressed('mouse',x,y)
end

function Screen.mousemoved(x,y)return Screen.pointermoved('mouse',x,y)end
function Screen.mousereleased(x,y,button)
    return button==1 and Screen.pointerreleased('mouse',x,y) or false
end

function Screen.keypressed(key)
    if key=="return" or key=="kpenter" or key=="space" then
        return Screen.canSign() and {action="sign"} or true
    end
    return false
end

function Screen.draw(_,assets,mouseX,mouseY)
    love.graphics.push("all")
    love.graphics.setColor(0.01,0.015,0.018,0.72)
    love.graphics.rectangle("fill",0,0,Config.baseWidth,Config.baseHeight)
    love.graphics.setColor(0,0,0,0.42)
    love.graphics.rectangle("fill",49,49,866,568,8,8)

    local paper=assets and assets.get and assets.get("palletWorkOrderPaper")
    if paper then
        local width,height=paper:getDimensions()
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(paper,PAPER.x,PAPER.y,0,PAPER.width/width,PAPER.height/height)
    else
        love.graphics.setColor(0.92,0.86,0.70,1)
        love.graphics.rectangle("fill",48,39,864,574,3,3)
    end

    local item=Screen.item or {}
    love.graphics.setFont(font(23));love.graphics.setColor(STAMP)
    text("DELIVERY RECEIPT",102,60,340)
    love.graphics.setFont(font(13));love.graphics.setColor(MUTED)
    text("WAREHOUSE RECEIVING COPY",470,59,260)
    love.graphics.setFont(font(15));love.graphics.setColor(INK)
    text(item.deliveryId or "UNKNOWN",470,78,185)

    labelValue("Order number",item.deliveryId,103,126,195)
    labelValue("Document",item.document or "DELIVERY RECEIPT",103,180,195)
    labelValue("Supplier / customer",item.supplier,103,234,195)
    labelValue("Order state",item.orderState,103,288,195)
    labelValue("Delivery",item.deliveryState,103,342,195)
    labelValue("Location",item.location or "Warehouse loading bay",103,396,195)

    labelValue("Shipment",item.shipment,337,126,286)
    labelValue("Quantity",item.quantity,337,180,286)
    labelValue("Category",item.category,337,234,286)
    labelValue(item.amountLabel or "Order value",
        item.declaredValue and Ui.money(item.declaredValue) or "--",337,288,286)
    labelValue("Pallet count",item.palletCount or 0,337,342,286)
    love.graphics.setFont(font(12));love.graphics.setColor(MUTED)
    text('DRAW YOUR SIGNATURE',PAD.x,390,PAD.width)
    love.graphics.setColor(.98,.96,.87,.75)
    love.graphics.rectangle('fill',PAD.x,PAD.y,PAD.width,PAD.height,3)
    love.graphics.setColor(.43,.37,.29,.65);love.graphics.setLineWidth(1)
    love.graphics.rectangle('line',PAD.x,PAD.y,PAD.width,PAD.height,3)
    love.graphics.line(PAD.x+12,PAD.y+PAD.height-15,PAD.x+PAD.width-12,PAD.y+PAD.height-15)
    if (Screen.pointCount or 0)==0 then
        love.graphics.setFont(font(16));love.graphics.setColor(.36,.31,.25,.7)
        text('Draw here with your mouse or finger',PAD.x+14,PAD.y+27,PAD.width-28)
    end
    love.graphics.setColor(.10,.17,.25,1);love.graphics.setLineWidth(2.5);love.graphics.setLineJoin('bevel')
    for _,stroke in ipairs(Screen.strokes or {}) do
        if #stroke>=4 then love.graphics.line(stroke) end
        for i=1,#stroke,2 do love.graphics.circle('fill',stroke[i],stroke[i+1],1.25) end
    end

    local art={x=669,y=151,width=188,height=188}
    require('src.screens.delivery_receipt_art').draw(item,assets,art)

    love.graphics.setFont(font(12));love.graphics.setColor(MUTED)
    text(Screen.pending and "SIGNATURE REQUEST SENT - WAITING FOR THE SHOP HOST" or
        "SIGNATURE ACCEPTS THIS DELIVERY AND RELEASES THE DRIVER TO RETURN TO THE TRUCK.",
        103,506,760,"left")
    local pointer={x=mouseX or -1,y=mouseY or -1}
    drawButton(CLEAR,'CLEAR',pointer,Screen.pending)
    drawButton(CANCEL,"[ ESC ]  CANCEL",pointer,Screen.pending)
    drawButton(SIGN,Screen.pending and "WAITING..." or "OK - SIGN",pointer,not Screen.canSign())
    love.graphics.pop()
end

Screen.clearInk()
return Screen
