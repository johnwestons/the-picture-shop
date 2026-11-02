local State=require("src.state")
local Home=require("src.home")
local Calendar=require("src.business_calendar")
local Residents=require("src.home_residents")
local Sleep=require("src.home_sleep")
local Layout=require("src.home_layouts")
local Schema=require("src.save_schema")
local Test={}
local function time(s,h) s.calendar=Calendar.dateFromHours(h);s.calendar.elapsed=h%24/24*Calendar.secondsPerDay(s) end
local function fresh(hours)
    local s=State.new();s.home=Home.new({furnishingPreset="modest"});s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;time(s,hours or 95)
    local x,y=Layout.spawn(s,1);return s,{id=1,sceneId="home",x=x,y=y}
end
local function advance(s,players,h)
    local first=Calendar.absoluteHours(s);Residents.advance(s,players,first,first+h);time(s,first+h)
end
function Test.run(context,check)
    local s,p=fresh();local r=s.home.residents.owner;r.energy=0
    assert(Residents.command(s,p,"sleepfloor:floor"))
    check("home_sleep_solo_opt_in_accelerates",Sleep.status(s,{p}) and p.resting)
    local dt,fast=Sleep.calendarStep(s,{p},.1)
    check("home_sleep_acceleration_bounded_to_five_game_minutes",fast and dt>.1 and dt<=Calendar.secondsPerDay(s)/288)
    local g={id=2,sceneId="home",x=p.x+30,y=p.y};assert(Residents.bind(s,g,string.rep("b",64),{p}))
    check("home_sleep_new_awake_guest_interrupts_acceleration",not Sleep.status(s,{p,g}) and Sleep.calendarStep(s,{p,g},.1)==.1)
    assert(Residents.command(s,g,"sleepfloor:floor"));check("home_sleep_all_connected_opt_in_accelerates",Sleep.status(s,{p,g}))
    assert(Residents.command(s,g,"cancel"));check("home_sleep_guest_can_stop_shared_acceleration",not Sleep.status(s,{p,g}) and r.activity~=nil)
    check("home_sleep_absent_residents_do_not_vote",Sleep.status(s,{p}))
    local before=s.home.residents[g.homeResidentId].energy;advance(s,{p},1)
    check("home_sleep_absent_needs_freeze",s.home.residents[g.homeResidentId].energy==before and r.energy>19 and r.energy<20)
    assert(Residents.command(s,p,"alarm:7"));check("home_sleep_personal_alarm_absolute_time",r.alarmAt==103 and Schema.validState(Schema.snapshot(s)))
    assert(context.save.save(3,s,{x=p.x,y=p.y,sceneId="home"}))
    local reloaded=State.new();assert(State.applyLocalSave(reloaded,assert(context.save.load(3))));Residents.recover(reloaded)
    check("home_sleep_reload_keeps_alarm_releases_sleep_vote",reloaded.home.residents.owner.alarmAt==103 and not reloaded.home.residents.owner.activity and not Sleep.status(reloaded,{p}))
    local shared=State.new();assert(State.applySharedSnapshot(shared,Schema.snapshot(s)))
    check("home_sleep_shared_snapshot_keeps_vote_and_alarm",shared.home.residents.owner.activity.kind=="sleepfloor" and shared.home.residents.owner.alarmAt==103)
    time(s,102.99);dt=Sleep.calendarStep(s,{p},100)
    check("home_sleep_step_stops_exactly_at_monday_wake",math.abs(dt-Calendar.secondsPerDay(s)/24*.01)<1e-7)
    advance(s,{p},.01)
    check("home_sleep_monday_alarm_wakes_once",not r.activity and not r.alarmAt and r.lastAlarmAt==103 and not p.resting)
    local rev=r.revision;advance(s,{p},0)
    check("home_sleep_repeated_wake_does_not_refire",r.revision==rev and not Sleep.status(s,{p}) and not Residents.command(s,p,"sleepfloor:floor"))
    assert(Residents.command(s,p,"alarm:7"));check("home_sleep_next_alarm_rolls_forward",r.alarmAt==127)
    assert(Residents.command(s,p,"alarm:off"));check("home_sleep_alarm_off_is_personal",not r.alarmAt)
    check("home_sleep_rejects_bad_alarm_commands",not Residents.validCommand("alarm:24") and not Residents.validCommand("alarm:07") and not Residents.validCommand("alarm:-1"))
    local bad=Schema.copy(s.home);bad.residents.owner.alarmAt=0/0;check("home_sleep_rejects_invalid_saved_alarm",not Home.valid(bad))
    local a,pa=fresh(71);local b,pb=fresh(71)
    for _,v in ipairs({{a,pa},{b,pb}}) do
        v[1].home.residents.owner.energy=0;assert(Residents.command(v[1],v[2],"alarm:0"));assert(Residents.command(v[1],v[2],"sleepfloor:floor"))
    end
    advance(a,{pa},3);for _=1,180 do advance(b,{pb},1/60) end
    check("home_sleep_alarm_reward_large_step_matches_small",not a.home.residents.owner.activity and not b.home.residents.owner.activity
        and math.abs(a.home.residents.owner.energy-b.home.residents.owner.energy)<1e-7 and a.home.residents.owner.energy>13)
    local c,pc=fresh(72);local bed=c.home.furniture.items[1];local target=require("src.home_furniture").targets(c,pc)["furniture"..bed.id]
    pc.x,pc.y=target.x,target.y;c.home.residents.owner.energy=0;assert(Residents.command(c,pc,"sleepbed:furniture"..bed.id));advance(c,{pc},1)
    check("home_sleep_bed_comfort_beats_floor",c.home.residents.owner.energy>60 and Schema.validState(Schema.snapshot(c)))
    local newcomer={id=2,sceneId="home",x=pc.x+60,y=pc.y};assert(Residents.bind(c,newcomer,string.rep("c",64),{pc}));assert(Residents.command(c,newcomer,"sleepfloor:floor"))
    local reconnect={id=3,sceneId="home",x=newcomer.x,y=newcomer.y};assert(Residents.bind(c,reconnect,string.rep("c",64),{pc}))
    check("home_sleep_reconnect_cannot_inherit_vote",not Residents.get(c,reconnect).activity and not Sleep.status(c,{pc,reconnect}))
    pc.x=pc.x+25;check("home_sleep_movement_immediately_disables_fast_time",not Sleep.status(c,{pc}));advance(c,{pc},0)
    check("home_sleep_movement_releases_occupied_bed",not c.home.residents.owner.activity)
    local readiness=Sleep.readiness(c,{pc,reconnect})
    check("home_sleep_readiness_includes_connected_residents",#readiness==2 and readiness[1].energy>60 and readiness[2].ready)
    local sunday,sp=fresh(92)
    assert(Residents.command(sunday,sp,"workfloor:floor"));advance(sunday,{sp},11)
    check("home_sleep_sunday_option_reaches_monday_morning",not sunday.home.residents.owner.activity and Calendar.absoluteHours(sunday)==103)
    sunday,sp=fresh(94);assert(Residents.command(sunday,sp,"workfloor:floor"));advance(sunday,{sp},9)
    check("home_sleep_late_sunday_start_still_stops_at_seven",not sunday.home.residents.owner.activity and Calendar.absoluteHours(sunday)==103)
    sunday,sp=fresh(71);check("home_sleep_workday_skip_is_not_available_all_weekend",not Residents.command(sunday,sp,"workfloor:floor"))
    local migrated=assert(Schema.migrate({version=34,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(State.new()),player={x=300,y=400}}))
    check("home_sleep_legacy_migration_no_invented_alarm",migrated.version==39 and not migrated.state.home.residents.owner.alarmAt)
    local sound=require("src.sound").new({state=s,world={player=p}});local chimes=0
    function sound:play(name) if name=="job_complete" then chimes=chimes+1 end;return true end
    r.alarmAt=127;local beforeSound=sound:capture();r.lastAlarmAt=127;r.alarmAt=nil;local afterSound=sound:capture()
    sound:handleTransitions(beforeSound,afterSound);sound:handleTransitions(afterSound,afterSound)
    check("home_sleep_personal_alarm_chimes_once",chimes==1)
    local working,wp=fresh(103);assert(Residents.command(working,wp,"alarm:9"))
    working.home.weekend.phase="working";working.home.weekend.closedAtHours=nil;wp.sceneId="warehouse"
    advance(working,{wp},2)
    check("home_sleep_personal_alarm_fires_after_return_to_work",working.home.residents.owner.lastAlarmAt==105 and not working.home.residents.owner.alarmAt)
    for _,minutes in ipairs({5,20,60}) do
        local m,mp=fresh(743.5);m.calendar.secondsPerDay=minutes*60;m.calendar.elapsed=23.5/24*m.calendar.secondsPerDay
        m.home.weekend=require("src.weekend_flow").new(743.5);m.home.weekend.phase="home";m.home.weekend.closedAtHours=m.home.weekend.closesAtHours
        local Shopping=require("src.home_shopping")
        assert(Shopping.order(m,mp,{productId="pizza",quantity=1,requestId="sleep-midnight",expectedRevision=m.home.revision}))
        assert(Residents.command(m,mp,"alarm:0"));assert(Residents.command(m,mp,"sleepfloor:floor"))
        local steps=0
        while m.home.residents.owner.activity and steps<1000 do
            local before=Calendar.absoluteHours(m);local step=Sleep.calendarStep(m,{mp},.1)
            Calendar.update(m,step);Residents.advance(m,{mp},before,Calendar.absoluteHours(m));steps=steps+1
        end
        check("home_sleep_midnight_rent_delivery_alarm_"..minutes,math.abs(Calendar.absoluteHours(m)-744)<1e-6 and m.home.lease.invoiceCount==1
            and Shopping.waiting(m)==1 and m.home.residents.owner.lastAlarmAt==744 and steps<1000)
        Calendar.update(m,0);Residents.advance(m,{mp},744,744)
        check("home_sleep_boundary_events_not_repeated_"..minutes,m.home.lease.invoiceCount==1 and Shopping.waiting(m)==1 and m.home.shopping.nextOrderId==2)
    end
end
return Test
