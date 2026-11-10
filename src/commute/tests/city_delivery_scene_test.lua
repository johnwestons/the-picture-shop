local Test={}
function Test.run(check)
    local Scene=require('src.commute.city_delivery_scene')
    local Art=require('src.commute.truck_art')
    local g=love.graphics
    local run={cutsceneStartedAtEpoch=100,cutsceneEndsAtEpoch=105,stopIndex=1,
        stops={{city='Millhaven City'}},vehicleModel='box'}
    Scene.release()
    check('city_scene_starts_at_departure',Scene.elapsed(run,50,100)==0)
    check('city_scene_moves_between_epoch_ticks',math.abs(Scene.elapsed(run,50.35,100)-.35)<.001)
    local copy={cutsceneStartedAtEpoch=100,cutsceneEndsAtEpoch=105}
    check('city_scene_network_snapshot_keeps_camera_time',math.abs(Scene.elapsed(copy,50.7,100)-.7)<.001)
    Scene.release()
    check('city_scene_resumes_saved_journey',Scene.elapsed(run,80,102)==2)
    check('city_scene_respects_return_deadline',Scene.shot(run,Scene.elapsed(run,80.1,105)).waiting)
    local waiting=Scene.shot(run,8)
    check('city_scene_waiting_vehicle_stays_stopped',waiting.travel==Scene.shot(run,20).travel
        and waiting.remaining==0 and waiting.progress==1)
    local art=Art.new()
    local original=art.drawSprite
    local observed
    art.drawSprite=function(self,vehicle,kind,angle,...)
        observed={vehicle=vehicle,kind=kind,angle=angle}
        return original(self,vehicle,kind,angle,...)
    end
    local box={model='box',livery='picture_shop',company='The Picture Shop'}
    local kei={model='kei'}
    local images={}
    local directory=os.getenv('PICTURE_SHOP_CITY_DELIVERY_CAPTURE')
    local function render(name,w,h,vehicle,time)
        local canvas=require('src.tests.support.pixel_canvas')(w,h)
        local stack=g.getStackDepth()
        g.push('all');g.setCanvas(canvas);g.origin();g.clear(0,0,0,0)
        local okay,err=xpcall(function()Scene.draw(w,h,run,vehicle,art,time)end,debug.traceback)
        g.pop()
        assert(okay,err)
        check('city_scene_balances_graphics_'..name,g.getStackDepth()==stack)
        local data=canvas:newImageData()
        local _,_,_,left=data:getPixel(0,math.floor(h*.5))
        local _,_,_,right=data:getPixel(w-1,math.floor(h*.5))
        check('city_scene_fills_viewport_'..name,left>.99 and right>.99)
        if directory then
            local png=data:encode('png')
            local file=assert(io.open(directory..'/'..name..'.png','wb'))
            file:write(png:getString());file:close();png:release()
        end
        canvas:release();return data
    end
    images.box=render('box-bridge',960,678,box,.9)
    check('city_scene_preserves_actual_truck_and_livery',observed.vehicle==box and observed.kind=='chase')
    local outward=observed.angle
    images.kei=render('kei-bridge',960,678,kei,.9)
    check('city_scene_mounted_kei_overrides_box_manifest',observed.vehicle==kei)
    images.dock=render('box-dock',960,678,box,2.8)
    images.back=render('box-return',960,678,box,4.5)
    check('city_scene_uses_opposite_direction_on_return',math.cos(observed.angle-outward)<-.99)
    images.keiBack=render('kei-return',960,678,kei,4.5)
    images.wide=render('kei-wide',1600,720,kei,2.8)
    images.small=render('box-small',720,509,box,.9)
    images.wait=render('return-wait',960,678,box,8)
    local different=0
    for y=270,540,3 do for x=200,760,3 do
        local a,b,c=images.box:getPixel(x,y)
        local d,e,f=images.kei:getPixel(x,y)
        if math.abs(a-d)+math.abs(b-e)+math.abs(c-f)>.15 then different=different+1 end
    end end
    check('city_scene_models_render_distinct_real_sprites',different>1000)
    check('city_scene_drawing_preserves_delivery_state',run.cutsceneEndsAtEpoch==105 and run.stopIndex==1
        and box.model=='box' and kei.model=='kei')
    -- Exercise the real commute entry point with both trucks available. The
    -- mounted vehicle wins even if the manifest still names the box truck.
    local Truck=require('src.commute.delivery_truck')
    local mountedBox=Truck.new(0,0,0,'picture_shop','box')
    local mountedKei=Truck.new(0,0,0,'picture_shop','kei')
    local part={rider={vehicle='truck'}}
    local trip={truck=mountedBox,keiTruck=mountedKei,deliveryRun=run,
        deliveryVehicleModel='box',participants={owner=part}}
    local runtime={state={home={commute=trip}},World={player={id=1,homeResidentId='owner'}},
        Config={baseWidth=960,baseHeight=678},_commute={renderer={truckArt=art}}}
    run.status='offmap'
    local canvas=require('src.tests.support.pixel_canvas')(960,678)
    for _,vehicle in ipairs({mountedBox,mountedKei}) do
        part.rider.truck=vehicle
        g.push('all');g.setCanvas(canvas);g.origin()
        local okay,err=xpcall(function()require('src.commute.runtime').draw(runtime)end,debug.traceback)
        g.pop();assert(okay,err)
        check('city_scene_runtime_uses_mounted_'..vehicle.model,observed.vehicle==vehicle)
    end
    canvas:release()
    for _,data in pairs(images) do data:release() end
    art:release();Scene.release()
end
return Test
