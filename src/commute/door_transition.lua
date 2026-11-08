-- Procedural doorway transition used by town businesses, apartments, and the
-- warehouse. Each design is drawn from vector primitives so the same entrance
-- can respond to its building style and current business hours.
local Door={DURATION=1.92,CLOSED_DURATION=2.65}

local function clamp(value,minimum,maximum)
    return math.max(minimum,math.min(maximum,value))
end
local function smooth(value)
    value=clamp(value,0,1)
    return value*value*(3-2*value)
end
local function mix(a,b,t)return a+(b-a)*t end
local function color(g,c,alpha)
    g.setColor(c[1],c[2],c[3],(c[4] or 1)*(alpha or 1))
end
local function polygon(g,c,points,alpha)
    color(g,c,alpha);g.polygon('fill',unpack(points))
end
local function line(g,c,width,...)
    color(g,c);g.setLineWidth(width);g.line(...)
end
local function styleFor(id)
    if id=='grocery' then return 'sliding-glass' end
    if id=='gas-station' or id=='diner' or id=='coffee-shop' then return 'glass-hinge' end
    if id=='warehouse' or id=='mechanic' or id=='butcher' or id=='farm' then return 'industrial' end
    if id=='brick-walkup' or id=='garden' or id=='courtyard' or id=='corner' then return 'apartment' end
    return 'wood'
end

function Door.new(action,token,buildingId,closedInfo)
    local closed=type(closedInfo)=='table'
    return {action=action,token=token,buildingId=buildingId,
        closedInfo=closed and closedInfo or nil,closed=closed,elapsed=0,
        duration=closed and Door.CLOSED_DURATION or Door.DURATION,
        style=styleFor(buildingId)}
end

function Door.update(transition,dt)
    if not transition then return false end
    transition.elapsed=transition.elapsed+math.max(0,dt or 0)
    return transition.elapsed>=(transition.duration or Door.DURATION)
end

local function drawRoom(g,x,y,w,h,open,style)
    -- An interior with a visible floor plane gives the camera push a clear
    -- destination and makes the aperture read as a passage rather than a mask.
    local light=.12+.62*open
    polygon(g,{.025+light*.34,.040+light*.29,.042+light*.21,1},
        {x,y,x+w,y,x+w,y+h,x,y+h})
    color(g,{.17+light*.44,.13+light*.34,.095+light*.19,1})
    g.rectangle('fill',x+w*.035,y+h*.04,w*.93,h*.58)
    color(g,{.30+light*.30,.22+light*.25,.13+light*.14,1})
    g.rectangle('fill',x+w*.07,y+h*.49,w*.86,h*.12)
    polygon(g,{.18+light*.36,.14+light*.27,.085+light*.15,1},
        {x,y+h*.60,x+w,y+h*.60,x+w*1.18,y+h,x-w*.18,y+h})
    for i=1,5 do
        local t=i/6
        line(g,{.50,.39,.25,1},math.max(1,w*.002),
            x+w*(.10+t*.18),y+h*.60,x+w*(t*.10),y+h)
    end
    for i=1,3 do
        local t=i/4
        line(g,{.50,.39,.25,1},math.max(1,h*.002),
            x+w*.035,y+h*(.60+t*.40),x+w*.965,y+h*(.60+t*.40))
    end
    -- Small, low-contrast silhouettes suggest shelves or counters inside.
    if style=='sliding-glass' or style=='glass-hinge' then
        color(g,{.32,.25,.15,.88*open})
        g.rectangle('fill',x+w*.12,y+h*.30,w*.24,h*.18,3)
        g.rectangle('fill',x+w*.67,y+h*.34,w*.20,h*.14,3)
        line(g,{.66,.48,.27,1},math.max(1,h*.006),
            x+w*.11,y+h*.43,x+w*.37,y+h*.43)
    elseif style=='industrial' then
        color(g,{.23,.27,.23,.84*open})
        g.rectangle('fill',x+w*.12,y+h*.28,w*.76,h*.20,2)
        for i=1,4 do
            local xx=x+w*(.15+i*.15)
            line(g,{.56,.48,.31,1},math.max(1,w*.003),xx,y+h*.30,xx,y+h*.47)
        end
    else
        color(g,{.32,.24,.16,.86*open})
        g.rectangle('fill',x+w*.66,y+h*.24,w*.18,h*.25,2)
    end
end

