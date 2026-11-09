local Home=require("src.home")
local Catalog=require("src.home_catalog")
local Schema=require("src.save_schema")
local State=require("src.state")
local Calendar=require("src.business_calendar")
local Setup=require("src.screens.shop_setup_screen")
local Test={}
local function officeChecks(check)
    local state=State.new();state.calendar=Calendar.dateFromTotalDay(31);Home.advance(state)
    state.home.balanceCents=60000
    local saves=0
    local access=true
    local command=require("src.office_authority").command({state=state,
        world={validateNetworkWorkshopAccess=function() return access,"out_of_range","Too far away" end},
        save=function() saves=saves+1 end})
    local function perform(player,intent)
        return command.perform({},player,{officeIntent=intent})
    end
    local intent={kind="home_pay_rent",expectedRevision=state.home.revision}
    local guest,code=perform({id=2},intent)
    check("home_office_guest_cannot_pay_or_change_split",not guest and code=="owner_only"
        and not perform({id=2},{kind="home_set_pay",percent=100,expectedRevision=state.home.revision})
        and not perform({id=2},{kind="home_set_reserve",reserveCents=0,expectedRevision=state.home.revision}) and saves==0)
    access=false
    check("home_office_requires_computer_access",not perform({id=1},intent) and saves==0)
    access=true
    check("home_office_payment_atomic_and_replay_safe",perform({id=1},intent)
        and not perform({id=1},intent) and saves==1 and state.home.balanceCents==15000 and state.money==180)
    local Intent=require("src.office_intent")
    check("home_office_rejects_client_price_and_fraction",not Intent.normalize({kind="home_pay_rent",expectedRevision=state.home.revision,amount=1})
        and not Intent.normalize({kind="home_set_pay",expectedRevision=state.home.revision,percent=25.5}))
    local Computer=require("src.screens.computer_screen")
    local ownerScreen=Computer.new({warehouseCommand=function(value)
        return perform({id=1},assert(Intent.normalize(value)))
    end})
    ownerScreen.tab="home"
    local x,y=ownerScreen.homeControlCenter("slider")
    local result=ownerScreen.mousepressed(state,x,y,1)
    check("home_office_slider_sets_and_saves_exact_percentage",result.action=="home_changed" and state.home.payPercent==50 and saves==2)
    local guestScreen=Computer.new({remoteCommand=function() error("Guest sent a host-only household command") end})
    guestScreen.tab="home"
    check("home_office_guest_controls_are_read_only",guestScreen.mousepressed(state,x,y,1).action=="blocked"
        and state.home.payPercent==50)
    local calendarHasRent=false
    for _,event in ipairs(Calendar.events(state)) do if event.kind=="home_rent" then calendarHasRent=true end end
    check("home_calendar_lists_apartment_rent",calendarHasRent)
