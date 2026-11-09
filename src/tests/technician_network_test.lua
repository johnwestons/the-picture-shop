local Pose=require("src.technician_pose")
local Replica=require("src.technician_replica")
local Technician=require("src.technician")
local Protocol=require("src.net.protocol")
local Session=require("src.net.session")
local Codec=require("src.net.codec")
local State=require("src.state")
local Schema=require("src.save_schema")
local Test={}
local function environment(technician,tick)
    return {sessionId="technician-motion",serverTick=tick or 1,
        bayDoor={state="closed",progress=0},truck={state="absent",backingProgress=0,cargoProgress=0},technician=technician}
end
local function row(distance,x,moving)
    return Codec.array({1,1,math.floor((x or 500)*100+.5),55500,8,
        math.floor((distance or 17.25)*100),0,140,moving==false and 0 or 1})
end
local function same(a,b) return math.abs(a-b)<.0001 end

local function wire(check)
    local visit={visible=true,status="entering",species="mouse",x=500.25,y=555.5,
        intentX=-1,intentY=-1,animationDistance=225.25,idleClock=0,animationClock=.14,inMotion=true}
    local captured=Pose.capture(visit)
    local actor=Pose.actor(captured)
    check("technician_pose_round_trip_retains_phase_and_achieved_facing",actor and actor.inMotion
        and same(actor.animationDistance,17.25) and actor.intentX==-1 and actor.intentY==-1
        and same(actor.x,500.25) and same(actor.y,555.5))
    local packet,err=Protocol.encode("environment_snapshot",environment(captured))
    local decoded=packet and Protocol.decode(packet)
    check("technician_pose_round_trips_environment_wire",decoded and #decoded.payload.technician==9
        and #packet<=Protocol.MAX_PACKET_BYTES,err)
    check("technician_absence_is_explicit_on_wire",#Pose.capture(nil)==0
        and Pose.actor(Pose.capture(nil))==false and #Pose.capture({visible=false})==0)
    local invalid=true
    for _,change in ipairs({function(t)t[2]=2;t[9]=1 end,function(t)t[3]=1000001 end,
        function(t)t[6]=10400 end,function(t)t[7]=3077 end,function(t)t[8]=16000 end,
        function(t)t[5]=0 end,function(t)t[9]=2 end,function(t)t[1]=1.5 end,
        function(t)t[4]=0/0 end,function(t)t[10]=1 end,function(t)t.money=1 end,
        function(t)t[7]=nil end}) do
        local bad=row();change(bad)
        invalid=invalid and Pose.normalize(bad)==nil and not Protocol.encode("environment_snapshot",environment(bad))
    end
    check("technician_wire_rejects_invalid_sparse_or_authoritative_fields",invalid)
    local maximum=environment(Codec.array({2,3,1000000,-1000000,8,10399,3076,15999,1}),4294967295)
    maximum.sessionId=string.rep("s",64);maximum.employees=Codec.array()
    maximum.roomDoors={front_left={state="opening",progress=.9999999999999999},
        front_right={state="closing",progress=.1111111111111111}}
    maximum.truck={state="cargo_opening",jobId=string.rep("j",64),mode="pickup",sceneId="front_right",
        backingProgress=1,cargoProgress=.1111111111111111}
    for i=1,4 do maximum.employees[i]=Codec.array({"EMP-999999999"..i,96000,67800,8,15999,12999,1,10,124,2,1000,28}) end
    local largest,largestError=Protocol.encode("environment_snapshot",maximum)
    check("technician_plus_four_employee_poses_fit_existing_packet_ceiling",largest and #largest<=Protocol.MAX_PACKET_BYTES,largestError)
end

local function presentation(check)
    local state=State.new()
    Replica.accept(state,assert(Pose.actor(row(103.5,500))))
    Replica.accept(state,assert(Pose.actor(row(2.5,503))))
    Replica.update(state,Replica.DURATION/2)
    local actor=Technician.presentation(state)
    check("technician_guest_position_and_stride_interpolate_together_through_loop_seam",
        same(actor.x,501.5) and same(actor.animationDistance,105))
    Replica.update(state,Replica.DURATION/2)
    check("technician_guest_reaches_latest_achieved_position",same(actor.x,503) and same(actor.animationDistance,106.5))
    local frozen=actor.animationDistance
    Replica.update(state,1)
    check("technician_guest_does_not_invent_steps_during_a_packet_gap",same(actor.animationDistance,frozen) and same(actor.x,503))
    Replica.accept(state,assert(Pose.actor(row(2.5,503,false))))
    Replica.update(state,.2)
    actor=Technician.presentation(state)
    check("technician_guest_blocked_update_stops_gait_and_keeps_last_direction",not actor.inMotion
        and same(actor.animationDistance,frozen) and actor.intentX==1 and actor.intentY==-1 and actor.idleClock>0)
    actor.animationDistance=104.00000001
    Replica.accept(state,assert(Pose.actor(row(0,503,false))))
    Replica.update(state,Replica.DURATION)
    check("technician_replica_rounding_cannot_create_an_extra_stride",state._technicianPose.animationDistance<104.01)
    state.technicianVisit={visible=true,status="servicing",species="mouse",x=503,y=555}
    Replica.accept(state,false)
    check("technician_empty_pose_hides_a_stale_durable_visit",Technician.presentation(state)==nil)
    state._technicianPose={x=500}
    check("technician_new_shared_shop_clears_old_realtime_pose",State.applySharedSnapshot(state,Schema.snapshot(State.new()))
        and state._technicianPose==nil)
end

local function delivery(context,check)
    local client=Session.new();client.mode="client";client.ready=true;client.sessionId="technician-motion"
    local host=Session.new();host.mode="host";host.sessionId=client.sessionId;host.idToPeer[2]="technician-peer"
    local sent={}
    host._broadcastJoined=function(_,kind,payload)
        local packet,err=Protocol.encode(kind,payload);assert(packet,err)
        sent[kind]=packet
        return true
    end
    host:_updateHost(.1,{getEnvironmentSnapshot=function() return environment(row(17.25,500),1) end})
    local envelope=sent.environment_snapshot and Protocol.decode(sent.environment_snapshot)
    check("host_emits_technician_motion_without_a_durable_shop_update",envelope and envelope.payload.technician[6]==1725)
    local guest=State.new()
    local runtime={state=guest,multiplayer=client,World=context.world,
        showConnectionError=function(message) error(message) end}
    require("src.runtime.multiplayer_events").install(runtime)
    local previous=context.world.environmentSnapshot()
    client:_handleClientEnvelope(envelope)
    runtime.handleMultiplayerEvents()
    check("guest_application_applies_realtime_technician_motion",guest._technicianPose
        and same(guest._technicianPose.x,500) and same(guest._technicianPose.animationDistance,17.25)
        and guest.technicianVisit==nil)
    local stale=assert(Protocol.decode(assert(Protocol.encode("environment_snapshot",environment(row(4,100),envelope.payload.serverTick-1)))))
    client:_handleClientEnvelope(stale)
    check("guest_discards_reordered_technician_motion",#client:drainEvents()==0 and same(guest._technicianPose.x,500))
    local before=context.world.environmentSnapshot().bayDoor
    local bad=row();bad[9]=3
    check("invalid_technician_pose_cannot_partially_apply_door_or_actor_state",
        not context.world.applyEnvironmentSnapshot({state="open",progress=1},previous.truck,nil,guest,bad)
        and context.world.environmentSnapshot().bayDoor.state==before.state and same(guest._technicianPose.x,500))
    client:_handleClientEnvelope(assert(Protocol.decode(assert(Protocol.encode("environment_snapshot",environment(Codec.array(),envelope.payload.serverTick+1))))))
    runtime.handleMultiplayerEvents()
    check("guest_application_clears_departed_technician",guest._technicianPose==false and Technician.presentation(guest)==nil)
    assert(context.world.applyEnvironmentSnapshot(previous.bayDoor,previous.truck,nil,guest))
end

local function guestMenu(context,check)
    local runtime=context.appRuntime
    local oldSession,oldState,oldLease=runtime.multiplayer,runtime.state,runtime.localWorkshopLease
    local fields={"taskAction","taskClock","taskClockAction","taskClockUpdatedAt","highFiveAnimation"}
    local saved={};for _,field in ipairs(fields) do saved[field]=runtime.World.player[field] end
    local guest=State.new();guest.screen="options";guest.optionsReturnScreen="world"
    local client=Session.new();client.mode="client";client.ready=true;client.sessionId="technician-motion"
    Replica.accept(guest,assert(Pose.actor(row(103.5,500))))
    Replica.accept(guest,assert(Pose.actor(row(2.5,503))))
    runtime.multiplayer,runtime.state,runtime.localWorkshopLease=client,guest,nil
    local ok,err=xpcall(function() runtime.updateMultiplayer(Replica.DURATION/2,0,0) end,debug.traceback)
    runtime.multiplayer,runtime.state,runtime.localWorkshopLease=oldSession,oldState,oldLease
    for _,field in ipairs(fields) do runtime.World.player[field]=saved[field] end
    check("guest_options_keeps_realtime_technician_interpolation_running",ok and guest.screen=="options"
        and same(guest._technicianPose.x,501.5) and same(guest._technicianPose.animationDistance,105),err)
end

function Test.run(context,check)
    wire(check);presentation(check);delivery(context,check);guestMenu(context,check)
end
return Test
