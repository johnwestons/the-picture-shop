-- Isolated warehouse camera experiment. It never loads the shop runtime or a save.
local Geometry = require("src.warehouse_perspective_geometry")
local Config = require("src.config")
local FP = require("src.commute.first_person_camera")
local Lab = {}
local g = love.graphics
local ROOM_EXPANSION = 1.55
local ROOM_CENTER_X, ROOM_CENTER_Z = Geometry.floorPoint(480,
    (Geometry.edge(480) + Geometry.HEIGHT) * .5)
local format = {{"VertexPosition", "float", 2}, {"WorldHeight", "float", 1},
    {"VertexTexCoord", "float", 2}}
local perspectiveSource = assert(love.filesystem.read("src/commute/perspective.glsl"))
local shaderSource = perspectiveSource .. [[
#ifdef VERTEX
attribute float WorldHeight;
extern vec2 orbitFocus;
extern vec2 screenAnchor;
extern float orbitYaw;
extern float orbitElevation;
extern float orbitScale;
extern float modelYaw;
extern float environmentScale;
extern vec2 environmentCenter;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    float mc=cos(modelYaw), ms=sin(modelYaw);
    vec3 world = vec3(vertex_position.x*mc-vertex_position.y*ms, WorldHeight,
        vertex_position.x*ms+vertex_position.y*mc);
    world.xz = environmentCenter + (world.xz-environmentCenter)*environmentScale;
    if (firstPerson) return riderProjection(transform_projection, world);
    vec2 delta = world.xz - orbitFocus;
    float c = cos(orbitYaw), s = sin(orbitYaw);
    float right = -delta.x * s + delta.y * c;
    float forward = delta.x * c + delta.y * s;
    vec2 pixel = screenAnchor + vec2(right,
        -forward * sin(orbitElevation) - world.y * cos(orbitElevation)) * orbitScale;
    vec4 clip = transform_projection * vec4(pixel, 0.0, 1.0);
    clip.z = (forward * cos(orbitElevation) - world.y * sin(orbitElevation)) / 100.0;
    return clip;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 pixel) {
    vec4 sample = Texel(texture, uv) * color;
    if (sample.a < 0.04) discard;
    return sample;
}
#endif
]]

local objects = {
    {id="cutter", label="Polar cutter", path="assets/generated/polar-cutter-64-v2.png",
        frames=64, frameColumns=8, frameRows=8, frame=1, rotation=0,
        x=Config.cutterPlacement.spawnX, y=Config.cutterPlacement.spawnY,
        drawScale=Config.cutterPlacement.drawScale*2.47, anchor=0.96,
        contactStrategy="wide-support", contactWidthFraction=.28, action="Run a test cut"},
    {id="wrapper", label="Skid wrapper", path="assets/generated/skid-wrapper-64-v1.png",
        frames=64, frameColumns=8, frameRows=8, frame=1, rotation=0,
        x=Config.wrapperPlacement.spawnX, y=Config.wrapperPlacement.spawnY,
        drawScale=Config.wrapperPlacement.drawScale*2, anchor=0.94, action="Wrap the paper skid"},
    {id="stock", label="Paper skid", path="assets/generated/loaded-paper-pallet-64-v1.png",
        frames=64, frameColumns=8, frameRows=8, frame=1, x=410, y=374,
        drawScale=Config.palletLogistics.drawScale, anchor=0.90, rotation=0, action="Stage paper at cutter"},
}

local state = {mode="orbit", original=true, drag=false, status="", showHelp=true,
    orbit={x=0,z=0,yaw=Geometry.YAW,elevation=Geometry.ELEVATION,zoom=1},
    player={}, heading=Geometry.YAW, pitch=-0.04,
    working=false, wrapped=false, staged=false}

local function mesh(vertices, image)
    local result = g.newMesh(format, vertices, "triangles", "static")
    result:setTexture(image)
    return result
end

local function scaledDimensions()
    local width, height = g.getDimensions()
    return width, height, width / Geometry.WIDTH, height / Geometry.HEIGHT
end

local function sourceToWorld(item)
    item.worldX, item.worldZ = Geometry.floorPoint(item.x, item.y)
