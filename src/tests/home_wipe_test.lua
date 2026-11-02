local Test={}
function Test.run(context,check)
 local Art=require("src.home_wipe_art");local R=require("src.home_wipe_registration")
 local Fixtures=require("src.tests.home_dining_test");local Residents=require("src.home_residents")
 local Routine=require("src.home_routine_pose");local Layout=require("src.home_layouts")
 local State=require("src.state");local Schema=require("src.save_schema");local Furniture=require("src.home_furniture")
 for _,id in ipairs(require("src.home_catalog").ORDER) do
  for _,kind in ipairs({"wipe","scrub"}) do
   local s,p=Fixtures.fresh(id);p.character="rabbit-worker"
   local name=kind=="wipe" and "sink" or "bath";local soil=kind=="wipe" and "kitchen" or "bathroom"
   s.home.chores.soil[soil]=70;p.x,p.y=Layout.toWorld(unpack(Layout.get(s).fixtures[name].approach))
   local x,y=p.x,p.y;assert(Residents.command(s,p,kind..":"..name));local elapsed=s.calendar.elapsed
   for phase,wanted in ipairs({1,2,3,2}) do
    s.calendar.elapsed=elapsed+(phase-1)/(kind=="wipe" and 5 or 7)+.001
    local pose=assert(Routine.get(s,p));local replay=State.new();assert(State.applySharedSnapshot(replay,Schema.snapshot(s)))
    local remote=assert(Routine.get(replay,p))
    check("home_wipe_"..id.."_"..kind.."_phase_"..phase,pose.action=="home_wipe_"..pose.direction and pose.frame==wanted
     and remote.frame==wanted and remote.x==pose.x and remote.y==pose.y and remote.direction==pose.direction
     and p.x==x and p.y==y and Art.onFixture(s,name,pose.direction,pose.frame,pose.x,pose.y))
   end
   p.x=x+3;check("home_wipe_"..id.."_"..kind.."_move_clears",Routine.get(s,p)==nil);p.x=x
   assert(Residents.command(s,p,"cancel"));check("home_wipe_"..id.."_"..kind.."_cancel_no_reward",s.home.chores.soil[soil]==70 and Routine.get(s,p)==nil)
   assert(Residents.command(s,p,kind..":"..name));Residents.recover(s)
   check("home_wipe_"..id.."_"..kind.."_recovery_clears",Routine.get(s,p)==nil and s.home.chores.soil[soil]==70)
   assert(Residents.command(s,p,kind..":"..name));local a=Residents.display(s,p).activity
   Residents.advance(s,{p},a.startedAt,a.endsAt)
   check("home_wipe_"..id.."_"..kind.."_completion_once",Routine.get(s,p)==nil and s.home.chores.soil[soil]==(kind=="wipe" and 35 or 20))
   local after=s.home.chores.soil[soil];Residents.advance(s,{p},a.startedAt,a.endsAt)
   check("home_wipe_"..id.."_"..kind.."_repeat_does_not_reward",s.home.chores.soil[soil]==after)
  end
 end
 local s,p=Fixtures.fresh("corner");p.character="rabbit-worker";s.home.chores.soil.kitchen=70
 p.x,p.y=Layout.toWorld(unpack(Layout.get(s).fixtures.sink.approach))
 local x,y=Art.standingPose(s,"sink");assert(Residents.command(s,p,"wipe:sink"));local a=Residents.display(s,p).activity
 s.home.inventory.couch=1;Furniture.materialize(s,false);local couch=s.home.furniture.items[#s.home.furniture.items]
 couch.location="floor";couch.x,couch.y=x,y
 check("home_wipe_new_obstacle_hides_pose",Art.standingPose(s,"sink")==nil and Routine.get(s,p)==nil)
 Residents.advance(s,{p},a.startedAt,a.endsAt)
 check("home_wipe_new_obstacle_cancels_without_reward",not Residents.display(s,p).activity and s.home.chores.soil.kitchen==70)
 local ok,_,message=Residents.command(s,p,"wipe:sink")
 check("home_wipe_blocked_stance_cannot_start",not ok and message:find("furniture",1,true)~=nil and not Residents.display(s,p).activity)
 couch.location="storage";couch.x,couch.y=0,0
 local g={id=2,sceneId="home",character="rabbit-worker",x=p.x,y=p.y}
 assert(Residents.bind(s,g,string.rep("f",64),{p}));assert(Residents.command(s,g,"wipe:sink"))
 s.calendar.elapsed=s.calendar.elapsed+.41
 local replay=State.new();assert(State.applySharedSnapshot(replay,Schema.snapshot(s)))
 local remote=assert(Routine.get(replay,{id=2,sceneId="home",character="rabbit-worker",x=g.x,y=g.y}))
 check("home_wipe_guest_public_identity_and_clock",remote.action=="home_wipe_north" and remote.frame==3)
 local canvas=love.graphics.newCanvas(960,480);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.13,.16,.18,1)
 for i,d in ipairs(R.order) do
  love.graphics.push();love.graphics.translate(115+(i-1)%4*240,210+math.floor((i-1)/4)*240);love.graphics.scale(1.6)
  Art.draw(d,3,0,0,{furColorway=(i-1)%6+1,overallsColorway=(i-1)%6+1});love.graphics.pop()
  check("home_wipe_cache_bound_"..d,Art.cachedPhases()<=4)
 end
 love.graphics.pop();local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
 if folder then local data=canvas:newImageData();local bytes=data:encode("png");local f=assert(io.open(folder.."/home-wipe-colorways.png","wb"));f:write(bytes:getString());f:close();bytes:release();data:release() end
 canvas:release();Art.release();check("home_wipe_release_reclaims_all_atlases",Art.cachedPhases()==0)
 canvas=love.graphics.newCanvas(256,256);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
 Art.draw("southwest",3,128,180,{});love.graphics.pop();canvas:release()
 check("home_wipe_corrected_frame_reloads_after_release",Art.cachedPhases()==1);Art.release()
end
return Test
