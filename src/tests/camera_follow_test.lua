local Camera = require("src.mobile_camera")
local Settings = require("src.settings")
local Options = require("src.screens.options_screen")
local Viewport = require("src.viewport")
local Test = {}
local function near(a,b) return math.abs(a-b)<.001 end
function Test.run(context,check)
    check("camera_follow_old_device_settings_default_off",
        not Settings.normalize().followPlayerCamera
        and not Settings.normalize({followPlayerCamera="true"}).followPlayerCamera)
    local player={x=35,y=70}
    local camera=Camera.new({enabled=true,followOffsetY=-38})
    camera:setViewport(1469,678);camera:selectView("world",true)
    camera:setFollowTarget(player)
    local x,y=camera:worldToScreen(player.x,player.y-38)
    check("camera_follow_centers_body_at_warehouse_edge",near(x,480) and near(y,339))
    local before=camera.zoom
    camera:beginGesture(600,420,200);camera:updateGesture(750,460,300)
    x,y=camera:worldToScreen(player.x,player.y-38)
    check("camera_follow_pinch_zooms_without_panning_off_player",camera.zoom>before and near(x,480) and near(y,339))
    player.x,player.y=850,630;camera:setFollowTarget(player)
    x,y=camera:worldToScreen(player.x,player.y-38)
    local worldX,worldY=camera:screenToWorld(x+71,y-83)
    local screenX,screenY=camera:worldToScreen(worldX,worldY)
    check("camera_follow_moving_target_keeps_precise_pointer_transform",
        near(x,480) and near(y,339) and near(screenX,x+71) and near(screenY,y-83))
    local worldZoom=camera.zoom
    camera:selectView("computer",false)
    check("camera_follow_leaves_menu_camera_independent",not camera.followTarget and near(camera.zoom,1))
    camera:selectView("world",true);camera:setFollowTarget(player)
    check("camera_follow_world_zoom_survives_menu_round_trip",near(camera.zoom,worldZoom))
    camera:setFollowTarget(nil)
    before=camera.centerX
    camera:beginGesture(480,339,200);camera:updateGesture(600,339,200)
    check("camera_follow_off_restores_manual_pan",not camera.followTarget and camera.centerX<before)
    camera:endGesture();camera:zoomBy(100)
    check("camera_follow_zoom_stays_bounded",camera.zoom==camera.maximumZoom)

    -- Run the real App draw/input routes on both camera modes. The test
    -- identity is isolated; device preferences and the shop state are restored.
    local app,state=context.app,context.state
    local savedSettings,savedCamera=app.settings,app.mobileCamera
    local savedPrefs=Settings.load()
    local savedScreen,savedSlot,savedReturn=state.screen,state.activeSlot,state.optionsReturnScreen
    local localPlayer=context.world.player
    local savedX,savedY,savedId=localPlayer.x,localPlayer.y,localPlayer.id
    local savedOptions={}
    local optionFields={"tab","selectedRow","selectedSlot","message","hover","editField","editBuffer","draggingControl","context"}
    for _,key in ipairs(optionFields) do savedOptions[key]=Options[key] end
    local function click(gx,gy)
        local ox,oy,scale=Viewport.transform(960,678)
        app.mousepressed(ox+gx*scale,oy+gy*scale,1,false)
        app.mousereleased(ox+gx*scale,oy+gy*scale,1,false)
    end
    for _,mobile in ipairs({false,true}) do
        local suffix=mobile and "mobile" or "desktop"
        app.mobileCamera=Camera.new({enabled=mobile,
            followOffsetY=-context.config.characterRendering.referenceHeight*context.config.player.drawScale/2})
        camera=app.mobileCamera
        app.settings=Settings.normalize(savedSettings);app.settings.followPlayerCamera=true
        state.screen,state.activeSlot="world",nil
        localPlayer.x,localPlayer.y,localPlayer.id=410,230,3
        app.draw()
        before=camera.zoom;app.wheelmoved(0,3);app.draw()
        x,y=camera:worldToScreen(localPlayer.x,localPlayer.y+camera.followOffsetY)
        check("camera_follow_real_app_zoom_centers_local_player_"..suffix,
            camera.followTarget==localPlayer and camera.zoom>before and near(x,480) and near(y,339))
        local clock=context.config.interactables.shopClock
        local cx,cy=camera:worldToScreen(clock.wallX,clock.wallY)
        worldZoom=camera.zoom
        click(cx,cy)
        check("camera_follow_real_app_world_tap_uses_inverse_transform_"..suffix,state.screen=="shop_clock")
        app.draw()
        check("camera_follow_real_app_clock_does_not_follow_"..suffix,
            not camera.followTarget and (not mobile or near(camera.zoom,1)))
        app.keypressed("escape");app.draw()
        localPlayer.x,localPlayer.y=760,570;app.draw()
        x,y=camera:worldToScreen(localPlayer.x,localPlayer.y+camera.followOffsetY)
        check("camera_follow_real_app_rejoins_after_menu_and_movement_"..suffix,
            state.screen=="world" and near(camera.zoom,worldZoom) and near(x,480) and near(y,339),
            state.screen.." zoom "..camera.zoom.." expected "..worldZoom.." center "..x..","..y)
        app.keypressed("o");app.draw();click(190,114);click(515,327)
        check("camera_follow_real_options_toggle_persists_locally_"..suffix,
            state.screen=="options" and not app.settings.followPlayerCamera
            and not Settings.load().followPlayerCamera and state.activeSlot==nil)
        app.keypressed("o");app.draw()
        check("camera_follow_real_options_off_releases_target_"..suffix,not camera.followTarget)
        app.keypressed("o");app.draw();click(515,327)
        check("camera_follow_real_options_on_survives_reload_"..suffix,
            app.settings.followPlayerCamera and Settings.load().followPlayerCamera)
        app.keypressed("o");app.draw()
    end
    state.screen,state.activeSlot,state.optionsReturnScreen=savedScreen,savedSlot,savedReturn
    localPlayer.x,localPlayer.y,localPlayer.id=savedX,savedY,savedId
    app.settings,app.mobileCamera=savedSettings,savedCamera
    for _,key in ipairs(optionFields) do Options[key]=savedOptions[key] end
    Settings.save(savedPrefs)
end
return Test
