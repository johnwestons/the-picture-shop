-- Auxiliary state is repeated for loss recovery, but an idle machine or empty
-- game table does not need the same bandwidth as a moving player. This cache
-- only remembers successful sends; every peer still gets its own baseline.
local R=require('src.net.shop_replication')
local Refresh={INTERVAL=1,MAX_ENTRIES=128}
local kinds={hockey_snapshot=true,fight_snapshot=true,crisis_snapshot=true,
    visitor_snapshot=true,environment_snapshot=true,employee_snapshot=true,
    extra_pallet_jack_snapshot=true,pallet_jack_snapshot=true,forklift_snapshot=true,
    cutter_snapshot=true,windmill_snapshot=true,wrapper_snapshot=true,workshop_snapshot=true}

local function ignored(kind,key)
    return key=='serverTick' or (kind=='workshop_snapshot' and key=='revision')
end
local visitorClocks={animationClock=true,idleClock=true,waitTimer=true,arrivalTimer=true}
local runtimeSequence={runtimeRevision=true}
local function sameExcept(a,b,ignoredFields)
    if type(a)~='table'or type(b)~='table'then return a==b end
    for key,value in pairs(a)do
        if not ignoredFields[key]and not R.equal(value,b[key])then return false end
    end
    for key in pairs(b)do
        if not ignoredFields[key]and a[key]==nil then return false end
    end
    return true
end
local function same(kind,a,b)
    for key,value in pairs(a) do
        if not ignored(kind,key)then
            local equal
            if kind=='visitor_snapshot'and(key=='customer'or key=='vendor')then
                equal=sameExcept(value,b[key],visitorClocks)
            elseif (kind=='cutter_snapshot'or kind=='windmill_snapshot')and key=='view'then
                -- Runtime revisions advance even when a machine's visible state
                -- is unchanged. Keep the latest sequence in periodic refreshes;
                -- phase, safety and the outer resourceRevision still send now.
                equal=sameExcept(value,b[key],runtimeSequence)
            else equal=R.equal(value,b[key])end
            if not equal then return false end
        end
    end
    for key in pairs(b) do
        if not ignored(kind,key) and a[key]==nil then return false end
    end
    return true
end
function Refresh.key(kind,payload)
    if not kinds[kind] then return nil end
    return kind..':'..tostring(payload.resourceId or payload.bayId or payload.jackId or '')
end
function Refresh.prune(session)
    if session.snapshotRefreshSession~=session.sessionId then
        session.snapshotRefresh={}
        session.snapshotRefreshSession=session.sessionId
    end
    for peer in pairs(session.snapshotRefresh or {}) do
        if not session.peerToId[peer] then session.snapshotRefresh[peer]=nil end
    end
end
function Refresh.forget(session,peer)
    if session.snapshotRefresh then session.snapshotRefresh[peer]=nil end
end
function Refresh.due(session,peer,key,kind,payload,now)
    if not key then return true end
    local cache=session.snapshotRefresh and session.snapshotRefresh[peer]
    local previous=cache and cache.entries[key]
    return not previous or now<previous.at or now-previous.at>=Refresh.INTERVAL-1e-9
        or not same(kind,payload,previous.payload)
end
function Refresh.remember(session,peer,key,payload,now)
    if not key then return end
    session.snapshotRefresh=session.snapshotRefresh or {}
    local cache=session.snapshotRefresh[peer]
    if not cache then cache={entries={},order={}};session.snapshotRefresh[peer]=cache end
    if not cache.entries[key] then
        if #cache.order>=Refresh.MAX_ENTRIES then
            cache.entries[table.remove(cache.order,1)]=nil
        end
        cache.order[#cache.order+1]=key
    end
    cache.entries[key]={payload=R.copy(payload),at=now}
end
return Refresh
