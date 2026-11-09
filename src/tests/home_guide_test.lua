local Guide=require("src.screens.computer.home_guide")
local Computer=require("src.screens.computer_screen")
local State=require("src.state")
local Schema=require("src.save_schema")
local Ui=require("src.screens.ui")
local Test={}
local function click(s,screen,name,index)
    local x,y=screen.homeGuideControlCenter(name,index);return screen.mousepressed(s,x,y,1)
end
local function open(s,screen)
    screen.tab="home";local x,y=screen.homeControlCenter("guide");return screen.mousepressed(s,x,y,1)
end
function Test.run(context,check)
    local s=State.new();local sent=0
    local guest=Computer.new({remoteCommand=function() sent=sent+1 end})
    local host=Computer.new();host.enter(s)
    check("home_guide_shop_computer_keeps_work_landing",host.tab=="active")
    s.home.weekend.phase="home";s.home.weekend.closedAtHours=44
    local Calendar=require("src.business_calendar");s.calendar=Calendar.dateFromHours(44);s.calendar.elapsed=20/24*s.calendar.secondsPerDay
    host.enter(s);guest.enter(s)
    check("home_guide_home_laptops_land_on_my_home",host.tab=="home" and guest.tab=="home")
    open(s,host);open(s,guest)
    local revision,balance,rent=s.home.revision,s.home.balanceCents,s.home.lease.paidCents
    local destination=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    for i=1,#Guide.TOPICS do
        click(s,guest,"topic",i)
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        guest.draw(s,nil,nil,context.assets)
        local bottom=Guide.draw({contains=Ui.contains,drawComputerButton=function() end},s,i)
        check("home_guide_topic_fits_above_footer_"..i,bottom<=550,"bottom="..bottom)
        love.graphics.pop()
        if destination then
            local data=canvas:newImageData();local encoded=data:encode("png")
            local file=assert(io.open(destination.."/home-guide-"..i..".png","wb"));file:write(encoded:getString());file:close()
            encoded:release();data:release()
        end
        canvas:release()
    end
    check("home_guide_reading_never_spends_or_sends",sent==0 and s.home.revision==revision and s.home.balanceCents==balance
        and s.home.lease.paidCents==rent and #s.home.shopping.orders==0)
    click(s,guest,"action") -- Personal pay, still read-only.
    local x,y=guest.homeControlCenter("plus")
    check("home_guide_guest_pay_link_keeps_authority",guest.mousepressed(s,x,y,1).action=="blocked" and sent==0)
    click(s,host,"action")
    check("home_guide_each_console_keeps_own_topic",host.tab=="groceries" and guest.tab=="home")
    host.tab="home"
    for _,row in ipairs({{1,"secondary","home_orders"},{2,"action","groceries"},{2,"secondary","takeout"},
        {3,"action","furniture"},{3,"secondary","home_orders"},{6,"secondary","home_orders"}}) do
        click(s,host,"topic",row[1]);click(s,host,row[2])
        check("home_guide_link_"..row[1].."_"..row[2],host.tab==row[3] and #s.home.shopping.orders==0)
        host.tab="home"
    end
    s.home.inventory.basic_meal=3;s.home.balanceCents=50
    local content=Guide.content(s,1)
    check("home_guide_live_pantry_and_low_cash_advice",content.blocks[1]:find("portions: 3",1,true)
        and content.blocks[3]:find("Buy food first",1,true))
    s.home.shopping.guestSpentCents=500;s.home.shopping.budgetCloseHours=s.home.weekend.closesAtHours
    content=Guide.content(s,6)
    check("home_guide_shared_budget_reports_remaining_not_spent",content.blocks[3]:find("$25.00 remains",1,true))
    s.home.balanceCents=balance;s.home.inventory.basic_meal=0
    click(s,host,"topic",5);s.home.weekend.phase="working";s.home.weekend.closedAtHours=nil;s.screen="computer"
    check("home_guide_sleep_link_blocks_outside_home",click(s,host,"action").action=="blocked" and s.screen=="computer")
    host.enter(s);s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;host.enter(s)
    open(s,host);click(s,host,"action")
    check("home_guide_reentry_resets_to_first_weekend",host.tab=="groceries")
    -- The actual guest wrapper projects state. Leaving it must release the
    -- console before changing the real client screen, not just the projection.
    local Remote=require("src.screens.workshop_remote_screen")
    Remote.enter({resourceId="office_computer",leaseId="guide-test",revision=0,view={}},s)
    check("home_guide_remote_laptop_landing",Remote.sharedComputer.tab=="home")
    local remoteScreen=Remote.sharedComputer
    x,y=remoteScreen.homeControlCenter("guide");Remote.mousepressed(s,x,y,1,function() error("Guide sent an office command") end)
    x,y=remoteScreen.homeGuideControlCenter("topic",5);Remote.mousepressed(s,x,y,1,function() end)
    x,y=remoteScreen.homeGuideControlCenter("action")
    local released=0
    local inputContext={state=s,workshopRemoteScreen=Remote,requestWorkshopCommand=function() error("Unexpected command") end,
        releaseWorkshopInteraction=function() released=released+1 end}
    Remote.waiting=true
    require("src.input").mousepressed(x,y,1,inputContext)
    check("home_guide_pending_guest_request_cannot_abandon_console",released==0 and s.screen=="workshop_remote")
    Remote.waiting=false
    require("src.input").mousepressed(x,y,1,inputContext)
    check("home_guide_guest_sleep_opens_real_screen_and_releases_once",s.screen=="home_activity" and released==1 and not Remote.isOpen()
        and require("src.home_activity_controls").mode=="sleep" and sent==0)
    s.screen="world";check("home_guide_browsing_keeps_save_valid",Schema.validState(Schema.snapshot(s)))
end
return Test
