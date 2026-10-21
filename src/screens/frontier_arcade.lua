-- Mouse Frontier's original minigame engines inside a disposable solo cabinet.
local Range=require('src.arcade_frontier.shooting_range')
local Stand=require('src.arcade_frontier.last_stand_shootout')
local Ambush=require('src.arcade_frontier.train_ambush')
local Shooting=require('src.arcade_frontier.first_person_shooting')
local Catalog=require('src.arcade_frontier.catalog')
local Views=require('src.arcade_frontier.first_person_weapon_views')
local Typography=require('src.arcade_frontier.typography')
local Arcade={}
local ROOT='assets/generated/frontier-arcade/assets/'
local WIDTH,HEIGHT=960,720
local SCALE=640/HEIGHT
local OFFSET=(960-WIDTH*SCALE)/2
local TITLES={range='GUN RANGE',stand='LAST STAND',train='BANDIT TRAIN ATTACK'}
local function profile()
    return {location=12,health=20,maxHealth=20,scrap=250,
        weapon='frontier-22-lever-rifle',equipment={weapon='frontier-22-lever-rifle'},
        inventory={'frontier-22-lever-rifle','frontier-9mm-service-pistol','sawed-off-shotgun'},
        ammo={['22lr']=240,['9mm']=240,['12-gauge']=60},weaponDurability={},weaponProficiency={},
        maintenance={condition=100},resources={food=20,water=20},accessibility={}}
end
local function loadImage(path)
    local image=love.graphics.newImage(path);image:setFilter('linear','linear');return image
end
local function rangeAssets()
    local assets={weaponViews=Views.new(loadImage,function(path)return love.filesystem.getInfo(path)~=nil end,love.graphics.newQuad)}
    for name,file in pairs({background='range-background.png',longRangeBackground='range-long-background.png',
        targets='target-atlas.png',sectionedTarget='sectioned-paper-target.png',sectionedFrame='sectioned-paper-target-frame.png',
        impacts='impact-atlas.png',dirtImpacts='dirt-impact-atlas.png'}) do
        assets[name]=loadImage(ROOT..'sprites/props/shooting-range/'..file)
    end
    return assets
end
function Arcade.close()
    if Arcade.assets then
        Arcade.assets.weaponViews:release()
        for name,asset in pairs(Arcade.assets) do if name~='weaponViews' then asset:release() end end
    end
    if Arcade.service then Arcade.service:suspend() end
    Shooting.release()
    require('src.arcade_frontier.window_scene').release()
    require('src.arcade_frontier.train_ambush_scene').release()
    Arcade.kind=nil;Arcade.state=nil;Arcade.assets=nil;Arcade.service=nil;Arcade.pad=nil;Arcade.touches={}
end
function Arcade.open(kind,runtime)
    assert(TITLES[kind],'Unknown imported minigame')
    Arcade.host=runtime or Arcade.host
    local pad=Arcade.pad
    Arcade.close();Arcade.kind=kind;Arcade.data=profile();Arcade.paused=false
    Arcade.pad=pad
    Arcade.touch=love.system.getOS()=='Android' or love.system.getOS()=='iOS'
    Arcade.controllerReady=false;Arcade.triggerFire=false;Arcade.triggerADS=false
    Arcade.data.arcadeSound=Arcade.host and Arcade.host.App and Arcade.host.App.sound
    if kind=='range' then
        Arcade.assets=rangeAssets()
        Arcade.state=assert(Range.new(Arcade.data,{highScores={},preferences={motion='mixed',material='paper',targetPattern='pop-up',distance=50}},Catalog))
    elseif kind=='stand' then
        Arcade.state=Stand.new({originStop=12},Arcade.data,Catalog,'wide',WIDTH,HEIGHT)
        Arcade.state.touchControls=Arcade.touch
    else
        Arcade.runtime={state='game',saveData=Arcade.data}
        require('src.arcade_frontier.train_ambush_rules').start(Arcade.data)
        Arcade.service=Ambush.new({runtime=Arcade.runtime,catalog=Catalog,width=WIDTH,height=HEIGHT,
            writeSave=function()end,enterStop=function()Arcade.finished=true end,
            controlBindings={axisValue=function(_,axis)
                if not Arcade.pad or not Arcade.pad:isConnected() then return 0 end
                local name=({aim_x='rightx',aim_y='righty',fire='triggerright',ads='triggerleft'})[axis]
                if (axis=='fire' or axis=='ads') and not Arcade.controllerReady then return 0 end
                local value=name and Arcade.pad:getGamepadAxis(name) or 0
                return math.abs(value)>.15 and value or 0
            end,translateButton=function(_,button)
                return ({a='space',rightshoulder='space',leftshoulder='c',x='r',y='tab',dpup='v'})[button]
            end}})
        Arcade.finished=false;Arcade.service:update(0)
    end
