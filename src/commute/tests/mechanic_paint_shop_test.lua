-- Real paint catalog/controller/host transaction tests. Only the visual room is
-- mocked; previews, request routing, prices and replicated records remain real.
local C=require('src.commute.runtime')
local Shop=require('src.commute.mechanic_shop')
local Paint=require('src.commute.bike_paint')
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
    assert(Residents.bind(state,guest,string.rep('d',64),{host}))
    local week=state.home.weekend
    week.travelToken=23;week.readyMask=3;week.travelPurpose='outing';week.travelOrigin='warehouse'
    assert(Trip.start(state,{host,guest},23,world));require('src.home_travel').clearRequest(week)
    local R={state=state,World={player=host},Config={baseWidth=960,baseHeight=678},App={},
        _commute={world=world},saves=0,dirty=0}
    R.saveCurrent=function()R.saves=R.saves+1;return true end
    R.multiplayer={isClient=function()return false end,isHost=function()return true end,
        markShopDirty=function()R.dirty=R.dirty+1 end}
    for _,player in ipairs({host,guest}) do
        local r=state.home.commute.participants[Residents.key(player)].rider
        local site=world.sites.byId.mechanic
        r.gear.mounted=false;r.gear.engine=false;r.gear.transition=nil
        r.bike.x,r.bike.z=site.parking.x,site.parking.z;r.bike.speed=0;Bike.resetContact(r.bike,world)
        r.ped.x,r.ped.z=site.door.x,site.door.z;r.ped.speed=0
    end
    return R,host,guest
end
local function resident(R,player)return R.state.home.residents[Residents.key(player or R.World.player)]end
local function bike(R,player)return R.state.home.commute.participants[Residents.key(player or R.World.player)].rider.bike end
local function copyTo(H,Client)
    assert(State.applySharedSnapshot(Client.state,assert(Schema.snapshot(H.state))));Client.state.screen='world'
