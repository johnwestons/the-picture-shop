-- Monthly overview and click-to-open daily agenda.
local Component={}
local CustomerDemand=require('src.customer_demand')
local BusinessHours=require('src.business_hours')

local COLORS={
    shop={.35,.78,.57,1},
    town={.36,.70,.91,1},
    bill={.94,.47,.34,1},
    machine={.76,.59,.94,1},
    shift={.40,.82,.68,1},
    shipment={.96,.72,.32,1},
    credit={.55,.72,.96,1},
    email={.49,.72,.93,1},
}

local function eventColor(event)
    return COLORS[event.kind] or COLORS.shop
end

local function drawFit(text,x,y,width,centered)
    text=tostring(text or '')
    local font=love.graphics.getFont()
    local measured=font:getWidth(text)
    local scale=measured>width and width/math.max(1,measured) or 1
    local drawX=centered and x+(width-measured*scale)*.5 or x
    love.graphics.print(text,drawX,y,0,scale,scale)
end

local function dayCounts(events)
    local shop,town=0,0
    for _,event in ipairs(events or {}) do
        if event.kind=='town' then town=town+1 else shop=shop+1 end
    end
    return shop,town
end

local function hourLabel(hours,twelveHourTime)
    if hours==24 then return '12:00 AM' end
    return require('src.business_calendar').formatTime(hours,0,twelveHourTime)
end

local function shopHoursLabel(totalDay,twelveHourTime)
    local opens,closes=BusinessHours.window(totalDay)
    if opens==closes then return 'CLOSED' end
    if opens==0 and closes==24 then return 'OPEN ALL DAY' end
    return 'OPEN '..hourLabel(opens,twelveHourTime)..' – '..hourLabel(closes,twelveHourTime)
end

local function eventTime(event,twelveHourTime)
    if event.hour==nil then return 'ALL DAY' end
    return require('src.business_calendar').formatTime(event.hour,event.minute or 0,twelveHourTime)
end

local function drawEventList(Runtime,rect,events,scroll,twelveHourTime,emptyMessage)
    local g=love.graphics
    local list=Runtime.CAL_DAY_LIST
    local startY=rect.y+51
    local rowHeight=list.rowHeight
    local visible=list.visibleRows
    if #events==0 then
        g.setColor(.58,.66,.67,1)
        g.printf(emptyMessage,rect.x+14,startY+10,rect.width-28,'center')
        return
    end
    for row=1,visible do
        local event=events[scroll+row]
        if not event then break end
        local x,y=rect.x+8,startY+(row-1)*rowHeight
        local width=rect.width-16
        local color=eventColor(event)
        Runtime.panel({x=x,y=y,width=width,height=rowHeight-4},
            { .055,.085,.10,1 },{ .16,.25,.28,1 },2,1)
        g.setColor(color);g.rectangle('fill',x,y,3,rowHeight-4)
        g.setColor(.70,.78,.78,1)
        drawFit(eventTime(event,twelveHourTime),x+9,y+5,68,false)
        g.setColor(.91,.94,.89,1)
        drawFit(event.title,x+82,y+4,width-91,false)
        if event.detail and event.detail~='' then
            g.setColor(.58,.68,.69,1)
            drawFit(event.detail,x+82,y+22,width-91,false)
        end
    end
end

