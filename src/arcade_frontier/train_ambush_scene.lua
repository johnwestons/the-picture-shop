local Rules=require("src.arcade_frontier.train_ambush_rules")
local Scene={}
local ROOT="assets/generated/frontier-arcade/assets/sprites/events/train-ambush/"
local TARGET="assets/generated/frontier-arcade/assets/sprites/quests/last-stand/runtime/mouse-bandit-rifle-target-atlas.png"
local EFFECTS="assets/generated/frontier-arcade/assets/sprites/quests/last-stand/runtime/shootout-effects-atlas.png"
local Backgrounds=require("src.arcade_frontier.last_stand_scene_data").backgrounds
local cache={}
local poses={peek=0,aim=2,fire=3,duck=4,hit=5,down=7}

-- Source coordinates are in each vehicle's damage atlas cell. The wagon and
-- cargo truck use the open side windows generated with their art sheets.
local visuals={
    pickup={id="pickup",art="pickup-damage.png",sourceY=200,cellW=543,height=340,
        laneX=.16,width=.47,baseline=515,ground="near",
        crewRects={{x=245,y=292,w=80,h=110},{x=88,y=240,w=95,h=110}},
        clips={{x=254,y=304,w=67,h=54},{x=80,y=250,w=105,h=110}},
        wheelCenters={{113,469,46},{436,469,46}},wheelFrames={{166,389},{938,389},{167,874},{938,873}}},
    wagon={id="wagon",art="bandit-wagon-damage.png",sourceY=0,cellW=768,height=512,
        laneX=.48,width=.30,baseline=497,ground="far",
        crewRects={{x=272,y=250,w=86,h=106},{x=394,y=248,w=80,h=106}},
        clips={{x=268,y=258,w=100,h=76},{x=390,y=256,w=82,h=78}}},
    cargo={id="cargo",art="bandit-cargo-truck-damage.png",sourceY=0,cellW=768,height=512,
        laneX=.48,width=.24,baseline=468,ground="far",
        crewRects={{x=290,y=164,w=92,h=106},{x=580,y=158,w=82,h=104}},
        clips={{x=282,y=178,w=116,h=70},{x=576,y=176,w=100,h=72}}},
}

local function asset(path)
    if not cache[path] then
        local pixels=love.image.newImageData(path)
        local image=love.graphics.newImage(pixels)
        image:setFilter("nearest","nearest")
        cache[path]={image=image,pixels=pixels,quads={}}
    end
    return cache[path]
end

local function quad(path,x,y,w,h)
    local a=asset(path)
    local key=table.concat({x,y,w,h},":")
    if not a.quads[key] then a.quads[key]=love.graphics.newQuad(x,y,w,h,a.image:getDimensions()) end
    return a.image,a.quads[key]
end

local function alpha(path,x,y)
    local p=asset(path).pixels
    x,y=math.floor(x),math.floor(y)
    if x<0 or y<0 or x>=p:getWidth() or y>=p:getHeight() then return 0 end
    return select(4,p:getPixel(x,y))
end

local function inside(r,x,y)
    return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h
end

local function scissor(x,y,w,h)
    local x1,y1=love.graphics.transformPoint(x,y)
    local x2,y2=love.graphics.transformPoint(x+w,y+h)
    love.graphics.intersectScissor(x1,y1,x2-x1,y2-y1)
end

function Scene.layout(state,w,h)
    local scale=w/835
    local cover=state.coverProgress or 0
    local eased=cover*cover*(3-2*cover)
    local frameY=h*.1-(h*.1+365*scale-h*.17)*eased
    local list={}
    -- Only one vehicle occupies the far lane at a time. The pickup remains
    -- near the train while the wagon and cargo rig take turns pulling up.
    local order={"cargo","wagon","pickup"}
    for _,id in ipairs(order) do
        local vehicle=Rules.vehicle(state,id)
        local v=visuals[id]
        local visible=vehicle and vehicle.active and (vehicle.distance=="near" or state.activeFar==id)
        if visible then
            local vehicleScale=w*v.width/v.cellW
            -- Each lane owns its yellow dash line. The far vehicle sits on
            -- the higher back-road line; the pickup uses the foreground line.
            local groundY=frameY+((v.ground=="far") and 314 or 354)*scale
            list[#list+1]={id=id,x=w*v.laneX+Rules.motionOffset(vehicle)*w,
                y=groundY-(v.baseline-v.sourceY)*vehicleScale,scale=vehicleScale,
                sourceY=v.sourceY,cellW=v.cellW,height=v.height,art=ROOT..v.art,visual=v}
        end
    end
    return {frameY=frameY,frameScale=scale,
        opening={x=134*scale,y=frameY+105*scale,w=609*scale,h=260*scale},vehicles=list}
end

