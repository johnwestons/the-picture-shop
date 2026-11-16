local Medical=require('src.player_medical')
local Residents=require('src.home_residents')
local State=require('src.state')
local Schema=require('src.save_schema')
local C=require('src.commute.runtime')
local Runtime=require('src.medical_runtime')
local Test={}
local function deprived(r) r.hunger=0;r.thirst=0;r.energy=0;r.hygiene=0 end
local function capture(R,name)
    local path=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE');if not path then return end
    local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
    love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true});R.App.draw();love.graphics.pop()
    local data=canvas:newImageData();local bytes=data:encode('png')
    local f=assert(io.open(path..'/'..name..'.png','wb'));f:write(bytes:getString());f:close()
    bytes:release();data:release();canvas:release()
end
function Test.run(context,check)
    local s=State.new();local p={id=1,sceneId='warehouse'}
    local r=Residents.get(s,p);local m=Medical.ensure(r)
    check('medical_legacy_optional_and_new_valid',Medical.valid(nil) and Medical.valid(m))
    r.hygiene=0
    check('medical_hygiene_alone_does_not_cause_faint',not Medical.advance(r,12) and not m.phase)
    deprived(r)
    check('medical_critical_needs_have_grace',not Medical.advance(r,.1) and not m.phase)
    check('medical_first_faint_stops_walking',Medical.advance(r,.2) and m.phase=='faint' and Medical.speed(s,p)==0)
    check('medical_faint_blocks_household_actions',not Residents.command(s,p,'rest:floor'))
    Medical.recover(r,'faint')
    check('medical_minor_faint_does_not_refill_needs',r.thirst==0 and m.notice=='faint')
    m.notice=nil;Medical.advance(r,1);check('medical_second_episode_remains_minor',m.phase=='faint')
    Medical.recover(r,'faint');m.notice=nil;Medical.advance(r,1)
    check('medical_third_episode_grandpa_rescue',m.phase=='rescue')
    Medical.recover(r,'rescue')
    check('medical_grandpa_gives_recovery_and_advice',r.thirst==55 and m.notice=='grandpa' and m.episodes==3)
    m.notice=nil;deprived(r);Medical.advance(r,1);s.home.balanceCents=5000;Medical.bill(s,r)
    check('medical_first_hospital_200_and_cannot_be_blocked_by_poverty',m.phase=='hospital'
        and m.lastBillCents==20000 and m.debtCents==15000 and s.home.balanceCents==0)
    local saved=assert(Schema.snapshot(s));local restored=State.new();assert(State.applyLocalSave(restored,{state=saved}))
    check('medical_active_episode_bill_and_debt_survive_snapshot',restored.home.residents.owner.medical.phase=='hospital'
        and restored.home.residents.owner.medical.hospitalVisits==1 and restored.home.residents.owner.medical.debtCents==15000)
    Medical.recover(r,'hospital');m.notice=nil;deprived(r);Medical.advance(r,1);Medical.bill(s,r)
    check('medical_repeat_hospital_adds_200',m.hospitalVisits==2 and m.lastBillCents==40000 and m.debtCents==55000)
    Medical.recover(r,'hospital');m.notice=nil;Medical.advance(r,12)
    check('medical_sustained_recovery_resets_warning_escalation_not_bills',m.episodes==0 and m.hospitalVisits==2)
    check('medical_first_ejection_is_warning',not Medical.crash(r,20) and Medical.speed(s,p)==1)
    check('medical_second_ejection_injures_and_halves_speed',Medical.crash(r,21) and Medical.speed(s,p)==.5
        and Residents.speedScale(s,p)==.5)
    local bad=Schema.copy(m);bad.injury=0/0
    check('medical_rejects_corrupt_health',not Medical.valid(bad))
    local guest={id=2,sceneId='warehouse'};local key=assert(Residents.bind(s,guest,string.rep('a',64),{p}))
    check('medical_injury_is_per_resident',Medical.speed(s,guest)==1 and s.home.residents[key].medical.injury==0)
    local waiting=Schema.copy(r);waiting.medical=Medical.new();deprived(waiting)
    check('medical_vehicle_defers_episode_but_accumulates_strain',not Medical.advance(waiting,3,false)
        and not waiting.medical.phase and waiting.medical.exposure>=Medical.EXPOSURE_HOURS
        and waiting.medical.episodes==0)
    check('medical_pending_faint_starts_immediately_on_foot',Medical.advance(waiting,0,true)
        and waiting.medical.phase=='faint')

    local R=assert(context.appRuntime)
    local Pockets=require('src.player_pockets')
    local week=State.new();local worker={id=1,sceneId='warehouse',x=400,y=400}
    local person=Residents.get(week,worker);local collapsed=false
    week.home.inventory.sandwich=20;week.home.inventory.bottled_drink=20
    for day=0,4 do
        worker.sceneId='home'
        assert(Residents.command(week,worker,'pocket:pack:sandwich:'..Pockets.ensure(person).revision))
        assert(Residents.command(week,worker,'pocket:pack:bottled_drink:'..person.pockets.revision))
        worker.sceneId='warehouse'
        for hour=1,16 do
            Residents.advance(week,{worker},day*24+hour-1,day*24+hour)
            if hour==8 then
                assert(Residents.command(week,worker,'pocket:use:sandwich:'..person.pockets.revision))
                assert(Residents.command(week,worker,'pocket:use:bottled_drink:'..person.pockets.revision))
            end
            collapsed=Medical.advance(person,1,true) or collapsed
        end
        person.energy=100 -- nightly sleep; this scenario isolates workday deprivation.
    end
    check('medical_normal_five_day_workweek_with_pocket_lunch_has_no_faints',not collapsed and Medical.ensure(person).episodes==0)
    local snapshot=assert(Schema.snapshot(week))
    check('medical_pockets_persist_in_valid_save',snapshot.home.residents.owner.pockets.revision==person.pockets.revision)
    local neglected=State.new();local nr=Residents.get(neglected,worker)
    for hour=1,72 do
        Residents.advance(neglected,{worker},hour-1,hour)
        assert(not Medical.advance(nr,1,true))
    end
    check('medical_first_three_days_do_not_trigger_deprivation_faint',Medical.ensure(nr).episodes==0)
    assert(R.Save.delete(3));assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden'})),'smoke'))
    R.state.screen='world';R.state.employment.recruiting=false
    local player=R.World.player;local world=C.world(R)
    r=Residents.get(R.state,player);m=Medical.ensure(r)
    r.pockets={revision=0,items={sandwich=1,bottled_drink=1}}
    r.hunger=10;r.thirst=10
    check('medical_pocket_touch_opens_menu',R.menuAccessPointer(850,410,1) and R.state.screen=='home_activity')
    R.App.draw()
    R.App.keypressed('1')
    check('medical_pocket_menu_drinks_at_work',r.thirst==85 and r.pockets.items.bottled_drink==nil)
    R.App.keypressed('1')
    check('medical_pocket_menu_eats_at_work',r.hunger==50 and next(r.pockets.items)==nil)
    R.App.keypressed('escape')
    check('medical_pocket_menu_returns_to_work',R.state.screen=='world')
    check('medical_world_has_clinic_with_road_access',world.sites.byId.clinic~=nil and world.roads.destinations.clinic~=nil)
    check('medical_world_has_rescue_farm',world.sites.byId.farm~=nil)
    deprived(r);m.exposure=Medical.EXPOSURE_HOURS;R.App.update(.05)
    check('medical_runtime_starts_faint_in_warehouse',m.phase=='faint' and player.medicalCollapsed)
    capture(R,'medical-faint')
    for i=1,5 do Runtime.update(R,1,0) end
    check('medical_runtime_recovers_without_teleport',not m.phase and player.sceneId=='warehouse')
    m.notice=nil;m.episodes=2;r.ridingDamage=43;deprived(r);Runtime.update(R,0,1)
    for i=1,5 do Runtime.update(R,1,0) end
    check('medical_runtime_rescue_enters_barn',not m.phase and m.notice=='grandpa' and player.sceneId=='barn'
        and C.localPart(R).interior=='barn')
    check('medical_grandpa_present_for_rescue',require('src.story_intro').grandpaPresent(R))
    check('medical_barn_rescue_snapshot_valid',Schema.snapshot(R.state)~=nil)
    check('medical_rescue_preserves_bike_damage',C.localPart(R).rider.bike.damage==43 and r.ridingDamage==43)
    R.App.update(0)
    capture(R,'medical-grandpa')
    require('src.medical_ui').key(R,'return')
    check('medical_dialogue_can_be_dismissed',not m.notice)
    deprived(r);R.state.home.balanceCents=100000;Runtime.update(R,0,1)
    check('medical_runtime_hospital_charges_once',m.phase=='hospital' and m.hospitalVisits==1 and R.state.home.balanceCents==80000)
    Runtime.update(R,1,0);capture(R,'medical-ambulance')
    for i=1,4 do Runtime.update(R,1,0) end
    capture(R,'medical-hospital')
    for i=1,2 do Runtime.update(R,1,0) end
    capture(R,'medical-return')
    assert(R.Save.save(3,R.state,R.World.snapshot()))
    local payload=assert(R.Save.load(3));assert(R.startGame(payload,'smoke'));R.state.screen='world'
    player=R.World.player;r=Residents.get(R.state,player);m=Medical.ensure(r)
    for i=1,10 do Runtime.update(R,1,0) end
    check('medical_reload_finishes_hospital_without_double_bill',not m.phase and m.hospitalVisits==1
        and R.state.home.balanceCents==80000 and player.sceneId=='home' and m.notice=='hospital')
    check('medical_discharge_restores_health',r.energy>=75 and r.thirst>=75 and m.injury==0)
    capture(R,'medical-discharge')
    check('medical_discharge_snapshot_valid',Schema.snapshot(R.state)~=nil)
    m.notice=nil;world=C.world(R)
    assert(require('src.commute.free_travel').enter(R.state,player,world,nil,{player}))
    local part=C.localPart(R);C.syncPlayer(player,part)
    Medical.crash(r,30);Medical.crash(r,31)
    local before=R.state.home.balanceCents
    check('medical_remote_clinic_rejected_without_charge',not Medical.treat(R.state,player,m.revision,world)
        and R.state.home.balanceCents==before)
    local site=world.sites.byId.clinic;part.rider.ped.x,part.rider.ped.z=site.door.x,site.door.z
    part.rider.ped.h=world:supportHeight(site.door.x,site.door.z)
    part.rider.gear.mounted=true
    check('medical_mounted_clinic_rejected',not Medical.treat(R.state,player,m.revision,world))
    part.rider.gear.mounted=false
    require('src.commute.tests.loading_test_support').wait(R,check,'medical_clinic_loading')
    capture(R,'medical-clinic-exterior')
    check('medical_clinic_opens_on_foot',require('src.medical_ui').openClinic(R))
    require('src.medical_ui').pointer(R,480,500,2)
    check('medical_right_click_does_not_buy_care',R._medicalClinic~=nil and R.state.home.balanceCents==before)
    capture(R,'medical-clinic')
    local price=Medical.quote(r);local revision=m.revision
    R.state.home.balanceCents=price-1
    check('medical_insufficient_clinic_money_preserves_health',not Medical.treat(R.state,player,revision,world) and m.injury==35)
    R.state.home.balanceCents=before
    local okay=C.command(R,player,('clinic:%d:%d:%d'):format(R.state.home.commute.token,revision,price))
    check('medical_clinic_command_charges_and_heals',okay and Medical.speed(R.state,player)==1 and r.thirst==100
        and R.state.home.balanceCents==before-price and m.injury==0)
    check('medical_duplicate_clinic_payment_rejected',not Medical.treat(R.state,player,revision,world)
        and R.state.home.balanceCents==before-price)
    check('medical_forged_or_stale_clinic_price_rejected',not Medical.treat(R.state,player,m.revision,world,1))
    check('medical_final_save_valid',Schema.snapshot(R.state)~=nil)
    R._medicalClinic=nil
    -- All escalation stages defer without stopping or ejecting the driver.
    for _,episodes in ipairs({0,2,3}) do
        m.episodes=episodes;m.exposure=0;m.phase=nil;m.notice=nil;deprived(r)
        part.rider.gear.outfit='geared';part.rider.gear.mounted=true;part.rider.bike.speed=8
        local cash,visits=R.state.home.balanceCents,m.hospitalVisits
        Runtime.update(R,1,2)
        check('medical_motorcycle_defers_stage_'..episodes,not m.phase and m.episodes==episodes
            and part.rider.gear.mounted and part.rider.bike.speed==8 and m.hospitalVisits==visits
            and R.state.home.balanceCents==cash)
        part.rider.gear.mounted=false;part.rider.vehicle='truck'
        Runtime.update(R,1,1)
        check('medical_truck_defers_stage_'..episodes,not m.phase and m.hospitalVisits==visits)
        part.rider.vehicle=nil
        part.rider.gear.transition={kind='dismount',elapsed=0}
        Runtime.update(R,1,0)
        check('medical_dismount_animation_defers_stage_'..episodes,not m.phase)
        part.rider.gear.transition=nil
        local lift=R.state.forklift;lift.operating=true;lift.operatorPlayerId=player.id or 1
        Runtime.update(R,1,1)
        check('medical_forklift_defers_stage_'..episodes,not m.phase and lift.operating)
        lift.operating=false;lift.operatorPlayerId=nil
        Runtime.update(R,0,0)
        check('medical_on_foot_releases_pending_stage_'..episodes,m.phase==(episodes==0 and 'faint'
            or episodes==2 and 'rescue' or 'hospital'))
        Medical.recover(r,m.phase);player._medicalStopped=nil
    end
    m.notice=nil
    -- The actual crash transition, rather than a collision count or button,
    -- reports injuries. One fall must never be counted every simulation frame.
    m.injury=0;m.crashCount=0
    local Bike=require('src.commute.motorcycle');local oldUpdate=Bike.update
    Bike.update=function(bike)
        bike.crashPending={nx=1,nz=0,dx=0,dz=1,severity=1};return 0
    end
    local okay,reason=xpcall(function()
        for n=1,2 do
            part.rider.gear.mounted=true;part.rider.gear.engine=true;part.rider.gear.outfit='geared'
            part.rider.ped.crash=nil
            require('src.commute.trip').update(R.state,player,{},.1,world)
            require('src.commute.trip').update(R.state,player,{},.1,world)
            check('medical_actual_ejection_count_'..n,m.crashCount==n)
        end
        check('medical_actual_repeated_ejection_injures',m.injury==35 and Medical.speed(R.state,player)==.5)
    end,debug.traceback)
    Bike.update=oldUpdate;if not okay then error(reason) end
    part.rider.ped.crash=nil
    -- Run the real dismount animation before allowing a pending collapse.
    m.injury=0;m.crashCount=0;m.episodes=0;m.exposure=0;m.notice=nil;deprived(r)
    part.rider.bike.speed=0;Bike.resetHorizontal(part.rider.bike)
    part.rider.gear.mounted=true;part.rider.gear.engine=false;part.rider.gear.transition=nil
    Runtime.update(R,0,1)
    assert(C.command(R,player,'dismount:'..R.state.home.commute.token))
    for i=1,8 do
        require('src.commute.trip').update(R.state,player,{},.05,world);Runtime.update(R,0,0)
        if part.rider.gear.transition then check('medical_real_dismount_no_mid_animation_faint_'..i,not m.phase) end
    end
    for i=1,100 do
        if not part.rider.gear.transition then break end
        require('src.commute.trip').update(R.state,player,{},.05,world)
    end
    Runtime.update(R,0,0)
    check('medical_real_dismount_releases_faint',not part.rider.gear.mounted and m.phase=='faint')
    Medical.recover(r,'faint');m.notice=nil;player._medicalStopped=nil
    -- A guest's emergency must leave the owner and other vehicles in place.
    for _,need in ipairs(Residents.NEEDS) do r[need]=100 end
    local remote=Schema.copy(player);remote.id=2;remote.sceneId='warehouse';remote.x=400;remote.y=500
    local remoteId=assert(Residents.bind(R.state,remote,string.rep('b',64),{player}))
    local remoteResident=Residents.get(R.state,remote);local remoteMedical=Medical.ensure(remoteResident)
    deprived(remoteResident);remoteMedical.episodes=3
    local oldPlayers=R.multiplayer.remotePlayers;local ownerPart=C.localPart(R)
    R.multiplayer.remotePlayers=function()return {remote}end
    local success,detail=xpcall(function()
        local cash=R.state.home.balanceCents
        Runtime.update(R,0,1)
        check('medical_guest_emergency_is_independent',remoteMedical.phase=='hospital' and not m.phase
            and R.state.home.balanceCents==cash-20000 and C.localPart(R)==ownerPart)
        for i=1,9 do Runtime.update(R,1,0) end
        check('medical_guest_discharge_does_not_teleport_host',remote.sceneId=='home' and player.sceneId=='commute'
            and C.localPart(R)==ownerPart and remoteMedical.notice=='hospital')
        check('medical_guest_snapshot_valid',Schema.snapshot(R.state)~=nil)
    end,debug.traceback)
    R.multiplayer.remotePlayers=oldPlayers;if not success then error(detail) end
end
return Test
