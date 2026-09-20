local Test={}
local Controls=require("src.screens.warehouse_controls")
local Forklift=require("src.forklift")
local Jobs=require("src.jobs")
local Storage=require("src.pallet_storage")
local Intent=require("src.warehouse_intent")
local function center(rect) return rect.x+rect.width/2,rect.y+rect.height/2 end
local function button(controls,key)
    for _,item in ipairs(controls:buttons()) do if item.key==key then return item end end
end
function Test.run(context,check)
    local state=context.State.new()
    local player={id=2,x=500,y=440}
    state.screen="world"
    state.forklift=Forklift.defaultState({spawnX=500,spawnY=440})
    state.forklift.owned,state.warehouse.forkliftOwned=true,true
    state.warehouse.bays.front_left={status="complete",optionId="storage"}
    state.storage.racks["front_left-rack"]=Storage.rackDefinition("front_left")
    local job=Jobs.createOffer({id="CONTROLS",company="Rack UI",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500}})
    Jobs.accept(job);state.jobs.active={job}
    local pallet=job.pallets[1]
    local sent,nearRack,response={},true,nil
    local stackCandidate
    local contextOkay,contextCalls=true,0
    local controls=Controls.new({state=state,player=function() return player end,
        command=function(intent) sent[#sent+1]=intent;return response end,
        world={warehouseNearRack=function() return nearRack and "front_left-rack" or nil end,
            warehouseCandidate=function() return pallet.id end,
            warehouseStackCandidate=function() return stackCandidate end,
            warehouseRackContext=function(observed,observedState,rackId,row,column)
                contextCalls=contextCalls+1
                contextOkay=contextOkay and observed==player and observedState==state
                    and rackId=="front_left-rack" and row~=nil and column~=nil
                return {playerId=observed.id,vehicle="forklift",near=nearRack,aligned=true,clear=true}
            end}})
    check("warehouse_controls_near_unmounted_drive_button",button(controls,"v") and button(controls,"h") and not button(controls,"r"))
    controls:keypressed("v")
    check("warehouse_controls_drive_emits_intent_without_mounting",sent[1].kind=="operate" and not state.forklift.operating)
    state.forklift.operating,state.forklift.operatorPlayerId=true,2
    for _,key in ipairs({"g","t","r"}) do controls:keypressed(key) end
    check("warehouse_controls_lower_travel_upper_height_targets",sent[2].height==0 and sent[3].height==0.08 and sent[4].height==1)
    local count=#sent
    local hotkeysBlocked=true
    for _,key in ipairs({"f","l","m","q","space"}) do hotkeysBlocked=controls:keypressed(key) and hotkeysBlocked end
    check("warehouse_controls_mounted_blocks_machine_hotkeys",hotkeysBlocked and #sent==count)
    check("warehouse_controls_keeps_movement_keys_available",not controls:keypressed("a") and not controls:keypressed("w"))
    check("warehouse_controls_mounted_world_tap_cannot_open_other_machine",controls:mousepressed(120,250,1) and #sent==count)
    controls:keypressed("e")
    check("warehouse_controls_pickup_uses_host_candidate_id",sent[#sent].kind=="pickup" and sent[#sent].palletId==pallet.id)
    state.forklift.carriedPalletId=pallet.id
    pallet.location,pallet.world="on_forklift",{x=500,y=440}
    controls:keypressed("e")
    check("warehouse_controls_loaded_use_requests_drop",sent[#sent].kind=="drop")
    count=#sent
    controls:keypressed("k")
    check("warehouse_controls_missing_stack_target_does_not_send",#sent==count and state.message:find("nearby matching skid")~=nil)
    stackCandidate={kind="stack",palletId=pallet.id,supportPalletId="BASE-P01"}
    local stackButton=button(controls,"k")
    local stackX,stackY=center(stackButton)
    controls:mousepressed(stackX,stackY,1)
    local stackRequest=sent[#sent]
    check("warehouse_controls_touch_stack_uses_bounded_canonical_intent",stackRequest.kind=="stack"
        and stackRequest.palletId==pallet.id and stackRequest.supportPalletId=="BASE-P01"
        and stackRequest.expectedRevision==state.storage.revision and Intent.normalize(stackRequest)~=nil
        and controls.stackPending==stackRequest and pallet.location=="on_forklift")
    count=#sent;controls:keypressed("k")
    check("warehouse_controls_pending_stack_prevents_duplicate_click",#sent==count)
    controls:resolve({requestId="unrelated"},true,"Unrelated")
    check("warehouse_controls_pending_stack_requires_matching_ack",controls.stackPending==stackRequest)
    controls:resolve(stackRequest,false,"Raise forks first.")
    check("warehouse_controls_stack_rejection_unlocks_and_explains",not controls.stackPending and state.message=="Raise forks first.")
    controls:keypressed("k")
    check("warehouse_controls_stack_retry_gets_fresh_request_id",sent[#sent].requestId~=stackRequest.requestId)
    controls:resolve(sent[#sent],true,"Stacked.")
    check("warehouse_controls_stack_success_clears_pending",not controls.stackPending and state.message=="Stacked.")
    stackCandidate={kind="unstack",palletId=pallet.id,supportPalletId="BASE-P01"};response=true
    controls:keypressed("k")
    check("warehouse_controls_keyboard_unstack_uses_same_host_route",sent[#sent].kind=="unstack" and not controls.stackPending)
    response=nil
    local minimumSize,noOverlap=true,true
    local buttons=controls:buttons()
    for i,item in ipairs(buttons) do
        minimumSize=minimumSize and item.width>=44 and item.height>=44
        for j,other in ipairs(buttons) do if i<j then
            noOverlap=noOverlap and (item.x+item.width<=other.x or other.x+other.width<=item.x
                or item.y+item.height<=other.y or other.y+other.height<=item.y)
        end end
    end
    check("warehouse_controls_mobile_targets_are_44px_and_nonoverlapping",minimumSize and noOverlap)
    controls:openRack()
    check("warehouse_controls_rack_opens_same_presenter",state.screen=="pallet_rack" and controls.rack.rackId=="front_left-rack")
    local rackLayout=controls.rack:layout()
    check("warehouse_controls_rack_transfer_and_back_targets_are_44px",rackLayout.store.height>=44
        and rackLayout.retrieve.height>=44 and rackLayout.close.height>=44)
    check("warehouse_controls_rack_upper_shortcut_does_not_steal_retrieve",button(controls,"u") and not button(controls,"r"))
    local request=controls.rack:activate(state,"store")
    check("warehouse_controls_rack_callback_uses_live_player_state",contextCalls>0 and contextOkay)
    check("warehouse_controls_async_rack_intent_remains_pending",request.pending and controls.rack.pending~=nil
        and sent[#sent].kind=="store" and sent[#sent].action==nil and Intent.normalize(sent[#sent])~=nil
        and controls.rack.pending.action=="store" and pallet.location=="on_forklift")
    local requestId=sent[#sent].requestId
    controls:resolve({requestId="different"},true,"Other result")
    check("warehouse_controls_unrelated_ack_keeps_pending",controls.rack.pending~=nil)
    controls:resolve(sent[#sent],false,"Move closer.")
    check("warehouse_controls_matching_rejected_ack_unlocks",controls.rack.pending==nil and controls.rack.message=="Move closer.")
    response=true
    request=controls.rack:activate(state,"store")
    check("warehouse_controls_local_success_does_not_stay_pending",not request.pending and controls.rack.pending==nil)
    controls:keypressed("escape")
    check("warehouse_controls_rack_back_restores_world",state.screen=="world" and controls.rack.closed)
    controls:openRack();response=nil
    request=controls.rack:activate(state,"store")
    check("warehouse_controls_reopening_never_reuses_prior_request_id",request.request.requestId~=requestId)
    controls:resolve(sent[#sent],true,"Stored.")
    check("warehouse_controls_matching_success_ack_unlocks",controls.rack.pending==nil and controls.rack.message=="Stored.")
    local captured
    controls.rack.draw=function(_,drawState,fonts,assets) captured={state=drawState,fonts=fonts,assets=assets} end
    local marker={images={}}
    local previousLove=love
    love={graphics={setColor=function() end,rectangle=function() end,setLineWidth=function() end,printf=function() end}}
    local drawn=pcall(function() controls:draw(marker) end)
    love=previousLove
    check("warehouse_controls_rack_draw_uses_correct_argument_order",drawn and captured and captured.state==state
        and captured.fonts==nil and captured.assets==marker)
    controls.stackPending={requestId="LOST-STACK"}
    controls:reset("Connection lost.")
    check("warehouse_controls_reset_clears_orphaned_stack_and_rack",
        controls.stackPending==nil and controls.rack==nil and state.screen=="world")
    controls:reset()
    check("warehouse_controls_reset_is_idempotent",controls.stackPending==nil and controls.rack==nil)
    state.screen="world";state.forklift.operating=false;state.forklift.operatorPlayerId=nil
    nearRack=false;player={id=3,x=200,y=200}
    check("warehouse_controls_live_player_callback_updates_ownership",not controls:ownsLift() and #controls:buttons()==0)
    check("warehouse_controls_unmounted_world_input_passes_through",not controls:keypressed("m") and not controls:mousepressed(120,250,1))
    check("warehouse_controls_out_of_range_rack_stays_closed",not controls:openRack() and state.screen=="world")
end
return Test
