-- Playable first-person warehouse view. Movement, collision, interaction and
-- machine state continue to come from the normal warehouse runtime.
local Geometry = require("src.warehouse_perspective_geometry")
local Perspective = require("src.commute.first_person_camera")
local Grounded = require("src.warehouse_first_person_grounded")
local Props = require("src.warehouse_first_person_props")
local Fixtures = require("src.warehouse_first_person_fixtures")
local Config = require("src.config")
local CutterPlacement = require("src.cutter_placement")
local WrapperPlacement = require("src.wrapper_placement")
local WindmillPlacement = require("src.windmill_placement")

local View = {}
local format = {{"VertexPosition", "float", 2}, {"WorldHeight", "float", 1},
    {"VertexTexCoord", "float", 2}}
local state = {enabled=false, cameraMenu=false, yaw=nil, pitch=-0.04, focused=true, mouseCaptured=false,
    ignoreMouseDelta=false, billboards={}, initialized=false}

local function setMouseCapture(enabled)
    enabled=enabled==true
    if state.mouseCaptured==enabled then return end
    local mouse=love and love.mouse
    if not mouse or type(mouse.setRelativeMode)~="function" then return end
    if enabled then
        state.previousRelativeMode=false
        state.previousMouseVisible=true
        if type(mouse.getRelativeMode)=="function" then
            local ok,value=pcall(mouse.getRelativeMode)
            if ok then state.previousRelativeMode=value==true end
        end
        if type(mouse.isVisible)=="function" then
            local ok,value=pcall(mouse.isVisible)
            if ok then state.previousMouseVisible=value~=false end
        end
    end
    local target=enabled and true or state.previousRelativeMode==true
    local ok=pcall(mouse.setRelativeMode,target)
    if not ok then return end
    if type(mouse.setVisible)=="function" then
        local visible=enabled and false or state.previousMouseVisible~=false
        pcall(mouse.setVisible,visible)
    end
    state.mouseCaptured=enabled
    if enabled then state.ignoreMouseDelta=true end
    if not enabled then state.previousRelativeMode,state.previousMouseVisible=nil,nil end
end

local function mesh(vertices, image)
    local result = love.graphics.newMesh(format, vertices, "triangles", "static")
    result:setTexture(image)
    return result
end

local function sourcePosition(x, y)
    return Geometry.floorPoint(x, y)
end

local function currentCamera(Runtime)
    local x, z = sourcePosition(Runtime.World.player.x, Runtime.World.player.y)
    return {centerX=x, centerZ=z, eyeHeight=1.65, viewHeading=state.yaw or Geometry.YAW,
        viewPitch=state.pitch, roll=0,
        focal=Runtime.Config.baseWidth * 0.5 / math.tan(math.rad(82) * 0.5),
        viewportWidth=Runtime.Config.baseWidth, viewportHeight=Runtime.Config.baseHeight}
end

local function initialize(Runtime)
    if state.initialized then return end
    local g = love.graphics
    local background = Runtime.Assets.get("warehouse")
    if not background then return end
    state.background = background
    local shaderSource = assert(love.filesystem.read("src/commute/perspective.glsl"))
    shaderSource = shaderSource .. [[
#ifdef VERTEX
attribute float WorldHeight;
extern float modelYaw;
extern vec2 modelPosition;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    float c=cos(modelYaw), s=sin(modelYaw);
    vec3 world=vec3(vertex_position.x*c-vertex_position.y*s+modelPosition.x, WorldHeight,
        vertex_position.x*s+vertex_position.y*c+modelPosition.y);
    return riderProjection(transform_projection,world);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 pixel) {
    vec4 sample=Texel(texture,uv)*color;
    if (sample.a < 0.04) discard;
    return sample;
}
#endif
]]
    state.shader = g.newShader(shaderSource)
    state.canvas = g.newCanvas(Runtime.Config.baseWidth, Runtime.Config.baseHeight)
    local floor, rear = Geometry.meshes()
    state.floor, state.rear = mesh(floor, background), mesh(rear, background)
    local left, right, front, ceiling, upper = Geometry.enclosure()
    state.left, state.right, state.front = mesh(left, background), mesh(right, background), mesh(front, background)
    local imageData = love.image.newImageData(1, 1)
    imageData:setPixel(0, 0, 1, 1, 1, 1)
    state.white = g.newImage(imageData)
    imageData:release()
    state.ceiling, state.upper = mesh(ceiling, state.white), mesh(upper, background)
    state.fixtures = Fixtures.build(state.white)
    state.machineModels = {}
    state.vehicleModels = {}
    state.windmillItems = {}
    state.palletModels = {}
    state.initialized = true
