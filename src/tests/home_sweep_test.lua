local Test={}
function Test.run(context,check)
    local Art=require("src.home_sweep_art");local Registration=require("src.home_sweep_registration")
    local Fixtures=require("src.tests.home_dining_test");local Residents=require("src.home_residents")
    local Routine=require("src.home_routine_pose");local State=require("src.state");local Schema=require("src.save_schema")
    local s,p=Fixtures.fresh();s.home.chores.soil.living=65;p.character="rabbit-worker"
    assert(Residents.command(s,p,"sweep:floor"));local elapsed=s.calendar.elapsed;local x,y=p.x,p.y
    for i,d in ipairs(Registration.order) do
        p.intentX,p.intentY=math.cos((i-1)*math.pi/4),math.sin((i-1)*math.pi/4)
        for phase,wanted in ipairs({1,2,3,4,3,2}) do
            s.calendar.elapsed=elapsed+(phase-1)/6+.001
            local pose=assert(Routine.get(s,p));local replay=State.new();assert(State.applySharedSnapshot(replay,Schema.snapshot(s)))
            local remote=assert(Routine.get(replay,p))
            check("home_sweep_"..d.."_phase_"..phase,pose.direction==d and pose.frame==wanted and pose.action=="home_sweep_"..d
                and pose.mirror==1 and remote.frame==pose.frame and remote.direction==d and p.x==x and p.y==y)
        end
        for frame=1,4 do check("home_sweep_"..d.."_physical_grip_"..frame,Art.contact(d,frame).valid) end
    end
    local canvas=love.graphics.newCanvas(960,480);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.13,.16,.18,1)
    for i=1,8 do
        love.graphics.push();love.graphics.translate(115+(i-1)%4*240,200+math.floor((i-1)/4)*240);love.graphics.scale(1.6)
        Art.draw(Registration.order[i],3,0,0,{furColorway=(i-1)%6+1,overallsColorway=(i-1)%6+1})
        love.graphics.pop();check("home_sweep_direction_cache_bound_"..i,Art.cachedDirections()<=4)
    end
    love.graphics.pop()
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if folder then local data=canvas:newImageData();local bytes=data:encode("png");local file=assert(io.open(folder.."/home-sweep-colorways.png","wb"));file:write(bytes:getString());file:close();data:release();bytes:release() end
    canvas:release();Art.release();check("home_sweep_release_reclaims_direction_cache",Art.cachedDirections()==0)
    canvas=love.graphics.newCanvas(256,256);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
    Art.draw("northwest",4,128,180,{});love.graphics.pop();canvas:release()
    check("home_sweep_reloads_after_release",Art.cachedDirections()==1)
    assert(Residents.command(s,p,"cancel"));check("home_sweep_cancel_clears_body_and_tool",Routine.get(s,p)==nil)
    assert(Residents.command(s,p,"sweep:floor"));p.x=x+3
    check("home_sweep_move_clears_body_and_tool",Routine.get(s,p)==nil)
    p.x=x;Residents.recover(s);check("home_sweep_recover_clears_body_and_tool",Routine.get(s,p)==nil)
    Art.release()
end
return Test
