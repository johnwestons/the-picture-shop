local FoodArt=require("src.home_food_art")
local Art={}

local BOXES={
    small={width=22,depth=16,height=14},
    medium={width=29,depth=21,height=18},
    large={width=37,depth=26,height=22},
}

local function drawBox(size,x,y)
    local box=BOXES[size] or BOXES.small
    local g=love.graphics
    g.setShader()
    local w,d,h=box.width,box.depth,box.height
    local back={x,y-d-h}
    local right={x+w/2,y-d/2-h}
    local front={x,y-h}
    local left={x-w/2,y-d/2-h}
    local rightBase={x+w/2,y-d/2}
    local frontBase={x,y}
    local leftBase={x-w/2,y-d/2}

    g.setColor(.12,.09,.06,.23);g.ellipse("fill",x,y-1,w*.57,d*.58)
    g.setColor(.57,.37,.22,1);g.polygon("fill",left[1],left[2],front[1],front[2],frontBase[1],frontBase[2],leftBase[1],leftBase[2])
    g.setColor(.68,.45,.28,1);g.polygon("fill",front[1],front[2],right[1],right[2],rightBase[1],rightBase[2],frontBase[1],frontBase[2])
    g.setColor(.79,.58,.37,1);g.polygon("fill",back[1],back[2],right[1],right[2],front[1],front[2],left[1],left[2])

    g.setColor(.34,.23,.15,1);g.setLineWidth(1)
    g.polygon("line",back[1],back[2],right[1],right[2],front[1],front[2],left[1],left[2])
    g.line(left[1],left[2],leftBase[1],leftBase[2],frontBase[1],frontBase[2],rightBase[1],rightBase[2],right[1],right[2])
    -- A folded center seam and a short paper-tape strip make each carton read
    -- as a sealed corrugated box at the apartment's normal camera distance.
    g.setColor(.54,.36,.22,1);g.line(back[1],back[2],front[1],front[2])
    local tapeY=y-h-d*.55
    g.setColor(.91,.74,.49,1);g.polygon("fill",x-2,tapeY-3,x+2,tapeY-3,x+2,tapeY+3,x-2,tapeY+3)
    g.setColor(.65,.47,.30,1);g.line(x-2,tapeY-3,x+2,tapeY-3,x+2,tapeY+3,x-2,tapeY+3,x-2,tapeY-3)
end

local function category(parcel)
    return parcel.kind=="bag" and "bag" or "box:"..tostring(parcel.size or "small")
end

local function displayPackages(packages)
    local chosen,seen,picked={},{},{}
    -- Show one of every available package shape first, so a mixed delivery
    -- still communicates both bagged food and boxed household goods.
    for index,parcel in ipairs(packages or {}) do
        local key=category(parcel)
        if not seen[key] then
            chosen[#chosen+1]=parcel;seen[key]=true;picked[index]=true
            if #chosen==4 then return chosen end
        end
    end
    if #chosen<4 then
        for index,parcel in ipairs(packages or {}) do
            if not picked[index] then
                chosen[#chosen+1]=parcel
                if #chosen==4 then break end
            end
        end
    end
    return chosen
end

function Art.draw(packages,x,y)
    love.graphics.push("all")
    local shown=displayPackages(packages)
    local offsets={
        {x=-18,y=-8},{x=18,y=-8},{x=-17,y=8},{x=17,y=8},
    }
    for index,parcel in ipairs(shown) do
        local offset=offsets[index]
        if parcel.kind=="bag" then
            FoodArt.draw(1,x+offset.x,y+offset.y-13,34)
        else
            drawBox(parcel.size,x+offset.x,y+offset.y)
        end
    end
    love.graphics.pop()
end

return Art
