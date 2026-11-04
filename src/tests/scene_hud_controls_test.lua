-- Exercise the real App callbacks, including transformed pointer coordinates.
local C=require('src.commute.runtime')
local B=require('src.commute.bindings')
local V=require('src.screens.hud_visibility')
local Settings=require('src.settings')
local Test={}
function Test.run(R,check,capture)
    R.Config.baseWidth,R.Config.baseHeight=640,480
    local part=C.localPart(R);local view=R._commute;local camera=view.camera
    C.bindings(R).outsideCamera='fixed';C.applyCameraPreference(R,camera,part.rider)
    camera:setFirstPerson(true,part.rider.bike);view.cameraLocked=false
    local function physical(x,y)
        R.syncCamera()
        local ox,oy,scale=R.Viewport.transform(640,480,R.App.officeUsesSafeArea())
        return ox+x*scale,oy+y*scale
    end
    local function press(id,x,y) R.App.touchpressed(id,physical(x,y)) end
    local function move(id,x,y) R.App.touchmoved(id,physical(x,y)) end
    local function release(id,x,y) R.App.touchreleased(id,physical(x or 256,y or 250)) end
    local function tap(id)
        for _,button in ipairs(V.buttons(R)) do
            if button.id==id then
                press('toolbar',button.x+button.width/2,button.y+16)
                release('toolbar',button.x+button.width/2,button.y+16);return
            end
        end
        error('Missing toolbar button: '..id)
    end
    local function signature()
        local result={}
        for _,key in ipairs({'lookYaw','lookPitch','fov','yaw','tilt','offsetX','offsetY','targetZoom'}) do
            result[#result+1]=('%.8f'):format(camera[key] or 0)
        end
        return table.concat(result,'|')
    end
    local function gestures()
        local x,y=physical(256,250)
        R.App.mousepressed(x,y,3,false);R.App.mousemoved(x+40,y+25,40,25,false)
        R.App.mousereleased(x+40,y+25,3,false)
        R.App.mousepressed(x,y,2,false);R.App.mousemoved(x+25,y+15,25,15,false)
        R.App.mousereleased(x+25,y+15,2,false)
        R.App.wheelmoved(0,1)
        press('look-one',256,250);move('look-one',280,265)
        press('look-two',340,250);move('look-two',380,280)
        release('look-two');release('look-one')
        R.App.keypressed('c');R.App.keypressed('=')
        C.touch(R).cameraX=1;C.touch(R).cameraY=1
        local before=signature();R.App.update(1/60)
        C.touch(R).cameraX=0;C.touch(R).cameraY=0
        return before==signature()
    end
    check('scene_hud_legacy_settings_default_to_visible_and_shortcuts_are_reserved',
        Settings.normalize({}).hudVisible and not B.valid('keyboard','horn','f8') and not B.valid('keyboard','horn','f9'))

    local x,y=physical(256,250)
    local before=signature()
    R.App.mousepressed(x,y,3,false);R.App.mousemoved(x+30,y+20,30,20,false);R.App.mousereleased(x+30,y+20,3,false)
    check('scene_hud_unlocked_first_person_mouse_look_works',signature()~=before)

    -- Locking must cancel an in-progress gesture without cancelling the throttle.
    local go
    for _,button in ipairs(require('src.commute.touch_controls').actionButtons(640,480,C.bindings(R),
        C.controlContext(R),{mobile=true,camera=camera})) do if button.action=='accelerate' then go=button end end
    press('gas',go.x,go.y);press('old-look',256,250);move('old-look',270,255)
    tap('lock')
    check('scene_hud_touch_lock_cancels_active_look_and_preserves_held_throttle',V.cameraLocked(R)
        and view.cameraTouches==nil and view.cameraPinch==nil and not view.cameraDrag.mode
        and B.value(C.bindings(R),'accelerate',C.touch(R))==1)
    local profile=C.bindings(R);local pan,beam=profile.mouse.pan,profile.mouse.beam
    profile.mouse.pan='';profile.mouse.beam='mouse2'
    local highBeam=part.rider.bike.headlightHighBeam==true
    x,y=physical(256,250);R.App.mousepressed(x,y,2,false);R.App.mousereleased(x,y,2,false)
    profile.mouse.pan,profile.mouse.beam=pan,beam
    check('scene_hud_camera_lock_preserves_remapped_mouse_bike_actions',
        (part.rider.bike.headlightHighBeam==true)~=highBeam)
    before=signature();move('old-look',300,285);release('old-look')
    local held=gestures()
    check('scene_hud_first_person_lock_blocks_mouse_touch_pinch_wheel_keys_and_polled_look',held and signature()==before)
    capture('bike-first-person-locked',640,480,false)

    view.mapOpen=true;tap('hud')
    check('scene_hud_hiding_closes_map_and_preserves_driving_contacts',not V.isVisible(R) and not view.mapOpen
        and B.value(C.bindings(R),'accelerate',C.touch(R))==1)
    check('scene_hud_hidden_preference_round_trips',Settings.load().hudVisible==false)
    before=signature();held=gestures()
    check('scene_hud_hidden_first_person_lock_still_blocks_camera_gestures',held and signature()==before)
    capture('bike-first-person-hidden-locked',640,480,false)
    local stick=C.bindings(R).layout.stick
    press('steer',stick.x*640,stick.y*480);move('steer',stick.x*640+36,stick.y*480-12)
    local steer,drive=B.drive(C.bindings(R),C.touch(R),camera,part.rider.bike)
    check('scene_hud_locked_hidden_controls_still_steer_and_accelerate',steer>.1 and drive<0,
        ('steer=%s drive=%s stick=%s throttle=%s firstPerson=%s'):format(steer,drive,C.touch(R).x,
            tostring(C.touch(R).held.accelerate),tostring(camera.firstPerson)))
    release('steer');release('gas',go.x,go.y)
    check('scene_hud_hidden_driving_contacts_release_normally',not C.touch(R).held.accelerate and C.touch(R).x==0)
    local _,bounds=R.optionsAccessLayout();local options=R.OptionsScreen.accessRect('world',bounds)
    press('invisible-options',options.x+10,options.y+10);release('invisible-options')
    check('scene_hud_invisible_options_button_does_not_open',R.state.screen=='world')
    tap('hud');tap('lock')
    check('scene_hud_touch_buttons_restore_hud_and_unlock',V.isVisible(R) and not V.cameraLocked(R) and Settings.load().hudVisible)
    before=signature();press('look',256,250);move('look',290,270);release('look')
    check('scene_hud_unlock_restores_touch_look',signature()~=before)

    camera:setFirstPerson(false,part.rider.bike)
    R.App.keypressed('f8');before=signature();held=gestures()
    check('scene_hud_fixed_third_person_lock_blocks_orbit_pan_zoom_and_polled_look',V.cameraLocked(R) and held and signature()==before)
    capture('bike-fixed-locked',640,480,true)
    R.App.keypressed('f9');capture('bike-fixed-hidden-locked',640,480,true)
    R.App.keypressed('f9');R.App.keypressed('f8')
    before=signature();press('outside-look',256,250);move('outside-look',290,270);release('outside-look')
    check('scene_hud_fixed_third_person_unlock_restores_orbit',not V.cameraLocked(R) and signature()~=before)
    R.App.keypressed('f8');C.toggleOutsideCamera(R)
    check('scene_hud_follow_camera_excludes_lock_and_keeps_auto_follow',camera.outsideMode=='follow'
        and not V.canLockCamera(R) and not V.cameraLocked(R) and #V.buttons(R)==1)
    local yaw=camera.yaw;part.rider.bike.heading=part.rider.bike.heading+.35
    for _=1,30 do R.App.update(1/60) end
    check('scene_hud_follow_camera_continues_tracking_heading',math.abs(camera.yaw-yaw)>.01)
    camera:setFirstPerson(true,part.rider.bike)
    check('scene_hud_first_person_lock_works_when_outside_preference_is_follow',V.canLockCamera(R) and V.cameraLocked(R))
    R.App.keypressed('f8')
end
return Test
