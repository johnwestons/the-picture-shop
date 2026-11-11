-- Central ceiling-light floor shadows. Small reusable masks union overlaps.
local Shapes=require('src.shadow_shapes')
local Config=require('src.config')
local Shadows={enabled=true,light={x=480,y=365,height=300},opacity=.18}
local staticMask,dynamicMask,staticKey,floorTriangles
local function floor()
    if floorTriangles then return floorTriangles end
    local points={};for _,p in ipairs(require('src.warehouse_registration').floorEdges.warehouse)do points[#points+1]=p[1];points[#points+1]=p[2]end
    points[#points+1]=960;points[#points+1]=678;points[#points+1]=0;points[#points+1]=678
    floorTriangles=love.math.triangulate(points);return floorTriangles
end
local function poly(points)
    if #points<6 then return end
    local ok,triangles=pcall(love.math.triangulate,points)
    if ok then for _,t in ipairs(triangles)do love.graphics.polygon('fill',t)end end
end
function Shadows.shape(p)
    local l=Shadows.light;local px,py=Shapes.point(p.x,p.y,p.height or 60,l.x,l.y,l.height)
    local dx,dy=px-p.x,py-p.y
    if p.kind=='person' then return Shapes.silhouette(Shapes.person,p.x,p.y,p.width or 24,dx,dy)end
    -- Ground footprints are registered in the room's authored screen plane.
    -- This point-light projection is affine-invariant for a flat floor.
    return Shapes.box(p.x,p.y,p.width or 30,p.depth or 12,dx,dy,p.angle or 0)
end
local function paint(canvas,items,base)
    local g=love.graphics;g.push('all');g.origin();g.setScissor();g.setShader();g.setCanvas({canvas,stencil=true});g.clear(0,0,0,0);g.scale(.5)
    if base then g.setBlendMode('alpha','premultiplied');g.setColor(1,1,1);g.draw(base,0,0,0,2,2)end
    g.stencil(function()for _,t in ipairs(floor())do g.polygon('fill',t)end end,'replace',1)
    g.setStencilTest('equal',1);g.setBlendMode('replace');g.setColor(1,1,1,1)
    for _,p in ipairs(items)do
        if p.kind=='skid_wrapper' then
            -- Broad low turntable plus narrow tall mast, not a tall solid box.
            poly(Shadows.shape({x=p.x,y=p.y,width=p.width,depth=p.depth,height=8}))
            poly(Shadows.shape({x=p.x-6,y=p.y-12,width=5,depth=5,height=105}))
        elseif p.kind=='polar_115' then
            poly(Shadows.shape({x=p.x,y=p.y,width=p.width,depth=p.depth,height=42}))
            poly(Shadows.shape({x=p.x,y=p.y-10,width=p.width*.88,depth=5,height=82}))
        elseif p.kind=='heidelberg_10x15' then
            poly(Shadows.shape({x=p.x,y=p.y,width=p.width*.65,depth=p.depth,height=55}))
            poly(Shadows.shape({x=p.x,y=p.y-8,width=p.width*.9,depth=6,height=80}))
        else poly(Shadows.shape(p))end
    end;g.pop()
end
function Shadows.draw(static,moving,powered)
    if not Shadows.enabled or not require('src.video_settings').current.dynamicShadows or powered==false then return end
    local g=love.graphics
    if not staticMask then
        staticMask=g.newCanvas(480,339,{dpiscale=1});dynamicMask=g.newCanvas(480,339,{dpiscale=1})
        staticMask:setFilter('linear','linear');dynamicMask:setFilter('linear','linear')
    end
    local keys={Shadows.light.x,Shadows.light.y,Shadows.light.height}
    for _,p in ipairs(static)do keys[#keys+1]=table.concat({p.x,p.y,p.width or 0,p.depth or 0,p.height or 0,p.angle or 0,p.kind or ''},',')end
    local key=table.concat(keys,';')
    if key~=staticKey then paint(staticMask,static);staticKey=key end
    paint(dynamicMask,moving,staticMask)
    g.push('all');g.setShader();g.setColor(.035,.045,.065,Shadows.opacity);g.setBlendMode('alpha','alphamultiply');g.draw(dynamicMask,0,0,0,2,2);g.pop()
end
function Shadows.scene(world,state,remote,employees,pallets,machines,placements)
    local static,moving={},{}
    local function add(list,p,kind,w,d,h)
        if p and type(p.x)=='number' and type(p.y)=='number' and (p.sceneId or 'warehouse')=='warehouse' then
            list[#list+1]={x=p.x,y=p.y,kind=kind,width=w,depth=d,height=h}
        end
    end
    for _,m in ipairs(machines)do
        local p=m.world or placements[m.modelId]
        local config=({polar_115=Config.cutterPlacement,skid_wrapper=Config.wrapperPlacement,heidelberg_10x15=Config.windmillPlacement,
            regal_folder=Config.regalFolderPlacement,chandler_price=Config.chandlerPricePlacement})[m.modelId]
        if p and config then
            -- Moving machinery is carried at the active jack's position.
            local pose=p.moving and placements._jack or p
            add(p.moving and moving or static,pose,m.modelId,config.collisionHalfWidth or 35,config.collisionHalfHeight or 15,m.modelId=='skid_wrapper' and 105 or 75)
        end
    end
    local forklift=state.forklift
    if forklift and forklift.owned then add(moving,forklift,'vehicle',28,13,65)end
    local carried={}
    if forklift and forklift.carriedPalletId then carried[forklift.carriedPalletId]=true end
    for _,jack in ipairs(require('src.pallet_jack_fleet').all(state))do
        add(moving,jack,'vehicle',25,9,32)
        if jack.carriedPalletId then carried[jack.carriedPalletId]=true end
    end
    add(moving,world.player,'person',24,10,68)
    for _,p in ipairs(remote or {})do add(moving,p,'person',24,10,68)end
    for _,entry in ipairs(employees or {})do add(moving,entry.actor,'person',23,10,65)end
    if world.customer.visible then add(moving,world.customer,'person',25,10,68)end
    if world.vendor.visible then add(moving,world.vendor,'person',25,10,68)end
    local tech=require('src.technician').presentation(state)
    if tech and tech.visible then add(moving,tech,'person',24,10,68)end
    for _,p in ipairs(pallets or {})do
        if p.pallet and not carried[p.pallet.id] and (p.pallet.world.sceneId or 'warehouse')=='warehouse' then add(static,p,'crate',30,11,30)end
    end
    Shadows.draw(static,moving,require('src.warehouse_condition').lit(state))
end
function Shadows.release()
    if staticMask then staticMask:release();dynamicMask:release()end
    staticMask,dynamicMask,staticKey=nil,nil,nil
end
return Shadows
