local Test={}
function Test.run(context,check)
    local R=context.appRuntime;if not R then return end
    local previous={};for k,v in pairs(R.state) do previous[k]=v end
    local previousPlayer=R.World.snapshot();local oldSpeed=R.App.gameClockSpeed
    assert(R.startGame(R.Save.newGame(3,{furnishingPreset="empty"}),"smoke"))
    local s,p=R.state,R.World.player;local Layout=require("src.home_layouts");local Calendar=require("src.business_calendar")
    local Furniture=require("src.home_furniture");local Controls=require("src.home_furniture_controls")
    local Activity=require("src.home_activity_controls");local Catalog=require("src.home_furniture_catalog")
    s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;s.calendar=Calendar.dateFromHours(44)
    s.calendar.elapsed=20/24*s.calendar.secondsPerDay;s.employment.recruiting=false;s.screen="world";p.sceneId="home";R.World._state=s
    local function advance(minutes) R.App.update(Calendar.secondsPerDay(s)*minutes/1440) end
    local function capture(name,menu)
        local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
        local canvas=love.graphics.newCanvas(960,678);love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        R.World.draw(R.Assets,R.CharacterAssets,s,nil,nil,{})
        if menu=="computer" then R.ComputerScreen.draw(s) elseif menu=="activity" then Activity.draw(R) end
        love.graphics.pop();local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    local computer=assert(Layout.targets(p,s).computer);p.x,p.y=computer.x,computer.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,computer.hoverX,computer.hoverY);R.App.keypressed("e")
    local screen=R.ComputerScreen;local x,y=screen.dropdownCenter();screen.mousepressed(s,x,y,1)
    x,y=screen.tabCenter("furniture");screen.mousepressed(s,x,y,1)
    local function click(name,index) local x,y=screen.homeShopControlCenter(name,index);screen.mousepressed(s,x,y,1) end
    for index=19,22 do
        for _=1,math.ceil(#Catalog.ORDER/4) do click("previous") end
        for _=1,math.floor((index-1)/4) do click("next") end
        if index==21 then capture("home-utilities-catalog","computer") end
        click("buy",(index-1)%4+1);click("confirm");click("cancel")
    end
    check("home_utilities_runtime_buys_four",s.home.balanceCents==7250,s.message)
    s.screen="world";advance(120);p.x,p.y=Layout.spawn(s,1);local parcel=assert(require("src.home_shopping").target(p,s))
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,parcel.hoverX,parcel.hoverY);R.App.keypressed("e")
    check("home_utilities_runtime_collects_four",#s.home.furniture.items==5,s.message)
    for index=2,5 do
        local item=s.home.furniture.items[index];item.location="storage";item.parentId=nil;item.slot=nil
        local spot=assert(require("src.tests.home_tables_lamp_test").findSpot(s,item.kind,{p},item.id))
        local assets={getData=function() return Layout.mask(s.home.apartmentId) end}
        for _,a in ipairs(Furniture.approaches(spot)) do
            if require("src.navigation").isWalkable(assets,a.x,a.y,Furniture.obstacles(s,nil,spot))
                and Furniture.canPlace(s,spot,{{id=1,sceneId="home",x=a.x,y=a.y}}) then p.x,p.y=a.x,a.y;break end
        end
        R.App.keypressed("m");for _=2,index do R.App.keypressed("down") end;R.App.keypressed("return");Controls.snapshot(R)
        for _=1,60 do
            local c=Controls.candidate
            if c.x~=spot.x then R.App.keypressed(c.x>spot.x and "left" or "right")
            elseif c.y~=spot.y then R.App.keypressed(c.y>spot.y and "up" or "down") else break end
        end
        Controls.mousepressed(240,626,1,R)
        check("home_utilities_runtime_places_"..item.kind,item.location=="floor" and item.x==spot.x and item.y==spot.y and not item.editor,s.message)
        R.App.keypressed("escape")
    end
    local function itemOf(kind)
        for _,item in ipairs(s.home.furniture.items) do if item.kind==kind then return item end end
        error("Missing delivered "..kind)
    end
    local wardrobe,cabinet,tv=itemOf("wardrobe"),itemOf("cabinet"),itemOf("old_tv")
    local function interact(item)
        s.screen="world";local t=assert(Furniture.targets(s,p)["furniture"..item.id]);p.x,p.y=t.x,t.y
        R.World.updateNetworkPlayer(0,0,0,R.Assets,s,t.hoverX,t.hoverY);R.App.keypressed("e")
    end
    local function clickCommand(prefix)
        local _,pages=Activity.visibleRows(R)
        for page=1,pages do
            Activity.page=page
            local rows=Activity.visibleRows(R)
            for index,row in ipairs(rows) do
                if row.command:find(prefix,1,true)==1 then
                    Activity.mousepressed(400,300+(index-1)*52+22,1,R);return true
                end
            end
        end
        return false
    end
    -- Real laundry produces the wardrobe supply; no free starter bundle is injected.
    s.screen="world";local laundry=Layout.targets(p,s).home_laundry;p.x,p.y=laundry.x,laundry.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,laundry.hoverX,laundry.hoverY);R.App.keypressed("e");R.App.keypressed("1")
    advance(50);R.App.keypressed("1");advance(5)
    check("home_utilities_runtime_laundry_produces_bundle",s.home.chores.laundry.clean==1,s.message)
    interact(wardrobe);Activity.mousepressed(400,322,1,R)
    check("home_wardrobe_runtime_touch_stores_bundle",wardrobe.contents.clean==1 and s.home.chores.laundry.clean==0,s.message)
    capture("home-wardrobe-storage-menu","activity");Activity.mousepressed(400,322,1,R);advance(2)
    check("home_wardrobe_runtime_touch_changes_clothes",wardrobe.contents.clean==0,s.message)
    interact(tv);assert(clickCommand("object:on:"..tv.id..":"))
    check("home_tv_runtime_touch_switches_on",tv.powered,s.message)
    s.screen="world"
    for _,a in ipairs(Furniture.approaches(tv)) do if require("src.home_utilities").visibleTV(s,{x=a.x,y=a.y},tv,tv) then p.x,p.y=a.x,a.y;break end end
    local target=assert(Furniture.targets(s,p)["furniture"..tv.id]);R.World.updateNetworkPlayer(0,0,0,R.Assets,s,target.hoverX,target.hoverY);R.App.keypressed("e")
    assert(clickCommand("watch:"))
    check("home_tv_runtime_touch_watches",s.home.residents.owner.activity and s.home.residents.owner.activity.kind=="watch",s.message)
    capture("home-tv-watch-menu","activity");R.App.keypressed("escape");capture("home-utilities-installed")
    R.App.keypressed("e");assert(clickCommand("object:off:"..tv.id..":"));advance(0)
    check("home_tv_runtime_viewer_can_switch_off",not tv.powered and not s.home.residents.owner.activity,s.message)
    Activity.mousepressed(400,374,1,R)
    assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
    local savedTV,savedWardrobe
    for _,item in ipairs(saved.state.home.furniture.items) do
        if item.kind=="old_tv" then savedTV=item elseif item.kind=="wardrobe" then savedWardrobe=item end
    end
    check("home_utilities_runtime_saved_power_and_storage",savedTV and not savedTV.powered and savedWardrobe and savedWardrobe.contents.clean==0)
    assert(R.Save.flush());assert(R.Save.delete(3))
    for k in pairs(s) do s[k]=nil end;for k,v in pairs(previous) do s[k]=v end
    R.World.load(previousPlayer);R.World._state=s;R.Machine.reset();R.Wrapper.clearInstances()
    R.App.gameClockSpeed=oldSpeed;R._weekendScene,R._weekendPromptToken=nil,nil
end
return Test