end

local function closeToWarehouse(Runtime)
    return Runtime.state.screen == "world"
        and require("src.shop_rooms").scene(Runtime.World.player) == "warehouse"
end

local function faceCutter(Runtime)
    if state.yaw then return end
    local playerX, playerZ = sourcePosition(Runtime.World.player.x, Runtime.World.player.y)
    local cutter = CutterPlacement.ensure(Runtime.state, Runtime.Config.cutterPlacement)
    local cutterX, cutterZ = sourcePosition(cutter.x, cutter.y)
    state.yaw = math.atan2(cutterZ - playerZ, cutterX - playerX)
end

local function setEnabled(Runtime, enabled)
    state.enabled=enabled==true
    state.cameraMenu=false
    if state.enabled then faceCutter(Runtime) end
    setMouseCapture(state.enabled and state.focused)
    return true
end

function View.cameraButton(Runtime)
    if not closeToWarehouse(Runtime) then return nil end
    local right=Runtime.Config.baseWidth
    if Runtime.optionsAccessLayout then
        local _,bounds=Runtime.optionsAccessLayout()
        if bounds and bounds.right then right=bounds.right end
    end
    return {x=right-410,y=58,width=132,height=32}
end

function View.cameraRow(Runtime,index)
    local button=View.cameraButton(Runtime)
    if not button then return nil end
    return {x=button.x,y=button.y+button.height+4+(index-1)*36,width=button.width,height=34}
end

function View:cameraPointer(Runtime,x,y,button)
    if button~=nil and button~=1 then return false end
    local cameraButton=View.cameraButton(Runtime)
    if not cameraButton then return false end
    local function hit(rect)
        return x>=rect.x and x<=rect.x+rect.width and y>=rect.y and y<=rect.y+rect.height
    end
    if hit(cameraButton) then
        state.cameraMenu=not state.cameraMenu
        setMouseCapture(state.enabled and state.focused and not state.cameraMenu)
        return true
    end
    if state.cameraMenu then
        for index,enabled in ipairs({false,true}) do
            local row=View.cameraRow(Runtime,index)
            if hit(row) then return setEnabled(Runtime,enabled) end
        end
        state.cameraMenu=false
        setMouseCapture(state.enabled and state.focused)
        return true
    end
    return false
end

function View:drawCameraOption(Runtime)
    local button=View.cameraButton(Runtime)
    if not button then return false end
    local g=love.graphics
    local Ui=require("src.screens.ui")
    local font=g.getFont()
    g.push("all")
    Ui.panel(button,state.enabled and {.12,.20,.16,1} or {.09,.13,.14,1},
        state.cameraMenu and {.84,.72,.36,1} or {.43,.53,.51,1},5,1)
    g.setColor(.94,.95,.89)
    g.printf(state.enabled and "CAMERA  ·  FP" or "CAMERA",button.x+4,
        button.y+(button.height-font:getHeight())*.5,button.width-8,"center")
    if state.cameraMenu then
        for index,entry in ipairs({{"Isometric",false},{"First person",true}}) do
            local row=View.cameraRow(Runtime,index)
            local selected=state.enabled==entry[2]
            Ui.panel(row,selected and {.16,.25,.19,1} or {.055,.085,.09,.97},
                selected and {.84,.72,.36,1} or {.32,.41,.40,1},4,1)
            g.setColor(selected and 1 or .88,selected and .88 or .91,selected and .54 or .84,1)
            g.circle("line",row.x+15,row.y+row.height*.5,5)
            if selected then g.circle("fill",row.x+15,row.y+row.height*.5,2.6) end
            g.print(entry[1],row.x+28,row.y+(row.height-font:getHeight())*.5)
        end
    end
    g.pop()
    return true
end

function View:touchLook(Runtime,dx,dy)
    if not self:isActive(Runtime) then return false end
    local turnRate=.0024*1280/math.max(1,Runtime.Config.baseWidth or 1280)
    state.yaw=((state.yaw or Geometry.YAW)+(dx or 0)*turnRate+math.pi)%(math.pi*2)-math.pi
    state.pitch=math.max(-.70,math.min(.50,state.pitch-(dy or 0)*turnRate))
    return true
end