end
function Arcade.active() return Arcade.kind~=nil end
function Arcade.setPad(pad)
    if Arcade.pad~=pad then
        if Arcade.pad then Arcade.focus(false) end
        Arcade.pad=pad;Arcade.controllerReady=false
    end
end
local function outcome(value)
    if value=='close' then Arcade.close()
    elseif value=='shot' then Shooting.playReport(Arcade.state.weapon,Catalog,Arcade.data)
    elseif value=='complete' then Range.complete(Arcade.state,Arcade.data,Arcade.state.spot,{add=function()end}) end
end
function Arcade.update(dt)
    if not Arcade.active() then return end
    if Arcade.pad and not Arcade.pad:isConnected() then Arcade.focus(false);Arcade.pad=nil end
    if Arcade.paused then return end
    if Arcade.pad and Arcade.pad:getGamepadAxis('triggerright')<=.4 and Arcade.pad:getGamepadAxis('triggerleft')<=.4 then
        Arcade.controllerReady=true
    end
    dt=math.min(dt,.1)
    if Arcade.kind=='range' then outcome(Range.update(Arcade.state,dt,Arcade.data,Catalog))
    elseif Arcade.kind=='stand' then Stand.update(Arcade.state,dt,Arcade.data,Catalog,WIDTH,HEIGHT)
    elseif Arcade.service then Arcade.service:update(dt);if Arcade.finished then Arcade.close();return end end
    if Arcade.pad and Arcade.pad:isConnected() then
        local dx,dy=Arcade.pad:getGamepadAxis('rightx'),Arcade.pad:getGamepadAxis('righty')
        if math.abs(dx)>.15 or math.abs(dy)>.15 then
            local aim=Arcade.kind=='range' and Arcade.state or Arcade.kind=='stand' and Arcade.state.gun
            if aim then Arcade.aim(math.max(0,math.min(WIDTH,aim.aimX+dx*330*dt)),math.max(0,math.min(HEIGHT,aim.aimY+dy*330*dt))) end
        end
        if Arcade.kind~='train' then
            local firing=Arcade.pad:getGamepadAxis('triggerright')>.4
            local ads=Arcade.pad:getGamepadAxis('triggerleft')>.4
            if not firing and not ads then Arcade.controllerReady=true end
            if Arcade.controllerReady then
                if firing~=Arcade.triggerFire then
                    if firing then Arcade.keypressed('space') else Arcade.keyreleased('space') end
                end
                if ads~=Arcade.triggerADS then
                    if Arcade.kind=='range' then Range.setAim(Arcade.state,ads)
                    elseif Arcade.kind=='stand' then Stand.setADS(Arcade.state,ads) end
                end
                Arcade.triggerFire,Arcade.triggerADS=firing,ads
            end
        end
    end
end
local function text(value,x,y,w,h,size)
    love.graphics.setFont(Typography.font(love.graphics,'regular',size or 20))
    love.graphics.setColor(1,.89,.68,1)
    Typography.drawText(love.graphics,value,x,y,w,h,{align='center',valign='center',scale=1,minScale=.7})
end
local function button(label,x,y,w,h)
    love.graphics.setColor(.065,.12,.16,1);love.graphics.rectangle('fill',x,y,w,h,5)
    love.graphics.setColor(.85,.64,.31,1);love.graphics.rectangle('line',x,y,w,h,5)
    text(label,x,y,w,h,18)
