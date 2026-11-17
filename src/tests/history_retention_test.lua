local Test={}
function Test.run(check)
    local H=require('src.history_retention')
    local State=require('src.state')
    local Schema=require('src.save_schema')
    local Calendar=require('src.business_calendar')
    local state=State.new()
    local template=assert(require('src.jobs').createOffer({id='JOB-0001',company='Returning client',
        sourceSize={width=17,height=12},finishedSize={width=8.5,height=11},sheetCounts={500},packaging='flat'}))
    for i=1,150 do
        local job=Schema.copy(template);job.id=('JOB-%04d'):format(i);job.status='completed'
        job.paymentAmount=125;job.completedAtHours=i
        for p,pallet in ipairs(job.pallets) do pallet.id=job.id..'-P'..p;pallet.location='none';pallet.status='picked_up' end
        state.jobs.completed[i]=job
        local declined=Schema.copy(template);declined.id='DECLINED-'..i;declined.status='declined'
        state.jobs.declined[i]=declined
        state.clientEmails.archive[i]={id='EMAIL-'..i,sender='Client',subject='Done',body='Completed',response='archived',noticeKind='notice',respondedAtHours=i}
        state.clientEmails.sentPromotions[i]={id='PROMO-'..i,recipient='Returning client',discountPercent=10,
            customMessage='Thank you',sentAtHours=i,responseOutcome='new_job'}
    end
    H.enforce(state)
    check('history_jobs_and_correspondence_keep_newest_100',#state.jobs.completed==100
        and state.jobs.completed[1].id=='JOB-0051' and #state.jobs.declined==100
        and #state.clientEmails.archive==100 and state.clientEmails.archive[1].id=='EMAIL-51'
        and #state.clientEmails.sentPromotions==100 and state.clientEmails.sentPromotions[1].id=='PROMO-51')
    check('history_retired_job_totals_preserve_relationships_and_revenue',state.jobs.retired.completed==50
        and state.jobs.retired.paymentCents==625000 and H.relationship(state,'Returning client')==50)
    local snapshot=assert(Schema.snapshot(state));local reloaded=State.new()
    assert(State.applyLocalSave(reloaded,{state=snapshot,slot=1}))
    check('history_caps_and_totals_survive_save_reload',Schema.validState(snapshot)
        and #reloaded.jobs.completed==100 and reloaded.jobs.retired.completed==50
        and H.relationship(reloaded,'Returning client')==50)
    local protected=State.new()
    for i=1,101 do protected.jobs.completed[i]={id='J'..i,company='Client',customerCase=i==1 and {status='open'} or nil} end
    H.enforce(protected)
    check('history_never_discards_an_unresolved_customer_case',#protected.jobs.completed==100
        and protected.jobs.completed[1].id=='J1' and protected.jobs.completed[2].id=='J3')
    protected.jobs.completed={}
    for i=1,100 do protected.jobs.completed[i]={id='J'..i,customerCase={status='open'}} end
    check('history_unresolved_case_capacity_blocks_more_jobs',not H.canAcceptJob(protected))
    local purchase=State.new()
    for i=1,150 do
        purchase.procurement.orders[i]={id='PO-'..i,status='received',pallets={{location=i==1 and 'warehouse' or 'none'}}}
        purchase.procurement.shipments[i]={id='SHIP-'..i,status='received',orderIds={'PO-'..i}}
    end
    H.enforce(purchase)
    check('history_orders_keep_owned_stock_and_remove_old_consumed_orders',#purchase.procurement.orders==100
        and purchase.procurement.orders[1].id=='PO-1' and purchase.procurement.orders[2].id=='PO-52'
        and #purchase.procurement.shipments==100 and purchase.procurement.shipments[1].orderIds[1]=='PO-1')
    for _,order in ipairs(purchase.procurement.orders) do order.pallets[1].location='warehouse' end
    check('history_full_physical_stock_log_blocks_new_purchases',not H.procurement(purchase,true)
        and #purchase.procurement.orders==100)
    local promos=State.new()
    for i=1,100 do promos.clientEmails.sentPromotions[i]={id='P'..i,responseOutcome='thank_you'} end
    check('history_unredeemed_coupons_are_not_silently_deleted',not H.reservePromotion(promos)
        and #promos.clientEmails.sentPromotions==100)
    promos.clientEmails.sentPromotions[1].couponUsedAtHours=5
    check('history_redeemed_promotion_can_make_room',H.reservePromotion(promos)
        and #promos.clientEmails.sentPromotions==99 and promos.clientEmails.sentPromotions[1].id=='P2')
    local mail=State.new()
    mail.clientEmails.inbox[1]={id='active-estimate',job={id='still-pending'}}
    for i=1,150 do
        require('src.inbox').addNotice(mail,{id='receipt-'..i,sender='Store',subject='Receipt',body='Purchase',noticeKind='receipt'},0)
        require('src.inbox').addNotice(mail,{id='pending-'..i,sender='Store',subject='Delivery',body='On the way',noticeKind='home_delivery'},24)
    end
    check('history_incoming_and_pending_notices_are_bounded_without_losing_estimates',#mail.clientEmails.inbox==100
        and mail.clientEmails.inbox[1].id=='active-estimate' and mail.clientEmails.inbox[100].id=='receipt-150'
        and #mail.clientEmails.pending==100 and mail.clientEmails.pending[1].id=='pending-51')
    for i=1,100 do mail.clientEmails.inbox[i]={id='estimate-'..i,job={id='job-'..i}} end
    check('history_outstanding_estimates_block_new_work_at_capacity',not H.canRequestEmailJob(mail))
    local debts=State.new();debts.money=10000
    debts.bills.balance=2500;debts.bills.nextInvoiceId=251
    for i=1,250 do debts.bills.ledger[i]={id='BILL-'..i,total=10,status='unpaid',issuedOnDay=i,dueOnDay=i,
        kind=i%2==0 and 'spoil_claim' or nil,charges={{id='cost',label='Charge',amount=10}}} end
    H.bills(debts)
    local total=0;local claims=0
    for _,invoice in ipairs(debts.bills.ledger) do
        total=total+invoice.total
        if invoice.kind=='spoil_claim' then claims=claims+invoice.total end
    end
    check('history_overdue_invoice_rollups_preserve_all_debt_and_kinds',#debts.bills.ledger==100
        and total==2500 and claims==1250 and debts.bills.balance==2500 and debts.bills.ledger[1].dueOnDay==1)
    local paid,amount=Calendar.pay(debts)
    check('history_rolled_up_invoices_can_be_paid_exactly_once',paid and amount==2500
        and debts.money==7500 and debts.bills.balance==0 and not Calendar.pay(debts))
    for i=1,125 do Calendar.recordPaidExpenseCents(debts,'Paid expense',100,'test-'..i) end
    check('history_new_paid_expenses_evict_oldest_invoice_records',#debts.bills.ledger==100
        and #debts.receipts.entries==100 and debts.bills.ledger[100].reference=='test-125')
end
return Test
