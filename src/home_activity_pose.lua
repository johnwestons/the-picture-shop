local Images=require("src.home_art_resources")
local Preload=require("src.home_art_preload")
-- Presentation only: furniture contacts never replace the walkable activity origin.
-- The same replicated activity selects the host and guest pose. No saved pose state.
local Residents=require("src.home_residents")
local Furniture=require("src.home_furniture")
local Catalog=require("src.home_furniture_catalog")
local Colorways=require("src.rabbit_colorways")
local Calendar=require("src.business_calendar")
local Pose={}
local cache,shader={},nil
local frameFor={southeast=1,south=2,southwest=3,west=4,northwest=5,north=6,northeast=7,east=8}
local hips={
    seated={{181,391},{182,397},{175,391},{232,397},{172,380},{182,375},{182,380},{183,404}},
    eating={{180,375},{193,385},{181,375},{225,378},{162,359},{192,363},{211,363},{198,372}},
}
-- Sleeping views were generated with uneven horizontal spacing. Explicit frame
-- regions keep every ear/boot and exclude neighboring sprites without editing PNGs.
local sleepRegions={
    {48,160,450,505},{476,108,678,500},{740,160,1130,505},{1110,257,1528,422},
    {60,617,434,928},{472,562,680,946},{722,638,1077,931},{1082,730,1514,891},
}
local sleepCenters={{250,337},{577,309},{937,337},{1318,345},{248,778},{577,756},{900,791},{1298,812}}
-- Furniture contacts are in each existing atlas frame's local coordinates.
local contacts={
    chair={{211,255},{192,261},{166,255},{187,247},{211,197},{192,205},{170,195},{193,217}},
    couch={{218,288},{210,295},{210,288},{218,245},{216,199},{210,206},{210,199},{170,211}},
    bed={{228,278},{128,274},{224,278},{180,284},{228,219},{128,225},{224,219},{180,250}},
    guest_mat={{225,287},{144,278},{230,287},{200,270},{225,232},{144,218},{230,232},{200,247}},
}
-- Only foreground wooden/upholstered parts are redrawn after the occupant.
-- Polygons refer to original furniture pixels, so texture and alpha stay exact.
local foreground={
    chair={
        [5]={{116,72,136,69,225,126,225,276,116,214}},
        [6]={{112,101,134,101,134,114,246,114,246,101,265,101,265,271,112,271}},
        [7]={{143,126,256,67,271,75,271,222,143,282}},
        [8]={{112,64,132,60,145,281,125,295}},
    },
    couch={
        [1]={{42,251,55,245,163,327,161,430,125,420,45,361}},
        [2]={{52,206,81,206,96,294,96,378,64,378},{330,207,356,208,378,290,366,381,336,381}},
        [3]={{247,332,350,250,369,269,368,366,271,427,248,419}},
        [4]={{105,300,284,311,289,408,111,415}},
        [5]={{43,160,295,249,297,365,49,270},{294,249,374,192,395,204,382,297,297,365}},
        [6]={{62,214,368,214,366,332,66,332}},
        [7]={{136,250,375,157,384,270,145,365},{49,204,71,192,136,250,145,365,58,302}},
        [8]={{95,272,283,265,282,370,99,374}},
    },
    bed={
        [1]={{264,378,385,304,402,315,402,388,282,454,264,440}},
        [2]={{32,383,223,383,223,455,32,455}},
        [3]={{45,306,67,306,199,379,199,451,45,382}},
        [5]={{261,255,387,185,402,194,402,285,280,383,261,365}},
        [6]={{32,250,223,250,223,368,32,368}},
        [7]={{44,190,65,193,202,258,202,383,44,285}},
    },
}
-- Couch registration above was measured against nominal 384-pixel columns;
-- its actual atlas partitions avoid the neighboring armrest at column edges.
for frame=1,8 do
    local shift=({0,32,16,16})[(frame-1)%4+1]
    contacts.couch[frame][1]=contacts.couch[frame][1]-shift
    for _,polygon in ipairs(foreground.couch[frame] or {}) do
        for i=1,#polygon,2 do polygon[i]=polygon[i]-shift end
    end
end
local function region(kind,frame)
    if kind=="sleeping" then return unpack(sleepRegions[frame]) end
    local row=frame>4 and 1 or 0
    local boundary=kind=="eating" and 498 or 512
    return (frame-1)%4*384,row*boundary,(frame-1)%4*384+384,row==0 and boundary or 1024
end
local function metrics(kind,frame)
    local x1,y1,x2,y2=region(kind,frame)
    if kind=="sleeping" then return sleepCenters[frame][1],sleepCenters[frame][2],x1,y1,x2,y2 end
    local p=hips[kind][frame]
    return (frame-1)%4*384+p[1],math.floor((frame-1)/4)*512+p[2],x1,y1,x2,y2
