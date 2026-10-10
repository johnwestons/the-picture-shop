local Kombat=require("src.critter_kombat")
local Art=require("src.critter_kombat_art")
local Screen=require("src.screens.critter_kombat_screen")
local Games=require("src.breakroom_games")
local Protocol=require("src.net.protocol")
local Codec=require("src.net.codec")
local Test={}
local function fixture(two)
    Kombat.clear()
    local state=require("src.state").new();state.money=50000
    local upgrades=require("src.warehouse_upgrades")
    for index,bay in ipairs(two and {"front_left","front_right"} or {"front_left"}) do
        local project="WUP-000"..index
        assert(upgrades.purchase(state,bay,"breakroom","KOMBAT-ROOM-"..index,0))
        upgrades.update(state,0)
        upgrades.update(state,0,{noticeDeliveredProjectId=project,noticeCallId="KOMBAT-CALL-"..index})
        upgrades.update(state,2,{workerArrivedProjectId=project})
        upgrades.update(state,98);upgrades.update(state,98,{workerReleasedProjectId=project})
        assert(Games.purchase(state,bay,"critter_kombat","KOMBAT-CABINET-"..index))
    end
    local fixture=Games.CATALOG.critter_kombat
    local player={id=1,x=fixture.interactionX,y=fixture.interactionY,sceneId="front_left",character="rabbit-worker"}
    local runtime={state=state,World={player=player},multiplayer={isClient=function()return false end},
        Config={baseWidth=960,baseHeight=678},Viewport={toGame=function(x,y)return x/2,y/2 end},
        App={officeFitsScreen=function()return true end}}
    return state,player,runtime
end
local function advance(seconds,inputs)
    for _=1,math.ceil(seconds*120) do Kombat.update(1/120,inputs) end
end
local function capture(runtime,name)
    local dir=os.getenv("PICTURE_SHOP_KOMBAT_CAPTURE_DIR")
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.origin();love.graphics.clear()
    Screen.draw(runtime);love.graphics.setCanvas();love.graphics.pop()
    if dir then
        local data=canvas:newImageData();local encoded=data:encode("png")
        local file=assert(io.open(dir.."/"..name..".png","wb"));file:write(encoded:getString());file:close()
        data:release();encoded:release()
    end
    canvas:release()
end
local function flowChecks(check)
    local state,player,runtime=fixture()
    Screen.enter(runtime,"front_left")
    check("kombat_cabinet_opens_own_title",Screen.page(runtime)=="title" and not next(Kombat.matches))
    capture(runtime,"title")
    Screen.keypressed(runtime,"1")
    local match=Kombat.matches.front_left
    advance(2,function()return {x=1,buttons=6}end)
    check("kombat_solo_stays_in_character_selection",Screen.page(runtime)=="select" and match.phase=="selecting"
        and match.seconds==60 and match.left.health==100 and match.left.x==255)
    Screen.mousepressed(runtime,660,300,1)
    check("kombat_mouse_selects_fox",Screen.selected=="fox")
    capture(runtime,"character-select")
    Screen.keypressed(runtime,"return")
    check("kombat_confirmation_sets_selected_character_and_AI",match.left.character=="fox" and match.right.character=="mouse"
        and match.phase=="intro" and Screen.page(runtime)=="fight")
    local x,bits=Screen.controls(runtime)
    check("kombat_intro_blocks_combat_input",x==0 and bits==0)
    capture(runtime,"get-ready")
    advance(1.3)
    check("kombat_only_fights_after_intro",match.phase=="playing" and match.left.health==100)
    match.left.action,match.left.actionTime,match.left.variant="punch",.16,2
    match.right.action,match.right.actionTime,match.right.variant="kick",.26,2
    capture(runtime,"fighting-variations")
    match.left.action="idle";match.right.action="idle"
    Screen.touchpressed(runtime,"move",400,1280);Screen.touchpressed(runtime,"punch",1200,1280)
    x,bits=Screen.controls(runtime)
    check("kombat_multitouch_moves_and_punches",x==1 and bits==2)
    Screen.touchreleased("move");Screen.touchreleased("punch")
    match.right.health=0;advance(.03)
    check("kombat_selected_character_wins_are_not_fixed_to_side",match.left.action=="victory" and match.left.wins==1)
    advance(2.3)
    check("kombat_character_selection_survives_next_round",match.left.character=="fox" and match.right.character=="mouse"
        and match.round==2 and match.left.wins==1)
    local saved=assert(require("src.save_schema").snapshot(state))
    check("kombat_selection_and_live_round_are_not_saved",saved.screen==nil and saved.roomGameBay==nil and saved.critterKombat==nil)
    Screen.leave(runtime)
    check("kombat_exit_frees_cabinet",state.screen=="world" and not Kombat.matches.front_left)
    Screen.enter(runtime,"front_left");Screen.keypressed(runtime,"2");Screen.keypressed(runtime,"escape")
    check("kombat_selection_back_returns_to_title",Screen.page(runtime)=="title" and not Kombat.matches.front_left)
    Screen.keypressed(runtime,"escape")
    check("kombat_title_exit_returns_to_room",state.screen=="world")
    state,player,runtime=fixture()
    Screen.enter(runtime,"front_left");Screen.touchpressed(runtime,"solo",650,1100)
    Screen.touchpressed(runtime,"fox",1300,600);Screen.touchpressed(runtime,"ready",960,1150)
    check("kombat_touch_title_and_selection_flow",Kombat.matches.front_left.phase=="intro"
        and Kombat.matches.front_left.left.character=="fox")
    Screen.leave(runtime)
