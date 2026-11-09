local CabViewport=require('src.commute.cab_viewport')
local Viewport=require('src.viewport')
local MobileCamera=require('src.mobile_camera')
local FP=require('src.commute.first_person_camera')
local View=require('src.commute.first_person_renderer')
local Cockpit=require('src.commute.truck_cockpit')
local Test={}
local function near(a,b)return math.abs(a-b)<.001 end

function Test.run(check)
    local g=love.graphics
    local dimensions=g.getDimensions
    local safeArea=love.window.getSafeArea
    local platform=love.system.getOS
    local stackDepth=g.getStackDepth()
    local cab=Cockpit.new()
    local world={supportHeight=function()return 0 end}
    local camera={firstPerson=true,localVehicle='truck',centerX=0,centerZ=0,eyeHeight=1.91,
        viewHeading=0,bikeHeading=0,viewPitch=0,roll=0,focal=640/math.tan(math.rad(41)),screen=FP.screen}
    local truck={x=0,z=0,h=0,heading=0,engine=true}
    local okay,err=xpcall(function()
        for _,size in ipairs({{960,678},{960,540},{1200,540},{540,960},{1200,540,true}}) do
            local w,h=unpack(size)
            local safe=size[3]
            local name=w..'x'..h..(safe and '_safe_area' or '')
            g.getDimensions=function()return w,h end
            love.window.getSafeArea=function()return 40,0,w-60,h end
            local eye,layout=CabViewport.forRuntime({Config={baseWidth=960,baseHeight=678},
                App={officeUsesSafeArea=function()return safe end}},camera)
            local renderer={viewportWidth=layout.width,viewportHeight=layout.height,
                effectiveRadius=60,world=world,visible={},roadMeshes={},visibleProps={},plantMotion={},
                structures={drawFirstPerson=function()end}}
            local scene=View.new(renderer)
            renderer.shader=function()return scene.shader end
            local canvas=g.newCanvas(w,h,{dpiscale=1})
            local before=Cockpit.controls(1280,880,camera,truck)
            local sx,sy=FP.screen(eye,10,0,camera.eyeHeight)
            check('cab_viewport_preserves_optical_center_'..name,
                near(sx+layout.x,640) and near(sy+layout.y,440)
                and camera.viewportWidth==nil and camera.viewCenterX==nil)
            g.push('all');g.setCanvas(canvas);g.origin();g.clear(0,0,0,0)
            local fullScreen=Viewport.fullScreenDevice()
            Viewport.beginDraw(960,678,not fullScreen,safe)
            local sceneScale=fullScreen and 678/880 or .75
            g.translate((960-1280*sceneScale)*.5,(678-880*sceneScale)*.5);g.scale(sceneScale)
            g.push();g.translate(layout.x,layout.y)
            scene:draw(renderer,eye,truck,{})
            g.pop()
            g.push('all');g.setCanvas()
            local background=canvas:newImageData()
            g.pop()
            local edges=true
            for _,x in ipairs({1,w-2}) do
                for _,y in ipairs({1,math.floor(h/2),h-2}) do
                    local r,green,b,a=background:getPixel(x,y)
                    edges=edges and a>.99 and r>.2 and green>.2 and b>.2
                end
            end
            check('cab_world_fills_both_display_edges_'..name,edges)
            background:release()
            if name=='960x678' then
                local Art=require('src.commute.truck_art')
                local shoulder=setmetatable({includeLocalRider=true,shoulderPerspective=true},{__index=eye})
                local seenFrame,seenHeading,seenKind
                renderer.truckArt={firstPersonOcclusionTop=function()return 0 end,
                    drawSignals=function()end,draw=function(_,actor,proxy)
                        seenFrame=Art.frame(proxy,actor.heading,actor.model)
                        seenHeading=proxy.viewHeading;seenKind=Art.viewKind(proxy)
                    end}
                for _,model in ipairs({'box','kei'}) do
                    local subject={x=10,z=10,h=0,heading=0,model=model}
                    scene:draw(renderer,shoulder,subject,{{actor=subject,truck=true,localPlayer=true}})
                    check('truck_shoulder_render_uses_actual_eye_bearing_'..model,
                        near(seenHeading,math.pi/4) and seenKind=='chase'
                        and seenFrame==(model=='kei' and 53 or 57))
                end
            end
            cab:draw(truck,1280,880,camera)
            Viewport.endDraw();g.pop()
            local after=Cockpit.controls(1280,880,camera,truck)
            check('cab_full_width_scene_keeps_switch_hit_targets_'..name,
                #before==#after and near(before[1].x,after[1].x) and near(before[1].y,after[1].y))
            if os.getenv('PICTURE_SHOP_CAB_AUDIT_IMAGES')=='1' then
                local data=canvas:newImageData()
                local png=data:encode('png')
                local file=assert(io.open('output/kei-cab-'..name..'.png','wb'))
                file:write(png:getString());file:close();png:release();data:release()
            end
            canvas:release();scene:release()
        end
        love.system.getOS=function()return 'Android' end
        g.getDimensions=function()return 2400,1080 end
        local ox,oy,scale,sx,sy=Viewport.transform(960,678,false)
        local bounds=Viewport.gameBounds(960,678,false)
        check('android_viewport_keeps_square_pixels_and_full_height',near(sx,sy)
            and near(scale,sx) and near(oy,0) and ox>0 and near(bounds.height,678))
        check('android_wide_edges_map_to_extra_world_space',bounds.left<0 and bounds.right>960
            and near(Viewport.toGame(0,540,960,678,false),bounds.left))
        local camera=MobileCamera.new({enabled=true,baseWidth=960,baseHeight=678})
        camera:setViewport(bounds.width,bounds.height,true)
        camera:selectView('world',true)
        check('android_world_camera_fills_width_without_stretch',near(camera.zoom,bounds.width/960)
            and near(camera:screenToWorld(bounds.left,339),0)
            and near(camera:screenToWorld(bounds.right,339),960))
        camera:zoomBy(1/camera.zoom)
        check('android_world_can_zoom_out',near(camera.zoom,1))
        camera:zoomBy(bounds.width/960)
        camera:setFollowTarget({x=20,y=339})
        camera:update(.1)
        check('android_world_follow_stays_within_scene_art',near(camera.centerX,480))
        local ride,wide=CabViewport.forRuntime({Config={baseWidth=960,baseHeight=678},
            App={officeUsesSafeArea=function()return false end}},
            {firstPerson=false,viewCenterX=640,viewCenterY=440})
        check('android_ride_extends_scenery_to_both_edges',wide.width>1280
            and near(ride.viewCenterX+wide.x,640)
            and near(ride.viewCenterY+wide.y,440))
    end,debug.traceback)
    while g.getStackDepth()>stackDepth do g.pop() end
    g.getDimensions=dimensions;love.window.getSafeArea=safeArea
    love.system.getOS=platform;cab:release()
    assert(okay,err)
end
return Test
