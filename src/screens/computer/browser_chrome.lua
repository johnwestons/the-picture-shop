-- Feedback and popups for the controls embedded in the browser sprite.
local Component = {}

function Component.install(Runtime)
    local screen = Runtime.ComputerScreen
    local Text = require("src.screens.typography")
    function Runtime.drawBrowserToolbar(pointerX, pointerY)
        local hoveredButton
        local buttons = Runtime.browserButtons()
        if buttons[1] and buttons[1].compact then
            Runtime.panel({x=buttons[1].x-4,y=buttons[1].y-4,width=518,height=92},
                {.035,.055,.065,.995},{.31,.56,.58,1},4,1)
            love.graphics.setFont(Text.get(14))
        end
        for _, button in ipairs(buttons) do
            local enabled = button.id ~= "back" and button.id ~= "forward"
                or screen.browserCanGo(button.id == "back" and -1 or 1)
            local visible = Runtime.browserButtonVisible(button)
            local hovered = visible and pointerX and Runtime.contains(button, pointerX, pointerY)
            if button.compact then
                Runtime.drawComputerButton(button,button.label,not enabled and "disabled" or hovered and "hover" or "secondary")
            elseif visible and (button.id == "back" or button.id == "forward") then
                Runtime.drawComputerButton(button, nil, not enabled and "disabled" or hovered and "hover" or "secondary")
                local x, y, direction = button.x+button.width/2, button.y+button.height/2, button.id == "back" and -1 or 1
                love.graphics.setColor(enabled and .04 or .55, enabled and .27 or .61, enabled and .33 or .61, 1)
                love.graphics.polygon("fill", x+direction*10,y, x,y-8, x,y-4,
                    x-direction*9,y-4, x-direction*9,y+4, x,y+4, x,y+8)
            elseif hovered then
                local pressed = love.mouse.isDown(1) or Runtime.Ui.pressWithin(button, .12)
                love.graphics.setColor(.18, .88, .83, pressed and .40 or .18)
                love.graphics.rectangle("fill", button.x+2, button.y+2, button.width-4, button.height-4)
                love.graphics.setColor(.55, 1, .91, .9)
                love.graphics.rectangle("line", button.x+1, button.y+1, button.width-2, button.height-2)
            end
            if hovered and not button.compact then
                hoveredButton = {rect=button, text=button.label .. (not enabled and " (no history)" or "")}
            end
        end
        if hoveredButton then
            local rect, label = hoveredButton.rect, hoveredButton.text
            love.graphics.setFont(Text.get(12))
            local width = love.graphics.getFont():getWidth(label)+16
            local x = math.min(890-width, math.max(70, rect.x))
            local y = rect.y > 580 and rect.y-25 or rect.y+rect.height+3
            Runtime.panel({x=x,y=y,width=width,height=22},{.02,.08,.10,.98},{.40,.70,.67,1},2)
            love.graphics.setColor(.9,.98,.94,1)
            love.graphics.print(label,x+8,y+4)
        end
    end

    function Runtime.drawBrowserOverlay(pointerX, pointerY)
        if not screen.browserOverlay then return end
        local search = screen.browserOverlay == "search"
        local results, maximum = Runtime.browserResultPages()
        Runtime.panel(Runtime.BROWSER_PANEL,{.035,.055,.065,.995},{.31,.56,.58,1},4,1)
        love.graphics.setFont(Text.get(16, "bold"))
        love.graphics.setColor(.76,.94,.90,1)
        love.graphics.print(search and "FIND ON CRITTERNET" or "FAVORITES",186,201)
        love.graphics.setFont(Text.get(14))
        local function button(rect,label,enabled)
            local hovered = pointerX and Runtime.contains(rect,pointerX,pointerY)
            Runtime.drawComputerButton(rect,label,enabled == false and "disabled" or hovered and "hover" or "secondary")
        end
        button(Runtime.BROWSER_CLOSE,"X")
        local field = Runtime.BROWSER_FIELD
        if search then
            Runtime.panel(field,{.02,.10,.12,1},screen.browserSearchFocused and {.50,.98,.84,1} or {.31,.56,.58,1},2)
            love.graphics.setColor(.76,.94,.90,1)
            local value = screen.browserQuery
            -- Keep the typed end and caret visible without changing the query.
            while love.graphics.getFont():getWidth(value .. "|") > field.width-24 do
                local offset = Runtime.utf8.offset(value,2)
                value = offset and value:sub(offset) or ""
            end
            if value == "" and not screen.browserSearchFocused then value = "Page, supplier, or supply name" end
            love.graphics.print(value .. (screen.browserSearchFocused and "|" or ""),field.x+12,field.y+12)
        else
            button(field,Runtime.browserFavoriteIndex() and "REMOVE THIS PAGE FROM FAVORITES" or "SAVE THIS PAGE TO FAVORITES")
        end
        for row=1,6 do
            local entry = results[(screen.browserPage-1)*6+row]
            if entry then
                local rect = Runtime.browserResultRect(row)
                button(rect,"")
                love.graphics.setColor(.035,.105,.14,1)
                love.graphics.setFont(Text.get(14,"bold"))
                love.graphics.print(Text.ellipsize(entry.label or Runtime.browserPageLabel(entry),rect.width-20),rect.x+10,rect.y+4)
                love.graphics.setFont(Text.get(12))
                love.graphics.print(Text.ellipsize(entry.url or "",rect.width-20),rect.x+10,rect.y+24)
                love.graphics.setFont(Text.get(14))
            end
        end
        if #results == 0 then
            love.graphics.setColor(.72,.82,.82,1)
            love.graphics.printf(search and "No matching pages or suppliers.\nTry another name."
                or "Save the current page above.\nFavorites stay available during this session.",206,358,446,"center")
        end
        button(Runtime.BROWSER_PREVIOUS,"PREV",screen.browserPage>1)
        button(Runtime.BROWSER_NEXT,"NEXT",screen.browserPage<maximum)
        love.graphics.setColor(.72,.85,.84,1)
        love.graphics.printf(string.format("%d results  /  %d of %d",#results,screen.browserPage,maximum),278,596,302,"center")
    end
end

return Component
