local Calendar=require("src.business_calendar")
local Config=require("src.config")
local Ui=require("src.screens.ui")
local Clock={}
local close={x=752,y=40,width=150,height=42}
local SPEED_OPTIONS={1,2,5,10}
local SPEED_BUTTON_WIDTH,SPEED_BUTTON_HEIGHT,SPEED_BUTTON_GAP=94,44,14

local function speedButtonRect(rect,index)
    local totalWidth=#SPEED_OPTIONS*SPEED_BUTTON_WIDTH+(#SPEED_OPTIONS-1)*SPEED_BUTTON_GAP
    return {x=rect.x+(rect.width-totalWidth)/2+(index-1)*(SPEED_BUTTON_WIDTH+SPEED_BUTTON_GAP),
        y=rect.y+170,width=SPEED_BUTTON_WIDTH,height=SPEED_BUTTON_HEIGHT}
end

function Clock.speedAt(x,y,rect)
    for index,speed in ipairs(SPEED_OPTIONS) do
        if Ui.contains(speedButtonRect(rect,index),x,y) then return speed end
    end
end
function Clock.handAngles(state)
    local _,_,hours=Calendar.clockTime(state)
    return hours%12/12*math.pi*2-math.pi/2, hours%1*math.pi*2-math.pi/2
end
function Clock.drawFace(state,x,y,radius)
    love.graphics.push("all")
    love.graphics.setColor(.055,.06,.07,1);love.graphics.circle("fill",x+2,y+3,radius+3)
    love.graphics.setColor(.64,.43,.19,1);love.graphics.circle("fill",x,y,radius+2)
    love.graphics.setColor(.96,.94,.83,1);love.graphics.circle("fill",x,y,radius-2)
    for minute=0,59 do
        local angle=minute/60*math.pi*2-math.pi/2
        local major=minute%5==0
        local inside=radius*(major and .78 or .87)
        love.graphics.setLineWidth(major and math.max(1,radius/70) or 1)
        love.graphics.setColor(.17,.19,.19,1)
        love.graphics.line(x+math.cos(angle)*inside,y+math.sin(angle)*inside,
            x+math.cos(angle)*radius*.94,y+math.sin(angle)*radius*.94)
    end
    if radius>=60 then
        local font=love.graphics.getFont()
        for _,hour in ipairs({12,3,6,9}) do
            local angle=hour/12*math.pi*2-math.pi/2
            love.graphics.printf(tostring(hour),x+math.cos(angle)*radius*.65-18,
                y+math.sin(angle)*radius*.65-font:getHeight()/2,36,"center")
        end
    end
    local hour,minute=Clock.handAngles(state)
    love.graphics.setColor(.08,.15,.18,1)
    love.graphics.setLineWidth(math.max(2,radius*.04))
    love.graphics.line(x,y,x+math.cos(hour)*radius*.48,y+math.sin(hour)*radius*.48)
    love.graphics.setLineWidth(math.max(1.5,radius*.024))
    love.graphics.line(x,y,x+math.cos(minute)*radius*.73,y+math.sin(minute)*radius*.73)
    love.graphics.setColor(.70,.20,.13,1);love.graphics.circle("fill",x,y,math.max(2,radius*.035))
    love.graphics.pop()
end
function Clock.hitWall(x,y)
    local c=Config.interactables.shopClock
    return (x-c.wallX)^2+(y-c.wallY)^2<=(c.clockRadius+8)^2
end
function Clock.closeHit(x,y) return Ui.contains(close,x,y) end
function Clock.drawPanel(state,rect,digitalOnly,gameSpeed,canChangeSpeed,pointerX,pointerY,drawComputerButton)
    local x,y,w,h=rect.x,rect.y,rect.width,rect.height
    Ui.box(x,y,w,h,{.055,.085,.095,.99},{.42,.64,.61,1},5)
    love.graphics.setColor(.96,.83,.33,1);love.graphics.printf("SHOP CLOCK",x+16,y+16,w-32,"center")
    love.graphics.setColor(.84,.91,.87,1);love.graphics.printf(Calendar.dateText(state),x+12,y+40,w-24,"center")
    if digitalOnly then
        love.graphics.setColor(.48,.70,.66,1)
        love.graphics.printf("Shop time is shown in the computer's bottom-right status display.",
            x+24,y+112,w-48,"center")
        love.graphics.setColor(.84,.91,.87,1)
        love.graphics.printf("GAME SPEED",x+24,y+143,w-48,"center")
        for index,speed in ipairs(SPEED_OPTIONS) do
            local button=speedButtonRect(rect,index)
            local enabled=canChangeSpeed==true
            local active=enabled and gameSpeed==speed
            local label=speed==1 and "1x" or (tostring(speed).."x")
            if drawComputerButton then
                local hovered=enabled and pointerX and pointerY and Ui.contains(button,pointerX,pointerY)
                local style=not enabled and "disabled"
                    or active and (hovered and "primaryHover" or "primary")
                    or hovered and "hover" or "secondary"
                drawComputerButton(button,label,style)
            else
                love.graphics.setColor(not enabled and {.18,.21,.22,1}
                    or active and {.26,.39,.29,1} or {.11,.16,.17,1})
                love.graphics.rectangle("fill",button.x,button.y,button.width,button.height,4,4)
                love.graphics.setColor(active and {.98,.80,.30,1}
                    or enabled and {.42,.62,.58,1} or {.31,.36,.36,1})
                love.graphics.setLineWidth(active and 3 or 1)
                love.graphics.rectangle("line",button.x,button.y,button.width,button.height,4,4)
                love.graphics.setLineWidth(1)
                love.graphics.setColor(enabled and {.94,.96,.91,1} or {.58,.62,.60,1})
                love.graphics.printf(label,button.x,button.y+13,button.width,"center")
            end
        end
        love.graphics.setColor(canChangeSpeed and {.48,.70,.66,1} or {.78,.66,.40,1})
        love.graphics.printf(canChangeSpeed and "Fast-forward while the shop is quiet."
            or "Only the host can change game speed.",x+24,y+228,w-48,"center")
    else
        love.graphics.setColor(1,.90,.52,1)
        love.graphics.printf(Calendar.timeText(state,true).."  /  "..Calendar.timeText(state),x+16,y+65,w-32,"center")
        local radius=h>460 and 147 or 120
        Clock.drawFace(state,x+w/2,y+98+radius,radius)
    end
    love.graphics.setColor(.73,.85,.78,1)
    love.graphics.printf(string.format("At 1x, one game day = %d real minutes",Calendar.secondsPerDay(state)/60),x+16,y+h-49,w-32,"center")
    love.graphics.printf("Employee shifts and wages follow this shop time.",x+16,y+h-27,w-32,"center")
end
function Clock.draw(state,pointerX,pointerY)
    love.graphics.setColor(.005,.015,.02,.80);love.graphics.rectangle("fill",0,0,Config.baseWidth,Config.baseHeight)
    Clock.drawPanel(state,{x=236,y=106,width=488,height=520})
    Ui.box(close.x,close.y,close.width,close.height,{.13,.27,.28,1},{.45,.69,.64,1},3)
    love.graphics.setColor(.95,.98,.92,1);love.graphics.printf("BACK",close.x,close.y+14,close.width,"center")
end
return Clock
