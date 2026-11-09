local Test={}
function Test.run(context,check)
 local Art=require("src.home_laundry_art");local R=require("src.home_laundry_registration")
 local Layout=require("src.home_layouts");local Navigation=require("src.navigation")
 local Fixtures=require("src.tests.home_dining_test");local Residents=require("src.home_residents")
 local Chores=require("src.home_chores");local Calendar=require("src.business_calendar")
 local State=require("src.state");local Schema=require("src.save_schema")
 local function clock(s,h)
  local day=Calendar.secondsPerDay(s);s.calendar=Calendar.dateFromHours(h);s.calendar.secondsPerDay=day;s.calendar.elapsed=h%24/24*day
 end
 local seen={}
 for _,d in ipairs(R.order) do
  local source=R.views[d].sourceIndex
  check("home_laundry_authored_view_"..d,not seen[source] and R.views[d].scale>0);seen[source]=true
  for frame=1,4 do
   local c=Art.contact(d,frame)
   check("home_laundry_registered_"..d..frame,c.valid and R.views[d].sourceIndex>0)
  end
  check("home_laundry_lift_"..d,Art.contact(d,2).y<Art.contact(d,1).y-3)
 end
 for _,day in ipairs({300,1200,3600}) do
  local duration=day/288
  check("home_laundry_load_one_shot_"..day,Art.frame(0,duration,"loadwash")==1 and Art.frame(duration*.3,duration,"loadwash")==2
   and Art.frame(duration*.6,duration,"loadwash")==3 and Art.frame(duration*.9,duration,"loadwash")==4
   and Art.frame(duration*2,duration,"loadwash")==4)
  check("home_laundry_unload_reverse_"..day,Art.frame(0,duration,"unload")==4 and Art.frame(duration*.2,duration,"unload")==3
   and Art.frame(duration*.5,duration,"unload")==2 and Art.frame(duration*.7,duration,"unload")==1
   and Art.frame(duration*.95,duration,"unload")==4)
 end
 check("home_laundry_release_hides_bundle",Art.bundleMode("loadwash",4,.9)==nil)
 check("home_laundry_unload_deposits_bundle",Art.bundleMode("unload",4,.01)==nil and Art.bundleMode("unload",4,.95)=="basket")
 for _,id in ipairs(require("src.home_catalog").ORDER) do
  local s,p=Fixtures.fresh(id);local x,y,d,dx,dy,error=Art.standingPose(s)
  check("home_laundry_fixture_stance_"..id,x~=nil)
  if x then
   check("home_laundry_fixture_feet_"..id,Navigation.isWalkable({getData=function()return Layout.mask(id) end},x,y,require("src.home_furniture").obstacles(s)))
   local c=Art.contact(d,3);local fx,fy=Layout.toWorld(unpack(Layout.get(s).fixtures.laundry.approach))
   check("home_laundry_fixture_reach_"..id,math.sqrt((x+c.x-dx)^2+(y+c.y-dy)^2)<=9.01 and error<=9.01
    and (x-fx)^2+(y-fy)^2<60^2)
   local sx,sy=Layout.toSource(dx,dy);local outline=Layout.get(s).fixtures.laundry.outline
   local inside=false;local last=#outline-1
   for j=1,#outline,2 do
    local ax,ay,bx,by=outline[j],outline[j+1],outline[last],outline[last+1]
    if (ay>sy)~=(by>sy) and sx<(bx-ax)*(sy-ay)/(by-ay)+ax then inside=not inside end;last=j
   end
   check("home_laundry_contact_inside_washer_art_"..id,inside)
   local blocker={id=999,kind="couch",location="floor",direction="south",x=x,y=y}
   s.home.furniture.items[#s.home.furniture.items+1]=blocker
   check("home_laundry_blocked_furniture_has_no_pose_"..id,Art.standingPose(s)==nil)
   s.home.furniture.items[#s.home.furniture.items]=nil
   check("home_laundry_clear_furniture_restores_pose_"..id,Art.standingPose(s)~=nil)
  end
 end
 -- A displayed handoff cannot consume a bundle, start a cycle, or create clean
 -- clothes. Only the existing authoritative chore completion may do that.
 local s,p=Fixtures.fresh("garden");p.character="rabbit-worker"
 p.x,p.y=Layout.toWorld(unpack(Layout.get(s).fixtures.laundry.approach))
 s.home.chores.laundry.dirty=2
 s.home.chores.contributions.owner=s.home.weekend.closesAtHours
 assert(Residents.command(s,p,"loadwash:laundry"))
 local a=Residents.display(s,p).activity;local started,ends=a.startedAt,a.endsAt
 for _,t in ipairs({0,.3,.6,.9}) do
  local frame=Art.frame(t,1,"loadwash")
  for _,d in ipairs(R.order) do
   local c=Art.contact(d,frame);check("home_laundry_presentation_no_reward_"..d..t,c.valid and s.home.chores.laundry.dirty==2 and s.home.chores.laundry.phase=="idle")
  end
 end
 assert(Residents.command(s,p,"cancel"))
 check("home_laundry_cancel_no_cycle",s.home.chores.laundry.dirty==2 and s.home.chores.laundry.cycle==0 and Residents.display(s,p).activity==nil)
 assert(Residents.command(s,p,"loadwash:laundry"));Residents.recover(s)
 check("home_laundry_recover_no_cycle",s.home.chores.laundry.dirty==2 and s.home.chores.laundry.cycle==0)
 assert(Residents.command(s,p,"loadwash:laundry"));a=Residents.display(s,p).activity;p.x=p.x+13
 Residents.advance(s,{p},a.startedAt,a.endsAt);p.x=p.x-13
 check("home_laundry_move_cancels_no_cycle",s.home.chores.laundry.dirty==2 and s.home.chores.laundry.phase=="idle" and Residents.display(s,p).activity==nil)
 assert(Residents.command(s,p,"loadwash:laundry"));a=Residents.display(s,p).activity
 Residents.advance(s,{p},a.startedAt,a.endsAt)
 local l=s.home.chores.laundry;local due=l.dueAt
 check("home_laundry_machine_runs_after_handoff",l.phase=="washing" and l.dirty==1 and l.cycle==1 and l.clean==0 and Residents.display(s,p).activity==nil
  and math.abs(l.dueAt-l.startedAt-.75)<1e-7)
 Residents.advance(s,{p},a.startedAt,a.endsAt)
 check("home_laundry_load_exact_once",l.dirty==1 and l.cycle==1)
 check("home_laundry_cannot_unload_running_cycle",not Residents.command(s,p,"unload:laundry"))
 clock(s,due);Chores.advance(s,{p},a.endsAt,due)
 assert(Residents.command(s,p,"unload:laundry"));a=Residents.display(s,p).activity
 check("home_laundry_clean_not_created_during_unload",l.clean==0 and l.phase=="ready")
 Residents.advance(s,{p},a.startedAt,a.endsAt)
 check("home_laundry_unload_authoritative_once",l.clean==1 and l.phase=="idle" and l.startedAt==nil and l.dueAt==nil)
 Residents.advance(s,{p},a.startedAt,a.endsAt)
 check("home_laundry_unload_not_duplicated",l.clean==1)
 -- Public guest identity is sufficient to derive the same action clock.
 local guest={id=2,sceneId="home",character="rabbit-worker",x=p.x,y=p.y}
 assert(Residents.bind(s,guest,string.rep("e",64),{p}));s.home.chores.laundry.dirty=1
 assert(Residents.command(s,guest,"loadwash:laundry"));a=Residents.display(s,guest).activity
 clock(s,a.startedAt+(a.endsAt-a.startedAt)*.5)
 local snapshot=Schema.snapshot(s);local replay=State.new();assert(State.applySharedSnapshot(replay,snapshot))
 local publicGuest={id=guest.id,sceneId="home",character="rabbit-worker",x=guest.x,y=guest.y}
 local remote=assert(Residents.display(replay,publicGuest)).activity
 local encoded=assert(require("src.net.codec").encode(snapshot,{maxBytes=1000000,maxEntries=20000,maxDepth=32,maxStringBytes=4096}))
 check("home_laundry_guest_uses_public_identity",publicGuest.homeResidentId==nil and not encoded:find(string.rep("e",64),1,true) and remote.kind=="loadwash")
 local function phase(state,activity)
  local day=Calendar.secondsPerDay(state);return Art.frame((Calendar.absoluteHours(state)-activity.startedAt)*day/24,(activity.endsAt-activity.startedAt)*day/24,activity.kind)
 end
 check("home_laundry_shared_guest_clock",phase(s,a)==3 and phase(replay,remote)==3,
  "host="..phase(s,a).." remote="..phase(replay,remote))
end
return Test
