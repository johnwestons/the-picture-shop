local Test={}
function Test.run(R,check)
    local state,p=R.state,R.World.player
    local Layout=require("src.home_layouts");local Calendar=require("src.business_calendar")
    local Furniture=require("src.home_furniture");local Controls=require("src.home_furniture_controls")
    local Activity=require("src.home_activity_controls");local Shopping=require("src.home_shopping")
    local function advance(minutes) R.App.update(Calendar.secondsPerDay(state)/1440*minutes) end
    local function capture(name,menu)
        local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
        local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        R.World.draw(R.Assets,R.CharacterAssets,state,nil,nil,{})
        if menu=="activity" then Activity.draw(R) elseif menu=="furnish" then Controls.draw(R) elseif menu=="computer" then R.ComputerScreen.draw(state) end
        love.graphics.pop();local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    state.screen="world";local laptop=assert(Layout.targets(p,state).computer);p.x,p.y=laptop.x,laptop.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,laptop.hoverX,laptop.hoverY);R.App.keypressed("e")
    local screen=R.ComputerScreen
    local function click(name,index) local x,y=screen.homeShopControlCenter(name,index);screen.mousepressed(state,x,y,1) end
    local function tab(name)
        local x,y=screen.dropdownCenter();screen.mousepressed(state,x,y,1)
        x,y=screen.tabCenter(name);screen.mousepressed(state,x,y,1)
    end
    tab("groceries");click("next");capture("home-kitchen-groceries","computer")
    local balance=state.home.balanceCents
    click("buy",3);click("confirm");click("cancel")
    click("buy",4);click("confirm");click("cancel")
    check("home_kitchen_runtime_orders_raw_groceries",state.home.balanceCents==balance-1200)
    tab("furniture");click("next");click("next");capture("home-kitchen-appliances","computer")
    click("buy",2);click("confirm");click("cancel")
    check("home_kitchen_runtime_buys_stove_with_household_funds",state.home.balanceCents==balance-16200)
    state.screen="world";advance(120);p.x,p.y=Layout.spawn(state,1)
    local parcel=assert(Shopping.target(p,state));R.World.updateNetworkPlayer(0,0,0,R.Assets,state,parcel.hoverX,parcel.hoverY);R.App.keypressed("e")
    local stove,index
    for i,item in ipairs(state.home.furniture.items) do if item.kind=="stove" then stove=item;index=i end end
    check("home_kitchen_runtime_receives_stove_and_ingredients",stove and (stove.location=="storage" or stove.location=="floor")
        and state.home.inventory.bread==4 and state.home.inventory.vegetables==4)
    local x,y=Layout.kitchenPower(state);p.x,p.y=x-60,y
    R.App.keypressed("m");for _=2,index do R.App.keypressed("down") end;R.App.keypressed("return")
    Controls.snapshot(R)
    check("home_kitchen_runtime_stove_snaps_to_power_point",Controls.candidate.x==x and Controls.candidate.y==y)
    for _=1,8 do Controls.mousepressed(80,626,1,R) end
    capture("home-kitchen-stove-placement","furnish")
    Controls.mousepressed(240,626,1,R)
    check("home_kitchen_runtime_touch_keeps_powered_facing",stove.location=="floor" and stove.x==x and stove.y==y and stove.direction=="west" and not stove.editor,state.message)
    R.App.keypressed("escape")
    local target=Furniture.targets(state,p)["furniture"..stove.id];p.x,p.y=target.x,target.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,target.hoverX,target.hoverY);R.App.keypressed("e");R.App.keypressed("return")
    check("home_kitchen_runtime_starts_stove_recipe",state.home.residents.owner.activity and state.home.residents.owner.activity.kind=="cook"
        and state.home.inventory.bread==3 and state.home.inventory.vegetables==2,state.message)
    advance(10);capture("home-kitchen-cooking-timing","activity")
    local pose=assert(require("src.home_routine_pose").get(state,p))
    check("home_kitchen_runtime_cooking_pose",pose.routine=="cook" and pose.item==stove and pose.bowlX~=nil
        and pose.action=="home_cook_"..pose.direction)
    capture("home-kitchen-cooking-pose")
    Activity.mousepressed(650,403,1,R)
    check("home_kitchen_runtime_touch_timing_uses_current_batch",state.home.residents.owner.activity.cookQuality==3)
    assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
    check("home_kitchen_runtime_saves_active_stove_recipe",saved.state.home.residents.owner.activity.cookQuality==3 and saved.state.home.residents.owner.activity.fixtureId==nil)
    advance(10);capture("home-kitchen-finished","activity")
    check("home_kitchen_runtime_delivers_quality_portions",state.home.inventory.good_meal==2 and not state.home.residents.owner.activity)
    state.screen="world";capture("home-kitchen-installed")
    assert(R.saveCurrent(true));saved=assert(R.Save.load(3))
    check("home_kitchen_runtime_completed_portions_saved",saved.state.home.inventory.good_meal==2 and saved.state.home.inventory.bread==3)
end
return Test
