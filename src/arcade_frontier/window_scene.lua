local WindowScene={}
local SceneData=require("src.arcade_frontier.last_stand_scene_data")
WindowScene.data=SceneData

local ROOT="assets/generated/frontier-arcade/assets/sprites/quests/last-stand/runtime/"
local PATHS={
    relay=ROOT.."rail-relay-facade-cutout.png",
    wide=ROOT.."house-firing-window-wide.png",
    tall=ROOT.."house-firing-window-tall.png",
    dust=ROOT.."distant-dust-loop.png",
    effects=ROOT.."shootout-effects-atlas.png",
    damage=ROOT.."house-surface-damage-decals.png",
}
local BACKGROUND_COVER_SCALE=1.08

WindowScene.targetAtlases={
    ROOT.."mouse-bandit-rifle-target-atlas.png",
    ROOT.."cowboy-mouse-rifle-target-atlas.png",
    ROOT.."tunnel-badger-rifle-target-atlas.png",
}

WindowScene.slots=SceneData.slots

local images={}
local quads={}
local pixels={}

local function image(path)
    if images[path]~=nil then return images[path] or nil end
    local ok,result=pcall(love.graphics.newImage,path)
    if ok and result then
        result:setFilter("linear","linear")
        images[path]=result
    else
        images[path]=false
    end
    return images[path] or nil
end

local function quad(path,frame,cellWidth,cellHeight,columns)
    local key=table.concat({path,frame,cellWidth,cellHeight,columns},":")
    if quads[key] then return quads[key] end
    local source=image(path)
    if not source then return nil end
    local column=frame%columns
    local row=math.floor(frame/columns)
    quads[key]=love.graphics.newQuad(
        column*cellWidth,row*cellHeight,cellWidth,cellHeight,source:getDimensions()
    )
    return quads[key]
end

