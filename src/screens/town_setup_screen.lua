-- The preview owns one frozen plan. Creating a shop passes that same plan to Home.
local Town=require('src.commute.town')
local Presets=require('src.commute.town_presets')
local Sites=require('src.commute.sites')
local Catalog=require('src.home_catalog')
local Ui=require('src.screens.ui')
local Skin=require('src.screens.title_skin')
local Fonts=require('src.screens.title_fonts')
local Preview=require('src.commute.town_preview')
local Setup={}
local buttons={terrain={x=405,y=73,width=150,height=28},generate={x=590,y=170,width=175,height=42},random={x=775,y=170,width=125,height=42},
    save={x=590,y=309,width=310,height=40},previous={x=590,y=511,width=52,height=36},
    next={x=848,y=511,width=52,height=36},load={x=590,y=555,width=150,height=36},
    delete={x=750,y=555,width=150,height=36},back={x=55,y=597,width=150,height=43},
    cancel={x=215,y=597,width=150,height=43},start={x=700,y=597,width=200,height=43}}
local fields={seed={x=590,y=118,width=310,height=42},name={x=590,y=259,width=310,height=40}}
local pageSize=4
function Setup.buttonCenter(name)
    local b=buttons[name] or fields[name];return b.x+b.width/2,b.y+b.height/2
end
local function randomSeed()
    return (love and love.math and love.math.random or math.random)(1,2147483646)
end
local function show(state,town)
    if state.terrainImage then state.terrainImage:release() end
    state.terrainImage=nil;state.terrainSamples=nil;state.selectedSite=nil
    state.town=Town.copy(town);state.seedText=tostring(town.seed)
    state.sites=Sites.create({placements=town.placements,designs=town.designs})
    state.dirty=false;state.focus=nil
end
function Setup.generate(state)
    state.dirty=true
    local seed=state.seedText:match('^%d+$') and tonumber(state.seedText)
    if not seed or seed%1~=0 or seed<1 or seed>2147483646 then
        state.message='Enter a seed from 1 to 2147483646.';return false
    end
    local town,err=Town.generate(seed)
    if not town then state.message=err or 'Could not generate this town.';return false end
    show(state,town);state.message='Town ready. Create shop to use this exact layout.';return true
end
function Setup.new(options)
    options=options or {}
    local items,err=Presets.load()
    local state={seedText=tostring(options.townSeed or randomSeed()),nameText='',items=items,
        page=1,selected=nil,focus=nil,message='',dirty=true,terrainVisible=true}
    if options.town and Town.valid(options.town) then show(state,options.town)
    else Setup.generate(state) end
    if err then state.message=err end
    return state
end
function Setup.wantsTextInput(state) return state and state.focus~=nil or false end
function Setup.textinput(state,value)
    if not state.focus or type(value)~='string' then return false end
    local key=state.focus=='seed' and 'seedText' or 'nameText'
    value=state.focus=='seed' and value:gsub('%D','') or value:gsub('[^%w %.%-]','')
    if state.replaceText then state[key]='';state.replaceText=false end
    state[key]=(state[key]..value):sub(1,state.focus=='seed' and 10 or Presets.MAX_NAME)
    if state.focus=='seed' then state.dirty=true end
    return true
end
local function action(state,name,options)
    state.focus=nil;state.replaceText=false
    if name=='back' or name=='cancel' then return name end
    if name=='terrain' then state.terrainVisible=not state.terrainVisible
    elseif name=='generate' then Setup.generate(state)
    elseif name=='random' then state.seedText=tostring(randomSeed());Setup.generate(state)
    elseif name=='start' then
        if state.dirty or not state.town then state.message='Generate a preview before creating your shop.'
        elseif Town.valid(state.town) then options.town=Town.copy(state.town);options.townSeed=state.town.seed;return 'start' end
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
function Setup.keypressed(state,key,options)
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
function Setup.mousepressed(state,x,y,options)
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
    text('Preview your roads, shops and homes.',55,80,345,14)
    map(state,options)
    for i,id in ipairs(Catalog.ORDER) do
        text(i..'  '..Catalog.APARTMENTS[id].name,55+((i-1)%2)*250,544+math.floor((i-1)/2)*23,245,13,
            id==options.apartmentId and {1,.84,.3,1} or nil)
    end
    text('TOWN SEED',590,92,310,17,{1,.86,.36,1})
    text('SAVE A NAMED TOWN',590,233,310,17,{1,.86,.36,1})
    for name,b in pairs(fields) do
        Skin.field(assets,b,state.focus==name and 'selected' or 'normal')
        local value=name=='seed' and state.seedText or state.nameText
        text(value~='' and value or 'Town name',b.x+12,b.y+10,b.width-24,18)
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
    for name,b in pairs(buttons) do
        local hovered=mouseX and mouseY and Ui.contains(b,mouseX,mouseY)
        local disabled=(name=='start' or name=='save') and (state.dirty or not state.town)
        Skin.button(assets,b,disabled and 'disabled' or Ui.pressWithin(b) and 'pressed' or hovered and 'hover' or 'normal')
        local font=Fonts.fit('metal',labels[name],15,b.width-16,b.height-12)
        love.graphics.setFont(font);love.graphics.setColor(disabled and {.5,.55,.52,1} or {.95,.98,.9,1})
        love.graphics.printf(labels[name],b.x+8,b.y+(b.height-font:getHeight())/2,b.width-16,'center')
    end
end
return Setup
