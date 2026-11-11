local Condition=require("src.warehouse_condition")
local Renderer={}
local canvas,key
local dirtShader
local images={}
local recent={}
local paths={
    stage0Off="assets/generated/warehouse-condition-v2/stage0-off.png",
    stage0On="assets/generated/warehouse-condition-v2/stage0-on.png",
    stage1Off="assets/generated/warehouse-condition-v2/stage1-off.png",
    stage1On="assets/generated/warehouse-condition-v2/stage1-on.png",
    stage2Off="assets/generated/warehouse-condition-v2/stage2-off.png",
    stage2On="assets/generated/warehouse-condition-v2/stage2-on.png",
    stage3Off="assets/generated/warehouse-condition-v2/stage3-off.png",
    stage3On="assets/generated/warehouse-condition-v2/stage3-on.png",
    stage4Off="assets/generated/warehouse-condition-v2/stage4-off.png",
}
function Renderer.image(state,assets)
    local c=Condition.of(state)
    if not c then return assets.get("warehouse") end
    local variant=Condition.variant(state)
    if variant=="stage4On" then return assets.get("warehouse") end
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
    return images[variant] or images[recent[#recent]] or assets.get("warehouse")
end
local function staticKey(c)
    return table.concat({c.seed,c.powerConnected and 1 or 0,c.breakerRepaired and 1 or 0,
        c.waterConnected and 1 or 0,
        c.cleaned.west and 1 or 0,c.cleaned.center and 1 or 0,c.cleaned.east and 1 or 0,
        c.repainted and 1 or 0},":")
end
local function build(c)
    if not canvas then canvas=love.graphics.newCanvas(960,678) end
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0,0,0,0)
    -- Transparent material masks preserve the floor and shelving perspective.
    if not dirtShader then
        local source=assert(love.filesystem.read("src/warehouse_dirt.glsl"))
        dirtShader=love.graphics.newShader(source)
    end
    dirtShader:send("cleanRegions",{c.cleaned.west and 0 or 1,c.cleaned.center and 0 or 1,c.cleaned.east and 0 or 1})
    dirtShader:send("conditionSeed",c.seed%10000)
    love.graphics.setShader(dirtShader)
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill",0,0,960,678)
    love.graphics.setShader()
    -- Historic damp staining and standing water share the east cleaning state.
    love.graphics.setCanvas()
    love.graphics.pop()
end
function Renderer.drawStatic(state)
    local c=Condition.of(state)
    if not c or c.mode~="story" then return end
    local nextKey=staticKey(c)
    if key~=nextKey then build(c);key=nextKey end
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
    if dirtShader and dirtShader.release then dirtShader:release() end
    dirtShader=nil
    for variant,image in pairs(images) do if image.release then image:release() end;images[variant]=nil end
    canvas,key,recent=nil,nil,{}
end
return Renderer
