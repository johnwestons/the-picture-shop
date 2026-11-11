return function(clips,stats,config)
    local D=require('dialogue');local Bubble=require('speech_bubble');local lines={};local checks=0
    local function check(name,okay)assert(okay,name);checks=checks+1;lines[#lines+1]='PASS '..name end
    local grandpa
    for _,character in ipairs(config.characters)do if character.id=='grandpa' then grandpa=character end end
    check('grandpa has a static dialogue preview',grandpa and grandpa.static and grandpa.image
        and grandpa.image:getWidth()>0 and grandpa.image:getHeight()>0)
    local voiceRoute=require('dialogue_voices')
    check('grandpa chosen voice routes by emotion and neutral fallback',
        voiceRoute.path({grandpa={greeting='hello.wav',neutral='talk.wav'}},'grandpa','greeting')=='hello.wav'
        and voiceRoute.path({grandpa={greeting='hello.wav',neutral='talk.wav'}},'grandpa','curious')=='talk.wav')
    for _,file in ipairs(require('syntax_checks'))do local chunk,reason=loadfile(file);check('game module parses: '..file,chunk~=nil);if not chunk then error(reason)end end
    for _,line in ipairs(D.lines) do
        local emotion=line[1];check(emotion..' selected and decoded',clips[emotion] and clips[emotion]:getDuration()>0)
        local s=stats[emotion];lines[#lines+1]=string.format('LEVEL %s duration=%.3fs peak=%.1fdBFS rms=%.1fdBFS %s',emotion,s.duration,s.peakDb,s.rmsDb,s.warning)
        check(emotion..' samples finite and within PCM range',s.valid)
    end
    local count,stops=0,0
    local fake={getDuration=function()return .8 end,setVolume=function(_,v)check('gain bounded',v>=0 and v<=1)end,play=function()count=count+1 end,stop=function()stops=stops+1 end}
    local engine=D.new(setmetatable({},{__index=function()return fake end}));engine.delay=.15
    engine:trigger(D.lines[1]);check('bubble visible immediately',engine.active~=nil and count==0)
    engine:update(.14);check('audio waits for configured delay',count==0)
    engine:update(.01);check('one voice onset',count==1)
    engine:update(.5);check('voice does not retrigger each frame',count==1)
    engine:trigger(D.lines[2]);check('interrupt stops old voice',stops==1)
    engine:stop();engine:update(1);check('cancel prevents pending playback',count==1 and not engine.active)
    engine.delay=0;engine.cps=20;engine:trigger(D.lines[1]);check('zero delay starts with bubble',count==2 and engine.events.audio==0)
    engine:update(.2);check('typewriter reveals text',#engine:text()==4)
    engine:update(20);check('bubble expires',not engine.active)
    local font=love.graphics.newFont(11);local w,h=Bubble.layout('Hello!',font);check('game bubble dimensions',w>=52 and w<=176 and h>=22)
    local oldW=Bubble.layout(string.rep('Long sentence ',20),font);check('long bubble wraps at game width',oldW==176)
    local profile=require('dialogue_profile')
    check('shared profile bounded',profile.gain>=0 and profile.gain<=1 and profile.delay>=0 and profile.delay<=.5 and profile.cps>=0 and profile.hold>=1)
    package.loaded['src.dialogue_profile']=profile
    package.loaded['assets.audio.dialogue.manifest']={['cat-worker']={greeting='greeting.wav'}}
    package.loaded['assets.audio.custom.manifest']={mix={master=.5,sfx=.8},slots={['shop-door']={gain=.5,bus='sfx',path='assets/audio/custom/not-valid.wav'}}}
    local mix=require('soundscape');package.loaded['src.soundscape']=mix
    package.loaded['src.dialogue_voices']=require('dialogue_voices')
    check('runtime mix multiplies channel and slot',math.abs(mix.gain('shop-door','sfx')-.2)<.0001)
    check('bad runtime custom path falls back',mix.path('shop-door','factory.wav')=='factory.wav')
    local presentation=require('dialogue_presentation')
    local realNewSource=love.audio.newSource;local played,level,released=0,0,0
    love.audio.newSource=function()return {setLooping=function()end,getDuration=function()return .4 end,
        setVolume=function(_,v)level=v end,play=function()played=played+1 end,stop=function()end,release=function()released=released+1 end}end
    local actor={}
    local text=presentation.present(actor,'cat-worker','Hello there!','greeting')
    check('game uses shared text reveal setting',profile.cps==0 and text=='Hello there!' or profile.cps>0 and text=='')
    for i=1,30 do presentation.update(.02,.5,true);presentation.present(actor,'cat-worker','Hello there!','greeting') end
    check('game dialogue audio plays once',played==1)
    check('game respects profile and existing volume',math.abs(level-profile.gain*.5*.4)<.0001)
    presentation.present(actor,'cat-worker','Another line','greeting');check('game dialogue interruption releases voice',released==1)
    presentation.update(.02,.5,false);check('game mute cancels pending voice',released==2)
    presentation.reset();love.audio.newSource=realNewSource
    for index,character in ipairs(config.characters)do
        if character.id=='grandpa' then
            for _=2,index do love.keypressed(']') end
            check('grandpa portrait draws in dialogue preview',pcall(love.draw))
            break
        end
    end
    lines[#lines+1]='DIALOGUE_SMOKE_OK '..checks..' checks; no game saves loaded; no test audio played'
    local f=assert(io.open(config.report,'w'));f:write(table.concat(lines,'\n'));f:close();print(table.concat(lines,'\n'))
end
