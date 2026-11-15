local State=require('src.state')
local Credit=require('src.credit')
local Assets=require('src.credit_assets')
local Dealer=require('src.vehicle_dealer')
local Schema=require('src.save_schema')
local Calendar=require('src.business_calendar')
local Intent=require('src.office_intent')
local Office=require('src.office_authority')
local Test={}
local function fresh()
    local state=State.new()
    state.warehouse.boxTruckOwned=false;state.warehouse.keiTruckOwned=false
    state.money=100000
    return state
end
local function capture(screen,state,context,name)
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.origin()
    screen.draw(state,nil,nil,context.assets)
    love.graphics.pop()
    local dir=os.getenv('PICTURE_SHOP_FINANCE_CAPTURE')
    if dir then
        local data=canvas:newImageData();local png=data:encode('png')
        local file=assert(io.open(dir..'/'..name..'.png','wb'));file:write(png:getString());file:close()
        png:release();data:release()
    end
    canvas:release()
end
function Test.run(context,check)
    for index,id in ipairs(Assets.ORDER) do
        local state=fresh();local offer=Assets.offer(id);local quote=Credit.assetQuotes(state)[index]
        state.money=quote.downPayment
        local bought,result=Credit.financeAsset(state,id,'finance-'..id)
        local loan=result and result.loan
        local owned=id=='forklift' and state.warehouse.forkliftOwned or Dealer.owns(state,offer.model)
        check('fleet_finance_down_payment_acquires_'..id,bought and owned and loan and state.money==0
            and loan.balance==quote.principal and loan.assetId==offer.model
            and loan.purchasePrice==offer.price and loan.monthlyPayment>0)
        local receipt=state.warehouse.receipts[1]
        check('fleet_finance_receipt_and_save_roundtrip_'..id,receipt.loanId==loan.id
            and receipt.pricePaid==offer.price and receipt.cashPaid==quote.downPayment
            and Schema.validState(assert(Schema.snapshot(state))) and Credit.validState(state.credit))
        if id~='forklift' then
            local vehicle=state.home.truckFleet[offer.model]
            check('fleet_finance_preserves_new_or_used_condition_'..id,
                offer.condition=='new' and vehicle.damage==0 and vehicle.service.totalMiles==0
                or offer.condition=='used' and vehicle.damage>0 and vehicle.service.totalMiles>0)
        end
        local again,_,code=Credit.financeAsset(state,id,'finance-'..id)
        local duplicate=Credit.financeAsset(state,id,'different-request')
        check('fleet_finance_replay_and_ownership_prevent_double_purchase_'..id,
            again and code=='replayed' and not duplicate and #state.credit.loans==1 and state.money==0)
    end

    local state=fresh();local down=Credit.assetQuotes(state)[4].downPayment
    state.money=down-1
    local bought=Credit.financeAsset(state,'kei_used','short-cash')
    check('fleet_finance_insufficient_down_payment_is_atomic',not bought and state.money==down-1
        and not Dealer.owns(state,'kei') and #state.credit.loans==0 and #state.warehouse.receipts==0)
    state.money=100000;state.credit.score=499
    check('fleet_finance_rejects_ineligible_credit',not Credit.financeAsset(state,'kei_used','low-credit'))
    state.credit.score=560
    assert(Credit.financeMachine(state,1,'machine-shared-limit'))
    assert(Credit.financeAsset(state,'kei_used','truck-shared-limit'))
    assert(Credit.financeAsset(state,'forklift','lift-shared-limit'))
    check('fleet_finance_shares_machine_loan_limit',not Credit.financeAsset(state,'box_new','over-limit')
        and Credit.profile(state).openLoans==3)
    check('fleet_finance_rejects_request_reused_for_another_asset',
        not Credit.financeAsset(state,'box_used','truck-shared-limit') and #state.credit.loans==3)
    local loan=state.credit.loans[2]
    state.calendar=Calendar.dateFromTotalDay(loan.nextDueDay);state.calendar.elapsed=0
    Credit.onDay(state)
    local event=false
    for _,item in ipairs(Calendar.events(state)) do
        event=event or item.title=='Equipment installment due: '..loan.machineName
    end
    check('fleet_finance_appears_on_monthly_calendar',event and loan.installmentsDue==1)
    local original=loan.balance
    local paid,payment=Credit.payLoan(state,loan.id)
    check('fleet_finance_pays_monthly_installment',paid and loan.balance==original-payment.amount
        and loan.installmentsDue==0 and Credit.hasLien(state,'kei'))
    while loan.status=='active' do
        state.calendar=Calendar.dateFromTotalDay(loan.nextDueDay);state.calendar.elapsed=0
        Credit.onDay(state);state.money=1000000;assert(Credit.payLoan(state,loan.id))
    end
    check('fleet_finance_paid_loan_releases_vehicle_lien',loan.status=='paid'
        and not Credit.hasLien(state,'kei') and Dealer.owns(state,'kei'))

    state=fresh();local saved=0
    local authority=Office.command({state=state,warehouseEnabled=true,save=function()saved=saved+1 end,
        world={validateNetworkWorkshopAccess=function()return true end}})
    local intent=assert(Intent.normalize({kind='finance_asset',listingId='forklift',requestId='host-lift'}))
    local accepted=authority.perform(authority,{id=1},{officeIntent=intent})
    local replayed,status=authority.perform(authority,{id=1},{officeIntent=intent})
    check('fleet_finance_host_commits_exactly_once',accepted and replayed and status=='replayed'
        and saved==1 and #state.credit.loans==1 and state.warehouse.forkliftOwned)
    check('fleet_finance_host_rejects_client_prices_and_unknown_assets',
        not Intent.normalize({kind='finance_asset',listingId='box_new',requestId='tamper',price=1})
        and not Intent.normalize({kind='finance_asset',listingId='unknown',requestId='bad'}))

    state=fresh()
    local ui=context.computerScreen.new();ui.enter(state);ui.tab='credit'
    local x,y=ui.creditChannelCenter('fleet');ui.mousepressed(state,x,y,1)
    check('fleet_finance_credit_tab_has_fleet_channel',ui.creditChannel=='fleet')
    capture(ui,state,context,'fleet-page-one')
    x,y=ui.creditPageCenter(true);ui.mousepressed(state,x,y,1)
    check('fleet_finance_all_truck_and_forklift_listings_are_reachable',ui.creditPage==2)
    capture(ui,state,context,'fleet-page-two')
    x,y=ui.creditMachineCenter(5)
    local review=ui.mousepressed(state,x,y,1)
    check('fleet_finance_reviews_forklift_terms',review and review.quote.listingId=='forklift')
    capture(ui,state,context,'forklift-terms')
    x,y=ui.creditSignCenter();local signed=ui.mousepressed(state,x,y,1)
    check('fleet_finance_sign_button_buys_forklift',signed and signed.action=='asset_financed'
        and state.warehouse.forkliftOwned and #state.credit.loans==1)
    capture(ui,state,context,'fleet-loan')

    state=fresh();state.money=20000
    ui=context.computerScreen.new({warehouseEnabled=true});ui.enter(state)
    ui.tab='www';ui.wwwSite=6
    capture(ui,state,context,'vehicle-dealer-finance')
    x,y=ui.vehicleFinanceCenter(1);local shortcut=ui.mousepressed(state,x,y,1)
    check('fleet_finance_vehicle_dealer_offers_finance_without_full_cash',shortcut
        and shortcut.action=='credit_financing' and ui.tab=='credit' and ui.creditChannel=='fleet')
    ui.tab='warehouse'
    capture(ui,state,context,'forklift-purchase-finance')
    x,y=ui.warehouseButtonCenter('forklift_finance');shortcut=ui.mousepressed(state,x,y,1)
    check('fleet_finance_forklift_purchase_links_to_its_credit_page',shortcut
        and shortcut.action=='credit_financing' and ui.tab=='credit' and ui.creditPage==2)

    state=fresh();local sent
    ui=context.computerScreen.new({remoteCommand=function(command)sent=command end})
    ui.enter(state);ui.tab='credit';ui.creditChannel='fleet'
    x,y=ui.creditMachineCenter(1);ui.mousepressed(state,x,y,1)
    x,y=ui.creditSignCenter();local pending=ui.mousepressed(state,x,y,1)
    check('fleet_finance_guest_submits_intent_without_local_purchase',pending and pending.action=='remote_pending'
        and sent and sent.kind=='finance_asset' and sent.listingId=='box_new'
        and not Dealer.owns(state,'box') and #state.credit.loans==0)
end
return Test