function View:isActive(Runtime)
    local scene = require("src.shop_rooms").scene(Runtime.World.player)
    local ended = scene ~= "warehouse" or Runtime.state.screen == "title"
        or Runtime.state.screen == "lan" or Runtime.state.screen == "direct"
        or Runtime.state.screen == "asset_error"
    if state.enabled and ended then
        state.enabled=false
        state.cameraMenu=false
    end
    local active=state.enabled and closeToWarehouse(Runtime)
    setMouseCapture(active and state.focused)
    return active
end

function View:focus(Runtime,focused)
    state.focused=focused==true
    if state.enabled then self:isActive(Runtime) else setMouseCapture(false) end
end

function View:keypressed(Runtime, key)
    if key == "f1" and closeToWarehouse(Runtime) then
        return setEnabled(Runtime,not state.enabled)
    end
    if key == "c" and closeToWarehouse(Runtime) then
        state.cameraMenu=not state.cameraMenu
        setMouseCapture(state.enabled and state.focused and not state.cameraMenu)
        return true
    end
    if key == "escape" and state.cameraMenu then
        state.cameraMenu=false
        setMouseCapture(state.enabled and state.focused)
        return true
    end
    if key == "escape" and state.enabled and Runtime.state.screen == "world" then
        state.enabled=false
        setMouseCapture(false)
        return true
    end
    return false
end

function View:movement(Runtime, x, y)
    if not self:isActive(Runtime) then return x, y end
    local forward, side = -y, x
    local length = math.sqrt(forward * forward + side * side)
    if length <= 0.0001 then return 0, 0 end
    local inputStrength=math.min(1,length)
    forward, side = forward / length, side / length
    local yaw = state.yaw or Geometry.YAW
    local worldX = forward * math.cos(yaw) - side * math.sin(yaw)
    local worldZ = forward * math.sin(yaw) + side * math.cos(yaw)
    local screenX = 48 * (worldX - worldZ)
    local screenY = 24 * (worldX + worldZ)
    local sourcePixelsPerWorldUnit = 48 * math.sqrt(2)
    return screenX * inputStrength / sourcePixelsPerWorldUnit,
        screenY * inputStrength / sourcePixelsPerWorldUnit
end

function View:mousepressed(Runtime, button)
    return self:isActive(Runtime)
end

function View:mousereleased(Runtime, button)
    return self:isActive(Runtime)
end

function View:mousemoved(Runtime, dx, dy)
    if not self:isActive(Runtime) then return false end
    if state.ignoreMouseDelta then
        state.ignoreMouseDelta=false
        return true
    end
    local turnRate=0.0024
    state.yaw = ((state.yaw or Geometry.YAW) + (dx or 0) * turnRate + math.pi) % (math.pi * 2) - math.pi
    state.pitch = math.max(-0.70, math.min(0.50, state.pitch - (dy or 0) * turnRate))
    return true
end

local function positionedModel(item, sourceX, sourceY, rotation)
    item.worldX, item.worldZ = sourcePosition(sourceX, sourceY)
    item.rotation = rotation or 0
    return item
end

local sourceAngles={
    northwest=-math.pi*.75,north=-math.pi*.5,northeast=-math.pi*.25,east=0,
    southeast=math.pi*.25,south=math.pi*.5,southwest=math.pi*.75,west=math.pi,
}

local function modelYawFromSourceAngle(angle)
    local screenX,screenY=math.cos(angle),math.sin(angle)
    local worldX=(screenX/48+screenY/24)*.5
    local worldZ=(screenY/24-screenX/48)*.5
    return math.atan2(-worldX,worldZ)
end

local function palletType(record)
    if not record or not record.pallet then return nil end
    local pallet=record.pallet
    if record.vendor then
        local category=pallet.category or "paper"
        if category=="press" then return "vendor_press" end
        if category=="packaging" then return "vendor_packaging" end
        if category=="equipment" then return "vendor_equipment" end
        return "vendor_paper"
    end
    if pallet.packaging=="boxed" then return pallet.wrapped and "wrapped_boxed" or "boxed" end
    if pallet.wrapped then return "wrapped" end
    return "paper"
end

local function cargoRecord(Runtime,palletId)
    if not palletId then return nil end
    return require("src.pallet_state").find(Runtime.state,palletId)
end

