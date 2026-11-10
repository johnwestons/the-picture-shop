local Test={}
function Test.run(R,check)
    local s,p=R.state,R.World.player;local Furniture=require("src.home_furniture")
    local Layout=require("src.home_layouts");local Controls=require("src.home_furniture_controls")
    local Activity=require("src.home_activity_controls");local Surface=require("src.home_surfaces")
    local function capture(name,computer)
        local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
        local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        R.World.draw(R.Assets,R.CharacterAssets,s,nil,nil,{})
        if computer then R.ComputerScreen.draw(s) end
        love.graphics.pop();local data=canvas:newImageData();local bytes=data:encode("png")
        local f=assert(io.open(folder.."/"..name..".png","wb"));f:write(bytes:getString());f:close()
        bytes:release();data:release();canvas:release()
    end
    s.screen="world";local laptop=assert(Layout.targets(p,s).computer);p.x,p.y=laptop.x,laptop.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,laptop.hoverX,laptop.hoverY);R.App.keypressed("e")
    local screen=R.ComputerScreen;local x,y=screen.dropdownCenter();screen.mousepressed(s,x,y,1)
    x,y=screen.tabCenter("furniture");screen.mousepressed(s,x,y,1)
    local function click(name,index) local x,y=screen.homeShopControlCenter(name,index);screen.mousepressed(s,x,y,1) end
    for _=1,math.ceil(#require("src.home_furniture_catalog").ORDER/4) do click("previous") end
    for _=1,3 do click("next") end
    capture("home-tables-catalog",true)
    local before=s.home.balanceCents;local count=#s.home.furniture.items
    for index=2,4 do click("buy",index);click("confirm");click("cancel") end
    check("home_tables_runtime_buys_three_from_catalog",s.home.balanceCents==before-9775,s.message)
    s.screen="world";R.App.update(require("src.business_calendar").secondsPerDay(s)/12)
    p.x,p.y=Layout.spawn(s,1);local parcel=assert(require("src.home_shopping").target(p,s))
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,parcel.hoverX,parcel.hoverY);R.App.keypressed("e")
    check("home_tables_runtime_receives_three",#s.home.furniture.items==count+3,s.message)
    local byKind={};for i,item in ipairs(s.home.furniture.items) do byKind[item.kind]={item=item,index=i} end
    for _,kind in ipairs({"bedside_table","coffee_table"}) do
        local row=byKind[kind];local item=row.item
        if item.location=="floor" then p.x,p.y=item.x,item.y end
        local spot=assert(require("src.tests.home_tables_lamp_test").findSpot(s,kind,{p},item.id))
        R.App.keypressed("m");for _=2,row.index do R.App.keypressed("down") end;R.App.keypressed("return")
        Controls.snapshot(R)
        assert(Controls.candidate,"Could not edit staged "..kind..": "..tostring(s.message))
        for _=1,40 do
            local c=Controls.candidate
            if c.x~=spot.x then R.App.keypressed(c.x>spot.x and "left" or "right")
            elseif c.y~=spot.y then R.App.keypressed(c.y>spot.y and "up" or "down") else break end
        end
        Controls.mousepressed(240,626,1,R)
        check("home_tables_runtime_places_"..kind,item.location=="floor" and item.x==spot.x and item.y==spot.y and not item.editor,s.message)
        R.App.keypressed("escape")
    end
    local tableItem=byKind.bedside_table.item;local lamp=byKind.desk_lamp.item
    if lamp.location=="floor" then lamp.location="storage" end
    p.x,p.y=tableItem.x+60,tableItem.y
    R.App.keypressed("m");for _=2,byKind.desk_lamp.index do R.App.keypressed("down") end;R.App.keypressed("return");Controls.snapshot(R)
    for _=1,32 do
        local c=Controls.candidate;if c.location=="surface" and c.parentId==tableItem.id and c.slot==1 then break end
        Controls.mousepressed(800,132,1,R)
    end
    Controls.mousepressed(240,626,1,R)
    check("home_tables_runtime_touch_attaches_lamp",lamp.location=="surface" and lamp.parentId==tableItem.id,s.message)
    R.App.keypressed("escape")
    local target=assert(Furniture.targets(s,p)["furniture"..lamp.id]);p.x,p.y=target.x,target.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,target.hoverX,target.hoverY);R.App.keypressed("e")
    Activity.mousepressed(400,322,1,R)
    check("home_tables_runtime_touch_switches_surface_lamp",lamp.lit and Surface.pose(s,lamp).lit,s.message)
    R.App.keypressed("escape");capture("home-tables-installed")
    assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
    check("home_tables_runtime_lit_attachment_saved",saved.state.home.furniture.items[byKind.desk_lamp.index].lit
        and saved.state.home.furniture.items[byKind.desk_lamp.index].parentId==tableItem.id)
end
return Test
