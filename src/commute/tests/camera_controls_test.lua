local Controls=require('src.commute.camera_controls')
local Commute=require('src.commute.runtime')
local Test={}
function Test.run(check)
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
    local R={App={},Assets={},state={screen='world',home={commute={}}},
        Config={baseWidth=1280,baseHeight=880},_commute={camera=camera},
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
    end)
    love.keyboard.isDown=oldIsDown
    assert(okay,reason)
end
return Test
