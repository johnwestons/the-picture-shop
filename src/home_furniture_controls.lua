local Furniture=require("src.home_furniture")
local Catalog=require("src.home_furniture_catalog")
local Grid=require("src.placement_grid")
local Art=require("src.home_furniture_art")
local Surface=require("src.home_surfaces")
local Controls={page=1,index=1}
local font,small
local buttons={rotate={x=20,y=604,width=140,height=44},place={x=172,y=604,width=160,height=44},
    store={x=344,y=604,width=140,height=44},sell={x=496,y=604,width=190,height=44},cancel={x=700,y=604,width=240,height=44},
    previous={x=20,y=496,width=110,height=44},next={x=140,y=496,width=110,height=44},
    move={x=290,y=110,width=210,height=44},purchase={x=510,y=110,width=210,height=44},sale={x=730,y=110,width=210,height=44},
    surface={x=700,y=110,width=240,height=44}}
local function inside(r,x,y) return x>=r.x and x<=r.x+r.width and y>=r.y and y<=r.y+r.height end
local function player(R) return require("src.home_activity_controls").localPlayer(R) end
function Controls.command(R,p,command)
    local people=require("src.weekend_runtime").players(R)
    Furniture.recover(R.state,people)
    local okay,message=Furniture.command(R.state,p,command,people)
    if okay then R.saveCurrent();if R.multiplayer:isHost() then R.multiplayer:markShopDirty() end end
    return okay,okay and "changed" or "blocked",message,"homeFurniture"
end
local function send(R,command)
    local okay,message
    if R.multiplayer:isClient() then okay,message=R.multiplayer:requestInteraction("homeFurniture",command)
    else local code;okay,code,message=Controls.command(R,player(R),command) end
    R.state.message=message or (okay and "Waiting for the host..." or "Furniture action unavailable.")
    Controls.cache=nil;return okay
end
local function editing(R)
    local who=require("src.home_residents").key(player(R))
    for _,item in ipairs(Furniture.ensure(R.state).items) do
        if item.editor==who then
            if Controls.token~=item.editToken then
                local p=player(R);local x,y=item.x,item.y
                if item.location=="storage" then x,y=Grid.snap(p.x+48,p.y,Furniture.GRID) end
                local direction=Catalog.ITEMS[item.kind].defaultDirection or item.direction
                local hookup=Furniture.hookupPoint(R.state,item)
                if hookup and not Furniture.hookedUp(R.state,item) then
                    x,y,direction=hookup.x,hookup.y,hookup.direction
                end
                Controls.candidate={id=item.id,kind=item.kind,x=x,y=y,direction=direction,location="floor"}
                if item.location=="surface" then Controls.candidate.location="surface";Controls.candidate.parentId=item.parentId;Controls.candidate.slot=item.slot end
                Controls.token=item.editToken;Controls.sellConfirm=false;Controls.cache=nil
            end
            return item
        end
    end
    Controls.token=nil;Controls.candidate=nil;Controls.cache=nil;return nil
end
function Controls.snapshot(R)
    local item=editing(R);if not item then return nil end
    local candidate=Controls.candidate;local people=require("src.weekend_runtime").players(R)
    if candidate.location=="surface" then return nil end
    local key=R.state.home.furniture.revision..":"..candidate.x..":"..candidate.y..":"..candidate.direction
    for _,actor in ipairs(people) do key=key..":"..actor.x..":"..actor.y end
    if Controls.cache and Controls.cacheKey==key then return Controls.cache end
    local cells=Grid.cells(candidate.x,candidate.y,Furniture.GRID,function(x,y)
        return Furniture.canPlace(R.state,{id=item.id,kind=item.kind,x=x,y=y,direction=candidate.direction},people,true)
    end)
    Controls.cache={config=Furniture.GRID,cells=cells,selected=Grid.find(cells,candidate.x,candidate.y),footprint=Furniture.footprint(candidate)}
    Controls.cacheKey=key;return Controls.cache
