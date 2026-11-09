local G=require('src.warehouse_perspective_geometry')
local Sprites=require('tools.warehouse_perspective_lab.grounded_sprites')
return function(objects)
    local worst=0
    for _,item in ipairs(objects) do
        local mesh=Sprites.mesh(item,G.YAW)
        for i=1,mesh:getVertexCount(),17 do
            local x,z,h,u,v=mesh:getVertex(i)
            local sx,sy=G.sourcePoint(x,z,h)
            local expectedX=item.x+(u*item.frames-.5)*item.frameWidth*item.drawScale
            local expectedY=item.y+(v-item.anchor)*item.frameHeight*item.drawScale
            worst=math.max(worst,math.abs(sx-expectedX),math.abs(sy-expectedY))
        end
        for sector=0,15 do
            local m=Sprites.mesh(item,G.YAW+sector*math.pi/8)
            for i=1,m:getVertexCount(),127 do
                local x,z,h=m:getVertex(i)
                assert(x==x and z==z and h==h and math.abs(h)<20,'Invalid sprite surface')
            end
        end
    end
    assert(worst<.002,'Source-angle registration drift: '..worst)
    local Fixtures=require('tools.warehouse_perspective_lab.fixtures')
    assert(Fixtures.insideExtension(G.floorPoint(632,194)),'Back-room floor inaccessible')
    assert(not Fixtures.insideExtension(G.floorPoint(400,400)),'Extension bounds leak')
    print(string.format('PASS: source registration max error %.6f px; 16 angles per sprite; extension bounds',worst))
end
