local Rooms=require("src.shop_rooms")
local Controls={page=1,selected=1}
function Controls.isPortableUtilities() return Controls.mode=="utilities" end
local fonts
local function setFont(size)
    fonts=fonts or {}
    fonts[size]=fonts[size] or love.graphics.newFont(size)
    love.graphics.setFont(fonts[size])
end
local function fitted(text,width)
    text=tostring(text):gsub("[\r\n\t]"," ")
    local font=love.graphics.getFont()
    if font:getWidth(text)<=width then return text end
    local utf8=require("utf8")
    while #text>0 and font:getWidth(text.."...")>width do
        text=text:sub(1,(utf8.offset(text,-1) or 1)-1)
    end
    return text.."..."
end
local function send(Runtime,kind,command)
    if Runtime.multiplayer:isClient() then
        local okay,message=Runtime.multiplayer:requestInteraction(kind,command)
        Runtime.state.message=message or (okay and "Waiting for the host..." or "This action is unavailable.")
        return okay
    end
    local okay,_,message=Runtime.World.performNetworkInteraction(Runtime.World.player,Runtime.state,kind,command)
    Runtime.state.message=message
    Runtime.World.selectedInteraction=nil
    if okay and (kind=="roomStock" or kind=="restoration" or kind=="roomGame"
        and (command=="basketball:pickup" or command=="basketball:drop")) then Runtime.saveCurrent() end
    return okay
end
local function rows(Runtime)
    local result={}
    if Controls.mode=="stock" then
        for _,entry in ipairs(Rooms.stockItems(Runtime.state,Rooms.scene(Runtime.World.player))) do
            local p=entry.item.pallet
            local name=p.productName or p.productId or p.id
            result[#result+1]={label=(entry.stored and "RETRIEVE  " or "STORE  ")..name,
                detail=entry.stored and ("Shelf "..p.storage.row.." / "..p.storage.column) or "Staged at the warehouse entrance",
                kind="roomStock",command=(entry.stored and "retrieve:" or "store:")..p.id,enabled=true}
        end
    elseif Controls.mode=="utilities" then
        local Condition=require("src.warehouse_condition")
        local c=Condition.of(Runtime.state)
        if not c or c.mode~="story" then return result end
        result[1]={label=c.powerConnected and "DONE  Power service connected" or "CALL POWER COMPANY",
            detail=("One-time connection fee: $%.2f. Charged to the shop and saved as a receipt."):format(Condition.POWER_FEE_CENTS/100),
            kind="restoration",command="call_power",enabled=not c.powerConnected}
        result[2]={label=c.waterConnected and "DONE  Water service connected" or "CALL WATER UTILITY",
            detail=("One-time connection fee: $%.2f. Charged to the shop and saved as a receipt."):format(Condition.WATER_FEE_CENTS/100),
            kind="restoration",command="call_water",enabled=not c.waterConnected}
    elseif Controls.mode=="restoration" then
        local Condition=require("src.warehouse_condition")
        local c=Condition.of(Runtime.state)
        if not c then return result end
        local function add(label,detail,command,done,blocked)
            result[#result+1]={label=(done and "DONE  " or "DO  ")..label,detail=detail,
                kind="restoration",command=command,enabled=not done and not blocked}
        end
        if c.mode=="quick" then
            add(c.lightsOn and "Switch warehouse lights off" or "Switch warehouse lights on",
                "The shop remains powered while the lights are off.",c.lightsOn and "lights_off" or "lights_on",false)
            return result
        end
        add("Reconnect power",("Stage %d/4. One-time fee $%.2f; then repair the breaker."):format(
            Condition.stage(Runtime.state),Condition.POWER_FEE_CENTS/100),
            "call_power",c.powerConnected)
        add("Reconnect water",("One-time fee $%.2f; then clean the damp floor."):format(Condition.WATER_FEE_CENTS/100),
            "call_water",c.waterConnected)
        add("Repair breaker","Stand by the west-wall breaker. Service must be connected.","repair_breaker",c.breakerRepaired)
        for _,region in ipairs({"west","center","east"}) do
            local prior=region=="center" and "west" or region=="east" and "center" or nil
            local blocked=prior and not c.cleaned[prior]
            add("Clean "..region.." floor",blocked and ("Clean the "..prior.." area first.")
                or "Stand in this floor area to remove dust and stains.","clean_"..region,c.cleaned[region],blocked)
        end
        local floorsClean=c.cleaned.west and c.cleaned.center and c.cleaned.east
        add("Touch up paint",floorsClean and "Stand near the worn wall and shelving."
            or "Clean all three floor areas first.","repaint",c.repainted,not floorsClean)
        add(c.lightsOn and "Switch warehouse lights off" or "Switch warehouse lights on",
            "The shop remains powered while the lights are off.",c.lightsOn and "lights_off" or "lights_on",false)
        local ready,reason=Condition.readyForOpening(Runtime.state)
        add("Hold grand opening",ready and "Announce that The Picture Shop is open for clients."
            or reason,"grand_opening",c.grandOpened)
    else
        for _,id in ipairs({"front_left","front_right"}) do
            local bay=Runtime.state.warehouse.bays[id]
            local ready=Rooms.definition(Runtime.state,id)
            local stage=Rooms.constructionStage(Runtime.state,id)
            local product=bay.optionId and require("src.warehouse_upgrades").catalog(bay.optionId)
            local project=require("src.warehouse_layout").project(Runtime.state,id)
            result[#result+1]={label=(id=="front_left" and "ROOM A" or "ROOM B").."  /  "..(product and product.name or "Unpurchased"),
                detail=stage and ("Under construction - stage "..stage.." of 4; enter the work area")
                    or ready and "Enter this separate room"
                    or project and ("Construction: "..project.phase.." / stage "..(project.stage or 0).." of 4")
                    or "Order this room on the office computer",
                kind="shopRoom",command=id,enabled=ready~=nil}
        end
    end
    return result
