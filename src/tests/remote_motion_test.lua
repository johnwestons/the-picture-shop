local Test={}
local Session=require('src.net.session')
local function scenario(check,scene,speed,slowHost)
    local now=0
    local client=Session.new({clock=function()return now end})
    client.mode='client';client.ready=true;client.localId=2;client.sessionId='motion-buffer'
    local waiting={}
    local variance,measured,maxSpeed=0,0,0
    local previous
    for frame=1,1200 do
        now=frame/60
        if frame%(slowHost and 10 or 5)==0 and frame<=1050 then
            local tick=frame/5
            if tick%13~=0 then
                waiting[#waiting+1]={at=now+.08+({.02,.10,.03,.12,0,.06})[tick%6+1],tick=tick,
                    x=100+speed*now}
            end
        end
        local index=1
        while index<=#waiting do
            local item=waiting[index]
            if item.at<=now then
                table.remove(waiting,index)
                client:_applySnapshot({sessionId=client.sessionId,serverTick=item.tick,players={{id=1,
                    sceneId=scene,x=item.x,y=100,velocityX=speed,velocityY=0,moving=true,intentX=1,intentY=0}}})
            else index=index+1 end
        end
        client:_updateClientVisuals(1/60,{})
        local p=client.players[1]
        if p and previous and frame>180 and frame<1020 then
            local observed=(p.x-previous)*60
            variance=variance+(observed/speed-1)^2;measured=measured+1
            maxSpeed=math.max(maxSpeed,observed/speed)
        end
        previous=p and p.x
    end
    local p=client.players[1]
    local rms=math.sqrt(variance/measured)
    local label='remote_'..scene..(slowHost and '_slow_host' or '')
    check(label..'_jitter_does_not_pulse_constant_speed',rms<(slowHost and .3 or .15) and maxSpeed<2,
        ('relative speed RMS=%.5f peak=%.5f'):format(rms,maxSpeed))
    check(label..'_outage_stops_bounded_extrapolation',
        p.x<=100+speed*17.5+speed*.13 and p.x>=100+speed*17,
        'position='..p.x)
    check(label..'_snapshot_history_is_bounded',not p._motionBuffer or #p._motionBuffer.samples<=24)
    client:_applySnapshot({sessionId=client.sessionId,serverTick=1000,players={{id=1,
        sceneId='home',x=50,y=75,velocityX=0,velocityY=0,moving=false}}})
    client:_updateClientVisuals(1/60,{})
    check(label..'_scene_transition_does_not_replay_old_positions',p.x==50 and p.y==75 and p.sceneId=='home')
end
local function adaptiveScenario(check)
    local now=0
    local client=Session.new({clock=function()return now end})
    client.mode='client';client.ready=true;client.localId=2;client.sessionId='adaptive-motion-buffer'
    local waiting,sendBudget,sent={},0,0
    local previous,squared,measured,peak,maxSamples=nil,0,0,0,0
    local stoppedAt
    local speed,stopAt=5,55
    for frame=1,3600 do
        now=frame/60
        -- The timestamp clock stays at 12 Hz. During congestion only two of
        -- every three base ticks emit, then normal cadence resumes. A separate
        -- 125ms clock would mislabel the alternating positions by half a tick.
        local hz=now>=15 and now<35 and 8 or 12
        if frame%5==0 then
            sendBudget=sendBudget+1/12
            if sendBudget>=1/hz-1e-8 then
                sendBudget=sendBudget-1/hz;sent=sent+1
                if sent%13~=0 then
                    waiting[#waiting+1]={at=now+.08+({.02,.10,.03,.12,0,.06})[sent%6+1],
                        tick=frame/5,x=100+speed*math.min(now,stopAt),vx=now<stopAt and speed or 0}
                end
            end
        end
        local index=1
        while index<=#waiting do
            local item=waiting[index]
            if item.at<=now then
                table.remove(waiting,index)
                client:_applySnapshot({sessionId=client.sessionId,serverTick=item.tick,players={{id=1,
                    sceneId='commute',x=item.x,y=100,velocityX=item.vx,velocityY=0,
                    moving=item.vx~=0,intentX=1,intentY=0}}})
            else index=index+1 end
        end
        client:_updateClientVisuals(1/60,{})
        local player=client.players[1]
        if player then
            maxSamples=math.max(maxSamples,player._motionBuffer and #player._motionBuffer.samples or 0)
            if previous and now>8 and now<54 then
                local ratio=(player.x-previous)*60/speed
                squared=squared+(ratio-1)^2;measured=measured+1;peak=math.max(peak,ratio)
            end
            if now>stopAt and not stoppedAt and math.abs(player.x-(100+speed*stopAt))<1e-7 then stoppedAt=now end
            previous=player.x
        end
    end
    local rms=math.sqrt(squared/measured)
    check('remote_commute_adaptive_eight_hz_survives_jitter_loss_and_rate_changes',rms<.05 and peak<1.15,
        ('relative speed RMS=%.5f peak=%.5f'):format(rms,peak))
    check('remote_commute_adaptive_eight_hz_history_remains_bounded',maxSamples<=24,
        'maximum retained samples='..maxSamples)
    check('remote_commute_adaptive_eight_hz_stop_converges_without_drift',
        stoppedAt and stoppedAt-stopAt<.5 and math.abs(client.players[1].x-(100+speed*stopAt))<1e-7)
end
function Test.run(check)
    scenario(check,'warehouse',60)
    scenario(check,'commute',5)
    scenario(check,'warehouse',60,true)
    adaptiveScenario(check)
    local now=0
    local host=Session.new({clock=function()return now end})
    host.mode='host';host.ready=true;host.localId=1;host.sessionId='slow-host'
    host:_installRoster({{id=1,x=100,y=100}},0);host.idToPeer[2]='peer'
    host.transport={send=function()return true end}
    for i=1,30 do now=i*.2;host:_updateHost(.2,{localPlayer=host.players[1]})end
    check('remote_snapshot_clock_tracks_sustained_host_stalls',host.serverTick==72,'tick='..host.serverTick)
end
return Test
