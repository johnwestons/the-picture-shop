-- A short, skippable campaign beat that celebrates the restored shop and only
-- unlocks business when its final OPEN card lands. All art is drawn in code.
local Opening={DURATION=12.8}
local Condition=require('src.warehouse_condition')
local W,H=960,678
local fonts={}
local colors={
    ink={.025,.065,.067},deep={.035,.12,.125},teal={.075,.34,.34},
    gold={.96,.72,.32},cream={1,.94,.75},paper={.98,.91,.69},
    red={.66,.17,.14},green={.16,.48,.32},white={1,.99,.91},
}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function ease(v) v=clamp(v,0,1);return v*v*(3-2*v) end
local function color(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
local function font(size)
    if not fonts[size] then fonts[size]=love.graphics.newFont(size) end
    love.graphics.setFont(fonts[size])
end
local function centered(text,y,size,tint,alpha)
    font(size);color(tint,alpha);love.graphics.printf(text,70,y,W-140,'center')
end
local function seedParticles(seed)
    local particles={}
    local value=math.floor(tonumber(seed) or 1)%2147483647
    if value<=0 then value=1 end
    for i=1,90 do
        value=(value*48271)%2147483647
        local x=(value%10000)/10000*W
        value=(value*48271)%2147483647
        local y=(value%10000)/10000*H
        value=(value*48271)%2147483647
        local speed=90+(value%180)
        value=(value*48271)%2147483647
        local size=4+(value%8)
        particles[i]={x=x,y=y,speed=speed,size=size,phase=i*.73,shade=i%3+1}
    end
    return particles
end
local function drawBackdrop(R)
    local g=love.graphics
    local image=require('src.warehouse_condition_renderer').image(R.state,R.Assets)
    if image then
        local scale=math.max(W/image:getWidth(),H/image:getHeight())
        g.setColor(1,1,1,1)
        g.draw(image,(W-image:getWidth()*scale)*.5,(H-image:getHeight()*scale)*.5,0,scale,scale)
    else
        color(colors.deep);g.rectangle('fill',0,0,W,H)
    end
    color(colors.ink,.56);g.rectangle('fill',0,0,W,H)
    for i=0,8 do
        local alpha=.025*(1-i/10)
        color(colors.gold,alpha)
        g.ellipse('fill',W*.5,H*.46,180+i*56,90+i*34)
    end
end
local function drawCurtains(open)
    local g=love.graphics
    local width=(W*.5+8)*(1-open)
    if width<1 then return end
    color(colors.deep,.98);g.rectangle('fill',0,0,width,H)
    g.rectangle('fill',W-width,0,width,H)
    color(colors.teal,.28)
    for x=12,width,38 do g.rectangle('fill',x,0,12,H);g.rectangle('fill',W-x-12,0,12,H) end
    color(colors.gold,.92)
    g.rectangle('fill',0,0,width,12);g.rectangle('fill',W-width,0,width,12)
    g.rectangle('fill',0,H-13,width,13);g.rectangle('fill',W-width,H-13,width,13)
end
local function drawBanner(progress,headline)
    local g=love.graphics
    local slide=ease(progress)
    local y=-130+slide*168
    local left,right=W*.5-390,W*.5+390
    color(colors.red);g.polygon('fill',left,y+126,left+56,y+126,left+13,y+205)
    g.polygon('fill',right,y+126,right-56,y+126,right-13,y+205)
    color(colors.gold);g.rectangle('fill',left,y, right-left,132,5)
    color(colors.deep);g.rectangle('fill',left+6,y+6,right-left-12,120,3)
    love.graphics.setLineWidth(3);color(colors.cream);g.rectangle('line',left+12,y+12,right-left-24,108,2)
    font(25);color(colors.gold);g.printf('THE PICTURE SHOP',left+20,y+23,right-left-40,'center')
    font(43);color(colors.white);g.printf(headline,left+18,y+55,right-left-36,'center')
end
local function drawDoorSign(progress)
    local g=love.graphics
    local flip=clamp(progress,0,1)
    local scale=math.max(.08,math.abs(math.cos(flip*math.pi)))
    local open=flip>=.5
    local x,y=W*.5+365,H*.56
    g.push();g.translate(x,y);g.scale(scale,1)
    color(colors.ink,.94);g.rectangle('fill',-94,-46,188,92,9)
    color(colors.gold);g.rectangle('line',-87,-39,174,78,6)
    color(open and colors.green or colors.red);g.rectangle('fill',-74,-27,148,54,4)
    font(26);color(colors.white);g.printf(open and 'OPEN' or 'CLOSED',-72,-16,144,'center')
    g.pop()
end
local function drawConfetti(particles,time,alpha)
    local g=love.graphics
    local shades={colors.gold,colors.cream,colors.red,colors.teal,colors.green}
    for _,p in ipairs(particles or {}) do
        local x=p.x+math.sin(time*1.6+p.phase)*26
        local y=(p.y+time*p.speed)% (H+30)-15
        local tint=shades[p.shade]
        color(tint,alpha)
        g.push();g.translate(x,y);g.rotate(time*2+p.phase)
        g.rectangle('fill',-p.size*.5,-p.size*.5,p.size,p.size*1.7)
        g.pop()
    end
end
local function drawSkip(time)
    local g=love.graphics
    local fade=ease(time/.45)*(1-ease((time-(Opening.DURATION-.65))/.65))
    if fade<=0 then return end
    color(colors.ink,.74*fade);g.rectangle('fill',W-238,26,208,48,7)
    color(colors.cream,fade);font(16);g.printf('ENTER TO OPEN NOW',W-228,42,188,'center')
end
function Opening.active(R) return R and R._grandOpening~=nil end
function Opening.begin(R,player,state)
    state=state or R.state
    local c=Condition.of(state)
    if not c or c.mode~='story' or c.grandOpened then
        return false,'already_applied','The Picture Shop is already open.'
    end
    if not player or player.sceneId~='warehouse' then
        return false,'wrong_scene','Return to the shop to hold its grand opening.'
    end
    if R.multiplayer:isActive() and R.multiplayer:isHost()
        and (tonumber(player.id) or 1)~=(tonumber(R.World.player.id) or 1) then
        return false,'host_only','The shop owner must lead the grand opening from the warehouse.'
    end
    local ready,reason=Condition.readyForOpening(state)
    if not ready then return false,'not_ready',reason end
    if Opening.active(R) then return false,'already_started','The grand opening is already underway.' end
    R.state=state
    state.screen='world'
    state.message='The Picture Shop grand opening is starting.'
    R._grandOpening={time=0,particles=seedParticles(c.seed),playerId=tonumber(player.id) or 1}
    return true,'accepted','The grand opening is underway.'
end
function Opening.finish(R,skip)
    local sequence=R and R._grandOpening
    if not sequence then return false end
    local okay,code,message=Condition.perform(R.state,
        {sceneId='warehouse',id=sequence.playerId},'grand_opening')
    R._grandOpening=nil
    if not okay then
        R.state.message=message or 'The grand opening could not be completed.'
        return false,code,message
    end
    R.state.message=skip and 'The Picture Shop is open. Your first customers can call now.'
        or 'Grand opening complete! The Picture Shop is open for clients.'
    if R.multiplayer:isHost() then R.multiplayer:markShopDirty(true) end
    if not R.multiplayer:isClient() and not R.saveCurrent(true) then
        R.state.message='The Picture Shop opened, but this device could not save it. Try again from the menu.'
    end
    return true
end
function Opening.update(R,dt)
    local sequence=R and R._grandOpening
    if not sequence then return false end
    sequence.time=math.min(Opening.DURATION,sequence.time+clamp(tonumber(dt) or 0,0,.5))
    if sequence.time>=Opening.DURATION then Opening.finish(R,false) end
    return true
end
function Opening.keypressed(R,key)
    if not Opening.active(R) then return false end
    if key=='return' or key=='space' or key=='escape' or key=='back' then Opening.finish(R,true) end
    return true
end
function Opening.pointer(R,x,y)
    if not Opening.active(R) then return false end
    if x>=W-250 and y<=100 then Opening.finish(R,true) end
    return true
end
function Opening.draw(R)
    local sequence=R and R._grandOpening
    if not sequence then return false end
    local g=love.graphics
    local t=sequence.time
    g.push('all');g.setShader()
    drawBackdrop(R)
    drawConfetti(sequence.particles,math.max(0,t-3),ease((t-3)/.7)*.9)
    local curtain=ease((t-.3)/2.2)
    drawCurtains(curtain)
    local titleAlpha=ease((t-.8)/.55)*(1-ease((t-2.55)/.45))
    if titleAlpha>0 then
        centered('TEN YEARS CLOSED.',H*.40,30,colors.cream,titleAlpha)
        centered('ONE MORE CHANCE.',H*.47,55,colors.white,titleAlpha)
        centered('THE PICTURE SHOP',H*.55,25,colors.gold,titleAlpha)
    end
    drawBanner(ease((t-2.35)/.62),t<6.7 and 'GRAND OPENING' or 'WELCOME IN')
    local signProgress=ease((t-4.6)/.85)
    drawDoorSign(signProgress)
    local welcome=ease((t-6.3)/.55)*(1-ease((t-9.5)/.55))
    if welcome>0 then
        centered('WELCOME TO YOUR NEW BEGINNING',H*.69,28,colors.cream,welcome)
        centered('The lights are on. The doors are open.',H*.75,22,colors.white,welcome)
        centered('Your first customers can call now.',H*.80,20,colors.gold,welcome)
    end
    local finish=ease((t-9.45)/.7)
    if finish>0 then
        color(colors.ink,.84*finish);g.rectangle('fill',W*.5-292,H*.405,584,190,15)
        color(colors.gold,finish);g.setLineWidth(3);g.rectangle('line',W*.5-282,H*.415,564,170,11)
        centered('NOW OPEN',H*.455,56,colors.white,finish)
        centered('THE PICTURE SHOP',H*.535,25,colors.gold,finish)
        centered('Your first customers can call now.',H*.59,19,colors.cream,finish)
    end
    local progress=clamp(t/Opening.DURATION,0,1)
    color(colors.white,.35);g.rectangle('fill',42,H-31,W-84,5,2)
    color(colors.gold);g.rectangle('fill',42,H-31,(W-84)*progress,5,2)
    drawSkip(t)
    local fadeOut=ease((t-(Opening.DURATION-.55))/.55)
    if fadeOut>0 then color(colors.ink,fadeOut);g.rectangle('fill',0,0,W,H) end
    g.pop()
    return true
end
return Opening
