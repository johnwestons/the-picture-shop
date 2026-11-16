local Test={}

function Test.run(context,check)
    local screen=context.computerScreen
    local state=context.State.new()
    screen.enter(state)
    screen.tab='calendar'
    screen.calendarYear=state.calendar.year
    screen.calendarMonth=state.calendar.month
    state.employment.staff[#state.employment.staff+1]={
        id='CAL-TEST-WORKER',name='Calendar Test Worker',status='employed',weeks={},
        contract={startDay=0,days=127,startHour=9,endHour=17,payWeeks=1,wageCents=2000},
    }
    state.townCalendarEvents={}
    for index=1,8 do
        state.townCalendarEvents[index]={id='COMMUNITY-'..index,
            title='Community gathering '..index,detail='Town square',
            startHours=4*24+10+index}
    end
    local x,y=screen.calendarDayCenter(5)
    local result=screen.mousepressed(state,x,y,1)
    check('calendar_click_opens_daily_agenda',result and result.action=='calendar_day'
        and screen.calendarDayOpen and screen.calendarSelectedDay==5)
    local shop,town=screen.calendarDayEvents(state,state.calendar.year,state.calendar.month,5)
    check('calendar_daily_agenda_separates_shop_and_town_items',#shop>0 and #town==8
        and town[1].hour~=nil and town[1].minute~=nil)
    check('calendar_day_agenda_scrolls_long_town_lists',screen.wheelmoved(state,0,-1)
        and screen.calendarDayScroll==1)
    local scrollX,scrollY=screen.calendarDayScrollCenter('down')
    result=screen.mousepressed(state,scrollX,scrollY,1)
    check('calendar_day_agenda_has_clickable_scroll_controls',result
        and result.action=='calendar_day_scroll' and screen.calendarDayScroll==2)
    local closeX,closeY=screen.calendarDayCloseCenter()
    result=screen.mousepressed(state,closeX,closeY,1)
    check('calendar_day_agenda_closes_cleanly',result and result.action=='calendar_day_closed'
        and not screen.calendarDayOpen)
    screen.calendarYear,screen.calendarMonth=2026,8
    local holidayX,holidayY=screen.calendarDayCenter(9)
    result=screen.mousepressed(state,holidayX,holidayY,1)
    local _,holidayEvents=screen.calendarDayEvents(state,2026,8,9)
    check('calendar_august_holiday_is_listed',result and result.action=='calendar_day'
        and holidayEvents[1] and holidayEvents[1].title=='Firefly Evening')
    result=screen.mousepressed(state,600,339,1)
    check('calendar_holiday_row_can_be_selected_without_crashing',
        result and result.action=='calendar_event_select'
            and screen.calendarSelectedEventId==nil)
    local timeEvents=context.businessCalendar.events(state,true,state.calendar.year,state.calendar.month)
    local scheduledShift=false
    for _,event in ipairs(timeEvents) do
        if event.kind=='shift' and event.atHours and event.hour and event.minute~=nil then
            scheduledShift=true;break
        end
    end
    check('calendar_month_data_includes_timed_shop_shifts',scheduledShift)
end

return Test
