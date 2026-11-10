local Config = require("src.config")
local BusinessCalendar = require("src.business_calendar")
local BackButton = require("src.screens.back_button")
local Ui = require("src.screens.ui")

local Hud = {}
local EXIT = { x = 816, y = 14, width = 126, height = 40 }

function Hud.exitRect(bounds)
    return {x=(bounds and bounds.right or Config.baseWidth)-EXIT.width-18,y=14,
        width=EXIT.width,height=EXIT.height}
end
function Hud.exitHit(x,y,bounds)
    return BackButton.contains(Hud.exitRect(bounds),x,y)
end
function Hud.drawExit(assets,pointerX,pointerY,bounds)
    local rect=Hud.exitRect(bounds)
    local hovered=pointerX and pointerY and BackButton.contains(rect,pointerX,pointerY)
    Ui.panel(rect,hovered and {.20,.27,.27,1} or {.12,.17,.18,1},{.43,.53,.51,1},4,1)
    require('src.screens.typography').label('EXIT TO MENU',rect,{size=14})
end

function Hud.draw(state, prompt, assets, pointerX, pointerY, mobile, controller, bounds,
        followPlayerCamera,twelveHourTime,feedback,sceneId,player)
    local Text=require('src.screens.typography')
    local Status=require('src.screens.player_status')
    bounds=bounds or {left=0,right=Config.baseWidth,bottom=Config.baseHeight}
    local left,right,bottom=bounds.left,bounds.right,bounds.bottom or Config.baseHeight
    local atHome=sceneId=='home' and state.home
    EXIT.x,EXIT.y=right-EXIT.width-18,14
    local g=love.graphics;g.push('all');g.setFont(Text.get(16))
    local rect=Status.draw(state,twelveHourTime,bounds,
        atHome and require('src.home_catalog').APARTMENTS[state.home.apartmentId].name or 'WAREHOUSE')
    local y=rect.y+rect.height+6
    local function card(text,color,width,size)
        width=math.max(180,width or rect.width)
        local lines,height,font=Text.lines(text,width-20,size or 16)
        local panel={x=left+18,y=y,width=width,height=height+14}
        Ui.panel(panel,Text.colors.panel,Text.colors.border,5,1)
        g.setFont(font);g.setColor(color or Text.colors.body)
        g.printf(text,panel.x+10,panel.y+7,width-20,'left')
        y=y+panel.height+6
        return panel
    end
    if not atHome then
        local inventory=state.inventory or {}
        local stock='Paper '..Ui.commaNumber(inventory.paper)..'   Samples '..Ui.commaNumber(inventory.prints)
        if state.bills and state.bills.balance>0 then stock=stock..'   Bills due '..Ui.money(state.bills.balance) end
        card(stock,Text.colors.muted,rect.width,14)
    end
    if feedback then
        local delta,timer=feedback:cashEffect()
        if timer and timer>0 and rect.width>=520 then
            g.setFont(Text.get(16,'bold'));g.setColor(delta>=0 and {.58,1,.73,1} or Text.colors.warning)
            g.print((delta>=0 and '+' or '−')..Ui.money(math.abs(delta)),rect.x+rect.width-125,rect.y+29)
        end
    end
    if state.message and state.message~='' then
        local messageWidth=atHome and math.min(rect.width,660) or rect.width
        card(state.message,Text.colors.body,messageWidth,16)
    end
    local homeNeedsTop=math.max(120,y)
    local week=state.home and state.home.weekend
    if week and week.phase~='working' then
        local status=require('src.weekend_flow').isOuting(state) and 'TOWN OUTING · The shop keeps its normal schedule.'
            or week.phase=='closing' and 'FRIDAY CLOSING · Finish work and pickups, then go home.'
            or week.phase=='ready' and 'SHOP CLOSED · Go home from the front entrance. Time is held.'
            or ('AT HOME · Return Monday at '..BusinessCalendar.formatTime(7,30,twelveHourTime)
                ..'. Shop opens '..BusinessCalendar.formatTime(9,0,twelveHourTime)..'.')
        -- Home needs occupy the left below the header; keep the weekend notice
        -- beside them, with its own backdrop instead of text on scene art.
        if atHome then
            local oldLeft=left;left=left+304;y=math.max(140,y)
            card(status,Text.colors.accent,math.max(210,right-left-24),14);left=oldLeft
        else card(status,Text.colors.accent,rect.width,14) end
    end
    if prompt and prompt~='' then
        local shown=prompt
        if mobile then
            shown=shown:gsub('^E%s+or%s+F:%s*','USE / PARK: '):gsub('^E:%s*','USE: ')
                :gsub('X:%s*dismiss applicant','DISMISS applicant')
        elseif controller then shown=shown:gsub('^E%s+or%s+F:%s*','A / X: '):gsub('^E:%s*','A: ') end
        local width=math.min(620,right-left-48)
        local _,height,font=Text.lines(shown,width-24,16,'bold')
        local panel={x=(left+right-width)/2,y=bottom-(mobile and 112 or 64)-height,width=width,height=height+20}
        Ui.panel(panel,Text.colors.panel,Text.colors.accent,6,1)
        g.setFont(font);g.setColor(Text.colors.accent);g.printf(shown,panel.x+12,panel.y+10,width-24,'center')
    end
    if atHome and player then require('src.home_activity_controls').drawHud(state,player,left,right,
        homeNeedsTop) end
    if not mobile then
        local hint=controller and 'LEFT STICK: Move   A: Use   X: Park   START: Menu' or 'WASD / arrows: Move   E: Use   O: Options'
        g.setFont(Text.get(14));local w=g.getFont():getWidth(hint)+20
        Ui.panel({x=left+18,y=bottom-32,width=w,height=26},Text.colors.panel,nil,4)
        g.setColor(Text.colors.muted);g.print(hint,left+28,bottom-27)
    end
    Hud.drawExit(assets,pointerX,pointerY,{right=right});g.pop()
end
function Hud.hitTest(x, y)
    return BackButton.contains(EXIT, x, y) and "exit" or nil
end

return Hud
