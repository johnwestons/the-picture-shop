local Test={}
function Test.run(R,check)
    local Layout=require("src.home_layouts");local Shopping=require("src.home_shopping")
    local Calendar=require("src.business_calendar");local Controls=require("src.home_activity_controls")
    local state,host=R.state,R.World.player;local balance=state.home.balanceCents
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    local function capture(name,menu)
        if not folder then return end
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        if menu then Controls.draw(R) else R.World.draw(R.Assets,R.CharacterAssets,state,nil,nil,{}) end
        love.graphics.pop()
        local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    host.x,host.y=Layout.toWorld(unpack(Layout.get(state).laptop.approach))
    local laptop=Layout.targets(host,state).computer
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,laptop.hoverX,laptop.hoverY)
    check("home_food_runtime_laptop_selectable",R.World.getInteraction() and R.World.getInteraction().kind=="computer")
    R.App.keypressed("e")
    check("home_food_runtime_opens_laptop",state.screen=="computer")
    local screen=R.ComputerScreen
    local x,y=screen.dropdownCenter();screen.mousepressed(state,x,y,1)
    x,y=screen.tabCenter("takeout");screen.mousepressed(state,x,y,1)
    check("home_food_runtime_takeout_in_dropdown",screen.tab=="takeout")
    x,y=screen.homeShopControlCenter("buy",1);screen.mousepressed(state,x,y,1)
    x,y=screen.homeShopControlCenter("confirm");screen.mousepressed(state,x,y,1)
    check("home_food_runtime_purchase_uses_household",state.home.balanceCents==balance-1800 and #state.home.shopping.orders==1,state.message)
    R.App.update(Calendar.secondsPerDay(state)/24*.5)
    check("home_food_runtime_calendar_delivers_order",Shopping.waiting(state)==1)
    state.screen="world";local target=Shopping.target(host,state);host.x,host.y=target.x-28,target.y-4
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,target.hoverX,target.hoverY)
    check("home_food_runtime_parcel_selectable",R.World.getInteraction() and R.World.getInteraction().kind=="homeDelivery",
        R.World.getInteraction() and R.World.getInteraction().kind or "none")
    capture("home-delivery-parcel")
    R.App.keypressed("e")
    check("home_food_runtime_keyboard_receives_parcel",state.home.inventory.pizza_slice==4 and Shopping.waiting(state)==0,state.message)
    state.home.residents.owner.hunger=10
    Controls.keypressed("h",R)
    check("home_food_runtime_menu_finds_takeout",require('src.tests.support.home_menu').choose(R,'pizza:floor'))
    check("home_food_runtime_menu_eats_owned_takeout",state.home.residents.owner.activity and state.home.residents.owner.activity.kind=="pizza",
        "activity="..tostring(state.home.residents.owner.activity and state.home.residents.owner.activity.kind).." mode="..Controls.mode.." target="..Controls.target.." message="..tostring(state.message))
    capture("home-food-routines",true);Controls.keypressed("escape",R);capture("home-eating-pizza")
    R.App.update(Calendar.secondsPerDay(state)/24*10/60)
    check("home_food_runtime_eating_restores_need",state.home.residents.owner.hunger>54 and state.home.inventory.pizza_slice==3)
    Controls.keypressed("h",R);Controls.keypressed("1",R);Controls.mousepressed(750,230,1,R)
    check("home_food_runtime_stop_available_without_paging",not state.home.residents.owner.activity)
    Controls.keypressed("right",R)
    check("home_food_runtime_food_menu_pages",Controls.page==2)
    Controls.keypressed("escape",R)
    return balance-state.home.balanceCents
end
return Test
