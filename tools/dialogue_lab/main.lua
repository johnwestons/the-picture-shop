local D=require('dialogue');local Bubble=require('speech_bubble');local VoiceRouting=require('dialogue_voices');local config=require('chosen')
local clipsByProfile,statsByProfile,buttons={},{},{}
local engine,player,font,small,bubbleFont,heading
local px,py=300,410;local nx,ny=540,330;local selected=1;local characterIndex=1;local sequence=false;local gap=0;local elapsed=0
local profile=require('dialogue_profile')
local gain=profile.gain;local delay=profile.delay;local cps=profile.cps;local hold=profile.hold;local scale=1;local ox,oy=0,0
local activeClips,activeStats,activeProfile,fallbacks={},{},nil,{}
local sharedVoiceProfiles={['cat-worker']=true,['mechanic-raccoon']=true,['business-dragon']=true,['medic-fox-worker']=true}
local activeTakeCount=0
local saveStatus='Shared profile loaded from project.'
local function saveProfile()
    local text=string.format('-- Saved from the Dialogue Lab; shared by all characters.\nreturn {gain=%.3f,delay=%.3f,cps=%d,hold=%.2f}\n',gain,delay,cps,hold)
    local file,err=io.open(config.profilePath,'w')
    if not file then saveStatus='Save failed: '..tostring(err);return end
    local okay,reason=file:write(text);file:close()
    saveStatus=okay and 'Saved for ALL characters. Restart the game to apply.' or 'Save failed: '..tostring(reason)
end
local function db(v)return v>0 and 20*math.log(v)/math.log(10) or -120 end
local function character()return config.characters[characterIndex]end
local function routedVoiceName(item)
    if not activeProfile then return item.id=='tinker-fox-worker'and'Individual voice only'or'No selected voice'end
    local name=config.voiceNames[activeProfile]or activeProfile
    if activeProfile==item.id then
        return sharedVoiceProfiles[activeProfile]and(name..' (voice profile)')or(item.name..' (individual)')
    end
    return sharedVoiceProfiles[activeProfile]and(name..' (shared)')or name
end
local function useCharacter(index)
    characterIndex=(index-1)%#config.characters+1;selected=1;sequence=false;gap=0
    if engine then engine:stop()end
    local current=character();activeProfile=VoiceRouting.resolve(config.voices,current.id)
    local chosen=activeProfile and clipsByProfile[activeProfile]or nil
    local profileStats=activeProfile and statsByProfile[activeProfile]or nil
    activeTakeCount=0;for _ in pairs(chosen or{})do activeTakeCount=activeTakeCount+1 end
    activeClips,activeStats,fallbacks={},{},{}
    for _,line in ipairs(D.lines)do
        local emotion=line[1];local fallback=chosen and not chosen[emotion] and chosen.neutral~=nil
        local key=fallback and 'neutral'or emotion
        if chosen and chosen[key]then
            activeClips[emotion]=chosen[key];activeStats[emotion]=profileStats[key];fallbacks[emotion]=fallback
        end
    end
    if engine then engine.clips=activeClips end
end
local function trigger(i)
    selected=i;engine.gain=gain;engine.delay=delay;engine.cps=cps;engine.hold=hold;engine:trigger(D.lines[i])
