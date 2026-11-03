-- Local preferences only: the network still receives semantic riding commands.
local B={}
B.actions={
 {id='accelerate',label='Accelerate / lift the nose in air',held=true,key='w',pad='axis:triggerright+',touch='touch1'},
 {id='brake',label='Brake / level the bike in air',held=true,key='s',pad='axis:triggerleft+',touch='touch2'},
 {id='left',label='Steer left',held=true,key='a',pad='axis:leftx-'},
 {id='right',label='Steer right',held=true,key='d',pad='axis:leftx+'},
 {id='handbrake',label='Additional brake',held=true,key='space',pad='b'},
 {id='boost',label='Boost',held=true,key='lshift',pad='rightshoulder',touch='touch3'},
 {id='interact',label='Mount / dismount / door',key='e',pad='a',touch='touch4',main='e',preview='e'},
 {id='ignition',label='Engine on / off',key='i',pad='back',main='i',preview='i'},
 {id='reverse',label='Forward / reverse',key='b',pad='leftstick',main='b',preview='b'},
 {id='headlight',label='Headlight',key='h',pad='y',touch='touch5',main='h',preview='h'},
 {id='view',label='Camera view',key='p',pad='rightstick',touch='touch6',main='p',preview='p'},
 {id='transmission',label='Auto / manual gearbox',key='v',pad='dpup',main='v',preview='v'},
 {id='shiftDown',label='Shift down',key='z',pad='dpleft',main='z',preview='z'},
 {id='shiftUp',label='Shift up',key='x',pad='dpright',main='x',preview='x'},
 {id='gear',label='Put on / remove riding gear',key='g',pad='x',main='g',preview='g'},
 {id='rescue',label='Recover the motorcycle to the last safe spot',key='u',main='u'},
 {id='recenter',label='Center camera',key='c',pad='dpdown',main='c',preview='c'},
 {id='orbitLeft',label='Rotate / look left',held=true,key='q',pad='axis:rightx-'},
 {id='orbitRight',label='Rotate / look right',held=true,key='t',pad='axis:rightx+'},
 {id='tiltUp',label='Tilt / look up',held=true,key='r',pad='axis:righty-'},
 {id='tiltDown',label='Tilt / look down',held=true,key='f',pad='axis:righty+'},
 {id='force',label='Bring party inside (host)',key='f6',main='f',preview=''},
 {id='orbit',label='Camera rotate / tilt drag',mouse='mouse3',mouseOnly=true},
 {id='pan',label='Camera pan drag',mouse='mouse2',mouseOnly=true},
 {id='zoomIn',label='Camera zoom in',key='=',mouse='wheelup',main='=',preview='='},
 {id='zoomOut',label='Camera zoom out',key='-',mouse='wheeldown',main='-',preview='-'},
 {id='panModifier',label='Pan modifier (with rotate drag)',key='lalt',modifier=true},
 {id='followCamera',label='Fixed / follow camera',key='o',pad='leftshoulder',main='o',preview='o'},
 {id='map',label='Town map',key='m',main='m',preview='m'},
}
B.byId={};for _,a in ipairs(B.actions) do B.byId[a.id]=a end
B.devices={'keyboard','mouse','controller','touch'}
local pads={a=true,b=true,x=true,y=true,back=true,leftstick=true,rightstick=true,leftshoulder=true,rightshoulder=true,
 dpup=true,dpdown=true,dpleft=true,dpright=true}
local axes={leftx=true,lefty=true,rightx=true,righty=true,triggerleft=true,triggerright=true}
local modifiers={lalt=true,ralt=true,lctrl=true,rctrl=true,lshift=true,rshift=true}
local reserved={escape=true,f10=true,delete=true,unknown=true}
local namedKeys={space=true,tab=true,['return']=true,backspace=true,up=true,down=true,left=true,right=true,
 home=true,['end']=true,pageup=true,pagedown=true,insert=true,lshift=true,rshift=true,lctrl=true,rctrl=true,
 lalt=true,ralt=true,lgui=true,rgui=true,capslock=true,numlock=true,scrolllock=true,pause=true,
 kpenter=true,['kp+']=true,['kp-']=true,['kp*']=true,['kp/']=true,['kp.']=true,['kp=']=true}
