-- A local customer view: the authoritative rider and motorcycle stay outside.
local Registration=require('assets.generated.mechanic-shop-v1.registration')
local Navigation=require('assets.generated.mechanic-shop-v1.navigation')
local Loader=require('src.image_loader')
local Fonts=require('src.screens.title_fonts')
local Animation=require('src.character_animation')
local Config=require('src.config')
local WalkMotion=require('src.player_walk_motion')
local Interior={}
local shopName=require('src.commute.sites').MECHANIC_NAME:upper()
Interior.hotspots={{id='counter',x=700,y=430,radius=48,label='Talk to the mechanic',action='catalog'},
    {id='bay',x=300,y=337,radius=62,label='Motorcycle service',action='catalog'},
    {id='door',x=640,y=248,radius=30,label='Return outside',action='exit'}}
local function release(value)if value and value.release then value:release()end end
local function cell(x,y)return math.floor(x/8)+1,math.floor(y/8)+1 end
local function free(cx,cy)
    local row=Navigation.grid[cy]
    return row~=nil and cx>=1 and cx<=Navigation.columns and row:sub(cx,cx)=='1'
end
function Interior.walkable(x,y)local cx,cy=cell(x,y);return free(cx,cy)end
local function nearest(x,y)
    local cx,cy=cell(x,y);if free(cx,cy)then return cx,cy end
    for radius=1,12 do
        local best,ax,ay=math.huge,nil,nil
        for dy=-radius,radius do for dx=-radius,radius do
            if (math.abs(dx)==radius or math.abs(dy)==radius) and free(cx+dx,cy+dy)then
                local d=dx*dx+dy*dy;if d<best then best,ax,ay=d,cx+dx,cy+dy end
            end
        end end
        if ax then return ax,ay end
    end
end
local function lineClear(ax,ay,bx,by)
    local count=math.max(1,math.ceil(math.sqrt((bx-ax)^2+(by-ay)^2)/3))
    for i=1,count do if not Interior.walkable(ax+(bx-ax)*i/count,ay+(by-ay)*i/count)then return false end end
    return true
