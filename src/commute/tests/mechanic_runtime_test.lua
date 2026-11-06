-- Actual customer service flow in a private smoke save, with real async artwork.
local C=require('src.commute.runtime')
local Trip=require('src.commute.trip')
local Town=require('src.commute.town')
local Rider=require('src.commute.rider')
local Shop=require('src.commute.mechanic_shop')
local Interior=require('src.commute.mechanic_interior')
local Loader=require('src.image_loader')
local Schema=require('src.save_schema')
local Test={}
function Test.run(context,check)
    local R=assert(context.appRuntime);local folder=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE')
    assert(C.enabled(),'Mechanic runtime fixture requires commute enabled')
    local oldWidth,oldHeight=R.Config.baseWidth,R.Config.baseHeight
    local oldLoader,oldMovement=Loader.enabled,R.Input.movement
    local canvas=love.graphics.newCanvas(960,678)
    local function render()
        love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear(0,0,0,1);C.draw(R);love.graphics.pop()
    end
    local function tick(dt)R.App.update(dt or 1/60);render();love.timer.sleep(.001)end
    local function waitFor(predicate,seconds,label)
        local deadline=love.timer.getTime()+seconds
        while not predicate()and love.timer.getTime()<deadline do tick()end
        assert(predicate(),label)
    end
    local function capture(name,width,height)
        if not folder then return end
        local beforeW,beforeH=R.Config.baseWidth,R.Config.baseHeight
        R.Config.baseWidth,R.Config.baseHeight=width or 960,height or 678
        local target=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
        love.graphics.push('all');love.graphics.setCanvas(target);love.graphics.clear(0,0,0,1);C.draw(R);love.graphics.pop()
        local data=target:newImageData();local bytes=data:encode('png');local file=assert(io.open(folder..'/'..name..'.png','wb'))
        file:write(bytes:getString());file:close();bytes:release();data:release();target:release()
        R.Config.baseWidth,R.Config.baseHeight=beforeW,beforeH
    end
    local okay,reason=xpcall(function()
        R.Save.delete(3)
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden',town=assert(Town.generate(712345))})),'smoke'))
        R.state.screen='world';R.Config.baseWidth,R.Config.baseHeight=960,678
        R.Input.movement=function()return 0,0 end
        local week=R.state.home.weekend;week.phase='ready';week.closedAtHours=44;week.travelToken=77;week.readyMask=1
        local world=C.world(R)
        assert(Trip.start(R.state,{R.World.player},77,world))
        -- This focused fixture begins after the travel confirmation was accepted.
        R._weekendPromptToken=77;R._weekendScene='commute'
        local part=C.localPart(R);local rider=part.rider;local site=world.sites.byId.mechanic
        local anchor=assert(Trip.parking(world,'mechanic',1))
        rider.gear.outfit='geared';rider.gear.mounted=false;rider.gear.engine=false;rider.gear.transition=nil
        rider.bike.x,rider.bike.z,rider.bike.heading=anchor.x,anchor.z,anchor.heading
        rider.bike.speed,rider.bike.vy,rider.bike.grounded=0,0,true
        rider.bike.h=world:supportHeight(anchor.x,anchor.z)
        rider.ped.x,rider.ped.z,rider.ped.speed=site.door.x,site.door.z,0
        Rider.update(rider,{},0,world);C.syncPlayer(R.World.player,part)
        R.state.home.residents.owner.ridingGear=Schema.copy(rider.gear)
        R.state.home.balanceCents=100000
        render();waitFor(function()return R._commute.renderer and not R._commute.loading end,15,'Exterior failed to prepare')
        local parked={x=rider.bike.x,z=rider.bike.z,heading=rider.bike.heading,px=rider.ped.x,pz=rider.ped.z}
        local funds=R.state.home.balanceCents
        Loader.setEnabled(true)
        assert(C.openMechanic(R),R.state.message);local offer=R._commute.mechanicOffer
        check('mechanic_runtime_opens_real_service_interior_at_registered_door',offer and offer.page=='lobby' and not offer.interior.ready)
        render()
        capture('opening',960,678)
        check('mechanic_runtime_visible_loading_precedes_image_requests',offer.interior.loadIndex==1 and offer.interior.presented)
        waitFor(function()return offer.interior.ready or offer.interior.error end,20,'Mechanic art did not become ready')
        assert(not offer.interior.error,offer.interior.error)
        for _=1,20 do tick()end
        check('mechanic_runtime_approved_background_mechanic_and_borrowed_bike_ready',offer.interior.images.background~=nil
            and offer.interior.images.idle~=nil and offer.interior.images.use~=nil
            and offer.interior.bikeImage==R._commute.renderer.bikeArt.images.parked and #offer.interior.requests==3)
        capture('ready-960',960,678);capture('ready-640',640,480)
        assert(C.pointer(R,700,430),'Pointer blocked in '..tostring(R.state.screen)..': '..tostring(R.state.message));check('mechanic_runtime_counter_opens_catalog',offer.page=='catalog')
        capture('catalog',960,678)
        assert(Shop.confirm(R));check('mechanic_runtime_quote_requires_separate_confirmation',offer.page=='confirm'
            and R.state.home.balanceCents==funds and (R.state.home.residents.owner.ridingUpgradeParts.engine or 0)==0)
        capture('confirmation',960,678)
        assert(Shop.confirm(R));tick()
        local engineOffer=require('src.commute.bike_upgrades').CATEGORY_BY_ID.engine.offers[1]
        check('mechanic_runtime_confirm_purchases_through_authoritative_command',offer.page=='install'
            and R.state.home.balanceCents==funds-engineOffer.costCents
            and R.state.home.residents.owner.ridingUpgradeParts.engine==1 and rider.bike.upgradeParts.engine==1)
        capture('installation',960,678)
        waitFor(function()return offer.page=='receipt'end,10,'Service did not finish')
        check('mechanic_runtime_installation_reaches_receipt_without_recharging',R.state.home.balanceCents==funds-engineOffer.costCents)
        capture('receipt',960,678)
        assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
        check('mechanic_runtime_saved_upgrade_and_funds_survive_storage',saved.state.home.balanceCents==funds-engineOffer.costCents
            and saved.state.home.residents.owner.ridingUpgradeParts.engine==1
            and saved.state.home.commute.participants.owner.rider.bike.upgradeParts.engine==1)
        Shop.keypressed(R,'return');check('mechanic_runtime_receipt_returns_to_shop_floor',offer.page=='lobby')
        local button=Interior.layout(R).exit;assert(C.pointer(R,button.x+button.w/2,button.y+button.h/2))
        check('mechanic_runtime_exit_preserves_same_parked_exterior_trip',R._commute.mechanicOffer==nil
            and R.World.player.sceneId=='commute' and R.state.home.commute.token==77
            and rider.bike.x==parked.x and rider.bike.z==parked.z and rider.bike.heading==parked.heading
            and rider.ped.x==parked.px and rider.ped.z==parked.pz and not rider.gear.mounted and not rider.gear.engine)
        capture('returned-outside',960,678)
    end,debug.traceback)
    Shop.close(R);canvas:release();Loader.setEnabled(oldLoader);R.Input.movement=oldMovement
    R.Config.baseWidth,R.Config.baseHeight=oldWidth,oldHeight;R.state.activeSlot=nil
    if not okay then error(reason,0)end
end
return Test
