local Test={}
local State=require('src.state')
local Calendar=require('src.business_calendar')
local Hours=require('src.business_hours')
local function at(state,hours)
    local seconds=Calendar.secondsPerDay(state)
    state.calendar=Calendar.dateFromTotalDay(math.floor(hours/24))
    state.calendar.secondsPerDay=seconds;state.calendar.elapsed=hours%24/24*seconds
end
function Test.run(context,check)
    for day=0,6 do
        for _,hour in ipairs({0,2,8.99,9,12,19.99,20,23.99}) do
            local open=Hours.weekday(day)<=5 and hour>=9 and hour<20
            check(('business_window_%d_%s'):format(day,hour),Hours.isOpen(day*24+hour)==open)
        end
    end
    check('business_friday_late_retry_goes_to_monday',Hours.nextService(46)==105 and Hours.nextService(50)==105)
    check('business_overnight_retry_goes_to_next_morning',Hours.nextService(26)==33)
    check('business_journey_must_fit_before_closing',Hours.nextService(43.5,1)==105 and Hours.nextService(42,1)==42)
    local fresh=assert(require('src.save_store')({}).newGame(3,{tutorialEnabled=true}))
    check('business_new_game_starts_at_customer_opening',Calendar.absoluteHours(fresh.state)==9)
    local phone=require('src.work_phone');local state=State.new();at(state,43)
    assert(phone.queueCall(state,{kind='customer_order',caller='Test customer'}))
    at(state,44);phone.update(state,.1)
    check('business_unanswered_call_defers_at_closing',not state.workPhone.incoming and #state.workPhone.deferredCalls==1)
    for _,hour in ipairs({50,60,84,104}) do at(state,hour);phone.update(state,10) end
    check('business_phone_does_not_ring_overnight_or_weekend',not state.workPhone.incoming)
    at(state,105);phone.update(state,.1)
    check('business_deferred_call_returns_at_opening_once',state.workPhone.incoming and #state.workPhone.deferredCalls==0)
    local Inbox=require('src.inbox');local Service=require('src.job_service')
    state=State.new();at(state,44)
    Inbox.addNotice(state,{id='HOURS-EMAIL',sender='Customer',subject='Next job',body='Details',noticeKind='client_thanks'},0)
    check('business_client_notice_queued_at_friday_close',#state.clientEmails.inbox==0
        and state.clientEmails.pending[1].readyAtHours==105)
    for _,hour in ipairs({46,50,60,84,104}) do at(state,hour);Service.updateClientEmails(state) end
    check('business_email_keeps_waiting_through_weekend',#state.clientEmails.inbox==0 and #state.clientEmails.pending==1)
    at(state,105);Service.updateClientEmails(state);Service.updateClientEmails(state)
    check('business_email_arrives_once_monday',#state.clientEmails.inbox==1 and #state.clientEmails.pending==0)
    at(state,50);Inbox.addNotice(state,{id='RECEIPT',sender='Accounts',subject='Receipt',body='Paid',noticeKind='receipt'},0)
    check('business_automated_receipts_still_available',#state.clientEmails.inbox==2)

    local Driver=require('src.warehouse_delivery_driver')
    state=State.new();at(state,43.75);local job=Service.createNextOffer(state,100)
    assert(Service.acceptOffer(state,job,100))
    Driver.start(state,job.id,'delivery');state.deliveryDriver.status='missed'
    Driver.departed(state,job.id)
    local retry=job.delivery.readyAtHours
    check('business_missed_signature_retries_next_opening',retry==105)
    at(state,105);Service.deliveryReady(state,job)
    check('business_readiness_does_not_erase_rescheduled_retry',job.delivery.readyAtHours>=retry)
    at(state,50)
    check('business_due_stock_cannot_arrive_at_2am',not Service.deliveryReady(state,job))
    local Network=require('src.commute.delivery_traffic')
    Network.update(state,state.home.town,50,1000)
    local route=job.delivery.route
    check('business_road_freight_does_not_dispatch_overnight',route and not route.departedAtEpoch
        and route.startAtHours>=105 and route.arrivalAtHours%24<20)
    at(state,route.startAtHours)
    Network.update(state,state.home.town,Calendar.absoluteHours(state),1001)
    check('business_road_freight_dispatches_at_next_opening',route.departedAtEpoch==1001)
    at(state,50)

    local Run=require('src.commute.delivery_run')
    local city={kind='city',id='industrial',label='Industrial customer',jobIds={job.id}}
    local before=state.money
    local okay,reason=Run.completeStop(state,city)
    check('business_industrial_handoff_rejected_without_payment',not okay and reason:find('Receiving is closed',1,true)
        and state.money==before and #state.jobs.completed==0)
    check('business_retail_open_saturday_and_sunday',Run.nextStopOpen(state,{kind='town',id='grocery'},60)==60
        and Run.nextStopOpen(state,{kind='town',id='gas-station'},84)==84)
    check('business_retail_still_closes_at_night',Run.nextStopOpen(state,{kind='town',id='grocery'},50)==55
        and Run.nextStopOpen(state,{kind='town',id='gas-station'},50)==54)
    local Characters=require('src.commute.town_characters')
    check('business_grocery_and_gas_attendants_work_weekends',Characters.isOpen(state.home,'grocery',60)
        and Characters.isOpen(state.home,'gas-station',84))

    local Flow=require('src.weekend_flow')
    state=State.new();at(state,44);Flow.update(state,false);at(state,60);Flow.update(state,false)
    check('business_owner_can_keep_producing_weekend',state.home.weekend.phase=='closing' and not Flow.shopClosed(state)
        and Flow.limitCalendarStep(state,1)==1)
    at(state,105);Flow.update(state,false)
    check('business_staying_all_weekend_reopens_monday',state.home.weekend.phase=='working' and Flow.acceptsNewWork(state)
        and state.home.weekend.closesAtHours==212 and state.home.finance.lastSettledClose==44)
    local Feedback=require('src.player_feedback');local Notices=require('src.notifications')
    state=State.new();state.screen='world';at(state,42)
    local f=Feedback.new({state=state});f:update(.1)
    check('business_friday_warning_is_clickable_saved_notice',f.notices[1].kind=='calendar'
        and f.notices[1].duration==14 and Notices.findKey(state,'business:friday:1'))
    f:update(.1);local reopened=Feedback.new({state=state});reopened:update(.1)
    check('business_friday_warning_does_not_repeat_after_reload',#state.notifications.items==1 and #reopened.notices==0)
    at(state,44);f:update(.1);at(state,60);f:update(.1)
    check('business_weekend_reminder_once_with_shutdown_directions',#state.notifications.items==2
        and Notices.findKey(state,'business:weekend:1').body:find('CLOSE SHOP & LEAVE',1,true))
    check('business_notices_roundtrip',require('src.save_schema').snapshot(state)~=nil)
end
return Test
