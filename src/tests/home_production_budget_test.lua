-- Optional scripted production probe. Real orders, cutting, wrapping, supplies
-- and payments; ideal controls and staged transport are explicit limitations.
local Test={}
local function scenario(context,check,options)
 local State=require("src.state");local Calendar=require("src.business_calendar")
 local Finance=require("src.household_finances");local Flow=require("src.weekend_flow")
 local Home=require("src.home");local Catalog=require("src.home_catalog")
 local Procurement=require("src.procurement");local Pallets=require("src.pallet_state")
 local Service=require("src.job_service");local Logistics=require("src.pallet_logistics")
 local Config=require("src.config");local Machine=context.machine;local Wrapper=context.wrapper
 local Maintenance=require("src.machine_maintenance");local Technician=require("src.technician")
 local seconds=options.seconds or 1200
 local label=options.apartment.."-"..options.residents.."p-"..options.jobs.."jobs"..(seconds~=1200 and ("-"..seconds.."s") or "")
 local verify=check;check=function(name,passed,detail)return verify(name.."_"..label,passed,detail) end
 local s=State.new();s.home=Home.new({apartmentId=options.apartment});s.screen="world";s.calendar.secondsPerDay=seconds
 local residents={{id=1,sceneId="warehouse",x=720,y=202}}
 for i=2,options.residents do
  residents[i]={id=i,sceneId="warehouse",x=720+i*12,y=202}
  assert(require("src.home_residents").bind(s,residents[i],string.rep(tostring(i),64),residents))
 end
 local initialCash=s.money;local elapsed,decisionSeconds,transportSeconds=0,0,0
 local purchases,billsPaid,receipts,homeSpent=0,0,0,0;local firstPay,firstRentShortfall;local maximumArrears=0
 local report={"Scripted natural-order production / household cash-flow probe.",
  string.format("Fresh $180 business; default stock, cutter and wrapper; no employees or loans; %g-minute game day.",seconds/60),
  "Real catalog orders, recipe cuts/lifts, wrap consumption, supplier purchases and pickup payments.",
  "Ideal machine controls; 1 real second per decision and 10 per staged pallet transfer.",
  "Delivery delays advance the game calendar. Transport uses state transitions, not physical driving.",
  "Truck schedule/door/backing durations are included; pickup commands bypass manual truck/GUI control.",
  "This is a scripted operating scenario, not a measured human throughput guarantee."}
 report[#report+1]=string.format("scenario=%s monthly_rent=%.2f resident_count=%d weekly_job_limit=%d pay_percent=%d",label,s.home.lease.monthlyCents/100,options.residents,options.jobs,s.home.payPercent)
 local function advance(seconds)
  assert(seconds>=0);Calendar.update(s,seconds);Finance.accrue(s);elapsed=elapsed+seconds
 end
 local function waitUntil(hours)advance(math.max(0,hours-Calendar.absoluteHours(s))*Calendar.secondsPerDay(s)/24) end
 local function decide()advance(1);decisionSeconds=decisionSeconds+1 end
 local function rotateToCut(pallet,cutNumber)
  local target=pallet.paper.cuts[cutNumber].orientation
  for _=1,4 do
   if pallet.paper.orientation==target then break end
   assert(Machine.keypressed("q",s),"Unable to rotate paper for programmed cut")
  end
  assert(pallet.paper.orientation==target,"Paper rotation did not reach programmed cut")
 end
 local function transfer(pallet,x,y)
  assert(Pallets.transition(s,pallet,"on_pallet_jack"))
  advance(10);transportSeconds=transportSeconds+10
  assert(Pallets.transition(s,pallet,"warehouse",{world={x=x,y=y,fromX=x,fromY=y,direction="northwest",rotation=1,spawnProgress=1,sceneId="warehouse"}}))
 end
 local function supplies(index)
  local before=s.money;local ok,order=Procurement.buyRetail(s,3,index);assert(ok,order)
  purchases=purchases+before-s.money;waitUntil(order.delivery.expectedAtHours)
  assert(Procurement.unload(s,order.id,order.pallets[1].id,Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin))
  transfer(order.pallets[1],440+(#s.procurement.orders%4)*45,565)
 end
 local function service(close)
  local item,cutter=Maintenance.cutterStatus(s)
  if item.variables.bladeSharpness>=55 and not cutter.bladeRemoved then return true end
  if not cutter.bladeRemoved then assert(Maintenance.prepareBladeForTechnician(s));assert(Maintenance.requestTechnician(s)) end
  while cutter.bladeRemoved do
   if cutter.nextTechnicianDay then
    local appointment=cutter.nextTechnicianDay*24+9
    if appointment>=close then return false end
    waitUntil(math.max(Calendar.absoluteHours(s),appointment));Maintenance.updateTechnician(s)
   end
   if s.technicianVisit then
    local seconds=0
    while s.technicianVisit do
     advance(.1);Technician.update(.1,s,false);seconds=seconds+.1
     assert(seconds<120,"Technician failed to finish the scripted route")
    end
    report[#report+1]=string.format("blade_exchange date=%.2fh route_seconds=%.1f charge=0 (current game rule)",Calendar.absoluteHours(s),seconds)
   end
  end
  return true
 end
 local function complete(job)
  local started=Calendar.absoluteHours(s);local startedSeconds=elapsed
  assert(Service.acceptOffer(s,job,1));waitUntil(job.delivery.readyAtHours)
  local cuts,lifts=0,0
  for _,pallet in ipairs(job.pallets) do
   assert(Logistics.unload(s,job.id,pallet.id,Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin))
   local x,y=context.CutterZones.inputAnchor(s,Config.cutterPlacement);transfer(pallet,x,y)
   assert(Machine.reset(s)~=false);assert(Machine.load(s),s.message)
   advance(Machine.transferTime+.01);Machine.update(Machine.transferTime+.01,s)
   repeat
    lifts=lifts+1
    for cut=1,4 do
     decide();Machine.selectProgram(cut,s);rotateToCut(pallet,cut)
     Machine.setGauge(pallet.paper.cuts[cut].gauge,s);Machine.saveGauge(s);Machine.autoGauge(s)
     assert(Machine.position(s),s.message);advance(Machine.transferTime+.01);Machine.update(Machine.transferTime+.01,s)
     decide();Machine.toggleClamp(s);Machine.keypressed("j",s);Machine.keypressed("k",s)
     Machine.keyreleased("j");Machine.keyreleased("k");Machine.update(.01,s);advance(.01)
     advance(Machine.cycleTime+.05);Machine.update(Machine.cycleTime+.05,s);cuts=cuts+1
    end
    assert(pallet.paper.status=="complete",s.message);assert(Machine.unload(s),s.message)
    advance(Machine.transferTime+.01);Machine.update(Machine.transferTime+.01,s)
    if pallet.remainingSheets>0 then
     assert(Machine.repeatLift(s),s.message);advance(Machine.transferTime+.01);Machine.update(Machine.transferTime+.01,s)
    end
   until pallet.remainingSheets==0
   assert(pallet.location=="cutter_output" and pallet.status=="cut",s.message)
   transfer(pallet,s.wrapper.x-60,s.wrapper.y)
   if s.inventory.plasticWrapUses<1 then supplies(2) end
   local cartons=Procurement.cartonsRequired(job,pallet)
   while Procurement.cartonsAvailable(s)<cartons do supplies(1) end
   assert(Wrapper.reset(s)~=false);assert(Wrapper.start(s),s.message)
   advance(Wrapper.cycleTime+.01);Wrapper.update(Wrapper.cycleTime+.01,s)
   assert(pallet.wrapped and pallet.status=="wrapped",s.message)
   -- Move finished output clear before the next skid uses the same machine.
   transfer(pallet,580+pallet.number*45,540)
  end
  local accepted,reason=Service.requestPickup(s,job,2);assert(accepted,reason);assert(Service.schedulePickup(job,3))
  advance(Config.truck.scheduleDelay+Config.loadingBay.duration+Config.truck.backingDuration+Config.truck.cargoDuration)
  for _,pallet in ipairs(job.pallets) do decide();assert(Service.loadForPickup(s,job.id,pallet.id,4)) end
  advance(Config.truck.cargoDuration+Config.truck.backingDuration)
  local before=s.money;assert(Service.completePickup(s,job.id,5));receipts=receipts+s.money-before
  check("home_production_paid_once_"..job.id,not Service.completePickup(s,job.id,6) and s.money==before+job.paymentAmount)
  check("home_production_actual_output_"..job.id,job.inspection.status=="passed" and job.paymentAmount==job.quote.totalPrice
   and Finance.ensure(s).totals.revenue==math.floor(receipts*100+.5))
  report[#report+1]=string.format("job=%s company=%s price=%.2f pallets=%d lifts=%d cuts=%d start=%.2fh end=%.2fh elapsed_real=%.1fs",
   job.id,job.company,job.paymentAmount,#job.pallets,lifts,cuts,started,Calendar.absoluteHours(s),elapsed-startedSeconds)
 end
 local ok,err=xpcall(function()
  context.world.load();Machine.reset(s);Wrapper.reset(s)
  for week=1,9 do
   local close=s.home.weekend.closesAtHours;local count=0
   for _=1,week==1 and 1 or options.jobs do
    if not service(close) then break end
    local job=assert(Service.createNextOffer(s,1));local liftCount=0
    for _,p in ipairs(job.pallets) do liftCount=liftCount+math.ceil(p.initialSheets/500) end
    -- Reserve enough time for controls, supplier restocking and shipping.
    local forecast=job.deliveryService.delayHours+(liftCount*35+#job.pallets*35+60)*24/Calendar.secondsPerDay(s)+8
    if Calendar.absoluteHours(s)+forecast>close then break end
    complete(job);count=count+1
   end
   assert(Calendar.absoluteHours(s)<=close,"Scripted work crossed Friday shutdown")
   waitUntil(close);assert(Flow.update(s,true));local pay=s.home.finance.history[#s.home.finance.history]
   assert(Flow.depart(s,s.home.revision))
   local Shopping=require("src.home_shopping");local Residents=require("src.home_residents");local Layout=require("src.home_layouts")
   local owner=residents[1]
   for _,p in ipairs(residents) do p.sceneId="home";p.x,p.y=Layout.spawn(s,p.id) end
   local function order(product,kind,quantity)
    local before=s.home.balanceCents
    assert(Shopping.order(s,owner,{kind=kind,productId=product,quantity=quantity or 1,requestId="production-"..week..product,expectedRevision=s.home.revision}))
    homeSpent=homeSpent+before-s.home.balanceCents
   end
   if week==1 then order("bed","home_order_furniture") end
   local needed=options.residents*2-(s.home.inventory.basic_meal or 0)
   if needed>0 then order("meal_pack","home_order_food",math.ceil(needed/4)) end
   waitUntil(close+2)
   if Shopping.waiting(s)>0 then local target=assert(Shopping.target(owner,s));owner.x,owner.y=target.x,target.y;assert(Shopping.collect(s,owner)) end
   for _,hour in ipairs({close+22,close+46}) do
    waitUntil(hour)
    for _,p in ipairs(residents) do assert(Residents.command(s,p,"eat:floor")) end
    local activity=Residents.get(s,owner).activity;local start=Calendar.absoluteHours(s)
    waitUntil(activity.endsAt);Residents.advance(s,residents,start,Calendar.absoluteHours(s))
   end
   waitUntil(s.home.weekend.opensAtHours);Residents.recover(s)
   local rent=Home.amountDue(s.home)
   if rent>0 and s.home.balanceCents>=rent then assert(Home.payRent(s.home,s.home.revision)) end
   if pay.paidCents>0 and not firstPay then firstPay=week end
   maximumArrears=math.max(maximumArrears,Home.amountDue(s.home))
   if Home.amountDue(s.home)>0 and not firstRentShortfall then firstRentShortfall=week end
   if s.bills.balance>0 and s.money>=s.bills.balance then local due=s.bills.balance;assert(Calendar.pay(s));billsPaid=billsPaid+due end
   check("home_production_conservation_week_"..week,math.abs(s.money-(initialCash+receipts-purchases-billsPaid-(s.home.balanceCents-Catalog.ALLOWANCE_CENTS+s.home.lease.paidCents+homeSpent)/100))<.001)
   local snapshot,why=require("src.save_schema").snapshot(s)
   check("home_production_valid_save_week_"..week,require("src.save_schema").validState(snapshot),
    tostring(why).." home="..tostring(Home.valid(s.home)).." finance="..tostring(Finance.valid(s.home.finance)).." calendar="..tostring(Calendar.valid(s.calendar,s.bills))
     ..string.format(" flow=%s closed=%.17g expected=%.17g",tostring(Flow.valid(s.home.weekend)),s.home.weekend.closedAtHours or -1,s.home.weekend.closesAtHours))
   report[#report+1]=string.format("week=%d jobs=%d sales=%.2f consumed=%.2f operating=%.2f eligible=%.2f pay=%.2f household=%.2f rent_due=%.2f business=%.2f bills_due=%.2f",
    week,count,pay.costs.revenue/100,pay.costs.materials/100,pay.costs.operating/100,pay.eligibleCents/100,pay.paidCents/100,s.home.balanceCents/100,Home.amountDue(s.home)/100,s.money,s.bills.balance)
   assert(Flow.returnToWork(s,s.home.revision))
   for _,p in ipairs(residents) do p.sceneId="warehouse" end
  end
  if options.jobs==4 then
   check("home_production_funds_two_rent_invoices_and_business_bills",s.home.lease.invoiceCount==2
    and s.home.lease.paidCents==2*s.home.lease.monthlyCents and Home.amountDue(s.home)==0
    and s.home.balanceCents>0 and s.bills.balance==0 and s.money>0)
  else
   check("home_production_low_workload_explains_shortfall",not firstPay and Home.amountDue(s.home)>0 and s.bills.balance>0
    and require("src.home_budget").summary(s).lastPayReason=="no_earnings")
  end
  report[#report+1]=string.format("totals jobs=%d receipts=%.2f purchases=%.2f bills_paid=%.2f household_purchases=%.2f decisions=%.1fs staged_transport=%.1fs",#s.jobs.completed,receipts,purchases,billsPaid,homeSpent/100,decisionSeconds,transportSeconds)
 end,debug.traceback)
 report[#report+1]=ok and "PROBE_COMPLETE" or ("PROBE_STOPPED: "..tostring(err))
 local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR") or "output/home-implementation"
 local file=assert(io.open(folder.."/home-production-"..label..".txt","wb"));file:write(table.concat(report,"\n").."\n");file:close()
 Machine.reset(s);Wrapper.reset(s);context.world.load();Machine.reset(context.state);Wrapper.reset(context.state)
 assert(ok,err)
 return {label=label,jobs=#s.jobs.completed,firstPay=firstPay or 0,firstRentShortfall=firstRentShortfall or 0,
  maximumArrears=maximumArrears/100,arrears=Home.amountDue(s.home)/100,household=s.home.balanceCents/100,
  business=s.money,bills=s.bills.balance,homeSpent=homeSpent/100,revenue=receipts}
end
function Test.run(context,check)
 local rows={"scenario,jobs,first_paid_week,first_rent_shortfall_week,max_rent_arrears,ending_rent_arrears,household_cash,business_cash,business_bills,household_purchases,collected_revenue"}
 local summaries={}
 for _,id in ipairs(require("src.home_catalog").ORDER) do for _,count in ipairs({1,4}) do
  summaries[#summaries+1]=scenario(context,check,{apartment=id,residents=count,jobs=4})
 end end
 summaries[#summaries+1]=scenario(context,check,{apartment="brick-walkup",residents=1,jobs=1})
 for _,seconds in ipairs({300,3600}) do
  summaries[#summaries+1]=scenario(context,check,{apartment="brick-walkup",residents=1,jobs=4,seconds=seconds})
 end
 for _,r in ipairs(summaries) do
  rows[#rows+1]=string.format("%s,%d,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",r.label,r.jobs,r.firstPay,r.firstRentShortfall,r.maximumArrears,r.arrears,r.household,r.business,r.bills,r.homeSpent,r.revenue)
 end
 local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR") or "output/home-implementation"
 local file=assert(io.open(folder.."/home-production-summary.csv","wb"));file:write(table.concat(rows,"\n").."\n");file:close()
end
return Test