end
function Arcade.draw()
    love.graphics.push('all')
    love.graphics.setColor(.015,.022,.035,1);love.graphics.rectangle('fill',0,0,960,678)
    love.graphics.push('all')
    local x,y=love.graphics.transformPoint(OFFSET,38)
    local right,bottom=love.graphics.transformPoint(960-OFFSET,678)
    love.graphics.intersectScissor(x,y,right-x,bottom-y)
    love.graphics.translate(OFFSET,38);love.graphics.scale(SCALE)
    love.graphics.setFont(Typography.font(love.graphics))
    if Arcade.kind=='range' then Range.draw(Arcade.state,Arcade.data,Arcade.assets,{},Catalog,Arcade.touch)
    elseif Arcade.kind=='stand' then
        Stand.draw(Arcade.state,Arcade.data,WIDTH,HEIGHT)
        local result=Arcade.state.result
        if result=='intermission' or result=='victory' then
            love.graphics.setColor(.015,.02,.03,.92);love.graphics.rectangle('fill',180,235,600,240,10)
            text(result=='victory' and 'LAST STAND CLEARED' or 'WAVE COMPLETE',200,265,560,50,30)
            text(result=='victory' and 'Restart above to play again.' or 'Reload, then continue the defense.',210,331,540,40,20)
            if result=='intermission' then button('CONTINUE  [ENTER]',330,403,300,50) end
        end
    elseif Arcade.service then Arcade.service:draw() end
    if Arcade.paused then
        love.graphics.setColor(0,0,0,.8);love.graphics.rectangle('fill',0,0,WIDTH,HEIGHT)
        text('PAUSED - P TO RESUME',190,300,580,80,30)
    end
    love.graphics.pop()
    button('BACK',12,4,98,30);button('RESTART',840,4,108,30)
    text('MOUSE FRONTIER / '..TITLES[Arcade.kind]..' / SOLO',126,4,698,30,18)
    love.graphics.pop()
end
function Arcade.keypressed(key)
    if key=='escape' then Arcade.close();return true end
    if key=='p' and Arcade.kind~='train' then
        Arcade.mousereleased(1);Arcade.keyreleased('space');Arcade.paused=not Arcade.paused;return true
    end
    if Arcade.paused then return true end
    if Arcade.kind=='range' then outcome(Range.keypressed(Arcade.state,key,Arcade.data,Catalog))
    elseif Arcade.kind=='stand' then
        local state=Arcade.state
        if key=='return' and state.result=='intermission' then state.result=nil;state.stageBanner=2.8
        elseif key=='return' and state.result=='retreat' then Stand.retry(state)
        elseif key=='r' then Stand.reload(state,Arcade.data)
        elseif key=='ads' then Stand.setADS(state,not state.gun.ads)
        elseif key=='tab' then Stand.cycleWeapon(state,Arcade.data,Catalog)
        elseif key=='v' then Stand.cycleFireMode(state)
        elseif key=='l' then Stand.supply(state,Arcade.data,Catalog)
        elseif key=='c' or key=='lshift' then Stand.setCover(state,not state.ducking)
        elseif key=='space' then Stand.setFireHeld(state,'keyboard',true,Arcade.data,WIDTH,HEIGHT,Catalog) end
    elseif Arcade.service then Arcade.service:keypressed(key) end
    return true
end
function Arcade.keyreleased(key)
    if Arcade.kind=='range' then Range.keyreleased(Arcade.state,key)
    elseif Arcade.kind=='stand' and key=='space' then Stand.setFireHeld(Arcade.state,'keyboard',false)
    elseif Arcade.service then Arcade.service:keyreleased(key) end
end
function Arcade.aim(x,y,touch)
    if Arcade.kind=='range' then Range.mousemoved(Arcade.state,x,y,touch)
    elseif Arcade.kind=='stand' then Stand.setAim(Arcade.state,x,y)
    elseif Arcade.service then Arcade.service:mousemoved(x,y,0,0,false) end
end
local function point(x,y) return (x-OFFSET)/SCALE,(y-38)/SCALE end
function Arcade.mousemoved(x,y) if y>=38 then Arcade.aim(point(x,y)) end end
function Arcade.mousepressed(x,y,button)
    if y<38 then
        if x<115 then Arcade.close() elseif x>=840 then Arcade.open(Arcade.kind) end
        return true
    end
    if Arcade.paused then Arcade.paused=false;return true end
    x,y=point(x,y)
    if Arcade.kind=='range' then outcome(Range.mousepressed(Arcade.state,x,y,Arcade.data,Catalog,button))
    elseif Arcade.kind=='stand' then
        if Arcade.state.result=='intermission' and x>=330 and x<=630 and y>=403 and y<=453 then Arcade.keypressed('return');return true end
        Arcade.aim(x,y)
        local action=Arcade.state.touchControls and Stand.touchAction(x,y,WIDTH,HEIGHT)
        if action then Arcade.keypressed(({fire='space',cover='c',reload='r',supply='l',weapon='tab',mode='v'})[action] or action)
        else Stand.mousepressed(Arcade.state,x,y,button,Arcade.data,Catalog,WIDTH,HEIGHT) end
    elseif Arcade.service then Arcade.service:mousepressed(x,y,button,false) end
    return true
