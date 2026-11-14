-- Close-up operator console. Machine motion stays in drawCutterScene; all
-- production changes pass through the existing local or host-owned machine API.
local Component={}
local ART='assets/generated/cutter-computer-v1/computer.png'
local ComputerArt=require('src.screens.cutter_computer_art')
local housing,palletArt,fonts
local scene={x=60,y=62,width=840,height=560}
local function rect(x,y,w,h)return {x=x,y=y,width=w,height=h} end
local function onMachine(x,y,w,h)
    return rect(scene.x+x*scene.width/768,scene.y+y*scene.height/512,w*scene.width/768,h*scene.height/512)
end
local tabs={pallets=rect(24,12,176,42),cutter=rect(208,12,160,42)}
local function text(value,x,y,w,size,color,align)
    local g=love.graphics
    fonts=fonts or {};fonts[size]=fonts[size] or g.newFont(size)
    g.setFont(fonts[size]);g.setColor(color or {.88,.94,.96,1})
    g.printf(tostring(value),x,y,w,align or 'left')
end
local function key(r,label,selected,hover)
    local g=love.graphics
    g.setColor(.015,.025,.035,1);g.rectangle('fill',r.x,r.y+4,r.width,r.height,5)
    g.setColor(selected and .13 or hover and .25 or .17,selected and .40 or .22,selected and .48 or .27,1)
    g.rectangle('fill',r.x,r.y,r.width,r.height,5)
    g.setColor(.45,.54,.60,1);g.rectangle('line',r.x+.5,r.y+.5,r.width-1,r.height-1,5)
    g.setColor(.60,.66,.70,.6);g.line(r.x+5,r.y+2,r.x+r.width-5,r.y+2)
    local size=#label<=3 and 20 or 13
    text(label,r.x+4,r.y+(r.height-size)/2,r.width-8,size,nil,'center')
end
local function card(index)
    return rect(44+((index-1)%2)*444,116+math.floor((index-1)/2)*145,428,132)
end

