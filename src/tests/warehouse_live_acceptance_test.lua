-- End-to-end desktop/mobile engine acceptance. Uses the real mask and World
-- collision boundary, with isolated in-memory actors and no save I/O.
local Test={}
local State=require("src.state")
local Config=require("src.config")
local World=require("src.world")
local Office=require("src.office_authority")
local Layout=require("src.warehouse_layout")
local Gameplay=require("src.warehouse_gameplay")
local Calendar=require("src.business_calendar")
local Forklift=require("src.forklift")
local ForkliftCargo=require("src.forklift_cargo")
local Pallets=require("src.pallet_state")
local Rack=require("src.screens.pallet_rack_screen")
local Navigation=require("src.navigation")
local function isolatedWorld()
    local old={}
    for _,name in ipairs({"player","bayDoor","truck","customer","vendor","selectedInteraction",
        "placementSelection","_assets","_state"}) do old[name]=World[name] end
    World.player={}
    World.bayDoor=require("src.bay_door").new(Config.loadingBay)
    World.truck=require("src.truck").new(Config.truck)
    World.customer=require("src.customer").new(Config.customer)
    World.vendor=require("src.customer").new(Config.vendor)
    World.load({id=1,x=500,y=185,character=Config.player.character})
    return function()
        for _,name in ipairs({"player","bayDoor","truck","customer","vendor","selectedInteraction",
            "placementSelection","_assets","_state"}) do World[name]=old[name] end
    end
