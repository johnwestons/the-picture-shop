-- Small walkable town grocery interior with shelf and checkout interactions.
local Animation=require('src.character_animation')
local Config=require('src.config')
local Loader=require('src.image_loader')
local Fonts=require('src.screens.title_fonts')
local Grocery={}
local GRID=8
local COLUMNS,ROWS=120,85
local ART='assets/generated/grocery-interior-v1/'
local LAYERS={
    {key='floor',path=ART..'floor.png'},
    {key='walls',path=ART..'walls.png'},
    {key='produce',path=ART..'produce-stand.png'},
    {key='counter',path=ART..'checkout-counter.png'},
    {key='specials',path=ART..'daily-specials-shelf.png'},
}
local walkArea={left=48,top=92,right=912,bottom=624}
local obstacles={
    -- Wall fixtures. Keep the aisle mouths open so the player can browse them.
    {left=188,top=130,right=326,bottom=240},
    {left=350,top=164,right=602,bottom=240},
    {left=658,top=126,right=794,bottom=244},
    {left=82,top=222,right=154,bottom=390},
    {left=812,top=216,right=882,bottom=386},
    -- Only the footprints block walking; the player can step behind each display.
    {left=153,top=492,right=300,bottom=524},
    {left=670,top=470,right=870,bottom=510},
    {left=404,top=493,right=556,bottom=518},
    -- Preserve the front wall while leaving the open central doorway traversable.
    {left=48,top=570,right=390,bottom=642},
    {left=570,top=570,right=912,bottom=642},
}
Grocery.hotspots={
    {id='produce',x=220,y=462,radius=38,label='Produce'},
    {id='pantry',x=464,y=274,radius=34,label='Pantry aisle'},
    {id='chilled',x=270,y=276,radius=34,label='Chilled goods'},
    {id='household',x=726,y=276,radius=34,label='Household shelf'},
    {id='specials',x=570,y=418,radius=34,label='Daily specials'},
    {id='checkout',x=690,y=420,radius=42,label='Checkout'},
}
local controls={browse={x=24,y=610,w=300,h=44},exit={x=730,y=610,w=206,h=44}}
local colors={cream={.95,.91,.77,1}}
local function insideRect(r,x,y,padding)
    padding=padding or 0
    return x>=r.left-padding and x<=r.right+padding and y>=r.top-padding and y<=r.bottom+padding
end
function Grocery.walkable(x,y)
    if x<walkArea.left or x>walkArea.right or y<walkArea.top or y>walkArea.bottom then return false end
    for _,obstacle in ipairs(obstacles) do if insideRect(obstacle,x,y,16) then return false end end
    return true
end
local function free(cx,cy)
    return cx>=1 and cx<=COLUMNS and cy>=1 and cy<=ROWS
        and Grocery.walkable((cx-.5)*GRID,(cy-.5)*GRID)
end
local function cell(x,y)return math.floor(x/GRID)+1,math.floor(y/GRID)+1 end
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
    for i=1,count do if not Grocery.walkable(ax+(bx-ax)*i/count,ay+(by-ay)*i/count) then return false end end
    return true
end
function Grocery.path(ax,ay,bx,by)
    local sx,sy=nearest(ax,ay);local gx,gy=nearest(bx,by)
    if not sx or not gx then return nil end
    local function key(x,y)return (y-1)*COLUMNS+x end
    local start,goal=key(sx,sy),key(gx,gy)
    local queue,head,previous={start},1,{[start]=false}
    while head<=#queue and previous[goal]==nil do
        local id=queue[head];head=head+1
        local x,y=(id-1)%COLUMNS+1,math.floor((id-1)/COLUMNS)+1
        for _,direction in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            local nx,ny=x+direction[1],y+direction[2];local nextId=key(nx,ny)
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
function Grocery.new(R)
    local original=R.World.player
    local pose={id=original.id,homeResidentId=original.homeResidentId,character=original.character,
        furColorway=original.furColorway,overallsColorway=original.overallsColorway,
        x=480,y=548,intentX=0,intentY=-1,animationDistance=0,idleClock=0,moving=false,
        velocityX=0,velocityY=0}
    return {pose=pose,clock=0,closed=false,path=nil,pathAction=nil,presented=false,
        images={},pending={},ready=false}
