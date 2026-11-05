local Test={}
function Test.run(context,check)
    local R=assert(context.appRuntime)
    local C=require('src.commute.runtime')
    local Residents=require('src.home_residents')
    local Weekend=require('src.weekend_runtime')
    local Trip=require('src.commute.trip')
    assert(R.startGame(assert(R.Save.newGame(3,{townSeed=712345})),'smoke'))
    local hp=R.World.player;hp.id=1
    local guests={}
    for i=2,3 do
        local p={id=i,x=300,y=335,sceneId='warehouse',character=hp.character,velocityX=0,velocityY=0,
            facing=1,intentX=0,intentY=1,animationDistance=0,moving=false,lastInputAt=R.multiplayer.clock()}
        assert(Residents.bind(R.state,p,string.rep(tostring(i),64),guests));guests[#guests+1]=p
    end
    local session=R.multiplayer
    local old={remotePlayers=session.remotePlayers,isActive=session.isActive,isHost=session.isHost,
        update=session.update,save=R.saveCurrent,movement=R.Input.movement}
    local function restore()
        for _,key in ipairs({'remotePlayers','isActive','isHost','update'}) do session[key]=old[key] end
        R.saveCurrent=old.save;R.Input.movement=old.movement
        C.release(R)
    end
    local okay,why=xpcall(function()
        session.remotePlayers=function()return guests end
        session.isActive=function()return true end;session.isHost=function()return true end
        R.saveCurrent=function()return true end;R.Input.movement=function()return 0,0 end
        session.update=function(_,dt,ctx)
            for _,p in ipairs(guests) do ctx.moveRemote(p,dt,p.inputX or 0,p.inputY or 0) end
        end
        local outside=guests[2]
        local exit=require('src.home_travel').target(outside,R.state)
        outside.x,outside.y=exit.x,exit.y
        R.state.screen='computer'
        local lease={leaseId='host-menu-lease'};R.localWorkshopLease=lease
        assert(Weekend.command(R,outside,'explore'))
        check('independent_runtime_guest_preserves_host_menu_lease',R.state.screen=='computer'
            and R.localWorkshopLease==lease and hp.sceneId=='warehouse')
        R.localWorkshopLease=nil
        local indoor=guests[1];local x=indoor.x;indoor.inputX=1
        local part=R.state.home.commute.participants[Residents.key(outside)]
        local outdoorX,outdoorZ=part.rider.ped.x,part.rider.ped.z
        outside.inputX=1
        R.state.employment.recruiting=false;R.World.customer.timer=10000;R.World.vendor.timer=10000
        local time=require('src.business_calendar').absoluteHours(R.state)
        for _=1,6 do outside.lastInputAt=session.clock();R.App.update(.05) end
        check('independent_runtime_routes_remote_movement_by_player',indoor.x>x
            and math.abs(part.rider.ped.x-outdoorX)+math.abs(part.rider.ped.z-outdoorZ)>.01)
        check('independent_runtime_clock_and_indoor_host_continue',require('src.business_calendar').absoluteHours(R.state)>time
            and R.state.screen=='computer' and not R._commute.renderer)
        indoor.inputX=0;outside.inputX=0
        exit=require('src.home_travel').target(hp,R.state);hp.x,hp.y=exit.x,exit.y
        assert(Weekend.command(R,hp,'explore'))
        -- An outdoor host still services the indoor player's real collision controller.
        x=indoor.x;indoor.inputX=1;R.App.update(.05);indoor.inputX=0
        check('independent_runtime_outdoor_host_keeps_indoor_guest_moving',indoor.x>x and hp.sceneId=='commute')
        local token=R.state.home.commute.token
        local owner=R.state.home.commute.participants.owner
        local site=C.world(R).sites.byId.warehouse
        owner.rider.ped.x,owner.rider.ped.z,owner.rider.ped.speed=site.door.x,site.door.z,0
        assert(C.command(R,hp,'cancel:'..token))
        check('independent_runtime_host_returns_alone_and_keeps_remote_world',hp.sceneId=='warehouse'
            and outside.sceneId=='commute' and R._commute.world and not R._commute.renderer)
        exit=require('src.home_travel').target(hp,R.state);hp.x,hp.y=exit.x,exit.y
        assert(Weekend.command(R,hp,'explore'))
        owner=R.state.home.commute.participants.owner
        local grocery=C.world(R).sites.byId.grocery
        owner.rider.ped.x,owner.rider.ped.z,owner.rider.ped.speed=grocery.door.x,grocery.door.z,0
        owner.rider.bike.x,owner.rider.bike.z=grocery.parking.x,grocery.parking.z
        assert(C.command(R,hp,'grocery:'..token));R.App.update(.05)
        check('independent_runtime_local_grocery_opens_without_outdoor_renderer',hp.sceneId=='grocery'
            and R._commute.mechanicOffer.interiorKind=='grocery' and not R._commute.renderer)
        x=hp.x;R.Input.movement=function()return 1,0 end
        for _=1,4 do R.App.update(.05) end
        R.Input.movement=function()return 0,0 end
        check('independent_runtime_grocery_controls_drive_authority',hp.x>x and hp.x==owner.interiorPose.x)
        local canvas=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
        for _=1,50 do
            R.App.update(.016)
            love.graphics.push('all');love.graphics.setCanvas(canvas);R.App.draw();love.graphics.pop()
            if R._commute.mechanicOffer.interior.ready then break end
            love.timer.sleep(.01)
        end
        check('independent_runtime_grocery_renders_shared_scene',R._commute.mechanicOffer.interior.ready)
        local data=canvas:newImageData();local encoded=data:encode('png')
        local output=assert(io.open('output/independent-scenes-grocery.png','wb'));output:write(encoded:getString());output:close()
        encoded:release();data:release();canvas:release()
        assert(R.Save.save(3,R.state,R.World.snapshot()))
        local grocerySave=assert(R.Save.load(3))
        check('independent_runtime_grocery_disk_save_keeps_scene',grocerySave.player.sceneId=='grocery'
            and grocerySave.state.home.commute.participants.owner.interior=='grocery')
        assert(C.command(R,hp,'exitgrocery:'..token));R.App.update(.05)
        check('independent_runtime_grocery_exit_closes_local_view',hp.sceneId=='commute'
            and not R._commute.mechanicOffer)
        local a=Trip.parking(C.world(R),'warehouse',1)
        owner.rider.bike.x,owner.rider.bike.z=a.x,a.z
        owner.rider.ped.x,owner.rider.ped.z,owner.rider.ped.speed=site.door.x,site.door.z,0
        assert(C.command(R,hp,'cancel:'..token))
        -- Reload the actual host save while the guest remains outside.
        assert(R.Save.save(3,R.state,R.World.snapshot()))
        local payload=assert(R.Save.load(3))
        check('independent_runtime_disk_preserves_indoor_host_and_remote_trip',payload.player.sceneId==nil
            or payload.player.sceneId=='warehouse')
        assert(R.startGame(payload,'smoke'))
        check('independent_runtime_reload_does_not_follow_remote_guest',R.World.player.sceneId=='warehouse'
            and R.state.home.commute.participants[Residents.key(outside)]~=nil)
        check('independent_runtime_reload_retains_shared_truck',Trip.valid(R.state.home.commute,R.state.home))
    end,debug.traceback)
    restore();assert(okay,why)
end
return Test
