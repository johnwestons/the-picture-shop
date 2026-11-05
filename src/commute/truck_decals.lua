-- Logos stay independent of the two plain 64-angle truck sprite sets.
local liveries=require('src.commute.truck_liveries')
local Decals={}
Decals.__index=Decals

local capture={
    chase={zoom=2,pitch=8,verticalBase=48},
    isometric={zoom=1,pitch=32,verticalBase=38.4},
}
local rear,front,halfWidth=-2.72,1.47,1.08

function Decals.new()
    local self=setmetatable({images={},companyImages={},companyOrder={},companyFonts={}},Decals)
    for id,path in pairs(liveries) do
        if path then
            local image=love.graphics.newImage(path,{mipmaps=true})
            image:setFilter('linear','linear')
            image:setMipmapFilter('linear')
            self.images[id]=image
        end
    end
    self.mesh=love.graphics.newMesh({{0,0,0,0},{0,0,1,0},{0,0,0,1},{0,0,1,1}},'strip','dynamic')
    return self
end

function Decals:companyImage(company)
    if type(company)~='string' then return nil end
    local label=company:gsub('[%c]+',' '):gsub('%s+',' '):match('^%s*(.-)%s*$')
    if not label or label=='' then return nil end
    label=label:upper()
    if #label>38 then label=label:sub(1,35)..'...' end
    local cached=self.companyImages[label]
    if cached then return cached end

    local g=love.graphics
    local canvas=g.newCanvas(512,200,{format='rgba8'})
    g.push('all')
    g.setCanvas(canvas)
    g.origin()
    g.setShader()
    g.setDepthMode()
    g.setScissor()
    g.setStencilTest()
    g.setBlendMode('alpha','alphamultiply')
    g.clear(0,0,0,0)
    local fontSize=48
    local font=self.companyFonts[fontSize]
    if not font then
        font=g.newFont('assets/fonts/BarlowCondensed-SemiBold.ttf',fontSize)
        font:setFilter('linear','linear')
        self.companyFonts[fontSize]=font
    end
    while fontSize>28 and font:getWidth(label)>470 do
        fontSize=fontSize-4
        font=self.companyFonts[fontSize]
        if not font then
            font=g.newFont('assets/fonts/BarlowCondensed-SemiBold.ttf',fontSize)
            font:setFilter('linear','linear')
            self.companyFonts[fontSize]=font
        end
    end
    g.setColor(.035,.16,.15,.95)
    g.setLineWidth(5)
    g.line(22,42,490,42)
    g.line(22,158,490,158)
    g.setFont(font)
    g.printf(label,21,70,470,'center')
    local accents={{.10,.34,.33,1},{.83,.39,.20,1},{.85,.69,.36,1}}
    for i,color in ipairs(accents) do
        g.setColor(color)
        g.rectangle('fill',112+(i-1)*96,174,88,5)
    end
    g.pop()
    canvas:setFilter('linear','linear')
    self.companyImages[label]=canvas
    self.companyOrder[#self.companyOrder+1]=label
    if #self.companyOrder>12 then
        local oldest=table.remove(self.companyOrder,1)
        local retired=self.companyImages[oldest]
        self.companyImages[oldest]=nil
        if retired then retired:release() end
    end
    return canvas
end

function Decals:drawTurntable(image,kind,frame,x,y,scale,format)
    if not image then return end
    local angle=(frame-1)*math.pi*2/64
    local s,c=math.sin(angle),math.cos(angle)
    if math.abs(s)<.0001 then return end
    local spec=assert(capture[kind])
    local pitch=math.rad(spec.pitch)
    local horizontal=48*spec.zoom
    local depth=35.4*math.sin(pitch)*spec.zoom
    local vertical=spec.verticalBase*math.cos(pitch)*spec.zoom
    local near=s>=0 and halfWidth or -halfWidth
    local left,right=rear+.08*(front-rear),front-.08*(front-rear)
    if s<0 then left,right=right,left end
    local function point(length,height)
        return format.anchorX+horizontal*(length*s+near*c),
            format.anchorY+depth*(-length*c+near*s)-vertical*height
    end
    local x0,y0=point(left,2.63)
    local x1,y1=point(right,2.63)
    local _,y2=point(left,1.38)
    local dy=y2-y0
    self.mesh:setVertices({{x0,y0,0,0},{x1,y1,1,0},
        {x0,y0+dy,0,1},{x1,y1+dy,1,1}})
    if self.mesh:getTexture()~=image then self.mesh:setTexture(image) end
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(self.mesh,x,y,0,scale,scale,format.anchorX,format.anchorY)
end

function Decals:release()
    self.mesh:release()
    for _,image in pairs(self.images) do image:release() end
    for _,image in pairs(self.companyImages) do image:release() end
    for _,font in pairs(self.companyFonts) do font:release() end
end

return Decals
