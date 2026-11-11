local Test={}
function Test.run(_,check)
    local Random=require('src.net.secure_random')
    local Credentials=require('src.resident_credentials')
    local oldNative,oldFfi=package.loaded['src.net.crypto_native'],package.loaded.ffi
    local oldOS,oldOpen=love.system.getOS,io.open
    local fs=love.filesystem
    local oldInfo,oldRead,oldWrite=fs.getInfo,fs.read,fs.write
    local okay,err=xpcall(function()
        love.system.getOS=function() return 'iOS' end
        package.loaded['src.net.crypto_native']={randomBytes=function()return nil end}
        package.loaded.ffi={cdef=function()end,new=function()return {} end,
            C={arc4random_buf=function(buffer,count)buffer.bytes=string.rep('a',count)end},
            string=function(buffer)return buffer.bytes end}
        local bytes,_,source=Random.bytes(32)
        check('ios_identity_uses_apple_system_random_without_game_native_library',#bytes==32 and source=='apple-system')
        package.loaded.ffi={}
        io.open=function(path)
            assert(path=='/dev/urandom')
            return {read=function(_,count)return string.rep('b',count)end,close=function()end}
        end
        bytes,_,source=Random.bytes(32)
        check('ios_identity_uses_secure_device_source_without_ffi',#bytes==32 and source=='system-device')
        local saved
        fs.getInfo=function()return saved and {} end
        fs.read=function()return saved end
        fs.write=function(_,value)saved=value;return true end
        local token=assert(Credentials.get())
        io.open=function()return nil end
        check('ios_resident_identity_is_saved_and_reused_without_regenerating',Credentials.get()==token)
        saved=nil
        check('ios_identity_refuses_insecure_random_when_all_secure_sources_fail',Credentials.get()==nil)
        io.open=function()return {read=function()return 'short'end,close=function()end} end
        check('ios_identity_rejects_short_entropy_reads',Random.bytes(32)==nil)

        local Transport=require('src.net.transport_enet')
        local calls=0
        local enet={host_create=function(endpoint)
            calls=calls+1
            if endpoint==nil then return nil,'binding needs explicit socket' end
            assert(endpoint=='*:0')
            return {connect=function(_,remote)
                assert(remote=='127.0.0.1:22122');return {}
            end,destroy=function()end}
        end}
        local transport=assert(Transport.createClient('127.0.0.1:22122',{enet=enet}))
        check('ios_enet_falls_back_to_explicit_ephemeral_socket',calls==2 and transport.compatibilityFallback)
        love.system.getOS=function()return 'Windows'end
        calls=0
        check('ios_enet_fallback_is_scoped_to_ios',Transport.createClient('127.0.0.1:22122',{enet=enet})==nil and calls==1)
    end,debug.traceback)
    package.loaded['src.net.crypto_native'],package.loaded.ffi=oldNative,oldFfi
    love.system.getOS,io.open=oldOS,oldOpen
    fs.getInfo,fs.read,fs.write=oldInfo,oldRead,oldWrite
    assert(okay,err)

    local Watchdog=require('src.ai_watchdog')
    local Session=require('src.net.session')
    local state={}
    local fail=false
    local factory={createClient=function()
        if fail then return nil,'ENet failed secret-address secret-token' end
        return {close=function()return true end}
    end,createHost=function()return {close=function()return true end}end}
    local s=Session.new({transportFactory=factory,clock=function()return 10 end,
        diagnosticState=function()return state end})
    assert(s:startClient('127.0.0.1:22122',{residentToken=string.rep('a',64)}))
    local snapshot=Watchdog.snapshot(state)
    check('connection_watchdog_tracks_client_handshake',#snapshot.active==1 and snapshot.active[1].stage=='handshake')
    s:_queue('ready',{})
    check('connection_watchdog_resolves_only_when_shop_is_ready',#Watchdog.snapshot(state).active==0)
    s:_queue('disconnected',{message='Connection timed out secret-address secret-token'})
    snapshot=Watchdog.snapshot(state)
    check('connection_watchdog_records_timeout_without_secrets',snapshot.active[1].reason=='Connection handshake timed out'
        and not snapshot.active[1].action:find('secret',1,true))
    s:stop('cancelled')
    check('connection_watchdog_clears_cancelled_attempts',#Watchdog.snapshot(state).active==0)
    fail=true
    local started=s:startClient('127.0.0.1:22122',{residentToken=string.rep('b',64)})
    check('connection_watchdog_records_synchronous_startup_failure',not started
        and Watchdog.snapshot(state).active[1].reason=='Network transport unavailable or failed')
    local before=#Watchdog.snapshot(state).events
    for i=1,200 do s:_queue('error',{message='ENet failed secret-token'}) end
    check('connection_watchdog_deduplicates_repeated_errors',#Watchdog.snapshot(state).events==before+1)
    for i=1,200 do s:connectionNote('test '..i,'RESOLVED','Lifecycle changed','Monitor connection') end
    check('connection_watchdog_history_remains_bounded',#Watchdog.snapshot(state).events==Watchdog.EVENT_LIMIT)
    factory.createClient=function()error('private startup detail')end
    local called,result,message=pcall(s.startClient,s,'127.0.0.1:22122',{residentToken=string.rep('c',64)})
    check('connection_watchdog_contains_startup_exceptions_and_cleans_session',called and not result
        and s.mode=='offline' and not s.transport and not message:find('private',1,true))
    local retry=require('src.net.lan_reconnect').new({delays={0,1}})
    local runtime={App={settings={}},Config={player={character='rabbit-worker'}},state={},
        lanReconnect=retry,lanDiscovery={stop=function()end},
        multiplayer={startClient=function()return true end,stop=function()return true end,
            connectionNote=function()end},
        clearWorkshopAuthority=function()end,WorkshopRemoteScreen={clear=function()end},
        LanScreen={showReconnect=function()end,showError=function()end},syncMobileKeyboard=function()end}
    require('src.runtime.lan_startup').install(runtime)
    require('src.runtime.lan_reconnect').install(runtime)
    runtime.startLanSearch=function()end
    assert(runtime.startLanClient('127.0.0.1:22122','Worker'))
    check('initial_lan_join_arms_bounded_recovery',runtime.lanReconnectArmed and not retry:isActive())
    runtime.handleLanReconnectFailure('Connection timed out')
    check('initial_lan_timeout_schedules_same_host_retry',retry:isActive()
        and retry:snapshot().target.address=='127.0.0.1:22122')
    local attempt=retry:update(0)
    check('lan_recovery_first_retry_is_bounded',attempt and attempt.attempt==1 and attempt.maxAttempts==2)
end
return Test
