-- North-up navigation shared by the real trip and the ride preview. Terrain,
-- roads and footprints are cached once; only navigation markers change per frame.
local Map={RESOLUTION=96};Map.__index=Map
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
local function finite(n,fallback)return type(n)=='number' and n==n and math.abs(n)<math.huge and n or fallback end
local function bounds(world)
    local b=world.bounds or world.playableBounds or {}
    local x0,z0=b.x0 or b.minX or 0,b.z0 or b.minZ or 0
    local x1,z1=b.x1 or b.maxX or world.size or 512,b.z1 or b.maxZ or world.size or 512
    for _,site in ipairs(world.sites and world.sites.all or {}) do
        local f=site.foundation
        if f then x0,z0=math.min(x0,f.minX),math.min(z0,f.minZ);x1,z1=math.max(x1,f.maxX),math.max(z1,f.maxZ)end
    end
    return {x0=x0,z0=z0,x1=math.max(x0+1,x1),z1=math.max(z0+1,z1)}
end
Map.bounds=bounds
function Map.layout(rect,count)
    local pad=16;local contentHeight=math.max(80,rect.height-96)
    local rows=math.max(1,math.floor(contentHeight/24))
    local columns=math.max(1,math.ceil((count or 0)/rows))
    local keyWidth=math.min(rect.width*.58,math.max(250,columns*210))
    return {panel=rect,map={x=rect.x+pad,y=rect.y+47,width=rect.width-keyWidth-pad*3,height=contentHeight},
        key={x=rect.x+rect.width-keyWidth-pad,y=rect.y+47,width=keyWidth,height=contentHeight},
        columns=columns,rows=rows,rowHeight=contentHeight/rows,columnWidth=keyWidth/columns,
        footerY=rect.y+rect.height-35}
end
local function fitted(world,rect)
    local b=bounds(world);local scale=math.min(rect.width/(b.x1-b.x0),rect.height/(b.z1-b.z0))
    return {x=rect.x+(rect.width-(b.x1-b.x0)*scale)*.5,y=rect.y+(rect.height-(b.z1-b.z0)*scale)*.5,
        width=(b.x1-b.x0)*scale,height=(b.z1-b.z0)*scale,scale=scale,bounds=b}
end
function Map.project(world,rect,x,z)
    local v=fitted(world,rect)
    return v.x+(x-v.bounds.x0)*v.scale,v.y+(z-v.bounds.z0)*v.scale,v
end
local compass={'E','SE','S','SW','W','NW','N','NE'}
function Map.headingLabel(heading)return compass[math.floor((heading+math.pi/8)/(math.pi/4))%8+1]end
function Map.new(world)
    local self=setmetatable({world=world,entries={},fonts={},backgroundBuilds=0,terrainSamples=0},Map)
    local destinations=world.roads and world.roads.destinations or {}
    for _,site in ipairs(world.sites and world.sites.all or {})do
        local destination=destinations[site.id]
        self.entries[#self.entries+1]={id=site.id,site=site,label=destination and destination.label
            or site.design and site.design.label or site.id:gsub('%-',' ')}
    end
    table.sort(self.entries,function(a,b)return a.id<b.id end)
    for i,entry in ipairs(self.entries)do entry.index=i end
    return self
