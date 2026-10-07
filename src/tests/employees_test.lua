local State=require("src.state")
local Schema=require("src.save_schema")
local Employees=require("src.employees")
local Contracts=require("src.employment_contracts")
local Payroll=require("src.payroll")
local AI=require("src.employee_ai")
local Work=require("src.employee_work")
local Animation=require("src.character_animation")
local Renderer=require("src.employee_renderer")
local Calendar=require("src.business_calendar")
local Intent=require("src.office_intent")
local Office=require("src.office_authority")
local Hiring=require("src.screens.hiring_screen")
local Jobs=require("src.jobs")
local Fleet=require("src.machine_fleet")
local Schedule=require("src.employee_schedule")
local Labor=require("src.employee_labor")
local Pose=require("src.employee_pose")
local Protocol=require("src.net.protocol")
local Codec=require("src.net.codec")
local Test={}
local function hours(state,h)
    state.calendar=Calendar.dateFromTotalDay(math.floor(h/24))
    state.calendar.elapsed=(h%24)/24*Calendar.secondsPerDay(state)
end
local function hire(state)
    local a=assert(Employees.createApplicant(state,0))
    assert(Employees.requestResume(state,a.id,0))
    hours(state,.5);Employees.advance(state,.5)
    assert(Employees.command(state,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=2200,days=31,startHour=9,endHour=17},.5))
    hours(state,1.25);Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    return state.employment.staff[1],a