end

local Grounded=require('tools.warehouse_perspective_lab.grounded_sprites')
local FirstPersonProps=require('tools.warehouse_perspective_lab.first_person_props')

local function perspectiveCamera(width, height)
    local focal = width * 0.5 / math.tan(math.rad(84) * 0.5)
    return {centerX=state.player.x, centerZ=state.player.z, eyeHeight=1.65,
        viewHeading=state.heading, viewPitch=state.pitch, roll=0, focal=focal,
        viewportWidth=width, viewportHeight=height}
end

local function sendCamera(width, height)
    local shader = state.shader
    local orbit = state.orbit
    shader:send("firstPerson", state.mode == "first person")
    shader:send("orbitFocus", {orbit.x, orbit.z})
    shader:send("orbitYaw", orbit.yaw)
    shader:send("orbitElevation", orbit.elevation)
    shader:send("orbitScale", Geometry.SCALE * orbit.zoom * width / Geometry.WIDTH)
    shader:send("modelYaw",0)
    shader:send("environmentScale", state.mode == "first person" and ROOM_EXPANSION or 1)
    shader:send("environmentCenter", {ROOM_CENTER_X, ROOM_CENTER_Z})
    shader:send("screenAnchor", {width * 0.5,
        height * 0.5 + (Geometry.CENTER_Y - Geometry.HEIGHT * 0.5)
            * height / Geometry.HEIGHT * orbit.zoom})
    FP.send(perspectiveCamera(width, height), shader)
end

local function project(x, z, height, width, canvasHeight)
    if state.mode == "first person" then
        return FP.screen(perspectiveCamera(width, canvasHeight), x, z, height)
    end
    return Geometry.projectOrbit(x, z, height, state.orbit, width, canvasHeight)
end

local function nearestObject()
    local best, distance
    for _, item in ipairs(objects) do
        local d = math.sqrt((item.worldX-state.player.x)^2 + (item.worldZ-state.player.z)^2)
        if not distance or d < distance then best, distance = item, d end
    end
    return best, distance
end

local function walkable(x,z)
    local scale=state.mode=="first person" and ROOM_EXPANSION or 1
    local floorX=ROOM_CENTER_X+(x-ROOM_CENTER_X)/scale
    local floorZ=ROOM_CENTER_Z+(z-ROOM_CENTER_Z)/scale
    if not Geometry.floorContains(floorX,floorZ)
        and not require('tools.warehouse_perspective_lab.fixtures').insideExtension(floorX,floorZ) then return false end
    if state.fixtures and require('tools.warehouse_perspective_lab.fixtures').blocked(
        state.fixtures,floorX,floorZ) then return false end
    for _,item in ipairs(objects) do
        local radius=item.id=="cutter" and 1.12 or item.id=="wrapper" and 0.88 or 0.64
        if (x-item.worldX)^2+(z-item.worldZ)^2<radius^2 then return false end
    end
    return true
end

local function activate(item)
    if not item then return end
    if item.id == "cutter" then
        if state.working then
            state.working, state.cutterTimer, state.cutterPhase = false, 0, 0
            state.status = "Cutter: cycle stopped"
        else
            state.working, state.cutterTimer, state.cutterPhase = true, 0, 0
            state.status = "Cutter: test cycle running"
        end
    elseif item.id == "wrapper" then
        if state.wrapping then
            state.wrapping, state.wrapperTimer, state.wrapperPhase = false, 0, 0
            state.status = "Wrapper: cycle stopped"
        elseif state.wrapped then
            state.wrapped, state.wrapperPhase = false, 0
            state.status = "Paper skid: unwrapped"
        else
            state.wrapping, state.wrapperTimer, state.wrapperPhase = true, 0, 0
            state.status = "Wrapper: automatic cycle running"
        end
    elseif item.id == "stock" then
        state.staged = not state.staged
        item.x,item.y=state.staged and 535 or 410,state.staged and 490 or 374
        sourceToWorld(item)
        state.status = state.staged and "Paper staged at cutter" or "Paper returned to stock"
    end
end

