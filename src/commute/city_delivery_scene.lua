-- A short, purely visual journey. Delivery completion remains owned by Trip.
local TruckArt=require('src.commute.truck_art')
local Text=require('src.screens.typography')
local Scene={}
local playback,fallbackArt,gradientMesh
local H=678
local function clamp(v) return math.max(0,math.min(1,v)) end
local function smooth(v) v=clamp(v);return v*v*(3-2*v) end
local function noise(i,salt)
    local value=math.sin(i*127.1+(salt or 0)*311.7)*43758.5453
    return value-math.floor(value)
end

-- Epoch timestamps survive saves/network snapshots; the monotonic clock keeps
-- the camera and dissolves smooth between those whole-second timestamps.
function Scene.elapsed(run,clock,epoch)
    clock=clock or love.timer.getTime();epoch=epoch or os.time()
    local started=run.cutsceneStartedAtEpoch or (run.cutsceneEndsAtEpoch or epoch+5)-5
    local ends=run.cutsceneEndsAtEpoch or started+5
    if not playback or playback.started~=started or playback.ends~=ends then
        playback={started=started,ends=ends,clock=clock,age=math.max(0,epoch-started)}
    end
    local age=playback.age+math.max(0,clock-playback.clock)
    if epoch>=ends then age=math.max(age,ends-started) end
    return age
end

function Scene.shot(run,elapsed)
    local ends=run.cutsceneEndsAtEpoch or 5
    local duration=math.max(1,ends-(run.cutsceneStartedAtEpoch or ends-5))
    local progress=clamp(elapsed/duration)
    local first,last=duration*.4,duration*.76
    local shot=elapsed<first and 'bridge' or elapsed<last and 'dock' or 'return'
    local since=shot=='bridge' and elapsed or shot=='dock' and elapsed-first or elapsed-last
    local span=shot=='bridge' and first or shot=='dock' and last-first or duration-last
    local travel=shot=='dock' and 0 or math.min(since,span)*190
    if shot=='return' then travel=-travel end
    local fade=0
    for _,cut in ipairs({first,last}) do fade=math.max(fade,1-math.abs(elapsed-cut)/.16) end
    fade=math.max(fade,1-elapsed/.18)
    return {id=shot,progress=progress,localProgress=clamp(since/span),waiting=progress>=1,
        travel=travel,angle=shot=='return' and math.pi*1.5 or math.pi*.5,
        fade=clamp(fade),remaining=math.max(0,math.ceil(duration-elapsed))}
end

local function gradient(g,w,y,height,top,bottom)
    local vertices={{0,y,0,0,top[1],top[2],top[3],1},
        {w,y,1,0,top[1],top[2],top[3],1},
        {0,y+height,0,1,bottom[1],bottom[2],bottom[3],1},
        {w,y+height,1,1,bottom[1],bottom[2],bottom[3],1}}
    if not gradientMesh then gradientMesh=g.newMesh(vertices,'strip','dynamic')
    else gradientMesh:setVertices(vertices) end
    g.setColor(1,1,1,1);g.draw(gradientMesh)
end

local function sky(g,w,travel)
    gradient(g,w,0,400,{.105,.19,.23},{.74,.64,.46})
    local sunX=w*.79-travel*.015
    for r=100,42,-6 do
        g.setColor(1,.78,.43,.018);g.circle('fill',sunX,225,r)
    end
    g.setColor(.98,.83,.56,.85);g.circle('fill',sunX,225,39)
    for i=-1,6 do
        local x=i*270-travel*.04
        g.setColor(.81,.77,.65,.07)
        g.ellipse('fill',x,168+noise(i,2)*74,95+noise(i,3)*80,5)
        g.ellipse('fill',x+80,185+noise(i,2)*74,120,3)
    end
    -- Two distinct silhouettes, with rooftops, cornices, and lit office bays.
    for layer=1,2 do
        local spacing=layer==1 and 76 or 112
        local offset=travel*(layer==1 and .09 or .19)
        local base=layer==1 and 356 or 377
        for i=math.floor(offset/spacing)-1,math.ceil((w+offset)/spacing) do
            local x=i*spacing-offset
            local bw=spacing-7-noise(i,4)*16
            local bh=40+noise(i,layer)*105
            if layer==1 then g.setColor(.35,.40,.39,1) else g.setColor(.23,.31,.32,1) end
            g.rectangle('fill',x,base-bh,bw,bh)
            g.rectangle('fill',x+7,base-bh-5,bw-14,5)
            g.rectangle('fill',x+bw*.6,base-bh-14,12,9)
            g.setColor(.57,.58,.48,.3);g.rectangle('fill',x,base-bh,bw,2)
            for row=1,math.floor((bh-12)/14) do for col=1,math.floor((bw-10)/13) do
                local lit=noise(i+row*7,col)>.64
                g.setColor(lit and .91 or .47,lit and .72 or .53,lit and .42 or .50,layer==1 and .28 or .52)
                g.rectangle('fill',x+col*13-4,base-bh+row*14,4,6)
            end end
            if layer==2 and i%4==0 then
                g.setColor(.22,.28,.28,1);g.setLineWidth(2)
                g.line(x+17,base-bh,x+20,base-bh-28,x+37,base-bh-28,x+40,base-bh)
                g.rectangle('fill',x+17,base-bh-43,23,18,3)
                g.polygon('fill',x+15,base-bh-43,x+29,base-bh-51,x+42,base-bh-43)
            end
        end
    end
