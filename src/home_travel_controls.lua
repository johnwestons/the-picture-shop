local Travel=require('src.home_travel')
local Controls={}
local font,small,tiny

local function send(R,command)
    local okay,message
    if R.multiplayer:isClient() then okay,message=R.multiplayer:requestInteraction('homeTravel',command)
    else local code;okay,code,message=require('src.weekend_runtime').command(R,R.World.player,command) end
    R.state.message=message or (okay and 'Waiting for the host...' or 'Travel is unavailable.')
    return okay
end

local function deliveryWorld(R)
    local town=R.state.home and R.state.home.town
    if not town then return nil end
    local okay,world=pcall(require('src.commute.runtime').world,R)
    if not okay then return nil end
    return world
end

local function available(R)
    if not require('src.commute.runtime').enabled() then return {} end
    local world=deliveryWorld(R)
    if not world then return {} end
    return require('src.commute.delivery_run').availableJobs(R.state,world,'player')
end

local function selectedCount(planner)
    local count=0
    for _,job in ipairs(planner.jobs) do if planner.selected[job.id] then count=count+job.palletCount end end
    return count
end

local function routeOrder(planner,wanted)
    local order=0
    for _,kind in ipairs({'town','city'}) do
        for _,job in ipairs(planner.jobs) do
            if planner.selected[job.id] and job.destination.kind==kind then
                order=order+1
                if job.id==wanted then return order end
            end
        end
    end
end

