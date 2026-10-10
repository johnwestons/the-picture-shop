local State=require("src.state")
local Employees=require("src.employees")
local Jobs=require("src.jobs")
local Fleet=require("src.machine_fleet")
local Jack=require("src.pallet_jack")
local Transport=require("src.employee_pallet_jack")
local Schedule=require("src.employee_schedule")
local Speech=require("src.employee_speech")
local Pose=require("src.employee_pose")
local Catalog=require("src.worker_catalog")
local Renderer=require("src.employee_renderer")
local Customer=require("src.customer")
local Config=require("src.config")
local AI=require("src.employee_ai")
local Schema=require("src.save_schema")
local Navigation=require("src.navigation")
local Footprint=require("src.floor_footprint")
local Protocol=require("src.net.protocol")
local Test={}

local function capture(context,state,name)
    local root=os.getenv("PICTURE_SHOP_EMPLOYEE_CAPTURE_DIR")
    if not root then
        if love.filesystem.getSource():match("%.love$") then return end
        root=love.filesystem.getSource().."/output/employee-motion-v2"
    end
    local canvas=love.graphics.newCanvas(Config.baseWidth,Config.baseHeight)
    love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.08,.09,.10,1)
    require("src.world_renderer").draw(context.world,context.assets,context.characterAssets,state,nil,nil,{})
    love.graphics.pop()
    local pixels=canvas:newImageData();local png=pixels:encode("png")
    local file=assert(io.open(root.."/"..name..".png","wb"))
    file:write(png:getString());file:close();png:release();pixels:release();canvas:release()
end