end

local function waterfront(g,w,travel)
    gradient(g,w,377,86,{.34,.43,.42},{.17,.29,.32})
    for row=1,12 do
        local y=378+row*6
        for i=-1,math.ceil(w/94)+1 do
            local x=i*94+(noise(i,row)-.5)*65-(travel*(.06+row*.006))%94
            g.setColor(.83,.73,.51,.06+noise(i,row)*.12)
            g.rectangle('fill',x,y,12+noise(i+3,row)*59,1)
        end
    end
    -- Distant quays give the water a visible far shore.
    g.setColor(.18,.28,.29,1);g.rectangle('fill',0,379,w,5)
    for i=-1,math.ceil(w/175)+1 do
        local x=i*175-(travel*.18)%175
        g.rectangle('fill',x,383,9,25)
        g.setColor(.63,.57,.43,.25);g.rectangle('fill',x+2,384,2,17)
        g.setColor(.18,.28,.29,1)
    end
end

local function docks(g,w)
    -- Street-level brick warehouses, roll-up doors, lamps and loading aprons.
    local spacing=330
    for i=-1,math.ceil(w/spacing) do
        local x=i*spacing+28
        local roof=263-noise(i,8)*28
        g.setColor(.35+noise(i,1)*.05,.30,.25,1);g.rectangle('fill',x,roof,320,452-roof)
        for row=0,21 do
            local y=roof+row*10
            if y<452 then
                g.setColor(.15,.16,.15,.25);g.rectangle('fill',x,y,320,1)
                for col=0,10 do
                    local bx=x+col*32+(row%2)*16
                    if bx<x+320 then g.rectangle('fill',bx,y,1,math.min(10,452-y)) end
                end
            end
        end
        g.setColor(.16,.23,.23,1);g.rectangle('fill',x-4,roof-6,328,10)
        g.setColor(.64,.57,.41,1);g.rectangle('fill',x-4,roof-6,328,2)
        for col=0,4 do
            local wx=x+19+col*59
            g.setColor(.13,.22,.23,1);g.rectangle('fill',wx,roof+20,42,34)
            g.setColor(.64,.63,.48,.5);g.rectangle('fill',wx+2,roof+22,18,29)
            g.setColor(.63,.58,.44,.6);g.rectangle('fill',wx-2,roof+54,46,3)
        end
        for col=0,1 do
            local dx=x+25+col*155
            g.setColor(.10,.16,.17,1);g.rectangle('fill',dx-5,353,119,102)
            g.setColor(.41,.44,.40,1);g.rectangle('fill',dx,359,109,88)
            g.setColor(.24,.30,.29,1)
            for row=1,10 do g.rectangle('fill',dx,359+row*8,109,2) end
            g.setColor(.10,.15,.15,1);g.rectangle('fill',dx-7,442,123,12)
            for side=0,1 do
                g.setColor(.78,.59,.28,1);g.rectangle('fill',dx-10+side*125,426,5,30)
                g.setColor(.13,.19,.19,1);g.rectangle('fill',dx-10+side*125,433,5,5)
            end
        end
        g.setColor(.13,.23,.23,1);g.rectangle('fill',x+41,321,238,24)
        g.setFont(Text.get(14,'bold'));g.setColor(.85,.80,.63,1)
        g.printf('MILLHAVEN  /  RECEIVING',x+41,325,238,'center')
    end
    g.setColor(.51,.49,.40,1);g.rectangle('fill',0,452,w,12)
    g.setColor(.20,.27,.27,1);g.rectangle('fill',0,464,w,5)
end

local function bridgeRail(g,w,travel,y,foreground)
    local spacing=foreground and 152 or 95
    for i=-1,math.ceil(w/spacing)+1 do
        local x=i*spacing-travel%spacing
        g.setColor(.13,.22,.23,1);g.rectangle('fill',x,y,6,23)
        g.setColor(.55,.54,.44,.7);g.rectangle('fill',x,y,2,23)
    end
    g.setColor(.16,.24,.25,1);g.rectangle('fill',0,y,w,5)
    g.setColor(.69,.64,.49,.8);g.rectangle('fill',0,y,w,2)
    g.setColor(.24,.30,.29,1);g.rectangle('fill',0,y+19,w,6)
end

