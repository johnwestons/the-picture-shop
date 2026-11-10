-- The receipt reuses the cargo sprites, job proof and vehicle company mark.
local Art={}
local marks
local function fitted(g,image,quad,x,y,w,h)
    local iw,ih=image:getDimensions()
    if quad then local _,_,qw,qh=quad:getViewport();iw,ih=qw,qh end
    local scale=math.min(w/iw,h/ih)
    g.setColor(1,1,1,1)
    if quad then g.draw(image,quad,x+(w-iw*scale)*.5,y+(h-ih*scale)*.5,0,scale,scale)
    else g.draw(image,x+(w-iw*scale)*.5,y+(h-ih*scale)*.5,0,scale,scale) end
end
function Art.draw(item,assets,rect)
    local g=love.graphics
    local Text=require('src.screens.typography')
    marks=marks or require('src.commute.truck_decals').new()
    local logo=marks:companyImage(item.supplier or 'The Picture Shop')
    if logo then fitted(g,logo,nil,rect.x,52,rect.width,69) end
    g.setFont(Text.get(12));g.setColor(.36,.31,.25,1)
    g.printf('SHIPMENT CONTENTS',rect.x,126,rect.width,'center')
    g.setColor(.98,.96,.89,1);g.rectangle('fill',rect.x,rect.y,rect.width,rect.height)
    g.setColor(.37,.33,.26,.8);g.setLineWidth(1)
    g.rectangle('line',rect.x,rect.y,rect.width,rect.height)
    -- Printed photo corners keep the preview feeling like part of the receipt.
    for _,corner in ipairs({{rect.x,rect.y,1,1},{rect.x+rect.width,rect.y,-1,1},
        {rect.x,rect.y+rect.height,1,-1},{rect.x+rect.width,rect.y+rect.height,-1,-1}}) do
        g.line(corner[1]+corner[3]*9,corner[2],corner[1],corner[2],corner[1],corner[2]+corner[4]*9)
    end
    local previews=item.previews or {{image='loadedPaperPalletDirections',quad='loadedPaperPallet1'}}
    local count=math.min(3,#previews)
    for i=1,count do
        local preview=previews[i]
        local image=assets and assets.get and assets.get(preview.image)
        local sprite=preview.quad and assets and assets.getQuad and assets.getQuad(preview.quad)
        if image and (not preview.quad or sprite) then
            local size=count>1 and 142 or 174
            local offset=count>1 and (i-1)*18 or 0
            fitted(g,image,sprite and sprite.quad,rect.x+6+offset,rect.y+7+offset,size,size)
        end
    end
    local proof=item.artworkKey and assets and assets.get and assets.get('artwork:'..item.artworkKey)
    if proof then
        local x,y=rect.x+rect.width-83,rect.y+rect.height-78
        g.setColor(.08,.07,.05,.22);g.rectangle('fill',x+3,y+3,77,72)
        g.setColor(1,.99,.95,1);g.rectangle('fill',x,y,77,72)
        fitted(g,proof,nil,x+4,y+4,69,64)
    end
    g.setFont(Text.get(12));g.setColor(.36,.31,.25,1)
    local caption=proof and 'PALLETS + CLIENT JOB ART' or 'CARGO ON THIS DELIVERY'
    g.printf(caption,rect.x-4,rect.y+rect.height+13,rect.width+8,'center')
end
return Art
