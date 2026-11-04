-- Live calendar and balances shared by apartment and outdoor riding scenes.
local Calendar=require('src.business_calendar')
local Ui=require('src.screens.ui')
local Status={}
local font
function Status.layout(bounds)
    local left=bounds and bounds.left or 0
    local right=bounds and bounds.right or require('src.config').baseWidth
    -- World Options starts 272px from the safe right edge; Exit sits beside it.
    return {x=left+18,y=12,width=math.max(1,right-272-12-(left+18)),height=44}
end
function Status.text(state,twelveHour)
    local date=Calendar.ensure(state)
    return Calendar.weekdayName(date.weekday)..'  ·  '..Calendar.shortDate(state)
            ..'  ·  '..Calendar.timeText(state,twelveHour),
        'Home '..Ui.money((state.home and state.home.balanceCents or 0)/100)
            ..'  ·  Shop '..Ui.money(state.money or 0)
end
function Status.printLine(text,x,y,width)
    local g=love.graphics
    local scale=math.min(1,math.max(0,width)/math.max(1,g.getFont():getWidth(text)))
    g.print(text,x,y,0,scale,scale)
end
function Status.draw(state,twelveHour,bounds,sceneLabel)
    local g=love.graphics;local rect=Status.layout(bounds)
    local date,money=Status.text(state,twelveHour)
    font=font or g.newFont(14)
    g.push('all');g.setShader();g.setFont(font)
    g.setColor(.025,.045,.05,.94);g.rectangle('fill',rect.x,rect.y,rect.width,rect.height,6)
    g.setColor(.35,.45,.43,.85);g.setLineWidth(1);g.rectangle('line',rect.x,rect.y,rect.width,rect.height,6)
    g.setColor(.87,.94,.92);Status.printLine(date,rect.x+10,rect.y+5,rect.width-20)
    g.setColor(.98,.85,.43);Status.printLine(money,rect.x+10,rect.y+24,rect.width-20)
    if sceneLabel then
        local remaining=rect.width-30-font:getWidth(money)
        if remaining>=font:getWidth(sceneLabel)+12 then
            g.setColor(.72,.81,.78);g.printf(sceneLabel,rect.x+rect.width-remaining-10,rect.y+24,remaining,'right')
        end
    end
    g.pop();return rect
end
return Status