end
local function button(label,x,y,w,fn,active)
    buttons[#buttons+1]={x=x,y=y,w=w,h=32,fn=fn}
    love.graphics.setColor(active and .38 or .16,active and .43 or .24,active and .29 or .23)
    love.graphics.rectangle('fill',x,y,w,32,5,5);love.graphics.setColor(.93,.93,.85)
    love.graphics.setFont(small);love.graphics.printf(label,x+4,y+8,w-8,'center')
end
local function row(label,value,y,minus,plus)
    love.graphics.setFont(small);love.graphics.setColor(.77,.83,.77);love.graphics.print(label,850,y+8)
    button('-',1030,y,32,minus);love.graphics.printf(value,1066,y+8,65,'center');button('+',1138,y,32,plus)
end
function love.load()
    love.graphics.setDefaultFilter('nearest','nearest')
    font=love.graphics.newFont(17);small=love.graphics.newFont(13);heading=love.graphics.newFont(27);bubbleFont=love.graphics.newFont(11)
    player=love.graphics.newImage('player.png')
    for _,item in ipairs(config.characters)do
        item.image=love.graphics.newImage(item.sprite)
    end
    for profileId,entries in pairs(config.voices)do
        clipsByProfile[profileId]={};statsByProfile[profileId]={}
        for emotion,entry in pairs(entries)do
            local data=love.sound.newSoundData(entry.file);local peak,sum,valid=0,0,true
            for i=0,data:getSampleCount()-1 do local s=data:getSample(i);peak=math.max(peak,math.abs(s));sum=sum+s*s;if s~=s or math.abs(s)>1 then valid=false end end
            local rms=math.sqrt(sum/math.max(1,data:getSampleCount()))
            statsByProfile[profileId][emotion]={peak=peak,peakDb=db(peak),rmsDb=db(rms),duration=data:getDuration(),valid=valid,warning=peak>=.99 and 'HOT: near full scale' or rms<.01 and 'QUIET: check audibility' or 'Level within review range'}
            clipsByProfile[profileId][emotion]=love.audio.newSource(data,'static')
        end
    end
    engine=D.new({});useCharacter(1)
    if os.getenv('PICTURE_SHOP_DIALOGUE_SMOKE')=='1' then
        local catClips,catStats=clipsByProfile['cat-worker']or{},statsByProfile['cat-worker']or{}
        local ok,err=pcall(require('smoke'),catClips,catStats,config)
        if not ok then local f=io.open(config.report,'w');if f then f:write('FAIL '..tostring(err));f:close()end;print(err)end
        love.event.quit(ok and 0 or 1)
    end
end
function love.update(dt)
    elapsed=elapsed+dt;engine:update(dt)
    local dx=(love.keyboard.isDown('d','right') and 1 or 0)-(love.keyboard.isDown('a','left') and 1 or 0)
    local dy=(love.keyboard.isDown('s','down') and 1 or 0)-(love.keyboard.isDown('w','up') and 1 or 0)
    local length=math.sqrt(dx*dx+dy*dy);if length>0 then px=math.max(80,math.min(750,px+dx/length*150*dt));py=math.max(260,math.min(460,py+dy/length*150*dt))end
    if sequence and not engine.active then gap=gap+dt;if gap>.7 then gap=0;if selected<#D.lines then trigger(selected+1)else sequence=false end end end
end
function love.keypressed(key)
    if key=='escape' then sequence=false;engine:stop()
    elseif key=='[' then useCharacter(characterIndex-1)
    elseif key==']' then useCharacter(characterIndex+1)
    elseif key=='e' and (px-nx)^2+(py-ny)^2<150^2 then sequence=false;trigger(selected)
    elseif key=='space' then sequence=false;trigger(selected)
    elseif key=='tab' then selected=selected%#D.lines+1
    elseif key=='m' then gain=gain>0 and 0 or .35;if engine.source then engine.source:setVolume(gain)end
    end
end
function love.focus(focus)if not focus then sequence=false;engine:stop()end end
function love.mousepressed(x,y,b)
    if b~=1 then return end;x=(x-ox)/scale;y=(y-oy)/scale
    for _,v in ipairs(buttons)do if x>=v.x and x<=v.x+v.w and y>=v.y and y<=v.y+v.h then v.fn();break end end
end
local function sprite(image,x,y,anchorX,anchorY,size,static)
    if static then
        local width,height=image:getDimensions()
        local scale=190/height
        love.graphics.setColor(1,1,1)
        love.graphics.draw(image,x,y,0,scale,scale,width*.5,height*.94)
        return
    end
    local frame=math.floor(elapsed*.65)%2;local frameSize=image:getHeight()
    local q=love.graphics.newQuad(frame*frameSize,0,frameSize,frameSize,image:getDimensions())
    love.graphics.setColor(1,1,1);love.graphics.draw(image,q,x,y,0,size,size,anchorX,anchorY)
end
local function routeDescription(item)
    if activeProfile then
        return string.format('Voice route: %s  |  %d of %d emotion takes selected',routedVoiceName(item),activeTakeCount,#D.lines)
    elseif item.id=='tinker-fox-worker'then
        return 'Voice route: individual voice only  |  no Tinker Fox takes selected'
    end
    return 'Voice route: no selected profile  |  dialogue previews as text only'
end
function love.draw()
    local w,h=love.graphics.getDimensions();scale=math.min(w/1200,h/760);ox=(w-1200*scale)/2;oy=(h-760*scale)/2
    love.graphics.clear(.055,.085,.08);love.graphics.push();love.graphics.translate(ox,oy);love.graphics.scale(scale);buttons={}
    local item=character()
    love.graphics.setFont(heading);love.graphics.setColor(.91,.82,.59);love.graphics.print('Character Dialogue Lab',30,22)
    love.graphics.setFont(small);love.graphics.setColor(.7,.79,.74);love.graphics.print('Chosen voice takes loaded at launch  |  shared timing controls  |  isolated lab; no game saves',32,60)
    love.graphics.setColor(.14,.22,.20);love.graphics.rectangle('fill',30,100,780,380,10)
    love.graphics.setColor(.22,.29,.25);love.graphics.rectangle('fill',50,220,740,240)
    for x=50,790,40 do love.graphics.setColor(.26,.33,.28);love.graphics.line(x,220,x,460)end
    for y=220,460,40 do love.graphics.line(50,y,790,y)end
    love.graphics.setColor(.34,.28,.19);love.graphics.rectangle('fill',90,160,250,65,5)
    love.graphics.setColor(.76,.72,.55);love.graphics.rectangle('fill',120,145,55,18);love.graphics.rectangle('fill',210,145,75,18)
    love.graphics.setFont(small);love.graphics.setColor(.78,.82,.72);love.graphics.print('PRINT SHOP / CONVERSATION TEST ROOM',90,120)
    sprite(item.image,nx,ny,134,229,.65,item.static)
    local ps=player:getHeight();sprite(player,px,py,ps*.5,ps*.9,128/ps)
    love.graphics.setColor(.88,.88,.75);love.graphics.printf(item.name,nx-110,ny+8,220,'center');love.graphics.printf('You',px-30,py+8,60,'center')
    if engine.active then Bubble.draw(engine:text(),bubbleFont,nx,ny-(229-37)*.65,800,engine.active[2])end
    love.graphics.setFont(small);love.graphics.setColor(.83,.85,.76);love.graphics.print('WASD / arrows: move    E: talk nearby    Space: replay    Tab: next emotion',48,490)
    button('< Previous',48,520,116,function()useCharacter(characterIndex-1)end)
    button('Next >',694,520,116,function()useCharacter(characterIndex+1)end)
    love.graphics.setFont(font);love.graphics.setColor(.94,.87,.67);love.graphics.printf(item.name,170,523,510,'center')
    love.graphics.setFont(small);love.graphics.setColor(.78,.83,.76);love.graphics.printf(routeDescription(item),48,556,760,'center')
    for i,line in ipairs(D.lines)do local col=(i-1)%3;local r=math.floor((i-1)/3);button(line[3],40+col*255,580+r*38,245,function()sequence=false;trigger(i)end,selected==i)end
    love.graphics.setColor(.11,.17,.16);love.graphics.rectangle('fill',830,100,350,630,10)
    love.graphics.setFont(font);love.graphics.setColor(.94,.87,.67);love.graphics.print('Timing & mix',850,120)
    row('Voice volume',string.format('%d%%',gain*100),160,function()gain=math.max(0,gain-.05);if engine.source then engine.source:setVolume(gain)end end,function()gain=math.min(1,gain+.05);if engine.source then engine.source:setVolume(gain)end end)
    row('Sound delay',string.format('%d ms',delay*1000),204,function()delay=math.max(0,delay-.05)end,function()delay=math.min(.5,delay+.05)end)
    row('Text reveal',cps==0 and 'Instant' or cps..'/s',248,function()cps=math.max(0,cps-10)end,function()cps=math.min(60,cps+10)end)
    row('Bubble minimum',string.format('%.1f s',hold),292,function()hold=math.max(1,hold-.5)end,function()hold=math.min(8,hold+.5)end)
    button('Play full conversation',850,342,320,function()sequence=true;gap=0;trigger(1)end,sequence)
    button('Stop / silence',850,382,155,function()sequence=false;engine:stop()end)
    button('Reset mix',1015,382,155,function()gain=.35;delay=0;cps=0;hold=2.5;if engine.source then engine.source:setVolume(gain)end end)
    button('Save timing for ALL characters',850,422,320,saveProfile)
    love.graphics.setFont(small);love.graphics.setColor(.8,.85,.8)
    love.graphics.printf('Selected speaker: '..routedVoiceName(item),850,466,310)
    local line=D.lines[selected];local s=activeStats[line[1]]
    love.graphics.setFont(font);love.graphics.setColor(.92,.83,.60);love.graphics.print(line[1]:upper(),850,492)
    love.graphics.setFont(small);love.graphics.setColor(.8,.85,.8)
    if s then
        local fallback=fallbacks[line[1]]and'Neutral take is used for this emotion.\n'or''
        love.graphics.printf(string.format(fallback..'Clip %.2f s | peak %.1f dBFS\nAverage %.1f dBFS | mixed peak %.1f dBFS\n%s',s.duration,s.peakDb,s.rmsDb,db(s.peak*gain),s.warning),850,518,310)
    else
        love.graphics.printf('No selected recording for this emotion.\nThe text and bubble still preview.',850,518,310)
    end
    love.graphics.printf('Bubble: '..(engine.active and 'visible' or 'off')..'  |  Voice: '..(engine.source and engine.source:isPlaying() and 'playing' or engine.pending and 'pending' or s and 'off' or 'no clip'),850,590,310)
    love.graphics.printf('Actual onset: '..(engine.events.audio and string.format('%.0f ms after bubble',engine.events.audio*1000) or 'not started'),850,614,310)
    love.graphics.printf('One voice per line; new dialogue interrupts the old voice. Timing applies to the next line and is shared across characters.',850,642,310)
    love.graphics.setColor(.88,.79,.55);love.graphics.printf(saveStatus,850,696,310)
    love.graphics.pop()
end
