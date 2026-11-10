-- Actual application rendering in disposable desktop, phone and tablet views.
-- Captures are reviewed alongside the text geometry report; a rendered screen
-- alone is not evidence of interaction or device-specific input coverage.
local Test={}
local Text=require('src.screens.typography')
function Test.run(context,check)
    local R=assert(context.appRuntime);local g=love.graphics
    require('src.tests.ui_typography_test').run(context,check)
    local output=assert(os.getenv('PICTURE_SHOP_UI_OUTPUT'))
    local mode=os.getenv('PICTURE_SHOP_UI_MODE') or 'desktop'
    local only=os.getenv('PICTURE_SHOP_UI_ONLY') or ''
    local width,height=960,678
    if mode=='phone' then width,height=832,384 elseif mode=='tablet' then width,height=1024,768 end
    assert(love.window.setMode(width,height,{resizable=true,minwidth=1,minheight=1,vsync=0}))
    local originalOS=love.system.getOS
    if mode~='desktop' then love.system.getOS=function()return mode=='phone' and 'Android' or 'iOS' end end
    require('src.image_loader').enabled=false
    local payload=assert(R.Save.newGame(3));assert(R.startGame(payload,'smoke'))
    -- Render fixtures deliberately include incomplete orders and synthetic
    -- scenes. Exercise navigation without enqueueing those as playable saves.
    local originalSaveCurrent=R.saveCurrent;R.saveCurrent=function()return true end
    local originalSaveQueue=R.Save.queue;R.Save.queue=function()return true end
    R.App.settings.hudVisible=true
    R.state.money=98765.43;R.state.home.balanceCents=123456
    R.state.message='Paper received. Three completed jobs are ready for delivery.'
    local records={};local failures={};local captures=0
    local function capture(name,prepare,draw)
        if only~='' and not name:find(only,1,true) then return end
        local okay,reason=xpcall(function()
            if prepare then prepare() end
            local rows={};local print,printf=g.print,g.printf
            local function record(text,x,y,limit,sx,sy)
                if type(text)~='string' or type(x)~='number' or type(y)~='number' then return end
                local font=g.getFont();local size=Text.size(font) or font:getHeight()
                local tx,ty=g.transformPoint(x,y);local ex,ey=g.transformPoint(x+1,y+1)
                local _,lines=font:getWrap(text,math.max(1,limit or font:getWidth(text)))
                rows[#rows+1]={text=text,x=tx,y=ty,size=size,effective=size*math.abs(ey-ty)*(sy or sx or 1),
                    width=(limit or font:getWidth(text))*math.abs(ex-tx)*(sx or 1),lines=#lines}
            end
            g.print=function(text,x,y,rotation,sx,sy,...)
                record(text,x,y,nil,sx,sy);return print(text,x,y,rotation,sx,sy,...)
            end
            g.printf=function(text,x,y,limit,align,rotation,sx,sy,...)
                record(text,x,y,limit,sx,sy);return printf(text,x,y,limit,align,rotation,sx,sy,...)
            end
            local canvas=g.newCanvas(width,height)
            g.push('all');g.setCanvas({canvas,stencil=true});g.clear(.025,.045,.05,1)
            local rendered,problem=xpcall(function()
                if draw then
                    require('src.viewport').beginDraw(960,678,false);g.setFont(Text.get(16));draw();require('src.viewport').endDraw()
                else R.App.draw() end
            end,debug.traceback)
            g.pop();g.print,g.printf=print,printf
            assert(rendered,problem)
            local data=canvas:newImageData();local png=data:encode('png')
            local file=assert(io.open(output..'/'..name..'.png','wb'));file:write(png:getString());file:close()
            png:release();data:release();canvas:release()
            records[#records+1]={screen=name,text=rows};captures=captures+1
            _G.print('UI_CAPTURE '..name..' '..#rows..' text draws')
        end,debug.traceback)
        if not okay then failures[#failures+1]=name..': '..tostring(reason);print('UI_CAPTURE_ERROR '..name..' '..tostring(reason)) end
    end
    capture('warehouse',function()R.state.screen='world' end)
    capture('title',function()R.state.screen='title' end)
    capture('new-shop',nil,function()require('src.screens.shop_setup_screen').draw(require('src.screens.shop_setup_screen').new(),3,R.Assets)end)
    local TownSetup=require('src.screens.town_setup_screen')
    local townOptions={town=R.state.home.town}
    local townSetup=TownSetup.new(townOptions)
    capture('new-town',nil,function()TownSetup.draw(townSetup,townOptions,3,R.Assets)end)
    capture('new-town-confirm',function()townSetup.confirming=true end,
        function()TownSetup.draw(townSetup,townOptions,3,R.Assets)end)
    capture('lan',function()R.state.screen='lan' end)
    capture('direct',function()R.state.screen='direct' end)
    R.state.screen='world';R.openOptions()
    for _,tab in ipairs({'game','audio','controls','character','cheats','debug'}) do
        capture('options-'..tab,function()R.state.screen='options';R.OptionsScreen.tab=tab end)
    end
    capture('options-update-notes',function()R.OptionsScreen.tab='debug';R.OptionsScreen.debugPage='notes' end)
    capture('options-watchdog-event',function()
        R.OptionsScreen.debugPage=nil
        require('src.ai_watchdog').observe(R.state,'ui-road-stall',{issueId='road-driver:SHIP-0001',system='Road traffic',
            subject='SHIP-0001',stage='outbound:302',dt=12,timeout=12,visible=true,scope='world-simulation',
            x=167.7,z=460.7,reason='Traffic wait has prevented route progress for twelve seconds.',
            action='Reversing to clear the oncoming vehicle; safe route recovery is available if traffic remains blocked.',
            detail='yield=true stop=false passing=false desired=0.0 waypoint=302'})
    end)
    local reviewJob=assert(require('src.jobs').createOffer({id='UI-104',company='Millhaven Community Theatre',
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500,500,500}}))
    require('src.jobs').accept(reviewJob);reviewJob.status='in_production';reviewJob.delivery={status='received'}
    R.state.jobs.active[#R.state.jobs.active+1]=reviewJob
    R.ComputerScreen.enter(R.state);R.ComputerScreen.selectedJobId=reviewJob.id
    for _,tab in ipairs({'active','completed','deliveries','estimating','email','reviews','clock','financials','bills',
            'player_wages','inventory','hiring','schedule','warehouse','radio','www','calendar','credit',
            'home','groceries','takeout','home_orders','furniture'}) do
        capture('computer-'..tab,function()R.state.screen='computer';R.ComputerScreen.tab=tab end)
    end
    capture('computer-dropdown',function()R.ComputerScreen.tabDropdownOpen=true end)
    R.ComputerScreen.tabDropdownOpen=false
    capture('computer-active-long',function()
        R.ComputerScreen.tab='active';R.ComputerScreen.selectedJobId=reviewJob.id
    end)
    if only=='' then
        R.ComputerScreen.wheelmoved(R.state,0,-100)
        check('job_detail_wheel_reaches_last_pallet',R.ComputerScreen.jobDetailMaxScroll>0
            and R.ComputerScreen.jobDetailScroll==R.ComputerScreen.jobDetailMaxScroll)
    end
    capture('computer-active-scrolled',function()R.ComputerScreen.jobDetailScroll=100000 end)
    if only=='' then
        local screen=R.ComputerScreen;local viewport=screen.jobDetailViewport()
        local mobile=require('src.screens.computer.mobile_layout')
        local function point(x,y)if mobile.active() then return mobile.fromContent(x,y) end return x,y end
        local x,y=point(viewport.x+40,viewport.y+30)
        screen.mousepressed(R.state,x,y,1)
        x,y=point(viewport.x+40,viewport.y+viewport.height-20);screen.mousemoved(R.state,x,y)
        screen.mousereleased(R.state,x,y,1)
        check('job_detail_drag_scrolls_and_releases',screen.jobDetailScroll<screen.jobDetailMaxScroll and not screen.jobDetailDragY)
        g.setFont(Text.get(16));local layout=screen.jobDetailLayout(reviewJob,R.state)
        check('job_detail_last_pallet_clears_fixed_action',layout.tableBottom-layout.scrollMax<=layout.actionTop-28+.01)
    end
    capture('computer-credit-confirm',function()
        R.ComputerScreen.tab='credit'
        local x,y=R.ComputerScreen.creditMachineCenter(1);R.ComputerScreen.mousepressed(R.state,x,y,1)
    end)
    R.ComputerScreen.creditConfirmation=nil
    capture('job-offer',function()R.state.screen='job_offer';R.state.currentOffer=reviewJob end)
    R.RuntimeDependencies.PalletWorkOrderScreen.enter({job=reviewJob,pallet=reviewJob.pallets[1]})
    R.RuntimeDependencies.DeliverySignatureScreen.enter({deliveryId='DEL-104',supplier=reviewJob.company,
        shipment='Three pallets of printed theatre posters',quantity='1,500 sheets',orderState='Completed',
        deliveryState='Ready to sign',location='Warehouse loading bay',category='Printed posters',palletCount=3})
    for _,screen in ipairs({'home_travel','shop_rooms','work_phone','vendor','truck_inventory','pallet_work_order','delivery_signature','shop_clock'}) do
        capture(screen,function()R.state.screen=screen end)
    end
    R.state.screen='press';R.PressScreen.enter(R.state)
    for _,tab in ipairs({'run','plates','setup','proof','maintenance','tutorial'}) do
        capture('press-'..tab,function()R.state.screen='press';R.PressScreen.tab=tab end)
    end
    for _,machine in ipairs({'cutter','skid_wrapper'}) do
        capture('machine-'..machine,function()R.state.screen='machine';R.state.machineType=machine;R.MachineScreen.enter() end)
    end
    capture('machine-cutter-help',function()R.state.machineType='cutter';R.MachineScreen.enter();R.MachineScreen.helpOpen=true end)
    R.MachineScreen.helpOpen=false
    capture('notifications',function()
        require('src.notifications').add(R.state,'supplier','Paper delivered to the warehouse',
            'Three pallets are ready to unload.',
            'The driver has arrived at the warehouse loading bay.\n\nOpen the bay, receive each pallet, and sign the delivery receipt. Your employees can keep working while you travel.')
        require('src.screens.notifications_screen').open(R)
    end)
    capture('home-apartment',function()
        R.state.screen='world';R.state.home.weekend.phase='home'
        local x,y=require('src.home_layouts').spawn(R.state,1)
        R.World.load({id=1,sceneId='home',x=x,y=y,character=R.World.player.character})
    end)
    for _,homeMode in ipairs({'routines','sleep','readiness'}) do
        capture('home-'..homeMode,function()
            R.state.screen='home_activity';local c=require('src.home_activity_controls')
            c.mode=homeMode;c.appliance=nil;c.target='floor'
        end)
    end
    R.state.home.inventory.mini_fridge=1;R.state.home.inventory.stove=1
    require('src.home_furniture').materialize(R.state,true)
    for _,appliance in ipairs({'fridge','stove','laundry','bike'}) do
        capture('home-'..appliance,function()
            R.state.screen='home_activity';local c=require('src.home_activity_controls')
            c.appliance=appliance;c.mode='routines';c.target=appliance;c.appliancePage=1
            for _,item in ipairs(R.state.home.furniture.items) do
                if item.kind==(appliance=='fridge' and 'mini_fridge' or appliance) then c.target='furniture'..item.id;break end
            end
        end)
    end
    require('src.home_activity_controls').appliance=nil
    capture('home-furnish',function()R.state.screen='home_furnish' end)
    local Store=require('src.commute.town_store')
    for _,id in ipairs({'grocery','general-store','diner','gas-station'}) do
        local store=Store.open(id,1);store.storeStock=require('src.commute.grocery_inventory').defaultState()
        capture('store-'..id,nil,function()Store.draw(store,123456,{items={},revision=0},0,960,678)end)
        if id=='grocery' then for _,category in ipairs({'produce','pantry','chilled','household','specials','checkout'}) do
            capture('store-grocery-'..category,function()store.categoryId=category;store.cart={bread=2,vegetables=1}end,
                function()Store.draw(store,123456,{items={},revision=0},0,960,678)end)
        end end
    end
    capture('arcade-cabinet',nil,function()require('src.screens.arcade_menu').draw()end)
    capture('arcade-kombat',function()require('src.screens.critter_kombat_screen').enter(R,'room-a');
        require('src.screens.critter_kombat_screen').view='title' end)
    capture('arcade-crisis',function()require('src.screens.critter_crisis_screen').enter() end,
        function()require('src.screens.critter_crisis_screen').draw(R)end)
    capture('air-hockey',function()require('src.screens.air_hockey_screen').enter(R,'room-a') end)
    for _,kind in ipairs({'range','stand','train'}) do
        capture('arcade-'..kind,function()require('src.screens.frontier_arcade').open(kind,R)end,
            function()require('src.screens.frontier_arcade').draw()end)
        require('src.screens.frontier_arcade').close()
    end
    capture('asset-error',function()R.state.screen='asset_error';R.state.assetErrors={'Example required image is missing. Reinstall the game package.'}end)
    if mode=='phone' then
        R.state.screen='computer';R.ComputerScreen.tab='active';R.ComputerScreen.tabDropdownOpen=false
        R.ComputerScreen.selectedJobId=reviewJob.id
        capture('phone-touch-job')
        local ox,oy,_,sx,sy=R.Viewport.transform(960,678,R.App.officeUsesSafeArea())
        if only=='' then
            local screen=R.ComputerScreen;screen.jobDetailScroll=0
            local viewport=screen.jobDetailViewport();local layout=require('src.screens.computer.mobile_layout')
            local x,y=layout.fromContent(viewport.x+30,viewport.y+viewport.height-20)
            local endX,endY=layout.fromContent(viewport.x+30,viewport.y+20)
            x,y=ox+x*sx,oy+y*sy;endX,endY=ox+endX*sx,oy+endY*sy
            R.App.touchpressed('ui-job-scroll',x,y)
            R.App.touchmoved('ui-job-scroll',endX,endY,endX-x,endY-y)
            R.App.touchreleased('ui-job-scroll',endX,endY)
            check('phone_job_scroll_works_through_native_touch_callbacks',screen.jobDetailScroll>0 and not screen.jobDetailDragY)
        end
        local function tap(x,y)
            R.App.mousepressed(ox+x*sx,oy+y*sy,1,false)
            R.App.mousereleased(ox+x*sx,oy+y*sy,1,false)
        end
        tap(R.ComputerScreen.dropdownCenter())
        check('phone_office_actual_app_opens_compact_navigation',R.ComputerScreen.tabDropdownOpen)
        tap(R.ComputerScreen.tabCenter('inventory'))
        check('phone_office_actual_app_selects_transformed_content',R.ComputerScreen.tab=='inventory' and not R.ComputerScreen.tabDropdownOpen)
        local l=require('src.screens.computer.mobile_layout').geometry()
        tap(l.options.x+30,l.options.y+20)
        check('phone_office_options_remains_reachable',R.state.screen=='options')
        R.state.screen='computer';tap(l.close.x+30,l.close.y+20)
        check('phone_office_back_returns_to_game',R.state.screen=='world')
        local remote=R.ComputerScreen.new({remoteCommand=function()return true end})
        remote.enter(R.state);local x,y=remote.dropdownCenter();remote.mousepressed(R.state,x,y,1)
        x,y=remote.tabCenter('inventory');remote.mousepressed(R.state,x,y,1)
        check('phone_remote_office_uses_same_navigation_transform',remote.tab=='inventory' and not remote.tabDropdownOpen)
    end
    if only=='' or only:find('commute',1,true) or only:find('mechanic',1,true) then
        local C=require('src.commute.runtime')
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden'})),'smoke'));R.state.screen='world'
        R.state.calendar=require('src.business_calendar').dateFromHours(44)
        R.state.calendar.secondsPerDay=1200;R.state.calendar.elapsed=1200*20/24
        R.state.home.weekend.phase='ready';R.state.home.weekend.closedAtHours=44;R.World.truck.state='absent'
        local entrance=require('src.home_travel').target(R.World.player,R.state)
        R.World.player.x,R.World.player.y=entrance.x,entrance.y
        local Weekend=require('src.weekend_runtime')
        assert(Weekend.command(R,R.World.player,'request'))
        assert(Weekend.command(R,R.World.player,'depart:'..R.state.home.weekend.travelToken))
        require('src.commute.tests.loading_test_support').wait(R,check,'ui_readability_commute')
        R.App.keypressed('g');for _=1,250 do R.App.update(1/60) end
        R.App.keypressed('e');for _=1,150 do R.App.update(1/60) end
        local part=C.localPart(R)
        capture('commute-bike',function()R._commute.camera:setFirstPerson(false,part.rider.bike)end)
        capture('commute-first-person',function()R._commute.camera:setFirstPerson(true,part.rider.bike)end)
        local notice=require('src.notifications').add(R.state,'supplier','Paper delivered to the warehouse',
            'Three pallets are ready to unload.','The driver has arrived. Return to the warehouse loading bay to receive the paper.')
        R.App.playerFeedback=R.App.playerFeedback or require('src.player_feedback').new({state=R.state,world=R.World})
        R.App.playerFeedback.notices={{id=notice.id,kind=notice.kind,title=notice.title,detail=notice.detail,remaining=6,duration=7}}
        capture('commute-notification')
        local _,bounds=R.optionsAccessLayout()
        local button=require('src.screens.notifications_screen').buttonRect(bounds,R)
        local map=C.miniMapRect(R)
        check('commute_notice_button_clears_navigation',button.x+button.width<=map.x and button.y+button.height<=map.y+map.height)
        local toast=R.App.playerFeedback:toastRect(bounds,'commute')
        check('commute_notice_toast_clears_minimap',toast.x+toast.width<=map.x-8)
        check('commute_notice_toast_uses_matching_hit_bounds',
            R.App.playerFeedback:toastHit(toast.x+20,toast.y+20,bounds,'commute')==notice.id)
        R.App.playerFeedback.notices={}
        capture('commute-map',function()R._commute.mapOpen=true end)
        R._commute.mapOpen=false
        local Interior=require('src.commute.mechanic_interior')
        local service={page='catalog',service='performance',selectedCategory='engine',selected=1,
            selectedPaintId=require('src.commute.bike_paint').DEFAULT,selectedTireId=part.rider.bike.service.tire,vehicleKind='bike',
            token=R.state.home.commute.token,interior=Interior.new(R),elapsed=0,previewFrame=5}
        R._commute.mechanicOffer=service
        for _,kind in ipairs({'performance','tires','paint','repair'}) do
            capture('mechanic-'..kind,function()service.service=kind end,function()require('src.commute.mechanic_shop').draw(R)end)
        end
        R._commute.mechanicOffer=nil
        local Station=require('src.commute.gas_station')
        local company=require('src.company_delivery_driver').ensure(R.state);company.fuelLiters=20
        local stationArgs={rider=part.rider,service=part.rider.bike.service,companyTruck=company,
            truck=R.state.home.commute.truck,householdCents=R.state.home.balanceCents,
            companyCash=R.state.money,world=C.world(R)}
        for _,stationMode in ipairs({'bike','truck','counter'}) do
            local station=Station.open(stationMode);station.amountMl=12500
            capture('commute-fuel-'..stationMode,nil,function()Station.draw(station,stationArgs,960,678)end)
        end
        capture('commute-city-delivery',nil,function()
            require('src.commute.city_delivery_scene').draw(960,678,
                {cutsceneStartedAtEpoch=0,cutsceneEndsAtEpoch=5,palletCount=3,jobIds={'UI-104','UI-105','UI-106'}},
                {model='box'},nil,2.7)
        end)
    end
    local report=assert(io.open(output..'/text-layout.tsv','wb'))
    report:write('screen\tx\ty\twidth\tfont_size\tpixel_size\tlines\ttext\n')
    for _,capture in ipairs(records) do for _,row in ipairs(capture.text) do
        report:write(('%s\t%.2f\t%.2f\t%.2f\t%d\t%.2f\t%d\t%s\n'):format(capture.screen,row.x,row.y,row.width,
            row.size,row.effective,row.lines,row.text:gsub('[\t\r\n]',' ')))
    end end
    report:close()
    love.system.getOS=originalOS
    R.saveCurrent=originalSaveCurrent
    R.Save.queue=originalSaveQueue
    check('ui_readability_all_requested_screens_render',#failures==0,table.concat(failures,'\n'))
    check('ui_readability_rendered_screens',captures>0,tostring(captures))
end
return Test
