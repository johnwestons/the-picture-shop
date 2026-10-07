-- Render the real warehouse with isolated in-memory room choices. No App,
-- saves, purchases, or automated tests are loaded by this authoring mode.
local Assets=require("src.assets")
local Characters=require("src.character_assets")
local Config=require("src.config")
local World=require("src.world")
local State=require("src.state")
local Storage=require("src.pallet_storage")
local root=love.filesystem.getSource():gsub("\\","/"):gsub("/$","")
local runId=os.date("%Y%m%d-%H%M%S")
local pending=true
function love.errorhandler(message)
    print("ART REVIEW ERROR "..tostring(message));io.stdout:flush()
    return function() return 1 end
end
function love.load()
    Assets.load();Characters.load()
    World.player={}
    World.bayDoor=require("src.bay_door").new(Config.loadingBay)
    World.truck=require("src.truck").new(Config.truck)
    World.customer=require("src.customer").new(Config.customer)
    World.vendor=require("src.customer").new(Config.vendor)
    World.load({id=1,x=490,y=500,character=Config.player.character})
end
function love.update()
    if not pending then return end
    pending=false
    local state=State.new()
    state.constructionWorker=nil
    state.warehouse.projects={}
    state.jobs.active={}
    for _,id in ipairs({"front_left","front_right"}) do
        state.storage.racks[id.."-rack"]=Storage.rackDefinition(id)
    end
    local function capture(name,view)
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all")
        love.graphics.setCanvas({canvas,stencil=true})
        love.graphics.clear(0.015,0.019,0.025,1)
        if view then
            love.graphics.translate(480,339)
            love.graphics.scale(view.zoom)
            love.graphics.translate(-view.x,-view.y)
        end
        World.draw(Assets,Characters,state)
        love.graphics.setCanvas()
        love.graphics.pop()
        local encoded=canvas:newImageData():encode("png")
        local path=root.."/output/warehouse-expansion-v1/live-acceptance/"..runId.."-art-"..name..".png"
        local file=assert(io.open(path,"wb"));file:write(encoded:getString());file:close()
        canvas:release()
        print("CAPTURE "..path)
    end
    for _,option in ipairs({"storage","floor","breakroom"}) do
        for _,id in ipairs({"front_left","front_right"}) do
            state.warehouse.bays[id]={status="complete",optionId=option}
        end
        World.updateWarehouse(0,state,Assets)
        capture(option)
        capture(option.."-left",{x=200,y=515,zoom=1.6})
        capture(option.."-right",{x=760,y=515,zoom=1.6})
    end
    state.warehouse.bays.front_left={status="complete",optionId="breakroom"}
    state.warehouse.bays.front_right={status="complete",optionId="storage"}
    capture("mixed")
    state.warehouse.bays.front_left={status="complete",optionId="storage"}
    local pallets={}
    for _,id in ipairs({"front_left","front_right"}) do
        for row=1,2 do for column=1,5 do
            pallets[#pallets+1]={id="ART-"..id.."-"..row.."-"..column,number=#pallets+1,
                location="rack",status="raw",wrapped=true,remainingSheets=500,
                paper={marker="art-review"},storage={rackId=id.."-rack",row=row,column=column}}
        end end
    end
    state.jobs.active={{id="ART-REVIEW",sourceSize={width=20,height=16},pallets=pallets}}
    capture("stocked")
    capture("stocked-left",{x=200,y=515,zoom=1.6})
    capture("stocked-right",{x=760,y=515,zoom=1.6})
    -- Show the live lift against the same shelf at both heights, with the
    -- body planted at one fixed point. This is a visual composition only.
    local Layout=require("src.warehouse_layout")
    local Layered=require("src.forklift_layered_presentation")
    state.jobs.active={{id="ART-CARGO",pallets={{id="ART-CARGO",number=1,
        location="on_forklift",status="raw",wrapped=true,remainingSheets=500,
        paper={marker="art-review"}}}}}
    local lift=state.forklift
    lift.owned,lift.operating,lift.operatorPlayerId,lift.carriedPalletId=true,true,1,"ART-CARGO"
    for _,id in ipairs({"front_left","front_right"}) do
        lift.direction=id=="front_left" and "west" or "east"
        lift.x,lift.y,lift.forkHeight=0,0,0
        local scale=Config.forklift.drawScale*Config.forklift.visualScaleMultiplier
        local plan=Layered.plan(lift,{review=true,scale=scale})
        local target=Layout.rackPoint(id,1,3)
        lift.x,lift.y=target.x-plan.loadX,target.y-plan.loadY
        local view={x=id=="front_left" and 200 or 760,y=515,zoom=1.6}
        for _,height in ipairs({0,1}) do
            lift.forkHeight,lift.targetForkHeight=height,height
            capture("lift-"..id.."-"..height,view)
        end
    end
    io.stdout:flush()
    love.event.quit(0)
end
