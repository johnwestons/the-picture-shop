local Paint=require('src.commute.bike_paint')
local State=require('src.state')
local Schema=require('src.save_schema')
local Residents=require('src.home_residents')
local Town=require('src.commute.town')
local Trip=require('src.commute.trip')
local Rider=require('src.commute.rider')
local Bike=require('src.commute.motorcycle')
local C=require('src.commute.runtime')
local Test={}
function Test.run(check)
    local ids={};local palette=true
    for _,finish in ipairs(Paint.CATALOG)do
        palette=palette and not ids[finish.id] and Paint.valid(finish.id) and Paint.get(finish.id)==finish
            and finish.costCents==12500 and #finish.color==3
        for _,value in ipairs(finish.color)do palette=palette and value>=0 and value<=1 end
        ids[finish.id]=true
    end
    check('bike_paint_catalog_has_eight_bounded_named_finishes',palette and #Paint.CATALOG==8
        and Paint.DEFAULT=='bronze' and Paint.get(nil).id=='bronze' and not Paint.valid(nil) and not Paint.valid('pink')
        and Paint.validRevision(Paint.MAX_REVISION) and not Paint.validRevision('0') and Paint.get(false)==nil)
    local state=State.new();state.home.town=assert(Town.generate(712345));state.home.balanceCents=1000000
    local host={id=1,sceneId='commute'};local guest={id=2,sceneId='commute',homeResidentId='guest-1'}
    state.home.residents['guest-1']=Schema.copy(state.home.residents.owner)
    state.home.residents['guest-1'].name='Guest';state.home.residents['guest-1'].credentialHash=string.rep('b',64)
    local world=Town.world(state.home.town);local week=state.home.weekend
    week.phase='ready';week.closedAtHours=week.closesAtHours;week.travelToken=7;week.readyMask=3
    assert(Trip.start(state,{host,guest},7,world))
    local trip=state.home.commute;local site=world.sites.byId.mechanic
    local function park(id)
        local rider=trip.participants[id].rider
        rider.bike.x,rider.bike.z=site.parking.x,site.parking.z;Bike.resetContact(rider.bike,world)
        rider.ped.x,rider.ped.z,rider.ped.speed=site.door.x,site.door.z,0
        return rider
    end
    local rider=park('owner');park('guest-1')
    local owner=state.home.residents.owner
    local function intent(id,revision)return {token=7,paintId=id,expectedPaintRevision=revision or owner.ridingPaintRevision}end
    local function buy(value,player)return Paint.purchase(state,player or host,trip,world,value)end
    local money,homeRevision,residentRevision=state.home.balanceCents,state.home.revision,owner.revision
    local current=Paint.quote(state,host,'bronze')
    check('bike_paint_current_finish_quote_is_free_and_idempotent',current.status=='current' and current.priceCents==0
        and buy(intent('bronze')) and state.home.balanceCents==money and state.home.revision==homeRevision
        and owner.revision==residentRevision and owner.ridingPaintRevision==0)
    local quote=Paint.quote(state,host,'red')
    check('bike_paint_quote_discloses_price_without_mutation',quote.status=='available' and quote.priceCents==12500
        and quote.expectedPaintRevision==0 and quote.revision==0 and state.home.balanceCents==money
        and rider.bike.paintId=='bronze')
    local malformed=true
    for _,value in ipairs({{token=7,paintId='pink',expectedPaintRevision=0},
        {token=7,paintId='red'},{token=7,paintId='red',expectedPaintRevision='0'},{token=7,paintId='red',expectedPaintRevision=-1},
        {token=7,paintId='red',expectedPaintRevision=.5},{token=7,paintId='red',expectedPaintRevision=0/0},
        {token=7,paintId='red',expectedPaintRevision=math.huge},{token=7,paintId='red',expectedPaintRevision=Paint.MAX_REVISION+1}})do
        malformed=malformed and not buy(value)
    end
    check('bike_paint_rejects_unknown_finish_and_malformed_revision_atomically',malformed
        and state.home.balanceCents==money and owner.ridingPaintRevision==0 and rider.bike.paintId=='bronze')
    check('bike_paint_rejects_wrong_trip_token',not buy({token=6,paintId='red',expectedPaintRevision=0}))
    host.sceneId='home';local indoors=buy(intent('red'));host.sceneId='commute'
    check('bike_paint_requires_actual_exterior_service_visit',not indoors)
    rider.gear.mounted=true;local mounted=buy(intent('red'));rider.gear.mounted=false
    rider.gear.engine=true;local running=buy(intent('red'));rider.gear.engine=false
    rider.bike.speed=.1;local moving=buy(intent('red'));rider.bike.speed=0
    rider.ped.speed=.1;local walking=buy(intent('red'));rider.ped.speed=0
    check('bike_paint_requires_stopped_dismounted_motorcycle',not mounted and not running and not moving and not walking)
    rider.bike.grounded=false;local airborne=buy(intent('red'));rider.bike.grounded=true
    rider.bike.vy=.2;local bouncing=buy(intent('red'));rider.bike.vy=0
    check('bike_paint_rejects_airborne_or_unsettled_bike',not airborne and not bouncing)
    rider.ped.x=site.door.x+10;local away=buy(intent('red'));park('owner')
    rider.bike.x=site.parking.x+8;local distant=buy(intent('red'));park('owner')
    check('bike_paint_requires_registered_door_and_own_parked_bike',not away and not distant)
    rider.bike.paintId='blue';local mismatched=buy(intent('red'));rider.bike.paintId='bronze'
    check('bike_paint_rejects_inconsistent_resident_and_bike_finish',not mismatched and state.home.balanceCents==money)
    state.home.balanceCents=12499
    local poor=Paint.quote(state,host,'red')
    check('bike_paint_cannot_spend_business_money',poor.status=='unaffordable' and poor.shortfallCents==1
        and not buy(intent('red')) and state.home.balanceCents==12499 and state.money==180)
    state.home.balanceCents=money;state.home.revision=state.home.revision+50
    local order=intent('red',0);order.costCents=0
    assert(buy(order))
    check('bike_paint_uses_host_price_and_ignores_unrelated_household_revision',state.home.balanceCents==money-12500
        and owner.ridingPaintId=='red' and owner.ridingPaintRevision==1 and rider.bike.paintId=='red')
    check('bike_paint_replayed_request_cannot_debit_twice',not buy(order) and state.home.balanceCents==money-12500)
    assert(buy(intent('bronze',1)))
    check('bike_paint_revision_blocks_old_order_after_color_cycle',owner.ridingPaintId=='bronze'
        and owner.ridingPaintRevision==2 and not buy(order) and state.home.balanceCents==money-25000)
    assert(buy(intent('red',2)))
    local R={state=state,World={player=host},_commute={world=world},saveCurrent=function()end,
        multiplayer={isClient=function()return false end,isHost=function()return false end}}
    check('bike_paint_runtime_parser_rejects_forged_payloads',C.decode('bikepaint:7:0:teal')=='bikepaint'
        and not C.decode('bikepaint:7:-1:teal') and not C.decode('bikepaint:7:1.5:teal')
        and not C.decode('bikepaint:7:1000000000001:teal') and not C.decode('bikepaint:7:0:unknown'))
    local beforeGuest=state.home.balanceCents
    local queued
    local Client={state=state,World={player=guest},multiplayer={isClient=function()return true end,
        requestInteraction=function(_,kind,command)queued={kind,command};return true end}}
    assert(C.request(Client,'bikepaint:7:0:teal'))
    check('bike_paint_client_request_does_not_commit_before_host',queued[1]=='commute'
        and queued[2]=='bikepaint:7:0:teal' and state.home.balanceCents==beforeGuest
        and state.home.residents['guest-1'].ridingPaintId=='bronze')
    local spoof={id=3,sceneId='commute',homeResidentId='guest-1'}
    check('bike_paint_host_rejects_wrong_assigned_slot',not C.command(R,spoof,'bikepaint:7:0:teal')
        and state.home.balanceCents==beforeGuest)
    assert(C.command(R,guest,queued[2]))
    check('bike_paint_guest_purchase_changes_only_assigned_bike',state.home.residents['guest-1'].ridingPaintId=='teal'
        and state.home.residents['guest-1'].ridingPaintRevision==1 and trip.participants['guest-1'].rider.bike.paintId=='teal'
        and owner.ridingPaintId=='red' and rider.bike.paintId=='red' and state.home.balanceCents==beforeGuest-12500)
    local snapshot=assert(Schema.snapshot(state));local loaded,shared=State.new(),State.new()
    assert(State.applyLocalSave(loaded,{state=snapshot,slot=3}));assert(State.applySharedSnapshot(shared,snapshot))
    check('bike_paint_save_and_shared_snapshot_preserve_id_and_revision',loaded.home.residents.owner.ridingPaintId=='red'
        and loaded.home.residents.owner.ridingPaintRevision==3 and shared.home.residents['guest-1'].ridingPaintId=='teal'
        and shared.home.commute.participants['guest-1'].rider.bike.paintId=='teal')
    local restored=assert(Trip.restore(snapshot.home.commute,world))
    check('bike_paint_trip_restore_keeps_finish_and_safe_contact',restored.participants.owner.rider.bike.paintId=='red'
        and restored.participants.owner.rider.bike.grounded and restored.participants.owner.rider.bike.vy==0)
    assert(Trip.rebind(state,guest,{host,guest},world))
    check('bike_paint_live_rebind_preserves_guest_finish',trip.participants['guest-1'].rider.bike.paintId=='teal'
        and state.home.residents['guest-1'].ridingPaintRevision==1)
    local damaged=Rider.snapshot(rider);damaged.bike.x=-1
    local recovered=assert(Rider.restore(damaged,world,assert(Trip.parking(world,'warehouse',1))))
    check('bike_paint_position_recovery_keeps_paid_finish',recovered.bike.paintId=='red' and not recovered.gear.mounted)
    loaded.home.commute=nil;assert(Trip.start(loaded,{host,guest},7,world))
    check('bike_paint_next_trip_uses_resident_finish',loaded.home.commute.participants.owner.rider.bike.paintId=='red'
        and loaded.home.commute.participants['guest-1'].rider.bike.paintId=='teal')
    local legacy=Schema.copy(snapshot)
    for _,resident in pairs(legacy.home.residents)do resident.ridingPaintId=nil;resident.ridingPaintRevision=nil end
    for _,part in pairs(legacy.home.commute.participants)do part.rider.bike.paintId=nil end
    local old=State.new();assert(State.applyLocalSave(old,{state=legacy,slot=3}))
    check('bike_paint_legacy_snapshot_defaults_to_original_bronze',old.home.residents.owner.ridingPaintId=='bronze'
        and old.home.residents.owner.ridingPaintRevision==0 and old.home.commute.participants.owner.rider.bike.paintId=='bronze')
    local rejected=true
    for _,value in ipairs({'pink',false,123})do
        local bad=Schema.copy(snapshot);bad.home.residents.owner.ridingPaintId=value
        rejected=rejected and not State.applySharedSnapshot(State.new(),bad)
        bad=Schema.copy(snapshot);bad.home.commute.participants.owner.rider.bike.paintId=value
        rejected=rejected and not State.applySharedSnapshot(State.new(),bad)
    end
    for _,value in ipairs({-1,.5,0/0,math.huge,Paint.MAX_REVISION+1})do
        local bad=Schema.copy(snapshot);bad.home.residents.owner.ridingPaintRevision=value
        rejected=rejected and not State.applySharedSnapshot(State.new(),bad)
    end
    check('bike_paint_rejects_invalid_persistent_ids_and_revisions',rejected)
    local inconsistent=Schema.copy(snapshot);inconsistent.home.commute.participants.owner.rider.bike.paintId='cream'
    check('bike_paint_snapshot_rejects_resident_vehicle_mismatch',not State.applySharedSnapshot(State.new(),inconsistent))
    owner.ridingUpgradeLevel=3;rider.bike.upgradeLevel=3
    assert(buy(intent('green')))
    check('bike_paint_available_after_all_performance_upgrades',owner.ridingPaintId=='green' and rider.bike.upgradeLevel==3)
    owner.ridingPaintRevision=Paint.MAX_REVISION;local finalMoney=state.home.balanceCents
    check('bike_paint_revision_exhaustion_rejects_without_partial_charge',not buy(intent('purple'))
        and state.home.balanceCents==finalMoney and owner.ridingPaintId=='green')
end
return Test
