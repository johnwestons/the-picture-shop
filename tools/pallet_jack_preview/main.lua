-- Isolated render check using the game's real assets, motion and world renderer.
local output = assert(os.getenv("PICTURE_SHOP_PREVIEW_OUTPUT"))
local Assets = require("src.assets")
local Characters = require("src.character_assets")
local Jack = require("src.pallet_jack")
local Config = require("src.config")
local World = require("src.world")
local State = require("src.state")
local Jobs = require("src.jobs")
local Logistics = require("src.pallet_logistics")
local Rig = require("src.pallet_jack_presentation")
local Blend = require("src.sprite_blend")
local frame, pending, captures = 1, false, {}
local checks = 0
local state
local cinematic = os.getenv("PICTURE_SHOP_PALLET_JACK_MOVIE") == "1"
local movieFrame = 1
local scenes = {}
for _, viewport in ipairs({{"desktop",960,678},{"phone",1600,720}}) do
    for _, direction in ipairs({"east","southeast","south","southwest","west","northwest","north","northeast"}) do
        for _, loaded in ipairs({false,true}) do
            scenes[#scenes+1]={viewport=viewport,direction=direction,loaded=loaded}
        end
    end
end
local function write(name, value)
    local f=assert(io.open(output.."/"..name,"wb"));f:write(value);f:close()
end
function love.errorhandler(message)
    local detail=tostring(message).."\n"..debug.traceback()
    write("error.txt",detail);print(detail);return function() return 1 end
end
local function prepare()
    local scene=scenes[frame]
    if not scene then
        write("engine-review.txt", "PASS: "..checks.." motion checks; 32 desktop/phone scenes, eight empty/loaded views, true runtime grip blending and texture loading.\n"..table.concat(captures,"\n"))
        love.event.quit(0);return
    end
    love.window.setMode(scene.viewport[2],scene.viewport[3],{vsync=0,resizable=false})
    state=State.new();state.screen="world"
    state.palletJack=Jack.defaultState(Config.palletJack)
    state.palletJack.x,state.palletJack.y=510,475
    state.palletJack.direction=scene.direction
    assert(Jack.mount(state,Config.palletJack,1))
    if scene.loaded then
        local job=assert(Jobs.createOffer({id="JACK-REVIEW",company="Grip review",sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
        Jobs.accept(job);state.jobs.active[1]=job
        Logistics.unload(state,job.id,job.pallets[1].id,Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin)
        job.pallets[1].world.x,job.pallets[1].world.y=510,475
        assert(Jack.lift(state,Config.palletJack,job.pallets[1].id))
    end
    World.load({x=510,y=475})
    World.player.character="rabbit-worker"
    World.player.id=1
    World.player.x,World.player.y=Jack.operatorPosition(state,Config.palletJack)
    -- Exercise fractional turn and gait sampling, rather than static cells.
    local angle=Jack.visualPose(state,Config.palletJack).heading+.13
    for _=1,12 do Jack.move(state,math.cos(angle),math.sin(angle),1/60,Config.palletJack,function() return true end) end
    World.player.x,World.player.y=Jack.operatorPosition(state,Config.palletJack)
    World.player.moving=state.palletJack.moving
end
function love.load()
    assert(love.filesystem.getIdentity():match("^the%-picture%-shop%-test%-"))
    love.graphics.setDefaultFilter("nearest","nearest")
    love.graphics.setFont(love.graphics.newFont(13))
    Assets.load();Characters.load();assert(Characters.assertHealthy())
    local function check(name, okay, detail)
        assert(okay, name..": "..tostring(detail or "failed"));checks=checks+1
    end
    require("src.tests.pallet_jack_motion_test").run({},check)
    require("src.tests.pallet_jack_audit_test").run({},check)
    require("src.tests.player_controller_test").run({},check)
    require("src.tests.pallet_state_test").run({State=State,jobs=Jobs,
        PalletState=require("src.pallet_state"),PalletJack=Jack,config=Config,world=World,assets=Assets},check)
    require("src.tests.warehouse_controls_test").run({State=State},check)
    prepare()
end
function love.update()
    if pending then return end
    if cinematic then
        if captures[movieFrame] then
            movieFrame=movieFrame+1
            if movieFrame>120 then
                write("movie-review.txt","PASS: 120 collision-resolved motion/turn frames rendered by the game.\n")
                love.event.quit(0);return
            end
        end
        local angle=(movieFrame-1)/120*math.pi*2
        Jack.move(state,math.cos(angle),math.sin(angle),1/30,Config.palletJack,function() return true end)
        World.player.x,World.player.y=Jack.operatorPosition(state,Config.palletJack)
        return
    end
    if captures[frame] then frame=frame+1;prepare() end
end
function love.draw()
    if not scenes[frame] or pending then return end
    local scene=scenes[frame]
    local w,h=love.graphics.getDimensions()
    if cinematic then
        if movieFrame>120 then return end
        love.graphics.clear(.11,.14,.17)
        love.graphics.push();love.graphics.translate(w/2,h*.62);love.graphics.scale(3)
        local pose=Jack.visualPose(state,Config.palletJack)
        -- Camera follows the jack to reveal turn and gait continuity clearly.
        love.graphics.translate(-pose.x,-pose.y)
        local behind=math.sin(pose.heading)>=0
        if behind then Rig.drawWorker(Characters,World.player,state) end
        Rig.drawJack(Assets,state)
        if not behind then Rig.drawWorker(Characters,World.player,state) end
        love.graphics.pop();love.graphics.setColor(1,1,1)
        love.graphics.print("Pallet jack: 32 turn views / 16 pushing frames / attached hands",20,20)
        pending=true
        love.graphics.captureScreenshot(function(data)
            local name=string.format("motion-%03d.png",movieFrame)
            write(name,data:encode("png"):getString());captures[movieFrame]=name;pending=false
        end)
        return
    end
    local worldScale=math.min(w/960,h/678)
    love.graphics.clear(.09,.12,.14)
    love.graphics.push()
    love.graphics.translate((w-960*worldScale)/2,0);love.graphics.scale(worldScale)
    World.draw(Assets,Characters,state,-100,-100)
    love.graphics.pop()
    -- Enlarged grip inspection next to the actual game scene.
    love.graphics.push();love.graphics.translate(w*.25,h*.5);love.graphics.scale(3)
    local pose=Jack.visualPose(state,Config.palletJack)
    love.graphics.translate(-pose.x,-pose.y)
    local behind=math.sin(pose.heading)>=0
    if behind then Rig.drawWorker(Characters,World.player,state) end
    Rig.drawJack(Assets,state)
    if not behind then Rig.drawWorker(Characters,World.player,state) end
    love.graphics.pop()
    love.graphics.setColor(1,1,1);love.graphics.print(scene.direction..(scene.loaded and " loaded" or " empty").." / "..scene.viewport[1],15,15)
    pending=true
    love.graphics.captureScreenshot(function(data)
        local name=scene.viewport[1].."-"..scene.direction..(scene.loaded and "-loaded" or "-empty")..".png"
        write(name,data:encode("png"):getString());captures[frame]=name;pending=false
    end)
end