end
function Test.run(context,check)
    if not context or not context.assets or not context.assets.getData("walkmask") then return end
    local function test(name,value,detail) check("warehouse_acceptance_"..name,value,detail) end
    local restore=isolatedWorld()
    local oldOptions=Config.warehouse
    Config.warehouse={enabled=true,provisionalArt=true,firstStorageOnly=true}
    local okay,reason=pcall(function()
        local assets,state=context.assets,State.new()
        state.money=50000
        local player=World.player
        World.updateWarehouse(0,state,assets)
        local saves=0
        local office=Office.command({state=state,world=World,warehouseEnabled=true,
            warehouseFirstStorageOnly=true,save=function() saves=saves+1 end})
        local function buy(intent)
            return office.perform({},player,assert(office.normalize({officeIntent=intent})))
        end
        local bought,code=buy({kind="buy_upgrade",bayId="front_left",optionId="storage",
            requestId="ACCEPT-STORAGE",confirmUpperRows=true})
        test("real_computer_purchase",bought and state.money==48800 and saves==1,code)
        bought,code=buy({kind="buy_forklift",requestId="ACCEPT-FORKLIFT"})
        test("real_computer_forklift_purchase",bought and state.money==15800 and saves==2,code)
        World.updateWarehouse(0,state,assets)
        test("actual_spawn_mask_and_collision_clear",state.forklift.owned
            and state.forklift.x==Layout.forkliftSpawn().x and state.forklift.y==Layout.forkliftSpawn().y)
        local interactionScanOkay,interactionScanError=pcall(World.update,0,0,0,assets,state)
        test("owned_forklift_world_interaction_is_declared",interactionScanOkay,interactionScanError)
        test("phone_notice_precedes_arrival",state.workPhone.incoming
            and state.workPhone.incoming.kind=="construction_notice" and not state.constructionWorker)
        test("locked_bay_remains_black_and_unwalkable",not Navigation.isWalkable(Gameplay.assets(assets,state),100,580,{}))
        Calendar.update(state,2/24*Config.businessCalendar.secondsPerDay)
        World.updateWarehouse(0,state,assets)
        test("builder_uses_glass_front_entrance",state.constructionWorker
            and state.constructionWorker.x==Config.customer.route[1].x
            and state.constructionWorker.y==Config.customer.route[1].y)
        local reached=false
        for _=1,1500 do
            World.updateWarehouse(0.1,state,assets)
            if state.constructionWorker and state.constructionWorker.phase=="working" then reached=true;break end
        end
        test("builder_physically_reaches_real_mask_workpoint",reached,
            state.constructionWorker and (state.constructionWorker.x..","..state.constructionWorker.y))
        test("builder_walk_distance_not_time_fake",state.constructionWorker.animationDistance>400)
        local stage=state.warehouse.projects[1]
        local start=Calendar.absoluteHours(state)
        for day=1,4 do
            if context.captureWarehouse then context.captureWarehouse("stage-"..day,state,World) end
            Calendar.update(state,(24-0.001)/24*Config.businessCalendar.secondsPerDay)
            World.updateWarehouse(0,state,assets)
            test("stage_"..day.."_requires_full_day",stage.stage==day and stage.phase=="building")
            Calendar.update(state,0.001/24*Config.businessCalendar.secondsPerDay)
            World.updateWarehouse(0,state,assets)
            test("stage_"..day.."_advances_at_full_day",stage.stage==math.min(day+1,4)
                and (day<4 or stage.phase=="complete"))
        end
        test("completion_after_96_game_hours",math.abs(stage.completedAtHours-start-96)<0.0001
            and state.storage.racks["front_left-rack"]
            and Navigation.isWalkable(Gameplay.assets(assets,state),100,580,{}))
        for _=1,1500 do
            World.updateWarehouse(0.1,state,assets)
            if not state.constructionWorker then break end
        end
        test("builder_leaves_via_front_entrance",not state.constructionWorker and stage.workerReleasedAtHours~=nil)
        player.x,player.y=state.forklift.x+60,state.forklift.y
        local authenticated={id=player.id,x=player.x,y=player.y}
        local success,why=World.warehouseCommand(authenticated,state,{kind="operate"})
        test("mount_actual_forklift",success and state.forklift.operatorPlayerId==1,why)
        test("detached_authority_mount_updates_local_player",player.x==state.forklift.x
            and player.y==state.forklift.y and player.x==authenticated.x)
        local px,py=Forklift.dropPosition(state,Config.forklift)
        local pallet={id="ACCEPT-PALLET",number=1,location="warehouse",status="raw",wrapped=true,
            quantity=500,remainingSheets=473,paper={status="complete",marker="unchanged-original"},
            world={x=px,y=py,direction="northwest",spawnProgress=1}}
        state.jobs.active={{id="ACCEPT-JOB",pallets={pallet}}}
        local originalPaper=pallet.paper
        test("real_floor_pickup_candidate",World.warehouseCandidate(state)==pallet.id)
        success,why=World.warehouseCommand(player,state,{kind="pickup",palletId=pallet.id})
        test("physical_stock_picked_up",success and pallet.location=="on_forklift",why)
        local lift=state.forklift
        local oldX,oldY=lift.x,lift.y
        World.updateNetworkForklift(player,0.1,-1,0,assets,state)
        test("loaded_drive_requires_travel_height",lift.x==oldX and lift.y==oldY)
        World.warehouseCommand(player,state,{kind="set_height",height=0.08})
        World.updateWarehouse(0.3,state,assets)
        -- One straight real movement path from the registered spawn, no
        -- position reassignment or bypassed mask/collision in the drive test.
        for _=1,30 do
            if lift.x<=340 then break end
            World.updateNetworkForklift(player,0.1,-1,0,assets,state)
        end
        World.updateNetworkForklift(player,0.1,0,0,assets,state)
        test("real_vehicle_drives_to_rack_approach",lift.x<=340 and lift.x>=320
            and lift.y==oldY and pallet.world.x==lift.x, "x="..lift.x.." y="..lift.y)
        local Layered=require("src.forklift_layered_presentation")
        local headings={"northwest","north","northeast","east","southeast","south","southwest","west"}
        local rackPoses,rackDiagnostics={},{}
        local initialRackApproach={x=lift.x,y=lift.y,direction=lift.direction}
        local scale=(Config.forklift.drawScale or 0.22)*(Config.forklift.visualScaleMultiplier or 1)
        local function scanRackPoses()
            local poses,diagnostics={},{}
            for row=1,2 do for column=1,5 do
                local target=Layout.rackPoint("front_left-rack",row,column)
                local slotDiagnostics={}
                for _,heading in ipairs(headings) do
                    local pose={owned=true,operating=true,direction=heading,forkHeight=row==2 and 1 or 0,
                        targetForkHeight=row==2 and 1 or 0,lifting=false,moving=false,carriedPalletId=pallet.id,
                        x=0,y=0}
                    local plan=Layered.plan(pose,{review=true,scale=scale})
                    if plan then
                        pose.x,pose.y=target.x-(plan.loadX-pose.x),target.y-(plan.loadY-pose.y)
                        lift.x,lift.y,lift.direction=pose.x,pose.y,heading
                        lift.forkHeight,lift.targetForkHeight=pose.forkHeight,pose.targetForkHeight
                        lift.lifting,lift.moving=false,false
                        ForkliftCargo.sync(state,Config.forklift)
                        local access=World.warehouseRackContext(player,state,"front_left-rack",row,column)
                        if access.near and access.clear and access.aligned then
                            poses[row..":"..column]={x=pose.x,y=pose.y,direction=heading}
                            break
                        end
                        slotDiagnostics[#slotDiagnostics+1]=heading.."="..tostring(access.near).."/"
                            ..tostring(access.footprintClear).."/"..tostring(access.obstaclesClear).."/"
                            ..tostring(access.aligned).."/"..tostring(access.loadAligned)
                    end
                end
                diagnostics[row..":"..column]=table.concat(slotDiagnostics,",")
            end end
            return poses,diagnostics
        end
        local originalLoadedWidth,originalLoadedHeight=Config.forklift.loadedCollisionHalfWidth,
            Config.forklift.loadedCollisionHalfHeight
        rackPoses,rackDiagnostics=scanRackPoses()
        Config.forklift.loadedCollisionHalfWidth,Config.forklift.loadedCollisionHalfHeight=
            originalLoadedWidth,originalLoadedHeight
        local poseCount=0
        for _ in pairs(rackPoses) do poseCount=poseCount+1 end
        test("all_ten_rack_slots_have_a_clear_loaded_forklift_pose",poseCount==10,
            "found="..poseCount.." "..table.concat((function() local out={} for key,value in pairs(rackDiagnostics) do
                out[#out+1]=key..":"..value end table.sort(out);return out end)()," "))
        local rackPose=rackPoses["2:3"]
        test("upper_rack_pose_matches_selected_slot_load_anchor",rackPose~=nil,
            "valid="..table.concat((function() local out={} for key,value in pairs(rackPoses) do
                out[#out+1]=key.."/"..value.direction end table.sort(out);return out end)(),","))
        assert(rackPose,"upper rack pose missing")
        lift.x,lift.y,lift.direction=initialRackApproach.x,initialRackApproach.y,initialRackApproach.direction
        lift.forkHeight,lift.targetForkHeight=Config.forklift.travelHeight,Config.forklift.travelHeight
        lift.lifting,lift.moving=false,false
        ForkliftCargo.sync(state,Config.forklift)
        local function driveTo(targetX,targetY,maxSteps)
            maxSteps=maxSteps or 160
            for _=1,maxSteps do
                local deltaX,deltaY=targetX-lift.x,targetY-lift.y
                if math.abs(deltaX)<=4 then deltaX=0 end
                if math.abs(deltaY)<=4 then deltaY=0 end
                if deltaX==0 and deltaY==0 then break end
                local oldX,oldY=lift.x,lift.y
                World.updateNetworkForklift(player,0.1,deltaX==0 and 0 or deltaX>0 and 1 or -1,
                    deltaY==0 and 0 or deltaY>0 and 1 or -1,assets,state)
                if lift.x==oldX and lift.y==oldY then break end
            end
            World.updateNetworkForklift(player,0.1,0,0,assets,state)
            return math.abs(targetX-lift.x)<=8 and math.abs(targetY-lift.y)<=8
        end
        local entered=driveTo(352,617) and driveTo(312,617) and driveTo(312,624)
            and lift.x<320 and lift.y>615
        test("loaded_vehicle_drives_into_service_aisle",entered,
            "x="..lift.x.." y="..lift.y)
        local aisleApproach=driveTo(rackPose.x,624)
            and driveTo(rackPose.x,rackPose.y)
        test("loaded_vehicle_drives_to_selected_upper_slot",aisleApproach,
            "x="..lift.x.." y="..lift.y.." heading="..lift.direction)
        test("real_rack_approach_uses_clearance_and_alignment",aisleApproach
            and lift.direction==rackPose.direction,
            "expected="..rackPose.direction.." actual="..lift.direction)
        local access=World.warehouseRackContext(player,state,"front_left-rack",2,3)
        test("real_mask_rack_clearance_while_traveling",access.near and access.clear,
            "near="..tostring(access.near).." clear="..tostring(access.clear).." aligned="..tostring(access.aligned))
        local store={kind="store",requestId="ACCEPT-UPPER-STORE",expectedRevision=0,vehicle="forklift",
            palletId=pallet.id,rackId="front_left-rack",row=2,column=3}
        success,why=World.warehouseCommand(player,state,store)
        test("upper_shelf_rejects_unraised_forks",not success and why=="wrong_fork_height",why)
        World.warehouseCommand(player,state,{kind="set_height",height=1})
        World.updateWarehouse(3,state,assets)
        access=World.warehouseRackContext(player,state,"front_left-rack",2,3)
        test("raised_load_anchor_aligns_with_selected_upper_slot",access.near and access.clear and access.aligned,
            "near="..tostring(access.near).." clear="..tostring(access.clear).." aligned="..tostring(access.aligned))
        if context.captureWarehouse then
            context.captureWarehouse("forklift-upper-rack-alignment",state,World,nil,
                {x=205,y=500,zoom=1.5})
        end
        success,why=World.warehouseCommand(player,state,store)
        test("upper_shelf_accepts_raised_forks",success and pallet.location=="rack"
            and pallet.storage.row==2 and pallet.storage.column==3 and not lift.carriedPalletId,why)
        local rack=Rack.new("front_left-rack",{
            requestPrefix="ACCEPT-UI",context=function(_,rackId,row,column)
                return World.warehouseRackContext(player,state,"front_left-rack",row,column)
            end,
            onIntent=function(request)
                local intent={kind=request.action}
                for key,value in pairs(request) do if key~="action" then intent[key]=value end end
                return World.warehouseCommand(player,state,intent)
            end})
        local WorldRackPresentation=require("src.warehouse_rack_presentation")
        local worldRackPlan=WorldRackPresentation.plan(state,"front_left",{review=true})
        local upperAnchor=WorldRackPresentation.slotPoint(worldRackPlan,2,3)
        test("real_world_rack_registers_upper_stock_anchor",worldRackPlan~=nil and upperAnchor~=nil
            and upperAnchor.y<upperAnchor.groundY and pallet.location=="rack"
            and pallet.storage.row==2 and pallet.storage.column==3)
        rack:select(2,3)
        test("real_rack_gui_enables_retrieval",rack:view(state).canRetrieve)
        if context.captureWarehouse then
            context.captureWarehouse("rack-world-upper-stock",state,World,nil,
                {x=190,y=470,zoom=1.65})
            context.captureWarehouse("completed-world",state,World)
            context.captureWarehouse("rack-inventory",state,World,rack)
        end
        local originalVariantFields={kind=pallet.kind,packaging=pallet.packaging,packagedAs=pallet.packagedAs,
            wrapped=pallet.wrapped,wrapProgress=pallet.wrapProgress,press=pallet.press,productName=pallet.productName,
            productId=pallet.productId,quantity=pallet.quantity,remainingQuantity=pallet.remainingQuantity,unit=pallet.unit}
        local function previewRackVariant(name,fields,expected)
            for key in pairs(originalVariantFields) do pallet[key]=nil end
            for key,value in pairs(fields) do pallet[key]=value end
            test("rack_"..name.."_selects_registered_stock_art",Rack.appearance(pallet)==expected,
                "variant="..tostring(Rack.appearance(pallet)))
            if context.captureWarehouse then context.captureWarehouse("rack-"..name.."-stock",state,World,rack) end
        end
        previewRackVariant("printed",{press={completedColors=1}},4)
        previewRackVariant("partial-wrap",{wrapProgress=0.5},5)
        previewRackVariant("boxed",{packaging="boxed"},6)
        previewRackVariant("supplier",{kind="vendor_product",productName="Print shop supplies",
            productId="maintenance-kit",quantity=12,remainingQuantity=12,unit="kits"},7)
        for key in pairs(originalVariantFields) do pallet[key]=nil end
        for key,value in pairs(originalVariantFields) do pallet[key]=value end
        local retrieveButton=rack:layout().retrieve
        local uiResult=rack:mousepressed(state,retrieveButton.x+10,retrieveButton.y+10,1)
        test("upper_shelf_retrieves_original_stock",uiResult and uiResult.action=="intent"
            and pallet.location=="on_forklift" and pallet.paper==originalPaper
            and pallet.remainingSheets==473 and pallet.wrapped,rack.message)
        test("single_canonical_pallet_after_round_trip",#Pallets.items(state)==1 and Pallets.validate(state)
            and state.storage.revision==2)
        if context.captureWarehouse then context.captureWarehouse("retrieved-load",state,World) end
        -- A lost operator must leave the original load suspended on the forks.
        -- The parked renderer uses the same raised pose with an empty seat.
        local released,releaseCode,exit=World.forceReleaseForklift(player,state)
        test("parked_raised_load_preserves_custody",not lift.operating and lift.forkHeight==1
            and lift.carriedPalletId==pallet.id and pallet.location=="on_forklift"
            and released and exit and player.x==exit.x and player.y==exit.y
            and (player.x~=lift.x or player.y~=lift.y),releaseCode)
        if context.captureWarehouse then
            context.captureWarehouse("parked-raised-load",state,World)
            local originalDirection=lift.direction
            local originalHeight=lift.forkHeight
            local function syncView()
                local synced,reason=ForkliftCargo.sync(state,Config.forklift)
                assert(synced or reason=="unchanged",reason)
            end
            for _,pose in ipairs({{name="low",height=0},{name="mid",height=0.5},
                {name="high",height=1}}) do
                lift.forkHeight,lift.targetForkHeight,lift.lifting=pose.height,pose.height,false
                for _,direction in ipairs({"northwest","north","northeast","east",
                    "southeast","south","southwest","west"}) do
                    lift.direction=direction
                    syncView()
                    context.captureWarehouse("forklift-parked-"..pose.name.."-"..direction,
                        state,World,nil,{x=lift.x,y=lift.y-95,zoom=2})
                end
            end
            lift.direction,lift.forkHeight,lift.targetForkHeight=originalDirection,originalHeight,originalHeight
            syncView()
        end
        success,why=World.warehouseCommand(player,state,{kind="operate"})
        local forkX,forkY=Forklift.dropPosition(state,Config.forklift)
        test("remount_preserves_raised_load",success and lift.operating and lift.operatorPlayerId==player.id
            and lift.forkHeight==1 and lift.carriedPalletId==pallet.id,
            tostring(why).." player="..tostring(player.x)..","..tostring(player.y)
                .." lift="..tostring(lift.x)..","..tostring(lift.y)
                .." direction="..tostring(lift.direction)
                .." fork="..tostring(forkX)..","..tostring(forkY)
                .." exit="..tostring(exit and exit.x)..","..tostring(exit and exit.y))
        -- Return through the actual floor corridor before testing a two-high
        -- floor stack. Only the test support stock is spawned; vehicle motion,
        -- collision, targeting, toolbar and transfer authority are the live path.
        World.warehouseCommand(player,state,{kind="set_height",height=0.08})
        World.updateWarehouse(3,state,assets)
        local leftServiceAisle=driveTo(rackPose.x,624) and driveTo(312,624)
            and driveTo(312,617) and driveTo(352,617)
            and driveTo(352,515) and driveTo(460,515)
        test("loaded_vehicle_returns_through_service_aisle",leftServiceAisle,
            "x="..lift.x.." y="..lift.y)
        World.updateNetworkForklift(player,0.01,-1,0,assets,state)
        World.updateNetworkForklift(player,0.1,0,0,assets,state)
        test("real_vehicle_returns_to_stack_approach",lift.x>=450 and lift.x<=470 and lift.direction=="west")
        state.jobs.active[1].sourceSize={width=20,height=16}
        local base={id="ACCEPT-STACK-BASE",number=1,location="warehouse",status="raw",wrapped=true,
            remainingSheets=500,paper={marker="original-support"},world={x=lift.x-100,y=lift.y,direction="northwest",spawnProgress=1}}
        state.jobs.active[2]={id="ACCEPT-STACK-BASE-JOB",sourceSize={width=20,height=16},pallets={base}}
        local controls=require("src.screens.warehouse_controls").new({state=state,world=World,
            player=function() return player end,
            command=function(intent)
                local accepted,_,message=World.warehouseCommand(player,state,intent)
                return accepted,message
            end})
        state.screen="world"
        local target=World.warehouseStackCandidate(state)
        test("real_floor_stack_targets_exact_support",target and target.palletId==pallet.id and target.supportPalletId==base.id)
        controls:keypressed("k")
        test("real_stack_control_requires_raised_forks",pallet.location=="on_forklift" and state.storage.revision==2)
        controls:keypressed("r")
        World.updateWarehouse(3,state,assets)
        controls:keypressed("k")
        test("real_stack_control_places_two_high",pallet.location=="stacked" and pallet.storage.supportPalletId==base.id
            and not lift.carriedPalletId and Pallets.validate(state) and state.storage.revision==3,state.message)
        if context.captureWarehouse then context.captureWarehouse("floor-stack",state,World) end
        target=World.warehouseStackCandidate(state)
        test("real_take_top_targets_original_upper_pallet",target and target.kind=="unstack" and target.palletId==pallet.id
            and target.supportPalletId==base.id and World.warehouseCandidate(state)==nil)
        local takeButton
        for _,button in ipairs(controls:buttons()) do if button.key=="k" then takeButton=button end end
        test("real_floor_stack_has_touch_target",takeButton and takeButton.width>=44 and takeButton.height>=44)
        controls:mousepressed(takeButton.x+10,takeButton.y+10,1)
        test("real_touch_take_top_restores_original_cargo",pallet.location=="on_forklift" and lift.carriedPalletId==pallet.id
            and pallet.paper==originalPaper and pallet.remainingSheets==473 and base.location=="warehouse"
            and base.remainingSheets==500 and #Pallets.items(state)==2 and Pallets.validate(state) and state.storage.revision==4,state.message)
        if context.captureWarehouse then context.captureWarehouse("floor-stack-retrieved",state,World) end
        World.warehouseCommand(player,state,{kind="set_height",height=0})
        World.updateWarehouse(3,state,assets)
        authenticated={id=player.id,x=player.x,y=player.y}
        success,why=World.warehouseCommand(authenticated,state,{kind="release"})
        test("detached_authority_release_updates_local_player",success and not lift.operating
            and player.x==authenticated.x and player.y==authenticated.y
            and (player.x~=lift.x or player.y~=lift.y),why)

        -- Render every added room option in the actual LÖVE world so the
        -- source registrations are checked against the real scene scale.
        local Renderer=require("src.warehouse_renderer")
        local Construction=require("src.warehouse_construction_presentation")
        local oldBays={front_left=state.warehouse.bays.front_left,
            front_right=state.warehouse.bays.front_right}
        local oldProjects,oldActive=state.warehouse.projects,state.warehouse.activeProjectId
        local oldWorker=state.constructionWorker
        state.constructionWorker=nil
        state.warehouse.projects={}
        state.warehouse.activeProjectId=nil
        state.warehouse.bays.front_left={status="complete",optionId="storage"}
        state.warehouse.bays.front_right={status="complete",optionId="storage"}
        for _,bayId in ipairs(Layout.BAY_IDS) do
            state.warehouse.projects={}
            state.warehouse.activeProjectId=nil
            state.warehouse.bays.front_left={status="complete",optionId="storage"}
            state.warehouse.bays.front_right={status="complete",optionId="storage"}
            local side=bayId=="front_right" and "right" or "left"
            for _,optionId in ipairs({"storage","floor","breakroom"}) do
                state.warehouse.bays[bayId]={status="complete",optionId=optionId}
                local plan=optionId=="storage" and Renderer.rackPlan(state,bayId)
                    or optionId=="breakroom" and Renderer.breakroomPlan(state,bayId)
                test(side.."_bay_finished_"..optionId.."_has_registered_art",
                    optionId=="floor" or plan~=nil)
                test(side.."_bay_"..optionId.."_capture_has_no_stale_build",#state.warehouse.projects==0
                    and state.warehouse.activeProjectId==nil and state.warehouse.bays.front_left.status=="complete"
                    and state.warehouse.bays.front_right.status=="complete"
                    and not Renderer.constructionPlan(state,"front_left")
                    and not Renderer.constructionPlan(state,"front_right"))
                if context.captureWarehouse then
                    context.captureWarehouse(side.."-"..optionId.."-complete",state,World)
                end
            end
            for _,optionId in ipairs({"floor","breakroom"}) do
                for stage=1,4 do
                    local project={id="ACCEPT-VISUAL-"..bayId.."-"..optionId.."-"..stage,
                        bayId=bayId,optionId=optionId,phase="building",stage=stage}
                    state.warehouse.projects[#state.warehouse.projects+1]=project
                    state.warehouse.activeProjectId=project.id
                    state.warehouse.bays[bayId]={status="building",optionId=optionId,projectId=project.id}
                    local plan=Construction.plan(state,bayId,{review=true})
                    test(side.."_bay_"..optionId.."_construction_stage_"..stage.."_registered",
                        plan and plan.stage==stage and plan.mirrorX==(bayId=="front_right"))
                    if context.captureWarehouse then
                        context.captureWarehouse(side.."-"..optionId.."-stage-"..stage,state,World)
                    end
                    state.warehouse.projects[#state.warehouse.projects]=nil
                end
            end
        end
        state.warehouse.bays.front_right={status="building",optionId="storage",projectId="ACCEPT-VISUAL-STORAGE"}
        local storageProject={id="ACCEPT-VISUAL-STORAGE",bayId="front_right",optionId="storage",phase="building",stage=3}
        state.warehouse.projects[#state.warehouse.projects+1]=storageProject
        state.warehouse.activeProjectId=storageProject.id
        local storagePlan=Construction.plan(state,"front_right",{review=true})
        test("right_bay_storage_construction_is_mirrored",storagePlan and storagePlan.mirrorX)
        if context.captureWarehouse then context.captureWarehouse("right-storage-stage-3",state,World) end

        -- Capture the five authored rabbit push views at live warehouse scale.
        -- The remaining diagonal sectors use the registered mirrored views.
        local oldJack=state.palletJack
        local playerPose={x=World.player.x,y=World.player.y,moving=World.player.moving,
            velocityX=World.player.velocityX,velocityY=World.player.velocityY,
            intentX=World.player.intentX,intentY=World.player.intentY,
            animationDistance=World.player.animationDistance}
        state.warehouse.projects={}
        state.warehouse.activeProjectId=nil
        state.constructionWorker=nil
        state.warehouse.bays.front_left={status="complete",optionId="storage"}
        state.warehouse.bays.front_right={status="complete",optionId="storage"}
        state.palletJack={x=560,y=520,direction="east",operating=true,operatorPlayerId=1,
            moving=true,animationClock=0,carriedPalletId=nil}
        local CharacterAnimation=require("src.character_animation")
        local pushViews={
            {name="east",x=1,y=0,direction="east",action="push"},
            {name="north",x=0,y=-1,direction="north",action="push_north"},
            {name="northeast",x=1,y=-1,direction="northeast",action="push_northeast"},
            {name="southeast",x=1,y=1,direction="southeast",action="push_southeast"},
            {name="south",x=0,y=1,direction="south",action="push_south"},
        }
        for _,view in ipairs(pushViews) do
            state.palletJack.direction=view.direction
            local operatorX,operatorY=require("src.pallet_jack").operatorPosition(state,Config.palletJack)
            World.player.x,World.player.y=operatorX,operatorY
            World.player.moving=true
            World.player.velocityX,World.player.velocityY=view.x,view.y
            World.player.intentX,World.player.intentY=view.x,view.y
            World.player.animationDistance=Config.player.walkPixelsPerFrame*2
            local action=CharacterAnimation.directionalPalletJackPushAction(view.x,view.y)
            test("pallet_jack_"..view.name.."_selects_registered_push_action",
                action==view.action and (not context.characters
                    or context.characters.hasAction(Config.player.character,action)),tostring(action))
            if context.captureWarehouse then
                context.captureWarehouse("pallet-jack-push-"..view.name,state,World,nil,
                    {x=560,y=520,zoom=1.65})
            end
        end
        state.palletJack=oldJack
        for key,value in pairs(playerPose) do World.player[key]=value end
        state.warehouse.bays.front_left,state.warehouse.bays.front_right=
            oldBays.front_left,oldBays.front_right
        state.warehouse.projects,state.warehouse.activeProjectId=oldProjects,oldActive
        state.constructionWorker=oldWorker
    end)
    Config.warehouse=oldOptions
    restore()
    if not okay then error(reason) end
end
return Test
