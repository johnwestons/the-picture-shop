local Test={}
function Test.run(check)
    local R=require('src.net.shop_replication')
    local Schema=require('src.save_schema')
    local State=require('src.state')
    local Protocol=require('src.net.protocol')
    local Session=require('src.net.session')
    local source=State.new()
    source.home=require('src.home').new({town=assert(require('src.commute.town').generate(712345))})
    for i=1,5000 do
        source.bills.ledger[i]={id='invoice:'..i,total=250,source='invoice:'..i,kind='bill',title='Shop invoice '..i,
            party='Paper supplier',account='Shop',status='paid',amountCents=25000,atHours=i,
            details=string.rep('Paid supply invoice. ',20)}
    end
    source.bills.nextInvoiceId=5001
    local core,history=R.project(source)
    core=assert(Schema.snapshot(core))
    check('audit_history_projection_preserves_host_documents',#source.bills.ledger==5000
        and #core.bills.ledger==0 and Schema.validState(core))
    local host=Session.new();host.mode='host';host.sessionId='paged-audit';host.localId=1;host.ready=true
    local client=Session.new();client.mode='client';client.localId=2;client.sessionId=host.sessionId
    client.players[2]={id=2,name='Guest',character='rabbit-worker',x=1,y=1,sceneId='warehouse',
        facing=1,inputSequence=0,moving=false,resting=false,taskAction='none'}
    local guest=State.new()
    local packets,maxPage,maxPatch,historyBytes=0,0,0,0
    local failNext=false
    host.idToPeer[2]='guest';host.peerToId.guest=2
    host.transport={send=function(_,_,bytes,channel,reliable)
        if failNext then failNext=false;return false,'injected failure' end
        assert(channel==Protocol.CHANNEL_DURABLE and reliable)
        local envelope=assert(Protocol.decode(bytes))
        if envelope.type=='shop_history' then
            maxPage=math.max(maxPage,#bytes);packets=packets+1
            historyBytes=historyBytes+#bytes+R.HISTORY_PACKET_OVERHEAD
        end
        if envelope.type=='shop_state' then maxPatch=math.max(maxPatch,#bytes) end
        client:_handleClientEnvelope(envelope)
        return true
    end}
    local function applyEvents()
        for _,event in ipairs(client:drainEvents()) do
            if event.type=='ready' then
                assert(State.applySharedSnapshot(guest,event.state));State.enableSharedHistory(guest)
            elseif event.type=='shop_state' then assert(State.applySharedUpdate(guest,event.state,event.changed))
            elseif event.type=='shop_history' then assert(State.applySharedHistory(guest,event))
            else assert(event.type~='error',event.message) end
        end
    end
    local initial,err=Protocol.encode('shop_snapshot',{sessionId=host.sessionId,revision=0,state=core,player={x=1,y=1}})
    check('audit_5000_invoices_can_join_without_a_giant_snapshot',initial~=nil,err)
    assert(host:_send('guest','shop_snapshot',{sessionId=host.sessionId,revision=0,state=core,player={x=1,y=1}}))
    host:_rememberShopPeer('guest',core,history,true);applyEvents()
    local oldJobs,oldMachines=guest.jobs,guest.machines
    local nextCore=R.copy(core);nextCore.money=nextCore.money+25;nextCore.home.revision=nextCore.home.revision+1
    assert(host:_sendShopChanges(nextCore,history));host:_updateShopHistory(1);applyEvents()
    check('audit_join_does_not_queue_live_updates_or_archives_before_client_ready',
        guest.money==core.money and packets==0 and maxPatch==0)
    host.players[2]=R.copy(client.players[2]);host.players[2].lastInputSequence=-1
    host:_handleHostEnvelope('guest',{type='input',payload={sessionId=host.sessionId,
        sequence=1,moveX=0,moveY=0}}, {})
    check('audit_first_client_input_releases_coalesced_join_state',
        not host.shopPeers.guest.awaitingReady and host.shopDirty)
    assert(host:_sendShopChanges(nextCore,history));applyEvents()
    check('audit_deltas_preserve_unchanged_domains_and_apply_money',guest.money==nextCore.money
        and guest.jobs==oldJobs and guest.machines==oldMachines and maxPatch<1000)
    host.shopDirty=true
    host:_updateShopHistory(.1)
    check('audit_history_waits_for_pending_live_state_before_sending',packets==0)
    host.shopDirty=false
    local historySeconds=0
    for _=1,3200 do
        host:_updateShopHistory(.05);applyEvents();historySeconds=historySeconds+.05
        if #guest.bills.ledger==5000 then break end
    end
    check('audit_5000_invoices_arrive_in_bounded_pages',#guest.bills.ledger==5000
        and guest.bills.ledger[5000].source=='invoice:5000' and packets>100 and maxPage<=R.HISTORY_WIRE_BYTES,
        'pages='..packets..' maxBytes='..maxPage)
    check('audit_archive_wire_budget_includes_packet_overhead',
        historyBytes<=historySeconds*R.HISTORY_BYTES_PER_SECOND+R.HISTORY_WIRE_BYTES+R.HISTORY_PACKET_OVERHEAD,
        'bytes='..historyBytes..' seconds='..historySeconds)
    local changed=R.copy(nextCore);changed.money=changed.money+1
    failNext=true
    local failed=host:_sendShopChanges(changed,history)
    assert(host:_sendShopChanges(changed,history));applyEvents()
    check('audit_failed_send_retries_from_the_clients_last_baseline',not failed and guest.money==changed.money
        and #guest.bills.ledger==5000)
    source.bills.ledger[1].status='unpaid'
    source.bills.ledger[5001]=R.copy(source.bills.ledger[5000])
    source.bills.ledger[5001].id='invoice:5001';source.bills.ledger[5001].source='invoice:5001'
    source.bills.nextInvoiceId=5002
    changed=R.copy(changed);changed.bills.nextInvoiceId=5002
    assert(host:_sendShopChanges(changed,history));applyEvents()
    for _=1,400 do host:_updateShopHistory(.05);applyEvents() end
    check('audit_history_appends_and_changes_to_old_documents_sync',#guest.bills.ledger==5001
        and guest.bills.ledger[1].status=='unpaid' and guest.bills.ledger[5001].id=='invoice:5001')
    for i=5001,21,-1 do source.bills.ledger[i]=nil end
    for _=1,60 do host:_updateShopHistory(.05);applyEvents() end
    check('audit_history_truncation_removes_stale_client_rows',#guest.bills.ledger==20)
    local before=client.lastShopRevision
    client:_acceptShopState({sessionId=host.sessionId,revision=before+1,baseRevision=0,state=R.diff(core,changed)})
    check('audit_delta_with_wrong_baseline_is_rejected',client.lastShopRevision==before)
    client:drainEvents()
    local bad=Protocol.encode('shop_history',{sessionId=host.sessionId,revision=1,collection='receipts',
        start=1,total=1,offset=1,bytes=24001,data=string.rep('x',24001)})
    check('audit_history_rejects_oversized_fragments',bad==nil)
    local sender=R.newHistorySender()
    local large={receipts={{details=string.rep('x',80000)}}}
    local page=assert(R.nextHistory(sender,large))
    local chunks=0
    repeat chunks=chunks+1;R.advanceHistory(sender) until not sender.pending
    check('audit_a_large_history_record_is_fragmented_without_dropping_it',chunks==4
        and #sender.sent.receipts[1].details==80000 and #page.data>80000)
    -- A weakly compressible document exercises the adaptive wire-size limit,
    -- cached retry and whole-record assembly rather than only LZ4's easy case.
    local randomBytes,seed={},712345
    for i=1,80000 do
        seed=(seed*48271)%2147483647
        randomBytes[i]=string.char(32+seed%95)
    end
    local randomDocument=table.concat(randomBytes)
    local limitedHost=Session.new();limitedHost.mode='host';limitedHost.sessionId='budget-audit'
    limitedHost.shopDirty=false;limitedHost.idToPeer[2]='guest';limitedHost.peerToId.guest=2
    local limitedClient=Session.new();limitedClient.mode='client';limitedClient.sessionId=limitedHost.sessionId
    limitedClient.ready=true;limitedClient.lastShopRevision=0
    local attempts,wireBytes,fragments,wireMaximum={},0,0,0
    limitedHost.transport={send=function(_,_,wire)
        attempts[#attempts+1]=wire
        if #attempts==1 then return false,'injected archive failure' end
        wireBytes=wireBytes+#wire+R.HISTORY_PACKET_OVERHEAD
        wireMaximum=math.max(wireMaximum,#wire);fragments=fragments+1
        local envelope=assert(Protocol.decode(wire))
        assert(limitedClient:_acceptShopHistory(envelope.payload))
        return true
    end}
    limitedHost:_rememberShopPeer('guest',{}, {receipts={{details=randomDocument}}})
    limitedHost:_updateShopHistory(100)
    check('audit_archive_stalled_frame_does_not_emit_a_catchup_burst',#attempts==1 and fragments==0)
    local recovered,elapsed=false,0
    for _=1,1000 do
        limitedHost:_updateShopHistory(.05);elapsed=elapsed+.05
        for _,event in ipairs(limitedClient:drainEvents()) do
            if event.collection=='receipts' then recovered=event.entries[1].details==randomDocument end
        end
        if recovered then break end
    end
    check('audit_incompressible_archive_uses_small_fragments_and_reassembles_exactly',
        recovered and fragments>60 and wireMaximum<=R.HISTORY_WIRE_BYTES)
    check('audit_archive_failed_fragment_retries_same_bytes_without_advancing',attempts[1]==attempts[2])
    check('audit_archive_budget_holds_for_incompressible_documents',
        wireBytes<=elapsed*R.HISTORY_BYTES_PER_SECOND+R.HISTORY_WIRE_BYTES+R.HISTORY_PACKET_OVERHEAD)
    local oldTree={jobs={active={{id='job',pallets={{id='p1',paper={cuts={1,2,3}}}}}}}}
    local newTree=R.copy(oldTree)
    newTree.jobs.active[1].pallets[1].paper.cuts[3]=nil
    newTree.jobs.active[1].pallets[2]={id='p2',paper={cuts={1,2}}}
    local wire=assert(Protocol.encode('shop_state',{sessionId='tree',baseRevision=0,revision=1,state=R.diff(oldTree,newTree)}))
    local patched=R.apply(oldTree,assert(Protocol.decode(wire)).payload.state)
    check('audit_nested_array_growth_and_deletion_roundtrip_atomically',R.equal(newTree,patched)
        and #oldTree.jobs.active[1].pallets==1 and #oldTree.jobs.active[1].pallets[1].paper.cuts==3)
    require('src.tests.multiplayer_snapshot_refresh_test').run(check)
    require('src.tests.multiplayer_shop_reuse_test').run(check)
end
return Test
