local Test={}
function Test.run(context,check)
 local Art=require("src.home_trash_art");local R=require("src.home_trash_registration")
 local Fixtures=require("src.tests.home_dining_test");local Residents=require("src.home_residents")
 local Routine=require("src.home_routine_pose");local State=require("src.state");local Schema=require("src.save_schema")
 local s,p=Fixtures.fresh();p.character="rabbit-worker";s.home.chores.trash=12
 assert(Residents.command(s,p,"trash:floor"));local elapsed=s.calendar.elapsed;local x,y=p.x,p.y
 local samples={0,.35,.65,1.1}
 for i,d in ipairs(R.order) do
  p.intentX,p.intentY=math.cos((i-1)*math.pi/4),math.sin((i-1)*math.pi/4)
  for phase,seconds in ipairs(samples) do
   s.calendar.elapsed=elapsed+seconds
   local pose=assert(Routine.get(s,p));local replay=State.new();assert(State.applySharedSnapshot(replay,Schema.snapshot(s)))
   local remote=assert(Routine.get(replay,p));local c=Art.contact(d,phase)
   check("home_trash_"..d.."_phase_"..phase,pose.action=="home_trash_"..d and pose.frame==phase and pose.mirror==1
    and remote.frame==phase and remote.direction==d and p.x==x and p.y==y and c.bottom<=3 and s.home.chores.trash==12)
  end
  check("home_trash_"..d.."_lifts_clear_of_floor",Art.contact(d,3).bottom<Art.contact(d,1).bottom-3)
 end
 for _,day in ipairs({300,1200,3600}) do
  local duration=day/288
  check("home_trash_short_day_phases_"..day,Art.frame(0,duration)==1 and Art.frame(math.min(.3,duration*.2)*1.5,duration)==2
   and Art.frame(math.min(.3,duration*.2)*2+.01,duration)==3 and Art.frame(duration*.9,duration)>=3)
 end
 s.calendar.elapsed=elapsed;assert(Residents.command(s,p,"cancel"))
 check("home_trash_cancel_clears_without_reward",Routine.get(s,p)==nil and s.home.chores.trash==12)
 assert(Residents.command(s,p,"trash:floor"));p.x=x+3
 check("home_trash_move_clears_body_and_tool",Routine.get(s,p)==nil)
 p.x=x;Residents.recover(s)
 check("home_trash_recover_clears_without_reward",Routine.get(s,p)==nil and s.home.chores.trash==12)
 assert(Residents.command(s,p,"trash:floor"));local a=Residents.display(s,p).activity
 Residents.advance(s,{p},a.startedAt,a.endsAt)
 check("home_trash_finish_removes_only_reserved_amount",s.home.chores.trash==4 and Routine.get(s,p)==nil)
 Residents.advance(s,{p},a.startedAt,a.endsAt)
 check("home_trash_finish_exactly_once",s.home.chores.trash==4)
 local guest={id=2,sceneId="home",character="rabbit-worker",x=x,y=y,intentX=-1,intentY=-1}
 assert(Residents.bind(s,guest,string.rep("d",64),{p}));assert(Residents.command(s,guest,"trash:floor"))
 s.calendar.elapsed=elapsed+.65
 local replay=State.new();assert(State.applySharedSnapshot(replay,Schema.snapshot(s)))
 local remote=assert(Routine.get(replay,guest))
 check("home_trash_guest_public_identity_and_clock",remote.action=="home_trash_northwest" and remote.frame==3)
 local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
 local function save(canvas,name)
  if not folder then return end
  local data=canvas:newImageData();local bytes=data:encode("png");local f=assert(io.open(folder.."/"..name..".png","wb"))
  f:write(bytes:getString());f:close();bytes:release();data:release()
 end
 local all=love.graphics.newCanvas(1280,2048)
 love.graphics.push("all");love.graphics.setCanvas(all);love.graphics.clear(.13,.16,.18,1)
 for i,d in ipairs(R.order) do
  for phase=1,4 do
   love.graphics.push();love.graphics.translate((phase-1)*320+160,(i-1)*256+210);love.graphics.scale(1.7)
   local c=Art.draw(d,phase,0,0,{})
   love.graphics.pop();love.graphics.setColor(1,1,1,1);love.graphics.print(d.." / "..phase,(phase-1)*320+8,(i-1)*256+8)
   check("home_trash_render_"..d..phase,c.valid and Art.cachedPhases()<=4)
  end
 end
 love.graphics.pop();save(all,"trash-all-directions");all:release()
 for _,d in ipairs(R.order) do
  local strip=love.graphics.newCanvas(1280,256)
  love.graphics.push("all");love.graphics.setCanvas(strip);love.graphics.clear()
  for phase=1,4 do
   love.graphics.push();love.graphics.translate((phase-1)*320+160,210);love.graphics.scale(1.7)
   Art.draw(d,phase,0,0,{});love.graphics.pop()
  end
  love.graphics.pop();save(strip,"trash-"..d.."-assembled");strip:release()
 end
 local colors=love.graphics.newCanvas(960,480)
 love.graphics.push("all");love.graphics.setCanvas(colors);love.graphics.clear(.13,.16,.18,1)
 for i,d in ipairs(R.order) do
  love.graphics.push();love.graphics.translate(120+(i-1)%4*240,210+math.floor((i-1)/4)*240);love.graphics.scale(1.7)
  Art.draw(d,3,0,0,{furColorway=(i-1)%6+1,overallsColorway=(i-1)%6+1});love.graphics.pop()
 end
 love.graphics.pop();save(colors,"trash-colorways");colors:release();Art.release()
 check("home_trash_release_reclaims_atlases",Art.cachedPhases()==0)
 local canvas=love.graphics.newCanvas(256,256);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
 Art.draw("northwest",2,128,180,{});love.graphics.pop();canvas:release()
 check("home_trash_reload_after_release",Art.cachedPhases()==1);Art.release()
end
return Test
