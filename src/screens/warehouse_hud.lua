-- The warehouse's compact desk-style status and menu. These are presentation
-- controls; balances, calendar, and notification history remain in game state.
local Calendar=require('src.business_calendar')
local Notices=require('src.notifications')
local Ui=require('src.screens.ui')
local Hud={menuOpen=false,noticesExpanded=true,narrowNoticesExpanded=false}
local images,fonts={},{}
local base='assets/generated/warehouse-hud-v1/'

local function image(name)
    if not images[name] then
        images[name]=love.graphics.newImage(base..name..'.png')
        images[name]:setFilter('linear','linear')
    end
    return images[name]
end
local function font(kind,size)
    local key=kind..size
    if not fonts[key] then
        local path=kind=='digital' and 'assets/fonts/VT323-Regular.ttf'
            or kind=='stencil' and 'assets/fonts/StardosStencil-Bold.ttf'
            or 'assets/fonts/CourierPrime-Bold.ttf'
        fonts[key]=love.graphics.newFont(path,size)
        fonts[key]:setFilter('linear','linear')
    end
    return fonts[key]
end
local function drawImage(name,r,alpha)
    local g=love.graphics;local sprite=image(name)
    g.setColor(1,1,1,alpha or 1)
    if name=='notice-banner' then
        -- The authored banner has transparent export margins. Use its painted
        -- band so the two text rows sit on the art rather than above and below it.
        local quad=images.noticeQuad
        if not quad then
            quad=g.newQuad(25,185,sprite:getWidth()-50,350,sprite:getDimensions())
            images.noticeQuad=quad
        end
        g.draw(sprite,quad,r.x,r.y,0,r.width/(sprite:getWidth()-50),r.height/350)
    else
        g.draw(sprite,r.x,r.y,0,r.width/sprite:getWidth(),r.height/sprite:getHeight())
    end
end
local function fits(r,x,y)return Ui.contains(r,x,y)end

function Hud.active(R)
    return R and R.state and R.state.screen=='world' and R.World and R.World.player
        and (R.World.player.sceneId=='warehouse' or R.World.player.sceneId=='commute')
end
function Hud.layout(bounds,terrain)
    local left=bounds and bounds.left or 0
    local right=bounds and bounds.right or 960
    local wide=right-left>1200
    if terrain and right-left<760 then
        return {
            terrain=true,narrow=true,
            cash={x=left+8,y=5,width=250,height=54},
            calendar={x=left+270,y=3,width=62,height=65},
            clock={x=left+346,y=7,width=104,height=51},
            noticeIcon={x=left+234,y=76,width=38,height=38},
            noticeToggle={x=left+278,y=80,width=28,height=28},
            noticePanel={x=left+8,y=194,width=300,height=60},
            menu={x=right-50,y=9,width=40,height=40},
            menuPanel={x=right-150,y=55,width=132,height=198},
        }
    end
    if terrain then
        local noticeX=left+(wide and 18 or 234)
        local noticeY=wide and 244 or 72
        return {
            terrain=true,wide=wide,
            cash={x=left+18,y=5,width=365,height=54},
            calendar={x=left+401,y=3,width=94,height=65},
            week={x=left+503,y=26,width=30,height=24},
            clock={x=left+540,y=7,width=120,height=51},
            noticeIcon={x=noticeX,y=noticeY,width=38,height=38},
            noticeToggle={x=noticeX+41,y=noticeY+4,width=28,height=28},
            noticePanel={x=noticeX+74,y=noticeY-1,
                width=wide and 300 or 328,height=60},
            menu={x=right-56,y=9,width=40,height=40},
            menuPanel={x=right-150,y=55,width=132,height=198},
        }
    end
    if right-left<760 then return {
        narrow=true,
        cash={x=left+8,y=8,width=165,height=52},
        calendar={x=left+183,y=3,width=80,height=76},
        week={x=left+267,y=33,width=28,height=24},
        clock={x=left+300,y=12,width=92,height=56},
        noticeIcon={x=left+8,y=84,width=38,height=38},
        noticeToggle={x=left+50,y=89,width=28,height=28},
        noticePanel={x=left+89,y=83,width=220,height=60},
        menu={x=right-50,y=12,width=40,height=42},
        menuPanel={x=right-150,y=62,width=132,height=198},
    } end
    if wide then return {
        wide=true,
        cash={x=left+14,y=7,width=230,height=64},
        calendar={x=left+270,y=3,width=133,height=101},
        week={x=left+416,y=39,width=48,height=33},
        clock={x=left+474,y=11,width=171,height=79},
        noticeIcon={x=left+18,y=111,width=48,height=48},
        noticeToggle={x=left+72,y=118,width=34,height=34},
        noticePanel={x=left+115,y=110,width=760,height=78},
        menu={x=right-70,y=12,width=52,height=52},
        menuPanel={x=right-190,y=70,width=172,height=258},
    } end
    return {
        cash={x=left+14,y=8,width=177,height=52},
        calendar={x=left+207,y=3,width=94,height=76},
        week={x=left+309,y=33,width=36,height=24},
        clock={x=left+345,y=12,width=116,height=56},
        noticeIcon={x=left+18,y=84,width=38,height=38},
        noticeToggle={x=left+60,y=89,width=28,height=28},
        noticePanel={x=left+94,y=83,width=520,height=60},
        menu={x=right-60,y=12,width=42,height=42},
        menuPanel={x=right-150,y=62,width=132,height=198},
    }
