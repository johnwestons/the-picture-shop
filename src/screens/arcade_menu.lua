-- Native CRT-style cabinet selector; shared bounds keep touch and drawing aligned.
local Menu = {}
Menu.cards = {{80,266,380,278},{500,266,380,278}}
local fonts = {}
local cyan, pink = {.25,.95,1,1}, {1,.24,.66,1}
local function label(value,x,y,width,size,color)
    fonts[size] = fonts[size] or love.graphics.newFont("assets/fonts/VT323-Regular.ttf",size)
    love.graphics.setFont(fonts[size]); love.graphics.setColor(unpack(color))
    love.graphics.printf(value,x,y,width,"center")
end
function Menu.hit(x,y)
    for index,r in ipairs(Menu.cards) do
        if x>=r[1] and x<=r[1]+r[3] and y>=r[2] and y<=r[2]+r[4] then return index end
    end
end
function Menu.draw(selected, pointerX, pointerY)
    local hover = pointerX and pointerY and Menu.hit(pointerX,pointerY)
    for y=0,678,6 do
        local t=y/678
        love.graphics.setColor(.025+.055*t,.025,.09+.09*t,1)
        love.graphics.rectangle("fill",0,y,960,6)
    end
    -- A striped sunset and perspective grid belong to the selector, not a game stage.
    for y=-110,110,10 do
        local half=math.sqrt(math.max(0,110*110-y*y))
        love.graphics.setColor(1,.25+(110-y)/440,.48,.32)
        love.graphics.rectangle("fill",480-half,230+y,half*2,6)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(.68,.16,.65,.42)
    for x=-900,1900,120 do love.graphics.line(480+(x-480)*.12,470,x,678) end
    for _,y in ipairs({470,484,504,531,568,615,677}) do love.graphics.line(0,y,960,y) end
    love.graphics.setColor(.23,.83,1,.14)
    for n=1,40 do
        local x=(n*173)%930+15;local y=(n*97)%450+16
        love.graphics.rectangle("fill",x,y,2,2)
    end
    label("AFTER HOURS  /  FREE PLAY",70,40,710,23,pink)
    label("CRITTER ARCADE",42,99,880,82,{.95,.16,.60,.65})
    label("CRITTER ARCADE",38,95,880,82,cyan)
    label("CHOOSE YOUR NEXT HIGH SCORE",80,190,800,27,{.84,.80,1,1})
    for index,r in ipairs(Menu.cards) do
        local active=hover==index or (not hover and selected==index)
        local color=index==1 and cyan or pink
        love.graphics.setColor(color[1],color[2],color[3],active and .15 or .05)
        love.graphics.rectangle("fill",r[1]-8,r[2]-8,r[3]+16,r[4]+16,10)
        love.graphics.setColor(.025,.035,.085,.98)
        love.graphics.rectangle("fill",unpack(r))
        love.graphics.setLineWidth(active and 3 or 1)
        love.graphics.setColor(color[1],color[2],color[3],active and 1 or .55)
        love.graphics.rectangle("line",unpack(r))
        love.graphics.rectangle("fill",r[1],r[2],r[3],5)
        label(index==1 and "01  /  THE FIGHT" or "02  /  THE SHOOTOUT",r[1],r[2]+19,r[3],24,color)
        label("CRITTER",r[1],r[2]+65,r[3],44,{.92,.94,1,1})
        label(index==1 and "KOMBAT" or "CRISIS!",r[1],r[2]+108,r[3],65,color)
        label(index==1 and "PICK A FIGHTER. RULE THE RING." or "TAKE COVER. CLEAR THREE MISSIONS.",
            r[1]+12,r[2]+180,r[3]-24,21,{.72,.78,.90,1})
        love.graphics.setColor(color[1],color[2],color[3],active and .22 or .10)
        love.graphics.rectangle("fill",r[1]+22,r[2]+224,r[3]-44,36,3)
        label("PLAY  /  "..index,r[1],r[2]+228,r[3],27,color)
    end
    label("TAP A GAME   /   ARROWS + ENTER   /   D-PAD + A",60,582,840,24,{.82,.85,.98,1})
    label("TWO GAMES. ONE CABINET.",80,628,800,20,{.57,.55,.76,1})
    love.graphics.setColor(0,0,0,.09)
    for y=0,678,4 do love.graphics.rectangle("fill",0,y,960,1) end
end
return Menu
