local C=require('src.commute.runtime')
local Test={}

function Test.run(context,check)
    local R=assert(context.appRuntime)
    R.Save.delete(3)
    assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden',townSeed=712345})),'smoke'))
    R.state.screen='world'
    local Calendar=require('src.business_calendar')
    R.state.calendar=Calendar.dateFromHours(44)
    R.state.calendar.elapsed=44%24/24*Calendar.secondsPerDay(R.state)
    local weekend=R.state.home.weekend
    weekend.phase='ready';weekend.closedAtHours=44
    R.World.truck.state='absent'
    local target=require('src.home_travel').target(R.World.player,R.state)
    R.World.player.x,R.World.player.y=target.x,target.y
    local Weekend=require('src.weekend_runtime')
    assert(Weekend.command(R,R.World.player,'request'))
    assert(Weekend.command(R,R.World.player,'depart:'..weekend.travelToken))
    require('src.commute.tests.loading_test_support').wait(R,check,'truck_render_runtime')
    local trip=C.localTrip(R);local part=C.localPart(R);local truck=trip.keiTruck
    part.rider.ped.x,part.rider.ped.z=truck.x,truck.z
    assert(C.command(R,R.World.player,'truck:'..trip.token))
    local camera=R._commute.camera
    camera:setFirstPerson(true,truck)
    local g=love.graphics;local originalDimensions=g.getDimensions
    local canvas=g.newCanvas(1200,540,{dpiscale=1})
    local stack=g.getStackDepth()
    local okay,err=xpcall(function()
        g.getDimensions=function()return 1200,540 end
        R.App.update(0)
        check('kei_live_cab_expands_scene_to_phone_aspect',camera.firstPerson and camera.localVehicle=='truck'
            and R._commute.renderer.viewportWidth>1900)
        g.push('all');g.setCanvas({canvas,stencil=true});g.origin();g.clear(0,0,0,0)
        local fullScreen=require('src.viewport').fullScreenDevice()
        local insideWidth,insideHeight=R._commute.renderer.viewportWidth,R._commute.renderer.viewportHeight
        require('src.viewport').beginDraw(R.Config.baseWidth,R.Config.baseHeight,not fullScreen,R.App.officeUsesSafeArea())
        C.draw(R)
        require('src.viewport').endDraw();g.pop()
        local data=canvas:newImageData()
        local _,_,_,left=data:getPixel(1,270)
        local _,_,_,right=data:getPixel(1198,270)
        check('kei_live_cab_draw_covers_phone_edges',left>.99 and right>.99)
        if os.getenv('PICTURE_SHOP_CAB_AUDIT_IMAGES')=='1' then
            local png=data:encode('png');local file=assert(io.open('output/kei-cab-live.png','wb'))
            file:write(png:getString());file:close();png:release()
        end
        data:release()
        camera:setFirstPerson(false,truck)
        R.App.update(0)
        check('kei_exiting_cab_restores_outside_canvas',not camera.firstPerson
            and R._commute.renderer.viewportWidth==(fullScreen and insideWidth or 1280)
            and R._commute.renderer.viewportHeight==(fullScreen and insideHeight or 880))
    end,debug.traceback)
    while g.getStackDepth()>stack do g.pop() end
    g.getDimensions=originalDimensions;canvas:release()
    C.release(R);R.state.screen='title'
    assert(okay,err)
end
return Test
