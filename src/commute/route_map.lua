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
function Map.layout(rect,count,options)
    options=options or {}
    local mobile=options.mobile==true
    local compact=rect.width<740 or (options.headerRight and options.headerRight-(rect.x+172)<320) or false
    local showPlaces=mobile and options.showPlaces==true or (not mobile and options.showPlaces~=false)
    local pad=mobile and 14 or 18
    local headerHeight=compact and (mobile and 116 or 110) or (mobile and 66 or 62)
    local footerHeight=mobile and 38 or 48
    local contentTop=rect.y+headerHeight
    local footerY=rect.y+rect.height-footerHeight
    local availableHeight=math.max(80,footerY-contentTop-pad)
    local key,map,rows,columns,rowHeight,columnWidth,pageSize,pageCount
    if mobile then
        local mapHeight=showPlaces and math.max(120,availableHeight*.57) or availableHeight
        mapHeight=math.min(availableHeight,mapHeight)
        map={x=rect.x+pad,y=contentTop,width=rect.width-pad*2,height=mapHeight}
        if showPlaces then
            local keyY=map.y+map.height+8
            key={x=rect.x+pad,y=keyY,width=rect.width-pad*2,
                height=math.max(42,footerY-keyY-6)}
            local listHeight=math.max(24,key.height-46)
            rows=math.max(1,math.min(3,math.floor(listHeight/48)))
            columns=2;rowHeight=listHeight/rows;columnWidth=key.width/columns
            pageSize=rows*columns
            pageCount=math.max(1,math.ceil((count or 0)/pageSize))
        else
            rows=1;columns=1;rowHeight=0;columnWidth=0;pageSize=0;pageCount=1
        end
    else
        local contentHeight=availableHeight
        rows=math.max(1,math.floor(math.max(36,contentHeight-46)/40))
        columns=math.max(1,math.ceil((count or 0)/rows))
        if options.paginatePlaces then columns=math.min(3,columns) end
        local keyWidth=options.showPlaces==false and 0 or math.min(rect.width*.48,math.max(320,columns*220))
        map={x=rect.x+pad,y=contentTop,width=rect.width-keyWidth-(keyWidth>0 and pad*3 or pad*2),height=contentHeight}
        if keyWidth>0 then key={x=rect.x+rect.width-keyWidth-pad,y=contentTop,width=keyWidth,height=contentHeight} end
        rowHeight=math.max(36,contentHeight-46)/rows;columnWidth=keyWidth>0 and keyWidth/columns or 0
        pageSize=options.paginatePlaces and rows*columns or (count or 0)
        pageCount=options.paginatePlaces and math.max(1,math.ceil((count or 0)/pageSize)) or 1
    end
    local page=math.max(1,math.min(pageCount,math.floor(options.placesPage or 1)))
    return {panel=rect,map=map,key=key,columns=columns,rows=rows,rowHeight=rowHeight,
        columnWidth=columnWidth,footerY=footerY,footerHeight=footerHeight,
        headerHeight=headerHeight,mobile=mobile,showPlaces=showPlaces,page=page,
        pageSize=pageSize,pageCount=pageCount,keyHeaderHeight=42,
        headerRight=options.headerRight,compact=compact}
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
    local self=setmetatable({world=world,entries={},fonts={},backgroundBuilds=0,terrainSamples=0,
        mapBounds=bounds(world),miniLevel=2,miniFollow=true,numbersVisible=true,
        desktopPlacesOpen=true,mobilePlacesOpen=false,placesPage=1},Map)
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
function Map:uiOptions(mobile,headerRight)
    return {mobile=mobile==true,showPlaces=mobile and self.mobilePlacesOpen or
        (not mobile and self.desktopPlacesOpen),placesPage=self.placesPage,
        showNumbers=self.numbersVisible,headerRight=headerRight,paginatePlaces=true}
