local R=require('src.net.shop_replication')
local Component={}
local function historyFragment(session,page,revision)
    local count=math.min(R.PART_BYTES,#page.data-page.offset+1)
    while count>=1 do
        local encoded,err=session:_encode('shop_history',{sessionId=session.sessionId,
            revision=revision,collection=page.collection,start=page.start,total=page.total,
            offset=page.offset,bytes=#page.data,data=page.data:sub(page.offset,page.offset+count-1)})
        if not encoded then return nil,err end
        if #encoded<=R.HISTORY_WIRE_BYTES then return {encoded=encoded,bytes=count} end
        count=math.floor(count/2)
    end
    return nil,'History fragment exceeds the network budget.'
end
function Component.install(Runtime)
    function Runtime.Session:_rememberShopPeer(peer,state,history,awaitingReady)
        self.shopPeers=self.shopPeers or {}
        self.shopPeers[peer]={state=R.copy(state),revision=self.shopRevision,history=R.newHistorySender(),
            awaitingReady=awaitingReady==true}
        require('src.net.snapshot_refresh').forget(self,peer)
        self.shopHistory=history
    end

    function Runtime.Session:_sendShopChanges(state,history)
        self.shopPeers=self.shopPeers or {}
        self.shopHistory=history
        local revision=self.shopRevision+1
        local success,reason=true,nil
        local sentAny=false
        local baseline
        -- Peers that accepted the same update share its private baseline. Reuse
        -- diff/encoding only within this call and only for that exact revision.
        -- Diverged/retrying peers keep their own patch; no mutable source is
        -- trusted across calls, and even an unexpected peer count stays bounded.
        local prepared={}
        local function prepare(previous)
            local old=previous and previous.state
            local baseRevision=previous and previous.revision
            for _,entry in ipairs(prepared) do
                if rawequal(entry.state,old) and entry.revision==baseRevision then return entry end
            end
            local delta=previous and R.diff(old,state)
            local entry={state=old,revision=baseRevision,changed=not previous or delta~=nil}
            if entry.changed then
                entry.encoded,entry.error=self:_encode('shop_state',{sessionId=self.sessionId,
                    revision=revision,baseRevision=baseRevision,state=delta or state})
            end
            if #prepared<3 then prepared[#prepared+1]=entry end
            return entry
        end
        for _,peer in pairs(self.idToPeer) do
            local previous=self.shopPeers[peer]
            local entry=(not previous or not previous.awaitingReady) and prepare(previous)
            if entry and entry.changed then
                local okay,err=false,entry.error
                if entry.encoded then
                    local channel,reliable=self:_route('shop_state')
                    okay,err=self.transport:send(peer,entry.encoded,channel,reliable)
                end
                if okay then
                    if not previous then self:_rememberShopPeer(peer,state,history);previous=self.shopPeers[peer] end
                    baseline=baseline or R.copy(state)
                    previous.state,previous.revision=baseline,revision
                    sentAny=true
                else success,reason=false,err end
            end
        end
        if sentAny then self.shopRevision=revision end
        return success,reason
    end

    function Runtime.Session:_updateShopHistory(dt,context)
        -- New records may refer to counters or jobs in the pending live update.
        -- Deliver that revision first, including when a peer's send must retry.
        if self.shopDirty then return end
        self.historyAccumulator=(self.historyAccumulator or 0)+dt
        if self.historyAccumulator<R.HISTORY_INTERVAL then return end
        -- Never catch up a stalled frame with a burst of reliable fragments.
        local elapsed=self.historyAccumulator
        self.historyAccumulator=0
        local history=context and context.getShopHistory and context.getShopHistory() or self.shopHistory
        if not history then return end
        for peer,previous in pairs(self.shopPeers or {}) do
            if not self.peerToId[peer] then self.shopPeers[peer]=nil
            elseif not previous.awaitingReady then
                previous.historyTokens=math.min(R.HISTORY_WIRE_BYTES+R.HISTORY_PACKET_OVERHEAD,
                    (previous.historyTokens or 0)+elapsed*R.HISTORY_BYTES_PER_SECOND)
                local page,err=R.nextHistory(previous.history,history)
                if page then
                    local fragment,reason=previous.historyFragment
                    if not fragment then fragment,reason=historyFragment(self,page,previous.revision) end
                    previous.historyFragment=fragment
                    if not fragment then self:_queue('error',{message=reason})
                    elseif previous.historyTokens>=#fragment.encoded+R.HISTORY_PACKET_OVERHEAD then
                        local channel,reliable=self:_route('shop_history')
                        local okay,sendError=self.transport:send(peer,fragment.encoded,channel,reliable)
                        if okay then
                            previous.historyTokens=previous.historyTokens-#fragment.encoded-R.HISTORY_PACKET_OVERHEAD
                            R.advanceHistory(previous.history,fragment.bytes)
                            previous.historyFragment=nil
                        else self:_queue('error',{message=sendError}) end
                    end
                elseif err then self:_queue('error',{message=err}) end
            end
        end
    end

    function Runtime.Session:_acceptShopHistory(payload)
        if payload.sessionId~=self.sessionId or not self.ready then return false end
        if payload.revision>self.lastShopRevision then return false end
        local assembly=self.historyAssembly
        if payload.offset==1 then
            assembly={collection=payload.collection,start=payload.start,total=payload.total,
                bytes=payload.bytes,nextOffset=1,parts={}}
            self.historyAssembly=assembly
        end
        if not assembly or assembly.collection~=payload.collection or assembly.start~=payload.start
            or assembly.total~=payload.total or assembly.bytes~=payload.bytes or assembly.nextOffset~=payload.offset then return false end
        assembly.parts[#assembly.parts+1]=payload.data
        assembly.nextOffset=assembly.nextOffset+#payload.data
        if assembly.nextOffset<=assembly.bytes then return true end
        self.historyAssembly=nil
        local entries=Runtime.Codec.decode(table.concat(assembly.parts),R.limits)
        if type(entries)~='table' or #entries>R.PAGE_ROWS or payload.start+#entries-1>payload.total then return false end
        local count=0;for k in pairs(entries) do
            if type(k)~='number' or k%1~=0 or k<1 or k>#entries then return false end
            count=count+1
        end
        if count~=#entries then return false end
        self:_queue('shop_history',{collection=payload.collection,start=payload.start,total=payload.total,entries=entries,
            baseline=self.receivedShop})
        return true
    end
end
return Component