end
function Interior.path(ax,ay,bx,by)
    local sx,sy=nearest(ax,ay);local gx,gy=nearest(bx,by)
    if not sx or not gx then return nil end
    local function key(x,y)return (y-1)*Navigation.columns+x end
    local start,goal=key(sx,sy),key(gx,gy)
    local queue,head,previous={start},1,{[start]=false}
    while head<=#queue and previous[goal]==nil do
        local id=queue[head];head=head+1
        local x,y=(id-1)%Navigation.columns+1,math.floor((id-1)/Navigation.columns)+1
        for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
            local nx,ny=x+d[1],y+d[2];local nextId=key(nx,ny)
            if free(nx,ny)and previous[nextId]==nil and nextId~=start then previous[nextId]=id;queue[#queue+1]=nextId end
        end
    end
    if previous[goal]==nil then return nil end
    local reversed={};local id=goal
    while id and id~=start do
        reversed[#reversed+1]={x=((id-1)%Navigation.columns+.5)*8,y=(math.floor((id-1)/Navigation.columns)+.5)*8}
        id=previous[id]
    end
    local path={};local x,y=ax,ay;local index=#reversed
    while index>0 do
        local chosen=index
        for candidate=1,index do local p=reversed[candidate];if lineClear(x,y,p.x,p.y)then chosen=candidate;break end end
        local p=reversed[chosen];path[#path+1]=p;x,y=p.x,p.y;index=chosen-1
    end
    return path
end
function Interior.layout(R)
    local sy=R.Config.baseHeight/678;local height=math.max(46,44/sy)
    return {catalog={x=24,y=678-height-12,w=270,h=height},exit={x=728,y=678-height-12,w=208,h=height}}
end
local function inside(b,x,y)return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
function Interior.new(R)
    local original=R.World.player
    local pose={id=original.id,homeResidentId=original.homeResidentId,character=original.character,furColorway=original.furColorway,
        overallsColorway=original.overallsColorway,x=620,y=280,intentX=0,intentY=1,
        animationDistance=0,idleClock=0,moving=false,velocityX=0,velocityY=0}
    local view={pose=pose,clock=0,ready=false,presented=false,closed=false,images={},quads={},pending={},
        requests={{key='background',path=Registration.background},{key='idle',path=Registration.idle.path},
            {key='use',path=Registration.use.path}},loadIndex=1}
    local renderer=R._commute and R._commute.renderer
    local bike=renderer and renderer.bikeArt
    if bike and (bike.parkedFrameCount==16 or bike.frameCount==16) and bike.images and bike.images.parked then
        view.bikeImage=bike.images.parked;view.bikeQuad=bike.quads[5]
        view.bikeQuads=bike.quads;view.bikeFrameCount=bike.frameCount;view.bikeFrame=5
    else view.requests[#view.requests+1]={key='bike',path='assets/commute/bike/parked-16.png'}end
    return view
end
local function loadNext(view)
    local spec=view.requests[view.loadIndex]
    if not spec then view.ready=true;return end
    view.pending[spec.path]=true
    local image,reason=Loader.load(spec.path)
    if not image then if reason~='pending' then view.error='Could not open the service shop artwork.'end;return end
    view.pending[spec.path]=nil;view.images[spec.key]=image
    image:setFilter(spec.key=='background' and 'linear' or 'nearest',spec.key=='background' and 'linear' or 'nearest')
    if spec.key=='idle' or spec.key=='use' then
        local r=Registration[spec.key];view.quads[spec.key]={}
        for frame=1,r.frames do view.quads[spec.key][frame]=love.graphics.newQuad((frame-1)*512,0,512,512,r.width,r.height)end
    elseif spec.key=='bike' then
        view.bikeImage=image;view.bikeQuads={};view.bikeFrameCount=16;view.bikeFrame=5
        for frame=1,16 do view.bikeQuads[frame]=love.graphics.newQuad((frame-1)%4*320,math.floor((frame-1)/4)*320,320,320,1280,1280) end
        view.bikeQuad=view.bikeQuads[5];view.ownedBikeQuads=true
    end
    view.loadIndex=view.loadIndex+1;view.ready=view.loadIndex>#view.requests
end
function Interior.update(view,R,dt)
    if view.closed then return end
    dt=math.max(0,math.min(.1,dt or 0));view.clock=view.clock+dt;view.pose.idleClock=view.clock
    -- Opening always presents a visible loading frame before any resource work.
    if not view.presented then return end
    if not view.ready and not view.error then loadNext(view)end
    if not view.ready then return end
    -- Menus pause local controls while resource loading and service clocks continue.
    if R.state.screen~='world' then view.pose.moving=false;return end
    local shop=R._commute and R._commute.mechanicOffer
    if shop and shop.page~='lobby' then view.path=nil;view.pose.moving=false;return end
    local dx,dy=0,0
    if R.Input and R.Input.movement then dx,dy=R.Input.movement()
    elseif love.keyboard then
        dx=(love.keyboard.isDown('d','right')and 1 or 0)-(love.keyboard.isDown('a','left')and 1 or 0)
        dy=(love.keyboard.isDown('s','down')and 1 or 0)-(love.keyboard.isDown('w','up')and 1 or 0)
    end
    dx,dy=dx or 0,dy or 0
    local magnitude=math.sqrt(dx*dx+dy*dy)
    if magnitude>.01 then view.path=nil
    else dx,dy=WalkMotion.pathInput(view.pose,view.path) end
    WalkMotion.update(view.pose,dx,dy,dt,Interior.walkable,R.state)
    WalkMotion.consumeReached(view.pose,view.path)
end
function Interior.pointer(view,R,x,y)
    if view.closed then return nil end
    x,y=x*960/R.Config.baseWidth,y*678/R.Config.baseHeight
    local layout=Interior.layout(R)
    if inside(layout.exit,x,y)then return 'exit' end
    if not view.ready then return nil end
    if inside(layout.catalog,x,y)then return 'catalog' end
    for _,hotspot in ipairs(Interior.hotspots)do
        if (x-hotspot.x)^2+(y-hotspot.y)^2<=hotspot.radius^2 then return hotspot.action end
    end
    view.path=Interior.path(view.pose.x,view.pose.y,x,y)
    return nil
end
function Interior.keypressed(view,R,key)
    if key=='escape' or key=='back' then return 'exit' end
    if not view.ready or view.closed then return nil end
    if key=='c' then return 'catalog' end
    if key=='e' or key=='return' or key=='kpenter' then
        local best,selected=math.huge,nil
        for _,hotspot in ipairs(Interior.hotspots)do
            local d=(view.pose.x-hotspot.x)^2+(view.pose.y-hotspot.y)^2
            if d<(hotspot.radius+28)^2 and d<best then best,selected=d,hotspot end
        end
        return selected and selected.action
    end
end
local function label(value,x,y,width,size,color,align)
    local g=love.graphics;g.setFont(Fonts.get('metal',size));g.setColor(unpack(color or {.95,.91,.78,1}))
    g.printf(value,x,y,width,align or 'left')
end
local function player(view,R)
    local p=view.pose;local assets=R.CharacterAssets
    local trip=R.state.home and R.state.home.commute
    local part=trip and trip.participants and trip.participants[require('src.home_residents').key(R.World.player)]
    local presentation=require('src.commute.presentation')
    if assets and presentation.indoor(p,R.state,assets,part and part.rider.gear,presentation.STORE_RIDER_SCALE)then return end
    if not assets then return end
    local character=p.character or Config.player.character
    local action,mirror
    if p.moving then action,mirror=Animation.actorWalkAction(p)else action,mirror=Animation.directionalIdleAction(p.intentX,p.intentY)end
    if not assets.hasAction(character,action)then action=p.moving and 'walk' or 'idle' end
    if assets.resolveAction then action=assets.resolveAction(character,action)end
    local _,_,count=assets.get(character,action,1)
    local frame=Animation.frameForPlayerAction(action,count or 1,p.animationDistance,p.idleClock,
        Config.player.walkPixelsPerFrame,Config.player.idleAnimationRate)
    local image,quad=assets.get(character,action,frame)
    if image and quad then
        local ax,ay=assets.getAnchor(character,action,frame);local scale=Config.player.drawScale*assets.getNormalization(character,action)
        love.graphics.setColor(1,1,1)
        if character=='rabbit-worker' then require('src.rabbit_colorways').draw(image,quad,p.x,p.y,0,scale*(mirror or 1),scale,ax,ay,0,0,p.furColorway,p.overallsColorway)
        else love.graphics.draw(image,quad,p.x,p.y,0,scale*(mirror or 1),scale,ax,ay)end
    end
end
function Interior.drawBike(view,R,x,y,scale,paintId,frame)
    if not view.ready or view.closed or not view.bikeImage then return false end
    local resident=require('src.home_residents').get(R.state,R.World.player)
    paintId=paintId or resident and resident.ridingPaintId or 'bronze'
    frame=frame or view.bikeFrame or 5
    local quad=view.bikeQuads and view.bikeQuads[frame] or view.bikeQuad
    love.graphics.setColor(1,1,1)
    require('src.commute.bike_paint_art').draw(view.bikeImage,quad,paintId,x,y,0,scale,scale,160,260,frame,'parked')
    return true
end
function Interior.drawMechanic(view,R,x,y,scale)
    if not view.ready or view.closed then return false end
    local shop=R._commute and R._commute.mechanicOffer
    local action=shop and shop.page=='install' and 'use' or 'idle'
    local spec=Registration[action];local tick=math.floor(view.clock*spec.fps)
    local frame=action=='use' and ({1,2,3,2})[tick%4+1]or tick%spec.frames+1
    local anchor=spec.anchors[frame]
    x=x or (action=='use' and 355 or 666);y=y or (action=='use' and 365 or 407);scale=scale or .218
    love.graphics.setColor(1,1,1)
    love.graphics.draw(view.images[action],view.quads[action][frame],x,y,0,scale,scale,anchor[1],anchor[2])
    return true
end
function Interior.draw(view,R)
    local g=love.graphics;g.push('all');g.setShader();g.scale(R.Config.baseWidth/960,R.Config.baseHeight/678)
    g.setColor(.025,.035,.04,1);g.rectangle('fill',0,0,960,678)
    view.presented=true
    if view.ready and not view.closed then
        g.setColor(1,1,1);g.draw(view.images.background,0,0,0,960/1536,678/1024)
        for _,h in ipairs(Interior.hotspots)do
            g.setColor(.98,.78,.32,.26);g.ellipse('fill',h.x,h.y,h.radius*.52,13)
            g.setColor(.98,.78,.32,.75);g.ellipse('line',h.x,h.y,h.radius*.52,13)
        end
        Interior.drawBike(view,R,300,330,.60)
        if view.pose.y<407 then player(view,R);Interior.drawMechanic(view,R)else Interior.drawMechanic(view,R);player(view,R)end
        for _,h in ipairs(Interior.hotspots)do label(h.label,h.x-95,h.y+17,190,14,nil,'center')end
    else
        label(view.error or 'OPENING '..shopName..'...',180,290,600,26,nil,'center')
        label(view.error and 'Return outside and try the service door again.'or 'Preparing the shop floor',180,332,600,17,{.65,.76,.74,1},'center')
    end
    g.setColor(.02,.04,.04,.92);g.rectangle('fill',0,0,960,67)
    label(shopName,24,12,600,26,{1,.84,.46,1})
    label('Motorcycle service  /  Tap a work area or click the floor to walk',24,43,900,15,{.78,.85,.81,1})
    local layout=Interior.layout(R)
    for _,entry in ipairs({{layout.catalog,'[C] BROWSE SERVICES',view.ready},{layout.exit,'RETURN OUTSIDE',true}})do
        local b,text,enabled=entry[1],entry[2],entry[3]
        g.setColor(.035,.09,.08,.97);g.rectangle('fill',b.x,b.y,b.w,b.h,5)
        g.setColor(enabled and .91 or .4,enabled and .76 or .45,enabled and .38 or .4,1);g.rectangle('line',b.x,b.y,b.w,b.h,5)
        label(text,b.x+8,b.y+(b.h-18)/2,b.w-16,18,enabled and {1,.91,.65,1}or {.5,.55,.5,1},'center')
    end
    g.pop();return true
end
function Interior.release(view)
    if not view or view.closed then return end
    view.closed=true;view.ready=false;view.path=nil
    for path in pairs(view.pending)do Loader.cancel(path)end;view.pending={}
    for _,image in pairs(view.images)do release(image)end;view.images={}
    for _,quads in pairs(view.quads)do for _,quad in ipairs(quads)do release(quad)end end;view.quads={}
    if view.ownedBikeQuads then for _,quad in ipairs(view.bikeQuads) do release(quad) end end
    view.bikeQuads=nil
    view.bikeImage,view.bikeQuad=nil,nil
end
return Interior