end
local function clientFixture()
    local H,host,guest=fixture();local state=State.new();local requests={}
    local Client={state=state,World={player={id=2,sceneId='commute',homeResidentId=Residents.key(guest)}},
        Config={baseWidth=960,baseHeight=678},App={},_commute={world=C.world(H)}}
    copyTo(H,Client)
    Client.multiplayer={isClient=function()return true end,isHost=function()return false end,
        requestInteraction=function(_,kind,command)
            requests[#requests+1]={kind=kind,command=command};return true,'Queued for host'
        end}
    assert(C.openMechanic(Client));assert(Shop.paint(Client));assert(Shop.selectPaint(Client,'red'))
    return H,Client,guest,requests
end
local function order(R)
    assert(Shop.confirm(R));assert(Shop.confirm(R));return R._commute.mechanicOffer
end
local function run(check)
    local R,host=fixture();local before=R.state.home.balanceCents
    assert(C.openMechanic(R));local v=R._commute.mechanicOffer
    check('mechanic_paint_shop_opens_with_performance_service',v.page=='lobby' and v.service=='performance')
    assert(C.keypressed(R,'e'));assert(C.keypressed(R,'tab'))
    check('mechanic_paint_shop_tab_exposes_eight_finishes',v.page=='catalog' and v.service=='paint' and #Paint.CATALOG==8)
    local all=true
    for n,finish in ipairs(Paint.CATALOG) do
        assert(C.keypressed(R,tostring(n)))
        all=all and v.selectedPaintId==finish.id and Shop.paintQuote(R,finish.id).offer==finish
    end
    check('mechanic_paint_shop_keys_browse_all_finishes_without_ownership_change',all and resident(R).ridingPaintId=='bronze'
        and bike(R).paintId=='bronze' and resident(R).ridingPaintRevision==0 and R.state.home.balanceCents==before and R.saves==0)
    R.Config.baseWidth,R.Config.baseHeight=640,480;all=true
    for n,finish in ipairs(Paint.CATALOG) do
        local x=96+(n-1)%2*124+57;local y=170+math.floor((n-1)/2)*92+40
        assert(C.pointer(R,x*640/960,y*480/678));all=all and v.selectedPaintId==finish.id
    end
    check('mechanic_paint_shop_scaled_pointer_reaches_all_eight_swatches',all)
    R.Config.baseWidth,R.Config.baseHeight=960,678
    local angle=v.previewFrame;assert(C.keypressed(R,'r'));assert(C.keypressed(R,'q'))
    local views={};for _=1,16 do
        views[v.previewFrame]=true;assert(C.keypressed(R,'r'))
    end
    local unique=0;for _ in pairs(views)do unique=unique+1 end
    check('mechanic_paint_shop_preview_cycles_all_sixteen_angles_without_purchase',unique==16 and v.previewFrame==angle
        and resident(R).ridingPaintId=='bronze' and bike(R).paintId=='bronze' and R.saves==0)
    check('mechanic_paint_shop_rotation_and_invalid_selection_are_local',v.previewFrame==angle
        and not Shop.selectPaint(R,'neon-invalid') and bike(R).paintId=='bronze' and R.saves==0)
    assert(C.keypressed(R,'tab'));local repair=v.service=='repair'
    assert(C.keypressed(R,'tab'));local performance=v.service=='performance'
    assert(C.deviceInput(R,'controller','x'));local paint=v.service=='paint'
    assert(C.deviceInput(R,'controller','rightshoulder'));local rightRepair=v.service=='repair'
    assert(C.deviceInput(R,'controller','leftshoulder'));local leftPerformance=v.service=='performance'
    check('mechanic_paint_shop_keyboard_and_controller_reach_all_three_services',
        repair and performance and paint and rightRepair and leftPerformance)
    assert(Shop.selectPaint(R,'red'));assert(Shop.confirm(R))
    check('mechanic_paint_shop_first_approval_only_reviews_fixed_quote',v.page=='confirm' and not v.pending
        and Shop.paintQuote(R,'red').priceCents==12500 and R.state.home.balanceCents==before and R.saves==0)
    assert(C.keypressed(R,'escape'))
    check('mechanic_paint_shop_cancel_preview_keeps_original_bike',v.page=='lobby' and bike(R).paintId=='bronze'
        and resident(R).ridingPaintRevision==0 and R.state.home.balanceCents==before and R.saves==0)
    assert(Shop.paint(R));assert(Shop.selectPaint(R,'bronze'))
    check('mechanic_paint_shop_current_finish_cannot_charge',Shop.paintQuote(R,'bronze').status=='current'
        and not Shop.confirm(R) and not v.pending and R.state.home.balanceCents==before and R.saves==0)
    assert(Shop.selectPaint(R,'red'));R.state.home.balanceCents=Paint.COST_CENTS-1
    check('mechanic_paint_shop_unaffordable_finish_reports_shortfall',Shop.paintQuote(R,'red').shortfallCents==1
        and not Shop.confirm(R) and v.page=='catalog' and R.saves==0)
    R.state.home.balanceCents=before;assert(Shop.confirm(R));R.state.home.balanceCents=0
    check('mechanic_paint_shop_funds_changed_after_quote_cannot_purchase',not Shop.confirm(R) and not v.pending
        and bike(R).paintId=='bronze' and R.state.home.balanceCents==0 and R.saves==0)
    C.keypressed(R,'escape');Shop.paint(R);Shop.selectPaint(R,'red');R.state.home.balanceCents=before
    assert(Shop.confirm(R));R.state.home.revision=R.state.home.revision+100;assert(Shop.confirm(R))
    check('mechanic_paint_shop_unrelated_household_changes_do_not_invalidate_paint',v.pending and v.pending.kind=='paint'
        and v.pending.previous==0 and v.pending.paintId=='red' and bike(R).paintId=='red'
        and resident(R).ridingPaintRevision==1 and R.state.home.balanceCents==before-Paint.COST_CENTS and R.saves==1)
    C.keypressed(R,'tab');C.deviceInput(R,'controller','x');C.keypressed(R,'escape');C.pointer(R,730,130)
    check('mechanic_paint_shop_pending_blocks_switch_exit_and_second_purchase',R._commute.mechanicOffer==v
        and v.service=='paint' and v.page=='confirm' and not Shop.selectPaint(R,'blue') and not Shop.confirm(R) and R.saves==1)
    Shop.update(R,.1)
    check('mechanic_paint_shop_receipt_requires_exact_authoritative_finish',v.page=='install' and not v.pending
        and v.receipt.kind=='paint' and v.receipt.paintId=='red' and v.receipt.costCents==Paint.COST_CENTS)
    C.keypressed(R,'tab');C.keypressed(R,'escape');C.pointer(R,180,590)
    check('mechanic_paint_shop_install_guards_service_and_exit',v.page=='install' and R._commute.mechanicOffer==v
        and not Shop.catalog(R) and not Shop.paint(R))
    for _=1,21 do Shop.update(R,.1) end
    check('mechanic_paint_shop_install_finishes_without_second_debit',v.page=='receipt'
        and R.state.home.balanceCents==before-Paint.COST_CENTS and R.saves==1)
    C.keypressed(R,'return');C.keypressed(R,'escape')
    check('mechanic_paint_shop_receipt_returns_to_shop_then_outdoors',not R._commute.mechanicOffer and bike(R).paintId=='red')
    assert(C.command(R,host,'bikeupgrade:23:0:1'));assert(C.command(R,host,'bikeupgrade:23:1:2'))
    assert(C.command(R,host,'bikeupgrade:23:2:3'));assert(C.openMechanic(R));assert(Shop.paint(R));assert(Shop.selectPaint(R,'teal'))
    check('mechanic_paint_shop_max_engine_still_allows_cosmetic_service',bike(R).upgradeLevel==3
        and Shop.paintQuote(R,'teal').status=='available' and Shop.confirm(R))
    C.release(R)

    -- A quote belongs to the revision shown when the player reviewed it, even
    -- if another accepted service changes A -> B -> A before they press Pay.
    local S,owner=fixture();assert(C.openMechanic(S));Shop.paint(S);Shop.selectPaint(S,'red');assert(Shop.confirm(S))
    assert(C.command(S,owner,'bikepaint:23:0:blue'));assert(C.command(S,owner,'bikepaint:23:1:bronze'))
    local spent=S.state.home.balanceCents
    check('mechanic_paint_shop_stale_review_after_color_roundtrip_requires_new_quote',not Shop.confirm(S)
        and not S._commute.mechanicOffer.pending and resident(S).ridingPaintRevision==2 and bike(S).paintId=='bronze'
        and S.state.home.balanceCents==spent and S.saves==2)
    C.release(S)

    local H,Client,guest,requests=clientFixture();local cv=order(Client);local clientBalance=Client.state.home.balanceCents
    Shop.update(Client,.1)
    check('mechanic_paint_shop_transport_ack_does_not_claim_paid_finish',#requests==1 and requests[1].kind=='commute'
        and cv.pending and cv.pending.kind=='paint' and not cv.receipt and cv.page=='confirm'
        and resident(Client).ridingPaintId=='bronze' and Client.state.home.balanceCents==clientBalance)
    H.state.home.balanceCents=0
    check('mechanic_paint_shop_host_denies_stale_funds_after_client_quote',not C.command(H,guest,requests[1].command)
        and resident(H,guest).ridingPaintRevision==0 and bike(H,guest).paintId=='bronze' and H.saves==0)
    for _=1,51 do Shop.update(Client,.1) end
    check('mechanic_paint_shop_timeout_offers_retry_without_receipt',not cv.pending and not cv.receipt and cv.page=='catalog'
        and cv.notice:find('No installation confirmed',1,true)~=nil)
    H.state.home.balanceCents=1000000;H.state.home.revision=H.state.home.revision+1;copyTo(H,Client)
    order(Client);local retry=requests[2];assert(C.command(H,guest,retry.command));Shop.update(Client,.1)
    check('mechanic_paint_shop_host_purchase_waits_for_replication',cv.pending and not cv.receipt
        and resident(Client).ridingPaintRevision==0 and resident(H,guest).ridingPaintRevision==1)
    copyTo(H,Client);Shop.update(Client,.1)
    check('mechanic_paint_shop_fresh_retry_receipt_follows_exact_host_revision_and_id',cv.page=='install'
        and cv.receipt.kind=='paint' and cv.receipt.paintId=='red' and not cv.pending
        and resident(Client).ridingPaintRevision==1 and bike(Client).paintId=='red')
    check('mechanic_paint_shop_guest_order_never_paints_host',resident(H).ridingPaintId=='bronze' and bike(H).paintId=='bronze'
        and resident(H,guest).ridingPaintId=='red' and bike(H,guest).paintId=='red')
    spent=H.state.home.balanceCents
    check('mechanic_paint_shop_duplicate_request_never_debits_twice',not C.command(H,guest,retry.command)
        and H.state.home.balanceCents==spent and H.saves==1)
    C.release(Client)

    -- A different finish at revision +1, or the same finish after later work,
    -- must not be presented as confirmation of this pending work order.
    local H2,C2,g2=clientFixture();local v2=order(C2)
    assert(C.command(H2,g2,'bikepaint:23:0:blue'));copyTo(H2,C2);Shop.update(C2,.1)
    check('mechanic_paint_shop_wrong_finish_at_expected_revision_is_not_success',not v2.pending and not v2.receipt
        and v2.page=='catalog' and resident(C2).ridingPaintId=='blue')
    C.release(C2)
    local H3,C3,g3=clientFixture();local v3=order(C3)
    assert(C.command(H3,g3,'bikepaint:23:0:red'));assert(C.command(H3,g3,'bikepaint:23:1:blue'))
    assert(C.command(H3,g3,'bikepaint:23:2:red'));copyTo(H3,C3);Shop.update(C3,.1)
    check('mechanic_paint_shop_same_finish_at_later_revision_is_not_success',not v3.pending and not v3.receipt
        and v3.page=='catalog' and resident(C3).ridingPaintRevision==3 and resident(C3).ridingPaintId=='red')
    C.release(C3)
end
function Test.run(check)
    local name='src.commute.mechanic_interior';local previous=package.loaded[name]
    package.loaded[name]={new=function()return {}end,release=function()end,update=function()end,draw=function()end,
        drawBike=function()end,drawMechanic=function()end,
        keypressed=function(_,_,key)if key=='return' or key=='e' then return 'catalog' end end,
        pointer=function()return 'catalog'end}
    local okay,reason=xpcall(function()run(check)end,debug.traceback)
    package.loaded[name]=previous
    if not okay then error(reason,0) end
end
return Test