end
function Test.run(context,check)
    local fresh=State.new()
    check("employees_fresh_shop_has_valid_empty_staff_and_recruitment",Employees.valid(fresh.employment) and #fresh.employment.staff==0 and fresh.employment.recruiting)
    local World=require("src.world")
    local visitState=State.new();local visitor=Employees.createApplicant(visitState,0)
    visitor.actor.visible=true;visitor.actor.phase="waiting";visitor.actor.x=759;visitor.actor.y=358
    local oldWorldState,oldWorldAssets,oldSelection=World._state,World._assets,World.selectedInteraction
    local oldX,oldY=World.player.x,World.player.y
    World.player.x,World.player.y=746,377;World.selectedInteraction=nil
    local visitOkay,visitError=pcall(World.update,0,0,0,context.assets,visitState,759,358)
    local selectedVisit=World.selectedInteraction
    World._state,World._assets,World.selectedInteraction=oldWorldState,oldWorldAssets,oldSelection
    World.player.x,World.player.y=oldX,oldY
    check("employees_reception_applicant_is_registered_and_selectable",visitOkay and selectedVisit and selectedVisit.kind=="applicant",tostring(visitError))
    check("employees_reception_interaction_requests_typed_resume",World.requestEmployeeResume(visitState,visitor.id) and visitor.status=="resume_requested")
    local legacy=Schema.newPayload(1,1);legacy.version=16;legacy.state.employment=nil
    local migrated=Schema.migrate(legacy)
    check("employees_v16_save_migrates_to_empty_staff",migrated and migrated.version==21 and #migrated.state.employment.staff==0)
    local a=Employees.createApplicant(fresh,0)
    Employees.requestResume(fresh,a.id,0)
    local revision=a.revision
    Employees.requestResume(fresh,a.id,0)
    check("employees_resume_request_is_idempotent",a.revision==revision and a.replyAtHours==.5)
    hours(fresh,.5);Employees.advance(fresh,.5)
    local notice=fresh.clientEmails.inbox[1]
    check("employees_typed_resume_attachment_arrives",notice and notice.applicationId==a.id and notice.attachmentKind=="resume" and a.status=="resume_received")
    local low={kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,wageCents=1500,days=31,startHour=9,endHour=17}
    check("employees_offer_goes_through_typed_office_intent",Intent.normalize(low)~=nil and Employees.command(fresh,low,.5))
    hours(fresh,1.25);Employees.advance(fresh,1.25)
    check("employees_low_offer_produces_stable_counter",a.status=="resume_received" and a.counter.wageCents==2200 and a.counters==1)
    low.expectedRevision=a.revision
    Employees.command(fresh,low,1.25)
    check("employees_duplicate_terms_do_not_consume_round",a.counters==1 and a.status=="resume_received")
    low.expectedRevision=a.revision-1;low.wageCents=2200
    check("employees_stale_offer_is_rejected",not Employees.command(fresh,low,1.25))
    low.expectedRevision=a.revision
    Employees.command(fresh,low,1.25)
    hours(fresh,2);Employees.advance(fresh,2)
    check("employees_applicant_accepts_viable_offer",a.status=="offer_accepted" and a.offer.wageCents==2200)
    local sign={kind="hire_employee",applicationId=a.id,expectedRevision=a.revision}
    check("employees_final_agreement_creates_cat_employee",Employees.command(fresh,sign,2)
        and fresh.employment.staff[1].id=="EMP-0001" and fresh.employment.staff[1].character=="cat-worker")
    Employees.command(fresh,sign,2)
    check("employees_signing_is_idempotent",#fresh.employment.staff==1)
    local w=fresh.employment.staff[1]
    local scheduleStatusState=State.new();local scheduleStatusWorker=hire(scheduleStatusState)
    scheduleStatusWorker.activity="Work schedule complete"
    local sharedSchedule=Schedule.team(scheduleStatusState)
    sharedSchedule.items[1]={id="TEAM-TASK-000001"}
    local sharedStatus,sharedDetail=Hiring.staffScheduleStatus(scheduleStatusState,scheduleStatusWorker)
    check("employees_staff_panel_shows_shared_jobs_instead_of_stale_no_work_status",
        sharedStatus=="Shared schedule | 1 job" and sharedDetail:find("shared day/night schedule",1,true)~=nil)
    sharedSchedule.items={}
    local emptyStatus,emptyDetail=Hiring.staffScheduleStatus(scheduleStatusState,scheduleStatusWorker)
    check("employees_staff_panel_reports_empty_shared_schedule_accurately",
        emptyStatus=="No scheduled work" and emptyDetail:find("Add jobs",1,true)~=nil)
    check("employees_contract_has_next_upcoming_shift_and_pay_preview",w.contract.startDay==0
        and Contracts.weeklyEstimate(w.contract)==825 and Contracts.onShift(w.contract,9) and not Contracts.onShift(w.contract,17))
    local snapshot=Schema.snapshot(fresh)
    check("employees_contract_and_resume_round_trip",snapshot and Schema.validState(snapshot)
        and snapshot.employment.staff[1].contract.wageCents==2200 and snapshot.clientEmails.inbox[1].applicationId==a.id)
    local bad=Schema.copy(snapshot);bad.employment.staff[1].contract.wageCents=0/0
    check("employees_malformed_payroll_rejected",not Schema.validState(bad) and Schema.snapshot(bad)==nil)
    local saves=0
    local command=Office.command({state=fresh,save=function() saves=saves+1 end,world={validateNetworkWorkshopAccess=function() return true end}})
    local accepted,code=command.perform({}, {id=2}, {officeIntent={kind="recruit_workers",enabled=false}})
    check("employees_lan_guest_can_change_employment",accepted and code=="completed" and saves==1 and not fresh.employment.recruiting)
    check("employees_owner_can_use_authoritative_office",command.perform({}, {id=1},{officeIntent={kind="recruit_workers",enabled=false}}) and saves==2 and not fresh.employment.recruiting)
    check("employees_invalid_days_and_terms_rejected",Intent.normalize({kind="offer_employee",applicationId=a.id,expectedRevision=1,wageCents=2200,days=0,startHour=9,endHour=17})==nil
        and not Contracts.validTerms(Contracts.terms(2200,31,14,17)))
    local wageState=State.new();local wageWorker=hire(wageState)
    wageWorker.visible=true;wageWorker.clockedIn=true;wageWorker.phase="working"
    Payroll.accrue(wageWorker,8,11)
    wageWorker.phase="break";wageWorker.breakKind="rest";Payroll.accrue(wageWorker,11,11.25)
    wageWorker.breakKind="meal";Payroll.accrue(wageWorker,13,13.5)
    wageWorker.phase="idle";wageWorker.breakKind=nil;Payroll.accrue(wageWorker,14,15)
    Payroll.accrue(wageWorker,17,20)
    check("employees_pay_actual_shift_waiting_and_paid_rest_not_unpaid_meal",Payroll.balance(wageWorker,0,true)==7150 and math.abs(wageWorker.weeks[1].paidHours-3.25)<1e-6)
    wageWorker.visible=false;Payroll.accrue(wageWorker,15,16)
    check("employees_no_wages_without_on_site_clock_in",Payroll.balance(wageWorker,0,true)==7150)
    local finishWorker=hire(State.new())
    finishWorker.visible=true;finishWorker.clockedIn=true;finishWorker.phase="working"
    Payroll.accrue(finishWorker,17,17.25,true)
    check("employees_finishing_safe_cycle_after_shift_is_paid",Payroll.balance(finishWorker,0,true)==550)
    local shortState=State.new();local shortWorker=hire(shortState)
    shortWorker.visible=true;shortWorker.clockedIn=true;shortWorker.phase="idle";shortWorker.breaksTaken=1
    shortWorker.contract.endHour=14
    AI.worker(shortState,shortWorker,.1,13.1,{idlePoint=function(worker) return {x=worker.x,y=worker.y} end})
    check("employees_short_shift_meal_matches_contract_estimate",shortWorker.phase=="idle" and shortWorker.breakKind==nil and Contracts.weeklyEstimate(shortWorker.contract)==550)
    wageWorker.weeks={};wageWorker.visible=true;wageWorker.contract.days=127
    for day=4,9 do Payroll.accrue(wageWorker,day*24+9,day*24+17) end
    check("employees_weekly_overtime_after_40_paid_hours",Payroll.balance(wageWorker,273,true)==114400 and wageWorker.weeks[1].paidHours==48)
    wageState.money=100
    Payroll.pay(wageState,273,true)
    check("employees_partial_pay_keeps_exact_wage_debt",wageState.money==0 and Payroll.balance(wageWorker,273,false)==104400 and Payroll.overdueSince(wageWorker,273)==273)
    wageWorker.status="dismissed";wageState.money=1100
    Payroll.pay(wageState,273,false)
    local remainder=wageState.money
    Payroll.pay(wageState,273,false)
    check("employees_dismissal_does_not_erase_wages_and_payment_no_double_charge",math.abs(remainder-56)<.001 and wageState.money==remainder and Payroll.balance(wageWorker,273,false)==0)
    local expired=State.new();local ew,ea=hire(expired)
    ea.status="offer_accepted";ea.expiresAtHours=3;ea.employeeId=nil
    hours(expired,4);Employees.advance(expired,4)
    check("employees_offer_expiry_is_persisted",ea.status=="expired" and not Employees.command(expired,{kind="hire_employee",applicationId=ea.id,expectedRevision=ea.revision},4))

    local maximum=Codec.array()
    for i=1,4 do maximum[i]=Codec.array({i==4 and "APP-999999" or ("EMP-99999"..i),96000,67800,8,10399,12999,1,9,4,2,1000,0}) end
    local env={sessionId=string.rep("s",64),serverTick=4294967295,bayDoor={state="open",progress=1},
        truck={state="backing",jobId=string.rep("J",64),mode="delivery",backingProgress=.123456789012345,cargoProgress=0},employees=maximum}
    local packet,packetError=Protocol.encode("environment_snapshot",env)
    local decoded=packet and Protocol.decode(packet)
    check("employees_four_npc_realtime_poses_fit_network_packet",decoded and #decoded.payload.employees==4 and #packet<=Protocol.MAX_PACKET_BYTES,tostring(packetError))
    local bad=Schema.copy(maximum);bad[2][1]=bad[1][1]
    check("employees_realtime_poses_reject_duplicate_ids",Pose.normalize(bad)==nil)
    bad=Schema.copy(maximum);bad[1][1]="1"
    check("employees_realtime_npc_ids_cannot_alias_players",Pose.normalize(bad)==nil)
    bad=Schema.copy(maximum);bad[1][2]=96001;env.employees=bad
    check("employees_realtime_poses_reject_out_of_world_coordinates",Pose.normalize(bad)==nil and Protocol.encode("environment_snapshot",env)==nil)
    local poseState=State.new();local poseWorker,poseApplication=hire(poseState)
    poseWorker.visible=true;poseWorker.moving=true;poseWorker.phase="walking"
    poseWorker.x=601.234;poseWorker.y=410.678;poseWorker.intentX=-1;poseWorker.intentY=-1
    poseWorker.distance=201.2;poseWorker.idleClock=0
    local rows=Pose.capture(Employees.actors(poseState))
    local poses=rows and Pose.actors(rows)
    local guestState=State.new()
    check("employees_guest_initial_shared_state_loads",State.applySharedSnapshot(guestState,Schema.snapshot(poseState)))
    guestState._employeePoses=poses
    local entry=Employees.actors(guestState)[1]
    check("employees_guest_renders_host_pose_and_authored_facing",entry and entry.actor.moving and math.abs(entry.actor.x-601.23)<.001 and Renderer.pose(entry)=="walk_northwest")
    check("employees_durable_updates_preserve_newer_realtime_pose",State.applySharedUpdate(guestState,Schema.snapshot(poseState)) and Employees.actors(guestState)[1].actor==poses[poseWorker.id])
    guestState._employeePoses=assert(Pose.actors(Codec.array()))
    check("employees_empty_realtime_snapshot_hides_departed_npcs",#Employees.actors(guestState)==0)
    check("employees_new_shop_snapshot_clears_stale_realtime_ids",State.applySharedSnapshot(guestState,Schema.snapshot(poseState)) and guestState._employeePoses==nil)

    -- Use the actual cutter domain, all four trims, two lifts and pallet output.
    local production=State.new();local operator=hire(production)
    local job=assert(Jobs.createOffer({id="JOB-EMPLOYEE-CUT",company="Employee cutter test",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={1000}}))
    Jobs.accept(job);production.jobs.active[1]=job
    context.PalletLogistics.unload(production,job.id,job.pallets[1].id,context.config.palletLogistics.spawnPoints,context.config.palletLogistics.unloadOrigin)
    local pallet=job.pallets[1]
    local machine=Fleet.installedUnits(production,"polar_115")[1]
    context.machine.reset(production)
    operator.cutterSkill,operator.pressSkill,operator.wrappingSkill=1,0,0
    local assign={kind="assign_employee",employeeId=operator.id,jobId=job.id,palletId=pallet.id,machineId=machine.id}
    job.difficulty="hard"
    local lowSkillRejected=not Employees.command(production,assign,2) and operator.assignment==nil
    operator.cutterSkill,operator.pressSkill,operator.wrappingSkill=80,60,70
    check("employees_require_skill_for_hard_cutter_jobs",
        lowSkillRejected and Employees.command(production,assign,2) and operator.assignment.jobId==job.id)
    check("employees_lower_skill_increases_machine_action_time",
        Labor.actionDelay({cutterSkill=1,focus=100},100)
            > Labor.actionDelay({cutterSkill=100,focus=100},100))
    local available=false
    local wc={canClaim=function() return available end,operatorPoint=function() return {x=700,y=470} end,
        move=function(worker,goal) worker.x,worker.y=goal.x,goal.y;worker.moving=false;return true end}
    pallet.world.x,pallet.world.y=450,490
    Work.update(production,operator,.1,wc)
    check("employees_do_not_claim_human_controlled_cutter_for_transfer",not operator.reserved
        and operator.assignment~=nil and operator.activity=="Waiting for the player to release this machine")
    local ix,iy=context.CutterZones.inputAnchor(production,context.config.cutterPlacement)
    pallet.world.x,pallet.world.y=ix,iy;pallet.world.fromX,pallet.world.fromY=ix,iy;pallet.world.spawnProgress=1
    Work.update(production,operator,1,wc)
    check("employees_never_override_human_machine_lease",not operator.reserved and context.machine.forId(machine.id).step=="idle")
    available=true;operator.visible=true;operator.clockedIn=true
    local m=context.machine.forId(machine.id)
    local priorResolver=m.outputResolver
    local clearOutput=false
    m.setOutputResolver(function() if clearOutput then return {x=ix+92,y=iy+60,direction="northwest"} end return nil,"Blocked output" end)
    m.setMultiplayerSingleControl(true)
    local sawBoth,sawBusy,sawCheckpoint=false,false,false
    for i=1,800 do
        Work.update(production,operator,.1,wc)
        if m.step=="armed" or m.step=="cutting" then
            sawBoth=sawBoth or (m.leftDown and m.rightDown)
            sawBusy=sawBusy or not Work.release(production,operator)
        end
        context.machine.updateAll(.1,production)
        if pallet.completedLifts==1 and m.step=="repeat_ready" then
            local saved=Schema.snapshot(production)
            sawCheckpoint=saved and Schema.validState(saved) and saved.jobs.active[1].pallets[1].completedLifts==1
        end
        if pallet.completedLifts==2 and m.step=="cut_complete" then break end
    end
    check("employees_use_both_safety_controls_even_in_multiplayer",sawBoth and sawBusy)
    check("employees_completed_lift_is_saved_at_safe_checkpoint",sawCheckpoint)
    check("employees_real_cutter_finishes_all_cuts_and_lifts",pallet.completedLifts==2 and pallet.finishedSheets==1000 and pallet.remainingSheets==0 and not pallet.paper.offSpec, m.step.." "..tostring(operator.activity))
    Work.update(production,operator,1,wc)
    check("employees_blocked_output_preserves_finished_stock",m.step=="cut_complete" and pallet.location=="at_cutter" and pallet.finishedSheets==1000 and operator.assignment~=nil)
    clearOutput=true
    for i=1,800 do
        Work.update(production,operator,.1,wc);context.machine.updateAll(.1,production)
        if pallet.location=="cutter_output" and pallet.status=="cut" then break end
    end
    -- The machine publishes its completed-pallet state after the worker's
    -- update, so let the worker observe that authoritative stage transition.
    Work.update(production,operator,.1,wc)
    local wrapStage=Schedule.stage(job,pallet)
    check("employees_trained_worker_resolves_wrapper_work_without_training_gate",
        wrapStage=="wrapping" and Schedule.skillAllows(operator,job,wrapStage),tostring(wrapStage))
    check("employees_real_output_returns_once_without_wrap_training_block",pallet.location=="cutter_output"
        and pallet.status=="cut" and production.inventory.finishedPallets==1 and operator.assignment~=nil
        and operator.activity~="Pallet-wrapping training required before shipping")
    local cutterAwards=job.employeeSkillAwards and job.employeeSkillAwards.cutter or {}
    check("employees_gain_one_cutter_skill_point_per_job",operator.cutterSkill==81
        and #cutterAwards==1 and cutterAwards[1]==operator.id,
        "skill="..tostring(operator.cutterSkill).." awards="..tostring(#cutterAwards)
            .." first="..tostring(cutterAwards[1]).." worker="..tostring(operator.id))
    local skillSnapshot=Schema.snapshot(production)
    local skillGuest=State.new()
    local skillSynced=skillSnapshot and State.applySharedSnapshot(skillGuest,skillSnapshot)
    local mirroredWorker=skillSynced and skillGuest.employment.staff[1]
    local mirroredAwards=skillSynced and skillGuest.jobs.active[1].employeeSkillAwards
    check("employees_cutter_skill_progress_replicates_in_multiplayer_snapshot",
        mirroredWorker and mirroredWorker.cutterSkill==81 and mirroredAwards
        and mirroredAwards.cutter and mirroredAwards.cutter[1]==operator.id)
    m.setOutputResolver(priorResolver);context.machine.reset(production);context.machine.setMultiplayerSingleControl(false)

    local pressState=State.new();pressState.money=1000000
    assert(Fleet.buy(pressState,"dealer",3))
    local pressWorker=hire(pressState)
    pressWorker.pressSkill=60;pressWorker.visible=true;pressWorker.clockedIn=true;pressWorker.phase="working"
    local pressJob=assert(Jobs.createOffer({id="JOB-EMPLOYEE-PRESS-SKILL",company="Employee press skill test",
        sourceSize={width=10,height=15},finishedSize={width=5,height=7},sheetCounts={1050},
        artworkKey="ad-photos",artwork={key="ad-photos",displayName="Client Photo Card",
            fileName="client-photo-card.png",suppliedBy="client",orientation="portrait"},
        stockSpec={suppliedBy="client",grade="cover",weight=80,finish="uncoated",color="white",
            grain="long",description="80 lb white uncoated cover"},
        press={colors=1,coverage=.35,artworkSize={width=4.25,height=6.25},
            colorSequence={"Black"},requestedCopies={1000}}}))
    Jobs.accept(pressJob);pressState.jobs.active[1]=pressJob
    context.PalletLogistics.unload(pressState,pressJob.id,pressJob.pallets[1].id,
        context.config.palletLogistics.spawnPoints,context.config.palletLogistics.unloadOrigin)
    local pressPallet=pressJob.pallets[1]
    pressPallet.status="printed";pressPallet.location="press_output"
    pressPallet.press.status="complete";pressPallet.press.completedColors=1
    local pressMachine=Fleet.installedUnits(pressState,"heidelberg_10x15")[1]
    pressWorker.assignment={jobId=pressJob.id,palletId=pressPallet.id,
        machineId=pressMachine.id,machineModel=pressMachine.modelId}
    local pressSkillBefore=pressWorker.pressSkill
    local pressWorkContext={canClaim=function() return true end,
        operatorPoint=function(_,worker) return {x=worker.x,y=worker.y} end,
        palletApproachPoint=function(pallet) return {x=pallet.world.x,y=pallet.world.y} end,
        move=function(worker,goal) worker.x,worker.y=goal.x,goal.y;return true end}
    Work.update(pressState,pressWorker,.1,pressWorkContext)
    local pressAwards=pressJob.employeeSkillAwards and pressJob.employeeSkillAwards.press or {}
    check("employees_gain_printing_skill_after_press_job_completes",
        pressWorker.pressSkill==pressSkillBefore+1 and #pressAwards==1
        and pressAwards[1]==pressWorker.id)

    -- Exercise the actual computer dropdown and every Hiring page with real UI.
    local screen=context.computerScreen.new()
    screen.enter(fresh)
    local x,y=screen.dropdownCenter();screen.mousepressed(fresh,x,y,1)
    x,y=screen.tabCenter("hiring")
    check("employees_hiring_tab_visible_and_selectable",x and screen.mousepressed(fresh,x,y,1).action=="tab" and screen.tab=="hiring")
    local function draw(name)
        love.graphics.push("all")
        local okay,err=pcall(screen.draw,fresh,nil,nil,context.assets)
        love.graphics.pop()
        check(name,okay,tostring(err))
    end
    screen.hiring.section="applications";screen.hiring.selectedId=a.id;draw("employees_hiring_resume_draws")
    screen.hiring.view="offer";screen.hiring.terms=Contracts.terms(2200,31,9,17);draw("employees_hiring_offer_draws")
    screen.hiring.section="staff";screen.hiring.view="detail";screen.hiring.selectedId=w.id;draw("employees_hiring_staff_draws")
    screen.hiring.view="assignment";draw("employees_hiring_assignment_draws")
    screen.hiring.section="payroll";screen.hiring.view="detail";draw("employees_hiring_payroll_draws")
    screen.openEmploymentResume(a.id)
    check("employees_email_attachment_opens_exact_application",screen.tab=="hiring" and screen.hiring.selectedId==a.id)
    local guestIntents={}
    local guest=context.computerScreen.new({remoteCommand=function(intent) guestIntents[#guestIntents+1]=intent end})
    guest.tab="hiring";guest.hiring.section="applications"
    local before=fresh.employment.recruiting
    x,y=Hiring.buttonCenter("recruit")
    check("employees_guest_hiring_ui_submits_recruitment",guest.mousepressed(fresh,x,y,1).action=="remote_pending"
        and guestIntents[1] and guestIntents[1].kind=="recruit_workers" and fresh.employment.recruiting==before)
    context.characterAssets.retainCharacters({})
    local dirs={east={1,0},northeast={1,-1},north={0,-1},northwest={-1,-1},west={-1,0},southwest={-1,1},south={0,1},southeast={1,1}}
    for dir,v in pairs(dirs) do
        local act=Animation.authoredAction("walk",v[1],v[2])
        local im,quad,count=context.characterAssets.get("cat-worker",act,1)
        local _,_,qw,qh=quad:getViewport()
        check("employees_cat_authored_direction_"..dir,Animation.authoredDirection(v[1],v[2])==dir and im and count==8 and qw==256 and qh==256)
        local idle=Animation.authoredAction("idle",v[1],v[2]);context.characterAssets.get("cat-worker",idle,1)
        context.characterAssets.get("cat-worker","operate_"..dir,4)
    end
    context.characterAssets.get("cat-worker","rest_east",2);context.characterAssets.get("cat-worker","rest_west",2)
    check("employees_cat_texture_pack_below_32_mib",context.characterAssets.textureBytes()<=32*1048576 and context.characterAssets.anchorPixelScans()==0)
    local blocked={actor={moving=false,intentX=-1,intentY=0,distance=200,idleClock=0,phase="idle"},worker=true}
    local action=Renderer.pose(blocked,context.characterAssets)
    check("employees_blocked_or_idle_keeps_last_authored_facing",action=="idle_west")
    context.characterAssets.retainCharacters({})
end
return Test
