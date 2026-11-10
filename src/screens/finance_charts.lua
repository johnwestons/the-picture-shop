-- Small, shared charts for the business and household finance views.
local Charts={}
local fonts={}
local ink={.91,.95,.93,1}
local muted={.65,.76,.75,1}
local panel={.055,.09,.10,1}

local function font(size)
    fonts[size]=fonts[size] or require('src.screens.typography').get(size)
    return fonts[size]
end
local function setColor(color,alpha)
    love.graphics.setColor(color[1],color[2],color[3],alpha or color[4] or 1)
end

function Charts.metric(x,y,width,height,title,value,color)
    local g=love.graphics
    g.setColor(.055,.09,.10,1);g.rectangle('fill',x,y,width,height,4,4)
    setColor(color);g.rectangle('fill',x,y,3,height,3,3)
    g.setFont(font(11));setColor(muted);g.printf(title,x+11,y+9,width-18,'left')
    g.setFont(font(19));setColor(color);g.printf(value,x+11,y+28,width-18,'left')
end

function Charts.bar(x,y,width,height,value,maximum,color)
    local g=love.graphics
    g.setColor(.13,.20,.22,1);g.rectangle('fill',x,y,width,height,3,3)
    local ratio=maximum>0 and math.max(0,math.min(1,value/maximum)) or 0
    if ratio>0 then setColor(color);g.rectangle('fill',x,y,width*ratio,height,3,3) end
end

function Charts.donut(cx,cy,radius,segments,title,value)
    local g=love.graphics;local total=0
    for _,segment in ipairs(segments or {})do total=total+math.max(0,tonumber(segment.value) or 0)end
    g.push('all')
    if total>0 then
        local angle=-math.pi/2
        for _,segment in ipairs(segments)do
            local amount=math.max(0,tonumber(segment.value) or 0)
            if amount>0 then
                local sweep=math.pi*2*amount/total
                local gap=math.min(.025,sweep*.12)
                local start,finish=angle+gap*.5,angle+sweep-gap*.5
                local steps=math.max(2,math.ceil((finish-start)/(math.pi/18)))
                local points={}
                for i=0,steps do
                    local a=start+(finish-start)*i/steps
                    points[#points+1]=cx+math.cos(a)*radius
                    points[#points+1]=cy+math.sin(a)*radius
                end
                local inner=radius*.58
                for i=steps,0,-1 do
                    local a=start+(finish-start)*i/steps
                    points[#points+1]=cx+math.cos(a)*inner
                    points[#points+1]=cy+math.sin(a)*inner
                end
                setColor(segment.color or {.45,.80,.75,1});g.polygon('fill',points)
                angle=angle+sweep
            end
        end
    else
        g.setColor(.13,.20,.22,1);g.circle('fill',cx,cy,radius)
        g.setColor(.30,.42,.42,1);g.setLineWidth(2);g.circle('line',cx,cy,radius)
    end
    g.setColor(panel);g.circle('fill',cx,cy,radius*.54)
    g.setFont(font(math.floor(math.max(8,math.min(11,radius*.19)))));setColor(muted)
    g.printf(title or (total>0 and 'TOTAL' or 'NO DATA'),cx-radius,cy-radius-19,radius*2,'center')
    if value then
        g.setFont(font(math.floor(math.max(9,math.min(16,radius*.28)))));setColor(ink)
        local Text=require('src.screens.typography')
        g.setFont(Text.fit(value,14,radius*1.06,nil,'bold',12))
        g.printf(Text.ellipsize(value,radius*1.06),cx-radius*.53,cy-g.getFont():getHeight()/2,radius*1.06,'center')
    end
    g.pop()
    return total
end

function Charts.legend(x,y,items,width,rowHeight,limit)
    local g=love.graphics;rowHeight=math.max(20,rowHeight or 20)
    for i,item in ipairs(items or {})do
        if limit and i>limit then break end
        local yy=y+(i-1)*rowHeight
        setColor(item.color or muted);g.rectangle('fill',x,yy+3,8,8,2,2)
        g.setFont(font(10));setColor(muted)
        local display=item.displayValue or item.valueText
        local valueWidth=display and math.min(76,width*.38) or 0
        g.printf(require('src.screens.typography').ellipsize(item.label or '',width-17-valueWidth),x+13,yy,width-17-valueWidth,'left')
        if display then setColor(item.valueColor or ink);g.printf(tostring(display),x+width-valueWidth,yy,valueWidth,'right')end
    end
end

function Charts.sparkline(x,y,width,height,values,color,leftLabel,rightLabel)
    local g=love.graphics;local points={};local count=#(values or {})
    g.push('all')
    g.setColor(.055,.09,.10,.96);g.rectangle('fill',x,y,width,height,3,3)
    g.setColor(.20,.31,.32,1);g.setLineWidth(1)
    g.line(x+8,y+height-13,x+width-8,y+height-13)
    if count>0 then
        local low,high=values[1],values[1]
        for _,value in ipairs(values)do low=math.min(low,value);high=math.max(high,value)end
        if high-low<.001 then local pad=math.max(1,math.abs(high)*.08);low,high=low-pad,high+pad end
        for i,value in ipairs(values)do
            local t=count==1 and .5 or (i-1)/(count-1)
            points[#points+1]=x+9+t*(width-18)
            points[#points+1]=y+8+(1-(value-low)/(high-low))*(height-23)
        end
        if #points>=4 then
            local fill={points[1],y+height-13}
            for _,point in ipairs(points)do fill[#fill+1]=point end
            fill[#fill+1]=points[#points-1];fill[#fill+1]=y+height-13
            setColor(color or {.40,.84,.81,1},.15);g.polygon('fill',fill)
            setColor(color or {.40,.84,.81,1});g.setLineWidth(2);g.line(points)
        else
            setColor(color or {.40,.84,.81,1});g.circle('fill',points[1],points[2],3)
        end
    end
    g.setFont(font(8));setColor(muted)
    if leftLabel then g.print(leftLabel,x+8,y+height-11)end
    if rightLabel then g.printf(rightLabel,x+width-78,y+height-11,70,'right')end
    g.pop()
end

return Charts
