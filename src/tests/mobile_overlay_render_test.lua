-- Replays the warehouse restoration and wall-phone overlays through App.draw.
-- A clipped graphics state is injected after scene rendering to catch state
-- leaks that can hide full-screen UI on mobile devices.
local Test={}
local Condition=require('src.warehouse_condition')
local Calendar=require('src.business_calendar')
local Controls=require('src.shop_room_controls')
-- These points sit in the left/right margins of each overlay panel, away from
-- labels and row controls, so their pixels should remain dark over any scene.
local OVERLAY_SAMPLES={{100,180},{850,180},{100,350},{850,350},{100,550},{850,550}}

local function save(canvas,path)
    local data=canvas:newImageData()
    local png=data:encode('png')
    local file=assert(io.open(path,'wb'))
    file:write(png:getString())
    file:close();png:release();data:release()
end

local function pixelAtVirtual(data,R,x,y)
    local ox,oy,sx,sy=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,
        R.App.officeUsesSafeArea())
    local px=math.max(0,math.min(data:getWidth()-1,math.floor(ox+x*sx)))
    local py=math.max(0,math.min(data:getHeight()-1,math.floor(oy+y*sy)))
    local red,green,blue=data:getPixel(px,py)
    return {red,green,blue}
end

function Test.run(context,check)
    local R=assert(context.appRuntime)
    local g=love.graphics
    local mode=os.getenv('PICTURE_SHOP_UI_MODE') or 'desktop'
    local mobile=mode=='phone'
    local output=assert(os.getenv('PICTURE_SHOP_OVERLAY_OUTPUT'))
    local width,height=mobile and 832 or 960,mobile and 384 or 678
    assert(love.window.setMode(width,height,{resizable=true,minwidth=1,minheight=1,vsync=0}))
    local originalOS=love.system.getOS
    if mobile then love.system.getOS=function()return 'Android' end end

    local originalDraw=R.World.draw
    local originalSave=R.saveCurrent
    local originalQueue=R.Save.queue
    local oldHud=R.App.settings.hudVisible
    local function drawWithClippedState(...)
        originalDraw(...)
        -- Models a scene renderer leaving a restrictive canvas clip behind.
        g.setScissor(0,0,1,1)
    end
    local function drawCapture(name,sampleX,sampleY)
        local canvas=g.newCanvas(width,height)
        g.push('all');g.setCanvas({canvas,stencil=true});g.clear(.04,.05,.07,1)
        local okay,reason=xpcall(function()R.App.draw()end,debug.traceback)
        g.pop()
        assert(okay,reason)
        local data=canvas:newImageData()
        local points=type(sampleX)=='table' and sampleX or {{sampleX,sampleY}}
        local pixels={}
        for index,point in ipairs(points) do
            pixels[index]=pixelAtVirtual(data,R,point[1],point[2])
        end
        save(canvas,output..'/'..name..'.png')
        data:release();canvas:release()
        return pixels
    end
    local function screenTap(x,y,id)
        local ox,oy,_,sx,sy=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,
            R.App.officeUsesSafeArea())
        local px,py=ox+x*sx,oy+y*sy
        if mobile and R.mobileControls then
            R.App.touchpressed(id or 'overlay-tap',px,py)
            R.App.touchreleased(id or 'overlay-tap',px,py)
        else
            R.App.mousepressed(px,py,1,false)
            R.App.mousereleased(px,py,1,false)
        end
    end
    local function interact()
        if mobile and R.mobileControls then
            local button=R.mobileControls.primary
            local ox,oy,_,sx,sy=R.Viewport.transform(R.Config.baseWidth,R.Config.baseHeight,
                R.App.officeUsesSafeArea())
            R.App.touchpressed('overlay-interact',ox+button.x*sx,oy+button.y*sy)
            R.App.touchreleased('overlay-interact',ox+button.x*sx,oy+button.y*sy)
        else
            R.App.keypressed('e')
        end
    end
    local function renderOverlay(name)
        local pixels=drawCapture(name,OVERLAY_SAMPLES)
        local dark=0
        for _,pixel in ipairs(pixels) do
            if math.max(pixel[1],pixel[2],pixel[3])<.20 then dark=dark+1 end
        end
        check('mobile_overlay_'..name..'_visible_after_world_draw',dark==#pixels,
            ('dark_margin_pixels=%d/%d'):format(dark,#pixels))
        return pixels
    end

    local okay,reason=xpcall(function()
        require('src.image_loader').enabled=false
        local payload=assert(R.Save.newGame(3))
        assert(R.startGame(payload,'smoke'))
        R.saveCurrent=function()return true end
        R.Save.queue=function()return true end
        R.App.settings.hudVisible=true
        R.World.draw=drawWithClippedState
        R.state.warehouse.condition=Condition.new('story',42)
        R.state.money=1000
        local day=Calendar.totalDayForDate(2026,11,4)
        R.state.calendar=Calendar.dateFromHours(day*24)
        R.state.calendar.elapsed=Calendar.secondsPerDay(R.state)*10/24
        R.state.screen='world'
        R.World.load({id=1,sceneId='warehouse',x=218,y=185,
            character=R.World.player.character})
        R.World._state=R.state
        R.World.update(0,0,0,R.Assets,R.state)

        R.App.keypressed('j')
        check('mobile_overlay_story_utility_box_opens','shop_rooms'==R.state.screen
            and Controls.mode=='utilities')
        renderOverlay('utilities-menu')
        screenTap(300,264,'utility-power')
        check('mobile_overlay_power_reconnect_action_completes',Condition.of(R.state).powerConnected)
        R.App.keypressed('escape')
        check('mobile_overlay_utility_back_returns_to_world',R.state.screen=='world')

        R.World.load({id=1,sceneId='warehouse',x=218,y=185,
            character=R.World.player.character})
        R.World._state=R.state
        R.World.update(0,0,0,R.Assets,R.state)
        check('mobile_overlay_restoration_interaction_is_in_range',
            R.World.getInteraction() and R.World.getInteraction().kind=='restoration')
        interact()
        check('mobile_overlay_restoration_menu_opens','shop_rooms'==R.state.screen
            and Controls.mode=='restoration')
        renderOverlay('restoration-menu')
        if mobile then screenTap(300,354,'repair-breaker')
        else R.App.keypressed('down');R.App.keypressed('down');R.App.keypressed('return') end
        check('mobile_overlay_breaker_repair_action_completes',Condition.of(R.state).breakerRepaired)
        renderOverlay('restoration-after-repair')
        R.App.keypressed('escape')
        check('mobile_overlay_restoration_back_returns_to_world',R.state.screen=='world')

        local phoneTarget=R.Config.interactables.workPhone
        R.World.load({id=1,sceneId='warehouse',x=phoneTarget.x,y=phoneTarget.y,
            character=R.World.player.character})
        R.World._state=R.state
        local queued,call=R.WorkPhone.queueCall(R.state,
            {kind='supplier_status',caller='Regression caller',subject='Warehouse update'})
        assert(queued and call and R.state.workPhone.incoming==call,'could not queue incoming phone call')
        R.World.update(0,0,0,R.Assets,R.state)
        local foundX,foundY
        local Rooms=require('src.shop_rooms')
        for radius=0,math.min(phoneTarget.radius or 72,64),8 do
            for angle=0,350,10 do
                local x=phoneTarget.x+math.cos(math.rad(angle))*radius
                local y=phoneTarget.y+math.sin(math.rad(angle))*radius
                if Rooms.walkable(x,y,'warehouse') then
                    R.World.player.x,R.World.player.y=x,y
                    local candidate=R.World.interactionForPlayer(R.World.player)
                    if candidate and candidate.kind=='workPhone' then foundX,foundY=x,y;break end
                end
            end
            if foundX then break end
        end
        if foundX then R.World.player.x,R.World.player.y=foundX,foundY end
        R.World.selectedInteraction=foundX and R.World.interactionForPlayer(R.World.player) or nil
        local phoneInteraction=R.World.getInteraction()
        check('mobile_overlay_wall_phone_interaction_is_in_range',
            phoneInteraction and phoneInteraction.kind=='workPhone',
            ('target=%.1f,%.1f player=%.1f,%.1f scene=%s selected=%s'):format(
                phoneTarget.x,phoneTarget.y,R.World.player.x,R.World.player.y,
                tostring(R.World.player.sceneId),tostring(phoneInteraction and phoneInteraction.kind)))
        interact()
        check('mobile_overlay_wall_phone_screen_opens',R.state.screen=='work_phone')
        renderOverlay('work-phone-ringing')
        local x,y=R.WorkPhoneScreen.buttonCenter('action')
        screenTap(x,y,'answer-call')
        check('mobile_overlay_incoming_call_answers_from_screen',R.state.workPhone.incoming
            and R.state.workPhone.incoming.answered==true)
        renderOverlay('work-phone-answered')
        R.App.keypressed('escape')
        check('mobile_overlay_phone_back_returns_to_world',R.state.screen=='world')
        drawCapture('world-after-phone-back',440,400)
    end,debug.traceback)

    R.World.draw=originalDraw
    R.saveCurrent=originalSave
    R.Save.queue=originalQueue
    R.App.settings.hudVisible=oldHud
    love.system.getOS=originalOS
    assert(okay,reason)
end

return Test
