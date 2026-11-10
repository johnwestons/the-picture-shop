local Watchdog=require('src.ai_watchdog')
local Config=require('src.config')
local BuildVersion=require('src.build_version')
local Panel={PAGE_SIZE=1}
local font,smallFont
local CARD={x=116,width=728,height=211}
local OLDER={x=735,y=577,width=108,height=23}
local NEWER={x=619,y=577,width=108,height=23}
local LATEST={x=503,y=577,width=108,height=23}
local colors={
    RECOVERING={.97,.77,.32,1},STALLED={1,.40,.34,1},RESOLVED={.47,.88,.69,1},
    RECOVERED={.47,.88,.69,1},CLEARED={.47,.88,.69,1},
}

local function clean(value)
    return tostring(value or 'n/a'):gsub('[%c]+',' ')
end

local function safeNumber(value,format)
    value=tonumber(value)
    if not value or value~=value or math.abs(value)==math.huge then return 'n/a' end
    return string.format(format or '%.1f',value)
end

local function ageText(seconds)
    if not seconds then return 'n/a' end
    if seconds<60 then return ('%.1fs'):format(seconds) end
    return ('%dm %02ds'):format(math.floor(seconds/60),math.floor(seconds%60))
end

local function diagnosticsItems(snapshot)
    local items,seen={},{}
    for _,event in ipairs(snapshot.active) do
        if not seen[event.sequence] then
            items[#items+1]=event;seen[event.sequence]=true
        end
    end
    for index=#snapshot.events,1,-1 do
        local event=snapshot.events[index]
        if not seen[event.sequence] then items[#items+1]=event end
    end
    return items
end

function Panel.maxOffset(snapshot)
    return math.max(0,#diagnosticsItems(snapshot)-Panel.PAGE_SIZE)
end

function Panel.hitTest(x,y)
    local function hit(rect)
        return x>=rect.x and x<=rect.x+rect.width and y>=rect.y and y<=rect.y+rect.height
    end
    if hit(NEWER) then return 'newer' end
    if hit(LATEST) then return 'latest' end
    if hit(OLDER) then return 'older' end
    return nil
end

local function drawEvent(g,event,y,now)
    g.setColor(.055,.075,.078,.98)
    g.rectangle('fill',CARD.x,y,CARD.width,CARD.height,4,4)
    g.setColor(.28,.36,.35,1)
    g.rectangle('line',CARD.x,y,CARD.width,CARD.height,4,4)
    local tint=colors[event.status] or {.85,.89,.85,1}
    g.setFont(font);g.setColor(tint)
    local scope=not event.visible and ' · OFF-SCREEN'
        or event.scope=='world-simulation' and ' · WORLD SIMULATION' or ''
    g.printf(('#%04d  %s  ·  %s  ·  %s%s'):format(event.sequence,event.status,
        clean(event.system),clean(event.subject),scope),CARD.x+8,y+5,CARD.width-16,'left')
    g.setFont(smallFont);g.setColor(.71,.82,.79,1)
    g.printf('Key: '..clean(event.issueId)..'    Stage: '..clean(event.stage),CARD.x+8,y+29,CARD.width-16,'left')
    local position=event.x and event.z and ('X/Z '..safeNumber(event.x)..', '..safeNumber(event.z))
        or event.x and event.y and ('X/Y '..safeNumber(event.x)..', '..safeNumber(event.y)) or 'position unavailable'
    local elapsed=event.elapsed and ('stalled '..safeNumber(event.elapsed)..'s') or 'duration n/a'
    local attempt=event.attempt and ('attempt '..tostring(event.attempt)) or 'attempt n/a'
    local age=event.recordedAt and ('age '..ageText(math.max(0,now-event.recordedAt))) or 'age n/a'
    g.setColor(.68,.75,.74,1)
    g.printf(table.concat({elapsed,attempt,age,position},'  ·  '),CARD.x+8,y+53,CARD.width-16,'left')
    local yy=y+78
    for _,row in ipairs({{'Reason: ',event.reason,{.9,.93,.87,1}},
            {'Action: ',event.action,{.72,1,.86,1}},{'Detail: ',event.detail,{.79,.85,.82,1}}}) do
        local text=row[1]..clean(row[2]);local _,height=require('src.screens.typography').lines(text,CARD.width-20,14)
        g.setFont(require('src.screens.typography').get(14));g.setColor(row[3])
        g.printf(text,CARD.x+10,yy,CARD.width-20,'left');yy=yy+height+7
    end
end

local function appSummary(state,environment,g)
    local osName=love.system and love.system.getOS and love.system.getOS() or 'unknown'
    local major,minor,revision
    if love.getVersion then major,minor,revision=love.getVersion() end
    local loveVersion=major and ('%d.%d.%d'):format(major,minor or 0,revision or 0) or 'unknown'
    local fps=love.timer and love.timer.getFPS and love.timer.getFPS() or 0
    local frameMs=love.timer and love.timer.getDelta and love.timer.getDelta()*1000 or 0
    local luaMb=collectgarbage and collectgarbage('count')/1024 or 0
    local graphics={}
    if g.getStats then
        local okay,result=pcall(g.getStats)
        if okay and type(result)=='table' then graphics=result end
    end
    local scene=environment.scene or (state and state.sceneId) or 'unknown'
    local player=environment.player or {}
    local slot=environment.activeSlot and tostring(environment.activeSlot) or 'none'
    local position=('%.1f, %.1f'):format(tonumber(player.x) or 0,tonumber(player.y) or 0)
    local clock=environment.gameHours and safeNumber(environment.gameHours,'%.2f')..'h' or 'n/a'
    local pack=environment.assetPack or 'unknown'
    local textureMb=graphics.texturememory and graphics.texturememory/1048576
        or graphics.textureMemory and graphics.textureMemory/1048576
    local width,height=0,0
    if g.getDimensions then
        local okay,w,h=pcall(g.getDimensions)
        if okay then width,height=w or 0,h or 0 end
    end
    return {
        ('APP %s | %s | LÖVE %s | %s FPS | %sms | Lua %.1f MB'):format(
            clean(BuildVersion.name),clean(osName),loveVersion,tostring(fps),safeNumber(frameMs,'%.2f'),luaMb),
        ('GAME %s / %s | slot %s | XY %s | %s | assets %s'):format(
            clean(environment.screen),clean(scene),slot,position,clock,clean(pack)),
        ('RENDER %dx%d / %dx%d | draws %s/%s batched | textures %s MB | images %s | canvases %s'):format(
            width,height,Config.baseWidth,Config.baseHeight,
            tostring(graphics.drawcalls or 'n/a'),tostring(graphics.drawcallsbatched or 'n/a'),
            safeNumber(textureMb,'%.1f'),tostring(graphics.images or 'n/a'),tostring(graphics.canvases or 'n/a')),
    }
end

local function drawNetwork(g,info,y)
    info=type(info)=='table' and info or {}
    local count=tonumber(info.playerCount) or 0
    local maximum=tonumber(info.maxPlayers) or 0
    local role=clean(info.role)
    local line1=('NET %s %s %s | ready %s | slot %s | %d/%d players | peers %s | wait %s/%s | %s ch%s v%s'):format(
        clean(info.status),role,clean(info.networkKind),tostring(info.connected==true),
        tostring(info.localSlot or 'n/a'),count,maximum,tostring(info.peerCount or 0),
        tostring(info.pendingPeers or 0),tostring(info.pendingApprovals or 0),clean(info.transport),
        tostring(info.channelCount or 'n/a'),tostring(info.protocolVersion or 'n/a'))
    local ping=info.rttMs and safeNumber(info.rttMs,'%.0f')
        or role=='Host' and 'host' or 'waiting'
    local lossTotal=(tonumber(info.pingReceived) or 0)+(tonumber(info.pingLost) or 0)
    local lossPercent=lossTotal>0 and ('%.1f%%'):format((info.pingLost or 0)*100/lossTotal) or 'n/a'
    local line2=('RTT now/avg/min/max %s/%s/%s/%sms | age %s | %s/%s samples | loss %s (%s) | fail %s | wait %s'):format(
        ping,safeNumber(info.rttAverageMs,'%.0f'),safeNumber(info.rttMinMs,'%.0f'),
        safeNumber(info.rttMaxMs,'%.0f'),ageText(info.rttAgeSeconds),tostring(info.pingReceived or 0),
        tostring(info.pingSent or 0),tostring(info.pingLost or 0),lossPercent,
        tostring(info.pingSendFailures or 0),tostring(info.pendingPings or 0))
    local peerRows={}
    for _,peer in ipairs(info.peers or {}) do
        local state=peer.state and clean(peer.state) or '?'
        local rtt=peer.rttMs and safeNumber(peer.rttMs,'%.0f') or '?'
        local variance=peer.varianceMs and safeNumber(peer.varianceMs,'%.0f') or '?'
        peerRows[#peerRows+1]=clean(peer.slot)..' '..state..' '..rtt..'±'..variance..'ms'
    end
    if #peerRows==0 then peerRows[1]='No active peer links.' end
    local sync=('SYNC host/client tick %s/%s | shop rev %s/%s | pending action/work/safety %d/%d/%d | rejects %s'):format(
        tostring(info.serverTick or 'n/a'),tostring(info.lastServerTick or 'n/a'),
        tostring(info.shopRevision or 'n/a'),tostring(info.lastShopRevision or 'n/a'),
        info.pendingInteraction and 1 or 0,info.pendingWorkshop and 1 or 0,
        info.pendingSafety and 1 or 0,tostring(info.protocolRejectingPeers or 0))
    g.setColor(.83,.88,.82,1)
    g.printf(line1,124,y,712,'left')
    g.printf(line2,124,y+18,712,'left')
    g.setColor(.66,.75,.74,1)
    g.printf('LINK DETAILS · '..table.concat(peerRows,' | '),124,y+38,712,'left')
    g.printf(sync,124,y+57,712,'left')
end

local function drawButton(g,rect,label,enabled)
    local active=enabled==true
    g.setColor(active and .12 or .08,active and .17 or .11,active and .17 or .12,1)
    g.rectangle('fill',rect.x,rect.y,rect.width,rect.height,3,3)
    g.setColor(active and .90 or .42,active and .84 or .48,active and .70 or .45,1)
    g.rectangle('line',rect.x,rect.y,rect.width,rect.height,3,3)
    g.printf(label,rect.x,rect.y+5,rect.width,'center')
end

function Panel.drawOptions(state,environment,offset)
    environment=type(environment)=='table' and environment or {}
    local snapshot=Watchdog.snapshot(state)
    local items=diagnosticsItems(snapshot)
    offset=math.max(0,math.min(Panel.maxOffset(snapshot),math.floor(tonumber(offset) or 0)))
    local first=#items>0 and offset+1 or 0
    local last=math.min(#items,offset+Panel.PAGE_SIZE)
    local g=love.graphics
    font=font or require('src.screens.typography').get(14);smallFont=smallFont or require('src.screens.typography').get(12)
    local now=love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
    g.push('all');g.setShader();g.setFont(font)
    g.setColor(.92,.95,.89,1);g.print('LIVE PLAYTEST DIAGNOSTICS',116,151)
    g.setColor(.61,.69,.66,1)
    g.setFont(smallFont)
    g.print(('Session %s · private connection and player data hidden'):format(
        ageText(environment.sessionSeconds)),116,169)
    g.setColor(.045,.061,.064,.98);g.rectangle('fill',110,185,740,132,5,5)
    g.setColor(.29,.37,.36,1);g.rectangle('line',110,185,740,132,5,5)
    local rows=appSummary(state,environment,g)
    g.setFont(smallFont);g.setColor(.78,.84,.80,1)
    for index,line in ipairs(rows) do g.printf(line,124,190+(index-1)*18,712,'left') end
    drawNetwork(g,environment.multiplayer,241)
    g.setColor(.045,.061,.064,.98);g.rectangle('fill',110,321,740,282,5,5)
    g.setColor(.29,.37,.36,1);g.rectangle('line',110,321,740,282,5,5)
    g.setFont(font);g.setColor(.92,.95,.89,1)
    g.printf(('AI WATCHDOG · %d active · %d retained reports · showing %s–%s'):format(
        #snapshot.active,#snapshot.events,#items>0 and first or 0,last),124,328,712,'left')
    g.setFont(smallFont)
    if #items==0 then
        g.setColor(.72,.80,.76,1)
        g.printf('No AI stalls or recoveries have been recorded in this session.',124,372,712,'left')
    else
        for row=1,Panel.PAGE_SIZE do
            local eventIndex=offset+row
            local event=items[eventIndex]
            if event then drawEvent(g,event,350,now) end
        end
    end
    drawButton(g,NEWER,'NEWER',offset>0)
    drawButton(g,LATEST,'LATEST',offset>0)
    drawButton(g,OLDER,'OLDER',offset<Panel.maxOffset(snapshot))
    g.setFont(smallFont);g.setColor(.58,.68,.64,1)
    g.pop()
    return {snapshot=snapshot,offset=offset,maxOffset=Panel.maxOffset(snapshot)}
end

return Panel
