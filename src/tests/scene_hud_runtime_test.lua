-- Native App.draw review of shared status text and the scene controls beside it.
local Status=require('src.screens.player_status')
local Calendar=require('src.business_calendar')
local C=require('src.commute.runtime')
local Visibility=require('src.screens.hud_visibility')
local WarehouseHud=require('src.screens.warehouse_hud')
local Ui=require('src.screens.ui')
local Test={}
local function save(canvas,path)
    local data=canvas:newImageData();local png=data:encode('png')
    local file=assert(io.open(path,'wb'));file:write(png:getString());file:close()
    png:release();data:release()
end
function Test.run(context,check)
    local R=assert(context.appRuntime);local g=love.graphics
    local output=assert(os.getenv('PICTURE_SHOP_HUD_OUTPUT'))
    local oldWidth,oldHeight=R.Config.baseWidth,R.Config.baseHeight
    local oldClock=R.App.settings.twelveHourTime
    local oldHud=R.App.settings.hudVisible
    R.App.settings.hudVisible=true
    local records={}
    local function sampleValues()
        R.state.calendar=Calendar.dateFromHours(Calendar.totalDayForDate(2026,11,4)*24)
        R.state.calendar.secondsPerDay=1200;R.state.calendar.elapsed=1200*23.75/24
        R.state.home.balanceCents=123456;R.state.money=98765.43
    end
    local function capture(scene,width,height,twelveHour)
        R.Config.baseWidth,R.Config.baseHeight=width,height
        R.App.settings.twelveHourTime=twelveHour
        local date,money=Status.text(R.state,twelveHour)
        local shown,labels,positions={},{},{};local print,printf=g.print,g.printf
        g.print=function(text,x,y,rotation,sx,sy,...)
            labels[text]=true
            if type(x)=='number' and type(y)=='number' then
                positions[text]={x=x,y=y,width=g.getFont():getWidth(tostring(text))*(sx or 1)}
            end
            if (text==date or text==money) and type(y)=='number' and y<56 then
                shown[text]={x=x,y=y,width=g.getFont():getWidth(text)*(sx or 1),height=g.getFont():getHeight()*(sy or sx or 1)}
            end
            return print(text,x,y,rotation,sx,sy,...)
        end
        g.printf=function(text,...)
            labels[text]=true;return printf(text,...)
        end
        local windowWidth,windowHeight=g.getDimensions()
        local canvas=g.newCanvas(windowWidth,windowHeight)
        local okay,reason=xpcall(function()
            g.push('all');g.setCanvas({canvas,stencil=true});R.App.draw();g.pop()
        end,debug.traceback)
        g.print,g.printf=print,printf;assert(okay,reason)
        local _,bounds=R.optionsAccessLayout();bounds=bounds or {left=0,right=width}
        local rect=Status.layout(bounds)
        local options=R.OptionsScreen.accessRect('world',bounds)
        local exit=require('src.screens.hud').exitRect(bounds)
        local newHud=WarehouseHud.active(R)
        local themedHud=newHud or scene=='apartment'
        local layout=newHud and WarehouseHud.layoutFor(R,bounds)
            or scene=='apartment' and WarehouseHud.layout(bounds,true)
        if Visibility.isVisible(R) then
            if themedHud then
                local cash=Ui.money(R.state.money)
                local time=Calendar.timeText(R.state,twelveHour)
                local home=Ui.money((R.state.home.balanceCents or 0)/100)
                local narrowRide=layout.narrow
                check('scene_hud_'..scene..'_'..width..'_live_date_and_balances_draw_at_top',
                    labels[cash] and labels[time] and labels[narrowRide and 'NOV' or 'NOV 2026']
                    and labels[home])
                local right=bounds.right or width
                check('scene_hud_'..scene..'_'..width..'_text_and_menu_controls_do_not_overlap',
                    layout.cash.x+layout.cash.width<layout.calendar.x
                    and layout.calendar.x+layout.calendar.width<layout.clock.x
                    and layout.clock.x+layout.clock.width<layout.menu.x
                    and layout.menu.x+layout.menu.width<=right)
            else
                check('scene_hud_'..scene..'_'..width..'_live_date_and_balances_draw_at_top',shown[date] and shown[money])
                local fits=shown[date] and shown[money]
                for _,text in ipairs({date,money}) do
                    local line=shown[text]
                    fits=fits and line and line.x>=rect.x and line.x+line.width<=rect.x+rect.width+.01
                        and line.y+line.height<=rect.y+rect.height
                end
                check('scene_hud_'..scene..'_'..width..'_text_and_menu_controls_do_not_overlap',fits
                    and rect.x+rect.width+8<=options.x and options.x+options.width<=exit.x)
            end
        else
            check('scene_hud_'..scene..'_'..width..'_hidden_stats_and_menu_buttons_are_not_drawn',
                not shown[date] and not shown[money] and not labels['EXIT TO MENU'] and not labels['OPTIONS'] and not labels['DOOR'])
        end
        for _,button in ipairs(Visibility.buttons(R)) do
            check('scene_hud_'..scene..'_'..width..'_'..button.id..'_button_remains_visible',
                button.icon or labels[button.label])
        end
        if R.World.player.sceneId=='commute' then
            local map=C.mapButton(R)
            local buttons=Visibility.buttons(R)
            if Visibility.isVisible(R) and not R._commute.mapOpen then
                check('ride_shop_and_home_balances_share_header_'..scene..width,
                    labels['SHOP'] and labels['HOME'])
                local cameraButton=C.cameraButton(R)
                check('ride_camera_control_remains_clear_of_menu_'..scene..width,
                    cameraButton and cameraButton.x+cameraButton.width<layout.menu.x)
                local bike=C.localPart(R).rider.bike
                local condition=positions['CONDITION '..(100-bike.damage)..'%']
                check('ride_bike_card_sits_below_stats_'..scene..width,
                    condition and condition.y>=layout.cash.y+layout.cash.height)
                if layout.narrow then
                    local mini=C.miniMapRect(R)
                    local cardRight=C.cardX(R)+require('src.commute.cockpit').CARD_WIDTH
                    local clock=positions[Calendar.timeText(R.state,twelveHour)]
                    check('ride_compact_header_and_notice_controls_have_separate_space_'..scene..width,
                        clock and clock.x>=layout.clock.x and clock.x+clock.width<=layout.clock.x+layout.clock.width
                        and layout.calendar.x+layout.calendar.width<layout.clock.x
                        and layout.noticeIcon.x>cardRight+4
                        and layout.noticeToggle.x+layout.noticeToggle.width<mini.x-4
                        and mini.y>=layout.calendar.y+layout.calendar.height
                        and mini.y>=layout.clock.y+layout.clock.height)
                end
                local fuel,_,low,beam=require('src.commute.fuel_gauge').read(bike)
                check('ride_bike_card_shows_miles_fuel_and_lamp_'..scene..width,
                    labels[('%.1f mi'):format(bike.service.miles)] and labels[('%.1f / 4.0 L'):format(fuel)]
                    and labels[require('src.commute.fuel_gauge').beamLabels[beam]]
                    and (labels['LOW FUEL']==true)==low)
            end
            check('scene_hud_'..scene..'_'..width..'_toolbar_and_menu_controls_do_not_overlap',map
                and layout and map.x+map.width<layout.menu.x
                and layout.menu.x+layout.menu.width<=(bounds.right or width))
            local Touch=require('src.commute.touch_controls')
            local ctx=C.controlContext(R)
            local controls=Touch.actionButtons(width,height,C.bindings(R),ctx,
                {mobile=C.mobileInputEnabled(R),camera=R._commute.camera})
            local clear=true
            for _,button in ipairs(controls) do
                if button.action=='followCamera' or button.action=='recenter' or button.action=='rescue' then
                    clear=clear and math.abs(button.y-button.radius-ctx.controlsTop)<.01
                        and button.x+button.radius<C.miniMapRect(R).x
                    if clear and button.action=='rescue' then
                        local hit=Touch.actionAt(button.x,button.y,width,height,C.bindings(R),ctx,
                            {mobile=C.mobileInputEnabled(R),camera=R._commute.camera})
                        clear=hit and hit.action=='rescue'
                    end
                end
            end
            check('scene_hud_'..scene..'_'..width..'_camera_actions_clear_condition_and_minimap',clear)
        end
        records[#records+1]=scene..' '..width..' '..date..' | '..money
        save(canvas,output..('/%s-%d.png'):format(scene,width));canvas:release()
    end
    local okay,reason=xpcall(function()
        local payload=assert(R.Save.newGame(3,{apartmentId='garden'}))
        assert(R.startGame(payload,'smoke'))
        R.state.home.weekend.phase='home'
        local x,y=require('src.home_layouts').spawn(R.state,1)
        R.World.load({id=1,sceneId='home',x=x,y=y,character=R.World.player.character})
        R.state.screen='world';sampleValues()
        for _,size in ipairs({{640,480},{960,678},{1280,880}}) do capture('apartment',size[1],size[2],true) end
        local homeScreen,homeBounds=R.optionsAccessLayout()
        local homeOptions=R.OptionsScreen.accessRect(homeScreen,homeBounds)
        local homeExit=require('src.screens.hud').exitRect(homeBounds)
        local homeNotices=require('src.screens.notifications_screen').buttonRect(homeBounds,R)
        local homeVisibility=Visibility.buttons(R)[1]
        check('scene_hud_home_icon_buttons_have_separate_hit_targets',homeScreen=='home_world'
            and homeOptions.x+homeOptions.width<=homeExit.x
            and homeVisibility.icon and homeVisibility.x+homeVisibility.width<=homeNotices.x
            and homeNotices.y>=homeExit.y+homeExit.height
            and R.OptionsScreen.accessHit(homeOptions.x+homeOptions.width/2,
                homeOptions.y+homeOptions.height/2,homeScreen,homeBounds))
        check('scene_hud_uses_game_weekday_date_and_twelve_hour_preference',records[1]:find('Wednesday',1,true)
            and records[1]:find('Nov 4, 2026',1,true) and records[1]:find('11:45 PM',1,true))
        R.state.home.balanceCents=122956
        local _,changed=Status.text(R.state,true)
        check('scene_hud_reads_changed_household_balance_without_a_cached_label',changed:find('Home $1,229.56',1,true))
        R.Config.baseWidth,R.Config.baseHeight=640,480
        R.App.keypressed('f9');capture('apartment-hidden',640,480,true)
        check('scene_hud_home_toggle_preference_is_saved',not require('src.settings').load().hudVisible)
        local button=Visibility.buttons(R)[1]
        local ox,oy,scale=R.Viewport.transform(640,480,R.App.officeUsesSafeArea())
        R.App.touchpressed('home-hud',ox+(button.x+button.width/2)*scale,oy+(button.y+16)*scale)
        R.App.touchreleased('home-hud',0,0)
        check('scene_hud_home_touch_restore_button_works',Visibility.isVisible(R))

        R.Config.baseWidth,R.Config.baseHeight=oldWidth,oldHeight
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden'})),'smoke'));R.state.screen='world'
        R.state.calendar=Calendar.dateFromHours(44);R.state.calendar.secondsPerDay=1200;R.state.calendar.elapsed=1200*20/24
        R.state.home.weekend.phase='ready';R.state.home.weekend.closedAtHours=44;R.World.truck.state='absent'
        local entrance=require('src.home_travel').target(R.World.player,R.state)
        R.World.player.x,R.World.player.y=entrance.x,entrance.y
        local Weekend=require('src.weekend_runtime')
        assert(Weekend.command(R,R.World.player,'request'))
        assert(Weekend.command(R,R.World.player,'depart:'..R.state.home.weekend.travelToken))
        require('src.commute.tests.loading_test_support').wait(R,check,'scene_hud')
        R.App.keypressed('g');for _=1,250 do R.App.update(1/60) end
        R.App.keypressed('e');for _=1,150 do R.App.update(1/60) end
        local part=C.localPart(R);assert(part.rider.gear.mounted,'HUD review needs a mounted rider')
        sampleValues();R.state.message='Ride safely. Your money and calendar stay visible.'
        for _,size in ipairs({{640,480},{960,678},{1280,880}}) do
            R._commute.camera:setFirstPerson(false,part.rider.bike)
            capture('bike-third-person',size[1],size[2],true)
            R._commute.camera:setFirstPerson(true,part.rider.bike)
            capture('bike-first-person',size[1],size[2],false)
        end
        check('scene_hud_bike_honors_twenty_four_hour_clock',records[#records]:find('23:45',1,true)
            and not records[#records]:find('PM',1,true))
        local bike=part.rider.bike
        bike.service.fuel,bike.service.miles,bike.headlight,bike.headlightHighBeam=.4,17.6,true,true
        for _,eye in ipairs({false,true}) do
            R._commute.camera:setFirstPerson(eye,bike)
            capture(eye and 'reserve-first-person' or 'reserve-outside',960,678,false)
        end
        bike.service.fuel,bike.headlight=4,false
        require('src.tests.scene_hud_controls_test').run(R,check,capture)
        local file=assert(io.open(output..'/rendered-status.txt','wb'));file:write(table.concat(records,'\n')..'\n');file:close()
    end,debug.traceback)
    R.Config.baseWidth,R.Config.baseHeight=oldWidth,oldHeight;R.App.settings.twelveHourTime=oldClock
    R.App.settings.hudVisible=oldHud;require('src.settings').save(R.App.settings)
    assert(okay,reason)
end
return Test
