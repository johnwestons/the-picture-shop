local Ball=require("src.basketball")
local Games=require("src.breakroom_games")
local Path=require("src.basketball_trajectory")
local Art=require("src.basketball_art")
local Controls=require("src.basketball_controls")
local Renderer=require("src.basketball_renderer")
local Protocol=require("src.net.protocol")
local Codec=require("src.net.codec")
local State=require("src.state")
local Test={}
local function fixture(x,y,id)
    Ball.clear()
    local state=State.new();state.money=50000
    local upgrades=require("src.warehouse_upgrades")
    assert(upgrades.purchase(state,"front_left","breakroom","BASKETBALL-ROOM",0))
    upgrades.update(state,0)
    upgrades.update(state,0,{noticeDeliveredProjectId="WUP-0001",noticeCallId="BALL-CALL"})
    upgrades.update(state,2,{workerArrivedProjectId="WUP-0001"})
    upgrades.update(state,98)
    upgrades.update(state,98,{workerReleasedProjectId="WUP-0001"})
    assert(Games.purchase(state,"front_left","basketball","TEST-HOOP"))
    local ball=state.breakroomGames.bays.front_left.ball
    ball.x,ball.y=x,y
    local player={id=id or 1,sceneId="front_left",x=x,y=y,intentX=-1,intentY=0,
        character="rabbit-worker",moving=false,animationDistance=0,idleClock=0,
        furColorway=1,overallsColorway=1}
    assert(Ball.command(state,player,"pickup"))
    return state,player,ball
end
local function advance(state,player,seconds,step)
    step=step or 1/120
    while seconds>.000001 do
        local dt=math.min(step,seconds)
        Ball.update(dt,state,{[player.id]=player});seconds=seconds-dt
    end
end
local function shoot(x,y,aim,height,elapsed,step)
    local state,player,ball=fixture(x,y)
    assert(Ball.command(state,player,"shot_start"))
    advance(state,player,elapsed)
    assert(Ball.command(state,player,"shot_release",{aimX=aim,arcHeight=height,elapsed=elapsed}))
    local shot=Ball.shots.front_left
    advance(state,player,shot.duration+.001,step)
    return state,player,ball,shot
end
local function physicsChecks(check)
    local state,player,ball=fixture(400,440)
    assert(Ball.command(state,player,"shot_start"))
    check("basketball_other_player_cannot_release_shot",not Ball.command(state,{id=2,x=400,y=440,sceneId="front_left"},"shot_release"))
    check("basketball_nonfinite_aim_is_rejected",not Ball.command(state,player,"shot_release",{aimX=0/0,arcHeight=100}))
    check("basketball_forged_apex_time_is_rejected",not Ball.command(state,player,"shot_release",{aimX=0,arcHeight=100,elapsed=.62}))
    check("basketball_drop_cannot_interrupt_charge",not Ball.command(state,player,"drop"))
    local earlyState,_,_,early=shoot(400,440,0,105,.2)
    check("basketball_early_release_misses",not early.scored and Ball.streaks.front_left==0)
    local lateState,_,_,late=shoot(400,440,0,105,.9)
    check("basketball_late_release_misses",not late.scored and Ball.streaks.front_left==0)
    for _,step in ipairs({1/30,1/60,.2}) do
        local backState,p,b,shot=shoot(100,420,0,105,Path.APEX,step)
        check("basketball_backboard_blocks_at_"..step,shot.boardHit and not shot.scored)
        local changed=false
        for _=1,400 do
            if Ball.update(1/120,backState,{[p.id]=p}) then changed=true end
        end
        check("basketball_backboard_rebound_becomes_retrievable_"..step,
            b.mode=="placed" and not Ball.shots.front_left,
            b.mode.." / "..b.x..","..b.y.." phase "..tostring(Ball.shots.front_left and Ball.shots.front_left.phase)
                .." / "..tostring(Ball.shots.front_left and Ball.shots.front_left.elapsed))
    end
    local hx,hy=Path.sweepBoard(Path.board[1]+30,Path.board[2]-80,Path.board[1]+30,Path.board[2]+120)
    check("basketball_fast_sweep_cannot_tunnel_through_board",hx and hy and not Path.overlapsBoard(hx,hy,Path.RADIUS-.01))
    local cleanState,p,b,clean=shoot(400,440,0,105,Path.APEX)
    check("basketball_clean_shot_counts_once",clean.scored and clean.perfect and Ball.streaks.front_left==1)
    advance(cleanState,p,3)
    check("basketball_scored_ball_returns_to_floor_without_duplicate_score",b.mode=="placed" and Ball.streaks.front_left==1)
    for _,height in ipairs({45,105,190}) do
        local path=Path.path(600,600,0,height,Path.APEX)
        local x,y=Path.point(path,path.duration)
        check("basketball_arc_"..height.."_reaches_rim_height",path.duration==path.duration
            and math.abs(x-Path.rim.x)<.001 and math.abs(y-Path.rim.y)<.001)
    end
    state,player,ball=fixture(400,440)
    assert(Ball.command(state,player,"shot_start"));advance(state,player,1.2)
    check("basketball_overheld_shot_auto_releases",ball.mode=="flight" and Ball.shots.front_left.phase~="charge")
    local saved=require("src.save_schema").snapshot(state)
    check("basketball_live_shot_not_written_into_test_saves",saved.breakroomGames.bays.front_left.ball.mode=="placed"
        and saved.breakroomGames.bays.front_left.ball.holderPlayerId==nil)