end
function Map:snapshot(rect,actor,options)
    options=options or {};actor=actor or {}
    local layout=Map.layout(rect,#self.entries)
    local x,y,viewport=Map.project(self.world,layout.map,finite(actor.x,0),finite(actor.z,0))
    local heading=finite(actor.heading,0);local dx,dz=math.cos(heading),math.sin(heading)
    local result={layout=layout,viewport=viewport,marker={x=x,y=y,heading=heading,dx=dx,dz=dz,
        tipX=x+dx*13,tipY=y+dz*13,label=Map.headingLabel(heading)},buildings={},recreation={}}
    local placed={}
    local function free(bx,by)
        if bx<viewport.x+9 or bx>viewport.x+viewport.width-9 or by<viewport.y+9 or by>viewport.y+viewport.height-9 then return false end
        for _,p in ipairs(placed)do if math.abs(p.x-bx)<20 and math.abs(p.y-by)<20 then return false end end
        return true
    end
    for i,entry in ipairs(self.entries)do
        local site=entry.site;local ax,ay=Map.project(self.world,layout.map,site.x or site.origin.x,site.z or site.origin.z)
        local bx,by=clamp(ax,viewport.x+9,viewport.x+viewport.width-9),clamp(ay,viewport.y+9,viewport.y+viewport.height-9)
        if not free(bx,by)then
            local found=false
            for radius=20,80,20 do
                for step=0,7 do
                    local angle=step*math.pi/4;local nx,ny=ax+math.cos(angle)*radius,ay+math.sin(angle)*radius
                    if free(nx,ny)then bx,by=nx,ny;found=true;break end
                end
                if found then break end
            end
        end
        placed[#placed+1]={x=bx,y=by}
        local column=math.floor((i-1)/layout.rows);local row=(i-1)%layout.rows
        result.buildings[i]={id=entry.id,index=i,label=entry.label,x=bx,y=by,anchorX=ax,anchorY=ay,
            destination=entry.id==options.destination,home=entry.id==options.home,
            keyRect={x=layout.key.x+column*layout.columnWidth,y=layout.key.y+row*layout.rowHeight,
                width=layout.columnWidth-7,height=layout.rowHeight-2}}
    end
    if options.bike then
        local bx,by=Map.project(self.world,layout.map,options.bike.x,options.bike.z)
        result.bike={x=bx,y=by}
    end
    for _,area in ipairs(self.world.town and self.world.town.recreation or {})do
        local px,py=Map.project(self.world,layout.map,area.x,area.z)
        result.recreation[#result.recreation+1]={id=area.id,x=px,y=py,kind=area.kind,label=area.label}
    end
    return result
end
function Map:label(id)
    for _,entry in ipairs(self.entries) do if entry.id==id then return entry.label end end
end
function Map:miniSnapshot(rect,actor,options)
    options=options or {};actor=actor or {}
    local mapRect={x=rect.x+7,y=rect.y+25,width=math.max(1,rect.width-14),height=math.max(1,rect.height-32)}
    local _,_,viewport=Map.project(self.world,mapRect,0,0)
    local result={viewport=viewport,buildings={},destination=options.destination}
    local placed={}
    local function free(x,y)
        if x<viewport.x+7 or x>viewport.x+viewport.width-7 or y<viewport.y+7 or y>viewport.y+viewport.height-7 then return false end
        for _,p in ipairs(placed) do if math.abs(p.x-x)<15 and math.abs(p.y-y)<15 then return false end end
        return true
    end
    for i,entry in ipairs(self.entries) do
        local site=entry.site;local ax,ay=Map.project(self.world,mapRect,site.x or site.origin.x,site.z or site.origin.z)
        local x,y=ax,ay
        if not free(x,y) then
            local found=false
            for radius=15,45,10 do
                for step=0,15 do
                    local angle=step*math.pi/8;local nx,ny=ax+math.cos(angle)*radius,ay+math.sin(angle)*radius
                    if free(nx,ny) then x,y=nx,ny;found=true;break end
                end
                if found then break end
            end
            x=math.max(viewport.x+7,math.min(viewport.x+viewport.width-7,x))
            y=math.max(viewport.y+7,math.min(viewport.y+viewport.height-7,y))
        end
        placed[#placed+1]={x=x,y=y}
        result.buildings[#result.buildings+1]={id=entry.id,index=entry.index,label=entry.label,
            x=x,y=y,anchorX=ax,anchorY=ay,destination=entry.id==options.destination}
    end
    local x,y=Map.project(self.world,mapRect,finite(actor.x,0),finite(actor.z,0))
    local heading=finite(actor.heading,0)
    result.marker={x=x,y=y,heading=heading,dx=math.cos(heading),dz=math.sin(heading)}
    return result
end
function Map:hit(rect,x,y,actor,options)
    local s=self:snapshot(rect,actor,options)
    local nearest,best
    for _,entry in ipairs(s.buildings) do
        local k=entry.keyRect
        if x>=k.x and x<=k.x+k.width and y>=k.y and y<=k.y+k.height then return entry.id end
        local distance=(x-entry.x)^2+(y-entry.y)^2
        if distance<=15*15 and (not best or distance<best) then nearest,best=entry.id,distance end
    end
    return nearest
end
function Map:hitMini(rect,x,y,actor,options)
    local s=self:miniSnapshot(rect,actor,options)
    local nearest,best
    for _,entry in ipairs(s.buildings) do
        local distance=(x-entry.x)^2+(y-entry.y)^2
        if distance<=12*12 and (not best or distance<best) then nearest,best=entry.id,distance end
    end
    return nearest
end
function Map:prepare()
    if self.background or self.released then return end
    local g=love.graphics;local n=Map.RESOLUTION;local b=bounds(self.world)
    local heights,high={},1
    for z=0,n-1 do for x=0,n-1 do
        local h=self.world:height(b.x0+(x+.5)/n*(b.x1-b.x0),b.z0+(z+.5)/n*(b.z1-b.z0))
        heights[z*n+x+1]=h;high=math.max(high,h)
    end end
    self.terrainSamples=self.terrainSamples+n*n
    local data=love.image.newImageData(n,n)
    data:mapPixel(function(x,z)
        local h=heights[z*n+x+1]
        if h<=(self.world.waterLevel or 0) then return .09,.27,.37,1 end
        local t=clamp(h/high,0,1);return .17+t*.24,.29+t*.23,.21+t*.11,1
    end)
    local terrain=g.newImage(data);data:release();terrain:setFilter('linear','linear')
    self.background=g.newCanvas(512,512);self.background:setFilter('linear','linear')
    g.push('all');g.setCanvas(self.background);g.origin();g.setScissor();g.setStencilTest()
    g.clear(.04,.09,.08,1);g.setShader();g.setColor(1,1,1)
    g.draw(terrain,0,0,0,512/n,512/n)
    local function at(x,z)return (x-b.x0)/(b.x1-b.x0)*512,(z-b.z0)/(b.z1-b.z0)*512 end
    g.setColor(.39,.49,.43,.25);g.setLineWidth(1)
    for i=0,8 do g.line(i*64,0,i*64,512);g.line(0,i*64,512,i*64)end
    for _,path in ipairs(self.world.roads and self.world.roads.paths or {})do
        g.setColor(path.surface=='dirt' and {.66,.43,.23,1} or path.role=='main' and {.90,.83,.61,1} or {.77,.74,.60,1})
        local points={};for _,p in ipairs(path.points)do local x,y=at(p.x,p.z);points[#points+1]=x;points[#points+1]=y end
        if #points>=4 then g.setLineWidth(math.max(1.8,(path.width or 4)*512/(b.x1-b.x0)));g.line(points)end
    end
    g.setLineWidth(1);g.setColor(.70,.80,.79,1)
    for _,entry in ipairs(self.entries)do for _,footprint in ipairs(entry.site.footprints or {})do
        local points={};for _,p in ipairs(footprint.corners)do local x,y=at(p.x,p.z);points[#points+1]=x;points[#points+1]=y end
        if #points>=6 then g.polygon('fill',points)end
    end end
    g.pop();terrain:release();self.backgroundBuilds=self.backgroundBuilds+1
end
local function badge(g,x,y,index,color,font)
    g.setColor(.025,.05,.05,.98);g.circle('fill',x,y,9)
    g.setColor(color);g.setLineWidth(1.5);g.circle('line',x,y,9)
    g.setFont(font);g.printf(tostring(index),x-10,y-font:getHeight()/2,20,'center')
end
function Map:font(size)
    if not self.fonts[size]then self.fonts[size]=love.graphics.newFont(size)end
    return self.fonts[size]
end
function Map:draw(rect,actor,options)
    if self.released then return end
    options=options or {};self:prepare()
    local s=self:snapshot(rect,actor,options);local g=love.graphics;local v=s.viewport
    g.push('all');g.setShader();g.setColor(.025,.05,.047,.98);g.rectangle('fill',rect.x,rect.y,rect.width,rect.height,8)
    g.setColor(.43,.57,.51,1);g.setLineWidth(1);g.rectangle('line',rect.x,rect.y,rect.width,rect.height,8)
    g.setFont(self:font(17));g.setColor(.98,.87,.52,1);g.print('TOWN MAP',rect.x+16,rect.y+13)
    g.setFont(self:font(12));g.setColor(.79,.86,.81,1)
    g.printf(options.closeHint or 'North up',rect.x+185,rect.y+16,rect.width-205,'right')
    g.setColor(1,1,1);g.draw(self.background,v.x,v.y,0,v.width/512,v.height/512)
    g.setColor(.44,.56,.51,1);g.rectangle('line',v.x,v.y,v.width,v.height)
    if options.route and options.route.points then
        local points={}
        for _,p in ipairs(options.route.points)do
            points[#points+1]=v.x+(p.x-v.bounds.x0)*v.scale
            points[#points+1]=v.y+(p.z-v.bounds.z0)*v.scale
        end
        if #points>=4 then g.setColor(.98,.65,.20,.9);g.setLineWidth(3);g.line(points)end
    end
    local numberFont=self:font(11);local labelFont=self:font(s.layout.columns>2 and 10 or 12)
    for _,entry in ipairs(s.buildings)do
        local color=entry.destination and {1,.73,.24,1} or entry.home and {.55,.91,.61,1} or {.81,.89,.85,1}
        g.setColor(color);g.setLineWidth(1);g.line(entry.anchorX,entry.anchorY,entry.x,entry.y)
        if entry.destination or entry.home then g.circle('line',entry.anchorX,entry.anchorY,12)end
        badge(g,entry.x,entry.y,entry.index,color,numberFont)
        local key=entry.keyRect
        if entry.destination or entry.home then g.setColor(color[1],color[2],color[3],.10);g.rectangle('fill',key.x,key.y,key.width,key.height,3)end
        badge(g,key.x+11,key.y+key.height/2,entry.index,color,numberFont)
        g.setFont(labelFont);g.setColor(color)
        local available=key.width-28;local _,lines=labelFont:getWrap(entry.label,available)
        local font=labelFont
        if #lines*font:getHeight()>key.height then font=self:font(10);g.setFont(font);_,lines=font:getWrap(entry.label,available)end
        g.printf(entry.label,key.x+26,key.y+math.max(0,(key.height-#lines*font:getHeight())/2),available,'left')
    end
    for _,area in ipairs(s.recreation)do
        g.setColor(.055,.15,.09,1);g.circle('fill',area.x,area.y,9)
        g.setColor(.65,.95,.67,1);g.setLineWidth(1.5);g.circle('line',area.x,area.y,9)
        g.setFont(self:font(11));g.printf(area.kind=='camp' and 'C' or 'P',area.x-9,area.y-6,18,'center')
        local label=area.label or (area.kind=='camp' and 'Campsite' or area.kind=='park' and 'Park' or 'Picnic area')
        local width=math.min(148,self:font(10):getWidth(label)+6)
        local x=clamp(area.x+12,v.x+2,v.x+v.width-width-2)
        local y=clamp(area.y-7,v.y+2,v.y+v.height-16)
        g.setColor(.025,.06,.04,.96);g.rectangle('fill',x,y,width,15,3)
        g.setColor(.75,.95,.70);g.setFont(self:font(10));g.printf(label,x+3,y+1,width-6,'left')
    end
    if s.bike then
        g.setColor(.93,.91,.71,1);g.setLineWidth(2);g.rectangle('line',s.bike.x-4,s.bike.y-4,8,8)
        g.setFont(self:font(10));g.print('BIKE',clamp(s.bike.x-28,v.x+2,v.x+v.width-30),clamp(s.bike.y+8,v.y+2,v.y+v.height-12))
    end
    local m=s.marker;local points={m.tipX,m.tipY,m.x-m.dx*8-m.dz*7,m.y-m.dz*8+m.dx*7,
        m.x-m.dx*4,m.y-m.dz*4,m.x-m.dx*8+m.dz*7,m.y-m.dz*8-m.dx*7}
    g.setColor(.01,.04,.05,1);g.setLineWidth(4);g.polygon('line',points)
    g.setColor(.24,1,.94,1);g.polygon('fill',points)
    local lx,ly=clamp(m.x+15,v.x+3,v.x+v.width-38),clamp(m.y-23,v.y+3,v.y+v.height-18)
    g.setColor(.02,.06,.06,.95);g.rectangle('fill',lx-2,ly-1,35,17,3)
    g.setColor(.24,1,.94,1);g.setFont(self:font(12));g.print('YOU',lx,ly)
    g.setColor(.93,.94,.84,1);g.setLineWidth(2);g.line(v.x+17,v.y+33,v.x+17,v.y+13)
    g.polygon('fill',v.x+17,v.y+9,v.x+13,v.y+17,v.x+21,v.y+17);g.print('N',v.x+12,v.y+36)
    g.setFont(self:font(12));g.setColor(.24,1,.94,1)
    g.print('YOU  /  Heading '..m.label,rect.x+16,s.layout.footerY)
    g.setColor(1,.73,.24,1);g.print('Gold: destination',rect.x+218,s.layout.footerY)
    g.setColor(.55,.91,.61,1);g.print('Green: your home',rect.x+370,s.layout.footerY)
    g.setColor(.79,.86,.81,1);g.printf(#s.recreation>0 and 'Brown: trails · P/C: park / camp' or 'Numbers identify buildings',rect.x+540,s.layout.footerY,rect.width-556,'right')
    g.pop()
    return s
end
function Map:drawMini(rect,actor,options)
    if self.released then return end
    options=options or {};self:prepare()
    local s=self:miniSnapshot(rect,actor,options);local g=love.graphics;local v=s.viewport
    g.push('all');g.setShader();g.setColor(.025,.05,.047,.96)
    g.rectangle('fill',rect.x,rect.y,rect.width,rect.height,7)
    g.setColor(.43,.57,.51,.96);g.setLineWidth(1);g.rectangle('line',rect.x,rect.y,rect.width,rect.height,7)
    g.setFont(self:font(11));g.setColor(.98,.87,.52,1)
    local title='NAV  ·  '..(self:label(options.destination) or 'Choose a building')
    if options.route and options.route.length then title=title..('  ·  %dm'):format(math.floor(options.route.length+.5)) end
    local titleScale=math.min(1,(rect.width-16)/math.max(1,g.getFont():getWidth(title)))
    g.print(title,rect.x+8,rect.y+7,0,titleScale,titleScale)
    g.setColor(1,1,1);g.draw(self.background,v.x,v.y,0,v.width/512,v.height/512)
    g.setColor(.44,.56,.51,1);g.rectangle('line',v.x,v.y,v.width,v.height)
    if options.route and options.route.points then
        local points={}
        for _,p in ipairs(options.route.points) do
            points[#points+1]=v.x+(p.x-v.bounds.x0)*v.scale
            points[#points+1]=v.y+(p.z-v.bounds.z0)*v.scale
        end
        if #points>=4 then
            g.setColor(.02,.05,.04,.95);g.setLineWidth(4);g.line(points)
            g.setColor(1,.66,.18,1);g.setLineWidth(2.4);g.line(points)
        end
    end
    local numberFont=self:font(9)
    for _,entry in ipairs(s.buildings) do
        if math.abs(entry.x-entry.anchorX)+math.abs(entry.y-entry.anchorY)>2 then
            g.setColor(.87,.91,.78,.85);g.setLineWidth(1);g.line(entry.anchorX,entry.anchorY,entry.x,entry.y)
        end
        local color=entry.destination and {1,.70,.18,1} or {.90,.94,.84,1}
        g.setColor(.025,.05,.05,.98);g.circle('fill',entry.x,entry.y,7)
        g.setColor(color);g.setLineWidth(entry.destination and 1.8 or 1);g.circle('line',entry.x,entry.y,7)
        g.setFont(numberFont);g.printf(tostring(entry.index),entry.x-7,entry.y-5.5,14,'center')
    end
    local m=s.marker;local dx,dz=m.dx,m.dz
    g.setColor(.02,.06,.06,1);g.circle('fill',m.x,m.y,7)
    g.setColor(.24,1,.94,1);g.circle('line',m.x,m.y,7)
    g.polygon('fill',m.x+dx*7,m.y+dz*7,
        m.x-dx*5-dz*5,m.y-dz*5+dx*5,
        m.x-dx*5+dz*5,m.y-dz*5-dx*5)
    g.setColor(.79,.86,.81,.96);g.setFont(self:font(9))
    g.printf('Tap a building number to navigate',rect.x+8,rect.y+rect.height-16,rect.width-16,'center')
    g.pop()
    return s
end
function Map:release()
    if self.background then self.background:release();self.background=nil end
    for _,font in pairs(self.fonts)do font:release()end
    self.fonts={};self.released=true
end
return Map