local function resetCamera()
    state.orbit={x=0,z=0,yaw=Geometry.YAW,elevation=Geometry.ELEVATION,zoom=1}
    state.player.x, state.player.z = Geometry.floorPoint(480,610)
    local cutter=objects[1]
    state.heading=math.atan2(cutter.worldZ-state.player.z,cutter.worldX-state.player.x)
    state.pitch=-0.08
    state.status="Camera and player reset to the warehouse entry"
end

local function drawOriginal(width, height)
    g.setColor(1,1,1)
    g.draw(state.background,0,0,0,width/state.background:getWidth(),height/state.background:getHeight())
    local sx, sy=width/Geometry.WIDTH,height/Geometry.HEIGHT
    for _,item in ipairs(objects) do
        local frame=item.frame
        if item.frames==64 then
            frame=(math.floor(item.rotation/(2*math.pi)*64+.5)%64)+1
        end
        local col=(frame-1)%item.frameColumns
        local row=math.floor((frame-1)/item.frameColumns)
        local quad=g.newQuad(col*item.frameWidth,row*item.frameHeight,
            item.frameWidth,item.frameHeight,item.image:getDimensions())
        g.draw(item.image,quad,item.x*sx,item.y*sy,0,
            item.drawScale*sx,item.drawScale*sy,item.frameWidth/2,item.frameHeight*item.anchor)
    end
end

local function drawHud(width, height)
    local pad=14
    g.setColor(0.035,0.055,0.07,0.88)
    g.rectangle("fill",pad,pad,math.min(width-2*pad,760),state.showHelp and 122 or 54,8,8)
    g.setColor(1,1,1)
    g.print("WAREHOUSE PERSPECTIVE LAB  |  "..state.mode:upper()
        ..(state.original and "  |  SOURCE SPRITE" or "  |  3D MESH"),pad+12,pad+9)
    g.setColor(0.80,0.90,0.94)
    if state.showHelp then
        g.print("TAB first person  |  C/V cutter  |  M/N wrapper  |  [ ] paper  |  right drag look",pad+12,pad+35)
        g.print("WASD move  |  Q/E turn  |  wheel zoom in third person  |  click object or F use nearby",pad+12,pad+57)
        g.print("H hide help  |  ESC exit  |  lab actions do not change a game save",pad+12,pad+79)
    end
    if state.status ~= "" then
        g.setColor(1,0.83,0.42)
        g.print(state.status,pad+12,state.showHelp and pad+100 or pad+32)
    end
    if state.mode == "first person" then
        local item, distance=nearestObject()
        if item and distance < 2.4 then
            local action = item.action
            if item.id == "cutter" and state.working then
                action = "Stop the test cycle"
            elseif item.id == "wrapper" then
                action = state.wrapping and "Stop the wrapping cycle"
                    or state.wrapped and "Remove the film" or "Wrap the paper skid"
            elseif item.id == "stock" and state.staged then
                action = "Return paper to stock"
            end
            g.setColor(0.04,0.06,0.07,0.86)
            g.rectangle("fill",width*0.5-165,height-72,330,44,5,5)
            g.setColor(1,0.88,0.55)
            g.printf("F  "..action,width*0.5-155,height-60,310,"center")
        end
        g.setColor(1,1,1,0.8)
        g.line(width*0.5-7,height*0.5,width*0.5+7,height*0.5)
        g.line(width*0.5,height*0.5-7,width*0.5,height*0.5+7)
    end
end

