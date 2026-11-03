-- Exercise the real shop/controller/transaction boundary. Only the visual
-- interior module is replaced; quotes, rider checks and purchases stay real.
local C=require('src.commute.runtime')
local Shop=require('src.commute.mechanic_shop')
local Upgrades=require('src.commute.bike_upgrades')
local State=require('src.state')
local Schema=require('src.save_schema')
local Town=require('src.commute.town')
local Trip=require('src.commute.trip')
local Bike=require('src.commute.motorcycle')
local Residents=require('src.home_residents')
local Test={}
local function fixture()
    local state=State.new();state.screen='world';state.home.balanceCents=1000000
    state.home.town=assert(Town.generate(712345))
    local world=Town.world(state.home.town)
    local host={id=1,sceneId='commute',homeResidentId='owner'}
    local guest={id=2,sceneId='commute'}
    assert(Residents.bind(state,guest,string.rep('c',64),{host}))
    local week=state.home.weekend;week.travelToken=17;week.readyMask=3;week.travelPurpose='outing';week.travelOrigin='warehouse'
    assert(Trip.start(state,{host,guest},17,world));require('src.home_travel').clearRequest(week)
    local R={state=state,World={player=host},Config={baseWidth=960,baseHeight=678},App={},_commute={world=world},saves=0,dirty=0}
    R.saveCurrent=function()R.saves=R.saves+1;return true end
    R.multiplayer={isClient=function()return false end,isHost=function()return true end,markShopDirty=function()R.dirty=R.dirty+1 end}
    local function park(player)
        local part=state.home.commute.participants[Residents.key(player)];local r=part.rider;local site=world.sites.byId.mechanic
        r.gear.mounted=false;r.gear.engine=false;r.gear.transition=nil
        r.bike.x,r.bike.z=site.parking.x,site.parking.z;r.bike.speed=0;Bike.resetContact(r.bike,world)
        r.ped.x,r.ped.z=site.door.x,site.door.z;r.ped.speed=0
        return r
    end
    return R,host,guest,park
