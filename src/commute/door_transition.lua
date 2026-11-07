-- Short first-person threshold transition built from the game's vector art.
local Door={DURATION=.98}

local function clamp(value,minimum,maximum)
    return math.max(minimum,math.min(maximum,value))
end
local function smooth(value)
    value=clamp(value,0,1)
    return value*value*(3-2*value)
end
local function quad(g,color,points)
    g.setColor(color[1],color[2],color[3],color[4] or 1)
    g.polygon('fill',unpack(points))
end
local function panel(g,left,top,rightTop,rightBottom,bottom,color)
    if rightTop<=left+1 or rightBottom<=left+1 then return end
    quad(g,color,{left,top,rightTop,top,rightBottom,bottom,left,bottom})
end

function Door.new(action,token)
    return {action=action,token=token,elapsed=0}
end

function Door.update(transition,dt)
    if not transition then return false end
    transition.elapsed=transition.elapsed+math.max(0,dt or 0)
    return transition.elapsed>=Door.DURATION
end

function Door.draw(transition,width,height)
    local g=love.graphics
    local time=clamp((transition and transition.elapsed or 0)/Door.DURATION,0,1)
    local turn=smooth((time-.22)/.19)
    local opening=smooth((time-.42)/.40)
    local fade=smooth((time-.82)/.18)
    local frameX,frameY=width*.235,height*.055
    local frameW,frameH=width*.53,height*.91
    local doorX,doorY=frameX+frameW*.115,frameY+frameH*.045
    local doorW,doorH=frameW*.77,frameH*.91
    local leafTop=doorX+doorW*(1-opening*.94)
    local leafBottom=doorX+doorW*(1-opening*.75)
    local inset=math.max(1,doorW*.035)

    g.push('all');g.setShader()
    g.setColor(.004,.006,.009,1);g.rectangle('fill',0,0,width,height)
    -- The frame sits in a nearly black wall, like a classic first-person doorway.
    g.setColor(.018,.022,.025,1);g.rectangle('fill',frameX-frameW*.10,0,frameW*1.20,height)
    g.setColor(.20,.115,.060,1);g.rectangle('fill',frameX,frameY,frameW,frameH)
    g.setColor(.055,.041,.030,1);g.rectangle('fill',frameX+frameW*.055,frameY+frameH*.025,
        frameW*.89,frameH*.94)
    g.setColor(.001,.002,.004,1);g.rectangle('fill',doorX,doorY,doorW,doorH)

    -- The dark opening is visible behind the leaf as it swings away.
    local wood={.35,.20,.105,1}
    quad(g,wood,{doorX,doorY,leafTop,doorY,leafBottom,doorY+doorH,doorX,doorY+doorH})
    local panelColor={.42,.26,.14,1}
    panel(g,doorX+inset,doorY+doorH*.07,
        doorX+inset+(leafTop-doorX-inset)*.91,
        doorX+inset+(leafBottom-doorX-inset)*.91,doorY+doorH*.93,panelColor)
    g.setColor(.24,.13,.066,1);g.setLineWidth(math.max(1,width*.0012))
    g.line(doorX+inset*1.8,doorY+doorH*.50,
        doorX+inset+(leafTop-doorX-inset)*.91,doorY+doorH*.50)

    -- Recessed panels remain visible while the door begins to open.
    local topInset=doorW*.12
    local bottomInset=doorW*.12
    local topRight=doorX+topInset+(leafTop-doorX-topInset)*.88
    local bottomRight=doorX+bottomInset+(leafBottom-doorX-bottomInset)*.88
    panel(g,doorX+topInset,doorY+doorH*.12,topRight,
        doorX+bottomInset+(leafBottom-doorX-bottomInset)*.88,doorY+doorH*.44,{.30,.17,.09,1})
    panel(g,doorX+topInset,doorY+doorH*.56,topRight,bottomRight,doorY+doorH*.88,{.30,.17,.09,1})
    panel(g,doorX+topInset*1.18,doorY+doorH*.14,doorX+topInset+(topRight-doorX-topInset)*.94,
        doorX+bottomInset+(bottomRight-doorX-bottomInset)*.94,doorY+doorH*.42,{.39,.235,.12,1})
    panel(g,doorX+topInset*1.18,doorY+doorH*.58,doorX+topInset+(topRight-doorX-topInset)*.94,
        doorX+bottomInset+(bottomRight-doorX-bottomInset)*.94,doorY+doorH*.86,{.39,.235,.12,1})

    -- Brass handle turns before the door moves.
    local handleX=doorX+doorW*(.84-opening*.70)
    local handleY=doorY+doorH*.53
    local handleAngle=-.12-turn*.95
    local handleLength=doorW*.052
    g.setColor(.11,.068,.035,1);g.ellipse('fill',handleX,handleY,doorW*.028,doorW*.037)
    g.setColor(.84,.64,.30,1);g.setLineWidth(math.max(2,width*.004))
    g.line(handleX,handleY,handleX+math.cos(handleAngle)*handleLength,
        handleY+math.sin(handleAngle)*handleLength)
    g.circle('fill',handleX+math.cos(handleAngle)*handleLength,
        handleY+math.sin(handleAngle)*handleLength,math.max(2,width*.006))

    -- Bring the jambs and threshold back over the leaf for a clear frame silhouette.
    g.setColor(.23,.13,.067,1);g.rectangle('fill',frameX,frameY,frameW*.07,frameH)
    g.rectangle('fill',frameX+frameW*.93,frameY,frameW*.07,frameH)
    g.setColor(.55,.34,.18,1);g.rectangle('fill',frameX-frameW*.035,frameY,frameW*1.07,frameH*.045)
    g.setColor(.40,.25,.13,1);g.rectangle('fill',frameX-frameW*.055,frameY+frameH*.955,frameW*1.11,frameH*.045)

    if fade>0 then
        g.setColor(.001,.002,.004,fade);g.rectangle('fill',0,0,width,height)
    end
    g.pop()
end

return Door
