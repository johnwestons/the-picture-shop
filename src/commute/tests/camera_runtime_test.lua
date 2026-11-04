-- Real application, saved preferences, input callbacks and native draw paths.
local C=require('src.commute.runtime')
local Bike=require('src.commute.motorcycle')
local Bindings=require('src.commute.bindings')
local Touch=require('src.commute.touch_controls')
local Settings=require('src.settings')
local Test={}
local function capture(R,name)
    local directory=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE');if not directory then return end
    local canvas=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
    love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true});R.App.draw();love.graphics.pop()
    local data=canvas:newImageData();local bytes=data:encode('png')
    local file=assert(io.open(directory..'/'..name..'.png','wb'));file:write(bytes:getString());file:close()
    bytes:release();data:release();canvas:release()
end
local function angle(a,b)return (a-b+math.pi)%(2*math.pi)-math.pi end
local function auditDrawnViews(R,check,rider)
    local view=R._commute;local originalCamera=view.camera
    local part=C.localPart(R);local originalPresentation=part.presentation
    local bike=rider.bike;local saved={}
    local fields={'heading','lean','pitch','speed','paintId','impactPulse','boostPulse','shiftTime','ridingAnimation','h','grounded','vy','vx','vz',
        'brake','throttle','acceleration'}
    for _,key in ipairs(fields) do saved[key]=bike[key] end
    local camera=require('src.commute.camera').new(bike,C.world(R));view.camera=camera
    local art=view.renderer.bikeArt;local g=love.graphics
    local originalDraw=g.draw;local calls={}
    -- The condition HUD also draws a parked-bike quad from this atlas.
    -- Count only draws issued for a world actor, including any incorrect pose.
    local drawBike,instanceDraw=art.draw,rawget(art,'draw')
    local drawingBike=false
    art.draw=function(self,...)
        drawingBike=true
        drawBike(self,...)
        drawingBike=false
    end
    g.draw=function(image,quad,...)
        local info=drawingBike and art:describe(image,quad)
        if info then local _,_,_,alpha=g.getColor();info.alpha=alpha;calls[#calls+1]=info end
        return originalDraw(image,quad,...)
    end
    local okay,reason=xpcall(function()
        part.presentation=nil
        bike.paintId='bronze';bike.speed=0;bike.lean=0;bike.pitch=0
        bike.impactPulse,bike.boostPulse,bike.shiftTime=0,0,0
        bike.ridingAnimation={kind='idle',remaining=0,queue={}}
        local canvas=g.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
        local records={};local duration=require('src.commute.riding_animation').durations
        local samples={
            {state='upright'},
            {state='aeroMid',speed=(Bike.TUCK_START_SPEED+Bike.BOOST_MAX_SPEED)/2},{state='aero',speed=Bike.BOOST_MAX_SPEED},
            {state='turnLeftMid',lean=.225},{state='turnLeft',lean=.3},
            {state='turnRightMid',lean=-.225},{state='turnRight',lean=-.3},
            {state='brakeMid',speed=8,brakingPose=.5},{state='brake',speed=8,brakingPose=1},
            {state='boostMid',ridingAction='boost',ridingActionTime=duration.boost*5/6},
            {state='boost',ridingAction='boost',ridingActionTime=duration.boost/2},
            {state='shiftMid',ridingAction='shift',ridingActionTime=duration.shift*5/6},
            {state='shift',ridingAction='shift',ridingActionTime=duration.shift/2},
            {state='impactMid',impactPulse=Bike.IMPACT_DURATION*5/6,impactStrength=1},
            {state='impact',impactPulse=Bike.IMPACT_DURATION/2,impactStrength=1},
        }
        for _,mode in ipairs({'fixed','follow'}) do for _,sample in ipairs(samples) do
            camera.outsideMode=mode
            camera.yaw=37
            part.presentation=sample
            local all=true;local count=64
            for i=1,64 do
                bike.heading=-math.pi/2+(i-1)*math.pi*2/64-math.rad(camera.yaw)
                calls={}
                g.push('all');g.setCanvas({canvas,stencil=true});R.App.draw();g.pop()
                local c=calls[1]
                records[#records+1]=('{"mode":"%s","expectedState":"%s","expectedFrame":%d,"drawCount":%d,"state":"%s","drawnFrame":%d,"alpha":%.3f}')
                    :format(mode,sample.state,i,#calls,c and c.state or 'missing',c and c.frame or 0,c and c.alpha or 0)
                all=all and #calls==1 and c.frame==i and c.alpha==1
                    and c.state==sample.state
            end
            check('camera_runtime_actual_app_'..mode..'_'..sample.state..'_draws_all_64_views_opaque',all)
        end end
        local directory=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE')
        if directory then
            local file=assert(io.open(directory..'/actual-draw-coverage.json','wb'))
            file:write('{"cameraYaw":37,"draws":['..table.concat(records,',')..']}\n');file:close()
        end
        canvas:release();part.presentation=nil
        camera.outsideMode='fixed';camera.yaw=25
        bike.heading=-math.pi/4;bike.lean=-.1
        capture(R,'fixed-dense-upright-turn')
        bike.h=bike.h+4;bike.grounded=false;bike.pitch=.6;bike.vy=2
        bike.vx,bike.vz=10*math.cos(bike.heading),10*math.sin(bike.heading)
        camera:setFirstPerson(true,bike)
        for _=1,45 do camera:updateRide(rider,1/60) end
        capture(R,'first-person-landing-look')
        check('camera_runtime_airborne_view_aims_below_horizon_with_pitched_bars',camera.viewPitch<-.1 and camera.bikePitch==.6)
    end,debug.traceback)
    g.draw=originalDraw
    art.draw=instanceDraw
    for _,key in ipairs(fields) do bike[key]=saved[key] end
    view.camera=originalCamera;part.presentation=originalPresentation
    assert(okay,reason)
end
function Test.run(context,check)
    local R=assert(context.appRuntime)
    R.Save.delete(3);assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden'})),'smoke'))
    R.state.screen='world'
    local originalProfile=R.App.settings.motorcycleControls
    local originalMovement,originalDrive=R.Input.movement,Bindings.drive
    local steer,drive=0,0
    R.App.settings.motorcycleControls=Bindings.defaults()
    R.Input.movement=function()return 0,0 end
    Bindings.drive=function()return steer,drive,false end
    local function ticks(n)for _=1,n do R.App.update(1/60)end end
    local okay,reason=xpcall(function()
        local Calendar=require('src.business_calendar')
        R.state.calendar=Calendar.dateFromHours(44)
        R.state.calendar.elapsed=44%24/24*Calendar.secondsPerDay(R.state)
        R.state.home.weekend.phase='ready';R.state.home.weekend.closedAtHours=44;R.World.truck.state='absent'
        local entrance=require('src.home_travel').target(R.World.player,R.state)
        R.World.player.x,R.World.player.y=entrance.x,entrance.y
        local Weekend=require('src.weekend_runtime')
        assert(Weekend.command(R,R.World.player,'request'))
        assert(Weekend.command(R,R.World.player,'depart:'..R.state.home.weekend.travelToken))
        require('src.commute.tests.loading_test_support').wait(R,check,'camera_runtime')
        R.App.keypressed('g');ticks(250);R.App.keypressed('e');ticks(150)
        local rider=C.localPart(R).rider;local bike=rider.bike;local camera=R._commute.camera
        assert(rider.gear.mounted and rider.gear.engine)
        check('camera_runtime_defaults_to_fixed_angle',camera.outsideMode=='fixed' and not camera.firstPerson)
        camera:orbit(25,0);local fixedYaw=camera.yaw
        R.App.keypressed('o')
        check('camera_runtime_keyboard_selects_and_saves_follow',camera.outsideMode=='follow'
            and Settings.load().motorcycleControls.outsideCamera=='follow')
        -- Initialize on a real road, then let ordinary inputs turn the bike.
        local segment
        for _,candidate in ipairs(C.world(R).roads.segments) do
            if not candidate.bridge and candidate.distance>40 and candidate.width>=6 then
                segment=candidate;break
            end
        end
        assert(segment,'Camera test needs an open road segment')
        local initialHeading=math.atan2(segment.b.z-segment.a.z,segment.b.x-segment.a.x)
        bike.x,bike.z=(segment.a.x+segment.b.x)*.5,(segment.a.z+segment.b.z)*.5
        bike.heading,bike.speed,bike.gear=initialHeading,6,3
        Bike.resetContact(bike,C.world(R));Bike.resetHorizontal(bike)
        camera:recenter();steer,drive=.6,-.5;ticks(60);steer,drive=0,0;ticks(30)
        local behind=(-bike.heading-math.pi/2)%(2*math.pi)
        check('camera_runtime_follow_tracks_actual_turning_bike',math.abs(angle(bike.heading,initialHeading))>.2
            and math.abs(angle(math.rad(camera.yaw),behind))<.08)
        capture(R,'follow-rider-turn')
        R.App.keypressed('o')
        check('camera_runtime_fixed_mode_restores_chosen_angle',camera.outsideMode=='fixed'
            and math.abs(camera.yaw-fixedYaw)<1e-8)
        local yaw=camera.yaw;steer=.6;ticks(45);steer=0
        check('camera_runtime_fixed_angle_stays_fixed_through_turn',camera.yaw==yaw)
        capture(R,'fixed-angle-turn')
        C.deviceInput(R,'controller','leftshoulder')
        check('camera_runtime_controller_can_select_follow',camera.outsideMode=='follow')
        R._commute.camera=nil;R.App.update(0);camera=R._commute.camera
        check('camera_runtime_recreated_camera_uses_saved_preference',camera.outsideMode=='follow')
        R.App.keypressed('p');assert(camera.firstPerson)
        bike.speed=0;Bike.resetHorizontal(bike);camera:recenter()
        R.App.mousepressed(450,300,3,false);R.App.mousemoved(474,282,24,-18,false)
        R.App.mousereleased(474,282,3,false);ticks(30)
        check('camera_runtime_pc_mouse_right_and_up_look_right_and_up',camera.lookYaw>0 and camera.lookPitch>0
            and camera.headYaw>0 and camera.headPitch>0)
        capture(R,'first-person-mouse-right-up')
        R.App.keypressed('c');R.App.mousepressed(450,300,2,false)
        R.App.mousemoved(426,318,-24,18,false);R.App.mousereleased(426,318,2,false);ticks(30)
        check('camera_runtime_alternate_mouse_drag_looks_left_and_down',camera.lookYaw<0 and camera.lookPitch<0)
        R.App.keypressed('o')
        check('camera_runtime_outside_choice_does_not_exit_first_person',camera.firstPerson and camera.outsideMode=='fixed')
        R.App.keypressed('o');R.App.keypressed('p')
        check('camera_runtime_exiting_first_person_returns_to_follow',not camera.firstPerson and camera.outsideMode=='follow')
        for _,size in ipairs({{960,678},{1280,880},{640,480}}) do
            local context=C.controlContext(R,C.localPart(R));local target
            for _,button in ipairs(Touch.actionButtons(size[1],size[2],Bindings.defaults(),context,{mobile=true})) do
                if button.action=='followCamera' then target=button end
            end
            local pressed=target and Touch.actionAt(target.x,target.y,size[1],size[2],Bindings.defaults(),
                context,{mobile=true})
            check('camera_runtime_follow_button_is_clickable_'..size[1],pressed and pressed.action=='followCamera')
        end
        local context=C.controlContext(R,C.localPart(R));local target
        for _,button in ipairs(Touch.actionButtons(R.Config.baseWidth,R.Config.baseHeight,C.bindings(R),context,
            {mobile=C.mobileInputEnabled(R)})) do if button.action=='followCamera' then target=button end end
        assert(target and C.pointer(R,target.x,target.y,'mouse'))
        check('camera_runtime_hud_button_toggles_fixed_follow',camera.outsideMode=='fixed')
        R.App.keypressed('f10');assert(R.OptionsScreen.motorcycleEditor)
        capture(R,'camera-options-fixed')
        R.App.keypressed('o')
        check('camera_runtime_options_selector_saves_follow',Settings.load().motorcycleControls.outsideCamera=='follow')
        capture(R,'camera-options-follow')
        R.App.keypressed('escape');R.App.keypressed('escape');R.App.update(0)
        check('camera_runtime_options_choice_applies_to_active_camera',R.state.screen=='world'
            and R._commute.camera.outsideMode=='follow')
        require('src.commute.tests.auto_reverse_runtime_test').run(R,check,originalDrive,capture)
        auditDrawnViews(R,check,rider)
    end,debug.traceback)
    R.Input.movement,Bindings.drive=originalMovement,originalDrive
    R.App.settings.motorcycleControls=originalProfile;Settings.save(R.App.settings)
    if not okay then error(reason,0)end
end
return Test