end
local function awkwardShotChecks(check)
    for _,x in ipairs({100,250,600}) do for _,y in ipairs({300,420,620}) do
        for _,height in ipairs({45,105,190}) do for _,aim in ipairs({-85,0,85}) do
            local state,player,ball=fixture(x,y)
            local started,code=Ball.command(state,player,"shot_start")
            if not started then
                check("basketball_distant_shot_is_rejected_"..x.."_"..y.."_"..height.."_"..aim,
                    code=="out_of_range" and not Ball.shots.front_left)
            else
            advance(state,player,Path.APEX)
            assert(Ball.command(state,player,"shot_release",{aimX=aim,arcHeight=height,elapsed=Path.APEX}))
            local clean=true
            for _=1,300 do
                Ball.update(1/30,state,{[1]=player})
                local shot=Ball.shots.front_left
                if shot and ball.x<Path.boardPlaneX+Path.RADIUS-.01
                    and Path.overlapsBoard(ball.x,shot.displayY,Path.RADIUS-.05) then clean=false end
            end
            check("basketball_awkward_shot_recovers_"..x.."_"..y.."_"..height.."_"..aim,
                clean and ball.mode=="placed" and not Ball.shots.front_left,
                tostring(clean).." / "..ball.mode.." / "..ball.x..","..ball.y)
            end
        end end
    end end
