-- One full-screen player per device, with independent aiming and action fingers.
local Input=require('src.critter_crisis_inputs')
local Bits=require('src.critter_crisis_frontier')
local Mobile={touches={},more=false,usedTouch=false}
local fonts={}
local controls={
    aim={20,560,322,104},cover={358,574,166,90},reload={538,574,178,90},fire={734,556,206,108},
    more={20,444,172,66},sights={748,444,192,66},back={12,8,114,60},
    next={300,342,360,74},restart={300,408,360,74},
}
local extra={{'WEAPON',Bits.WEAPON},{'FIRE MODE',Bits.MODE},{'SUPPLIES',Bits.SUPPLY},{'NEXT WAVE',Bits.CONTINUE}}
local function inside(x,y,r)return x>=r[1] and x<=r[1]+r[3] and y>=r[2] and y<=r[2]+r[4]end
local function text(value,x,y,w,size,color)
    if not fonts[size] then fonts[size]=love.graphics.newFont('assets/fonts/VT323-Regular.ttf',size) end
    love.graphics.setFont(fonts[size]);love.graphics.setColor(unpack(color or {1,.9,.7,1}))
    love.graphics.printf(value,x,y,w,'center')
end
local function box(r,label,active)
    love.graphics.setColor(active and .11 or .02,active and .25 or .06,active and .3 or .09,.98)
    love.graphics.rectangle('fill',unpack(r));love.graphics.setColor(.3,.89,1,1)
    love.graphics.rectangle('line',unpack(r));text(label,r[1]+4,r[2]+(r[4]-32)/2,r[3]-8,32)
end
function Mobile.enabled(runtime)
    return Mobile.usedTouch or runtime.mobileControls and runtime.mobileControls:isEnabled()
        or os.getenv('PICTURE_SHOP_MOBILE')=='1' or love.system.getOS()=='Android'
end
function Mobile.active(runtime,s) return s and s.mode=='coop' and Mobile.enabled(runtime) end
function Mobile.reset()
    Mobile.touches={};Mobile.more=false;Mobile.round=nil
end
function Mobile.configure(s)
    Input.configure(s)
    if Mobile.round~=s.roundId then Mobile.reset();Mobile.round=s.roundId end
end
local function extraRect(i)return {270+(i-1)%2*220,235+math.floor((i-1)/2)*94,200,78}end
local function frame(runtime,s)
    return s.frontier or runtime.multiplayer.crisisFrontier and runtime.multiplayer:crisisFrontier(s)
end
function Mobile.press(runtime,s,id,x,y)
    Mobile.configure(s)
    local source='phone:'..tostring(id)
    if inside(x,y,controls.back) or s.game=='mission' and x>820 and y<76 then return 'leave' end
    if s.phase=='finished' or s.phase=='failed' then
        if inside(x,y,controls.restart) and tonumber(runtime.World.player.id)==s.ownerId then return 'restart' end
        return true
    end
    if s.phase~='playing' then return true end
    local f=s.game~='mission' and frame(runtime,s)
    if f and f.kind=='stand' and f.world.result=='intermission' and inside(x,y,controls.next) then
        Input.press(source,1,Bits.CONTINUE);Mobile.touches[id]={source=source};return true
    end
    if Mobile.more then
        for i,action in ipairs(extra) do if (s.game=='stand' or i<=2) and inside(x,y,extraRect(i)) then
            Input.press(source,1,action[2]);Mobile.touches[id]={source=source};Mobile.more=false;return true
        end end
        Mobile.more=false;return true
    end
    if s.game~='mission' and inside(x,y,controls.more) then Mobile.more=true;return true end
    if s.game~='mission' and inside(x,y,controls.sights) then
        if Input.actors[1].held.phoneSights then Input.release('phoneSights') else Input.press('phoneSights',1,Bits.ADS) end
        return true
    end
    for name,action in pairs({fire=Bits.FIRE,cover=Bits.COVER,reload=Bits.RELOAD}) do
        if inside(x,y,controls[name]) then
            Input.press(source,1,action);Mobile.touches[id]={source=source};return true
        end
    end
    if x>=0 and x<=960 and y>=80 and y<=678 then
        for _,touch in pairs(Mobile.touches) do if touch.aim then return true end end
        local a=Input.actors[1]
        Mobile.touches[id]={source=source,aim=true,x=x,y=y,aimX=a.x,aimY=a.y}
    end
    return true
end
function Mobile.move(id,x,y)
    local t=Mobile.touches[id]
    if not t then return false end
    if t.aim then
        local maxY=Input.session.game=='mission' and 514 or 550
        Input.aim(1,math.max(30,math.min(930,t.aimX+(x-t.x)*2.2)),
            math.max(95,math.min(maxY,t.aimY+(y-t.y)*2.2)))
    end
    return true
end
function Mobile.release(id)
    local t=Mobile.touches[id]
    if t then Input.release(t.source);Mobile.touches[id]=nil;return true end
    return false
end
function Mobile.draw(runtime,s)
    Mobile.configure(s)
    local f=s.game~='mission' and frame(runtime,s)
    local slot=tonumber(runtime.World.player.id)==s.ownerId and 1 or 2
    local hp,ammo,partnerHp,reload,covered=0,0,0,false,false
    for _,p in pairs(s.players) do
        if p.id==tonumber(runtime.World.player.id) then hp=p.hp;ammo=p.ammo;reload=p.reload>0;covered=p.covered
        else partnerHp=p.hp end
    end
    if f then
        local p=f.pilots[slot];hp=p.data.health;partnerHp=f.pilots[3-slot].data.health
        ammo=f.kind=='range' and p.range.loaded or p.gun.magazine
    end
    love.graphics.push('all')
    love.graphics.setColor(.012,.025,.04,1);love.graphics.rectangle('fill',0,520,960,158)
    text('P'..slot..' LIFE '..hp..'   AMMO '..ammo..'   |   PARTNER '..partnerHp..'   |   SCORE '..s.score,15,526,930,26)
    box(controls.aim,'DRAG TO AIM')
    box(controls.cover,covered and 'IN COVER' or 'COVER',covered)
    box(controls.reload,reload and 'LOADING' or 'RELOAD',reload)
    box(controls.fire,'FIRE')
    if s.game~='mission' then
        box(controls.more,'MORE')
        box(controls.sights,Input.actors[1].held.phoneSights and 'HIP VIEW' or 'SIGHTS',Input.actors[1].held.phoneSights)
    end
    if f and f.kind=='stand' and f.world.result=='intermission' then box(controls.next,'NEXT WAVE') end
    if s.phase=='finished' or s.phase=='failed' then
        if slot==1 then box(controls.restart,'PLAY AGAIN')
        else text('Player 1 can start the next round.',180,420,600,28) end
    end
    if Mobile.more then
        love.graphics.setColor(.005,.012,.022,.94);love.graphics.rectangle('fill',220,160,520,360,12)
        text('YOUR WEAPON',260,179,440,34)
        for i,action in ipairs(extra) do if s.game=='stand' or i<=2 then box(extraRect(i),action[1]) end end
        text('Tap outside to close',250,452,460,26)
    end
    love.graphics.pop()
end
return Mobile
