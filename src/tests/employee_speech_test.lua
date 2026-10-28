local State=require("src.state")
local Employees=require("src.employees")
local Schedule=require("src.employee_schedule")
local AI=require("src.employee_ai")
local Jobs=require("src.jobs")
local Fleet=require("src.machine_fleet")
local Speech=require("src.employee_speech")
local Pose=require("src.employee_pose")
local Codec=require("src.net.codec")
local Renderer=require("src.employee_renderer")
local Test={}
local function hire(s)
    local a=assert(Employees.createApplicant(s,0));a.shiftPreference="flexible"
    Employees.requestResume(s,a.id,0);Employees.advance(s,.5)
    assert(Employees.command(s,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=math.max(2400,a.requestedWage),days=31,startHour=9,endHour=17},.5))
    Employees.advance(s,1.25)
    assert(Employees.command(s,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local w=s.employment.staff[#s.employment.staff]
    w.visible,w.clockedIn,w.phase,w.shiftDay=true,true,"idle",0
    w.x,w.y=600,540
    w.cutterSkill,w.pressSkill,w.wrappingSkill=100,100,100
    return w
end
local function fixture(context,id)
    local s=State.new();local w=hire(s)
    local machine=Fleet.installedUnits(s,"polar_115")[1]
    local j=assert(Jobs.createOffer({id=id,company="Employee bubble QA",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500}}))
    Jobs.accept(j);j.status,j.delivery="in_production",{status="received"}
    s.jobs.active[#s.jobs.active+1]=j
    local x,y=context.CutterZones.inputAnchor(s,context.config.cutterPlacement)
    local p=j.pallets[1];p.location,p.status="warehouse","raw"
    p.world={x=x,y=y,direction="northwest",spawnProgress=1}
    context.machine.reset(s)
    return s,w,j,machine,p
end
local function caption(w) return Speech.code({worker=w,actor=w}) end
local function idleContext()
    return {canClaim=function() return true end,freeSeat=function() end,
        idlePoint=function(w) return {x=w.x,y=w.y} end}
end
local function schedules(context,check)
    local s,w,j,m=fixture(context,"BUBBLE-PERSONAL")
    j.difficulty="hard";w.cutterSkill=1
    assert(Employees.command(s,{kind="queue_employee_job",employeeId=w.id,jobId=j.id,machineId=m.id},9))
    Schedule.advance(s,w,9)
    check("employee_bubble_personal_job_explains_low_cutter_skill",not w.assignment
        and caption(w)==Speech.REASONS.cutter_skill and Speech.message(caption(w)):find("higher cutter skill",1,true))
    AI.worker(s,w,.1,9.001,idleContext())
    check("employee_bubble_idle_movement_preserves_blocked_personal_job_reason",caption(w)==Speech.REASONS.cutter_skill)

    s,w,j,m=fixture(context,"BUBBLE-TEAM");j.difficulty="hard";w.cutterSkill=1
    assert(Employees.command(s,{kind="queue_team_job",jobId=j.id,machineId=m.id},9))
    Schedule.advance(s,w,9);AI.worker(s,w,.1,9.001,idleContext())
    check("employee_bubble_shared_job_explains_skill_instead_of_empty_schedule",not w.assignment and #w.schedule.items==0
        and #Schedule.team(s).items==1 and caption(w)==Speech.REASONS.cutter_skill)
    w.cutterSkill=100;w._scheduleRetryAtHours=nil
    Schedule.advance(s,w,9.1)
    check("employee_bubble_reason_clears_when_skill_allows_work",w.assignment and w.assignment.jobId==j.id
        and not w._scheduleBlockedReason and caption(w)~=Speech.REASONS.cutter_skill)

    local empty=State.new();local idle=hire(empty)
    Schedule.advance(empty,idle,9);AI.worker(empty,idle,.1,9.001,idleContext())
    check("employee_bubble_empty_schedule_states_no_jobs",caption(idle)==Speech.REASONS.no_jobs
        and Speech.message(caption(idle))=="No jobs on the schedule")
    idle.schedule.enabled=false
    Schedule.advance(empty,idle,9.1);AI.worker(empty,idle,.1,9.101,idleContext())
    check("employee_bubble_paused_schedule_is_distinct_from_empty_schedule",caption(idle)==22)
    idle.schedule.enabled=true;idle._scheduleBlockedReason="This job needs a more skilled cutter operator"
    idle._waitingForJack=false;idle._scheduleRetryAtHours=10
    AI.worker(empty,idle,.1,9.2,idleContext())
    check("employee_bubble_removed_jobs_do_not_leave_stale_skill_warning",caption(idle)==Speech.REASONS.no_jobs)
end
local function blockers(context,check)
    local s,w,j,m,p=fixture(context,"BUBBLE-BLOCKERS")
    j.difficulty="hard";j.press={};p.status="cut";w.pressSkill=0
    local _,_,_,reason=Schedule.resolve(s,w,{jobId=j.id})
    w.activity=reason
    check("employee_bubble_press_skill_is_specific",caption(w)==Speech.REASONS.press_skill)
    j.press=nil;w.wrappingSkill=0
    _,_,_,reason=Schedule.resolve(s,w,{jobId=j.id});w.activity=reason
    check("employee_bubble_wrapping_skill_is_specific",caption(w)==Speech.REASONS.wrapping_skill)
    w.wrappingSkill=100;s.inventory.plasticWrapUses=0
    _,_,_,reason=Schedule.resolve(s,w,{jobId=j.id});w.activity=reason
    check("employee_bubble_missing_wrap_reports_supply_needed",caption(w)==Speech.REASONS.film)
    p.status="raw"
    _,_,_,reason=Schedule.resolve(s,w,{jobId=j.id},nil,function() return false end);w.activity=reason
    check("employee_bubble_player_occupied_machine_reports_why",caption(w)==Speech.REASONS.player_machine)
    local other=hire(s);other.assignment={jobId=j.id,palletId=p.id,machineId=m.id,machineModel="polar_115"}
    _,_,_,reason=Schedule.resolve(s,w,{jobId=j.id});w.activity=reason
    check("employee_bubble_employee_occupied_machine_is_distinct",caption(w)==Speech.REASONS.employee_machine)
    other.assignment=nil;m.maintenance.cutter.bladeRemoved=true
    _,_,_,reason=Schedule.resolve(s,w,{jobId=j.id});w.activity=reason
    check("employee_bubble_installed_cutter_reports_missing_blade_instead_of_missing_machine",caption(w)==Speech.REASONS.blade_missing)
    m.maintenance.cutter.bladeRemoved=false
    p.location="awaiting_delivery";j.delivery.status="scheduled"
    _,_,_,reason=Schedule.resolve(s,w,{jobId=j.id});w.activity=reason
    check("employee_bubble_delivery_wait_is_explicit",caption(w)==Speech.REASONS.delivery)
    p.location="warehouse";j.delivery.status="received"
    require("src.employee_pallet_jack").update(s,w,m,p,"cutter",.1,{jackApproachPoint=function() end})
    check("employee_bubble_jack_access_names_the_obstruction",caption(w)==Speech.REASONS.jack_access)
    w.greetingKind=1
    check("employee_bubble_blocked_reason_takes_priority_over_greeting",caption(w)==Speech.REASONS.jack_access)
    w.activity="Operating paper cutter";w.phase="working";w.greetingKind=nil
    w.assignment={machineModel="polar_115"}
    check("employee_bubble_resolved_obstruction_returns_to_work_caption",caption(w)==4)
end
local function network(context,check)
    local s=State.new();local w=hire(s)
    w.activity="Press training required before this employee can print"
    local rows=Pose.capture(Employees.actors(s))
    local Protocol=require("src.net.protocol")
    local packet=assert(Protocol.encode("employee_snapshot",{sessionId="speech-reasons",serverTick=1,employees=rows}))
    local client=require("src.net.session").new()
    client.mode,client.ready,client.sessionId="client",true,"speech-reasons"
    client:_handleClientEnvelope(assert(Protocol.decode(packet)))
    client:_handleClientEnvelope(assert(Protocol.decode(packet)))
    local events=client:drainEvents();local guest=State.new()
    local applied=events[1] and context.world.applyEmployeeSnapshot(events[1].employees,guest)
    check("employee_bubble_guest_uses_current_host_reason_instead_of_stale_activity",applied and #events==1
        and Speech.code({worker={activity="Work schedule complete"},actor=guest._employeePoses[w.id]})==Speech.REASONS.press_skill)
    local maximum=Codec.array()
    for i=1,11 do maximum[i]=Codec.array({"EMP-"..string.format("%012d",i),96000,67800,8,15999,12999,1,10,124,2,1000,Speech.MAX_CODE}) end
    local largest,errorMessage=Protocol.encode("employee_snapshot",{sessionId=string.rep("s",64),serverTick=4294967295,employees=maximum})
    check("employee_bubble_reasons_fit_full_eleven_actor_packet",largest and #largest<=Protocol.MAX_PACKET_BYTES,errorMessage)
    maximum[1][12]=Speech.MAX_CODE+1
    check("employee_bubble_wire_rejects_unknown_reason_code",not Protocol.encode("employee_snapshot",{
        sessionId="speech-reasons",serverTick=2,employees=maximum}))
end
local function layout(context,check)
    local font=love.graphics.newFont(11)
    local fits,multiline=true,false
    for code=1,Speech.MAX_CODE do
        local message=Speech.message(code)
        local width,height=Renderer.bubbleLayout(message,font)
        local _,lines=font:getWrap(message,width-12)
        fits=fits and width<=176 and height>=#lines*font:getHeight()*font:getLineHeight()+10
        multiline=multiline or #lines>1
    end
    check("employee_bubble_long_reasons_wrap_inside_resized_bubble",fits and multiline)
    font:release()
    local directory=os.getenv("PICTURE_SHOP_EMPLOYEE_SPEECH_CAPTURE_DIR")
    if directory then
        local s=State.new()
        local cases={{"This job needs a more skilled cutter operator",330,380},
            {"No jobs on the schedule",560,430},{"Clear the far side of the room doorway",740,530}}
        for _,item in ipairs(cases) do
            local w=hire(s);w.activity,w.x,w.y=item[1],item[2],item[3]
        end
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(0,0,0,1)
        love.graphics.setColor(1,1,1);local image=context.assets.get("warehouse")
        love.graphics.draw(image,0,0,0,960/image:getWidth(),678/image:getHeight())
        for _,entry in ipairs(Employees.actors(s)) do Renderer.draw(entry,context.characterAssets,s);Renderer.drawBubble(entry,context.characterAssets,s) end
        love.graphics.setCanvas();love.graphics.pop()
        local data=canvas:newImageData();local bytes=data:encode("png"):getString();data:release();canvas:release()
        local f=assert(io.open(directory.."/employee-reasons.png","wb"));f:write(bytes);f:close()
    end
end
function Test.run(context,check)
    schedules(context,check);blockers(context,check);network(context,check);layout(context,check)
end
return Test
