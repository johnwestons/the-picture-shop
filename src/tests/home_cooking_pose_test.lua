local Test={}
function Test.run(context,check)
 local Fixtures=require("src.tests.home_dining_test");local Layout=require("src.home_layouts")
 local Furniture=require("src.home_furniture");local Residents=require("src.home_residents")
 local Animation=require("src.character_animation")
 local Routine=require("src.home_routine_pose");local Art=require("src.home_cooking_art")
 local Registration=require("src.home_cooking_registration");local State=require("src.state");local Schema=require("src.save_schema")
 check("home_cook_pan_scale_matches_stove_burner",math.abs(Art.PAN_SCALE-.13)<.000001)
 local function install(state)
  state.home.inventory.stove=1;Furniture.materialize(state,false)
  local item=state.home.furniture.items[#state.home.furniture.items]
  item.location="floor";item.x,item.y=Layout.kitchenPower(state);item.direction="west"
  return item
 end
 for _,id in ipairs(require("src.home_catalog").ORDER) do
  for _,d in ipairs(Registration.order) do
   local state,p=Fixtures.fresh(id);p.character="rabbit-worker";state.home.inventory.bread=2;state.home.inventory.vegetables=4
   local item=install(state);local approach
   for _,point in ipairs(Furniture.approaches(item)) do
    if Animation.authoredDirection(item.x-point.x,(item.y-point.y)*2)==d then approach=point;break end
   end
   assert(approach,"no stove approach for cooking pose "..d)
   p.x,p.y=approach.x,approach.y
   local target=assert(Furniture.targets(state,p)["furniture"..item.id]);p.x,p.y=target.x,target.y
   assert(Residents.command(state,p,"cook:furniture"..item.id))
   local elapsed=state.calendar.elapsed;local x,y=p.x,p.y
   for phase=1,4 do
    state.calendar.elapsed=elapsed+(phase-1)/4+.001
    local pose=assert(Routine.get(state,p));local replay=State.new();assert(State.applySharedSnapshot(replay,Schema.snapshot(state)))
    local remote=assert(Routine.get(replay,p))
    check("home_cook_pose_"..id.."_"..d.."_"..phase,pose.action=="home_cook_"..pose.direction and pose.frame==phase
     and pose.bowlX~=nil and remote.x==pose.x and remote.y==pose.y and remote.frame==phase and remote.bowlX==pose.bowlX
     and p.x==x and p.y==y)
   end
   assert(Residents.command(state,p,"cancel"));check("home_cook_cancel_"..id.."_"..d,Routine.get(state,p)==nil)
  end
 end
 local state,p=Fixtures.fresh();p.character="rabbit-worker";state.home.inventory.bread=2;state.home.inventory.vegetables=4
 local item=install(state)
 local target=assert(Furniture.targets(state,p)["furniture"..item.id]);p.x,p.y=target.x,target.y
 local guest={id=2,sceneId="home",character="rabbit-worker",x=p.x,y=p.y}
 assert(Residents.bind(state,guest,string.rep("e",64),{p}));assert(Residents.command(state,guest,"cook:furniture"..item.id))
 local pose=assert(Routine.get(state,guest));local replay=State.new();assert(State.applySharedSnapshot(replay,Schema.snapshot(state)))
 local remote=assert(Routine.get(replay,{id=2,sceneId="home",character="rabbit-worker",x=guest.x,y=guest.y}))
 check("home_cook_guest_shared_identity_pose",remote.action==pose.action and remote.x==pose.x and remote.bowlY==pose.bowlY)
 guest.x=guest.x+3;check("home_cook_movement_clears_pose",Routine.get(state,guest)==nil)
 guest.x=guest.x-3;Residents.recover(state);check("home_cook_recovery_clears_pose",Routine.get(state,guest)==nil)
 local canvas=love.graphics.newCanvas(960,480);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.13,.16,.18,1)
 for i,d in ipairs(Registration.order) do
  love.graphics.push();love.graphics.translate(110+(i-1)%4*240,210+math.floor((i-1)/4)*240);love.graphics.scale(1.6)
  Art.draw(d,2,0,0,{furColorway=(i-1)%6+1,overallsColorway=(i-1)%6+1});love.graphics.pop()
  check("home_cook_cache_bound_"..d,Art.cachedDirections()<=4)
 end
 love.graphics.pop()
 local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
 if folder then local data=canvas:newImageData();local bytes=data:encode("png");local file=assert(io.open(folder.."/home-cook-colorways.png","wb"));file:write(bytes:getString());file:close();bytes:release();data:release() end
 canvas:release();Art.release();check("home_cook_release_reclaims_direction_cache",Art.cachedDirections()==0)
 canvas=love.graphics.newCanvas(256,256);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
 Art.draw("north",1,128,180,{});love.graphics.pop();canvas:release()
 check("home_cook_reload_after_release",Art.cachedDirections()==1);Art.release()
end
return Test