end
function Hud.layoutFor(R,bounds)
    bounds=bounds or {left=0,right=R and R.Config and R.Config.baseWidth or 960}
    return Hud.layout(bounds,R and R.World and R.World.player
        and R.World.player.sceneId=='commute')
end
function Hud.menuRow(layout,index)
    return {x=layout.menuPanel.x+6,
        y=layout.menuPanel.y+(layout.wide and 12 or 9)
            +(index-1)*(layout.wide and 78 or 59),
        width=layout.menuPanel.width-12,height=layout.wide and 72 or 54}
end

local function fitFont(kind,text,size,width,minimum)
    for n=size,minimum,-1 do
        local candidate=font(kind,n)
        if candidate:getWidth(text)<=width then return candidate end
    end
    return font(kind,minimum)
end
local function deepText(text,x,y,paint)
    local g=love.graphics
    g.setColor(0,0,0,.96)
    g.print(text,x+3,y+3)
    g.setColor(0,0,0,.78)
    g.print(text,x+1,y+2)
    g.setColor(paint)
    g.print(text,x,y)
end
local function cashFlow(r,feedback)
    if not feedback then return end
    local delta,remaining,duration=feedback:cashEffect()
    if not delta or delta==0 or not remaining or remaining<=0 then return end
    local g=love.graphics;local bill=image('flowing-bill')
    local elapsed=math.max(0,(duration or 1)-remaining)
    local alpha=math.min(.38,remaining*.58)
    for i=1,5 do
        local phase=(elapsed*1.7+(i-1)*.24)%1
        if delta<0 then phase=1-phase end
        local x=r.x+27+phase*(r.width-54)
        local y=r.y+22+((elapsed*2.5+i*.37)%1)*11
        g.setColor(1,1,1,alpha)
        g.draw(bill,x,y,math.sin(elapsed*6+i)*.17,
            32/bill:getWidth(),15/bill:getHeight(),bill:getWidth()/2,bill:getHeight()/2)
    end
