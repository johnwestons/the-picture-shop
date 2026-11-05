local Test={}
function Test.run(context,check)
    local R=context.appRuntime;if not R then return end
    local previous={};for k,v in pairs(R.state) do previous[k]=v end
    local previousPlayer=R.World.snapshot();local oldSpeed=R.App.gameClockSpeed
    assert(R.startGame(R.Save.newGame(3,{furnishingPreset="empty"}),"smoke"))
    local s,p=R.state,R.World.player;local Layout=require("src.home_layouts");local Calendar=require("src.business_calendar")
    local Furniture=require("src.home_furniture");local Controls=require("src.home_furniture_controls")
    local Activity=require("src.home_activity_controls")
    s.home.weekend.phase="home";s.home.weekend.closedAtHours=44;s.calendar=Calendar.dateFromHours(44)
    s.calendar.elapsed=20/24*s.calendar.secondsPerDay;s.employment.recruiting=false;s.screen="world";p.sceneId="home";R.World._state=s
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
    for _=1,5 do click("previous") end;for _=1,4 do click("next") end
    capture("home-desk-mat-catalog","computer")
    for i=1,2 do click("buy",i);click("confirm");click("cancel") end
    check("home_desk_mat_runtime_checkout",s.home.balanceCents==15250,s.message)
    s.screen="world";R.App.update(Calendar.secondsPerDay(s)/12)
    p.x,p.y=Layout.spawn(s,1);local parcel=assert(require("src.home_shopping").target(p,s))
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,parcel.hoverX,parcel.hoverY);R.App.keypressed("e")
    check("home_desk_mat_runtime_collect",#s.home.furniture.items==3,s.message)
    for index=2,3 do
        local item=s.home.furniture.items[index]
        if item.location=="floor" then p.x,p.y=item.x,item.y end
        local spot=assert(require("src.tests.home_tables_lamp_test").findSpot(s,item.kind,{p},item.id))
        R.App.keypressed("m");for _=2,index do R.App.keypressed("down") end;R.App.keypressed("return");Controls.snapshot(R)
        for _=1,60 do
            local c=Controls.candidate
            if c.x~=spot.x then R.App.keypressed(c.x>spot.x and "left" or "right")
            elseif c.y~=spot.y then R.App.keypressed(c.y>spot.y and "up" or "down") else break end
        end
        Controls.mousepressed(240,626,1,R)
        check("home_desk_mat_runtime_place_"..item.kind,item.location=="floor" and item.x==spot.x and item.y==spot.y and not item.editor,s.message)
        R.App.keypressed("escape")
    end
    local function itemOf(kind)
        for _,item in ipairs(s.home.furniture.items) do if item.kind==kind then return item end end
        error("Missing delivered "..kind)
    end
    local laptop,desk,mat=itemOf("laptop"),itemOf("desk"),itemOf("guest_mat")
    if laptop.location=="floor" then laptop.location="storage" end
    if laptop.location=="surface" then
        local approach=assert(require("src.home_surfaces").approaches(s,laptop)[1]);p.x,p.y=approach.x,approach.y
    else p.x,p.y=desk.x+60,desk.y end
    R.App.keypressed("m");R.App.keypressed("return");Controls.snapshot(R)
    for _=1,16 do
        local c=Controls.candidate;if c.location=="surface" and c.parentId==desk.id and c.slot==1 then break end
        Controls.mousepressed(800,132,1,R)
    end
    p.x,p.y=desk.x+60,desk.y
    Controls.mousepressed(240,626,1,R)
    check("home_desk_runtime_attach_laptop",laptop.location=="surface" and laptop.parentId==desk.id,s.message)
    R.App.keypressed("escape");computer=assert(Layout.targets(p,s).computer);p.x,p.y=computer.x,computer.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,computer.hoverX,computer.hoverY);R.App.keypressed("e")
    check("home_desk_runtime_laptop_opens_on_desk",s.screen=="computer",s.screen)
    R.App.keypressed("escape");local target=assert(Furniture.targets(s,p)["furniture"..mat.id]);p.x,p.y=target.x,target.y
    R.World.updateNetworkPlayer(0,0,0,R.Assets,s,target.hoverX,target.hoverY);R.App.keypressed("e")
    Activity.mousepressed(400,322,1,R)
    check("home_mat_runtime_touch_nap",s.home.residents.owner.activity and s.home.residents.owner.activity.kind=="matrest",s.message)
    R.App.keypressed("backspace");R.App.keypressed("t");capture("home-guest-mat-sleep-menu","activity")
    Activity.mousepressed(400,352,1,R)
    check("home_mat_runtime_touch_sleep",s.home.residents.owner.activity and s.home.residents.owner.activity.kind=="sleepmat",s.message)
    local pose=assert(require("src.home_activity_pose").get(s,p))
    check("home_mat_runtime_sleep_pose_on_mat",pose.kind=="sleeping" and pose.item.id==mat.id and pose.groundX==mat.x)
    R.App.keypressed("escape");capture("home-desk-mat-installed")
    assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
    local savedLaptop,savedMat
    for _,item in ipairs(saved.state.home.furniture.items) do
        if item.kind=="laptop" then savedLaptop=item elseif item.kind=="guest_mat" then savedMat=item end
    end
    check("home_desk_mat_runtime_saved",savedLaptop and savedLaptop.parentId==desk.id and savedMat and savedMat.location=="floor")
    require("src.tests.support.home_dining_runtime").run(R,check)
    assert(R.Save.flush());assert(R.Save.delete(3))
    for k in pairs(s) do s[k]=nil end;for k,v in pairs(previous) do s[k]=v end
    R.World.load(previousPlayer);R.World._state=s;R.Machine.reset();R.Wrapper.clearInstances()
    R.App.gameClockSpeed=oldSpeed;R._weekendScene,R._weekendPromptToken=nil,nil
end
return Test