function B.valid(device,id,token)
    local a=B.byId[id];if not a or type(token)~='string' or #token>32 then return false end
    if token=='' then return true end
    if a.modifier then return device=='keyboard' and modifiers[token]==true end
    if a.mouseOnly and device~='mouse' then return false end
    if device=='keyboard' then
        if love and love.keyboard and love.keyboard.getScancodeFromKey then
            local okay,scan=pcall(love.keyboard.getScancodeFromKey,token)
            if not okay or scan=='unknown' then return false end
        end
        local f=tonumber(token:match('^f(%d+)$'))
        return not reserved[token] and (namedKeys[token]==true or #token==1 and token:byte()>=33 and token:byte()<=126
            or f~=nil and f>=1 and f<=24 or token:match('^kp%d$')~=nil)
    elseif device=='mouse' then
        if token=='wheelup' or token=='wheeldown' then return not a.held and not a.mouseOnly end
        local n=tonumber(token:match('^mouse(%d)$'));return n~=nil and n>=2 and n<=8
    elseif device=='controller' then
        if pads[token] then return true end
        local axis=token:match('^axis:(%a+)[+-]$');return axes[axis]==true
    elseif device=='touch' then return token:match('^touch[1-6]$')~=nil end
    return false
end
function B.defaults()
    local p={keyboard={},mouse={},controller={},touch={},layout={stick={x=.10,y=.80},cameraStick={x=.90,y=.34}},
        layoutVersion=2,showTouch=false,outsideCamera='fixed'}
    for _,a in ipairs(B.actions) do
        p.keyboard[a.id]=a.key or '';p.mouse[a.id]=a.mouse or ''
        p.controller[a.id]=a.pad or '';p.touch[a.id]=a.touch or ''
    end
    for i=1,6 do p.layout['touch'..i]={x=i%2==1 and .84 or .94,y=.62+math.floor((i-1)/2)*.14} end
    return p
end
function B.normalize(value)
    local p=B.defaults();value=type(value)=='table' and value or {}
    for _,device in ipairs(B.devices) do
        local source=type(value[device])=='table' and value[device] or {};local used={}
        for _,a in ipairs(B.actions) do
            local token=source[a.id]
            if B.valid(device,a.id,token) then p[device][a.id]=token end
            token=p[device][a.id]
            if token~='' then if used[token] then p[device][a.id]='' else used[token]=true end end
        end
    end
    p.showTouch=value.showTouch==true
    p.outsideCamera=value.outsideCamera=='follow' and 'follow' or 'fixed'
    local oldLayout=tonumber(value.layoutVersion) or 1
    for id,point in pairs(p.layout) do
        local sourceId=id=='cameraStick' and 'cameraStick' or id
        local v=type(value.layout)=='table' and value.layout[sourceId]
        if oldLayout<2 and type(v)=='table' then
            local index=tonumber(sourceId:match('^touch(%d)$'))
            if index then
                local oldX=index%2==1 and .84 or .94
                local oldY=.56+math.floor((index-1)/2)*.16
                if tonumber(v.x)==oldX and tonumber(v.y)==oldY then v=nil end
            end
        end
        if type(v)=='table' then
            local margin=(id=='stick' or id=='cameraStick') and .10 or .06
            for _,axis in ipairs({'x','y'}) do local n=tonumber(v[axis]);if n and n==n then point[axis]=math.max(margin,math.min(1-margin,n)) end end
        end
    end
    p.layoutVersion=2
    return p
end
function B.assign(p,device,id,token)
    if not B.valid(device,id,token) then return false,'Unavailable input. Esc / F10 / controller Start and left-click remain menu controls.' end
    local old=p[device][id];local swapped
    if token~='' then for _,a in ipairs(B.actions) do
        if a.id~=id and p[device][a.id]==token then
            p[device][a.id]=B.valid(device,a.id,old) and old or '';swapped=a.label;break
        end
    end end
    p[device][id]=token
    return true,swapped and ('Swapped with '..swapped..'.') or 'Binding saved.'
end
function B.action(p,device,token)
    for _,a in ipairs(B.actions) do if p[device][a.id]~='' and p[device][a.id]==token then return a.id end end
end
function B.label(token)
    if not token or token=='' then return 'Unbound' end
    local labels={['axis:leftx-']='LEFT STICK LEFT',['axis:leftx+']='LEFT STICK RIGHT',
        ['axis:lefty-']='LEFT STICK UP',['axis:lefty+']='LEFT STICK DOWN',
        ['axis:rightx-']='RIGHT STICK LEFT',['axis:rightx+']='RIGHT STICK RIGHT',
        ['axis:righty-']='RIGHT STICK UP',['axis:righty+']='RIGHT STICK DOWN',
        ['axis:triggerleft+']='LEFT TRIGGER',['axis:triggerright+']='RIGHT TRIGGER',
        leftshoulder='LEFT SHOULDER',rightshoulder='RIGHT SHOULDER',leftstick='LEFT STICK CLICK',rightstick='RIGHT STICK CLICK',
        dpup='D-PAD UP',dpdown='D-PAD DOWN',dpleft='D-PAD LEFT',dpright='D-PAD RIGHT',
        lalt='LEFT ALT',ralt='RIGHT ALT',lshift='LEFT SHIFT',rshift='RIGHT SHIFT',lctrl='LEFT CTRL',rctrl='RIGHT CTRL'}
    if labels[token] then return labels[token] end
    return (token:gsub('axis:',''):gsub('mouse','Mouse '):gsub('touch','Button '):gsub('wheelup','Wheel up'):gsub('wheeldown','Wheel down')):upper()
