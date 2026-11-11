local Test={}
function Test.run(context,check)
    local R=context.appRuntime
    local C=require('src.commute.runtime')
    local Opening=require('src.story_opening')
    local Intro=require('src.story_intro')
    local Condition=require('src.warehouse_condition')
    local Trip=require('src.commute.trip')
    local Routes=require('src.commute.routes')
    local Controls=require('src.shop_room_controls')
    local function start(slot,seed)
        local payload=assert(R.Save.newGame(slot,{startMode='story',townSeed=seed}))
        assert(R.startGame(payload,'new'))
        assert(Opening.finish(R,true))
        check('story_free_roam_handoff_'..slot,R.state.warehouse.condition.grandpaMet
            and not Intro.dialogueOpen(R) and C.activeWaypoint(R)==nil
            and not Condition.openForBusiness(R.state)
            and R.state.message:find('explore')~=nil)
        check('story_free_roam_has_no_choice_panel_'..slot,not Intro.pointer(R,400,210)
            and pcall(Intro.drawHud,R))
    end
    local function enter(id,label)
        local world=C.world(R)
        local site=assert(world.sites.byId[id])
        local part=assert(C.localPart(R))
        local route=assert(Routes.new(world.roads):findFromPoint(
            part.rider.ped.x,part.rider.ped.z,id))
        check('story_free_roam_connected_road_'..label,#route.points>2 and route.length>20)
        part.rider.ped.x,part.rider.ped.z=site.door.x,site.door.z
        part.rider.ped.speed,part.rider.ped.vx,part.rider.ped.vz=0,0,0
        C.syncPlayer(R.World.player,part)
        check('story_free_roam_door_prompt_'..label,
            C.controlContext(R,part).worldActionLabel=='ENTER')
        assert(C.perform(R,'worldAction'))
        check('story_free_roam_correct_door_'..label,R._commute.doorTransition
            and R._commute.doorTransition.action==(id=='warehouse' and 'enterwork' or 'enterhome'))
        for _=1,8 do
            if R.World.player.sceneId~='commute' then break end
            C.update(R,.5,0,0,false)
        end
        check('story_free_roam_entered_'..label,R.World.player.sceneId==
            (id=='warehouse' and 'warehouse' or 'home') and C.localPart(R)==nil)
        check('story_free_roam_visit_recorded_'..label,id=='warehouse'
            and R.state.warehouse.condition.visitedShop or R.state.warehouse.condition.visitedApartment)
    end
    local function explore(label)
        local target=assert(require('src.home_travel').target(R.World.player,R.state))
        R.World.player.x,R.World.player.y=target.x,target.y
        local okay,_,message=require('src.weekend_runtime').command(R,R.World.player,'explore')
        assert(okay,message)
        C.restore(R)
        check('story_free_roam_explore_after_'..label,R.World.player.sceneId=='commute'
            and C.localPart(R)~=nil and Trip.valid(R.state.home.commute,R.state.home)
            and C.activeWaypoint(R)==nil)
    end
    local function firstRepair(label)
        local c=R.state.warehouse.condition
        check('story_free_roam_shop_stays_closed_'..label,not Condition.openForBusiness(R.state)
            and not c.powerConnected and not c.breakerRepaired)
        Controls.open(R,'restoration')
        Controls.selected=1;Controls.keypressed('return',R)
        check('story_free_roam_power_paid_'..label,c.powerConnected
            and #R.state.receipts.entries==1)
        R.World.player.x,R.World.player.y=Condition.anchors.breaker.x,Condition.anchors.breaker.y
        Controls.selected=3;Controls.keypressed('return',R)
        check('story_free_roam_breaker_repaired_'..label,c.breakerRepaired
            and Condition.powered(R.state) and Condition.stage(R.state)==0)
        Controls.keypressed('escape',R)
        check('story_free_roam_repair_persisted_'..label,
            assert(R.Save.load(R.state.activeSlot)).state.warehouse.condition.breakerRepaired)
    end
    local function cleanShopFloors()
        local c=R.state.warehouse.condition
        Controls.open(R,'restoration')
        Controls.selected=2;Controls.keypressed('return',R)
        check('story_restoration_water_paid_in_shop',c.waterConnected and #R.state.receipts.entries==2)
        Controls.keypressed('escape',R)
        for index,region in ipairs({'west','center','east'}) do
            local point=Condition.anchors[region]
            R.World.player.x,R.World.player.y=point.x,point.y
            local selected=R.World.interactionAt(point.x,point.y)
            check('story_restoration_'..region..'_floor_prompt',selected and selected.kind=='restoration'
                and selected.target.restorationAction=='clean_'..region)
            assert(Controls.keypressed('e',R))
            check('story_restoration_'..region..'_checklist_opens_on_action',
                R.state.screen=='shop_rooms' and Controls.selected==index+3)
            Controls.keypressed('return',R)
            check('story_restoration_'..region..'_saved_after_cleanup',
                c.cleaned[region] and Condition.stage(R.state)==index
                    and assert(R.Save.load(R.state.activeSlot)).state.warehouse.condition.cleaned[region])
            Controls.keypressed('escape',R)
        end
        local paint=Condition.anchors.paint
        R.World.player.x,R.World.player.y=paint.x,paint.y
        local selected=R.World.interactionAt(paint.x,paint.y)
        check('story_restoration_paint_prompt_after_cleanup',selected and selected.kind=='restoration'
            and selected.target.restorationAction=='repaint')
        assert(Controls.keypressed('e',R))
        check('story_restoration_paint_checklist_opens_on_action',
            R.state.screen=='shop_rooms' and Controls.selected==7 and Controls.page==2)
        Controls.keypressed('return',R)
        check('story_restoration_repaint_persists_without_opening_early',
            c.repainted and Condition.complete(R.state) and not Condition.openForBusiness(R.state)
                and assert(R.Save.load(R.state.activeSlot)).state.warehouse.condition.repainted)
        Controls.keypressed('escape',R)
    end

    -- From the farm, either entrance works without selecting a route.
    start(1,712345)
    local map=require('src.commute.route_map').new(C.world(R))
    local markers=map:snapshot({x=0,y=0,width=960,height=678},C.localPart(R).rider.ped,
        {home=R.state.home.apartmentId})
    local apartmentMarked,shopMarked=false,false
    for _,marker in ipairs(markers.buildings) do
        apartmentMarked=apartmentMarked or marker.id==R.state.home.apartmentId and marker.home
        shopMarked=shopMarked or marker.id=='warehouse'
    end
    check('story_free_roam_map_lists_apartment_and_shop',apartmentMarked and shopMarked)
    local saved=assert(R.Save.load(1))
    assert(R.startGame(saved,'continue'))
    check('story_free_roam_continue_has_no_forced_route',C.localPart(R)~=nil
        and C.activeWaypoint(R)==nil and not Intro.dialogueOpen(R))
    enter('warehouse','shop_first')
    firstRepair('shop_first')
    cleanShopFloors()
    explore('shop')
    enter(R.state.home.apartmentId,'apartment_second')
    check('story_free_roam_shop_first_visits_both',R.state.warehouse.condition.visitedShop
        and R.state.warehouse.condition.visitedApartment)

    start(2,712346)
    enter(R.state.home.apartmentId,'apartment_first')
    explore('apartment')
    enter('warehouse','shop_second')
    firstRepair('shop_second')
    check('story_free_roam_apartment_first_visits_both',R.state.warehouse.condition.visitedShop
        and R.state.warehouse.condition.visitedApartment)

    -- Choosing a GPS destination is optional and cannot lock the other door.
    start(3,845001)
    assert(C.setWaypoint(R,'warehouse'))
    check('story_free_roam_optional_gps_selects_shop',C.activeWaypoint(R)=='warehouse')
    assert(C.setWaypoint(R,R.state.home.apartmentId))
    check('story_free_roam_optional_gps_switches_to_apartment',
        C.activeWaypoint(R)==R.state.home.apartmentId)
    assert(C.setWaypoint(R,R.state.home.apartmentId))
    check('story_free_roam_optional_gps_can_clear',C.activeWaypoint(R)==nil)
    assert(C.setWaypoint(R,R.state.home.apartmentId))
    local routedSave=assert(R.Save.load(3))
    assert(R.startGame(routedSave,'continue'))
    check('story_free_roam_optional_gps_survives_continue',
        C.activeWaypoint(R)==R.state.home.apartmentId)
    enter('warehouse','gps_points_elsewhere')
    explore('gps_points_elsewhere')
    check('story_free_roam_gps_clears_after_visit',C.activeWaypoint(R)==nil)
end
return Test
