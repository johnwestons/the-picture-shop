local C=require('src.commute.runtime')
local Trip=require('src.commute.trip')
local Town=require('src.commute.town')
local Calendar=require('src.business_calendar')
local Bindings=require('src.commute.bindings')
local Schema=require('src.save_schema')
local Test={}
function Test.run(context,check)
    local R=assert(context.appRuntime)
    local oldMovement,oldDrive=R.Input.movement,Bindings.drive
    local canvas=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
    local okay,reason=xpcall(function()
        assert(R.Save.delete(3))
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden',town=Town.legacy()})),'smoke'))
        R.state.screen='world';R.state.employment.recruiting=false
        R.Input.movement=function()return 0,0 end;Bindings.drive=function()return 0,0,false end
        R.state.calendar=Calendar.dateFromHours(10);R.state.calendar.secondsPerDay=3600
        R.state.calendar.elapsed=10/24*3600
        local week=R.state.home.weekend;week.phase='working';week.travelToken=77
        week.travelPurpose='outing';week.travelOrigin='warehouse';week.readyMask=1
        local world=C.world(R);assert(Trip.start(R.state,{R.World.player},77,world))
        R._weekendPromptToken=77;R._weekendScene='commute'
        local part=C.localPart(R);local rider=part.rider
        rider.gear.outfit='geared';rider.gear.mounted=true;rider.gear.engine=true;rider.gear.transition=nil
        rider.bike.x,rider.bike.z,rider.bike.heading=140,270,0
        rider.bike.speed,rider.bike.vy,rider.bike.grounded,rider.bike.upgradeLevel=26.8,0,true,3
        rider.bike.h=world:supportHeight(140,270)
        local movingSpeed=rider.bike.speed
        R.state.home.residents.owner.ridingUpgradeLevel=3
        R.state.home.residents.owner.ridingGear=Schema.copy(rider.gear)
        C.syncPlayer(R.World.player,part)
        assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
        assert(R.startGame(saved,'smoke'));R.state.screen='world'
        local bike=C.localPart(R).rider.bike
        check('loading_runtime_save_recovery_stops_moving_bike_before_reveal',movingSpeed==26.8 and bike.speed==0 and bike.vy==0)
        local before={x=bike.x,z=bike.z,h=bike.h,heading=bike.heading,speed=bike.speed,vy=bike.vy}
        local clock=Calendar.absoluteHours(R.state);local started=love.timer.getTime();local frames=0
        repeat
            R.App.update(1/60);frames=frames+1
            love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true});R.App.draw();love.graphics.pop()
            love.graphics.setColor(1,1,1);love.graphics.draw(canvas);love.graphics.present()
            assert(love.timer.getTime()-started<60,'Terrain load timed out')
        until R._commute.renderer and not R._commute.loading
        bike=C.localPart(R).rider.bike
        local after={x=bike.x,z=bike.z,h=bike.h,heading=bike.heading,speed=bike.speed,vy=bike.vy}
        local distance=math.sqrt((after.x-before.x)^2+(after.z-before.z)^2)
        local result={movingSpeedBeforeSave=movingSpeed,before=before,after=after,distance=distance,frames=frames,simulatedSeconds=frames/60,
            wallSeconds=love.timer.getTime()-started,calendarDeltaHours=Calendar.absoluteHours(R.state)-clock}
        local folder=assert(os.getenv('PICTURE_SHOP_LOADING_COAST_OUTPUT'))
        local file=assert(io.open(folder..'/measurements.json','wb'))
        file:write(require('tools.performance_probe.json')(result));file:close()
        check('loading_runtime_warehouse_clock_continues',result.calendarDeltaHours>0)
        check('loading_runtime_restored_pose_and_velocity_remain_exact',distance==0 and after.speed==before.speed
            and after.h==before.h and after.vy==before.vy and after.heading==before.heading,
            ('moved %.3fm; speed %.3f -> %.3f in %d loading frames'):format(distance,before.speed,after.speed,frames))
        -- Existing live-session rebind uses the same safe-stop contract and
        -- must leave every other rider's pose and velocity untouched.
        local Residents=require('src.home_residents')
        local guest={id=2,sceneId='warehouse',character='rabbit-worker'}
        local id=assert(Residents.bind(R.state,guest,string.rep('a',64),{R.World.player}))
        assert(C.bind(R,guest,{R.World.player,guest}))
        local remote=R.state.home.commute.participants[id].rider
        remote.gear.outfit='geared';remote.gear.mounted=true;remote.gear.engine=true;remote.gear.transition=nil
        remote.bike.x,remote.bike.z,remote.bike.heading=140,270,0
        remote.bike.h=C.world(R):supportHeight(140,270);remote.bike.speed=26.8;remote.bike.vy=2
        remote.ped.x,remote.ped.z=140,270
        bike.speed=9;local hostX,hostZ=bike.x,bike.z
        assert(C.bind(R,guest,{R.World.player,guest}))
        remote=R.state.home.commute.participants[id].rider
        check('loading_runtime_guest_rebind_stops_only_reconnected_rider',remote.bike.speed==0 and remote.bike.vy==0
            and remote.bike.x==140 and remote.bike.z==270 and remote.gear.mounted and remote.gear.engine
            and bike.x==hostX and bike.z==hostZ and bike.speed==9)
        Trip.update(R.state,R.World.player,{},1/60,C.world(R))
        check('loading_runtime_other_rider_simulation_can_continue',bike.x~=hostX or bike.z~=hostZ)
        bike.speed=0;R.state.activeSlot=nil
    end,debug.traceback)
    R.Input.movement,Bindings.drive=oldMovement,oldDrive;canvas:release()
    if not okay then error(reason,0)end
end
return Test
