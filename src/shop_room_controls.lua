local Rooms=require("src.shop_rooms")
local Controls={page=1,selected=1}
function Controls.isPortableUtilities() return Controls.mode=="utilities" end
local function cancelGameplayTouches(Runtime)
    if Runtime.mobileControls and Runtime.mobileControls.cancelAll then
        Runtime.mobileControls:cancelAll()
    end
end
local function close(Runtime)
    cancelGameplayTouches(Runtime)
    Runtime.state.screen="world"
    return true
end
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
local hudSlices={}
local function drawNineSlice(name,x,y,width,height,source,borderX,borderY,targetBorderX,targetBorderY)
    local g=love.graphics
    local hud=require("src.screens.warehouse_hud")
    local sprite=hud.sprite(name)
    local imageWidth,imageHeight=sprite:getDimensions()
    local sx,sy,sw,sh=0,0,imageWidth,imageHeight
    if source then sx,sy,sw,sh=source[1],source[2],source[3],source[4] end
    borderX,borderY=math.min(borderX,sw/2),math.min(borderY,sh/2)
    g.setColor(1,1,1,1)
    local key=table.concat({name,sx,sy,sw,sh,borderX,borderY},":")
    local cached=hudSlices[key]
    if not cached then
        local xs={sx,sx+borderX,sx+sw-borderX,sx+sw}
        local ys={sy,sy+borderY,sy+sh-borderY,sy+sh}
        cached={quads={},sourceWidths={},sourceHeights={}}
        for column=1,3 do cached.sourceWidths[column]=xs[column+1]-xs[column] end
        for row=1,3 do cached.sourceHeights[row]=ys[row+1]-ys[row] end
        for row=1,3 do
            cached.quads[row]={}
            for column=1,3 do
                cached.quads[row][column]=g.newQuad(xs[column],ys[row],
                    cached.sourceWidths[column],cached.sourceHeights[row],imageWidth,imageHeight)
            end
        end
        hudSlices[key]=cached
    end
    local left,right=math.min(targetBorderX or borderX,width/2),math.min(targetBorderX or borderX,width/2)
    local top,bottom=math.min(targetBorderY or borderY,height/2),math.min(targetBorderY or borderY,height/2)
    local dx={x,x+left,x+width-right,x+width}
    local dy={y,y+top,y+height-bottom,y+height}
    for row=1,3 do
        for column=1,3 do
            local drawWidth,drawHeight=dx[column+1]-dx[column],dy[row+1]-dy[row]
            if drawWidth>0 and drawHeight>0 then
                g.draw(sprite,cached.quads[row][column],dx[column],dy[row],0,
                    drawWidth/cached.sourceWidths[column],drawHeight/cached.sourceHeights[row])
            end
        end
    end
end
local function drawHudFont(kind,size)
    love.graphics.setFont(require("src.screens.warehouse_hud").font(kind,size))
end
local function drawBanner(x,y,width,height)
    local sprite=require("src.screens.warehouse_hud").sprite("notice-banner")
    local imageWidth,imageHeight=sprite:getDimensions()
    drawNineSlice("notice-banner",x,y,width,height,{25,185,imageWidth-50,350},125,95,
        42,math.min(16,height*.33))
end
local function rowTitle(row)
    return tostring(row.label or ""):gsub("^DONE%s+",""):gsub("^DO%s+","")
end
local function iconKind(command)
    if command=="call_power" then return "power" end
    if command=="call_water" then return "water" end
    if command=="repair_breaker" then return "breaker" end
    if command and command:match("^clean_") then return "clean" end
    if command=="lights_on" or command=="lights_off" then return "lights" end
    if command=="grand_opening" then return "opening" end
    return "service"
