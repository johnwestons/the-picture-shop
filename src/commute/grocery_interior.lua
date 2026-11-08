-- Small walkable town grocery interior with shelf and checkout interactions.
local Animation=require('src.character_animation')
local Config=require('src.config')
local WalkMotion=require('src.player_walk_motion')
local Loader=require('src.image_loader')
local Fonts=require('src.screens.title_fonts')
local GroceryUiArt=require('src.commute.grocery_ui_art')
local Grocery={}
local GRID=8
local COLUMNS,ROWS=120,85
local ART='assets/generated/grocery-interior-v1/'
local CART_ART='assets/generated/grocery-cart-v1/cart-roll-atlas.png'
local LAYERS={
    {key='floor',path=ART..'floor.png'},
    {key='walls',path=ART..'walls.png'},
    {key='produce',path=ART..'produce-stand.png'},
    {key='counter',path=ART..'checkout-counter.png'},
    {key='specials',path=ART..'daily-specials-shelf.png'},
    {key='cart',path=CART_ART},
}
local CART_SIZE,CART_SCALE=128,.62
local CART_ITEM_ORDER={'vegetables','bread','cereal','sandwich','drink','meal','cup','meal_pack'}
local CART_ITEM_COLORS={
    vegetables={.33,.62,.28,1},bread={.77,.48,.23,1},cereal={.9,.69,.24,1},
    sandwich={.54,.67,.34,1},drink={.3,.59,.78,1},meal={.81,.43,.26,1},
    cup={.82,.83,.70,1},meal_pack={.63,.45,.29,1},
}
local CART_VIEWS={
    north={row=1,mirror=false},northeast={row=2,mirror=false},east={row=3,mirror=false},
    southeast={row=4,mirror=false},south={row=5,mirror=false},
    southwest={row=4,mirror=true},west={row=3,mirror=true},northwest={row=2,mirror=true},
}
local cartOffsets={
    north={x=0,y=-3},northeast={x=16,y=-4},east={x=25,y=12},southeast={x=18,y=32},
    south={x=0,y=34},southwest={x=-18,y=32},west={x=-25,y=12},northwest={x=-16,y=-4},
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
        {id='checkout',x=690,y=420,radius=42,label='Checkout / Register'},
}
local controls={browse={x=24,y=610,w=300,h=44},exit={x=730,y=610,w=206,h=44}}
local colors={cream={.95,.91,.77,1}}
local function insideRect(r,x,y,padding)
    padding=padding or 0
    return x>=r.left-padding and x<=r.right+padding and y>=r.top-padding and y<=r.bottom+padding
end
function Grocery.walkable(x,y,extraPadding)
    extraPadding=math.max(0,tonumber(extraPadding) or 0)
    if x<walkArea.left+extraPadding or x>walkArea.right-extraPadding
        or y<walkArea.top+extraPadding or y>walkArea.bottom-extraPadding then return false end
    for _,obstacle in ipairs(obstacles) do if insideRect(obstacle,x,y,16+extraPadding) then return false end end
    return true
end
local function free(cx,cy,extraPadding)
    return cx>=1 and cx<=COLUMNS and cy>=1 and cy<=ROWS
        and Grocery.walkable((cx-.5)*GRID,(cy-.5)*GRID,extraPadding)
end
local function cell(x,y)return math.floor(x/GRID)+1,math.floor(y/GRID)+1 end
local function nearest(x,y,extraPadding)
    local cx,cy=cell(x,y)
    if free(cx,cy,extraPadding) then return cx,cy end
    for radius=1,14 do
        local best,ax,ay=math.huge,nil,nil
        for dy=-radius,radius do for dx=-radius,radius do
            if (math.abs(dx)==radius or math.abs(dy)==radius) and free(cx+dx,cy+dy,extraPadding) then
                local distance=dx*dx+dy*dy
                if distance<best then best,ax,ay=distance,cx+dx,cy+dy end
            end
        end end
        if ax then return ax,ay end
    end
end
local function lineClear(ax,ay,bx,by,extraPadding)
    local count=math.max(1,math.ceil(math.sqrt((bx-ax)^2+(by-ay)^2)/3))
    for i=1,count do if not Grocery.walkable(ax+(bx-ax)*i/count,ay+(by-ay)*i/count,extraPadding) then return false end end
    return true
