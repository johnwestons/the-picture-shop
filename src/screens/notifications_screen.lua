local Notices=require('src.notifications')
local Tutorial=require('src.tutorial')
local Ui=require('src.screens.ui')
local Text=require('src.screens.typography')
local Clipboard=require('src.screens.notification_clipboard')
local WarehouseHud=require('src.screens.warehouse_hud')
local Screen={}
local hidden={title=true,lan=true,direct=true,asset_error=true,options=true,notifications=true}
Screen.layout=Clipboard.layout
Screen.detailHit=Clipboard.detailHit
function Screen.available(R)return not hidden[R.state.screen]end
function Screen.buttonRect(bounds,R)
    local right=bounds and bounds.right or require('src.config').baseWidth
    if WarehouseHud.active(R) then return WarehouseHud.layoutFor(R,bounds).noticeIcon end
    if R and R.World and R.World.player.sceneId=='commute' then
        local hud=require('src.commute.cockpit')
        local commute=require('src.commute.runtime')
        local map=commute.miniMapRect(R)
        local x=commute.cardX(R)+hud.CARD_WIDTH+8
        return {x=x,y=hud.CARD_Y+34,width=math.max(106,math.min(174,map.x-x-12)),height=34}
    end
    return {x=right-60,y=60,width=40,height=40}
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
    Screen.pageTurn=nil
    local list=Screen.items(R)
    Screen.select(R,id or list[1] and list[1].id)
    if R.syncMobileKeyboard then R.syncMobileKeyboard() end
    return true
end
function Screen.close(R)
    R.state.screen=R.state.notificationReturnScreen or 'world'
    R.state.notificationReturnScreen=nil
    Screen.pageTurn=nil
    if R.syncMobileKeyboard then R.syncMobileKeyboard() end
    return true
end
function Screen.scroll(R,amount)
    R.state.notificationScroll=math.max(0,math.min(R.state.notificationMaxScroll or 0,
        (R.state.notificationScroll or 0)+amount))
end
local function page(R,direction)
    local items=Screen.items(R);local pages=math.max(1,math.ceil(#items/6))
    local old=R.state.notificationPage or 1
    R.state.notificationPage=math.max(1,math.min(pages,old+direction))
    if R.state.notificationPage~=old then
        Screen.pageTurn={start=love.timer.getTime(),direction=direction,from=old}
    end
    local first=items[(R.state.notificationPage-1)*6+1];Screen.select(R,first and first.id)
end
function Screen.pointer(R,x,y,button)
    if R.state.screen=='notifications' then
        if button~=1 then return true end
        local layout=Clipboard.layout(R)
        for name,rect in pairs(layout.rects) do if Ui.contains(rect,x,y) then
            if name=='close' then return Screen.close(R)
            elseif name=='night' then
                R.App=R.App or {};R.App.settings=R.App.settings or {}
                local settings=R.App.settings
                settings.notificationClipboardDarkMode=not (settings.notificationClipboardDarkMode==true)
                if not require('src.settings').save(settings) then
                    R.state.message='Clipboard display preference could not be saved.'
                end
            elseif name=='all' or name=='tutorial' then
                if name=='tutorial' and Tutorial.addReferences(R.state) then changed(R) end
                R.state.notificationFilter=name;R.state.notificationPage=1;Screen.pageTurn=nil;page(R,0)
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
            if n and Ui.contains({x=layout.list.x,y=layout.list.y+(row-1)*46,
                    width=layout.list.width,height=44},x,y) then Screen.select(R,n.id);break end
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
    if WarehouseHud.active(R) then return WarehouseHud.noticePointer(R,x,y,bounds) end
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
        if list[current] then
            local old=R.state.notificationPage or 1
            R.state.notificationPage=math.ceil(current/6)
            if R.state.notificationPage~=old then
                Screen.pageTurn={start=love.timer.getTime(),direction=key=='down' and 1 or -1,from=old}
            end
            Screen.select(R,list[current].id)
        end
    end
    return true
end
function Screen.drawAccess(R,bounds)
    if R.state.screen~='world' then return end
    if WarehouseHud.active(R) then return WarehouseHud.drawNotices(R,bounds) end
    local count=Notices.unread(R.state);local rect=Screen.buttonRect(bounds,R)
    WarehouseHud.drawNoticeIcon(rect,count)
end
function Screen.draw(R)
    if not Clipboard.draw(R,Screen.items(R),Screen.pageTurn) then Screen.pageTurn=nil end
end
return Screen