end
local function drawTaskIcon(kind,x,y,size,color)
    local g=love.graphics
    local cx,cy=x+size/2,y+size/2
    g.setColor(.035,.075,.064,.95);g.circle("fill",cx,cy,size/2)
    g.setColor(color);g.setLineWidth(1.5);g.circle("line",cx,cy,size/2-1)
    if kind=="power" then
        g.polygon("fill",cx+1,cy-size*.30,cx-size*.12,cy-size*.02,
            cx+size*.02,cy-size*.02,cx-size*.08,cy+size*.30,
            cx+size*.19,cy+size*.04,cx+size*.05,cy+size*.04)
    elseif kind=="water" then
        g.circle("fill",cx,cy-size*.08,size*.14)
        g.polygon("fill",cx,cy-size*.29,cx-size*.19,cy+size*.01,cx+size*.19,cy+size*.01)
    elseif kind=="breaker" then
        g.rectangle("line",cx-size*.22,cy-size*.25,size*.44,size*.50,2)
        g.line(cx-size*.09,cy+size*.12,cx+size*.10,cy-size*.12)
        g.circle("fill",cx-size*.10,cy+size*.13,1.5)
    elseif kind=="clean" then
        g.line(cx-size*.13,cy-size*.27,cx+size*.10,cy+size*.08)
        g.line(cx+size*.10,cy+size*.08,cx-size*.02,cy+size*.26)
        g.line(cx-size*.21,cy+size*.26,cx+size*.14,cy+size*.26)
    elseif kind=="lights" then
        g.circle("line",cx,cy-size*.06,size*.16)
        g.line(cx-size*.09,cy+size*.14,cx+size*.09,cy+size*.14)
        g.line(cx-size*.07,cy+size*.22,cx+size*.07,cy+size*.22)
        for angle=0,315,45 do
            local a=math.rad(angle);g.line(cx+math.cos(a)*size*.27,cy-size*.06+math.sin(a)*size*.27,
                cx+math.cos(a)*size*.34,cy-size*.06+math.sin(a)*size*.34)
        end
    elseif kind=="opening" then
        local points={}
        for index=0,9 do
            local radius=index%2==0 and size*.27 or size*.12
            local angle=-math.pi/2+index*math.pi/5
            points[#points+1]=cx+math.cos(angle)*radius
            points[#points+1]=cy+math.sin(angle)*radius
        end
        g.polygon("fill",points)
    else
        g.rectangle("line",cx-size*.20,cy-size*.20,size*.40,size*.40,2)
        g.line(cx-size*.11,cy,cx+size*.11,cy)
        g.line(cx,cy-size*.11,cx,cy+size*.11)
    end
end
local function statusFor(row)
    if row.done then return "DONE",{.35,.68,.48,1} end
    if row.physical then return row.physical,{.72,.68,.42,1} end
    if row.blocked then return "LOCKED",{.52,.58,.53,1} end
    if row.enabled then return "READY",{.82,.64,.31,1} end
    return "WAIT",{.52,.58,.53,1}
end
local function drawStatusChip(x,y,width,height,label,color,size)
    local g=love.graphics
    g.setColor(color[1]*.25,color[2]*.25,color[3]*.25,.96)
    g.rectangle("fill",x,y,width,height,4)
    g.setColor(color);g.setLineWidth(1);g.rectangle("line",x,y,width,height,4)
    drawHudFont("typewriter",size or 10);g.printf(label,x,y+(height-(size or 10))/2-1,width,"center")
end
local function drawTaskCard(row,index,x,y,width,height,compact,hovered)
    local g=love.graphics
    local status,statusColor=statusFor(row)
    local selected=Controls.selected==index
    local ready=row.enabled or row.done or row.physical
    if hovered or selected then
        g.setColor(.14,.17,.105,.98)
    else
        g.setColor(.025,.065,.054,.94)
    end
    g.rectangle("fill",x,y,width,height,5)
    local border=selected and {.88,.70,.36,1} or statusColor
    g.setColor(border);g.setLineWidth(selected and 1.5 or 1)
    g.rectangle("line",x,y,width,height,5)
    local iconSize=compact and 21 or 34
    local iconX=x+(compact and 6 or 9)
    local iconY=y+(height-iconSize)/2
    drawTaskIcon(iconKind(row.command),iconX,iconY,iconSize,
        ready and {.94,.78,.41,1} or {.52,.58,.52,1})
    local chipWidth=compact and 53 or 64
    local chipHeight=compact and 16 or 19
    local chipX=x+width-chipWidth-(compact and 6 or 8)
    local chipY=y+(compact and 4 or 7)
    drawStatusChip(chipX,chipY,chipWidth,chipHeight,status,statusColor,compact and 9 or 10)
    local textX=x+(compact and 34 or 52)
    local textWidth=chipX-textX-(compact and 4 or 6)
    drawHudFont("typewriter",compact and 11 or 13)
    g.setColor(ready and {.96,.92,.76,1} or {.68,.71,.66,1})
    g.print(fitted(rowTitle(row),textWidth),textX,y+(compact and 2 or 8))
    if compact then
        drawHudFont("digital",10);g.setColor(.68,.76,.68,1)
        g.print(fitted(row.detail or "",textWidth),textX,y+17)
    else
        drawHudFont("typewriter",10);g.setColor(.70,.78,.70,1)
        g.print(fitted(row.detail or "",textWidth+chipWidth-3),textX,y+34)
    end
end
local function closeButtonRect()
    return {x=776,y=151,width=36,height=36}
end
local function drawRestorationMenu(Runtime,entries)
    local g=love.graphics
    local condition=require("src.warehouse_condition").of(Runtime.state)
    local isUtilities=Controls.mode=="utilities"
    local isQuick=condition and condition.mode=="quick"
    local panel={x=95,y=124,width=770,height=474}
    g.setColor(1,1,1,.98);drawNineSlice("menu-panel",panel.x,panel.y,panel.width,panel.height,nil,145,150,100,50)
    drawBanner(128,143,704,50)
    drawHudFont("stencil",23);g.setColor(.97,.85,.53,1)
    local title=isUtilities and "PORTABLE UTILITIES PHONE"
        or isQuick and "WAREHOUSE LIGHTING"
        or "WAREHOUSE RESTORATION"
    g.print(title,151,151)
    local back=closeButtonRect()
    g.setColor(.035,.08,.065,.95);g.circle("fill",back.x+back.width/2,back.y+back.height/2,15)
    g.setColor(.91,.76,.43,1);g.setLineWidth(1.5);g.circle("line",back.x+back.width/2,back.y+back.height/2,15)
    g.line(back.x+23,back.y+18,back.x+13,back.y+18,back.x+18,back.y+13)
    g.line(back.x+13,back.y+18,back.x+18,back.y+23)
    drawHudFont("typewriter",11);g.setColor(.83,.87,.77,1)
    local subtitle=isUtilities and "Call the power or water company and pay the reconnection fee."
        or isQuick and "Use the wall switch to change the warehouse lights."
        or "Move through both puddles while mopping. Each pass clears part of the spill."
    g.print(fitted(subtitle,570),151,202)

    Controls.hitRects={}
    local px,py=Runtime.pointerPosition and Runtime.pointerPosition()
    if isUtilities then
        drawBanner(138,235,684,30)
        drawHudFont("typewriter",12);g.setColor(.96,.84,.51,1)
        g.print("SERVICE PROVIDERS",157,242)
        for index,row in ipairs(entries) do
            local x=index==1 and 140 or 490
            local rect={x=x,y=274,width=330,height=116}
            Controls.hitRects[index]=rect
            local hover=px and py and px>=x and px<=x+rect.width and py>=rect.y and py<=rect.y+rect.height
            drawTaskCard(row,index,x,rect.y,rect.width,rect.height,false,hover)
        end
        drawBanner(140,407,680,77)
        drawHudFont("stencil",15);g.setColor(.91,.78,.47,1);g.print("SERVICE NOTES",161,416)
        drawHudFont("typewriter",11);g.setColor(.82,.86,.76,1)
        local note="Fees are charged once. The shop keeps a receipt for each completed connection."
        g.print(fitted(note,630),161,444)
        drawBanner(140,493,680,52)
        drawHudFont("stencil",14);g.setColor(.91,.78,.47,1);g.print("NEXT: WAREHOUSE REPAIRS",160,502)
        drawHudFont("typewriter",10);g.setColor(.82,.86,.76,1)
        g.print("After service is connected, return to the warehouse to repair the breaker and restore the shop.",160,523)
    elseif isQuick then
        drawBanner(138,235,684,30)
        drawHudFont("typewriter",12);g.setColor(.96,.84,.51,1);g.print("LIGHTING",157,242)
        for index,row in ipairs(entries) do
            local rect={x=143,y=278,width=674,height=90}
            Controls.hitRects[index]=rect
            local hover=px and py and px>=rect.x and px<=rect.x+rect.width and py>=rect.y and py<=rect.y+rect.height
            drawTaskCard(row,index,rect.x,rect.y,rect.width,rect.height,false,hover)
        end
        drawBanner(140,393,680,77)
        drawHudFont("stencil",15);g.setColor(.91,.78,.47,1);g.print("POWER STATUS",161,402)
        drawHudFont("typewriter",11);g.setColor(.82,.86,.76,1)
        g.print("Warehouse equipment remains powered while the lamps are off.",161,430)
    else
        local completed,total=0,#entries
        for _,row in ipairs(entries) do if row.done then completed=completed+1 end end
        drawHudFont("digital",13);g.setColor(.91,.80,.49,1)
        g.print("MOP PUDDLES IN THE WORLD",151,216)
        drawHudFont("digital",13);g.setColor(.82,.87,.76,1)
        g.printf(("%d / %d TASKS COMPLETE"):format(completed,total),560,216,251,"right")
        drawBanner(137,237,270,30);drawBanner(415,237,408,30)
        drawHudFont("typewriter",12);g.setColor(.96,.84,.51,1)
        g.print("POWER & CLEANUP",155,244);g.print("LIGHTS & OPENING",433,244)
        local leftIndex,rightIndex=0,0
        for index,row in ipairs(entries) do
            if index<=5 then
                leftIndex=leftIndex+1
                local y=273+(leftIndex-1)*35
                local rect={x=140,y=y,width=264,height=31}
                Controls.hitRects[index]=rect
                local hover=px and py and px>=rect.x and px<=rect.x+rect.width and py>=rect.y and py<=rect.y+rect.height
                drawTaskCard(row,index,rect.x,rect.y,rect.width,rect.height,true,hover)
            else
                rightIndex=rightIndex+1
                local y=273+(rightIndex-1)*35
                local rect={x=418,y=y,width=402,height=31}
                Controls.hitRects[index]=rect
                local hover=px and py and px>=rect.x and px<=rect.x+rect.width and py>=rect.y and py<=rect.y+rect.height
                drawTaskCard(row,index,rect.x,rect.y,rect.width,rect.height,true,hover)
            end
        end
        drawBanner(140,493,680,52)
        drawHudFont("stencil",14);g.setColor(.91,.78,.47,1);g.print("WORK ORDER",160,502)
        drawHudFont("typewriter",11);g.setColor(.82,.86,.76,1)
        g.print(fitted(Runtime.state.message or "Select a task to review its requirements.",625),160,523)
    end
    Controls.hitRects.back=back
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
            kind="restoration",command="call_power",enabled=not c.powerConnected,done=c.powerConnected}
        result[2]={label=c.waterConnected and "DONE  Water service connected" or "CALL WATER COMPANY",
            detail=("One-time connection fee: $%.2f. Charged to the shop and saved as a receipt."):format(Condition.WATER_FEE_CENTS/100),
            kind="restoration",command="call_water",enabled=not c.waterConnected,done=c.waterConnected}
    elseif Controls.mode=="restoration" then
        local Condition=require("src.warehouse_condition")
        local c=Condition.of(Runtime.state)
        if not c then return result end
        local function add(label,detail,command,done,blocked,physical)
            result[#result+1]={label=(done and "DONE  " or "DO  ")..label,detail=detail,
                kind="restoration",command=command,enabled=not done and not blocked and not physical,
                done=done,blocked=blocked,physical=physical}
        end
        if c.mode=="quick" then
            add(c.lightsOn and "Switch warehouse lights off" or "Switch warehouse lights on",
                "Use the breaker box on the west wall.",c.lightsOn and "lights_off" or "lights_on",false,false,"WORLD")
            return result
        end
        add("Reconnect power","Use the wall phone to call and pay the power company.",
            "call_power",c.powerConnected,false,"PHONE")
        add("Reconnect water","Use the wall phone to call and pay the water utility.",
            "call_water",c.waterConnected,false,"PHONE")
        add("Repair breaker","Use the damaged box on the west wall after service returns.",
            "repair_breaker",c.breakerRepaired,false,"WORLD")
        for _,puddle in ipairs({"puddle1","puddle2"}) do
            local label=puddle=="puddle1" and "Clean left oily puddle" or "Clean right oily puddle"
            add(label,"Mop directly across the visible water; each pass fades it further.",
                "clean_"..puddle,c.cleanedPuddles[puddle],false,"WORLD")
        end
        add("Switch warehouse lights on","Use the repaired wall breaker; lamps start off.",
            "lights_on",c.lightsOn,false,"WORLD")
        local ready,reason=Condition.readyForOpening(Runtime.state)
        add("Hold grand opening",ready and "Start the celebration. Clients can call when it ends."
            or reason,"grand_opening",c.grandOpened,not ready)
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
        local mopAction=row.kind=="restoration" and row.command:match("^clean_")
        local character=Runtime.World.player.character or require("src.config").player.character
        if mopAction and character=="rabbit-worker" then
            local okay,message=require("src.warehouse_mop_action").begin(Runtime,row.command)
            if not okay then Runtime.state.message=message end
            return
        end
        local okay=send(Runtime,row.kind,row.command)
        if okay and row.kind=="shopRoom" then Runtime.state.screen="world" end
    end
end
function Controls.open(Runtime,mode,action)
    -- The menu replaces gameplay input. Clear held joystick/button touches so a
    -- touch that began on the world cannot remain latched when the menu closes.
    cancelGameplayTouches(Runtime)
    Controls.mode,Controls.page,Controls.selected=mode,1,1
    if action then
        for index,row in ipairs(rows(Runtime)) do
            if row.command==action then
                Controls.selected=index
                Controls.page=math.floor((index-1)/6)+1
                break
            end
        end
    end
    Runtime.state.screen="shop_rooms"
    Runtime.state.message=mode=="stock" and "Stage delivered shop stock at the warehouse entrance. Store or retrieve it here."
        or mode=="utilities" and "Call the utility providers to reconnect the closed shop."
        or mode=="restoration" and (require("src.warehouse_condition").of(Runtime.state).mode=="story"
            and "Use the wall phone, breaker box, and mop. This list updates as you work."
            or "Use the wall switch to turn the warehouse lights on or off.")
        or "Choose an available room. Other players stay in their own rooms."
end
function Controls.keypressed(key,Runtime)
    if require("src.warehouse_mop_action").active(Runtime.World.player) then
        if key=="e" or key=="back" then require("src.warehouse_mop_action").stop(Runtime) end
        return true
    end
    if require("src.home_furniture_controls").keypressed(key,Runtime) then return true end
    if require("src.home_delivery_controls").keypressed(key,Runtime) then return true end
    if require("src.home_activity_controls").keypressed(key,Runtime) then return true end
    if require("src.home_travel_controls").keypressed(key,Runtime) then return true end
    if Runtime.state.screen=="shop_rooms" then
        if key=="escape" or key=="back" then close(Runtime)
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
    if key=="u" and sceneId=="warehouse" then
        Controls.open(Runtime,"restoration")
        return true
    end
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
    elseif selected.kind=="restoration" then
        local action=selected.target and selected.target.restorationAction
        if action and action:match("^clean_puddle%d+$") then
            local character=Runtime.World.player.character or require("src.config").player.character
            if character=="rabbit-worker" then
                local okay,message=require("src.warehouse_mop_action").begin(Runtime,action)
                if not okay then Runtime.state.message=message end
            else send(Runtime,"restoration",action) end
        elseif action then send(Runtime,"restoration",action)
        else Controls.open(Runtime,"restoration") end
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
    if Controls.mode=="utilities" or Controls.mode=="restoration" then
        local rects=Controls.hitRects or {}
        local back=rects.back
        if back and x>=back.x and x<=back.x+back.width and y>=back.y and y<=back.y+back.height then
            close(Runtime);return true
        end
        for index,rect in ipairs(rects) do
            if x>=rect.x and x<=rect.x+rect.width and y>=rect.y and y<=rect.y+rect.height then
                activate(Runtime,index);return true
            end
        end
        return true
    end
    if x>=760 and x<=845 and y>=140 and y<=180 then close(Runtime);return true end
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
    if Controls.mode=="utilities" or Controls.mode=="restoration" then
        love.graphics.push("all");love.graphics.setShader()
        drawRestorationMenu(Runtime,rows(Runtime))
        love.graphics.pop()
        return
    end
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
