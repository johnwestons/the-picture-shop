-- App-private acceptance instrumentation. The real App, Session, transport,
-- authority, timers, renderer and input callbacks keep running unchanged.
return function(R,config)
    local root=R.liveEvidenceRoot
    local function json(v,depth)
        depth=(depth or 0)+1;assert(depth<50,'JSON depth')
        if v==nil then return 'null' end
        if type(v)=='boolean' then return tostring(v) end
        if type(v)=='number' then return v==v and math.abs(v)<math.huge and tostring(v) or 'null' end
        if type(v)=='string' then
            return '"'..v:gsub('[%z\1-\31\\"]',function(c)
                return ({['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'})[c]
                    or string.format('\\u%04x',c:byte())
            end)..'"'
        end
        if type(v)~='table' then return json(tostring(v),depth) end
        local parts={};local array=#v>0
        if array then for i=1,#v do parts[#parts+1]=json(v[i],depth) end
        else for k,value in pairs(v) do parts[#parts+1]=json(tostring(k),depth)..':'..json(value,depth) end end
        return (array and '[' or '{')..table.concat(parts,',')..(array and ']' or '}')
    end
    local function write(name,value)
        local f=assert(io.open(root..'/'..name,'wb'));f:write(json(value));f:close()
    end
    R.liveEvents={}
    local drain=R.multiplayer.drainEvents
    R.multiplayer.drainEvents=function(session,...)
        local events=drain(session,...)
        for _,event in ipairs(events) do
            local item={}
            for _,key in ipairs({'type','code','message','accepted','granted','resourceId','leaseId',
                'revision','commandId','requestId','playerId','sessionId','networkKind'}) do item[key]=event[key] end
            R.liveEvents[#R.liveEvents+1]=item
            if #R.liveEvents>24 then table.remove(R.liveEvents,1) end
        end
        return events
    end
    R.liveInspect=function()
        local players={}
        for id,p in pairs(R.multiplayer.players or {}) do players[#players+1]={id=id,name=p.name,
            scene=p.sceneId,x=p.x,y=p.y,residentId=p.residentId,moving=p.moving} end
        local p=R.World.player
        local lease=R.localWorkshopLease
        return {platform=love.system.getOS(),screen=R.state.screen,message=R.state.message,
            player={id=p.id,x=p.x,y=p.y,scene=p.sceneId},role=R.multiplayer:isHost() and 'host'
                or R.multiplayer:isClient() and 'guest' or 'offline',ready=R.multiplayer.ready,
            localId=R.multiplayer.localId,sessionId=R.multiplayer.sessionId,players=players,
            money=R.state.money,slot=R.state.activeSlot,lease=lease,
            home=R.state.home and {phase=R.state.home.weekend.phase,revision=R.state.home.revision},
            events=R.liveEvents}
    end
    local elapsed=0
    R.liveDevicePoll=function(dt)
        elapsed=elapsed+dt;if elapsed<.15 then return end;elapsed=0
        local f=io.open(root..'/live-command.lua','rb');if not f then return end
        local source=f:read('*a');f:close();os.remove(root..'/live-command.lua')
        local id=source:match('^%-%- id:([%w%-]+)') or 'unknown'
        local okay,result=xpcall(function()
            local chunk=assert(loadstring('return function(R)\n'..source..'\nend','live-acceptance-'..id))
            return chunk()(R)
        end,debug.traceback)
        local recorded,reason=pcall(write,'live-result.json',{id=id,okay=okay,result=result})
        if not recorded then write('live-result.json',{id=id,okay=false,result=tostring(reason)}) end
    end
    write('live-ready.json',{platform=love.system.getOS(),version=config.version,startedAt=os.time()})
end