end
function Pose.get(state,player)
    if not state.home or player.sceneId~="home" or not require("src.weekend_flow").atHome(state)
        or (player.character or require("src.config").player.character)~="rabbit-worker" then return nil end
    local resident=Residents.display(state,player);local a=resident and resident.activity
    if not a or (player.x-a.x)^2+(player.y-a.y)^2>4 then return nil end
    local definition=Residents.ACTIONS[a.kind];if not definition then return nil end
    local item=a.furnitureId and Furniture.find(state,a.furnitureId)
    if item and (item.location~="floor" or item.editor) then return nil end
    local kind,direction,x,y,depth,groundX,groundY
    local sleeping=definition.sleep or a.kind=="nap" or a.kind=="couchrest" or a.kind=="matrest" or a.kind=="rest"
    if item and contacts[item.kind] then
        if sleeping then kind="sleeping"
        elseif item.kind=="chair" or item.kind=="couch" then kind=definition.item and "eating" or "seated" end
        if not kind then return nil end
        direction=kind=="sleeping" and item.kind=="couch" and Catalog.rotate(item.direction,2) or item.direction
        local entry=Catalog.ITEMS[item.kind];local f=entry.frames[item.direction];local contact=contacts[item.kind][f];local pivot=entry.pivots[f]
        x=item.x+(contact[1]-pivot[1])*entry.scale
        y=item.y+(contact[2]-pivot[2])*entry.scale*(entry.frameScaleY and entry.frameScaleY[f] or 1)
        groundX,groundY=item.x,item.y
        depth=item.y+Furniture.footprint(item).halfHeight+.01
    elseif a.target=="floor" and sleeping then
        kind="sleeping";direction="east";x,y=player.x,player.y-5;depth=player.y;groundX,groundY=player.x,player.y
    else return nil end
    local frame=frameFor[direction];local ox,oy,x1,y1,x2,y2=metrics(kind,frame)
    local sx,sy=.14,.14
    if kind=="sleeping" then
        sx,sy=.20,.16
        if frame==2 or frame==6 then sx,sy=.18,.18 end
        if item and item.kind=="couch" then sx,sy=sx*.8,sy*.8 end
        if item and item.kind=="guest_mat" then sy=sy*.70 end
    end
    local seconds=math.max(0,Calendar.absoluteHours(state)-(tonumber(a.startedAt) or Calendar.absoluteHours(state)))
        *Calendar.secondsPerDay(state)/24
    local television=a.kind=="watch" and a.tvId and Furniture.find(state,a.tvId)
    return {kind=kind,frame=frame,direction=direction,x=x,y=y,sx=sx,sy=sy,ox=ox,oy=oy,
        depth=depth,groundX=groundX,groundY=groundY,item=item,
        activity=a.kind,seconds=seconds,watching=television and television.powered==true or false,
        bounds={x+(x1-ox)*sx,y+(y1-oy)*sy,x+(x2-ox)*sx,y+(y2-oy)*sy}}
end
local function resource(kind)
    if cache[kind] then return cache[kind] end
    local image=Images.load("pose","assets/generated/home-poses-v1/"..kind.."-eight-directions.png")
    if not image then return nil end
    image:setFilter("linear","linear");local frames={}
    for i=1,8 do
        local x1,y1,x2,y2=region(kind,i)
        local polygon={x1,y1,x2,y1,x2,y2,x1,y2}
        if kind=="sleeping" and i==3 then polygon={740,160,1130,160,1130,250,1108,250,1108,505,740,505} end
        local vertices={}
        for _,triangle in ipairs(love.math.triangulate(polygon)) do for n=1,6,2 do
            local x,y=triangle[n],triangle[n+1];vertices[#vertices+1]={x,y,x/1536,y/1024,1,1,1,1}
        end end
        local mesh=love.graphics.newMesh(vertices,"triangles","static");mesh:setTexture(image);frames[i]=mesh
    end
    cache[kind]={image=image,frames=frames};return cache[kind]
end
local function ensureShader()
    shader=shader or love.graphics.newShader(Colorways.blendShaderSource()..[[
vec4 effect(vec4 color,Image texture,vec2 uv,vec2 screen) {
    vec4 pixel=Texel(texture,uv);if(pixel.a<0.18) discard;
    return applyRabbitColorways(pixel)*color;
}]])
end
function Pose.prewarm(kind)
    if not resource(kind) then return false end
    ensureShader();return true
end
function Pose.draw(pose,player)
    if not Preload.want("pose",function()return Pose.prewarm(pose.kind) end) then return false end
    local asset=resource(pose.kind)
    ensureShader()
    local settle=math.max(0,1-math.max(0,pose.seconds or 0)/.36)
    settle=settle*settle*(3-2*settle)
    local breathing=pose.kind=="sleeping" and math.sin((pose.seconds or 0)*math.pi*2/2.8)*.012 or 0
    love.graphics.push("all");love.graphics.setColor(1,1,1,1);love.graphics.setShader(shader)
    Colorways.configureShader(shader,player.furColorway,player.overallsColorway)
    love.graphics.draw(asset.frames[pose.frame],pose.x,pose.y-2*settle,0,
        pose.sx*(1-.025*settle),pose.sy*(1-.025*settle+breathing),pose.ox,pose.oy)
    if pose.watching then
        love.graphics.setShader()
        local offsetX=({7,0,-7,-8,-6,0,6,8})[pose.frame] or 0
        local glow=.10+.025*(.5+.5*math.sin((pose.seconds or 0)*6.4))
        love.graphics.setColor(.42,.72,1,glow)
        love.graphics.ellipse("fill",pose.x+offsetX,pose.y-30,3.2,2.2)
    end
    love.graphics.pop();return true
end
function Pose.drawForeground(pose)
    local item=pose.item;local regions=item and foreground[item.kind]
    if regions then require("src.home_furniture_art").drawRegion(item,regions[Catalog.ITEMS[item.kind].frames[item.direction]]) end
end
function Pose.release()
    Images.release("pose")
    for _,a in pairs(cache) do for _,mesh in ipairs(a.frames) do mesh:release() end;a.image:release() end
    cache={};if shader then shader:release();shader=nil end
end
return Pose
