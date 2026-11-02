local Routine=require("src.home_routine_pose")
local Residents=require("src.home_residents")
local Layout=require("src.home_layouts")
local Fixtures=require("src.tests.home_dining_test")
local Schema=require("src.save_schema")
local Test={}
local function capture(canvas,name)
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
    local data=canvas:newImageData();local bytes=data:encode("png")
    local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
    bytes:release();data:release()
end
function Test.run(context,check)
    require("src.tests.home_action_art_review").run(check)
    require("src.tests.home_privacy_art_test").run(context,check)
    require("src.tests.home_held_art_test").run(context,check)
    require("src.tests.home_sweep_test").run(context,check)
    require("src.tests.home_cooking_pose_test").run(context,check)
    require("src.tests.home_trash_test").run(context,check)
    require("src.tests.home_wipe_test").run(context,check)
    for _,id in ipairs(require("src.home_catalog").ORDER) do
        for _,example in ipairs({{"wash","sink"},{"dishes","sink"},{"wipe","sink"},{"scrub","bath"},
            {"loadwash","laundry"},{"unload","laundry"},{"change","laundry"},{"sweep","floor"},{"trash","floor"}}) do
            local s,p=Fixtures.fresh(id);p.character="rabbit-worker"
            local kind,target=unpack(example);local c=s.home.chores
            c.dishes=4;c.trash=4;c.soil.kitchen=50;c.soil.bathroom=50;c.soil.living=50
            c.laundry.dirty=1;c.laundry.clean=1
            if kind=="unload" then c.laundry.phase="ready";c.laundry.cycle=1;c.laundry.startedAt=43;c.laundry.dueAt=43.75 end
            if target~="floor" then p.x,p.y=Layout.toWorld(unpack(Layout.get(s).fixtures[target].approach)) end
            local x,y=p.x,p.y;assert(Residents.command(s,p,kind..":"..target))
            local pose=assert(Routine.get(s,p));local prefix="home_routine_"..id.."_"..kind
            local px,py=x,y
            if kind=="wipe" or kind=="scrub" then px,py=require("src.home_wipe_art").standingPose(s,target) end
            if kind=="wash" or kind=="dishes" then px,py=require("src.home_washing_art").standingPose(s,target,kind) end
            if kind=="loadwash" or kind=="unload" then px,py=require("src.home_laundry_art").standingPose(s) end
            local authored=kind=="sweep" or kind=="trash" or kind=="wipe" or kind=="scrub"
            local expectedFrame=authored and 1 or 2
            if kind=="wash" or kind=="dishes" then expectedFrame=require("src.home_washing_art").frame(kind,0) end
            if kind=="loadwash" or kind=="unload" then expectedFrame=require("src.home_laundry_art").frame(0,1,kind) end
            check(prefix.."_anchored_without_moving_physics",pose.x==px and pose.y==py and p.x==x and p.y==y and pose.frame==expectedFrame,
                ("pose=%.2f,%.2f expected=%.2f,%.2f player=%.2f,%.2f frame=%d expectedFrame=%d"):format(
                    pose.x,pose.y,px,py,p.x,p.y,pose.frame,expectedFrame))
            local snapshot=Schema.snapshot(s);local replay=require("src.state").new()
            assert(require("src.state").applySharedSnapshot(replay,snapshot))
            local remote=assert(Routine.get(replay,p))
            check(prefix.."_snapshot_same_pose",remote.x==pose.x and remote.action==pose.action and remote.frame==pose.frame and Schema.validState(snapshot))
            context.world.load(p);context.world._state=s
            local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
            context.world.draw(context.assets,context.characterAssets,s,nil,nil,{})
            love.graphics.pop();capture(canvas,"home-routine-"..id.."-"..kind);canvas:release()
            p.x=x+3;check(prefix.."_movement_clears",Routine.get(s,p)==nil);p.x=x
            assert(Residents.command(s,p,"cancel"));check(prefix.."_cancel_clears",Routine.get(s,p)==nil)
        end
    end
    local s,p=Fixtures.fresh();local g={id=2,sceneId="home",character="rabbit-worker"}
    g.x,g.y=Layout.toWorld(unpack(Layout.get(s).fixtures.sink.approach))
    assert(Residents.bind(s,g,string.rep("b",64),{p}));assert(Residents.command(s,g,"wash:sink"))
    local pose=assert(Routine.get(s,g));local replay=require("src.state").new()
    assert(require("src.state").applySharedSnapshot(replay,Schema.snapshot(s)))
    local remote=assert(Routine.get(replay,{id=2,sceneId="home",character="rabbit-worker",x=g.x,y=g.y}))
    check("home_routine_guest_without_private_identity",remote.action==pose.action and remote.x==pose.x and remote.frame==pose.frame)
    local before=Schema.snapshot(s)
    local Calendar=require("src.business_calendar")
    local elapsed=s.calendar.elapsed
    s.calendar.elapsed=elapsed+.4
    local nextPose=assert(Routine.get(s,g))
    check("home_routine_frame_follows_shared_clock",nextPose.frame==require("src.home_washing_art").frame("wash",.4)
        and math.abs(nextPose.seconds-.4)<1e-7)
    s.calendar.elapsed=elapsed
    local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(.13,.16,.18,1)
    for i,example in ipairs({{"cook","work_task",1,"east"},{"prepare","work_task_south",1,"south"},
        {"dishes","work_task_northeast",1,"southeast"},{"wipe","work_task_southeast",1,"northeast"},
        {"sweep","work_task",-1,"west"},{"loadwash","work_task_north",1,"north"},
        {"trash","work_task_northeast",-1,"southwest"},{"change","work_task_southeast",-1,"northwest"}}) do
        local preview={routine=example[1],action=example[2],mirror=example[3],direction=example[4],frame=2,seconds=0,progress=.5,x=0,y=0}
        love.graphics.push();love.graphics.translate(120+((i-1)%4)*240,230+math.floor((i-1)/4)*300);love.graphics.scale(2)
        check("home_routine_draw_"..preview.routine,Routine.draw(preview,g,context.characterAssets))
        love.graphics.pop();love.graphics.setColor(1,1,1,1)
        love.graphics.printf(preview.routine.." / "..preview.direction,((i-1)%4)*240,260+math.floor((i-1)/4)*300,240,"center")
    end
    love.graphics.pop();capture(canvas,"home-routine-directions");canvas:release()
    check("home_routine_sink_art_draws_without_character_pack",Routine.draw(pose,g,nil))
    Residents.recover(s);check("home_routine_recovery_clears",Routine.get(s,g)==nil)
    check("home_routine_does_not_create_inventory",before.home.inventory.basic_meal==s.home.inventory.basic_meal and #before.home.furniture.items==#s.home.furniture.items)
    Routine.release()
end
return Test