end
function Hud.drawStatus(state,feedback,bounds,twelveHour)
    local g=love.graphics;local r=Hud.layout(bounds)
    local cash=Ui.money(state.money or 0)
    local date=Calendar.ensure(state)
    g.push('all');g.setShader()
    drawImage('cash-display',r.cash)
    cashFlow(r.cash,feedback)
    g.setFont(fitFont('digital',cash,r.wide and 43 or 31,r.cash.width-23,r.wide and 30 or 23))
    local cashY=r.cash.y+(r.wide and 13 or 11)
    g.setColor(0,0,0,.96)
    g.printf(cash,r.cash.x+18+2,cashY+3,r.cash.width-36,'center')
    g.setColor(.99,.84,.28,1)
    g.printf(cash,r.cash.x+18,cashY,r.cash.width-36,'center')
    drawImage('calendar',r.calendar)
    local month=Calendar.monthName(date.month):sub(1,3):upper()..' '..date.year
    g.setFont(fitFont('typewriter',month,r.wide and 19 or 14,r.calendar.width-12,10))
    local monthY=r.calendar.y+(r.wide and 6 or 4)
    g.setColor(1,.83,.52,.76)
    g.printf(month,r.calendar.x+7,monthY+1,r.calendar.width-12,'center')
    g.setColor(.04,.025,.015,1)
    g.printf(month,r.calendar.x+6,monthY,r.calendar.width-12,'center')
    g.setFont(font('typewriter',r.wide and 39 or 28));g.setColor(.20,.20,.17,1)
    g.printf(tostring(date.day),r.calendar.x+6,r.calendar.y+(r.wide and 39 or 29),r.calendar.width-12,'center')
    g.setFont(font('typewriter',r.wide and 15 or 11));g.setColor(.35,.32,.28,1)
    g.printf(Calendar.weekdayName(date.weekday):sub(1,3):upper(),
        r.calendar.x+6,r.calendar.y+(r.wide and 79 or 59),r.calendar.width-12,'center')
    g.setFont(font('typewriter',r.wide and 24 or 18))
    deepText('W'..Calendar.weekNumber(state),r.week.x,r.week.y,{.75,.90,.91,1})
    drawImage('alarm-clock',r.clock)
    local time=Calendar.timeText(state,twelveHour)
    local clockFont=fitFont('digital',time,r.wide and 42 or r.narrow and 24 or 29,
        r.clock.width-12,r.wide and 30 or r.narrow and 17 or 22)
    g.setFont(clockFont);g.setColor(.91,.94,.47,1)
    g.print(time,r.clock.x+(r.clock.width-clockFont:getWidth(time))/2,
        r.clock.y+(r.wide and 27 or 19))
    g.pop()
end

function Hud.drawTerrainStatus(state,feedback,bounds,twelveHour)
    local g=love.graphics;local r=Hud.layout(bounds,true)
    local date=Calendar.ensure(state)
    local function balance(label,amount,x,width)
        local value=Ui.money(amount or 0)
        g.setFont(font('typewriter',10));g.setColor(.98,.91,.65,1)
        g.printf(label,x,r.cash.y+9,width,'center')
        g.setFont(fitFont('digital',value,25,width-10,18))
        g.setColor(.99,.84,.28,1)
        g.printf(value,x,r.cash.y+19,width,'center')
    end
    g.push('all');g.setShader()
    drawImage('cash-display',r.cash)
    cashFlow(r.cash,feedback)
    local half=(r.cash.width-34)/2
    balance('HOME',(state.home and state.home.balanceCents or 0)/100,r.cash.x+17,half)
    balance('SHOP',state.money,r.cash.x+17+half,half)
    drawImage('calendar',r.calendar)
    local month=Calendar.monthName(date.month):sub(1,3):upper()
        ..(r.narrow and '' or ' '..date.year)
    g.setFont(fitFont('typewriter',month,12,r.calendar.width-10,9))
    g.setColor(.04,.025,.015,1)
    g.printf(month,r.calendar.x+5,r.calendar.y+3,r.calendar.width-10,'center')
    g.setFont(font('typewriter',26));g.setColor(.20,.20,.17,1)
    g.printf(tostring(date.day),r.calendar.x+5,r.calendar.y+23,r.calendar.width-10,'center')
    g.setFont(font('typewriter',10));g.setColor(.35,.32,.28,1)
    g.printf(Calendar.weekdayName(date.weekday):sub(1,3):upper(),
        r.calendar.x+5,r.calendar.y+47,r.calendar.width-10,'center')
    if r.week then
        g.setFont(font('typewriter',16))
        deepText('W'..Calendar.weekNumber(state),r.week.x,r.week.y,{.75,.90,.91,1})
    end
    drawImage('alarm-clock',r.clock)
    local time=Calendar.timeText(state,twelveHour)
    local face=fitFont('digital',time,r.narrow and 24 or 28,r.clock.width-14,r.narrow and 17 or 20)
    g.setFont(face);g.setColor(.91,.94,.47,1)
    g.print(time,r.clock.x+(r.clock.width-face:getWidth(time))/2,r.clock.y+18)
    g.pop()
end

local function circleButton(r,active)
    local g=love.graphics
    g.setColor(active and .14 or .045,active and .24 or .10,active and .20 or .11,.95)
    g.circle('fill',r.x+r.width/2,r.y+r.height/2,r.width/2)
    g.setColor(active and .91 or .56,active and .76 or .63,active and .40 or .57,1)
    g.setLineWidth(2);g.circle('line',r.x+r.width/2,r.y+r.height/2,r.width/2-2)
