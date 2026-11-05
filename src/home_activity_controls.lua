local Residents=require("src.home_residents")
local Calendar=require("src.business_calendar")
local Objects=require("src.home_objects")
local Chores=require("src.home_chores")
local Cooking=require("src.home_cooking")
local Sleep=require("src.home_sleep")
local Dining=require("src.home_dining")
local BikeCargo=require("src.home_bike_cargo")
local HomeInteractions=require("src.home_interactions")
local Controls={target="floor",page=1,mode="routines",appliance=nil,appliancePage=1,alarmHour=nil,alarmMinute=nil}
local font,small,hudRect,alarmLabelFont
local applianceSmall
local function applianceNow()
    return love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end
function Controls.localPlayer(R)
    local player=R.World.player
    if R.multiplayer:isClient() then player.homeResidentId=R.multiplayer.residentId end
    return player
end
function Controls.prepareAlarmSelection(state,player,force)
    if not force and Controls.alarmHour~=nil and Controls.alarmMinute~=nil then return end
    local resident=Residents.get(state,player)
    local target=resident and resident.alarmAt or Calendar.absoluteHours(state)+8
    local minutes=math.floor((target%24)*60+1e-7)%1440
    Controls.alarmHour=math.floor(minutes/60)
    Controls.alarmMinute=minutes%60
end
local function adjustAlarmMinutes(delta)
    local time=(Controls.alarmHour*60+Controls.alarmMinute+delta)%1440
    Controls.alarmHour=math.floor(time/60)
    Controls.alarmMinute=time%60
end
function Controls.command(R,player,command)
    local now=Calendar.absoluteHours(R.state)
    Residents.advance(R.state,require("src.weekend_runtime").players(R),now,now)
    local okay,code,message=Residents.command(R.state,player,command)
    if okay then
        R.state.message=message;R.saveCurrent()
        if R.multiplayer:isHost() then R.multiplayer:markShopDirty() end
    end
    return okay,code,message,"homeActivity"
end
local function send(R,command)
    local okay,message
    if R.multiplayer:isClient() then okay,message=R.multiplayer:requestInteraction("homeActivity",command)
    else local code;okay,code,message=Controls.command(R,Controls.localPlayer(R),command) end
    R.state.message=message or (okay and "Waiting for the host..." or "Home activity unavailable.")
