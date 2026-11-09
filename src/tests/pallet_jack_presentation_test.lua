local Config=require("src.config")
local State=require("src.state")
local Jack=require("src.pallet_jack")
local Pose=require("src.pallet_jack_pose")
local Rig=require("src.pallet_jack_presentation")
local Protocol=require("src.net.protocol")
local Session=require("src.net.session")
local Schema=require("src.save_schema")
local Test={}
local function fresh()
    local state=State.new()
    local jack=Jack.ensure(state,Config.palletJack)
    jack.x,jack.y,jack.direction=500,500,"east"
    assert(Jack.mount(state,Config.palletJack,1))
    return state
end
local function frame(sample)
    local x,_,width=sample.quad:getViewport()
    return x/width+1
end
function Test.run(context,check)
    local worldPlayer=context.world.player
    local priorPlayer={x=worldPlayer.x,y=worldPlayer.y,moving=worldPlayer.moving,facing=worldPlayer.facing}
    local host=fresh()
    Jack.followNavigation(host,537.25,500,.1,Config.palletJack)
    Jack.followNavigation(host,537.25,481.5,.05,Config.palletJack)
    local original=Jack.visualPose(host,Config.palletJack)
    local raw=context.world.networkPalletJackSnapshot(host)
    local payload={sessionId="jack-presentation",serverTick=1,jack=raw,machines=context.world.networkMachinePoseSnapshot(host)}
    local packet,err=Protocol.encode("pallet_jack_snapshot",payload)
    local decoded=packet and Protocol.decode(packet)
    local guest=State.new()
    local applied=decoded and context.world.applyNetworkPalletJackSnapshot(guest,decoded.payload.jack,decoded.payload.machines)
    local replica=applied and Jack.visualPose(guest,Config.palletJack)
    check("jack_midstride_join_restores_authoritative_phase_heading_and_clock",replica
        and math.abs(replica.distance%Pose.CYCLE_DISTANCE-original.distance%Pose.CYCLE_DISTANCE)<=.0051
        and math.abs(replica.heading%(math.pi*2)-original.heading%(math.pi*2))<=.000051
        and math.abs(guest.palletJack.animationClock-host.palletJack.animationClock)<.0011,err)
    local player={id=1,character="rabbit-worker",animationDistance=99999}
    local a=Rig.workerPoses(context.characterAssets,player,host)
    local b=Rig.workerPoses(context.characterAssets,player,guest)
    check("jack_host_and_joining_guest_use_one_matching_authored_pose",#a==1 and #b==1
        and a[1].weight==1 and b[1].weight==1 and frame(a[1])==frame(b[1])
        and a[1].anchorX==b[1].anchorX and a[1].anchorY==b[1].anchorY,
        string.format("host %.8f frame %d anchor %.2f,%.2f; guest %.8f frame %d anchor %.2f,%.2f",original.heading,
            frame(a[1]),a[1].anchorX,a[1].anchorY,replica.heading,frame(b[1]),b[1].anchorX,b[1].anchorY))
    local samples=true
    for i=0,15 do
        local state=fresh()
        Jack.followNavigation(state,500+(i+.5)*Pose.CYCLE_DISTANCE/16,500,.1,Config.palletJack)
        local poses=Rig.workerPoses(context.characterAssets,player,state)
        samples=samples and #poses==1 and poses[1].weight==1 and frame(poses[1])==i+1
    end
    check("jack_subframe_samples_do_not_crossfade_two_boot_silhouettes",samples)
    -- The first path bends, so endpoint displacement cannot reconstruct its
    -- traveled phase. Later packets also cross the stride seam.
    Jack.followNavigation(host,537.25,454,.1,Config.palletJack)
    local nextRaw=context.world.networkPalletJackSnapshot(host)
    check("jack_phase_wrap_survives_a_curved_route_and_skipped_packet",Jack.applySnapshot(guest,nextRaw,Config.palletJack)
        and math.abs(Jack.animationDistance(guest,Config.palletJack)%Pose.CYCLE_DISTANCE
            -Jack.animationDistance(host,Config.palletJack)%Pose.CYCLE_DISTANCE)<=.0051)
    local stateBefore=Schema.copy(guest.palletJack)
    local poseBefore=Jack.visualPose(guest,Config.palletJack)
    local invalid=true
    for _,mutate in ipairs({function(t)t[1]=-1 end,function(t)t[1]=Pose.CYCLE_DISTANCE*100 end,
        function(t)t[2]=62832 end,function(t)t[3]=3077 end,function(t)t[1]=0/0 end,
        function(t)t[1]=.5 end,function(t)t[4]=1 end,function(t)t[2]=nil end,function(t)t.money=1 end}) do
        local bad=Schema.copy(raw);bad.motion=Schema.copy(raw.motion);mutate(bad.motion)
        invalid=invalid and not Pose.normalize(bad.motion) and not Jack.applySnapshot(guest,bad,Config.palletJack)
            and not Protocol.encode("pallet_jack_snapshot",{sessionId=payload.sessionId,serverTick=2,jack=bad,machines=payload.machines})
    end
    check("jack_invalid_motion_is_rejected_atomically_in_api_and_wire",invalid and guest.palletJack.x==stateBefore.x
        and Jack.visualPose(guest,Config.palletJack).distance==poseBefore.distance
        and not Jack.applySnapshot(guest,1,Config.palletJack))
    guest.palletJack.moving=false
    local stopped=Jack.animationDistance(guest,Config.palletJack)
    local idleClock=guest.palletJack.animationClock
    Jack.updateRemotePresentation(guest,.2,Config.palletJack)
    check("jack_packet_gaps_advance_idle_without_inventing_stride",Jack.animationDistance(guest,Config.palletJack)==stopped
        and math.abs(guest.palletJack.animationClock-idleClock-.2)<.00001)
    local Fleet=require("src.pallet_jack_fleet")
    local extra=Fleet.add(host,"JACK-0002",{x=450,y=500})
    extra.direction="east"
    local selected=Fleet.view(host,extra)
    host.employment.staff[1]={id="EMP-1",visible=true,status="employed",sceneId="warehouse"}
    assert(Jack.mountEmployee(selected,Config.palletJack,"EMP-1"))
    Jack.followNavigation(selected,463.75,500,.1,Config.palletJack)
    local extraRaw=Fleet.snapshots(host)[1]
    local extraPacket=assert(Protocol.encode("extra_pallet_jack_snapshot",{sessionId=payload.sessionId,
        serverTick=2,jackId=extraRaw.id,jack=extraRaw.jack}))
    local extraPayload=assert(Protocol.decode(extraPacket)).payload
    local guestExtra=Fleet.add(guest,extra.id,{x=450,y=500})
    check("jack_extra_vehicle_snapshots_preserve_their_own_motion_phase",Fleet.applySnapshot(guest,extra.id,extraPayload.jack)
        and math.abs(Jack.animationDistance(Fleet.view(guest,guestExtra),Config.palletJack)-13.75)<.0051)
    local primaryClock,extraClock=guest.palletJack.animationClock,guestExtra.animationClock
    context.world.updatePalletJackPresentation(guest,0,{},nil,.2)
    check("jack_predicting_owner_does_not_freeze_other_vehicles_or_double_advance_own_clock",
        guest.palletJack.animationClock==primaryClock and math.abs(guestExtra.animationClock-extraClock-.2)<.00001)
    local client=Session.new()
    client.mode,client.ready,client.sessionId="client",true,payload.sessionId
    client:_handleClientEnvelope(decoded);client:_handleClientEnvelope(decoded)
    local events=client:drainEvents()
    check("jack_session_preserves_motion_and_drops_reordered_pose_packets",#events==1
        and events[1].type=="pallet_jack_state" and events[1].jack.motion[1]==raw.motion[1])
    local maximum=Schema.copy(payload)
    maximum.sessionId=string.rep("s",64);maximum.serverTick=4294967295
    maximum.jack.x,maximum.jack.y=100000,-100000
    maximum.jack.operatorPlayerId=nil;maximum.jack.operatorEmployeeId="EMP-999999999999"
    maximum.jack.carriedPalletId=string.rep("p",64);maximum.jack.candidatePalletId=nil
    maximum.jack.motion={Pose.CYCLE_DISTANCE*100-1,62831,3076}
    local largest,largestError=Protocol.encode("pallet_jack_snapshot",maximum)
    check("jack_motion_and_machine_poses_fit_existing_packet_ceiling",largest and #largest<=Protocol.MAX_PACKET_BYTES,largestError)
    -- Presentation data is transient; adding it to the wire must not extend
    -- persisted jack records or invalidate a legacy packet without the field.
    check("jack_wire_presentation_does_not_enter_durable_records",host.palletJack.motion==nil
        and Jack.snapshot(host,Config.palletJack).motion==nil)
    local legacy=Schema.copy(raw);legacy.motion=nil
    check("jack_legacy_snapshot_fallback_remains_usable",Jack.applySnapshot(State.new(),legacy,Config.palletJack))
    worldPlayer.x,worldPlayer.y,worldPlayer.moving,worldPlayer.facing=priorPlayer.x,priorPlayer.y,priorPlayer.moving,priorPlayer.facing
end
return Test
