local Review={}
function Review.install()
    function love.load()
        local Audio=require('src.commute.audio')
        local mixer=Audio.new()
        local checks=0
        local function check(name,ok)
            assert(ok,name);checks=checks+1;print('PASS '..name)
        end
        local bike={rpm=1400,speed=0,throttle=0,gear=1,brake=0}
        local function advance(seconds)
            for _=1,math.ceil(seconds*60) do mixer:update(1/60,bike,true) end
        end
        advance(1)
        local count=0;for _ in pairs(mixer.sources) do count=count+1 end
        check('all_original_cues_and_reused_ambience_decode',count==13 and #mixer.errors==0)
        check('idle_has_engine_and_nature_but_no_wind',mixer.sources['engine-1400']:getVolume()>.1
            and mixer.sources.nature:getVolume()>0 and mixer.sources.wind:getVolume()==0)
        bike.rpm=6500;bike.speed=11;bike.throttle=1;advance(1)
        check('rpm_crossfades_to_upper_engine_bands',mixer.sources['engine-1400']:getVolume()==0
            and mixer.sources['engine-5000']:getVolume()>.1 and mixer.sources['engine-7500']:getVolume()>.1)
        check('speed_and_throttle_drive_layers',mixer.sources.wind:getVolume()>.01 and mixer.sources.intake:getVolume()>.05)
        local open=mixer.sources['engine-5000']:getVolume()
        bike.throttle=0;advance(1)
        check('closed_throttle_reduces_exhaust',mixer.sources['engine-5000']:getVolume()<open*.65)
        bike.brake=1;advance(.1)
        check('braking_has_friction',mixer.sources.brake:getVolume()>.01)
        local cues={};local cue=mixer.cue
        function mixer:cue(name,volume) cues[#cues+1]=name;return cue(self,name,volume) end
        bike.gear=2;advance(.1)
        check('shift_cue_once',#cues==1 and cues[1]=='shift')
        bike.impactPulse=.6;advance(.1)
        check('held_collision_snapshot_does_not_repeat',#cues==2 and cues[2]=='impact')
        mixer:setMuted(true);advance(.1)
        local silent=true;for _,s in pairs(mixer.sources) do silent=silent and not s:isPlaying() end
        check('mute_stops_every_layer',silent)
        mixer:setMuted(false);advance(.1)
        check('unmute_resumes_engine_without_ignition_replay',mixer.sources['engine-5000']:isPlaying() and #cues==2)
        mixer:setPaused(true);advance(.1)
        silent=true;for _,s in pairs(mixer.sources) do silent=silent and not s:isPlaying() end
        check('focus_loss_stops_all_audio',silent)
        mixer:setPaused(false);advance(.1)
        check('focus_return_resumes_loops',mixer.sources['engine-5000']:isPlaying())
        mixer:setLevels(0,.85,.42);advance(.1)
        silent=true;for _,s in pairs(mixer.sources) do silent=silent and s:getVolume()==0 end
        check('zero_master_silences_oneshots_and_loops',silent)
        mixer:setLevels(1,.85,.42)
        bike.speed=0;bike.brake=0
        for _=1,180 do mixer:update(1/60,bike,false) end
        check('engine_shutdown_fades_out',mixer.sources['engine-5000']:getVolume()<.00001)
        local part={rider={bike={gear=2},gear={mounted=true,engine=true}},presentation={speed=6,throttle=.8,shiftTime=.1}}
        local public=Audio.partBike(part)
        check('guest_rpm_and_load_derive_from_public_presentation',public.rpm>6000 and public.throttle==.8 and public.shiftTime==.1)
        part.rider.gear.mounted=false
        check('walking_guest_cannot_rev_parked_bike',Audio.partBike(part).speed==0)
        mixer:release();check('release_clears_sources',next(mixer.sources)==nil)
        -- Exercise the production Sound adapter without loading or writing saves.
        local Sound=require('src.sound')
        local state={screen='world',home={commute={participants={owner=part}}}}
        local sound=Sound.new({state=state,world={player={}}})
        sound:syncCommuteAudio(.1)
        check('production_adapter_creates_local_mixer',sound.commuteAudio~=nil)
        sound:setMuted(true);check('production_settings_reach_mixer',sound.commuteAudio.muted)
        state.home.commute=nil;sound:syncCommuteAudio(.1)
        check('leaving_scene_releases_audio',sound.commuteAudio==nil)
        -- Existing shop sound regressions still run entirely in memory.
        require('src.tests.sound_test').run({Sound=Sound},check)
        for _,name in ipairs({'controls','motorcycle','gear','rider','trip'}) do
            require('src.commute.tests.'..name..'_test').run(check)
        end
        print('COMMUTE_AUDIO_AND_CONTROLS_OK '..checks..' checks; no saves accessed')
        love.event.quit(0)
    end
end
return Review