local function palletStackHeight(style)
    if style=="vendor_press" then return .95 end
    if style=="vendor_packaging" then return 1.09 end
    if style=="vendor_equipment" then return .79 end
    if style=="boxed" then return .93 end
    if style=="wrapped_boxed" then return .93 end
    if style=="wrapped" then return .94 end
    return 1.06
end

local function palletRotation(pallet)
    local direction=pallet and pallet.world and pallet.world.direction
    local angle=sourceAngles[direction]
    return angle and modelYawFromSourceAngle(angle) or 0
end

local function updateMachineItems(Runtime)
    local result, used = {}, {}
    local cutter = CutterPlacement.ensure(Runtime.state, Runtime.Config.cutterPlacement)
    local wrapper = WrapperPlacement.ensure(Runtime.state, Runtime.Config.wrapperPlacement)
    local windmill = WindmillPlacement.ensure(Runtime.state, Runtime.Config.windmillPlacement)
    local function add(id, source, kind)
        if not source or source.sceneId and source.sceneId ~= "warehouse" then return end
        local item = state.machineModels[id]
        if not item then item={id=kind};state.machineModels[id]=item end
        item.viewId=id
        positionedModel(item, source.x, source.y, ((source.rotationIndex or 1) - 1) * (math.pi * 2 / 64))
        item.working = kind == "cutter" and Runtime.state.cutter and Runtime.state.cutter.working == true or false
        item.wrapping = kind == "wrapper" and Runtime.Wrapper.step == "wrapping" or false
        item.wrapped = kind == "wrapper" and Runtime.Wrapper.step == "complete" or false
        item.actionPhase = 0
        result[#result + 1], used[id] = item, true
    end
    local cutterUnits = Runtime.MachineFleet.installedUnits(Runtime.state, "polar_115")
    local wrapperUnits = Runtime.MachineFleet.installedUnits(Runtime.state, "skid_wrapper")
    local windmillUnits = Runtime.MachineFleet.installedUnits(Runtime.state, "heidelberg_10x15")
    local hasCutterPose,hasWrapperPose,hasWindmillPose=false,false,false
    for _, unit in ipairs(cutterUnits) do
        if unit.world then
            hasCutterPose=true
            if (unit.world.sceneId or "warehouse")=="warehouse" then add(unit.id,unit.world,"cutter") end
        end
    end
    for _, unit in ipairs(wrapperUnits) do
        if unit.world then
            hasWrapperPose=true
            if (unit.world.sceneId or "warehouse")=="warehouse" then add(unit.id,unit.world,"wrapper") end
        end
    end
    for _, unit in ipairs(windmillUnits) do
        if unit.world then
            hasWindmillPose=true
            if (unit.world.sceneId or "warehouse")=="warehouse" then add(unit.id,unit.world,"windmill") end
        end
    end
    if #cutterUnits > 0 and not hasCutterPose then add("cutter:default", cutter, "cutter") end
    if #wrapperUnits > 0 and not hasWrapperPose then add("wrapper:default", wrapper, "wrapper") end
    if #windmillUnits > 0 and not hasWindmillPose then add("windmill:default", windmill, "windmill") end
    for id, item in pairs(state.machineModels) do
        if not used[id] and item.fpModel then
            for _, part in ipairs(item.fpModel.parts) do part.mesh:release() end
            item.fpModel=nil
        end
    end
    return result
end

local function updatePalletModels(Runtime)
    local visible, used = {}, {}
    local physical={}
    for _,record in ipairs(Runtime.PalletLogistics.physicalPallets(Runtime.state)) do
        if record.pallet.world and (record.pallet.world.sceneId or "warehouse")=="warehouse" then
            physical[#physical+1]=record
        end
    end
    local carried={}
    local forklift=Runtime.Forklift.ensure(Runtime.state,Runtime.Config.forklift)
    if forklift.carriedPalletId then carried[forklift.carriedPalletId]=true end
    for _,jack in ipairs(require("src.pallet_jack_fleet").all(Runtime.state)) do
        if jack.carriedPalletId then carried[jack.carriedPalletId]=true end
    end
    local player=Runtime.World.player
    table.sort(physical,function(a,b)
        local ad=(a.x-player.x)^2+(a.y-player.y)^2
        local bd=(b.x-player.x)^2+(b.y-player.y)^2
        return ad<bd
    end)
    local function add(record,x,y,rotation,baseHeight,visualScale,placement)
        local pallet=record and record.pallet
        if not pallet then return end
        local id = tostring(pallet.id or ("anonymous-"..tostring(#visible+1)))
        local item = state.palletModels[id]
        if not item then item={id="pallet"};state.palletModels[id]=item end
        positionedModel(item,x,y,rotation or palletRotation(pallet))
        item.palletType=palletType(record) or "paper"
        item.modelKey=item.palletType..":"..tostring(pallet.productId or pallet.packaging or "paper")
            ..":"..tostring(placement or "floor")
        item.wrapped = pallet.wrapped == true
        item.working = false
        item.actionPhase = 0
        item.baseHeight=baseHeight or 0
        item.visualScale=visualScale or 1
        visible[#visible+1], used[id] = item, true
    end

    local floorCount=0
    for _,record in ipairs(physical) do
        if not carried[record.pallet.id] then
            floorCount=floorCount+1
            if floorCount>24 then break end
            add(record,record.x,record.y,nil,0,1,"floor")
        end
    end

    local storage=require("src.pallet_storage")
    local rackId="warehouse-rack"
    if Runtime.state.storage and Runtime.state.storage.racks
        and Runtime.state.storage.racks[rackId] then
        local layout=Runtime.WarehouseLayout or require("src.warehouse_layout")
        local first=layout.rackPoint(rackId,1,1)
        local last=layout.rackPoint(rackId,1,storage.COLUMNS)
        local rackYaw=0
        if first and last then
            local x1,z1=sourcePosition(first.x,first.groundY)
            local x2,z2=sourcePosition(last.x,last.groundY)
            rackYaw=math.atan2(z2-z1,x2-x1)
        end
        local slots=storage.slots(Runtime.state,rackId)
        for row=1,storage.ROWS do
            for column=1,storage.COLUMNS do
                local palletId=slots[row][column]
                local record=palletId and storage.find(Runtime.state,palletId)
                local point=layout.rackPoint(rackId,row,column)
                if record and point then
                    local shelfTop=.34+(row-1)*1.30
                    add(record,point.x,point.groundY,rackYaw,shelfTop,.78,"rack:"..row)
                end
            end
        end
    end

    for _,record in ipairs(require("src.pallet_state").items(Runtime.state)) do
        local pallet=record.pallet
        if pallet.location=="stacked" and pallet.world
            and (pallet.world.sceneId or "warehouse")=="warehouse" then
            local support=pallet.storage and storage.find(Runtime.state,pallet.storage.supportPalletId)
            local supportHeight=support and palletStackHeight(palletType(support) or "paper") or 1.06
            add(record,pallet.world.x,pallet.world.y,palletRotation(pallet),supportHeight,1,"stacked")
        end
    end
    for id, item in pairs(state.palletModels) do
        if not used[id] and item.fpModel then
            for _, part in ipairs(item.fpModel.parts) do part.mesh:release() end
            item.fpModel=nil
        end
    end
    return visible
end

local function updateVehicleModels(Runtime)
    local visible,used={},{}
    local function add(id,kind,source,angle,cargo)
        if not source or (source.sceneId or "warehouse")~="warehouse" then return end
        local item=state.vehicleModels[id]
        if not item then item={id=kind};state.vehicleModels[id]=item end
        positionedModel(item,source.x,source.y,modelYawFromSourceAngle(angle))
        item.cargoType=palletType(cargo)
        item.modelKey=item.cargoType and (item.cargoType..":"..tostring(cargo.pallet.productId or cargo.pallet.id)) or "empty"
        item.cargoWrapped=cargo and cargo.pallet.wrapped==true or false
        item.carrying=item.cargoType~=nil
        item.forkHeight=kind=="forklift" and (source.forkHeight or 0) or nil
        item.operating=source.operating==true
        visible[#visible+1],used[id]=item,true
    end

    local lift=Runtime.Forklift.ensure(Runtime.state,Runtime.Config.forklift)
    if lift.owned and (lift.sceneId or "warehouse")=="warehouse" then
        local direction=sourceAngles[lift.direction] and lift.direction or "northwest"
        add("forklift", "forklift", lift, sourceAngles[direction], cargoRecord(Runtime,lift.carriedPalletId))
    end
    local fleet=require("src.pallet_jack_fleet")
    for index,jack in ipairs(fleet.all(Runtime.state)) do
        local key=jack.id or (index==1 and "JACK-0001" or "JACK-"..tostring(index))
        local jackView=fleet.view(Runtime.state,jack)
        local pose=Runtime.PalletJack.visualPose(jackView,Runtime.Config.palletJack)
        add(key,"palletJack",jack,pose.heading,cargoRecord(Runtime,jack.carriedPalletId))
    end
    for id,item in pairs(state.vehicleModels) do
        if not used[id] and item.fpModel then
            for _,part in ipairs(item.fpModel.parts) do part.mesh:release() end
            item.fpModel=nil
        end
    end
    return visible
end

local function getWindmillSprite(Runtime, item)
    local key = item.viewId or item.id
    local cached = state.windmillItems[key]
    local path = Config.paths.windmillDirections
    if not cached then
        local image = Runtime.Assets.get("windmillDirections")
        if not image then return nil end
        cached={id="windmill",image=image,path=path,frames=64,frameColumns=8,frameRows=8,
            frameWidth=256,frameHeight=256,drawScale=Config.windmillPlacement.drawScale,anchor=.94}
        Grounded.prepare(cached)
        state.windmillItems[key]=cached
    end
    cached.worldX,cached.worldZ=item.worldX,item.worldZ
    cached.rotation=item.rotation
    return Grounded.sprite(cached, state.yaw or Geometry.YAW)
end

local function drawActor(Runtime, actor, key, camera)
    local assets = Runtime.CharacterAssets
    local character = actor.character or Config.player.character
    local animation = require("src.character_animation")
    local action, mirror = "idle", 1
    if actor.moving then
        action, mirror = animation.actorWalkAction(actor)
    else
        local cameraX,cameraY=Geometry.sourcePoint(camera.centerX,camera.centerZ,0)
        action,mirror=animation.directionalIdleAction(cameraX-(actor.x or 0),cameraY-(actor.y or 0))
    end
    if not assets.hasAction(character, action) then action = actor.moving and "walk" or "idle" end
    if assets.resolveAction then action=assets.resolveAction(character,action) end
    local count = assets.getFrameCount(character, action) or 1
    local frame = animation.frameForPlayerAction(action,count,
        actor.animationDistance or 0,actor.idleClock or 0,Config.player.walkPixelsPerFrame,
        Config.player.idleAnimationRate)
    local image, quad = assets.get(character, action, frame)
    if not image or not quad then return end
    local qx,qy,qw,qh=quad:getViewport()
    local imageWidth,imageHeight=image:getDimensions()
    local _,anchorY=assets.getAnchor(character,action,frame)
    local scale=Config.player.drawScale*assets.getNormalization(character,action)
        /(Geometry.SCALE*math.cos(Geometry.ELEVATION))
    local width,height=qw*scale,qh*scale
    local leftX,leftZ
    local rightX,rightZ
    local x,z=sourcePosition(actor.x or 0,actor.y or 0)
    local rightWorldX,rightWorldZ=-math.sin(camera.viewHeading),math.cos(camera.viewHeading)
    leftX,leftZ=x-rightWorldX*width*.5,z-rightWorldZ*width*.5
    rightX,rightZ=x+rightWorldX*width*.5,z+rightWorldZ*width*.5
    local top, bottom=anchorY*scale,(anchorY-qh)*scale
    local u0,u1=qx/imageWidth,(qx+qw)/imageWidth
    if mirror < 0 then u0,u1=u1,u0 end
    local v0,v1=qy/imageHeight,(qy+qh)/imageHeight
    local vertices={{leftX,leftZ,top,u0,v0},{rightX,rightZ,top,u1,v0},
        {rightX,rightZ,bottom,u1,v1},{leftX,leftZ,top,u0,v0},
        {rightX,rightZ,bottom,u1,v1},{leftX,leftZ,bottom,u0,v1}}
    local cache=state.billboards[key]
    if not cache then
        cache={mesh=love.graphics.newMesh(format,vertices,"triangles","dynamic")}
        state.billboards[key]=cache
    else cache.mesh:setVertices(vertices) end
    if cache.image~=image then cache.mesh:setTexture(image);cache.image=image end
    love.graphics.setColor(1,1,1)
    love.graphics.draw(cache.mesh)
end

local function presentActors(Runtime, camera)
    local visibleCharacters = {}
    local actors = {}
    local function add(actor,key)
        if not actor or actor.visible==false or type(actor.x)~="number" or type(actor.y)~="number" then return end
        if actor.sceneId and actor.sceneId~="warehouse" then return end
        actors[#actors+1]={actor=actor,key=key}
        visibleCharacters[actor.character or Config.player.character]=true
    end
    for _, player in ipairs(Runtime.multiplayer:remotePlayers() or {}) do
        add(player,"player:"..tostring(player.id))
    end
    for _, entry in ipairs(require("src.employee_renderer").entries(Runtime.state)) do
        local worker=entry.worker or entry.application
        if worker and (worker.sceneId or "warehouse")=="warehouse" then
            add(worker,"employee:"..tostring(worker.id or entry.id))
        end
    end
    if Runtime.World.customer and Runtime.World.customer.visible then add(Runtime.World.customer,"customer") end
    if Runtime.World.vendor and Runtime.World.vendor.visible then add(Runtime.World.vendor,"vendor") end
    Runtime.CharacterAssets.retainCharacters(visibleCharacters,true)
    for _, item in ipairs(actors) do drawActor(Runtime,item.actor,item.key,camera) end
end

local function drawHelp(Runtime, prompt)
    local g=love.graphics
    g.setColor(.025,.04,.05,.78)
    g.rectangle("fill",12,12,310,74,7,7)
    g.setColor(.93,.96,.94)
    g.print("WAREHOUSE  |  F1: CAMERA",24,21)
    g.setColor(.73,.83,.83)
    local mobile=Runtime.mobileControls and Runtime.mobileControls:isEnabled()
    g.print(mobile and "Joystick move  |  drag to look  |  tap use"
        or "WASD move  |  mouse look  |  E use  |  C camera",24,43)
    if prompt then
        g.setColor(.025,.04,.05,.82)
        g.rectangle("fill",Runtime.Config.baseWidth*.5-190,Runtime.Config.baseHeight-70,380,42,5,5)
        g.setColor(1,.89,.56)
        g.printf(prompt,Runtime.Config.baseWidth*.5-180,Runtime.Config.baseHeight-58,360,"center")
    end
    g.setColor(1,1,1,.82)
    local cx,cy=Runtime.Config.baseWidth*.5,Runtime.Config.baseHeight*.5
    g.line(cx-7,cy,cx+7,cy);g.line(cx,cy-7,cx,cy+7)
end

function View:draw(Runtime)
    if not self:isActive(Runtime) then return false end
    initialize(Runtime)
    if not state.initialized then return false end
    local g=love.graphics
    local camera=currentCamera(Runtime)
    local shader=state.shader
    g.push("all")
    g.setCanvas({state.canvas,depth=true})
    g.clear(.10,.13,.15,1,0,1)
    g.setDepthMode("lequal",true)
    g.setMeshCullMode("none")
    shader:send("modelYaw",0)
    shader:send("modelPosition",{0,0})
    Perspective.send(camera,shader)
    g.setShader(shader)
    g.setColor(1,1,1)
    g.draw(state.floor)
    g.draw(state.rear)
    g.draw(state.fixtures.mesh)
    g.setColor(.48,.46,.40)
    g.draw(state.left);g.draw(state.right);g.draw(state.front)
    g.setColor(1,1,1);g.draw(state.upper)
    g.setColor(.20,.23,.24);g.draw(state.ceiling)
    g.setDepthMode("lequal",false)
    local machineItems=updateMachineItems(Runtime)
    for _,item in ipairs(machineItems) do
        if item.worldX then
            g.setColor(.06,.05,.03,.22)
            g.draw(Grounded.shadow(item,state.white))
        end
    end
    g.setDepthMode("lequal",true)
    for _, item in ipairs(machineItems) do
        if item.id=="windmill" then
            local sprite=getWindmillSprite(Runtime,item)
            if sprite then g.setColor(1,1,1);g.draw(sprite) end
        else
            Props.draw(item,state.white,shader)
        end
    end
    local vehicles=updateVehicleModels(Runtime)
    g.setDepthMode("lequal",false)
    for _,item in ipairs(vehicles) do
        g.setColor(.055,.05,.035,.24)
        g.draw(Grounded.shadow(item,state.white))
    end
    g.setDepthMode("lequal",true)
    for _,item in ipairs(vehicles) do Props.draw(item,state.white,shader) end
    for _, item in ipairs(updatePalletModels(Runtime)) do Props.draw(item,state.white,shader) end
    presentActors(Runtime,camera)
    g.setShader()
    g.setDepthMode()
    g.setCanvas()
    g.pop()
    g.setColor(1,1,1)
    g.draw(state.canvas,0,0)
    drawHelp(Runtime,Runtime.World.prompt())
    return true
end

return View