local function drawWallAndFrame(g,w,h,frameX,frameY,frameW,frameH)
    color(g,{.010,.015,.020,1});g.rectangle('fill',0,0,w,h)
    -- Broad wall planes, restrained grain and baseboard provide scale cues.
    color(g,{.055,.064,.060,1});g.rectangle('fill',frameX-frameW*.22,0,frameW*1.44,h)
    color(g,{.075,.078,.067,1});g.rectangle('fill',frameX-frameW*.19,0,frameW*.055,h)
    color(g,{.035,.044,.041,1});g.rectangle('fill',frameX+frameW*1.135,0,frameW*.055,h)
    color(g,{.14,.095,.054,1});g.rectangle('fill',frameX-frameW*.035,frameY,frameW*1.07,frameH)
    color(g,{.045,.041,.033,1});g.rectangle('fill',frameX+frameW*.035,frameY+frameH*.025,frameW*.93,frameH*.95)
    color(g,{.08,.09,.075,1});g.rectangle('fill',0,h*.89,w,h*.11)
    color(g,{.24,.15,.075,1});g.rectangle('fill',0,h*.875,w,h*.018)
end

local function point(x,y,w,h,u,v,rightTop,rightBottom)
    local right=mix(rightTop,rightBottom,v)
    return x+w*u,y+h*v,right
end

local function mappedQuad(g,x,y,w,h,rightTop,rightBottom,u0,v0,u1,v1,c,alpha)
    local ax,ay=point(x,y,w,h,u0,v0,rightTop,rightBottom)
    local bx,by=point(x,y,w,h,u1,v0,rightTop,rightBottom)
    local cx,cy=point(x,y,w,h,u1,v1,rightTop,rightBottom)
    local dx,dy=point(x,y,w,h,u0,v1,rightTop,rightBottom)
    polygon(g,c,{ax,ay,bx,by,cx,cy,dx,dy},alpha)
    return ax,ay,bx,by,cx,cy,dx,dy
end

local function drawHingedLeaf(g,x,y,w,h,style,opening,turn)
    local depth=style=='glass-hinge' and .045 or .085
    local open=opening
    -- A single projected door plane: the free edge rotates toward the hinge,
    -- and every inset, rail and handle uses the same mapping.
    local rightTop=x+w*(1-open*.94)
    local rightBottom=x+w*(1-open*(1-depth))
    if open>.94 then
        color(g,{.035,.032,.025,1});g.rectangle('fill',x-w*.012,y,w*.018,h)
        if style=='glass-hinge' then color(g,{.46,.48,.43,1});g.rectangle('fill',x+w*.004,y,w*.014,h) end
        return
    end
    mappedQuad(g,x,y,w,h,rightTop,rightBottom,0,0,1,1,
        style=='glass-hinge' and {.12,.18,.18,1} or style=='industrial' and {.22,.25,.22,1} or {.31,.18,.095,1})
    if style=='glass-hinge' then
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.075,.055,.925,.94,{.16,.27,.28,1},.86)
        for _,u in ipairs({.10,.50,.90}) do
            local ax,ay=point(x,y,w,h,u,.055,rightTop,rightBottom)
            local bx,by=point(x,y,w,h,u,.94,rightTop,rightBottom)
            line(g,{.74,.79,.72,1},math.max(1,w*.008),ax,ay,bx,by)
        end
        for _,v in ipairs({.055,.50,.94}) do
            local ax,ay=point(x,y,w,h,.075,v,rightTop,rightBottom)
            local bx,by=point(x,y,w,h,.925,v,rightTop,rightBottom)
            line(g,{.72,.77,.70,1},math.max(1,w*.008),ax,ay,bx,by)
        end
        local ax,ay=point(x,y,w,h,.21,.12,rightTop,rightBottom)
        local bx,by=point(x,y,w,h,.37,.88,rightTop,rightBottom)
        line(g,{.91,.89,.73,.6},math.max(1,w*.012),ax,ay,bx,by)
    elseif style=='industrial' then
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.07,.07,.93,.93,{.29,.32,.29,1})
        for v=.16,.88,.12 do
            local ax,ay=point(x,y,w,h,.07,v,rightTop,rightBottom)
            local bx,by=point(x,y,w,h,.93,v,rightTop,rightBottom)
            line(g,{.12,.15,.14,1},math.max(1,h*.009),ax,ay,bx,by)
            line(g,{.43,.46,.39,1},math.max(1,h*.003),ax,ay-h*.008,bx,by-h*.008)
        end
        for _,u in ipairs({.15,.85}) do
            local ax,ay=point(x,y,w,h,u,.08,rightTop,rightBottom)
            local bx,by=point(x,y,w,h,u,.92,rightTop,rightBottom)
            line(g,{.10,.13,.12,1},math.max(1,w*.008),ax,ay,bx,by)
        end
    else
        for _,row in ipairs({{.10,.43},{.56,.90}}) do
            mappedQuad(g,x,y,w,h,rightTop,rightBottom,.12,row[1],.88,row[2],{.22,.12,.065,1})
            mappedQuad(g,x,y,w,h,rightTop,rightBottom,.15,row[1]+.025,.85,row[2]-.025,{.39,.235,.12,1})
        end
        local ax,ay=point(x,y,w,h,.18,.50,rightTop,rightBottom)
        local bx,by=point(x,y,w,h,.82,.50,rightTop,rightBottom)
        line(g,{.16,.095,.05,1},math.max(1,w*.008),ax,ay,bx,by)
    end
    local hx,hy=point(x,y,w,h,.82,.53,rightTop,rightBottom)
    color(g,{.09,.07,.04,1});g.ellipse('fill',hx,hy,w*.027,h*.030)
    color(g,style=='glass-hinge' and {.88,.79,.51,1} or {.91,.68,.29,1})
    g.setLineWidth(math.max(2,w*.014))
    local angle=style=='glass-hinge' and -.12-turn*.55 or -.12-turn*.78
    g.line(hx,hy,hx+math.cos(angle)*w*.055,hy+math.sin(angle)*w*.055)
    g.circle('fill',hx+math.cos(angle)*w*.055,hy+math.sin(angle)*w*.055,math.max(2,w*.012))
