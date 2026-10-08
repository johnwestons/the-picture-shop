local Rooms=require("src.shop_rooms")
local Controls={page=1,selected=1}
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
    if okay and kind=="roomStock" then Runtime.saveCurrent() end
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
    else
        for _,id in ipairs({"front_left","front_right"}) do
            local bay=Runtime.state.warehouse.bays[id]
            local ready=Rooms.definition(Runtime.state,id)
            local product=bay.optionId and require("src.warehouse_upgrades").catalog(bay.optionId)
            local project=require("src.warehouse_layout").project(Runtime.state,id)
            result[#result+1]={label=(id=="front_left" and "ROOM A" or "ROOM B").."  /  "..(product and product.name or "Unpurchased"),
                detail=ready and "Enter this separate room" or project and ("Construction: "..project.phase.." / stage "..(project.stage or 0).." of 4")
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
        or "Choose an available room. Other players stay in their own rooms."
end
function Controls.keypressed(key,Runtime)
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
    if Rooms.scene(Runtime.World.player)~="warehouse" and ({f=true,l=true,m=true,q=true,v=true,g=true,t=true,r=true,k=true,h=true})[key] then
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
    elseif selected.kind=="roomRest" then send(Runtime,"roomRest",Runtime.World.player.resting and "stand" or "rest")
    else return false end
    return true
end
function Controls.mousepressed(x,y,button,Runtime)
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
    love.graphics.print(fitted(Controls.mode=="stock" and Rooms.name(Runtime.state,Rooms.scene(Runtime.World.player)).." / SHOP STOCK" or "FRONT ENTRANCE / SHOP ROOMS",625),115,151)
    love.graphics.setColor(.13,.23,.28,1);love.graphics.rectangle("fill",760,140,85,40,4)
    setFont(16)
    love.graphics.setColor(.95,.97,.94,1);love.graphics.printf("BACK",760,152,85,"center")
    love.graphics.setColor(.79,.87,.88,1)
    love.graphics.printf(Controls.mode=="stock" and "Bring supplies to the warehouse entrance with a pallet jack. Park it and use this room's stock desk. Retrieved stock returns to the entrance."
        or "Rooms are purchased on the computer and unlocked after construction. Each player can enter and leave independently.",115,194,730)
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
        love.graphics.setColor(.78,.84,.82,1);love.graphics.print("No stock stored here or staged at the warehouse entrance.",127,260)
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