end
local function inputChecks(check)
    local state,player=fixture(420,450);state.screen="world"
    local Runtime={state=state,World={player=player},multiplayer={isClient=function() return false end},
        App={cameraTransformsWorld=function() return true end,
            mobileCamera={screenToWorld=function(_,x,y)return x*2,y*2 end}},
        mobileControls={joystick={x=80,y=580,radius=60},_buttonAt=function()return nil end}}
    check("basketball_mouse_hold_starts_shot",Controls.mousepressed(320,300,1,Runtime))
    Controls.drag(Runtime,350,270,"mouse")
    check("basketball_drag_respects_camera_and_changes_target_and_arc",Runtime.basketballCharge.aimX==39
        and Runtime.basketballCharge.arcHeight==141)
    Controls.update(.2,Runtime);Ball.update(.2,state,{[1]=player})
    check("basketball_arc_uses_current_drag_while_jumping",state._basketballAim.elapsed==.2
        and Ball.renderRecords(state)[1].aimX==39)
    check("basketball_mouse_release_launches_final_aim",Controls.mousereleased(350,270,1,Runtime)
        and Ball.shots.front_left.aimX==39 and Ball.shots.front_left.arcHeight==141)
    check("basketball_mouse_release_clears_pointer",not Runtime.basketballCharge and not state._basketballAim)
    state,player=fixture(420,450);state.screen="world";Runtime.state,Runtime.World.player=state,player
    check("basketball_touch_hold_starts_without_camera_gesture",Controls.touchpressed("finger",320,300,Runtime))
    check("basketball_other_finger_cannot_steal_aim",not Controls.touchmoved("other",360,280,Runtime))
    Controls.touchmoved("finger",360,280,Runtime)
    check("basketball_touch_drag_updates_arc",Runtime.basketballCharge.aimX==52 and Runtime.basketballCharge.arcHeight==129)
    check("basketball_touch_release_shoots",Controls.touchreleased("finger",360,280,Runtime)
        and state.breakroomGames.bays.front_left.ball.mode=="flight")
    state,player=fixture(420,450);state.screen="world";Runtime.state,Runtime.World.player=state,player
    assert(Controls.start(Runtime))
    Controls.beginDrag(Runtime,320,300,"aim-only");Controls.drag(Runtime,340,290,"aim-only")
    Controls.release(Runtime,"aim-only")
    check("basketball_secondary_drag_does_not_release_space_shot",Runtime.basketballCharge and Ball.isCharging(1))
    assert(Controls.release(Runtime))
    state,player=fixture(420,450);state.screen="world";Runtime.state,Runtime.World.player=state,player
    check("basketball_touch_joystick_retains_movement",not Controls.touchpressed("stick",80,580,Runtime))
    assert(Controls.start(Runtime));player.sceneId="warehouse";Controls.update(.01,Runtime)
    check("basketball_scene_change_clears_aim",not Runtime.basketballCharge)
    state,player=fixture(420,450);state.screen="world";Runtime.state,Runtime.World.player=state,player
    local requests,available={},false
    Runtime.multiplayer={isClient=function()return true end,requestInteraction=function(_,_,command,aim)
        if command=="basketball:shot_start" then return true end
        if not available then return false end
        requests[#requests+1]=aim;return true
    end}
    assert(Controls.start(Runtime));Controls.update(.62,Runtime)
    -- The simulation clamps long frames to .2; use the exact sampled release.
    Runtime.basketballCharge.elapsed=.62
    Controls.release(Runtime,"mouse") -- A secondary pointer doesn't fire a Space hold.
    Controls.release(Runtime)
    Controls.update(.1,Runtime);available=true;Controls.update(.1,Runtime)
    check("basketball_pending_LAN_start_keeps_original_release_timing",#requests==1 and requests[1].elapsed==.62
        and not Runtime.basketballCharge)
    Ball.clear()
end
local function artChecks(check)
    for _,direction in ipairs({"north","northeast","east","southeast","south"}) do
        local data=love.image.newImageData("assets/generated/basketball-actions-v2/"..direction..".png")
        check("basketball_atlas_dimensions_"..direction,data:getWidth()==1024 and data:getHeight()==1536)
        for frame=1,24 do
            local ox,oy=(frame-1)%4*256,math.floor((frame-1)/4)*256
            local safe=true
            for i=0,255 do
                for _,point in ipairs({{ox+i,oy},{ox+i,oy+255},{ox,oy+i},{ox+255,oy+i}}) do
                    local _,_,_,alpha=data:getPixel(point[1],point[2]);if alpha>.02 then safe=false end
                end
            end
            check("basketball_pose_has_no_clipped_edges_"..direction.."_"..frame,safe)
        end
        data:release()
    end
    local frames={}
    for i=0,11 do frames[Art.chargeFrame(Path.APEX*i/12+.001)]=true end
    local count=0;for _ in pairs(frames) do count=count+1 end
    check("basketball_all_twelve_pre_release_poses_play",count==12)
end
local function wireChecks(check)
    local state,player=fixture(420,450)
    assert(Ball.command(state,player,"shot_start"));advance(state,player,Path.APEX)
    local request={sessionId="BASKETBALL",requestId=1,targetKind="roomGame",desiredState="basketball:shot_release",
        shotAim={aimX=12,arcHeight=130,elapsed=.62}}
    local packet,err=Protocol.encode("interaction_request",request)
    local decoded=packet and Protocol.decode(packet)
    check("basketball_wire_carries_final_drag_and_precise_release",decoded and decoded.payload.shotAim.elapsed==.62,err)
    request.shotAim.aimX=101
    check("basketball_wire_rejects_out_of_range_aim",not Protocol.encode("interaction_request",request))
    request.shotAim.aimX=12;request.desiredState="basketball:pickup"
    check("basketball_wire_rejects_aim_on_other_actions",not Protocol.encode("interaction_request",request))
    local record=Ball.snapshot(state)[1]
    local wire,error=Protocol.encode("snapshot",{sessionId="BASKETBALL",serverTick=10,
        players=Codec.array({}),balls=Codec.array({record})})
    local decodeError
    if wire then decoded,decodeError=Protocol.decode(wire) end
    check("basketball_ball_shard_stays_below_MTU",decoded and #wire<=1200 and decoded.payload.balls[1].arcHeight==105,
        error or decodeError or (wire and #wire))
    local session=require("src.net.session").new({})
    session.sessionId="BASKETBALL"
    session:_applySnapshot(decoded.payload)
    local old={};for k,v in pairs(record)do old[k]=v end
    old.aimX=-90
    session:_applySnapshot({sessionId="BASKETBALL",serverTick=9,players={},balls={old}})
    check("basketball_old_ball_packet_cannot_rewind_aim",session:ballSnapshot()[1].aimX==0)
    old.bayId="front_right"
    session:_applySnapshot({sessionId="BASKETBALL",serverTick=11,players={},balls={old}})
    check("basketball_two_room_shards_merge",#session:ballSnapshot()==2)
    Ball.clear()
end
local function sessionChecks(context,check)
    local state,unused=fixture(380,440,2)
    -- Begin the session with the owned ball loose, then use real guest requests.
    state.breakroomGames.bays.front_left.ball.mode="placed"
    state.breakroomGames.bays.front_left.ball.holderPlayerId=nil
    local upgrades=require("src.warehouse_upgrades")
    assert(upgrades.purchase(state,"front_right","breakroom","SECOND-BALL-ROOM",100))
    upgrades.update(state,100)
    upgrades.update(state,100,{noticeDeliveredProjectId="WUP-0002",noticeCallId="BALL-CALL-2"})
    upgrades.update(state,102,{workerArrivedProjectId="WUP-0002"})
    upgrades.update(state,198)
    upgrades.update(state,198,{workerReleasedProjectId="WUP-0002"})
    assert(Games.purchase(state,"front_right","basketball","SECOND-HOOP"))
    local Harness=require("src.tests.support.network_impairment_harness")
    local network=Harness.new({maxClients=1,classify=function(bytes)local e=Protocol.decode(bytes);return e and e.type or "invalid" end})
    local Session=require("src.net.session")
    local now=0
    local hp={id=1,x=420,y=400,sceneId="front_left",intentX=-1,intentY=0,character="rabbit-worker"}
    local gp={id=2,x=380,y=440,sceneId="front_left",intentX=-1,intentY=0,character="rabbit-worker"}
    local host=Session.new({transportFactory=network.factory,clock=function()return now end})
    local guest=Session.new({transportFactory=network.factory,clock=function()return now end})
    local hc={localPlayer=hp,moveRemote=function()end,resolveGuestSpawn=function()return 380,440 end,
        getShopSnapshot=function()return {state=assert(require("src.save_schema").snapshot(state)),
            player={x=hp.x,y=hp.y,character=hp.character}}end,
        getBasketballSnapshot=function()return Ball.snapshot(state)end,
        performInteraction=function(p,kind,command,aim)
            return context.world.performNetworkInteraction(p,state,kind,command,aim)
        end}
    local gc={localPlayer=gp,inputX=0,inputY=0,gameX=0,gameY=0}
    assert(host:startHost({name="Basket Host",character="rabbit-worker",localPlayer=hp,
        addressOptions={socket={dns={gethostname=function()return "host"end,toip=function()return "192.168.1.2"end}}}}))
    assert(guest:startClient("192.168.1.2:22122",{name="Basket Guest",character="rabbit-worker"}))
    local function pump(n)
        for _=1,n do
            now=now+.01;network:advanceSteps(1)
            host:update(.01,hc);guest:update(.01,gc)
            local players={[1]=hp,[2]=host.players[2]}
            Ball.update(.01,state,players)
        end
    end
    pump(100)
    check("basketball_real_LAN_guest_ready",guest.ready)
    host.players[2].sceneId="front_left";gp.sceneId="front_left"
    assert(guest:requestInteraction("roomGame","basketball:pickup"));pump(20)
    check("basketball_real_LAN_guest_takes_possession",state.breakroomGames.bays.front_left.ball.holderPlayerId==2)
    assert(guest:requestInteraction("roomGame","basketball:shot_start"));pump(45)
    gc.gameX,gc.gameY=.04,.3
    pump(10)
    check("basketball_LAN_live_drag_reaches_host",math.abs(Ball.shots.front_left.aimX-4)<.001)
    assert(guest:requestInteraction("roomGame","basketball:shot_release",{aimX=0,arcHeight=105,elapsed=.62}))
    pump(25)
    local shot=Ball.shots.front_left
    check("basketball_LAN_precise_release_and_final_aim_reach_host",shot and shot.perfect and shot.aimX==0)
    local received=guest:ballSnapshot()
    check("basketball_two_room_LAN_ball_shards_are_retained",#received==2)
    local flight
    for _,record in ipairs(received) do if record.bayId=="front_left" then flight=record end end
    check("basketball_LAN_flight_and_animation_replicate",flight and flight.mode=="flight" and flight.releaseTime==.62)
    pump(300)
    check("basketball_LAN_clean_shot_scores_and_ball_returns",Ball.streaks.front_left==1 and state.breakroomGames.bays.front_left.ball.mode=="placed")
    local errors={}
    for _,event in ipairs(host:drainEvents()) do if event.type=="error" then errors[#errors+1]=event.message end end
    check("basketball_LAN_packets_fit_MTU_without_send_errors",#errors==0,table.concat(errors," / "))
    host:stop("basketball test done");guest:stop("basketball test done");network:dispose();Ball.clear()
end
local function drawAvatar(state,player,fur,overalls)
    player.furColorway,player.overallsColorway=fur,overalls
    local canvas=love.graphics.newCanvas(128,128)
    love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,0)
    love.graphics.translate(64-player.x,108-player.y)
    assert(Renderer.draw(player,state));love.graphics.pop()
    local data=canvas:newImageData();canvas:release();return data
end
local function renderChecks(context,check)
    local state,player=fixture(400,450)
    player.intentX,player.intentY=1,0;player.idleClock=.36
    local normal=drawAvatar(state,player,1,1)
    local customized=drawAvatar(state,player,4,3)
    local changed=0
    for y=0,127 do for x=0,127 do
        local r,g,b,a=normal:getPixel(x,y)
        local nr,ng,nb=customized:getPixel(x,y)
        if a>.5 and math.abs(r-nr)+math.abs(g-ng)+math.abs(b-nb)>.15 then changed=changed+1 end
    end end
    check("basketball_real_shader_recolors_dribble_fur_and_overalls",changed>400,changed)
    local bx,by=Art.ballPoint(player,3,0)
    local px,py=math.floor(64+bx-player.x),math.floor(108+by-player.y+2)
    local r,g,b=normal:getPixel(px,py);local nr,ng,nb=customized:getPixel(px,py)
    check("basketball_remains_orange_after_character_recolor",r>g and g>b
        and math.abs(r-nr)+math.abs(g-ng)+math.abs(b-nb)<.02)
    normal:release();customized:release()
    local output=os.getenv("PICTURE_SHOP_BASKETBALL_CAPTURE_DIR")
    local world=context.world
    local previous={};for k,v in pairs(world.player)do previous[k]=v end
    local oldState,selection=world._state,world.selectedInteraction
    world._state,world.selectedInteraction=state,nil
    local function capture(name)
        for k in pairs(world.player)do world.player[k]=nil end
        for k,v in pairs(player)do world.player[k]=v end
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(0,0,0,1)
        world.draw(context.assets,context.characterAssets,state,nil,nil,{})
        love.graphics.pop()
        if output then
            local data=canvas:newImageData()
            local file=assert(io.open(output.."/"..name..".png","wb"));file:write(data:encode("png"):getString());file:close();data:release()
        end
        canvas:release()
    end
    capture("customized-dribble")
    assert(Ball.command(state,player,"shot_start"));advance(state,player,Path.APEX)
    Ball.setAim(state,1,4,125);capture("aim-at-apex")
    assert(Ball.command(state,player,"shot_release"));advance(state,player,.15)
    local oldDraw=love.graphics.draw
    local index,ballIndex,goalIndex=0,0,0
    love.graphics.draw=function(image,...)
        index=index+1
        if image.getDimensions then
            local w,h=image:getDimensions()
            if w==24 and h==24 then ballIndex=index elseif h==235 then goalIndex=index end
        end
        return oldDraw(image,...)
    end
    capture("flight-in-front-of-goal")
    love.graphics.draw=oldDraw
    check("basketball_flight_draws_above_backboard_layer",goalIndex>0 and ballIndex>goalIndex)
    state,player=fixture(250,420);world._state=state
    assert(Ball.command(state,player,"shot_start"));advance(state,player,Path.APEX)
    assert(Ball.command(state,player,"shot_release",{aimX=-85,arcHeight=45,elapsed=.62}))
    for _=1,300 do
        Ball.update(1/120,state,{[1]=player})
        if Ball.shots.front_left and Ball.shots.front_left.boardHit then capture("backboard-contact");break end
    end
    for k in pairs(world.player)do world.player[k]=nil end
    for k,v in pairs(previous)do world.player[k]=v end
    world._state,world.selectedInteraction=oldState,selection
    Ball.clear();Renderer.clear()
end
function Test.run(context,check)
    check("basketball_perfect_release_is_one_sixtieth_second_precision",
        Path.PERFECT_WINDOW*2<2/60 and Path.CHARGE_FRAMES==12)
    for _,pos in ipairs({{380,460},{500,400},{250,380},{180,540}}) do
        local found,detail=false,""
        for aim=-5,11,4 do
            local state,_,_,shot=shoot(pos[1],pos[2],aim,105,Path.APEX)
            detail=detail..aim..":"..tostring(shot.scored).."/"..tostring(shot.boardHit).." "
            if shot.scored then found=true end
        end
        check("basketball_clean_apex_shot_"..pos[1].."_"..pos[2],found,detail)
    end
    physicsChecks(check)
    awkwardShotChecks(check)
    inputChecks(check)
    artChecks(check)
    wireChecks(check)
    sessionChecks(context,check)
    renderChecks(context,check)
    Ball.clear()
end
return Test