function Component.install(R)
    local S,M=R.Screen,R.Machine
    local old={enter=S.enter,draw=S.draw,mousepressed=S.mousepressed,keypressed=S.keypressed,
        mousereleased=S.mousereleased,buttonCenter=S.buttonCenter,hasModal=S.hasModal,
        loadMenuRowCenter=S.loadMenuRowCenter,loadMenuBackCenter=S.loadMenuBackCenter,update=S.update}
    local function active(state)return state.machineType~='skid_wrapper' and not S.helpOpen and not S.maintenanceView end
    local function factor()return S.gaugeUnit=='mm' and 25.4 or 1 end
    local function page(name)
        S.cutterPage=name;S.gaugeFocused=false;S.rotatePress=nil
        if name~='pallets' then S.loadMenu=nil end
    end
    local function menu(state)
        if not S.loadMenu and (M.step=='idle' or M.step=='finished') then R.openLoadMenu(state) end
        return S.loadMenu
    end
    function R.formatGauge()
        S.gaugeText=string.format('%.2f',(M.gauge or 0)*factor());S.gaugeReplaceOnType=true;S.gaugeDraft=false
    end
    function R.commitGauge(state)
        local value=tonumber(S.gaugeText)
        if not value then state.message='Enter a valid backgauge measurement.';return false end
        local okay=M.setGauge(value/factor(),state)
        if okay then S.gaugeDraft=false;S.gaugeReplaceOnType=true
            if not R.dependencies.remoteCommand then R.formatGauge() end
        end
        return okay
    end
    function S.enter()
        S.gaugeUnit='in';S.keyFeedback=nil;old.enter();page(M.loaded and 'cutter' or 'pallets')
    end
    S.cutterPage='pallets';S.gaugeUnit='in'
    R.loadMenuPageSize=6
    function R.layout()
        R.buttons={}
        local function add(id,label,r,value,shortcut)
            R.addButton(id,label,r.x,r.y,r.width,r.height,shortcut,value)
        end
        for name,r in pairs(tabs) do add('page',name:upper(),r,name) end
        if S.cutterPage=='computer' then
            add('page','BACK TO CUTTER',rect(376,12,168,42),'cutter')
            add('estop','E-STOP',rect(24,66,140,34),nil,'x')
            R.gaugeInput=rect(126,206,455,52)
            local digits={'7','8','9','4','5','6','1','2','3','C','0','.'}
            for i,label in ipairs(digits) do
                add('digit',label,rect(644+((i-1)%3)*73,176+math.floor((i-1)/3)*49,65,41),label)
            end
            add('erase','DELETE',rect(644,372,65,36));add('set_gauge','ENTER',rect(717,372,138,36))
            add('program','PREV',rect(644,414,65,36),math.max(1,(M.programIndex or 1)-1))
            add('program','NEXT',rect(717,414,65,36),math.min(4,(M.programIndex or 1)+1))
            add('auto','AUTO',rect(790,414,65,36),nil,'g')
            add('save','SAVE',rect(644,456,65,36),nil,'m');add('recall','RECALL',rect(717,456,65,36),nil,'v')
            add('unit','IN / mm',rect(790,456,65,36))
            for i,v in ipairs({-1,-.1,.1,1}) do add('gauge',v>0 and '+'..v or tostring(v),rect(662+(i-1)*46,498,42,36),v) end
            add('reset','RESET SAFETY',rect(594,66,150,34),nil,'r')
            add('barrier',M.barrierClear and 'BARRIER CLEAR' or 'BARRIER BLOCKED',rect(754,66,182,34),nil,'b')
        elseif S.cutterPage=='cutter' then
            add('computer','CUT COMPUTER',onMachine(249,8,230,123))
            add('estop','E-STOP',onMachine(477,67,45,48),nil,'x')
            add('cut_left','CUT',onMachine(525,67,48,48),nil,'j')
            add('cut_right','CUT',onMachine(576,67,48,48),nil,'k')
            add('position','PUSH / PULL STOCK',onMachine(238,238,293,63),nil,'p')
            add('clamp','CLAMP',onMachine(338,462,91,43),nil,'space')
            add('rotate','ROTATE',onMachine(280,337,208,62),nil,'q')
            local canPausePallet=M.step=='repeat_ready' and M.pallet and (tonumber(M.pallet.remainingSheets) or 0)>0
            local unloadLabel=M.paper and (M.paper.status~='complete' or canPausePallet) and 'UNLOAD' or 'TO PALLET'
            add('unload',unloadLabel,rect(24,568,140,40),nil,'u')
            add('repeat','NEXT LIFT',rect(796,568,140,40),nil,'t')
        end
    end
    R.exitButton=rect(832,12,104,42)
    R.helpButton=rect(552,12,104,42);R.maintenanceButton=rect(664,12,160,42)
    local function sendAction(state,b)
        S.pressedAction=b.action
        S.keyFeedback={x=b.x,y=b.y,remaining=.14,held=true}
        if b.action=='page' then page(b.value);if b.value=='pallets' then menu(state) end;return true end
        if b.action=='computer' then page('computer');R.formatGauge();return true end
        if b.action=='unit' then
            -- Unit selection only changes the readout, never moves the gauge.
            local inches=tonumber(S.gaugeText)
            if inches then inches=inches/factor() end
            S.gaugeUnit=S.gaugeUnit=='mm' and 'in' or 'mm'
            if inches then S.gaugeText=string.format('%.2f',inches*factor()) else R.formatGauge() end
            return true
        end
        if b.action=='digit' or b.action=='erase' then
            S.gaugeFocused=true
            if b.value=='C' then S.gaugeText='';S.gaugeReplaceOnType=false
            elseif b.action=='erase' then old.keypressed(state,'backspace')
            else S.textinput(state,b.value) end
            S.gaugeDraft=true;S.gaugeFocused=false;return true
        end
        if b.action=='set_gauge' then return R.commitGauge(state) end
        if b.action=='program' then return M.selectProgram(b.value,state) end
        if b.action=='cut_left' or b.action=='cut_right' then
            return M.guardedCut(state)
        end
        local okay
        if b.action=='estop' and M.emergencyStopped then return M.keypressed('r',state) end
        if b.action=='gauge' then okay=M.adjustGauge(b.value/factor(),state)
        elseif b.action=='auto' then okay=M.autoGauge(state)
        elseif b.action=='save' then okay=M.saveGauge(state)
        elseif b.action=='recall' then okay=M.recallGauge(state)
        else okay=M.keypressed(b.key,state) end
        if okay and (b.action=='gauge' or b.action=='auto' or b.action=='recall') then R.formatGauge() end
        return okay
    end
    function S.mousepressed(state,x,y,button)
        if not active(state) then return old.mousepressed(state,x,y,button) end
        if button~=1 then return false end
        S.gaugeFocused=false;R.layout()
        if R.inside(R.exitButton,x,y) then return {action='exit'} end
        if R.inside(R.helpButton,x,y) then S.helpOpen=true;return true end
        if R.inside(R.maintenanceButton,x,y) then
            if M.loaded or M.step~='idle' then state.message='Unload the cutter before opening service.';return true end
            S.loadMenu=nil;S.maintenanceView='hub';return {action='maintenance_hub'}
        end
        for _,b in ipairs(R.buttons) do if R.inside(b,x,y) then
            if b.action=='rotate' then S.rotatePress={x=x,y=y};return true end
            sendAction(state,b);return true
        end end
        if S.cutterPage=='computer' and R.inside(R.gaugeInput,x,y) then
            S.gaugeFocused=true;S.gaugeReplaceOnType=true;return true
        end
        if S.cutterPage=='pallets' then
            local list=menu(state)
            if list then
                local start=math.floor(((list.selected or 1)-1)/6)*6
                for i=1,6 do if list.options[start+i] and R.inside(card(i),x,y) then
                    if R.loadSelected(state,start+i) then page('cutter') end
                    return true
                end end
                if y>=568 and y<=608 then
                    if x<164 then list.selected=math.max(1,start-5)
                    elseif x>796 then list.selected=math.min(#list.options,start+7) end
                    return true
                end
            end
        end
        return true
    end
    function S.mousereleased(state,x,y,button)
        if button==1 and S.keyFeedback then S.keyFeedback.held=false end
        if active(state) and S.rotatePress and button==1 then
            local delta=x-S.rotatePress.x
            local center=scene.x+384*scene.width/768
            local direction=math.abs(delta)>16 and (delta<0 and 1 or -1) or (x<center and 1 or -1)
            S.rotatePress=nil;M.rotate(state,direction);return true
        end
        return old.mousereleased(state,x,y,button)
    end
    function S.keypressed(state,k)
        if not active(state) then return old.keypressed(state,k) end
        if k=='escape' or k=='back' then
            if S.cutterPage=='computer' then page('cutter');return true end
            S.loadMenu=nil;return false
        end
        if k=='l' and not S.gaugeFocused then page('pallets');menu(state);return true end
        if k=='x' then M.keypressed('x',state);return true end
        if S.cutterPage=='pallets' and S.loadMenu then
            local result=old.keypressed(state,k)
            if not S.loadMenu then page('cutter') end
            return result
        end
        if S.gaugeFocused then return old.keypressed(state,k) end
        if k=='j' or k=='k' then
            if M.guardedCut then M.guardedCut(state) else M.keypressed('j',state) end;return true
        end
        if S.cutterPage=='computer' then
            local result=M.keypressed(k,state)
            if result then R.formatGauge() end
            return result
        end
        return false
    end
    function S.hasModal()return S.helpOpen or S.maintenanceView~=nil or S.cutterPage=='computer' end
    function S.update(dt)
        if S.keyFeedback and not S.keyFeedback.held then
            S.keyFeedback.remaining=S.keyFeedback.remaining-dt
            if S.keyFeedback.remaining<=0 then S.keyFeedback=nil end
        end
        return old.update(dt)
    end
    function S.buttonCenter(action,value)
        if action=='load' then return tabs.pallets.x+88,tabs.pallets.y+21 end
        R.layout()
        for _,b in ipairs(R.buttons) do if b.action==action and (value==nil or value==b.value) then
            return b.x+b.width/2,b.y+b.height/2
        end end
    end
    function S.loadMenuRowCenter(index)
        local r=card(((index or 1)-1)%6+1);return r.x+r.width/2,r.y+r.height/2
    end
    function S.loadMenuBackCenter()return tabs.cutter.x+80,tabs.cutter.y+21 end
    function S.gaugeInputCenter()
        R.layout();return R.gaugeInput.x+R.gaugeInput.width/2,R.gaugeInput.y+R.gaugeInput.height/2
    end
    S.operatorSceneRect=scene
    local function rotationArrow(r,hover)
        local g=love.graphics
        -- A beveled ribbon on a flattened circular path, with a real extruded
        -- underside. Geometry scales with the registered machine hit target.
        local cx,cy=r.x+r.width/2,r.y+r.height*.40
        local rx,ry=r.width*.39,r.height*.35
        local points={}
        for i=0,26 do local a=math.rad(20+i*140/26)
            points[#points+1]=cx+math.cos(a)*rx;points[#points+1]=cy+math.sin(a)*ry end
        g.setLineJoin('bevel')
        for depth=7,0,-1 do
            local p={};for i,v in ipairs(points) do p[i]=v+(i%2==0 and depth or 0) end
            g.setColor(depth>0 and .34 or 1,depth>0 and .15 or hover and .77 or .60,.10,1)
            g.setLineWidth(12);g.line(p)
            g.polygon('fill',p[#p-1]-17,p[#p]+1,p[#p-1]+12,p[#p]-18,p[#p-1]+9,p[#p]+16)
            g.polygon('fill',p[1]+17,p[2]+1,p[1]-12,p[2]-18,p[1]-9,p[2]+16)
        end
        g.setLineWidth(2);g.setColor(1,.88,.49,.9);g.line(points)
    end
    local function drawComputer(state,assets,px,py)
        local g=love.graphics
        housing=housing or g.newImage(ART)
        g.setColor(1,1,1);g.draw(housing,0,68,0,960/housing:getWidth(),570/housing:getHeight())
        -- Live readout is rendered separately from its physical housing/keys.
        local label=ComputerArt.label
        label('BACKGAUGE CONTROL',126,179,350,22,'metal',{.49,.80,1,1})
        label('P'..(M.programIndex or 1),495,175,84,30,'lcd',{.49,.80,1,1},'right')
        label(S.gaugeText..(S.gaugeFocused and '_' or ''),126,204,355,56,'lcd',{.88,1,.81,1})
        label(S.gaugeUnit,500,231,80,24,'metal',{.66,.89,.85,1},'right')
        label(string.format('ACTUAL  %7.2f %s',(M.gauge or 0)*factor(),S.gaugeUnit),126,268,450,18,'program')
        for _,column in ipairs({{'STEP',126},{'EDGE',167},{'TARGET',255},{'ANGLE',371}}) do
            label(column[1],column[2],300,90,16,'metal',{.49,.80,1,1})
        end
        for i=1,4 do
            local cut=M.paper and M.paper.cuts[i]
            local row=cut and string.format('%02d  %-6s  %7.2f %-2s  %03d deg',i,cut.edge:upper(),cut.gauge*factor(),S.gaugeUnit,cut.orientation) or ('CUT '..i..'   --')
            local y=327+(i-1)*28
            if i==M.programIndex then g.setColor(.12,.32,.48,1);g.rectangle('fill',120,y-3,465,30) end
            label(row,126,y,450,17,'program')
        end
        for _,b in ipairs(R.buttons) do
            if b.action~='page' or b.x==376 then
                local feedback=S.keyFeedback
                local pressed=feedback and feedback.x==b.x and feedback.y==b.y
                if b.y>=176 and b.x>=644 then ComputerArt.key(b,b.label,pressed,px and R.inside(b,px,py))
                else key(b,b.label,false,px and R.inside(b,px,py)) end
            end
        end
        local saved=M.savedMeasurements(state,M.programIndex) or {}
        local values={};for _,v in ipairs(saved) do values[#values+1]=string.format('%.2f',v*factor()) end
        label('MEMORY  '..(#values>0 and table.concat(values,' / ') or 'EMPTY'),126,451,450,16,'program')
        if M.paper then
            label(string.format('STOCK  %.2f x %.2f %s\nROTATION  %03d deg',M.paper.currentSize.width*factor(),M.paper.currentSize.height*factor(),S.gaugeUnit,M.paper.orientation),126,488,450,16,'program')
        else label('LOAD A PALLET TO REVIEW ITS CUT PROGRAM',126,488,450,18,'metal') end
    end
    function S.draw(state,assets,px,py)
        if not active(state) then return old.draw(state,assets,px,py) end
        R.layout();local g=love.graphics;g.push('all');g.setShader()
        g.setColor(.025,.035,.045,1);g.rectangle('fill',0,0,960,678)
        for name,r in pairs(tabs) do key(r,name=='pallets' and 'NEARBY PALLETS' or 'CUTTER',S.cutterPage==name,px and R.inside(r,px,py)) end
        if S.cutterPage~='computer' then text('POLAR 115',382,26,160,18) end
        key(R.helpButton,'HELP');key(R.maintenanceButton,'SERVICE');key(R.exitButton,'EXIT')
        if S.cutterPage=='computer' then drawComputer(state,assets,px,py)
        elseif S.cutterPage=='pallets' then
            text('CHOOSE THE PALLET / RUN TO LOAD',44,76,870,20)
            local list=menu(state);local start=list and math.floor(((list.selected or 1)-1)/6)*6 or 0
            palletArt=palletArt or g.newImage('assets/generated/empty-pallet.png')
            for i=1,6 do local option=list and list.options[start+i]
                if option then local r=card(i);key(r,'',false,px and R.inside(r,px,py))
                    g.setColor(1,1,1);g.draw(palletArt,r.x+12,r.y+55,0,88/palletArt:getWidth(),52/palletArt:getHeight())
                    g.setColor(.85,.88,.88);g.rectangle('fill',r.x+25,r.y+35,66,37,2)
                    for line=1,7 do g.setColor(.53,.61,.66);g.line(r.x+25,r.y+35+line*4,r.x+91,r.y+35+line*4) end
                    text(option.title,r.x+112,r.y+12,r.width-124,14)
                    text(option.detail,r.x+112,r.y+49,r.width-124,13,{.66,.78,.82,1})
                    text('LOAD THIS PALLET',r.x+112,r.y+102,r.width-124,13,{.71,.90,.59,1})
                end
            end
            if not list or #list.options==0 then text(M.loaded and 'A run is already on the cutter. Switch to CUTTER to continue.' or 'No eligible pallets nearby. Move a paper pallet to the cutter staging area.',90,230,780,20,nil,'center') end
            key(rect(24,568,140,40),'PREVIOUS');key(rect(796,568,140,40),'NEXT')
        else
            S.drawCutterScene(assets,M,scene)
            for _,b in ipairs(R.buttons) do
                local hover=px and R.inside(b,px,py)
                if b.action=='rotate' then rotationArrow(b,hover)
                elseif b.action=='unload' or b.action=='repeat' then key(b,b.label,false,hover)
                elseif hover and b.action~='page' then
                    g.setColor(.60,.89,1,.85);g.setLineWidth(2);g.rectangle('line',b.x,b.y,b.width,b.height,5)
                    text(b.label,b.x-30,b.y+b.height+3,b.width+60,12,nil,'center')
                end
            end
        end
        local paper=M.paper;local pallet=M.pallet
        local summary=string.format('%s  |  GAUGE %.2f in  |  CLAMP %s  |  %s',tostring(M.step):upper(),M.gauge or 0,M.clamp and 'DOWN' or 'UP',M.emergencyStopped and 'E-STOP' or M.barrierClear and 'BARRIER CLEAR' or 'BARRIER BLOCKED')
        if paper then summary=summary..string.format('  |  CUT %d/%d',paper.activeCut or 1,#(paper.cuts or {})) end
        if pallet then summary=summary..string.format('  |  LIFT %d/%d',pallet.activeLift or 1,pallet.requiredLifts or 1) end
        text(summary,24,618,912,12,{.63,.83,.87,1})
        text(state.message or '',24,642,912,13,{.92,.84,.64,1})
        g.pop()
    end
end
return Component