end
function Grocery.path(ax,ay,bx,by,extraPadding)
    local sx,sy=nearest(ax,ay,extraPadding);local gx,gy=nearest(bx,by,extraPadding)
    if not sx or not gx then return nil end
    local function key(x,y)return (y-1)*COLUMNS+x end
    local start,goal=key(sx,sy),key(gx,gy)
    local queue,head,previous={start},1,{[start]=false}
    while head<=#queue and previous[goal]==nil do
        local id=queue[head];head=head+1
        local x,y=(id-1)%COLUMNS+1,math.floor((id-1)/COLUMNS)+1
        for _,direction in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            local nx,ny=x+direction[1],y+direction[2];local nextId=key(nx,ny)
            if free(nx,ny,extraPadding) and previous[nextId]==nil and nextId~=start then
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
            if lineClear(x,y,point.x,point.y,extraPadding) then chosen=candidate;break end
        end
        local point=reversed[chosen];path[#path+1]=point;x,y=point.x,point.y;index=chosen-1
    end
    return path
end
function Grocery.new(R)
    local original=R.World.player
    local key=require('src.home_residents').key(original)
    local trip=R.state.home and R.state.home.commute
    local part=trip and trip.participants and trip.participants[key]
    local cartPushed=part and part.interiorPose and part.interiorPose.cartPushing==true or false
    local pose={id=original.id,homeResidentId=original.homeResidentId,character=original.character,
        furColorway=original.furColorway,overallsColorway=original.overallsColorway,
        x=480,y=548,intentX=0,intentY=-1,animationDistance=0,idleClock=0,moving=false,
        velocityX=0,velocityY=0,cartPushing=cartPushed}
    return {pose=pose,clock=0,closed=false,path=nil,pathAction=nil,presented=false,
        cartPose={x=520,y=548,direction='east',pushed=cartPushed},cartCount=0,cartTotalCents=0,
        images={},pending={},ready=false}
end
function Grocery.movePose(pose,inputX,inputY,dt,state)
    local directionX,directionY=tonumber(inputX) or 0,tonumber(inputY) or 0
    if directionX*directionX+directionY*directionY<.0001 then
        directionX,directionY=pose.intentX or 0,pose.intentY or -1
    end
    local direction=Animation.authoredDirection(directionX,directionY)
    local offset=cartOffsets[direction] or cartOffsets.north
    return WalkMotion.update(pose,inputX,inputY,dt,function(x,y)
        if not Grocery.walkable(x,y) then return false end
        if pose.cartPushing then return Grocery.walkable(x+offset.x,y+offset.y,10) end
        return (x-520)^2+(y-548)^2>=28^2
    end,state)
end
function Grocery.atCheckout(pose)
    if type(pose)~='table' then return false end
    local hotspot
    for _,entry in ipairs(Grocery.hotspots) do if entry.id=='checkout' then hotspot=entry;break end end
    if not hotspot then return false end
    local radius=hotspot.radius+22
    return (pose.x-hotspot.x)^2+(pose.y-hotspot.y)^2<=radius*radius
end
local function directionOf(pose)
    return Animation.authoredDirection(pose.intentX or 0,pose.intentY or -1)
end
function Grocery.cartPosition(view)
    local cart=view and view.cartPose
    if not cart then return nil end
    if not cart.pushed then return cart.x,cart.y,cart.direction,false end
    local direction=directionOf(view.pose)
    local offset=cartOffsets[direction] or cartOffsets.north
    return view.pose.x+offset.x,view.pose.y+offset.y,direction,true
end
function Grocery.cartPositionForPose(pose)
    if type(pose)~='table' then return nil end
    local direction=directionOf(pose)
    local offset=cartOffsets[direction] or cartOffsets.north
    return pose.x+offset.x,pose.y+offset.y,direction,true
end
local function nearCart(view,x,y)
    local cart=view.cartPose
    if not cart or cart.pushed then return false end
    local radius=54
    return (x-cart.x)^2+(y-cart.y)^2<=radius*radius
end
local function parkCart(view)
    view.cartPose.x,view.cartPose.y,view.cartPose.direction=520,548,'east'
    view.cartPose.pushed=false
    view.pose.cartPushing=false
    view.path,view.pathAction=nil,nil
    view.notice='Shopping cart returned to the entrance rack.'
    return 'cartpush_off'
end
local function takeCart(view)
    view.cartPose.pushed=true
    view.pose.cartPushing=true
    view.path,view.pathAction=nil,nil
    view.notice='Shopping cart ready. Push it through the aisles; bring it to the register to check out.'
    return 'cartpush_on'
end
local function nearestHotspot(p)
    local best,distance
    for _,hotspot in ipairs(Grocery.hotspots) do
        local d=(p.x-hotspot.x)^2+(p.y-hotspot.y)^2
        if d<=(hotspot.radius+22)^2 and (not distance or d<distance) then best,distance=hotspot,d end
    end
    return best
end
local function setPath(view,x,y,hotspot)
    view.path=Grocery.path(view.pose.x,view.pose.y,x,y,view.cartPose.pushed and 12 or 0)
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
    view.pose.cartPushing=view.cartPose and view.cartPose.pushed==true or false
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
    if magnitude>.01 then view.path=nil;view.pathAction=nil
    else dx,dy=WalkMotion.pathInput(view.pose,view.path) end
    if view.cartPose.pushed then dx,dy=dx*.78,dy*.78 end
    if shared then
        view.netInputX,view.netInputY=dx,dy
    else
        Grocery.movePose(view.pose,dx,dy,dt,R.state)
        WalkMotion.consumeReached(view.pose,view.path)
    end
    if view.pathAction and (not view.path or #view.path==0) then
        local target
        for _,hotspot in ipairs(Grocery.hotspots) do if hotspot.id==view.pathAction then target=hotspot;break end end
        view.pathAction=nil
        if target and (view.pose.x-target.x)^2+(view.pose.y-target.y)^2<=(target.radius+22)^2 then
            view.pose.moving=false
            if not view.cartPose.pushed then
                view.notice='Take the shopping cart before collecting groceries or checking out.'
                return nil
            end
            if target.id=='checkout' and not Grocery.atCheckout(view.pose) then return nil end
            view.notice=nil
            return target.id
        end
    end
    return nil
end
local function inside(b,x,y)return x>=b.x and y>=b.y and x<=b.x+b.w and y<=b.y+b.h end
local function openOrWalk(view,hotspot)
    if (view.pose.x-hotspot.x)^2+(view.pose.y-hotspot.y)^2<=(hotspot.radius+22)^2 then
        if not view.cartPose.pushed then
            view.notice='Take the shopping cart before collecting groceries or checking out.'
            return nil
        end
        view.notice=nil
        return hotspot.id
    end
    setPath(view,hotspot.x,hotspot.y,hotspot);return nil
end
function Grocery.pointer(view,R,x,y)
    if view.closed then return nil end
    x,y=x*960/R.Config.baseWidth,y*678/R.Config.baseHeight
    if inside(controls.exit,x,y) then return 'exit' end
    local p=view.pose
    local cartX,cartY=Grocery.cartPosition(view)
    if (x-cartX)^2+(y-cartY)^2<=34^2 then
        if view.cartPose.pushed then return parkCart(view)
        elseif nearCart(view,p.x,p.y) then return takeCart(view)
        else
            view.notice='Walk to the shopping cart to take it.'
            setPath(view,cartX,cartY,nil)
        end
        return nil
    end
    if inside(controls.browse,x,y) then
        if not view.cartPose.pushed and nearCart(view,p.x,p.y) then return takeCart(view) end
        local nearby=nearestHotspot(p)
        if nearby then return openOrWalk(view,nearby) end
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
    if key=='f' and view.cartPose.pushed then return parkCart(view) end
    if key=='e' or key=='return' or key=='kpenter' then
        if nearCart(view,view.pose.x,view.pose.y) then return takeCart(view) end
        local hotspot=nearestHotspot(view.pose)
        if hotspot then return openOrWalk(view,hotspot) end
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
    if p.cartPushing then
        action,mirror=Animation.directionalPalletJackPushAction(p.intentX,p.intentY)
        if not p.moving then action=action..'_idle' end
        if not assets.hasAction(character,action) then
            if p.moving then action,mirror=Animation.actorWalkAction(p)
            else action,mirror=Animation.directionalIdleAction(p.intentX,p.intentY) end
        end
    elseif p.moving then action,mirror=Animation.actorWalkAction(p)
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
local function drawShoppingCart(g,view,cart)
    local image=view.images.cart
    if not image then return end
    local direction=CART_VIEWS[cart.direction] and cart.direction or 'north'
    local spec=CART_VIEWS[direction]
    view.cartQuads=view.cartQuads or {}
    if not view.cartQuads[spec.row] then
        view.cartQuads[spec.row]={}
        for frame=1,4 do
            view.cartQuads[spec.row][frame]=g.newQuad((frame-1)*CART_SIZE,(spec.row-1)*CART_SIZE,
                CART_SIZE,CART_SIZE,image:getDimensions())
        end
    end
    local frame=cart.moving and Animation.frameForDistance(4,cart.animationDistance,5) or 1
    local mirror=spec.mirror and -CART_SCALE or CART_SCALE
    g.setColor(1,1,1,1)
    g.draw(image,view.cartQuads[spec.row][frame],cart.x,cart.y,0,mirror,CART_SCALE,64,112)
    local index=0
    for _,itemId in ipairs(CART_ITEM_ORDER) do
        for _=1,math.min(12-index,(view.cartItems and view.cartItems[itemId]) or 0) do
            index=index+1
            local column=(index-1)%4
            local row=math.floor((index-1)/4)
            local localX=43+column*14
            local localY=49+row*9
            local itemX=cart.x+(localX-64)*mirror
            local itemY=cart.y+(localY-112)*CART_SCALE
            if not GroceryUiArt.drawProduct(itemId,itemX,itemY,16) then
                g.setColor(unpack(CART_ITEM_COLORS[itemId] or colors.cream))
                if itemId=='vegetables' or itemId=='cup' then
                    g.ellipse('fill',itemX,itemY,3.2*CART_SCALE,3.8*CART_SCALE)
                else
                    g.rectangle('fill',itemX-3*CART_SCALE,itemY-3*CART_SCALE,
                        6*CART_SCALE,7*CART_SCALE,1.5*CART_SCALE)
                end
            end
            if index>=12 then break end
        end
        if index>=12 then break end
    end
    if cart.itemCount>0 then
        local badgeX,badgeY=cart.x+20*CART_SCALE,cart.y-70*CART_SCALE
        g.setColor(.035,.09,.08,.96);g.circle('fill',badgeX,badgeY,9)
        g.setColor(1,.85,.49,1);g.setFont(Fonts.get('metal',10))
        g.printf(tostring(math.min(99,cart.itemCount)),badgeX-8,badgeY-6,16,'center')
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
        local cartX,cartY,cartDirection,pushed=Grocery.cartPosition(view)
        local cartActor={shoppingCart=true,x=cartX,y=cartY,direction=cartDirection,
            moving=pushed and view.pose.moving,animationDistance=view.pose.animationDistance,
            itemCount=view.cartCount or 0}
        local people={view.pose,{cashier=true,y=340},cartActor}
        if R.multiplayer and R.multiplayer.remotePlayers then
            for _,p in ipairs(R.multiplayer:remotePlayers()) do
                if p.sceneId=='grocery' then
                    people[#people+1]=p
                    if p.cartPushing then
                        local remoteX,remoteY,remoteDirection=Grocery.cartPositionForPose(p)
                        people[#people+1]={shoppingCart=true,x=remoteX,y=remoteY,direction=remoteDirection,
                            moving=p.moving,animationDistance=p.animationDistance,itemCount=0}
                    end
                end
            end
        end
        table.sort(people,function(a,b)
            if a.y==b.y then return a.shoppingCart==true end
            return a.y<b.y
        end)
        local previousY=-math.huge
        for _,p in ipairs(people) do
            drawSceneFixtures(g,view,p.y,false,previousY)
            if p.cashier then drawCashier(R,view)
            elseif p.shoppingCart then drawShoppingCart(g,view,p)
            else drawPlayer(R,{pose=p}) end
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
    label(mobile and 'Move with the thumbstick. Tap the cart to take or park it; use INTERACT at a shelf or register.'
        or ('Move with WASD / arrows. Press %s at a shelf or checkout to interact; F parks your cart.'):format(interactHint),
        24,41,900,15,{.80,.87,.81,1})
    if view.cartCount then
        label(('CART %d  /  $%.2f'):format(view.cartCount,(view.cartTotalCents or 0)/100),650,11,286,18,{1,.85,.49,1},'right')
    end
    local nearby=nearestHotspot(view.pose)
    local cartNearby=not view.cartPose.pushed and nearCart(view,view.pose.x,view.pose.y)
    local browseText=cartNearby and '[E] TAKE SHOPPING CART'
        or nearby and ('[E] BROWSE '..nearby.label:upper()) or 'WALK TO A DISPLAY OR CHECKOUT'
    if view.cartPose.pushed then browseText=nearby and ('[E] BROWSE '..nearby.label:upper()) or 'PUSH CART TO A DISPLAY OR REGISTER' end
    if view.notice then label(view.notice,180,576,600,14,{1,.82,.48,1},'center') end
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
