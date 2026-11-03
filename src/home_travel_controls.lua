local Travel=require("src.home_travel")
local Flow=require("src.weekend_flow")
local Controls={}
local font,small
local function send(R,command)
    local okay,message
    if R.multiplayer:isClient() then okay,message=R.multiplayer:requestInteraction("homeTravel",command)
    else local code;okay,code,message=require("src.weekend_runtime").command(R,R.World.player,command) end
    R.state.message=message or (okay and "Waiting for the host..." or "Travel is unavailable.")
end
local function buttons(R)
    local week=R.state.home.weekend;local host=not R.multiplayer:isClient()
    if not week then return {} end
    if week.travelToken then
        local token=tostring(week.travelToken)
        if host then return {{key="return",label="TRAVEL WHEN ALL READY",command="depart:"..token},
            {key="b",label="BRING EVERYONE",command="force:"..token},
            {key="c",label="CANCEL REQUEST",command="cancel"}} end
        return {{key="r",label="I'M READY",command="ready:"..token}}
    end
    if host then
        local result={{key="return",label="EXPLORE TOWN",command="outing"}}
        local scene=R.World.player.sceneId or "warehouse"
        if week.phase=="ready" and scene=="warehouse" or week.phase=="home" and scene=="home" then
            result[#result+1]={key="w",label=week.phase=="home" and "RETURN FOR THE WORK WEEK" or "GO HOME FOR THE WEEKEND",command="request"}
        end
        return result
    end
    return {}
end
function Controls.keypressed(key,R)
    if R.state.screen=="home_travel" then
        if key=="escape" then R.state.screen="world";return true end
        for _,b in ipairs(buttons(R)) do if key==b.key then send(R,b.command);return true end end
        return true
    end
    if R.state.screen=="world" and key=="e" then
        local selected=R.World.getInteraction()
        if selected and selected.kind=="homeTravel" then R.state.screen="home_travel";return true end
    end
    return false
end
function Controls.mousepressed(x,y,button,R)
    if R.state.screen~="home_travel" then return false end
    if button~=1 then return true end
    if x>=760 and x<=850 and y>=100 and y<=144 then R.state.screen="world";return true end
    for i,b in ipairs(buttons(R)) do
        if x>=140 and x<=820 and y>=418+(i-1)*50 and y<=462+(i-1)*50 then send(R,b.command);break end
    end
    return true
end
function Controls.draw(R)
    font=font or love.graphics.newFont(18);small=small or love.graphics.newFont(15)
    love.graphics.push("all");love.graphics.setColor(.025,.045,.06,.97);love.graphics.rectangle("fill",110,82,740,530,8)
    love.graphics.setFont(font);love.graphics.setColor(.96,.92,.79,1)
    love.graphics.print("TOWN / HOUSEHOLD TRAVEL",140,110)
    love.graphics.setFont(small);love.graphics.printf("BACK [Esc]",752,112,88,"center")
    local week=R.state.home.weekend;local lines={}
    lines={"You can leave for town and return through the same entrance at any time.",
        "The shop keeps its normal schedule while you are away.",
        "Park, dismount, and walk to the warehouse or your apartment door to enter."}
    if week and week.phase=="closing" then
        lines[#lines+1]="Friday shutdown is in progress; the household can still go into town."
    elseif week and (week.phase=="ready" or week.phase=="home") then
        lines[#lines+1]="The shop is closed for the weekend. Town outings remain available."
    end
    lines[#lines+1]="Current time: "..require("src.business_calendar").dateTimeTextAtHours(require("src.business_calendar").absoluteHours(R.state))
    if week and week.travelToken then
        lines={"Everyone travels together, including guests in other shop rooms.",
            "The host may wait for readiness or choose Bring everyone."}
        for _,p in ipairs(require("src.weekend_runtime").players(R)) do
            lines[#lines+1]=(p.name or ((p.id or 1)==1 and "Host" or "Guest "..p.id))..": "
                ..(Travel.ready(week,p.id or 1) and "Ready" or "Waiting")
        end
    end
    for i=1,math.min(#lines,8) do love.graphics.printf(lines[i],140,164+(i-1)*28,680,"left") end
    for i,b in ipairs(buttons(R)) do
        local y=418+(i-1)*50
        love.graphics.setColor(.13,.32,.35,1);love.graphics.rectangle("fill",140,y,680,44,5)
        love.graphics.setColor(.96,.96,.88,1);love.graphics.printf(b.label.."  ["..b.key:upper().."]",148,y+13,664,"center")
    end
    love.graphics.setColor(.96,.79,.4,1);love.graphics.printf(R.state.message or "",140,575,680,"left")
    love.graphics.pop()
end
return Controls
