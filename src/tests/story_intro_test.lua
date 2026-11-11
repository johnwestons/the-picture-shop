local Test={}
function Test.run(context,check)
    local R=context.appRuntime
    local Intro=require('src.story_intro')
    local Opening=require('src.story_opening')
    local Commute=require('src.commute.runtime')
    local Trip=require('src.commute.trip')
    local Condition=require('src.warehouse_condition')
    local quick=assert(R.Save.newGame(2,{startMode='quick',townSeed=712345}))
    check('story_intro_quick_start_keeps_shop_open',Condition.openForBusiness(quick.state)
        and quick.state.warehouse.condition.grandpaMet)
    local title=R.TitleScreen
    title.enter(function() end)
    title.keypressed('n');title.update(.5)
    if title.mode=='overwrite-confirm' then title.keypressed('return') end
    check('story_intro_title_offers_both_modes',title.mode=='start-mode' and title.startMode=='quick')
    title.mousepressed(400,440,1)
    check('story_intro_story_choice_reaches_setup',title.mode=='shop-setup'
        and title.setup.startMode=='story')
    local payload=assert(R.Save.newGame(3,{startMode='story',townSeed=712345}))
    check('story_intro_new_story_closes_shop',not Condition.openForBusiness(payload.state)
        and not payload.state.warehouse.condition.grandpaMet
        and select(1,Condition.readyForOpening(payload.state))==false)
    local okay,reason=R.startGame(payload,'new')
    assert(okay,reason)
    local captureRoot=os.getenv('PICTURE_SHOP_STORY_CAPTURE_DIR')
    local function capture(label,time)
        if not captureRoot then return end
        local g=love.graphics
        local canvas=g.newCanvas(960,678)
        local previous=R._storyOpening.time
        if time then R._storyOpening.time=time end
        g.push('all');g.setCanvas(canvas);g.clear(.02,.03,.04,1)
        Opening.draw(R)
        g.setCanvas();g.pop()
        local file=assert(io.open(captureRoot..'/'..label..'.png','wb'))
        file:write(canvas:newImageData():encode('png'):getString());file:close()
        if time then R._storyOpening.time=previous end
    end
    capture('packing',2.2);capture('departure',9.2);capture('bridge',13.4);capture('farm-road',17.7)
    check('story_opening_starts_before_farm_control',Opening.active(R)
        and R._storyOpening.time==0 and R.state.warehouse.condition.openingSeen==false)
    check('story_opening_packing_scene_renders',pcall(R.App.draw))
    local calendarBefore=require('src.business_calendar').absoluteHours(R.state)
    R.App.keypressed('j')
    R.App.update(.25)
    check('story_opening_blocks_gameplay_and_pauses_clock',Opening.active(R)
        and R.state.screen=='world' and R._storyOpening.time>.2
        and require('src.business_calendar').absoluteHours(R.state)==calendarBefore)
    for _=1,22 do Opening.update(R,.5) end
    check('story_opening_travel_montage_renders',Opening.active(R) and pcall(R.App.draw))
    for _=1,17 do Opening.update(R,.5) end
    local arrival=R._storyOpening and R._storyOpening.arrival
    check('story_arrival_uses_connected_generated_roads',arrival and arrival.plan
        and arrival.plan.length>20 and #arrival.plan.points>2)
    local start=arrival and arrival.plan.points[1]
    local traveled,nativeDraw,roadClear=false,false,true
    local capturedMiddle,capturedWalk,capturedPorch=false,false,false
    for _=1,220 do
        if not Opening.active(R) then break end
        Opening.update(R,.5)
        local current=R._storyOpening and R._storyOpening.arrival
        if current and current.distance>15 then
            traveled=true
            roadClear=roadClear and not Commute.world(R).roads:blocked(Commute.world(R),
                Commute.localPart(R).rider.bike.x,Commute.localPart(R).rider.bike.z)
            if not nativeDraw and R._commute.renderer and not R._commute.loading then
                nativeDraw=pcall(R.App.draw)
                capture('native-road')
            end
            if not capturedMiddle and current.distance>current.plan.length*.55 then
                capture('native-midroute');capturedMiddle=true
            end
        end
        if current and current.phase=='walk' and not capturedWalk then
            capture('native-farm-walk');capturedWalk=true
        end
        if current and current.phase=='walk' and not capturedPorch then
            local porch=current.plan.walk[#current.plan.walk]
            local ped=Commute.localPart(R).rider.ped
            if (ped.x-porch.x)^2+(ped.z-porch.z)^2<16 then
                capture('native-porch-approach');capturedPorch=true
            end
        end
    end
    check('story_arrival_motorcycle_moves_on_generated_route',traveled and start
        and arrival.distance>=arrival.plan.length-.01 and roadClear)
    check('story_arrival_native_renderer_draws',nativeDraw)
    check('story_opening_arrival_hands_off_at_farm',not Opening.active(R)
        and R.state.warehouse.condition.openingSeen)
    local part=assert(Commute.localPart(R))
    local farm=assert(Commute.world(R).sites.byId.farm)
    local bx,bz=farm:toWorld(0,25,0)
    check('story_intro_arrives_on_foot_at_farm_with_bike',R.World.player.sceneId=='commute'
        and not part.rider.gear.mounted and math.abs(part.rider.bike.x-bx)<.01
        and math.abs(part.rider.bike.z-bz)<.01 and Trip.valid(R.state.home.commute,R.state.home))
    check('story_arrival_walk_opens_grandpa_dialogue',Intro.near(R,part)
        and Intro.dialogueOpen(R) and R._commute.introDialogue==1)
    check('story_arrival_restores_gameplay_camera',R._commute.camera
        and math.abs(R._commute.camera.centerX-part.rider.ped.x)<.01
        and math.abs(R._commute.camera.centerZ-part.rider.ped.z)<.01)
    local saved=assert(R.Save.load(3))
    check('story_intro_first_save_resumes_at_farm',saved.player.sceneId=='commute'
        and saved.state.warehouse.condition.grandpaMet==false
        and Trip.valid(saved.state.home.commute,saved.state.home))
    local drawOkay=pcall(function()
        Intro.drawWorld(R,{viewportWidth=1280,screen=function(_,_,_,height)return 640,700-height*60 end})
        Intro.drawHud(R)
    end)
    check('story_intro_grandpa_art_and_dialogue_render',drawOkay)
    assert(Commute.touchPressed(R,1,900,760))
    check('story_intro_dialogue_has_touch_advance',R._commute.introDialogue==2)
    for _=2,5 do assert(Intro.advance(R)) end
    check('story_intro_handoff_opens_control_and_marks_met',not Intro.dialogueOpen(R)
        and R.state.warehouse.condition.grandpaMet and not Condition.openForBusiness(R.state)
        and Commute.activeWaypoint(R)==nil and not Intro.pointer(R,400,210)
        and not Intro.near(R,Commute.localPart(R)))
    local mobilePhone=false
    for _,action in ipairs(R.extraMobileActions()) do if action.key=='j' then mobilePhone=true end end
    check('story_intro_mobile_has_portable_utilities_action',mobilePhone)
    R.dispatchKeyPressed('j')
    check('story_intro_portable_utilities_open_at_farm',R.state.screen=='shop_rooms'
        and require('src.shop_room_controls').isPortableUtilities())
    check('story_intro_portable_phone_renders_over_farm',pcall(R.App.draw))
    local controls=require('src.shop_room_controls')
    controls.mousepressed(150,260,1,R)
    controls.mousepressed(150,305,1,R)
    check('story_intro_farm_utility_calls_are_receipted',R.state.warehouse.condition.powerConnected
        and R.state.warehouse.condition.waterConnected and #R.state.receipts.entries==2)
    controls.keypressed('escape',R)
    check('story_intro_portable_phone_returns_outdoors',R.state.screen=='world'
        and R.World.player.sceneId=='commute')
    saved=assert(R.Save.load(3))
    check('story_intro_handoff_persists',saved.state.warehouse.condition.grandpaMet==true)
    assert(R.startGame(saved,'continue'))
    check('story_intro_continue_keeps_farm_and_progress',R.World.player.sceneId=='commute'
        and R.state.warehouse.condition.grandpaMet and Commute.localPart(R)~=nil
        and not Opening.active(R) and Commute.activeWaypoint(R)==nil)
    local skipped=assert(R.Save.newGame(2,{startMode='story',townSeed=712346}))
    assert(R.startGame(skipped,'new'))
    check('story_opening_resume_replays_unfinished_cutscene',Opening.active(R))
    local beforeSkip=assert(R.Save.load(2))
    check('story_opening_unfinished_save_stays_pending',beforeSkip.state.warehouse.condition.openingSeen==false)
    assert(R.startGame(beforeSkip,'continue'))
    check('story_opening_continue_restarts_montage',Opening.active(R) and R._storyOpening.time==0)
    for _=1,39 do Opening.update(R,.5) end
    check('story_opening_can_skip_during_native_arrival',Opening.active(R)
        and R._storyOpening.arrival~=nil)
    local ox,oy,_,sx,sy=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,R.App.officeUsesSafeArea())
    R.App.touchpressed(99,ox+820*sx,oy+40*sy)
    check('story_opening_skip_grants_safe_farm_handoff',not Opening.active(R)
        and R.state.warehouse.condition.openingSeen and R.state.warehouse.condition.grandpaMet
        and R.World.player.sceneId=='commute' and Commute.localPart(R)~=nil
        and R._commute.renderer==nil)
    local afterSkip=assert(R.Save.load(2))
    check('story_opening_skip_persists',afterSkip.state.warehouse.condition.openingSeen
        and afterSkip.state.warehouse.condition.grandpaMet)
    assert(R.startGame(quick,'new'))
    check('story_opening_quick_start_never_plays_montage',not Opening.active(R)
        and R.World.player.sceneId~='commute')
    for _,seed in ipairs({712347,845001,991337}) do
        local generated=assert(R.Save.newGame(1,{startMode='story',townSeed=seed}))
        assert(R.startGame(generated,'new'))
        local plan=require('src.story_arrival').plan(Commute.world(R))
        check('story_arrival_generated_route_seed_'..seed,plan and plan.length>20
            and #plan.points>2 and #plan.walk==3)
    end
end
return Test
