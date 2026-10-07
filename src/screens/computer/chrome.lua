-- Office monitor chrome, buttons, and tab selector.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.basePanel = Runtime.Ui.panel

    function Runtime.panel(rect, fill, border, radius, lineWidth)
        Runtime.basePanel(rect, fill, border, radius, lineWidth)
        if rect.width < 80 or rect.height < 32 then return end
        local inset = math.max(3, radius or 4)
        local innerWidth = rect.width - inset * 2
        local innerHeight = rect.height - inset * 2
        if innerWidth <= 2 or innerHeight <= 2 then return end
        love.graphics.setColor(0.82, 0.95, 0.91, 0.13)
        love.graphics.rectangle("fill", rect.x + inset, rect.y + 2, innerWidth, 1)
        love.graphics.rectangle("fill", rect.x + 2, rect.y + inset, 1, innerHeight)
        love.graphics.setColor(0.005, 0.018, 0.025, 0.24)
        love.graphics.rectangle("fill", rect.x + inset, rect.y + rect.height - 3, innerWidth, 1)
        love.graphics.rectangle("fill", rect.x + rect.width - 3, rect.y + inset, 1, innerHeight)
    end

    Runtime.COMPUTER_BUTTON_STYLES = {
        secondary = {
            edge = { 0.08, 0.15, 0.18, 1 }, face = { 0.57, 0.64, 0.66, 1 },
            highlight = { 0.96, 0.98, 0.92, 1 }, shadow = { 0.27, 0.36, 0.39, 1 },
            text = { 0.035, 0.105, 0.14, 1 },
        },
        hover = {
            edge = { 0.02, 0.20, 0.23, 1 }, face = { 0.24, 0.63, 0.63, 1 },
            highlight = { 0.69, 0.98, 0.91, 1 }, shadow = { 0.07, 0.29, 0.32, 1 },
            text = { 0.025, 0.10, 0.13, 1 },
        },
        primary = {
            edge = { 0.015, 0.105, 0.13, 1 }, face = { 0.025, 0.44, 0.46, 1 },
            highlight = { 0.47, 0.91, 0.85, 1 }, shadow = { 0.015, 0.20, 0.23, 1 },
            text = { 0.98, 0.99, 0.94, 1 },
        },
        primaryHover = {
            edge = { 0.015, 0.14, 0.16, 1 }, face = { 0.08, 0.60, 0.59, 1 },
            highlight = { 0.75, 1.00, 0.92, 1 }, shadow = { 0.025, 0.28, 0.29, 1 },
            text = { 1.00, 1.00, 0.97, 1 },
        },
        pressed = {
            edge = { 0.04, 0.09, 0.11, 1 }, face = { 0.31, 0.41, 0.44, 1 },
            highlight = { 0.17, 0.26, 0.29, 1 }, shadow = { 0.76, 0.84, 0.82, 1 },
            text = { 0.98, 0.99, 0.94, 1 },
        },
        primaryPressed = {
            edge = { 0.01, 0.075, 0.09, 1 }, face = { 0.015, 0.32, 0.34, 1 },
            highlight = { 0.01, 0.20, 0.22, 1 }, shadow = { 0.18, 0.63, 0.59, 1 },
            text = { 1.00, 1.00, 0.97, 1 },
        },
        dangerPressed = {
            edge = { 0.15, 0.04, 0.04, 1 }, face = { 0.40, 0.11, 0.10, 1 },
            highlight = { 0.24, 0.06, 0.05, 1 }, shadow = { 0.77, 0.34, 0.29, 1 },
            text = { 1.00, 0.98, 0.93, 1 },
        },
        disabled = {
            edge = { 0.08, 0.12, 0.14, 1 }, face = { 0.22, 0.28, 0.30, 1 },
            highlight = { 0.39, 0.47, 0.47, 1 }, shadow = { 0.12, 0.17, 0.18, 1 },
            text = { 0.76, 0.82, 0.79, 1 },
        },
        danger = {
            edge = { 0.19, 0.055, 0.05, 1 }, face = { 0.51, 0.15, 0.14, 1 },
            highlight = { 0.91, 0.49, 0.40, 1 }, shadow = { 0.29, 0.085, 0.075, 1 },
            text = { 0.99, 0.94, 0.90, 1 },
        },
        dangerHover = {
            edge = { 0.22, 0.07, 0.06, 1 }, face = { 0.69, 0.22, 0.18, 1 },
            highlight = { 1.00, 0.62, 0.49, 1 }, shadow = { 0.35, 0.10, 0.08, 1 },
            text = { 1.00, 0.98, 0.93, 1 },
        },
    }

    Runtime.buttonDrawPointerX, Runtime.buttonDrawPointerY = nil

    function Runtime.drawComputerButton(rect, label, styleName)
        local enabled = styleName ~= "disabled"
        local mouseHeld = Runtime.buttonDrawPointerX and Runtime.buttonDrawPointerY
            and Runtime.contains(rect, Runtime.buttonDrawPointerX, Runtime.buttonDrawPointerY)
            and love.mouse and love.mouse.isDown and love.mouse.isDown(1)
        local pressed = enabled and (mouseHeld or Runtime.Ui.pressWithin(rect, 0.12))
        if pressed then
            styleName = styleName and styleName:match("^primary") and "primaryPressed"
                or styleName and styleName:match("^danger") and "dangerPressed"
                or "pressed"
        end
        local style = Runtime.COMPUTER_BUTTON_STYLES[styleName] or Runtime.COMPUTER_BUTTON_STYLES.secondary
        local faceInset = pressed and 2 or 1
        love.graphics.setColor(style.edge)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 3, 3)
        love.graphics.setColor(style.face)
        love.graphics.rectangle("fill", rect.x + faceInset, rect.y + faceInset,
            rect.width - faceInset * 2, rect.height - faceInset * 2, 2, 2)
        love.graphics.setColor(style.highlight)
        love.graphics.rectangle("fill", rect.x + 3, rect.y + 2,
            math.max(1, rect.width - 6), 1)
        love.graphics.rectangle("fill", rect.x + 2, rect.y + 3,
            1, math.max(1, rect.height - 6))
        love.graphics.setColor(style.shadow)
        love.graphics.rectangle("fill", rect.x + 3, rect.y + rect.height - 3,
            math.max(1, rect.width - 6), 1)
        love.graphics.rectangle("fill", rect.x + rect.width - 3, rect.y + 3,
            1, math.max(1, rect.height - 6))

        if label ~= nil and label ~= "" then
            local text = tostring(label)
            local font = love.graphics.getFont()
            local textWidth, lineCount = 0, 0
            for line in (text .. "\n"):gmatch("(.-)\n") do
                textWidth = math.max(textWidth, font:getWidth(line))
                lineCount = lineCount + 1
            end
            local textHeight = font:getHeight() * lineCount
            local scale = math.min(1, (rect.width - 12) / math.max(1, textWidth),
                (rect.height - 6) / math.max(1, textHeight))
            love.graphics.setColor(style.text)
            love.graphics.print(text,
                rect.x + (rect.width - textWidth * scale) / 2,
                rect.y + (rect.height - textHeight * scale) / 2 + (pressed and 1 or 0),
                0, scale, scale)
        end
    end

    function Runtime.printCenteredFit(text, x, y, width)
        text = tostring(text or "")
        local font = love.graphics.getFont()
        local textWidth = font:getWidth(text)
        local scale = textWidth > width and width / textWidth or 1
        love.graphics.print(text, x + (width - textWidth * scale) / 2, y,
            0, scale, scale)
    end

    function Runtime.drawMonitorFrame(state,twelveHourTime)
        -- A thick CRT shell makes the software feel like it lives inside a real
        -- beige 1990s office monitor instead of floating over the warehouse.
        love.graphics.setColor(0.08, 0.075, 0.065, 1)
        love.graphics.rectangle("fill", Runtime.MONITOR.x + 8, Runtime.MONITOR.y + 10,
            Runtime.MONITOR.width, Runtime.MONITOR.height, 16, 16)
        love.graphics.setColor(0.63, 0.61, 0.54, 1)
        love.graphics.rectangle("fill", Runtime.MONITOR.x, Runtime.MONITOR.y,
            Runtime.MONITOR.width, Runtime.MONITOR.height, 16, 16)
        love.graphics.setColor(0.76, 0.74, 0.66, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", Runtime.MONITOR.x + 2, Runtime.MONITOR.y + 2,
            Runtime.MONITOR.width - 4, Runtime.MONITOR.height - 4, 14, 14)
        love.graphics.setColor(0.88, 0.86, 0.77, 1)
        love.graphics.line(Runtime.MONITOR.x + 16, Runtime.MONITOR.y + 8,
            Runtime.MONITOR.x + Runtime.MONITOR.width - 16, Runtime.MONITOR.y + 8)
        love.graphics.line(Runtime.MONITOR.x + 8, Runtime.MONITOR.y + 16,
            Runtime.MONITOR.x + 8, Runtime.MONITOR.y + Runtime.MONITOR.height - 16)
        love.graphics.setColor(0.27, 0.26, 0.23, 1)
        love.graphics.line(Runtime.MONITOR.x + 16, Runtime.MONITOR.y + Runtime.MONITOR.height - 8,
            Runtime.MONITOR.x + Runtime.MONITOR.width - 16, Runtime.MONITOR.y + Runtime.MONITOR.height - 8)
        love.graphics.line(Runtime.MONITOR.x + Runtime.MONITOR.width - 8, Runtime.MONITOR.y + 16,
            Runtime.MONITOR.x + Runtime.MONITOR.width - 8, Runtime.MONITOR.y + Runtime.MONITOR.height - 16)
        love.graphics.setColor(0.04, 0.045, 0.045, 1)
        love.graphics.rectangle("fill", Runtime.PANEL.x - 8, Runtime.PANEL.y - 8,
            Runtime.PANEL.width + 16, Runtime.PANEL.height + 16, 9, 9)
        love.graphics.setColor(0.31, 0.32, 0.30, 1)
        love.graphics.rectangle("line", Runtime.PANEL.x - 5, Runtime.PANEL.y - 5,
            Runtime.PANEL.width + 10, Runtime.PANEL.height + 10, 7, 7)

        -- Small slotted fasteners make the bezel read as assembled hardware while
        -- staying clear of the fixed screen and its controls.
        for index = 1, 4 do
            local screwX = index % 2 == 1 and 28 or 932
            local screwY = index <= 2 and 20 or 656
            love.graphics.setColor(0.22, 0.21, 0.18, 1)
            love.graphics.circle("fill", screwX, screwY, 6)
            love.graphics.setColor(0.80, 0.79, 0.72, 1)
            love.graphics.circle("fill", screwX, screwY, 4.5)
            love.graphics.setColor(0.43, 0.43, 0.39, 1)
            love.graphics.circle("line", screwX, screwY, 4.5)
            love.graphics.setColor(0.28, 0.29, 0.28, 1)
            love.graphics.line(screwX - 2.5, screwY - 1,
                screwX + 2.5, screwY + 1)
            love.graphics.setColor(0.96, 0.94, 0.86, 0.8)
            love.graphics.line(screwX - 2, screwY - 2,
                screwX + 1.5, screwY - 0.5)
        end

        love.graphics.setColor(0.22, 0.21, 0.18, 1)
        for index = 1, 3 do
            local ventY = 648 + (index - 1) * 5
            love.graphics.rectangle("fill", 58, ventY, 94, 3, 1, 1)
            love.graphics.setColor(0.91, 0.88, 0.79, 0.75)
            love.graphics.line(61, ventY, 149, ventY)
            love.graphics.setColor(0.22, 0.21, 0.18, 1)
        end
        love.graphics.setColor(0.18, 0.19, 0.17, 1)
        love.graphics.circle("fill", 876, 655, 6)
        love.graphics.setColor(0.06, 0.25, 0.14, 1)
        love.graphics.circle("fill", 876, 655, 4)
        love.graphics.setColor(0.26, 0.92, 0.48, 1)
        love.graphics.circle("fill", 876, 655, 2.5)
        love.graphics.setColor(0.24, 0.23, 0.20, 1)
        love.graphics.print("CRITTERWORKS CRT-17", 374, 649)
        local displayDate = Runtime.BusinessCalendar.shortDate(state):gsub("%s+W%d+$", "")
        love.graphics.printf(displayDate, 646, 649, 132, "right")
        love.graphics.setColor(0.025, 0.055, 0.045, 1)
        love.graphics.rectangle("fill", 785, 646, 76, 20, 3, 3)
        love.graphics.setColor(0.35, 0.49, 0.41, 1)
        love.graphics.rectangle("line", 785, 646, 76, 20, 3, 3)
        love.graphics.setColor(0.52, 0.98, 0.65, 1)
        love.graphics.printf(Runtime.BusinessCalendar.timeText(state,twelveHourTime), 788, 648, 70, "center")
    end

    function Runtime.drawTabSelector(state, pointerX, pointerY)
        love.graphics.setColor(0.72, 0.72, 0.68, 1)
        love.graphics.rectangle("fill", Runtime.TAB_ADDRESS.x, Runtime.TAB_ADDRESS.y,
            Runtime.TAB_ADDRESS.width, Runtime.TAB_ADDRESS.height)
        love.graphics.setColor(0.97, 0.97, 0.92, 1)
        love.graphics.line(Runtime.TAB_ADDRESS.x, Runtime.TAB_ADDRESS.y,
            Runtime.TAB_ADDRESS.x + Runtime.TAB_ADDRESS.width, Runtime.TAB_ADDRESS.y)
        love.graphics.line(Runtime.TAB_ADDRESS.x, Runtime.TAB_ADDRESS.y,
            Runtime.TAB_ADDRESS.x, Runtime.TAB_ADDRESS.y + Runtime.TAB_ADDRESS.height)
        love.graphics.setColor(0.25, 0.26, 0.25, 1)
        love.graphics.line(Runtime.TAB_ADDRESS.x, Runtime.TAB_ADDRESS.y + Runtime.TAB_ADDRESS.height,
            Runtime.TAB_ADDRESS.x + Runtime.TAB_ADDRESS.width, Runtime.TAB_ADDRESS.y + Runtime.TAB_ADDRESS.height)
        love.graphics.setColor(0.035, 0.12, 0.15, 1)
        love.graphics.rectangle("fill", Runtime.TAB_ADDRESS.x + 7, Runtime.TAB_ADDRESS.y + 8,
            Runtime.TAB_ADDRESS.width - 14, Runtime.TAB_ADDRESS.height - 15)
        love.graphics.setColor(0.76, 0.94, 0.90, 1)
        love.graphics.print(Runtime.ComputerScreen.activeUrl(), Runtime.TAB_ADDRESS.x + 15, Runtime.TAB_ADDRESS.y + 14)

        local hovered = pointerX and Runtime.contains(Runtime.TAB_DROPDOWN_ARROW, pointerX, pointerY)
        Runtime.drawComputerButton(Runtime.TAB_DROPDOWN_ARROW, nil,
            Runtime.ComputerScreen.tabDropdownOpen and "primary" or hovered and "hover" or "secondary")
        love.graphics.setColor(Runtime.ComputerScreen.tabDropdownOpen
            and { 0.98, 0.99, 0.94, 1 } or { 0.035, 0.105, 0.14, 1 })
        love.graphics.polygon("fill", Runtime.TAB_DROPDOWN_ARROW.x + 13,
            Runtime.TAB_DROPDOWN_ARROW.y + (Runtime.ComputerScreen.tabDropdownOpen and 25 or 15),
            Runtime.TAB_DROPDOWN_ARROW.x + 27,
            Runtime.TAB_DROPDOWN_ARROW.y + (Runtime.ComputerScreen.tabDropdownOpen and 25 or 15),
            Runtime.TAB_DROPDOWN_ARROW.x + 20,
            Runtime.TAB_DROPDOWN_ARROW.y + (Runtime.ComputerScreen.tabDropdownOpen and 14 or 26))
        if Runtime.tabUnreadCount(state, "email") + Runtime.tabUnreadCount(state, "estimating") > 0 then
            love.graphics.setColor(0.92, 0.22, 0.12, 1)
            love.graphics.circle("fill", Runtime.TAB_DROPDOWN_ARROW.x + 32,
                Runtime.TAB_DROPDOWN_ARROW.y + 8, 5)
        end

        if not Runtime.ComputerScreen.tabDropdownOpen then return end
        for index, tab in ipairs(Runtime.visibleTabs()) do
            local rect = Runtime.tabDropdownRect(index)
            local selected = Runtime.ComputerScreen.tab == tab.id
            local itemHovered = pointerX and Runtime.contains(rect, pointerX, pointerY)
            Runtime.drawComputerButton(rect, nil,
                selected and "primary" or itemHovered and "hover" or "secondary")
            if selected then
                love.graphics.setColor(0.53, 0.98, 0.84, 1)
                love.graphics.rectangle("fill", rect.x + 4, rect.y + 7, 2, rect.height - 14)
            end
            local foreground = itemHovered and { 0.025, 0.10, 0.13, 1 }
                or { 0.035, 0.105, 0.14, 1 }
            if selected then foreground = { 0.98, 0.99, 0.94, 1 } end
            love.graphics.setColor(foreground)
            local textY = rect.y + (rect.height - love.graphics.getFont():getHeight()) / 2
            love.graphics.print(tab.label, rect.x + 14, textY)
            local unread = Runtime.tabUnreadCount(state, tab.id)
            if unread > 0 then
                local badge = { x = rect.x + 130, y = rect.y + 6, width = 32, height = 21 }
                love.graphics.setColor(0.82, 0.22, 0.12, 1)
                love.graphics.rectangle("fill", badge.x, badge.y, badge.width, badge.height, 5, 5)
                love.graphics.setColor(1, 0.97, 0.91, 1)
                love.graphics.printf(unread > 9 and "9+" or tostring(unread), badge.x,
                    badge.y + (badge.height - love.graphics.getFont():getHeight()) / 2,
                    badge.width, "center")
            end
            love.graphics.setColor(selected and { 0.78, 0.95, 0.89, 1 }
                or itemHovered and { 0.035, 0.12, 0.15, 1 }
                or { 0.22, 0.31, 0.34, 1 })
            love.graphics.printf(tab.url, rect.x + 168, textY,
                rect.width - 182, "right")
        end
    end
end

return Component
