local Test = {}
local Screen = require("src.screens.pallet_rack_screen")
local Storage = require("src.pallet_storage")
local Jobs = require("src.jobs")

local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end
local function same(left,right)
    if type(left)~=type(right) then return false end
    if type(left)~="table" then return left==right end
    for key,item in pairs(left) do if not same(item,right[key]) then return false end end
    for key in pairs(right) do if left[key]==nil then return false end end
    return true
end
local function fixture()
    local job=Jobs.createOffer({id="RACK-SCREEN",company="Shelf UI test",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500,1000,1500}})
    Jobs.accept(job)
    local state={jobs={active={job}},procurement={orders={}},storage=Storage.defaultState(),
        warehouse={forkliftOwned=false,bays={front_left={status="complete",optionId="storage"}}},
        palletJack={x=500,y=400,operating=true,operatorPlayerId=1,moving=false,carriedPalletId=job.pallets[1].id},
        forklift={x=500,y=400,operating=false,moving=false,forkHeight=0,targetForkHeight=0,owned=false}}
    state.storage.racks["front_left-rack"]=Storage.rackDefinition("front_left")
    job.pallets[1].location,job.pallets[1].world="on_pallet_jack",{x=500,y=400}
    job.pallets[2].location,job.pallets[2].storage="rack",{rackId="front_left-rack",row=1,column=3}
    job.pallets[2].paper.status="complete"
    job.pallets[3].location,job.pallets[3].storage="rack",{rackId="front_left-rack",row=2,column=4}
    job.pallets[3].wrapped=true
    return state,job.pallets
end
local function context()
    return {playerId=1,vehicle="pallet_jack",near=true,aligned=true,clear=true}
end
local function center(rect) return rect.x+rect.width/2,rect.y+rect.height/2 end