function Lab.install()
    function love.load()
        love.window.setTitle("The Picture Shop — Warehouse Perspective Lab")
        state.background=g.newImage(Config.paths.warehouse)
        state.background:setFilter("linear","linear")
        state.shader=g.newShader(shaderSource)
        local width,height=g.getDimensions()
        state.canvas=g.newCanvas(width,height)
        local floor, rear=Geometry.meshes()
        state.floor=mesh(floor,state.background)
        state.rear=mesh(rear,state.background)
        local left,right,front,ceiling,upper=Geometry.enclosure()
        state.left=mesh(left,state.background)
        state.right=mesh(right,state.background)
        state.front=mesh(front,state.background)
        state.upper=mesh(upper,state.background)
        local pixel=love.image.newImageData(1,1)
        pixel:setPixel(0,0,1,1,1,1)
        state.white=g.newImage(pixel)
        state.ceiling=mesh(ceiling,state.white)
        state.fixtures=require('tools.warehouse_perspective_lab.fixtures').build(state.white)
        for _,item in ipairs(objects) do
            item.image=g.newImage(item.path)
            item.image:setFilter("linear","linear")
            item.frameColumns=item.frameColumns or item.frames
            item.frameRows=item.frameRows or 1
            item.frameWidth=item.image:getWidth()/item.frameColumns
            item.frameHeight=item.image:getHeight()/item.frameRows
            Grounded.prepare(item)
            sourceToWorld(item)
        end
        resetCamera()
        state.status="Registered floor, walls, cutter, wrapper, and paper skid loaded"
        local capture=os.getenv("PICTURE_SHOP_WAREHOUSE_PERSPECTIVE_CAPTURE")
        if capture=='verify' then require('tools.warehouse_perspective_lab.verify')(objects) end
        if capture=="first" or capture=="first-turned" then
            state.mode="first person";state.original=false
        end
        if capture=="first-turned" then state.heading=state.heading+1.35 end
        if capture=="orbit-rotated" then
            state.mode="first person";state.original=false;state.heading=state.heading+0.55
        end
                if capture=="source" then state.original=true end
        if capture=="contact" then
            state.mode="first person";state.original=false
            local target=objects[1]
            state.player.x=target.worldX+3.4
            state.player.z=target.worldZ+3.4
            state.heading=Geometry.YAW;state.pitch=-.22
            state.showHelp=false;state.status="Floor-contact review"
        end
        if capture=="props" then
            state.mode="first person";state.original=false
            local targetX,targetZ=0,0
            for _,item in ipairs(objects) do
                targetX,targetZ=targetX+item.worldX,targetZ+item.worldZ
            end
            targetX,targetZ=targetX/#objects,targetZ/#objects
            state.player.x,state.player.z=Geometry.floorPoint(480,620)
            state.heading=math.atan2(targetZ-state.player.z,targetX-state.player.x)
            state.pitch=-.08
            state.showHelp=false;state.status="Procedural 3D cutter, wrapper and paper-skid review"
        end
        if capture=="cutter-detail" then
            state.mode="first person";state.original=false
            local cutter=objects[1]
            state.player.x,state.player.z=cutter.worldX+2.1,cutter.worldZ+4.0
            state.heading=math.atan2(cutter.worldZ-state.player.z,
                cutter.worldX-state.player.x)
            state.pitch=-.06
            state.showHelp=false;state.status="Polar cutter 3D detail review"
        end
        if capture=="wrapper-detail" then
            state.mode="first person";state.original=false
            local wrapper=objects[2]
            state.player.x,state.player.z=wrapper.worldX+2.3,wrapper.worldZ+4.0
            state.heading=math.atan2(wrapper.worldZ-state.player.z,
                wrapper.worldX-state.player.x)
            state.pitch=-.06
            state.showHelp=false;state.status="Skid wrapper 3D detail review"
        end
    end

    function love.update(dt)
        dt=math.min(dt,0.1)
        if state.working then
            state.cutterTimer = (state.cutterTimer or 0) + dt
            state.cutterPhase = math.min(1, state.cutterTimer / 3.2)
            if state.cutterTimer >= 3.2 then
                state.working, state.cutterPhase = false, 0
                state.status = "Cutter: test cycle complete"
            end
        end
        if state.wrapping then
            state.wrapperTimer = (state.wrapperTimer or 0) + dt
            state.wrapperPhase = math.min(1, state.wrapperTimer / 5)
            state.wrapperRotation = (state.wrapperRotation or 0) + dt * 1.35
            if state.wrapperTimer >= 5 then
                state.wrapping, state.wrapped = false, true
                state.wrapperPhase = 1
                state.status = "Wrapper: skid secured with film"
            end
        end
        objects[1].working = state.working
        objects[1].actionPhase = state.working and (state.cutterPhase or 0) or 0
        objects[2].wrapping = state.wrapping
        objects[2].wrapped = state.wrapped
        objects[2].actionPhase = state.wrapping and (state.wrapperPhase or 0)
            or state.wrapped and 1 or 0
        objects[2].loadRotation = state.wrapperRotation or 0
        if state.mode == "first person" then
            local forward, side=0,0
            if love.keyboard.isDown("w") then forward=forward+1 end
            if love.keyboard.isDown("s") then forward=forward-1 end
            if love.keyboard.isDown("d") then side=side+1 end
            if love.keyboard.isDown("a") then side=side-1 end
            if forward~=0 or side~=0 then
                local length=math.sqrt(forward*forward+side*side)
                forward,side=forward/length,side/length
                local c,s=math.cos(state.heading),math.sin(state.heading)
                local moveSpeed=3.6*ROOM_EXPANSION
                local dx=(forward*c-side*s)*dt*moveSpeed
                local dz=(forward*s+side*c)*dt*moveSpeed
                local nextX,nextZ=state.player.x+dx,state.player.z+dz
                if walkable(nextX,state.player.z) then state.player.x=nextX end
                if walkable(state.player.x,nextZ) then state.player.z=nextZ end
            end
        else
            local orbit=state.orbit
            if love.keyboard.isDown("a") then orbit.x=orbit.x-dt*3 end
            if love.keyboard.isDown("d") then orbit.x=orbit.x+dt*3 end
            if love.keyboard.isDown("w") then orbit.z=orbit.z-dt*3 end
            if love.keyboard.isDown("s") then orbit.z=orbit.z+dt*3 end
        end
        local yawDelta=0
        if love.keyboard.isDown("q") then yawDelta=yawDelta-dt*1.1 end
        if love.keyboard.isDown("e") then yawDelta=yawDelta+dt*1.1 end
        if state.mode == "first person" then state.heading=state.heading+yawDelta
        else state.orbit.yaw=state.orbit.yaw+yawDelta end
        local pitchDelta=0
        if love.keyboard.isDown("up") then pitchDelta=pitchDelta+dt*0.75 end
        if love.keyboard.isDown("down") then pitchDelta=pitchDelta-dt*0.75 end
        if state.mode == "first person" then
            state.pitch=math.max(-1.3,math.min(1.3,state.pitch+pitchDelta))
        else
            state.orbit.elevation=math.max(math.rad(8),math.min(math.rad(80),state.orbit.elevation+pitchDelta))
        end
    end

    function love.draw()
        local width,height=scaledDimensions()
        g.clear(0.12,0.15,0.17,1)
        if state.mode=="orbit" or state.original then
            drawOriginal(width,height)
        else
            if state.canvas:getWidth()~=width or state.canvas:getHeight()~=height then
                state.canvas:release()
                state.canvas=g.newCanvas(width,height)
            end
            g.push("all")
            g.setCanvas({state.canvas,depth=true})
            g.clear(0.12,0.15,0.17,1,0,1)
            g.setDepthMode("lequal",true)
            g.setMeshCullMode("none")
            sendCamera(width,height)
            g.setShader(state.shader)
            g.setColor(1,1,1)
            g.draw(state.floor)
            g.draw(state.fixtures.mesh)
            if state.mode=="first person" then
                g.setColor(.48,.46,.40); state.left:setTexture(state.white); g.draw(state.left)
                state.right:setTexture(state.white); g.draw(state.right)
                g.setColor(1,1,1)
                g.setColor(.48,.46,.40); state.front:setTexture(state.white); g.draw(state.front)
                g.setColor(0.21,0.24,0.25)
                g.draw(state.ceiling)
                g.setColor(1,1,1)
            end
            state.shader:send("environmentScale",1)
            local yaw=state.mode=="first person" and state.heading or state.orbit.yaw
            g.setDepthMode('lequal',false)
            for _,item in ipairs(objects) do
                g.setColor(.07,.055,.035,.22)
                g.draw(Grounded.shadow(item,state.white))
            end
            g.setDepthMode('lequal',true);g.setColor(1,1,1)
            for _,item in ipairs(objects) do
                if state.mode == 'first person' and FirstPersonProps.supports(item) then
                    FirstPersonProps.draw(item, state.white)
                else
                    local bearing=state.mode=='first person' and math.atan2(state.player.z-item.worldZ,state.player.x-item.worldX) or yaw
                    g.draw(Grounded.sprite(item,bearing))
                end
            end
            g.pop()
            g.setColor(1,1,1)
            g.draw(state.canvas)
        end
        drawHud(width,height)
        if os.getenv("PICTURE_SHOP_WAREHOUSE_PERSPECTIVE_CAPTURE") and not state.captured then
            state.captured=true
            g.captureScreenshot(function(data)
                data:encode("png","warehouse-perspective-capture.png")
                love.event.quit(0)
            end)
        end
    end

    function love.keypressed(key)
        if key=="escape" then love.event.quit()
        elseif key=="tab" then
            if state.mode=="orbit" then
                state.mode="first person";state.original=false
            else
                state.mode="orbit";state.original=true
                state.orbit={x=0,z=0,yaw=Geometry.YAW,elevation=Geometry.ELEVATION,zoom=1}
            end
            state.status="Camera: "..state.mode..(state.mode=="orbit" and " (reset)" or "")
        elseif key=="b" then
            if state.mode=="first person" then
                state.original=not state.original
                state.status=state.original and "Source image inspection" or "Procedural first-person workshop"
            end
        elseif key=="r" then resetCamera()
        elseif key=="h" then state.showHelp=not state.showHelp
        elseif key=="f" then
            local item,distance=nearestObject()
            if distance and distance<2.4 then activate(item) end
        elseif key=="[" or key=="-" then
            objects[3].rotation=objects[3].rotation-math.pi/32
            objects[3].spriteQuad=nil;objects[3].lastYaw=nil
            state.status="Paper skid rotated 5.625 degrees"
        elseif key=="]" or key=="=" then
            objects[3].rotation=objects[3].rotation+math.pi/32
            objects[3].spriteQuad=nil;objects[3].lastYaw=nil
            state.status="Paper skid rotated 5.625 degrees"
        elseif key=="c" then
            objects[1].rotation=objects[1].rotation-math.pi/32
            objects[1].spriteQuad=nil;objects[1].lastYaw=nil
            state.status="Polar cutter rotated 5.625 degrees"
        elseif key=="v" then
            objects[1].rotation=objects[1].rotation+math.pi/32
            objects[1].spriteQuad=nil;objects[1].lastYaw=nil
            state.status="Polar cutter rotated 5.625 degrees"
        elseif key=="m" then
            objects[2].rotation=objects[2].rotation-math.pi/32
            objects[2].spriteQuad=nil;objects[2].lastYaw=nil
            state.status="Skid wrapper rotated 5.625 degrees"
        elseif key=="n" then
            objects[2].rotation=objects[2].rotation+math.pi/32
            objects[2].spriteQuad=nil;objects[2].lastYaw=nil
            state.status="Skid wrapper rotated 5.625 degrees"
        end
    end

    function love.mousepressed(x,y,button)
        if button==2 then state.drag=true; return end
        if button~=1 then return end
        local width,height=scaledDimensions()
        local nearest,best=nil,math.huge
        for _,item in ipairs(objects) do
            local px,py,depth=project(item.worldX,item.worldZ,0,width,height)
            if not depth or depth>0 then
                local distance=math.sqrt((x-px)^2+(y-py)^2)
                if distance<best then nearest,best=item,distance end
            end
        end
        if best<65 then activate(nearest) end
    end
    function love.mousereleased(x,y,button) if button==2 then state.drag=false end end
    function love.mousemoved(x,y,dx,dy)
        if not state.drag then return end
        if state.mode=="first person" then
            state.heading=state.heading+dx*0.006
            state.pitch=math.max(-1.3,math.min(1.3,state.pitch-dy*0.005))
        else
            state.orbit.yaw=state.orbit.yaw+dx*0.005
            state.orbit.elevation=math.max(math.rad(8),
                math.min(math.rad(80),state.orbit.elevation+dy*0.004))
        end
    end
    function love.wheelmoved(x,y)
        if state.mode=="orbit" then
            state.orbit.zoom=math.max(0.45,math.min(2.2,state.orbit.zoom*(1+y*0.12)))
        end
    end
end

return Lab
