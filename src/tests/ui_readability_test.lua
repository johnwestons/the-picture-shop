-- Actual application rendering in disposable desktop, phone and tablet views.
-- Captures are reviewed alongside the text geometry report; a rendered screen
-- alone is not evidence of interaction or device-specific input coverage.
local Test={}
local Text=require('src.screens.typography')
function Test.run(context,check)
    local R=assert(context.appRuntime);local g=love.graphics
    require('src.tests.ui_typography_test').run(context,check)
    local baselineFont=g.newFont(12)
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
    local originalFeedback=R.App.playerFeedback
    if not originalFeedback then
        R.App.playerFeedback=require('src.player_feedback').new({state=R.state,world=R.World})
        R.App.playerFeedback:seed()
    end
    -- Render fixtures deliberately include incomplete orders and synthetic
    -- scenes. Exercise navigation without enqueueing those as playable saves.
    local originalSaveCurrent=R.saveCurrent;R.saveCurrent=function()return true end
    local originalSaveQueue=R.Save.queue;R.Save.queue=function()return true end
    R.App.settings.hudVisible=true
    R.state.money=98765.43;R.state.home.balanceCents=123456
    R.state.message='Paper received. Three completed jobs are ready for delivery.'
    require('src.notifications').add(R.state,'shop','THREE JOBS READY',
        'Three completed jobs are ready for delivery.',
        'Review the job desk and load the finished pallets into the truck.','ui-review:ready')
    if R.App.playerFeedback then R.App.playerFeedback.statusTimer=0 end
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
            g.push('all');g.setFont(baselineFont);g.setCanvas({canvas,stencil=true});g.clear(.025,.045,.05,1)
            local rendered,problem=xpcall(function()
                if draw then
                    require('src.viewport').beginDraw(960,678,false);g.setFont(baselineFont);draw();require('src.viewport').endDraw()
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
    capture('warehouse-money-in',function()
        R.state.screen='world';R.App.playerFeedback.cashDelta=125
        R.App.playerFeedback.cashTimer=.76
    end)
    capture('warehouse-money-out',function()
        R.state.screen='world';R.App.playerFeedback.cashDelta=-45
        R.App.playerFeedback.cashTimer=.76
    end)
    R.App.playerFeedback.cashTimer=0
    local WarehouseHud=require('src.screens.warehouse_hud')
    WarehouseHud.menuOpen=true
    capture('warehouse-menu',function()R.state.screen='world' end)
    WarehouseHud.menuOpen=false
    WarehouseHud.noticesExpanded=false
    capture('warehouse-notices-collapsed',function()R.state.screen='world' end)
    WarehouseHud.noticesExpanded=true
    local previousInteraction=R.World.selectedInteraction
    R.World.selectedInteraction={kind='computer',target={prompt='E: use office computer'}}
    capture('warehouse-interaction',function()R.state.screen='world' end)
    R.World.selectedInteraction=previousInteraction
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
    for _,tab in ipairs({'active','completed','deliveries','estimating','email','reviews','clock','financials','bills','receipts',
            'player_wages','inventory','hiring','schedule','warehouse','radio','www','calendar','credit',
            'home','groceries','takeout','home_orders','furniture'}) do
        capture('computer-'..tab,function()R.state.screen='computer';R.ComputerScreen.tab=tab end)
    end
    capture('computer-financials-staff',function()
        R.state.screen='computer';R.ComputerScreen.tab='financials';R.ComputerScreen.financialSection='staff'
    end)
    R.ComputerScreen.financialSection='overview'
    capture('computer-www-cart',function()
        R.state.screen='computer';R.ComputerScreen.tab='www';R.ComputerScreen.cartOpen=true
        R.ComputerScreen.cart={{name='House paper',quantity=2,price=30,kind='supply',categoryIndex=1,itemIndex=1}}
    end)
    R.ComputerScreen.cartOpen=false;R.ComputerScreen.cart={}
    capture('computer-www-machines',function()
        R.state.screen='computer';R.ComputerScreen.tab='www';R.ComputerScreen.wwwSite=5
    end)
    R.ComputerScreen.wwwSite=1
    local buyX,buyY=R.ComputerScreen.homeShopControlCenter('buy',1)
    R.ComputerScreen.tab='groceries'
    R.ComputerScreen.mousepressed(R.state,buyX,buyY,1)
    capture('computer-home-checkout',function()
        R.state.screen='computer';R.ComputerScreen.tab='groceries'
    end)
    capture('computer-calendar-day',function()
        R.state.screen='computer';R.ComputerScreen.tab='calendar'
        R.ComputerScreen.calendarYear=R.state.calendar.year
        R.ComputerScreen.calendarMonth=R.state.calendar.month
        R.ComputerScreen.calendarSelectedDay=1;R.ComputerScreen.calendarDayOpen=true
    end)
    R.ComputerScreen.calendarDayOpen=false
    capture('computer-warehouse-staging',function()
        R.state.screen='computer';R.ComputerScreen.tab='warehouse'
        R.ComputerScreen.warehouseStagingPage=true
    end)
    R.ComputerScreen.warehouseStagingPage=false
    local receiptBook=require('src.receipt_book')
    local originalReceipts=R.state.receipts
    R.state.receipts=receiptBook.new()
    for index=1,7 do
        receiptBook.add(R.state,{kind='delivery',title='Delivery receipt UI-'..index,
            party='Millhaven Freight',account='Shop',status='received',amountCents=12500,
            details='Shipment UI-'..index..'\n'..string.rep('Wrapped stock pallet delivered to the warehouse.\n',12)})
    end
    capture('computer-receipts-populated',function()
        R.state.screen='computer';R.ComputerScreen.tab='receipts'
        R.ComputerScreen.receiptFilter='all';R.ComputerScreen.receiptPage=1
        R.ComputerScreen.selectedReceiptId=nil;R.ComputerScreen.receiptDetailPage=1
    end)
    receiptBook.add(R.state,{kind='delivery',title='Signed pallet delivery',party='Millhaven Freight',
        account='Shop',status='received',amountCents=12500,
        details='Three wrapped pallets received at the warehouse.\nAll skids inspected before unloading.',
        signature='0000ffff',signedBy='Jamie'})
    capture('computer-receipts-signed',function()
        R.state.screen='computer';R.ComputerScreen.tab='receipts'
        R.ComputerScreen.receiptFilter='all';R.ComputerScreen.receiptPage=1
        R.ComputerScreen.selectedReceiptId=nil;R.ComputerScreen.receiptDetailPage=1
    end)
    R.state.receipts=originalReceipts
    local originalResidents=R.state.home.residents
    R.state.home.residents={owner=originalResidents.owner}
    for index=1,3 do
        R.state.home.residents['guest'..index]={name='Guest '..index,activePlayerId=index+1,
            wageCents=1500+index*100,wagePaidCents=2000,wageEarnedCents=5000+index*800,
            wageRevision=1}
    end
    capture('computer-player_wages-populated',function()
        R.state.screen='computer';R.ComputerScreen.tab='player_wages'
    end)
    R.state.home.residents=originalResidents
    local completedSample=require('src.screens.gui_projection').copy(reviewJob)
    completedSample.id='UI-105';completedSample.status='completed';completedSample.inspection={status='passed'}
    for _,pallet in ipairs(completedSample.pallets) do
        pallet.status='completed';pallet.remainingSheets=0;pallet.finishedSheets=pallet.initialSheets
        pallet.completedLifts=pallet.requiredLifts
    end
    local originalCompleted=R.state.jobs.completed
    R.state.jobs.completed={completedSample}
    capture('computer-completed-sample',function()
        R.state.screen='computer';R.ComputerScreen.tab='completed';R.ComputerScreen.selectedJobId=completedSample.id
    end)
    R.state.jobs.completed=originalCompleted
    local inboundSample=require('src.screens.gui_projection').copy(reviewJob)
    inboundSample.id='UI-106';inboundSample.status='awaiting_delivery'
    inboundSample.delivery={status='scheduled',route={originCity='Millhaven City',originLocation='Freight Yard',
        startAtHours=9,arrivalAtHours=12}}
    local originalActive=R.state.jobs.active
    R.state.jobs.active={inboundSample}
    capture('computer-deliveries-sample',function()
        R.state.screen='computer';R.ComputerScreen.tab='deliveries';R.ComputerScreen.selectedJobId=inboundSample.id
    end)
    R.state.jobs.active=originalActive
    capture('computer-dropdown',function()R.ComputerScreen.tabDropdownOpen=true end)
    R.ComputerScreen.tabDropdownOpen=false
    local reviewJobs=R.state.jobs.active
    local longJob=require('src.screens.gui_projection').copy(reviewJob)
    longJob.id='UI-LONG'
    longJob.company='Millhaven Community Theatre and Regional Performing Arts Workshop'
    longJob.stockSpec={description='Heavy uncoated customer-supplied cover stock; keep grain direction consistent across every finished pallet.'}
    longJob.spoiledSheets=75;longJob.spoilCost=20;longJob.replacementSkids=1;longJob.replacementSheets=500
    longJob.press={colors=4,colorSequence={'Warm Red','Process Blue','Metallic Gold','Black'},actual={impressions=1575,spoilage=75}}
    for i=4,10 do
        local pallet=require('src.screens.gui_projection').copy(longJob.pallets[1])
        pallet.id='UI-LONG-P'..i;pallet.number=i;longJob.pallets[i]=pallet
    end
    capture('computer-active-long',function()
        R.state.screen='computer';R.state.jobs.active={longJob}
        R.ComputerScreen.tab='active';R.ComputerScreen.selectedJobId=longJob.id;R.ComputerScreen.jobScroll=0
    end)
    capture('computer-active-long-bottom',function()
        R.state.screen='computer';R.state.jobs.active={longJob}
        R.ComputerScreen.tab='active';R.ComputerScreen.selectedJobId=longJob.id
        for _=1,40 do R.ComputerScreen.wheelmoved(R.state,0,-1) end
    end)
    R.state.jobs.active=reviewJobs;R.ComputerScreen.selectedJobId=reviewJob.id;R.ComputerScreen.jobScroll=0
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
    capture('notifications-many',function()
        R.state.screen='world'
        local notices=require('src.notifications')
        for i=1,8 do
            notices.add(R.state,'email','Shop note '..i,
                'A short update from the print shop.',
                'The crew completed another part of the job. Check the job desk for details.',
                'ui-clipboard-note-'..i)
        end
        require('src.screens.notifications_screen').open(R)
    end)
    capture('notifications-page-turn',function()
        local screen=require('src.screens.notifications_screen')
        local next=screen.layout(R).rects.next
        screen.pointer(R,next.x+next.width/2,next.y+next.height/2,1)
        if screen.pageTurn then screen.pageTurn.start=love.timer.getTime()-.25 end
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
        local function tap(x,y)
            R.App.mousepressed(ox+x*sx,oy+y*sy,1,false)
            R.App.mousereleased(ox+x*sx,oy+y*sy,1,false)
        end
        tap(R.ComputerScreen.dropdownCenter())
        check('phone_office_actual_app_opens_sprite_navigation',R.ComputerScreen.tabDropdownOpen)
        tap(R.ComputerScreen.tabCenter('inventory'))
        check('phone_office_actual_app_selects_original_content',R.ComputerScreen.tab=='inventory' and not R.ComputerScreen.tabDropdownOpen)
        local _,bounds=R.optionsAccessLayout()
        local options=R.OptionsScreen.accessRect('computer',bounds)
        tap(options.x+options.width/2,options.y+options.height/2)
        check('phone_office_options_remains_reachable',R.state.screen=='options')
        R.state.screen='computer';tap(R.ComputerScreen.closeCenter())
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
        local onFoot=C.localPart(R)
        onFoot.rider.ped.x,onFoot.rider.ped.z=onFoot.rider.bike.x,onFoot.rider.bike.z
        capture('commute-on-foot')
        if mode=='phone' then
            local bounds=C.worldUiBounds(R)
            local cardX=C.cardX(R)
            local mini=C.miniMapRect(R)
            local notice=require('src.screens.warehouse_hud').layoutFor(R,bounds).noticeIcon
            local gear=C.gearTouchButton(R)
            check('commute_phone_hud_uses_screen_edges',bounds and cardX<=bounds.left+20
                and notice.x<=bounds.left+20 and mini.x+mini.width>=bounds.right-20
                and gear and gear.x>=bounds.right-100)
            local gearHit=gear and require('src.commute.touch_controls').actionAt(
                gear.x+gear.width/2,gear.y+gear.height/2,R.Config.baseWidth,R.Config.baseHeight,
                C.touchProfile(R,onFoot),C.controlContext(R,onFoot),{mobile=true,bounds=bounds})
            check('commute_phone_gear_button_has_matching_hit_target',gearHit and gearHit.action=='gear')
            local footX=onFoot.rider.ped.x
            onFoot.rider.ped.x=onFoot.rider.bike.x+5
            check('commute_phone_gear_button_hides_away_from_bike',C.gearTouchButton(R)==nil)
            onFoot.rider.ped.x=footX
        end
        R.App.keypressed('g');for _=1,250 do R.App.update(1/60) end
        R.App.keypressed('e');for _=1,150 do R.App.update(1/60) end
        local part=C.localPart(R)
        if mode=='phone' then
            local bounds=C.worldUiBounds(R)
            local buttons=require('src.commute.touch_controls').actionButtons(R.Config.baseWidth,
                R.Config.baseHeight,C.touchProfile(R,part),C.controlContext(R,part),
                {mobile=true,bounds=bounds,camera=R._commute.camera})
            local byAction={}
            for _,button in ipairs(buttons) do byAction[button.action]=button end
            local stick=C.touchProfile(R,part).layout.stick
            check('commute_phone_driving_controls_use_screen_edges',bounds and stick
                and bounds.left+stick.x*bounds.width<bounds.left+bounds.width*.15
                and byAction.accelerate and byAction.accelerate.x>bounds.left+bounds.width*.80
                and byAction.rescue and byAction.rescue.x<bounds.left+bounds.width*.15)
            local touch=require('src.commute.touch_controls')
            local options={mobile=true,bounds=bounds,camera=R._commute.camera}
            local profile=C.touchProfile(R,part)
            local context=C.controlContext(R,part)
            local go=byAction.accelerate
            local rescue=byAction.rescue
            local goHit=go and touch.actionAt(go.x,go.y,R.Config.baseWidth,R.Config.baseHeight,
                profile,context,options)
            local rescueHit=rescue and touch.actionAt(rescue.x,rescue.y,R.Config.baseWidth,
                R.Config.baseHeight,profile,context,options)
            check('commute_phone_outer_controls_have_matching_hit_targets',goHit and goHit.action=='accelerate'
                and rescueHit and rescueHit.action=='rescue')
        end
        check('commute_warehouse_departure_has_no_forced_home_route',C.activeWaypoint(R)==nil)
        local homeAddress=R.state.home.apartmentId
        check('commute_explicit_home_route_can_be_selected',
            C.setWaypoint(R,homeAddress) and C.activeWaypoint(R)==homeAddress)
        check('commute_explicit_route_can_be_cleared',
            C.setWaypoint(R,homeAddress) and C.activeWaypoint(R)==nil)
        R.state.message=nil
        if R.App.playerFeedback then
            R.App.playerFeedback.statusText=nil;R.App.playerFeedback.statusTimer=0
        end
        capture('commute-bike',function()R._commute.camera:setFirstPerson(false,part.rider.bike)end)
        capture('commute-first-person',function()R._commute.camera:setFirstPerson(true,part.rider.bike)end)
        local _,rideBounds=R.optionsAccessLayout()
        local shared=require('src.screens.warehouse_hud').layoutFor(R,rideBounds)
        local navButton,camButton,mapButton=C.miniMapButton(R),C.cameraButton(R),C.mapButton(R)
        check('commute_compact_toolbar_fits_between_clock_and_menu',
            navButton and camButton and mapButton
            and shared.clock.x+shared.clock.width<navButton.x
            and navButton.x+navButton.width<camButton.x
            and camButton.x+camButton.width<mapButton.x
            and mapButton.x+mapButton.width<shared.menu.x
            and navButton.y==camButton.y and camButton.y==mapButton.y
            and C.miniMapRect(R).y>mapButton.y+mapButton.height)
        local oldHome,oldShop=R.state.home.balanceCents,R.state.money
        R.state.home.balanceCents=9876543;R.state.money=98765.43
        capture('commute-money-long')
        R.state.home.balanceCents,R.state.money=oldHome,oldShop
        capture('commute-camera-menu',function()R._commute.cameraMenu=true end)
        local lockRow=require('src.commute.camera_menu').row(camButton,6,C.miniMapRect(R).x)
        check('commute_camera_menu_lock_toggles_on',
            C.cameraPointer(R,lockRow.x+lockRow.width/2,lockRow.y+lockRow.height/2)
            and require('src.screens.hud_visibility').cameraLocked(R))
        R._commute.cameraMenu=true
        check('commute_camera_menu_lock_toggles_off',
            C.cameraPointer(R,lockRow.x+lockRow.width/2,lockRow.y+lockRow.height/2)
            and not require('src.screens.hud_visibility').cameraLocked(R))
        R._commute.cameraMenu=false
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
    baselineFont:release()
    love.system.getOS=originalOS
    R.saveCurrent=originalSaveCurrent
    R.Save.queue=originalSaveQueue
    R.App.playerFeedback=originalFeedback
    check('ui_readability_all_requested_screens_render',#failures==0,table.concat(failures,'\n'))
    check('ui_readability_rendered_screens',captures>0,tostring(captures))
end
return Test
