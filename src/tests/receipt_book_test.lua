local Book=require('src.receipt_book')
local Ink=require('src.receipt_signature')
local State=require('src.state')
local Calendar=require('src.business_calendar')
local Schema=require('src.save_schema')
local Test={}
function Test.run(context,check)
    local state=State.new();state.money=100000
    local pad={x=10,y=20,width=520,height=82}
    local strokes={{18,66,45,29,42,88,82,43,100,66,134,33,170,77},{200,60,235,53,260,68}}
    local ink=assert(Ink.encode(strokes,pad))
    check('archive_signature_retains_pen_lifts_and_normalized_coordinates',Ink.valid(ink)
        and #Ink.decode(ink,pad)==2 and math.abs(Ink.decode(ink,pad)[1][1]-18)<2.1)
    local dense={};for i=1,4096 do dense[#dense+1]=10+i%520;dense[#dense+1]=20+i%82 end
    local packed=assert(Ink.encode({dense},pad))
    local Protocol=require('src.net.protocol')
    local packet=assert(Protocol.encode('interaction_request',{sessionId='receipt-test',requestId=1,
        targetKind='deliverySignature',desiredState='sign',signature={deliveryId='JOB-0010',ink=packed}}))
    local decoded=assert(Protocol.decode(packet))
    check('archive_guest_ink_fits_control_packet_and_roundtrips',#packet<=Protocol.MAX_PACKET_BYTES
        and decoded.payload.signature.ink==packed)
    check('archive_rejects_malformed_and_oversized_signature_packets',not Ink.valid('00zz') and not Ink.valid('0000//ffff')
        and not Ink.valid(string.rep('0000',Ink.MAX_POINTS+1))
        and not Protocol.encode('interaction_request',{sessionId='receipt-test',requestId=2,targetKind='deliverySignature',
            desiredState='sign',signature={deliveryId='JOB-0010',ink=ink,amountCents=1}}))
    local Driver=require('src.warehouse_delivery_driver')
    local job=assert(require('src.jobs').createOffer({id='JOB-0010',company='Corner Copy & Mail',
        sourceSize={width=17,height=12},finishedSize={width=8.5,height=11},sheetCounts={500},packaging='flat'}))
    state.jobs.active={job};Driver.start(state,job.id,'job_delivery');state.deliveryDriver.status='waiting'
    local actor=Driver.actor(state);local player={x=actor.x,y=actor.y,sceneId='warehouse',name='Jamie'}
    check('archive_stale_delivery_cannot_store_ink_or_accept_shipment',not Driver.sign(state,player,{deliveryId='OLD',ink=ink})
        and #state.receipts.entries==0 and state.deliveryDriver.status=='waiting')
    check('archive_out_of_range_signer_cannot_create_receipt',not Driver.sign(state,
        {x=actor.x+500,y=actor.y,sceneId='warehouse'},{deliveryId=job.id,ink=ink}) and #state.receipts.entries==0)
    assert(Driver.sign(state,player,{deliveryId=job.id,ink=ink}))
    local receipt=state.receipts.entries[1]
    check('archive_signed_delivery_keeps_exact_submitted_ink_and_signer',receipt.signature==ink
        and receipt.signedBy=='Jamie' and receipt.status=='received' and receipt.party==job.company)
    check('archive_repeated_sign_does_not_duplicate_delivery',not Driver.sign(state,player,{deliveryId=job.id,ink=ink})
        and #state.receipts.entries==1)
    job.company='Changed client';require('src.screens.delivery_signature_screen').clear()
    check('archive_receipt_is_independent_of_live_manifest_and_signature_screen',receipt.party=='Corner Copy & Mail'
        and receipt.signature==ink)
    -- Continue with a clean, valid shop; receipt history survives removal of the live delivery.
    local shop=State.new();shop.money=100000;shop.receipts=Book.normalize(state.receipts)
    local oldMoney=shop.money;local count=#shop.receipts.entries
    shop.money=0;check('archive_failed_purchase_creates_no_receipt',not require('src.shop').buyPaper(shop) and #shop.receipts.entries==count)
    shop.money=oldMoney;assert(require('src.shop').buyPaper(shop))
    check('archive_purchase_records_actual_amount_without_double_charge',shop.money==oldMoney-25
        and shop.receipts.entries[#shop.receipts.entries].amountCents==2500)
    local fleet=require('src.machine_fleet');local machines=State.new();machines.money=100000
    local beforePurchase=machines.money;local bought,machine=fleet.buy(machines,'dealer',1);assert(bought)
    local purchase=Book.list(machines,'purchase')[1]
    check('archive_machine_purchase_records_cash_actually_paid',purchase.amountCents==(beforePurchase-machines.money)*100)
    local beforeSale=machines.money;assert(fleet.sell(machines,machine.id,'online'))
    local sale=Book.list(machines,'payout')[1]
    check('archive_machine_sale_records_payout_and_asset',sale.amountCents==(machines.money-beforeSale)*100
        and sale.details:find(machine.id,1,true) and Book.valid(machines.receipts))
    local invoice=Calendar.addCharge(shop,'Customer stock replacement',125,'JOB-0001')
    local before=#shop.receipts.entries
    assert(Calendar.pay(shop))
    local bill
    for _,row in ipairs(shop.receipts.entries) do if row.source=='invoice:'..invoice.id then bill=row end end
    check('archive_invoice_payment_updates_same_document',#shop.receipts.entries==before and bill.status=='paid'
        and bill.amountCents==12500 and bill.paidAtHours~=nil)
    before=#shop.receipts.entries
    require('src.household_finances').record(shop,'wages',500)
    check('archive_employee_wages_remain_outside_receipts',#shop.receipts.entries==before)
    local jobPaid={id='JOB-PAID',company='Juniper Outfitters',quote={totalPrice=220,playerPrice=180},paymentAmount=220,
        completedAtHours=10,paper='White stock',packaging='boxed',pallets={{finishedSheets=500}},
        sourceSize={width=17,height=12},finishedSize={width=8.5,height=11}}
    local paid=Book.job(shop,jobPaid);local paidId=paid.id;jobPaid.paymentAmount=900
    local repeated,inserted=Book.job(shop,jobPaid)
    check('archive_job_payment_is_frozen_and_deduplicated',not inserted and repeated.id==paidId and repeated.amountCents==22000
        and repeated.details:find('Delivery: $40.00',1,true) and repeated.details:find('500',1,true)
        and repeated.details:find('17 x 12 in to 8.5 x 11 in',1,true))
    local dueDay=shop.home.lease.nextDueDay
    shop.calendar=Calendar.dateFromHours(dueDay*24);shop.home.balanceCents=1000000
    require('src.home').advance(shop)
    local rent=shop.receipts.entries[#shop.receipts.entries]
    assert(require('src.home').command(shop,{kind='home_pay_rent',expectedRevision=shop.home.revision}))
    check('archive_household_rent_keeps_invoice_and_paid_status',rent.source=='rent:'..dueDay and rent.status=='paid'
        and rent.account=='Household' and rent.amountCents==shop.home.lease.monthlyCents)
    local snapshot=assert(Schema.snapshot(shop))
    check('archive_save_schema_accepts_persistent_documents',Schema.validState(snapshot) and Book.valid(snapshot.receipts))
    local shared=State.new();assert(State.applySharedSnapshot(shared,snapshot))
    check('archive_host_documents_are_available_in_shared_read_only_state',shared.receipts.entries[1].signature==ink
        and #shared.receipts.entries==#shop.receipts.entries)
    local invalid=Book.normalize(shop.receipts);invalid.entries[1].signature='not-ink'
    check('archive_invalid_ink_and_duplicate_documents_are_rejected',not Book.valid(invalid))
    invalid=Book.normalize(shop.receipts);invalid.entries[2].source=invalid.entries[1].source
    check('archive_duplicate_source_is_rejected',not Book.valid(invalid))
    local legacy=assert(Schema.snapshot(shop));legacy.receipts=nil
    local migrated=assert(Schema.snapshot(legacy))
    check('archive_legacy_save_imports_existing_bills_without_fabricated_ink',Book.valid(migrated.receipts)
        and #migrated.receipts.entries>=1 and migrated.receipts.entries[1].signature==nil)
    context.save.delete(2)
    assert(context.save.save(2,shop,{x=600,y=500,sceneId='warehouse'}))
    local loaded=assert(context.save.load(2));local restored=State.new();assert(State.applySave(restored,loaded))
    check('archive_disk_reload_preserves_signature_amounts_and_receipt_ids',restored.receipts.entries[1].signature==ink
        and restored.receipts.nextId==shop.receipts.nextId and restored.receipts.entries[1].signedBy=='Jamie')
    context.save.delete(2)
    return restored
end
return Test
