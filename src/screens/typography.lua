-- Text helpers for newer screens. Existing screens retain their original fonts.
-- The broad Courier Prime replacement was rolled back pending screen reviews.
local Text = {}
local cache = {}
local sizes = setmetatable({}, {__mode='k'})
Text.sizes = {caption=12, compact=14, body=16, button=16, heading=20, title=26}
Text.colors = {body={.94,.95,.89,1}, muted={.76,.84,.82,1}, accent={1,.85,.44,1},
    panel={.025,.045,.05,.97}, border={.42,.54,.51,1}, warning={1,.72,.43,1}}

function Text.get(size, weight)
    size=math.max(Text.sizes.caption,math.floor(tonumber(size) or Text.sizes.body))
    weight=weight or 'regular'
    local key=weight..':'..size
    if not cache[key] then
        local font=love.graphics.newFont(size)
        cache[key]=font;sizes[font]=size
    end
    return cache[key]
end

function Text.size(font) return sizes[font or love.graphics.getFont()] end

-- Helpers remain available to the receipt archive, notifications and browser.
function Text.fit(text,size,width,height,weight,minimum)
    minimum=math.max(Text.sizes.caption,minimum or Text.sizes.compact)
    for candidate=math.max(minimum,size),minimum,-1 do
        local font=Text.get(candidate,weight)
        if font:getWidth(tostring(text))<=width and (not height or font:getHeight()<=height) then return font,true end
    end
    return Text.get(minimum,weight),false
end

function Text.ellipsize(text,width,font)
    text=tostring(text or '');font=font or love.graphics.getFont()
    if font:getWidth(text)<=width then return text end
    local utf8=require('utf8')
    while #text>0 and font:getWidth(text..'…')>width do
        local last=utf8.offset(text,-1);text=last and text:sub(1,last-1) or ''
    end
    return font:getWidth('…')<=width and text..'…' or ''
end

function Text.label(text,rect,options)
    options=options or {};local g=love.graphics
    g.push('all')
    local font=Text.fit(text,options.size or Text.sizes.button,rect.width-16,rect.height-8,
        options.weight or 'bold',options.minimum)
    g.setFont(font);g.setColor(options.color or Text.colors.body)
    local shown=Text.ellipsize(text,rect.width-16,font)
    g.printf(shown,rect.x+8,rect.y+(rect.height-font:getHeight())/2,rect.width-16,options.align or 'center')
    g.pop();return shown
end

function Text.lines(text,width,size,weight)
    local font=Text.get(size,weight);local _,lines=font:getWrap(tostring(text or ''),math.max(1,width))
    return lines,font:getHeight()*(1+math.max(0,#lines-1)*font:getLineHeight()),font
end

return Text
