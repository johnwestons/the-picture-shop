local Test={}
local State=require("src.state")
local Computer=require("src.screens.computer_screen")
local Office=require("src.office_authority")
local Intent=require("src.office_intent")
local Upgrades=require("src.warehouse_upgrades")
local Projection=require("src.screens.gui_projection")
local Protocol=require("src.net.protocol")

local function same(left,right)
    if type(left)~=type(right) then return false end
    if type(left)~="table" then return left==right end
    for key,value in pairs(left) do if not same(value,right[key]) then return false end end
    for key in pairs(right) do if left[key]==nil then return false end end
    return true
end
local function shop()
    local state=State.new();state.money=30000
    return state
end
local function purchase(bay,option,id,confirm)
    return {kind="buy_upgrade",bayId=bay,optionId=option,requestId=id,confirmUpperRows=confirm}
end
local function click(screen,state,bay,option)
    local x,y=screen.warehouseButtonCenter(bay,option)
    return screen.mousepressed(state,x,y,1)
end

function Test.run(_,check)
    local state=shop()
    local saves,inRange=0,true
    local options={state=state,warehouseEnabled=true,save=function() saves=saves+1 end,
        world={validateNetworkWorkshopAccess=function()
            return inRange,inRange and "available" or "out_of_range","Move closer to the computer."
        end}}
    local command=Office.command(options)
    local function perform(intent,cmd)
        cmd=cmd or command
        local normalized=cmd.normalize({officeIntent=intent})
        if not normalized then return false,"invalid_office_action" end
        return cmd.perform({}, {id=1}, normalized)
    end
    check("warehouse_office_intents_have_bounded_choices",Intent.normalize(purchase("front_left","storage","BUY-1",true))~=nil
        and Intent.normalize({kind="buy_forklift",requestId="FORK-1"})~=nil)
    local malformed={
        purchase("unknown","floor","BUY-1"),purchase("front_left","unknown","BUY-1"),
        purchase("front_left","storage","BUY-1","yes"),purchase("front_left","storage","BUY-1",1),
        purchase("front_left","floor",string.rep("x",65)),{kind="buy_forklift"},
        {kind="buy_forklift",requestId="FORK-1",price=1},
        {kind="buy_upgrade",bayId="front_left",optionId="floor",requestId="BUY-1",price=0},
        {kind="buy_upgrade",bayId="front_left",optionId="floor",requestId="BUY-1",money=99999},
        {kind="buy_upgrade",bayId="front_left",optionId="floor",requestId="BUY-1",completed=true},
    }
    for index,value in ipairs(malformed) do check("warehouse_office_rejects_forged_data_"..index,Intent.normalize(value)==nil) end
    local disabledOptions={state=state,save=options.save,world=options.world}
    local disabled=Office.command(disabledOptions)
    local before=Projection.copy(state)
    local allowed,reason=perform(purchase("front_left","floor","OFF-1"),disabled)
    check("warehouse_office_authority_disabled_by_default",not allowed and reason=="warehouse_disabled"
        and same(state,before) and saves==0)
    allowed,reason=perform(purchase("front_left","storage","SHELF-NO-ACK"))
    check("warehouse_office_requires_upper_row_warning_ack",not allowed and reason=="forklift_warning_required"
        and same(state,before) and saves==0)
    inRange=false
    allowed,reason=perform(purchase("front_left","storage","SHELF-NO-RANGE",true))
    check("warehouse_office_host_rechecks_computer_access",not allowed and reason=="out_of_range" and same(state,before))
    inRange=true
    local request=purchase("front_left","storage","SHELF-1",true)
    allowed,reason=perform(request)
    check("warehouse_office_host_purchases_at_catalog_price_and_saves_once",allowed and reason=="completed"
        and state.money==30000-Upgrades.catalog("storage").price and saves==1
        and state.warehouse.bays.front_left.status=="reserved" and #state.warehouse.projects==1
        and Upgrades.validate(state.warehouse))
    local after=Projection.copy(state)
    allowed,reason=perform(request)
    check("warehouse_office_replay_never_charges_or_saves_again",allowed and reason=="replayed" and same(state,after) and saves==1)
    allowed=perform(purchase("front_right","floor","SHELF-1"))
    check("warehouse_office_request_collision_is_atomic",not allowed and same(state,after) and saves==1)
    local forkliftBefore=Projection.copy(state.forklift)
    allowed=perform({kind="buy_forklift",requestId="FORK-1"})
    check("warehouse_office_forklift_purchase_entitlement_keeps_spawn_safe",allowed
        and state.warehouse.forkliftOwned and state.money==30000-Upgrades.catalog("storage").price-Upgrades.catalog("forklift").price
        and same(state.forklift,forkliftBefore) and saves==2)
    local forkliftAfter=Projection.copy(state)
    allowed,reason=perform({kind="buy_forklift",requestId="FORK-1"})
    check("warehouse_office_forklift_replay_preserves_vehicle",allowed and reason=="replayed" and same(state,forkliftAfter) and saves==2)
    allowed=perform(purchase("front_right","storage","SHELF-2"))
    check("warehouse_office_owned_forklift_needs_no_redundant_warning",allowed and saves==3 and #state.warehouse.projects==2)
    local broke=shop();broke.money=1
    local brokeSaves=0
    local brokeCommand=Office.command({state=broke,warehouseEnabled=true,world=options.world,save=function() brokeSaves=brokeSaves+1 end})
    local brokeBefore=Projection.copy(broke)
    allowed=perform(purchase("front_left","floor","POOR-1"),brokeCommand)
    check("warehouse_office_insufficient_cash_is_atomic",not allowed and same(broke,brokeBefore) and brokeSaves==0)
    local packet=Protocol.encode("workshop_command",{sessionId="warehouse-office",commandId=1,
        resourceId="office_computer",leaseId="warehouse-lease",expectedRevision=0,action="office_action",
        officeIntent=purchase("front_left","storage",string.rep("r",64),true)})
    check("warehouse_office_intent_fits_existing_bounded_packet",packet~=nil and #packet<=1200 and Protocol.decode(packet)~=nil)

    local client=shop()
    local clientBefore=Projection.copy(client)
    local sent={}
    local remote=Computer.new({warehouseEnabled=true,warehouseRequestPrefix="GUEST-SESSION-2",
        remoteCommand=function(intent) sent[#sent+1]=Projection.copy(intent);return true end})
    local hidden=Computer.new()
    check("warehouse_office_tab_hidden_until_explicit_enable",hidden.tabCenter("warehouse")==nil
        and not hidden.warehouseEnabled() and remote.tabCenter("warehouse")~=nil)
    hidden.tab="warehouse"
    local hiddenResult=click(hidden,client,"front_left","floor")
    check("warehouse_office_forced_hidden_tab_cannot_purchase",hiddenResult.action=="blocked" and same(client,clientBefore))
    remote.tab="warehouse"
    local result=click(remote,client,"front_left","storage")
    check("warehouse_office_first_click_only_reviews_purchase",result.action=="warehouse_confirmation" and #sent==0
        and remote.warehouseConfirmation.warningRequired and same(client,clientBefore))
    result=click(remote,client,"confirm")
    check("warehouse_office_ui_requires_warning_confirmation",result.action=="blocked" and #sent==0 and same(client,clientBefore))
    click(remote,client,"acknowledge")
    result=click(remote,client,"confirm")
    check("warehouse_office_guest_sends_intent_without_local_debit",result.action=="remote_pending" and #sent==1
        and sent[1].kind=="buy_upgrade" and sent[1].bayId=="front_left" and sent[1].optionId=="storage"
        and sent[1].confirmUpperRows==true and sent[1].price==nil and Intent.normalize(sent[1])~=nil
        and same(client,clientBefore))
    click(remote,client,"confirm")
    check("warehouse_office_ui_blocks_double_pending_purchase",#sent==1 and remote.warehousePending)
    remote.resolveWarehouse(false,"Please move closer.")
    click(remote,client,"confirm")
    check("warehouse_office_retry_reuses_same_idempotent_request",#sent==2 and sent[2].requestId==sent[1].requestId
        and same(client,clientBefore))
    remote.resolveWarehouse(true,"Bought.")
    check("warehouse_office_reply_closes_confirmation",not remote.warehousePending and remote.warehouseConfirmation==nil)
    result=click(remote,client,"forklift")
    check("warehouse_office_forklift_has_explicit_review",result.action=="warehouse_confirmation" and #sent==2)
    result=click(remote,client,"cancel")
    check("warehouse_office_cancel_never_sends_or_mutates",result.action=="warehouse_cancelled" and #sent==2 and same(client,clientBefore))
    for _,bay in ipairs({"front_left","front_right"}) do for _,option in ipairs({"floor","storage","breakroom"}) do
        click(remote,client,bay,option)
        check("warehouse_office_all_six_choices_select_exact_target_"..bay.."_"..option,
            remote.warehouseConfirmation.bayId==bay and remote.warehouseConfirmation.optionId==option)
        click(remote,client,"cancel")
    end end
    local localState=shop()
    local localSaves=0
    local localCommand=Office.command({state=localState,warehouseEnabled=true,world=options.world,save=function() localSaves=localSaves+1 end})
    local localScreen=Computer.new()
    localScreen.configureWarehouse({enabled=true,command=function(intent)
        return localCommand.perform({}, {id=1}, localCommand.normalize({officeIntent=intent}))
    end})
    localScreen.tab="warehouse"
    click(localScreen,localState,"front_right","breakroom")
    result=click(localScreen,localState,"confirm")
    check("warehouse_office_local_gui_uses_same_host_save_boundary",result.action=="warehouse_purchased" and result.hostSaved
        and localSaves==1 and localState.warehouse.bays.front_right.optionId=="breakroom")
    localScreen.configureWarehouse({enabled=false})
    check("warehouse_office_gate_can_be_removed_safely",localScreen.tab=="active" and localScreen.tabCenter("warehouse")==nil)
    local projectView=Computer.new({warehouseEnabled=true}).warehouseView(state)
    check("warehouse_office_view_shows_both_ordered_bays_and_owned_vehicle",#projectView.bays==2
        and projectView.bays[1].phase=="queued" and projectView.bays[1].status=="reserved" and projectView.forkliftOwned)

    local limitedState=shop()
    local limitedSaves=0
    local limitedCommand=Office.command({state=limitedState,warehouseEnabled=true,warehouseFirstStorageOnly=true,
        world=options.world,save=function() limitedSaves=limitedSaves+1 end})
    local limitedBefore=Projection.copy(limitedState)
    for _,bay in ipairs({"front_left","front_right"}) do for _,option in ipairs({"floor","storage","breakroom"}) do
        if bay~="front_left" or option~="storage" then
            allowed,reason=perform(purchase(bay,option,"NOT-READY-"..bay.."-"..option,true),limitedCommand)
            check("warehouse_office_live_catalog_host_rejects_unready_"..bay.."_"..option,
                not allowed and reason=="warehouse_not_ready" and same(limitedState,limitedBefore) and limitedSaves==0)
        end
    end end
    allowed=perform({kind="buy_forklift",requestId="LIVE-FORK-1"},limitedCommand)
    check("warehouse_office_live_catalog_keeps_forklift_purchase",allowed and limitedState.warehouse.forkliftOwned and limitedSaves==1)
    allowed=perform(purchase("front_left","storage","LIVE-SHELF-1",true),limitedCommand)
    check("warehouse_office_live_catalog_keeps_left_storage_purchase",allowed
        and limitedState.warehouse.bays.front_left.optionId=="storage" and limitedSaves==2)

    local limitedScreen=Computer.new({warehouseEnabled=true,warehouseFirstStorageOnly=true,remoteCommand=function() return true end})
    limitedScreen.tab="warehouse"
    local offered=limitedScreen.warehouseView(client)
    check("warehouse_office_live_catalog_marks_disabled_options",not offered.bays[1].options[1].available
        and offered.bays[1].options[2].available and not offered.bays[1].options[3].available
        and not offered.bays[2].options[1].available and not offered.bays[2].options[2].available
        and not offered.bays[2].options[3].available)
    result=click(limitedScreen,client,"front_right","storage")
    check("warehouse_office_live_catalog_ui_blocks_unready_without_confirmation",result.action=="blocked"
        and result.reason=="warehouse_not_ready" and limitedScreen.warehouseConfirmation==nil)
    limitedScreen.configureWarehouse({enabled=true,firstStorageOnly=true})
    check("warehouse_office_local_configuration_carries_offer_filter",not limitedScreen.warehouseView(client).bays[2].options[2].available)

    local Config=require("src.config")
    local Remote=require("src.screens.workshop_remote_screen")
    local priorWarehouse=Config.warehouse
    Config.warehouse={enabled=true,firstStorageOnly=true}
    local remoteState=shop()
    local remoteMoney=remoteState.money
    local remoteSent={}
    Remote.enter({resourceId="office_computer",leaseId="warehouse-gui-lease",revision=0,view={}},remoteState)
    local guestComputer=Remote.sharedComputer
    guestComputer.tab="warehouse"
    local function remoteClick(bay,option)
        local x,y=guestComputer.warehouseButtonCenter(bay,option)
        return Remote.mousepressed(remoteState,x,y,1,function(action,args)
            remoteSent[#remoteSent+1]={action=action,args=Projection.copy(args)};return true
        end)
    end
    check("warehouse_office_guest_uses_live_config_and_offer_filter",guestComputer.warehouseEnabled()
        and guestComputer.warehouseView(remoteState).bays[1].options[2].available
        and not guestComputer.warehouseView(remoteState).bays[2].options[2].available)
    remoteClick("front_left","storage");remoteClick("acknowledge");remoteClick("confirm")
    check("warehouse_office_guest_live_purchase_waits_for_ack",Remote.waiting and guestComputer.warehousePending
        and #remoteSent==1 and remoteSent[1].action=="office_action" and remoteState.money==remoteMoney)
    Remote.applyResult({resourceId="office_computer",action="office_action",revision=1,accepted=false,message="Try again."})
    check("warehouse_office_guest_rejected_purchase_unlocks_retry",not guestComputer.warehousePending
        and not Remote.waiting and guestComputer.warehouseConfirmation~=nil and guestComputer.warehouseMessage=="Try again.")
    remoteClick("confirm")
    Remote.applyResult({resourceId="office_computer",action="office_action",revision=2,accepted=true,message="Storage ordered."})
    check("warehouse_office_guest_purchase_ack_clears_confirmation",not guestComputer.warehousePending
        and not Remote.waiting and guestComputer.warehouseConfirmation==nil and guestComputer.warehouseMessage=="Storage ordered."
        and #remoteSent==2 and remoteSent[1].args.officeIntent.requestId==remoteSent[2].args.officeIntent.requestId
        and remoteState.money==remoteMoney)
    Remote.clear()
    Config.warehouse=priorWarehouse

    local previousLove=love
    local texts={}
    love={timer={getTime=function() return 0 end},mouse={isDown=function() return false end},graphics={
        setColor=function() end,rectangle=function() end,line=function() end,circle=function() end,
        polygon=function() end,setLineWidth=function() end,draw=function() end,
        print=function(text) texts[#texts+1]=text end,printf=function(text) texts[#texts+1]=text end,
    }}
    local drawState=shop()
    local drawScreen=Computer.new({warehouseEnabled=true,remoteCommand=function() end})
    drawScreen.tab="warehouse"
    local drawOkay=pcall(function() drawScreen.draw(drawState,nil,nil,nil) end)
    click(drawScreen,drawState,"front_left","storage")
    local confirmOkay=pcall(function() drawScreen.draw(drawState,nil,nil,nil) end)
    love=previousLove
    local allText=table.concat(texts,"\n")
    check("warehouse_office_page_and_confirmation_render_in_shared_chrome",drawOkay and confirmOkay
        and allText:find("CRITTERNET / WAREHOUSE",1,true)~=nil
        and allText:find("one game day per stage",1,true)~=nil
        and allText:find("upper 5 require a forklift",1,true)~=nil
        and allText:find("I understand: the upper 5 shelves need a forklift",1,true)~=nil)
end

return Test
