local Test = {}
local Intent = require("src.warehouse_intent")
local Warehouse = require("src.warehouse_authority")
local Forklift = require("src.forklift")
local Protocol = require("src.net.protocol")
local Workshop = require("src.workshop_authority")
local Session = require("src.net.session")
local Harness = require("src.tests.support.network_impairment_harness")

local function worker(x, y)
    return { x=x, y=y, velocityX=0, velocityY=0, intentX=0, intentY=0,
        moving=false, facing=1, animationDistance=0, character="rabbit-worker" }
end
local function event(events, kind)
    for _, item in ipairs(events) do if item.type == kind then return item end end
end
local function actualStackAuthority(context,check)
    local Gameplay=require("src.warehouse_gameplay")
    local Config=require("src.config")
    local state=context.State.new();state.money=50000
    assert(require("src.warehouse_upgrades").purchaseForklift(state,"AUTHORITY-LIFT",0))
    local mask={getDimensions=function() return 960,678 end,getPixel=function() return 1,1,1,1 end}
    local cx={assets={getData=function() return mask end},obstacles=function() return {} end}
    Gameplay.update(0,state,cx)
    local player={id=2,x=state.forklift.x,y=state.forklift.y}
    assert(Gameplay.command(player,state,{kind="operate"},cx))
    local lift=state.forklift
    lift.direction,lift.forkHeight,lift.targetForkHeight="west",1,1
    local job=assert(require("src.jobs").createOffer({id="AUTH-STACK",company="Stack authority",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500,600}}))
    require("src.jobs").accept(job)
    state.jobs.active={job}
    local top,base=job.pallets[1],job.pallets[2]
    top.location,top.world="on_forklift",{x=lift.x,y=lift.y,direction="west",spawnProgress=1}
    base.location,base.world="warehouse",{x=lift.x-80,y=lift.y,direction="west",spawnProgress=1}
    lift.carriedPalletId=top.id
    local saves=0
    local command=Warehouse.command({state=state,save=function() saves=saves+1 end,world={
        warehouseAccess=function(p,s,i) return Gameplay.access(p,s,i,cx) end,
        warehouseCommand=function(p,s,i) return Gameplay.command(p,s,i,cx) end}})
    local intent={kind="stack",requestId="AUTH-STACK-1",expectedRevision=0,vehicle="forklift",palletId=top.id,supportPalletId=base.id}
    local okay,code=command.perform({resourceId="pallet_jack"},player,{warehouseIntent=intent})
    check("warehouse_authority_stack_rejects_jack_lease_before_mutation",not okay and code=="wrong_vehicle_lease"
        and top.location=="on_forklift" and saves==0)
    okay,code=command.perform({resourceId="warehouse"},{id=3,x=lift.x,y=lift.y},{warehouseIntent=intent})
    check("warehouse_authority_stack_authenticates_actual_operator",not okay and code=="not_owner" and saves==0)
    okay,code=command.perform({resourceId="warehouse"},player,{warehouseIntent=intent})
    check("warehouse_authority_stack_commits_actual_pallet_once",okay and code=="stack" and top.location=="stacked"
        and top.storage.supportPalletId==base.id and not lift.carriedPalletId and saves==1)
    okay,code=command.perform({resourceId="warehouse"},player,{warehouseIntent=intent})
    check("warehouse_authority_stack_replay_never_saves_or_charges_twice",okay and code=="replayed" and saves==1
        and state.storage.revision==1 and state.money==17000)
    intent={kind="unstack",requestId="AUTH-TAKE-1",expectedRevision=1,vehicle="forklift",palletId=top.id,supportPalletId=base.id}
    okay,code=command.perform({resourceId="warehouse"},player,{warehouseIntent=intent})
    check("warehouse_authority_take_top_returns_exact_canonical_load",okay and code=="unstack" and top.location=="on_forklift"
        and lift.carriedPalletId==top.id and base.location=="warehouse" and saves==2 and state.storage.revision==2)