end

local function drawSlidingPanel(g,x,y,w,h,opening,side)
    local half=w*.5
    local offset=opening*half*.94*(side=='left' and -1 or 1)
    local panelX=x+(side=='right' and half or 0)+offset
    -- Clip each translated glass leaf to the door aperture. It disappears
    -- into its side pocket as it slides, without cutting across the wall.
    local px=math.max(x,panelX)
    local panelRight=math.min(x+w,panelX+half)
    local visibleW=panelRight-px
    if visibleW<=0 then return end
    local inset=math.min(visibleW*.18,half*.09)
    color(g,{.14,.21,.22,1});g.rectangle('fill',px,y,visibleW,h)
    color(g,{.13,.31,.32,1});g.rectangle('fill',px+inset,y+h*.05,math.max(0,visibleW-inset*2),h*.89)
    -- Glass glints and rails move with the complete panel.
    color(g,{.87,.89,.78,.57});g.rectangle('fill',px+visibleW*.10,y+h*.055,visibleW*.035,h*.88)
    color(g,{.57,.64,.58,.8});g.rectangle('fill',px+visibleW*.86,y+h*.055,visibleW*.035,h*.88)
    color(g,{.74,.79,.68,.48});g.rectangle('fill',px+visibleW*.15,y+h*.14,visibleW*.62,h*.025)
    color(g,{.08,.11,.10,1});g.rectangle('fill',px,y,visibleW,h*.045)
    g.rectangle('fill',px,y+h*.955,visibleW,h*.045)
end

local function drawApartmentPlaque(g,x,y,w,h,buildingId)
    local number=({['brick-walkup']='12',garden='204',courtyard='3',corner='8'})[buildingId] or '12'
    local px,py=x+w*.78,y+h*.16
    color(g,{.13,.105,.075,1});g.rectangle('fill',px,py,w*.13,h*.085,3)
    color(g,{.80,.69,.44,1});g.rectangle('line',px,py,w*.13,h*.085,3)
    local font=g.getFont();local scale=math.min(w*.13/math.max(1,font:getWidth(number)),h*.06/math.max(1,font:getHeight()))
    color(g,{.94,.85,.62,1});g.printf(number,px,py+h*.012,w*.13,'center',0,scale,scale)
end

