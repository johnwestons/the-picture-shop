local Harness=require("src.tests.support.network_impairment_harness")
local Session=require("src.net.session")
local Protocol=require("src.net.protocol")
local Workshop=require("src.workshop_authority")
local Office=require("src.office_authority")
local Intent=require("src.office_intent")
local PhoneAuthority=require("src.phone_authority")
local Phone=require("src.work_phone")
local Calendar=require("src.business_calendar")
local Test={}
local function worker(x,y)
    return {x=x,y=y,velocityX=0,velocityY=0,intentX=0,intentY=0,moving=false,facing=1,
        animationDistance=0,character="rabbit-worker"}
end
local function event(events,kind)
    for _,item in ipairs(events) do if item.type==kind then return item end end
end
function Test.run(context,check)
    local state=context.State.new(); state.money=10000
    local saves,inRange=0,true
    local options={state=state,save=function() saves=saves+1 end,world={validateNetworkWorkshopAccess=function()
        return inRange,inRange and "available" or "out_of_range","Move closer to the workstation."
    end}}
    local authority=Workshop.new({tokenGenerator=function(n) return "office-phone-"..n end,resources={
        work_phone=PhoneAuthority.resource(options),office_computer={
            canAcquire=function() return true end,onAcquire=function() return true,"acquired","Office connected.",{} end,
            commands={office_action=Office.command(options)}}}})
    local network=Harness.new({maxClients=1,classify=function(bytes) local value=Protocol.decode(bytes); return value and value.type or "invalid" end})
    local host=Session.new({transportFactory=network.factory})
    local guest=Session.new({transportFactory=network.factory})
    local hp,gp=worker(100,100),worker(110,100)
    local hc={localPlayer=hp,resolveGuestSpawn=function() return 110,100 end,moveRemote=function() end,
        touchWorkshop=function(p) authority:touchPlayer(p) end,updateWorkshop=function() authority:update({}) end,
        getShopSnapshot=function() return {state={money=state.money,screen="world",inventory={paper=0,prints=0},
            jobs={active={},completed={}},workPhone=state.workPhone},player={x=hp.x,y=hp.y,character=hp.character}} end,
        getWorkshopSnapshot=function() return {resources=authority:snapshot(),wrapper={step="idle",progress=0,cycleTime=3,pallets={}}} end}
    hc.performWorkshop=function(p,kind,payload)
        if kind=="workshop_acquire" then return authority:acquire(p,{requestId=payload.requestId,resourceId=payload.resourceId},{}) end
        if kind=="workshop_release" then return authority:release(p,{requestId=payload.requestId,resourceId=payload.resourceId,leaseId=payload.leaseId,reason=payload.reason},{}) end
        return authority:command(p,{requestId=payload.commandId,resourceId=payload.resourceId,leaseId=payload.leaseId,
            action=payload.action,expectedRevision=payload.expectedRevision,args={callId=payload.callId,officeIntent=payload.officeIntent}},{})
    end
    local gc={localPlayer=gp,inputX=0,inputY=0}
    local hs=host:startHost({name="Office Host",character="rabbit-worker",addressOptions={socket={dns={
        gethostname=function() return "gui-host" end,getaddrinfo=function() return {{addr="192.168.1.93"}} end}}}})
    host.sessionId="office-phone-test"
    local gs=guest:startClient("192.168.1.93:22122",{name="Office Guest",character="rabbit-worker"})
    guest.clientNonce="office-phone-guest"
    guest:update(0,gc); host:update(0,hc); guest:update(0,gc); host:update(0.1,hc); guest:update(0,gc)
    guest:drainEvents(); host:drainEvents()
    check("office_phone_session_connects",hs and gs and guest.ready)
    local function pump() host:update(0,hc); guest:update(0,gc); return guest:drainEvents() end
    local function acquire(resource)
        guest:requestWorkshopAcquire(resource)
        local grant=event(pump(),"workshop_grant")
        check("office_phone_acquires_"..resource,grant and grant.granted)
        return grant
    end
    local commands=0
    local function command(action,args,duplicate)
        commands=commands+1
        if duplicate then network:duplicateNext("client_to_host",1,1,true) end
        local sent=guest:requestWorkshopCommand(action,args)
        local result=event(pump(),"workshop_result")
        check("office_phone_receives_"..action.."_result_"..commands,sent and result~=nil)
        return result
    end
    Phone.queueCall(state,{kind="service_order",caller="Otis Wrench",role="SUPPLIER",subject="MAINTENANCE KIT",
        message="Would you like a kit?",categoryIndex=4,itemIndex=1})
    local callId=state.workPhone.incoming.id
    local grant=acquire("work_phone")
    local busy=authority:acquire({id=3},{requestId=1,resourceId="work_phone"},{})
    check("phone_lease_prevents_two_workers_answering",not busy.accepted and busy.code=="resource_busy")
    local reply=command("phone_respond",{callId=callId})
    check("phone_cannot_order_before_answering",not reply.accepted and saves==0)
    reply=command("phone_answer",{callId=callId},true)
    check("phone_answer_round_trip_is_exactly_once",reply.accepted and state.workPhone.incoming.answered and saves==1)
    local before=state.money
    reply=command("phone_respond",{callId=callId},true)
    check("phone_order_round_trip_is_exactly_once",reply.accepted and #state.procurement.orders==1 and state.money<before
        and state.workPhone.incoming==nil and #state.workPhone.history==1 and saves==2)
    Phone.queueCall(state,{kind="customer_order",caller="Another Client",role="CUSTOMER",subject="NEW JOB",message="Please quote our order."})
    local newId=state.workPhone.incoming.id
    reply=command("phone_dismiss",{callId=callId})
    check("phone_stale_call_cannot_dismiss_new_caller",not reply.accepted and state.workPhone.incoming.id==newId and saves==2)
    inRange=false; reply=command("phone_answer",{callId=newId})
    check("phone_rechecks_host_range_for_every_action",not reply.accepted and reply.code=="out_of_range" and saves==2)
    inRange=true; reply=command("phone_dismiss",{callId=newId})
    check("phone_guest_can_decline_current_call",reply.accepted and saves==3 and state.workPhone.incoming==nil)
    guest:releaseWorkshop("closed"); pump()
    check("phone_exit_releases_for_next_worker",authority:acquire({id=3},{requestId=2,resourceId="work_phone"},{}).accepted)

    acquire("office_computer")
    before=state.money
    local intent={kind="checkout",items={{kind="supply",categoryIndex=1,itemIndex=1,quantity=2}}}
    reply=command("office_action",{officeIntent=intent},true)
    local price=context.procurement.categories[1].items[1].retailPrice
    check("office_cart_round_trip_uses_host_prices_exactly_once",reply.accepted and #state.procurement.orders==3
        and state.money==before-price*2 and saves==4)
    Calendar.addCharge(state,"Spoiled customer stock",123,"GUI-CLAIM")
    before=state.money
    reply=command("office_action",{officeIntent={kind="pay_bills"}},true)
    check("office_guest_pays_host_bills_once",reply.accepted and state.money==before-123 and state.bills.balance==0 and saves==5)
    inRange=false
    reply=command("office_action",{officeIntent=intent})
    check("office_payment_rechecks_range",not reply.accepted and reply.code=="out_of_range" and saves==5)
    inRange=true
    local invalid={
        {kind="checkout",items={{kind="supply",categoryIndex=1,itemIndex=1,quantity=1,price=0}}},
        {kind="checkout",items={{kind="supply",categoryIndex=1,itemIndex=1,quantity=-1}}},
        {kind="estimate",id="MAIL-1",amount=0}, {kind="promotion",id="JOB-1",text=string.rep("x",601)},
        {kind="pay_bills",money=999999}, {kind="buy_anything",price=0},
    }
    for index,value in ipairs(invalid) do check("office_rejects_forged_intent_"..index,Intent.normalize(value)==nil) end
    local normalized=Intent.normalize({kind="checkout",items={{kind="supply",categoryIndex=1,itemIndex=1,quantity=1},
        {kind="supply",categoryIndex=1,itemIndex=16,quantity=1}}})
    before=state.money
    local ok=Office.command(options).perform({}, {id=2},{officeIntent=normalized})
    check("office_failed_checkout_is_atomic",not ok and state.money==before and #state.procurement.orders==3 and saves==5)
    local packet=Protocol.encode("workshop_command",{sessionId="office-phone-test",commandId=200,resourceId="office_computer",
        leaseId="office-phone-2",expectedRevision=1,action="office_action",officeIntent={kind="promotion",id="JOB-1",text=string.rep("x",600)}})
    check("office_long_typed_promotion_fits_bounded_protocol",packet~=nil and Protocol.decode(packet)~=nil)
    local offer=context.jobs.createOffer({id="OFFICE-QUOTE-1",company="Written Quotes Co.",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500},packaging="flat"})
    state.clientEmails.inbox={{id="EMAIL-9001",sender=offer.company,subject="Written job details",job=offer}}
    local saveBefore=saves
    reply=command("office_action",{officeIntent={kind="estimate",id="EMAIL-9001",amount=120}},true)
    check("office_guest_typed_estimate_waits_for_customer_email_reply",reply.accepted and #state.jobs.active==0
        and #state.clientEmails.pending==1 and state.clientEmails.pending[1].job.estimate.stage=="awaiting_reply"
        and saves==saveBefore+1)
    local nextOffer=context.jobs.createOffer({id="OFFICE-QUOTE-2",company="Another Quote Co.",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500},packaging="flat"})
    state.clientEmails.inbox={{id="EMAIL-9002",sender=nextOffer.company,subject="Written details",job=nextOffer}}
    reply=command("office_action",{officeIntent={kind="decline",id="EMAIL-9002"}})
    check("office_guest_can_decline_written_estimate",reply.accepted and #state.clientEmails.inbox==0)
    context.machineFleet.addServiceNotice(state,"Technician visit","The blade is ready.")
    local notices=context.machineFleet.ensure(state).serviceNotices
    local noticeId=notices[#notices].id
    reply=command("office_action",{officeIntent={kind="archive_service",id=noticeId}})
    check("office_guest_can_archive_service_email",reply.accepted and #context.machineFleet.ensure(state).serviceNotices==0)
    nextOffer.status="completed"
    state.jobs.completed={nextOffer}
    reply=command("office_action",{officeIntent={kind="promotion",id=nextOffer.id,text=string.rep("Thank you for your business. ",8)}},true)
    check("office_guest_typed_followup_is_sent_once",reply.accepted and #state.clientEmails.sentPromotions==1)
    guest:stop("test_complete"); host:update(0,hc); host:stop("test_complete")
end
return Test