end
function Arcade.mousereleased(button)
    if Arcade.kind=='range' then
        Range.mousereleased(Arcade.state,button or 1)
        if button==2 then Range.setAim(Arcade.state,false) end
    elseif Arcade.kind=='stand' then Stand.mousereleased(Arcade.state,button or 1);Stand.setFireHeld(Arcade.state,'keyboard',false)
    elseif Arcade.service then Arcade.service:mousereleased(0,0,button or 1) end
end
function Arcade.gamepadpressed(pad,button)
    Arcade.setPad(pad)
    if button=='back' then Arcade.close();return true end
    if Arcade.service then return Arcade.service:gamepadpressed(pad,button) end
    if button=='a' and Arcade.kind=='stand' and Arcade.state.result then
        if Arcade.state.result=='victory' then Arcade.open('stand');return true end
        return Arcade.keypressed('return')
    end
    if button=='a' and Arcade.kind=='range' and Arcade.state.phase~='play' then return Arcade.keypressed('return') end
    if Arcade.kind=='stand' and (button=='dpup' or button=='dpdown') then return Arcade.keypressed(button=='dpup' and 'v' or 'l') end
    if button=='leftshoulder' and Arcade.kind=='range' then return Arcade.keypressed('lshift') end
    return Arcade.keypressed(({a='space',b='escape',x='r',y='tab',start='p',rightshoulder='space',leftshoulder='c',dpup='up',dpdown='down',dpleft='left',dpright='right'})[button] or '')
end
function Arcade.gamepadreleased(pad,button)
    if Arcade.service then Arcade.service:gamepadreleased(pad,button)
    elseif button=='a' or button=='rightshoulder' then Arcade.keyreleased('space') end
end
function Arcade.touchpressed(id,x,y)
    Arcade.touch=true
    if y<38 or Arcade.paused then return Arcade.mousepressed(x,y,1) end
    local gx,gy=point(x,y)
    if Arcade.service then return Arcade.service:touchpressed(id,gx,gy) end
    if Arcade.kind=='range' then
        local second=false;for _,action in pairs(Arcade.touches) do if action=='aim' then second=true end end
        local action=Range.mousepressed(Arcade.state,gx,gy,Arcade.data,Catalog,second and 5 or 4)
        Arcade.touches[id]=action=='aimPointer' and 'aim' or action=='shot' and 'fire' or 'button'
        outcome(action)
    elseif Arcade.kind=='stand' then
        local state=Arcade.state
        state.touchControls=true
        if state.result or Stand.needsSupply(state,Arcade.data) then return Arcade.mousepressed(x,y,1) end
        local action=Stand.touchAction(gx,gy,WIDTH,HEIGHT)
        if not action then for _,other in pairs(Arcade.touches) do if other=='aim' then action='fire';break end end end
        Arcade.touches[id]=action or 'aim'
        if action=='fire' then Stand.setFireHeld(state,'touch:'..tostring(id),true,Arcade.data,WIDTH,HEIGHT,Catalog)
        elseif action then Arcade.keypressed(action)
        else Stand.setTouchAim(state,gx,gy,WIDTH,HEIGHT) end
    end
    return true
end
function Arcade.touchmoved(id,x,y)
    if Arcade.paused then return true end
    x,y=point(x,y)
    if Arcade.service then return Arcade.service:touchmoved(id,x,y) end
    if Arcade.touches[id]=='aim' then
        if Arcade.kind=='range' then Range.mousemoved(Arcade.state,x,y,true)
        elseif Arcade.kind=='stand' then Stand.setTouchAim(Arcade.state,x,y,WIDTH,HEIGHT) end
    end
    return true
end
function Arcade.touchreleased(id)
    if Arcade.service then return Arcade.service:touchreleased(id) end
    if Arcade.touches[id]=='fire' then
        if Arcade.kind=='range' then
            local another=false
            for other,action in pairs(Arcade.touches) do if other~=id and action=='fire' then another=true end end
            if not another then Range.mousereleased(Arcade.state,4) end
        elseif Arcade.kind=='stand' then Stand.setFireHeld(Arcade.state,'touch:'..tostring(id),false) end
    end
    Arcade.touches[id]=nil;return true
end
function Arcade.focus(focused)
    if not focused and Arcade.active() then
        Arcade.mousereleased(1);Arcade.keyreleased('space')
        Arcade.mousereleased(2)
        Arcade.controllerReady=false;Arcade.triggerFire=false;Arcade.triggerADS=false
        for id in pairs(Arcade.touches) do Arcade.touchreleased(id) end
        if Arcade.service then Arcade.service:focus(false) else Arcade.paused=true end
    end
end
Arcade.rangeAssets=rangeAssets
return Arcade
