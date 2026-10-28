-- Deterministic captures through the production loaders, lab and world renderer.
-- This mode does not load or save a shop.
local output = assert(os.getenv("PICTURE_SHOP_ANIMATION_OUTPUT"))
assert(love.filesystem.getIdentity():match("^the%-picture%-shop%-test%-"), "Isolated review identity required")
io.stdout:setvbuf("no")
function love.errorhandler(message)
    local detail = tostring(message) .. "\n" .. debug.traceback()
    local file = io.open(output .. "/error.txt", "wb")
    if file then file:write(detail); file:close() end
    print(detail)
    return function() return 1 end
end
local Assets = require("src.assets")
local Characters = require("src.character_assets")
local State = require("src.state")
local World = require("src.world")
local Renderer = require("src.world_renderer")
local Machine = require("src.machine")
local PaperWork = require("src.paper_work")
local MachineScreen = require("src.screens.machine_screen")
local CutterPresentation = require("src.screens.cutter_presentation")
local CutterMotion = require("src.screens.cutter_motion")
local Protocol = require("src.net.protocol")
local Codec = require("src.net.codec")
local Lab = require("src.screens.sprite_motion_lab")
local Catalog = require("src.worker_catalog")
local Config = require("src.config")
local TechnicianPose = require("src.technician_pose")
local TechnicianReplica = require("src.technician_replica")
local Employees = require("src.employees")
local Fleet = require("src.machine_fleet")
local WorkPose = require("src.employee_work_presentation")
local EmployeePose = require("src.employee_pose")
local Jack = require("src.pallet_jack")
local JackPresentation = require("src.pallet_jack_presentation")
local encode = require("tools.performance_probe.json")
local queue, shot, pending, peak, sourcePeak = {}, 1, false, 0, 0
local state, remotes
if os.getenv("PICTURE_SHOP_ANIMATION_CAT_PROPOSAL")=="1" then
    -- Only this isolated review entry point can opt into unapproved artwork.
    local staged=assert(love.filesystem.load("output/animation-overhaul/cat-south-install-preview/src/worker_walk_art.lua"))()
    Config.characters["cat-worker"].walk_south=staged.paths["cat-worker"].walk_south
    require("src.cat_worker_anchors")["cat-worker"].walk_south=staged.anchors["cat-worker"].walk_south
    require("src.cat_worker_metrics")["cat-worker"].walk_south=staged.metrics["cat-worker"].walk_south
end
if os.getenv("PICTURE_SHOP_ANIMATION_PLAYER_NORTH_PROPOSAL")=="1" then
    local stagedPath=os.getenv("PICTURE_SHOP_ANIMATION_PLAYER_NORTH_PROPOSAL_FILE")
        or "output/animation-overhaul/player-north-passing-preview/src/player_walk_art.lua"
    local staged=assert(love.filesystem.load(stagedPath))()
    Config.characters["rabbit-worker"].walk_north=staged.paths["rabbit-worker"].walk_north
    require("src.character_anchors")["rabbit-worker"].walk_north=staged.anchors["rabbit-worker"].walk_north
    require("src.character_metrics")["rabbit-worker"].walk_north=staged.metrics["rabbit-worker"].walk_north