end
local function rows(state,player)
    local result={}
    local resident=Residents.get(state,player)
    if Controls.mode=="readiness" then return result end
    if not resident then return result end
    if resident and resident.activity then
        local activity=resident.activity
        if Controls.mode=="routines" and Cooking.RECIPES[activity.kind] then
            if Residents.householdAllowed(state,player) then result=Cooking.rows(state,player) end
            result[#result+1]={label="STOP — discard this prepared batch",command="cancel"}
            return result
        end
        if Controls.mode=="routines" and activity.kind=="watch" then
            result={{label="STOP CURRENT ACTIVITY",command="cancel"}}
            local targetId=Controls.target:match("^furniture(%d+)$")
            local targetItem=targetId and require("src.home_furniture").find(state,tonumber(targetId))
            if targetItem and targetItem.id==activity.tvId and targetItem.kind=="old_tv" and targetItem.powered then
                result[#result+1]={label="SWITCH TV OFF",command="object:off:"..targetItem.id..":"..targetItem.revision}
            end
            return result
        end
        local sleeping=Sleep.ACTIONS[activity.kind]~=nil
        return {{label=sleeping and "WAKE UP — return time to normal speed" or "STOP CURRENT ACTIVITY",command="cancel"}}
    end
    if not Residents.householdAllowed(state,player) then return result end
    if Controls.mode=="dining" then
        return Dining.rows(state,player,Controls.target)
    end
    if Controls.mode=="sleep" then
        if Sleep.prepare(state,"sleepfloor") then
            for _,kind in ipairs({"workbed","workcouch","workmat","workfloor","sleepbed","sleepcouch","sleepmat"}) do
                local target=kind=="workfloor" and "floor" or Controls.target
                local startable=Residents.prepareActivity(state,player,kind,target)
                if startable then result[#result+1]={label=Sleep.ACTIONS[kind].label,command=kind..":"..target} end
            end
            local floorStartable=Residents.prepareActivity(state,player,"sleepfloor","floor")
            if floorStartable then result[#result+1]={label=Sleep.ACTIONS.sleepfloor.label,command="sleepfloor:floor"} end
        end
        return result
    end
    for _,kind in ipairs({"drink","wash","bathe","toilet","loadwash","unload","change","rest","nap","couchrest","matrest","sit","watch","checktime","eat","sandwich","cereal","pizza","takeout","bottle","dishes","wipe","scrub","sweep","trash","cook","prepare","hotmeal","goodmeal","plainmeal","goodsandwich","roughsandwich"}) do
        local action=Residents.ACTIONS[kind]
        local startable=Residents.prepareActivity(state,player,kind,Controls.target)
        if startable then
            result[#result+1]={label=action.label.."  /  "..action.minutes.." game min"..(action.item and "  /  "..(state.home.inventory[action.item] or 0).." left" or ""),
                command=kind..":"..Controls.target}
        end
    end
    local objectRows=Objects.rows(state,player,Controls.target)
    if Objects.held(state,player) then
        for i=#objectRows,1,-1 do table.insert(result,1,objectRows[i]) end
    else for _,row in ipairs(objectRows) do result[#result+1]=row end end
    local cookingRows=Cooking.rows(state,player);for i=#cookingRows,1,-1 do table.insert(result,1,cookingRows[i]) end
    return result
end
local function visibleRows(state,player)
    local all=rows(state,player);local pages=math.max(1,math.ceil(#all/3))
    Controls.page=math.max(1,math.min(Controls.page,pages))
    local result={};for i=1,3 do result[i]=all[(Controls.page-1)*3+i] end
    return result,pages
end
local function applianceTarget(R)
    local id=Controls.target:match("^furniture(%d+)$")
    return id and require("src.home_furniture").find(R.state,tonumber(id))
end
local function applianceRows(R)
    local player=Controls.localPlayer(R)
    local resident=Residents.get(R.state,player)
    if Controls.appliance=="bike" then return BikeCargo.rows(R.state,player) end
    if Controls.appliance=="laundry" then
        if resident and resident.activity then return {{label="STOP CURRENT ACTIVITY",command="cancel"}} end
        local result={}
        for _,kind in ipairs({"loadwash","unload"}) do
            local ready=Residents.prepareActivity(R.state,player,kind,"laundry")
            if ready then
                local action=Residents.ACTIONS[kind]
                result[#result+1]={label=action.label:upper().." / "..action.minutes.." GAME MINUTES",
                    command=kind..":laundry"}
            end
        end
        return result
    end
    local item=applianceTarget(R)
    if not item then return {} end
    if Controls.appliance=="fridge" then
        return Objects.rows(R.state,player,Controls.target)
    end
    if resident and resident.activity then
        if Cooking.RECIPES[resident.activity.kind] then
            local result=Cooking.rows(R.state,player)
            if #result>0 then result[1].label="TEND BATCH NOW — improve the meal quality" end
            result[#result+1]={label="STOP — discard this batch",command="cancel"}
            return result
        end
        return {{label="STOP CURRENT ACTIVITY",command="cancel"}}
    end
    local ready,_,message=Residents.prepareActivity(R.state,player,"cook",Controls.target)
    if ready then
        Controls.applianceHint=nil
        return {{label="START COOKING — vegetables and toast / 20 game min",command="cook:"..Controls.target}}
    end
    Controls.applianceHint=message or "This stove is not ready to use."
    return {}
end
local function visibleApplianceRows(R)
    local all=applianceRows(R);local perPage=Controls.appliance=="bike" and 3 or 5
    local pages=math.max(1,math.ceil(#all/perPage))
    Controls.appliancePage=math.max(1,math.min(Controls.appliancePage,pages))
    local visible={}
    for i=1,perPage do visible[i]=all[(Controls.appliancePage-1)*perPage+i] end
    return visible,pages,all
end
local function closeAppliance(R)
    Controls.appliance=nil
    R.state.screen="world"
end
function Controls.visibleRows(R)
    return visibleRows(R.state,Controls.localPlayer(R))
end
function Controls.keypressed(key,R)
    if R.state.screen=="home_activity" then
        if Controls.appliance then
            if key=="escape" or key=="h" then closeAppliance(R);return true end
            if key=="left" or key=="right" then
                local _,pages=visibleApplianceRows(R)
                Controls.appliancePage=math.max(1,math.min(pages,Controls.appliancePage+(key=="right" and 1 or -1)))
                return true
            end
            if key=="backspace" then send(R,"cancel");return true end
            local visible=visibleApplianceRows(R)
            local row=visible[tonumber(key) or (key=="return" and 1 or 0)]
            if row then send(R,row.command) end
            return true
        end
        if key=="escape" or key=="h" then R.state.screen="world";return true end
        if key=="backspace" then send(R,"cancel");return true end
        if key=="t" then
            Controls.mode=Controls.mode=="sleep" and "routines" or "sleep";Controls.page=1
            if Controls.mode=="sleep" then Controls.prepareAlarmSelection(R.state,Controls.localPlayer(R),true) end
            return true
        end
        if key=="r" then
            Controls.mode=Controls.mode=="readiness" and "sleep" or "readiness";Controls.page=1
            if Controls.mode=="sleep" then Controls.prepareAlarmSelection(R.state,Controls.localPlayer(R),true) end
            return true
        end
        if key=="d" then Controls.mode=Controls.mode=="dining" and "routines" or "dining";Controls.page=1;return true end
        local visible,pages=visibleRows(R.state,Controls.localPlayer(R))
        if key=="left" then Controls.page=math.max(1,Controls.page-1);return true end
        if key=="right" then Controls.page=math.min(pages,Controls.page+1);return true end
        local row=visible[tonumber(key) or (key=="return" and 1 or 0)]
        if row then send(R,row.command) end
        return true
    end
    if R.state.screen~="world" or R.World.player.sceneId~="home" then return false end
    local selected=R.World.getInteraction()
    if key=="h" or key=="e" and selected and selected.kind=="homeActivity" then
        Controls.target=key=="e" and selected.target.fixtureId or "floor"
        local id=Controls.target:match("^furniture(%d+)$");local item=id and require("src.home_surfaces").find(R.state,tonumber(id))
        if key=="e" and item then
            local command=HomeInteractions.directCommand(R.state,Controls.localPlayer(R),item)
            if command then Controls.appliance=nil;send(R,command);return true end
        end
        Controls.appliance=HomeInteractions.appliance(item and item.kind,not item and Controls.target or nil)
        Controls.appliancePage=1;Controls.applianceHint=nil
        Controls.applianceOpenedAt=applianceNow()
        Controls.mode=item and item.kind=="clock" and "sleep" or "routines"
        if Controls.mode=="sleep" then Controls.prepareAlarmSelection(R.state,Controls.localPlayer(R),true) end
        Controls.page=1
        R.state.screen="home_activity";return true
    end
    return false
end
function Controls.mousepressed(x,y,button,R)
    if button~=1 then return R.state.screen=="home_activity" end
    if R.state.screen=="world" and R.World.player.sceneId=="home" and hudRect
        and x>=hudRect.x and x<=hudRect.x+hudRect.width and y>=hudRect.y and y<=hudRect.y+hudRect.height then
        return Controls.keypressed("h",R)
    end
    if R.state.screen~="home_activity" then return false end
    if Controls.mode=="sleep" and y>=290 and y<=328 then
        local player=Controls.localPlayer(R)
        Controls.prepareAlarmSelection(R.state,player,false)
        if x>=140 and x<=195 then Controls.alarmHour=(Controls.alarmHour+23)%24
        elseif x>=237 and x<=282 then Controls.alarmHour=(Controls.alarmHour+1)%24
        elseif x>=315 and x<=357 then adjustAlarmMinutes(-15)
        elseif x>=359 and x<=401 then adjustAlarmMinutes(-1)
        elseif x>=453 and x<=495 then adjustAlarmMinutes(1)
        elseif x>=497 and x<=549 then adjustAlarmMinutes(15)
        elseif x>=580 and x<=690 then
            send(R,string.format("alarm:time:%02d:%02d",Controls.alarmHour,Controls.alarmMinute));return true
        elseif x>=700 and x<=820 then send(R,"alarm:off");return true end
        return true
    end
    if Controls.appliance then
        if x>=748 and x<=850 and y>=95 and y<=145 then closeAppliance(R);return true end
        local visible,pages=visibleApplianceRows(R)
        if y>=510 and y<=548 then
            if x>=485 and x<=620 then Controls.appliancePage=math.max(1,Controls.appliancePage-1)
            elseif x>=680 and x<=820 then Controls.appliancePage=math.min(pages,Controls.appliancePage+1) end
            return true
        end
        for i,row in ipairs(visible) do
            local top=Controls.appliance=="fridge" and 264 or Controls.appliance=="bike" and 224 or 382
            top=top+(i-1)*(Controls.appliance=="bike" and 56 or 48)
            if x>=480 and x<=820 and y>=top and y<=top+42 then send(R,row.command);return true end
        end
        return true
    end
    local current=Residents.get(R.state,Controls.localPlayer(R))
    local cooking=Controls.mode=="routines" and current and current.activity and Cooking.RECIPES[current.activity.kind]
    if not cooking and y>=590 and y<=634 then
        if x>=140 and x<=370 then return Controls.keypressed("t",R) end
        if x>=390 and x<=620 then return Controls.keypressed("r",R) end
        if x>=640 and x<=820 then return Controls.keypressed("d",R) end
    end
    if x>=748 and x<=850 and y>=95 and y<=145 then R.state.screen="world";return true end
    local resident=Residents.get(R.state,Controls.localPlayer(R))
    if resident and resident.activity and x>=690 and x<=820 and y>=207 and y<=251 then send(R,"cancel");return true end
    local visible,pages=visibleRows(R.state,Controls.localPlayer(R))
    local pageTop=Controls.mode=="sleep" and 490 or 470
    if y>=pageTop and y<=pageTop+44 then
        if x>=140 and x<=330 then Controls.page=math.max(1,Controls.page-1)
        elseif x>=630 and x<=820 then Controls.page=math.min(pages,Controls.page+1) end
        return true
    end
    for i,row in ipairs(visible) do
        local top=(Controls.mode=="sleep" and 332 or 300)+(i-1)*52
        if x>=140 and x<=820 and y>=top and y<=top+44 then send(R,row.command);return true end
    end
    return true
end
local function needs(p,x,y,width)
    if not p then return end
    local cell=width/4
    for i,need in ipairs(Residents.NEEDS) do
        local left=x+(i-1)*cell
        love.graphics.setColor(.9,.94,.9,1)
        love.graphics.print(need:sub(1,1):upper()..need:sub(2).." "..math.floor(p[need]),left,y)
        love.graphics.setColor(.08,.15,.17,1);love.graphics.rectangle("fill",left,y+20,cell-12,8,3)
        love.graphics.setColor(p[need]<20 and .95 or .3,p[need]<20 and .5 or .8,.5,1)
        love.graphics.rectangle("fill",left,y+20,(cell-12)*p[need]/100,8,3)
    end
end
function Controls.hideHud() hudRect=nil end
function Controls.drawHud(state,player,left,right)
    small=small or love.graphics.newFont(15)
    hudRect={x=left+18,y=120,width=math.min(720,right-left-36),height=63}
    love.graphics.push("all");love.graphics.setFont(small)
    love.graphics.setColor(.025,.05,.065,.94);love.graphics.rectangle("fill",hudRect.x,hudRect.y,hudRect.width,hudRect.height,6)
    local resident=Residents.get(state,player)
    needs(resident,hudRect.x+10,126,hudRect.width-110)
    if resident and resident.dirtyClothes then
        love.graphics.setColor(.98,.67,.37,1)
        love.graphics.print("STINKY CLOTHES / WASH & CHANGE",hudRect.x+10,159)
    end
    love.graphics.setColor(.96,.86,.45,1);love.graphics.printf("HOME [H]\nFurnish [M]",hudRect.x+hudRect.width-105,126,100,"center")
    love.graphics.pop()
end
local function drawApplianceRows(R)
    local visible,pages,all=visibleApplianceRows(R)
    local Food=require("src.home_food_catalog")
    for i,row in ipairs(visible) do
        local y=Controls.appliance=="fridge" and 264 or Controls.appliance=="bike" and 224 or 382
        y=y+(i-1)*(Controls.appliance=="bike" and 56 or 48)
        love.graphics.setColor(.12,.29,.32,1);love.graphics.rectangle("fill",480,y,340,42,5)
        local food=row.command:match("^object:[a-z]+:%d+:%d+:([a-z_]+)$")
        local definition=food and Food.ITEMS[food]
        if definition then require("src.home_food_art").draw(definition.sprite,502,y+21,27) end
        love.graphics.setFont(applianceSmall)
        love.graphics.setColor(.96,.96,.88,1)
        love.graphics.printf(row.label,522,y+5,288,"left")
    end
    if pages>1 then
        love.graphics.setColor(.13,.32,.35,1)
        love.graphics.rectangle("fill",480,510,140,38,5);love.graphics.rectangle("fill",680,510,140,38,5)
        love.graphics.setColor(.96,.96,.88,1)
        love.graphics.setFont(applianceSmall)
        love.graphics.printf("< PREVIOUS",480,521,140,"center")
        love.graphics.printf("NEXT >",680,521,140,"center")
        love.graphics.printf(Controls.appliancePage.." / "..pages,620,521,60,"center")
    end
    return visible,pages,all
end
local function drawAppliance(R)
    font=font or love.graphics.newFont(18);small=small or love.graphics.newFont(15)
    applianceSmall=applianceSmall or love.graphics.newFont(13)
    local Art=require("src.home_appliance_art")
    local item=applianceTarget(R)
    local player=Controls.localPlayer(R)
    local resident=Residents.get(R.state,player)
    local cooking=resident and resident.activity and Cooking.RECIPES[resident.activity.kind]
    local now=applianceNow()
    local open=math.max(0,math.min(1,(now-(Controls.applianceOpenedAt or now))/.52))
    local elapsed=cooking and math.max(0,(Calendar.absoluteHours(R.state)-resident.activity.startedAt)*Calendar.secondsPerDay(R.state)/24) or now

    love.graphics.push("all")
    love.graphics.setColor(.025,.045,.06,.98);love.graphics.rectangle("fill",110,82,740,558,8)
    love.graphics.setColor(.30,.52,.58,1);love.graphics.rectangle("line",110,82,740,558,8)
    love.graphics.setFont(font);love.graphics.setColor(.96,.92,.79,1)
    local title=Controls.appliance=="fridge" and (item and item.kind=="mini_fridge"
        and "MINI FRIDGE / HOUSEHOLD FOOD" or "REFRIGERATOR / HOUSEHOLD FOOD") or "STOVE / COOKING"
    love.graphics.print(title,140,110)
    love.graphics.setColor(.17,.28,.33,1);love.graphics.rectangle("fill",748,95,102,50,5)
    love.graphics.setFont(small);love.graphics.setColor(.96,.96,.88,1)
    love.graphics.printf("BACK [Esc]",748,111,102,"center")
    love.graphics.setColor(.035,.065,.075,1);love.graphics.rectangle("fill",126,153,326,392,8)
    love.graphics.setColor(.24,.39,.43,1);love.graphics.rectangle("line",126,153,326,392,8)

    if not item then
        love.graphics.setFont(font);love.graphics.setColor(1,.74,.42,1)
        love.graphics.printf("This appliance is no longer available.",480,210,340,"center")
    elseif Controls.appliance=="fridge" then
        Art.drawFridge(128,158,.43,open,item.contents,item.kind)
        love.graphics.setFont(small);love.graphics.setColor(.96,.92,.79,1)
        love.graphics.printf(""..require("src.home_objects").count(item).." / "..require("src.home_objects").capacity(item).." portions stored",142,530,300,"center")
        love.graphics.setFont(font);love.graphics.setColor(.96,.92,.79,1)
        love.graphics.print("INSIDE / TAKE OR STORE",480,164)
        love.graphics.setFont(small)
        local connected=require("src.home_furniture").hookedUp(R.state,item)
        love.graphics.setColor(connected and .73 or 1,connected and .88 or .68,connected and .77 or .43,1)
        love.graphics.printf(connected and "Fridge contents are shown on the shelves." or "Connect this fridge to use food storage.",480,192,340,"left")
        local visible=drawApplianceRows(R)
        if not connected then
            love.graphics.setColor(1,.76,.46,1)
            love.graphics.printf(require("src.home_furniture").hookupHint(R.state,item),480,220,340,"left")
        elseif #visible==0 then
            love.graphics.setColor(.78,.86,.87,1)
            love.graphics.printf("No available food transfers. Use the grocery order on the laptop to restock.",480,232,340,"left")
        end
    else
        Art.drawStove(131,142,.80,not not cooking,elapsed)
        love.graphics.setFont(font);love.graphics.setColor(.96,.92,.79,1)
        love.graphics.print("VEGETABLES & TOAST",480,164)
        love.graphics.setFont(small)
        local bread=R.state.home.inventory.bread or 0
        local vegetables=R.state.home.inventory.vegetables or 0
        love.graphics.setColor(.80,.88,.88,1)
        love.graphics.print("Recipe / 2 portions / 20 game minutes",480,192)
        require("src.home_food_art").draw(11,503,229,30)
        love.graphics.setColor(.94,.91,.78,1);love.graphics.printf("Bread  x1    Household: "..bread,525,220,285,"left")
        require("src.home_food_art").draw(13,503,269,30)
        love.graphics.printf("Vegetables  x2    Household: "..vegetables,525,260,285,"left")
        if cooking then
            local a=resident.activity
            local progress=math.max(0,math.min(1,(Calendar.absoluteHours(R.state)-a.startedAt)/(a.endsAt-a.startedAt)))
            love.graphics.setColor(.13,.20,.23,1);love.graphics.rectangle("fill",480,306,340,16,4)
            love.graphics.setColor(.25,.66,.42,1);love.graphics.rectangle("fill",480,306,340*progress,16,4)
            love.graphics.setColor(.96,.90,.67,1)
            love.graphics.printf(a.cookTended and "TENDED / waiting for the timer" or "TEND IN THE GREEN BAND FOR BETTER FOOD",480,326,340,"center")
        else
            local description=Cooking.description(R.state,player,Controls.target) or Controls.applianceHint
            love.graphics.setColor(.78,.86,.87,1)
            love.graphics.printf(description or "Move close to the stove and collect bread and vegetables from the fridge first.",480,306,340,"left")
        end
        drawApplianceRows(R)
    end

    if R.state.message and R.state.message~="" then
        love.graphics.setFont(applianceSmall);love.graphics.setColor(.97,.79,.43,1)
        love.graphics.printf(R.state.message,480,559,340,"left")
    end
    love.graphics.setFont(applianceSmall);love.graphics.setColor(.73,.81,.82,1)
    love.graphics.printf("Tap an action or use [1]–[5]. Arrow keys change pages.",140,603,680,"center")
    love.graphics.pop()
end
local function drawLaundry(R)
    font=font or love.graphics.newFont(18);small=small or love.graphics.newFont(15)
    applianceSmall=applianceSmall or love.graphics.newFont(13)
    local chores=require("src.home_chores").ensure(R.state)
    local laundry=chores.laundry
    local player=Controls.localPlayer(R)
    local resident=Residents.get(R.state,player)
    local activity=resident and resident.activity
    local now=Calendar.absoluteHours(R.state)
    local progress=0
    local status
    if activity and (activity.kind=="loadwash" or activity.kind=="unload") then
        progress=math.max(0,math.min(1,(now-activity.startedAt)/math.max(.001,activity.endsAt-activity.startedAt)))
        status=activity.kind=="loadwash" and "LOADING THE WASHER" or "UNLOADING CLEAN CLOTHES"
    elseif laundry.phase=="washing" then
        progress=math.max(0,math.min(1,(now-laundry.startedAt)/math.max(.001,laundry.dueAt-laundry.startedAt)))
        status="WASH CYCLE / "..require("src.home_chores").minutesLeft(R.state).." GAME MIN LEFT"
    elseif laundry.phase=="ready" then
        progress=1;status="CYCLE COMPLETE / READY TO UNLOAD"
    elseif laundry.dirty>0 then status="READY / LOAD A DIRTY BUNDLE"
    else status="IDLE / NO DIRTY LAUNDRY"
    end

    love.graphics.push("all")
    love.graphics.setColor(.025,.045,.06,.98);love.graphics.rectangle("fill",110,82,740,558,8)
    love.graphics.setColor(.30,.52,.58,1);love.graphics.rectangle("line",110,82,740,558,8)
    love.graphics.setFont(font);love.graphics.setColor(.96,.92,.79,1)
    love.graphics.print("LAUNDRY / WASHER",140,110)
    love.graphics.setColor(.17,.28,.33,1);love.graphics.rectangle("fill",748,95,102,50,5)
    love.graphics.setFont(small);love.graphics.setColor(.96,.96,.88,1)
    love.graphics.printf("BACK [Esc]",748,111,102,"center")

    -- Compact washer illustration for the dedicated laundry activity screen.
    love.graphics.setColor(.035,.065,.075,1);love.graphics.rectangle("fill",126,153,326,392,8)
    love.graphics.setColor(.24,.39,.43,1);love.graphics.rectangle("line",126,153,326,392,8)
    love.graphics.setColor(.61,.66,.63,1);love.graphics.rectangle("fill",170,188,238,316,12)
    love.graphics.setColor(.77,.79,.72,1);love.graphics.rectangle("fill",181,201,216,58,6)
    love.graphics.setColor(.12,.22,.24,1);love.graphics.rectangle("fill",194,215,103,31,4)
    love.graphics.setFont(applianceSmall);love.graphics.setColor(.51,.94,.71,1)
    love.graphics.printf(laundry.phase=="washing" and "WASH" or laundry.phase=="ready" and "DONE" or "READY",197,223,97,"center")
    love.graphics.setColor(.28,.36,.36,1);love.graphics.circle("fill",355,231,17)
    love.graphics.setColor(.91,.88,.77,1);love.graphics.circle("line",355,231,17)
    love.graphics.setColor(.20,.34,.36,1);love.graphics.circle("fill",289,375,93)
    love.graphics.setColor(.55,.73,.73,1);love.graphics.circle("line",289,375,93)
    love.graphics.setColor(.10,.18,.21,1);love.graphics.circle("fill",289,375,72)
    love.graphics.setColor(.23,.42,.47,1);love.graphics.circle("line",289,375,69)
    local spin=applianceNow()*(laundry.phase=="washing" and 2.4 or .35)
    for i=1,3 do
        local angle=spin+(i-1)*math.pi*2/3
        love.graphics.push()
        love.graphics.translate(289+math.cos(angle)*34,375+math.sin(angle)*30)
        love.graphics.rotate(angle)
        love.graphics.setColor(i==1 and .82 or .56,i==2 and .72 or .49,.39,1)
        love.graphics.rectangle("fill",-17,-9,34,18,5)
        love.graphics.pop()
    end
    love.graphics.setColor(.22,.32,.34,1);love.graphics.rectangle("fill",193,478,55,12,4)
    love.graphics.rectangle("fill",330,478,55,12,4)

    love.graphics.setFont(font);love.graphics.setColor(.96,.92,.79,1)
    love.graphics.print("HOUSEHOLD LAUNDRY",480,164)
    love.graphics.setFont(small);love.graphics.setColor(.76,.86,.86,1)
    love.graphics.printf("The washer runs for 45 game minutes after loading. You can leave while the cycle runs.",480,192,340,"left")
    love.graphics.setColor(.10,.20,.23,1);love.graphics.rectangle("fill",480,240,160,58,5)
    love.graphics.rectangle("fill",650,240,170,58,5)
    love.graphics.setColor(.96,.96,.88,1);love.graphics.setFont(applianceSmall)
    love.graphics.printf("DIRTY BUNDLES",488,250,144,"center")
    love.graphics.printf("CLEAN BUNDLES",658,250,154,"center")
    love.graphics.setFont(font);love.graphics.setColor(.98,.80,.42,1)
    love.graphics.printf(tostring(laundry.dirty),480,270,160,"center")
    love.graphics.printf(tostring(laundry.clean),650,270,170,"center")
    love.graphics.setFont(applianceSmall);love.graphics.setColor(.96,.92,.79,1)
    love.graphics.printf(status,480,318,340,"center")
    love.graphics.setColor(.12,.20,.23,1);love.graphics.rectangle("fill",480,344,340,16,4)
    love.graphics.setColor(.24,.68,.44,1);love.graphics.rectangle("fill",480,344,340*progress,16,4)
    local visible=drawApplianceRows(R)
    if #visible==0 then
        love.graphics.setColor(.77,.85,.85,1)
        love.graphics.printf(laundry.phase=="washing" and "The machine is running." or "Dirty bundles collect during the shop week.",480,391,340,"center")
    end
    if R.state.message and R.state.message~="" then
        love.graphics.setFont(applianceSmall);love.graphics.setColor(.97,.79,.43,1)
        love.graphics.printf(R.state.message,480,559,340,"left")
    end
    love.graphics.setFont(applianceSmall);love.graphics.setColor(.73,.81,.82,1)
    love.graphics.printf("Tap the washer action or use [1].",140,603,680,"center")
    love.graphics.pop()
end
local function drawBikeCargo(R)
    font=font or love.graphics.newFont(18);small=small or love.graphics.newFont(15)
    applianceSmall=applianceSmall or love.graphics.newFont(13)
    local player=Controls.localPlayer(R);local resident=Residents.get(R.state,player)
    local inventory=resident and BikeCargo.ensure(resident) or BikeCargo.new()
    local used=BikeCargo.used(inventory)
    love.graphics.push("all")
    love.graphics.setColor(.025,.045,.06,.98);love.graphics.rectangle("fill",110,82,740,558,8)
    love.graphics.setColor(.30,.52,.58,1);love.graphics.rectangle("line",110,82,740,558,8)
    love.graphics.setFont(font);love.graphics.setColor(.96,.92,.79,1)
    love.graphics.print("BIKE CARGO / APARTMENT PARKING",140,110)
    love.graphics.setColor(.17,.28,.33,1);love.graphics.rectangle("fill",748,95,102,50,5)
    love.graphics.setFont(small);love.graphics.setColor(.96,.96,.88,1);love.graphics.printf("BACK [Esc]",748,111,102,"center")
    love.graphics.setColor(.035,.065,.075,1);love.graphics.rectangle("fill",126,153,326,392,8)
    love.graphics.setColor(.24,.39,.43,1);love.graphics.rectangle("line",126,153,326,392,8)
    love.graphics.setColor(.78,.86,.87,1);love.graphics.setFont(small)
    love.graphics.printf("Your bike is parked in an apartment space outside. Groceries stay on the bike until you unload them here.",148,178,282,"center")
    love.graphics.setColor(.12,.20,.23,1);love.graphics.circle("fill",215,325,50);love.graphics.circle("fill",362,325,50)
    love.graphics.setColor(.68,.76,.71,1);love.graphics.setLineWidth(7)
    love.graphics.circle("line",215,325,43);love.graphics.circle("line",362,325,43)
    love.graphics.setLineWidth(5);love.graphics.line(215,325,263,270,310,325,215,325,280,325,362,325,310,325)
    love.graphics.line(263,270,310,265,325,276);love.graphics.line(272,260,292,260)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(.96,.84,.52,1);love.graphics.rectangle("fill",278,284,54,37,4)
    love.graphics.setColor(.18,.29,.27,1);love.graphics.rectangle("line",278,284,54,37,4)
    love.graphics.setColor(.96,.92,.79,1);love.graphics.setFont(font)
    love.graphics.printf(("CARGO  %d / %d BAGS"):format(used,BikeCargo.CAPACITY),148,408,282,"center")
    love.graphics.setFont(small);love.graphics.setColor(.76,.86,.86,1)
    love.graphics.printf("Choose a bag to unload it into shared home storage. You can also unload everything at once.",148,443,282,"center")
    love.graphics.setColor(.96,.92,.79,1);love.graphics.setFont(font);love.graphics.print("BIKE INVENTORY",480,164)
    local visible,pages,all=drawApplianceRows(R)
    if #all==0 then
        love.graphics.setFont(small);love.graphics.setColor(.78,.86,.87,1)
        love.graphics.printf("No groceries on the bike. Pick up food at a town counter to load its cargo.",480,230,340,"center")
    end
    if R.state.message and R.state.message~="" then
        love.graphics.setFont(applianceSmall);love.graphics.setColor(.97,.79,.43,1)
        love.graphics.printf(R.state.message,480,559,340,"left")
    end
    love.graphics.setFont(applianceSmall);love.graphics.setColor(.73,.81,.82,1)
    love.graphics.printf("Tap a bag or use [1]–[5]. Left/right changes pages. [Esc] closes.",140,603,680,"center")
    love.graphics.pop()
end
function Controls.draw(R)
    if Controls.appliance=="laundry" then drawLaundry(R);return end
    if Controls.appliance=="bike" then drawBikeCargo(R);return end
    if Controls.appliance then drawAppliance(R);return end
    font=font or love.graphics.newFont(18);small=small or love.graphics.newFont(15)
    local p=Residents.get(R.state,Controls.localPlayer(R))
    love.graphics.push("all");love.graphics.setColor(.025,.045,.06,.97);love.graphics.rectangle("fill",110,82,740,558,8)
    love.graphics.setFont(font);love.graphics.setColor(.96,.92,.79,1)
    local id=Controls.target:match("^furniture(%d+)$");local item=id and require("src.home_furniture").find(R.state,tonumber(id))
    local title=item and require("src.home_furniture_catalog").ITEMS[item.kind].name or Controls.target
    love.graphics.print(Controls.mode=="sleep" and "SLEEP & PERSONAL ALARMS" or Controls.mode=="readiness" and "HOUSEHOLD READINESS" or Controls.mode=="dining" and "SERVED MEALS / "..title:upper() or "HOME ROUTINES / "..title:upper(),140,110)
    love.graphics.setFont(small);love.graphics.printf("BACK [Esc]",750,112,88,"center")
    love.graphics.print(Calendar.dateTimeTextAtHours(Calendar.absoluteHours(R.state)),140,139)
    needs(p,140,165,680)
    local description="Choose an activity. Time continues while this menu is open."
    if Controls.target=="laundry" and R.state.home.chores.laundry.phase=="washing" then description="The washer runs on its own. You can leave and do other things." end
    if p and p.activity then
        local a=p.activity
        local endsAt=Residents.activityEndAt(R.state,p,a)
        description=Residents.ACTIONS[a.kind].label.." — "..math.ceil(math.max(0,endsAt-Calendar.absoluteHours(R.state))*60).." game min remaining."
    end
    if p and p.dirtyClothes and Controls.mode=="routines" and not p.activity then
        description="Your clothes are dirty. Wash a bundle and put on fresh clothes."
    end
    if Controls.mode=="sleep" then
        local all,asleep,total=Sleep.status(R.state,require("src.weekend_runtime").players(R),true)
        description=asleep.." / "..total.." connected residents sleeping. "..(all and "Shared time: 32x." or "Time stays normal until everyone chooses sleep.")
        if Calendar.absoluteHours(R.state)>=R.state.home.weekend.opensAtHours-2 then description="Monday morning: get ready for work. Short naps are available through Routines." end
    elseif Controls.mode=="readiness" then description="Aim for at least 35 in each need before work. Eat, drink, wash or rest if a need is low."
    elseif Controls.mode=="dining" and not (p and p.activity) then description="Serve a real portion onto a clear surface slot, then eat here or from an aligned nearby seat." end
    love.graphics.setColor(.88,.93,.92,1);love.graphics.printf(description,140,220,p and p.activity and 530 or 680,"left")
    if p and p.activity then
        love.graphics.setColor(.40,.19,.14,1);love.graphics.rectangle("fill",690,207,130,44,5)
        love.graphics.setColor(.96,.96,.88,1);love.graphics.printf("STOP",690,221,130,"center")
    end
    if Controls.mode=="sleep" then Controls.prepareAlarmSelection(R.state,Controls.localPlayer(R),false) end
    local paneDescription=Controls.mode=="sleep" and (p and p.alarmAt and "Alarm set for "..Calendar.dateTimeTextAtHours(p.alarmAt)..". Choose a custom time below."
        or "No alarm set. Choose any time below; the alarm rings once.")
        or Controls.mode=="readiness" and "Monday wake: 07:00. Shop opens: 09:00. Use the apartment entrance to return."
        or Controls.mode=="dining" and "Use a table/counter or the kitchen sink's dry counter. For seated meals, place a chair/couch close to and facing the surface. Take food out of storage first."
    love.graphics.printf(paneDescription or Cooking.description(R.state,Controls.localPlayer(R),Controls.target) or Objects.description(R.state,Controls.localPlayer(R),Controls.target) or Chores.description(R.state,Controls.target)
        or "Order groceries or takeout on the laptop; collect them by the entrance. Floor rest is always available.",140,253,680,"left")
    if Controls.mode=="sleep" then
        alarmLabelFont=alarmLabelFont or love.graphics.newFont(11)
        love.graphics.setFont(alarmLabelFont)
        love.graphics.setColor(.67,.79,.78,1)
        love.graphics.printf("HOUR",140,273,142,"center")
        love.graphics.printf("MINUTE",315,273,234,"center")
        love.graphics.printf("ALARM",580,273,240,"center")
        local function alarmButton(x,width,text,filled)
            love.graphics.setColor(filled and {.13,.32,.35,1} or {.07,.12,.14,1})
            love.graphics.rectangle("fill",x,290,width,38,5)
            love.graphics.setColor(.29,.52,.56,1)
            love.graphics.rectangle("line",x+.5,290.5,width-1,37,5)
            love.graphics.setFont(small)
            love.graphics.setColor(.96,.96,.88,1)
            love.graphics.printf(text,x,300,width,"center")
        end
        alarmButton(140,45,"−H",true)
        alarmButton(187,48,string.format("%02d",Controls.alarmHour),false)
        alarmButton(237,45,"+H",true)
        alarmButton(315,42,"−15",true)
        alarmButton(359,42,"−1",true)
        alarmButton(403,48,string.format("%02d",Controls.alarmMinute),false)
        alarmButton(453,42,"+1",true)
        alarmButton(497,52,"+15",true)
        alarmButton(580,110,"SET ALARM",true)
        alarmButton(700,120,"OFF",false)
    end
    local visible,pages=visibleRows(R.state,Controls.localPlayer(R))
    for i,row in ipairs(visible) do
        local y=(Controls.mode=="sleep" and 332 or 300)+(i-1)*52
        love.graphics.setColor(.13,.32,.35,1);love.graphics.rectangle("fill",140,y,680,44,5)
        love.graphics.setColor(.96,.96,.88,1);love.graphics.printf("["..i.."]  "..row.label,148,y+13,664,"center")
    end
    if Controls.mode=="readiness" then
        for i,row in ipairs(Sleep.readiness(R.state,require("src.weekend_runtime").players(R))) do
            local y=300+(i-1)*48
            love.graphics.setColor(row.ready and .5 or 1,row.ready and .9 or .7,.5,1)
            love.graphics.printf(row.name..(row.sleeping and " / sleeping" or row.ready and " / ready" or " / needs attention"),140,y,680,"left")
            love.graphics.setColor(.9,.93,.9,1)
            love.graphics.printf(string.format("Hunger %d   Thirst %d   Hygiene %d   Energy %d",row.hunger,row.thirst,row.hygiene,row.energy),140,y+20,680,"left")
        end
    end
    local cooking=Controls.mode=="routines" and p and p.activity and Cooking.RECIPES[p.activity.kind]
    if cooking then
        local a=p.activity;local progress=math.max(0,math.min(1,(Calendar.absoluteHours(R.state)-a.startedAt)/(a.endsAt-a.startedAt)))
        love.graphics.setColor(.14,.20,.23,1);love.graphics.rectangle("fill",140,538,680,16,4)
        love.graphics.setColor(.24,.64,.39,1);love.graphics.rectangle("fill",140+680*.4,538,680*.3,16)
        love.graphics.setColor(1,.91,.58,1);love.graphics.rectangle("fill",140+676*progress,535,4,22)
        love.graphics.printf(a.cookTended and ({"Batch tended — modest portions","Batch tended — good portions","Batch tended — excellent portions"})[a.cookQuality] or "Tend once while the marker is in green. [1] / tap the first row",140,568,680,"center")
    end
    if pages>1 then
        love.graphics.setColor(.13,.32,.35,1)
        local pageY=Controls.mode=="sleep" and 490 or 470
        love.graphics.rectangle("fill",140,pageY,190,44,5);love.graphics.rectangle("fill",630,pageY,190,44,5)
        love.graphics.setColor(.96,.96,.88,1)
        love.graphics.printf("< PREVIOUS",140,pageY+14,190,"center");love.graphics.printf("NEXT >",630,pageY+14,190,"center")
        love.graphics.printf(Controls.page.." / "..pages,330,pageY+14,300,"center")
    end
    love.graphics.setColor(.96,.79,.4,1);love.graphics.printf(R.state.message or "",140,cooking and 596 or 540,680,"left")
    if not cooking then
        for _,b in ipairs({{140,Controls.mode=="sleep" and "ROUTINES [T]" or "SLEEP & ALARMS [T]"},{390,"READINESS [R]"},{640,Controls.mode=="dining" and "ROUTINES [D]" or "MEALS [D]",180}}) do
            love.graphics.setColor(.13,.32,.35,1);love.graphics.rectangle("fill",b[1],590,b[3] or 230,44,5)
            love.graphics.setColor(.96,.96,.88,1);love.graphics.printf(b[2],b[1],602,b[3] or 230,"center")
        end
    end
    love.graphics.pop()
end
return Controls
