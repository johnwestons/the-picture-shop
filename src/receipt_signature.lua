-- Compact vector ink, independent of window size and safe for a control packet.
local Ink={MAX_POINTS=160,MAX_STROKES=32}
function Ink.valid(value)
    if type(value)~='string' or #value<4 or #value>Ink.MAX_POINTS*4+Ink.MAX_STROKES-1
        or value:find('[^%x/]') or value:sub(1,1)=='/' or value:sub(-1)=='/' or value:find('//',1,true) then return false end
    local strokes,points=0,0
    for stroke in value:gmatch('[^/]+') do
        if #stroke%4~=0 then return false end
        strokes=strokes+1;points=points+#stroke/4
    end
    return strokes<=Ink.MAX_STROKES and points<=Ink.MAX_POINTS
end
function Ink.encode(strokes,pad)
    local source,total={},0
    for _,stroke in ipairs(strokes or {}) do
        if #stroke>=2 and #source<Ink.MAX_STROKES then source[#source+1]=stroke;total=total+#stroke/2 end
    end
    if total==0 then return nil end
    local result,remaining={},Ink.MAX_POINTS
    for i,stroke in ipairs(source) do
        local count=#stroke/2;local minimum=count>1 and 2 or 1
        local reserve=0
        for j=i+1,#source do reserve=reserve+math.min(2,#source[j]/2) end
        local keep=math.min(count,remaining-reserve,math.max(minimum,math.floor(count/total*Ink.MAX_POINTS)))
        local points={}
        for j=1,keep do
            local index=keep==1 and 1 or math.floor((j-1)*(count-1)/(keep-1)+.5)+1
            local x,y=stroke[index*2-1],stroke[index*2]
            x=math.floor(math.max(0,math.min(1,(x-pad.x)/pad.width))*255+.5)
            y=math.floor(math.max(0,math.min(1,(y-pad.y)/pad.height))*255+.5)
            points[#points+1]=('%02x%02x'):format(x,y)
        end
        remaining=remaining-keep;result[#result+1]=table.concat(points)
    end
    return table.concat(result,'/')
end
function Ink.decode(value,rect)
    if not Ink.valid(value) then return {} end
    local result={}
    for line in value:gmatch('[^/]+') do
        local points={}
        for i=1,#line,4 do
            points[#points+1]=rect.x+tonumber(line:sub(i,i+1),16)/255*rect.width
            points[#points+1]=rect.y+tonumber(line:sub(i+2,i+3),16)/255*rect.height
        end
        result[#result+1]=points
    end
    return result
end
function Ink.draw(value,rect)
    local g=love.graphics;g.push('all');g.setColor(.12,.20,.25,1);g.setLineWidth(2)
    for _,stroke in ipairs(Ink.decode(value,rect)) do
        if #stroke>=4 then g.line(stroke) else g.circle('fill',stroke[1],stroke[2],1) end
    end
    g.pop()
end
return Ink
