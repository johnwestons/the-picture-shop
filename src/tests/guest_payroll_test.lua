local State=require('src.state')
local Residents=require('src.home_residents')
local Payroll=require('src.guest_payroll')
local Pay=require('src.portable_pay')
local Schema=require('src.save_schema')
local Credentials=require('src.resident_credentials')
local Intent=require('src.office_intent')
local Test={}

function Test.run(_,check)
    local state=State.new()
    state.money=100
    local host={id=1,sceneId='warehouse'}
    local guest={id=2,name='Worker',sceneId='commute'}
    local token=assert(Credentials.get())
    local id=assert(Residents.bind(state,guest,token,{host}))
    local resident=state.home.residents[id]
    check('guest_wage_default_and_identity',resident.wageCents==100 and resident.wagePaidCents==0
        and resident.activePlayerId==2)
    local oldDefault={wageCents=2000,wageEarnedCents=800,wagePaidCents=800,wageRevision=0}
    Payroll.ensure(oldDefault)
    local negotiated={wageCents=2000,wageEarnedCents=800,wagePaidCents=800,wageRevision=2}
    Payroll.ensure(negotiated)
    check('guest_wage_old_unnegotiated_rate_moves_to_one_dollar',oldDefault.wageCents==100
        and oldDefault.wagePaidCents==800 and negotiated.wageCents==2000)
    local previousSave=State.new()
    local previousGuest={id=2,name='Prior worker',sceneId='warehouse'}
    local previousId=assert(Residents.bind(previousSave,previousGuest,token,{host}))
    local previousRow=previousSave.home.residents[previousId]
    previousRow.wageCents,previousRow.wageEarnedCents,previousRow.wagePaidCents=2000,1500,1000
    local restored=State.new()
    assert(State.applyLocalSave(restored,{state=Schema.copy(previousSave),slot=1}))
    local migrated=restored.home.residents[previousId]
    check('guest_wage_save_load_migrates_only_rate',migrated.wageCents==100
        and migrated.wageEarnedCents==1500 and migrated.wagePaidCents==1000)
    check('guest_wage_one_dollar_offer_is_valid',Intent.normalize({kind='player_wage_propose',
        residentId=id,expectedRevision=0,wageCents=100})~=nil
        and Intent.normalize({kind='player_wage_propose',residentId=id,
            expectedRevision=0,wageCents=99})==nil)

    local monday=4*24
    local late=State.new();late.money=100
    local lateGuest={id=2,sceneId='warehouse'}
    local lateId=assert(Residents.bind(late,lateGuest,token,{host}))
    lateGuest.homeJoinedAtHours=monday+9.5
    Payroll.advance(late,{lateGuest},monday+9,monday+10)
    check('guest_wage_starts_at_actual_join_time',late.home.residents[lateId].wagePaidCents==50)
    Payroll.advance(state,{guest},monday+8,monday+10)
    check('guest_wages_cover_open_hours_and_bike_travel',resident.wageEarnedCents==100
        and resident.wagePaidCents==100 and state.money==99)
    Payroll.advance(state,{guest},monday+10,monday+11)
    check('guest_wages_continue_during_connected_week',resident.wagePaidCents==200 and state.money==98)
    Payroll.advance(state,{guest},monday+11,monday+11)
    check('guest_wages_do_not_repeat_without_elapsed_time',resident.wagePaidCents==200)
    Payroll.advance(state,{guest},8*24+20,11*24+9)
    check('guest_wages_skip_closed_weekend',resident.wageEarnedCents==200)

    local offer=assert(Intent.normalize({kind='player_wage_propose',residentId=id,
        expectedRevision=0,wageCents=3000}))
    local accepted=assert(Intent.normalize({kind='player_wage_accept',residentId=id,expectedRevision=1}))
    local connected={host,guest}
    check('guest_wage_rejects_unconnected_offer',not Payroll.command(state,offer,host,{host}))
    check('guest_wage_rejects_unrelated_player',not Payroll.command(state,offer,{id=3},connected))
    check('guest_wage_offer_needs_other_players_acceptance',Payroll.command(state,offer,host,connected)
        and resident.wageCents==100 and not Payroll.command(state,accepted,host,connected))
    check('guest_wage_rejects_stale_offer',not Payroll.command(state,offer,guest,connected))
    check('guest_wage_agreement_changes_saved_rate',Payroll.command(state,accepted,guest,connected)
        and resident.wageCents==3000 and resident.wageRevision==2 and resident.wageProposal==nil)
    check('guest_wage_snapshot_keeps_contract',Schema.validState(Schema.snapshot(state)))

    state.money=5
    Payroll.advance(state,{guest},monday+11,monday+12)
    check('guest_wage_short_cash_remains_host_debt',resident.wageEarnedCents==3200
        and resident.wagePaidCents==700 and Payroll.totalOwed(state)==2500 and state.money==0)
    check('guest_wage_outstanding_balance_appears_in_budget',
        require('src.household_finances').reserves(state).unpaid>=2500
        and require('src.staff_finances').summary(state).earnedUnpaid==25)
    Residents.advance(state,{host},monday+12,monday+13)
    Payroll.advance(state,{},monday+12,monday+13)
    check('guest_wage_disconnect_stops_new_earnings',resident.activePlayerId==nil
        and resident.wageEarnedCents==3200)
    state.money=25
    Payroll.advance(state,{},monday+13,monday+13)
    check('guest_wage_old_debt_settles_after_disconnect',resident.wagePaidCents==3200
        and Payroll.totalOwed(state)==0 and state.money==0)
    local reconnect={id=3,name='Worker renamed',sceneId='warehouse'}
    check('guest_wage_reconnect_keeps_agreement',Residents.bind(state,reconnect,token,{host})==id
        and resident.wageCents==3000 and resident.wagePaidCents==3200)
    local sent
    local computer=require('src.screens.computer_screen').new({localPlayerId=1,
        warehouseCommand=function(intent) sent=intent;return true,'completed','Wage offer sent.' end})
    computer.enter(state)
    local arrowX,arrowY=computer.dropdownCenter()
    computer.mousepressed(state,arrowX,arrowY,1)
    local tabX,tabY=computer.tabCenter('player_wages')
    computer.mousepressed(state,tabX,tabY,1)
    local plusX,plusY=computer.playerWageControlCenter('plus',1)
    computer.mousepressed(state,plusX,plusY,1)
    local offerX,offerY=computer.playerWageControlCenter('propose',1)
    computer.mousepressed(state,offerX,offerY,1)
    check('guest_wage_office_tab_sends_checked_offer',computer.tab=='player_wages' and sent
        and sent.kind=='player_wage_propose' and sent.residentId==id
        and sent.wageCents==3100 and sent.expectedRevision==2)
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.setCanvas(canvas)
    computer.draw(state)
    love.graphics.setCanvas()
    check('guest_wage_office_tab_draws',canvas~=nil)
    local saved=0
    local office=require('src.office_authority').command({state=state,
        world={validateNetworkWorkshopAccess=function() return true end},
        players=function() return {host,reconnect} end,
        save=function() saved=saved+1;return true end})
    local proposed=office.perform({},reconnect,{officeIntent={kind='player_wage_propose',
        residentId=id,expectedRevision=2,wageCents=3200}})
    local agreed=office.perform({},host,{officeIntent={kind='player_wage_accept',
        residentId=id,expectedRevision=3}})
    check('guest_wage_office_authority_saves_two_party_agreement',proposed and agreed
        and saved==2 and resident.wageCents==3200 and resident.wageRevision==4)
    local noDisk=require('src.office_authority').command({state=state,
        world={validateNetworkWorkshopAccess=function() return true end},
        players=function() return {host,reconnect} end,
        save=function() return false,'disk full' end})
    check('guest_wage_failed_host_save_rolls_back_offer',
        not noDisk.perform({},host,{officeIntent={kind='player_wage_propose',
            residentId=id,expectedRevision=4,wageCents=3300}})
        and resident.wageRevision==4 and resident.wageProposal==nil)

    -- Exercise the real receipt file with an in-memory slot adapter. The
    -- host's state is never itself used as the player's destination shop.
    if love.filesystem.getInfo(Pay.FILE) then assert(love.filesystem.remove(Pay.FILE)) end
    check('guest_wage_receipt_is_credential_bound',Pay.recordSnapshot(state,id,token)
        and not Pay.recordSnapshot(state,id,string.rep('a',64)))
    local own=State.new()
    local startingBalance=own.home.balanceCents
    local slots={}
    local save={load=function(slot) return slots[slot] end}
    local function saveCurrent()
        slots[1]={state=Schema.copy(own)}
        return true
    end
    local imported,amount=Pay.claim(own,save,saveCurrent)
    check('guest_wage_imports_into_own_save',imported and amount==3200
        and own.home.balanceCents==startingBalance+3200 and slots[1].state.home.portableClaims[state.home.shopId]==3200)
    imported,amount=Pay.claim(own,save,saveCurrent)
    check('guest_wage_receipt_cannot_be_claimed_twice',imported and amount==0)
    resident.wageEarnedCents,resident.wagePaidCents=6200,6200
    assert(Pay.recordSnapshot(state,id,token))
    local other=State.new()
    imported,amount=Pay.claim(other,save,function()
        slots[2]={state=Schema.copy(other)}
        return true
    end)
    check('guest_wage_later_payment_imports_only_difference',imported and amount==3000)
    check('guest_wage_claim_does_not_spread_across_slots',Pay.claim(own,save,saveCurrent)
        and own.home.balanceCents==startingBalance+3200)
    local interrupted=assert(Pay.load())
    interrupted.sequence=interrupted.sequence+1
    interrupted.sources[state.home.shopId]=8200
    local encoded=assert(require('src.net.codec').encode(interrupted))
    assert(love.filesystem.write(Pay.FILE..'.tmp',encoded))
    assert(love.filesystem.write(Pay.FILE,'interrupted write'))
    check('guest_wage_receipt_survives_interrupted_replace',
        assert(Pay.load()).sources[state.home.shopId]==8200)
    assert(love.filesystem.remove(Pay.FILE))
    assert(love.filesystem.remove(Pay.FILE..'.tmp'))
end

return Test
