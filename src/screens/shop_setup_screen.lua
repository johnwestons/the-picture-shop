local Config=require("src.config")
local Ui=require("src.screens.ui")
local Skin=require("src.screens.title_skin")
local Fonts=require("src.screens.title_fonts")
local Setup={}
local buttons={minus={x=290,y=315,width=58,height=44},plus={x=612,y=315,width=58,height=44},
    fast={x=284,y=443,width=120,height=40},standard={x=420,y=443,width=120,height=40},
    slow={x=556,y=443,width=120,height=40},cancel={x=265,y=548,width=200,height=48},
    start={x=495,y=548,width=200,height=48}}
local slider={x=290,y=386,width=380,height=32}
function Setup.new() return {dayLengthMinutes=Config.businessCalendar.secondsPerDay/60} end
function Setup.buttonCenter(name)
    local b=buttons[name];return b.x+b.width/2,b.y+b.height/2
end
local function change(options,delta)
    options.dayLengthMinutes=math.min(60,math.max(5,options.dayLengthMinutes+delta))
    return "changed"
end
function Setup.keypressed(options,key)
    if key=="return" or key=="kpenter" then return "start" end
    if key=="escape" then return "cancel" end
    if key=="left" then return change(options,-1) end
    if key=="right" then return change(options,1) end
    if key=="up" then return change(options,5) end
    if key=="down" then return change(options,-5) end
end
function Setup.mousepressed(options,x,y)
    for name,b in pairs(buttons) do if Ui.contains(b,x,y) then
        if name=="start" or name=="cancel" then return name end
        if name=="minus" then return change(options,-1) end
        if name=="plus" then return change(options,1) end
        options.dayLengthMinutes=name=="fast" and 5 or name=="slow" and 60 or 20
        return "changed"
    end end
    if Ui.contains(slider,x,y) then
        options.dayLengthMinutes=math.min(60,math.max(5,math.floor(5+(x-slider.x)/slider.width*55+.5)))
        return "changed"
    end
end
function Setup.draw(options,slot,assets,mouseX,mouseY)
    assets=assets or require("src.assets")
    love.graphics.setColor(.015,.025,.03,.84);love.graphics.rectangle("fill",0,0,Config.baseWidth,Config.baseHeight)
    Skin.panel(assets,{x=240,y=146,width=480,height=470})
    love.graphics.setColor(.98,.84,.33,1);love.graphics.printf("SHOP SETUP OPTIONS",260,169,440,"center")
    love.graphics.setColor(.83,.92,.85,1);love.graphics.printf("New shop in slot "..slot,260,203,440,"center")
    love.graphics.printf("Choose how long a full game day takes.\nThis setting belongs to this shop save.",270,247,420,"center")
    local minutes=options.dayLengthMinutes
    Skin.field(assets,{x=358,y=315,width=244,height=44},"selected")
    love.graphics.setColor(1,.89,.40,1);love.graphics.printf(minutes.." real minutes / day",350,330,260,"center")
    Skin.slider(assets,slider,(minutes-5)/55)
    local labels={minus="-",plus="+",fast="5 MIN",standard="20 MIN",slow="60 MIN",cancel="CANCEL",start="CREATE SHOP"}
    for name,b in pairs(buttons) do
        local selected=(name=="fast" and minutes==5) or (name=="standard" and minutes==20)
            or (name=="slow" and minutes==60)
        local hovered=mouseX and mouseY and Ui.contains(b,mouseX,mouseY)
        Skin.button(assets,b,Ui.pressWithin(b) and "pressed" or (hovered or selected) and "hover" or "normal")
        local font=Fonts.fit("metal",labels[name],16,b.width-20,b.height-14)
        love.graphics.setFont(font)
        love.graphics.setColor(.95,.98,.90,1);love.graphics.printf(labels[name],b.x+10,b.y+(b.height-font:getHeight())/2,b.width-20,"center")
    end
    love.graphics.setColor(.75,.87,.79,1)
    love.graphics.printf(string.format("8-hour shift: %.1f real minutes  |  12-hour shift: %.1f",minutes/3,minutes/2),255,505,450,"center")
end
return Setup