function Scene.pointOpen(state,w,h,x,y)
    local l=Scene.layout(state,w,h)
    if not inside(l.opening,x,y) then return false end
    local px,py=x/l.frameScale,(y-l.frameY)/l.frameScale
    for i=0,3 do
        if alpha(ROOT.."window-rattle.png",(i%2)*835+px,math.floor(i/2)*470+py)>.08 then return false end
    end
    return true
end

local function targetCrew(entry,state,px,py)
    local v=Rules.vehicle(state,entry.id)
    if not v or v.hull<=0 then return nil end
    for index,crew in ipairs(v.crew or {}) do
        local clip=entry.visual.clips[index]
        if clip and inside(clip,px,py) and Rules.exposed(crew) then
            local r=entry.visual.crewRects[index]
            local frame=poses[crew.phase] or 0
            local ax=(px-r.x)/r.w*512+(frame%4)*512
            local ay=(py-r.y)/r.h*512+math.floor(frame/4)*512
            if alpha(TARGET,ax,ay)>.15 then return {kind="crew",vehicle=entry.id,index=index} end
        end
    end
end

function Scene.target(state,w,h,x,y)
    if not Scene.pointOpen(state,w,h,x,y) then return nil end
    local l=Scene.layout(state,w,h)
    -- Test near vehicles first so a solid near shell shields a distant target.
    for i=#l.vehicles,1,-1 do
        local entry=l.vehicles[i]
        local v=Rules.vehicle(state,entry.id)
        if v and v.hull>0 then
            local px=(x-entry.x)/entry.scale
            local py=(y-entry.y)/entry.scale+entry.sourceY
            if px>=0 and px<entry.cellW and py>=entry.sourceY and py<entry.sourceY+entry.height then
                local crew=targetCrew(entry,state,px,py)
                if crew then return crew end
                local inWindow=false
                for _,clip in ipairs(entry.visual.clips) do if inside(clip,px,py) then inWindow=true; break end end
                -- Empty window openings are intentionally non-solid.
                if not inWindow and alpha(entry.art,(Rules.vehicleStage(v)-1)*entry.cellW+px,py)>.35 then
                    return {kind="hull",vehicle=entry.id,x=px,y=py}
                end
            end
        end
    end
end