local function buttons(R)
    local week=R.state.home.weekend;local host=not R.multiplayer:isClient()
    if not week then return {} end
    if week.travelToken then
        local token=tostring(week.travelToken)
        if host then return {{key='return',label='TRAVEL WHEN ALL READY',command='depart:'..token},
            {key='b',label='BRING EVERYONE',command='force:'..token},
            {key='c',label='CANCEL REQUEST',command='cancel'}} end
        return {{key='r',label="I'M READY",command='ready:'..token}}
    end
    if not require('src.commute.runtime').enabled() then
        if not host then return {} end
        return {{key='w',label=week.phase=='home' and 'RETURN FOR THE WORK WEEK' or 'GO HOME FOR THE WEEKEND',command='request'}}
    end
    do
        local trip=R.state.home.commute
        local resuming=trip and trip.deliveryRun and trip.deliveryDriver==require('src.home_residents').key(R.World.player)
        local result={{key='return',label=resuming and 'RESUME DELIVERY' or 'EXPLORE TOWN',command='explore'}}
        local scene=R.World.player.sceneId or 'warehouse'
        if scene=='warehouse' and #available(R)>0 then
            result[#result+1]={key='d',label='PLAN PAPER DELIVERIES',command='planner'}
        end
        if host and week.phase=='closing' and scene=='warehouse' then
            result[#result+1]={key='w',label='CLOSE SHOP & LEAVE',command='shutdown'}
        end
        return result
    end
end

local function openPlanner(R)
    local jobs=available(R)
    R._deliveryPlanner={jobs=jobs,selected={},scroll=1}
    if #jobs==0 then R.state.message='No inspected, wrapped jobs are ready to load.' end
end

local function toggleVisible(R,index)
    local planner=R._deliveryPlanner
    local job=planner and planner.jobs[planner.scroll+index-1]
    if not job then return end
    planner.selected[job.id]=not planner.selected[job.id] or nil
end

local function submitPlanner(R)
    local planner=R._deliveryPlanner
    if not planner then return false end
    local capacity=selectedCount(planner)
    if capacity<1 then R.state.message='Choose jobs to add to the delivery route.';return true end
    if capacity>10 then R.state.message='The truck holds ten pallets. Remove jobs until the manifest fits.';return true end
    local ids={}
    for _,job in ipairs(planner.jobs) do if planner.selected[job.id] then ids[#ids+1]=job.id end end
    if send(R,'delivery:'..table.concat(ids,',')) then R._deliveryPlanner=nil end
    return true
end

function Controls.keypressed(key,R)
    if R.state.screen=='home_travel' then
        local planner=R._deliveryPlanner
        if planner then
            if key=='escape' or key=='back' then R._deliveryPlanner=nil;return true end
            if key=='up' then planner.scroll=math.max(1,planner.scroll-1);return true end
            if key=='down' then planner.scroll=math.min(math.max(1,#planner.jobs-7),planner.scroll+1);return true end
            if key=='return' or key=='kpenter' then return submitPlanner(R) end
            local index=tonumber(key)
            if index==0 then index=10 end
            if index and index>=1 and index<=8 then toggleVisible(R,index);return true end
            return true
        end
        if key=='escape' or key=='back' then R.state.screen='world';return true end
        for _,b in ipairs(buttons(R)) do
            if key==b.key then
                if b.command=='planner' then openPlanner(R) else send(R,b.command) end
                return true
            end
        end
        return true
    end
    if R.state.screen=='world' and key=='e' then
        local selected=R.World.getInteraction()
        if selected and selected.kind=='homeTravel' then R.state.screen='home_travel';return true end
    end
    return false
end

function Controls.mousepressed(x,y,button,R)
    if R.state.screen~='home_travel' then return false end
    if button~=1 then return true end
    local planner=R._deliveryPlanner
    if planner then
        if x>=760 and x<=850 and y>=100 and y<=144 then R._deliveryPlanner=nil;return true end
        if x>=140 and x<=464 and y>=526 and y<=570 then submitPlanner(R);return true end
        if x>=496 and x<=820 and y>=526 and y<=570 then R._deliveryPlanner=nil;return true end
        if x>=140 and x<=820 then
            for index=1,8 do
                local rowY=174+(index-1)*37
                if y>=rowY and y<=rowY+33 then toggleVisible(R,index);return true end
            end
        end
        if x>=745 and x<=820 and y>=145 and y<=172 then
            planner.scroll=math.min(math.max(1,#planner.jobs-7),planner.scroll+1);return true
        end
        if x>=650 and x<=725 and y>=145 and y<=172 then
            planner.scroll=math.max(1,planner.scroll-1);return true
        end
        return true
    end
    if x>=760 and x<=850 and y>=100 and y<=144 then R.state.screen='world';return true end
    for i,b in ipairs(buttons(R)) do
        if x>=140 and x<=820 and y>=418+(i-1)*50 and y<=462+(i-1)*50 then
            if b.command=='planner' then openPlanner(R) else send(R,b.command) end
            break
        end
    end
    return true
end

local function drawPanel(title,R)
    local g=love.graphics
    g.push('all');g.setColor(.025,.045,.06,.97);g.rectangle('fill',110,82,740,530,8)
    g.setFont(font);g.setColor(.96,.92,.79,1);g.print(title,140,110)
    g.setFont(small);g.setColor(.76,.82,.77,1);g.printf('BACK [Esc]',752,112,88,'center')
end

local function drawPlanner(R)
    local g=love.graphics;local planner=R._deliveryPlanner
    drawPanel('PLAN CUSTOMER DELIVERIES',R)
    local count=selectedCount(planner)
    g.setFont(small);g.setColor(count>10 and 1 or .83,count>10 and .35 or .86,count>10 and .3 or .75,1)
    g.print(('Select jobs · %d / 10 pallets · town stops first, Millhaven after'):format(count),140,148)
    local maxStart=math.max(1,#planner.jobs-7)
    g.setColor(.71,.79,.72,1)
    if #planner.jobs>0 then g.printf(('JOBS %d–%d OF %d'):format(planner.scroll,math.min(#planner.jobs,planner.scroll+7),#planner.jobs),590,148,135,'right')
    else g.printf('NO READY JOBS',590,148,135,'right') end
    g.setFont(tiny)
    if #planner.jobs==0 then
        g.setColor(.82,.86,.79,1);g.printf('No ready jobs. Jobs appear here after inspection passes and all pallets are wrapped and staged.',150,225,660,'center')
    end
    for visible=1,8 do
        local job=planner.jobs[planner.scroll+visible-1]
        if job then
            local y=174+(visible-1)*37;local isSelected=planner.selected[job.id]
            g.setColor(isSelected and .17 or .075,isSelected and .30 or .105,isSelected and .28 or .12,1)
            g.rectangle('fill',140,y,680,33,4)
            g.setColor(isSelected and .95 or .68,isSelected and .85 or .75,isSelected and .55 or .70,1)
            g.print(('['..visible..']'),150,y+8)
            if isSelected then g.print(('ROUTE '..routeOrder(planner,job.id)),184,y+8) end
            local location=job.destination.kind=='city' and ('Millhaven · '..job.destination.label)
                or ('Town · '..job.destination.label)
            local line=('%s  ·  %d pallet%s  ·  %s'):format(job.company,job.palletCount,job.palletCount==1 and '' or 's',location)
            g.printf(line,250,y+8,550,'left')
        end
    end
    if maxStart>1 then
        g.setFont(small);g.setColor(.88,.88,.79,1);g.print('↑',662,146);g.print('↓',735,146)
    end
    g.setFont(small)
    g.setColor(.13,.32,.35,1);g.rectangle('fill',140,526,324,44,5)
    g.rectangle('fill',496,526,324,44,5)
    g.setColor(.96,.96,.88,1);g.printf('RESERVE DELIVERY  [Enter]',148,540,308,'center')
    g.printf('CANCEL',504,540,308,'center')
    g.setColor(.96,.79,.4,1);g.printf(R.state.message or '',140,582,680,'left')
    g.pop()
end

function Controls.draw(R)
    font=font or love.graphics.newFont(18);small=small or love.graphics.newFont(15);tiny=tiny or love.graphics.newFont(13)
    if R._deliveryPlanner then return drawPlanner(R) end
    local g=love.graphics;drawPanel('TOWN / DELIVERIES',R)
    local week=R.state.home.weekend;local lines={
        'Leave on your own. Other players stay where they are and keep playing.',
        'The shop keeps its normal schedule while you are away.',
        'Dismount and walk to the warehouse or your apartment door to enter.'}
    if week and week.phase=='closing' then
        lines[#lines+1]='Friday closing: finish jobs, call pickups, and clear the dock before leaving.'
        local pending=require('src.shop_shutdown').checklist(R.state,R.World)
        if #pending==0 then lines[#lines+1]='The shop is clear. Choose Go Home when you are ready.'
        else for i=1,math.min(2,#pending) do lines[#lines+1]=pending[i] end end
    elseif week and (week.phase=='ready' or week.phase=='home') then
        lines[#lines+1]='The shop is closed for the weekend. Town outings remain available.'
    end
    local twelveHourTime=not (R.App.settings and R.App.settings.twelveHourTime==false)
    lines[#lines+1]='Current time: '..require('src.business_calendar').dateTimeTextAtHours(require('src.business_calendar').absoluteHours(R.state),twelveHourTime)
    if week and week.travelToken then
        lines={'Everyone travels together, including guests in other shop rooms.',
            'The host may wait for readiness or choose Bring everyone.'}
        for _,p in ipairs(require('src.weekend_runtime').players(R)) do
            lines[#lines+1]=(p.name or ((p.id or 1)==1 and 'Host' or 'Guest '..p.id))..': '
                ..(Travel.ready(week,p.id or 1) and 'Ready' or 'Waiting')
        end
    end
    for i=1,math.min(#lines,8) do g.printf(lines[i],140,164+(i-1)*28,680,'left') end
    for i,b in ipairs(buttons(R)) do
        local y=418+(i-1)*50
        g.setColor(.13,.32,.35,1);g.rectangle('fill',140,y,680,44,5)
        g.setColor(.96,.96,.88,1);g.printf(b.label..'  ['..b.key:upper()..']',148,y+13,664,'center')
    end
    g.setColor(.96,.79,.4,1);g.printf(R.state.message or '',140,575,680,'left')
    g.pop()
end

return Controls
