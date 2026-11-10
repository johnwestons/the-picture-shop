-- On wide phones, spend the available height on the page instead of the CRT
-- bezel and decorative browser toolbar. All content and hit targets share one
-- reversible transform, including remote office instances and drag controls.
local Layout={}
local Text=require('src.screens.typography')
local Ui=require('src.screens.ui')
function Layout.active()
    local platform=love and love.system and love.system.getOS and love.system.getOS()
    if platform~='Android' and platform~='iOS' then return false end
    local w,h=love.graphics.getDimensions()
    return w/h>=1.7
end
function Layout.geometry()
    local Config=require('src.config')
    local bounds=require('src.viewport').gameBounds(Config.baseWidth,Config.baseHeight,true)
    local scale=math.min((bounds.width-32)/800,(bounds.height-78)/456)
    local width=800*scale;local left=(bounds.left+bounds.right-width)/2
    local tx,ty=left-78*scale,bounds.top+66-182*scale
    return {scale=scale,x=tx,y=ty,left=left,right=left+width,top=bounds.top,bounds=bounds,
        menu={x=left,y=bounds.top+8,width=300,height=48},
        close={x=left+width-124,y=bounds.top+8,width=124,height=48},
        options={x=left+width-254,y=bounds.top+8,width=124,height=48},
        clock={x=left+310,y=bounds.top+30,width=width-574,height=26}}
end
function Layout.toContent(x,y)
    if not x or not y or not Layout.active() then return x,y end
    local l=Layout.geometry()
    if Ui.contains(l.menu,x,y) then return 668,156 end
    if Ui.contains(l.close,x,y) then return 822,68 end
    if Ui.contains(l.clock,x,y) then return 823,656 end
    return (x-l.x)/l.scale,(y-l.y)/l.scale
end
function Layout.fromContent(x,y,name)
    if not x or not y or not Layout.active() then return x,y end
    local l=Layout.geometry()
    if name=='dropdownCenter' then return l.menu.x+l.menu.width/2,l.menu.y+l.menu.height/2 end
    if name=='closeCenter' then return l.close.x+l.close.width/2,l.close.y+l.close.height/2 end
    return l.x+x*l.scale,l.y+y*l.scale
end
function Layout.drawHeader(Runtime,state,pointerX,pointerY,twelveHour)
    local l=Layout.geometry();local g=love.graphics
    g.push('all');g.setShader()
    local tab=Runtime.tabById(Runtime.ComputerScreen.tab)
    Ui.panel(l.menu,{.05,.20,.22,1},Text.colors.border,5,1)
    Text.label((tab and tab.label or 'JOB DESK')..'  v',l.menu,{size=20})
    Ui.panel(l.close,Text.colors.panel,Text.colors.border,5,1);Text.label('BACK',l.close,{size=18})
    g.setFont(Text.get(20,'bold'));g.setColor(Text.colors.accent)
    local balance=require('src.screens.player_status').moneyText(state,l.clock.width,g.getFont())
    g.print(Text.ellipsize(balance,l.clock.width),l.clock.x,l.top+8)
    g.setFont(Text.get(18));g.setColor(Text.colors.body)
    g.print(Runtime.BusinessCalendar.shortDate(state)..'  '..Runtime.BusinessCalendar.timeText(state,twelveHour),l.clock.x,l.clock.y+3)
    g.pop()
end
function Layout.install(Runtime)
    local screen=Runtime.ComputerScreen
    for _,name in ipairs({'mousepressed','mousemoved','mousereleased'}) do
        local fn=screen[name]
        if fn then screen[name]=function(state,x,y,...)
            x,y=Layout.toContent(x,y);return fn(state,x,y,...)
        end end
    end
    for name,fn in pairs(screen) do
        if type(fn)=='function' and name:match('Center$') then
            local key=name
            screen[key]=function(...)
                local x,y=fn(...);return Layout.fromContent(x,y,key)
            end
        end
    end
end
return Layout
