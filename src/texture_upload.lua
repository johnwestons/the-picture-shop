-- Preserve source resolution and straight-alpha pixels while bounding each
-- frame's transfer. A large atlas is assembled into a drawable Texture over
-- several updates, rather than uploading its entire pixel buffer at once.
local Upload={}
Upload.__index=Upload
local BUDGET=2*1024*1024
function Upload.new(data)
    local width,height=data:getDimensions()
    return setmetatable({data=data,width=width,height=height,row=0},Upload)
end
function Upload:release()
    if self.data then self.data:release();self.data=nil end
    if self.texture then self.texture:release();self.texture=nil end
end
function Upload:step()
    if self.width*self.height*4<=BUDGET then
        local image=love.graphics.newImage(self.data)
        self.data:release();self.data=nil
        return image
    end
    local rows=math.min(self.height-self.row,math.max(1,math.floor(BUDGET/(self.width*4))))
    local tile=love.image.newImageData(self.width,rows)
    tile:paste(self.data,0,0,0,self.row,self.width,rows)
    local image=love.graphics.newImage(tile)
    tile:release()
    love.graphics.push("all")
    local okay,reason=pcall(function()
        if not self.texture then
            self.texture=love.graphics.newCanvas(self.width,self.height,{format="rgba8",dpiscale=1})
            love.graphics.setCanvas(self.texture);love.graphics.clear(0,0,0,0)
        else love.graphics.setCanvas(self.texture) end
        love.graphics.origin();love.graphics.setScissor();love.graphics.setShader();love.graphics.setStencilTest()
        love.graphics.setColorMask(true,true,true,true)
        love.graphics.setColor(1,1,1,1);love.graphics.setBlendMode("replace","premultiplied")
        love.graphics.draw(image,0,self.row)
    end)
    love.graphics.pop()
    image:release()
    if not okay then error(reason,0) end
    self.row=self.row+rows
    if self.row==self.height then
        self.data:release();self.data=nil
        local texture=self.texture;self.texture=nil
        return texture
    end
end
return Upload