end
local function activate(Runtime,index)
    local row=rows(Runtime)[index]
    if row and row.enabled then
        local okay=send(Runtime,row.kind,row.command)
        if okay and row.kind=="shopRoom" then Runtime.state.screen="world" end
    end
end
function Controls.open(Runtime,mode)
    Controls.mode,Controls.page,Controls.selected=mode,1,1
    Runtime.state.screen="shop_rooms"
    Runtime.state.message=mode=="stock" and "Stage delivered shop stock at the warehouse entrance. Store or retrieve it here."
        or mode=="utilities" and "Call the utility providers to reconnect the closed shop."
        or mode=="restoration" and (require("src.warehouse_condition").of(Runtime.state).mode=="story"
            and "Call utilities, repair the existing breaker, then clean and repaint the shop."
            or "Use the wall switch to turn the warehouse lights on or off.")
        or "Choose an available room. Other players stay in their own rooms."
end
function Controls.keypressed(key,Runtime)
    if require("src.home_furniture_controls").keypressed(key,Runtime) then return true end
    if require("src.home_delivery_controls").keypressed(key,Runtime) then return true end
    if require("src.home_activity_controls").keypressed(key,Runtime) then return true end
    if require("src.home_travel_controls").keypressed(key,Runtime) then return true end
    if Runtime.state.screen=="shop_rooms" then
        if key=="escape" then Runtime.state.screen="world"
        elseif key=="up" or key=="down" then
            local count=#rows(Runtime)
            Controls.selected=math.max(1,math.min(count,Controls.selected+(key=="down" and 1 or -1)))
            Controls.page=math.floor((Controls.selected-1)/6)+1
        elseif key=="return" or key=="e" then activate(Runtime,Controls.selected) end
        return true
    end
    if Runtime.state.screen~="world" then return false end
    local held=require("src.basketball").heldBy(Runtime.state,tonumber(Runtime.World.player.id) or 1)
    if held then
        if key=="q" then send(Runtime,"roomGame","basketball:drop");return true end
        if key=="space" then return require("src.basketball_controls").start(Runtime) end
    end
    local sceneId=Rooms.scene(Runtime.World.player)
    local storageRoom=sceneId~="warehouse" and Rooms.isComplete(Runtime.state,sceneId)
        and Rooms.definition(Runtime.state,sceneId)=="storage"
    local vehicleKey=({f=true,l=true,q=true,m=true})[key]
    local warehouseKey=({v=true,g=true,t=true,r=true,k=true,h=true})[key]
    if sceneId~="warehouse" and vehicleKey and not Rooms.machineRoomAllowed(Runtime.state,sceneId)
        or sceneId~="warehouse" and warehouseKey and not storageRoom then
        Runtime.state.message="Return to the warehouse to use its machines and vehicles."
        return true
    end
    if key~="e" then return false end
    local selected=Runtime.World.getInteraction()
    if not selected then return false end
    if selected.kind=="shopEntrance" then
        if Rooms.scene(Runtime.World.player)=="warehouse" then Controls.open(Runtime,"rooms")
        else send(Runtime,"shopRoom","warehouse") end
    elseif selected.kind=="roomStock" then Controls.open(Runtime,"stock")
    elseif selected.kind=="restoration" then Controls.open(Runtime,"restoration")
    elseif selected.kind=="roomRest" then send(Runtime,"roomRest",Runtime.World.player.resting and "stand" or "rest")
    elseif selected.kind=="roomGame" then
        local fixtureId=selected.target and selected.target.fixtureId
        if fixtureId=="air_hockey" then
            require("src.screens.air_hockey_screen").enter(Runtime,Rooms.scene(Runtime.World.player))
        elseif fixtureId=="critter_kombat" then
            require("src.screens.critter_kombat_screen").enter(Runtime,Rooms.scene(Runtime.World.player))
        elseif fixtureId=="basketball" then
            if selected.target.ball then send(Runtime,"roomGame","basketball:pickup")
            else
                local contest
                for _,entry in ipairs(require("src.basketball").renderRecords(Runtime.state)) do
                    if entry.bayId==Rooms.scene(Runtime.World.player) then contest=entry;break end
                end
                local id=tonumber(Runtime.World.player.id) or 1
                if contest and contest.contestPhase=="waiting" and contest.leftId~=id then
                    send(Runtime,"roomGame","basketball:join")
                elseif not contest or not contest.contestPhase or contest.contestPhase=="finished" then
                    send(Runtime,"roomGame","basketball:contest")
                else Runtime.state.message="Contest in progress. Pick up the ball and shoot." end
            end
        else
            Runtime.state.message="This game is unavailable."
        end
    else return false end
    return true
