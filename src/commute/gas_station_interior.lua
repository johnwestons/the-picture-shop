-- Walkable gas station shop floor. Payment and service details stay in the
-- existing station panel; this room provides the shared indoor controls.
local Animation=require('src.character_animation')
local Config=require('src.config')
local WalkMotion=require('src.player_walk_motion')
local Loader=require('src.image_loader')
local Fonts=require('src.screens.title_fonts')
local DisplayFonts=require('src.screens.reference_display_fonts')
local Room={}
local GRID,COLUMNS,ROWS=8,120,85
local ART='assets/generated/gas-station-interior-v1/'
local LAYERS={
    {key='floor',path=ART..'floor.png'},
    {key='walls',path=ART..'walls.png'},
    {key='wallShelf',path=ART..'wall-shelf.png'},
    {key='aisle',path=ART..'aisle-gondola.png'},
    {key='counter',path=ART..'service-counter.png'},
    {key='candy',path=ART..'candy-bar.png'},
    {key='gum',path=ART..'chewing-gum.png'},
}
local walkArea={left=44,top=91,right=916,bottom=616}
local obstacles={
    {left=42,top=90,right=108,bottom=570},
    {left=850,top=90,right=918,bottom=570},
    {left=110,top=88,right=840,bottom=128},
    {left=110,top=560,right=390,bottom=620},
    {left=574,top=560,right=850,bottom=620},
    {left=350,top=130,right=610,bottom=220},
    {left=140,top=224,right=410,bottom=408},
    {left=530,top=224,right=800,bottom=408},
    {left=580,top=396,right=870,bottom=486},
}
Room.hotspots={
    {id='shop',x=768,y=522,radius=48,label='Buy snacks'},
    {id='counter',x=626,y=522,radius=44,label='Fuel and oil services'},
}
local controls={shop={x=24,y=610,w=270,h=44},service={x=310,y=610,w=390,h=44},
    exit={x=730,y=610,w=206,h=44}}
local function insideRect(r,x,y,padding)
    padding=padding or 0
    return x>=r.left-padding and x<=r.right+padding and y>=r.top-padding and y<=r.bottom+padding
end
function Room.walkable(x,y)
    if x<walkArea.left or x>walkArea.right or y<walkArea.top or y>walkArea.bottom then return false end
    for _,obstacle in ipairs(obstacles) do if insideRect(obstacle,x,y,12) then return false end end
    return true
end
local function cell(x,y)return math.floor(x/GRID)+1,math.floor(y/GRID)+1 end
local function free(cx,cy)
    return cx>=1 and cx<=COLUMNS and cy>=1 and cy<=ROWS
        and Room.walkable((cx-.5)*GRID,(cy-.5)*GRID)
end
local function nearest(x,y)
    local cx,cy=cell(x,y)
    if free(cx,cy) then return cx,cy end
    for radius=1,14 do
        local best,ax,ay=math.huge,nil,nil
        for dy=-radius,radius do for dx=-radius,radius do
            if (math.abs(dx)==radius or math.abs(dy)==radius) and free(cx+dx,cy+dy) then
                local distance=dx*dx+dy*dy
                if distance<best then best,ax,ay=distance,cx+dx,cy+dy end
            end
        end end
        if ax then return ax,ay end
    end
end
local function lineClear(ax,ay,bx,by)
    local count=math.max(1,math.ceil(math.sqrt((bx-ax)^2+(by-ay)^2)/3))
    for i=1,count do if not Room.walkable(ax+(bx-ax)*i/count,ay+(by-ay)*i/count) then return false end end
    return true
