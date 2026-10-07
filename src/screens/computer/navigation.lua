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

    function Runtime.tabDropdownRect(index)
        return {
            x = Runtime.TAB_DROPDOWN.x,
            y = Runtime.TAB_DROPDOWN.y + (index - 1) * Runtime.TAB_DROPDOWN.rowHeight,
            width = Runtime.TAB_DROPDOWN.width,
            height = Runtime.TAB_DROPDOWN.rowHeight,
        }
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
