local Notices=require('src.notifications')
local Tutorial=require('src.tutorial')
local Ui=require('src.screens.ui')
local Text=require('src.screens.typography')
local Screen={}
local hidden={title=true,lan=true,direct=true,asset_error=true,options=true,notifications=true}
local rects={close={x=790,y=34,width=132,height=44},all={x=40,y=115,width=146,height=40},
    tutorial={x=194,y=115,width=146,height=40},previous={x=40,y=552,width=90,height=40},
    next={x=250,y=552,width=90,height=40},up={x=742,y=552,width=80,height=40},
    down={x=834,y=552,width=80,height=40},toggle={x=40,y=612,width=250,height=40},
    readAll={x=306,y=612,width=210,height=40}}
function Screen.available(R)return not hidden[R.state.screen]end
function Screen.buttonRect(bounds,R)
    local right=bounds and bounds.right or require('src.config').baseWidth
    if R and R.World and R.World.player.sceneId=='commute' then
        local hud=require('src.commute.cockpit');hud.syncLayout(R)
        local map=require('src.commute.runtime').miniMapRect(R)
        local x=hud.CARD_X+hud.CARD_WIDTH+8
        return {x=x,y=hud.CARD_Y+34,width=math.max(106,math.min(174,map.x-x-12)),height=34}
    end
    return {x=right-140,y=58,width=122,height=32}
