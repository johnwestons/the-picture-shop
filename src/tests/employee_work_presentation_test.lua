local Presentation=require("src.employee_work_presentation")
local Work=require("src.employee_work")
local Pose=require("src.employee_pose")
local State=require("src.state")
local Fleet=require("src.machine_fleet")
local Machine=require("src.machine")
local Renderer=require("src.employee_renderer")
local Protocol=require("src.net.protocol")
local Test={}
function Test.run(context,check)
    local state=State.new()
    local machine=Fleet.installed(state,"polar_115")
    local runtime=Machine.forId(machine.id)
    local oldStep,oldBarrier,oldEmergency=runtime.step,runtime.barrierClear,runtime.emergencyStopped
    local w={id="EMP-1",character="tinker-fox-worker",visible=true,phase="working",moving=false,
        x=500,y=500,intentX=1,intentY=0,distance=0,idleClock=0,reserved=true,
        assignment={machineId=machine.id,machineModel=machine.modelId,palletId="PAL-1",jobId="JOB-1"}}
    runtime.step,runtime.barrierClear,runtime.emergencyStopped="clamped",true,false
    local input=Work.presentation(state,w)
    check("work_pose_clamped_cutter_is_contact_not_running",input.mode=="contact" and input.contactFrame==5)
    Presentation.update(state,w,.36)
    local action,frame=Presentation.pose(w)
    check("work_pose_cutter_approach_holds_at_safety_controls",action=="work_cutter" and frame==5)
    runtime.step="cutting"
    Presentation.update(state,w,0)
    action,frame=Presentation.pose(w)
    check("work_pose_active_cutter_immediately_holds_both_controls",action=="work_cutter" and frame==6)
    Presentation.update(state,w,40)
    check("work_pose_machine_hold_does_not_loop_on_clock",select(2,Presentation.pose(w))==6)
    w.phase="idle"
    Presentation.update(state,w,4)
    check("work_pose_blocked_idle_cannot_release_an_active_machine",select(2,Presentation.pose(w))==6)
    w.phase="working"
    runtime.step="positioning"
    local positioning=Work.presentation(state,w)
    check("work_pose_cutter_feed_motion_is_not_a_blade_control_hold",positioning.mode=="contact" and positioning.contactFrame==4 and not positioning.safeToRecover)
    runtime.step="cutting"
    local rows=Pose.capture({{actor=w,worker=w}})
    local packet,err=Protocol.encode("employee_snapshot",{sessionId="work-pose",serverTick=1,employees=rows})
    local decoded=packet and Protocol.decode(packet)
    local actors=decoded and Pose.actors(decoded.payload.employees)
    local stale={character=w.character,assignment={machineModel="skid_wrapper"}}
    local guestAction,guestFrame=Renderer.pose({actor=actors and actors[w.id] or {},worker=stale},context.characterAssets)
    check("work_pose_guest_renders_host_action_despite_stale_assignment",guestAction==action and guestFrame==frame,err)
    local before=Presentation.capture(w)
    Renderer.pose({actor=w,worker=w},context.characterAssets)
    check("work_pose_draw_is_a_pure_read",Presentation.capture(w)==before)
    local valid=true
    for _,bad in ipairs({-1,125,.5,0/0}) do
        local copy={};for i,v in ipairs(rows[1]) do copy[i]=v end
        copy[9]=bad
        valid=valid and Pose.normalize({copy})==nil
    end
    check("work_pose_wire_rejects_unknown_and_fractional_frames",valid)
    runtime.step="loaded"
    Presentation.update(state,w,0)
    check("work_pose_operation_stop_begins_recovery",select(2,Presentation.pose(w))==7)
    Presentation.update(state,w,.24)
    check("work_pose_recovery_replays_approach",select(2,Presentation.pose(w))==2)
    Presentation.update(state,w,.36)
    check("work_pose_return_to_feed_uses_new_contact_frame",select(2,Presentation.pose(w))==4)
    w.moving=true;w.phase="walking"
    Presentation.update(state,w,0)
    w.moving=false;w.phase="idle"
    Presentation.update(state,w,20)
    check("work_pose_walking_cancels_stale_recovery",Presentation.capture(w)==0)
    w.phase="working";w.training={skill="cutter"};w.assignment=nil
    Presentation.update(state,w,.36)
    check("work_pose_training_is_contact_not_machine_operation",select(2,Presentation.pose(w))==4)
    Presentation.reset(w)
    runtime.step,runtime.barrierClear,runtime.emergencyStopped=oldStep,oldBarrier,oldEmergency
end
return Test
