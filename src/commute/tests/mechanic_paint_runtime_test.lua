-- Real customer flow in an isolated App: existing kit service, two paint jobs,
-- persistent appearance, and the imported raccoon's idle/work presentation.
local C=require('src.commute.runtime')
local Trip=require('src.commute.trip')
local Town=require('src.commute.town')
local Rider=require('src.commute.rider')
local Shop=require('src.commute.mechanic_shop')
local Paint=require('src.commute.bike_paint')
local Upgrades=require('src.commute.bike_upgrades')
local Loader=require('src.image_loader')
local Schema=require('src.save_schema')
local Test={}
function Test.run(context,check)
    local R=assert(context.appRuntime)
    local folder=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE')
    local originalWidth,originalHeight=R.Config.baseWidth,R.Config.baseHeight
    local originalLoader,originalMovement=Loader.enabled,R.Input.movement
    local canvas=love.graphics.newCanvas(960,678)
    local function part()return assert(C.localPart(R))end
    local function resident()return R.state.home.residents.owner end
    local function render()
        love.graphics.push('all');love.graphics.setCanvas({canvas,stencil=true})
        love.graphics.clear(0,0,0,1);C.draw(R);love.graphics.pop()
    end
    local function tick(dt)R.App.update(dt or 1/60);render();love.timer.sleep(.001)end
    local function waitFor(predicate,seconds,label)
        local deadline=love.timer.getTime()+seconds
        while not predicate()and love.timer.getTime()<deadline do tick()end
        assert(predicate(),label)
    end
    local function capture(name,width,height)
        if not folder then return end
        local oldW,oldH=R.Config.baseWidth,R.Config.baseHeight
        R.Config.baseWidth,R.Config.baseHeight=width or 960,height or 678
        local target=love.graphics.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
        love.graphics.push('all');love.graphics.setCanvas({target,stencil=true})
        love.graphics.clear(0,0,0,1);C.draw(R);love.graphics.pop()
        local pixels=target:newImageData();local encoded=pixels:encode('png')
        local file=assert(io.open(folder..'/'..name..'.png','wb'));file:write(encoded:getString());file:close()
        encoded:release();pixels:release();target:release()
        R.Config.baseWidth,R.Config.baseHeight=oldW,oldH
    end
    local function key(value)return R.dispatchKeyPressed(value)end
    local function tap(rect)
        local x=(rect.x+rect.w/2)*R.Config.baseWidth/960
        local y=(rect.y+rect.h/2)*R.Config.baseHeight/678
        local ox,oy,scale=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,R.App.officeFitsScreen())
        local sx,sy=ox+x*scale,oy+y*scale
        local consumed=R.App.touchpressed('mechanic-paint',sx,sy)
        R.App.touchreleased('mechanic-paint',sx,sy)
        return consumed
    end
    local function open()
        assert(key('e'),'App did not dispatch the mechanic interaction')
        local offer=assert(R._commute.mechanicOffer,'Mechanic did not open')
        render()
        waitFor(function()return offer.interior.ready or offer.interior.error end,25,'Mechanic artwork did not prepare')
        assert(not offer.interior.error,offer.interior.error)
        return offer
    end
    local function seeMechanic(offer,action,frames)
        local draw=love.graphics.draw
        love.graphics.draw=function(image,quad,...)
            if image==offer.interior.images[action]then
                for index,expected in ipairs(offer.interior.quads[action])do
                    if quad==expected then frames[index]=true end
                end
            end
            return draw(image,quad,...)
        end
        local okay,reason=xpcall(render,debug.traceback)
        love.graphics.draw=draw
        if not okay then error(reason,0)end
    end
    local function previewQuad(offer)
        local draw=love.graphics.draw;local seen
        love.graphics.draw=function(image,quad,...)
            local x,y=...
            if image==offer.interior.bikeImage and x==614 and y==382 then seen=quad end
            return draw(image,quad,...)
        end
        local okay,reason=xpcall(render,debug.traceback);love.graphics.draw=draw
        if not okay then error(reason,0)end
        return assert(seen,'Live preview did not draw its borrowed motorcycle quad')
    end
    local function finishService(offer,label)
        waitFor(function()return offer.page=='receipt'end,12,label..' did not reach receipt')
    end
    local function leave(offer)
        if offer.page~='lobby'then key('escape')end
        key('escape')
        assert(not R._commute.mechanicOffer,'Shop did not return outside')
    end
    local okay,reason=xpcall(function()
        assert(C.enabled(),'Mechanic paint fixture requires commute')
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden',town=assert(Town.generate(712345))})),'smoke'))
        R.Config.baseWidth,R.Config.baseHeight=960,678;R.state.screen='world'
        R.Input.movement=function()return 0,0 end
        local week=R.state.home.weekend
        week.phase='ready';week.closedAtHours=44;week.travelToken=177;week.readyMask=1
        local world=C.world(R)
        assert(Trip.start(R.state,{R.World.player},177,world))
        R._weekendPromptToken=177;R._weekendScene='commute'
        local rider=part().rider;local site=world.sites.byId.mechanic
        local anchor=assert(Trip.parking(world,'mechanic',1))
        rider.gear.outfit='geared';rider.gear.mounted=false;rider.gear.engine=false;rider.gear.transition=nil
        rider.bike.x,rider.bike.z,rider.bike.heading=anchor.x,anchor.z,anchor.heading
        rider.bike.speed,rider.bike.vy,rider.bike.grounded=0,0,true
        rider.bike.h=world:supportHeight(anchor.x,anchor.z)
        rider.ped.x,rider.ped.z,rider.ped.speed=site.door.x,site.door.z,0
        Rider.update(rider,{},0,world);C.syncPlayer(R.World.player,part())
        resident().ridingGear=Schema.copy(rider.gear);R.state.home.balanceCents=100000
        local parked={x=rider.bike.x,z=rider.bike.z,heading=rider.bike.heading,px=rider.ped.x,pz=rider.ped.z}
        render();waitFor(function()return R._commute.renderer and not R._commute.loading end,60,'Exterior terrain did not prepare')
        Loader.setEnabled(true)
        local offer=open();local indoor=offer.interior
        local idleFrames={};seeMechanic(offer,'idle',idleFrames)
        local iw,ih=indoor.images.idle:getDimensions();local uw,uh=indoor.images.use:getDimensions()
        check('mechanic_paint_runtime_imported_raccoon_art_and_idle_draw',iw==1024 and ih==512 and uw==1536 and uh==512
            and #indoor.quads.idle==2 and #indoor.quads.use==3 and next(idleFrames)~=nil)
        capture('raccoon-idle-960');capture('raccoon-idle-640',640,480)
        for _=1,16 do tick(.1);seeMechanic(offer,'idle',idleFrames)end
        check('mechanic_paint_runtime_imported_raccoon_idle_blink_frames_draw',idleFrames[1] and idleFrames[2])
        check('mechanic_paint_runtime_starts_original_bronze',resident().ridingPaintId==Paint.DEFAULT
            and rider.bike.paintId==Paint.DEFAULT and resident().ridingPaintRevision==0)
        -- Keep the pre-existing engine upgrade path exercised alongside cosmetics.
        Shop.catalog(R);local originalFunds=R.state.home.balanceCents
        key('return')
        check('mechanic_paint_runtime_kit_quote_is_not_purchase',offer.page=='confirm' and R.state.home.balanceCents==originalFunds)
        key('return');tick()
        local kitCost=Upgrades.CATALOG[1].costCents
        check('mechanic_paint_runtime_existing_kit_still_installs',offer.page=='install' and resident().ridingUpgradeLevel==1
            and rider.bike.upgradeLevel==1 and R.state.home.balanceCents==originalFunds-kitCost)
        capture('kit-installing-960')
        local useFrames={}
        for _=1,12 do seeMechanic(offer,'use',useFrames);tick(.1)end
        check('mechanic_paint_runtime_imported_raccoon_three_work_frames_draw',useFrames[1] and useFrames[2] and useFrames[3])
        finishService(offer,'Engine kit');capture('kit-receipt-960');key('return')
        Shop.catalog(R);R.Config.baseWidth,R.Config.baseHeight=640,480
        local layout=Shop.layout()
        local touchPaint=tap(layout.paint);local touchRed=tap(layout.swatches[2])
        check('mechanic_paint_runtime_640_app_touch_selects_color',touchPaint and touchRed
            and offer.service=='paint' and offer.selectedPaintId=='red')
        local priorFrame=offer.previewFrame;local priorQuad=previewQuad(offer);tap(layout.next)
        local nextQuad=previewQuad(offer);local rotated=offer.previewFrame~=priorFrame
        tap(layout.previous)
        check('mechanic_paint_runtime_640_app_touch_rotates_preview_only',rotated and offer.previewFrame==priorFrame
            and priorQuad~=nextQuad and previewQuad(offer)==priorQuad
            and rider.bike.heading==parked.heading and rider.bike.paintId==Paint.DEFAULT)
        local seenQuads={[priorQuad]=true};local uniqueViews=1
        for _=1,16 do
            tap(layout.next);local q=previewQuad(offer)
            if not seenQuads[q]then seenQuads[q]=true;uniqueViews=uniqueViews+1 end
        end
        check('mechanic_paint_runtime_preview_wraps_exactly_sixteen_physical_views',uniqueViews==16
            and offer.previewFrame==priorFrame and previewQuad(offer)==priorQuad)
        R.Config.baseWidth,R.Config.baseHeight=960,678
        local beforePaint=R.state.home.balanceCents
        check('mechanic_paint_runtime_preview_does_not_change_owned_bike',offer.service=='paint' and offer.selectedPaintId=='red'
            and resident().ridingPaintId==Paint.DEFAULT and rider.bike.paintId==Paint.DEFAULT and R.state.home.balanceCents==beforePaint)
        capture('paint-catalog-960');capture('paint-catalog-640',640,480)
        key('return')
        check('mechanic_paint_runtime_paint_quote_requires_second_approval',offer.page=='confirm'
            and R.state.home.balanceCents==beforePaint and resident().ridingPaintRevision==0)
        capture('paint-confirm-640',640,480)
        key('return');tick()
        check('mechanic_paint_runtime_paint_approval_updates_same_bike_once',offer.page=='install'
            and resident().ridingPaintId=='red' and rider.bike.paintId=='red' and resident().ridingPaintRevision==1
            and R.state.home.balanceCents==beforePaint-Paint.COST_CENTS and rider.bike.upgradeLevel==1)
        local afterRed=R.state.home.balanceCents
        key('return');tick()
        check('mechanic_paint_runtime_repeated_approval_during_install_is_free',R.state.home.balanceCents==afterRed
            and resident().ridingPaintRevision==1)
        capture('paint-installing-960');capture('paint-installing-640',640,480)
        finishService(offer,'Red paint')
        check('mechanic_paint_runtime_paint_receipt_identifies_cosmetic_service',offer.receipt and offer.receipt.kind=='paint'
            and R.state.home.balanceCents==afterRed)
        capture('paint-receipt-960')
        assert(C.request(R,'bikepaint:177:1:red'))
        check('mechanic_paint_runtime_same_current_finish_is_idempotent',R.state.home.balanceCents==afterRed
            and resident().ridingPaintRevision==1 and rider.bike.paintId=='red')
        leave(offer);render();capture('red-exterior-960')
        check('mechanic_paint_runtime_exit_preserves_parked_trip_and_gear',rider.bike.x==parked.x and rider.bike.z==parked.z
            and rider.bike.heading==parked.heading and rider.ped.x==parked.px and rider.ped.z==parked.pz
            and not rider.gear.mounted and not rider.gear.engine and R.state.home.commute.token==177)
        assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
        check('mechanic_paint_runtime_save_keeps_paint_revision_cash_and_kit',saved.state.home.residents.owner.ridingPaintId=='red'
            and saved.state.home.residents.owner.ridingPaintRevision==1 and saved.state.home.balanceCents==afterRed
            and saved.state.home.commute.participants.owner.rider.bike.paintId=='red'
            and saved.state.home.commute.participants.owner.rider.bike.upgradeLevel==1)
        assert(R.startGame(saved,'smoke'));R.state.screen='world'
        render();waitFor(function()return R._commute.renderer and not R._commute.loading end,60,'Reload terrain did not prepare')
        rider=part().rider
        check('mechanic_paint_runtime_reload_restores_painted_parked_motorcycle',rider.bike.paintId=='red'
            and resident().ridingPaintId=='red' and resident().ridingPaintRevision==1
            and rider.bike.x==parked.x and rider.bike.z==parked.z and R.state.home.balanceCents==afterRed)
        capture('red-reloaded-exterior-960')
        offer=open();Shop.catalog(R);key('tab');key('3');key('return');key('escape')
        check('mechanic_paint_runtime_cancelled_repaint_keeps_red_and_funds',resident().ridingPaintId=='red'
            and R.state.home.balanceCents==afterRed and resident().ridingPaintRevision==1)
        Shop.catalog(R);key('tab');key('3');key('return');key('return');tick()
        check('mechanic_paint_runtime_second_finish_advances_paint_only',resident().ridingPaintId=='blue'
            and rider.bike.paintId=='blue' and resident().ridingPaintRevision==2 and rider.bike.upgradeLevel==1
            and R.state.home.balanceCents==afterRed-Paint.COST_CENTS)
        capture('blue-installing-640',640,480)
        finishService(offer,'Blue paint');leave(offer);render()
        capture('blue-exterior-960');capture('blue-exterior-640',640,480)
        assert(R.saveCurrent(true));saved=assert(R.Save.load(3))
        check('mechanic_paint_runtime_final_repaint_persists_both_records',saved.state.home.residents.owner.ridingPaintId=='blue'
            and saved.state.home.residents.owner.ridingPaintRevision==2
            and saved.state.home.commute.participants.owner.rider.bike.paintId=='blue'
            and saved.state.home.balanceCents==originalFunds-kitCost-2*Paint.COST_CENTS)
    end,debug.traceback)
    Shop.close(R);canvas:release();Loader.setEnabled(originalLoader);R.Input.movement=originalMovement
    R.Config.baseWidth,R.Config.baseHeight=originalWidth,originalHeight;R.state.activeSlot=nil
    if not okay then error(reason,0)end
end
return Test
