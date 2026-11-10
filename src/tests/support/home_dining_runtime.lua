local Test={}
function Test.run(R,check)
    local s,p=R.state,R.World.player;local Layout=require("src.home_layouts");local Calendar=require("src.business_calendar")
    local Furniture=require("src.home_furniture");local Controls=require("src.home_furniture_controls")
    local Activity=require("src.home_activity_controls");local Dining=require("src.home_dining");local Find=require("src.tests.home_dining_test")
    R.App.keypressed("h");R.App.keypressed("backspace");R.App.keypressed("escape")
    local function capture(name,menu)
        local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
        local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        R.World.draw(R.Assets,R.CharacterAssets,s,nil,nil,{});if menu then Activity.draw(R) end
        love.graphics.pop();local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    local laptop=assert(Layout.targets(p,s).computer);p.x,p.y=laptop.x,laptop.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,laptop.hoverX,laptop.hoverY);R.App.keypressed("e")
    local screen=R.ComputerScreen
    local function tab(name) local x,y=screen.dropdownCenter();screen.mousepressed(s,x,y,1);x,y=screen.tabCenter(name);screen.mousepressed(s,x,y,1) end
    local function click(name,index) local x,y=screen.homeShopControlCenter(name,index);screen.mousepressed(s,x,y,1) end
    local money=s.home.balanceCents
    tab("furniture");for _=1,6 do click("previous") end;for _=1,3 do click("next") end
    click("buy",1);click("confirm");click("cancel")
    for _=1,6 do click("previous") end;click("buy",2);click("confirm");click("cancel")
    tab("groceries");click("buy",2);click("confirm");click("cancel")
    check("home_dining_runtime_buys_table_chair_food",s.home.balanceCents==money-11270,s.message)
    s.screen="world";R.App.update(Calendar.secondsPerDay(s)/12);p.x,p.y=Layout.spawn(s,1)
    local parcel=assert(require("src.home_shopping").target(p,s));R.World.updateNetworkPlayer(0,0,0,R.Assets,s,parcel.hoverX,parcel.hoverY);R.App.keypressed("e")
    local function itemOf(kind)
        for _,item in ipairs(s.home.furniture.items) do if item.kind==kind then return item end end
        error("Missing delivered "..kind)
    end
    local tableItem,chair=itemOf("kitchen_table"),itemOf("chair")
    check("home_dining_runtime_receives_actual_supplies",tableItem.kind=="kitchen_table" and chair.kind=="chair" and s.home.inventory.basic_meal==4)
    for _,item in ipairs({tableItem,chair}) do
        local index
        for i,row in ipairs(s.home.furniture.items) do if row==item then index=i;break end end
        item.location="storage";item.parentId=nil;item.slot=nil
        local spot=item==tableItem and require("src.tests.home_tables_lamp_test").findSpot(s,item.kind,{p},item.id) or Find.seat(s,tableItem,item.id)
        assert(spot)
        for _,a in ipairs(Furniture.approaches(spot)) do
            if Furniture.canPlace(s,spot,{{id=1,sceneId="home",x=a.x,y=a.y}}) then p.x,p.y=a.x,a.y;break end
        end
        R.App.keypressed("m");for _=2,index do R.App.keypressed("down") end;R.App.keypressed("return");Controls.snapshot(R)
        for _=1,8 do if Controls.candidate.direction==spot.direction then break end;R.App.keypressed("q") end
        for _=1,60 do
            local c=Controls.candidate
            if c.x~=spot.x then R.App.keypressed(c.x>spot.x and "left" or "right")
            elseif c.y~=spot.y then R.App.keypressed(c.y>spot.y and "up" or "down") else break end
        end
        Controls.mousepressed(240,626,1,R)
        check("home_dining_runtime_places_"..item.kind,item.location=="floor" and item.x==spot.x and item.y==spot.y and item.direction==spot.direction,s.message)
        R.App.keypressed("escape")
    end
    Find.near(s,p,tableItem.id);local target=assert(Furniture.targets(s,p)["furniture"..tableItem.id])
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,target.hoverX,target.hoverY);R.App.keypressed("e");Activity.mousepressed(730,612,1,R)
    check("home_dining_runtime_meals_touch_tab",Activity.mode=="dining" and s.screen=="home_activity")
    Activity.mousepressed(400,322,1,R);Activity.mousepressed(400,426,1,R)
    check("home_dining_runtime_serves_two_real_portions",#s.home.dining.items==2 and s.home.inventory.basic_meal==2,s.message)
    capture("home-served-meals-menu",true);R.App.keypressed("escape");capture("home-served-meals-table")
    target=assert(Furniture.targets(s,p)["furniture"..chair.id]);p.x,p.y=target.x,target.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,target.hoverX,target.hoverY);R.App.keypressed("e");R.App.keypressed("d")
    capture("home-chair-meal-menu",true);Activity.mousepressed(400,322,1,R)
    check("home_dining_runtime_eats_from_aligned_chair",s.home.residents.owner.activity and s.home.residents.owner.activity.diningParentId==tableItem.id
        and s.home.residents.owner.activity.furnitureId==chair.id and #s.home.dining.items==1,s.message)
    local pose=assert(require("src.home_activity_pose").get(s,p))
    check("home_dining_runtime_pose_matches_chair",pose.kind=="eating" and pose.direction==chair.direction and pose.item.id==chair.id)
    assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
    check("home_dining_runtime_saved_served_and_active_meal",#saved.state.home.dining.items==1 and saved.state.home.residents.owner.activity.diningSlot==1)
    R.App.keypressed("escape");capture("home-chair-eating");R.App.update(Calendar.secondsPerDay(s)/96)
    check("home_dining_runtime_meal_finishes_frees_slot",not s.home.residents.owner.activity and not Dining.occupied(s,tableItem.id,1))
    Find.near(s,p,tableItem.id);R.App.keypressed("m");for _=2,5 do R.App.keypressed("down") end;R.App.keypressed("return");R.App.keypressed("p")
    check("home_dining_runtime_packing_returns_uneaten_portion",tableItem.location=="storage" and #s.home.dining.items==0 and s.home.inventory.basic_meal==3,s.message)
    R.App.keypressed("escape")
end
return Test
