local Rules=require("src.arcade_frontier.train_ambush_rules")
local CoopProgression=require("src.arcade_frontier.coop_progression")
local Scene=require("src.arcade_frontier.train_ambush_scene")
local Shooting=require("src.arcade_frontier.first_person_shooting")
local Typography=require("src.arcade_frontier.typography")
local Accessibility=require("src.arcade_frontier.accessibility")
local Ambush={}

function Ambush.new(context)
    local runtime,catalog=context.runtime,context.catalog
    local w,h=context.width,context.height
    local save=context.writeSave
    local service={}
    local bound,gun,data,impact
    local held,touches={},{}
    local paused=false
    local saveClock=0
    local controllerFire,controllerADS=false,false
    local controllerReady=false
    local actions={
        {label="FIRE\nLMB / SPACE",key="space"},{label="AIM\nRMB",key="aim"},{label="RELOAD\nR",key="r"},
        {label="COVER\nC",key="c"},{label="WEAPON\nTAB",key="tab"},{label="MODE\nV",key="v"},
        {label="WITHDRAW\nX",key="withdraw"},{label="PAUSE\nP",key="p"},
    }
    local function rect(index)
        local width=(w-40)/#actions
        return {x=20+(index-1)*width,y=h-76,w=width-5,h=56}
    end
    local function inside(r,x,y) return x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h end
    local function label(text,x,y,width,height,scale)
        Typography.drawText(love.graphics,text,x,y,width,height,{scale=(scale or .8)*Accessibility.textScale(data),minScale=.7,align="center",valign="center"})
    end
    function service:isCapturing()
        local state=runtime.saveData and runtime.saveData.trainAmbush
        return runtime.state=="game" and type(state)=="table" and state.active==true
    end
    function service:suspend()
        held={}; touches={}; controllerFire=false; controllerADS=false; controllerReady=false
        if gun then Shooting.setADS(gun,false) end
    end
    local function bind()
        if not service:isCapturing() then return false end
        data=runtime.saveData
        local state=Rules.start(data)
        if bound~=state then
            service:suspend()
            bound=state
            gun=Shooting.new(data,catalog,state,w,h)
            paused=false; saveClock=0; impact=nil
            runtime.dialogue=nil
        end
        runtime.trainAmbush=state
        return true
    end
    local function aim(x,y,touch)
        if not gun then return end
        if touch then Shooting.setTouchAim(gun,x,y,w,h)
        else Shooting.setAim(gun,math.max(0,math.min(w,x)),math.max(0,math.min(h,y))) end
    end
    local function fire()
        if paused or bound.phase~="combat" or bound.cover or bound.coverProgress>0 then return end
        if not Scene.pointOpen(bound,w,h,gun.aimX,gun.aimY) then return end
        local fired,reason=Shooting.fire(gun,data,bound)
        if not fired then
            if reason=="reload" then Shooting.reload(gun,data,bound); save() end
            return
        end
        bound.shots=bound.shots+1
        Shooting.playReport(gun.weapon,catalog,data)
        local target=Scene.target(bound,w,h,gun.aimX,gun.aimY)
        if Rules.hit(data,bound,target,gun) then impact={x=gun.aimX,y=gun.aimY,time=.22} end
        save()
    end
    local function fireHeld(source,down)
        local previous=held[source]
        held[source]=down or nil
        if down and not previous then fire() end
    end
    local function cycleWeapon()
        local options={}
        for _,entry in ipairs(Shooting.weaponOptions(data,catalog)) do
            if not entry.borrowed then options[#options+1]=entry end
        end
        if #options==0 then return end
        local selected=0
        for i,entry in ipairs(options) do if entry.name==gun.weapon and entry.itemId==gun.itemId then selected=i; break end end
        service:suspend()
        gun=Shooting.chooseWeapon(gun,options[selected%#options+1],data,catalog,bound)
        save()
    end
    local function continueJourney()
        if not CoopProgression.allowed(runtime,"ambush.continue") then return false,"host_only" end
        bound.active=false
        runtime.trainAmbush=nil
        service:suspend()
        bound=nil; gun=nil
        Scene.release(); Shooting.release()
        context.enterStop()
        save()
    end
    local function action(key)
        if key=="kpenter" then key="return" end
        if key=="p" then paused=not paused; service:suspend(); save(); return end
        if paused then
            if key=="return" or key=="space" then paused=false; service:suspend() end
            return
        end
        if bound.phase=="result" then
            if key=="return" then continueJourney() end
            return
        end
        if key=="withdraw" or key=="x" then
            if not CoopProgression.allowed(runtime,"ambush.withdraw") then return false,"host_only" end
            if Rules.withdraw(data,bound) then service:suspend(); save() end
        elseif key=="c" then
            bound.cover=not bound.cover; service:suspend(); save()
        elseif key=="r" then Shooting.reload(gun,data,bound); save()
        elseif key=="tab" then cycleWeapon()
        elseif key=="v" then Shooting.cycleFireMode(gun); save()
        elseif key=="aim" and not bound.cover then Shooting.setADS(gun,not gun.ads)
        elseif key=="space" then fireHeld("keyboard",true) end
    end
    function service:keypressed(key,_,isrepeat)
        if not bind() then return false end
        if not isrepeat then action(key) end
        return true
    end
    function service:keyreleased(key)
        if not self:isCapturing() then return false end
        if key=="space" then fireHeld("keyboard",false) end
        return true
    end
    function service:mousepressed(x,y,button,istouch)
        if not bind() then return false end
        if istouch then return true end
        if button==1 then
            if bound.phase=="result" then
                if inside({x=w/2-130,y=h*.61,w=260,h=58},x,y) then continueJourney() end
                return true
            end
            if paused then action("return"); return true end
            for i,item in ipairs(actions) do
                if inside(rect(i),x,y) then
                    if item.key=="space" then fireHeld("mouse",true) else action(item.key) end
                    return true
                end
            end
            aim(x,y); fireHeld("mouse",true)
        elseif button==2 and not paused and not bound.cover then aim(x,y); Shooting.setADS(gun,true) end
        return true
    end
    function service:mousemoved(x,y,_,_,istouch)
        if not bind() then return false end
        if not istouch and not paused and y<h-100 then aim(x,y) end
        return true
    end
    function service:mousereleased(_,_,button)
        if not self:isCapturing() then return false end
        if button==1 then fireHeld("mouse",false)
        elseif button==2 and gun then Shooting.setADS(gun,false) end
        return true
    end
    function service:touchpressed(id,x,y)
        if not bind() then return false end
        if paused or bound.phase=="result" then return self:mousepressed(x,y,1,false) end
        for i,item in ipairs(actions) do
            if inside(rect(i),x,y) then
                touches[id]=item.key
                if item.key=="space" then fireHeld("touch:"..tostring(id),true) else action(item.key) end
                return true
            end
        end
        touches[id]="aimdrag"; aim(x,y,true)
        return true
    end
    function service:touchmoved(id,x,y)
        if not self:isCapturing() then return false end
        if touches[id]=="aimdrag" and not paused then aim(x,y,true) end
        return true
    end
    function service:touchreleased(id)
        if not self:isCapturing() then return false end
        if touches[id]=="space" then fireHeld("touch:"..tostring(id),false) end
        touches[id]=nil
        return true
    end
    function service:gamepadpressed(_,button)
        if not bind() then return false end
        if button=="start" then action("p")
        elseif bound.phase=="result" and button=="a" then action("return")
        elseif button=="b" then action("withdraw")
        else
            local key=context.controlBindings:translateButton(button,"last_stand_shootout")
            if key then action(key) end
        end
        return true
    end
    function service:gamepadreleased(_,button)
        if not self:isCapturing() then return false end
        local key=context.controlBindings:translateButton(button,"last_stand_shootout")
        if key=="space" then fireHeld("keyboard",false) end
        return true
    end
    function service:focus(focused)
        if not focused and self:isCapturing() then paused=true; self:suspend(); save() end
    end
    function service:update(dt)
        if not CoopProgression.allowed(runtime,"ambush.continue") then return self:isCapturing() end
        if not bind() then
            if bound then self:suspend(); bound=nil; gun=nil; runtime.trainAmbush=nil; Scene.release(); Shooting.release() end
            return false
        end
        dt=math.min(dt,.1)
        if paused or bound.phase=="result" then return true end
        local bindings=context.controlBindings
        local dx,dy=bindings:axisValue("aim_x"),bindings:axisValue("aim_y")
        if dx~=0 or dy~=0 then aim(gun.aimX+dx*340*dt,gun.aimY+dy*340*dt) end
        local firing,ads=bindings:axisValue("fire")>.4,bindings:axisValue("ads")>.4
        if not firing and not ads then controllerReady=true end
        if controllerReady then
            if firing~=controllerFire then fireHeld("controller",firing) end
            if ads~=controllerADS and not bound.cover then Shooting.setADS(gun,ads) end
            controllerFire,controllerADS=firing,ads
        end
        Shooting.update(gun,dt,data,bound,w,h)
        if gun.fireMode=="auto" and next(held) then fire() end
        if impact then impact.time=impact.time-dt end
        local changed=Rules.update(data,bound,dt,function()
            Shooting.playReport("frontier-22-lever-rifle",catalog,data,true)
        end)
        saveClock=saveClock+dt
        if changed or saveClock>=1 then saveClock=0; save() end
        return true
    end
    function service:draw()
        if not bind() then return false end
        local g=love.graphics
        g.push("all")
        g.setFont(Typography.font(g))
        Scene.draw(bound,w,h,Accessibility.ensure(data),impact)
        if bound.coverProgress==0 and bound.phase~="result" then
            Shooting.draw(gun,w,h)
            g.setColor(1,.94,.75,1)
            local x,y=gun.aimX,gun.aimY
            g.line(x-9,y,x-3,y); g.line(x+3,y,x+9,y); g.line(x,y-9,x,y-3); g.line(x,y+3,x,y+9)
        end
        -- All interface elements are drawn after the window and weapon art.
        g.setColor(.035,.025,.02,.94); g.rectangle("fill",16,12,w-32,54,6,6)
        g.setColor(1,.89,.68,1)
        label("HEALTH "..math.ceil(data.health or 20).." / "..(data.maxHealth or 20),22,17,205,42)
        label("CARRIAGE "..bound.protection.." / "..bound.maxProtection,232,17,235,42)
        local hull,maxHull=Rules.hullTotal(bound)
        label("CONVOY "..math.ceil(hull).." / "..maxHull,480,17,235,42)
        label("BANDITS "..Rules.crewTotal(bound),730,17,w-750,42)
        g.setColor(.035,.025,.02,.94); g.rectangle("fill",0,h-143,w,143)
        g.setColor(1,.89,.68,1)
        local name=(gun.weapon or "No firearm"):gsub("%-"," "):upper()
        local status=gun.reloadTimer>0 and "RELOADING" or gun.fireMode or ""
        label(name.."   "..(gun.magazine or 0).." / "..Shooting.rounds(gun,data,bound).." ROUNDS   "..status:upper(),25,h-141,w-50,29,.77)
        local hint=bound.phase=="approach" and "The bandit convoy is pulling alongside."
            or bound.phase=="depart" and "The bandit convoy is falling behind."
            or bound.cover and "IN COVER - the carriage is still taking fire."
            or "Disable the convoy or stop its bandits. Withdrawal costs 6 train condition."
        if bound.phase=="combat" and not Shooting.hasUsableFirearm(data,catalog) then hint="No ammunition remaining. Switch weapons or withdraw." end
        label(hint,30,h-111,w-60,30,.72)
        for i,item in ipairs(actions) do
            local r=rect(i)
            g.setColor(.12,.075,.035,.96); g.rectangle("fill",r.x,r.y,r.w,r.h,5,5)
            g.setColor(.73,.49,.22,1); g.rectangle("line",r.x,r.y,r.w,r.h,5,5)
            g.setColor(1,.89,.68,1); label(item.label,r.x+2,r.y+2,r.w-4,r.h-4,.69)
        end
        if paused or bound.phase=="result" then
            g.setColor(0,0,0,.8); g.rectangle("fill",0,0,w,h)
            g.setColor(1,.89,.68,1)
            if paused then
                label("PAUSED",100,h*.3,w-200,60,1.3)
                label("P / START to resume. Tap to resume.",100,h*.45,w-200,55)
            else
                local won=bound.outcome=="disabled" or bound.outcome=="crew"
                label(won and "BANDITS DRIVEN OFF" or "ENCOUNTER ENDED",90,h*.27,w-180,60,1.25)
                local text=string.format("Salvage: %d scrap\nHealth lost: %d   Train condition lost: %d\nShots fired: %d",bound.reward or 0,bound.playerDamage,bound.trainDamage,bound.shots)
                label(text,120,h*.37,w-240,120,.95)
                g.setColor(.22,.13,.06,1); g.rectangle("fill",w/2-130,h*.61,260,58,6,6)
                g.setColor(1,.89,.68,1); label("CONTINUE  [ENTER / A]",w/2-125,h*.61,250,58,.85)
            end
        end
        g.pop()
        return true
    end
    return service
end
return Ambush
