-- Crash into the actual seeded mechanic shop, recover, ride into its parking
-- area, reload the damaged bike and authorize a repair at the service counter.
local Bike = require('src.commute.motorcycle')
local Bindings = require('src.commute.bindings')
local Calendar = require('src.business_calendar')
local Commute = require('src.commute.runtime')
local Loader = require('src.image_loader')
local Loading = require('src.commute.tests.loading_test_support')
local Residents = require('src.home_residents')
local Schema = require('src.save_schema')
local Shop = require('src.commute.mechanic_shop')
local Town = require('src.commute.town')
local Trip = require('src.commute.trip')
local Test = {}

local function distance(x,z,otherX,otherZ)
    return math.sqrt((x-otherX)^2+(z-otherZ)^2)
end

-- Project a desired walking direction onto the current game camera, just as
-- keyboard/joystick movement does. The live App still applies gait and solids.
local function walkTo(R, targetX, targetZ, stopDistance)
    local ped = Commute.localPart(R).rider.ped
    R.Input.movement = function()
        local dx,dz = targetX-ped.x,targetZ-ped.z
        local length = math.sqrt(dx*dx+dz*dz)
        if length < stopDistance then return 0,0 end
        local camera = R._commute.camera
        local rx,rz = camera:screenVectorToWorld(1,0)
        local vx,vz = camera:screenVectorToWorld(0,1)
        return (dx*rx+dz*rz)/length,(dx*vx+dz*vz)/length
    end
    for _=1,450 do
        R.App.update(1/60)
        if distance(ped.x,ped.z,targetX,targetZ) <= stopDistance then break end
    end
    R.Input.movement = function() return 0,0 end
    for _=1,20 do R.App.update(1/60) end
    assert(distance(ped.x,ped.z,targetX,targetZ) < stopDistance+.1, 'Could not reach bike or service door on foot')
end

local function frame(R, canvas, name)
    local g=love.graphics
    g.push('all');g.setCanvas({canvas,stencil=true})
    local okay,reason=xpcall(R.App.draw,debug.traceback)
    g.pop();assert(okay,reason)
    local folder=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE')
    if name and folder then
        local pixels=canvas:newImageData()
        local encoded=pixels:encode('png')
        local file=assert(io.open(folder..'/'..name..'.png','wb'))
        file:write(encoded:getString());file:close()
        encoded:release();pixels:release()
    end
end

local function tap(R, rect)
    local x=(rect.x+rect.w/2)*R.Config.baseWidth/960
    local y=(rect.y+rect.h/2)*R.Config.baseHeight/678
    local ox,oy,scale=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,R.App.officeFitsScreen())
    local consumed=R.App.touchpressed('bike-damage-service',ox+x*scale,oy+y*scale)
    R.App.touchreleased('bike-damage-service',ox+x*scale,oy+y*scale)
    assert(consumed,'Service counter did not consume touch')
end

local function checkNextTrip(saved, world, check, damage)
    -- Fork the disk state at the repair counter to verify ending a damaged
    -- outing and starting another one, independently of the paid repair path.
    local state=Schema.copy(saved.state)
    local owner={id=1,sceneId='commute',homeResidentId='owner'}
    state.home.commute=assert(Trip.restore(state.home.commute,world))
    local previous=state.home.commute
    local rider=previous.participants.owner.rider
    local parking=assert(Trip.parking(world,previous.origin,1))
    local door=world.sites.byId[previous.origin].door
    rider.bike.x,rider.bike.z=parking.x,parking.z
    rider.ped.x,rider.ped.z=door.x,door.z
    assert(Trip.cancel(state,owner,previous.token,world))
    state.home.weekend.travelToken=previous.token+1
    state.home.weekend.readyMask=1
    assert(Trip.start(state,{owner},previous.token+1,world))
    check('bike_damage_runtime_next_trip_keeps_unrepaired_damage',
        state.home.commute.participants.owner.rider.bike.damage==damage and state.home.residents.owner.ridingDamage==damage)
end