end
local function move(view,dx,dy)
    local p=view.pose;local oldX,oldY=p.x,p.y
    local distance=math.sqrt(dx*dx+dy*dy);local steps=math.max(1,math.ceil(distance/3))
    for _=1,steps do
        local nx,ny=p.x+dx/steps,p.y+dy/steps
        if Grocery.walkable(nx,ny) then p.x,p.y=nx,ny
        else
            if Grocery.walkable(nx,p.y) then p.x=nx end
            if Grocery.walkable(p.x,ny) then p.y=ny end
        end
    end
    local moved=math.sqrt((p.x-oldX)^2+(p.y-oldY)^2)
    p.moving=moved>.01;p.animationDistance=p.animationDistance+moved
    if p.moving then p.intentX,p.intentY=(p.x-oldX)/moved,(p.y-oldY)/moved end
end
function Grocery.movePose(pose,dx,dy) move({pose=pose},dx,dy) end
local function nearestHotspot(p)
    local best,distance
    for _,hotspot in ipairs(Grocery.hotspots) do
        local d=(p.x-hotspot.x)^2+(p.y-hotspot.y)^2
        if d<=(hotspot.radius+22)^2 and (not distance or d<distance) then best,distance=hotspot,d end
    end
    return best
end
local function setPath(view,x,y,hotspot)
    view.path=Grocery.path(view.pose.x,view.pose.y,x,y)
    view.pathAction=hotspot and hotspot.id or nil
