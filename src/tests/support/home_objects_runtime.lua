local Test={}
function Test.run(R,check)
    local state,p=R.state,R.World.player
    local Furniture=require("src.home_furniture");local Objects=require("src.home_objects")
    local Activity=require("src.home_activity_controls");local Layout=require("src.home_layouts");local Calendar=require("src.business_calendar")
    local items={};for _,item in ipairs(state.home.furniture.items) do if not items[item.kind] then items[item.kind]=item end end
    local function open(item)
        state.screen="world";local t=assert(Furniture.targets(state,p)["furniture"..item.id]);p.x,p.y=t.x,t.y
        R.World.updateNetworkPlayer(0,0,0,R.Assets,state,t.hoverX,t.hoverY);R.App.keypressed("e")
        assert(state.screen=="home_activity","Expected home object activity screen")
    end
    local function capture(name,menu)
        local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
        local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        R.World.draw(R.Assets,R.CharacterAssets,state,nil,nil,{})
        if menu then Activity.draw(R) end
        love.graphics.pop();local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    local function advance(minutes) R.App.update(Calendar.secondsPerDay(state)/1440*minutes) end
    open(items.mini_fridge);local pantry=state.home.inventory.basic_meal
    Activity.mousepressed(400,320,1,R)
    check("home_objects_runtime_touch_stores_food",items.mini_fridge.contents.basic_meal==1 and state.home.inventory.basic_meal==pantry-1)
    capture("home-fridge-storage",true)
    R.App.keypressed("2")
    check("home_objects_runtime_keyboard_takes_food",items.mini_fridge.contents.basic_meal==0 and state.home.inventory.basic_meal==pantry)
    open(items.floor_lamp);R.App.keypressed("1")
    check("home_objects_runtime_switches_lamp_on",items.floor_lamp.lit)
    R.App.keypressed("escape");capture("home-lamp-on")
    open(items.cup);Activity.mousepressed(400,320,1,R)
    check("home_objects_runtime_picks_up_cup",Objects.held(state,p)==items.cup)
    R.App.keypressed("escape");capture("home-carry-empty-cup")
    p.x,p.y=Layout.toWorld(unpack(Layout.get(state).fixtures.sink.approach));state.home.residents.owner.thirst=0
    R.App.keypressed("h");R.App.keypressed("2");advance(1)
    check("home_objects_runtime_fills_cup_after_game_time",items.cup.contents.water==1 and not state.home.residents.owner.activity)
    capture("home-cup-routines",true)
    R.App.keypressed("1");advance(2)
    check("home_objects_runtime_drinks_and_marks_dirty",items.cup.contents.water==0 and items.cup.contents.dirty and state.home.residents.owner.thirst>74)
    R.App.keypressed("3");advance(2)
    check("home_objects_runtime_washes_cup",items.cup.contents.dirty==false and not state.home.residents.owner.activity)
    R.App.keypressed("2");advance(1)
    R.App.keypressed("escape");capture("home-carry-full-cup")
    assert(R.saveCurrent(true));local save=assert(R.Save.load(3));local held,lit
    for _,item in ipairs(save.state.home.furniture.items) do
        if item.kind=="cup" then held=item.location=="carried" and item.holderId=="owner" and item.contents.water==1 end
        if item.kind=="floor_lamp" then lit=item.lit end
    end
    check("home_objects_runtime_saves_contents_and_light",held and lit)
    p.x,p.y=Layout.toWorld(unpack(Layout.get(state).laptop.approach))
    R.App.keypressed("h");R.App.keypressed("right");R.App.keypressed("1")
    check("home_objects_runtime_sets_full_cup_on_counter",items.cup.location=="surface" and items.cup.parentId==0 and items.cup.contents.water==1)
    open(items.cup);R.App.keypressed("1");R.App.keypressed("escape")
    R.App.keypressed("h");R.App.keypressed("right");R.App.keypressed("2")
    check("home_objects_runtime_can_put_cup_away",items.cup.location=="storage" and not items.cup.holderId and items.cup.contents.water==1)
end
return Test