end
local moments = {.04, .13, .24, .36, .47, .58, .73, .91}
local directions={{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}
for _, viewport in ipairs({{name="desktop",width=960,height=678}, {name="mobile",width=1600,height=720}}) do
    for frame, time in ipairs(moments) do
        queue[#queue+1] = {viewport=viewport, kind="high-five", frame=frame, time=time}
    end
    for _,role in ipairs({"host","guest"}) do
     for frame=1,8 do
        queue[#queue+1]={viewport=viewport,kind="employee-walk",character="cat-worker",frame=frame,
            role=role,action="walk-south-"..role}
     end
    end
    for _,role in ipairs({"host","guest"}) do
     for frame=1,8 do
      queue[#queue+1]={viewport=viewport,kind="player-walk",character="rabbit-worker",frame=frame,
        role=role,action="walk-north-"..role}
     end
    end
    for _, profile in ipairs(Catalog.profiles) do
        for frame=1,8 do
            queue[#queue+1] = {viewport=viewport, kind="directions", character=profile.character, frame=frame}
        end
        for _, action in ipairs({"work_cutter", "work_press", "work_wrapping", "break_eat", "break_water", "break_coffee"}) do
            queue[#queue+1] = {viewport=viewport, kind="action", character=profile.character, action=action, frame=1}
        end
    end
    for _,character in ipairs({"tinker-fox-worker","ferret-engineer-worker"}) do
     for _,task in ipairs({{action="work_cutter",model="polar_115"},{action="work_press",model="heidelberg_10x15"},
         {action="work_wrapping",model="skid_wrapper"}}) do
      for _,role in ipairs({"host","guest"}) do
       for frame=1,8 do
        queue[#queue+1]={viewport=viewport,kind="work-contact",character=character,frame=frame,
            workAction=task.action,model=task.model,role=role,action=task.action.."-"..role.."-contact"}
       end
      end
     end
    end
    for _,species in ipairs({"mouse","lizard"}) do
        for frame=1,16 do
            queue[#queue+1]={viewport=viewport,kind="technician-idle",species=species,
                character=Config.technician.characters[species],frame=frame,direction=directions[(frame-1)%8+1],blink=frame>8}
        end
    end
    for _,species in ipairs({"mouse","lizard"}) do
     for _,view in ipairs({{name="north",direction={0,-1}},{name="south",direction={0,1}},
         {name="east",direction={1,0}}}) do
      for _,role in ipairs({"host","guest"}) do
        for frame=1,8 do
            queue[#queue+1]={viewport=viewport,kind="technician-walk-"..role,species=species,
                character=Config.technician.characters[species],frame=frame,direction=view.direction,
                action="technician-walk-"..role.."-"..view.name}
        end
      end
     end
    end
    for _,view in ipairs({{name="east",x=1,y=0},{name="northwest",x=-1/math.sqrt(2),y=-1/math.sqrt(2)}}) do
     for _,role in ipairs({"host","guest"}) do
      for frame=1,8 do
       queue[#queue+1]={viewport=viewport,kind="jack",character="rabbit-worker",frame=frame,
          role=role,view=view,action="jack-"..role.."-"..view.name}
      end
     end
    end
    for _,direction in ipairs(directions) do
        local view=require("src.character_animation").authoredDirection(direction[1],direction[2])
        for frame=1,10 do
            queue[#queue+1]={viewport=viewport,kind="construction",character="mechanic-raccoon",frame=frame,
                direction=direction,view=view,action="construction-"..view}
        end
    end
    local cutterMotionSamples = {
        { name="loaded-home-baseline", home=true },
        { name="cutting-depth-0.6" },
        { name="estop-stopped-rising-depth-0.6", stop="emergency", cutPhase=0.7 },
        { name="estop-stopped-depth-0.6", stop="emergency" },
        { name="barrier-stopped-depth-0.6", stop="barrier" },
        { name="reset-estop-start-depth-0.6", stop="emergency", reset=true },
        { name="reset-estop-mid-depth-0.3", stop="emergency", reset=true, resetElapsed=0.075 },
        { name="home-after-estop-reset", stop="emergency", reset=true, resetElapsed=0.35 },
        { name="reset-barrier-start-depth-0.6", stop="barrier", reset=true },
        { name="reset-barrier-mid-depth-0.3", stop="barrier", reset=true, resetElapsed=0.075 },
        { name="home-after-barrier-reset", stop="barrier", reset=true, resetElapsed=0.35 },
    }
    for _, role in ipairs({"host", "guest"}) do
        for _, sample in ipairs(cutterMotionSamples) do
            queue[#queue+1] = { viewport=viewport, kind="machine-motion", role=role,
                sample=sample.name, stop=sample.stop, reset=sample.reset,
                resetElapsed=sample.resetElapsed, cutPhase=sample.cutPhase }
        end
    end
end
local focus=os.getenv("PICTURE_SHOP_ANIMATION_REVIEW_FOCUS") or "all"
if focus=="jack" or focus=="player-walk" or focus=="employee-walk" or focus=="construction"
    or focus=="machine-motion" then
    local selected={};for _,scene in ipairs(queue) do if scene.kind==focus then selected[#selected+1]=scene end end
    queue=selected
end

local function write(name, text)
    local file = assert(io.open(output .. "/" .. name, "wb"))
    file:write(text); file:close()
end

local machineTextureAuditWritten=false
local function recordMachineTextureAudit()
    if machineTextureAuditWritten then return end
    local limits={}
    for key,value in pairs(love.graphics.getSystemLimits()) do
        if type(value)=="number" or type(value)=="string" or type(value)=="boolean" then
            limits[tostring(key)]=value
        end
    end
    local images,maxArea,maxTexture={},0,nil
    for name,image in pairs(Assets.images) do
        local width,height=image:getDimensions()
        local area=width*height
        images[#images+1]={name=name,width=width,height=height,rgbaBytes=area*4}
        if area>maxArea then maxArea,maxTexture=area,images[#images] end
    end
    table.sort(images,function(a,b)return a.name<b.name end)
    local stats={}
    for key,value in pairs(love.graphics.getStats()) do
        if type(value)=="number" or type(value)=="string" or type(value)=="boolean" then
            stats[tostring(key)]=value
        end
    end
    write("machine-motion-texture-audit.json",encode({activePack=Assets.activePackName(),
        graphicsLimits=limits,graphicsStats=stats,estimatedLoadedImageBytes=Assets.textureBytes(),
        largestLoadedImage=maxTexture,loadedImages=images,
        viewports={{name="desktop",width=960,height=678},{name="mobile",width=1600,height=720}}}))
    machineTextureAuditWritten=true
end

local function prepare()
    local scene = queue[shot]
    if not scene then
        assert(Characters.assertHealthy())
        local description=focus=="construction" and "Construction visitor eight-view gait and planted neutral/brief alternate poses."
            or focus=="employee-walk" and "Cat south-walk canonical phases through host and guest employee renderers."
            or focus=="player-walk" and "Player north-walk canonical phases through local and remote renderers."
            or focus=="jack" and "Mid-drawing pallet-jack gait samples through host and guest pose packets in east and northwest views."
            or focus=="machine-motion" and "Cutter cut, safety-stop, reset-return, and home states through production scene rendering; host and decoded guest views."
            or "High-five, employee gait/work/break, technician idle/walk, and pallet-jack host/guest samples."
        write("engine-review.txt", string.format("PASS: %d captures through production renderers. %s Desktop and landscape phone layouts.\nPeak resident registered character textures: %.2f MiB. Peak warehouse source textures: %.2f MiB. No shop save access.\n", #queue,description, peak / 1048576,sourcePeak/1048576))
        love.event.quit(0)
        return
    end
    if scene.kind=="machine-motion" then
        if Assets.activePackName()~="cutter" then assert(Assets.activatePack("cutter"),"Cutter asset pack failed") end
        assert(Assets.get("polarOperatorConsole") and Assets.get("cutterBlade") and Assets.get("cutterClamp"),
            "Required cutter scene textures are missing")
        recordMachineTextureAudit()
    else
        if Assets.activePackName()~=nil then assert(Assets.activatePack(nil),"World asset pack restore failed") end
        assert(Assets.get("warehouse") and Assets.get("polarDirections") and Assets.get("loadedPaperPalletDirections"),
            "Required world textures were lost while restoring the base asset set")
    end
    love.window.setMode(scene.viewport.width, scene.viewport.height, {vsync=0,resizable=false})
    state.technicianVisit=nil
    state._technicianPose=nil
    if scene.kind=="construction" then
        state=State.new();state.screen="world";state.money=20000
        assert(require("src.warehouse_upgrades").purchase(state,"front_left","floor","ANIMATION-CONSTRUCTION",0))
        local construction=require("src.warehouse_construction")
        local options={nowHours=0,canMove=function() return true end,workPoint=function() return 350,500 end}
        construction.update(state,0,options);options.nowHours=2;construction.update(state,0,options)
        local worker=assert(construction.worker(state))
        worker.x,worker.y=500,555
        worker.moving=scene.frame<=8
        worker.direction=scene.view;worker.facingX,worker.facingY=scene.direction[1],scene.direction[2]
        worker.animationDistance=((scene.frame-1)%8)*construction.PIXELS_PER_FRAME+.5
        worker.idleTime=scene.frame==10 and 2/.65-.05 or 0
        local frame=construction.frame(worker)
        local expected=worker.moving and scene.frame or scene.frame==10 and 2 or 1
        assert(frame==expected,"Construction animation phase drift")
        local action=worker.moving and "walk" or "idle"
        local path="assets/source/warehouse-expansion-v1/mechanic-raccoon/"..action
            ..(scene.view=="east" and "" or "_"..scene.view)..".png"
        local width,height=require("src.image_contract").dimensions(path)
        assert(width==512*(worker.moving and 8 or 2) and height==512,"Construction source frame contract")
        write(string.format("%s-%s-%d-pose.json",scene.viewport.name,scene.action,scene.frame),
            encode({action=action,frame=frame,direction=worker.direction,path=path,idleClock=worker.idleTime,
                distance=worker.animationDistance,x=worker.x,y=worker.y}))
        World.player.x,World.player.y=920,630
        World.player.moving=false;World.player.highFiveAnimation,World.player.taskAction=nil,nil;remotes={}
    elseif scene.kind=="employee-walk" then
        state=State.new();state.screen="world"
        local distance=(scene.frame-1)*Catalog.motion.walkPixelsPerFrame+.5
        local worker={id="EMP-1",name="Walk review",character=scene.character,visible=true,
            x=500,y=440+distance,intentX=0,intentY=1,moving=true,phase="walking",
            distance=distance,idleClock=0,sceneId="warehouse"}
        Employees.ensure(state).staff={worker}
        if scene.role=="guest" then
            local protocol=require("src.net.protocol")
            local packet=assert(protocol.encode("employee_snapshot",{sessionId="walk-review",serverTick=1,
                employees=EmployeePose.capture(Employees.actors(state))}))
            state._employeePoses=assert(EmployeePose.actors(assert(protocol.decode(packet)).payload.employees))
        end
        local entry=assert(Employees.actors(state)[1])
        local action,frame,mirror=require("src.employee_renderer").pose(entry,Characters)
        local ax,ay=Characters.getAnchor(scene.character,action,frame)
        assert(action=="walk_south" and frame==scene.frame and mirror==1,"Employee gait phase drift")
        write(string.format("%s-%s-%s-%d-pose.json",scene.viewport.name,scene.character,scene.action,scene.frame),
            encode({action=action,frame=frame,mirror=mirror,x=entry.actor.x,y=entry.actor.y,
                distance=entry.actor.distance,anchor={ax,ay},scale=.30*Characters.getNormalization(scene.character,action),
                path=Characters.metadata[scene.character][action].path}))
        World.player.x,World.player.y=920,630
        World.player.highFiveAnimation,World.player.taskAction=nil,nil
        World.player.moving=false;remotes={}
    elseif scene.kind=="player-walk" then
        state=State.new();state.screen="world"
        local distance=(scene.frame-1)*Config.player.walkPixelsPerFrame+.5
        local actor={id=1,name="Walk operator",character="rabbit-worker",x=500,y=555-distance,
            intentX=0,intentY=-1,velocityX=0,velocityY=0,moving=true,animationDistance=distance,idleClock=0,facing=1}
        if scene.role=="guest" then
            World.player.id,World.player.x,World.player.y=2,920,630
            World.player.moving=false
            remotes={actor}
        else
            for key,value in pairs(actor) do World.player[key]=value end
            remotes={}
        end
        World.player.highFiveAnimation,World.player.taskAction=nil,nil
    elseif scene.kind=="jack" then
        state=State.new();state.screen="world"
        local jack=Jack.ensure(state,Config.palletJack)
        jack.x,jack.y,jack.direction=500,540,scene.view.name
        assert(Jack.mount(state,Config.palletJack,1))
        local distance=(scene.frame-1+.25)*Config.palletJack.gaitPixelsPerFrame
        Jack.followNavigation(state,500+scene.view.x*distance,540+scene.view.y*distance,.1,Config.palletJack)
        if scene.role=="guest" then
            local protocol=require("src.net.protocol")
            local packet=assert(protocol.encode("pallet_jack_snapshot",{sessionId="jack-review",serverTick=1,
                jack=World.networkPalletJackSnapshot(state),machines=World.networkMachinePoseSnapshot(state)}))
            local decoded=assert(protocol.decode(packet)).payload
            state=State.new();state.screen="world"
            assert(World.applyNetworkPalletJackSnapshot(state,decoded.jack,decoded.machines))
        end
        local x,y=Jack.operatorPosition(state,Config.palletJack)
        local actor={id=1,name="Jack operator",character="rabbit-worker",x=x,y=y,moving=true,intentX=scene.view.x,intentY=scene.view.y}
        if scene.role=="guest" then
            World.player.id=2;World.player.x,World.player.y=920,630;remotes={actor}
        else
            World.player.id=1;World.player.x,World.player.y=x,y;remotes={}
        end
        World.player.highFiveAnimation=nil
        local poses,pose=JackPresentation.workerPoses(Characters,actor,state)
        local samples={}
        for _,sample in ipairs(poses) do
            local qx,qy,qw,qh=sample.quad:getViewport()
            samples[#samples+1]={frame=qx/qw+1,weight=sample.weight,anchorX=sample.anchorX,anchorY=sample.anchorY}
        end
        write(string.format("%s-%s-%d-pose.json",scene.viewport.name,scene.action,scene.frame),encode({
            distance=pose.distance,heading=pose.heading,clock=state.palletJack.animationClock,samples=samples}))
    elseif scene.kind == "work-contact" then
        state=State.new();state.screen="world";state.money=40000
        if scene.model=="heidelberg_10x15" then assert(Fleet.buy(state,"dealer",3)) end
        local applicant=assert(Employees.createApplicant(state,0))
        assert(Employees.requestResume(state,applicant.id,0));Employees.advance(state,.5)
        assert(Employees.command(state,{kind="offer_employee",applicationId=applicant.id,
            expectedRevision=applicant.revision,wageCents=math.max(2400,applicant.requestedWage),
            days=31,startHour=9,endHour=17},.5))
        Employees.advance(state,1.25)
        assert(Employees.command(state,{kind="hire_employee",applicationId=applicant.id,
            expectedRevision=applicant.revision},1.25))
        local worker=state.employment.staff[1]
        worker.character,worker.visible,worker.moving=scene.character,true,false
        worker.x,worker.y,worker.phase,worker.idleClock=600,560,"working",0
        local machine=assert(Fleet.installed(state,scene.model))
        worker.assignment={machineId=machine.id,machineModel=scene.model}
        local context=World.employeeContext(state,Assets)
        local point=assert(context.operatorPoint(machine.id,worker),"No real machine operator point")
        -- Match the wire's existing 0.01px precision for deterministic pixel
        -- comparisons; the reachable production point changes by <0.005px.
        worker.x,worker.y=math.floor(point.x*100+.5)/100,math.floor(point.y*100+.5)/100
        local pose=context.machinePose(machine.id)
        worker.intentX,worker.intentY=pose.x-worker.x,pose.y-worker.y
        worker.workPose=WorkPose.encode(scene.workAction,scene.frame)
        if scene.role=="guest" then
            local protocol=require("src.net.protocol")
            local packet=assert(protocol.encode("employee_snapshot",{sessionId="work-contact",serverTick=1,
                employees=EmployeePose.capture(Employees.actors(state))}))
            state._employeePoses=assert(EmployeePose.actors(assert(protocol.decode(packet)).payload.employees))
        end
        World.player.x,World.player.y=920,630
        World.player.highFiveAnimation=nil
        remotes={}
    elseif scene.kind == "machine-motion" then
        state=State.new();state.screen="world"
        local machine=Machine.forId("MCH-ANIMATION-MOTION-CAPTURE")
        machine.reset(state)
        local paper,pallet=PaperWork.createStockPaper()
        pallet.activeLift,pallet.requiredLifts,pallet.remainingSheets=1,1,1000
        machine.paper,machine.pallet,machine.loaded=paper,pallet,true
        machine.legacyPaper=false
        machine.clamp,machine.clampProgress=true,1
        machine.step,machine.progress,machine.bladeProgress="armed",0,0
        if scene.sample=="loaded-home-baseline" then
            machine.clamp,machine.clampProgress=false,0
            machine.step,machine.progress,machine.paperTravel="loaded",0,.35
        else
            machine.update(machine.cycleTime*(scene.cutPhase or .3),state)
            assert(machine.step=="cutting" and math.abs(machine.bladeProgress-.6)<.00001,
                "Cutter did not reach the requested 0.6 blade depth")
        end
        if scene.stop=="emergency" then
            assert(machine.emergencyStop(state),"Cutter E-stop did not engage")
        elseif scene.stop=="barrier" then
            assert(machine.setBarrier(false,state),"Cutter light barrier did not interrupt the cycle")
        end
        if scene.reset then
            assert(machine.resetSafety(state),"Cutter safety reset did not start")
            if scene.resetElapsed then machine.update(scene.resetElapsed,state) end
        end
        local expectedDepth=scene.sample:match("depth%-0%.3$") and .3
            or scene.sample:match("depth%-0%.6$") and .6 or 0
        if expectedDepth>0 then
            assert(math.abs(machine.bladeProgress-expectedDepth)<.00001,
                "Cutter sample depth does not match its requested physical position")
        else
            assert(machine.step=="loaded" and machine.bladeProgress==0,
                "Cutter reset did not return the blade home")
        end
        local authoritativeView=machine.networkView(state,false)
        local model=machine
        local deliveredView=authoritativeView
        if scene.role=="guest" then
            local wireView={}
            for key,value in pairs(authoritativeView) do wireView[key]=value end
            wireView.memoryCentiInch=Codec.array(authoritativeView.memoryCentiInch)
            local packet=assert(Protocol.encode("cutter_snapshot",{
                sessionId="machine-motion-review",serverTick=shot,resourceId="cutter",
                resourceRevision=machine.runtimeRevision,view=wireView,
            }))
            local envelope=assert(Protocol.decode(packet))
            deliveredView=envelope.payload.view
            local presentation=CutterPresentation.new()
            assert(presentation:accept(deliveredView),"Guest rejected the current cutter snapshot")
            model=presentation:model(state,deliveredView)
        end
        assert(math.abs((model.bladeProgress or 0)-expectedDepth)<.001,
            "Host/guest cutter blade depth does not match the requested capture state")
        local visualProgress=model.step=="cutting" and model.progress/model.cycleTime
            or ((model.step=="blocked" or model.step=="resetting") and (model.bladeProgress or 0)*.5 or 0)
        local bladeSourceCell,bladeSourceOffsetY=CutterMotion.sample("cutterBlade",visualProgress)
        local clampSourceCell,clampSourceOffsetY=CutterMotion.sample("cutterClamp",model.clampProgress)
        local filename=string.format("%s-machine-%s-%s",scene.viewport.name,scene.role,scene.sample)
        write(filename.."-pose.json",encode({viewport=scene.viewport,role=scene.role,sample=scene.sample,
            cutPhase=scene.cutPhase,
            visualProgress=visualProgress,
            stop=scene.stop,step=model.step,progress=model.progress,cycleTime=model.cycleTime,
            physicalBladeDepth=model.bladeProgress,
            bladeMotion={sourceCell=bladeSourceCell,sourceOffsetY=bladeSourceOffsetY},
            clampMotion={sourceCell=clampSourceCell,sourceOffsetY=clampSourceOffsetY},clamp=model.clamp,
            clampProgress=model.clampProgress,barrierClear=authoritativeView.barrierClear,
            emergencyStopped=authoritativeView.emergencyStopped,networkView=authoritativeView,
            deliveredView=deliveredView,sourceAtlases={
                clamp={width=Assets.get("cutterClamp"):getWidth(),height=Assets.get("cutterClamp"):getHeight()},
                blade={width=Assets.get("cutterBlade"):getWidth(),height=Assets.get("cutterBlade"):getHeight()},
            },drawRect={x=60,y=59,width=840,height=560}}))
        scene.machineModel=model
    elseif scene.kind == "high-five" then
        World.player.x, World.player.y, World.player.character = 470, 555, "rabbit-worker"
        World.player.id, World.player.moving, World.player.taskAction = 1, false, nil
        World.player.highFiveAnimation = {elapsed=scene.time*.95,duration=.95,partnerX=530,partnerId=2}
        remotes = {{id=2,name="Partner",character="rabbit-worker",x=530,y=555,facing=-1,
            intentX=-1,intentY=0,moving=false,highFiveAnimation={elapsed=scene.time*.95,duration=.95,partnerX=470,partnerId=1}}}
    elseif scene.kind:match("^technician%-") then
        World.player.x,World.player.y=420,555
        World.player.highFiveAnimation=nil
        remotes={}
        state.technicianVisit={species=scene.species,kind=scene.species=="mouse" and "cutter" or "windmill",
            status="entering",visible=true,inMotion=false,x=500,y=555,intentX=scene.direction[1],intentY=scene.direction[2],
            animationDistance=0,idleClock=scene.blink and 2/.65-.07 or 0,animationClock=0,
            route={{x=500,y=555},{x=600,y=555}},waypoint=2,serviceTimer=0}
        if scene.kind~="technician-idle" then
            local actor=state.technicianVisit
            local distance=(scene.frame-1)*Config.technician.walkPixelsPerFrame+.5
            local dx,dy=scene.direction[1],scene.direction[2]
            local length=math.sqrt(dx*dx+dy*dy)
            dx,dy=dx/length,dy/length
            local startX=dx>0 and 450 or dx<0 and 600 or 500
            local startY=dy>0 and 430 or dy<0 and 555 or 500
            local function place(traveled)
                actor.animationDistance=traveled
                actor.x,actor.y=startX+dx*traveled,startY+dy*traveled
            end
            place(distance)
            actor.inMotion=true
            if scene.kind=="technician-walk-guest" then
                place(distance-6.5)
                TechnicianReplica.accept(state,assert(TechnicianPose.actor(TechnicianPose.capture(actor))))
                place(distance+6.5)
                TechnicianReplica.accept(state,assert(TechnicianPose.actor(TechnicianPose.capture(actor))))
                TechnicianReplica.update(state,TechnicianReplica.DURATION/2)
                state.technicianVisit=nil
            end
        end
    else
        for index, name in ipairs(Characters.characterNames()) do
            if name == scene.character then Lab.selected = index end
        end
        Characters.retainCharacters({[scene.character]=true})
        Lab.mode = scene.kind == "action" and "actions" or "directions"
        Lab.distance, Lab.clock = (scene.frame-1)*Catalog.motion.walkPixelsPerFrame+.01, .5
        if scene.action then
            for index, action in ipairs(Characters.actions(scene.character)) do
                if action == scene.action then Lab.selectedAction = index end
            end
        end
    end
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    Assets.load(); Characters.load()
    assert(Characters.assertHealthy())
    state = State.new(); state.screen="world"
    World.load({x=470,y=555}); Lab.enter(Characters)
    local probeWorker={id="EMP-ANIMATION-PROBE",x=600,y=560,sceneId="warehouse",visible=true}
    local probeContext=World.employeeContext(state,Assets)
    local probe={}
    for _,x in ipairs({650,655,660,665,670}) do for _,y in ipairs({405,411,415,420}) do
        probe[#probe+1]={x=x,y=y,walkable=require("src.navigation").isWalkable(Assets,x,y,probeContext.obstacles(probeWorker))}
    end end
    write("cutter-contact-navigation-probe.json",encode(probe))
    local routeProbe={}
    local Navigator=require("src.npc_navigation")
    local Navigation=require("src.navigation")
    for _,start in ipairs({{x=600,y=560},{x=500,y=500},{x=760,y=450},{x=700,y=520}}) do
        local route,goal=Navigator.findPath(start,{{x=660,y=411}},
            {assets=probeContext.assets,obstacles=function() return probeContext.obstacles(probeWorker) end})
        local prior,length=start,0
        for _,point in ipairs(route or {}) do
            assert(Navigation.canTraverse(probeContext.assets,prior.x,prior.y,point.x,point.y,
                probeContext.obstacles(probeWorker)),"Contact route crosses an obstacle")
            length=length+math.sqrt((point.x-prior.x)^2+(point.y-prior.y)^2);prior=point
        end
        routeProbe[#routeProbe+1]={start=start,goal=goal,reachable=route~=nil,route=route,length=length}
    end
    write("cutter-contact-reachable-route-probe.json",encode(routeProbe))
    local inventory = {}
    for _, name in ipairs(Characters.characterNames()) do
        local actions = {}
        for _, action in ipairs(Characters.actions(name)) do
            local entry = Characters.metadata[name][action]
            actions[#actions+1] = {action=action,path=entry.path,frames=entry.frameCount,frameSize=entry.frameSize}
        end
        inventory[#inventory+1] = {character=name,actions=actions}
    end
    write("character-inventory.json", encode(inventory))
    prepare()
end

function love.draw()
    local scene = queue[shot]
    if not scene then return end
    local factor = math.min(scene.viewport.width/Config.baseWidth, scene.viewport.height/Config.baseHeight)
    love.graphics.clear(.025,.035,.05)
    love.graphics.push("all")
    love.graphics.translate((scene.viewport.width-Config.baseWidth*factor)/2,
        (scene.viewport.height-Config.baseHeight*factor)/2)
    love.graphics.scale(factor)
    Characters.beginFrame()
    if scene.kind=="machine-motion" then
        MachineScreen.drawCutterScene(Assets,scene.machineModel,{x=60,y=59,width=840,height=560})
    elseif scene.kind == "high-five" or scene.kind=="work-contact" or scene.kind=="jack" or scene.kind=="player-walk" or scene.kind=="employee-walk" or scene.kind=="construction" or scene.kind:match("^technician%-") then Renderer.draw(World,Assets,Characters,state,nil,nil,remotes)
    else Lab.draw(Characters) end
    peak = math.max(peak,Characters.textureBytes())
    sourcePeak=math.max(sourcePeak,require("src.warehouse_renderer").sourceTextureBytes())
    Characters.endFrame()
    love.graphics.pop()
    if pending then return end
    pending = true
    local name = scene.kind=="machine-motion"
        and string.format("%s-machine-%s-%s.png",scene.viewport.name,scene.role,scene.sample)
        or string.format("%s-%s-%s-%d.png", scene.viewport.name, scene.character or "rabbit-pair", scene.action or scene.kind, scene.frame)
    love.graphics.captureScreenshot(function(data)
        local png = data:encode("png")
        write(name,png:getString())
        png:release(); data:release()
        shot, pending = shot+1, false
        prepare()
    end)
end

function love.keypressed(key)
    if key == "escape" then love.event.quit(1) end
end
