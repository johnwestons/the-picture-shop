-- The preview owns one frozen plan. Creating a shop passes that same plan to Home.
local Town=require('src.commute.town')
local Presets=require('src.commute.town_presets')
local Sites=require('src.commute.sites')
local Catalog=require('src.home_catalog')
local Ui=require('src.screens.ui')
local Skin=require('src.screens.title_skin')
local Fonts=require('src.screens.title_fonts')
local Preview=require('src.commute.town_preview')
local Options=require('src.commute.island_options')
local Codec=require('src.net.codec')
local Setup={}
local buttons={terrain={x=405,y=73,width=150,height=28},generate={x=590,y=170,width=175,height=42},random={x=775,y=170,width=125,height=42},
    save={x=590,y=309,width=310,height=40},previous={x=590,y=511,width=52,height=36},
    next={x=848,y=511,width=52,height=36},load={x=590,y=555,width=150,height=36},
    delete={x=750,y=555,width=150,height=36},back={x=55,y=597,width=150,height=43},
    cancel={x=215,y=597,width=150,height=43},start={x=700,y=597,width=200,height=43}}
local fields={seed={x=590,y=118,width=310,height=42},name={x=590,y=259,width=310,height=40}}
buttons.island={x=215,y=73,width=180,height=28}
local progressCancel={x=380,y=408,width=200,height=44}
local confirmation={tutorial={x=240,y=320,width=480,height=58},
    backPreview={x=240,y=433,width=220,height=46},confirmCreate={x=480,y=433,width=240,height=46}}
local pageSize=4
local generationSerial=0
function Setup.buttonCenter(name)
    local b=buttons[name] or fields[name] or confirmation[name];return b.x+b.width/2,b.y+b.height/2
end
local function randomSeed()
    return (love and love.math and love.math.random or math.random)(1,2147483646)
end
local function seedNumber(value)
    value=tostring(value or ''):upper()
    if value:match('^%d+$') then
        local seed=tonumber(value)
        if seed and seed%1==0 and seed>=Town.MIN_SEED and seed<=Town.MAX_SEED then return seed end
        return nil,'Enter a numeric seed from 1 to '..Town.MAX_SEED..'.'
    end
    if not value:match('^[%w]+$') then return nil,'Use letters and numbers for the town seed.' end
    local hash=0
    for i=1,#value do
        local byte=value:byte(i)
        local digit=byte>=48 and byte<=57 and byte-48 or byte>=65 and byte<=90 and byte-55 or nil
        if not digit then return nil,'Use letters and numbers for the town seed.' end
        hash=(hash*36+digit)%Town.MAX_SEED
    end
    return math.max(Town.MIN_SEED,hash)
end
local function show(state,town,seedText,ownedData)
    if state.terrainImage then state.terrainImage:release() end
    state.terrainImage=nil;state.terrainSamples=nil;state.selectedSite=nil
    state.settings=Options.copy(town.terrain.settings)
    state.town=ownedData and town or Town.copy(town);state.seedText=seedText or tostring(town.seed)
    state.sites=Sites.create({placements=town.placements,designs=town.designs})
    state.dirty=false;state.focus=nil
end
local function generateNow(state)
    state.dirty=true
    local seed,seedError=seedNumber(state.seedText)
    if not seed then state.message=seedError;return false end
    local town,err=Town.generate(seed,{island=state.settings})
    if not town then state.message=err or 'Could not generate this town.';return false end
    show(state,town,state.seedText,true);state.message='Town ready. Create shop to use this exact layout.';return true
end

local function clearJob(job)
    if not job then return end
    job.progressChannel:clear();job.resultChannel:clear();job.cancelChannel:clear()
end