function Test.run(context, check)
    local R=assert(context.appRuntime)
    local oldMovement,oldDrive,oldProfile=R.Input.movement,Bindings.drive,R.App.settings.motorcycleControls
    local oldWidth,oldHeight=R.Config.baseWidth,R.Config.baseHeight
    local oldLoader=Loader.enabled
    local canvas=love.graphics.newCanvas(960,678)
    local okay,reason=xpcall(function()
        R.Save.delete(3)
        local town=assert(Town.generate(712345))
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden',town=town})),'smoke'))
        R.Config.baseWidth,R.Config.baseHeight=960,678
        R.App.settings.motorcycleControls=Bindings.defaults()
        R.Input.movement=function() return 0,0 end
        local drive=0
        Bindings.drive=function() return 0,drive,false end
        R.state.screen='world'
        R.state.calendar=Calendar.dateFromHours(44)
        R.state.calendar.elapsed=44%24/24*Calendar.secondsPerDay(R.state)
        local week=R.state.home.weekend
        week.phase='ready';week.closedAtHours=44;week.travelToken=207;week.readyMask=1
        local world=Commute.world(R)
        local home=R.state.home
        home.balanceCents=30000;home.residents.owner.ridingUpgradeLevel=3
        local guest={id=2}
        local guestId=assert(Residents.bind(R.state,guest,string.rep('d',64),{R.World.player}))
        home.residents[guestId].ridingDamage=17
        assert(Trip.start(R.state,{R.World.player},207,world))
        R._weekendPromptToken=207;R._weekendScene='commute'
        local part=Commute.localPart(R)
        local rider=part.rider
        local bike=rider.bike
        local shop=world.sites.byId.mechanic
        rider.gear={version=1,outfit='geared',mounted=true,engine=true,revision=1}
        -- Five meters to the side of the door, facing the actual facade.
        bike.x=shop.door.x+shop.front.x*2.7+shop.cos*5
        bike.z=shop.door.z+shop.front.z*2.7+shop.sin*5
        bike.heading=math.atan2(-shop.front.z,-shop.front.x)
        rider.ped.x,rider.ped.z=bike.x,bike.z
        Bike.resetContact(bike,world)
        Commute.syncPlayer(R.World.player,part)
        Loading.wait(R,check,'bike_damage_runtime')
        local camera=R._commute.camera
        camera.zoom,camera.targetZoom=2,2
        camera.tilt=42;camera.yaw=(-bike.heading*180/math.pi-90)%360;camera.fixedYaw=camera.yaw
        bike.speed=22;Bike.resetHorizontal(bike)
        for _=1,30 do
            R.App.update(1/60)
            if rider.ped.crash then break end
        end
        assert(rider.ped.crash,'Severe impact did not eject the rider from the motorcycle')
        local damage=bike.damage
        check('bike_damage_runtime_real_wall_crash_dismounts_and_persists_to_owner',
            bike.collisionKind=='barrier' and damage>0 and damage<=24 and home.residents.owner.ridingDamage==damage
            and not rider.gear.mounted and not rider.gear.engine and bike.speed==0)
        local publicTrip=Trip.snapshot(home.commute)
        local publicRider=publicTrip.participants.owner
        check('bike_damage_crash_snapshot_shows_fall_and_survives_midair_save',
            Trip.valid(publicTrip,home) and publicRider.presentation.pose=='crash'
            and not publicRider.rider.gear.mounted and publicRider.rider.bike.damage==damage
            and assert(Trip.restore(publicTrip,world)).participants.owner.rider.bike.damage==damage)
        publicRider.rider.bike.damage=damage-1
        check('bike_damage_rejects_inconsistent_shared_bike_condition',not Trip.valid(publicTrip,home))
        R.dispatchKeyPressed('e')
        check('bike_damage_runtime_rider_cannot_remount_during_fall',not rider.gear.transition and not rider.gear.mounted)
        for _=1,15 do R.App.update(1/60) end
        frame(R,canvas,'damage-rider-fall')
        for _=1,95 do R.App.update(1/60) end
        check('bike_damage_runtime_rider_lands_away_from_bike',
            not rider.ped.crash and distance(rider.ped.x,rider.ped.z,bike.x,bike.z)>2)
        walkTo(R,bike.x,bike.z,1.5)
        R.dispatchKeyPressed('e')
        assert(rider.gear.transition and rider.gear.transition.kind=='mount','Could not begin ordinary remount after crash')
        for _=1,120 do R.App.update(1/60) end
        check('bike_damage_runtime_normal_remount_starts_damaged_motorcycle',rider.gear.mounted and rider.gear.engine and bike.damage==damage)
        local initialX,initialZ=bike.x,bike.z
        drive=1
        for _=1,420 do
            R.App.update(1/60)
            if distance(bike.x,bike.z,initialX,initialZ)>2.8 then break end
        end
        drive=-1
        for _=1,90 do
            R.App.update(1/120)
            if bike.speed<.05 then break end
        end
        drive=0
        check('bike_damage_runtime_crashed_bike_can_back_into_mechanic_parking',distance(bike.x,bike.z,initialX,initialZ)>2.8 and bike.speed<.05)
        R.dispatchKeyPressed('e')
        for _=1,120 do R.App.update(1/60) end
        assert(not rider.gear.mounted,'Could not dismount to visit mechanic')
        walkTo(R,shop.door.x,shop.door.z,1)
        assert(R.saveCurrent(true))
        local saved=assert(R.Save.load(3))
        check('bike_damage_runtime_disk_keeps_crash_damage_on_both_records',
            saved.state.home.commute.participants.owner.rider.bike.damage==damage and saved.state.home.residents.owner.ridingDamage==damage)
        checkNextTrip(saved,world,check,damage)
        local legacy=Schema.copy(saved.state)
        for _,resident in pairs(legacy.home.residents) do
            resident.ridingDamage=nil;resident.ridingRepairRevision=nil
        end
        legacy.home.commute.participants.owner.rider.bike.damage=nil
        Residents.ensure(legacy)
        check('bike_damage_older_save_defaults_to_a_healthy_bike',Schema.validState(legacy)
            and legacy.home.residents.owner.ridingRepairRevision==0 and legacy.home.residents.owner.ridingDamage==0
            and assert(Trip.restore(legacy.home.commute,world)).participants.owner.rider.bike.damage==0)
        assert(R.startGame(saved,'smoke'))
        R.state.screen='world';R._weekendPromptToken=207;R._weekendScene='commute'
        Loading.wait(R,check,'bike_damage_runtime_reload')
        home=R.state.home;bike=Commute.localPart(R).rider.bike
        check('bike_damage_runtime_reload_preserves_damage_and_stopped_speed',bike.damage==damage and bike.speed==0)
        Loader.setEnabled(true)
        R.dispatchKeyPressed('e')
        local offer=assert(R._commute.mechanicOffer,'Mechanic shop did not open after reload')
        frame(R,canvas)
        local deadline=love.timer.getTime()+25
        while not offer.interior.ready and not offer.interior.error and love.timer.getTime()<deadline do
            R.App.update(1/60);love.timer.sleep(.001)
        end
        assert(offer.interior.ready,offer.interior.error or 'Mechanic artwork timeout')
        R.dispatchKeyPressed('c')
        local balance=home.balanceCents
        local quote=assert(Shop.repairQuote(R))
        check('bike_damage_runtime_mechanic_shows_current_condition_and_price',
            offer.page=='catalog' and offer.service=='repair' and quote.damage==damage
            and quote.condition==100-damage and quote.priceCents==damage*200)
        frame(R,canvas,'damage-repair-estimate')
        tap(R,Shop.layout().buy)
        check('bike_damage_runtime_review_does_not_charge',offer.page=='confirm' and balance==home.balanceCents and bike.damage==damage)
        tap(R,Shop.layout().buy)
        R.App.update(1/60)
        check('bike_damage_runtime_payment_repairs_only_owned_motorcycle',
            offer.page=='install' and offer.receipt.kind=='repair' and offer.receipt.costCents==quote.priceCents
            and home.balanceCents==balance-quote.priceCents and bike.damage==0 and home.residents.owner.ridingDamage==0
            and home.residents[guestId].ridingDamage==17 and bike.upgradeLevel==3)
        frame(R,canvas,'damage-mechanic-repair')
        for _=1,150 do R.App.update(1/60) end
        assert(offer.page=='receipt')
        frame(R,canvas,'damage-repair-receipt')
        R.dispatchKeyPressed('return');R.dispatchKeyPressed('escape')
        assert(not R._commute.mechanicOffer)
        assert(R.saveCurrent(true));saved=assert(R.Save.load(3))
        check('bike_damage_runtime_disk_keeps_repair_revision_cash_and_restored_condition',
            saved.state.home.residents.owner.ridingRepairRevision==1 and saved.state.home.residents.owner.ridingDamage==0
            and saved.state.home.commute.participants.owner.rider.bike.damage==0 and saved.state.home.balanceCents==balance-quote.priceCents)
        assert(R.returnToTitle())
    end,debug.traceback)
    canvas:release();Loader.setEnabled(oldLoader)
    R.Input.movement,Bindings.drive,R.App.settings.motorcycleControls=oldMovement,oldDrive,oldProfile
    R.Config.baseWidth,R.Config.baseHeight=oldWidth,oldHeight
    if not okay then Commute.release(R);error(reason,0) end
end
return Test