local function drawWorld(state,w,h,reduced)
    local l=Scene.layout(state,w,h)
    local o=l.opening
    local path="assets/generated/frontier-arcade/assets/backgrounds/"..Backgrounds[((state.location or 1)-1)%#Backgrounds+1]
    local image=asset(path).image
    local iw,ih=image:getDimensions()
    local scale=math.max(o.w/iw,o.h/ih)
    local dw=iw*scale
    local time=reduced and 0 or state.clock
    local offset=(time*14)%dw
    love.graphics.setColor(1,1,1)
    for i=0,1 do love.graphics.draw(image,o.x-offset+i*dw,o.y+o.h-ih*scale,0,scale,scale) end
    -- The far lane sits behind the near rail-side lane. Its road edge is
    -- deliberately higher so distant wheels have a separate ground plane.
    love.graphics.setColor(.24,.14,.08,.78)
    love.graphics.rectangle("fill",o.x,o.y+o.h-61,o.w,16)
    love.graphics.setColor(.48,.31,.16,.62)
    local offsetFar=(time*120)%74
    for i=-1,12 do love.graphics.rectangle("fill",o.x+i*74-offsetFar,o.y+o.h-54,30,3) end
    love.graphics.setColor(.32,.19,.10,.85)
    love.graphics.rectangle("fill",o.x,o.y+o.h-21,o.w,21)
    love.graphics.setColor(.60,.40,.21,.75)
    local offsetNear=(time*180)%84
    for i=-1,10 do love.graphics.rectangle("fill",o.x+i*84-offsetNear,o.y+o.h-15,35,4) end
end

local function drawBulletHoles(state,entry)
    local atlas=ROOT.."vehicle-bullet-holes.png"
    local cell=627
    local size=(entry.id=="pickup" and 86) or (entry.id=="wagon" and 72) or 58
    for _,hole in ipairs(state.bulletHoles or {}) do
        if hole.vehicle==entry.id then
            local variant=(hole.variant or 1)-1
            local image,q=quad(atlas,(variant%2)*cell,math.floor(variant/2)*cell,cell,cell)
            love.graphics.setColor(1,1,1,.94)
            love.graphics.draw(image,q,entry.x+(hole.x-size/2)*entry.scale,
                entry.y+(hole.y-entry.sourceY-size/2)*entry.scale,0,
                size*entry.scale/cell,size*entry.scale/cell)
        end
    end
end

local function drawCrew(state,entry)
    local v=Rules.vehicle(state,entry.id)
    if not v then return end
    for index,crew in ipairs(v.crew or {}) do
        if crew.phase~="hidden" then
            local r,c=entry.visual.crewRects[index],entry.visual.clips[index]
            local frame=poses[crew.phase] or 0
            local image,q=quad(TARGET,frame%4*512,math.floor(frame/4)*512,512,512)
            love.graphics.push("all")
            scissor(entry.x+c.x*entry.scale,entry.y+(c.y-entry.sourceY)*entry.scale,c.w*entry.scale,c.h*entry.scale)
            love.graphics.setColor(1,1,1)
            love.graphics.draw(image,q,entry.x+r.x*entry.scale,entry.y+(r.y-entry.sourceY)*entry.scale,0,
                r.w*entry.scale/512,r.h*entry.scale/512)
            love.graphics.pop()
        end
    end
end

local function drawVehicle(state,entry,reduced,settings)
    local v=Rules.vehicle(state,entry.id)
    if not v then return end
    local stage=Rules.vehicleStage(v)
    local image,q=quad(entry.art,(stage-1)*entry.cellW,entry.sourceY,entry.cellW,entry.height)
    love.graphics.setColor(1,1,1)
    love.graphics.draw(image,q,entry.x,entry.y,0,entry.scale,entry.scale)
    drawBulletHoles(state,entry)
    if entry.id=="pickup" and stage<4 then
        local frame=reduced and 1 or (math.floor(state.clock*9)%4+1)
        local center=entry.visual.wheelFrames[frame]
        local wheel,wq=quad(ROOT.."pickup-wheel-frames-source.png",center[1]-61,center[2]-61,122,122)
        for _,wc in ipairs(entry.visual.wheelCenters) do
            local cx,cy=entry.x+wc[1]*entry.scale,entry.y+(wc[2]-entry.sourceY)*entry.scale
            local radius=wc[3]*entry.scale*.92
            love.graphics.stencil(function() love.graphics.circle("fill",cx,cy,radius) end,"replace",1)
            love.graphics.setStencilTest("equal",1)
            love.graphics.draw(wheel,wq,cx-radius,cy-radius,0,radius/61,radius/61)
            love.graphics.setStencilTest()
        end
    end
    drawCrew(state,entry)
    for index,crew in ipairs(v.crew or {}) do
        local c=entry.visual.clips[index]
        if c and crew.phase=="aim" and not state.outcome then
            local cx=entry.x+(c.x+c.w/2)*entry.scale
            local cy=math.max(0,entry.y+(c.y-entry.sourceY-8)*entry.scale)
            love.graphics.setColor(.03,.02,.01,1); love.graphics.rectangle("fill",cx-22,cy-8,44,8)
            love.graphics.setColor(1,.78,.25,1)
            love.graphics.rectangle("line",cx-20,cy-6,40,5)
            love.graphics.rectangle("fill",cx-19,cy-5,38*(1-crew.timer/1.4),3)
        elseif c and crew.phase=="fire" and not state.outcome and not (settings and (settings.reducedFlashes or settings.reducedMotion)) then
            local fx,fq=quad(EFFECTS,0,0,512,512)
            love.graphics.setColor(1,1,1)
            love.graphics.draw(fx,fq,entry.x+(c.x+c.w/2)*entry.scale-14,entry.y+(c.y-entry.sourceY)*entry.scale-10,0,28/512,28/512)
        end
    end
end

function Scene.draw(state,w,h,settings,impact)
    local g=love.graphics
    local reduced=settings and settings.reducedMotion
    local l=Scene.layout(state,w,h)
    g.push("all")
    g.setColor(.075,.035,.02,1); g.rectangle("fill",0,0,w,h)
    if (state.coverProgress or 0)>0 then
        local wall,wq=quad(ROOT.."window-rattle.png",112,422,648,23)
        g.setColor(.72,.65,.58,1)
        local start=l.frameY+442*l.frameScale
        local tileHeight=46*l.frameScale
        for y=start,h,tileHeight do g.draw(wall,wq,0,y,0,w/648,tileHeight/23) end
    end
    g.push("all")
    scissor(l.opening.x,l.opening.y,l.opening.w,l.opening.h)
    drawWorld(state,w,h,reduced)
    for _,entry in ipairs(l.vehicles) do drawVehicle(state,entry,reduced,settings) end
    if impact and impact.time>0 then
        local fx,fq=quad(EFFECTS,512,0,512,512)
        g.setColor(1,1,1,math.min(1,impact.time*5)); g.draw(fx,fq,impact.x-19,impact.y-19,0,38/512,38/512)
    end
    g.pop()
    local frame=reduced and 0 or math.floor(state.clock*5)%4
    local shell,sq=quad(ROOT.."window-rattle.png",frame%2*835,math.floor(frame/2)*470,835,470)
    g.setColor(1,1,1); g.draw(shell,sq,0,l.frameY,0,l.frameScale,l.frameScale)
    g.pop()
end

function Scene.release()
    for _,a in pairs(cache) do
        for _,q in pairs(a.quads) do q:release() end
        a.image:release(); a.pixels:release()
    end
    cache={}
end
return Scene
