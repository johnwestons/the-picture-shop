-- Draw floor props as ordinary 2D sprites in the 3D scene. The only geometry
-- here is a flat camera-facing quad; the prop itself always comes from its
-- authored raster frame and is never modeled procedurally.
local G=require('src.warehouse_perspective_geometry')
local S={}
local format={{'VertexPosition','float',2},{'WorldHeight','float',1},{'VertexTexCoord','float',2}}

function S.prepare(item)
    local data=love.image.newImageData(item.path)
    item.bottomRows={};item.pivotRows={}
    for frame=1,item.frames do
        local frameX=((frame-1)%item.frameColumns)*item.frameWidth
        local frameY=math.floor((frame-1)/item.frameColumns)*item.frameHeight
        local rows={};local bottom
        for y=0,item.frameHeight-1 do
            rows[y]=0
            for x=0,item.frameWidth-1 do
                local _,_,_,alpha=data:getPixel(frameX+x,frameY+y)
                if alpha>0.35 then rows[y]=rows[y]+1;bottom=y end
            end
        end
        bottom=bottom or math.floor(item.frameHeight*(item.anchor or 1))-1
        local pivot=bottom+1
        if item.contactStrategy=='wide-support' then
            local maxRow=0
            for y=math.floor(item.frameHeight*.55),bottom do maxRow=math.max(maxRow,rows[y] or 0) end
            local threshold=maxRow*(item.contactWidthFraction or .28)
            for y=bottom,math.floor(item.frameHeight*.55),-1 do
                if rows[y]>=threshold then pivot=y+1;break end
            end
        end
        item.bottomRows[frame]=bottom
        item.pivotRows[frame]=pivot
    end
    data:release()
end

function S.sprite(item,yaw)
    if item.spriteQuad and item.lastYaw==yaw and item.lastX==item.worldX and item.lastZ==item.worldZ
        and item.lastRotation==item.rotation then return item.spriteQuad end

    item.lastYaw,item.lastX,item.lastZ,item.lastRotation=yaw,item.worldX,item.worldZ,item.rotation
    local delta=(yaw-G.YAW+math.pi*2)%(math.pi*2)
    local sector
    if item.frames==64 then
        sector=math.floor((math.pi*.25-yaw+(item.rotation or 0))/(math.pi*2/64)+.5)%64
    else
        sector=math.floor(delta/(2*math.pi/item.frames)+.5)%item.frames
    end
    -- The cutter, wrapper, and pallet atlases share a row-major 64-step turntable order.
    local frame=item.frames==64 and sector+1
        or item.frames==4 and ({1,2,4,3})[sector+1] or sector+1
    item.frame=frame

    local col=(frame-1)%item.frameColumns
    local row=math.floor((frame-1)/item.frameColumns)
    local bottom=item.bottomRows[frame] or item.frameHeight-1
    local pivot=item.pivotRows[frame] or bottom+1
    local pixel=item.drawScale/G.SCALE
    local halfWidth=item.frameWidth*pixel*.5
    local topHeight=pivot*pixel/math.cos(G.ELEVATION)
    local bottomHeight=(pivot-(bottom+1))*pixel/math.cos(G.ELEVATION)
    -- Keep the cutout vertical and facing the camera. The authored support row
    -- sits on the registered floor point; details below it can dip beneath the floor.
    local rx,rz=-math.sin(yaw),math.cos(yaw)
    local leftX,leftZ=item.worldX-rx*halfWidth,item.worldZ-rz*halfWidth
    local rightX,rightZ=item.worldX+rx*halfWidth,item.worldZ+rz*halfWidth
    local u0,u1=col/item.frameColumns,(col+1)/item.frameColumns
    local v0=(row)/item.frameRows
    local v1=(row+(bottom+1)/item.frameHeight)/item.frameRows
    local vertices={
        {leftX,leftZ,topHeight,u0,v0},{rightX,rightZ,topHeight,u1,v0},{rightX,rightZ,bottomHeight,u1,v1},
        {leftX,leftZ,topHeight,u0,v0},{rightX,rightZ,bottomHeight,u1,v1},{leftX,leftZ,bottomHeight,u0,v1},
    }
    if item.spriteQuad then item.spriteQuad:setVertices(vertices)
    else item.spriteQuad=love.graphics.newMesh(format,vertices,'triangles','dynamic');item.spriteQuad:setTexture(item.image) end
    return item.spriteQuad
end

function S.shadow(item)
    if not S.shadowTexture then
        local data=love.image.newImageData(64,64)
        for y=0,63 do for x=0,63 do
            local radius=((x-31.5)/31.5)^2+((y-31.5)/31.5)^2
            data:setPixel(x,y,1,1,1,math.max(0,1-radius)^2)
        end end
        S.shadowTexture=love.graphics.newImage(data);data:release()
    end
    local radius=item.id=='cutter' and 1.25 or item.id=='wrapper' and .95
        or item.id=='forklift' and 1.45 or item.id=='palletJack' and 1.0 or .70
    local x,z=item.worldX,item.worldZ
    local a,b,c,d={x-radius,z-radius,.012,0,0},{x+radius,z-radius,.012,1,0},
        {x+radius,z+radius,.012,1,1},{x-radius,z+radius,.012,0,1}
    local vertices={a,b,c,a,c,d}
    if item.shadow then item.shadow:setVertices(vertices)
    else item.shadow=love.graphics.newMesh(format,vertices,'triangles','dynamic');item.shadow:setTexture(S.shadowTexture) end
    return item.shadow
end

return S
