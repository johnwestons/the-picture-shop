-- Procedural doorway transition used by town businesses, apartments, and the
-- warehouse. Each design is drawn from vector primitives so the same entrance
-- can respond to its building style and current business hours.
local Door={DURATION=1.92,CLOSED_DURATION=4.65}

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
    if id=='warehouse' then return 'picture-shop' end
    if id=='mechanic' or id=='butcher' or id=='farm' then return 'industrial' end
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
    if style=='picture-shop' then
        color(g,{.37,.25,.15,.94*open});g.rectangle('fill',x+w*.08,y+h*.18,w*.84,h*.40,3)
        color(g,{.15,.12,.085,.95*open})
        for _,t in ipairs({.28,.52,.76}) do g.rectangle('fill',x+w*.07,y+h*t,w*.86,h*.025) end
        local papers={{.88,.79,.55,1},{.38,.55,.49,1},{.68,.39,.24,1},{.80,.76,.65,1}}
        for shelf=1,3 do
            local yy=y+h*(.205+shelf*.095)
            for stack=1,5 do
                local xx=x+w*(.12+stack*.135)
                local p=papers[(stack+shelf-2)%#papers+1]
                color(g,{.10,.085,.06,.85*open});g.rectangle('fill',xx,yy+h*.014,w*.105,h*.055,1)
                color(g,p,open);g.rectangle('fill',xx+w*.008,yy,w*.088,h*.045,1)
                color(g,{.96,.89,.70,.48*open});g.rectangle('fill',xx+w*.014,yy+h*.009,w*.060,h*.005)
            end
        end
        color(g,{.24,.16,.095,.96*open});g.rectangle('fill',x+w*.18,y+h*.51,w*.64,h*.10,2)
        color(g,{.65,.47,.25,.84*open});g.rectangle('fill',x+w*.20,y+h*.515,w*.60,h*.018)
        color(g,{.84,.75,.54,.85*open});g.rectangle('fill',x+w*.38,y+h*.43,w*.24,h*.07,2)
        color(g,{.27,.20,.12,.95*open});g.rectangle('fill',x+w*.40,y+h*.445,w*.20,h*.045,1)
        color(g,{.52,.39,.22,1});g.rectangle('fill',x+w*.07,y+h*.60,w*.86,h*.025)
    elseif style=='sliding-glass' or style=='glass-hinge' then
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

local function drawPictureShopSign(g,x,y,w,h)
    color(g,{.055,.035,.022,.44});g.rectangle('fill',x+w*.018,y+h*.10,w,h,2)
    color(g,{.83,.75,.58,1});g.rectangle('fill',x,y,w,h,2)
    color(g,{.30,.16,.075,1});g.setLineWidth(math.max(1,h*.055));g.rectangle('line',x+w*.025,y+h*.09,w*.95,h*.82,2)
    color(g,{.93,.87,.70,1});g.rectangle('fill',x+w*.045,y+h*.15,w*.91,h*.70)
    local font=g.getFont();local title='THE PICTURE SHOP';local subtitle='PAPER  /  PRINT  /  DESIGN'
    local titleScale=math.min(w*.82/math.max(1,font:getWidth(title)),h*.40/math.max(1,font:getHeight()))
    local subScale=math.min(w*.74/math.max(1,font:getWidth(subtitle)),h*.20/math.max(1,font:getHeight()))
    color(g,{.25,.13,.075,1});g.printf(title,x+w*.05,y+h*.20,w*.90,'center',0,titleScale,titleScale)
    color(g,{.42,.27,.14,1});g.printf(subtitle,x+w*.06,y+h*.62,w*.88,'center',0,subScale,subScale)
end

local function drawShopSconce(g,x,y,scale)
    color(g,{.16,.10,.055,1});g.rectangle('fill',x-scale*.10,y-scale*.025,scale*.20,scale*.10,2)
    color(g,{.28,.18,.08,1});g.rectangle('fill',x-scale*.035,y-scale*.15,scale*.07,scale*.15)
    color(g,{.79,.57,.25,1});g.polygon('fill',x-scale*.16,y-scale*.16,x+scale*.16,y-scale*.16,
        x+scale*.11,y-scale*.09,x-scale*.11,y-scale*.09)
    color(g,{.98,.76,.36,.35});g.ellipse('fill',x,y-scale*.07,scale*.12,scale*.16)
    color(g,{.91,.72,.39,1});g.rectangle('fill',x-scale*.09,y-scale*.065,scale*.18,scale*.025,1)
end

local function drawWallAndFrame(g,w,h,frameX,frameY,frameW,frameH,style)
    color(g,{.010,.015,.020,1});g.rectangle('fill',0,0,w,h)
    if style=='picture-shop' then
        local wallX,wallW=frameX-frameW*.22,frameW*1.44
        color(g,{.38,.18,.115,1});g.rectangle('fill',wallX,0,wallW,h*.89)
        color(g,{.50,.25,.16,1});g.rectangle('fill',wallX,frameY+frameH*.12,wallW,frameH*.66)
        for row=0,8 do
            local yy=frameY+frameH*(.15+row*.075)
            color(g,{.25,.12,.085,.70});g.setLineWidth(math.max(1,frameH*.002));g.line(wallX,yy,wallX+wallW,yy)
            color(g,{.64,.34,.21,.42});g.line(wallX,yy+frameH*.006,wallX+wallW,yy+frameH*.006)
            local offset=row%2==0 and wallW*.10 or wallW*.025
            for col=0,8 do
                local xx=wallX+offset+col*wallW*.115
                color(g,{.28,.13,.09,.55});g.setLineWidth(math.max(1,frameW*.002));g.line(xx,yy,xx,yy+frameH*.075)
            end
        end
        color(g,{.30,.13,.09,1});g.rectangle('fill',wallX,h*.80,wallW,h*.09)
        color(g,{.57,.30,.19,1});g.rectangle('fill',wallX,h*.80,wallW,h*.012)
        drawPictureShopSign(g,frameX+frameW*.18,frameY-frameH*.06,frameW*.64,frameH*.058)
        drawShopSconce(g,frameX-frameW*.14,frameY+frameH*.105,frameH*.08)
        drawShopSconce(g,frameX+frameW*1.14,frameY+frameH*.105,frameH*.08)
        color(g,{.22,.14,.08,1});g.rectangle('fill',frameX-frameW*.035,frameY,frameW*1.07,frameH)
        color(g,{.13,.11,.075,1});g.rectangle('fill',frameX+frameW*.035,frameY+frameH*.025,frameW*.93,frameH*.95)
        color(g,{.68,.49,.27,1});g.rectangle('fill',frameX-frameW*.025,frameY,frameW*1.05,frameH*.045)
        color(g,{.31,.20,.11,1});g.rectangle('fill',frameX-frameW*.04,frameY+frameH*.955,frameW*1.08,frameH*.045)
        color(g,{.08,.065,.045,1});g.rectangle('fill',0,h*.89,w,h*.11)
        color(g,{.48,.30,.16,1});g.rectangle('fill',0,h*.875,w,h*.018)
        return
    end
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
        style=='glass-hinge' and {.12,.18,.18,1} or style=='industrial' and {.22,.25,.22,1}
            or style=='picture-shop' and {.24,.27,.19,1} or {.31,.18,.095,1})
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
    elseif style=='picture-shop' then
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.045,.025,.955,.975,{.105,.135,.095,1})
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.065,.040,.935,.960,{.31,.33,.23,1})
        -- Raised dark-olive rails and inset panels match the shop's exterior door.
        for _,u in ipairs({.105,.48,.52,.895})do
            local ax,ay=point(x,y,w,h,u,.045,rightTop,rightBottom)
            local bx,by=point(x,y,w,h,u,.955,rightTop,rightBottom)
            line(g,{.17,.19,.13,1},math.max(1,w*.009),ax,ay,bx,by)
            line(g,{.48,.48,.33,.9},math.max(1,w*.0025),ax+w*.006,ay,bx+w*.006,by)
        end
        for _,v in ipairs({.345,.625,.875})do
            local ax,ay=point(x,y,w,h,.07,v,rightTop,rightBottom)
            local bx,by=point(x,y,w,h,.93,v,rightTop,rightBottom)
            line(g,{.16,.18,.12,1},math.max(1,h*.008),ax,ay,bx,by)
            line(g,{.51,.49,.34,.9},math.max(1,h*.0025),ax,ay-h*.005,bx,by-h*.005)
        end
        -- A nine-lite vision window adds depth and lets the warm shop interior read through.
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.275,.075,.725,.315,{.075,.09,.075,1})
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.292,.092,.708,.298,{.22,.34,.30,1})
        local columns={{.302,.418},{.442,.558},{.582,.698}}
        local rows={{.102,.158},{.174,.230},{.246,.292}}
        local glass={{.64,.59,.40,.34},{.13,.20,.17,.48},{.54,.60,.49,.32},
            {.17,.23,.18,.50},{.83,.68,.39,.36},{.15,.22,.18,.48},
            {.59,.61,.48,.32},{.14,.21,.17,.48},{.68,.62,.43,.34}}
        local pane=1
        for _,row in ipairs(rows)do
            for _,column in ipairs(columns)do
                mappedQuad(g,x,y,w,h,rightTop,rightBottom,column[1],row[1],column[2],row[2],glass[pane])
                pane=pane+1
            end
        end
        for _,u in ipairs({.43,.57})do
            local ax,ay=point(x,y,w,h,u,.095,rightTop,rightBottom)
            local bx,by=point(x,y,w,h,u,.305,rightTop,rightBottom)
            line(g,{.14,.16,.12,1},math.max(1,w*.008),ax,ay,bx,by)
        end
        for _,v in ipairs({.166,.238})do
            local ax,ay=point(x,y,w,h,.285,v,rightTop,rightBottom)
            local bx,by=point(x,y,w,h,.715,v,rightTop,rightBottom)
            line(g,{.14,.16,.12,1},math.max(1,h*.007),ax,ay,bx,by)
        end
        local gx1,gy1=point(x,y,w,h,.315,.115,rightTop,rightBottom)
        local gx2,gy2=point(x,y,w,h,.385,.115,rightTop,rightBottom)
        line(g,{.81,.73,.51,.78},math.max(1,w*.004),gx1,gy1,gx2,gy2)
        -- Four raised lower panels with subtle inset highlights.
        for _,box in ipairs({{.14,.385,.45,.575},{.565,.385,.86,.575},{.14,.665,.45,.835},{.565,.665,.86,.835}})do
            mappedQuad(g,x,y,w,h,rightTop,rightBottom,box[1],box[2],box[3],box[4],{.20,.23,.16,1})
            mappedQuad(g,x,y,w,h,rightTop,rightBottom,box[1]+.012,box[2]+.012,box[3]-.012,box[4]-.012,{.36,.38,.26,1})
            local lx,ly=point(x,y,w,h,box[1]+.018,box[2]+.02,rightTop,rightBottom)
            local rx,ry=point(x,y,w,h,box[3]-.018,box[2]+.02,rightTop,rightBottom)
            line(g,{.59,.57,.39,.78},math.max(1,h*.0022),lx,ly,rx,ry)
        end
        -- Brushed brass kick plate, hinge leaves, screws, and lever hardware.
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.085,.895,.915,.958,{.20,.18,.12,1})
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.095,.902,.905,.949,{.60,.47,.25,1})
        for i=1,5 do
            local v=.908+i*.007
            local lx,ly=point(x,y,w,h,.11,v,rightTop,rightBottom)
            local rx,ry=point(x,y,w,h,.89,v,rightTop,rightBottom)
            line(g,{.78,.65,.37,.55},math.max(1,h*.0012),lx,ly,rx,ry)
        end
        for _,v in ipairs({.18,.50,.82})do
            mappedQuad(g,x,y,w,h,rightTop,rightBottom,.025,v-.055,.085,v+.055,{.12,.13,.095,1})
            local hx,hy=point(x,y,w,h,.055,v,rightTop,rightBottom)
            color(g,{.61,.51,.31,1});g.circle('fill',hx,hy,math.max(1,w*.007))
        end
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.765,.475,.855,.615,{.12,.13,.09,1})
        mappedQuad(g,x,y,w,h,rightTop,rightBottom,.777,.488,.843,.602,{.68,.53,.29,1})
        local hx,hy=point(x,y,w,h,.81,.535,rightTop,rightBottom)
        color(g,{.24,.17,.075,1});g.ellipse('fill',hx,hy,w*.014,h*.018)
        color(g,{.92,.77,.43,1});g.setLineWidth(math.max(2,w*.012));g.line(hx,hy,hx+w*.052,hy-h*.003)
        g.circle('fill',hx+w*.052,hy-h*.003,math.max(2,w*.012))
        local lx,ly=point(x,y,w,h,.81,.585,rightTop,rightBottom)
        color(g,{.13,.11,.075,1});g.circle('fill',lx,ly,math.max(1,w*.008))
        color(g,{.85,.72,.43,1});g.circle('fill',lx,ly,math.max(1,w*.004))
    else
        for _,row in ipairs({{.10,.43},{.56,.90}}) do
            mappedQuad(g,x,y,w,h,rightTop,rightBottom,.12,row[1],.88,row[2],{.22,.12,.065,1})
            mappedQuad(g,x,y,w,h,rightTop,rightBottom,.15,row[1]+.025,.85,row[2]-.025,{.39,.235,.12,1})
        end
        local ax,ay=point(x,y,w,h,.18,.50,rightTop,rightBottom)
        local bx,by=point(x,y,w,h,.82,.50,rightTop,rightBottom)
        line(g,{.16,.095,.05,1},math.max(1,w*.008),ax,ay,bx,by)
    end
    if style~='picture-shop' then
        local hx,hy=point(x,y,w,h,.82,.53,rightTop,rightBottom)
        color(g,{.09,.07,.04,1});g.ellipse('fill',hx,hy,w*.027,h*.030)
        color(g,style=='glass-hinge' and {.88,.79,.51,1} or {.91,.68,.29,1})
        g.setLineWidth(math.max(2,w*.014))
        local angle=style=='glass-hinge' and -.12-turn*.55 or -.12-turn*.78
        g.line(hx,hy,hx+math.cos(angle)*w*.055,hy+math.sin(angle)*w*.055)
        g.circle('fill',hx+math.cos(angle)*w*.055,hy+math.sin(angle)*w*.055,math.max(2,w*.012))
    end
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
    drawWallAndFrame(g,width,height,frameX,frameY,frameW,frameH,style)
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
    color(g,style=='picture-shop' and {.21,.15,.08,1} or {.24,.15,.075,1});g.rectangle('fill',frameX,frameY,frameW*.075,frameH)
    g.rectangle('fill',frameX+frameW*.925,frameY,frameW*.075,frameH)
    color(g,style=='picture-shop' and {.68,.48,.24,1} or {.52,.34,.18,1});g.rectangle('fill',frameX-frameW*.025,frameY,frameW*1.05,frameH*.045)
    color(g,style=='picture-shop' and {.38,.25,.12,1} or {.35,.23,.13,1});g.rectangle('fill',frameX-frameW*.04,frameY+frameH*.955,frameW*1.08,frameH*.045)
    if transition and transition.closed then
        drawClosedSign(g,transition,doorX,doorY,doorW,doorH,transition.elapsed or 0)
    end
    g.pop()
    if fade>0 then color(g,{.003,.005,.007,fade});g.rectangle('fill',0,0,width,height) end
    g.setColor(1,1,1,1)
end

return Door
