local Test={}
function Test.run(context,check)
    local R=context.appRuntime;if not R then return end
    local previous={};for k,v in pairs(R.state) do previous[k]=v end
    local previousPlayer=R.World.snapshot();local oldSpeed=R.App.gameClockSpeed
    assert(R.startGame(R.Save.newGame(3,{furnishingPreset="modest"}),"smoke"))
    local state,p=R.state,R.World.player;local Layout=require("src.home_layouts");local Calendar=require("src.business_calendar")
    -- This shared fixture buys a chair, appliances, food and three tables.
    -- Fund the complete catalog journey; insufficient-funds behavior is tested separately.
    state.home.balanceCents=100000
    local Controls=require("src.home_furniture_controls");local Furniture=require("src.home_furniture");local Shopping=require("src.home_shopping")
    state.home.weekend.phase="home";state.home.weekend.closedAtHours=44
    state.calendar=Calendar.dateFromHours(44);state.calendar.elapsed=20/24*state.calendar.secondsPerDay
    state.employment.recruiting=false;p.sceneId="home";local bed=state.home.furniture.items[1];p.x,p.y=bed.x+80,bed.y
    state.screen="world";R.World._state=state
    local Footprint=require("src.floor_footprint")
    p.x,p.y=bed.x-90,bed.y
    local guest={id=2,sceneId="home",x=p.x,y=p.y,facing=1}
    require("src.player_controller").reset(guest,{x=p.x,y=p.y},R.Config.player)
    for _=1,100 do
        R.World.updateNetworkPlayer(1/60,1,0,R.Assets,state)
        R.World.updateRemotePlayer(guest,1/60,1,0,R.Assets,state)
    end
    check("home_furniture_runtime_walking_cannot_cross_bed",p.x<bed.x-5 and Footprint.penetration(Furniture.footprint(bed),p.x,p.y)<=.001)
    check("home_furniture_runtime_guest_collision_matches_host",math.abs(p.x-guest.x)<.001 and math.abs(p.y-guest.y)<.001)
    p.x,p.y=bed.x+80,bed.y
    local mobile=R.extraMobileActions();local furnishButton=false
    for _,action in ipairs(mobile) do if action.key=="m" and action.label=="FURNISH" then furnishButton=true end end
    check("home_furniture_runtime_mobile_has_furnish_action",furnishButton)
    local function capture(name,screen)
        local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR");if not folder then return end
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        if screen then screen.draw(state) else R.World.draw(R.Assets,R.CharacterAssets,state,nil,nil,{});Controls.draw(R) end
        love.graphics.pop();local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    R.App.keypressed("m")
    check("home_furniture_runtime_opens_fitted_controls",state.screen=="home_furnish" and R.App.officeFitsScreen())
    R.App.keypressed("return");local direction=bed.direction;R.App.keypressed("q")
    check("home_furniture_runtime_preview_keeps_original",bed.direction==direction and Controls.candidate.direction~=direction)
    capture("home-furnish-preview")
    R.App.keypressed("return")
    check("home_furniture_runtime_commits_rotation",bed.direction=="south" and not bed.editor,state.message)
    R.App.keypressed("return");R.App.keypressed("p")
    check("home_furniture_runtime_stores_bed",bed.location=="storage" and not bed.editor)
    capture("home-furnish-storage");R.App.keypressed("escape")
    local homeLaptop=assert(Layout.targets(p,state).computer);p.x,p.y=homeLaptop.x,homeLaptop.y
    local laptop=Layout.targets(p,state).computer
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,laptop.hoverX,laptop.hoverY);R.App.keypressed("e")
    local screen=R.ComputerScreen;local x,y=screen.dropdownCenter();screen.mousepressed(state,x,y,1)
    x,y=screen.tabCenter("furniture");screen.mousepressed(state,x,y,1)
    check("home_furniture_runtime_laptop_catalog_available",screen.tab=="furniture")
    capture("home-living-catalog",screen)
    x,y=screen.homeShopControlCenter("buy",2);screen.mousepressed(state,x,y,1)
    capture("home-furniture-checkout",screen)
    local balance=state.home.balanceCents;x,y=screen.homeShopControlCenter("confirm");screen.mousepressed(state,x,y,1)
    check("home_furniture_runtime_pays_household",state.home.balanceCents==balance-2875,state.message)
    R.App.update(Calendar.secondsPerDay(state)/12)
    state.screen="world";local parcel=assert(Shopping.target(p,state));p.x,p.y=Layout.spawn(state,1)
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,parcel.hoverX,parcel.hoverY);R.App.keypressed("e")
    local chair=state.home.furniture.items[10]
    check("home_furniture_runtime_receives_one_chair_instance",#state.home.furniture.items==10 and chair.kind=="chair"
        and (chair.location=="floor" or chair.location=="storage"),state.message)
    if chair.location=="floor" then p.x,p.y=chair.x,chair.y end
    R.App.keypressed("m");Controls.mousepressed(190,518,1,R);Controls.mousepressed(110,274,1,R)
    local grid=assert(Controls.snapshot(R));local selected
    for _,cell in ipairs(grid.cells) do
        local c=Controls.candidate
        if cell.valid and cell.y>165 and cell.y<580 and Furniture.canPlace(state,{id=c.id,kind=c.kind,x=cell.x,y=cell.y,direction=c.direction},{p}) then selected=cell;break end
    end
    assert(selected,"No valid unpacking position near delivery spot")
    Controls.mousepressed(selected.x,selected.y,1,R);Controls.mousepressed(240,626,1,R)
    check("home_furniture_runtime_touch_places_delivery",chair.location=="floor" and chair.x==selected.x and chair.y==selected.y,state.message)
    assert(R.saveCurrent(true));local saved=assert(R.Save.load(3))
    check("home_furniture_runtime_commit_saved",saved.state.home.furniture.items[1].location=="storage" and saved.state.home.furniture.items[10].x==chair.x)
    local Surface=require("src.home_surfaces");local laptopItem=state.home.furniture.items[8]
    local target=assert(Surface.computer(state,p));p.x,p.y=target.x,target.y
    R.App.keypressed("escape");R.App.keypressed("m")
    for _=1,7 do R.App.keypressed("down") end
    R.App.keypressed("return")
    Controls.snapshot(R)
    check("home_surface_runtime_starts_laptop_edit",laptopItem.editor=="owner" and Controls.candidate.location=="surface")
    for _=1,10 do
        local c=Controls.candidate;if c.location=="surface" and c.parentId==0 and c.slot==1 then break end
        Controls.mousepressed(800,132,1,R)
    end
    local counterX,counterY=Layout.toWorld(unpack(Layout.get(state).laptop.approach));p.x,p.y=counterX,counterY
    capture("home-surface-placement")
    Controls.mousepressed(240,626,1,R)
    check("home_surface_runtime_touch_attaches_laptop_to_counter",laptopItem.parentId==0 and laptopItem.slot==1 and not laptopItem.editor,state.message)
    assert(R.saveCurrent(true));saved=assert(R.Save.load(3))
    check("home_surface_runtime_attachment_saved",saved.state.home.furniture.items[8].parentId==0 and saved.state.home.furniture.items[8].slot==1)
    local Controller=require("src.controller");local keys={}
    local controller=Controller.new({pressKey=function(k) keys[#keys+1]=k end,releaseKey=function() end,pressPointer=function() end,
        releasePointer=function() end,screenInfo=function() return "home_furnish" end,menuAction=function() end})
    local pad={isGamepad=function() return true end}
    for _,b in ipairs({"a","y","x","b","dpright","leftshoulder"}) do controller:gamepadpressed(pad,b);controller:gamepadreleased(pad,b) end
    check("home_furniture_controller_place_rotate_store_cancel_grid",table.concat(keys,",")=="return,q,p,escape,right,tab")
    require("src.tests.support.home_objects_runtime").run(R,check)
    require("src.tests.support.home_chores_runtime").run(R,check)
    require("src.tests.support.home_kitchen_runtime").run(R,check)
    require("src.tests.support.home_tables_runtime").run(R,check)
    require("src.tests.support.home_guide_runtime").run(R,check)
    require("src.tests.support.home_sleep_runtime").run(R,check)
    assert(R.Save.flush());assert(R.Save.delete(3))
    for k in pairs(state) do state[k]=nil end;for k,v in pairs(previous) do state[k]=v end
    R.World.load(previousPlayer);R.World._state=state;R.Machine.reset();R.Wrapper.clearInstances()
    R.App.gameClockSpeed=oldSpeed;R._weekendScene,R._weekendPromptToken=nil,nil
end
return Test
