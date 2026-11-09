local Controls=require('src.commute.camera_controls')
local Commute=require('src.commute.runtime')
local Camera=require('src.commute.camera')
local Test={}
local function firstPersonMouse(check)
    local world={height=function()return 0 end,supportHeight=function()return 0 end}
    local tau=math.pi*2
    -- Check actual projected world points, including headings across the wrap;
    -- this would fail if the input signs or projection convention are inverted.
    for _,heading in ipairs({0,tau-.02}) do
        local actor={x=100,z=100,heading=heading,speed=0}
        local camera=Camera.new(actor,world);camera:setFirstPerson(true,actor)
        local drag={}
        for _,gesture in ipairs({{button=3,alt=false,name='middle'},
            {button=2,alt=false,name='right'},{button=3,alt=true,name='alt_middle'}}) do
            assert(Controls.press(drag,gesture.button,gesture.alt))
            for _,delta in ipairs({{20,0,'right'},{-20,0,'left'},{0,-20,'up'},{0,20,'down'}}) do
                camera:recenter()
                local x,z=actor.x+math.cos(heading)*10,actor.z+math.sin(heading)*10
                local h=camera.eyeHeight+math.tan(camera.viewPitch)*10
                local beforeX,beforeY=camera:screen(x,z,h)
                Controls.move(drag,camera,delta[1],delta[2],1)
                for _=1,60 do camera:update(actor,1/60) end
                local afterX,afterY=camera:screen(x,z,h)
                local intuitive=(delta[1]>0 and afterX<beforeX-1 and camera.lookYaw>0)
                    or (delta[1]<0 and afterX>beforeX+1 and camera.lookYaw<0)
                    or (delta[2]<0 and afterY>beforeY+1 and camera.lookPitch>0)
                    or (delta[2]>0 and afterY<beforeY-1 and camera.lookPitch<0)
                check('first_person_mouse_'..gesture.name..'_looks_'..delta[3]..(heading==0 and '' or '_wrapped'),intuitive)
            end
            Controls.release(drag,gesture.button)
        end
        assert(Controls.press(drag,3,false));camera:recenter()
        Controls.move(drag,camera,20,-12,1)
        local yaw,pitch=camera.lookYaw,camera.lookPitch
        camera:recenter();Controls.move(drag,camera,10,-6,.5)
        check('first_person_mouse_scaling_is_resolution_independent'..(heading==0 and '' or '_wrapped'),
            math.abs(camera.lookYaw-yaw)<1e-10 and math.abs(camera.lookPitch-pitch)<1e-10)
        Controls.cancel(drag)
    end
end
function Test.run(check)
    firstPersonMouse(check)
    local calls={}
    local camera={orbit=function(_,x,y) calls[#calls+1]={'orbit',x,y} end,
        pan=function(_,x,y) calls[#calls+1]={'pan',x,y} end}
    local drag={}
    check('camera_left_click_is_not_drag',not Controls.press(drag,1,false))
    assert(Controls.press(drag,3,false));Controls.move(drag,camera,20,12,1)
    check('camera_middle_orbits_with_critter_party_sensitivity',calls[1][1]=='orbit' and calls[1][2]==-9 and calls[1][3]==3)
    check('camera_left_release_preserves_middle_drag',not Controls.release(drag,1) and drag.mode=='orbit')
    Controls.move(drag,camera,10,6,.5)
    check('camera_drag_is_viewport_scale_independent',calls[2][2]==-9 and calls[2][3]==3)
    check('camera_matching_release_stops_drag',Controls.release(drag,3) and not Controls.move(drag,camera,5,5))
    assert(Controls.press(drag,3,true));Controls.move(drag,camera,20,12,1)
    check('camera_left_alt_middle_pans',calls[3][1]=='pan' and calls[3][2]==20 and calls[3][3]==12)
    Controls.move(drag,camera,2,4,1)
    check('camera_pan_mode_stays_latched_until_release',calls[4][1]=='pan')
    Controls.release(drag,3);Controls.press(drag,2,false);Controls.move(drag,camera,3,4,1)
    check('camera_right_drag_is_alternate_pan',calls[5][1]=='pan')
    Controls.cancel(drag);check('camera_cancel_clears_drag',not drag.mode and not drag.button)

    -- Exercise the actual production callback routing, not just the helper.
    local dispatched=0
    local owner={id=1}
    local R={App={},Assets={},World={player=owner},
        state={screen='world',home={commute={participants={owner={}}}}},
        Config={baseWidth=1280,baseHeight=880},_commute={camera=camera,renderer={}},
        toPointerCoordinates=function(x,y)return x*.5,y*.5 end,
        dispatchMousePressed=function()dispatched=dispatched+1 end,
        dispatchMouseReleased=function()dispatched=dispatched+1 end,
        dispatchMouseMoved=function()dispatched=dispatched+1 end}
    require('src.runtime.input_callbacks').install(R)
    local oldIsDown=love.keyboard.isDown
    local alt=false
    love.keyboard.isDown=function(key)return key=='lalt' and alt end
    local okay,reason=pcall(function()
        R.App.mousepressed(300,200,3,false);R.App.mousemoved(320,212,20,12,false)
        local last=calls[#calls]
        check('main_callback_routes_middle_drag_in_logical_pixels',last[1]=='orbit' and last[2]==-4.5 and last[3]==1.5 and dispatched==0)
        R.App.mousereleased(320,212,3,false)
        alt=true;R.App.mousepressed(300,200,3,false);alt=false
        R.App.mousemoved(320,212,20,12,false);last=calls[#calls]
        check('main_callback_keeps_alt_pan_after_alt_release',last[1]=='pan' and last[2]==10 and last[3]==6)
        Commute.cancelCameraDrag(R)
        check('main_focus_cancel_prevents_stuck_drag',not R._commute.cameraDrag.mode)
        R.App.mousepressed(300,200,2,false);R.state.screen='options'
        R.App.mousemoved(320,212,20,12,false)
        check('main_menu_cancels_camera_drag',not R._commute.cameraDrag.mode and dispatched==1)
        R.state.screen='world';R.state.home.commute=nil
        R.App.mousepressed(300,200,3,false)
        check('main_noncommute_input_keeps_existing_controls',dispatched==2 and not R._commute.cameraDrag.mode)
        R.state.home.commute={participants={owner={}}};R.state.screen='world';alt=false
        local actor={x=100,z=100,heading=math.pi*2-.02,speed=0}
        local eye=Camera.new(actor,{height=function()return 0 end})
        eye:setFirstPerson(true,actor);R._commute.camera=eye
        -- The neutral gaze is slightly below the chassis axis. A small upward
        -- drag should raise it from that initial view, including across 2π.
        local initialHeading,initialPitch=eye.viewHeading,eye.viewPitch
        R.App.mousepressed(300,200,3,false);R.App.mousemoved(320,188,20,-12,false)
        for _=1,60 do eye:update(actor,1/60) end
        check('main_callback_first_person_mouse_right_up_turns_head_right_up',eye.lookYaw>0 and eye.lookPitch>0
            and eye.viewHeading>initialHeading and eye.viewPitch>initialPitch)
        R.App.mousereleased(320,188,3,false);eye:recenter()
        R.App.mousepressed(300,200,2,false);R.App.mousemoved(280,212,-20,12,false)
        check('main_callback_first_person_alternate_drag_looks_left_down',eye.lookYaw<0 and eye.lookPitch<0)
        R.App.mousereleased(280,212,2,false)
    end)
    love.keyboard.isDown=oldIsDown
    assert(okay,reason)
end
return Test
