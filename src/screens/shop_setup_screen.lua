local Config=require("src.config")
local Ui=require("src.screens.ui")
local Skin=require("src.screens.title_skin")
local Fonts=require("src.screens.title_fonts")
local Catalog=require("src.home_catalog")
local Condition=require("src.warehouse_condition")
local Setup={}
local buttons={
    previous={x=60,y=353,width=70,height=44},random={x=140,y=353,width=210,height=44},
    next={x=360,y=353,width=70,height=44},
    empty={x=60,y=450,width=170,height=44},modest={x=240,y=450,width=190,height=44},
    minus={x=500,y=175,width=58,height=44},plus={x=832,y=175,width=58,height=44},
    fast={x=500,y=290,width=120,height=44},standard={x=635,y=290,width=120,height=44},
    slow={x=770,y=290,width=120,height=44},
    cancel={x=490,y=589,width=190,height=48},start={x=700,y=589,width=200,height=48},
}
local slider={x=510,y=241,width=370,height=32}
function Setup.new()
    return {dayLengthMinutes=Config.businessCalendar.secondsPerDay/60,
        apartmentId="brick-walkup",furnishingPreset="empty"}
end
function Setup.buttonCenter(name)
    local b=buttons[name];return b.x+b.width/2,b.y+b.height/2
end
function Setup.sliderPoint(fraction) return slider.x+slider.width*fraction,slider.y+slider.height/2 end
local function change(options,delta)
    options.dayLengthMinutes=math.min(60,math.max(5,options.dayLengthMinutes+delta));return "changed"
end
local function choose(options,delta)
    local index=1
    for i,id in ipairs(Catalog.ORDER) do if id==options.apartmentId then index=i end end
    options.apartmentId=Catalog.ORDER[(index-1+delta)%#Catalog.ORDER+1]
    options.randomized=false;return "changed"
end
function Setup.randomize(options,random)
    options.apartmentId=Catalog.roll(random);options.randomized=true;return "changed"
end
function Setup.keypressed(options,key)
    if key=="return" or key=="kpenter" then return "start" end
    if key=="escape" then return "cancel" end
    if key=="left" then return change(options,-1) end
    if key=="right" then return change(options,1) end
    if key=="up" then return change(options,5) end
    if key=="down" then return change(options,-5) end
    if key=="a" then return choose(options,-1) end
    if key=="d" then return choose(options,1) end
    if key=="r" then return Setup.randomize(options) end
    if key=="f" then options.furnishingPreset=options.furnishingPreset=="empty" and "modest" or "empty";return "changed" end
end
function Setup.mousepressed(options,x,y)
    for name,b in pairs(buttons) do if Ui.contains(b,x,y) then
        if name=="start" or name=="cancel" then return name end
        if name=="previous" then return choose(options,-1) end
        if name=="next" then return choose(options,1) end
        if name=="random" then return Setup.randomize(options) end
        if name=="empty" or name=="modest" then options.furnishingPreset=name;return "changed" end
        if name=="minus" then return change(options,-1) end
        if name=="plus" then return change(options,1) end
        options.dayLengthMinutes=name=="fast" and 5 or name=="slow" and 60 or 20;return "changed"
    end end
    if Ui.contains(slider,x,y) then
        options.dayLengthMinutes=math.min(60,math.max(5,math.floor(5+(x-slider.x)/slider.width*55+.5)))
        return "changed"
    end
end
local function text(value,x,y,width,size,color,align)
    love.graphics.setFont(Fonts.get("paper",size or 17))
    love.graphics.setColor(unpack(color or {.84,.93,.87,1}))
    love.graphics.printf(value,x,y,width,align or "left")
end
function Setup.draw(options,slot,assets,mouseX,mouseY)
    assets=assets or require("src.assets")
    love.graphics.setColor(.015,.025,.03,.96);love.graphics.rectangle("fill",0,0,Config.baseWidth,Config.baseHeight)
    Skin.panel(assets,{x=30,y=30,width=900,height=624})
    text("NEW SHOP & STARTER HOME  /  SLOT "..slot,55,48,850,22,{1,.86,.36,1},"center")
    local entry=Catalog.APARTMENTS[options.apartmentId]
    text(entry.name.."  -  $"..(entry.rentCents/100).." / month",60,91,370,20,{1,.88,.42,1})
    text(entry.condition,60,119,370,16)
    love.graphics.setColor(.055,.075,.075,1);love.graphics.rectangle("fill",60,147,370,197,5,5)
    local art,reason
    if assets.getApartment then art,reason=assets.getApartment(options.apartmentId) end
    if art and art.floor and art.wall then
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(art.floor,97,147,0,197/1024,197/1024)
        love.graphics.draw(art.wall,97,147,0,197/1024,197/1024)
    else text(reason and "Apartment art unavailable" or "Loading apartment...",70,230,350,17,nil,"center") end
    text(options.randomized and "Random selection shown above; saved exactly as shown." or entry.description,60,405,370,16)
    local preset=Catalog.PRESETS[options.furnishingPreset]
    text(preset.description,60,505,370,16)
    text("GAME DAY LENGTH",500,117,390,20,{1,.86,.36,1},"center")
    Skin.field(assets,{x=567,y=175,width=255,height=44},"selected")
    text(options.dayLengthMinutes.." real minutes / day",568,187,254,18,nil,"center")
    Skin.slider(assets,slider,(options.dayLengthMinutes-5)/55)
    text("8-hour shift: "..string.format("%.1f",options.dayLengthMinutes/3).." real minutes",500,353,390,17,nil,"center")
    text("HOUSEHOLD START",500,402,390,20,{1,.86,.36,1})
    local story=options.startMode=="story"
    local businessBalance=180+(story and Condition.GRANDPA_ALLOWANCE or 0)
    local balanceDetail=story and "Grandpa's repair help is included."
        or "No furniture surcharge or deposit."
    text("Living allowance: $"..(Catalog.ALLOWANCE_CENTS/100)
        .."\nBusiness balance: $"..businessBalance.." (separate)\nFirst apartment rent: February 1\n"
        ..balanceDetail,500,435,390,18)
    text("A / D apartment   R random   F furnishings\nArrow keys adjust day length. Enter chooses town.",60,590,420,14)
    local labels={previous="<",next=">",random="RANDOM APARTMENT",empty="EMPTY",modest="MODESTLY FURNISHED",
        minus="-",plus="+",fast="5 MIN",standard="20 MIN",slow="60 MIN",cancel="CANCEL",start="CHOOSE TOWN"}
    for name,b in pairs(buttons) do
        local selected=name==options.furnishingPreset or (name=="fast" and options.dayLengthMinutes==5)
            or (name=="standard" and options.dayLengthMinutes==20) or (name=="slow" and options.dayLengthMinutes==60)
        local hovered=mouseX and mouseY and Ui.contains(b,mouseX,mouseY)
        Skin.button(assets,b,Ui.pressWithin(b) and "pressed" or (hovered or selected) and "hover" or "normal")
        local font=Fonts.fit("metal",labels[name],16,b.width-16,b.height-12)
        love.graphics.setFont(font);love.graphics.setColor(.95,.98,.90,1)
        love.graphics.printf(labels[name],b.x+8,b.y+(b.height-font:getHeight())/2,b.width-16,"center")
    end
end
return Setup