local function road(g,w,shot)
    gradient(g,w,463,130,{.23,.27,.27},{.12,.18,.20})
    g.setColor(.67,.64,.51,.8);g.rectangle('fill',0,473,w,2)
    for row=0,7 do for i=-1,math.ceil(w/44)+1 do
        local x=i*44-shot.travel%44+noise(i,row)*17
        g.setColor(.67,.64,.53,.045);g.rectangle('fill',x,482+row*13,4+noise(i,row)*13,1)
    end end
    for i=-1,math.ceil(w/185)+1 do
        local x=i*185-shot.travel%185
        g.setColor(.91,.80,.53,.8);g.polygon('fill',x,555,x+88,555,x+84,559,x-4,559)
        g.setColor(.72,.65,.47,.8);g.rectangle('fill',x+131,557,3,2)
    end
    if shot.id~='dock' then
        bridgeRail(g,w,shot.travel*.9,440,false)
        for i=-1,math.ceil(w/430)+1 do
            local x=i*430-(shot.travel*.9)%430
            g.setColor(.14,.22,.23,1);g.rectangle('fill',x,307,5,156)
            g.rectangle('fill',x,306,49,4)
            g.setColor(.90,.77,.46,.85);g.rectangle('fill',x+32,310,19,3)
            g.setColor(1,.81,.48,.06);g.ellipse('fill',x+40,314,28,10)
        end
    end
end

local function captions(g,w,run,shot)
    local margin=math.min(48,w*.07)
    g.setColor(.05,.105,.13,.96);g.rectangle('fill',0,0,w,148)
    g.setColor(.87,.70,.40,1);g.rectangle('fill',margin,42,32,3)
    g.setFont(Text.get(14,'bold'));g.print('ON THE DELIVERY ROUTE',margin+44,37)
    local stop=run.stops and run.stops[run.stopIndex or 1]
    local label=string.upper(stop and stop.city or 'Millhaven City')
    g.setFont(Text.fit(label,34,w-margin*2,45,'bold',20))
    g.setColor(.95,.90,.77,1);g.print(label,margin,67)
    g.setFont(Text.get(14));g.setColor(.66,.76,.74,1)
    g.print(shot.id=='dock' and 'THE WAREHOUSE DISTRICT' or 'THE MAINLAND CROSSING',margin,115)
    g.setColor(.035,.075,.09,.98);g.rectangle('fill',0,587,w,H-587)
    local caption=shot.waiting and 'Waiting for a clear return lane'
        or shot.id=='bridge' and 'Crossing the bridge into the city'
        or shot.id=='dock' and 'Dropping off your loaded pallets' or 'Heading back across the bridge'
    g.setFont(Text.fit(caption,18,w-margin*2,24,'regular',12))
    g.setColor(.93,.88,.75,1);g.print(caption,margin,607)
    g.setFont(Text.get(12));g.setColor(.63,.74,.72,1)
    g.print(shot.waiting and 'DELIVERY ROUTE IN PROGRESS' or ('RETURNING IN %d'):format(shot.remaining),margin,638)
    local trackWidth=math.min(190,w*.25)
    local x=w-margin-trackWidth
    g.setColor(.25,.34,.33,1);g.rectangle('fill',x,643,trackWidth,3)
    g.setColor(.87,.70,.40,1);g.rectangle('fill',x,643,trackWidth*shot.progress,3)
    for i=0,2 do
        local active=i==0 or i==1 and shot.id~='bridge' or i==2 and shot.id=='return'
        g.setColor(active and .87 or .35,active and .70 or .44,active and .40 or .42,1)
        g.circle('fill',x+trackWidth*i/2,644.5,3)
    end
end

function Scene.draw(w,h,run,vehicle,art,elapsed)
    elapsed=elapsed or Scene.elapsed(run)
    local shot=Scene.shot(run,elapsed)
    vehicle=vehicle or {model=run.vehicleModel or 'box'}
    if not art then fallbackArt=fallbackArt or TruckArt.new();art=fallbackArt end
    local g=love.graphics
    local scale=h/H;local width=w/scale
    g.push('all');g.scale(scale,scale)
    sky(g,width,shot.travel)
    if shot.id=='dock' then docks(g,width) else waterfront(g,width,shot.travel) end
    road(g,width,shot)
    local zoom=1.95*math.min(1,width/860)
    local drift=shot.id=='dock' and 0 or (smooth(shot.localProgress)-.5)*22
    local x=width*.51+(shot.id=='return' and -drift or drift)
    local stationary=shot.id=='dock' or shot.waiting
    local y=532+(stationary and 0 or math.sin(elapsed*17)*.55)
    local shadowWidth=(vehicle.model=='kei' and 75 or 112)*zoom
    g.setColor(.02,.04,.045,.13);g.ellipse('fill',x,537,shadowWidth*1.08,13)
    g.setColor(.02,.04,.045,.28);g.ellipse('fill',x,536,shadowWidth,8)
    art:drawSprite(vehicle,'chase',shot.angle,x,y,zoom)
    if shot.id~='dock' then bridgeRail(g,width,shot.travel*1.22,567,true) end
    -- Fade the scenery at the cuts; keep route information readable.
    if shot.fade>0 then
        g.setColor(.035,.075,.09,shot.fade);g.rectangle('fill',0,148,width,439)
    end
    captions(g,width,run,shot)
    g.pop()
end

function Scene.release()
    if fallbackArt then fallbackArt:release();fallbackArt=nil end
    if gradientMesh then gradientMesh:release();gradientMesh=nil end
    playback=nil
end
return Scene