end
local function act(R,action)
    local item=editing(R);if not item then return false end
    if action=="surface" then
        if not Catalog.ITEMS[item.kind].small then return false end
        local choices={{location="floor"}}
        local parents={0};for _,p in ipairs(Furniture.ensure(R.state).items) do if p.location=="floor" and Catalog.ITEMS[p.kind].surface then parents[#parents+1]=p.id end end
        for _,id in ipairs(parents) do for slot=1,#Surface.slots(R.state,id) do choices[#choices+1]={location="surface",parentId=id,slot=slot} end end
        local c=Controls.candidate;local index=1
        for i,v in ipairs(choices) do if c.location==v.location and c.parentId==v.parentId and c.slot==v.slot then index=i end end
        local choice=choices[index%#choices+1]
        c.location,c.parentId,c.slot=choice.location,choice.parentId,choice.slot
        c.x,c.y=Grid.snap(player(R).x+48,player(R).y,Furniture.GRID);c.direction="east";Controls.cache=nil;return true
    end
    if action=="rotate" then Controls.candidate.direction=Catalog.rotate(Controls.candidate.direction);Controls.cache=nil;return true end
    if action=="sell" and not Controls.sellConfirm then Controls.sellConfirm=true;return true end
    local command=action..":"..item.id..":"..item.editToken
    if action=="place" then
        local c=Controls.candidate
        if c.location=="surface" then command="attach:"..item.id..":"..item.editToken..":"..c.parentId..":"..c.slot..":"..c.direction
        else
            local cell=Grid.cellId(c.x,c.y,Furniture.GRID);if not cell then return false end
            command=command..":"..cell..":"..c.direction
        end
    end
    send(R,command);return true
end
function Controls.keypressed(key,R)
    if R.state.screen=="world" and player(R).sceneId=="home" and (key=="m" or key=="b") then
        Controls.page=1;Controls.index=1;Controls.cache=nil;Controls.sellConfirm=false;R.state.screen="home_furnish";return true
    end
    if R.state.screen~="home_furnish" then return false end
    local item=editing(R)
    if key=="escape" then
        if item then act(R,"cancel") else R.state.screen="world" end
    elseif item then
        if key=="q" then act(R,"rotate")
        elseif key=="tab" then act(R,"surface")
        elseif key=="return" or key=="e" then act(R,Controls.sellConfirm and "sell" or "place")
        elseif key=="p" then act(R,"store") elseif key=="delete" then act(R,"sell")
        else
            local offsets={left={-8,0},right={8,0},up={0,-6},down={0,6}}
            local d=offsets[key]
            if d and Controls.candidate.location=="floor" then local c=Controls.candidate;c.x=math.max(0,math.min(960,c.x+d[1]));c.y=math.max(0,math.min(678,c.y+d[2]));Controls.cache=nil end
        end
    else
        local items=Furniture.ensure(R.state).items
        if key=="up" or key=="down" then Controls.index=math.max(1,math.min(#items,Controls.index+(key=="up" and -1 or 1)));Controls.page=math.floor((Controls.index-1)/7)+1
        elseif key=="return" and items[Controls.index] then send(R,"begin:"..items[Controls.index].id) end
    end
    return true
end
function Controls.mousepressed(x,y,button,R)
    if R.state.screen~="home_furnish" then return false end
    if button~=1 then return true end
    if editing(R) then
        for _,name in ipairs({"rotate","place","store","sell","cancel","surface"}) do if inside(buttons[name],x,y) then act(R,name);return true end end
        if y>165 and y<580 then
            local grid=Controls.snapshot(R);local cell=grid and Grid.hit(grid.cells,x,y,Furniture.GRID)
            if cell then Controls.candidate.x,Controls.candidate.y=cell.x,cell.y;Controls.cache=nil end
        end
    else
        if inside(buttons.cancel,x,y) then R.state.screen="world";return true end
        local items=Furniture.ensure(R.state).items
        if inside(buttons.previous,x,y) then Controls.page=math.max(1,Controls.page-1)
        elseif inside(buttons.next,x,y) then Controls.page=math.min(math.max(1,math.ceil(#items/7)),Controls.page+1)
        else
            for i=1,7 do
                if x>=20 and x<=250 and y>=160+(i-1)*46 and y<=204+(i-1)*46 then
                    local index=(Controls.page-1)*7+i;local item=items[index]
                    if item then Controls.index=index;send(R,"begin:"..item.id) end
                    return true
                end
            end
            for _,pair in ipairs({{"move","move"},{"purchase","purchase"},{"sale","sell"}}) do
                if inside(buttons[pair[1]],x,y) then
                    send(R,"permission:"..pair[2]..":"..(Furniture.ensure(R.state).permissions[pair[2]] and "0" or "1"));return true
                end
            end
        end
    end
    return true
end
function Controls.draw(R)
    font=font or love.graphics.newFont(18);small=small or love.graphics.newFont(14)
    local item=editing(R);local data=Furniture.ensure(R.state)
    love.graphics.push("all");love.graphics.setFont(font)
    love.graphics.setColor(.025,.05,.065,.96);love.graphics.rectangle("fill",0,40,960,55)
    love.graphics.setColor(.96,.92,.8,1);love.graphics.print("FURNISH / "..(item and Catalog.ITEMS[item.kind].name or "Select an owned object"),20,50)
    if item then love.graphics.setFont(small);love.graphics.printf("Condition "..item.condition.."%  /  Object #"..item.id,660,54,280,"right") end
    love.graphics.setFont(small);love.graphics.print(item and "Arrow keys / tap grid: position · Q: rotate · Enter: place · Esc: cancel" or "Walk near floor furniture first. Stored objects can be unpacked beside you.",20,75)
    local function button(r,label,enabled)
        love.graphics.setColor(enabled==false and .12 or .10,enabled==false and .16 or .35,.32,1);love.graphics.rectangle("fill",r.x,r.y,r.width,r.height,4)
        love.graphics.setColor(.95,.95,.85,1);love.graphics.printf(label,r.x+4,r.y+14,r.width-8,"center")
    end
    if item then
        local grid=Controls.snapshot(R);if grid then Grid.draw(grid) end
        local pose=Surface.pose(R.state,Controls.candidate);if pose then Art.draw(pose,.65) end
        local hookup=Furniture.hookupPoint(R.state,item)
        if hookup then
            love.graphics.setColor(.98,.72,.2,.95);love.graphics.setLineWidth(3)
            love.graphics.circle("line",hookup.x,hookup.y,23);love.graphics.circle("line",hookup.x,hookup.y,15)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(.98,.84,.47,1)
            love.graphics.printf(Furniture.hookupHint(R.state,{kind=item.kind,location="floor",
                x=Controls.candidate.x,y=Controls.candidate.y,direction=Controls.candidate.direction}),270,165,675,"left")
        end
        if Catalog.ITEMS[item.kind].small then
            local c=Controls.candidate
            love.graphics.setColor(.025,.05,.065,.96);love.graphics.rectangle("fill",270,105,675,55,4)
            love.graphics.setColor(.95,.95,.85,1)
            local parent=c.parentId and Surface.find(R.state,c.parentId)
            love.graphics.print(c.location=="floor" and "Place on clear floor" or (c.parentId==0 and "Kitchen counter" or (parent and Catalog.ITEMS[parent.kind].name or "Surface").." #"..c.parentId).." / slot "..c.slot,285,122)
            button(buttons.surface,"NEXT SURFACE [Tab]")
            if c.location=="surface" then
                local okay,message=Surface.canAttach(R.state,item,c.parentId,c.slot,player(R))
                love.graphics.setColor(okay and .3 or .98,okay and .9 or .5,.45,1)
                love.graphics.printf(okay and "Slot available. Q rotates; Enter places." or message,280,165,660,"left")
            end
        end
        love.graphics.setColor(.025,.05,.065,.96);love.graphics.rectangle("fill",0,580,960,98)
        local price=math.floor(Catalog.ITEMS[item.kind].priceCents*.4*item.condition/100)
        button(buttons.rotate,"ROTATE [Q]");button(buttons.place,"PLACE [Enter]");button(buttons.store,"STORE [P]")
        button(buttons.sell,(Controls.sellConfirm and "CONFIRM SALE $" or "SELL $")..string.format("%.2f",price/100))
        button(buttons.cancel,"CANCEL [Esc]")
    else
        love.graphics.setColor(.025,.05,.065,.96);love.graphics.rectangle("fill",12,105,246,443,5)
        love.graphics.setColor(.95,.95,.85,1);love.graphics.print("FLOOR & STORAGE",20,120)
        for i=1,7 do
            local index=(Controls.page-1)*7+i;local row=data.items[index]
            if row then
                local r={x=20,y=160+(i-1)*46,width=230,height=44}
                button(r,(Controls.index==index and "> " or "")..Catalog.ITEMS[row.kind].name.." / "..row.location)
            end
        end
        if #data.items==0 then love.graphics.printf("No movable furniture yet. Buy furniture on CritterNet's Home & Living page.",20,170,220,"left") end
        button(buttons.previous,"PREVIOUS");button(buttons.next,"NEXT")
        local owner=(player(R).id or 1)==1
        for _,pair in ipairs({{"move","move","Guests move"},{"purchase","purchase","Guests buy"},{"sale","sell","Guests sell"}}) do
            button(buttons[pair[1]],pair[3]..": "..(data.permissions[pair[2]] and "ON" or "OFF"),owner)
        end
        button(buttons.cancel,"BACK TO APARTMENT")
    end
    love.graphics.setColor(.99,.84,.45,1);love.graphics.printf(R.state.message or "",20,656,920,"left")
    love.graphics.pop()
end
return Controls
