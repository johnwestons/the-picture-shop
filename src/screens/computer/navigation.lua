-- Office tabs and calendar navigation helpers.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.tabById(tabId)
        if tabId == "online" then tabId = "www" end
        for _, tab in ipairs(Runtime.visibleTabs()) do
            if tab.id == tabId then return tab end
        end
    end

    function Runtime.tabDropdownGroups()
        local dropdown=Runtime.TAB_DROPDOWN
        local groups={}
        local columnWidth=dropdown.width/#Runtime.TAB_GROUPS
        for index,definition in ipairs(Runtime.TAB_GROUPS) do
            groups[index]={id=definition.id,label=definition.label,index=index,
                x=dropdown.x+(index-1)*columnWidth,width=columnWidth,items={}}
        end
        for tabIndex,tab in ipairs(Runtime.visibleTabs()) do
            for _,group in ipairs(groups) do
                if tab.group==group.id then
                    group.items[#group.items+1]={index=tabIndex,tab=tab}
                    break
                end
            end
        end
        local maxRows=0
        for _,group in ipairs(groups) do maxRows=math.max(maxRows,#group.items) end
        return groups,dropdown.headerHeight+maxRows*dropdown.rowHeight+4
    end

    function Runtime.tabDropdownRect(index)
        local tab=Runtime.visibleTabs()[index]
        if not tab then return nil end
        local groups=Runtime.tabDropdownGroups()
        for _,group in ipairs(groups) do
            for row,item in ipairs(group.items) do
                if item.index==index then
                    return {x=group.x+2,y=Runtime.TAB_DROPDOWN.y+Runtime.TAB_DROPDOWN.headerHeight
                        +(row-1)*Runtime.TAB_DROPDOWN.rowHeight,width=group.width-4,
                        height=Runtime.TAB_DROPDOWN.rowHeight-2}
                end
            end
        end
    end

    function Runtime.calendarMonthEvents(state, year, month, twelveHourTime)
        local result = {}
        for _, event in ipairs(Runtime.BusinessCalendar.events(state,twelveHourTime)) do
            if event.year == year and event.month == month then result[#result + 1] = event end
        end
        return result
    end

    function Runtime.calendarDayRect(year, month, day)
        local firstTotal = Runtime.BusinessCalendar.totalDayForDate(year, month, 1)
        local firstColumn = Runtime.BusinessCalendar.dateFromTotalDay(firstTotal or 0).weekday
        local cellIndex = firstColumn - 1 + day - 1
        local column, row = cellIndex % 7, math.floor(cellIndex / 7)
        return {
            x = Runtime.CAL_GRID.x + column * Runtime.CAL_GRID.cellWidth + 2,
            y = Runtime.CAL_GRID.y + row * Runtime.CAL_GRID.cellHeight + 2,
            width = Runtime.CAL_GRID.cellWidth - 4,
            height = Runtime.CAL_GRID.cellHeight - 4,
        }
    end

    function Runtime.calendarDayAt(year, month, x, y)
        for day = 1, Runtime.BusinessCalendar.daysInMonth(year, month) do
            if Runtime.contains(Runtime.calendarDayRect(year, month, day), x, y) then return day end
        end
    end

    function Runtime.clampCalendarScroll(state)
        local events = Runtime.calendarMonthEvents(state, Runtime.ComputerScreen.calendarYear, Runtime.ComputerScreen.calendarMonth)
        local maximum = math.max(0, #events - Runtime.CAL_EVENT_LIST.visibleRows)
        Runtime.ComputerScreen.calendarScroll = math.min(maximum, math.max(0, Runtime.ComputerScreen.calendarScroll or 0))
        return events, maximum
    end
end

return Component
