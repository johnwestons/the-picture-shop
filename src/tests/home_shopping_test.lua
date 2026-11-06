local Shopping=require("src.home_shopping")
local State=require("src.state")
local Schema=require("src.save_schema")
local Calendar=require("src.business_calendar")
local Residents=require("src.home_residents")
local Layout=require("src.home_layouts")
local Test={}
local function at(state,hours)
    state.calendar=Calendar.dateFromHours(hours)
    state.calendar.elapsed=hours%24/24*state.calendar.secondsPerDay
end
local function order(s,id,product,quantity)
    return {kind="home_order_food",productId=product or "meal",quantity=quantity or 1,requestId=id,expectedRevision=s.home.revision}
end
local function capture(screen,state,name)
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear();screen.draw(state);love.graphics.pop()
    local data=canvas:newImageData();local bytes=data:encode("png")
    local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
    bytes:release();data:release();canvas:release()
end
function Test.run(context,check)
    local s=State.new();local p={id=1,sceneId="warehouse",x=0,y=0};local business=s.money
    local first=order(s,"food-first","pizza",2)
    assert(Shopping.order(s,p,first))
    check("home_food_household_charge_includes_delivery",s.home.balanceCents==26600 and s.money==business and #s.home.shopping.orders==1)
    check("home_food_duplicate_order_never_recharges",Shopping.order(s,p,first) and #s.home.shopping.orders==1 and s.home.balanceCents==26600)
    first.quantity=1
    check("home_food_conflicting_reference_rejected",not Shopping.order(s,p,first))
    local bad=order(s,"stale");bad.expectedRevision=0
    check("home_food_stale_revision_rejected",not Shopping.order(s,p,bad))
    at(s,.49);check("home_food_not_delivered_early",not Shopping.advance(s))
    at(s,.5);check("home_food_arrives_while_at_shop_once",Shopping.advance(s) and not Shopping.advance(s) and Shopping.waiting(s)==1)
    check("home_food_cannot_collect_from_shop",not Shopping.collect(s,p))
    s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;p.sceneId="home"
    check("home_food_collection_requires_proximity",not Shopping.collect(s,p))
    local target=assert(Shopping.target(p,s));p.x,p.y=target.x,target.y
    assert(context.save.save(3,s,{x=p.x,y=p.y,sceneId="home"}))
    local loaded=State.new();assert(State.applyLocalSave(loaded,assert(context.save.load(3))))
    check("home_food_delivery_survives_reload",Shopping.waiting(loaded)==1 and loaded.home.balanceCents==26600)
    assert(Shopping.collect(loaded,p))
    check("home_food_collect_exact_servings_once",loaded.home.inventory.pizza_slice==8 and not Shopping.collect(loaded,p))
    assert(context.save.save(3,loaded,{x=p.x,y=p.y,sceneId="home"}))
    local resumed=State.new();assert(State.applyLocalSave(resumed,assert(context.save.load(3))))
    check("home_food_collected_state_survives_reload",resumed.home.inventory.pizza_slice==8 and not Shopping.advance(resumed) and not Shopping.collect(resumed,p))
    for _,id in ipairs(require("src.home_catalog").ORDER) do
        local layout=Schema.copy(s);layout.home.apartmentId=id
        local parcel=assert(Shopping.target(p,layout));local x,y=Layout.spawn(layout,1)
        check("home_food_delivery_reachable_"..id,Layout.walkable(id,x,y) and (parcel.x-x)^2+(parcel.y-y)^2<=parcel.radius^2)
    end
    local full=Schema.copy(s);full.home.inventory.pizza_slice=9999
    check("home_food_full_storage_preserves_unclaimed_order",not Shopping.collect(full,p) and Shopping.waiting(full)==1 and full.home.inventory.pizza_slice==9999)
    local broke=State.new();broke.home.balanceCents=0;broke.money=1000000
    check("home_food_business_cash_cannot_cover_personal_shortfall",not Shopping.order(broke,p,order(broke,"broke")) and broke.money==1000000 and #broke.home.shopping.orders==0)
    local forged=order(s,"forged");forged.priceCents=1
    check("home_food_protocol_rejects_client_price",not require("src.office_intent").normalize(forged))
    local pending=State.new();pending.home.balanceCents=100000
    for i=1,16 do assert(Shopping.order(pending,p,order(pending,"pending-"..i))) end
    local before=pending.home.balanceCents
    check("home_food_pending_capacity_does_not_charge",not Shopping.order(pending,p,order(pending,"pending-overflow")) and pending.home.balanceCents==before)
    local guests={}
    for i=2,4 do
        guests[i]={id=i,sceneId="home",x=p.x,y=p.y}
        assert(Residents.bind(s,guests[i],string.rep(tostring(i),64),{p}))
    end
    assert(Shopping.order(s,guests[2],order(s,"guest-pizza","pizza")))
    check("home_food_guests_share_spending_limit",not Shopping.order(s,guests[3],order(s,"guest-chinese","chinese")))
    local limit,spent,remaining=Shopping.budget(s)
    check("home_food_guest_budget_includes_fee",limit==3000 and spent==1800 and remaining==1200)
    local reconnect={id=4};assert(Residents.bind(s,reconnect,string.rep("2",64),{p}))
    check("home_food_reconnect_cannot_reset_budget",not Shopping.order(s,reconnect,order(s,"guest-reconnect","chinese")))
    check("home_food_guest_cannot_change_limit",not Shopping.setLimit(s,reconnect,{expectedRevision=s.home.revision,limitCents=10000}))
    assert(Shopping.setLimit(s,p,{expectedRevision=s.home.revision,limitCents=5000}))
    local _,retained=Shopping.budget(s);check("home_food_increased_limit_keeps_spending",retained==1800)
    s.home.weekend.closesAtHours=s.home.weekend.closesAtHours+168
    local _,newSpent=Shopping.budget(s);check("home_food_new_week_refreshes_budget",newSpent==0)
    check("home_food_unregistered_guest_denied",not Shopping.order(s,{id=3},order(s,"no-resident")))
    resumed.home.inventory.pizza_slice=1
    for i=2,4 do assert(Residents.bind(resumed,guests[i],string.rep(tostring(i),64),{p})) end
    resumed.home.residents.owner.hunger=10
    assert(Residents.command(resumed,p,"pizza:floor"))
    local accepted=0;for i=2,4 do if Residents.command(resumed,guests[i],"pizza:floor") then accepted=accepted+1 end end
    Residents.advance(resumed,{p,guests[2],guests[3],guests[4]},.5,.5+10/60)
    check("home_food_four_players_cannot_duplicate_last_serving",accepted==0 and resumed.home.inventory.pizza_slice==0 and resumed.home.residents.owner.hunger>54)
    local invalid=Schema.copy(s);invalid.home.shopping.orders[1].totalCents=1
    check("home_food_invalid_receipt_rejected",not Schema.validState(invalid))
    local legacy={version=28,slot=3,createdAt=1,updatedAt=2,state=Schema.snapshot(State.new()),player={x=300,y=400}}
    legacy.state.home.shopping=nil
    local migrated=assert(Schema.migrate(legacy))
    check("home_food_legacy_migration_has_empty_ledger",migrated.version==Schema.VERSION and #migrated.state.home.shopping.orders==0 and migrated.state.home.balanceCents==30000)
    -- Real office authorization validates the laptop range for each guest action.
    local officeState=State.new();officeState.home.weekend.phase="home";officeState.home.weekend.closedAtHours=44
    local shopper={id=2,sceneId="home",x=0,y=0};Residents.bind(officeState,shopper,string.rep("b",64),{p})
    local saves=0
    local office=require("src.office_authority").command({state=officeState,world=context.world,save=function() saves=saves+1 end})
    local intent=order(officeState,"office-guest","sandwich")
    check("home_food_guest_office_rejects_remote_purchase",not office.perform(nil,shopper,{officeIntent=intent}))
    shopper.x,shopper.y=Layout.toWorld(unpack(Layout.get(officeState).laptop.approach))
    check("home_food_guest_can_order_at_laptop",office.perform(nil,shopper,{officeIntent=intent}) and officeState.home.balanceCents==29600 and saves==1)
    local screen=require("src.screens.computer_screen").new({warehouseCommand=function(value)
        return office.perform(nil,shopper,{officeIntent=value})
    end,isNetworkClient=function() return true end})
    local function click(name,index) local x,y=screen.homeShopControlCenter(name,index);return screen.mousepressed(officeState,x,y,1) end
    screen.tab="groceries";capture(screen,officeState,"home-groceries")
    click("buy",1);click("quantityPlus");capture(screen,officeState,"home-food-checkout")
    click("confirm");local balance=officeState.home.balanceCents;local count=#officeState.home.shopping.orders
    click("quantityPlus");click("confirm")
    check("home_food_checkout_receipt_locks_repeat_clicks",count==2 and balance==28500 and officeState.home.balanceCents==balance and #officeState.home.shopping.orders==count)
    screen.tab="home_orders";capture(screen,officeState,"home-deliveries")
    click("plus");check("home_food_guest_limit_ui_readonly",officeState.home.shopping.guestLimitCents==3000)
    screen.tab="takeout";capture(screen,officeState,"home-takeout")
    -- Every generated prop can be rendered using its registered atlas cell.
    local canvas=love.graphics.newCanvas(512,512);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
    for i=1,16 do require("src.home_food_art").draw(i,64+((i-1)%4)*128,64+math.floor((i-1)/4)*128,120) end
    love.graphics.pop();canvas:release();check("home_food_all_atlas_cells_render",true)
    assert(context.save.delete(3))
end
return Test
