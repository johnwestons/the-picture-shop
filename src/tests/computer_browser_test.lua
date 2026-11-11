local Test = {}

function Test.run(context, check)
    require('src.tests.computer_job_review_test').run(context,check)
    local state = context.State.new()
    local screen = context.computerScreen.new({warehouseEnabled=true})
    screen.enter(state)
    local function click(id)
        local x, y = screen.browserControlCenter(id)
        assert(x, id)
        return screen.mousepressed(state, x, y, 1)
    end
    local function selectTab(id)
        if not screen.tabDropdownOpen then click("address") end
        local x,y = screen.tabCenter(id)
        return screen.mousepressed(state,x,y,1)
    end
    local function firstResult()
        local x,y = screen.browserResultCenter(1)
        return screen.mousepressed(state,x,y,1)
    end
    local function capture(name, width, height)
        local output = os.getenv("PICTURE_SHOP_BROWSER_CAPTURE")
        if not output then return end
        local g = love.graphics
        local canvas = g.newCanvas(width,height)
        g.push("all");g.setCanvas({canvas,stencil=true});g.clear(.02,.03,.04,1)
        local scale = math.min(width/960,height/678)
        g.translate((width-960*scale)/2,(height-678*scale)/2);g.scale(scale)
        screen.draw(state,nil,nil,context.assets,true)
        g.pop()
        local data = canvas:newImageData()
        local png = data:encode("png")
        local file = assert(io.open(output.."/"..name..".png","wb"))
        file:write(png:getString());file:close()
        png:release();data:release();canvas:release()
    end
    check("browser_history_starts_disabled",not screen.browserCanGo(-1) and not screen.browserCanGo(1))
    check("browser_back_at_start_keeps_page",click("back").action=="browser_history_end" and screen.tab=="active")
    for index, point in ipairs({{171,137},{409,156},{647,175},{668,156}}) do
        check("browser_full_address_opens_"..index,screen.mousepressed(state,point[1],point[2],1).action=="dropdown_opened")
        check("browser_full_address_toggles_"..index,screen.mousepressed(state,point[1],point[2],1).action=="dropdown_closed")
    end
    screen.mousepressed(state,400,156,2)
    check("browser_right_click_ignored",not screen.tabDropdownOpen)
    for _, id in ipairs({"directory","address_paw","status_paw"}) do
        check("browser_paw_menu_"..id,click(id).action=="dropdown_opened")
        click(id)
    end
    selectTab("hiring");selectTab("calendar")
    screen.calendarMonth,screen.calendarSelectedDay = 6,12
    selectTab("financials")
    click("back")
    check("browser_back_restores_calendar_view",screen.tab=="calendar" and screen.calendarMonth==6 and screen.calendarSelectedDay==12)
    click("forward")
    check("browser_forward_returns_to_page",screen.tab=="financials" and not screen.browserCanGo(1))
    click("back");click("email")
    check("browser_new_navigation_discards_forward",screen.tab=="email" and not screen.browserCanGo(1))
    local count = #screen.browserHistory
    click("email")
    check("browser_same_page_does_not_duplicate_history",#screen.browserHistory==count)
    click("home")
    check("browser_home_returns_to_start",screen.tab=="active")
    click("www")
    check("browser_globe_opens_suppliers",screen.tab=="www" and screen.wwwSite==1)
    local x,y = screen.wwwSiteCenter(4)
    screen.mousepressed(state,x,y,1)
    click("back")
    check("browser_back_tracks_supplier_sites",screen.tab=="www" and screen.wwwSite==1)
    click("forward")
    check("browser_forward_tracks_supplier_sites",screen.wwwSite==4 and screen.activeUrl():find("/tools",1,true)~=nil)
    screen.cart={{name="Test item",quantity=2,price=100}}
    x,y=screen.cartButtonCenter();screen.mousepressed(state,x,y,1)
    click("back")
    check("browser_back_closes_cart_without_losing_items",not screen.cartOpen and #screen.cart==1 and screen.cart[1].quantity==2)
    click("forward")
    check("browser_forward_restores_cart",screen.cartOpen and #screen.cart==1)
    click("home");click("back")
    capture("toolbar-history",960,678)
    click("search")
    check("browser_find_requests_text_input",screen.browserOverlay=="search" and screen.wantsTextInput())
    screen.textinput(state,"HIRING")
    check("browser_find_opens_matching_page",firstResult().tab=="hiring" and screen.tab=="hiring" and not screen.wantsTextInput())
    click("search");screen.textinput(state,"pallet jack")
    firstResult()
    check("browser_find_supply_opens_supplier",screen.tab=="www" and screen.wwwSite==4)
    click("search");screen.textinput(state,"does not exist")
    firstResult()
    check("browser_no_results_does_not_navigate",screen.tab=="www" and screen.browserOverlay=="search")
    capture("search-no-results",960,678)
    click("close");click("search");screen.textinput(state,"é")
    screen.keypressed(state,"backspace")
    check("browser_find_backspace_keeps_valid_utf8",screen.browserQuery=="")
    screen.textinput(state,string.rep("a",100))
    check("browser_find_caps_query_length",#screen.browserQuery==64)
    click("close");click("search");screen.textinput(state,"calendar")
    local result=screen.keypressed(state,"return")
    check("browser_find_enter_opens_result",result.tab=="calendar" and not screen.browserOverlay)
    click("search")
    click("next")
    check("browser_find_paginates",screen.browserPage==2)
    screen.wheelmoved(state,0,1)
    check("browser_find_wheel_paginates",screen.browserPage==1)
    screen.textinput(state,"shop") -- Click the input to restore focus after paging.
    check("browser_find_unfocused_field_ignores_typing",screen.browserQuery=="")
    click("field");screen.textinput(state,"shop")
    capture("search-desktop",960,678)
    capture("search-phone",832,384)
    local inputContext={state=state,computerScreen=screen}
    state.screen="computer"
    check("browser_escape_dismisses_popup_first",context.input.keypressed("escape",inputContext)
        and not screen.browserOverlay and state.screen=="computer" and not screen.wantsTextInput())
    click("address")
    check("browser_escape_dismisses_directory",context.input.keypressed("escape",inputContext) and not screen.tabDropdownOpen)
    click("favorites");click("field")
    check("browser_favorites_adds_current_page",#screen.browserFavorites==1 and screen.browserFavorites[1].tab=="calendar")
    click("close");click("home");click("favorites")
    capture("favorites-desktop",960,678)
    firstResult()
    check("browser_favorite_opens_saved_page",screen.tab=="calendar" and not screen.browserOverlay)
    click("favorites");click("field")
    check("browser_favorites_removes_current_page",#screen.browserFavorites==0)
    click("search");click("address")
    check("browser_address_replaces_search",screen.tabDropdownOpen and not screen.browserOverlay and not screen.wantsTextInput())
    selectTab("financials")
    click("search")
    screen.mousepressed(state,96,260,1)
    check("browser_outside_click_dismisses_without_page_action",not screen.browserOverlay and screen.tab=="financials")
    click("clock")
    check("browser_bezel_clock_opens_clock",screen.tab=="clock")
    click("home")
    screen.mousepressed(state,800,120,1)
    check("browser_decorative_header_has_no_hidden_clock_hit",screen.tab=="active")
    screen.enter(state)
    capture("toolbar-initial",960,678)
    check("browser_reenter_resets_history",#screen.browserHistory==1 and not screen.browserCanGo(-1))
    local notice={id="BROWSER-NOTICE",unread=true,subject="Browser test",body="Test notice"}
    state.clientEmails.inbox={notice}
    local saved=0
    inputContext.saveCurrent=function()saved=saved+1 end
    click("search");screen.textinput(state,"EMAIL")
    context.input.keypressed("return",inputContext)
    check("browser_find_enter_saves_email_read",not notice.unread and saved==1 and screen.tab=="email")
    screen.enter(state)

    local commands={}
    local remote=context.computerScreen.new({remoteCommand=function(intent)commands[#commands+1]=intent end})
    remote.enter(state)
    local function remoteClick(id)
        local bx,by=remote.browserControlCenter(id)
        return remote.mousepressed(state,bx,by,1)
    end
    remoteClick("search");remote.textinput(state,"thecritternet.com/warehouse")
    local rx,ry=remote.browserResultCenter(1);remote.mousepressed(state,rx,ry,1)
    check("browser_search_respects_hidden_destinations",remote.tab=="active" and remote.browserOverlay=="search")
    remoteClick("www");remoteClick("back")
    check("browser_remote_navigation_stays_local",remote.tab=="active" and #commands==0)
    check("browser_console_histories_are_independent",not screen.browserCanGo(-1) and remote.browserCanGo(1))
    local Remote=require("src.screens.workshop_remote_screen")
    local previous=Remote.sharedComputer
    Remote.sharedComputer=remote
    remoteClick("search");state.screen="workshop_remote"
    check("browser_remote_escape_dismisses_popup",context.input.keypressed("escape",{state=state,workshopRemoteScreen=Remote})
        and not remote.browserOverlay and state.screen=="workshop_remote")
    Remote.sharedComputer=previous

    -- Exercise native landscape layout separately from the desktop fit matrix.
    local originalOS,originalDimensions,originalSafeArea=love.system.getOS,love.graphics.getDimensions,love.window.getSafeArea
    local ok,problem=xpcall(function()
        love.system.getOS=function()return "Android" end
        love.graphics.getDimensions=function()return 832,384 end
        love.window.getSafeArea=function()return 0,0,832,384 end
        screen.enter(state)
        local function menu()
            local mx,my=screen.dropdownCenter()
            return screen.mousepressed(state,mx,my,1)
        end
        menu()
        capture("sprite-phone-menu",832,384)
        check("browser_phone_sprite_menu_opens",screen.tabDropdownOpen)
        click("search");screen.textinput(state,"hiring")
        capture("sprite-phone-search",832,384)
        firstResult()
        check("browser_phone_sprite_find_opens_page",screen.tab=="hiring" and not screen.browserOverlay)
        menu();click("back")
        check("browser_phone_sprite_back_restores_page",screen.tab=="active")
        menu();click("forward")
        check("browser_phone_sprite_forward_restores_page",screen.tab=="hiring")
        menu();click("favorites");click("field")
        capture("sprite-phone-favorites",832,384)
        check("browser_phone_sprite_favorites_saves_page",#screen.browserFavorites==1 and screen.browserFavorites[1].tab=="hiring")
        screen.dismissBrowserOverlay()
        click("clock")
        check("browser_phone_sprite_clock_opens",screen.tab=="clock")
    end,debug.traceback)
    love.system.getOS,love.graphics.getDimensions,love.window.getSafeArea=originalOS,originalDimensions,originalSafeArea
    assert(ok,problem)
end

return Test
