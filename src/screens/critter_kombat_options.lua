local Controls=require("src.critter_kombat_controls")
local Options={}
local tabs={"keyboard","mouse","gamepad","touch"}
local labels={keyboard="KEYBOARD",mouse="MOUSE",gamepad="CONTROLLER",touch="TOUCH LAYOUT"}
local fonts={}
local function inside(x,y,r) return x>=r[1] and x<=r[1]+r[3] and y>=r[2] and y<=r[2]+r[4] end
local function text(value,x,y,w,size,color)
    fonts[size]=fonts[size] or love.graphics.newFont("assets/fonts/VT323-Regular.ttf",size)
    love.graphics.setFont(fonts[size]);love.graphics.setColor(unpack(color or {1,.86,.55,1}))
    love.graphics.printf(value,x,y,w,"center")
end
local function button(r,label,selected,alpha)
    alpha=alpha or 1
    love.graphics.setColor(selected and .18 or .07,selected and .31 or .15,.21,alpha)
    love.graphics.rectangle("fill",r[1],r[2],r[3],r[4],5)
    love.graphics.setColor(selected and 1 or .4,selected and .8 or .54,.38,alpha)
    love.graphics.rectangle("line",r[1],r[2],r[3],r[4],5)
    text(label,r[1],r[2]+(r[4]-25)/2,r[3],25,{1,.86,.55,alpha})
end
local function rowRect(row) return {337,221+(row-1)*53,383,43} end
local function tabRect(index) return {96+(index-1)*192,112,180,44} end
local chrome={back={28,28,110,42},save={806,28,126,42},reset={666,28,128,42},
    smaller={130,166,42,34},larger={308,166,42,34},dimmer={428,166,42,34},brighter={608,166,42,34},show={713,166,181,34},
    deadLess={329,553,42,35},deadMore={589,553,42,35}}
function Options.enter(config,onSave,onBack)
    Options.draft=Controls.normalize(config);Options.onSave=onSave;Options.onBack=onBack
    Options.tab="keyboard";Options.row=1;Options.listening=nil;Options.drag=nil
    Options.message="Choose an action to change its binding."
end
local function begin()
    Options.listening=Controls.ACTIONS[Options.row]
    Options.message=Options.tab=="keyboard" and "Press a key. Escape cancels."
        or Options.tab=="mouse" and "Click a mouse button (1-5). Escape cancels."
        or "Press a button or move a stick/trigger. Escape / Back cancels."
end
local function bind(value)
    if Controls.assign(Options.draft,Options.tab,Options.listening,value) then
        Options.message="Binding updated. SAVE applies your changes.";Options.listening=nil;return true
    end
    return false
end
local function changeTab(index)
    Options.tab=tabs[(index-1)%4+1];Options.listening=nil;Options.drag=nil
    Options.message=Options.tab=="touch" and "Drag each control to its preferred position. SAVE applies the layout."
        or "Choose an action to change its binding."
end
local function save()
    Options.listening=nil;Options.drag=nil
    if not Options.onSave(Controls.normalize(Options.draft)) then Options.message="Could not save controls. Please try again." end
end
local function back() Options.listening=nil;Options.drag=nil;Options.onBack() end
local function reset()
    local defaults=Controls.default()
    if Options.tab=="touch" then
        Options.draft.touch=defaults.touch;Options.draft.touchScale=1;Options.draft.touchOpacity=.9;Options.draft.showTouch=true
    else Options.draft[Options.tab]=defaults[Options.tab] end
    Options.message="This tab was reset. SAVE applies the defaults."
end
function Options.keypressed(key)
    if Options.listening then
        if key=="escape" then Options.listening=nil;Options.message="Binding cancelled."
        elseif Options.tab=="keyboard" then bind(key) end
        return true
    end
    if key=="escape" then back()
    elseif key=="tab" then
        for i,tab in ipairs(tabs) do if tab==Options.tab then changeTab(i+1);break end end
    elseif key=="up" or key=="down" then Options.row=(Options.row-1+(key=="up" and -1 or 1))%6+1
    elseif key=="return" and Options.tab~="touch" then begin()
    elseif key=="s" then save()
    elseif key=="r" then reset()
    elseif key=="delete" and Options.tab~="touch" then
        Options.draft[Options.tab][Controls.ACTIONS[Options.row]]={};Options.message="Binding cleared. SAVE applies your changes."
    elseif Options.tab=="touch" and (key=="left" or key=="right") then
        local p=Options.draft.touch[Controls.ACTIONS[Options.row]];p.x=math.max(.04,math.min(.96,p.x+(key=="left" and -.01 or .01)))
    end
    return true
end
function Options.gamepadpressed(button)
    if Options.listening then
        if button=="back" then Options.listening=nil;Options.message="Binding cancelled."
        elseif Options.tab=="gamepad" then bind(button) end;return true
    end
    if button=="a" then if Options.tab~="touch" then begin() else Options.row=Options.row%6+1 end
    elseif button=="b" or button=="back" then back()
    elseif button=="start" then save()
    elseif button=="y" then reset()
    elseif button=="x" and Options.tab~="touch" then Options.draft[Options.tab][Controls.ACTIONS[Options.row]]={}
    elseif button=="dpup" or button=="dpdown" then Options.row=(Options.row-1+(button=="dpup" and -1 or 1))%6+1
    elseif button=="dpleft" or button=="dpright" or button=="leftshoulder" or button=="rightshoulder" then
        for i,tab in ipairs(tabs) do
            if tab==Options.tab then changeTab(i+((button=="dpleft" or button=="leftshoulder") and -1 or 1));break end
        end
    end
    return true
