local State=require('src.state')
local Jobs=require('src.jobs')
local Service=require('src.job_service')
local Run=require('src.commute.delivery_run')
local Loading=require('src.player_delivery_loading')
local Town=require('src.commute.town')
local Calendar=require('src.business_calendar')
local Test={}

local function job(state,id,count,mode,destination,customer)
    local counts={};for _=1,count do counts[#counts+1]=500 end
    local value=assert(Jobs.createOffer({id=id,company=destination and ('Town '..destination) or ('Client '..id),
        customerDestination=destination,sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts=counts,
        outboundDelivery=customer and {transport='customer'} or nil}))
    Jobs.accept(value);value.status='in_production';value.delivery={status='received'}
    state.jobs.active[#state.jobs.active+1]=value
    for i,p in ipairs(value.pallets) do
        p.location,p.status,p.wrapped,p.remainingSheets='warehouse','wrapped',true,0
        p.finishedSheets=p.initialSheets;p.completedLifts=p.requiredLifts
        p.world={x=350+i*60,y=500,sceneId='warehouse',direction='northwest',spawnProgress=1}
        state.inventory.finishedPallets=(state.inventory.finishedPallets or 0)+1
    end
    assert(Service.requestPickup(state,value,100,mode));value.pickup.dispatchAtHours=0
    return value
end

local function capture(name,draw)
    local directory=os.getenv('PICTURE_SHOP_PLAYER_DELIVERY_CAPTURE')
    if not directory then return end
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear(.02,.03,.04,1)
    draw();love.graphics.pop()
    local data=canvas:newImageData();local bytes=data:encode('png')
    local file=assert(io.open(directory..'/'..name..'.png','wb'));file:write(bytes:getString());file:close()
    bytes:release();data:release();canvas:release()
end

local function playerManifest(context,check,town,world)
    local state=State.new();state.home.town=town
    state.calendar.elapsed=Calendar.secondsPerDay(state)*9/24
    state.home.townCharacters=require('src.commute.town_characters').defaultState(town)
    local a=job(state,'MIXED-A',1,'player','grocery')
    local b=job(state,'MIXED-B',1,'player','diner')
    local c=job(state,'MIXED-C',1,'player')
    local customer=job(state,'CUSTOMER-COLLECT',1,'employee',nil,true)
    local large=job(state,'LARGE',5,'player')
    local overflow=job(state,'OVERFLOW',3,'player')
    local fitting=job(state,'FITTING',2,'player')
    check('multi_job_capacity_checks_pallets_across_clients_before_reserving',
        not Run.build(state,{a.id,b.id,c.id,large.id,overflow.id},world,'player') and a.status=='ready_for_pickup'
        and Run.build(state,{a.id,b.id,c.id,large.id,fitting.id},world,'player').palletCount==10)
    local Controls=require('src.home_travel_controls')
    local sent
    local planner={state=state,_commute={world=world},World={player={id=1,sceneId='warehouse'}},
        multiplayer={isClient=function()return true end,requestInteraction=function(_,resource,command)
            sent={resource,command};return true end}}
    state.screen='home_travel'
    Controls.keypressed('d',planner)
    Controls.mousepressed(200,495,1,planner)
    local selected=planner._deliveryPlanner.selected
    capture('multi-job-planner',function()Controls.draw(planner)end)
    check('multi_job_planner_fill_truck_selects_ten_and_excludes_customer_transport',
        selected[a.id] and selected[b.id] and selected[c.id] and selected[large.id] and selected[fitting.id]
        and not selected[overflow.id] and not selected[customer.id])
    Controls.keypressed('return',planner)
    check('multi_job_planner_submits_all_selected_jobs_for_host_validation',sent and sent[1]=='homeTravel'
        and sent[2]=='delivery:MIXED-A,MIXED-B,MIXED-C,LARGE,FITTING')
    state.screen='world'
    local run=assert(Run.build(state,{a.id,b.id,c.id,large.id,fitting.id},world,'player'))
    local Codec=require('src.net.codec')
    local bad=assert(Codec.decode(assert(Codec.encode(run))))
    bad.stops[2].jobIds={a.id}
    check('multi_job_route_rejects_duplicate_or_missing_stop_assignments',not Run.valid(bad,state.home))
    local player={id=1,homeResidentId='owner',sceneId='warehouse',character='rabbit-worker'}
    local _,trip=assert(require('src.commute.free_travel').enter(state,player,world,run,{player}))
    local bay=world.sites.byId.warehouse
    trip.truck.x,trip.truck.z,trip.truck.h=bay.truckParking.x,bay.truckParking.z,bay.truckParking.h
    trip.truck.heading=bay.yaw;trip.truck.speed=0
    local warehouse=context.world
    warehouse.load();warehouse._state=state
    assert(Loading.sync(state,warehouse.truck,warehouse.bayDoor))
    warehouse.truck.state='cargo_open';warehouse.truck.cargoProgress=1
    local Authority=require('src.truck_authority')
    local view=Authority.view(state,warehouse,1)
    check('multi_job_loading_manifest_lists_every_client_and_destination',#view.items==3 and view.remaining==10
        and view.pageCount==4
        and view.items[1].detail:find('grocery',1,true) and view.items[2].detail:find('diner',1,true)
        and view.items[3].detail:find('Millhaven',1,true))
    local Screen=require('src.screens.truck_inventory_screen')
    capture('multi-job-cargo',function()Screen.draw(state,warehouse,context.assets,0,0)end)
    local x,y=Screen.unloadButtonCenter(3)
    local loaded=Screen.mousepressed(state,warehouse,x,y,1)
    check('multi_job_player_can_load_a_later_client_before_the_first',loaded and loaded.remaining==9
        and c.pallets[1].location=='outbound_truck' and a.pallets[1].location=='warehouse')
    check('multi_job_customer_arranged_pallet_cannot_enter_player_truck',
        not warehouse.loadPickupPallet(state,customer.pallets[1].id) and customer.pallets[1].location=='warehouse')
    assert(warehouse.loadPickupPallet(state,a.pallets[1].id))
    check('multi_job_closing_requires_every_client_loaded',not warehouse.closeTruckAfterUnload(state)
        and not Authority.view(state,warehouse,1).canClose)
    local target=warehouse.truck:getInteraction()
    local guest={id=2,x=target.x,y=target.y,sceneId='warehouse'}
    local saves=0
    local authority=require('src.workshop_authority').new({tokenGenerator=function(n)return 'multi-'..n end,
        resources={truck=Authority.resource({state=state,world=warehouse,save=function()saves=saves+1 end})}})
    local grant=authority:acquire(guest,{requestId=1,resourceId='truck'},{})
    assert(grant.accepted,grant.message)
    check('multi_job_guest_manifest_fits_the_multiplayer_protocol',require('src.net.protocol').encode('workshop_grant',{
        sessionId='mixed-delivery',requestId=1,resourceId='truck',granted=true,leaseId=grant.leaseId,
        code='granted',message='Truck manifest connected.',revision=grant.revision,view=grant.data})~=nil)
    local command={requestId=2,resourceId='truck',leaseId=grant.leaseId,action='move_item',
        args={itemIndex=2},expectedRevision=grant.revision}
    local result=authority:command(guest,command,{})
    local replay=authority:command(guest,command,{})
    check('multi_job_guest_load_resolves_the_correct_client_exactly_once',result.accepted and replay.accepted
        and b.pallets[1].location=='outbound_truck' and saves==1 and result.data.remaining==7
        and not result.data.canClose and result.data.manifestId==view.manifestId)
    for page=2,4 do
        assert(Screen.mousepressed(state,warehouse,803,429,1).action=='page_changed')
        for row=1,(page==4 and 1 or 3) do
            x,y=Screen.unloadButtonCenter(row)
            assert(Screen.mousepressed(state,warehouse,x,y,1).action=='loaded')
            Loading.sync(state,warehouse.truck,warehouse.bayDoor)
        end
    end
    check('multi_job_all_ten_pallets_load_across_pages_without_resetting_the_manifest',
        select(1,Run.loadingProgress(state,run))==10 and Screen.page==4
        and Authority.view(state,warehouse,4).remaining==0 and customer.pallets[1].location=='warehouse')
    warehouse.load()
end

local function employeeRun(context,check,town,world)
    local state=State.new();state.home.town=town;state.money=10000
    state.home.townCharacters=require('src.commute.town_characters').defaultState(town)
    state.calendar.elapsed=Calendar.secondsPerDay(state)*9.5/24
    local Employees=require('src.employees')
    local applicant=assert(Employees.createApplicant(state,0));applicant.shiftPreference='flexible'
    Employees.requestResume(state,applicant.id,0);Employees.advance(state,.5)
    assert(Employees.command(state,{kind='offer_employee',applicationId=applicant.id,expectedRevision=applicant.revision,
        wageCents=math.max(2400,applicant.requestedWage),days=31,startHour=9,endHour=17},.5))
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind='hire_employee',applicationId=applicant.id,expectedRevision=applicant.revision},1.25))
    local worker=state.employment.staff[1]
    worker.visible,worker.clockedIn,worker.phase,worker.sceneId,worker.x,worker.y=true,true,'idle','warehouse',560,550
    worker.shiftDay,worker.breaksTaken,worker.drivingSkill=0,3,75
    state.employment.lastAtHours=Calendar.absoluteHours(state)
    local a=job(state,'EMP-A',2,'employee','grocery')
    local b=job(state,'EMP-B',3,'employee')
    local c=job(state,'EMP-C',5,'employee')
    local overflow=job(state,'EMP-OVERFLOW',1,'employee')
    local customer=job(state,'EMP-CUSTOMER-COLLECT',1,'employee',nil,true)
    local player=job(state,'EMP-PLAYER-RESERVED',1,'player')
    local Company=require('src.company_delivery_driver')
    local now=Calendar.absoluteHours(state)
    state.calendar.elapsed=Calendar.secondsPerDay(state)*19.99/24
    worker.contract.startHour,worker.contract.endHour=16,23
    Company.update(state,Calendar.absoluteHours(state))
    check('multi_job_employee_does_not_dispatch_route_that_cannot_finish_before_business_closes',
        not Company.ensure(state).deliveryRun and a.pallets[1].location=='warehouse')
    state.calendar.elapsed=Calendar.secondsPerDay(state)*now/24
    worker.contract.startHour,worker.contract.endHour=9,17
    assert(Company.update(state,now))
    local company=Company.ensure(state)
    local run=company.deliveryRun
    check('multi_job_employee_dispatch_batches_ten_pallets_from_three_clients',run and run.palletCount==10
        and #run.jobIds==3 and run.stops[1].id=='grocery' and #run.stops==3
        and company.vehicleModel=='box' and select(1,Run.loadingProgress(state,run))==10,
        ('run=%s status=%s pending=%s activity=%s shift=%.2f-%.2f message=%s'):
            format(tostring(run and run.palletCount),tostring(company.status),
                tostring(company.pendingDriverEmployeeId),tostring(worker.activity),
                worker.contract.startHour,worker.contract.endHour,tostring(state.message)))
    check('multi_job_employee_leaves_overflow_player_jobs_and_customer_pickups',overflow.status=='ready_for_pickup'
        and customer.status=='ready_for_pickup' and player.status=='ready_for_pickup'
        and overflow.pallets[1].location=='warehouse' and customer.pallets[1].location=='warehouse')
    local warehouse=context.world;warehouse.load();warehouse._state=state
    warehouse.player.x,warehouse.player.y=930,640
    warehouse.configureEmployees({players=function()return {} end,canClaim=function()return false end})
    local epoch=os.time()
    for step=1,1800 do
        Calendar.update(state,.1);now=Calendar.absoluteHours(state)
        warehouse.updateSimulation(.1,context.assets,state,.1)
        Company.updateExterior(state,world,epoch+step*.1,now)
        if not company.departureStage then break end
    end
    check('multi_job_employee_boards_and_departs_with_the_whole_load',not company.departureStage
        and run.status=='driving' and company.nextActionAtHours and worker.awayForDelivery,
        ('stage=%s run=%s next=%s away=%s phase=%s activity=%s pose=%.1f,%.1f'):format(
            tostring(company.departureStage),run.status,tostring(company.nextActionAtHours),
            tostring(worker.awayForDelivery),tostring(worker.phase),tostring(worker.activity),worker.x,worker.y))
    local before,payment=state.money,a.quote.totalPrice+b.quote.totalPrice+c.quote.totalPrice
    assert(Company.update(state,company.nextActionAtHours))
    check('multi_job_employee_local_stop_keeps_city_cargo_onboard',#state.jobs.completed==1
        and b.pallets[1].location=='outbound_truck' and c.pallets[1].location=='outbound_truck'
        and company.deliveryRun.stopIndex==2)
    local Schema=require('src.save_schema')
    local saved=assert(Schema.snapshot(state))
    assert(context.save.save(3,state,warehouse.snapshot()))
    local payload=assert(context.save.load(3));context.save.delete(3)
    local restored=State.new();assert(State.applySave(restored,payload));state=restored;company=Company.ensure(state)
    check('multi_job_employee_route_restores_after_first_customer_delivery',Schema.validState(saved)
        and company.deliveryRun.stopIndex==2 and company.deliveryRun.palletCount==10)
    for _=1,5 do
        if not company.deliveryRun then break end
        assert(Company.update(state,company.nextActionAtHours))
    end
    check('multi_job_employee_delivers_all_clients_pays_once_and_returns_empty',company.status=='parked'
        and not company.deliveryRun and #state.jobs.completed==3 and state.money==before+payment
        and Service.pickupInventory(state,overflow.id).status=='ready_for_pickup')
    local receipts=require('src.receipt_book').list(state,'job');local paid=0
    for _,receipt in ipairs(receipts) do paid=paid+receipt.amountCents end
    check('archive_delivery_route_files_one_payment_per_completed_job',#receipts==3 and paid==payment*100
        and require('src.receipt_book').valid(state.receipts))
    warehouse.configureEmployees({});warehouse.load()
end

function Test.run(context,check)
    local town=assert(Town.generate(712345));local world=Town.world(town)
    playerManifest(context,check,town,world)
    employeeRun(context,check,town,world)
end
return Test