end
function Room.path(ax,ay,bx,by)
    local sx,sy=nearest(ax,ay);local gx,gy=nearest(bx,by)
    if not sx or not gx then return nil end
    local function key(x,y)return (y-1)*COLUMNS+x end
    local start,goal=key(sx,sy),key(gx,gy)
    local queue,head,previous={start},1,{[start]=false}
    while head<=#queue and previous[goal]==nil do
        local id=queue[head];head=head+1
        local x,y=(id-1)%COLUMNS+1,math.floor((id-1)/COLUMNS)+1
        for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            local nx,ny=x+d[1],y+d[2];local nextId=key(nx,ny)
            if free(nx,ny) and previous[nextId]==nil and nextId~=start then
                previous[nextId]=id;queue[#queue+1]=nextId
            end
        end
    end
    if previous[goal]==nil then return nil end
    local reversed={};local id=goal
    while id and id~=start do
        reversed[#reversed+1]={x=((id-1)%COLUMNS+.5)*GRID,y=(math.floor((id-1)/COLUMNS)+.5)*GRID}
        id=previous[id]
    end
    local path={};local x,y=ax,ay;local index=#reversed
    while index>0 do
        local chosen=index
        for candidate=1,index do
            local point=reversed[candidate]
            if lineClear(x,y,point.x,point.y) then chosen=candidate;break end
        end
        local point=reversed[chosen];path[#path+1]=point;x,y=point.x,point.y;index=chosen-1
    end
    return path
end
function Room.new(R)
    local original=R.World.player
    return {pose={id=original.id,homeResidentId=original.homeResidentId,character=original.character,
        furColorway=original.furColorway,overallsColorway=original.overallsColorway,
        x=480,y=528,intentX=0,intentY=-1,animationDistance=0,idleClock=0,moving=false,
        velocityX=0,velocityY=0},clock=0,closed=false,path=nil,pathAction=nil,
        images={},pending={},ready=false,presented=false}
end
local function nearestHotspot(p)
    local best,distance
    for _,hotspot in ipairs(Room.hotspots) do
        local d=(p.x-hotspot.x)^2+(p.y-hotspot.y)^2
        if d<=(hotspot.radius+22)^2 and (not distance or d<distance) then best,distance=hotspot,d end
    end
    return best
end
local function setPath(view,x,y,hotspot)
    view.path=Room.path(view.pose.x,view.pose.y,x,y)
    view.pathAction=hotspot and hotspot.id or nil
end
function Room.update(view,R,dt)
    if view.closed then return nil end
    dt=math.max(0,math.min(.1,dt or 0));view.clock=view.clock+dt;view.pose.idleClock=view.clock
    if not view.presented then return nil end
    if not view.ready then
        local complete=true
        for _,spec in ipairs(LAYERS) do
            if not view.images[spec.key] then
                local image,reason=Loader.load(spec.path)
                if image then view.images[spec.key]=image;view.pending[spec.path]=nil;image:setFilter('linear','linear')
                elseif reason=='pending' then view.pending[spec.path]=true;complete=false
                else view.error='Could not open the gas station artwork.';complete=false;break end
            end
        end
        view.ready=complete
    end
    if not view.ready then return nil end
    if R.state.screen~='world' then view.pose.moving=false;return nil end
    local dx,dy=0,0
    if R.Input and R.Input.movement then dx,dy=R.Input.movement()
    elseif love.keyboard then
        dx=(love.keyboard.isDown('d','right') and 1 or 0)-(love.keyboard.isDown('a','left') and 1 or 0)
        dy=(love.keyboard.isDown('s','down') and 1 or 0)-(love.keyboard.isDown('w','up') and 1 or 0)
    end
    dx,dy=dx or 0,dy or 0
    local magnitude=math.sqrt(dx*dx+dy*dy)
    if magnitude>.01 then view.path=nil;view.pathAction=nil
    else dx,dy=WalkMotion.pathInput(view.pose,view.path) end
    WalkMotion.update(view.pose,dx,dy,dt,Room.walkable,R.state)
    WalkMotion.consumeReached(view.pose,view.path)
    if view.pathAction and (not view.path or #view.path==0) then
        local target
        for _,hotspot in ipairs(Room.hotspots) do if hotspot.id==view.pathAction then target=hotspot;break end end
        view.pathAction=nil
        if target and (view.pose.x-target.x)^2+(view.pose.y-target.y)^2<=(target.radius+22)^2 then
            view.pose.moving=false;return target.id
        end
    end
end
local function inside(b,x,y)return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
local function openOrWalk(view,hotspot)
    if (view.pose.x-hotspot.x)^2+(view.pose.y-hotspot.y)^2<=(hotspot.radius+22)^2 then return hotspot.id end
    setPath(view,hotspot.x,hotspot.y,hotspot);return nil
end
function Room.pointer(view,R,x,y)
    if view.closed then return nil end
    x,y=x*960/R.Config.baseWidth,y*678/R.Config.baseHeight
    if inside(controls.exit,x,y) then return 'exit' end
    if inside(controls.shop,x,y) then return openOrWalk(view,Room.hotspots[1]) end
    if inside(controls.service,x,y) then return openOrWalk(view,Room.hotspots[2]) end
    for _,hotspot in ipairs(Room.hotspots) do
        if (x-hotspot.x)^2+(y-hotspot.y)^2<=hotspot.radius^2 then return openOrWalk(view,hotspot) end
    end
    view.path=Room.path(view.pose.x,view.pose.y,x,y);view.pathAction=nil
    return nil
end
function Room.keypressed(view,key)
    if key=='escape' or key=='back' then return 'exit' end
    if key=='e' or key=='return' or key=='kpenter' then
        local hotspot=nearestHotspot(view.pose)
        if hotspot then return hotspot.id end
    end
end
local function label(value,x,y,width,size,tint,align)
    local g=love.graphics;g.setFont(Fonts.get('metal',size));g.setColor(unpack(tint or {.95,.91,.77,1}))
    g.printf(value,x,y,width,align or 'left')
end
local function drawImage(g,image,x,y,sx,sy)
    if not image then return end
    g.setColor(1,1,1,1);g.draw(image,x,y,0,sx,sy)
end
local function drawCentered(g,image,cx,cy,sx,sy)
    if not image then return end
    g.setColor(1,1,1,1);g.draw(image,cx,cy,0,sx,sy,image:getWidth()/2,image:getHeight()/2)
end
local function drawCharacter(R,p)
    local assets=R.CharacterAssets
    if not assets then return end
    local trip=R.state.home and R.state.home.commute
    local part=trip and trip.participants and trip.participants[require('src.home_residents').key(p)]
    local presentation=require('src.commute.presentation')
    if presentation.indoor(p,R.state,assets,part and part.rider.gear,presentation.STORE_RIDER_SCALE) then return end
    local character=p.character or Config.player.character
    local action,mirror
    if p.moving then action,mirror=Animation.actorWalkAction(p)
    else action,mirror=Animation.directionalIdleAction(p.intentX,p.intentY) end
    if not assets.hasAction(character,action) then action=p.moving and 'walk' or 'idle' end
    if assets.resolveAction then action=assets.resolveAction(character,action) end
    local _,_,count=assets.get(character,action,1)
    local frame=Animation.frameForPlayerAction(action,count or 1,p.animationDistance,p.idleClock,
        Config.player.walkPixelsPerFrame,Config.player.idleAnimationRate)
    local image,quad=assets.get(character,action,frame)
    if not image or not quad then return end
    local ax,ay=assets.getAnchor(character,action,frame)
    local scale=Config.player.drawScale*assets.getNormalization(character,action)
    love.graphics.setColor(1,1,1,1)
    if character=='rabbit-worker' then require('src.rabbit_colorways').draw(image,quad,p.x,p.y,0,scale*(mirror or 1),scale,ax,ay,0,0,p.furColorway,p.overallsColorway)
    else love.graphics.draw(image,quad,p.x,p.y,0,scale*(mirror or 1),scale,ax,ay) end
end
local function drawAttendant(R,view)
    local assets=R.CharacterAssets;local character='green-blazer-cat'
    if not assets or not assets.hasAction(character,'idle') then return end
    local action=assets.hasAction(character,'use') and 'use' or 'idle'
    local count=math.max(1,assets.getFrameCount(character,action))
    local frame=action=='use' and math.floor(view.clock*2.2)%count+1 or math.floor(view.clock*.65)%count+1
    local image,quad=assets.get(character,action,frame)
    if not image or not quad then return end
    local ax,ay=assets.getAnchor(character,action,frame)
    local scale=Config.player.drawScale*.88*assets.getNormalization(character,action)
    love.graphics.setColor(1,1,1,1);love.graphics.draw(image,quad,714,350,0,scale,scale,ax,ay)
end
function Room.draw(view,R)
    local g=love.graphics;g.push('all');g.setShader();g.scale(R.Config.baseWidth/960,R.Config.baseHeight/678)
    view.presented=true;g.setColor(.035,.055,.052,1);g.rectangle('fill',0,0,960,678)
    local footprints=require('src.player_footprints')
    if view.pose then
        footprints.update(R.state,{x=view.pose.x,y=view.pose.y,moving=view.pose.moving,
            sceneId='station'},nil,love.timer.getTime())
    end
    local sx,sy=960/1536,678/1024
    drawImage(g,view.images.floor,0,0,sx,sy);footprints.draw('station')
    drawImage(g,view.images.walls,0,0,sx,sy)
    drawCentered(g,view.images.wallShelf,480,225,sx*.43,sy*.43)
    local function drawAisles()
        drawCentered(g,view.images.aisle,300,358,sx*.30,sy*.30)
        drawCentered(g,view.images.aisle,660,358,sx*.30,sy*.30)
    end
    local function drawCounter()
        drawCentered(g,view.images.counter,730,420,sx*.46,sy*.46)
        drawCentered(g,view.images.candy,718,395,sx*.075,sy*.075)
        drawCentered(g,view.images.gum,770,396,sx*.075,sy*.075)
    end
    if view.ready and not view.closed then
        local playerY=view.pose.y
        drawAttendant(R,view)
        if playerY<470 then
            drawCharacter(R,view.pose);drawAisles();drawCounter()
        else
            drawAisles();drawCounter();drawCharacter(R,view.pose)
        end
        for _,hotspot in ipairs(Room.hotspots) do
            local nearby=nearestHotspot(view.pose)==hotspot
            g.setColor(.98,.77,.30,nearby and .34 or .14);g.ellipse('fill',hotspot.x,hotspot.y,hotspot.radius*.55,13)
            g.setColor(.98,.77,.30,nearby and .95 or .52);g.ellipse('line',hotspot.x,hotspot.y,hotspot.radius*.55,13)
            label(hotspot.label,hotspot.x-80,hotspot.y+20,160,13,{.19,.24,.18,1},'center')
        end
        if view.path and #view.path>0 then
            g.setColor(.98,.80,.40,.5);for _,point in ipairs(view.path) do g.circle('fill',point.x,point.y,2) end
        end
    else
        drawAisles();drawCounter()
        label(view.error or 'OPENING GAS STATION...',180,302,600,25,nil,'center')
        label(view.error and 'Return outside and try again.' or 'Preparing the gas station',180,338,600,16,{.70,.78,.72,1},'center')
    end
    g.setColor(.025,.045,.05,.92);g.rectangle('fill',0,0,960,67)
    g.setColor(1,.85,.49,1);DisplayFonts.draw('groovySlab','GAS STATION',24,7,34,'left',700)
    g.setFont(Fonts.get('metal',13));g.print('/ CONVENIENCE STORE',215,27)
    local mobile=R.mobileControls and R.mobileControls:isEnabled()
    local interactHint=require('src.commute.bindings').hint(
        require('src.commute.runtime').bindings(R),'interact')
    label(mobile and 'Move with the thumbstick. Shop with the clerk or choose fuel and oil services.'
        or ('Move with WASD / arrows. Press %s near the counter to shop or open fuel and oil services.'):format(interactHint),
        24,41,900,15,{.80,.87,.81,1})
    if not mobile then
        for _,entry in ipairs({{controls.shop,'SHOP WITH CLERK'},{controls.service,'FUEL / OIL SERVICES'},
            {controls.exit,'RETURN OUTSIDE'}}) do
            local b,text=entry[1],entry[2]
            g.setColor(.035,.09,.08,.97);g.rectangle('fill',b.x,b.y,b.w,b.h,5)
            g.setColor(.91,.76,.38,1);g.rectangle('line',b.x,b.y,b.w,b.h,5)
            label(text,b.x+8,b.y+13,b.w-16,16,{1,.91,.65,1},'center')
        end
    end
    g.pop();return true
end
function Room.release(view)
    if not view or view.closed then return end
    view.closed=true;view.ready=false;view.path=nil;view.pose=nil
    for _,spec in ipairs(LAYERS) do Loader.cancel(spec.path) end
    view.pending={}
    for _,image in pairs(view.images) do if image and image.release then image:release() end end
    view.images={}
end
return Room
