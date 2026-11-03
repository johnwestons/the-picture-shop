local Upgrades=require('src.commute.bike_upgrades')
local Town=require('src.commute.town')
local State=require('src.state')
local Schema=require('src.save_schema')
local Trip=require('src.commute.trip')
local Bike=require('src.commute.motorcycle')
local Test={}
function Test.run(check)
    local state=State.new();state.home.town=assert(Town.generate(712345));state.home.balanceCents=1000000
    local world=Town.world(state.home.town)
    local host={id=1,sceneId='commute'};local guest={id=2,sceneId='commute',homeResidentId='guest-1'}
    state.home.residents['guest-1']=Schema.copy(state.home.residents.owner)
    state.home.residents['guest-1'].name='Guest';state.home.residents['guest-1'].credentialHash=string.rep('b',64)
    local week=state.home.weekend;week.phase='ready';week.closedAtHours=week.closesAtHours
    week.travelToken=7;week.readyMask=3
    assert(Trip.start(state,{host,guest},7,world))
    local trip=state.home.commute;local site=assert(world.sites.byId.mechanic)
    local function park(id)
        local r=trip.participants[id].rider
        r.bike.x,r.bike.z=site.parking.x,site.parking.z;Bike.resetContact(r.bike,world)
        r.ped.x,r.ped.z=site.door.x,site.door.z;return r
    end
    local rider=park('owner');park('guest-1')
    local function intent(level)return {level=level,token=7,expectedRevision=state.home.revision} end
    local money=state.home.balanceCents;local buy=intent(1)
    check('commute_upgrade_requires_current_trip_and_revision',not Upgrades.purchase(state,host,trip,world,
        {level=1,token=6,expectedRevision=state.home.revision}) and not Upgrades.purchase(state,host,trip,world,
        {level=1,token=7,expectedRevision=state.home.revision-1}) and state.home.balanceCents==money)
    rider.gear.outfit='geared';rider.gear.mounted=true;rider.gear.engine=true
    check('commute_upgrade_requires_park_and_dismount',not Upgrades.purchase(state,host,trip,world,buy))
    rider.gear.mounted=false;rider.gear.engine=false;rider.ped.speed=.1
    check('commute_upgrade_requires_stopped_pedestrian',not Upgrades.purchase(state,host,trip,world,buy))
    rider.ped.speed=0;rider.ped.x=site.door.x+10
    check('commute_upgrade_requires_actual_mechanic_door',not Upgrades.purchase(state,host,trip,world,buy))
    park('owner');state.home.balanceCents=Upgrades.CATALOG[1].costCents-1
    check('commute_upgrade_cannot_spend_business_money',not Upgrades.purchase(state,host,trip,world,buy)
        and state.money==180 and rider.bike.upgradeLevel==0)
    state.home.balanceCents=money
    check('commute_upgrade_requires_sequential_progress',not Upgrades.purchase(state,host,trip,world,intent(2)))
    assert(Upgrades.purchase(state,host,trip,world,buy))
    check('commute_upgrade_debits_once_and_rejects_replay',state.home.balanceCents==money-Upgrades.CATALOG[1].costCents
        and state.home.residents.owner.ridingUpgradeLevel==1 and rider.bike.upgradeLevel==1
        and not Upgrades.purchase(state,host,trip,world,buy))
    assert(Upgrades.purchase(state,host,trip,world,intent(2)))
    assert(Upgrades.purchase(state,host,trip,world,intent(3)))
    check('commute_upgrade_catalog_has_bounded_top_level',not Upgrades.next(3)
        and not Upgrades.purchase(state,host,trip,world,intent(4)) and rider.bike.upgradeLevel==3)
    assert(Upgrades.purchase(state,guest,trip,world,intent(1)))
    check('commute_guest_upgrade_changes_only_assigned_resident_bike',state.home.residents['guest-1'].ridingUpgradeLevel==1
        and trip.participants['guest-1'].rider.bike.upgradeLevel==1 and rider.bike.upgradeLevel==3)
    local spoof={id=3,sceneId='commute',homeResidentId='guest-1'}
    check('commute_upgrade_rejects_wrong_network_slot',not Upgrades.purchase(state,spoof,trip,world,intent(2)))
    local snapshot=assert(Schema.snapshot(state));local localState,shared=State.new(),State.new()
    assert(State.applyLocalSave(localState,{state=snapshot,slot=3}));assert(State.applySharedSnapshot(shared,snapshot))
    check('commute_upgrades_survive_save_and_host_shared_snapshot',localState.home.residents.owner.ridingUpgradeLevel==3
        and shared.home.residents['guest-1'].ridingUpgradeLevel==1
        and snapshot.home.commute.participants.owner.rider.bike.upgradeLevel==3)
    local restored=assert(Trip.restore(snapshot.home.commute,world))
    check('commute_upgraded_trip_restores_safe_contact',restored.participants.owner.rider.bike.upgradeLevel==3
        and restored.participants.owner.rider.bike.grounded and restored.participants.owner.rider.bike.vy==0)
    localState.home.commute=nil
    assert(Trip.start(localState,{host,guest},7,world))
    check('commute_next_trip_uses_saved_resident_upgrade',localState.home.commute.participants.owner.rider.bike.upgradeLevel==3
        and localState.home.commute.participants['guest-1'].rider.bike.upgradeLevel==1)
    local invalid=Schema.copy(snapshot);invalid.home.residents.owner.ridingUpgradeLevel=4
    check('commute_invalid_resident_upgrade_rejected',not State.applySharedSnapshot(State.new(),invalid))
end
return Test
