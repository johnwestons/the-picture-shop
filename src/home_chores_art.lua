local Layout=require("src.home_layouts")
local Art={};local font
function Art.floor(state)
    local c=state.home.chores;if not c then return end
    love.graphics.push("all");love.graphics.setShader()
    for _,pair in ipairs({{"living","living"},{"kitchen","kitchen"},{"bathroom","bathroom"}}) do
        local soil=c.soil[pair[1]];local room=Layout.get(state).rooms[pair[2]]
        if soil>=5 then
            local x,y=Layout.toWorld(unpack(room))
            love.graphics.setColor(.12,.08,.035,math.min(.3,soil/220))
            for i=1,math.min(8,math.ceil(soil/12)) do
                local dx=((i*37)%77)-38;local dy=((i*23)%35)-17
                love.graphics.ellipse("fill",x+dx,y+dy,6+i%3,2+i%2)
            end
        end
    end
    love.graphics.pop()
end
function Art.fixture(state,id)
    local c=state.home.chores;if not c then return end
    local text
    if id=="laundry" then
        local l=c.laundry
        if l.phase=="washing" then text="WASH "..require("src.home_chores").minutesLeft(state).."m"
        elseif l.phase=="ready" then text="UNLOAD"
        elseif l.dirty>0 then text="LAUNDRY "..l.dirty end
    elseif id=="sink" and c.dishes>0 then text="DISHES "..c.dishes end
    if not text then return end
    local f=Layout.get(state).fixtures[id];local x,y=Layout.toWorld(f.x,f.y)
    font=font or love.graphics.newFont(10)
    love.graphics.push("all");love.graphics.setShader();love.graphics.setFont(font)
    local width=font:getWidth(text)+10;local top=y-(id=="laundry" and 62 or 48)
    love.graphics.setColor(.035,.09,.10,.94);love.graphics.rectangle("fill",x-width/2,top,width,16,3)
    love.graphics.setColor(.95,.87,.49,1);love.graphics.print(text,x-width/2+5,top+2)
    love.graphics.pop()
end
return Art