function Test.run(testContext,check)
    local state,pallets=fixture()
    local sent={}
    local screen=Screen.new("front_left-rack",{context=context(),onIntent=function(request) sent[#sent+1]=request end})
    local before=copy(state)
    local view=screen:view(state)
    check("rack_screen_projects_same_canonical_slot_ids", view.slots[1][3].palletId==pallets[2].id
        and view.slots[2][4].palletId==pallets[3].id and view.slots[1][1].palletId==nil
        and view.slots[1][3].variant==2 and view.slots[2][4].variant==3 and same(state,before))
    check("rack_screen_lower_selection_allows_loaded_jack", view.canStore and not view.canRetrieve
        and view.carriedPalletId==pallets[1].id and view.upperLocked)
    local layout=screen:layout()
    check("rack_screen_geometry_places_upper_row_above_lower", layout.slots[2][1].y<layout.slots[1][1].y
        and layout.slots[1][1].source.y==483 and layout.slots[2][1].source.y==240)
    for row=1,2 do for column=1,5 do
        local selected=screen:touchpressed(state,center(layout.slots[row][column]))
        check("rack_screen_touch_selects_"..row.."_"..column,selected and selected.action=="selected"
            and screen:getSelected().row==row and screen:getSelected().column==column and #sent==0 and same(state,before))
    end end
    screen:select(2,1)
    local blocked=screen:activate(state,"store")
    check("rack_screen_upper_row_warns_without_teleporting",blocked.action=="blocked" and blocked.reason=="forklift_required"
        and not screen:view(state).canStore and screen:view(state).warning:find("forklift",1,true) and #sent==0 and same(state,before))
    screen:select(1,1)
    local sendEvent=screen:activate(state,"store")
    check("rack_screen_emits_strict_revisioned_store_intent",sendEvent.action=="intent" and sendEvent.pending
        and #sent==1 and sent[1].action=="store" and sent[1].palletId==pallets[1].id
        and sent[1].expectedRevision==0 and sent[1].rackId=="front_left-rack" and sent[1].row==1
        and sent[1].column==1 and sent[1].vehicle=="pallet_jack" and sent[1].near==nil
        and sent[1].requestId:match("^[%w_.%-]+$") and same(state,before))
    screen:keypressed(state,"return")
    screen:activate(state,"store")
    check("rack_screen_pending_blocks_double_submit",#sent==1 and not screen:view(state).canStore)
    check("rack_screen_wrong_ack_cannot_clear_pending",not screen:resolve("OTHER",true) and screen.pending~=nil)
    check("rack_screen_host_ack_releases_pending",screen:resolve(sent[1].requestId,false,"Shelf changed; try again.")
        and screen.pending==nil and screen:view(state).warning=="Shelf changed; try again.")
    screen:activate(state,"store")
    check("rack_screen_retry_uses_new_request_id",#sent==2 and sent[2].requestId~=sent[1].requestId)
    screen:resolve(sent[2].requestId,false)
    screen:select(1,3)
    local occupied=screen:view(state)
    check("rack_screen_occupied_slot_requires_empty_vehicle",not occupied.canStore and not occupied.canRetrieve
        and occupied.storeReason=="occupied" and occupied.retrieveReason=="loaded")
    state.palletJack.carriedPalletId=nil
    pallets[1].location="warehouse"
    local retrieveBefore=copy(state)
    screen:keypressed(state,"return")
    check("rack_screen_retrieves_selected_stable_id_without_mutation",#sent==3 and sent[3].action=="retrieve"
        and sent[3].palletId==pallets[2].id and sent[3].column==3 and same(state,retrieveBefore))
    screen:resolve(sent[3].requestId,false)
    state.storage.revision=12
    screen:activate(state,"retrieve")
    check("rack_screen_uses_fresh_shared_revision",sent[4].expectedRevision==12)
    screen:resolve(sent[4].requestId,false)

    local hostState=fixture()
    local host=Screen.new("front_left-rack",{context=context(),onIntent=function(request)
        return Storage.apply(hostState,request,context())
    end})
    local hostEvent=host:activate(hostState,"store")
    check("rack_screen_host_callback_is_only_mutation_boundary",hostEvent.action=="intent" and not hostEvent.pending
        and hostState.jobs.active[1].pallets[1].location=="rack" and hostState.storage.revision==1)

    local calls=0
    screen:setContext(function(_,rackId,row,column)
        calls=calls+1
        local result=context(); result.near=false
        check("rack_screen_context_receives_exact_target_"..calls,rackId=="front_left-rack" and row==1 and column==3)
        return result
    end)
    local outOfRange=screen:view(state)
    check("rack_screen_rechecks_host_geometry_each_view",calls==1 and not outOfRange.canRetrieve and outOfRange.retrieveReason=="out_of_range")
    screen:setContext(context())
    for _,entry in ipairs({{key="near",reason="out_of_range"},{key="aligned",reason="not_aligned"},{key="clear",reason="blocked"}}) do
        local invalid=context();invalid[entry.key]=false;screen:setContext(invalid)
        check("rack_screen_disables_"..entry.key,screen:view(state).retrieveReason==entry.reason)
    end
    screen:setContext(context())
    state.palletJack.moving=true
    check("rack_screen_cannot_transfer_while_driving",screen:view(state).retrieveReason=="moving")
    state.palletJack.moving=false
    state.palletJack.operatorPlayerId=2
    check("rack_screen_observer_cannot_use_other_worker_vehicle",screen:view(state).retrieveReason=="not_operator")
    state.palletJack.operatorPlayerId=1
    local viewOnly=Screen.new("front_left-rack",{context=context()})
    check("rack_screen_unwired_presenter_is_read_only",not viewOnly:view(state).canStore and viewOnly:view(state).storeReason=="readonly")
    local hostView=Screen.new("front_left-rack",{context=context(),onIntent=function() return true end})
    local guestView=Screen.new("front_left-rack",{context=context(),onIntent=function() end})
    check("rack_screen_host_guest_share_identical_presenter",same(hostView:view(state),guestView:view(state)))
    local rejectedScreen=Screen.new("front_left-rack",{context=context(),onIntent=function() return false,"stale_revision" end})
    rejectedScreen:select(1,3)
    rejectedScreen:activate(state,"retrieve")
    check("rack_screen_synchronous_rejection_is_recoverable",rejectedScreen.pending==nil
        and rejectedScreen:view(state).warning:find("rack changed",1,true)~=nil)
    local callbackFailure=Screen.new("front_left-rack",{context=context(),onIntent=function() error("offline") end})
    callbackFailure:select(1,3)
    local failedSend=callbackFailure:activate(state,"retrieve")
    check("rack_screen_transport_error_does_not_leave_stuck_pending",failedSend.action=="intent"
        and not failedSend.pending and callbackFailure.pending==nil)

    state.palletJack.operating=false
    state.warehouse.forkliftOwned,state.forklift.owned=true,true
    state.forklift.operating,state.forklift.operatorPlayerId=true,1
    local forkContext=context();forkContext.vehicle="forklift"
    screen:setContext(forkContext);screen:select(2,4)
    check("rack_screen_raised_shelf_requires_matching_fork_height",screen:view(state).retrieveReason=="wrong_height")
    state.forklift.forkHeight,state.forklift.targetForkHeight,state.forklift.lifting=1,1,true
    check("rack_screen_fork_raise_animation_blocks_early_transfer",screen:view(state).retrieveReason=="lifting")
    state.forklift.lifting=false
    check("rack_screen_upper_retrieve_unlocks_after_raise",screen:view(state).canRetrieve and not screen:view(state).upperLocked)
    state.forklift.targetForkHeight=0
    check("rack_screen_fork_lower_target_blocks_transfer",screen:view(state).retrieveReason=="wrong_height")
    state.forklift.targetForkHeight=1
    screen:keypressed(state,"left");screen:keypressed(state,"down")
    check("rack_screen_keyboard_matches_visual_rows",screen:getSelected().row==1 and screen:getSelected().column==3)
    local beforeRepeat=#sent
    screen:keypressed(state,"return",true)
    check("rack_screen_key_repeat_never_repeats_transfer",#sent==beforeRepeat)
    local selected=screen:getSelected();selected.row=99
    check("rack_screen_selection_snapshot_cannot_mutate_view",screen:getSelected().row==1)
    check("rack_screen_rejects_invalid_selection",not screen:select(0,1) and not screen:select(1,6) and not screen:select(1,1.5))
    check("rack_screen_source_variants_preserve_wrapping_precedence",Screen.appearance({wrapped=true,finishedSheets=500})==3
        and Screen.appearance({paper={status="complete"}})==2 and Screen.appearance({paper={status="raw"}})==1)

    for _,dimensions in ipairs({{480,320},{640,400},{960,678},{1920,1080}}) do
        assert(screen:resize(dimensions[1],dimensions[2]))
        local responsive=screen:layout()
        local valid=true
        for row=1,2 do for column=1,5 do
            local r=responsive.slots[row][column]
            valid=valid and r.x>=0 and r.y>=0 and r.x+r.width<=dimensions[1]
                and r.y+r.height<=responsive.details.y and r.height>0 and r.width>0
        end end
        check("rack_screen_responsive_registered_slots_"..dimensions[1],valid
            and responsive.store.y+responsive.store.height<=dimensions[2]
            and responsive.retrieve.x+responsive.retrieve.width<=dimensions[1])
    end
    check("rack_screen_invalid_resize_is_rejected",not screen:resize(0,100) and not screen:resize(600,0))
    screen:resize(960,678)

    local previousLove=love
    local imagePaths,drawn,quads,depth={}, {}, {}, 0
    local font={getHeight=function() return 12 end}
    love={graphics={
        push=function() depth=depth+1 end,pop=function() depth=depth-1 end,
        setColor=function() end,rectangle=function() end,setLineWidth=function() end,
        setFont=function() end,getFont=function() return font end,printf=function() end,
        newQuad=function(x,y,w,h,sw,sh) local q={x=x,y=y,w=w,h=h,sw=sw,sh=sh};quads[#quads+1]=q;return q end,
        newImage=function(path)
            imagePaths[#imagePaths+1]=path
            return {path=path,setFilter=function() end,getDimensions=function()
                if path==Screen.RACK_IMAGE then return 1536,1024 end
                return 2172,724
            end}
        end,
        draw=function(image,quad,...) drawn[#drawn+1]={path=image.path,quad=quad} end,
    }}
    Screen.clearImageCache()
    local drawBefore=copy(state)
    local drawOkay,drawError=pcall(function() screen:draw(state);screen:draw(state) end)
    Screen.clearImageCache()
    love=previousLove
    check("rack_screen_draw_is_read_only_and_restores_graphics",drawOkay and depth==0 and same(state,drawBefore))
    check("rack_screen_lazy_loads_approved_art_once",drawOkay and #imagePaths==2
        and imagePaths[1]==Screen.RACK_IMAGE and imagePaths[2]==Screen.PALLET_IMAGE)
    check("rack_screen_uses_front_art_source_quads_without_raster_edits",drawOkay and #quads==4
        and quads[1].h==740 and quads[2].x==0 and quads[3].x==724 and quads[4].x==1448
        and quads[4].w==724 and #drawn==6)
    local closeBefore=copy(state)
    local closed=screen:keypressed(state,"escape")
    check("rack_screen_close_never_moves_or_deletes_stock",closed.action=="close" and screen.closed
        and screen:activate(state,"store")==nil and same(state,closeBefore))
    local partialState, partialPallets = fixture()
    partialPallets[2].kind, partialPallets[2].productName = "vendor_product", "Maintenance kits"
    partialPallets[2].quantity, partialPallets[2].remainingQuantity, partialPallets[2].unit = 10, 3, "kits"
    local partialScreen = Screen.new("front_left-rack", {context=context()})
    partialScreen:select(1,3)
    check("rack_screen_vendor_label_uses_remaining_physical_quantity",
        partialScreen:view(partialState).detail:find("3 kits",1,true) ~= nil)
    partialPallets[2].remainingQuantity = 0
    check("rack_screen_vendor_label_preserves_zero_instead_of_original_quantity",
        partialScreen:view(partialState).detail:find("0 kits",1,true) ~= nil)
end

return Test