end
function Test.run(context,check)
    officeChecks(check)
    local options=Setup.new()
    check("home_empty_default_only_owns_laptop",options.furnishingPreset=="empty"
        and Home.new().inventory.laptop==0 and #Home.new().furniture.items==1 and Home.new().furniture.items[1].kind=="laptop" and next(Home.new().inventory,"laptop")==nil)
    options.furnishingPreset="modest"
    Setup.randomize(options,function(count) assert(count==4);return 4 end)
    check("home_random_preview_preserves_furnishings",options.apartmentId=="corner"
        and options.furnishingPreset=="modest" and options.randomized)
    for _,id in ipairs(Catalog.ORDER) do
        for _,preset in ipairs({"empty","modest"}) do
            local payload=assert(context.save.newGame(3,{apartmentId=id,furnishingPreset=preset}))
            local state=State.new();assert(State.applyLocalSave(state,payload))
            assert(context.save.save(3,state,{x=320,y=400}))
            local loaded=assert(context.save.load(3))
            local guest=State.new();assert(State.applySharedSnapshot(guest,Schema.snapshot(state)))
            check("home_save_and_shared_"..id.."_"..preset,loaded.state.home.apartmentId==id
                and loaded.state.home.furnishingPreset==preset
                and loaded.state.home.lease.monthlyCents==Catalog.APARTMENTS[id].rentCents
                and loaded.state.home.balanceCents==30000 and loaded.state.money==180
                and guest.home.apartmentId==id and guest.home.inventory.laptop==0 and #guest.home.furniture.items==(preset=="empty" and 1 or 9)
                and (preset=="empty" or guest.home.inventory.basic_meal==4))
        end
        for _,path in ipairs({Catalog.APARTMENTS[id].floorPath,Catalog.APARTMENTS[id].wallPath}) do
            local w,h=require("src.image_contract").dimensions(path)
            check("home_asset_"..id.."_"..(path:find("floor",1,true) and "floor" or "wall"),w==1536 and h==1024)
        end
    end
    local invalidOptions={{apartmentId="random"},{apartmentId="missing"},{furnishingPreset="luxury"}}
    for i,value in ipairs(invalidOptions) do check("home_setup_rejects_"..i,context.save.newGame(1,value)==nil) end
    local state=State.new();local businessMoney=state.money
    state.calendar=Calendar.dateFromTotalDay(30)
    check("home_rent_grace_first_month",not Home.advance(state) and Home.amountDue(state.home)==0)
    state.calendar=Calendar.dateFromTotalDay(31)
    check("home_rent_posts_month_once",Home.advance(state) and Home.amountDue(state.home)==45000
        and not Home.advance(state) and state.home.lease.nextDueDay==59)
    local revision=state.home.revision
    check("home_rent_cannot_use_business_balance",not Home.payRent(state.home,revision)
        and state.money==businessMoney and state.home.balanceCents==30000)
    state.home.balanceCents=90000
    check("home_rent_payment_replay_safe",Home.payRent(state.home,revision)
        and not Home.payRent(state.home,revision) and state.home.balanceCents==45000
        and Home.amountDue(state.home)==0 and state.money==businessMoney)
    local snapshot=assert(Schema.snapshot(state))
    local restored=State.new();assert(State.applyLocalSave(restored,{state=snapshot,slot=3}))
    check("home_rent_reload_has_no_new_charge",not Home.advance(restored) and Home.amountDue(restored.home)==0)
    restored.calendar=Calendar.dateFromTotalDay(90)
    check("home_rent_large_step_posts_each_month",Home.advance(restored)
        and restored.home.lease.invoiceCount==3 and Home.amountDue(restored.home)==90000
        and restored.home.lease.nextDueDay==120 and not Home.advance(restored))
    local lateStart=Home.new(nil,29)
    check("home_rent_late_month_grace",lateStart.lease.firstDueDay==59)
    for _,percent in ipairs({0,100,25}) do
        local rev=state.home.revision
        check("home_pay_percentage_"..percent,Home.setPayPercent(state.home,percent,rev)
            and not Home.setPayPercent(state.home,percent,rev) and state.home.payPercent==percent)
    end
    for i,value in ipairs({-1,101,0/0,math.huge,"25",2.5}) do
        check("home_pay_invalid_"..i,not Home.setPayPercent(state.home,value,state.home.revision))
    end
    local old={version=23,slot=1,createdAt=1,updatedAt=2,state=Schema.snapshot(State.new()),player={x=320,y=400}}
    old.state.home=nil
    local migrated=assert(Schema.migrate(old))
    check("home_legacy_gets_separate_allowance_once",migrated.version==Schema.VERSION and migrated.state.home.balanceCents==30000
        and migrated.state.money==180 and Schema.migrate(migrated).state.home.balanceCents==30000)
    local bad=Schema.copy(migrated);bad.state.home.balanceCents=0/0
    check("home_rejects_corrupt_local_and_guest_state",not Schema.validPayload(bad)
        and not State.applyLocalSave(State.new(),bad) and not State.applySharedSnapshot(State.new(),bad.state))
    local paid=Schema.copy(migrated);paid.state.home.lease.paidCents=1
    check("home_rejects_paid_more_than_charged",not Schema.validPayload(paid))
    local skipped=Schema.copy(migrated);skipped.state.home.lease.nextDueDay=59
    check("home_rejects_skipped_rent_checkpoint",not Schema.validPayload(skipped))
    local detached=Home.normalize(state.home);detached.inventory.laptop=1
    check("home_snapshot_is_detached",state.home.inventory.laptop==0)
    assert(context.save.delete(3))
    -- Render both contents previews through the actual setup screen, optionally
    -- exporting review images without requiring an interactive game window.
    local destination=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    local loader=require("src.image_loader");local enabled=loader.enabled;loader.setEnabled(false)
    local previousPack=context.assets.activePackName()
    assert(context.assets.activatePack("menu"))
    for _,preset in ipairs({"empty","modest"}) do
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        local preview=Setup.new();preview.furnishingPreset=preset
        if preset=="modest" then preview.apartmentId="corner" end
        Setup.draw(preview,1,context.assets)
        love.graphics.pop()
        if destination then
            local data=canvas:newImageData();local encoded=data:encode("png")
            local file=assert(io.open(destination.."/setup-"..preset..".png","wb"))
            file:write(encoded:getString());file:close();encoded:release();data:release()
        end
        canvas:release()
        check("home_setup_render_"..preset,true)
    end
    local computer=require("src.screens.computer_screen").new();computer.tab="home"
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
    computer.draw(State.new(),nil,nil,context.assets)
    love.graphics.pop()
    if destination then
        local data=canvas:newImageData();local encoded=data:encode("png")
        local file=assert(io.open(destination.."/my-home.png","wb"));file:write(encoded:getString());file:close()
        encoded:release();data:release()
    end
    canvas:release();check("home_computer_renders",true)
    require("src.tests.home_guide_test").run(context,check)
    context.assets.releaseApartment();assert(context.assets.activatePack(previousPack));loader.setEnabled(enabled)
end
return Test