local function drawDayDialog(Runtime,state,year,month,day,shopEvents,townEvents,twelveHourTime)
    local g=love.graphics
    local dialog=Runtime.CAL_DAY_DIALOG
    local date=Runtime.BusinessCalendar.dateFromTotalDay(
        Runtime.BusinessCalendar.totalDayForDate(year,month,day))
    local shopRect,townRect=Runtime.CAL_DAY_LIST.shop,Runtime.CAL_DAY_LIST.town
    local scroll=Runtime.ComputerScreen.calendarDayScroll or 0
    local current=year==state.calendar.year and month==state.calendar.month and day==state.calendar.day
    local totalDay=Runtime.BusinessCalendar.totalDayForDate(year,month,day)
    local shopHours=shopHoursLabel(totalDay,twelveHourTime)

    g.setColor(.005,.012,.018,.70)
    g.rectangle('fill',Runtime.CAL_PANEL.x,Runtime.CAL_PANEL.y,
        Runtime.CAL_PANEL.width,Runtime.CAL_PANEL.height)
    Runtime.panel(dialog,{.035,.052,.063,.99},{.40,.67,.65,1},5,2)
    g.setColor(.96,.84,.30,1)
    drawFit(string.upper(Runtime.BusinessCalendar.weekdayName(date.weekday)..' · '
        ..Runtime.BusinessCalendar.monthName(month)..' '..day..', '..year),
        dialog.x+18,dialog.y+14,dialog.width-82,false)
    local closeHovered=Runtime.buttonDrawPointerX
        and Runtime.contains(Runtime.CAL_DAY_CLOSE,Runtime.buttonDrawPointerX,Runtime.buttonDrawPointerY)
    Runtime.drawComputerButton(Runtime.CAL_DAY_CLOSE,'X',
        closeHovered and 'hover' or 'secondary')
    g.setColor(current and .38 or .63,current and .86 or .72,current and .55 or .73,1)
    g.printf((current and 'TODAY' or 'DAY PLAN')..'   •   SHOP '..shopHours
        ..'   •   '..(#shopEvents..' shop item(s) / '..#townEvents..' town event(s)'),
        dialog.x+18,dialog.y+44,dialog.width-36,'left')

    local function section(rect,title,accent,events,emptyMessage)
        Runtime.panel({x=rect.x,y=dialog.y+76,width=rect.width,height=292},
            {.045,.065,.075,1},{.18,.30,.32,1},3,1)
        g.setColor(accent)
        g.rectangle('fill',rect.x,dialog.y+76,rect.width,2)
        g.setColor(.91,.90,.78,1)
        g.print(title,rect.x+12,dialog.y+86)
        g.setColor(.58,.70,.70,1)
        g.print(string.format('%d scheduled',#events),rect.x+12,dialog.y+105)
        drawEventList(Runtime,rect,events,scroll,twelveHourTime,emptyMessage)
    end
    section(shopRect,'SHOP SCHEDULE',COLORS.shop,shopEvents,'No shop items are scheduled for this day.')
    section(townRect,'TOWN EVENTS & GATHERINGS',COLORS.town,townEvents,
        'No town events or gatherings are scheduled for this day.')

    local _,_,maximum=Runtime.clampCalendarDayScroll(state)
    if maximum>0 then
        g.setColor(.62,.72,.71,1)
        g.printf(string.format('Showing %d–%d of %d in each list  •  scroll or use arrows',
            scroll+1,math.min(scroll+Runtime.CAL_DAY_LIST.visibleRows,
                math.max(#shopEvents,#townEvents)),math.max(#shopEvents,#townEvents)),
            dialog.x+16,dialog.y+386,dialog.width-180,'left')
        Runtime.drawComputerButton(Runtime.CAL_DAY_SCROLL_UP,'UP',
            scroll>0 and 'secondary' or 'disabled')
        Runtime.drawComputerButton(Runtime.CAL_DAY_SCROLL_DOWN,'DOWN',
            scroll<maximum and 'secondary' or 'disabled')
    else
        g.setColor(.55,.65,.66,1)
        g.print('Click another date to see its plan.',dialog.x+18,dialog.y+390)
    end
end

function Component.install(Runtime)
    function Runtime.drawCalendar(state,pointerX,pointerY,twelveHourTime)
        local screen=Runtime.ComputerScreen
        local year=screen.calendarYear or state.calendar.year
        local month=screen.calendarMonth or state.calendar.month
        Runtime.panel(Runtime.CAL_PANEL,{.055,.07,.09,1},{.23,.35,.38,1})
        local function navButton(rect,label)
            local hovered=pointerX and Runtime.contains(rect,pointerX,pointerY)
            Runtime.drawComputerButton(rect,label,hovered and 'hover' or 'secondary')
        end
        navButton(Runtime.CAL_PREVIOUS,'<')
        navButton(Runtime.CAL_NEXT,'>')
        love.graphics.setColor(.96,.84,.30,1)
        love.graphics.printf(string.upper(Runtime.BusinessCalendar.monthName(month))..' '..year,
            146,207,650,'center')
        local season=CustomerDemand.seasonForMonth(month)
        love.graphics.setColor(.63,.75,.75,1)
        love.graphics.printf(string.format('%s  •  Seasonal demand %d%%  •  Click a date for its day plan',
            season.name,math.floor(season.demand*100+.5)),112,235,732,'center')

        local weekdayLabels={'MON','TUE','WED','THU','FRI','SAT','SUN'}
        local grid=Runtime.CAL_GRID
        local gridX,gridY,cellW,cellH=grid.x,grid.y,grid.cellWidth,grid.cellHeight
        for index,label in ipairs(weekdayLabels) do
            love.graphics.setColor(index>5 and .65 or .78,.78,.79,1)
            love.graphics.printf(label,gridX+(index-1)*cellW,gridY-19,cellW,'center')
        end

        local events=Runtime.calendarMonthEvents(state,year,month,twelveHourTime)
        local eventsByDay={}
        for _,event in ipairs(events) do
            eventsByDay[event.day]=eventsByDay[event.day] or {}
            eventsByDay[event.day][#eventsByDay[event.day]+1]=event
        end
        local firstTotal=Runtime.BusinessCalendar.totalDayForDate(year,month,1)
        local firstColumn=Runtime.BusinessCalendar.dateFromTotalDay(firstTotal or 0).weekday
        for day=1,Runtime.BusinessCalendar.daysInMonth(year,month) do
            local cellIndex=firstColumn-1+day-1
            local column,row=cellIndex%7,math.floor(cellIndex/7)
            local x,y=gridX+column*cellW,gridY+row*cellH
            local today=year==state.calendar.year and month==state.calendar.month and day==state.calendar.day
            local selected=day==screen.calendarSelectedDay
            local hovered=pointerX and Runtime.contains(Runtime.calendarDayRect(year,month,day),pointerX,pointerY)
            local rect={x=x+2,y=y+1,width=cellW-4,height=cellH-3}
            local fill=selected and {.09,.30,.31,1} or today and {.08,.20,.22,1}
                or hovered and {.08,.15,.18,1} or {.045,.075,.095,1}
            local border=selected and {.96,.72,.27,1} or today and {.30,.62,.49,1}
                or hovered and {.24,.49,.54,1} or {.15,.27,.33,1}
            Runtime.panel(rect,fill,border,2,selected and 2 or 1)
            love.graphics.setColor(selected and .98 or .87,selected and .84 or .90,
                selected and .36 or .91,1)
            love.graphics.print(tostring(day),x+9,y+4)
            local shopCount,townCount=dayCounts(eventsByDay[day])
            if shopCount>0 then
                love.graphics.setColor(COLORS.shop)
                love.graphics.circle('fill',x+13,y+35,3)
                love.graphics.setColor(.72,.83,.77,1)
                love.graphics.printf(shopCount..' SHOP',x+20,y+29,42,'left')
            end
            if townCount>0 then
                love.graphics.setColor(COLORS.town)
                love.graphics.circle('fill',x+67,y+35,3)
                love.graphics.setColor(.72,.80,.86,1)
                love.graphics.printf(townCount..' TOWN',x+74,y+29,31,'left')
            end
            if shopCount==0 and townCount==0 then
                love.graphics.setColor(.43,.52,.55,1)
                love.graphics.print('—',x+9,y+30)
            end
        end

        if screen.calendarDayOpen and screen.calendarSelectedDay then
            local shopEvents,townEvents=Runtime.calendarDayEvents(state,year,month,
                screen.calendarSelectedDay,twelveHourTime)
            Runtime.drawCalendarDayDialog(Runtime,state,year,month,screen.calendarSelectedDay,
                shopEvents,townEvents,twelveHourTime)
        end
    end

    Runtime.drawCalendarDayDialog=drawDayDialog
end

return Component
