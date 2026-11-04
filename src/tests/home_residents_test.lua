local Residents=require("src.home_residents")
local State=require("src.state")
local Schema=require("src.save_schema")
local Calendar=require("src.business_calendar")
local Layout=require("src.home_layouts")
local Test={}
local function home()
    local s=State.new();s.home.weekend.phase="home";s.home.weekend.closedAtHours=44
    s.calendar=Calendar.dateFromHours(44)
    s.calendar.elapsed=20/24*s.calendar.secondsPerDay
    local x,y=Layout.spawn(s,1)
    return s,{id=1,x=x,y=y,sceneId="home"}
end
local function fixture(s,p,id) p.x,p.y=Layout.toWorld(unpack(Layout.get(s).fixtures[id].approach)) end
function Test.run(context,check)
    local s,host=home();local guest={id=2,name="Guest",sceneId="home",x=host.x,y=host.y}
    local token=string.rep("a",64);local id=assert(Residents.bind(s,guest,token,{host}))
    local encoded=assert(require("src.net.codec").encode(assert(Schema.snapshot(s)),{maxBytes=1000000,maxEntries=20000,maxDepth=32,maxStringBytes=4096}))
    check("home_resident_private_token_not_in_shared_save",id~=token and not encoded:find(token,1,true))
    local g=s.home.residents[id];g.hunger=32
    local reconnect={id=4,name="Changed name",sceneId="home",x=host.x,y=host.y}
    check("home_resident_reconnect_keeps_needs_across_slot_and_name",Residents.bind(s,reconnect,token,{host})==id
        and Residents.get(s,reconnect).hunger==32)
    check("home_resident_cannot_connect_same_identity_twice",not Residents.bind(s,reconnect,token,{host,guest}))
    local other={id=2,name="Guest",sceneId="home",x=host.x,y=host.y}
    local otherId=assert(Residents.bind(s,other,string.rep("b",64),{host}))
    check("home_resident_reused_slot_and_name_do_not_inherit_needs",otherId~=id and Residents.get(s,other).hunger==100)
    check("home_resident_public_digest_is_not_authentication",Residents.bind(s,reconnect,g.credentialHash,{host})~=id)
    Residents.advance(s,{host,guest},44,46)
    check("home_resident_individual_needs_and_absent_freeze",s.home.residents.owner.thirst==92
        and g.hunger==27 and s.home.residents[otherId].hunger==100)
    assert(context.save.save(3,s,{x=host.x,y=host.y,sceneId="home"}))
    local resumed=State.new();assert(State.applyLocalSave(resumed,assert(context.save.load(3))))
    Residents.recover(resumed)
    check("home_resident_rejoins_same_identity_after_host_reload",Residents.bind(resumed,reconnect,token,{host})==id
        and Residents.get(resumed,reconnect).hunger==27)
    for _,layout in ipairs(require("src.home_catalog").ORDER) do
        local scene,p=home();scene.home.apartmentId=layout;fixture(scene,p,"sink")
        local person=scene.home.residents.owner;person.thirst=10
        assert(Residents.command(scene,p,"drink:sink"))
        Residents.advance(scene,{p},44,44+2/60)
        check("home_resident_drink_works_"..layout,person.thirst>84 and not person.activity)
    end
    local busy,p=home();fixture(busy,p,"bath");busy.home.residents.owner.hygiene=10
    local q={id=2,name="Guest",sceneId="home",x=p.x,y=p.y};Residents.bind(busy,q,token,{p})
    assert(Residents.command(busy,p,"bathe:bath"))
    check("home_resident_fixture_lock_rejects_second_user",not Residents.command(busy,q,"bathe:bath"))
    Residents.advance(busy,{q},44,44+.1)
    check("home_resident_disconnect_releases_fixture_and_freezes_need",not busy.home.residents.owner.activity
        and busy.home.residents.owner.hygiene==10 and Residents.command(busy,q,"bathe:bath"))
    q.x=q.x+20;Residents.advance(busy,{q},44+.1,44+.2)
    check("home_resident_walking_away_releases_fixture",not Residents.get(busy,q).activity)
    check("home_resident_rejects_remote_fixture",not Residents.command(busy,q,"drink:sink"))
    local meal,eater=home();meal.home.inventory.basic_meal=1;meal.home.residents.owner.hunger=10
    assert(Residents.command(meal,eater,"eat:floor"))
    check("home_resident_food_consumed_once_at_start",meal.home.inventory.basic_meal==0
        and not Residents.command(meal,eater,"eat:floor"))
    Residents.advance(meal,{eater},44,44+.25)
    check("home_resident_eating_restores_hunger",meal.home.residents.owner.hunger>74 and not meal.home.residents.owner.activity)
    check("home_resident_empty_start_has_no_free_food",not Residents.command(meal,eater,"eat:floor"))
    meal.home.residents.owner.energy=0;assert(Residents.command(meal,eater,"rest:floor"))
    Residents.advance(meal,{eater},44,45)
    check("home_resident_floor_rest_is_available_without_bed",meal.home.residents.owner.energy>19 and not eater.resting)
    local one,a=home();local many,b=home();one.home.residents.owner.energy=5;many.home.residents.owner.energy=5
    assert(Residents.command(one,a,"rest:floor"));assert(Residents.command(many,b,"rest:floor"))
    Residents.advance(one,{a},44,46)
    for i=1,120 do Residents.advance(many,{b},44+(i-1)/60,44+i/60) end
    check("home_resident_large_step_matches_small_action_steps",math.abs(one.home.residents.owner.energy-many.home.residents.owner.energy)<1e-7)
    local owner=one.home.residents.owner;owner.energy=0;owner.hunger=0;owner.thirst=0
    check("home_resident_penalty_is_capped",Residents.speedScale(one,a)==.75)
    one.home.weekend.phase="working";one.home.weekend.closedAtHours=nil
    Residents.advance(one,{a},46,47)
    check("home_resident_workweek_does_not_reset_needs",owner.energy==0 and owner.hunger==0 and owner.thirst==0)
    local weekday=State.new();local working={id=1,sceneId="warehouse"};local wear=weekday.home.residents.owner
    Residents.advance(weekday,{working},0,20)
    check("home_resident_workweek_wear_is_persistent",wear.hunger<100 and wear.thirst<100
        and wear.hygiene<100 and wear.energy<100 and not wear.dirtyClothes)
    Residents.advance(weekday,{working},20,44)
    local longWeek=State.new();local longWorker={id=1,sceneId="warehouse"}
    Residents.advance(longWeek,{longWorker},0,90)
    check("home_resident_long_workweek_soils_clothes",longWeek.home.residents.owner.dirtyClothes
        and longWeek.home.residents.owner.hunger<50 and longWeek.home.residents.owner.energy<30)
    local firstWeek={wear.hunger,wear.thirst,wear.hygiene,wear.energy}
    Residents.advance(weekday,{working},44,44)
    check("home_resident_zero_step_keeps_workweek_needs",wear.hunger==firstWeek[1]
        and wear.thirst==firstWeek[2] and wear.hygiene==firstWeek[3] and wear.energy==firstWeek[4])
    weekday.calendar=Calendar.dateFromHours(44);weekday.calendar.elapsed=20/24*weekday.calendar.secondsPerDay
    local Flow=require("src.weekend_flow")
    assert(Flow.update(weekday,false));assert(Flow.update(weekday,true))
    assert(Flow.depart(weekday,weekday.home.revision));working.sceneId="home"
    check("home_resident_friday_arrival_is_exhausted",wear.hunger<=30 and wear.thirst<=25
        and wear.hygiene<=18 and wear.energy<=12 and wear.dirtyClothes)
    fixture(weekday,working,"bath")
    assert(Residents.command(weekday,working,"bathe:bath"))
    Residents.advance(weekday,{working},44,44+20/60)
    check("home_resident_shower_does_not_clean_worn_clothes",wear.hygiene>90 and wear.dirtyClothes)
    local friday=Schema.snapshot(weekday)
    check("home_resident_friday_needs_and_clothes_are_shareable",Schema.validState(friday)
        and friday.home.residents.owner.dirtyClothes and friday.home.residents.owner.energy==wear.energy)
    local replay=State.new();assert(State.applySharedSnapshot(replay,friday))
    check("home_resident_friday_condition_survives_snapshot",replay.home.residents.owner.dirtyClothes
        and replay.home.residents.owner.hunger==wear.hunger and replay.home.residents.owner.energy==wear.energy)
    weekday.calendar=Calendar.dateFromHours(107);weekday.calendar.elapsed=11/24*weekday.calendar.secondsPerDay
    assert(Flow.returnToWork(weekday,weekday.home.revision));working.sceneId="warehouse"
    local mondayEnergy=wear.energy
    Residents.advance(weekday,{working},107,108)
    check("home_resident_monday_shop_retains_weekend_condition",wear.energy<mondayEnergy
        and wear.energy<20 and wear.dirtyClothes)
    local oldResident=Schema.copy(friday);oldResident.home.residents.owner.dirtyClothes=nil
    local normalized=State.new();assert(State.applySharedSnapshot(normalized,oldResident))
    check("home_resident_prior_save_gets_clean_clothing_default",normalized.home.residents.owner.dirtyClothes==false)
    local saving,sp=home();saving.home.residents.owner.energy=12;assert(Residents.command(saving,sp,"rest:floor"))
    assert(context.save.save(3,saving,{x=sp.x,y=sp.y,sceneId="home"}))
    local loaded=assert(context.save.load(3));local restored=State.new();assert(State.applyLocalSave(restored,loaded))
    Residents.recover(restored)
    check("home_resident_reload_keeps_needs_and_releases_action",restored.home.residents.owner.energy==12
        and not restored.home.residents.owner.activity)
    local invalid=Schema.copy(saving);invalid.home.residents.owner.energy=0/0
    check("home_resident_invalid_needs_rejected",not Schema.validState(invalid))
    invalid=Schema.copy(saving);invalid.home.residents.owner.activity.endsAt=999
    check("home_resident_invalid_activity_rejected",not Schema.validState(invalid))
    local legacy=Schema.copy(loaded);legacy.version=27;legacy.state.home.residents=nil
    local migrated=assert(Schema.migrate(legacy));Residents.recover(migrated.state)
    check("home_resident_legacy_gets_owner_once",migrated.version==39 and migrated.state.home.residents.owner.energy==100)
    assert(context.save.delete(3))
    local private=assert(require("src.resident_credentials").get())
    check("home_resident_local_credential_persists",require("src.resident_credentials").get()==private)
end
return Test