end
function B.hint(p,id) return B.label(p.keyboard[id]) end
function B.value(p,id,touch)
    local result=0;local key=p.keyboard[id]
    if key and key~='' and love.keyboard.isDown(key) then result=1 end
    local mouse=p.mouse[id];local button=mouse and tonumber(mouse:match('^mouse(%d)$'))
    if button and love.mouse.isDown(button) then result=1 end
    local token=p.controller[id]
    if token and token~='' and love.joystick then for _,joy in ipairs(love.joystick.getJoysticks()) do
        if joy:isGamepad() then
            local axis,sign=token:match('^axis:(%a+)([+-])$')
            if axis then
                local v=(joy:getGamepadAxis(axis) or 0)*(sign=='-' and -1 or 1)
                result=math.max(result,math.max(0,math.min(1,(v-.20)/.80)))
            elseif joy:isGamepadDown(token) then result=1 end
        end
    end end
    if touch and touch.held and touch.held[id] then result=1 end
    return result
end
local function wrapRadians(angle) return (angle+math.pi)%(math.pi*2)-math.pi end
function B.drive(p,touch,camera,bike)
    local x=B.value(p,'right',touch)-B.value(p,'left',touch)
    local throttle=B.value(p,'accelerate',touch)
    local brake=math.max(B.value(p,'brake',touch),B.value(p,'handbrake',touch))
    local touchX,touchY=touch and touch.x or 0,touch and touch.y or 0
    local magnitude=math.sqrt(touchX*touchX+touchY*touchY)
    if magnitude>.001 then
        if camera and not camera.firstPerson and bike and camera.screenVectorToWorld then
            -- In the outside view, the riding pad points toward a screen-space
            -- destination. The rider still turns through the bike's normal
            -- steering physics instead of teleporting its velocity.
            local worldX,worldZ=camera:screenVectorToWorld(touchX,touchY)
            local heading=math.atan2(worldZ,worldX)
            local reverse=bike.reverse==true
            local desiredHeading=heading+(reverse and math.pi or 0)
            local error=wrapRadians(desiredHeading-(bike.heading or 0))*(reverse and -1 or 1)
            -- The outside-view stick points toward a destination. Ease off
            -- the throttle while the bike is still aimed elsewhere, and brake
            -- when the requested direction is behind the bike. This gives the
            -- steering physics room to turn without carrying full speed into
            -- a wall or shoreline.
            x=math.max(-1,math.min(1,error/(math.pi*.5)))*magnitude*.78
            local alignment=math.cos(error)
            throttle=math.max(throttle,magnitude*math.max(0,alignment)^2)
            brake=math.max(brake,magnitude*math.max(0,-alignment))
        else
            if camera and camera.firstPerson then touchX=touchX*.78 end
            if math.abs(touchX)>math.abs(x) then x=touchX end
            throttle=math.max(throttle,math.max(0,-touchY))
            brake=math.max(brake,math.max(0,touchY))
        end
    end
    return x,brake>0 and brake or -throttle,B.value(p,'boost',touch)>.1
end
function B.camera(p,camera,dt,touch)
    if not camera then return end
    local x=B.value(p,'orbitRight',touch)-B.value(p,'orbitLeft',touch)
    local up=B.value(p,'tiltUp',touch)-B.value(p,'tiltDown',touch)
    local y
    if camera.firstPerson then
        -- The rider-eye camera uses positive pitch to look up.
        y=up-(touch and touch.cameraY or 0)
    else
        -- Outside tilt grows downward, so invert the conventional up input.
        y=-up+(touch and touch.cameraY or 0)
    end
    if touch then x=x+(touch.cameraX or 0) end
    if x~=0 or y~=0 then camera:orbit(x*72*dt,y*48*dt) end
end
function B.encode(p)
    p=B.normalize(p)
    local function encode(v)
        if type(v)=='string' then return string.format('%q',v) end
        if type(v)~='table' then return tostring(v) end
        local keys={};for key in pairs(v) do keys[#keys+1]=key end;table.sort(keys)
        local rows={};for _,key in ipairs(keys) do rows[#rows+1]='['..string.format('%q',key)..']='..encode(v[key]) end
        return '{'..table.concat(rows,',')..'}'
    end
    return encode(p)
end
return B
