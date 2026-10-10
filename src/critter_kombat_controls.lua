-- Device-local combat bindings and touch geometry; never part of a shop save.
local Codec=require("src.net.codec")
local Controls={ACTIONS={"left","right","jump","punch","kick","block"}}
Controls.PATH="critter-kombat-controls.dat"
local padButtons={}
-- Back and Escape stay available to leave the cabinet regardless of mappings.
for name in ("a b x y guide start leftstick rightstick leftshoulder rightshoulder dpup dpdown dpleft dpright"):gmatch("%S+") do padButtons[name]=true end
local axes={leftx=true,lefty=true,rightx=true,righty=true,triggerleft=true,triggerright=true}
local keys={}
for name in ("space return kpenter tab backspace delete insert home end pageup pagedown left right up down lshift rshift lctrl rctrl lalt ralt lgui rgui capslock numlock scrolllock pause printscreen menu application"):gmatch("%S+") do keys[name]=true end
for i=1,24 do keys["f"..i]=true end
for i=0,9 do keys["kp"..i]=true end
for name in ("kp. kp/ kp* kp- kp+ kp="):gmatch("%S+") do keys[name]=true end
local defaults={
    keyboard={left={"a","left"},right={"d","right"},jump={"space","w","up"},punch={"j"},kick={"k"},block={"l","s","down"}},
    mouse={left={},right={},jump={},punch={},kick={},block={}},
    gamepad={left={"dpleft","leftx-"},right={"dpright","leftx+"},jump={"a"},punch={"x"},kick={"y"},block={"rightshoulder"}},
    touch={left={x=125/960,y=638/678},right={x=201/960,y=638/678},jump={x=528/960,y=638/678},
        punch={x=615/960,y=638/678},kick={x=703/960,y=638/678},block={x=788.5/960,y=638/678}},
    touchScale=1,touchOpacity=.9,showTouch=true,deadzone=.22,
}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function bounded(v,a,b,fallback) return finite(v) and math.max(a,math.min(b,v)) or fallback end
function Controls.valid(kind,value)
    if kind=="keyboard" then return type(value)=="string" and (keys[value] or #value==1 and value:match("^[%w%p]$")~=nil) or false end
    if kind=="mouse" then return type(value)=="number" and value==math.floor(value) and value>=1 and value<=5 end
    if kind=="gamepad" then
        if type(value)~="string" then return false end
        if padButtons[value] then return true end
        local axis,sign=value:match("^(%a+)([+-])$")
        return axes[axis]==true and sign~=nil
    end
    return false
end
function Controls.normalize(value)
    value=type(value)=="table" and value or {}
    local result={touch={},touchScale=bounded(value.touchScale,.7,1.5,1),touchOpacity=bounded(value.touchOpacity,.3,1,.9),
        showTouch=value.showTouch~=false,deadzone=bounded(value.deadzone,.1,.5,.22)}
    for _,kind in ipairs({"keyboard","mouse","gamepad"}) do
        result[kind]={};local used={}
        for _,action in ipairs(Controls.ACTIONS) do
            local list=type(value[kind])=="table" and value[kind][action] or nil
            list=type(list)=="table" and list or defaults[kind][action]
            result[kind][action]={}
            for index=1,math.min(3,#list) do
                local binding=list[index]
                if Controls.valid(kind,binding) and not used[binding] then
                    result[kind][action][#result[kind][action]+1]=binding;used[binding]=true
                end
            end
        end
    end
    for _,action in ipairs(Controls.ACTIONS) do
        local p=type(value.touch)=="table" and value.touch[action] or nil
        p=type(p)=="table" and p or {}
        result.touch[action]={x=bounded(p.x,.04,.96,defaults.touch[action].x),y=bounded(p.y,.18,.95,defaults.touch[action].y)}
    end
    return result
end
function Controls.default() return Controls.normalize(defaults) end
function Controls.load()
    if not love.filesystem.getInfo(Controls.PATH,"file") then return Controls.default() end
    local bytes=love.filesystem.read(Controls.PATH)
    local value=bytes and Codec.decode(bytes) or nil
    return Controls.normalize(value)
end
function Controls.findGamepad(preferred)
    if preferred and (not preferred.isConnected or preferred:isConnected()) then return preferred end
    for _,pad in ipairs(love.joystick and love.joystick.getJoysticks() or {}) do
        if pad:isGamepad() and (not pad.isConnected or pad:isConnected()) then return pad end
    end
end
function Controls.save(value)
    local bytes=Codec.encode(Controls.normalize(value))
    return bytes and love.filesystem.write(Controls.PATH,bytes)==true or false
end
function Controls.assign(value,kind,action,binding)
    if not value[kind] or not value[kind][action] or not Controls.valid(kind,binding) then return false end
    -- Moving a binding removes its old assignment, avoiding accidental double actions.
    for _,name in ipairs(Controls.ACTIONS) do
        for i=#value[kind][name],1,-1 do if value[kind][name][i]==binding then table.remove(value[kind][name],i) end end
    end
    value[kind][action]={binding};return true
end
function Controls.label(value,kind,action)
    local result={}
    for _,binding in ipairs(value[kind][action]) do
        result[#result+1]=kind=="mouse" and ("Mouse "..binding) or tostring(binding):upper()
    end
    return #result>0 and table.concat(result," / ") or "UNBOUND"
end
function Controls.rect(value,action)
    local p=value.touch[action]
    local w,h=({left=70,right=70,jump=76,punch=86,kick=78,block=81})[action]*value.touchScale,48*value.touchScale
    local x=math.max(w/2+8,math.min(952-w/2,p.x*960))
    local y=math.max(200+h/2,math.min(670-h/2,p.y*678))
    return {x-w/2,y-h/2,w,h}
end
function Controls.input(value,active,mouse,pad,environment)
    environment=environment or love
    local on={}
    for _,action in ipairs(Controls.ACTIONS) do
        on[action]=active[action]==true
        for _,key in ipairs(value.keyboard[action]) do
            local okay,down=pcall(environment.keyboard.isDown,key)
            if okay and down then on[action]=true end
        end
        for _,button in ipairs(value.mouse[action]) do if mouse[button] then on[action]=true end end
        if pad and (not pad.isConnected or pad:isConnected()) then
            for _,binding in ipairs(value.gamepad[action]) do
                local axis,sign=binding:match("^(%a+)([+-])$")
                if axis then
                    local v=pad:getGamepadAxis(axis) or 0
                    if sign=="+" and v>value.deadzone or sign=="-" and v< -value.deadzone then on[action]=true end
                elseif pad:isGamepadDown(binding) then on[action]=true end
            end
        end
    end
    return (on.right and 1 or 0)-(on.left and 1 or 0),
        (on.jump and 1 or 0)+(on.punch and 2 or 0)+(on.kick and 4 or 0)+(on.block and 8 or 0)
end
return Controls