end
function Hud.drawNoticeIcon(rect,count)
    local g=love.graphics;local scale=rect.width/38
    g.push('all');g.setShader()
    circleButton(rect,count>0)
    g.setColor(.91,.92,.79,1)
    g.rectangle('fill',rect.x+13*scale,rect.y+10*scale,14*scale,18*scale,2)
    g.setColor(.19,.34,.29,1);g.setLineWidth(math.max(1,scale))
    g.line(rect.x+16*scale,rect.y+16*scale,rect.x+24*scale,rect.y+16*scale)
    g.line(rect.x+16*scale,rect.y+21*scale,rect.x+24*scale,rect.y+21*scale)
    if count>0 then
        g.setFont(font('digital',15));g.setColor(.99,.81,.34,1)
        g.print(tostring(math.min(count,99)),rect.x+rect.width-14,rect.y+rect.height-15)
    end
    g.pop()
end
local function noticeShown(R)
    local feedback=R.App and R.App.playerFeedback
    local live=feedback and feedback.notices[1]
    if live then return live end
    if feedback and (feedback.statusTimer or 0)>0 and feedback.statusText then
        return {title='SHOP STATUS',detail=feedback.statusText}
    end
    local items=Notices.ensure(R.state).items
    for i=#items,1,-1 do if items[i].unread then return items[i] end end
    return items[#items]
end
local function noticePanelRect(R,layout,selected)
    local title=selected and selected.title or 'All caught up'
    local detail=selected and selected.detail or 'Open the clipboard to review shop notices.'
    local titleFont=font('typewriter',layout.wide and 23 or 16)
    local detailFont=font('typewriter',layout.wide and 19 or 14)
    local width=math.max(titleFont:getWidth(title),detailFont:getWidth(detail))+42
    local minWidth=layout.wide and 310 or 230
    local r=layout.noticePanel
    return {x=r.x,y=r.y,width=math.max(minWidth,math.min(r.width,width)),height=r.height}
end
function Hud.drawNotices(R,bounds)
    if not Hud.active(R) then return end
    local g=love.graphics;local r=Hud.layoutFor(R,bounds)
    local expanded=Hud.noticesExpanded
    if r.narrow and r.terrain then expanded=Hud.narrowNoticesExpanded end
    local selected=noticeShown(R);local count=Notices.unread(R.state)
    local panel=noticePanelRect(R,r,selected)
    g.push('all');g.setShader();g.setFont(font('typewriter',r.wide and 20 or 14))
    circleButton(r.noticeIcon,count>0)
    -- A small folded sheet is the direct link to the clipboard.
    local iconScale=r.wide and 1.3 or 1
    g.setColor(.91,.92,.79,1)
    g.rectangle('fill',r.noticeIcon.x+13*iconScale,r.noticeIcon.y+10*iconScale,
        14*iconScale,18*iconScale,2)
    g.setColor(.19,.34,.29,1)
    g.line(r.noticeIcon.x+16*iconScale,r.noticeIcon.y+16*iconScale,
        r.noticeIcon.x+24*iconScale,r.noticeIcon.y+16*iconScale)
    g.line(r.noticeIcon.x+16*iconScale,r.noticeIcon.y+21*iconScale,
        r.noticeIcon.x+24*iconScale,r.noticeIcon.y+21*iconScale)
    if count>0 then
        g.setFont(font('digital',r.wide and 19 or 15));g.setColor(.99,.81,.34,1)
        g.print(tostring(math.min(count,99)),r.noticeIcon.x+r.noticeIcon.width-14,
            r.noticeIcon.y+r.noticeIcon.height-15)
    end
    circleButton(r.noticeToggle,expanded)
    g.setColor(.94,.90,.69,1);g.setLineWidth(2)
    local cx=r.noticeToggle.x+14;local cy=r.noticeToggle.y+14
    if expanded then g.line(cx-5,cy-2,cx,cy+3,cx+5,cy-2)
    else g.line(cx-3,cy-5,cx+2,cy,cx-3,cy+5) end
    if expanded then
        drawImage('notice-banner',panel,.73)
        g.setFont(font('typewriter',r.wide and 23 or 16));g.setColor(.99,.86,.47,1)
        local title=selected and selected.title or 'All caught up'
        g.print(require('src.screens.typography').ellipsize(title,panel.width-38),
            panel.x+19,panel.y+(r.wide and 10 or 7))
        g.setFont(font('typewriter',r.wide and 19 or 14));g.setColor(.91,.94,.86,1)
        local detail=selected and selected.detail or 'Open the clipboard to review shop notices.'
        g.print(require('src.screens.typography').ellipsize(detail,panel.width-38),
            panel.x+19,panel.y+(r.wide and 45 or 34))
    end
    g.pop()
end
function Hud.noticePointer(R,x,y,bounds)
    if not Hud.active(R) then return false end
    local r=Hud.layoutFor(R,bounds)
    if fits(r.noticeIcon,x,y) then return require('src.screens.notifications_screen').open(R) end
    if fits(r.noticeToggle,x,y) then
        if r.narrow and r.terrain then
            Hud.narrowNoticesExpanded=not Hud.narrowNoticesExpanded
        else Hud.noticesExpanded=not Hud.noticesExpanded end
        return true
    end
    local n=noticeShown(R)
    local expanded=Hud.noticesExpanded
    if r.narrow and r.terrain then expanded=Hud.narrowNoticesExpanded end
    if expanded and fits(noticePanelRect(R,r,n),x,y) then
        return require('src.screens.notifications_screen').open(R,n and n.id)
    end
    return false
end

function Hud.drawMenu(R,bounds)
    if not Hud.active(R) then Hud.menuOpen=false;return end
    local g=love.graphics;local r=Hud.layoutFor(R,bounds)
    local px,py=R.pointerPosition and R.pointerPosition()
    local hovered=px and py and fits(r.menu,px,py)
    g.push('all');g.setShader();g.setFont(font('typewriter',r.wide and 20 or 15))
    circleButton(r.menu,Hud.menuOpen or hovered)
    g.setColor(.96,.93,.77,1);g.setLineWidth(2.2)
    local mid=r.menu.x+r.menu.width/2
    for i=-1,1 do
        local y=r.menu.y+r.menu.height/2+i*(r.wide and 9 or 7)
        g.line(mid-(r.wide and 12 or 9),y,mid+(r.wide and 12 or 9),y)
    end
    if Hud.menuOpen then
        drawImage('menu-panel',r.menuPanel,.83)
        local rows={'OPTIONS','EXIT TO MENU',
            require('src.screens.hud_visibility').isVisible(R) and 'HIDE HUD' or 'SHOW HUD'}
        for i,label in ipairs(rows) do
            local row=Hud.menuRow(r,i)
            if px and py and fits(row,px,py) then
                g.setColor(.91,.79,.43,.17)
                g.rectangle('fill',row.x+4,row.y+6,row.width-8,row.height-12,4)
            end
            g.setColor(.96,.96,.87,1)
            g.printf(label,row.x,row.y+(r.wide and 27 or 20),row.width,'center')
        end
    elseif hovered then
        local tip={x=r.menu.x-94,y=r.menu.y+45,width=135,height=27}
        Ui.panel(tip,{.04,.09,.09,.95},{.53,.65,.53,1},4,1)
        g.setColor(.96,.96,.87,1);g.printf('SHOP MENU',tip.x,tip.y+5,tip.width,'center')
    end
    g.pop()
end
function Hud.menuPointer(R,x,y,button,bounds)
    if not Hud.active(R) or button~=1 then return false end
    local r=Hud.layoutFor(R,bounds)
    if fits(r.menu,x,y) then Hud.menuOpen=not Hud.menuOpen;return true end
    if not Hud.menuOpen then return false end
    for i=1,3 do
        local row=Hud.menuRow(r,i)
        if fits(row,x,y) then
            Hud.menuOpen=false
            if i==1 then return R.openOptions() end
            if i==2 then return R.returnToTitle() end
            return require('src.screens.hud_visibility').toggle(R)
        end
    end
    Hud.menuOpen=false
    return fits(r.menuPanel,x,y)
end
-- Restoration and utility menus share these cached HUD sprites and fonts so
-- the warehouse interface keeps one visual language and one texture copy.
Hud.sprite=image
Hud.font=font
return Hud
