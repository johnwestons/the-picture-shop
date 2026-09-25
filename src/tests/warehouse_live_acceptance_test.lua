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
        state.money=30000
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
        test("real_computer_purchase",bought and state.money==25500 and saves==1,code)
        bought,code=buy({kind="buy_forklift",requestId="ACCEPT-FORKLIFT"})
        test("real_computer_forklift_purchase",bought and state.money==19000 and saves==2,code)
        World.updateWarehouse(0,state,assets)
        test("actual_spawn_mask_and_collision_clear",state.forklift.owned
            and state.forklift.x==Layout.forkliftSpawn().x and state.forklift.y==Layout.forkliftSpawn().y)
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
        local access=World.warehouseRackContext(player,state,"front_left-rack")
        test("real_mask_rack_clearance_and_alignment",access.near and access.clear and access.aligned)
        local store={kind="store",requestId="ACCEPT-UPPER-STORE",expectedRevision=0,vehicle="forklift",
            palletId=pallet.id,rackId="front_left-rack",row=2,column=3}
        success,why=World.warehouseCommand(player,state,store)
        test("upper_shelf_rejects_unraised_forks",not success and why=="wrong_fork_height",why)
        World.warehouseCommand(player,state,{kind="set_height",height=1})
        World.updateWarehouse(3,state,assets)
        success,why=World.warehouseCommand(player,state,store)
        test("upper_shelf_accepts_raised_forks",success and pallet.location=="rack"
            and pallet.storage.row==2 and pallet.storage.column==3 and not lift.carriedPalletId,why)
        local rack=Rack.new("front_left-rack",{
            requestPrefix="ACCEPT-UI",context=function()return World.warehouseRackContext(player,state,"front_left-rack")end,
            onIntent=function(request)
                local intent={kind=request.action}
                for key,value in pairs(request) do if key~="action" then intent[key]=value end end
                return World.warehouseCommand(player,state,intent)
            end})
        rack:select(2,3)
        test("real_rack_gui_enables_retrieval",rack:view(state).canRetrieve)
        if context.captureWarehouse then
            context.captureWarehouse("completed-world",state,World)
            context.captureWarehouse("rack-inventory",state,World,rack)
        end
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
        Forklift.forceRelease(state,Config.forklift,player.id)
        player.x,player.y=lift.x+60,lift.y
        test("parked_raised_load_preserves_custody",not lift.operating and lift.forkHeight==1
            and lift.carriedPalletId==pallet.id and pallet.location=="on_forklift")
        if context.captureWarehouse then context.captureWarehouse("parked-raised-load",state,World) end
        success,why=World.warehouseCommand(player,state,{kind="operate"})
        test("remount_preserves_raised_load",success and lift.operating and lift.operatorPlayerId==player.id
            and lift.forkHeight==1 and lift.carriedPalletId==pallet.id,why)
        -- Return through the actual floor corridor before testing a two-high
        -- floor stack. Only the test support stock is spawned; vehicle motion,
        -- collision, targeting, toolbar and transfer authority are the live path.
        World.warehouseCommand(player,state,{kind="set_height",height=0.08})
        World.updateWarehouse(3,state,assets)
        for _=1,30 do
            if lift.x>=455 then break end
            World.updateNetworkForklift(player,0.1,1,0,assets,state)
        end
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
    end)
    Config.warehouse=oldOptions
    restore()
    if not okay then error(reason) end
end
return Test