local function drawClosedSign(g,transition,x,y,w,h,time)
    local info=transition.closedInfo or {}
    local sway=math.sin(time*5.4)*.035
    local cx=x+w*.5;local sy=y+h*.24
    local signW=w*.53;local signH=h*.22
    local left,top=cx-signW*.5,sy
    local palette=transition.buildingId=='grocery' and {{.12,.30,.22,1},{.92,.88,.68,1}}
        or transition.buildingId=='gas-station' and {{.58,.10,.075,1},{.99,.84,.52,1}}
        or transition.buildingId=='mechanic' and {{.18,.20,.19,1},{.94,.68,.26,1}}
        or {{.26,.16,.085,1},{.94,.86,.67,1}}
    line(g,{.35,.30,.21,1},math.max(1,w*.006),cx-signW*.29,y+h*.055,left+signW*.15,top)
    line(g,{.35,.30,.21,1},math.max(1,w*.006),cx+signW*.29,y+h*.055,left+signW*.85,top)
    g.push();g.translate(cx,top+signH*.5);g.rotate(sway);g.translate(-cx,-(top+signH*.5))
    color(g,{.035,.025,.015,.38});g.rectangle('fill',left+signW*.018,top+signH*.05,signW,signH,5)
    color(g,palette[1]);g.rectangle('fill',left,top,signW,signH,5)
    color(g,palette[2]);g.setLineWidth(math.max(1,w*.007));g.rectangle('line',left+signW*.025,top+signH*.075,signW*.95,signH*.85,3)
    local font=g.getFont()
    local title='CLOSED'
    local titleScale=math.min(signW*.74/math.max(1,font:getWidth(title)),signH*.32/math.max(1,font:getHeight()))
    color(g,palette[2]);g.printf(title,left,top+signH*.14,signW,'center',0,titleScale,titleScale)
    local hours=info.hoursLine or 'HOURS 8:00 AM – 6:00 PM'
    local returnLine=info.returnLine or 'OPENS TOMORROW AT 8:00 AM'
    local smallScale=math.min(signW*.92/math.max(1,font:getWidth(hours)),signH*.19/math.max(1,font:getHeight()))
    color(g,palette[2]);g.printf(hours,left+signW*.025,top+signH*.55,signW*.95,'center',0,smallScale,smallScale)
    local returnScale=math.min(signW*.94/math.max(1,font:getWidth(returnLine)),signH*.17/math.max(1,font:getHeight()))
    g.printf(returnLine,left+signW*.02,top+signH*.75,signW*.96,'center',0,returnScale,returnScale)
    g.pop()
end

function Door.draw(transition,width,height)
    local g=love.graphics
    local duration=transition and transition.duration or Door.DURATION
    local time=clamp((transition and transition.elapsed or 0)/duration,0,1)
    local style=transition and transition.style or 'wood'
    local frameX,frameY=width*.225,height*.055
    local frameW,frameH=width*.55,height*.88
    local doorX,doorY=frameX+frameW*.105,frameY+frameH*.045
    local doorW,doorH=frameW*.79,frameH*.91
    local unlock=smooth((time-.10)/.15)
    local opening=transition and transition.closed and 0 or smooth((time-.26)/.43)
    local cameraPush=transition and transition.closed and 0 or smooth((time-.63)/.31)
    local fade=transition and transition.closed and smooth((time-.92)/.08) or smooth((time-.92)/.08)
    local bob=(transition and not transition.closed) and math.sin(time*25)*height*.004*cameraPush or 0

    g.push('all');g.setShader();color(g,{.004,.006,.009,1});g.rectangle('fill',0,0,width,height)
    g.translate(width*.5,height*.52+bob)
    g.scale(1+cameraPush*.34)
    g.translate(-width*.5,-height*.52)
    drawWallAndFrame(g,width,height,frameX,frameY,frameW,frameH)
    drawRoom(g,doorX+doorW*.035,doorY+doorH*.035,doorW*.93,doorH*.93,opening,style)

    -- The interior remains behind the opening. The leaf itself covers it when
    -- shut and reveals it naturally as its panels move away.
    if style=='sliding-glass' then
        color(g,{.19,.22,.19,1});g.rectangle('fill',doorX,doorY,doorW,doorH*.055)
        color(g,{.13,.16,.15,1});g.rectangle('fill',doorX,doorY+doorH*.955,doorW,doorH*.045)
        drawSlidingPanel(g,doorX,doorY,doorW,doorH,opening,'left')
        drawSlidingPanel(g,doorX,doorY,doorW,doorH,opening,'right')
        color(g,{.70,.73,.65,1});g.rectangle('fill',doorX+doorW*.492,doorY+doorH*.08,doorW*.016,doorH*.84)
    else
        local turn=unlock*(1-opening*.9)
        drawHingedLeaf(g,doorX,doorY,doorW,doorH,style,opening,turn)
        if style=='apartment' and not (opening>.96) then drawApartmentPlaque(g,doorX,doorY,doorW,doorH,transition and transition.buildingId) end
    end
    -- Fixed jambs and lintel give the moving panel a stable frame to pass.
    color(g,{.24,.15,.075,1});g.rectangle('fill',frameX,frameY,frameW*.075,frameH)
    g.rectangle('fill',frameX+frameW*.925,frameY,frameW*.075,frameH)
    color(g,{.52,.34,.18,1});g.rectangle('fill',frameX-frameW*.025,frameY,frameW*1.05,frameH*.045)
    color(g,{.35,.23,.13,1});g.rectangle('fill',frameX-frameW*.04,frameY+frameH*.955,frameW*1.08,frameH*.045)
    if transition and transition.closed then
        drawClosedSign(g,transition,doorX,doorY,doorW,doorH,transition.elapsed or 0)
    end
    g.pop()
    if fade>0 then color(g,{.003,.005,.007,fade});g.rectangle('fill',0,0,width,height) end
    g.setColor(1,1,1,1)
end

return Door
