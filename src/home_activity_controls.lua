local Residents=require("src.home_residents")
local Calendar=require("src.business_calendar")
local Objects=require("src.home_objects")
local Chores=require("src.home_chores")
local Cooking=require("src.home_cooking")
local Sleep=require("src.home_sleep")
local Dining=require("src.home_dining")
local Controls={target="floor",page=1,mode="routines"}
local font,small,hudRect
function Controls.localPlayer(R)
    local player=R.World.player
    if R.multiplayer:isClient() then player.homeResidentId=R.multiplayer.residentId end
    return player
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
        for _,row in ipairs({{"ALARM: NEXT 07:00","alarm:7"},{"ALARM: NEXT 09:00","alarm:9"},{"ALARM: MONDAY 07:00","alarm:work"},{"TURN MY ALARM OFF","alarm:off"}}) do
            if row[2]~="alarm:work" or Calendar.absoluteHours(state)<state.home.weekend.opensAtHours-2 then result[#result+1]={label=row[1],command=row[2]} end
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
function Controls.visibleRows(R)
    return visibleRows(R.state,Controls.localPlayer(R))
end
function Controls.keypressed(key,R)
    if R.state.screen=="home_activity" then
        if key=="escape" or key=="h" then R.state.screen="world";return true end
        if key=="backspace" then send(R,"cancel");return true end
        if key=="t" then Controls.mode=Controls.mode=="sleep" and "routines" or "sleep";Controls.page=1;return true end
        if key=="r" then Controls.mode=Controls.mode=="readiness" and "sleep" or "readiness";Controls.page=1;return true end
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
        Controls.mode=item and item.kind=="clock" and "sleep" or "routines"
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
    if y>=470 and y<=514 then
        if x>=140 and x<=330 then Controls.page=math.max(1,Controls.page-1)
        elseif x>=630 and x<=820 then Controls.page=math.min(pages,Controls.page+1) end
        return true
    end
    for i,row in ipairs(visible) do
        local top=300+(i-1)*52
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
function Controls.drawHud(state,player,left,right)
    small=small or love.graphics.newFont(15)
    hudRect={x=left+18,y=120,width=math.min(720,right-left-36),height=46}
    love.graphics.push("all");love.graphics.setFont(small)
    love.graphics.setColor(.025,.05,.065,.94);love.graphics.rectangle("fill",hudRect.x,hudRect.y,hudRect.width,hudRect.height,6)
    needs(Residents.get(state,player),hudRect.x+10,126,hudRect.width-110)
    love.graphics.setColor(.96,.86,.45,1);love.graphics.printf("HOME [H]\nFurnish [M]",hudRect.x+hudRect.width-105,126,100,"center")
    love.graphics.pop()
end
function Controls.draw(R)
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
    local paneDescription=Controls.mode=="sleep" and (p and p.alarmAt and "Your alarm: "..Calendar.dateTimeTextAtHours(p.alarmAt) or "No personal alarm. Shared sleep stops at Monday 07:00.")
        or Controls.mode=="readiness" and "Monday wake: 07:00. Shop opens: 09:00. Use the apartment entrance to return."
        or Controls.mode=="dining" and "Use a table/counter or the kitchen sink's dry counter. For seated meals, place a chair/couch close to and facing the surface. Take food out of storage first."
    love.graphics.printf(paneDescription or Cooking.description(R.state,Controls.localPlayer(R),Controls.target) or Objects.description(R.state,Controls.localPlayer(R),Controls.target) or Chores.description(R.state,Controls.target)
        or "Order groceries or takeout on the laptop; collect them by the entrance. Floor rest is always available.",140,253,680,"left")
    local visible,pages=visibleRows(R.state,Controls.localPlayer(R))
    for i,row in ipairs(visible) do
        local y=300+(i-1)*52
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
        love.graphics.rectangle("fill",140,470,190,44,5);love.graphics.rectangle("fill",630,470,190,44,5)
        love.graphics.setColor(.96,.96,.88,1)
        love.graphics.printf("< PREVIOUS",140,484,190,"center");love.graphics.printf("NEXT >",630,484,190,"center")
        love.graphics.printf(Controls.page.." / "..pages,330,484,300,"center")
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