end
function Map:snapshot(rect,actor,options)
    options=options or {};actor=actor or {}
    local layout=Map.layout(rect,#self.entries,options)
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
        local column,row
        if layout.mobile or layout.pageCount>1 then
            local ordinal=i-(layout.page-1)*layout.pageSize
            if ordinal>=1 and ordinal<=layout.pageSize then
                if layout.mobile then
                    column=(ordinal-1)%layout.columns;row=math.floor((ordinal-1)/layout.columns)
                else
                    column=math.floor((ordinal-1)/layout.rows);row=(ordinal-1)%layout.rows
                end
            end
        elseif layout.key then
            column=math.floor((i-1)/layout.rows);row=(i-1)%layout.rows
        end
        local keyRect
        if layout.key and column and row then
            local keyY=layout.key.y+(layout.mobile and layout.keyHeaderHeight or 0)
            keyRect={x=layout.key.x+column*layout.columnWidth+3,
                y=keyY+row*layout.rowHeight+2,width=layout.columnWidth-6,height=layout.rowHeight-4}
        end
        result.buildings[i]={id=entry.id,index=i,label=entry.label,x=bx,y=by,anchorX=ax,anchorY=ay,
            destination=entry.id==options.destination,home=entry.id==options.home,
            keyRect=keyRect}
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
local miniScales={1,1.5,2,2.5}

local function miniButtonSize(rect)
    return math.max(1,math.min(38,(rect.height-32)/3))
end
function Map.miniZoomButton(rect,direction)
    local size=miniButtonSize(rect)
    return {x=rect.x+rect.width-size-5,y=rect.y+24+(direction<0 and (size+4)*2 or 0),width=size,height=size}
end
function Map.miniFollowButton(rect)
    local size=miniButtonSize(rect)
    return {x=rect.x+rect.width-size-5,y=rect.y+24+size+4,width=size,height=size}
end
function Map:pressMiniZoom(rect,x,y)
    for direction=-1,1,2 do
        local b=Map.miniZoomButton(rect,direction)
        if x>=b.x and x<=b.x+b.width and y>=b.y and y<=b.y+b.height then
            self.miniLevel=clamp(self.miniLevel+direction,1,#miniScales)
            return true
        end
    end
    return false
end
function Map:pressMiniFollow(rect,x,y,actor)
    local b=Map.miniFollowButton(rect)
    if x<b.x or x>b.x+b.width or y<b.y or y>b.y+b.height then return false end
    actor=actor or {}
    if self.miniFollow==false then
        self.miniFollow=true;self.miniCenter=nil
    else
        self.miniFollow=false
        self.miniCenter={x=finite(actor.x,0),z=finite(actor.z,0)}
    end
    return true
end
local function miniPoint(snapshot,x,z)
    local t=snapshot.transform
    local dx,dz=x-t.centerX,z-t.centerZ
    return t.x+t.scale*(t.cos*dx-t.sin*dz),t.y+t.scale*(t.sin*dx+t.cos*dz)
end
function Map:miniSnapshot(rect,actor,options)
    options=options or {};actor=actor or {}
    local button=Map.miniZoomButton(rect,1)
    local area={x=rect.x+6,y=rect.y+24,width=math.max(1,button.x-rect.x-10),height=math.max(1,rect.height-30)}
    local b=self.mapBounds
    local scale=miniScales[self.miniLevel]*math.min(area.width/(b.x1-b.x0),area.height/(b.z1-b.z0))
    local heading=finite(actor.heading,0)
    if self.miniFollow~=false then self.miniCenter={x=finite(actor.x,0),z=finite(actor.z,0)} end
    self.miniCenter=self.miniCenter or {x=finite(actor.x,0),z=finite(actor.z,0)}
    local angle=-heading-math.pi/2
    local centerX,centerY=area.x+area.width*.5,area.y+area.height*.5
    local transform={x=centerX,y=centerY,scale=scale,rotation=angle,
        cos=math.cos(angle),sin=math.sin(angle),centerX=self.miniCenter.x,centerZ=self.miniCenter.z}
    local result={area=area,transform=transform,center=self.miniCenter,heading=heading,
        viewport={x=area.x,y=area.y,width=area.width,height=area.height,scale=scale,bounds=b},
        marker={x=centerX,y=centerY,dx=0,dz=-1,heading=heading,label=Map.headingLabel(heading)}}
    if self.miniFollow==false then
        result.marker.x,result.marker.y=miniPoint(result,finite(actor.x,0),finite(actor.z,0))
    end
    local destinations=self.world.roads and self.world.roads.destinations
    local target=destinations and destinations[options.destination]
    if target and target.x and target.z then
        result.goal={x=target.x,y=target.z}
        result.goal.screenX,result.goal.screenY=miniPoint(result,target.x,target.z)
    end
    local home=destinations and destinations[options.home]
    if home and home.x and home.z then
        result.home={id=options.home,x=home.x,y=home.z}
        result.home.screenX,result.home.screenY=miniPoint(result,home.x,home.z)
    end
    result.players={}
    for i,player in ipairs(options.players or {}) do
        local x,z=finite(player.x,nil),finite(player.z,nil)
        if x and z then
            local screenX,screenY=miniPoint(result,x,z)
            result.players[#result.players+1]={x=screenX,y=screenY,
                name=tostring(player.name or ('Player '..tostring(player.id or i))),id=player.id}
        end
    end
    return result
end
function Map:hit(rect,x,y,actor,options)
    local s=self:snapshot(rect,actor,options)
    local nearest,best
    for _,entry in ipairs(s.buildings) do
        local k=entry.keyRect
        if k and x>=k.x and x<=k.x+k.width and y>=k.y and y<=k.y+k.height then return entry.id end
        local mx,my=options and options.showNumbers==false and entry.anchorX or entry.x,
            options and options.showNumbers==false and entry.anchorY or entry.y
        local distance=(x-mx)^2+(y-my)^2
        local radius=options and options.mobile and 23 or 18
        if distance<=radius*radius and (not best or distance<best) then nearest,best=entry.id,distance end
    end
    return nearest
end
function Map:hitMini(rect,x,y,actor,options)
    local s=self:miniSnapshot(rect,actor,options);local area=s.area
    if x<area.x or y<area.y or x>area.x+area.width or y>area.y+area.height then return nil end
    -- Keep tap-to-navigate attached to the actual building on the cached map.
    local nearest,best
    for _,entry in ipairs(self.entries) do
        local site=entry.site
        local bx,by=miniPoint(s,site.x or site.origin.x,site.z or site.origin.z)
        local distance=(x-bx)^2+(y-by)^2
        if bx>=area.x and by>=area.y and bx<=area.x+area.width and by<=area.y+area.height
            and distance<=9^2 and (not best or distance<best) then nearest,best=entry.id,distance end
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
local function badge(g,x,y,index,color,font,radius)
    radius=radius or 11
    g.setColor(.025,.05,.05,.98);g.circle('fill',x,y,radius)
    g.setColor(color);g.setLineWidth(1.5);g.circle('line',x,y,radius)
    g.setFont(font);g.printf(tostring(index),x-radius,y-font:getHeight()/2,radius*2,'center')
end
function Map:font(size)
    if not self.fonts[size]then self.fonts[size]=love.graphics.newFont(size)end
    return self.fonts[size]
end
local function contains(rect,x,y)
    return rect and x>=rect.x and x<=rect.x+rect.width and y>=rect.y and y<=rect.y+rect.height
end
function Map:controlRects(rect,layout)
    local mobile=layout.mobile
    local closeReserve=mobile and 158 or 156
    local firstX=layout.compact and rect.x+16 or rect.x+172
    local lastX=layout.compact and rect.x+rect.width-16
        or layout.headerRight or rect.x+rect.width-closeReserve
    local gap=8
    local available=math.max(1,lastX-firstX-gap)
    local labelsWidth,placesWidth
    if available<210 then
        labelsWidth=available*.54;placesWidth=available-labelsWidth
    else
        labelsWidth=math.min(mobile and 166 or 150,available*.54)
        placesWidth=math.min(mobile and 166 or 150,available-labelsWidth)
    end
    local height=mobile and 46 or 42
    local y=rect.y+(layout.compact and 58 or 9)
    local controls={labels={x=firstX,y=y,width=labelsWidth,height=height},
        places={x=firstX+labelsWidth+gap,y=y,width=placesWidth,height=height}}
    if layout.key and layout.pageCount>1 then
        local py=layout.key.y+3
        controls.previous={x=layout.key.x+layout.key.width-107,y=py,width=48,height=34}
        controls.next={x=layout.key.x+layout.key.width-53,y=py,width=48,height=34}
    end
    return controls
end
function Map:pressControl(rect,x,y,mobile,headerRight)
    local ui=self:uiOptions(mobile,headerRight)
    local layout=Map.layout(rect,#self.entries,ui)
    local controls=self:controlRects(rect,layout)
    if contains(controls.labels,x,y) then self.numbersVisible=not self.numbersVisible;return true end
    if contains(controls.places,x,y) then
        if mobile then self.mobilePlacesOpen=not self.mobilePlacesOpen
        else self.desktopPlacesOpen=not self.desktopPlacesOpen end
        local nextLayout=Map.layout(rect,#self.entries,self:uiOptions(mobile,headerRight))
        self.placesPage=math.min(self.placesPage,nextLayout.pageCount)
        return true
    end
    if contains(controls.previous,x,y) then
        self.placesPage=math.max(1,self.placesPage-1);return true
    end
    if contains(controls.next,x,y) then
        self.placesPage=math.min(layout.pageCount,self.placesPage+1);return true
    end
    return false
end
function Map:draw(rect,actor,options)
    if self.released then return end
    options=options or {};self:prepare()
    local s=self:snapshot(rect,actor,options);local g=love.graphics;local v=s.viewport
    g.push('all');g.setShader();g.setColor(.025,.05,.047,.98);g.rectangle('fill',rect.x,rect.y,rect.width,rect.height,8)
    g.setColor(.43,.57,.51,1);g.setLineWidth(1);g.rectangle('line',rect.x,rect.y,rect.width,rect.height,8)
    local mobile=s.layout.mobile
    local controls=self:controlRects(rect,s.layout)
    g.setFont(self:font(mobile and 23 or 25));g.setColor(.98,.87,.52,1);g.print('TOWN MAP',rect.x+16,rect.y+14)
    local function button(b,label,active)
        if not b then return end
        g.setColor(active and {.15,.30,.22,1} or {.10,.16,.15,1})
        g.rectangle('fill',b.x,b.y,b.width,b.height,6)
        g.setColor(active and {.65,.94,.62,1} or {.48,.62,.56,1})
        g.setLineWidth(1.5);g.rectangle('line',b.x,b.y,b.width,b.height,6)
        local font=self:font(mobile and 17 or 16)
        g.setFont(font);g.setColor(.96,.97,.90,1)
        g.printf(label,b.x+4,b.y+(b.height-font:getHeight())/2,b.width-8,'center')
    end
    button(controls.labels,self.numbersVisible and 'NUMBERS: ON' or 'NUMBERS: OFF',self.numbersVisible)
    local placesOpen=mobile and self.mobilePlacesOpen or (not mobile and self.desktopPlacesOpen)
    button(controls.places,placesOpen and 'HIDE PLACES' or 'PLACES',placesOpen)
    if controls.previous then
        button(controls.previous,'<',s.layout.page>1)
        button(controls.next,'>',s.layout.page<s.layout.pageCount)
    end
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
    if s.layout.key then
        g.setColor(.035,.065,.06,.98);g.rectangle('fill',s.layout.key.x,s.layout.key.y,s.layout.key.width,s.layout.key.height,6)
        g.setColor(.37,.52,.46,1);g.setLineWidth(1);g.rectangle('line',s.layout.key.x,s.layout.key.y,s.layout.key.width,s.layout.key.height,6)
    end
    local numberFont=self:font(mobile and 15 or 14)
    local labelFont=self:font(mobile and 17 or (s.layout.columns>2 and 14 or 16))
    for _,entry in ipairs(s.buildings)do
        local color=entry.destination and {1,.73,.24,1} or entry.home and {.55,.91,.61,1} or {.81,.89,.85,1}
        local key=entry.keyRect
        if options.showNumbers~=false then
            g.setColor(color);g.setLineWidth(1.5);g.line(entry.anchorX,entry.anchorY,entry.x,entry.y)
            if entry.destination or entry.home then g.circle('line',entry.anchorX,entry.anchorY,14)end
            badge(g,entry.x,entry.y,entry.index,color,numberFont,13)
        else
            g.setColor(.015,.04,.04,.98);g.circle('fill',entry.anchorX,entry.anchorY,7)
            g.setColor(color);g.circle('fill',entry.anchorX,entry.anchorY,5)
            if entry.destination or entry.home then g.setLineWidth(2);g.circle('line',entry.anchorX,entry.anchorY,11)end
        end
        if key then
            g.setColor(.055,.09,.085,.96);g.rectangle('fill',key.x,key.y,key.width,key.height,4)
            if entry.destination or entry.home then g.setColor(color[1],color[2],color[3],.14);g.rectangle('fill',key.x,key.y,key.width,key.height,4)end
            local left=key.x+10
            if options.showNumbers~=false then
                badge(g,left+11,key.y+key.height/2,entry.index,color,numberFont,11)
                left=left+29
            end
            local available=math.max(24,key.x+key.width-left-8)
            local font=labelFont;local _,lines=font:getWrap(entry.label,available)
            if #lines*font:getHeight()>key.height then font=self:font(mobile and 14 or 12);_,lines=font:getWrap(entry.label,available)end
            g.setFont(font);g.setColor(color)
            g.printf(entry.label,left,key.y+math.max(0,(key.height-#lines*font:getHeight())/2),available,'left')
        end
    end
    if s.layout.key then
        g.setFont(self:font(mobile and 16 or 17));g.setColor(.94,.90,.75,1)
        if s.layout.pageCount>1 then
            g.print(('DESTINATIONS  ·  %d / %d'):format(s.layout.page,s.layout.pageCount),s.layout.key.x+12,s.layout.key.y+8)
        elseif mobile then
            g.print('DESTINATIONS  ·  TAP A PLACE TO SET ROUTE',s.layout.key.x+12,s.layout.key.y+8)
        else
            g.print('DESTINATIONS  ·  TAP A PLACE TO SET ROUTE',s.layout.key.x+12,s.layout.key.y+9)
        end
    end
    for _,area in ipairs(s.recreation)do
        g.setColor(.055,.15,.09,1);g.circle('fill',area.x,area.y,9)
        g.setColor(.65,.95,.67,1);g.setLineWidth(1.5);g.circle('line',area.x,area.y,9)
        g.setFont(self:font(13));g.printf(area.kind=='camp' and 'C' or 'P',area.x-9,area.y-7,18,'center')
        local label=area.label or (area.kind=='camp' and 'Campsite' or area.kind=='park' and 'Park' or 'Picnic area')
        local font=self:font(13);local width=math.min(180,font:getWidth(label)+12)
        local x=clamp(area.x+12,v.x+2,v.x+v.width-width-2)
        local y=clamp(area.y-9,v.y+2,v.y+v.height-20)
        g.setColor(.025,.06,.04,.96);g.rectangle('fill',x,y,width,19,3)
        g.setColor(.75,.95,.70);g.setFont(font);g.printf(label,x+5,y+1,width-10,'left')
    end
    if s.bike then
        g.setColor(.93,.91,.71,1);g.setLineWidth(2);g.rectangle('line',s.bike.x-4,s.bike.y-4,8,8)
        g.setFont(self:font(13));g.print('BIKE',clamp(s.bike.x-34,v.x+2,v.x+v.width-42),clamp(s.bike.y+9,v.y+2,v.y+v.height-16))
    end
    local m=s.marker;local points={m.tipX,m.tipY,m.x-m.dx*8-m.dz*7,m.y-m.dz*8+m.dx*7,
        m.x-m.dx*4,m.y-m.dz*4,m.x-m.dx*8+m.dz*7,m.y-m.dz*8-m.dx*7}
    g.setColor(.01,.04,.05,1);g.setLineWidth(4);g.polygon('line',points)
    g.setColor(.24,1,.94,1);g.polygon('fill',points)
    local lx,ly=clamp(m.x+15,v.x+3,v.x+v.width-42),clamp(m.y-25,v.y+3,v.y+v.height-20)
    g.setColor(.02,.06,.06,.95);g.rectangle('fill',lx-3,ly-2,42,20,4)
    g.setColor(.24,1,.94,1);g.setFont(self:font(14));g.print('YOU',lx,ly)
    local footerFont=mobile and 15 or 16
    g.setFont(self:font(footerFont));g.setColor(.24,1,.94,1)
    g.print('YOU  ·  Heading '..m.label,rect.x+16,s.layout.footerY)
    g.setColor(.79,.86,.81,1)
    g.printf(options.closeHint or 'Tap a marker or place to set a route',rect.x+rect.width*.42,
        s.layout.footerY,rect.width*.56,'right')
    g.pop()
    return s
end
function Map:drawMini(rect,actor,options)
    if self.released then return end
    options=options or {};self:prepare()
    local s=self:miniSnapshot(rect,actor,options);local g=love.graphics;local v,area=s.viewport,s.area
    g.push('all');g.setShader();g.setColor(.025,.05,.047,.96)
    g.rectangle('fill',rect.x,rect.y,rect.width,rect.height,7)
    g.setColor(.43,.57,.51,.96);g.setLineWidth(1);g.rectangle('line',rect.x,rect.y,rect.width,rect.height,7)
    g.setFont(self:font(13));g.setColor(.98,.87,.52,1)
    local title='NAV  ·  '..(self:label(options.destination) or 'Town map')
    if options.route and options.route.length then title=title..('  ·  %dm'):format(math.floor(options.route.length+.5)) end
    local titleScale=math.min(1,(rect.width-16)/math.max(1,g.getFont():getWidth(title)))
    g.print(title,rect.x+8,rect.y+7,0,titleScale,titleScale)

    g.push('all')
    local sx,sy=g.transformPoint(area.x,area.y)
    local ex,ey=g.transformPoint(area.x+area.width,area.y+area.height)
    g.intersectScissor(sx,sy,ex-sx,ey-sy)
    local b=v.bounds;local t=s.transform
    g.push()
    g.translate(t.x,t.y);g.rotate(t.rotation);g.scale(t.scale,t.scale);g.translate(-t.centerX,-t.centerZ)
    g.setColor(1,1,1);g.draw(self.background,b.x0,b.z0,0,(b.x1-b.x0)/512,(b.z1-b.z0)/512)
    if options.route and options.route.points then
        local points={}
        for _,p in ipairs(options.route.points) do
            points[#points+1]=p.x
            points[#points+1]=p.z
        end
        if #points>=4 then
            g.setColor(.02,.05,.04,.95);g.setLineWidth(4/t.scale);g.line(points)
            g.setColor(1,.66,.18,1);g.setLineWidth(2.4/t.scale);g.line(points)
        end
    end
    g.pop()
    local m=s.marker
    local playerX=clamp(m.x,area.x+6,area.x+area.width-6)
    local playerY=clamp(m.y,area.y+6,area.y+area.height-6)
    local function edgePoint(x,y)
        local dx,dy=x-playerX,y-playerY;local f=1
        if dx>0 then f=math.min(f,(area.x+area.width-6-playerX)/dx)
        elseif dx<0 then f=math.min(f,(area.x+6-playerX)/dx) end
        if dy>0 then f=math.min(f,(area.y+area.height-6-playerY)/dy)
        elseif dy<0 then f=math.min(f,(area.y+6-playerY)/dy) end
        f=math.max(0,math.min(1,f))
        return playerX+dx*f,playerY+dy*f,f<.999,dx,dy
    end
    local function drawHome(x,y)
        local edge
        x,y,edge=edgePoint(x,y)
        g.setColor(.025,.07,.05,.98);g.circle('fill',x,y,8)
        g.setColor(.55,.96,.62,1);g.setLineWidth(1.5);g.circle('line',x,y,8)
        g.polygon('fill',x,y-4,x+4,y,x+3,y,x+3,y+4,x-3,y+4,x-3,y,x-4,y)
        local labelX=x+8
        if labelX+31>area.x+area.width then labelX=x-39 end
        g.setColor(.02,.06,.04,.96);g.rectangle('fill',labelX,y-7,31,13,3)
        g.setColor(.65,1,.69,1);g.setFont(self:font(9));g.print(edge and 'HOME  ›' or 'HOME',labelX+2,y-6)
    end
    if s.home then drawHome(s.home.screenX,s.home.screenY) end
    if s.goal then
        local x,y=edgePoint(s.goal.screenX,s.goal.screenY)
        local dx,dy=x-playerX,y-playerY;local len=math.max(1,math.sqrt(dx*dx+dy*dy));dx,dy=dx/len,dy/len
        g.setColor(1,.73,.27,1)
        g.polygon('fill',x+dx*5,y+dy*5,x-dy*4-dx*3,y+dx*4-dy*3,
            x+dy*4-dx*3,y-dx*4-dy*3)
    end
    g.setFont(self:font(9))
    for _,player in ipairs(s.players) do
        local x,y,edge,dx,dy=edgePoint(player.x,player.y)
        local color={.82,.48,1,1}
        g.setColor(.015,.045,.045,.98);g.circle('fill',x,y,6)
        g.setColor(color);g.circle('fill',x,y,4)
        if edge then
            local length=math.max(1,math.sqrt(dx*dx+dy*dy));dx,dy=dx/length,dy/length
            g.polygon('fill',x+dx*7,y+dy*7,x-dy*3-dx*2,y+dx*3-dy*2,
                x+dy*3-dx*2,y-dx*3-dy*2)
        end
        local label=player.name:gsub('[%c]',''):sub(1,12)
        local font=self:font(9);local labelWidth=math.min(font:getWidth(label)+6,82)
        local labelX=x+8
        if labelX+labelWidth>area.x+area.width then labelX=x-labelWidth-8 end
        labelX=clamp(labelX,area.x+2,area.x+area.width-labelWidth-2)
        local labelY=clamp(y-7,area.y+2,area.y+area.height-15)
        g.setColor(.015,.04,.045,.92);g.rectangle('fill',labelX,labelY,labelWidth,13,3)
        g.setColor(.94,.88,1,1);g.print(label,labelX+3,labelY+1)
    end
    g.setColor(.02,.06,.06,1);g.circle('fill',playerX,playerY,7)
    g.setColor(.24,1,.94,1);g.circle('line',playerX,playerY,7)
    g.polygon('fill',playerX,playerY-7,playerX-5,playerY+5,playerX,playerY+3,playerX+5,playerY+5)
    local northX,northY=math.sin(t.rotation),-math.cos(t.rotation)
    local nx,ny=area.x+16,area.y+17
    g.setColor(.02,.06,.06,.88);g.circle('fill',nx,ny,10)
    g.setColor(.93,.94,.84,1);g.setLineWidth(1.6);g.line(nx,ny,nx+northX*8,ny+northY*8)
    g.polygon('fill',nx+northX*9,ny+northY*9,nx+northX*3-northY*3,ny+northY*3+northX*3,
        nx+northX*3+northY*3,ny+northY*3-northX*3)
    g.setFont(self:font(8));g.print('N',nx-3,ny+9)
    g.pop() -- Restore the viewport clip before drawing the map controls.

    for direction=-1,1,2 do
        local b=Map.miniZoomButton(rect,direction)
        local enabled=direction>0 and self.miniLevel<#miniScales or direction<0 and self.miniLevel>1
        local x,y=b.x+b.width*.5,b.y+b.height*.5
        g.setColor(.12,.18,.16);g.rectangle('fill',b.x,b.y,b.width,b.height,4)
        g.setColor(.48,.62,.56,1);g.setLineWidth(1.2);g.rectangle('line',b.x,b.y,b.width,b.height,4)
        if enabled then g.setColor(.87,.91,.79) else g.setColor(.40,.46,.42) end
        local mark=math.min(16,b.width*.38)
        g.setLineWidth(3);g.line(x-mark,y,x+mark,y)
        if direction>0 then g.line(x,y-mark,x,y+mark) end
    end
    local follow=Map.miniFollowButton(rect)
    local fx,fy=follow.x+follow.width*.5,follow.y+follow.height*.5
    g.setColor(self.miniFollow==false and {.12,.18,.16,1} or {.20,.34,.25,1})
    g.rectangle('fill',follow.x,follow.y,follow.width,follow.height,4)
    g.setColor(.48,.62,.56,1);g.setLineWidth(1.2);g.rectangle('line',follow.x,follow.y,follow.width,follow.height,4)
    g.setColor(self.miniFollow==false and {.72,.79,.70,1} or {.65,1,.69,1})
    local radius,arm=math.min(7,follow.width*.2),math.min(13,follow.width*.32)
    g.setLineWidth(2.2);g.circle('line',fx,fy,radius);g.circle('fill',fx,fy,2)
    g.line(fx-arm,fy,fx-radius,fy);g.line(fx+radius,fy,fx+arm,fy)
    g.line(fx,fy-arm,fx,fy-radius);g.line(fx,fy+radius,fx,fy+arm)
    g.pop()
    return s
end
function Map:release()
    if self.background then self.background:release();self.background=nil end
    for _,font in pairs(self.fonts)do font:release()end
    self.fonts={};self.released=true
end
return Map