end
function Test.run(context, check)
    actualStackAuthority(context,check)
    local valid = {
        {kind="operate"}, {kind="release"}, {kind="pickup",palletId="JOB-1-P01"}, {kind="drop"},
        {kind="set_height",height=0}, {kind="set_height",height=0.08}, {kind="set_height",height=1},
        {kind="store",requestId="STORE-1",expectedRevision=0,vehicle="forklift",palletId="JOB-1-P01",rackId="front_left-rack",row=2,column=5},
        {kind="retrieve",requestId="TAKE-1",expectedRevision=1,vehicle="pallet_jack",palletId="JOB-1-P01",rackId="front_left-rack",row=1,column=1},
        {kind="stack",requestId="STACK-1",expectedRevision=0,vehicle="forklift",palletId="JOB-1-P01",supportPalletId="JOB-1-P02"},
        {kind="unstack",requestId="UNSTACK-1",expectedRevision=1,vehicle="forklift",palletId="JOB-1-P01",supportPalletId="JOB-1-P02"},
    }
    for i, intent in ipairs(valid) do
        local normalized = Intent.normalize(intent)
        local bytes = Protocol.encode("workshop_command", {sessionId="warehouse-test",commandId=i,
            resourceId="warehouse",leaseId="warehouse-lease",action="warehouse_action",expectedRevision=0,warehouseIntent=intent})
        check("warehouse_intent_round_trip_"..i, normalized and bytes and #bytes<=1200 and Protocol.decode(bytes)~=nil)
    end
    local bad = {{kind="operate",playerId=1},{kind="operate",x=0},{kind="set_height",height=0.5},
        {kind="set_height",height=0/0},{kind="pickup",palletId=""},{kind="drop",palletId="X"},
        {kind="store",requestId="x",expectedRevision=0,vehicle="forklift",palletId="P",rackId="R",row=3,column=1},
        {kind="store",requestId="x",expectedRevision=-1,vehicle="forklift",palletId="P",rackId="R",row=1,column=1},
        {kind="store",requestId="x",expectedRevision=0,vehicle="forklift",palletId="P",rackId="R",row=1,column=1,near=true},
        {kind="purchase",price=0}, {kind="move",dx=1,dt=999}, {},
        {kind="stack",requestId="x",expectedRevision=0,vehicle="pallet_jack",palletId="P",supportPalletId="Q"},
        {kind="stack",requestId="x",expectedRevision=0,vehicle="forklift",palletId="P",supportPalletId="P"},
        {kind="stack",requestId="x",expectedRevision=0,vehicle="forklift",palletId="P",supportPalletId="Q",clear=true},
        {kind="unstack",requestId="x",expectedRevision=0,vehicle="forklift",palletId="P",supportPalletId="Q",row=2},
    }
    for i, intent in ipairs(bad) do check("warehouse_intent_rejects_forgery_"..i,Intent.normalize(intent)==nil) end
    local jackTransfer={kind="retrieve",requestId="JACK-TAKE-1",expectedRevision=1,vehicle="pallet_jack",
        palletId="JOB-1-P01",rackId="front_left-rack",row=1,column=1}
    local function jackPacket(intent)
        return Protocol.encode("workshop_command",{sessionId="warehouse-test",commandId=1,
            resourceId="pallet_jack",leaseId="jack-lease",action="warehouse_action",expectedRevision=0,warehouseIntent=intent})
    end
    check("warehouse_jack_lease_accepts_its_strict_rack_transfer",jackPacket(jackTransfer)~=nil)
    check("warehouse_jack_lease_rejects_forklift_actions_on_wire",jackPacket({kind="operate"})==nil
        and jackPacket({kind="set_height",height=1})==nil and jackPacket(valid[8])==nil)
    check("warehouse_jack_lease_rejects_floor_stack_actions_on_wire",jackPacket(valid[10])==nil and jackPacket(valid[11])==nil)

    local state = context.State.new()
    state.warehouse.forkliftOwned, state.forklift.owned = true, true
    local saves, calls, inRange = 0, 0, true
    local command = Warehouse.command({ state=state, save=function() saves=saves+1 end, world={
        warehouseAccess=function() return inRange,"out_of_range","Move closer." end,
        warehouseCommand=function(player, shop, intent)
            calls=calls+1
            if intent.kind=="operate" then return Forklift.acquire(shop,nil,player.id)
            elseif intent.kind=="release" then return Forklift.release(shop,nil,player.id)
            elseif intent.kind=="set_height" then return Forklift.setForkHeight(shop,nil,player.id,intent.height) end
            return false,"unsupported"
        end,
    }})
    check("warehouse_authority_rejects_extra_envelope",command.normalize({warehouseIntent={kind="operate"},near=true})==nil)
    local ok, code=command.perform({}, {id=0}, {warehouseIntent={kind="operate"}})
    check("warehouse_authority_requires_authenticated_worker",not ok and code=="invalid_player" and saves==0 and calls==0)
    inRange=false
    ok,code=command.perform({}, {id=2}, {warehouseIntent={kind="operate"}})
    check("warehouse_authority_fresh_host_range_before_mutation",not ok and code=="out_of_range" and saves==0 and calls==0)
    inRange=true
    ok,code=command.perform({resourceId="pallet_jack"},{id=2},{warehouseIntent={kind="operate"}})
    check("warehouse_jack_lease_cannot_control_forklift_authoritatively",not ok and code=="wrong_vehicle_lease" and calls==0 and saves==0)
    local jackAllowed,jackCalls,jackSaves=false,0,0
    local jackCommand=Warehouse.command({state=state,save=function() jackSaves=jackSaves+1 end,
        world={warehouseAccess=function() return jackAllowed,"out_of_range","Move the jack to the rack." end,
            warehouseCommand=function(p,actual,intent)
                jackCalls=jackCalls+1
                return p.id==2 and actual==state and intent.vehicle=="pallet_jack" and intent.kind=="retrieve","completed"
            end}})
    local jackAuthority=Workshop.new({resources={pallet_jack={canAcquire=function() return true end,
        onAcquire=function() return true,"acquired","Jack controlled.",{} end,
        commands={warehouse_action=jackCommand}}}})
    local jackGrant=jackAuthority:acquire({id=2},{requestId=1,resourceId="pallet_jack"},{})
    local function transferOnJack(requestId)
        return jackAuthority:command({id=2},{requestId=requestId,resourceId="pallet_jack",leaseId=jackGrant.leaseId,
            action="warehouse_action",expectedRevision=jackAuthority:resourceRevision("pallet_jack"),args={warehouseIntent=jackTransfer}}, {})
    end
    local jackResult=transferOnJack(2)
    check("warehouse_jack_lease_still_rechecks_world_range",not jackResult.accepted and jackResult.code=="out_of_range" and jackCalls==0 and jackSaves==0)
    jackAllowed=true;jackResult=transferOnJack(3)
    check("warehouse_jack_lease_transfers_without_releasing_operator",jackResult.accepted and jackCalls==1 and jackSaves==1
        and jackAuthority:leaseForPlayer({id=2}).resourceId=="pallet_jack")
    local authority=Workshop.new({resources={warehouse={canAcquire=function() return true end,
        onAcquire=function() return true,"acquired","Warehouse controls connected.",{} end,
        commands={warehouse_action=command}}}})
    local network=Harness.new({maxClients=1,classify=function(bytes) local value=Protocol.decode(bytes);return value and value.type or "invalid" end})
    local host,guest=Session.new({transportFactory=network.factory}),Session.new({transportFactory=network.factory})
    local hp,gp=worker(100,100),worker(110,100)
    local hc={localPlayer=hp,resolveGuestSpawn=function() return 110,100 end,moveRemote=function() end,
        touchWorkshop=function(p) authority:touchPlayer(p) end,updateWorkshop=function() authority:update({}) end,
        getShopSnapshot=function() return {state={money=state.money,screen="world",inventory={paper=0,prints=0},jobs={active={},completed={}}},player={x=hp.x,y=hp.y,character=hp.character}} end,
        getForkliftSnapshot=function() return Forklift.snapshot(state) end,
        getWorkshopSnapshot=function() return {resources=authority:snapshot(),wrapper={step="idle",progress=0,cycleTime=3,pallets={}}} end}
    hc.performWorkshop=function(p,kind,payload)
        if kind=="workshop_acquire" then return authority:acquire(p,{requestId=payload.requestId,resourceId=payload.resourceId},{}) end
        if kind=="workshop_release" then return authority:release(p,{requestId=payload.requestId,resourceId=payload.resourceId,leaseId=payload.leaseId,reason=payload.reason},{}) end
        return authority:command(p,{requestId=payload.commandId,resourceId=payload.resourceId,leaseId=payload.leaseId,
            action=payload.action,expectedRevision=payload.expectedRevision,args={warehouseIntent=payload.warehouseIntent}}, {})
    end
    local gc={localPlayer=gp,inputX=0,inputY=0}
    local hs=host:startHost({name="Warehouse Host",character="rabbit-worker",addressOptions={socket={dns={
        gethostname=function() return "warehouse-host" end,getaddrinfo=function() return {{addr="192.168.1.93"}} end}}}})
    host.sessionId="warehouse-test"
    local gs=guest:startClient("192.168.1.93:22122",{name="Warehouse Guest",character="rabbit-worker"})
    guest.clientNonce="warehouse-guest"
    guest:update(0,gc);host:update(0,hc);guest:update(0,gc);host:update(0.1,hc);guest:update(0,gc)
    check("warehouse_session_connects",hs and gs and guest.ready)
    local pose=event(guest:drainEvents(),"forklift_state")
    check("warehouse_session_initial_forklift_pose",pose and pose.forklift.owned and pose.forklift.forkHeight==0)
    local function pump(dt) host:update(dt or 0,hc);guest:update(0,gc);return guest:drainEvents() end
    guest:requestWorkshopAcquire("warehouse")
    local grant=event(pump(),"workshop_grant")
    check("warehouse_session_grants_authenticated_lease",grant and grant.granted)
    network:duplicateNext("client_to_host",1,1,true)
    guest:requestWorkshopCommand("warehouse_action",{warehouseIntent={kind="operate"}})
    local reply=event(pump(),"workshop_result")
    check("warehouse_session_duplicate_operate_runs_once",reply and reply.accepted and state.forklift.operatorPlayerId==2 and calls==1 and saves==1)
    local occupied=authority:acquire({id=3},{requestId=1,resourceId="warehouse"},{})
    check("warehouse_session_second_worker_cannot_steal_controls",not occupied.accepted and occupied.code=="resource_busy")
    guest:requestWorkshopCommand("warehouse_action",{warehouseIntent={kind="set_height",height=1}})
    reply=event(pump(),"workshop_result")
    check("warehouse_session_raise_starts_host_simulation",reply and reply.accepted and state.forklift.targetForkHeight==1 and state.forklift.forkHeight==0)
    Forklift.update(state,1.5)
    pose=event(pump(0.1),"forklift_state")
    check("warehouse_session_replicates_intermediate_height",pose and pose.forklift.forkHeight>0 and pose.forklift.forkHeight<1 and pose.forklift.lifting)
    local lastTick=guest.lastForkliftTick
    guest:_handleClientEnvelope({type="forklift_snapshot",payload={sessionId=host.sessionId,serverTick=lastTick-1,forklift=Forklift.defaultState()}})
    check("warehouse_session_old_pose_cannot_rewind",not event(guest:drainEvents(),"forklift_state") and guest.lastForkliftTick==lastTick)
    guest:_handleClientEnvelope({type="forklift_snapshot",payload={sessionId="old-session",serverTick=lastTick+1,forklift=Forklift.defaultState()}})
    check("warehouse_session_other_session_pose_ignored",not event(guest:drainEvents(),"forklift_state") and guest.lastForkliftTick==lastTick)
    inRange=false
    guest:requestWorkshopCommand("warehouse_action",{warehouseIntent={kind="release"}})
    reply=event(pump(),"workshop_result")
    check("warehouse_session_rechecks_access_after_grant",reply and not reply.accepted and reply.code=="out_of_range" and saves==2 and calls==2)
    local good=Forklift.snapshot(state)
    good.money=9000
    check("warehouse_snapshot_rejects_extra_state_fields",Protocol.encode("forklift_snapshot",{sessionId="x",serverTick=1,forklift=good})==nil)
    good=Forklift.snapshot(state);good.forkHeight=2
    check("warehouse_snapshot_rejects_impossible_height",Protocol.encode("forklift_snapshot",{sessionId="x",serverTick=1,forklift=good})==nil)
    guest:stop("test_complete");host:update(0,hc);host:stop("test_complete")
end
return Test
