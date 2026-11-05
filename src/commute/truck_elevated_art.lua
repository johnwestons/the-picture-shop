-- One isometric pitch for the outside sprite. Only its bearing turns with the camera.
local Cab=require('src.commute.truck_cab_mesh')
local Elevated={}
Elevated.__index=Elevated

local cargo={rear=-2.72,front=1.47,halfWidth=1.08,height=2.89}
local regions={
    -- Start each face on the painted edge so the roof and walls meet.
    cargoRoof={4,9,1536,511},cargoSide={2,543,439,289},
    shutter={583,542,271,371},
    -- Sample a single clean cargo-panel patch. The old crop included a full
    -- side-view truck, which appeared as a second truck on the front cap.
    bulkhead={600,50,230,430},
}

function Elevated.new()
    local image=love.graphics.newImage('assets/commute/truck/elevated-panels.png',{mipmaps=true})
    image:setFilter('linear','linear')
    image:setMipmapFilter('linear')
    local faces={}
    for name,r in pairs(regions) do
        faces[name]=love.graphics.newQuad(r[1],r[2],r[3],r[4],image:getDimensions())
    end
    return setmetatable({image=image,faces=faces,cab=Cab.new(image),transform=love.math.newTransform()},Elevated)
end

-- O, U and V are the projected top-left, top-right and bottom-left corners.
function Elevated:panel(name,ox,oy,ux,uy,vx,vy)
    local r=regions[name]
    self.transform:setMatrix('row',
        (ux-ox)/r[3],(vx-ox)/r[4],0,ox,
        (uy-oy)/r[3],(vy-oy)/r[4],0,oy,
        0,0,1,0, 0,0,0,1)
    love.graphics.draw(self.image,self.faces[name],self.transform)
end

function Elevated:draw(x,y,zoom,angle,decal,pitchDegrees,verticalBase)
    local s,c=math.sin(angle),math.cos(angle)
    local pitch=math.rad(pitchDegrees or 32)
    local horizontal=48*zoom
    local depth=35.4*math.sin(pitch)*zoom
    local vertical=(verticalBase or 38.4)*math.cos(pitch)*zoom
    local function point(length,width,height)
        return x+horizontal*(length*s+width*c),y+depth*(-length*c+width*s)-vertical*height
    end
    if c>=0 then Cab.draw(self.cab,self.transform,x,y,horizontal,depth,vertical,s,c) end
    do
        local a,b,w,h=cargo.rear,cargo.front,cargo.halfWidth,cargo.height
        local near=s>=0 and w or -w
        if math.abs(s)>.0001 then
            local ox,oy=point(a,near,h)
            local ux,uy=point(b,near,h)
            self:panel('cargoSide',ox,oy,ux,uy,point(a,near,0))
            if decal then
                local left,right=a+.08*(b-a),b-.08*(b-a)
                if s<0 then left,right=right,left end
                local x0,y0=point(left,near,2.63)
                local x1,y1=point(right,near,2.63)
                local _,y2=point(left,near,1.38)
                local width,height=decal:getDimensions()
                self.transform:setMatrix('row',
                    (x1-x0)/width,0,0,x0, (y1-y0)/width,(y2-y0)/height,0,y0,
                    0,0,1,0, 0,0,0,1)
                love.graphics.draw(decal,self.transform)
            end
        end
        if math.abs(c)>.0001 then
            local rear=c>0
            local endX=rear and a or b
            local left=rear and -w or w
            local name=rear and 'shutter' or 'bulkhead'
            local ox,oy=point(endX,left,h)
            local ux,uy=point(endX,-left,h)
            self:panel(name,ox,oy,ux,uy,point(endX,left,name=='bulkhead' and .95 or 0))
        end
        local ox,oy=point(a,-w,h)
        local ux,uy=point(b,-w,h)
        self:panel('cargoRoof',ox,oy,ux,uy,point(a,w,h))
    end
    if c<0 then Cab.draw(self.cab,self.transform,x,y,horizontal,depth,vertical,s,c) end
end

function Elevated:release()
    self.cab.left:release()
    self.cab.right:release()
    for _,quad in pairs(self.faces) do quad:release() end
    self.transform:release()
    self.image:release()
end

return Elevated
