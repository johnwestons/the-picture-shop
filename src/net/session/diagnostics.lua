-- Connection lifecycle reports share the bounded playtest watchdog. Never retain
-- packets, names, endpoints, invitation codes, or resident credentials here.
local Watchdog=require('src.ai_watchdog')
local Component={}
local function diagnosis(message)
    local text=tostring(message or ''):lower()
    if text:find('identity',1,true) then
        return 'Resident identity unavailable','Check secure random support and writable app storage'
    elseif text:find('cleanup',1,true) then
        return 'Transport cleanup could not be verified','Restart the game before creating another connection'
    elseif text:find('timed out',1,true) or text:find('timeout',1,true) then
        return 'Connection handshake timed out','Use bounded LAN reconnect; check the host and local network'
    elseif text:find('protocol',1,true) or text:find('invalid packet',1,true) then
        return 'Network protocol mismatch or invalid packet','Use matching game versions; keep packet validation enabled'
    elseif text:find('enet',1,true) or text:find('transport',1,true) then
        return 'Network transport unavailable or failed','Check runtime networking support and the host connection'
    end
    return 'Connection request could not complete','Review the connection screen; check network reachability and host availability'
end
function Component.install(Runtime)
    local Session=Runtime.Session
    local create=Session.new
    function Session.new(options)
        local self=create(options)
        self.diagnosticState=options and options.diagnosticState
        return self
    end
    function Session:connectionNote(stage,status,reason,action,id)
        local key=id or 'network:session'
        local clockOkay,now=pcall(self.clock)
        if not clockOkay or not Runtime.finite(now) then now=0 end
        self.connectionReports=self.connectionReports or {}
        local prior=self.connectionReports[key]
        local signature=stage..status..reason..action
        if prior and prior.signature==signature and now>=prior.at and now-prior.at<2 then return end
        self.connectionReports[key]={signature=signature,at=now}
        local state=self
        if type(self.diagnosticState)=='function' then
            local okay,value=pcall(self.diagnosticState)
            if okay and type(value)=='table' then state=value end
        end
        return Watchdog.note(state,key,{system='Multiplayer',subject='Connection',
            scope='network',stage=stage,status=status,reason=reason,action=action,
            attempt=self.connectionAttempt or 0})
    end
    local queue=Session._queue
    function Session:_queue(kind,values)
        local lifecycle={host_started={'hosting','RESOLVED','Host transport is listening'},
            ready={'connected','RECOVERED','Worker joined and received the shop state'},
            approval_waiting={'approval','RECOVERING','Waiting for host approval'},
            disconnected={'disconnected','STALLED'},error={'protocol','STALLED'}}
        local event=lifecycle[kind]
        if event then
            local reason,action=diagnosis(values and values.message)
            self:connectionNote(event[1],event[2],event[3] or reason,
                event[3] and 'Monitor connection lifecycle' or action)
        elseif kind=='player_joined' or kind=='player_left' or kind=='join_requested'
            or kind=='join_rejected' or kind=='join_expired' or kind=='join_cancelled' then
            -- All peer notices are historical; one pending worker must not leave
            -- a permanent active issue after a different worker joins.
            self:connectionNote(kind,'RESOLVED','Peer lifecycle: '..kind,
                'Keep the host running; preserve host admission decisions','network:peer')
        end
        return queue(self,kind,values)
    end
    for _,method in ipairs({'startHost','startClient'}) do
        local start=Session[method]
        Session[method]=function(self,...)
            self.connectionAttempt=(self.connectionAttempt or 0)+1
            local stage=method=='startHost' and 'host startup' or 'client startup'
            self:connectionNote(stage,'RECOVERING','Connection requested','Starting the supported transport')
            local okay,success,message=pcall(start,self,...)
            if not okay then
                local cleaned,stopped=pcall(self.stop,self,'Connection startup error')
                success=false
                message=cleaned and stopped and 'Network startup failed unexpectedly. Try connecting again.'
                    or 'Network cleanup could not be verified; restart the game before connecting.'
            end
            if not success then
                local reason,action=diagnosis(message)
                self:connectionNote(stage,'STALLED',reason,action)
            elseif method=='startClient' then
                self:connectionNote('handshake','RECOVERING','Transport opened; waiting for the host',
                    'Wait for validated shop state before entering multiplayer')
            end
            if success and self.transport and self.transport.compatibilityFallback then
                self:connectionNote('transport fallback','RECOVERED','Runtime needed an explicit local client socket',
                    'Opened an ephemeral socket using the same endpoint and protocol','network:transport-fallback')
            end
            return success,message
        end
    end
    local stop=Session.stop
    function Session:stop(...)
        local okay,message=stop(self,...)
        self:connectionNote('stopped',okay and 'CLEARED' or 'STALLED',
            okay and 'Connection stopped' or 'Transport cleanup could not be verified',
            okay and 'Released session resources' or 'Restart before another connection')
        return okay,message
    end
end
return Component
