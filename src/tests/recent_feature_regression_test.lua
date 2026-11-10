local Test={}

function Test.run(_,check)
    local State=require('src.state')
    local Inventory=require('src.commute.grocery_inventory')
    local Store=require('src.commute.town_store')
    local Schema=require('src.save_schema')
    local Calendar=require('src.business_calendar')
    local state=State.new()
    state.calendar.elapsed=9/24*Calendar.secondsPerDay(state)
    local stock=Inventory.ensure(state)
    local player={id=1}
    local rider={ped={x=1,z=2,crash=false},gear={mounted=false,transition=false},vehicle=nil,transport=nil}
    local world={sites={byId={grocery={door={x=1,z=2}}}}}
    local balance=state.home.balanceCents
    local breadBefore=stock.stock.bread
    local bought,message=Store.purchaseCart(state,player,rider,world,
        {expectedRevision=state.home.revision,cart={bread=2}})
    local cargo=state.home.residents.owner.bikeInventory
    check('grocery_checkout_consumes_shelf_stock_and_loads_bike',bought and stock.stock.bread==breadBefore-2
        and cargo.items.bread==2 and state.home.balanceCents<balance,message)

    local stableStock,stableBalance,stableRevision=stock.stock.meal_pack,state.home.balanceCents,stock.revision
    local oversold=Store.purchaseCart(state,player,rider,world,
        {expectedRevision=state.home.revision,cart={meal_pack=3}})
    check('grocery_checkout_rejects_cart_above_available_stock',not oversold
        and stock.stock.meal_pack==stableStock and state.home.balanceCents==stableBalance
        and stock.revision==stableRevision)
    stock.stock.meal_pack=0
    local view=Store.open('grocery',1);view.storeStock=stock
    Store.category(view,'specials');view.quantity=1
    Store.key(view,'space',state.home.revision,function()end,function()end)
    check('grocery_shelf_ui_reports_out_of_stock',view.cart.meal_pack==nil
        and view.notice and view.notice:find('out of stock',1,true)~=nil)

    state.calendar.totalDays,state.calendar.weekday=1,5
    local delivered=Inventory.arriveFromOutsideConnection(state)
    local afterFriday=stock.stock.bread
    check('grocery_outside_connection_replenishes_on_delivery_day',delivered
        and stock.deliveryCount==1 and afterFriday>breadBefore-2 and stock.nextDeliveryDay==4)
    state.calendar.totalDays,state.calendar.weekday=2,6
    local weekendDelivery=Inventory.arriveFromOutsideConnection(state)
    check('grocery_deliveries_pause_over_weekend',not weekendDelivery and stock.deliveryCount==1
        and stock.stock.bread==afterFriday)
    state.calendar.totalDays,state.calendar.weekday=4,1
    local mondayDelivery=Inventory.arriveFromOutsideConnection(state)
    check('grocery_next_delivery_replenishes_again',mondayDelivery and stock.deliveryCount==2
        and stock.nextDeliveryDay==7)
    local snapshot=assert(Schema.snapshot(state));local replay=State.new()
    check('grocery_stock_and_delivery_schedule_survive_shared_save',State.applySharedSnapshot(replay,snapshot)
        and replay.groceryStore.stock.bread==stock.stock.bread
        and replay.groceryStore.deliveryCount==stock.deliveryCount
        and replay.groceryStore.nextDeliveryDay==stock.nextDeliveryDay)

    local Fleet=require('src.machine_fleet')
    local Machine=require('src.machine')
    local Maintenance=require('src.machine_maintenance')
    local Technician=require('src.technician')
    local Config=require('src.config')
    local Speech=require('src.employee_speech')
    local cutterState=State.new()
    cutterState.calendar.elapsed=require('src.business_calendar').secondsPerDay(cutterState)*10/24
    local machine=Fleet.installed(cutterState,'polar_115')
    local cutter=machine.maintenance.cutter
    cutter.weeklyTechnician=true;cutter.nextTechnicianDay=7;cutter.technicianSequence=0
    cutterState.calendar.totalDays,cutterState.calendar.weekday=7,5
    cutterState.employment.staff={{id=1,name='Robin',status='employed',visible=true,
        assignment={machineId=machine.id,palletId='SKID-007'}}}
    Machine.forId(machine.id).step='loaded'
    check('weekly_blade_exchange_waits_for_active_cutter_skid',Maintenance.updateTechnician(cutterState)
        and cutter.technicianStatus=='waiting_for_skid' and cutterState.technicianVisit==nil)
    Machine.forId(machine.id).step='finished'
    local scheduled=Maintenance.updateTechnician(cutterState)
    local visit=cutterState.technicianVisit
    check('weekly_blade_exchange_arrives_with_sleeved_spare',scheduled and visit and visit.kind=='cutter'
        and visit.bladeKit and visit.bladeKit.woodenSleeve==true and visit.removeInstalledBlade==true
        and love.filesystem.getInfo(Config.paths.woodenBladeSleeve)~=nil)
    check('traveling_blade_exchange_blocks_new_cutter_operation',not Fleet.canOperate(cutterState,'polar_115',machine.id))
    Technician.update(0,cutterState,false)
    for _=1,600 do
        if visit.status=='servicing' then break end
        Technician.update(.1,cutterState,false)
    end
    check('mara_reaches_cutter_before_service',visit.status=='servicing')
    local phase=Config.technician.serviceDuration/3+.01
    Technician.update(phase,cutterState,false)
    check('mara_removes_dull_blade_into_wooden_sleeve',cutter.bladeRemoved and cutter.bladeInSleeve
        and visit.exchangePhase==1)
    Technician.update(phase,cutterState,false)
    check('mara_installs_sharp_replacement_blade',not cutter.bladeRemoved and not cutter.bladeInSleeve
        and machine.variables.bladeSharpness==100 and visit.exchangePhase==2)
    Technician.update(phase,cutterState,false)
    check('mara_completes_staged_blade_exchange',cutter.technicianStatus=='completed'
        and cutter.nextTechnicianDay==14 and visit.status=='exiting')
    local employee=cutterState.employment.staff[1]
    machine.variables.bladeSharpness=50;cutter.bladeDullNoticeSent=false
    Fleet.recordUse(cutterState,'polar_115',0,machine.id)
    check('employee_warns_player_when_blade_gets_low',employee.greetingKind==Speech.EMPLOYEE_BLADE_DULL
        and cutter.bladeDullNoticeSent and cutterState.message:find('blade',1,true)~=nil
        and #Fleet.serviceInbox(cutterState)>0)
end

return Test
