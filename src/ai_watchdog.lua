-- Runtime-only AI progress monitoring and a bounded recovery report.
-- The session is keyed by live game state, so diagnostics never enter saves.
local Watchdog={EVENT_LIMIT=96}
local sessions=setmetatable({},{__mode='k'})

local function session(state)
    if type(state)~='table' then return nil end
    local value=sessions[state]
    if not value then
        value={nextSequence=0,events={},active={},monitors=setmetatable({},{__mode='k'})}
        sessions[state]=value
    end
    return value
end

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end

local function safeString(value)
    local okay,result=pcall(tostring,value)
    local text=okay and result or '<error value could not be formatted>'
    return text:sub(1,4096)
end

local function pack(...)
    return {n=select('#',...),...}
end

local unpackValues=table.unpack or unpack

local function monotonicNow()
    if love and love.timer and love.timer.getTime then
        local okay,value=pcall(love.timer.getTime)
        if okay and finite(value) then return value end
    end
    return os.clock()
end

function Watchdog.note(state,issueId,details)
    local current=session(state)
    if not current then return nil end
    details=type(details)=='table' and details or {}
    issueId=safeString(issueId or details.issueId or 'ai:unknown')
    current.nextSequence=current.nextSequence+1
    local event={sequence=current.nextSequence,issueId=issueId,
        status=safeString(details.status or 'STALLED'):upper(),
        system=safeString(details.system or 'AI'),subject=safeString(details.subject or 'Autonomous actor'),
        stage=safeString(details.stage or 'unknown stage'),reason=safeString(details.reason or 'Progress stopped'),
        scope=safeString(details.scope or 'world'),
        action=safeString(details.action or 'No automatic recovery available'),
        detail=details.detail and safeString(details.detail) or nil,
        elapsed=finite(details.elapsed) and math.max(0,details.elapsed) or nil,
        attempt=finite(details.attempt) and math.max(0,math.floor(details.attempt)) or nil,
        recordedAt=monotonicNow(),
        x=finite(details.x) and details.x or nil,y=finite(details.y) and details.y or nil,
        z=finite(details.z) and details.z or nil,
        visible=details.visible~=false}
    current.events[#current.events+1]=event
    if #current.events>Watchdog.EVENT_LIMIT then table.remove(current.events,1) end
    if event.status=='RESOLVED' or event.status=='RECOVERED' or event.status=='CLEARED' then
        current.active[issueId]=nil
    else
        current.active[issueId]=event
    end
    return event
end

function Watchdog.resolve(state,issueId,details)
    local current=session(state)
    issueId=tostring(issueId or '')
    local prior=current and current.active[issueId]
    if not prior then return false end
    details=type(details)=='table' and details or {}
    local visible=details.visible
    if visible==nil then visible=prior.visible end
    Watchdog.note(state,issueId,{status='RESOLVED',system=details.system or prior.system,
        subject=details.subject or prior.subject,stage=details.stage or prior.stage,
        reason=details.reason or 'Progress resumed',scope=details.scope or prior.scope,
        action=details.action or prior.action,
        detail=details.detail,x=details.x or prior.x,y=details.y or prior.y,z=details.z or prior.z,
        attempt=details.attempt or prior.attempt,
        visible=visible})
    return true
end

-- Protect a small AI operation whose owner can provide a domain-safe fallback.
-- This catches Lua failures at actor boundaries without hiding them: every
-- failure is still recorded for the playtest diagnostics page.
function Watchdog.protect(state,issueId,details,operation,recover)
    details=type(details)=='table' and details or {}
    if type(operation)~='function' then
        return false,'AI operation is unavailable',false
    end
    local function traceback(err)
        local message=safeString(err)
        if debug and type(debug.traceback)=='function' then
            local okay,result=pcall(debug.traceback,message,2)
            if okay then return safeString(result) end
        end
        return message
    end
    local result=pack(xpcall(operation,traceback))
    local id=issueId or details.issueId or 'ai:unknown'
    if result[1] then
        Watchdog.resolve(state,id,{system=details.system,subject=details.subject,stage=details.stage,
            scope=details.scope,x=details.x,y=details.y,z=details.z,visible=details.visible,
            reason='AI operation completed after an earlier error',
            action='Resumed the AI operation'})
        return true,unpackValues(result,2,result.n)
    end

    local operationError=safeString(result[2])
    local recovery
    if type(recover)=='function' then
        local okay,value=pcall(recover,operationError)
        if okay and type(value)=='table' then
            recovery=value
        elseif not okay then
            recovery={ok=false,action='Recovery callback failed',detail=safeString(value)}
        else
            recovery={ok=false,action='No safe recovery point found'}
        end
    else
        recovery={ok=false,action='No automatic recovery configured'}
    end
    local detail='Operation error: '..operationError
    if recovery.detail then detail=detail..'\nRecovery detail: '..safeString(recovery.detail) end
    Watchdog.note(state,id,{status=recovery.ok and 'RECOVERED' or 'STALLED',
        system=details.system,subject=details.subject,stage=details.stage,
        reason='AI operation raised an error',scope=details.scope,
        action=recovery.action or (recovery.ok and 'Applied an automatic recovery' or 'No automatic recovery available'),
        detail=detail,attempt=1,x=details.x,y=details.y,z=details.z,visible=details.visible})
    return false,operationError,recovery.ok==true
end

function Watchdog.clear(state,key,reason)
    if key==nil then return false end
    local current=session(state)
    local monitor=current and current.monitors[key]
    if not monitor then return false end
    Watchdog.resolve(state,monitor.issueId,{reason=reason or 'Movement completed'})
    current.monitors[key]=nil
    return true
end

-- Monitor an explicit workflow stage using actual progress supplied by its owner.
-- Recovery stays local to that AI system, which knows what positions or queue
-- transitions are safe. The watchdog records the attempt and watches for resume.
function Watchdog.observe(state,key,options)
    if key==nil or type(options)~='table' then return false end
    local current=session(state)
    if not current then return false end
    local dt=finite(options.dt) and math.max(0,options.dt) or 0
    local stage=tostring(options.stage or 'unknown stage')
    local monitor=current.monitors[key]
    if not monitor or monitor.stage~=stage then
        if monitor then Watchdog.resolve(state,monitor.issueId,{reason='AI advanced to another stage'}) end
        monitor={stage=stage,elapsed=0,retry=0,attempts=0,
            issueId=tostring(options.issueId or ('ai:'..tostring(options.system or 'actor')..':'..tostring(key)))}
        current.monitors[key]=monitor
    end
    monitor.retry=math.max(0,monitor.retry-dt)
    if options.progressed then
        if current.active[monitor.issueId] then Watchdog.resolve(state,monitor.issueId,{reason='Progress resumed',
            system=options.system,subject=options.subject,stage=monitor.stage,
            scope=options.scope,x=options.x,y=options.y,z=options.z,visible=options.visible}) end
        monitor.elapsed=0;monitor.attempts=0
        return false
    end
    monitor.elapsed=monitor.elapsed+dt
    local timeout=finite(options.timeout) and math.max(.1,options.timeout) or 10
    if monitor.elapsed<timeout or monitor.retry>0 then return false end
    monitor.attempts=monitor.attempts+1
    local recovery
    if type(options.recover)=='function' then
        local okay,result=pcall(options.recover,monitor.attempts)
        if okay and type(result)=='table' then recovery=result
        elseif not okay then recovery={ok=false,action='Recovery callback failed',detail=tostring(result)}
        else recovery={ok=false,action='No safe recovery point found'} end
    else
        recovery={ok=false,action='No automatic recovery configured'}
    end
    Watchdog.note(state,monitor.issueId,{status=recovery.ok and 'RECOVERING' or 'STALLED',
        system=options.system,subject=options.subject,stage=monitor.stage,
        reason=options.reason or 'No measurable progress',scope=options.scope,action=recovery.action,
        detail=recovery.detail or ('Recovery attempt '..monitor.attempts),elapsed=monitor.elapsed,
        attempt=monitor.attempts,
        x=options.x,y=options.y,z=options.z,visible=options.visible})
    monitor.elapsed=0
    monitor.retry=finite(options.retryDelay) and math.max(0,options.retryDelay) or timeout
    return recovery.ok==true
end

function Watchdog.snapshot(state)
    local current=session(state)
    local result={events={},active={}}
    if not current then return result end
    local function copyEvent(event)
        return {sequence=event.sequence,issueId=event.issueId,status=event.status,system=event.system,
            subject=event.subject,stage=event.stage,reason=event.reason,scope=event.scope,
            action=event.action,detail=event.detail,
            elapsed=event.elapsed,attempt=event.attempt,recordedAt=event.recordedAt,
            x=event.x,y=event.y,z=event.z,visible=event.visible}
    end
    for index=1,#current.events do
        result.events[#result.events+1]=copyEvent(current.events[index])
    end
    for _,event in pairs(current.active) do result.active[#result.active+1]=copyEvent(event) end
    table.sort(result.active,function(a,b)return a.sequence>b.sequence end)
    return result
end

function Watchdog.reset(state)
    if type(state)~='table' then return false end
    sessions[state]=nil
    return true
end

return Watchdog