end
function Options.gamepadaxis(axis,value)
    if Options.listening and Options.tab=="gamepad" and math.abs(value)>.6 then bind(axis..(value>0 and "+" or "-")) end
    return true
end
function Options.cancelPending()
    Options.drag=nil;Options.listening=nil
end
function Options.mousepressed(x,y,buttonId,pointer)
    if Options.drag then return true end
    if Options.listening and Options.tab=="mouse" then if not pointer then bind(buttonId) end;return true end
    if buttonId~=1 then return true end
    if Options.listening then return true end
    if inside(x,y,chrome.back) then back();return true end
    if inside(x,y,chrome.save) then save();return true end
    if inside(x,y,chrome.reset) then reset();return true end
    for i=1,4 do if inside(x,y,tabRect(i)) then changeTab(i);return true end end
    if Options.tab=="touch" then
        if inside(x,y,chrome.smaller) then Options.draft.touchScale=math.max(.7,Options.draft.touchScale-.1)
        elseif inside(x,y,chrome.larger) then Options.draft.touchScale=math.min(1.5,Options.draft.touchScale+.1)
        elseif inside(x,y,chrome.dimmer) then Options.draft.touchOpacity=math.max(.3,Options.draft.touchOpacity-.1)
        elseif inside(x,y,chrome.brighter) then Options.draft.touchOpacity=math.min(1,Options.draft.touchOpacity+.1)
        elseif inside(x,y,chrome.show) then Options.draft.showTouch=not Options.draft.showTouch
        else
            for i,action in ipairs(Controls.ACTIONS) do
                local r=Controls.rect(Options.draft,action)
                if inside(x,y,r) then
                    Options.row=i;Options.drag={pointer=pointer or "mouse",action=action,dx=x-r[1]-r[3]/2,dy=y-r[2]-r[4]/2};break
                end
            end
        end
    else
        for i,action in ipairs(Controls.ACTIONS) do
            if inside(x,y,rowRect(i)) then Options.row=i;begin();break end
            if inside(x,y,{738,221+(i-1)*53,94,43}) then Options.row=i;Options.draft[Options.tab][action]={};break end
        end
        if Options.tab=="gamepad" then
            if inside(x,y,chrome.deadLess) then Options.draft.deadzone=math.max(.1,Options.draft.deadzone-.05)
            elseif inside(x,y,chrome.deadMore) then Options.draft.deadzone=math.min(.5,Options.draft.deadzone+.05) end
        end
    end
    return true
end
function Options.mousemoved(x,y,pointer)
    local drag=Options.drag
    if drag and drag.pointer==(pointer or "mouse") then
        local p=Options.draft.touch[drag.action]
        p.x=math.max(.04,math.min(.96,(x-drag.dx)/960));p.y=math.max(.18,math.min(.95,(y-drag.dy)/678))
        local r=Controls.rect(Options.draft,drag.action);p.x=(r[1]+r[3]/2)/960;p.y=(r[2]+r[4]/2)/678
    end
    return true
end
function Options.released(pointer)
    if Options.drag and Options.drag.pointer==(pointer or "mouse") then Options.drag=nil end
    return true
end
function Options.draw()
    love.graphics.push("all");love.graphics.setColor(.025,.04,.065,.97);love.graphics.rectangle("fill",0,0,960,678)
    text("CRITTER KOMBAT CONTROLS",150,29,510,36)
    button(chrome.back,"BACK");button(chrome.save,"SAVE");button(chrome.reset,"RESET TAB")
    text(Options.message,85,77,790,24,{.73,.85,.84,1})
    for i,tab in ipairs(tabs) do button(tabRect(i),labels[tab],Options.tab==tab) end
    if Options.tab=="touch" then
        button(chrome.smaller,"-");button(chrome.larger,"+");text("SIZE "..math.floor(Options.draft.touchScale*100+.5).."%",178,168,124,25)
        button(chrome.dimmer,"-");button(chrome.brighter,"+");text("ALPHA "..math.floor(Options.draft.touchOpacity*100+.5).."%",476,168,126,25)
        button(chrome.show,Options.draft.showTouch and "SHOW IN FIGHT" or "HIDE IN FIGHT")
        love.graphics.setColor(.07,.10,.13,1);love.graphics.rectangle("fill",24,211,912,458,5)
        text("TOUCH CONTROL PREVIEW",110,246,740,37,{.3,.4,.43,1})
        text("Each finger controls one action. Drag buttons here to rearrange them.",60,298,840,24,{.4,.53,.55,1})
        for i,action in ipairs(Controls.ACTIONS) do
            button(Controls.rect(Options.draft,action),action:upper(),Options.row==i,Options.draft.touchOpacity)
        end
    else
        for i,action in ipairs(Controls.ACTIONS) do
            text(action:upper(),130,229+(i-1)*53,180,27)
            button(rowRect(i),Options.listening==action and "LISTENING..." or Controls.label(Options.draft,Options.tab,action),Options.row==i)
            button({738,221+(i-1)*53,94,43},"CLEAR")
        end
        if Options.tab=="gamepad" then
            button(chrome.deadLess,"-");button(chrome.deadMore,"+")
            text("STICK DEADZONE "..math.floor(Options.draft.deadzone*100+.5).."%",376,557,206,25)
        end
        text("Enter: rebind   Tab: device   S: save   Esc: back",80,614,800,24,{.67,.8,.82,1})
        text("Controller: A rebind   shoulders device   Start save   B back",80,643,800,22,{.57,.69,.72,1})
    end
    love.graphics.pop()
end
return Options
