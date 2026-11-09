local Test={}
function Test.run(R,check)
    local state,p=R.state,R.World.player;local Calendar=require("src.business_calendar")
    local Activity=require("src.home_activity_controls");local Sleep=require("src.home_sleep")
    local Layout=require("src.home_layouts");local Shopping=require("src.home_shopping")
    local function capture(name)
        local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
        local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        R.World.draw(R.Assets,R.CharacterAssets,state,nil,nil,{});Activity.draw(R)
        love.graphics.pop();local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    state.screen="world";local laptop=assert(Layout.targets(p,state).computer);p.x,p.y=laptop.x,laptop.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,laptop.hoverX,laptop.hoverY);R.App.keypressed("e")
    local screen=R.ComputerScreen;local x,y=screen.dropdownCenter();screen.mousepressed(state,x,y,1)
    x,y=screen.tabCenter("home");screen.mousepressed(state,x,y,1)
    x,y=screen.homeControlCenter("sleep");screen.mousepressed(state,x,y,1)
    check("home_sleep_runtime_laptop_opens_personal_controls",state.screen=="home_activity" and Activity.mode=="sleep")
    Activity.mousepressed(160,309,1,R) -- Set an alarm before the eight-hour sleep ends.
    Activity.mousepressed(475,309,1,R) -- Fine tune the selected minute.
    local now=Calendar.absoluteHours(state)
    local expectedAlarm=math.floor(now/24)*24+Activity.alarmHour+Activity.alarmMinute/60
    if expectedAlarm<=now+1e-7 then expectedAlarm=expectedAlarm+24 end
    Activity.mousepressed(635,309,1,R) -- Confirm the custom time.
    local owner=state.home.residents.owner;local alarm=owner.alarmAt
    check("home_sleep_runtime_touch_sets_custom_alarm_time",alarm and math.abs(alarm-expectedAlarm)<1e-7)
    assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
    check("home_sleep_runtime_personal_alarm_saved",saved.state.home.residents.owner.alarmAt==alarm)
    local pantryBefore=state.home.inventory.basic_meal or 0
    assert(Shopping.order(state,p,{productId="meal",quantity=1,requestId="sleep-runtime-food",expectedRevision=state.home.revision}))
    check("home_sleep_runtime_shop_speed_cannot_override_consent",not R.App.setGameClockSpeed(10))
    local sleepStarted=Calendar.absoluteHours(state)
    owner.energy=0;R.App.keypressed("return")
    check("home_sleep_runtime_starts_opt_in_sleep",owner.activity and owner.activity.kind=="sleepfloor" and Sleep.status(state,{p}))
    capture("home-shared-sleep-menu")
    local updates=0
    while owner.activity and updates<250 do R.App.update(.5);updates=updates+1 end
    check("home_sleep_runtime_fast_sleep_stops_at_personal_alarm",not owner.activity and math.abs(Calendar.absoluteHours(state)-alarm)<1e-6
        and owner.lastAlarmAt==alarm and math.abs(owner.energy-math.min(100,(alarm-sleepStarted)*19.3))<1e-5 and updates<100,
        ("time=%.6f alarm=%.6f start=%.6f last=%s energy=%.6f updates=%d"):format(
            Calendar.absoluteHours(state),alarm,sleepStarted,tostring(owner.lastAlarmAt),owner.energy,updates))
    check("home_sleep_runtime_delivery_waits_safely_during_sleep",Shopping.waiting(state)==1 and (state.home.inventory.basic_meal or 0)==pantryBefore)
    local revision=owner.revision;R.App.update(.01)
    check("home_sleep_runtime_alarm_does_not_repeat",owner.revision==revision and not owner.alarmAt)
    R.App.keypressed("r");capture("home-readiness-summary")
    check("home_sleep_runtime_readiness_panel_available",Activity.mode=="readiness")
    state.calendar=Calendar.dateFromHours(102.9);state.calendar.elapsed=6.9/24*Calendar.secondsPerDay(state)
    state.screen="world";R.App.keypressed("h");R.App.keypressed("t");R.App.keypressed("return")
    updates=0;while owner.activity and updates<30 do R.App.update(.5);updates=updates+1 end
    check("home_sleep_runtime_stops_at_monday_reminder",math.abs(Calendar.absoluteHours(state)-103)<1e-6
        and not owner.activity and state.home.weekend.returnReminderSent)
    capture("home-monday-wake")
    assert(R.saveCurrent(true));saved=assert(R.Save.load(3))
    check("home_sleep_runtime_monday_wake_saved",saved.state.home.weekend.returnReminderSent and not saved.state.home.residents.owner.activity)
end
return Test
