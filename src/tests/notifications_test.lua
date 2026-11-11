local Notices=require('src.notifications')
local Tutorial=require('src.tutorial')
local Feedback=require('src.player_feedback')
local Screen=require('src.screens.notifications_screen')
local State=require('src.state')
local Schema=require('src.save_schema')
local Test={}
local function saveImage(canvas,path)
    local data=canvas:newImageData();local png=data:encode('png')
    local file=assert(io.open(path,'wb'));file:write(png:getString());file:close()
    png:release();data:release()
end
function Test.run(context,check)
    local state=State.new();state.screen='world';state.tutorial=Tutorial.new(true)
    local machine={};local feedback=Feedback.new({state=state,machine=machine})
    feedback:update(.016)
    check('tutorial_starts_with_saved_expanded_lesson',#state.notifications.items==1
        and state.notifications.items[1].kind=='tutorial' and #state.notifications.items[1].body>200
        and feedback.notices[1].duration==14)
    local first=state.notifications.items[1]
    feedback:update(4)
    check('tutorial_popup_stays_readable_longer_than_ordinary_alert',feedback.notices[1].remaining>9)
    feedback:update(20)
    check('notification_popup_expiry_keeps_unread_history',#feedback.notices==0 and first.unread)
    state.screen='computer';feedback:update(.1)
    check('tutorial_advances_when_computer_really_opens',state.tutorial.step==2 and #state.notifications.items==2)
    feedback:update(60)
    check('tutorial_waits_for_actual_job_instead_of_timer',state.tutorial.step==2)
    local job={pallets={{location='in_truck'}}};state.jobs.active={job};feedback:update(.1)
    check('tutorial_job_award_advances_to_receiving',state.tutorial.step==3)
    job.pallets[1].location='warehouse';feedback:update(.1)
    check('tutorial_receiving_advances_to_loading',state.tutorial.step==4)
    machine.loaded=true;machine.paper={};feedback:update(.1)
    check('tutorial_actual_cutter_load_advances_to_cutting',state.tutorial.step==5)
    state.shopProgress.completedCuts=1;feedback:update(.1)
    check('tutorial_actual_cut_advances_to_wrapping',state.tutorial.step==6)
    job.pallets[1].wrapped=true;feedback:update(.1)
    check('tutorial_continues_to_shipping_after_wrapped_stack',not state.tutorial.finished and state.tutorial.step==7)
    state.jobs.completed={job};feedback:update(.1)
    check('tutorial_completed_job_advances_to_town',state.tutorial.step==8)
    local travel={sceneId='commute'};feedback.context.travel=function()return travel end
    feedback:update(.1)
    check('tutorial_town_visit_advances_to_map',state.tutorial.step==9)
    travel.mapOpen=true;feedback:update(.1)
    check('tutorial_observes_map_open',state.tutorial.step==10)
    travel.mapOpen=false;travel.rider={gear={mounted=true,engine=true},bike={speed=2}}
    feedback:update(.1)
    check('tutorial_observes_actual_motorcycle_ride',state.tutorial.step==11)
    travel.sceneId='home';feedback:update(.1)
    check('tutorial_observes_apartment_arrival',state.tutorial.step==12)
    travel.resident={activity={kind='sleepbed'}};feedback:update(.1)
    check('tutorial_observes_home_activity',state.tutorial.step==13)
    travel.shopOpen=true;feedback:update(.1)
    check('tutorial_observes_town_errand',state.tutorial.step==14)
    state.home.weekend.phase='home';feedback:update(.1)
    check('tutorial_completes_after_weekend_shutdown',state.tutorial.finished and state.tutorial.step==15
        and Notices.findKey(state,'tutorial:complete-v2'))
    local old=Tutorial.normalize({enabled=true,finished=true,step=7,seen={computer=true,job=true,
        delivery=true,load=true,cut=true,wrap=true}})
    check('tutorial_old_completion_resumes_expanded_lessons',old and old.step==7 and not old.finished)
    local count=#state.notifications.items
    feedback:update(30);feedback:update(.1)
    check('tutorial_completed_steps_do_not_repeat',#state.notifications.items==count)

    local fresh=State.new();fresh.screen='world'
    local f=Feedback.new({state=fresh});f:update(.1)
    check('tutorial_opt_out_has_no_lessons',#fresh.notifications.items==0)
    fresh.clientEmails.inbox={{id='email-test',subject='New work',sender='Mira',body='A small cutting job.',unread=true}}
    fresh.workPhone.incoming={id='call-test',caller='Mira',subject='Paper delivery'}
    f:update(.1);f:update(.1)
    check('notification_email_and_phone_keep_full_details_without_duplicates',#fresh.notifications.items==2
        and fresh.notifications.items[1].body:find('A small cutting job.',1,true)
        and fresh.notifications.items[2].body:find('Paper delivery',1,true))
    local shop=State.new();shop.screen='world'
    local shopFeedback=Feedback.new({state=shop});shopFeedback:update(.1)
    local beforeShop=#shop.notifications.items
    shop.inventory.paper=shop.inventory.paper+200
    shop.jobs.active={{id='SHOP-NOTICE-1',company='Millhaven Studio',status='ready_for_pickup'}}
    shop.bills.balance=75
    shopFeedback:update(.1)
    check('warehouse_important_events_use_saved_notices',
        #shop.notifications.items==beforeShop+3
        and Notices.findKey(shop,'shop:ready:SHOP-NOTICE-1')
        and Notices.findKey(shop,'business:bills:2026:1'))
    shopFeedback:update(.1)
    check('warehouse_event_notices_do_not_repeat_each_frame',#shop.notifications.items==beforeShop+3)
    local R={state=fresh,App={playerFeedback=f,settings={}},optionsAccessLayout=function()return 'world',nil end}
    local rect=f:toastRect(nil,'world');local id=f.notices[1].id
    check('notification_toast_opens_matching_expanded_entry',Screen.pointer(R,rect.x+15,rect.y+15,1)
        and fresh.screen=='notifications' and fresh.notificationSelection==id and not Notices.find(fresh,id).unread)
    local remaining=f.notices[1].remaining;f:update(5)
    check('notification_reading_pauses_popup_clock',f.notices[1].remaining==remaining)
    Screen.keypressed(R,'escape')
    check('notification_close_returns_to_original_screen',fresh.screen=='world')
    fresh.screen='computer';Screen.keypressed(R,'f6');Screen.keypressed(R,'f6')
    check('notification_shortcut_returns_to_computer',fresh.screen=='computer')
    fresh.screen='world'
    local access=Screen.buttonRect()
    check('notification_hud_button_opens_recent_history',Screen.pointer(R,access.x+10,access.y+10,1)
        and fresh.screen=='notifications')
    Screen.close(R)

    local paging=State.new();paging.screen='world'
    for i=1,8 do Notices.add(paging,'email','Paging note '..i,'Detail '..i,'Body '..i) end
    local pageRuntime={state=paging,App={settings={}}}
    Screen.open(pageRuntime)
    local nextPage=Screen.layout(pageRuntime).rects.next
    Screen.pointer(pageRuntime,nextPage.x+10,nextPage.y+10,1)
    check('clipboard_next_turns_to_second_page_and_selects_a_note',paging.notificationPage==2
        and Screen.pageTurn and Screen.pageTurn.direction==1 and paging.notificationSelection)
    local previousPage=Screen.layout(pageRuntime).rects.previous
    Screen.pointer(pageRuntime,previousPage.x+10,previousPage.y+10,1)
    check('clipboard_previous_returns_to_first_page',paging.notificationPage==1
        and Screen.pageTurn and Screen.pageTurn.direction==-1)
    Screen.close(pageRuntime)

    Screen.open(R)
    local referenceTab=Screen.layout(R).rects.tutorial
    Screen.pointer(R,referenceTab.x+10,referenceTab.y+10,1)
    check('tutorial_reference_library_available_before_earning_lessons',Notices.findKey(fresh,'tutorial:apartment')
        and Notices.findKey(fresh,'tutorial:weekend') and Notices.findKey(fresh,'tutorial:motorcycle'))
    Screen.close(R)

    local early=State.new();early.screen='world';early.tutorial=Tutorial.new(true)
    local localTravel={sceneId='commute'}
    local earlyFeedback=Feedback.new({state=early,travel=function()return localTravel end})
    earlyFeedback:update(.1)
    check('tutorial_exploring_early_offers_map_help_without_completing_shop',early.tutorial.step==1
        and Notices.findKey(early,'tutorial:visited:map'))
    earlyFeedback:update(.1)
    check('tutorial_context_tip_does_not_repeat_each_frame',#early.notifications.items==2)
    local contextState=State.new();contextState.screen='world';contextState.tutorial=Tutorial.new(true)
    local rider={gear={mounted=true,engine=true},bike={speed=3}}
    contextState.home.commute={participants={owner={rider=rider}}}
    local runtime={state=contextState,World={player={id=1,sceneId='commute'}},_commute={mapOpen=true}}
    local linked=Feedback.new({state=contextState,world=runtime.World,
        travel=function()return Tutorial.travelContext(runtime)end})
    linked:update(.1)
    check('tutorial_reads_local_commute_map_and_bike_runtime',contextState.tutorial.seen.map
        and contextState.tutorial.seen.motorcycle and contextState.tutorial.seen.commute)
    runtime.World.player.sceneId='home';runtime._commute.mapOpen=false
    contextState.home.residents.owner.activity={kind='sleepbed'};linked:update(.1)
    check('tutorial_reads_apartment_activity_from_local_resident',contextState.tutorial.seen.apartment
        and contextState.tutorial.seen.homecare)
    fresh.tutorial=Tutorial.new(true);Screen.open(R)
    local tutorialToggle=Screen.layout(R).rects.toggle
    Screen.pointer(R,tutorialToggle.x+10,tutorialToggle.y+10,1)
    check('tutorial_can_be_paused_without_losing_step',not fresh.tutorial.enabled and fresh.tutorial.step==1)
    Screen.pointer(R,tutorialToggle.x+10,tutorialToggle.y+10,1)
    check('tutorial_can_be_enabled_from_inbox',fresh.tutorial.enabled and fresh.tutorial.step==1)
    Screen.close(R)

    local persisted=State.new();persisted.tutorial=Tutorial.new(true);persisted.tutorial.step=3
    persisted.tutorial.seen.computer=true;persisted.tutorial.seen.job=true
    local n=Notices.add(persisted,'tutorial','A saved lesson','Short guidance','Expanded instructions','tutorial:saved')
    Notices.read(persisted,n.id)
    local snapshot=assert(Schema.snapshot(persisted));local loaded=State.new()
    assert(State.applyLocalSave(loaded,{state=snapshot,slot=3}))
    check('notification_and_tutorial_roundtrip_save_and_read_state',loaded.tutorial.enabled
        and loaded.tutorial.step==3 and loaded.notifications.items[1].body=='Expanded instructions'
        and not loaded.notifications.items[1].unread)
    local legacy=Schema.copy(snapshot);legacy.notifications=nil;legacy.tutorial=nil
    local restored=assert(Schema.snapshot(legacy))
    check('notification_legacy_saves_start_with_tutorial_off',not restored.tutorial.enabled and #restored.notifications.items==0)
    local guest=State.new();assert(State.applySharedSnapshot(guest,snapshot))
    local own=Notices.add(guest,'phone','Guest call','Guest detail')
    Notices.read(guest,own.id);assert(State.applySharedUpdate(guest,snapshot))
    check('notification_peer_updates_preserve_local_history_without_host_lessons',#guest.notifications.items==1
        and guest.notifications.items[1].title=='Guest call' and not guest.notifications.items[1].unread
        and not guest.tutorial.enabled)
    local resumed=Feedback.new({state=loaded});loaded.screen='world';resumed:update(.1)
    check('tutorial_resume_reopens_current_lesson_without_resetting_progress',loaded.tutorial.step==3
        and resumed.notices[1] and resumed.notices[1].title:find('Receive',1,true))
    for i=1,100 do Notices.add(persisted,'email','Message '..i,'A message') end
    check('notification_history_is_bounded_and_valid',#persisted.notifications.items==Notices.LIMIT
        and Notices.normalize(persisted.notifications)~=nil)
    local bad=Schema.copy(snapshot);bad.notifications.items[1].body=string.rep('x',2401)
    check('notification_invalid_saved_data_is_rejected',not Schema.validState(bad) and not Schema.snapshot(bad))
    local store=require('src.save_store')({})
    check('tutorial_new_game_option_is_applied',store.newGame(3,{tutorialEnabled=true}).state.tutorial.enabled
        and not store.newGame(3,{tutorialEnabled=false}).state.tutorial.enabled)

    if context and context.appRuntime then
        local live=context.appRuntime;local oldScreen=live.state.screen
        local oldFeedback=live.App.playerFeedback
        live.App.playerFeedback=Feedback.new({state=live.state,machine=live.Machine})
        local oldHistory,oldTutorial=live.state.notifications,live.state.tutorial
        live.state.notifications=Notices.new();live.state.tutorial=Tutorial.new(true)
        live.state.screen='world';live.App.playerFeedback:seed()
        Tutorial.update(live.App.playerFeedback)
        live.App.keypressed('f6')
        check('notification_native_keyboard_opens_panel',live.state.screen=='notifications')
        live.App.keypressed('e')
        check('notification_panel_consumes_gameplay_keys',live.state.screen=='notifications')
        local output=os.getenv('PICTURE_SHOP_TUTORIAL_OUTPUT')
        if output then
            local g=love.graphics;local canvas=g.newCanvas(960,678)
            g.push('all');g.setCanvas(canvas);g.clear();Screen.draw(live);g.pop()
            saveImage(canvas,output..'/notification-inbox.png')
            g.push('all');g.setCanvas(canvas);g.clear(.05,.08,.09,1)
            live.App.playerFeedback.notices[1].remaining=10
            live.App.playerFeedback:drawToast(nil,'world');g.pop()
            saveImage(canvas,output..'/tutorial-popup.png')
            Tutorial.addReferences(live.state)
            live.state.notificationFilter='tutorial';live.state.notificationPage=3
            Screen.select(live,Notices.findKey(live.state,'tutorial:weekend').id)
            g.push('all');g.setCanvas(canvas);g.clear();Screen.draw(live);g.pop()
            saveImage(canvas,output..'/weekend-tutorial.png')
            live.App.playerFeedback:enqueue('calendar','FRIDAY: CLOSING SOON',
                'Closes at 20:00. Prepare to head home.',require('src.business_notifications').weekendBody)
            live.App.playerFeedback.notices[1].remaining=12
            g.push('all');g.setCanvas(canvas);g.clear(.05,.08,.09,1)
            live.App.playerFeedback:drawToast(nil,'world');g.pop()
            saveImage(canvas,output..'/friday-reminder.png');canvas:release()
            local phone=g.newCanvas(1280,720)
            g.push('all');g.setCanvas(phone);g.clear(.025,.045,.05,1)
            g.translate((1280-960*.96)/2,24);g.scale(.96)
            Screen.draw(live);g.pop()
            saveImage(phone,output..'/notification-inbox-wide.png');phone:release()
        end
        live.App.keypressed('escape')
        local ox,oy,scale=live.Viewport.transform(live.Config.baseWidth,live.Config.baseHeight,live.App.officeUsesSafeArea())
        local _,bounds=live.optionsAccessLayout();local access=Screen.buttonRect(bounds,live)
        live.App.touchpressed('notification-test',ox+(access.x+12)*scale,oy+(access.y+12)*scale)
        check('notification_native_touch_opens_hud_inbox',live.state.screen=='notifications')
        for i=1,7 do Notices.add(live.state,'email','Touch page '..i,'Page check','Body') end
        local nextRect=Screen.layout(live).rects.next
        live.App.touchpressed('notification-next',ox+(nextRect.x+nextRect.width/2)*scale,
            oy+(nextRect.y+nextRect.height/2)*scale)
        check('notification_native_touch_turns_clipboard_page',live.state.notificationPage==2
            and Screen.pageTurn and Screen.pageTurn.direction==1)
        live.App.gamepadpressed(nil,'b')
        check('notification_controller_back_restores_world',live.state.screen=='world')
        live.state.screen=oldScreen;live.state.notifications=oldHistory;live.state.tutorial=oldTutorial
        live.App.playerFeedback=oldFeedback
    end
end
return Test
