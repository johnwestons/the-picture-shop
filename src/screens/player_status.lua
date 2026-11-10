-- Live calendar and balances shared by apartment and outdoor riding scenes.
local Calendar=require('src.business_calendar')
local Ui=require('src.screens.ui')
local Text=require('src.screens.typography')
local Status={}
function Status.layout(bounds)
    local left=bounds and bounds.left or 0
    local right=bounds and bounds.right or require('src.config').baseWidth
    -- World Options starts 272px from the safe right edge; Exit sits beside it.
    local width=math.max(1,right-272-12-(left+18))
    return {x=left+18,y=12,width=width,height=width<520 and 96 or 54}
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
    local shown=Text.ellipsize(text,width)
    g.print(shown,x,y)
    return shown
end
function Status.displayText(state,twelveHour,width)
    local date,money=Status.text(state,twelveHour)
    if Text.get(14):getWidth(date)>width then
        local calendar=Calendar.ensure(state)
        date=Calendar.weekdayName(calendar.weekday):sub(1,3)..' · '
            ..Calendar.shortDate(state):gsub(', %d%d%d%d',''):gsub('%s+W%d+','')
            ..' · '..Calendar.timeText(state,twelveHour)
    end
    money=Status.moneyText(state,width,Text.get(14,'bold'))
    return date,money
end
function Status.moneyText(state,width,font)
    local _,full=Status.text(state,true)
    if not width or (font or Text.get(14,'bold')):getWidth(full)<=width then return full end
    local function compact(value)
        local magnitude=math.abs(value)
        for _,unit in ipairs({{1e9,'B'},{1e6,'M'},{1e3,'K'}}) do
            if magnitude>=unit[1] then return ('$%.1f%s'):format(value/unit[1],unit[2]) end
        end
        return Ui.money(value)
    end
    return 'Home '..compact((state.home and state.home.balanceCents or 0)/100)..' · Shop '..compact(state.money or 0)
end
function Status.statsWidth(rect,objective)
    return objective and rect.width>=520 and math.max(330,(rect.width-34)*.57) or rect.width-20
end
function Status.draw(state,twelveHour,bounds,sceneLabel,objective)
    local g=love.graphics;local rect=Status.layout(bounds)
    g.push('all');g.setShader()
    Ui.panel(rect,Text.colors.panel,Text.colors.border,6,1)
    local statsWidth=Status.statsWidth(rect,objective)
    local stacked=rect.width<520
    local date,money=Status.displayText(state,twelveHour,statsWidth)
    g.setFont(Text.fit(date,16,statsWidth,22));g.setColor(Text.colors.body)
    Status.printLine(date,rect.x+10,rect.y+5,statsWidth)
    g.setFont(Text.fit(money,16,statsWidth,22,'bold'));g.setColor(Text.colors.accent)
    Status.printLine(money,rect.x+10,rect.y+29,statsWidth)
    if objective then
        local width=stacked and statsWidth or rect.width-statsWidth-34
        local x=stacked and rect.x+10 or rect.x+rect.width-10-width
        local y=rect.y+(stacked and 54 or 5)
        g.setFont(Text.get(14,'bold'));g.setColor(Text.colors.muted);Status.printLine(objective,x,y,width)
        g.setFont(Text.get(16));g.setColor(Text.colors.accent);Status.printLine(sceneLabel,x,y+21,width)
        if not stacked then g.setColor(Text.colors.border);g.line(x-7,rect.y+7,x-7,rect.y+rect.height-7) end
    elseif sceneLabel and stacked then
        g.setFont(Text.get(16));g.setColor(Text.colors.muted);Status.printLine(sceneLabel,rect.x+10,rect.y+59,statsWidth)
    end
    g.pop();return rect
end
return Status