end
function Controls.keyreleased(key,Runtime)
    if Runtime.state.screen=="critter_kombat" then
        return require("src.screens.critter_kombat_screen").keyreleased(key)
    end
    if key~="space" or Runtime.state.screen~="world" then return false end
    local id=tonumber(Runtime.World.player.id) or 1
    local held=require("src.basketball").heldBy(Runtime.state,id)
    if held or require("src.basketball").isChargingFor(Runtime.state,id) then
        require("src.basketball_controls").release(Runtime)
        return true
    end
    return false
end
function Controls.mousepressed(x,y,button,Runtime)
    if require("src.home_furniture_controls").mousepressed(x,y,button,Runtime) then return true end
    if require("src.home_activity_controls").mousepressed(x,y,button,Runtime) then return true end
    if require("src.home_travel_controls").mousepressed(x,y,button,Runtime) then return true end
    if require("src.basketball_controls").mousepressed(x,y,button,Runtime) then return true end
    if Runtime.state.screen~="shop_rooms" then return false end
    if button~=1 then return true end
    if x>=760 and x<=845 and y>=140 and y<=180 then Runtime.state.screen="world";return true end
    if x>=115 and x<=845 then
        for index=1,6 do
            local top=244+(index-1)*45
            if y>=top and y<=top+40 then activate(Runtime,(Controls.page-1)*6+index);return true end
        end
        if y>=528 and y<=562 then
            local count=math.max(1,math.ceil(#rows(Runtime)/6))
            Controls.page=math.max(1,math.min(count,Controls.page+(x<480 and -1 or 1)))
            Controls.selected=(Controls.page-1)*6+1
        end
    end
    return true
end
function Controls.draw(Runtime)
    love.graphics.push("all")
    love.graphics.setColor(.015,.025,.035,.94);love.graphics.rectangle("fill",95,124,770,474,8)
    love.graphics.setColor(.34,.54,.59,1);love.graphics.rectangle("line",95,124,770,474,8)
    love.graphics.setColor(.95,.90,.72,1)
    setFont(20)
    love.graphics.print(fitted(Controls.mode=="stock" and Rooms.name(Runtime.state,Rooms.scene(Runtime.World.player)).." / SHOP STOCK"
        or Controls.mode=="utilities" and "PORTABLE PHONE / UTILITIES"
        or Controls.mode=="restoration" and (require("src.warehouse_condition").of(Runtime.state).mode=="quick"
            and "WAREHOUSE / LIGHTS" or "WAREHOUSE / RESTORATION")
        or "FRONT ENTRANCE / SHOP ROOMS",625),115,151)
    love.graphics.setColor(.13,.23,.28,1);love.graphics.rectangle("fill",760,140,85,40,4)
    setFont(16)
    love.graphics.setColor(.95,.97,.94,1);love.graphics.printf("BACK",760,152,85,"center")
    love.graphics.setColor(.79,.87,.88,1)
    love.graphics.printf(Controls.mode=="stock" and "Bring supplies to the warehouse entrance with a pallet jack. Park it and use this room's stock desk. Retrieved stock returns to the entrance."
        or Controls.mode=="utilities" and "Choose a provider to reconnect the shop. The quoted fee is charged once; the receipt is kept with your shop records."
        or Controls.mode=="restoration" and (require("src.warehouse_condition").of(Runtime.state).mode=="quick"
            and "Switch the warehouse lamps on or off. The machines remain powered."
            or "Utility calls use shop funds. Repairs and cleaning require you to stand near the work. Completed work is saved for everyone.")
        or "Enter a room once construction begins to watch the raccoon engineer work. Room services open when construction is complete. Each player can enter and leave independently.",115,194,730)
    local entries=rows(Runtime)
    Controls.page=math.max(1,math.min(Controls.page,math.ceil(#entries/6)))
    Controls.selected=math.max(1,math.min(Controls.selected,#entries))
    for i=1,6 do
        local index=(Controls.page-1)*6+i
        local row=entries[index]
        if row then
            local y=244+(i-1)*45
            love.graphics.setColor(row.enabled and (index==Controls.selected and .18 or .08) or .07,.18,.20,1)
            love.graphics.rectangle("fill",115,y,730,40,3)
            love.graphics.setColor(row.enabled and .95 or .52,row.enabled and .94 or .61,.82,1)
            setFont(16);love.graphics.print(fitted(row.label,706),127,y+3)
            setFont(14);love.graphics.setColor(.64,.76,.78,1);love.graphics.print(fitted(row.detail,706),127,y+22)
        end
    end
    if #entries==0 then
        love.graphics.setColor(.78,.84,.82,1);love.graphics.print(Controls.mode=="stock"
            and "No stock stored here or staged at the warehouse entrance." or "Nothing to show.",127,260)
    end
    if #entries>6 then
        setFont(16)
        love.graphics.setColor(.78,.88,.89,1);love.graphics.print("< PREVIOUS",122,535)
        love.graphics.printf("Page "..Controls.page.." / "..math.ceil(#entries/6),370,535,220,"center")
        love.graphics.print("NEXT >",778,535)
    end
    setFont(14)
    love.graphics.setColor(.93,.79,.42,1);love.graphics.printf(Runtime.state.message or "",115,572,730,"left")
    love.graphics.pop()
end
return Controls
