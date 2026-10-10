-- Calendar presentation.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}
local CustomerDemand = require("src.customer_demand")

function Component.install(Runtime)
    function Runtime.drawCalendar(state, pointerX, pointerY, twelveHourTime)
        local year = Runtime.ComputerScreen.calendarYear or state.calendar.year
        local month = Runtime.ComputerScreen.calendarMonth or state.calendar.month
        Runtime.panel({ x = 82, y = 190, width = 516, height = 408 },
            { 0.055, 0.07, 0.09, 1 }, { 0.23, 0.35, 0.38, 1 })
        Runtime.panel({ x = 612, y = 190, width = 240, height = 408 },
            { 0.065, 0.08, 0.10, 1 }, { 0.23, 0.35, 0.38, 1 })
        local function navButton(rect, label)
            local hovered = pointerX and Runtime.contains(rect, pointerX, pointerY)
            Runtime.drawComputerButton(rect, label, hovered and "hover" or "secondary")
        end
        navButton(Runtime.CAL_PREVIOUS, "<")
        navButton(Runtime.CAL_NEXT, ">")
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.printf(string.upper(Runtime.BusinessCalendar.monthName(month)) .. " " .. year,
            146, 210, 388, "center")
        local season = CustomerDemand.seasonForMonth(month)
        love.graphics.setColor(0.60, 0.77, 0.75)
        love.graphics.printf(string.format("%s  •  Seasonal demand %d%%",
            season.name, math.floor(season.demand * 100 + 0.5)), 102, 233, 476, "center")
        local weekdayLabels = { "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN" }
        local gridX, gridY, cellW, cellH = Runtime.CAL_GRID.x, Runtime.CAL_GRID.y - 24,
            Runtime.CAL_GRID.cellWidth, Runtime.CAL_GRID.cellHeight
        for index, label in ipairs(weekdayLabels) do
            love.graphics.setColor(index > 5 and 0.66 or 0.76, 0.78, 0.79)
            love.graphics.printf(label, gridX + (index - 1) * cellW, gridY, cellW, "center")
        end
        local firstTotal = Runtime.BusinessCalendar.totalDayForDate(year, month, 1)
        local firstDate = Runtime.BusinessCalendar.dateFromTotalDay(firstTotal or 0)
        local firstColumn = firstDate.weekday
        local events = Runtime.calendarMonthEvents(state, year, month, twelveHourTime)
        local eventsByDay = {}
        for _, event in ipairs(events) do
            eventsByDay[event.day] = eventsByDay[event.day] or {}
            eventsByDay[event.day][#eventsByDay[event.day] + 1] = event
        end
        for day = 1, Runtime.BusinessCalendar.daysInMonth(year, month) do
            local cellIndex = firstColumn - 1 + day - 1
            local column, row = cellIndex % 7, math.floor(cellIndex / 7)
            local x, y = gridX + column * cellW, Runtime.CAL_GRID.y + row * cellH
            local today = year == state.calendar.year and month == state.calendar.month and day == state.calendar.day
            local selected = day == Runtime.ComputerScreen.calendarSelectedDay
            local hovered = pointerX and Runtime.contains(Runtime.calendarDayRect(year, month, day), pointerX, pointerY)
            local dayRect = { x = x + 2, y = y + 2, width = cellW - 4, height = cellH - 4 }
            local dayFill = selected and { 0.09, 0.31, 0.32, 1 }
                or today and { 0.08, 0.22, 0.23, 1 }
                or hovered and { 0.075, 0.15, 0.18, 1 }
                or { 0.055, 0.085, 0.11, 1 }
            local dayBorder = selected and { 0.96, 0.72, 0.27, 1 }
                or today and { 0.28, 0.60, 0.48, 1 }
                or hovered and { 0.24, 0.49, 0.54, 1 }
                or { 0.15, 0.27, 0.33, 1 }
            Runtime.panel(dayRect, dayFill, dayBorder, 2, selected and 2 or 1)
            love.graphics.setColor((selected or today) and 0.98 or 0.84,
                (selected or today) and 0.84 or 0.88,
                (selected or today) and 0.35 or 0.90)
            love.graphics.print(tostring(day), x + 7, y + 6)
            local dayEvents = eventsByDay[day] or {}
            for marker = 1, math.min(4, #dayEvents) do
                local event = dayEvents[marker]
                if event.kind == "bill" then love.graphics.setColor(0.93, 0.34, 0.25)
                elseif event.kind == "machine" then love.graphics.setColor(0.76, 0.55, 0.94)
                elseif event.kind == "credit" then love.graphics.setColor(0.34, 0.79, 0.75)
                elseif event.kind == "email" then love.graphics.setColor(0.32, 0.72, 0.92)
                else love.graphics.setColor(0.30, 0.78, 0.48) end
                love.graphics.circle("fill", x + 10 + (marker - 1) * 12, y + 39, 4)
            end
        end
        love.graphics.setColor(0.96, 0.84, 0.30)
        love.graphics.print("MONTH EVENTS", 628, 210)
        local _, maximumScroll = Runtime.clampCalendarScroll(state)
        local visibleCount = 0
        for row = 1, Runtime.CAL_EVENT_LIST.visibleRows do
            local event = events[Runtime.ComputerScreen.calendarScroll + row]
            if event then
                visibleCount = visibleCount + 1
                local y = Runtime.CAL_EVENT_LIST.y + (row - 1) * Runtime.CAL_EVENT_LIST.rowHeight
                local selected = event.day == Runtime.ComputerScreen.calendarSelectedDay
                love.graphics.setColor(0.10, 0.14, 0.16, 1)
                if selected then love.graphics.setColor(0.12, 0.29, 0.30, 1) end
                love.graphics.rectangle("fill", Runtime.CAL_EVENT_LIST.x, y, Runtime.CAL_EVENT_LIST.width, 31, 2, 2)
                love.graphics.setColor(0.95, 0.84, 0.30)
                love.graphics.print(tostring(event.day), 632, y + 8)
                love.graphics.setColor(0.80, 0.86, 0.85)
                love.graphics.printf(event.title, 656, y + 5, 176, "left")
            end
        end
        if visibleCount == 0 then
            love.graphics.setColor(0.56, 0.64, 0.65)
            love.graphics.printf("No scheduled events this month.", 628, 340, 208, "center")
        end
        local function scrollButton(rect, label, enabled)
            local hovered = enabled and pointerX and Runtime.contains(rect, pointerX, pointerY)
            Runtime.drawComputerButton(rect, label,
                not enabled and "disabled" or hovered and "hover" or "secondary")
        end
        scrollButton(Runtime.CAL_SCROLL_UP, "UP", Runtime.ComputerScreen.calendarScroll > 0)
        scrollButton(Runtime.CAL_SCROLL_DOWN, "DOWN", Runtime.ComputerScreen.calendarScroll < maximumScroll)

        local hoverDay = pointerX and Runtime.calendarDayAt(year, month, pointerX, pointerY)
        if hoverDay then
            local dayEvents = eventsByDay[hoverDay] or {}
            local shown = math.min(6, #dayEvents)
            local tooltipWidth = 440
            local font, contentWidth = love.graphics.getFont(), 406
            local rows, rowsHeight = {}, 0
            for index = 1, shown do
                local event = dayEvents[index]
                local _, titleLines = font:getWrap("• " .. tostring(event.title), contentWidth)
                local detailLines = {}
                if event.detail and event.detail ~= "" then
                    _, detailLines = font:getWrap(tostring(event.detail), contentWidth - 12)
                end
                local height = math.max(22, #titleLines * font:getHeight()
                    + #detailLines * font:getHeight() + 7)
                rows[index] = { event = event, height = height }
                rowsHeight = rowsHeight + height
            end
            local tooltipHeight = 48 + math.max(30, rowsHeight) + (#dayEvents > shown and 22 or 0)
            local tx = math.min(Runtime.Config.baseWidth - tooltipWidth - 12, pointerX + 16)
            local ty = math.min(Runtime.Config.baseHeight - tooltipHeight - 12, pointerY + 18)
            Runtime.panel({ x = tx, y = ty, width = tooltipWidth, height = tooltipHeight },
                { 0.025, 0.04, 0.05, 0.98 }, { 0.42, 0.70, 0.72, 1 })
            love.graphics.setColor(0.96, 0.84, 0.30)
            love.graphics.print(string.format("%s %d, %d", Runtime.BusinessCalendar.monthName(month), hoverDay, year), tx + 12, ty + 11)
            if #dayEvents == 0 then
                love.graphics.setColor(0.65, 0.72, 0.73)
                love.graphics.print("No scheduled events", tx + 12, ty + 46)
            else
                local rowY = ty + 40
                for index = 1, shown do
                    local row, event = rows[index], rows[index].event
                    love.graphics.setColor(0.84, 0.90, 0.88)
                    love.graphics.printf("• " .. event.title, tx + 12, rowY, contentWidth, "left")
                    if event.detail and event.detail ~= "" then
                        local _, titleLines = font:getWrap("• " .. tostring(event.title), contentWidth)
                        love.graphics.setColor(0.56, 0.66, 0.67)
                        love.graphics.printf(tostring(event.detail), tx + 24,
                            rowY + #titleLines * font:getHeight(), contentWidth - 12, "left")
                    end
                    rowY = rowY + row.height
                end
                if #dayEvents > shown then
                    love.graphics.setColor(0.65, 0.72, 0.73)
                    love.graphics.print("+" .. (#dayEvents - shown) .. " more", tx + 12, ty + tooltipHeight - 21)
                end
            end
        end
    end
end

return Component