end
local function run(check,counters)
    local R,host,guest,park=fixture();local state=R.state
    local balance=state.home.balanceCents;local rider=state.home.commute.participants.owner.rider
    check('mechanic_shop_requires_actual_parked_door',not C.openMechanic(R) and not R._commute.mechanicOffer and counters.created==0)
    park(host);rider.gear.outfit='geared';rider.gear.mounted=true;rider.gear.engine=true
    check('mechanic_shop_rejects_seated_running_bike',not C.openMechanic(R))
    park(host);rider.bike.grounded=false
    check('mechanic_shop_rejects_airborne_bike',not C.openMechanic(R));park(host)
    assert(C.openMechanic(R));local v=R._commute.mechanicOffer
    check('mechanic_shop_enters_lobby_without_changing_money_or_bike',v.page=='lobby' and counters.created==1
        and state.home.balanceCents==balance and rider.bike.upgradeLevel==0)
    assert(C.deviceInput(R,'controller','a'));check('mechanic_shop_controller_opens_catalog',v.page=='catalog')
    local all=true
    for n=1,3 do
        assert(C.keypressed(R,tostring(n)));local q=Shop.quote(R,n)
        all=all and v.selected==n and q.offer==Upgrades.CATALOG[n] and q.current.level==0
            and q.status==(n==1 and 'available' or 'locked')
    end
    check('mechanic_shop_all_three_tiers_are_browsable_with_live_status',all)
    R.Config.baseWidth,R.Config.baseHeight=640,452
    assert(C.pointer(R,200*640/960,202*452/678))
    local firstTouch=v.selected==1
    assert(C.pointer(R,200*640/960,434*452/678))
    check('mechanic_shop_pointer_selects_scaled_catalog_tiers',firstTouch and v.selected==3)
    R.Config.baseWidth,R.Config.baseHeight=960,678
    local before=state.home.balanceCents
    check('mechanic_shop_locked_tier_cannot_start_confirmation',not C.buyUpgrade(R) and v.page=='catalog' and state.home.balanceCents==before)
    C.keypressed(R,'1');assert(C.buyUpgrade(R))
    check('mechanic_shop_first_confirm_only_reviews_quote',v.page=='confirm' and not v.pending and state.home.balanceCents==before and R.saves==0)
    C.keypressed(R,'escape')
    check('mechanic_shop_cancel_quote_does_not_purchase',v.page=='lobby' and rider.bike.upgradeLevel==0 and R.saves==0)
    Shop.catalog(R);state.home.balanceCents=Upgrades.CATALOG[1].costCents-1
    local q=Shop.quote(R,1)
    check('mechanic_shop_unaffordable_quote_reports_exact_shortfall',q.status=='unaffordable' and q.shortfallCents==1
        and not C.buyUpgrade(R) and v.page=='catalog')
    state.home.balanceCents=balance;assert(C.buyUpgrade(R))
    state.home.revision=state.home.revision+100 -- payroll/needs may advance behind the quote
    assert(C.buyUpgrade(R))
    check('mechanic_shop_install_accepts_unrelated_household_revision',rider.bike.upgradeLevel==1
        and state.home.residents.owner.ridingUpgradeLevel==1 and state.home.balanceCents==balance-Upgrades.CATALOG[1].costCents
        and R._commute.mechanicOffer==v and v.pending~=nil and R.saves==1 and R.dirty==1)
    local spent=state.home.balanceCents
    check('mechanic_shop_replayed_expected_level_debits_once',not C.command(R,host,'bikeupgrade:17:0:1')
        and state.home.balanceCents==spent and R.saves==1)
    Shop.update(R,.1)
    check('mechanic_shop_receipt_follows_authoritative_install',not v.pending and v.page=='install'
        and v.receipt.level==1 and v.receipt.costCents==Upgrades.CATALOG[1].costCents)
    for _=1,21 do Shop.update(R,.1) end
    check('mechanic_shop_service_finishes_in_open_shop',v.page=='receipt' and R._commute.mechanicOffer==v)
    assert(C.deviceInput(R,'controller','a'));assert(C.deviceInput(R,'controller','b'))
    check('mechanic_shop_controller_exit_releases_only_interior',not R._commute.mechanicOffer and counters.released==1
        and state.home.commute~=nil and rider.bike.upgradeLevel==1)
    park(guest);local guestId=Residents.key(guest);local guestBike=state.home.commute.participants[guestId].rider.bike
    check('mechanic_shop_guest_cannot_impersonate_another_slot',not C.command(R,{id=3,sceneId='commute',homeResidentId=guestId},'bikeupgrade:17:0:1'))
    assert(C.command(R,guest,'bikeupgrade:17:0:1'))
    check('mechanic_shop_host_dispatch_upgrades_assigned_guest_only',guestBike.upgradeLevel==1
        and state.home.residents[guestId].ridingUpgradeLevel==1 and rider.bike.upgradeLevel==1)
    assert(C.command(R,host,'bikeupgrade:17:1:2'));assert(C.command(R,host,'bikeupgrade:17:2:3'))
    assert(C.openMechanic(R));Shop.catalog(R)
    check('mechanic_shop_maxed_bike_can_still_visit_and_review_all_tiers',R._commute.mechanicOffer~=nil
        and Shop.quote(R,1).status=='installed' and Shop.quote(R,2).status=='installed' and Shop.quote(R,3).status=='installed'
        and not C.buyUpgrade(R))
    C.release(R);check('mechanic_shop_runtime_release_closes_interior',not R._commute and counters.released==2)

    -- The client only sends an intent. A transport ACK must not be mistaken
    -- for a purchase, and a rejected order can be retried against fresh state.
    local H,owner,remote,parkRemote=fixture();parkRemote(remote)
    local remoteId=Residents.key(remote);local clientState=State.new()
    assert(State.applySharedSnapshot(clientState,assert(Schema.snapshot(H.state))))
    local localGuest={id=2,sceneId='commute',homeResidentId=remoteId}
    local requests={};local Client={state=clientState,World={player=localGuest},Config={baseWidth=960,baseHeight=678},App={},
        _commute={world=C.world(H)}}
    Client.state.screen='world'
    Client.multiplayer={isClient=function()return true end,isHost=function()return false end,
        requestInteraction=function(_,kind,command)requests[#requests+1]={kind=kind,command=command};return true,'Queued for host' end}
    assert(C.openMechanic(Client));Shop.catalog(Client);assert(C.buyUpgrade(Client));assert(C.buyUpgrade(Client))
    local pending=Client._commute.mechanicOffer;local clientBalance=Client.state.home.balanceCents
    Shop.update(Client,.1)
    check('mechanic_shop_client_transport_ack_does_not_claim_install',#requests==1 and requests[1].kind=='commute'
        and pending.pending~=nil and pending.page=='confirm' and not pending.receipt
        and (Client.state.home.residents[remoteId].ridingUpgradeLevel or 0)==0 and Client.state.home.balanceCents==clientBalance)
    H.state.home.balanceCents=0
    check('mechanic_shop_host_denies_quote_when_funds_changed',not C.command(H,remote,requests[1].command)
        and (H.state.home.residents[remoteId].ridingUpgradeLevel or 0)==0 and H.saves==0)
    for _=1,51 do Shop.update(Client,.1) end
    check('mechanic_shop_unconfirmed_order_returns_to_retry_without_success',not pending.pending and not pending.receipt
        and pending.page=='catalog' and pending.notice:find('No installation confirmed',1,true)~=nil)
    H.state.home.balanceCents=1000000;H.state.home.revision=H.state.home.revision+1
    assert(State.applySharedSnapshot(Client.state,assert(Schema.snapshot(H.state))))
    Client.state.screen='world';assert(C.buyUpgrade(Client));assert(C.buyUpgrade(Client))
    local retry=requests[2];assert(C.command(H,remote,retry.command));Shop.update(Client,.1)
    check('mechanic_shop_client_waits_for_replicated_level_even_after_host_purchase',pending.pending~=nil and not pending.receipt
        and (Client.state.home.residents[remoteId].ridingUpgradeLevel or 0)==0)
    assert(State.applySharedSnapshot(Client.state,assert(Schema.snapshot(H.state))))
    Client.state.screen='world';Shop.update(Client,.1)
    check('mechanic_shop_fresh_retry_confirms_only_after_host_replication',pending.page=='install' and pending.receipt.level==1
        and Client.state.home.residents[remoteId].ridingUpgradeLevel==1 and H.saves==1
        and (H.state.home.residents.owner.ridingUpgradeLevel or 0)==0)
    local finalBalance=H.state.home.balanceCents
    check('mechanic_shop_late_duplicate_order_still_cannot_charge_again',not C.command(H,remote,retry.command)
        and H.state.home.balanceCents==finalBalance and H.saves==1)
    C.release(Client)
end
local function testRepairs(check)
    local R,host,guest,park=fixture()
    local home=R.state.home
    local function damaged(player,damage)
        local resident=Residents.get(R.state,player)
        resident.ridingDamage=damage
        home.commute.participants[Residents.key(player)].rider.bike.damage=damage
    end
    damaged(host,40)
    check('mechanic_repair_checks_actual_patient_and_location',
        not C.command(R,host,'bikerepair:17:0:40') and R.saves==0)
    check('mechanic_repair_rejects_forged_damage_and_revision',
        not C.decode('bikerepair:17:0:0') and not C.decode('bikerepair:17:0:101')
        and not C.decode('bikerepair:17:-1:40') and not C.decode('bikerepair:17:0:40:1'))
    local rider=park(host)
    assert(C.openMechanic(R));assert(C.keypressed(R,'e'))
    local view=R._commute.mechanicOffer
    local quote=Shop.repairQuote(R)
    check('mechanic_repair_counter_prioritizes_damaged_bike_and_quotes_condition',
        view.service=='repair' and quote.condition==60 and quote.priceCents==8000)
    home.balanceCents=quote.priceCents-1
    check('mechanic_repair_unaffordable_at_counter_and_host',
        not Shop.confirm(R) and Shop.repairQuote(R).shortfallCents==1 and not C.command(R,host,'bikerepair:17:0:40')
        and rider.bike.damage==40 and home.balanceCents==7999 and R.saves==0)
    home.balanceCents=20000
    assert(Shop.confirm(R));damaged(host,42)
    check('mechanic_repair_updated_damage_requires_fresh_quote',
        not Shop.confirm(R) and view.page=='catalog' and home.balanceCents==20000 and R.saves==0)
    assert(Shop.confirm(R));assert(Shop.confirm(R));Shop.update(R,.1)
    check('mechanic_repair_restores_live_and_owned_bike_once_for_confirmed_price',
        view.page=='install' and view.receipt.kind=='repair' and view.receipt.costCents==8400
        and home.balanceCents==11600 and home.residents.owner.ridingDamage==0
        and home.residents.owner.ridingRepairRevision==1 and rider.bike.damage==0 and R.saves==1 and R.dirty==1)
    local healthy=Shop.repairQuote(R)
    check('mechanic_repair_healthy_bike_quotes_zero',healthy.status=='healthy' and healthy.priceCents==0)
    damaged(host,42)
    check('mechanic_repair_replayed_order_after_equivalent_later_crash_is_rejected',
        not C.command(R,host,'bikerepair:17:0:42') and home.balanceCents==11600 and rider.bike.damage==42)
    damaged(guest,20);local guestRider=park(guest)
    assert(C.command(R,guest,'bikerepair:17:0:20'))
    check('mechanic_repair_host_repairs_only_purchasing_guests_bike',guestRider.bike.damage==0 and rider.bike.damage==42
        and Residents.get(R.state,guest).ridingRepairRevision==1 and home.balanceCents==7600)
    C.release(R)
end
function Test.run(check)
    local name='src.commute.mechanic_interior';local previous=package.loaded[name]
    local counters={created=0,released=0}
    package.loaded[name]={new=function()counters.created=counters.created+1;return {}end,
        release=function()counters.released=counters.released+1 end,update=function()end,draw=function()end,
        keypressed=function(_,_,key)if key=='return' or key=='e' then return 'catalog' end end,
        pointer=function()return 'catalog'end}
    local okay,reason=xpcall(function()run(check,counters);testRepairs(check)end,debug.traceback)
    package.loaded[name]=previous
    if not okay then error(reason,0) end
end
return Test
