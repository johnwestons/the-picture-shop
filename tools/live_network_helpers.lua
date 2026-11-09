-- Diagnostic observers and control adapters. They do not replace transport,
-- validation, authority, simulation, or App event handling.
R.liveResults={}
if not R.liveOriginalDrain then R.liveOriginalDrain=R.multiplayer.drainEvents end
R.multiplayer.drainEvents=function(session,...)
    local events=R.liveOriginalDrain(session,...)
    for _,e in ipairs(events) do
        if e.type=='workshop_result' or e.type=='workshop_grant' or e.type=='interaction_result'
            or e.type=='workshop_lost' or e.type=='disconnected' or e.type=='ready' or e.type=='error' then
            local entry={}
            for _,k in ipairs({'type','action','code','message','accepted','granted','resourceId','leaseId',
                'requestId','commandId','targetKind','playerId'}) do entry[k]=e[k] end
            R.liveResults[#R.liveResults+1]=entry
            if #R.liveResults>100 then table.remove(R.liveResults,1) end
        end
    end
    return events
end
R.liveKey=function(key)
    return R.WorkshopRemoteScreen.keypressed(key,R.state,function(a,b)
        return R.multiplayer:requestWorkshopCommand(a,b) end)
end
R.liveClick=function(x,y)
    return R.WorkshopRemoteScreen.mousepressed(R.state,x,y,1,function(a,b)
        return R.multiplayer:requestWorkshopCommand(a,b) end)
end
R.liveTab=function(name)
    local c=R.WorkshopRemoteScreen.sharedComputer
    R.liveClick(c.dropdownCenter());R.liveClick(c.tabCenter(name))
end
return {ready=R.multiplayer.ready,role=R.multiplayer:isHost() and 'host' or 'guest'}