end
local function changed(R)if R.App.playerFeedback then R.App.playerFeedback.dirty=true end end
function Screen.items(R)
    local result={}
    if R.state.notificationFilter=='tutorial' then
        for _,step in ipairs(Tutorial.steps) do
            local n=Notices.findKey(R.state,'tutorial:'..step.id)
            if n then result[#result+1]=n end
        end
        return result
    end
    for i=#Notices.ensure(R.state).items,1,-1 do
        local n=R.state.notifications.items[i]
        if R.state.notificationFilter~='tutorial' or n.kind=='tutorial' then result[#result+1]=n end
    end
    return result
end
function Screen.select(R,id)
    R.state.notificationSelection=id;R.state.notificationScroll=0
    if Notices.read(R.state,id) then changed(R) end
end
function Screen.open(R,id)
    if not Screen.available(R) then return false end
    local state=R.state
    state.notificationReturnScreen=state.screen
    if R.Input and R.inputContext then R.Input.mousereleased(-100,-100,1,R.inputContext) end
    if state.screen=='machine' and R.Machine and R.Machine.releaseOperator then R.Machine.releaseOperator(state) end
    if R.mobileControls then R.mobileControls:cancelAll() end
    state.screen='notifications';state.notificationFilter='all';state.notificationPage=1
    local list=Screen.items(R)
    Screen.select(R,id or list[1] and list[1].id)
    if R.syncMobileKeyboard then R.syncMobileKeyboard() end
    return true
end
function Screen.close(R)
    R.state.screen=R.state.notificationReturnScreen or 'world'
    R.state.notificationReturnScreen=nil
    if R.syncMobileKeyboard then R.syncMobileKeyboard() end
    return true
end
function Screen.scroll(R,amount)
    R.state.notificationScroll=math.max(0,math.min(R.state.notificationMaxScroll or 0,
        (R.state.notificationScroll or 0)+amount))
end
local function page(R,direction)
    local items=Screen.items(R);local pages=math.max(1,math.ceil(#items/6))
    R.state.notificationPage=math.max(1,math.min(pages,(R.state.notificationPage or 1)+direction))
    local first=items[(R.state.notificationPage-1)*6+1];Screen.select(R,first and first.id)
end
function Screen.pointer(R,x,y,button)
    if R.state.screen=='notifications' then
        if button~=1 then return true end
        for name,rect in pairs(rects) do if Ui.contains(rect,x,y) then
            if name=='close' then return Screen.close(R)
            elseif name=='all' or name=='tutorial' then
                if name=='tutorial' and Tutorial.addReferences(R.state) then changed(R) end
                R.state.notificationFilter=name;R.state.notificationPage=1;page(R,0)
            elseif name=='previous' or name=='next' then page(R,name=='next' and 1 or -1)
            elseif name=='up' or name=='down' then Screen.scroll(R,name=='down' and 180 or -180)
            elseif name=='toggle' then
                local t=R.state.tutorial
                if t and not t.finished then t.enabled=not t.enabled;changed(R)
                    if R.App.playerFeedback then
                        R.App.playerFeedback.tutorialStep=nil
                        for i=#R.App.playerFeedback.notices,1,-1 do
                            if R.App.playerFeedback.notices[i].kind=='tutorial' then table.remove(R.App.playerFeedback.notices,i) end
                        end
                    end
                end
            elseif name=='readAll' then
                for _,n in ipairs(Notices.ensure(R.state).items) do n.unread=false end;changed(R)
            end
            return true
        end end
        local items=Screen.items(R)
        for row=1,6 do
            local n=items[((R.state.notificationPage or 1)-1)*6+row]
            if n and Ui.contains({x=40,y=168+(row-1)*62,width=300,height=56},x,y) then Screen.select(R,n.id);break end
        end
        return true
    end
    if button~=1 or not Screen.available(R) then return false end
    if R.state.screen=='world' and not require('src.screens.hud_visibility').isVisible(R) then return false end
    local feedback=R.App and R.App.playerFeedback
    -- Arcade and standalone panels have no notices button. Without a toast,
    -- let their controls handle the pointer without requesting world geometry.
    if R.state.screen~='world' and not feedback then return false end
    local _,bounds=R.optionsAccessLayout()
    if R.state.screen=='world' and Ui.contains(Screen.buttonRect(bounds,R),x,y) then return Screen.open(R) end
    local toastBounds=R.syncCamera and R.syncCamera() or bounds
    local commute=R.state.screen=='world' and R.World and R.World.player
        and (R.World.player.sceneId=='commute' or R.World.player.sceneId=='grocery')
    local id=feedback and feedback:toastHit(x,y,commute and bounds or toastBounds,commute and 'commute' or R.state.screen)
    if id then return Screen.open(R,id) end
    return false
end
function Screen.keypressed(R,key)
    if R.state.screen~='notifications' then
        if key=='f6' then return Screen.open(R) end
        return false
    end
    if key=='escape' or key=='back' or key=='f6' then return Screen.close(R) end
    if key=='left' then page(R,-1) elseif key=='right' then page(R,1)
    elseif key=='pageup' then Screen.scroll(R,-220) elseif key=='pagedown' then Screen.scroll(R,220)
    elseif key=='up' or key=='down' then
        local list=Screen.items(R);local current=1
        for i,n in ipairs(list) do if n.id==R.state.notificationSelection then current=i end end
        current=math.max(1,math.min(#list,current+(key=='down' and 1 or -1)))
        if list[current] then R.state.notificationPage=math.ceil(current/6);Screen.select(R,list[current].id) end
    end
    return true
end
local function label(value,x,y,width,size,color)
    love.graphics.setFont(Text.get(size or 16));love.graphics.setColor(color or {.88,.93,.91,1})
    love.graphics.printf(value,x,y,width,'left')
end
local function button(rect,title,selected)
    Ui.panel(rect,selected and {.15,.30,.23,1} or {.10,.16,.18,1},{.34,.53,.46,1},5,1)
    Text.label(title,rect,{size=15})
end
function Screen.drawAccess(R,bounds)
    if R.state.screen~='world' then return end
    local count=Notices.unread(R.state);local rect=Screen.buttonRect(bounds,R)
    love.graphics.push('all')
    button(rect,'NOTICES'..(count>0 and (' '..(count>99 and '99+' or count)) or ''),count>0)
    love.graphics.pop()
end
function Screen.draw(R)
    local g=love.graphics;g.push('all');g.setShader()
    g.setColor(.025,.045,.05,1);g.rectangle('fill',0,0,960,678)
    label('NOTIFICATIONS',40,36,700,28,{.71,.96,.79,1})
    local t=R.state.tutorial or Tutorial.new(false)
    local status=t.finished and 'Tutorial complete' or t.enabled and ('Tutorial: lesson '..t.step..' of '..#Tutorial.steps) or 'Tutorial off'
    label(Notices.unread(R.state)..' unread  /  '..status,40,80,720,15)
    button(rects.close,'CLOSE / ESC');button(rects.all,'ALL',R.state.notificationFilter~='tutorial')
    button(rects.tutorial,'TUTORIAL',R.state.notificationFilter=='tutorial')
    local items=Screen.items(R);local currentPage=R.state.notificationPage or 1
    for row=1,6 do
        local n=items[(currentPage-1)*6+row]
        if n then
            local rect={x=40,y=168+(row-1)*62,width=300,height=56}
            Ui.panel(rect,n.id==R.state.notificationSelection and {.14,.28,.23,1} or {.07,.12,.14,1},{.22,.35,.32,1},4,1)
            local f=Text.get(14,'bold');g.setFont(f);g.setColor(.91,.96,.9,1)
            g.print(Text.ellipsize(n.title,274,f),rect.x+12,rect.y+8)
            label((n.unread and 'NEW  ·  ' or '')..n.kind:upper()..'  ·  Day '..(n.day+1),rect.x+12,rect.y+32,274,12,{.62,.80,.73,1})
        end
    end
    if #items==0 then label('No notifications here yet.\nNew messages and tutorial lessons will appear here.',52,204,276,17) end
    button(rects.previous,'PREV');button(rects.next,'NEXT')
    label(currentPage..' / '..math.max(1,math.ceil(#items/6)),158,564,80,15)
    Ui.panel({x=360,y=115,width=562,height=477},{.055,.10,.115,1},{.25,.40,.36,1},6,1)
    local n=Notices.find(R.state,R.state.notificationSelection)
    if n then
        label(n.title,382,136,516,22,{.86,.98,.88,1})
        label(n.detail,382,206,516,16,{.64,.82,.75,1})
        local lines,height,font=Text.lines(n.body,516,17)
        R.state.notificationMaxScroll=math.max(0,height-270)
        Screen.scroll(R,0)
        local sx,sy=g.transformPoint(382,268);local ex,ey=g.transformPoint(898,538)
        g.setScissor(sx,sy,ex-sx,ey-sy);g.setFont(font);g.setColor(.9,.94,.92,1)
        g.printf(n.body,382,268-(R.state.notificationScroll or 0),516,'left');g.setScissor()
        button(rects.up,'UP');button(rects.down,'DOWN')
        label(height>270 and 'Scroll for more / PgUp / PgDn' or 'Saved for you to revisit.',382,563,350,13,{.64,.82,.75,1})
    else label('Select a notification to read more.',382,156,516,20) end
    button(rects.toggle,t.finished and 'TUTORIAL COMPLETE' or t.enabled and 'PAUSE TUTORIAL' or 'ENABLE TUTORIAL')
    button(rects.readAll,'MARK ALL READ')
    label('Close to return to your game.',548,624,374,14)
    g.pop()
end
return Screen