function Setup.beginGeneration(state)
    if state.previewJob then return false end
    local seed,seedError=seedNumber(state.seedText)
    if not seed then state.message=seedError;return false end
    if not love or not love.thread or not love.thread.newThread then
        state.message='Background town generation is unavailable on this device.';return false
    end
    local limits={maxBytes=65536,maxDepth=8,maxEntries=256,maxStringBytes=512,maxNumberBytes=32}
    local config,encodeError=Codec.encode({seed=seed,island=state.settings},limits)
    if not config then state.message='Could not prepare town generation: '..tostring(encodeError);return false end
    generationSerial=generationSerial+1
    local prefix=('town-preview-%d-%d'):format(os.time(),generationSerial)
    local progressChannel=love.thread.getChannel(prefix..'-progress')
    local resultChannel=love.thread.getChannel(prefix..'-result')
    local cancelChannel=love.thread.getChannel(prefix..'-cancel')
    progressChannel:clear();resultChannel:clear();cancelChannel:clear()
    local okay,thread=pcall(love.thread.newThread,'src/commute/town_setup_worker.lua')
    if not okay or not thread then
        progressChannel:clear();resultChannel:clear();cancelChannel:clear()
        state.message='Could not start town generation: '..tostring(thread);return false
    end
    local started,reason=pcall(thread.start,thread,config,prefix)
    if not started then
        progressChannel:clear();resultChannel:clear();cancelChannel:clear()
        state.message='Could not start town generation: '..tostring(reason);return false
    end
    state.dirty=true
    state.previewJob={thread=thread,progressChannel=progressChannel,resultChannel=resultChannel,
        cancelChannel=cancelChannel,progress=0,label='Starting generator…',cancelRequested=false,
        seed=seed,seedText=state.seedText}
    state.message='Generating the town preview…'
    return true
end

function Setup.generate(state)
    if state.asyncGeneration then return Setup.beginGeneration(state) end
    return generateNow(state)
end

function Setup.cancelGeneration(state)
    local job=state and state.previewJob
    if not job then return false end
    if not job.cancelRequested then
        job.cancelRequested=true;job.cancelChannel:push(true)
        job.label='Cancelling generation…';state.message='Cancelling the town preview…'
    end
    return true
end

function Setup.update(state)
    local job=state and state.previewJob
    if not job then return false end
    while job.progressChannel:getCount()>0 do
        local message=job.progressChannel:pop()
        if type(message)=='table' then
            job.progress=math.max(0,math.min(1,tonumber(message.progress) or job.progress))
            job.label=type(message.label)=='string' and message.label or job.label
        end
    end
    local result=job.resultChannel:pop()
    if result then
        state.previewJob=nil;clearJob(job)
        if job.cancelRequested or result.status=='cancelled' then
            state.dirty=true;state.message='Preview generation cancelled. Adjust the seed or settings and try again.'
        elseif result.status=='complete' then
            local limits={maxBytes=8*1024*1024,maxDepth=16,maxEntries=500000,maxStringBytes=4096,maxNumberBytes=32}
            local town,err=Codec.decode(result.town,limits)
            if type(town)=='table' and town.seed==job.seed then
                show(state,town,job.seedText,true);state.message='Town ready. Create shop to use this exact layout.'
            else
                state.dirty=true;state.message='Generated preview could not be loaded: '..tostring(err or 'invalid town data')
            end
        else
            state.dirty=true;state.message=type(result.error)=='string' and result.error or 'Could not generate this town.'
        end
        return true
    end
    if not job.thread:isRunning() then
        local err=job.thread:getError()
        state.previewJob=nil;clearJob(job);state.dirty=true
        state.message=job.cancelRequested and 'Preview generation cancelled.'
            or 'Town generator stopped unexpectedly: '..tostring(err or 'unknown error')
        return true
    end
    return false
end

function Setup.new(options,asyncGeneration)
    options=options or {}
    local items,err=Presets.load()
    local state={seedText=tostring(options.townSeed or randomSeed()),nameText='',items=items,
        page=1,selected=nil,focus=nil,message='Roll or enter a number or word, then generate a preview.',
        settings=Options.copy(options.island),dirty=true,terrainVisible=true,asyncGeneration=asyncGeneration==true,
        tutorialEnabled=options.tutorialEnabled~=false}
    if options.town and Town.valid(options.town) then show(state,options.town)
    end
    if err then state.message=err end
    return state
end
function Setup.wantsTextInput(state) return state and state.focus~=nil or false end
function Setup.textinput(state,value)
    if state.confirming then return false end
    if not state.focus or type(value)~='string' then return false end
    local key=state.focus=='seed' and 'seedText' or 'nameText'
    value=state.focus=='seed' and value:gsub('[^%a%d]','') or value:gsub('[^%w %.%-]','')
    if state.replaceText then state[key]='';state.replaceText=false end
    state[key]=(state[key]..value):sub(1,state.focus=='seed' and 32 or Presets.MAX_NAME)
    if state.focus=='seed' then state.dirty=true end
    return true