local function hire(state)
    local applicant=Employees.createApplicant(state,0)
    Employees.requestResume(state,applicant.id,0);Employees.advance(state,.5)
    assert(Employees.command(state,{kind="offer_employee",applicationId=applicant.id,
        expectedRevision=applicant.revision,wageCents=math.max(2400,applicant.requestedWage),
        days=31,startHour=9,endHour=17},.5))
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=applicant.id,expectedRevision=applicant.revision},1.25))
    local worker=state.employment.staff[#state.employment.staff]
    worker.visible,worker.clockedIn,worker.phase=true,true,"idle"
    worker.x,worker.y,worker.cutterSkill,worker.pressSkill,worker.wrappingSkill=600,560,100,100,100
    return worker
end
local function job(state,id,x,y)
    local result=assert(Jobs.createOffer({id=id,company="Transport QA",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500}}))
    Jobs.accept(result);state.jobs.active[#state.jobs.active+1]=result
    result.status="in_production";result.delivery={status="received"}
    local pallet=result.pallets[1]
    pallet.location,pallet.status="warehouse","raw"
    pallet.world={x=x,y=y,fromX=x,fromY=y,spawnProgress=1,direction="northwest"}
    return result,pallet
end
function Test.run(context,check)
    local state=State.new();local worker=hire(state)
    local machine=Fleet.installedUnits(state,"polar_115")[1]
    local first,pallet=job(state,"JOB-EMPLOYEE-JACK",350,550)
    local entry={worker=worker,actor=worker}
    for _,profile in ipairs(Catalog.profiles) do
        worker.character=profile.character;worker.phase="break";worker.seatBay="front_left"
        worker.moving=false;worker.breakRemaining=.3;worker.idleClock=1;worker.breakKind="meal"
        local action,frame,mirror=Renderer.pose(entry,context.characterAssets)
        local image,_,count=context.characterAssets.get(worker.character,action,frame)
        check("employee_chair_pose_"..profile.character,image and action=="break_eat"
            and count==4 and frame==2 and mirror==-1)
        worker.seatBay=nil;worker.phase="pushing";worker.intentX,worker.intentY=-1,-1
        worker.jackDistance=20;worker.moving=true
        local pushing,pushFrame,mirror=Renderer.pose(entry,context.characterAssets)
        check("employee_directional_push_"..profile.character,pushing=="push_northeast" and pushFrame==3 and mirror==-1)
        worker.moving=false
        local _,stopped=Renderer.pose(entry,context.characterAssets)
        check("employee_stopped_push_plants_feet_"..profile.character,stopped==2)
        worker.phase="working";worker.training={skill="press"};worker.idleClock=.75
        local operating,workFrame=Renderer.pose(entry,context.characterAssets)
        check("employee_training_uses_machine_animation_"..profile.character,operating=="work_press" and workFrame==4)
        worker.training=nil
    end
    worker.character="cat-worker";worker.phase="idle"
    for _,character in ipairs({"tan-cat","blue-coaler-cat","green-blazer-cat"}) do
        local visitor=Customer.new(Config.vendor);visitor.character=character;visitor.state="waiting"
        local action=visitor:poseAction(context.characterAssets)
        check("salesman_uses_existing_chair_pose_"..character,visitor.seat and action=="sit" and context.characterAssets.get(character,action,1)~=nil)
    end
    local reception=context.world.employeeContext(State.new(),context.assets)
    for seatIndex=1,#Config.vendor.seatSpots do
        local visitor=Customer.new(Config.vendor)
        for _=2,seatIndex do visitor:reset(true) end
        visitor.timer=0
        for _=1,1200 do
            visitor:update(.1,{x=930,y=640},false,.1,reception)
            if visitor.state=="waiting" then break end
        end
        check("salesman_navigates_to_reception_seat_"..seatIndex,visitor.state=="waiting"
            and visitor:poseAction(context.characterAssets)=="sit","phase="..visitor.state.." routeBlocked="..tostring(visitor.routeBlocked))
    end
    context.machine.reset(state)
    assert(Employees.command(state,{kind="queue_employee_job",employeeId=worker.id,jobId=first.id,machineId=machine.id},9))
    assert(Jack.mount(state,Config.palletJack,1))
    Schedule.advance(state,worker,9)
    check("employee_requests_player_held_jack_without_stealing",not worker.assignment
        and Speech.code(entry)==27 and state.palletJack.operatorPlayerId==1 and not Jack.mountEmployee(state,Config.palletJack,worker.id),
        "activity="..tostring(worker.activity).." speech="..Speech.code(entry).." assignment="..tostring(worker.assignment))
    local x,y=context.CutterZones.inputAnchor(state,Config.cutterPlacement)
    local ready=job(state,"JOB-JACK-ALTERNATIVE",x,y)
    assert(Employees.command(state,{kind="queue_employee_job",employeeId=worker.id,jobId=ready.id,machineId=machine.id},9))
    worker._scheduleRetryAtHours=nil
    Schedule.advance(state,worker,9.1)
    check("employee_skips_jack_task_for_ready_work",worker.assignment and worker.assignment.jobId==ready.id)
    worker.assignment=nil;worker.schedule.items={};worker._scheduleRetryAtHours=nil
    assert(Employees.command(state,{kind="queue_team_job",jobId=first.id,machineId=machine.id},9.1))
    Schedule.advance(state,worker,9.2)
    check("shared_schedule_requests_held_jack_when_no_work_ready",not worker.assignment and Speech.code(entry)==27)
    Jack.forceRelease(state,Config.palletJack,1)
    local oldX,oldY=context.world.player.x,context.world.player.y
    context.world.player.x,context.world.player.y=930,640
    local oldOptions=context.world._employeeOptions
    context.world.configureEmployees({players=function() return {} end})
    local ctx=context.world.employeeContext(state,context.assets)
    ctx.move=function(actor,goal,dt) return AI.move(actor,goal,dt,ctx) end
    worker.assignment={jobId=first.id,palletId=pallet.id,machineId=machine.id,machineModel=machine.modelId}
    worker.reserved=true
    local lifted,delivered,collisionSafe=false,false,true
    local blockedDropDetail
    local startX,startY=state.palletJack.x,state.palletJack.y
    for _=1,2200 do
        Transport.update(state,worker,machine,pallet,"cutter",.1,ctx)
        if worker.activity=="Clear floor beside the cutter is blocked" then
            local dropX,dropY=Jack.dropPosition(state,Config.palletJack)
            local target=worker._jackTarget and worker._jackTarget.goal
            blockedDropDetail=string.format("%s jack=%.1f,%.1f facing=%s target=%s drop=%.1f,%.1f clear=%s inZone=%s",
                worker.activity,state.palletJack.x,state.palletJack.y,state.palletJack.direction,
                target and string.format("%.1f,%.1f",target.x,target.y) or "nil",dropX,dropY,
                tostring(ctx.jackDropClear(worker,pallet.id,dropX,dropY)),
                tostring(context.CutterZones.inInputZone(state,{world={x=dropX,y=dropY}},Config.cutterPlacement)))
        end
        if pallet.location=="on_pallet_jack" then
            lifted=true
            local nav=ctx.jackNavigation(worker,pallet.id)
            collisionSafe=collisionSafe and Navigation.isWalkable(nav.assets,state.palletJack.x,state.palletJack.y,nav.obstacles())
        elseif lifted and pallet.location=="warehouse" then delivered=true;break end
    end
    context.world.player.x,context.world.player.y=oldX,oldY
    context.world.configureEmployees(oldOptions)
    check("employee_walks_to_real_jack_and_lifts_reserved_pallet",lifted and not worker.carryingPalletId,
        worker.activity.." jack="..state.palletJack.x..","..state.palletJack.y)
    check("employee_loaded_jack_routes_and_lowers_in_machine_zone",delivered and collisionSafe
        and context.CutterZones.inInputZone(state,pallet,Config.cutterPlacement)
        and not state.palletJack.carriedPalletId
        and (startX~=state.palletJack.x or startY~=state.palletJack.y),blockedDropDetail or worker.activity)
    local Work=require("src.employee_work")
    context.world.player.x,context.world.player.y=930,640
    for _=1,600 do
        Work.update(state,worker,.1,ctx)
        if worker.phase=="working" then break end
    end
    check("employee_parks_jack_then_reaches_real_machine_operator",worker.phase=="working"
        and not state.palletJack.operating and pallet.location=="warehouse",worker.activity)
    worker.idleClock=.75;state.screen="world"
    for _,profile in ipairs(Catalog.profiles) do
        worker.character=profile.character
        capture(context,state,profile.character.."-working-in-game")
    end
    context.world.player.x,context.world.player.y=oldX,oldY
    -- The jack has parked away from the cutter; position it at this skid for
    -- the independent loaded-jack network snapshot fixture below.
    state.palletJack.x,state.palletJack.y=pallet.world.x,pallet.world.y
    assert(Jack.mountEmployee(state,Config.palletJack,worker.id))
    assert(Jack.lift(state,Config.palletJack,pallet.id))
    worker.phase="pushing";worker.moving=true;worker.jackDistance=125;worker.idleClock=0
    local snapshot=context.world.networkPalletJackSnapshot(state)
    local machines=context.world.networkMachinePoseSnapshot(state)
    local packet,errorMessage=Protocol.encode("pallet_jack_snapshot",{sessionId="employee-jack-test",serverTick=1,jack=snapshot,machines=machines})
    local decoded=packet and Protocol.decode(packet)
    check("employee_jack_owner_round_trips_protocol",decoded and decoded.payload.jack.operatorEmployeeId==worker.id,errorMessage)
    snapshot.operatorPlayerId=1
    check("employee_jack_protocol_rejects_dual_ownership",not Protocol.encode("pallet_jack_snapshot",{sessionId="employee-jack-test",serverTick=2,jack=snapshot,machines=machines}))
    local rows=Pose.capture({entry});local actors=Pose.actors(rows)
    check("employee_push_gait_survives_guest_pose",actors and actors[worker.id].phase=="pushing" and actors[worker.id].jackDistance==125)
    local maximum=require("src.net.codec").array()
    for i=1,11 do maximum[i]=require("src.net.codec").array({"EMP-9999"..string.format("%02d",i),96000,67800,8,15999,12999,1,10,4,2,1000,28}) end
    local rosterPacket,rosterError=Protocol.encode("employee_snapshot",{sessionId=string.rep("s",64),serverTick=4294967295,employees=maximum})
    check("full_employee_roster_and_push_poses_fit_network_packet",rosterPacket and #rosterPacket<=Protocol.MAX_PACKET_BYTES,rosterError)
    local Session=require("src.net.session")
    local client=Session.new();client.mode="client";client.ready=true;client.sessionId=string.rep("s",64)
    client:_handleClientEnvelope(assert(Protocol.decode(rosterPacket)))
    local events=client:drainEvents()
    local employeeEvent=events[1]
    local guest=State.new()
    check("guest_receives_all_employee_poses_and_speech",employeeEvent and employeeEvent.type=="employee_state"
        and context.world.applyEmployeeSnapshot(employeeEvent.employees,guest) and guest._employeePoses[maximum[11][1]].speechCode==28)
    client:_handleClientEnvelope(assert(Protocol.decode(rosterPacket)))
    check("guest_discards_stale_employee_pose_packet",#client:drainEvents()==0)
    local host=Session.new();host.mode="host";host.sessionId=string.rep("s",64);host.idToPeer[2]="employee-test-peer"
    local packets={}
    host._broadcastJoined=function(_,kind,payload)
        local packet,err=Protocol.encode(kind,payload)
        assert(packet,err);packets[kind]=payload;return true
    end
    host:_updateHost(.1,{getEnvironmentSnapshot=function() return {bayDoor={state="open",progress=1},
        truck={state="absent",backingProgress=0,cargoProgress=0},employees=maximum} end})
    check("host_sends_large_staff_roster_separately_from_truck_and_door",packets.employee_snapshot
        and #packets.employee_snapshot.employees==11 and packets.environment_snapshot and not packets.environment_snapshot.employees)
    local saved=Schema.snapshot(state)
    check("save_parks_employee_jack_without_losing_pallet",saved and saved.palletJack.carriedPalletId==pallet.id
        and not saved.palletJack.operating and not saved.palletJack.operatorEmployeeId and not saved.palletJack.operatorPlayerId)
    local previousScene=context.world.player.sceneId
    state.screen="world"
    for _,profile in ipairs(Catalog.profiles) do
        worker.character=profile.character
        capture(context,state,profile.character.."-pushing-in-game")
    end
    Transport.release(state,worker,{jackEmergencyDropPoint=function() return nil end})
    check("blocked_emergency_drop_parks_loaded_jack_safely",not state.palletJack.operating
        and pallet.location=="on_pallet_jack" and state.palletJack.carriedPalletId==pallet.id)
    state.warehouse.bays.front_left.optionId="breakroom";state.warehouse.bays.front_left.status="complete"
    context.world.player.sceneId="front_left"
    worker.phase,worker.seatBay,worker.moving,worker.idleClock="break","front_left",false,1
    worker.breakRemaining=.3
    for _,profile in ipairs(Catalog.profiles) do
        worker.character=profile.character
        capture(context,state,profile.character.."-seated-in-game")
    end
    context.world.player.sceneId=previousScene
    worker.phase,worker.seatBay,worker.moving="idle",nil,false
    for _,stage in ipairs({"wrapping","press"}) do
        state.money=1000000
        local model=stage=="press" and "heidelberg_10x15" or "skid_wrapper"
        if #Fleet.installedUnits(state,model)==0 then assert(Fleet.buy(state,"dealer",stage=="press" and 3 or 2)) end
        local destination=assert(Fleet.installedUnits(state,model)[1])
        worker.assignment.machineId,worker.assignment.machineModel=destination.id,model
        local oldPX,oldPY=context.world.player.x,context.world.player.y
        context.world.player.x,context.world.player.y=930,640
        local transportContext=context.world.employeeContext(state,context.assets)
        transportContext.move=function(actor,goal,dt) return AI.move(actor,goal,dt,transportContext) end
        local lowered,wrapperDropValid,blockedTransportDetail,wrapperDropDetail=false,stage~="wrapping",nil,nil
        for _=1,1800 do
            if worker._parkingJack then Transport.park(state,worker,.1,transportContext)
            else Transport.update(state,worker,destination,pallet,stage,.1,transportContext) end
            if worker.activity=="Clear floor beside the skid wrapper is blocked" then
                local dropX,dropY=Jack.dropPosition(state,Config.palletJack)
                local target=worker._jackTarget and worker._jackTarget.goal
                blockedTransportDetail=string.format("%s jack=%.1f,%.1f facing=%s target=%s drop=%.1f,%.1f clear=%s",
                    worker.activity,state.palletJack.x,state.palletJack.y,state.palletJack.direction,
                    target and string.format("%.1f,%.1f",target.x,target.y) or "nil",dropX,dropY,
                    tostring(transportContext.jackDropClear(worker,pallet.id,dropX,dropY)))
            end
            if pallet.location=="warehouse" and not state.palletJack.operating then
                if stage=="wrapping" then
                    local wrapperPose=destination.world or require("src.wrapper_placement").ensure(state,Config.wrapperPlacement)
                    local wrapperFootprint=Footprint.at(wrapperPose.x,wrapperPose.y,Config.wrapperPlacement)
                    local skidFootprint=Footprint.at(pallet.world.x,pallet.world.y,Config.palletLogistics)
                    local spacing=Footprint.distanceSquared(wrapperFootprint,skidFootprint)
                    wrapperDropValid=spacing>0 and spacing<=Config.wrapperPlacement.palletReach^2
                    wrapperDropDetail=string.format("facing=%s skid=%.1f,%.1f wrapper=%.1f,%.1f spacing=%.1f reach=%.1f",
                        tostring(pallet.world.direction),pallet.world.x,pallet.world.y,wrapperPose.x,wrapperPose.y,
                        math.sqrt(spacing),Config.wrapperPlacement.palletReach)
                end
                lowered=true;break
            end
        end
        check("employee_delivers_real_jack_to_"..stage,lowered and wrapperDropValid,
            wrapperDropDetail or blockedTransportDetail or worker.activity)
        context.world.player.x,context.world.player.y=oldPX,oldPY
    end
    state.palletJack.x,state.palletJack.y=pallet.world.x,pallet.world.y
    assert(Jack.mountEmployee(state,Config.palletJack,worker.id))
    assert(Jack.lift(state,Config.palletJack,pallet.id))
    worker.weeks={{week=-3,dueAtHours=0,paidHours=1,earnedCents=2400,paidCents=0,notified=false}}
    worker.phase="pushing";worker.breaksTaken=7
    AI.worker(state,worker,.1,9,{jackEmergencyDropPoint=function() return nil end})
    check("employee_waiting_for_pay_releases_loaded_jack",not state.palletJack.operating
        and pallet.location=="on_pallet_jack" and not worker.reserved and Speech.code(entry)==21)
    context.machine.reset(state)
end
return Test