end
function Grocery.update(view,R,dt)
    if view.closed then return nil end
    local trip=R.state.home and R.state.home.commute
    local shared=trip and trip.independent
    if shared then
        local p=R.World.player
        for _,key in ipairs({'x','y','intentX','intentY','moving','animationDistance'}) do view.pose[key]=p[key] end
    end
    dt=math.max(0,math.min(.1,dt or 0));view.clock=view.clock+dt;view.pose.idleClock=view.clock
    if R.state.screen~='world' then view.pose.moving=false;view.netInputX,view.netInputY=0,0;return nil end
    local dx,dy=0,0
    if R.Input and R.Input.movement then dx,dy=R.Input.movement()
    elseif love.keyboard then
        dx=(love.keyboard.isDown('d','right') and 1 or 0)-(love.keyboard.isDown('a','left') and 1 or 0)
        dy=(love.keyboard.isDown('s','down') and 1 or 0)-(love.keyboard.isDown('w','up') and 1 or 0)
    end
    dx,dy=dx or 0,dy or 0
    local magnitude=math.sqrt(dx*dx+dy*dy)
    if magnitude>.01 then view.path=nil;view.pathAction=nil;dx,dy=dx/magnitude*145*dt,dy/magnitude*145*dt
    elseif view.path and #view.path>0 then
        local goal=view.path[1];dx,dy=goal.x-view.pose.x,goal.y-view.pose.y;magnitude=math.sqrt(dx*dx+dy*dy)
        if magnitude<=145*dt then table.remove(view.path,1) else dx,dy=dx/magnitude*145*dt,dy/magnitude*145*dt end
    end
    if shared then
        view.netInputX=dt>0 and dx/(145*dt) or 0;view.netInputY=dt>0 and dy/(145*dt) or 0
    else move(view,dx,dy) end
    if view.pathAction and (not view.path or #view.path==0) then
        local target
        for _,hotspot in ipairs(Grocery.hotspots) do if hotspot.id==view.pathAction then target=hotspot;break end end
        view.pathAction=nil
        if target and (view.pose.x-target.x)^2+(view.pose.y-target.y)^2<=(target.radius+22)^2 then
            view.pose.moving=false;return target.id
        end
    end
    return nil
end
local function inside(b,x,y)return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
local function openOrWalk(view,hotspot)
    if (view.pose.x-hotspot.x)^2+(view.pose.y-hotspot.y)^2<=(hotspot.radius+22)^2 then return hotspot.id end
    setPath(view,hotspot.x,hotspot.y,hotspot);return nil
end
function Grocery.pointer(view,R,x,y)
    if view.closed then return nil end
    x,y=x*960/R.Config.baseWidth,y*678/R.Config.baseHeight
    if inside(controls.exit,x,y) then return 'exit' end
    local p=view.pose
    if inside(controls.browse,x,y) then
        local nearby=nearestHotspot(p)
        if nearby then return nearby.id end
        local best,distance
        for _,hotspot in ipairs(Grocery.hotspots) do
            local d=(p.x-hotspot.x)^2+(p.y-hotspot.y)^2
            if not distance or d<distance then best,distance=hotspot,d end
        end
        return best and openOrWalk(view,best) or nil
    end
    for _,hotspot in ipairs(Grocery.hotspots) do
        if (x-hotspot.x)^2+(y-hotspot.y)^2<=hotspot.radius^2 then return openOrWalk(view,hotspot) end
    end
    setPath(view,x,y,nil);return nil
end
function Grocery.keypressed(view,key)
    if key=='escape' or key=='back' then return 'exit' end
    if key=='e' or key=='return' or key=='kpenter' then
        local hotspot=nearestHotspot(view.pose)
        if hotspot then return hotspot.id end
    end
    return nil
end
local function color(value)love.graphics.setColor(unpack(value))end
local function label(value,x,y,width,size,tint,align)
    local g=love.graphics;g.setFont(Fonts.get('metal',size));color(tint or colors.cream);g.printf(value,x,y,width,align or 'left')
end
local function drawCashier(R,view)
    local assets=R.CharacterAssets
    local character='green-blazer-cat'
    if not assets or not assets.hasAction(character,'idle') then return end
    local action=assets.hasAction(character,'use') and 'use' or 'idle'
    local count=math.max(1,assets.getFrameCount(character,action))
    local frame=action=='use' and math.floor(view.clock*2.4)%count+1 or math.floor(view.clock*.65)%count+1
    local image,quad=assets.get(character,action,frame)
    if not image or not quad then return end
    local ax,ay=assets.getAnchor(character,action,frame)
    local scale=Config.player.drawScale*.90*assets.getNormalization(character,action)
    love.graphics.setColor(1,1,1);love.graphics.draw(image,quad,650,340,0,scale,scale,ax,ay)
end
local function drawPlayer(R,view)
    local p=view.pose;local assets=R.CharacterAssets
    if not assets then return end
    local trip=R.state.home and R.state.home.commute
    local part=trip and trip.participants and trip.participants[require('src.home_residents').key(p)]
    if require('src.commute.presentation').indoor(p,R.state,assets,part and part.rider.gear) then return end
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
    love.graphics.setColor(1,1,1)
    if character=='rabbit-worker' then
        require('src.rabbit_colorways').draw(image,quad,p.x,p.y,0,scale*(mirror or 1),scale,ax,ay,0,0,p.furColorway,p.overallsColorway)
    else love.graphics.draw(image,quad,p.x,p.y,0,scale*(mirror or 1),scale,ax,ay) end
end
local function loadLayers(view)
    if view.ready or view.error or view.closed then return end
    if not view.presented then return end
    local complete=true
    for _,spec in ipairs(LAYERS) do
        if not view.images[spec.key] then
            local image,reason=Loader.load(spec.path)
            if image then
                view.images[spec.key]=image;view.pending[spec.path]=nil
                image:setFilter('linear','linear')
            elseif reason=='pending' then
                view.pending[spec.path]=true;complete=false
            else
                view.error='Could not open the grocery store artwork.';complete=false;break
            end
        end
    end
    view.ready=complete
end
local function drawMapImage(g,image,x,y,sx,sy)
    if not image then return end
    g.setColor(1,1,1,1);g.draw(image,x,y,0,sx,sy)
end
local function drawMapImageAnchored(g,image,x,y,sx,sy,factor,anchorX,anchorY)
    if not image then return end
    local px,py=x+anchorX*sx,y+anchorY*sy
    g.setColor(1,1,1,1)
    g.draw(image,px-anchorX*sx*factor,py-anchorY*sy*factor,0,sx*factor,sy*factor)
end
local function drawCenteredSprite(g,image,cx,cy,scaleX,scaleY)
    if not image then return end
    g.setColor(1,1,1,1)
    g.draw(image,cx,cy,0,scaleX,scaleY,image:getWidth()/2,image:getHeight()/2)
end
local function drawSceneFixtures(g,view,playerY,front,lowerY)
    local sx,sy=960/1536,678/1024
    local fixtures={
        {key='produce',x=0,y=-110,sx=sx,sy=sy,shrink=.72,anchorX=355,anchorY=975,depth=534},
        {key='counter',x=0,y=0,sx=sx,sy=sy,depth=507},
    }
    local shrink=.32
    fixtures[#fixtures+1]={key='specials',centered=true,cx=480,cy=420,
        sx=sx*shrink,sy=sy*shrink,depth=519}
    table.sort(fixtures,function(a,b)return a.depth<b.depth end)
    for _,fixture in ipairs(fixtures) do
        if (fixture.depth>=playerY)==front and (not lowerY or fixture.depth>=lowerY) then
            local image=view.images[fixture.key]
            if fixture.centered then drawCenteredSprite(g,image,fixture.cx,fixture.cy,fixture.sx,fixture.sy)
            elseif fixture.shrink then drawMapImageAnchored(g,image,fixture.x,fixture.y,fixture.sx,fixture.sy,
                fixture.shrink,fixture.anchorX,fixture.anchorY)
            else drawMapImage(g,image,fixture.x,fixture.y,fixture.sx,fixture.sy) end
        end
    end
end
function Grocery.draw(view,R)
    local g=love.graphics;g.push('all');g.setShader();g.scale(R.Config.baseWidth/960,R.Config.baseHeight/678)
    view.presented=true;loadLayers(view)
    g.setColor(.035,.055,.052,1);g.rectangle('fill',0,0,960,678)
    local sx,sy=960/1536,678/1024
    drawMapImage(g,view.images.floor,0,0,sx,sy)
    drawMapImage(g,view.images.walls,0,0,sx,sy)
    if view.ready then
        local people={view.pose,{cashier=true,y=340}}
        if R.multiplayer and R.multiplayer.remotePlayers then
            for _,p in ipairs(R.multiplayer:remotePlayers()) do
                if p.sceneId=='grocery' then people[#people+1]=p end
            end
        end
        table.sort(people,function(a,b)return a.y<b.y end)
        local previousY=-math.huge
        for _,p in ipairs(people) do
            drawSceneFixtures(g,view,p.y,false,previousY)
            if p.cashier then drawCashier(R,view) else drawPlayer(R,{pose=p}) end
            previousY=p.y
        end
        drawSceneFixtures(g,view,previousY,true)
        for _,hotspot in ipairs(Grocery.hotspots) do
            local nearby=nearestHotspot(view.pose)==hotspot
            g.setColor(.98,.77,.30,nearby and .35 or .14);g.ellipse('fill',hotspot.x,hotspot.y,hotspot.radius*.55,13)
            g.setColor(.98,.77,.30,nearby and .95 or .52);g.ellipse('line',hotspot.x,hotspot.y,hotspot.radius*.55,13)
            label(hotspot.label,hotspot.x-58,hotspot.y+17,116,12,{.19,.24,.18,1},'center')
        end
        if view.path and #view.path>0 then
            g.setColor(.98,.80,.40,.5)
            for i=1,#view.path do local point=view.path[i];g.circle('fill',point.x,point.y,2) end
        end
    else
        label(view.error or 'OPENING TOWN GROCERY...',180,302,600,25,nil,'center')
        label(view.error and 'Return outside and try the store again.' or 'Preparing the grocery store',180,338,600,16,{.70,.78,.72,1},'center')
    end
    g.setColor(.025,.045,.05,.92);g.rectangle('fill',0,0,960,67)
    label('TOWN GROCERY',24,10,560,25,{1,.85,.49,1})
    local mobile=R.mobileControls and R.mobileControls:isEnabled()
    local interactHint=require('src.commute.bindings').hint(
        require('src.commute.runtime').bindings(R),'interact')
    label(mobile and 'Move with the thumbstick. Use INTERACT at a shelf or checkout.'
        or ('Move with WASD / arrows. Press %s at a shelf or checkout to interact.'):format(interactHint),
        24,41,900,15,{.80,.87,.81,1})
    if view.cartCount then
        label(('CART %d  /  $%.2f'):format(view.cartCount,(view.cartTotalCents or 0)/100),650,11,286,18,{1,.85,.49,1},'right')
    end
    local nearby=nearestHotspot(view.pose)
    local browseText=nearby and ('[E] BROWSE '..nearby.label:upper()) or 'WALK TO A DISPLAY OR CHECKOUT'
    if not mobile then
        for _,entry in ipairs({{controls.browse,browseText,true},{controls.exit,'RETURN OUTSIDE',true}}) do
            local b,text,enabled=entry[1],entry[2],entry[3]
            g.setColor(.035,.09,.08,.97);g.rectangle('fill',b.x,b.y,b.w,b.h,5)
            g.setColor(enabled and .91 or .43,enabled and .76 or .48,enabled and .38 or .42,1);g.rectangle('line',b.x,b.y,b.w,b.h,5)
            label(text,b.x+8,b.y+13,b.w-16,16,enabled and {1,.91,.65,1} or {.57,.62,.56,1},'center')
        end
    end
    g.pop();return true
end
function Grocery.release(view)
    if not view or view.closed then return end
    view.closed=true;view.ready=false;view.path=nil;view.pathAction=nil;view.pose=nil
    for _,spec in ipairs(LAYERS) do Loader.cancel(spec.path) end;view.pending={}
    for _,image in pairs(view.images) do if image and image.release then image:release() end end
    view.images={}
end
return Grocery
