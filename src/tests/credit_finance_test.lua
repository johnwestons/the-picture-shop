local State = require("src.state")
local Credit = require("src.credit")
local Calendar = require("src.business_calendar")
local MachineFleet = require("src.machine_fleet")
local Schema = require("src.save_schema")
local Intent = require("src.office_intent")
local Office = require("src.office_authority")
local Config = require("src.config")

local Test = {}

local function setDay(state, day)
    state.calendar = Calendar.dateFromTotalDay(day)
    state.calendar.elapsed = 0
end

local function findEvent(state, prefix)
    for _, event in ipairs(Calendar.events(state)) do
        if event.title:find(prefix, 1, true) == 1 then return event end
    end
end

function Test.run(context, check)
    local state = State.new()
    state.money = 50000
    local profile = Credit.profile(state)
    local quote = Credit.machineQuotes(state)[1]
    check("credit_starts_below_prime_and_quotes_down_apr_and_fixed_term", profile.score == 560
        and profile.tier == "Poor" and profile.apr == 18.99
        and quote and quote.eligible and quote.downPayment == math.ceil(quote.price * 0.25)
        and quote.principal == quote.price - quote.downPayment
        and quote.termMonths == 36 and quote.monthlyPayment > 0)

    local ui = context.computerScreen
    ui.enter(state)
    local dropdownX, dropdownY = ui.dropdownCenter()
    local dropdown = ui.mousepressed(state, dropdownX, dropdownY, 1)
    local creditX, creditY = ui.tabCenter("credit")
    local opened = ui.mousepressed(state, creditX, creditY, 1)
    local offerX, offerY = ui.creditMachineCenter(1)
    local terms = ui.mousepressed(state, offerX, offerY, 1)
    local signX, signY = ui.creditSignCenter()
    local signed = ui.mousepressed(state, signX, signY, 1)
    local loan = signed and signed.loan
    check("computer_credit_tab_signs_financing_and_orders_machine", dropdown
        and dropdown.action == "dropdown_opened" and opened and opened.action == "tab"
        and ui.tab == "credit" and terms and terms.action == "finance_terms"
        and signed and signed.action == "machine_financed" and loan
        and loan.id == "CR-0001" and #state.machines.deliveries == 1
        and state.money == 50000 - loan.downPayment)

    local dealerState = State.new()
    local dealerQuote = Credit.machineQuotes(dealerState, "dealer")[3]
    dealerState.money = dealerQuote.downPayment
    local dealerUi = context.computerScreen.new({ warehouseRequestPrefix = "CREDIT-DEALER-TEST" })
    dealerUi.enter(dealerState)
    local dealerDropdownX, dealerDropdownY = dealerUi.dropdownCenter()
    dealerUi.mousepressed(dealerState, dealerDropdownX, dealerDropdownY, 1)
    local dealerTabX, dealerTabY = dealerUi.tabCenter("credit")
    dealerUi.mousepressed(dealerState, dealerTabX, dealerTabY, 1)
    local channelX, channelY = dealerUi.creditChannelCenter("dealer")
    local channel = dealerUi.mousepressed(dealerState, channelX, channelY, 1)
    local dealerOfferX, dealerOfferY = dealerUi.creditMachineCenter(3)
    local dealerTerms = dealerUi.mousepressed(dealerState, dealerOfferX, dealerOfferY, 1)
    local dealerSignX, dealerSignY = dealerUi.creditSignCenter()
    local dealerSigned = dealerUi.mousepressed(dealerState, dealerSignX, dealerSignY, 1)
    check("credit_tab_finances_used_dealer_machines_for_a_down_payment", channel
        and channel.channel == "dealer" and dealerTerms and dealerTerms.quote.channel == "dealer"
        and dealerSigned and dealerSigned.action == "machine_financed"
        and dealerSigned.loan.channel == "dealer" and dealerSigned.loan.machineId == "MCH-0003"
        and #dealerState.machines.deliveries == 0 and #dealerState.machines.items == 3
        and dealerState.money == 0)

    local shopState = State.new()
    shopState.money = 0
    local shopUi = context.computerScreen.new()
    shopUi.enter(shopState)
    local shopDropdownX, shopDropdownY = shopUi.dropdownCenter()
    shopUi.mousepressed(shopState, shopDropdownX, shopDropdownY, 1)
    local shopTabX, shopTabY = shopUi.tabCenter("www")
    shopUi.mousepressed(shopState, shopTabX, shopTabY, 1)
    local machineSiteX, machineSiteY = shopUi.wwwSiteCenter(5)
    shopUi.mousepressed(shopState, machineSiteX, machineSiteY, 1)
    local machineBuyX, machineBuyY = shopUi.machineBuyCenter(1)
    local financeShortcut = shopUi.mousepressed(shopState, machineBuyX, machineBuyY, 1)
    check("unaffordable_online_listing_leads_to_credit_tab", financeShortcut
        and financeShortcut.action == "credit_financing" and shopUi.tab == "credit"
        and shopUi.creditChannel == "online")

    local order = state.machines.deliveries[1]
    local unloaded, financedMachine = MachineFleet.unloadDelivery(state, order.id, order.machineId, 0)
    local blockedSale, saleMessage = MachineFleet.sell(state, financedMachine and financedMachine.id, "online")
    check("financed_machine_has_a_lien_until_the_loan_is_paid", unloaded and financedMachine
        and not blockedSale and tostring(saleMessage):find(loan.id, 1, true) ~= nil
        and Credit.hasLien(state, financedMachine.id))

    local persisted = Schema.snapshot(state)
    check("credit_account_and_machine_lien_are_save_valid", persisted
        and persisted.credit and Schema.validState(persisted)
        and Credit.validState(persisted.credit))
    local legacyState = Schema.copy(persisted)
    legacyState.credit = nil
    local migrated = Schema.migrate({ version = 15, slot = 1, createdAt = 1, updatedAt = 1,
        state = legacyState, player = { x = 400, y = 450 } })
    check("version_15_saves_receive_a_safe_starter_credit_profile", migrated
        and migrated.version == Schema.VERSION and migrated.state.credit.score == Credit.STARTING_SCORE
        and #migrated.state.credit.loans == 0)

    local scheduledBalance = loan.balance
    setDay(state, loan.nextDueDay - 1)
    local advanced = Calendar.update(state, Config.businessCalendar.secondsPerDay)
    local dueEvent = findEvent(state, "Machine installment due:")
    local scheduledAmount = loan.monthlyPayment
    local accruedInterest = loan.accruedInterest
    local paidButtonX, paidButtonY = ui.creditLoanPayCenter(1)
    local paid = ui.mousepressed(state, paidButtonX, paidButtonY, 1)
    local expectedBalance = math.max(0, scheduledBalance + accruedInterest - scheduledAmount)
    check("computer_credit_tab_shows_due_date_and_processes_on_time_payment", advanced
        and loan.installmentsDue == 0 and dueEvent and dueEvent.kind == "credit"
        and paid and paid.action == "machine_payment" and paid.payment.onTime
        and loan.balance == expectedBalance and loan.status == "active"
        and state.credit.score == Credit.STARTING_SCORE - 2,
        string.format("advanced=%s installments=%s event=%s paid=%s onTime=%s balance=%s expected=%s score=%s",
            tostring(advanced), tostring(loan.installmentsDue), tostring(dueEvent and dueEvent.title),
            tostring(paid and paid.action), tostring(paid and paid.payment and paid.payment.onTime),
            tostring(loan.balance), tostring(expectedBalance), tostring(state.credit.score)))

    local lateState = State.new()
    lateState.money = 50000
    local financed, lateResult = Credit.financeMachine(lateState, 1, "credit-late-case")
    local lateLoan = financed and lateResult.loan
    if lateLoan then
        setDay(lateState, lateLoan.nextDueDay)
        Credit.onDay(lateState)
        setDay(lateState, lateLoan.oldestDueDay + 15)
        Credit.onDay(lateState)
        local feeWasAdded = lateLoan.feesDue >= 10 and lateLoan.lateFeeCharged
        setDay(lateState, lateLoan.oldestDueDay + 30)
        Credit.onDay(lateState)
        check("late_installments_add_capped_fees_and_report_to_credit", feeWasAdded
            and lateLoan.installmentsDue >= 2 and lateLoan.delinquencyLevel == 1
            and lateState.credit.score == Credit.STARTING_SCORE - 4 - 30)
    else
        check("late_installments_add_capped_fees_and_report_to_credit", false)
    end

    local billsState = State.new()
    billsState.money = 1000
    billsState.bills.balance = 25
    billsState.bills.ledger = { { id = "BILL-TEST", total = 25, status = "unpaid",
        issuedOnDay = 0, dueOnDay = 0 } }
    local billsPaid = Calendar.pay(billsState)
    check("paying_monthly_bills_on_time_builds_credit", billsPaid
        and billsState.credit.score == Credit.STARTING_SCORE + 2
        and billsState.bills.ledger[1].paidOnDay == 0)

    local mature = State.new()
    mature.money = 500000
    local opened, matureResult = Credit.financeMachine(mature, 1, "credit-maturity-case")
    local matureLoan = opened and matureResult.loan
    if matureLoan then
        while matureLoan.status == "active" do
            setDay(mature, matureLoan.nextDueDay)
            Credit.onDay(mature)
            mature.money = mature.money + matureLoan.amountDue + matureLoan.feesDue
            local paidOk = Credit.payLoan(mature, matureLoan.id)
            if not paidOk then break end
        end
    end
    local lienReleased = matureLoan and matureLoan.status == "paid" and matureLoan.lienReleased
    check("maturity_installment_pays_remaining_balance_and_releases_lien", lienReleased
        and not Credit.hasLien(mature, matureLoan.machineId))

    local authorityState = State.new()
    authorityState.money = 50000
    local saves = 0
    local command = Office.command({
        state = authorityState,
        save = function() saves = saves + 1 end,
        world = { validateNetworkWorkshopAccess = function() return true, "available", "" end },
    })
    local normalized = command.normalize({ officeIntent = {
        kind = "finance_machine", offerIndex = 1, requestId = "authority-credit-1",
    } })
    local accepted, status = command.perform(command, {}, { officeIntent = normalized.officeIntent })
    local replayed, replayStatus = command.perform(command, {}, { officeIntent = normalized.officeIntent })
    check("host_office_authority_commits_credit_once_and_replays_safely", normalized and accepted
        and status == "completed" and replayed and replayStatus == "replayed"
        and saves == 1 and #authorityState.credit.loans == 1)
    local dealerAuthorityState = State.new()
    local dealerAuthorityQuote = Credit.machineQuotes(dealerAuthorityState, "dealer")[3]
    dealerAuthorityState.money = dealerAuthorityQuote.downPayment
    local dealerAuthority = Office.command({
        state = dealerAuthorityState,
        save = function() end,
        world = { validateNetworkWorkshopAccess = function() return true, "available", "" end },
    })
    local dealerIntent = dealerAuthority.normalize({ officeIntent = {
        kind = "finance_machine", offerIndex = 3, requestId = "authority-dealer-credit-1", channel = "dealer",
    } })
    local dealerAccepted, dealerStatus = dealerAuthority.perform(dealerAuthority, {}, {
        officeIntent = dealerIntent.officeIntent,
    })
    check("host_office_authority_validates_and_finances_dealer_listings", dealerIntent and dealerAccepted
        and dealerStatus == "completed" and dealerAuthorityState.credit.loans[1].channel == "dealer"
        and dealerAuthorityState.credit.loans[1].machineId == "MCH-0003"
        and #dealerAuthorityState.machines.deliveries == 0 and dealerAuthorityState.money == 0)
    check("credit_network_intent_rejects_client_supplied_price", not Intent.normalize({
        kind = "finance_machine", offerIndex = 1, requestId = "price-tamper", price = 1,
    }))
end

return Test
