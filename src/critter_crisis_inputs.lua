-- Independent local seats. LAN sends seat one; a local pair sends both seats.
local Bits=require('src.critter_crisis_frontier')
local Actions=require('src.critter_crisis_actions')
local Input={actors={},touches={},mouse={},suspended=false}
local function actor(x) return {x=x,y=330,held={},sequences=Actions.blank(),pad=nil,controllerReady=false} end
function Input.reset()
    Input.actors={actor(320),actor(680)};Input.touches={};Input.mouse={};Input.round=nil;Input.suspended=false
end
Input.reset()
function Input.configure(session)
    if Input.round~=session.roundId then
        local previous,suspended=Input.actors,Input.suspended
        Input.reset();Input.round=session.roundId;Input.suspended=suspended
        for slot,actor in ipairs(previous) do
            if actor.pad and actor.pad:isConnected() then Input.actors[slot].pad=actor.pad end
        end
    end
    Input.session=session
end
function Input.active(session)
    return session and (session.mode=='local' or session.mode=='coop')
end
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
function Input.update(dt)
    if not Input.session or Input.suspended then return end
    local localPair=Input.session.mode=='local'
    for slot,a in ipairs(Input.actors) do if slot==1 or localPair then
        local keys=slot==1 and {'a','d','w','s'} or {'left','right','up','down'}
        local dx=(love.keyboard.isDown(keys[2]) and 1 or 0)-(love.keyboard.isDown(keys[1]) and 1 or 0)
        local dy=(love.keyboard.isDown(keys[4]) and 1 or 0)-(love.keyboard.isDown(keys[3]) and 1 or 0)
        if a.pad and a.pad:isConnected() then
            local px,py=a.pad:getGamepadAxis('rightx'),a.pad:getGamepadAxis('righty')
            if math.abs(px)>.15 then dx=px end;if math.abs(py)>.15 then dy=py end
            local fire=a.pad:getGamepadAxis('triggerright')>.4
            local ads=a.pad:getGamepadAxis('triggerleft')>.4
            if not fire and not ads then a.controllerReady=true end
            if a.controllerReady and fire then Input.press('triggerFire',slot,Bits.FIRE) else a.held.triggerFire=nil end
            a.held.triggerADS=a.controllerReady and ads and (Input.session.game=='mission' and Bits.COVER or Bits.ADS) or nil
        elseif a.pad then
            a.held.triggerFire=nil;a.held.triggerADS=nil
            for source in pairs(a.held) do if source:sub(1,4)=='pad:' then a.held[source]=nil end end
            a.pad=nil
        end
        local length=math.sqrt(dx*dx+dy*dy);if length>1 then dx=dx/length;dy=dy/length end
        a.x=clamp(a.x+dx*460*dt,30,930)
        a.y=clamp(a.y+dy*460*dt,Input.session.game=='mission' and 105 or 30,Input.session.game=='mission' and 560 or 620)
    end end
end
local function keyAction(key)
    local mission=Input.session.game=='mission'
    local first={lctrl=Bits.FIRE,r=Bits.RELOAD,c=Bits.COVER,tab=Bits.WEAPON,v=Bits.MODE,l=Bits.SUPPLY,
        space=mission and Bits.COVER or Bits.FIRE,lshift=mission and Bits.COVER or Bits.ADS,
        rshift=mission and Bits.COVER or Bits.ADS,['return']=Bits.CONTINUE}
    if Input.session.mode=='local' then
        local second={['return']=Bits.FIRE+Bits.CONTINUE,kpenter=Bits.FIRE+Bits.CONTINUE,rshift=Bits.COVER,
            backspace=Bits.RELOAD,kp0=Bits.FIRE,kp1=Bits.RELOAD,rctrl=Bits.ADS,delete=Bits.WEAPON,['end']=Bits.MODE,insert=Bits.SUPPLY}
        if second[key] then return 2,second[key] end
    end
    return 1,first[key]
end
function Input.keypressed(key)
    if Input.suspended then return end
    local slot,action=keyAction(key)
    if action then Input.press('key:'..key,slot,action) end
end
function Input.keyreleased(key)
    for _,a in ipairs(Input.actors) do a.held['key:'..key]=nil end
end
function Input.aim(slot,x,y)
    Input.actors[slot].x=clamp(x,0,960);Input.actors[slot].y=clamp(y,0,Input.session.game=='mission' and 678 or 720)
end
function Input.press(source,slot,action)
    if not Input.suspended and action then
        local a=Input.actors[slot]
        if a.held[source]~=action then Actions.record(a,action) end
        a.held[source]=action
    end
end
function Input.release(source)
    for _,a in ipairs(Input.actors) do a.held[source]=nil end
end
function Input.assignPad(pad)
    local slot
    for i,a in ipairs(Input.actors) do if a.pad==pad then slot=i end end
    if not slot then
        slot=Input.session.mode=='local' and (not Input.actors[2].pad and 2 or 1) or 1
        Input.actors[slot].pad=pad
    end
    return slot
end
function Input.gamepadpressed(pad,button)
    local slot=Input.assignPad(pad)
    local action=({a=Bits.FIRE,rightshoulder=Bits.FIRE,leftshoulder=Bits.COVER,x=Bits.RELOAD,y=Bits.WEAPON,
        dpup=Bits.MODE,dpdown=Bits.SUPPLY,start=Bits.CONTINUE})[button]
    Input.press('pad:'..slot..':'..button,slot,action)
    return slot
end
function Input.gamepadreleased(pad,button)
    for i,a in ipairs(Input.actors) do if a.pad==pad then Input.release('pad:'..i..':'..button) end end
end
function Input.focus(focused)
    Input.suspended=not focused
    if not focused then for _,a in ipairs(Input.actors) do a.held={};a.controllerReady=false end;Input.touches={};Input.mouse={} end
end
local function vector(slot)
    local a=Input.actors[slot];local bits=0
    if not Input.suspended then
        for shift=0,7 do
            local value=2^shift
            for _,mask in pairs(a.held) do if math.floor(mask/value)%2==1 then bits=bits+value;break end end
        end
    end
    local center=Input.session.game=='mission' and 339 or 360
    return clamp((a.x-480)/480,-1,1),clamp((a.y-center)/center,-1,1),bits
end
function Input.packet()
    local x,y,buttons=vector(1);local x2,y2,buttons2=vector(2)
    if Input.session.mode~='local' then x2,y2,buttons2=0,0,0 end
    local first,second={},{}
    for i=1,6 do first[i]=Input.actors[1].sequences[i];second[i]=Input.session.mode=='local' and Input.actors[2].sequences[i] or 0 end
    return {x=x,y=y,buttons=buttons,x2=x2,y2=y2,buttons2=buttons2,
        sequences=first,sequences2=second,roundId=Input.session.roundId,suspended=Input.suspended}
end
return Input
