-- The normalized atlas is baked offline. Runtime preparation performs one
-- bounded texture upload and keeps the prior filter, mipmap and wrap settings.
local Palette=require('src.commute.vendor.ground_materials')
local Ground={TILE_UNITS=4,FORMAT={{'VertexPosition','float',2},{'WorldHeight','float',1},{'GroundNormal','float',3},{'VertexTexCoord','float',2},
    {'GroundTextureCoord','float',2},{'GroundTexturePhase','float',2},
    {'VertexColor','float',4},{'GroundWeights','float',4},{'GroundVariants','float',3},{'WaterDepth','float',1}},
    PREPARE_BUDGET_MS=6}
Ground.__index=Ground
Ground.MAX_DESKTOP_UPLOAD_BYTES=4*1024*1024
Ground.MAX_MOBILE_UPLOAD_BYTES=1024*1024
function Ground.new(options)
    options=options or {}
    local mobile=options.mobile==true or love.system.getOS()=='Android'
    for _,v in ipairs(arg or {}) do if v=='--low-ground-memory' then mobile=true end end
    local cell=mobile and 128 or 256;local pad=mobile and 8 or 16
    local size=cell*4
    local self=setmetatable({images={},enabled=true,tileSize=cell,padding=pad,size=size,
        materialCount=#Palette.records,ready=false,nextMaterial=1,mobile=mobile,
        atlasPath=mobile and 'assets/commute/terrain/ground-mobile-v1.png'
            or 'assets/commute/terrain/ground-desktop-v1.png',
        uploadBudgetBytes=mobile and Ground.MAX_MOBILE_UPLOAD_BYTES or Ground.MAX_DESKTOP_UPLOAD_BYTES,
        bytes=4,lastPrepareMs=0,lastPrepareBytes=0,lastUploadMs=0,
        totalUploadedBytes=0,maxUploadBytes=0},Ground)
    for _,v in ipairs(arg or {}) do if v=='--flat-ground' then self.enabled=false end end
    local g=love.graphics
    self.shader=g.newShader(love.filesystem.read('src/commute/perspective.glsl')..'\n'
        ..love.filesystem.read('src/commute/vendor/ground.glsl'))
    local fallback=love.image.newImageData(1,1)
    fallback:setPixel(0,0,.42,.42,.42,1)
    self.atlas=g.newImage(fallback);fallback:release()
    self.atlas:setFilter('linear','linear');self.atlas:setWrap('clamp','clamp')
    self.images.atlas=self.atlas
    local inner=cell-pad*2
    self.shader:send('materialAtlas',self.atlas)
    self.shader:send('atlasInset',(pad+.5)/size);self.shader:send('atlasInner',(inner-1)/size)
    self.shader:send('groundDepthSpan',65536)
    self.shader:send('detailStrength',0);self.shader:send('seasonTint',{1,1,1})
    self.shader:send('detailFadeStart',65536);self.shader:send('detailFadeEnd',65537)
    self.shader:send('litterSeasonShift',0);self.shader:send('snowCoverage',0)
    self.shader:send('sunDirection',{0,1,0});self.shader:send('sunColor',{1,1,1})
    self.shader:send('sunlight',0);self.shader:send('ambientLight',.52)
    self.shader:send('moonDirection',{0,1,0});self.shader:send('moonColor',{.58,.69,.94})
    self.shader:send('moonlight',0);self.shader:send('waterSunDirection',{0,1,0})
    self.shader:send('waterMoonDirection',{0,1,0})
    return self
end
function Ground:prepare()
    if self.ready then return false end
    local started=love.timer.getTime()
    local g=love.graphics
    local atlas=g.newImage(self.atlasPath,{mipmaps=true})
    atlas:setFilter('linear','linear');atlas:setMipmapFilter('linear');atlas:setWrap('clamp','clamp')
    local uploadMs=(love.timer.getTime()-started)*1000
    local width,height=atlas:getDimensions()
    assert(width==self.size and height==self.size,'Unexpected prebaked ground atlas dimensions')
    local uploadBytes=width*height*4
    assert(uploadBytes<=self.uploadBudgetBytes,'Prebaked ground atlas exceeds upload budget')
    local fallback=self.atlas
    self.atlas=atlas;self.images.atlas=atlas
    self.shader:send('materialAtlas',atlas)
    fallback:release()
    self.lastPrepareBytes=uploadBytes;self.lastUploadMs=uploadMs
    self.totalUploadedBytes=self.totalUploadedBytes+uploadBytes
    self.maxUploadBytes=math.max(self.maxUploadBytes,uploadBytes)
    self.bytes=math.floor(self.lastPrepareBytes*4/3)
    self.lastPrepareMs=(love.timer.getTime()-started)*1000
    self.nextMaterial=self.materialCount+1
    self.ready=true
    return true
end
function Ground:release()
    for _,image in pairs(self.images) do image:release() end
    self.shader:release()
end
return Ground
