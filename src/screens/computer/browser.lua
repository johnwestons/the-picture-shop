-- Interactive controls aligned with the CritterNet browser artwork.
local Component = {}

function Component.install(Runtime)
    local screen = Runtime.ComputerScreen
    Runtime.BROWSER_BUTTONS = {
        {id="back", label="Back", x=121, y=83, width=49, height=40},
        {id="forward", label="Forward", x=171, y=83, width=49, height=40},
        {id="home", label="Home page", x=235, y=83, width=47, height=40},
        {id="directory", label="CritterNet menu", x=283, y=83, width=47, height=40},
        {id="search", label="Find a page or supplier", x=331, y=83, width=47, height=40},
        {id="favorites", label="Favorites", x=379, y=83, width=47, height=40},
        {id="email", label="Email", x=431, y=83, width=46, height=40},
        {id="address_paw", label="CritterNet menu", x=121, y=137, width=48, height=41},
        {id="www", label="Online suppliers", x=697, y=137, width=42, height=42},
        {id="status_paw", label="CritterNet menu", x=116, y=601, width=47, height=36},
        {id="clock", label="Shop clock", x=Runtime.BEZEL_CLOCK.x, y=Runtime.BEZEL_CLOCK.y,
            width=Runtime.BEZEL_CLOCK.width, height=Runtime.BEZEL_CLOCK.height},
    }
    Runtime.BROWSER_PANEL = {x=170, y=184, width=518, height=444}
    Runtime.BROWSER_CLOSE = {x=630, y=194, width=44, height=30}
    Runtime.BROWSER_FIELD = {x=186, y=236, width=486, height=40}
    Runtime.BROWSER_PREVIOUS = {x=186, y=587, width=82, height=30}
    Runtime.BROWSER_NEXT = {x=590, y=587, width=82, height=30}
    local pageSize = 6
    screen.browserHistory, screen.browserHistoryIndex = {}, 0
    screen.browserFavorites = {}
    screen.browserQuery, screen.browserPage = "", 1

    -- Store view state, never business data or actions that would be replayed.
    local viewFields = {"tab", "wwwSite", "cartOpen", "cartPage", "machinePage",
        "financialSection", "selectedJobId", "selectedEmailId", "emailPage", "emailFolder",
        "emailSelectionRequired", "calendarYear", "calendarMonth", "calendarSelectedDay",
        "calendarDayOpen", "calendarDayScroll", "retailPage", "warehouseGamesPage",
        "warehouseStagingPage","receiptFilter","receiptPage","receiptDetailPage","selectedReceiptId"}
    local function snapshot()
        local entry = {}
        for _, key in ipairs(viewFields) do entry[key] = screen[key] end
        entry.pages = {}
        for key, value in pairs(screen.pages) do entry.pages[key] = value end
        return entry
    end
    local function routeKey(entry)
        return tostring(entry.tab) .. (entry.tab == "www"
            and (":" .. tostring(entry.wwwSite) .. ":" .. tostring(entry.cartOpen == true))
            or entry.tab == "financials" and (":" .. tostring(entry.financialSection)) or "")
    end
    local function syncHistory()
        local history, index = screen.browserHistory, screen.browserHistoryIndex
        local current = snapshot()
        if index == 0 or routeKey(history[index]) ~= routeKey(current) then
            for n = #history, index + 1, -1 do history[n] = nil end
            history[#history + 1] = current
            screen.browserHistoryIndex = #history
        else history[index] = current end
    end
    function Runtime.closeBrowserOverlay()
        screen.browserOverlay, screen.browserSearchFocused = nil, false
        screen.tabDropdownOpen = false
    end
    function screen.dismissBrowserOverlay()
        if not screen.browserOverlay and not screen.tabDropdownOpen then return false end
        Runtime.closeBrowserOverlay()
        return true
    end
    function Runtime.browserButtonVisible(button)
        return button.id ~= "status_paw" or screen.tab == "active"
            or screen.tab == "completed" or screen.tab == "deliveries"
    end
    function Runtime.browserButtons()
        return Runtime.BROWSER_BUTTONS
    end
    local function clearFocus()
        screen.quoteFocused, screen.deliveryQuoteFocused, screen.promoFocused = false, false, false
        screen.warehouseStagingDrag = nil
    end
    local function restore(state, entry)
        Runtime.closeBrowserOverlay()
        clearFocus()
        screen.promoJobId, screen.warehouseConfirmation, screen.creditConfirmation = nil, nil, nil
        screen.warehouseStagingDrag = nil
        for _, key in ipairs(viewFields) do screen[key] = entry[key] end
        screen.pages = {}
        for key, value in pairs(entry.pages or {}) do screen.pages[key] = value end
        Runtime.ensureSelection(state)
        local emailRead = false
        if screen.tab == "email" or screen.tab == "estimating" then
            emailRead = Runtime.markEmailRead(state, Runtime.selectedEmail(state))
            if screen.tab == "estimating" then Runtime.resetQuoteText(state) end
        end
        return {action="tab", tab=screen.tab, emailRead=emailRead}
    end
    function screen.browserCanGo(direction)
        local index = screen.browserHistoryIndex + direction
        return index >= 1 and index <= #screen.browserHistory
    end
    function screen.browserGo(state, direction)
        syncHistory()
        if not screen.browserCanGo(direction) then return {action="browser_history_end"} end
        screen.browserHistoryIndex = screen.browserHistoryIndex + direction
        return restore(state, screen.browserHistory[screen.browserHistoryIndex])
    end
    function Runtime.browserNavigate(state, entry)
        syncHistory()
        local result
        if entry.pages then result = restore(state, entry)
        else
            local tab = Runtime.tabById(entry.tab)
            if not tab then return {action="blocked"} end
            Runtime.closeBrowserOverlay()
            clearFocus()
            screen.promoJobId = nil
            result = Runtime.activateTab(state, tab)
            if entry.wwwSite then
                screen.wwwSite, screen.wwwSiteChangedAt = entry.wwwSite, love.timer.getTime()
            end
        end
        syncHistory()
        return result
    end
    function Runtime.browserPageLabel(entry)
        if entry.tab == "www" then
            local site = Runtime.WWW_SITES[entry.wwwSite or 1]
            return site.name .. (entry.cartOpen and " / CART" or "")
        end
        for _, tab in ipairs(Runtime.visibleTabs()) do
            if tab.id == entry.tab then return tab.label end
        end
        return "CRITTERNET"
    end
    function Runtime.browserFavoriteIndex()
        local current = routeKey(screen)
        for index, entry in ipairs(screen.browserFavorites) do
            if routeKey(entry) == current then return index end
        end
    end
    function Runtime.browserResults()
        if screen.browserOverlay == "favorites" then
            local visible = {}
            for _, entry in ipairs(screen.browserFavorites) do
                if Runtime.tabById(entry.tab) then visible[#visible + 1] = entry end
            end
            return visible
        end
        local results, query = {}, screen.browserQuery:lower()
        local function add(entry, text)
            if text:lower():find(query, 1, true) then results[#results + 1] = entry end
        end
        for _, tab in ipairs(Runtime.visibleTabs()) do
            add({tab=tab.id, label=tab.label, url=tab.url}, tab.label .. " " .. tab.url)
        end
        for index, site in ipairs(Runtime.WWW_SITES) do
            local words = site.name .. " " .. site.short .. " " .. site.url
            if site.categoryIndex then
                for _, item in ipairs(Runtime.Procurement.category(site.categoryIndex).items) do
                    words = words .. " " .. item.name
                end
            elseif site.kind=="vehicles" then
                local dealer=require('src.vehicle_dealer')
                for _,listingId in ipairs(dealer.ORDER) do
                    local listing=dealer.listing(listingId)
                    words=words.." "..listing.name.." "..listing.description
                end
            end
            add({tab="www", wwwSite=index, label=site.name, url=site.url}, words)
        end
        return results
    end
    function Runtime.browserResultRect(row)
        return {x=186, y=287+(row-1)*48, width=486, height=43}
    end
    function Runtime.browserResultPages()
        local results = Runtime.browserResults()
        local maximum = math.max(1, math.ceil(#results/pageSize))
        screen.browserPage = math.max(1, math.min(screen.browserPage, maximum))
        return results, maximum
    end
    function screen.browserControlCenter(id)
        local controls = {field=Runtime.BROWSER_FIELD, close=Runtime.BROWSER_CLOSE,
            previous=Runtime.BROWSER_PREVIOUS, next=Runtime.BROWSER_NEXT, address=Runtime.TAB_ADDRESS}
        local rect = controls[id]
        for _, button in ipairs(Runtime.browserButtons()) do if button.id == id then rect = button end end
        if rect then return rect.x+rect.width/2, rect.y+rect.height/2 end
    end
    function screen.browserResultCenter(row)
        local rect = Runtime.browserResultRect(row)
        return rect.x+rect.width/2, rect.y+rect.height/2
    end
    local function toggleOverlay(kind)
        local open = screen.browserOverlay ~= kind
        Runtime.closeBrowserOverlay()
        clearFocus()
        if open then
            screen.browserOverlay, screen.browserPage = kind, 1
            screen.browserSearchFocused = kind == "search"
            if kind == "search" then screen.browserQuery = "" end
        end
        return {action=open and "browser_opened" or "browser_closed"}
    end
    local function toggleDirectory()
        local open = not screen.tabDropdownOpen
        Runtime.closeBrowserOverlay()
        clearFocus()
        screen.tabDropdownOpen = open
        return {action=open and "dropdown_opened" or "dropdown_closed"}
    end
    local function browserPointer(state, x, y)
        if Runtime.contains(Runtime.CLOSE, x, y) then Runtime.closeBrowserOverlay(); return {action="close"} end
        if Runtime.contains(Runtime.TAB_ADDRESS, x, y) or Runtime.contains(Runtime.TAB_DROPDOWN_ARROW, x, y) then
            return toggleDirectory()
        end
        if Runtime.contains(Runtime.BROWSER_BUTTONS[#Runtime.BROWSER_BUTTONS],x,y) then
            return Runtime.browserNavigate(state,{tab="clock"})
        end
        for _, button in ipairs(Runtime.browserButtons()) do
            -- The bottom paw is behind the page content on some views.
            local covered = button.id == "status_paw" and (screen.browserOverlay or screen.tabDropdownOpen)
            if not covered and Runtime.browserButtonVisible(button) and Runtime.contains(button, x, y) then
                local id = button.id
                if id == "back" or id == "forward" then return screen.browserGo(state, id == "back" and -1 or 1)
                elseif id == "search" or id == "favorites" then return toggleOverlay(id)
                elseif id == "directory" or id == "address_paw" or id == "status_paw" then return toggleDirectory()
                elseif id == "home" then
                    if Runtime.resetHomeView then Runtime.resetHomeView() end
                    return Runtime.browserNavigate(state, {tab=screen.browserHomeTab or "active"})
                elseif id == "www" then return Runtime.browserNavigate(state, {tab="www", wwwSite=1})
                else return Runtime.browserNavigate(state, {tab=id}) end
            end
        end
        if not screen.browserOverlay then return nil end
        if Runtime.contains(Runtime.BROWSER_CLOSE, x, y) or not Runtime.contains(Runtime.BROWSER_PANEL, x, y) then
            Runtime.closeBrowserOverlay()
            return {action="browser_closed"}
        end
        screen.browserSearchFocused = screen.browserOverlay == "search" and Runtime.contains(Runtime.BROWSER_FIELD, x, y)
        if Runtime.contains(Runtime.BROWSER_FIELD, x, y) then
            if screen.browserOverlay == "favorites" then
                local index = Runtime.browserFavoriteIndex()
                if index then table.remove(screen.browserFavorites, index)
                else
                    local entry = snapshot()
                    entry.label, entry.url = Runtime.browserPageLabel(entry), screen.activeUrl()
                    screen.browserFavorites[#screen.browserFavorites+1] = entry
                end
                return {action="browser_favorite_changed"}
            end
            return {action="browser_search_focus"}
        end
        local results, maximum = Runtime.browserResultPages()
        if Runtime.contains(Runtime.BROWSER_PREVIOUS, x, y) then screen.browserPage = math.max(1,screen.browserPage-1)
        elseif Runtime.contains(Runtime.BROWSER_NEXT, x, y) then screen.browserPage = math.min(maximum,screen.browserPage+1)
        else
            for row=1,pageSize do
                local entry = results[(screen.browserPage-1)*pageSize+row]
                if entry and Runtime.contains(Runtime.browserResultRect(row), x, y) then
                    return Runtime.browserNavigate(state, entry)
                end
            end
        end
        return {action="browser_page"}
    end

    local enter, mousepressed = screen.enter, screen.mousepressed
    function screen.enter(state)
        enter(state)
        screen.browserHomeTab = screen.tab
        screen.browserHistory, screen.browserHistoryIndex = {}, 0
        screen.browserQuery, screen.browserPage = "", 1
        Runtime.closeBrowserOverlay()
        syncHistory()
    end
    function screen.mousepressed(state, x, y, button)
        if button ~= 1 then return nil end
        syncHistory()
        local result = browserPointer(state, x, y)
        if result then return result end
        result = mousepressed(state, x, y, button)
        syncHistory()
        return result
    end
    local keypressed, textinput, wantsTextInput = screen.keypressed, screen.textinput, screen.wantsTextInput
    function screen.keypressed(state, key)
        if screen.browserOverlay then
            if key == "escape" or key == "back" then Runtime.closeBrowserOverlay()
            elseif screen.browserOverlay == "search" then
                if key == "return" or key == "kpenter" then
                    local results = Runtime.browserResults()
                    local entry = results[(screen.browserPage-1)*pageSize+1]
                    if entry then return Runtime.browserNavigate(state, entry) end
                elseif key == "backspace" and screen.browserSearchFocused then
                    local offset = Runtime.utf8.offset(screen.browserQuery, -1)
                    screen.browserQuery = offset and screen.browserQuery:sub(1, offset-1) or ""
                    screen.browserPage = 1
                end
            end
            return true
        end
        if screen.tabDropdownOpen and (key == "escape" or key == "back") then
            Runtime.closeBrowserOverlay(); return true
        end
        return keypressed(state, key)
    end
    function screen.textinput(state, text)
        if screen.browserOverlay then
            if screen.browserSearchFocused then
                for _, codepoint in Runtime.utf8.codes(text) do
                    if codepoint >= 32 and codepoint ~= 127 and Runtime.utf8.len(screen.browserQuery) < 64 then
                        screen.browserQuery = screen.browserQuery .. Runtime.utf8.char(codepoint)
                    end
                end
                screen.browserPage = 1
            end
            return true
        end
        return textinput(state, text)
    end
    function screen.wantsTextInput()
        if screen.browserOverlay then return screen.browserSearchFocused == true end
        return wantsTextInput()
    end
    local wheelmoved = screen.wheelmoved
    function screen.wheelmoved(state, x, y)
        if screen.browserOverlay then
            local _, maximum = Runtime.browserResultPages()
            screen.browserPage = math.max(1,math.min(maximum,screen.browserPage-(y > 0 and 1 or y < 0 and -1 or 0)))
            return true
        end
        if screen.tabDropdownOpen then return true end
        return wheelmoved and wheelmoved(state, x, y) or false
    end
end

return Component
