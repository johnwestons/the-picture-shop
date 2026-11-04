-- Native App.draw review of shared status text and the scene controls beside it.
local Status=require('src.screens.player_status')
local Calendar=require('src.business_calendar')
local C=require('src.commute.runtime')
local Visibility=require('src.screens.hud_visibility')
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
        local shown,labels={},{};local print,printf=g.print,g.printf
        g.print=function(text,x,y,rotation,sx,sy,...)
            labels[text]=true
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
        if Visibility.isVisible(R) then
        check('scene_hud_'..scene..'_'..width..'_live_date_and_balances_draw_at_top',shown[date] and shown[money])
        local fits=shown[date] and shown[money]
        for _,text in ipairs({date,money}) do
            local line=shown[text]
            fits=fits and line and line.x>=rect.x and line.x+line.width<=rect.x+rect.width+.01
                and line.y+line.height<=rect.y+rect.height
        end
        check('scene_hud_'..scene..'_'..width..'_text_and_menu_controls_do_not_overlap',fits
            and rect.x+rect.width+8<=options.x and options.x+options.width<=exit.x)
        else
            check('scene_hud_'..scene..'_'..width..'_hidden_stats_and_menu_buttons_are_not_drawn',
                not shown[date] and not shown[money] and not labels['EXIT TO MENU'] and not labels['OPTIONS'] and not labels['DOOR'])
        end
        for _,button in ipairs(Visibility.buttons(R)) do
            check('scene_hud_'..scene..'_'..width..'_'..button.id..'_button_remains_visible',labels[button.label])
        end
        if R.World.player.sceneId=='commute' then
            local map=C.mapButton(R)
            local buttons=Visibility.buttons(R)
            check('scene_hud_'..scene..'_'..width..'_toolbar_and_menu_controls_do_not_overlap',map
                and buttons[1].y>=options.y+options.height and buttons[1].y+buttons[1].height<=map.y)
            local Touch=require('src.commute.touch_controls')
            local controls=Touch.actionButtons(width,height,C.bindings(R),C.controlContext(R),
                {mobile=C.mobileInputEnabled(R),camera=R._commute.camera})
            local clear=true
            for _,button in ipairs(controls) do
                if button.action=='followCamera' or button.action=='recenter' or button.action=='rescue' then
                    clear=clear and button.y-button.radius> (C.mobileInputEnabled(R) and 199 or 237)
                        and button.x+button.radius<C.miniMapRect(R).x
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
        require('src.tests.scene_hud_controls_test').run(R,check,capture)
        local file=assert(io.open(output..'/rendered-status.txt','wb'));file:write(table.concat(records,'\n')..'\n');file:close()
    end,debug.traceback)
    R.Config.baseWidth,R.Config.baseHeight=oldWidth,oldHeight;R.App.settings.twelveHourTime=oldClock
    R.App.settings.hudVisible=oldHud;require('src.settings').save(R.App.settings)
    assert(okay,reason)
end
return Test
