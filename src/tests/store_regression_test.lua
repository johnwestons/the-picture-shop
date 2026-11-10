local Test={}
function Test.run(_,check)
    local Store=require('src.commute.town_store')
    local Shopping=require('src.home_shopping')
    local Inventory=require('src.commute.grocery_inventory')
    local Characters=require('src.character_assets')
    local Config=require('src.config')
    local Presentation=require('src.commute.presentation')
    local State=require('src.state')
    local Loader=require('src.image_loader')
    local originalEnabled=Loader.enabled
    Loader.setEnabled(false)
    local canvas=require('src.tests.support.pixel_canvas')(960,678)
    local function capture(name)
        local folder=os.getenv('PICTURE_SHOP_STORE_PREVIEW_DIR')
        if not folder then return end
        love.graphics.setCanvas()
        local data=canvas:newImageData();local bytes=data:encode('png')
        local file=assert(io.open(folder..'/'..name..'.png','wb'))
        file:write(bytes:getString());file:close();bytes:release();data:release()
        love.graphics.setCanvas(canvas)
    end
    love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear()
    for _,id in ipairs({'grocery','general-store','diner','gas-station'}) do
        local view=Store.open(id,1);view.storeStock=Inventory.defaultState()
        Store.draw(view,30000,{items={},revision=0},0,960,678)
        check('store_panel_fonts_render_'..id,true)
        if id=='grocery' then
            for _,category in ipairs({'produce','pantry','chilled','household','specials','checkout'}) do
                view.categoryId=category;view.cart={bread=2,vegetables=1}
                Store.draw(view,30000,{items={},revision=0},0,960,678)
                check('grocery_cart_panel_renders_'..category,true)
                if category=='checkout' then capture('grocery-cart-checkout') end
            end
            view.cart={};Store.draw(view,30000,{items={},revision=0},0,960,678)
            check('grocery_empty_checkout_renders',true)
        end
    end
    local state=State.new()
    local normalDraw=love.graphics.draw
    local draw
    love.graphics.draw=function(image,quad,x,y,rotation,sx,sy,ax,ay,...)
        draw={x=x,y=y,sx=sx,sy=sy,ax=ax,ay=ay}
        return normalDraw(image,quad,x,y,rotation,sx,sy,ax,ay,...)
    end
    local okay,err=xpcall(function()
        local player={id=1,character='rabbit-worker',x=480,y=400,idleClock=0,animationDistance=0}
        for _,direction in ipairs({{0,-1},{1,-1},{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1}}) do
            player.intentX,player.intentY=unpack(direction)
            for _,moving in ipairs({false,true}) do
                player.moving=moving;draw=nil
                love.graphics.clear(0,0,0,0)
                assert(Presentation.indoor(player,state,Characters,{outfit='geared'},Presentation.STORE_RIDER_SCALE))
                love.graphics.setCanvas()
                local data=canvas:newImageData();local top,bottom=678,-1
                love.graphics.setCanvas(canvas)
                for y=280,420 do for x=390,570 do
                    local _,_,_,alpha=data:getPixel(x,y)
                    if alpha>.2 then top=math.min(top,y);bottom=math.max(bottom,y) end
                end end
                data:release()
                local height=bottom-top+1
                local label=direction[1]..'_'..direction[2]..'_'..tostring(moving)
                check('store_geared_rider_pixel_stature_'..label,height>=84 and height<=91,height)
                check('store_geared_rider_foot_anchor_'..label,draw and draw.x==480 and draw.y==400)
            end
        end
        local rooms={{'grocery','src.commute.grocery_interior'},
            {'gas_station','src.commute.gas_station_interior'},{'mechanic','src.commute.mechanic_interior'}}
        local originalIndoor=Presentation.indoor
        local receivedScale
        Presentation.indoor=function(p,s,a,gear,scale)
            receivedScale=scale
            return originalIndoor(p,s,a,gear,scale)
        end
        local placeholder=require('src.tests.support.pixel_canvas')(1,1)
        local quad=love.graphics.newQuad(0,0,1,1,1,1)
        local R={state=state,World={player=player},CharacterAssets=Characters,Config=Config,
            _commute={mechanicOffer={page='lobby'}}}
        state.home.commute={participants={owner={rider={gear={outfit='geared'}}}}}
        local roomOkay,roomError=xpcall(function()
            for _,entry in ipairs(rooms) do
                local room=require(entry[2]);local view=room.new(R)
                view.ready=true;view.images={background=placeholder,idle=placeholder}
                view.quads={idle={}}
                for index=1,16 do view.quads.idle[index]=quad end
                receivedScale=nil;room.draw(view,R)
                check('store_interior_uses_shared_geared_size_'..entry[1],receivedScale==Presentation.STORE_RIDER_SCALE)
            end
        end,debug.traceback)
        Presentation.indoor=originalIndoor;placeholder:release();quad:release()
        assert(roomOkay,roomError)
        if os.getenv('PICTURE_SHOP_STORE_PREVIEW_DIR') then
            love.graphics.clear(.045,.065,.07,1)
            love.graphics.setFont(require('src.screens.title_fonts').get('metal',18))
            love.graphics.setColor(1,.9,.7,1)
            for index,label in ipairs({'Normal outfit','Previous riding size','Updated store size'}) do
                love.graphics.printf(label,30+(index-1)*310,80,300,'center')
            end
            love.graphics.push('all');love.graphics.scale(2,2)
            player.x,player.y,player.intentX,player.intentY,player.moving=90,200,1,1,false
            local action='idle_southeast';local image,quad=Characters.get('rabbit-worker',action,1)
            local ax,ay=Characters.getAnchor('rabbit-worker',action,1)
            local scale=Config.player.drawScale*Characters.getNormalization('rabbit-worker',action)
            love.graphics.setColor(1,1,1,1);normalDraw(image,quad,player.x,player.y,0,scale,scale,ax,ay)
            player.x=245;originalIndoor(player,state,Characters,{outfit='geared'})
            player.x=400;originalIndoor(player,state,Characters,{outfit='geared'},Presentation.STORE_RIDER_SCALE)
            love.graphics.pop();capture('store-rider-size')
        end
    end,debug.traceback)
    love.graphics.draw=normalDraw
    love.graphics.pop();canvas:release();Loader.setEnabled(originalEnabled)
    assert(okay,err)
    for _,id in ipairs({'meal','meal_pack','pizza','chinese','bed','mug'}) do
        local q=assert(Shopping.quote(id,3))
        check('home_delivery_percentage_'..id,q.shippingCents==math.max(200,math.floor(q.subtotalCents*.15+.5))
            and q.totalCents==q.subtotalCents+q.shippingCents)
    end
    check('home_delivery_small_order_minimum',Shopping.quote('drink',1).shippingCents==200)
    check('home_delivery_quantity_increases_fee',Shopping.quote('meal_pack',10).shippingCents==2700)
    check('home_delivery_rounds_to_whole_cents',Shopping.quote('cup',9).shippingCents==338)
    check('store_pickup_has_no_delivery_fee',Store.quote('grocery','meal_pack',3).totalCents==4200)
    local oldReceipt=Shopping.new();oldReceipt.nextOrderId=2
    oldReceipt.orders={{id=1,requestId='legacy',residentId='owner',productId='meal',itemId='basic_meal',
        quantity=1,servingsPerUnit=1,unitPriceCents=500,shippingCents=100,totalCents=600,
        orderedAt=0,dueAt=1,budgetCloseHours=100,status='transit'}}
    check('home_delivery_old_receipts_keep_recorded_charge',Shopping.valid(oldReceipt)
        and oldReceipt.orders[1].shippingCents==100)
end
return Test