end
local function action(state,name,options)
    if state.previewJob then return 'changed' end
    state.focus=nil;state.replaceText=false
    if name=='back' or name=='cancel' then return name end
    if name=='island' then state.settings=state.settings or Options.copy();state.optionsPage=1
    elseif name=='terrain' then state.terrainVisible=not state.terrainVisible
    elseif name=='generate' then Setup.generate(state)
    elseif name=='random' then
        state.seedText=tostring(randomSeed());state.dirty=true
        state.message='Seed rolled. Generate a preview to see this town.'
    elseif name=='start' then
        if state.dirty or not state.town then state.message='Generate a preview before creating your shop.'
        elseif Town.valid(state.town) then state.confirming=true end
    elseif name=='previous' or name=='next' then
        local pages=math.max(1,math.ceil(#state.items/pageSize))
        state.page=(state.page-1+(name=='next' and 1 or -1))%pages+1
    elseif name=='load' then
        local item=state.items[state.selected]
        if item then show(state,item.town);state.nameText=item.name;state.message='Loaded '..item.name..'.'
        else state.message='Choose a saved town first.' end
    elseif name=='save' then
        if state.dirty or not state.town then state.message='Generate a preview before saving it.';return 'changed' end
        local items,err=Presets.upsert(state.items,{name=state.nameText,town=state.town})
        if items then
            state.items=items;state.nameText=Presets.cleanName(state.nameText)
            for i,item in ipairs(items) do if item.name==state.nameText then state.selected=i;state.page=math.ceil(i/pageSize) end end
            state.message='Saved '..state.nameText..' on this device.'
        else state.message=err end
    elseif name=='delete' then
        local items,err=Presets.remove(state.items,state.selected)
        if items then state.items=items;state.selected=nil;state.page=math.min(state.page,math.max(1,math.ceil(#items/pageSize)));state.message='Saved town deleted.'
        else state.message=err end
    end
    return 'changed'
end
local function confirm(state,name,options)
    if name=='tutorial' then state.tutorialEnabled=not state.tutorialEnabled
    elseif name=='backPreview' then state.confirming=false
    elseif name=='confirmCreate' and not state.dirty and state.town and Town.valid(state.town) then
        options.town=Town.copy(state.town);options.townSeed=state.town.seed
        options.tutorialEnabled=state.tutorialEnabled
        state.confirming=false;return 'start'
    end
    return 'changed'
end
function Setup.nextAction(state)
    if state.previewJob or state.optionsPage or state.confirming then return nil end
    return (state.dirty or not state.town) and 'generate' or 'start'
end
function Setup.keypressed(state,key,options)
    if state.confirming then
        if key=='escape' or key=='back' then return confirm(state,'backPreview',options) end
        if key=='space' then return confirm(state,'tutorial',options) end
        if key=='return' or key=='kpenter' then return confirm(state,'confirmCreate',options) end
        return 'changed'
    end
    if state.previewJob then
        if key=='escape' or key=='back' then Setup.cancelGeneration(state) end
        return 'changed'
    end
    if state.optionsPage then
        if key=='escape' or key=='back' then state.optionsPage=nil end
        return 'changed'
    end
    if key=='escape' or key=='back' then
        if state.focus then state.focus=nil;return 'changed' end
        return 'back'
    end
    if key=='tab' then state.focus=state.focus=='seed' and 'name' or 'seed';state.replaceText=true;return 'changed' end
    if state.focus then
        if key=='return' or key=='kpenter' then return action(state,state.focus=='seed' and 'generate' or 'save',options) end
        if key=='backspace' or key=='delete' then
            local field=state.focus=='seed' and 'seedText' or 'nameText'
            state[field]=state.replaceText and '' or state[field]:sub(1,-2);state.replaceText=false
            if state.focus=='seed' then state.dirty=true end
        end
        return 'changed'
    end
    if key=='return' or key=='kpenter' then return action(state,'start',options) end
    if key=='r' then return action(state,'random',options) end
    if key=='t' then return action(state,'terrain',options) end
end
local function optionRows(state)
    local rows={}
    local function row(x,y,width,label,click)
        rows[#rows+1]={x=x,y=y,width=width,height=39,label=label,click=click}
    end
    if state.optionsPage==1 then
        for i,field in ipairs(Options.fields) do
            local key,values=field[1],field[3]
            row(180,95+(i-1)*46,600,field[2]..'     '..values[state.settings[key]],function()
                state.settings[key]=state.settings[key]%#values+1
                state.dirty=true
            end)
        end
    else
        local first=(state.optionsPage-2)*16
        for j=1,16 do
            local kind=Options.species[first+j]
            if not kind then break end
            row(155+(j-1)%2*330,95+math.floor((j-1)/2)*46,320,
                kind..(state.settings.excluded[kind] and '   Off' or '   On'),function()
                    state.settings.excluded[kind]=not state.settings.excluded[kind] or nil
                    state.dirty=true
                end)
        end
    end
    local pages=1+math.ceil(#Options.species/16)
    row(180,485,290,state.optionsPage==1 and 'Advanced foliage' or state.optionsPage<pages and 'More species' or 'Island settings',
        function() state.optionsPage=state.optionsPage%pages+1 end)
    row(490,485,290,'Back to preview',function()
        state.optionsPage=nil
        if state.dirty then state.message='Settings changed. Generate a preview to see them.' end
    end)
    return rows
end
function Setup.mousepressed(state,x,y,options)
    if state.confirming then
        for name,b in pairs(confirmation) do if Ui.contains(b,x,y) then return confirm(state,name,options) end end
        return 'changed'
    end
    if state.previewJob then
        if Ui.contains(progressCancel,x,y) then Setup.cancelGeneration(state) end
        return 'changed'
    end
    if state.optionsPage then
        for _,row in ipairs(optionRows(state)) do
            if Ui.contains(row,x,y) then row.click();break end
        end
        return 'changed'
    end
    for name,b in pairs(fields) do if Ui.contains(b,x,y) then state.focus=name;state.replaceText=true;return 'changed' end end
    for name,b in pairs(buttons) do if Ui.contains(b,x,y) then return action(state,name,options) end end
    for row=1,pageSize do
        local index=(state.page-1)*pageSize+row
        if state.items[index] and Ui.contains({x=590,y=365+(row-1)*35,width=310,height=33},x,y) then
            state.selected=index;state.nameText=state.items[index].name;state.focus=nil;return 'changed'
        end
    end
    if state.sites and x>=55 and x<=555 and y>=107 and y<=514 then
        local size=state.town.size;local scale=430/size
        local ox=55+(500-size*scale)*.5
        local bestDistance=16*16;state.selectedSite=nil
        for _,site in ipairs(state.sites.all) do
            local dx,dz=x-(ox+site.x*scale),y-(107+site.z*scale)
            if dx*dx+dz*dz<bestDistance then bestDistance=dx*dx+dz*dz;state.selectedSite=site.id end
        end
    end
    state.focus=nil;return 'changed'
end
local function text(value,x,y,width,size,color,align)
    love.graphics.setFont(Fonts.get('paper',size or 16));love.graphics.setColor(unpack(color or {.84,.93,.87,1}))
    love.graphics.printf(value,x,y,width,align or 'left')
end
local function map(state,options)
    local rect={x=55,y=107,width=500,height=430}
    love.graphics.setColor(.055,.10,.095,1);love.graphics.rectangle('fill',rect.x,rect.y,rect.width,rect.height,5,5)
    if not state.town then return end
    local size=state.town.size;local scale=math.min(rect.width,rect.height)/size
    local ox=rect.x+(rect.width-size*scale)/2;local oy=rect.y
    local function at(x,z)return ox+x*scale,oy+z*scale end
    if state.terrainVisible then
        if not state.terrainSamples then state.terrainSamples=Preview.sample(state.town) end
        if not state.terrainImage then state.terrainImage=Preview.image(state.terrainSamples) end
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(state.terrainImage,ox,oy,0,size*scale/Preview.RESOLUTION,size*scale/Preview.RESOLUTION)
    end
    love.graphics.setColor(.38,.47,.42,state.terrainVisible and .35 or 1);love.graphics.setLineWidth(1)
    for n=0,8 do local p=n*size/8;local x,y=at(p,0);local x1,y1=at(p,size);love.graphics.line(x,y,x1,y1) end
    for n=0,8 do local p=n*size/8;local x,y=at(0,p);local x1,y1=at(size,p);love.graphics.line(x,y,x1,y1) end
    love.graphics.setColor(.77,.72,.57,1)
    for _,road in ipairs(state.town.roads or {}) do
        love.graphics.setColor(road.surface=='dirt' and {.66,.43,.23,1} or road.role=='main' and {.94,.83,.54,1} or {.77,.72,.57,1})
        local points={};for _,p in ipairs(road.points) do local x,y=at(p.x or p[1],p.z or p[2]);points[#points+1]=x;points[#points+1]=y end
        if #points>=4 then love.graphics.setLineWidth(math.max(2,(road.width or 5)*scale));love.graphics.line(points) end
    end
    love.graphics.setLineWidth(1)
    for _,area in ipairs(state.town.recreation or {})do
        local x,y=at(area.x,area.z)
        love.graphics.setColor(.09,.27,.16,1);love.graphics.circle('fill',x,y,7)
        text(area.kind=='camp' and 'C' or 'P',x-6,y-7,12,12,{.65,1,.68,1},'center')
    end
    local labels={warehouse='W'};for i,id in ipairs(Catalog.ORDER) do labels[id]=tostring(i) end
    for _,site in ipairs(state.sites.all) do
        local selected=site.id==options.apartmentId
        love.graphics.setColor(selected and {1,.78,.28,1} or {.64,.79,.84,1})
        for _,footprint in ipairs(site.footprints) do
            local points={};for _,p in ipairs(footprint.corners) do local x,y=at(p.x,p.z);points[#points+1]=x;points[#points+1]=y end
            love.graphics.polygon('fill',points)
        end
        local x,y=at(site.door.x,site.door.z)
        love.graphics.circle('fill',x,y,3)
        text(labels[site.id] or '',x+5,y-7,24,14,selected and {1,.84,.3,1} or {.94,.96,.94,1})
    end
    local selected=state.selectedSite and state.town.destinations[state.selectedSite]
    local selectedLabel=state.selectedSite=='mechanic' and Sites.MECHANIC_NAME or selected and selected.label
    text(selectedLabel or 'W Picture Shop · Gold: your home · Tap buildings',64,514,480,14)
    if state.terrainVisible then
        text(('Blue: water · Green: lowland · Tan: hills · 0–%dm'):format(math.ceil(state.terrainSamples.high)),64,111,480,12)
    end
end
function Setup.draw(state,options,slot,assets,mouseX,mouseY)
    love.graphics.setColor(.015,.025,.03,.98);love.graphics.rectangle('fill',0,0,960,684)
    Skin.panel(assets,{x=30,y=30,width=900,height=624})
    text('CHOOSE YOUR TOWN  /  SLOT '..slot,55,48,845,23,{1,.86,.36,1},'center')
    text('Town preview',55,80,145,14)
    if state.optionsPage then
        text(state.optionsPage==1 and 'Island settings • Tap a value to change it' or 'Advanced foliage • Tap a species to toggle it',120,72,720,16,nil,'center')
        for _,row in ipairs(optionRows(state)) do
            Skin.button(assets,row,'normal')
            text(row.label,row.x+6,row.y+9,row.width-12,16,nil,'center')
        end
        return
    end
    map(state,options)
    for i,id in ipairs(Catalog.ORDER) do
        text(i..'  '..Catalog.APARTMENTS[id].name,55+((i-1)%2)*250,544+math.floor((i-1)/2)*23,245,13,
            id==options.apartmentId and {1,.84,.3,1} or nil)
    end
    text('TOWN SEED · LETTERS OK',590,92,310,17,{1,.86,.36,1})
    text('SAVE A NAMED TOWN',590,233,310,17,{1,.86,.36,1})
    for name,b in pairs(fields) do
        Skin.field(assets,b,state.focus==name and 'selected' or 'normal')
        local value=name=='seed' and state.seedText or state.nameText
        text(value~='' and value or 'Town name',b.x+12,b.y+10,b.width-24,
            name=='seed' and #value>24 and 15 or 18)
    end
    if #state.items==0 then text('No saved towns yet.',600,394,290,16,nil,'center') end
    for row=1,pageSize do
        local index=(state.page-1)*pageSize+row;local item=state.items[index]
        if item then
            local b={x=590,y=365+(row-1)*35,width=310,height=33}
            Skin.field(assets,b,index==state.selected and 'selected' or 'normal')
            text(item.name,b.x+8,b.y+8,b.width-16,15)
        end
    end
    text(state.page..' / '..math.max(1,math.ceil(#state.items/pageSize)),644,522,202,14,nil,'center')
    text(state.message or '',377,597,309,13,state.dirty and {1,.79,.35,1} or nil)
    local labels={terrain=state.terrainVisible and 'TERRAIN: ON' or 'TERRAIN: OFF',generate='GENERATE PREVIEW',random='REROLL',save='SAVE NAMED TOWN',previous='<',next='>',
        load='LOAD PRESET',delete='DELETE PRESET',back='BACK',cancel='CANCEL',start='CREATE SHOP'}
    labels.island='ISLAND SETTINGS'
    for name,b in pairs(buttons) do
        local hovered=mouseX and mouseY and Ui.contains(b,mouseX,mouseY)
        local disabled=(name=='start' or name=='save') and (state.dirty or not state.town)
        Skin.button(assets,b,disabled and 'disabled' or Ui.pressWithin(b) and 'pressed' or hovered and 'hover' or 'normal')
        if Setup.nextAction(state)==name then
            local pulse=.5+.5*math.sin((love.timer and love.timer.getTime() or 0)*math.pi*1.5)
            love.graphics.setColor(.22,.85,.43,.12+.10*pulse)
            love.graphics.rectangle('fill',b.x,b.y,b.width,b.height,5,5)
            love.graphics.setColor(.40,1,.57,.5+.35*pulse);love.graphics.setLineWidth(2)
            love.graphics.rectangle('line',b.x-2,b.y-2,b.width+4,b.height+4,6,6)
            love.graphics.setLineWidth(1)
        end
        local font=Fonts.fit('metal',labels[name],15,b.width-16,b.height-12)
        love.graphics.setFont(font);love.graphics.setColor(disabled and {.5,.55,.52,1} or {.95,.98,.9,1})
        love.graphics.printf(labels[name],b.x+8,b.y+(b.height-font:getHeight())/2,b.width-16,'center')
    end
    text(Setup.nextAction(state)=='generate' and '1. Generate a preview to see your town.'
        or '2. Review the map, then Create Shop.',590,215,310,12,{.60,.97,.70,1})
    if state.confirming then
        local g=love.graphics
        g.setColor(.005,.012,.015,.84);g.rectangle('fill',0,0,960,684)
        Skin.panel(assets,{x=205,y=190,width=550,height=315})
        text('IS THIS YOUR TOWN?',235,215,490,24,{1,.86,.36,1},'center')
        text('Create this town in save slot '..slot..'?',240,258,480,17,nil,'center')
        text('Town seed: '..tostring(state.town.seed),240,292,480,15,nil,'center')
        local b=confirmation.tutorial
        Ui.panel(b,{.09,.16,.15,1},{.4,.65,.48,1},5,1)
        g.setColor(.73,.94,.76,1);g.rectangle('line',b.x+15,b.y+16,25,25,3,3)
        if state.tutorialEnabled then
            g.setLineWidth(3);g.line(b.x+20,b.y+29,b.x+26,b.y+35,b.x+36,b.y+22);g.setLineWidth(1)
        end
        text('Enable tutorial',b.x+54,b.y+8,400,19,{.88,1,.88,1})
        text('First steps with saved, detailed instructions.',b.x+54,b.y+33,408,12)
        text('Space: tutorial  /  Enter: create  /  Esc: back',240,393,480,13,nil,'center')
        for _,name in ipairs({'backPreview','confirmCreate'}) do
            local rect=confirmation[name];Skin.button(assets,rect,'normal')
            text(name=='backPreview' and 'KEEP LOOKING' or 'CREATE THIS SHOP',rect.x+8,rect.y+14,rect.width-16,16,nil,'center')
        end
    end
    if state.previewJob then
        local g=love.graphics;local job=state.previewJob
        g.setColor(.005,.012,.015,.78);g.rectangle('fill',0,0,960,684)
        Skin.panel(assets,{x=220,y=244,width=520,height=202})
        text('GENERATING TOWN PREVIEW',250,265,460,20,{1,.86,.36,1},'center')
        text(job.label or 'Preparing town…',260,305,440,16,nil,'center')
        g.setColor(.12,.19,.18,1);g.rectangle('fill',280,342,400,22,4,4)
        g.setColor(.46,.74,.57,1);g.rectangle('fill',280,342,400*job.progress,22,4,4)
        text(('%d%%'):format(math.floor(job.progress*100+.5)),280,370,400,14,nil,'center')
        Skin.button(assets,progressCancel,job.cancelRequested and 'disabled' or 'normal')
        local cancelFont=Fonts.fit('metal',job.cancelRequested and 'CANCELLING…' or 'CANCEL',15,progressCancel.width-16,progressCancel.height-12)
        g.setFont(cancelFont);g.setColor(job.cancelRequested and {.58,.63,.59,1} or {.95,.98,.9,1})
        g.printf(job.cancelRequested and 'CANCELLING…' or 'CANCEL',progressCancel.x+8,
            progressCancel.y+(progressCancel.height-cancelFont:getHeight())/2,progressCancel.width-16,'center')
    end
end
return Setup
