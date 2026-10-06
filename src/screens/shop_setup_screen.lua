local Config=require("src.config")
local Ui=require("src.screens.ui")
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
function Setup.draw(options,slot)
    love.graphics.setColor(.015,.025,.03,.84);love.graphics.rectangle("fill",0,0,Config.baseWidth,Config.baseHeight)
    Ui.box(240,146,480,470,{.055,.10,.11,.99},{.52,.72,.65,1},5)
    love.graphics.setColor(.98,.84,.33,1);love.graphics.printf("SHOP SETUP OPTIONS",260,169,440,"center")
    love.graphics.setColor(.83,.92,.85,1);love.graphics.printf("New shop in slot "..slot,260,203,440,"center")
    love.graphics.printf("Choose how long a full game day takes.\nThis setting belongs to this shop save.",270,247,420,"center")
    local minutes=options.dayLengthMinutes
    love.graphics.setColor(1,.89,.40,1);love.graphics.printf(minutes.." real minutes / day",350,330,260,"center")
    love.graphics.setColor(.24,.39,.35,1);love.graphics.rectangle("fill",slider.x,slider.y+12,slider.width,8)
    local sx=slider.x+(minutes-5)/55*slider.width
    love.graphics.setColor(.98,.79,.27,1);love.graphics.circle("fill",sx,slider.y+16,10)
    local labels={minus="-",plus="+",fast="5 MIN",standard="20 MIN",slow="60 MIN",cancel="CANCEL",start="CREATE SHOP"}
    for name,b in pairs(buttons) do
        Ui.box(b.x,b.y,b.width,b.height,{.14,.30,.28,1},{.43,.64,.51,1},3)
        love.graphics.setColor(.95,.98,.90,1);love.graphics.printf(labels[name],b.x,b.y+(b.height-13)/2,b.width,"center")
    end
    love.graphics.setColor(.75,.87,.79,1)
    love.graphics.printf(string.format("8-hour shift: %.1f real minutes  |  12-hour shift: %.1f",minutes/3,minutes/2),255,505,450,"center")
end
return Setup
