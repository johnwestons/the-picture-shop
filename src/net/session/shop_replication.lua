local R=require('src.net.shop_replication')
local Component={}
function Component.install(Runtime)
    function Runtime.Session:_rememberShopPeer(peer,state,history)
        self.shopPeers=self.shopPeers or {}
        self.shopPeers[peer]={state=R.copy(state),revision=self.shopRevision,history=R.newHistorySender()}
        self.shopHistory=history
    end

    function Runtime.Session:_sendShopChanges(state,history)
        self.shopPeers=self.shopPeers or {}
        self.shopHistory=history
        local revision=self.shopRevision+1
        local success,reason=true,nil
        local sentAny=false
        local baseline
        for _,peer in pairs(self.idToPeer) do
            local previous=self.shopPeers[peer]
            local delta=previous and R.diff(previous.state,state)
            if not previous or delta then
                local okay,err=self:_send(peer,'shop_state',{sessionId=self.sessionId,
                    revision=revision,baseRevision=previous and previous.revision,state=delta or state})
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
        if self.historyAccumulator<.05 then return end
        self.historyAccumulator=0
        local history=context and context.getShopHistory and context.getShopHistory() or self.shopHistory
        if not history then return end
        for peer,previous in pairs(self.shopPeers or {}) do
            if not self.peerToId[peer] then self.shopPeers[peer]=nil
            else
                local page,err=R.nextHistory(previous.history,history)
                if page then
                    local okay,reason=self:_send(peer,'shop_history',{sessionId=self.sessionId,
                        revision=previous.revision,collection=page.collection,start=page.start,total=page.total,
                        offset=page.offset,bytes=#page.data,data=page.data:sub(page.offset,page.offset+R.PART_BYTES-1)})
                    if okay then R.advanceHistory(previous.history) else self:_queue('error',{message=reason}) end
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
