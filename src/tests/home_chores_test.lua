local State=require("src.state")
local Home=require("src.home")
local Calendar=require("src.business_calendar")
local Chores=require("src.home_chores")
local Residents=require("src.home_residents")
local Layout=require("src.home_layouts")
local Schema=require("src.save_schema")
local Test={}
local function time(state,hours)
    state.calendar=Calendar.dateFromHours(hours);state.calendar.elapsed=hours%24/24*Calendar.secondsPerDay(state)
end
local function fixture(state,p,id) p.x,p.y=Layout.toWorld(unpack(Layout.get(state).fixtures[id].approach)) end
local function fresh()
    local s=State.new();s.home=Home.new();s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;time(s,44)
    local p={id=1,sceneId="home"};fixture(s,p,"laundry");Residents.advance(s,{p},44,44)
    return s,p
end
local function advance(s,people,minutes)
    local first=Calendar.absoluteHours(s);local last=first+minutes/60
    Residents.advance(s,people,first,last);time(s,last)
end
function Test.run(context,check)
    local s,p=fresh();local c=s.home.chores;local l=c.laundry
    check("home_chores_first_visit_has_one_work_bundle",l.dirty==1 and l.clean==0 and l.phase=="idle")
    local revision=s.home.revision
    Residents.advance(s,{p},44,44);Residents.advance(s,{p},44,44)
    check("home_chores_repeated_zero_step_no_extra_laundry",l.dirty==1 and s.home.revision==revision)
    local g={id=2,sceneId="home",x=p.x,y=p.y};assert(Residents.bind(s,g,string.rep("c",64),{p}))
    Residents.advance(s,{p,g},44,44);local people={p,g}
    check("home_chores_guest_contributes_once",l.dirty==2)
    local reconnect={id=3,sceneId="home",x=p.x,y=p.y};assert(Residents.bind(s,reconnect,string.rep("c",64),{p}))
    Residents.advance(s,{p,reconnect},44,44)
    check("home_chores_reconnect_does_not_mint_laundry",l.dirty==2)
    local joined,jp=fresh();local jg={id=2,sceneId="home",x=jp.x,y=jp.y}
    time(joined,46);assert(Residents.bind(joined,jg,string.rep("d",64),{jp}))
    Chores.advance(joined,{jp,jg},44,47)
    check("home_chores_late_guest_only_adds_present_time_dirt",joined.home.chores.soil.living==2 and joined.home.chores.laundry.dirty==2)
    joined.home.weekend.closesAtHours=212;time(joined,212);Chores.advance(joined,{jp,jg},212,212);Chores.advance(joined,{jp,jg},212,212)
    check("home_chores_next_week_adds_one_bundle_per_resident",joined.home.chores.laundry.dirty==4)
    people={p,reconnect};g=reconnect
    assert(Residents.command(s,p,"loadwash:laundry"))
    check("home_chores_washer_load_exclusive",not Residents.command(s,g,"loadwash:laundry"))
    advance(s,people,2);assert(Residents.command(s,p,"cancel"))
    check("home_chores_cancel_loading_retains_dirty_bundle",l.dirty==2 and l.phase=="idle")
    assert(Residents.command(s,p,"loadwash:laundry"));advance(s,people,5)
    check("home_chores_loading_starts_one_timed_cycle",l.phase=="washing" and l.dirty==1 and l.clean==0 and l.cycle==1
        and math.abs(l.dueAt-l.startedAt-.75)<1e-7 and not s.home.residents.owner.activity)
    check("home_chores_cycle_countdown_does_not_round_up_extra_minute",Chores.minutesLeft(s)==45)
    check("home_chores_cannot_reload_or_unload_running_machine",not Residents.command(s,p,"loadwash:laundry") and not Residents.command(s,p,"unload:laundry"))
    p.x,p.y=Layout.spawn(s,1);assert(Residents.command(s,p,"rest:floor"))
    revision=s.home.revision;advance(s,people,10)
    check("home_chores_machine_runs_without_holding_player",l.phase=="washing" and s.home.residents.owner.activity.kind=="rest" and s.home.revision==revision)
    assert(context.save.save(3,s,{x=p.x,y=p.y,sceneId="home"}))
    local resumed=State.new();assert(State.applyLocalSave(resumed,assert(context.save.load(3))));Residents.recover(resumed)
    check("home_chores_reload_preserves_cycle_without_offline_time",resumed.home.chores.laundry.phase=="washing" and math.abs(resumed.home.chores.laundry.dueAt-l.dueAt)<1e-8
        and resumed.home.chores.laundry.dirty==1 and not resumed.home.residents.owner.activity,
        string.format("phase=%s due=%.17g expected=%.17g dirty=%d activity=%s",resumed.home.chores.laundry.phase,resumed.home.chores.laundry.dueAt or -1,l.dueAt,resumed.home.chores.laundry.dirty,tostring(resumed.home.residents.owner.activity)))
    assert(Residents.command(s,p,"cancel"));advance(s,people,35)
    check("home_chores_cycle_finishes_without_auto_unloading",l.phase=="ready" and l.clean==0 and l.cycle==1)
    fixture(s,p,"laundry");assert(Residents.command(s,p,"unload:laundry"));advance(s,people,5)
    check("home_chores_unload_delivers_exactly_one_clean_bundle",l.phase=="idle" and l.clean==1 and not l.dueAt and not Residents.command(s,p,"unload:laundry"))
    s.home.residents.owner.hygiene=10;assert(Residents.command(s,p,"change:laundry"));advance(s,people,2)
    check("home_chores_fresh_clothes_restore_hygiene_once",l.clean==0 and s.home.residents.owner.hygiene>44 and s.home.residents.owner.hygiene<45
        and not Residents.command(s,p,"change:laundry"))
    local copy=State.new();assert(State.applySharedSnapshot(copy,Schema.snapshot(s)))
    check("home_chores_shared_snapshot_keeps_counts",copy.home.chores.laundry.dirty==1 and copy.home.chores.laundry.clean==0 and copy.home.chores.laundry.cycle==1)
    local a,pa=fresh();local b,pb=fresh();assert(Residents.command(a,pa,"loadwash:laundry"));assert(Residents.command(b,pb,"loadwash:laundry"))
    advance(a,{pa},120);for _=1,120 do advance(b,{pb},1) end
    check("home_chores_large_step_matches_washer_and_floor",a.home.chores.laundry.phase=="ready" and b.home.chores.laundry.phase=="ready"
        and a.home.chores.laundry.cycle==1 and math.abs(a.home.chores.soil.living-b.home.chores.soil.living)<1e-7)
    a,pa=fresh();b,pb=fresh();a.home.chores.soil.living=100;b.home.chores.soil.living=100
    assert(Residents.command(a,pa,"sweep:floor"));assert(Residents.command(b,pb,"sweep:floor"))
    advance(a,{pa},120);for _=1,120 do advance(b,{pb},1) end
    check("home_chores_large_step_preserves_dirt_after_sweeping",a.home.chores.soil.living>60 and math.abs(a.home.chores.soil.living-b.home.chores.soil.living)<1e-7)
    a,pa=fresh();b,pb=fresh();a.home.chores.laundry.clean=1;b.home.chores.laundry.clean=1
    a.home.residents.owner.hygiene=99;b.home.residents.owner.hygiene=99
    assert(Residents.command(a,pa,"change:laundry"));assert(Residents.command(b,pb,"change:laundry"))
    advance(a,{pa},120);for _=1,120 do advance(b,{pb},1) end
    check("home_chores_clothes_reward_applies_before_later_decay",a.home.residents.owner.hygiene<98 and math.abs(a.home.residents.owner.hygiene-b.home.residents.owner.hygiene)<1e-7)
    a,pa=fresh();assert(Residents.command(a,pa,"loadwash:laundry"));advance(a,{pa},5)
    a.home.weekend.phase="working";pa.sceneId="warehouse";local soil=a.home.chores.soil.living;advance(a,{pa},60)
    check("home_chores_running_laundry_finishes_while_away",a.home.chores.laundry.phase=="ready" and a.home.chores.soil.living==soil)
    s.home.inventory.basic_meal=1;assert(Residents.command(s,p,"eat:floor"))
    check("home_chores_meal_creates_used_dish_and_trash_once",c.dishes==1 and c.trash==1 and not Residents.command(s,p,"eat:floor"))
    assert(Residents.command(s,p,"cancel"));check("home_chores_failed_food_does_not_create_dirt",not Residents.command(s,p,"eat:floor") and c.dishes==1)
    fixture(s,p,"sink");c.dishes=6;assert(Residents.command(s,p,"dishes:sink"))
    s.home.inventory.basic_meal=1;g.x,g.y=Layout.spawn(s,1);assert(Residents.command(s,g,"eat:floor"));advance(s,people,5)
    check("home_chores_dish_batch_does_not_wash_new_extra_portions",c.dishes==3 and not s.home.residents.owner.activity)
    assert(Residents.command(s,g,"cancel"));assert(Residents.command(s,p,"dishes:sink"));p.x=p.x-20;advance(s,people,5)
    check("home_chores_moving_cancels_dish_work",c.dishes==3 and not s.home.residents.owner.activity)
    fixture(s,p,"sink");c.soil.kitchen=58;assert(Residents.command(s,p,"wipe:sink"));advance(s,people,5)
    check("home_chores_wiping_removes_saved_kitchen_dirt",c.soil.kitchen==23)
    fixture(s,p,"toilet");assert(Residents.command(s,p,"toilet:toilet"));assert(Residents.command(s,p,"cancel"))
    check("home_chores_bathroom_use_leaves_dirt",c.soil.bathroom==2)
    fixture(s,p,"bath");assert(Residents.command(s,p,"scrub:bath"));advance(s,people,8)
    check("home_chores_bathroom_cleaning_removes_dirt",c.soil.bathroom==0)
    c.trash=10;p.x,p.y=0,0
    check("home_chores_trash_requires_entrance",not Residents.command(s,p,"trash:floor"))
    p.x,p.y=Layout.spawn(s,1);assert(Residents.command(s,p,"trash:floor"))
    g.x,g.y=p.x,p.y;check("home_chores_trash_task_cannot_be_duplicated",not Residents.command(s,g,"trash:floor"))
    advance(s,people,5);check("home_chores_trash_disposal_removes_one_bag_batch",c.trash==2)
    for name,mutate in pairs({negative=function(d)d.laundry.dirty=-1 end,overfill=function(d)d.laundry.clean=65 end,
        bad_phase=function(d)d.laundry.phase="magic" end,bad_soil=function(d)d.soil.living=0/0 end,
        fake_due=function(d)d.laundry.phase="washing";d.laundry.cycle=1;d.laundry.startedAt=44;d.laundry.dueAt=46 end}) do
        local data=Chores.new(44);mutate(data);check("home_chores_invalid_"..name,not Chores.valid(data))
    end
    local old=State.new();old.home.chores=nil
    old.home.residents.owner.activity={kind="laundry",target="laundry",startedAt=0,endsAt=.75,x=300,y=400}
    local migrated=assert(Schema.migrate({version=32,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(old),player={x=300,y=400}}))
    check("home_chores_legacy_laundry_migrates_without_free_clean_clothes",migrated.version==39 and migrated.state.home.chores.laundry.phase=="idle"
        and migrated.state.home.chores.laundry.clean==0 and migrated.state.home.chores.laundry.dirty==0 and not migrated.state.home.residents.owner.activity)
    check("home_chores_legacy_shortcut_no_longer_usable",not Residents.command(s,p,"laundry:laundry"))
end
return Test