end
local function versusChecks(check)
    local state,player,runtime=fixture(true)
    local other={id=2,x=player.x,y=player.y,sceneId=player.sceneId}
    local spectator={id=3,x=player.x,y=player.y,sceneId=player.sceneId}
    assert(Kombat.command(state,player,"start_versus"))
    assert(Kombat.command(state,player,"ready_fox"))
    local match=Kombat.matches.front_left
    check("kombat_first_ready_waits_for_second_player",match.phase=="selecting" and match.leftReady and not match.rightReady)
    check("kombat_confirmed_character_is_locked",not Kombat.command(state,player,"ready_mouse") and match.left.character=="fox")
    check("kombat_spectator_cannot_confirm",not Kombat.command(state,spectator,"ready_mouse"))
    assert(Kombat.command(state,other,"join"))
    check("kombat_join_does_not_skip_selection",match.phase=="selecting" and not match.rightReady)
    check("kombat_second_join_cannot_replace_player",not Kombat.command(state,spectator,"join") and match.rightId==2)
    assert(Kombat.command(state,other,"ready_fox"))
    check("kombat_both_players_can_choose_same_character",match.phase=="intro" and match.left.character=="fox" and match.right.character=="fox")
    check("kombat_character_cannot_change_midfight",not Kombat.command(state,other,"ready_mouse"))
    local second={id=3,x=player.x,y=player.y,sceneId="front_right"}
    assert(Kombat.command(state,second,"start_solo"));assert(Kombat.command(state,second,"ready_mouse"))
    advance(1.4)
    local snapshot=Kombat.snapshot()
    local wire,err=Protocol.encode("fight_snapshot",{sessionId="KOMBAT",serverTick=5,matches=Codec.array(snapshot)})
    check("kombat_two_room_snapshot_fits_MTU",wire and #wire<=1200,err or wire and #wire)
    local decoded=wire and Protocol.decode(wire)
    check("kombat_snapshot_carries_chosen_characters_and_variants",decoded and decoded.payload.matches[1].left.character=="fox"
        and decoded.payload.matches[1].right.character=="fox" and decoded.payload.matches[1].left.variant==1)
    local worst=Kombat.snapshot()
    for _,m in ipairs(worst) do
        m.mode="versus";m.rightId=4;m.seconds=59.123
        for _,f in ipairs({m.left,m.right}) do
            f.x=728.123;f.z=193.654;f.actionTime=119.999;f.action="knockout";f.character="mouse"
        end
    end
    local large,largeError=Protocol.encode("fight_snapshot",{sessionId=string.rep("K",64),serverTick=4294967295,matches=Codec.array(worst)})
    check("kombat_maximum_two_room_snapshot_fits_MTU",large and #large<=1200,largeError or large and #large)
    snapshot[1].left.character="dragon"
    check("kombat_unknown_wire_character_rejected",not Protocol.encode("fight_snapshot",{sessionId="KOMBAT",serverTick=6,matches=snapshot}))
    snapshot[1].left.character="fox";snapshot[1].right.variant=3
    check("kombat_unknown_wire_attack_variant_rejected",not Protocol.encode("fight_snapshot",{sessionId="KOMBAT",serverTick=6,matches=snapshot}))
    local request={sessionId="KOMBAT",requestId=1,targetKind="roomGame",desiredState="critter_kombat:ready_fox"}
    check("kombat_selected_character_command_is_allowed_over_LAN",Protocol.encode("interaction_request",request)~=nil)
    request.desiredState="critter_kombat:ready_dragon"
    check("kombat_invalid_character_command_rejected",not Protocol.encode("interaction_request",request))
    Kombat.prune({[1]=player,[3]=second})
    check("kombat_missing_player_frees_reserved_cabinet",not Kombat.matches.front_left and Kombat.matches.front_right~=nil)
    Kombat.clear()
end
local function combatChecks(check)
    local state,player=fixture()
    local other={id=2,x=player.x,y=player.y,sceneId=player.sceneId}
    assert(Kombat.command(state,player,"start_versus"));assert(Kombat.command(state,other,"join"))
    assert(Kombat.command(state,player,"ready_mouse"));assert(Kombat.command(state,other,"ready_fox"));advance(1.3)
    local match=Kombat.matches.front_left
    -- Keep the AI outside reach while observing each attack's full timing.
    match.left.x,match.right.x=255,600
    for _,attack in ipairs({{name="punch",bit=2,duration=.33},{name="kick",bit=4,duration=.52}}) do
        for variant=1,2 do
            advance(.02,function(id)return id==1 and {x=0,buttons=attack.bit} or nil end)
            check("kombat_"..attack.name.."_variation_"..variant,match.left.action==attack.name and match.left.variant==variant)
            local seen={}
            for i=0,600 do
                local sheet,frame=Art.pose({action=attack.name,variant=variant,actionTime=i/600*attack.duration})
                seen[frame]=true
            end
            local count=0;for _ in pairs(seen)do count=count+1 end
            check("kombat_"..attack.name.."_six_distinct_frames_"..variant,count==6)
            advance(attack.duration+.05)
        end
    end
    match.left.x,match.right.x=310,380;match.right.action="idle";match.right.hitGrace=0
    match.aiNextAttack=match.clock+10;match.right.health=100
    advance(.02,function(id)return id==1 and {x=0,buttons=2} or nil end)
    advance(.31)
    check("kombat_six_frame_punch_damages_once",match.right.health==92)
    advance(.6);match.right.health=100;match.right.hitGrace=0;match.left.x,match.right.x=310,380
    advance(.02,function(id)return id==1 and {x=0,buttons=4} or nil end)
    advance(.51)
    check("kombat_six_frame_kick_damages_once",match.right.health==88,match.right.health)
    match.left.action,match.left.actionTime="idle",10
    advance(.02,function(id)return id==1 and {x=0,buttons=1} or nil end)
    check("kombat_jump_pose_starts_at_takeoff",match.left.action=="jump" and match.left.actionTime<.04)
    Kombat.clear()
end
local function artChecks(check)
    for _,character in ipairs({"mouse","fox"}) do
        for _,sheet in ipairs({"attacks","support"}) do
            local data=love.image.newImageData("assets/generated/critter-kombat-v2/"..character.."-"..sheet..".png")
            local cols,rows=sheet=="attacks" and 6 or 4,sheet=="attacks" and 4 or 6
            check("kombat_"..character.."_"..sheet.."_dimensions",data:getWidth()==cols*256 and data:getHeight()==rows*256)
            for frame=1,24 do
                local x,y=(frame-1)%cols*256,math.floor((frame-1)/cols)*256
                local clear,visible=true,false
                for p=0,255 do
                    for _,xy in ipairs({{x+p,y},{x+p,y+255},{x,y+p},{x+255,y+p}}) do
                        local _,_,_,a=data:getPixel(xy[1],xy[2]);if a>0 then clear=false end
                    end
                end
                for py=8,248,8 do for px=8,248,8 do local _,_,_,a=data:getPixel(x+px,y+py);if a>.5 then visible=true end end end
                check("kombat_"..character.."_"..sheet.."_complete_pose_"..frame,clear and visible)
            end
            data:release()
        end
    end
end
local function jumpChecks(check)
    local function matchForTest()
        local state,player,runtime=fixture()
        local other={id=2,x=player.x,y=player.y,sceneId=player.sceneId}
        assert(Kombat.command(state,player,"start_versus"));assert(Kombat.command(state,other,"join"))
        assert(Kombat.command(state,player,"ready_mouse"));assert(Kombat.command(state,other,"ready_fox"));advance(1.3)
        local match=Kombat.matches.front_left
        match.left.x,match.right.x=310,380
        Screen.enter(runtime,"front_left")
        return match,runtime
    end
    for _,fps in ipairs({30,60,120}) do
        for _,id in ipairs({1,2}) do
            local match,runtime=matchForTest()
            local jumper=id==1 and match.left or match.right
            local other=id==1 and match.right or match.left
            local direction=id==1 and 1 or -1
            local peak,crossed,faced,captured=0,false,false,false
            for frame=1,math.ceil(1.3*fps) do
                Kombat.update(1/fps,function(playerId)
                    return playerId==id and {x=direction,buttons=1} or nil
                end)
                peak=math.max(peak,jumper.z)
                if (jumper.x-other.x)*direction>0 then
                    crossed=true;faced=jumper.face==-direction and other.face==direction
                    if fps==60 and id==1 and jumper.z>150 and not captured then capture(runtime,"jump-crossover");captured=true end
                end
            end
            check("kombat_jump_crosses_and_turns_"..id.."_at_"..fps.."fps",crossed and faced
                and peak>Kombat.BODY_HEIGHT and jumper.z==0 and math.abs(jumper.x-other.x)>=46)
            check("kombat_held_jump_does_not_repeat_"..id.."_at_"..fps.."fps",jumper.z==0 and jumper.vz==0)
            advance(.02);advance(.02,function(playerId)return playerId==id and {buttons=1,x=0} or nil end)
            check("kombat_jump_rearms_after_release_"..id.."_at_"..fps.."fps",jumper.z>0 and jumper.vz>0)
        end
    end
    local match=matchForTest()
    advance(1,function(id)return {x=id==1 and 1 or -1,buttons=0}end)
    check("kombat_grounded_fighters_cannot_walk_through",match.left.x<match.right.x and math.abs(match.right.x-match.left.x)>=46)
    match=matchForTest()
    advance(1.3,function(id)return {x=id==1 and 1 or -1,buttons=1}end)
    check("kombat_same_height_airborne_bodies_still_collide",match.left.x<match.right.x and match.left.z==0 and match.right.z==0)
    match=matchForTest()
    match.left.x,match.right.x=383,380;match.left.z,match.left.vz=151,-400
    advance(.02)
    check("kombat_landing_overlap_separates_on_correct_side",match.left.x>match.right.x
        and math.abs(match.left.x-match.right.x)>=46 and match.left.face==-1 and match.right.face==1)
    match=matchForTest()
    match.left.x,match.right.x=700,735
    advance(.02,function()return {x=1,buttons=0}end)
    check("kombat_body_separation_stays_inside_arena",match.right.x<=735 and match.left.x>=65 and match.right.x-match.left.x>=46)
    match=matchForTest()
    match.left.x,match.right.x=380,310
    advance(.32,function(id)return {x=0,buttons=id==1 and 2 or 8}end)
    check("kombat_crossed_fighters_guard_the_new_facing",match.right.health==98 and match.left.face==-1 and match.right.face==1)
    match=matchForTest()
    match.left.x,match.right.x=380,310
    advance(.32,function(id)return id==2 and {x=0,buttons=4} or nil end)
    check("kombat_crossed_fighters_can_hit_back",match.left.health==88 and match.right.face==1)
    Kombat.clear()
end
local function networkChecks(context,check)
    local state,hp=fixture(true)
    local gp={id=2,x=hp.x,y=hp.y,sceneId="front_left",character="rabbit-worker"}
    local network=require("src.tests.support.network_impairment_harness").new({maxClients=1,
        classify=function(bytes)local e=Protocol.decode(bytes);return e and e.type or "invalid"end})
    local Session=require("src.net.session")
    local now=0
    local host=Session.new({transportFactory=network.factory,clock=function()return now end})
    local guest=Session.new({transportFactory=network.factory,clock=function()return now end})
    local hc={localPlayer=hp,moveRemote=function()end,resolveGuestSpawn=function()return gp.x,gp.y end,
        getShopSnapshot=function()return {state=assert(require("src.save_schema").snapshot(state)),
            player={x=hp.x,y=hp.y,character=hp.character}}end,
        getFightSnapshot=Kombat.snapshot,
        performInteraction=function(p,kind,command)return context.world.performNetworkInteraction(p,state,kind,command)end}
    local gc={localPlayer=gp,inputX=0,inputY=0,gameX=0,gameY=0,combatButtons=0}
    assert(host:startHost({name="Kombat Host",character="rabbit-worker",localPlayer=hp,
        addressOptions={socket={dns={gethostname=function()return "host"end,toip=function()return "192.168.1.2"end}}}}))
    assert(guest:startClient("192.168.1.2:22122",{name="Kombat Guest",character="rabbit-worker"}))
    local function pump(count)
        for _=1,count do
            now=now+.01;network:advanceSteps(1);host:update(.01,hc);guest:update(.01,gc)
            Kombat.update(.01,function(id)
                local p=host.players[id];return p and {x=p.gameInputX or 0,buttons=p.combatButtons or 0}
            end)
        end
    end
    pump(100)
    check("kombat_real_LAN_guest_ready",guest.ready)
    host.players[2].sceneId="front_left"
    assert(Kombat.command(state,hp,"start_versus"));assert(Kombat.command(state,hp,"ready_fox"))
    local second={id=3,x=hp.x,y=hp.y,sceneId="front_right"}
    assert(Kombat.command(state,second,"start_solo"));assert(Kombat.command(state,second,"ready_mouse"))
    pump(30)
    local runtime={state={screen="world"},World={player=gp},multiplayer=guest}
    Screen.enter(runtime,"front_left")
    check("kombat_LAN_join_starts_from_title",Screen.page(runtime)=="title")
    Screen.keypressed(runtime,"3");pump(30)
    check("kombat_LAN_join_waits_in_selection",Screen.page(runtime)=="select" and Kombat.matches.front_left.phase=="selecting")
    Screen.keypressed(runtime,"1");Screen.keypressed(runtime,"return");pump(30)
    local match=Kombat.matches.front_left
    check("kombat_LAN_confirmation_sets_guest_character",match.phase=="intro" and match.left.character=="fox" and match.right.character=="mouse")
    capture(runtime,"LAN-get-ready")
    pump(130)
    check("kombat_LAN_both_clients_receive_fight_and_two_rooms",Screen.page(runtime)=="fight" and #guest:fightSnapshot()==2
        and guest:fightSnapshot()[1].left.character=="fox")
    match.left.x,match.right.x=310,380
    gc.gameX,gc.combatButtons=-1,1;pump(65)
    local replicated=guest:fightSnapshot()[1]
    check("kombat_LAN_jump_crosses_opponent_and_turns",match.right.x<match.left.x and match.right.face==1
        and match.left.face==-1 and match.right.z>0 and replicated.right.x<replicated.left.x
        and replicated.right.face==1 and replicated.left.face==-1 and replicated.right.z>0)
    capture(runtime,"LAN-jump-crossover")
    gc.gameX,gc.combatButtons=0,0;pump(70)
    check("kombat_LAN_crossed_fighter_lands_without_snapping_back",match.right.z==0 and match.right.x<match.left.x
        and guest:fightSnapshot()[1].right.z==0 and guest:fightSnapshot()[1].right.face==1)
    match.left.x,match.right.x=255,330
    gc.combatButtons=2;pump(15)
    check("kombat_LAN_first_punch_uses_jab",match.right.action=="punch" and match.right.variant==1)
    gc.combatButtons=0;pump(30)
    gc.combatButtons=2;pump(15)
    check("kombat_LAN_next_punch_uses_hook",match.right.action=="punch" and match.right.variant==2
        and guest:fightSnapshot()[1].right.variant==2)
    capture(runtime,"LAN-hook")
    gc.combatButtons=0;pump(30)
    match.phase="finished";match.left.wins=2
    pump(20);Screen.keypressed(runtime,"return");pump(30)
    match=Kombat.matches.front_left
    check("kombat_LAN_rematch_preserves_both_players_and_requires_selection",match.phase=="selecting"
        and match.leftId==1 and match.rightId==2 and not match.leftReady and not match.rightReady
        and Screen.page(runtime)=="select")
    -- Closing during an in-flight ready request must still release the cabinet.
    Screen.keypressed(runtime,"return");Screen.leave(runtime)
    check("kombat_LAN_exit_waits_for_pending_choice",runtime.state.screen=="critter_kombat" and Screen.exitRequested)
    pump(30);Screen.controls(runtime);pump(30)
    check("kombat_LAN_pending_choice_exit_frees_cabinet",runtime.state.screen=="world" and not Kombat.matches.front_left)
    local errors={}
    for _,session in ipairs({host,guest}) do
        for _,event in ipairs(session:drainEvents()) do if event.type=="error" then errors[#errors+1]=event.message end end
    end
    check("kombat_LAN_selection_and_animation_packets_send_without_errors",#errors==0,table.concat(errors," / "))
    host:stop("Kombat test complete");guest:stop("Kombat test complete");network:dispose();Kombat.clear()
end
function Test.run(context,check)
    flowChecks(check);versusChecks(check);combatChecks(check);jumpChecks(check);artChecks(check);networkChecks(context,check)
    Kombat.clear();Screen.held={};Screen.touches={};Screen.view="title"
end
return Test
