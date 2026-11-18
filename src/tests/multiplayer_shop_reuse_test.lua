local Test={}
function Test.run(check)
    local Session=require('src.net.session')
    local Protocol=require('src.net.protocol')
    local R=require('src.net.shop_replication')
    local originalDiff,diffs=R.diff,0
    R.diff=function(...)diffs=diffs+1;return originalDiff(...)end
    local okay,err=xpcall(function()
        local function fixture(records,options)
            options=options or {};diffs=0
            local host=Session.new();host.mode='host';host.sessionId='shop-reuse';host.shopRevision=20
            host.shopPeers={}
            local sent,encodes={},0
            local encode=host._encode
            host._encode=function(self,kind,payload)
                encodes=encodes+1
                if options.encodeFailure then return nil,'injected encoding failure' end
                return encode(self,kind,payload)
            end
            for i,record in ipairs(records) do
                local peer='guest'..i
                host.idToPeer[i+1]=peer;host.peerToId[peer]=i+1
                if record~=false then host.shopPeers[peer]=record end
            end
            host.pendingPeers.secret={}
            host.transport={send=function(_,peer,wire,channel,reliable)
                assert(channel==Protocol.CHANNEL_DURABLE and reliable)
                sent[peer]={wire=wire,payload=assert(Protocol.decode(wire)).payload}
                if options.fail==peer then return false,'injected transport failure' end
                return true
            end}
            return host,sent,function()return encodes end
        end
        local function record(state,revision,waiting)
            return {state=state,revision=revision or 20,awaitingReady=waiting,history=R.newHistorySender()}
        end
        local old={money=100,inventory={stock={paper=4}},home={revision=1}}
        local target=R.copy(old);target.money=125;target.home.revision=2
        local host,sent,encoded=fixture({record(old),record(old),record(old)})
        assert(host:_sendShopChanges(target,{}))
        check('lan_matching_shop_baselines_share_one_diff_and_encoding',diffs==1 and encoded()==1)
        local converged=true
        for i=1,3 do
            local peer='guest'..i;local payload=sent[peer].payload
            converged=converged and payload.baseRevision==20 and payload.revision==21
                and R.equal(R.apply(old,payload.state),target) and host.shopPeers[peer].revision==21
                and host.shopPeers[peer].state~=target
                and host.shopPeers[peer].state==host.shopPeers.guest1.state
        end
        check('lan_reused_shop_packet_preserves_independent_client_convergence',converged
            and sent.guest1.wire==sent.guest2.wire and sent.guest2.wire==sent.guest3.wire)
        check('lan_shop_reuse_never_sends_private_state_to_pending_sockets',sent.secret==nil)
        diffs=0;local before=encoded();assert(host:_sendShopChanges(target,{}))
        check('lan_matching_unchanged_shop_baselines_share_noop_diff',diffs==1 and encoded()==before and host.shopRevision==21)

        -- A second call must detect in-place source changes, even with the same
        -- source table and the same peer identities as the preceding call.
        target.inventory.stock.paper=8;diffs=0;before=encoded()
        assert(host:_sendShopChanges(target,{}))
        check('lan_shop_reuse_does_not_cache_mutable_source_across_calls',diffs==1 and encoded()==before+1
            and host.shopPeers.guest1.state.inventory.stock.paper==8 and host.shopRevision==22)

        local divergent=R.copy(old);divergent.money=90
        host,sent,encoded=fixture({record(old),record(divergent)})
        assert(host:_sendShopChanges(target,{}))
        check('lan_divergent_shop_baselines_receive_separate_correct_patches',diffs==2 and encoded()==2
            and R.equal(R.apply(old,sent.guest1.payload.state),target)
            and R.equal(R.apply(divergent,sent.guest2.payload.state),target))
        host,sent,encoded=fixture({record(old,19),record(old,20)})
        assert(host:_sendShopChanges(target,{}))
        check('lan_same_shop_pointer_with_different_revisions_never_reuses_wire',diffs==2 and encoded()==2
            and sent.guest1.payload.baseRevision==19 and sent.guest2.payload.baseRevision==20)
        host,sent,encoded=fixture({record(old),record(R.copy(old))})
        assert(host:_sendShopChanges(target,{}))
        check('lan_equal_distinct_shop_baselines_do_not_gain_identity_trust',diffs==2 and encoded()==2)

        host,sent,encoded=fixture({record(old),record(old),record(old)},{fail='guest1'})
        local good,reason=host:_sendShopChanges(target,{})
        check('lan_reused_shop_send_failure_does_not_block_other_peers',not good and reason=='injected transport failure'
            and encoded()==1 and diffs==1 and sent.guest2 and sent.guest3
            and host.shopPeers.guest1.state==old and host.shopPeers.guest1.revision==20
            and host.shopPeers.guest2.revision==21 and host.shopPeers.guest3.revision==21 and host.shopRevision==21)
        local delivered=host.shopPeers.guest2.state
        host.transport.send=function(_,peer,wire)
            sent[peer]={wire=wire,payload=assert(Protocol.decode(wire)).payload};return true
        end
        diffs=0;before=encoded();assert(host:_sendShopChanges(target,{}))
        check('lan_failed_shop_peer_retries_its_old_revision_without_advancing_other_peers',
            diffs==2 and encoded()==before+1 and sent.guest1.payload.baseRevision==20
            and host.shopPeers.guest1.revision==22 and host.shopPeers.guest2.revision==21
            and host.shopPeers.guest2.state==delivered)

        host,sent,encoded=fixture({record(old),record(old)},{encodeFailure=true})
        good=host:_sendShopChanges(target,{})
        check('lan_reused_shop_encoding_failure_preserves_all_peer_baselines',not good and diffs==1
            and encoded()==1 and next(sent)==nil and host.shopRevision==20
            and host.shopPeers.guest1.state==old and host.shopPeers.guest2.state==old)
        host,sent,encoded=fixture({record(old,20,true),record(old)})
        assert(host:_sendShopChanges(target,{}))
        check('lan_awaiting_shop_ready_never_consumes_reused_packet_or_baseline',diffs==1 and encoded()==1
            and sent.guest1==nil and sent.guest2~=nil and host.shopPeers.guest1.state==old
            and host.shopPeers.guest1.revision==20 and host.shopPeers.guest1.awaitingReady)
        host,sent,encoded=fixture({false,false,false})
        assert(host:_sendShopChanges(target,{}))
        check('lan_missing_shop_baselines_share_full_encoding_and_initialize_history',diffs==0 and encoded()==1
            and sent.guest1.payload.baseRevision==nil and R.equal(sent.guest1.payload.state,target)
            and host.shopPeers.guest1.history~=host.shopPeers.guest2.history)

        local records={}
        for i=1,6 do local baseline=R.copy(old);baseline.money=i
            records[#records+1]=record(baseline);records[#records+1]=record(baseline)
        end
        host,sent,encoded=fixture(records);assert(host:_sendShopChanges(target,{}))
        check('lan_shop_preparation_cache_retains_at_most_three_distinct_baselines',diffs==9 and encoded()==9)
    end,debug.traceback)
    R.diff=originalDiff
    assert(okay,err)
end
return Test
