-- Outside drags match Critter Party's logical-pixel orbit/pan sensitivity.
-- Choose the mode on press, so releasing Alt mid-drag cannot change the gesture.
local Controls={}
function Controls.press(state,button,leftAlt,bindings)
    local mode
    if bindings then
        mode=require('src.commute.bindings').action(bindings,'mouse','mouse'..button)
        if mode~='orbit' and mode~='pan' then return false end
    else
        if button~=2 and button~=3 then return false end
        mode=button==2 and 'pan' or 'orbit'
    end
    state.button=button
    state.mode=(mode=='pan' or leftAlt) and 'pan' or 'orbit'
    return true
end
function Controls.cancel(state) state.button=nil;state.mode=nil end
function Controls.release(state,button)
    if state.button~=button then return false end
    Controls.cancel(state);return true
end
function Controls.move(state,camera,dx,dy,scale)
    if not state.mode or not camera then return false end
    scale=math.max(.001,scale or 1);dx,dy=dx/scale,dy/scale
    -- Outside drags manipulate the world; rider-eye drags turn the head.
    -- Screen Y grows downward, while positive head pitch looks upward.
    if camera.firstPerson then camera:orbit(dx*.45,-dy*.25)
    elseif state.mode=='orbit' then camera:orbit(-dx*.45,dy*.25)
    else camera:pan(dx,dy) end
    return true
end
return Controls
