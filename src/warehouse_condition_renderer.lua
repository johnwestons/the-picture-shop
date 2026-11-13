local Condition=require("src.warehouse_condition")
local Renderer={}
local canvas,eraseCanvas,overlayKey,maskSeed
local rendered={puddle1=0,puddle2=0}
local dirtShader
local images={}
local recent={}
local paths={
    stage3Off="assets/generated/warehouse-condition-v2/stage3-off.png",
}
local function plate(variant)
    if not images[variant] then
        local image
        if #recent==0 then
            -- A resumed closed shop must not flash the pristine lit plate while
            -- its first condition image decodes.
            local okay,loaded=pcall(love.graphics.newImage,paths[variant])
            if okay then image=loaded end
        else
            image=require("src.image_loader").load(paths[variant])
        end
        if image then
            image:setFilter("linear","linear")
            images[variant]=image
            recent[#recent+1]=variant
            if #recent>2 then
                local old=table.remove(recent,1)
                if images[old] and images[old].release then images[old]:release() end
                images[old]=nil
            end
        end
    end
    return images[variant]
end
function Renderer.image(state,assets)
    local base=assets.get("warehouse")
    local c=Condition.of(state)
    if not c or Condition.lit(state) then return base end
    -- A different condition plate can still be decoding after power, lighting,
    -- or cleanup changes. Do not show the most recently cached full-scene image:
    -- it may depict the previous restoration state for the entire world frame.
    return plate("stage3Off") or base
end
local function drawWipe(spot)
    love.graphics.push()
    love.graphics.translate(spot.x,spot.y)
    love.graphics.rotate(tonumber(spot.angle) or 0)
    love.graphics.setColor(1,1,1,.13);love.graphics.ellipse("fill",0,0,12,7)
    love.graphics.setColor(1,1,1,.22);love.graphics.ellipse("fill",0,0,9.6,5.6)
    love.graphics.setColor(1,1,1,.30);love.graphics.ellipse("fill",0,0,6.96,4.06)
    love.graphics.setColor(1,1,1,.36);love.graphics.ellipse("fill",0,0,4.08,2.38)
    love.graphics.pop()
end
local function ensureResources()
    if not canvas then canvas=love.graphics.newCanvas(960,678) end
    if not eraseCanvas then
        eraseCanvas=love.graphics.newCanvas(960,678)
        eraseCanvas:setFilter("linear","linear")
    end
    if not dirtShader then
        local source=assert(love.filesystem.read("src/warehouse_dirt.glsl"))
        dirtShader=love.graphics.newShader(source)
    end
end
local function overlaySignature(c)
    return table.concat({c.seed,c.cleanedPuddles.puddle1 and 1 or 0,
        c.cleanedPuddles.puddle2 and 1 or 0},":")
end
local function rebuildOverlay(c)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0,0,0,0)
    dirtShader:send("cleanedPuddles",{c.cleanedPuddles.puddle1 and 1 or 0,
        c.cleanedPuddles.puddle2 and 1 or 0})
    dirtShader:send("conditionSeed",c.seed%10000)
    dirtShader:send("eraseMask",eraseCanvas)
    dirtShader:send("canvasSize",{960,678})
    for _,name in ipairs({"puddle1","puddle2"}) do
        local point=Condition.anchors[name]
        dirtShader:send(name,{point.x,point.y,point.visualRadiusX,point.visualRadiusY})
    end
    love.graphics.setShader(dirtShader)
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill",0,0,960,678)
    love.graphics.setShader()
end
local function sync(state)
    local c=Condition.of(state)
    ensureResources()
    local counts={puddle1=#(c.puddleStrokes and c.puddleStrokes.puddle1 or {}),
        puddle2=#(c.puddleStrokes and c.puddleStrokes.puddle2 or {})}
    local reset=maskSeed~=c.seed or counts.puddle1<rendered.puddle1
        or counts.puddle2<rendered.puddle2
    love.graphics.push("all")
    local changed=false
    if reset then
        love.graphics.setCanvas(eraseCanvas);love.graphics.clear(0,0,0,0)
        rendered={puddle1=0,puddle2=0};maskSeed=c.seed
        changed=true
    end
    for _,name in ipairs({"puddle1","puddle2"}) do
        local strokes=c.puddleStrokes and c.puddleStrokes[name] or {}
        if counts[name]>rendered[name] then
            love.graphics.setCanvas(eraseCanvas)
            love.graphics.setBlendMode("alpha")
            for index=rendered[name]+1,counts[name] do drawWipe(strokes[index]) end
            rendered[name]=counts[name]
            changed=true
        end
    end
    local nextKey=overlaySignature(c)
    if changed or overlayKey~=nextKey then
        rebuildOverlay(c)
        overlayKey=nextKey
    end
    love.graphics.pop()
end
function Renderer.drawStatic(state)
    local c=Condition.of(state)
    if not c or c.mode~="story" then return end
    sync(state)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(canvas)
end
function Renderer.drawAmbient(state)
    local c=Condition.of(state)
    if not c or c.mode~="story" then return end
    love.graphics.push("all")
    local t=love.timer.getTime()
    if c.powerConnected and not c.breakerRepaired and math.floor(t*2.3)%4==0 then
        love.graphics.setColor(1,.68,.22,.8)
        love.graphics.setLineWidth(2)
        love.graphics.line(216,111,223,106,219,102)
        love.graphics.line(218,119,212,125,215,129)
    end
    love.graphics.pop()
end
function Renderer.clear()
    if canvas and canvas.release then canvas:release() end
    if eraseCanvas and eraseCanvas.release then eraseCanvas:release() end
    if dirtShader and dirtShader.release then dirtShader:release() end
    dirtShader=nil
    for variant,image in pairs(images) do if image.release then image:release() end;images[variant]=nil end
    canvas,eraseCanvas,overlayKey,maskSeed=nil,nil,nil,nil
    rendered={puddle1=0,puddle2=0}
    recent={}
end
return Renderer