function WindowScene.backgroundPath(state)
    local quest=state.quest or state
    local stop=math.floor(tonumber(quest.originStop) or 12)
    return "assets/generated/frontier-arcade/assets/backgrounds/"..SceneData.backgrounds[(stop-1)%#SceneData.backgrounds+1]
end

function WindowScene.frameLayout(windowId,width,height)
    local frame=SceneData.frames[windowId] or SceneData.frames.wide
    local scale=math.min(width*.76/frame.w,height*.68/frame.h)
    return {x=width/2-frame.centerX*scale,y=height*.45-frame.centerY*scale,
        scale=scale,frame=frame}
end

function WindowScene.impactPosition(windowId,width,height,pointIndex)
    local layout=WindowScene.frameLayout(windowId,width,height)
    local points=SceneData.damagePoints[windowId] or SceneData.damagePoints.wide
    local point=points[((pointIndex or 1)-1)%#points+1]
    return layout.x+point[1]*layout.scale,layout.y+point[2]*layout.scale
end

function WindowScene.opening(windowId,width,height)
    local layout=WindowScene.frameLayout(windowId,width,height)
    local frame=layout.frame
    return layout.x+frame.x*layout.scale,layout.y+frame.y*layout.scale,
        frame.w*layout.scale,frame.h*layout.scale
end

function WindowScene.screenRect(x,y,w,h)
    local x1,y1=love.graphics.transformPoint(x,y)
    local x2,y2=love.graphics.transformPoint(x+w,y+h)
    return math.min(x1,x2),math.min(y1,y2),math.abs(x2-x1),math.abs(y2-y1)
end

function WindowScene.clipWindow(windowId,width,height)
    love.graphics.intersectScissor(WindowScene.screenRect(WindowScene.opening(windowId,width,height)))
end

function WindowScene.layout(windowId,width,height)
    local scale=math.min(width*.64/2001,height*.36/786)
    local buildingWidth=2001*scale
    local buildingHeight=786*scale
    return {
        windowId=windowId or "wide",
        x=(width-buildingWidth)/2+(windowId=="tall" and -width*.025 or 0),
        y=height*.35,
        width=buildingWidth,
        height=buildingHeight,
        scale=scale,
    }
end

function WindowScene.slotPosition(layout,index)
    local x,y,w,h=WindowScene.slotRect(layout,index)
    return x+w/2,y+h*.43
end

function WindowScene.slotRect(layout,index)
    local slot=WindowScene.slots[index] or WindowScene.slots[1]
    return layout.x+slot.x*layout.scale,layout.y+slot.y*layout.scale,
        slot.w*layout.scale,slot.h*layout.scale
end

local function alphaAt(path,x,y)
    if not pixels[path] then pixels[path]=love.image.newImageData(path) end
    local source=pixels[path]
    if x<0 or y<0 or x>=source:getWidth() or y>=source:getHeight() then return 0 end
    return select(4,source:getPixel(math.floor(x),math.floor(y)))
end

function WindowScene.pointOpen(windowId,width,height,x,y)
    local layout=WindowScene.frameLayout(windowId,width,height)
    local frame=layout.frame
    local px,py=(x-layout.x)/layout.scale,(y-layout.y)/layout.scale
    return px>=frame.x and px<frame.x+frame.w and py>=frame.y and py<frame.y+frame.h
        and alphaAt(windowId=="tall" and PATHS.tall or PATHS.wide,px,py)<.08
end

function WindowScene.buildingSolid(layout,x,y)
    return alphaAt(PATHS.relay,(x-layout.x)/layout.scale,(y-layout.y)/layout.scale)>.9
end

function WindowScene.targetHit(layout,index,x,y)
    local rx,ry,rw,rh=WindowScene.slotRect(layout,index)
    if x<rx or x>rx+rw or y<ry or y>ry+rh then return false end
    return ((x-rx-rw/2)/(rw*.46))^2+((y-ry-rh*.43)/(rh*.50))^2<=1
end

function WindowScene.drawBackground(state,width,height)
    love.graphics.push("all")
    local source=image(WindowScene.backgroundPath(state))
    local time=state.reducedMotion and 0 or (state.clock or state.elapsed or 0)
    if source then
        local iw,ih=source:getDimensions()
        local scale=math.max(width/iw,height/ih)*BACKGROUND_COVER_SCALE
        local drift=math.sin(time*.055)*width*.008
        local y=height-ih*scale
        love.graphics.setColor(.88,.85,.79,1)
        love.graphics.draw(source,(width-iw*scale)/2+drift,y,0,scale,scale)
    end
    love.graphics.setColor(.63,.55,.42,.10)
    love.graphics.rectangle("fill",0,0,width,height)

    local dust=image(PATHS.dust)
    if dust then
        local frame=math.floor(time*8)%8
        local dustQuad=quad(PATHS.dust,frame,320,512,8)
        love.graphics.setColor(1,1,1,.22)
        love.graphics.draw(dust,dustQuad,width*.10,8,0,1.25,1.0)
        love.graphics.draw(dust,dustQuad,width*.58,35,0,1.05,.92)
    end
    love.graphics.pop()
    return WindowScene.layout(state.windowId,width,height)
end

function WindowScene.drawActor(path,frame,x,y,scale,alpha)
    local source=image(path)
    local actorQuad=source and quad(path,frame,512,512,4)
    if not actorQuad then return false end
    love.graphics.setColor(1,1,1,alpha or 1)
    love.graphics.draw(source,actorQuad,x,y,0,scale,scale,256,500)
    return true
end

function WindowScene.drawBuilding(layout)
    local source=image(PATHS.relay)
    if not source then return end
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(source,layout.x,layout.y,0,layout.scale,layout.scale)
end

function WindowScene.drawApertures(layout)
    love.graphics.setColor(.065,.05,.035,1)
    for index in ipairs(WindowScene.slots) do
        love.graphics.rectangle("fill",WindowScene.slotRect(layout,index))
    end
end

function WindowScene.clipSlot(layout,index,draw)
    love.graphics.push("all")
    love.graphics.intersectScissor(WindowScene.screenRect(WindowScene.slotRect(layout,index)))
    draw()
    love.graphics.pop()
end

-- One shared camera rendered behind the two alpha openings. Scissor bounds
-- enclose only each aperture, so the cutaway's exterior alpha stays empty.
local interiorCanvas
function WindowScene.drawInterior(quest,clock,width,height,shellScale,shellY,reducedMotion,reducedFlashes)
    if not interiorCanvas then interiorCanvas=love.graphics.newCanvas(960,720) end
    love.graphics.push("all")
    local previous=love.graphics.getCanvas()
    love.graphics.setCanvas(interiorCanvas)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.clear(0,0,0,0)
    local state={quest=quest,clock=clock,reducedMotion=reducedMotion}
    local layout=WindowScene.drawBackground(state,960,720)
    WindowScene.drawApertures(layout)
    if not quest.victory and not quest.rewardClaimed then
        local index=math.floor(clock/3.7)%#WindowScene.slots+1
        if clock%3.7<2 then
            local rx,ry,rw,rh=WindowScene.slotRect(layout,index)
            WindowScene.clipSlot(layout,index,function()
                WindowScene.drawActor(WindowScene.targetAtlases[(index-1)%3+1],2,rx+rw/2,ry+rh*1.45,rh*1.5/512)
            end)
        end
    end
    WindowScene.drawBuilding(layout)
    if not quest.victory and not quest.rewardClaimed then
        local beat=clock%3.7
        if beat<.13 and not reducedMotion and not reducedFlashes then
            local index=math.floor(clock/3.7)%#WindowScene.slots+1
            WindowScene.clipSlot(layout,index,function()
                WindowScene.drawEffect(0,WindowScene.slotPosition(layout,index))
            end)
        end
    end
    if previous then love.graphics.setCanvas({previous,stencil=true}) else love.graphics.setCanvas() end
    love.graphics.pop()
    love.graphics.push("all")
    for _,opening in ipairs(SceneData.interiorWindows) do
        local x,y=opening.x*shellScale,shellY+opening.y*shellScale
        local w,h=opening.w*shellScale,opening.h*shellScale
        love.graphics.setScissor(WindowScene.screenRect(x,y,w,h))
        love.graphics.setColor(1,1,1,1)
        local scale=math.max(w/960,h/720)
        love.graphics.draw(interiorCanvas,x+(w-960*scale)/2+opening.cameraOffset*scale,
            y+(h-720*scale)/2,0,scale,scale)
    end
    love.graphics.pop()
end

function WindowScene.drawEffect(frame,x,y,scale,alpha,rotation)
    local source=image(PATHS.effects)
    local effectQuad=source and quad(PATHS.effects,frame,512,512,4)
    if not effectQuad then return end
    love.graphics.setColor(1,1,1,alpha or 1)
    love.graphics.draw(source,effectQuad,x,y,rotation or 0,scale or .15,scale or .15,256,256)
end

function WindowScene.drawWindow(windowId,width,height)
    local path=windowId=="tall" and PATHS.tall or PATHS.wide
    local source=image(path)
    if not source then return end
    local layout=WindowScene.frameLayout(windowId,width,height)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(source,layout.x,layout.y,0,layout.scale,layout.scale)
end

-- Continue the interior wall below the sill as the player's eye level drops.
function WindowScene.drawLowerWall(windowId,width,height,drop)
    local _,y,_,h=WindowScene.opening(windowId,width,height)
    local top=y+h+30
    local bottom=height+drop
    local source=image(PATHS.wide)
    if source and not quads.lowerWall then
        quads.lowerWall=love.graphics.newQuad(240,700,555,44,source:getDimensions())
    end
    love.graphics.setColor(.24,.13,.065,1)
    love.graphics.rectangle("fill",0,top,width,math.max(0,bottom-top))
    local boardHeight=height*.10
    for row=0,math.ceil(math.max(0,bottom-top)/boardHeight) do
        local by=top+row*boardHeight
        local shade=row%2==0 and .02 or 0
        love.graphics.setColor(.27+shade,.15+shade,.077,1)
        love.graphics.rectangle("fill",0,by+3,width,boardHeight-5)
        if source then
            love.graphics.setColor(.64+shade,.59+shade,.53,1)
            local reverse=row%2==1
            love.graphics.draw(source,quads.lowerWall,reverse and width or 0,by+3,0,
                (reverse and -1 or 1)*width/555,(boardHeight-5)/44)
        end
        love.graphics.setColor(.39,.23,.12,.6)
        love.graphics.rectangle("fill",0,by+3,width,2)
        love.graphics.setColor(.13,.07,.035,.7)
        for seam=1,3 do
            local sx=(seam-.35*(row%2))*width/3
            love.graphics.rectangle("fill",sx,by+3,2,boardHeight-4)
        end
    end
end

local damageShader
function WindowScene.drawDamage(impacts,width,height,windowId)
    local source=image(PATHS.damage)
    if not source then return end
    local frameSource=image(windowId=="tall" and PATHS.tall or PATHS.wide)
    local layout=WindowScene.frameLayout(windowId,width,height)
    local points=SceneData.damagePoints[windowId] or SceneData.damagePoints.wide
    if not damageShader then
        damageShader=love.graphics.newShader([[
            extern Image surface;
            extern vec2 origin;
            extern vec2 extent;
            vec4 effect(vec4 color, Image texture, vec2 uv, vec2 pixel) {
                vec2 maskUV=(pixel-origin)/extent;
                if (maskUV.x<0.0 || maskUV.y<0.0 || maskUV.x>1.0 || maskUV.y>1.0) discard;
                float solid=step(0.95,Texel(surface,maskUV).a);
                return Texel(texture,uv)*color*solid;
            }
        ]])
    end
    love.graphics.push("all")
    damageShader:send("surface",frameSource)
    local ox,oy,ew,eh=WindowScene.screenRect(layout.x,layout.y,887*layout.scale,887*layout.scale)
    damageShader:send("origin",{ox,oy})
    damageShader:send("extent",{ew,eh})
    love.graphics.setShader(damageShader)
    for _,impact in ipairs(impacts or {}) do
        local point=points[((impact.point or 1)-1)%#points+1]
        local frame=impact.frame or 0
        local damageQuad=quad(PATHS.damage,frame,512,512,4)
        love.graphics.setColor(1,1,1,math.min(1,(impact.age or 1)*3))
        love.graphics.draw(source,damageQuad,layout.x+point[1]*layout.scale,layout.y+point[2]*layout.scale,impact.rotation or 0,.13,.13,256,256)
    end
    love.graphics.pop()
end

function WindowScene.release()
    if interiorCanvas then interiorCanvas:release(); interiorCanvas=nil end
    if damageShader then damageShader:release(); damageShader=nil end
    for _,cache in ipairs({images,quads,pixels}) do
        for _,resource in pairs(cache) do
            if resource and resource.release then pcall(resource.release,resource) end
        end
    end
    images,quads,pixels={},{},{}
end

return WindowScene
